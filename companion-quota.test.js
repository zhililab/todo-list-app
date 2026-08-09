import test from 'node:test';
import assert from 'node:assert/strict';
import {
    getDeviceId,
    parseQuotaError,
    classifyQuota,
    decideRoute,
    proxyRequest,
    fetchQuota
} from './companion-quota.js';

function makeMemoryStorage(initial = {}) {
    const map = new Map(Object.entries(initial));
    return {
        getItem: key => (map.has(key) ? map.get(key) : null),
        setItem: (key, value) => map.set(key, String(value)),
        removeItem: key => map.delete(key),
        _map: map
    };
}

test('getDeviceId 生成并保存匿名设备 id', () => {
    const storage = makeMemoryStorage();
    const id = getDeviceId(storage);
    assert.ok(typeof id === 'string' && id.length >= 12);
    assert.equal(storage.getItem('todo_device_id'), id);
});

test('getDeviceId 复用已有 id 不重复生成', () => {
    const storage = makeMemoryStorage({ todo_device_id: 'fixed-id-abc' });
    assert.equal(getDeviceId(storage), 'fixed-id-abc');
    assert.equal(storage.getItem('todo_device_id'), 'fixed-id-abc');
});

test('getDeviceId 兼容无 storage 场景', () => {
    const id = getDeviceId(null);
    assert.ok(typeof id === 'string' && id.length >= 12);
});

test('parseQuotaError 从字符串解析 free 额度错误', () => {
    assert.deepEqual(parseQuotaError('{"error":{"code":"quota_exceeded","kind":"free"}}'), {
        code: 'quota_exceeded',
        kind: 'free'
    });
});

test('parseQuotaError 从对象解析 daily 额度错误', () => {
    assert.deepEqual(parseQuotaError({ error: { code: 'quota_exceeded', kind: 'daily' } }), {
        code: 'quota_exceeded',
        kind: 'daily'
    });
});

test('parseQuotaError 非额度错误返回 null', () => {
    assert.equal(parseQuotaError('{"error":{"code":"proxy_error"}}'), null);
    assert.equal(parseQuotaError(''), null);
    assert.equal(parseQuotaError('not json at all'), null);
    assert.equal(parseQuotaError(null), null);
});

test('parseQuotaError 缺省 kind 归为 free', () => {
    assert.deepEqual(parseQuotaError('{"error":{"code":"quota_exceeded"}}'), {
        code: 'quota_exceeded',
        kind: 'free'
    });
});

test('classifyQuota 仅在 402 时返回 kind', () => {
    const freeBody = '{"error":{"code":"quota_exceeded","kind":"free"}}';
    const dailyBody = '{"error":{"code":"quota_exceeded","kind":"daily"}}';
    assert.equal(classifyQuota(freeBody, 402), 'free');
    assert.equal(classifyQuota(dailyBody, 402), 'daily');
    assert.equal(classifyQuota(freeBody, 400), null);
    assert.equal(classifyQuota(freeBody, 200), null);
    assert.equal(classifyQuota('{}', 402), null);
});

test('decideRoute 自定义 Key 优先进直连', () => {
    assert.equal(decideRoute(true, 'https://proxy.example.com'), 'direct');
    assert.equal(decideRoute(true, ''), 'direct');
});

test('decideRoute 无 Key 且有代理地址走 proxy', () => {
    assert.equal(decideRoute(false, 'https://proxy.example.com'), 'proxy');
    assert.equal(decideRoute(false, '   https://proxy.example.com/  '), 'proxy');
});

test('decideRoute 无 Key 无代理走 local', () => {
    assert.equal(decideRoute(false, ''), 'local');
    assert.equal(decideRoute(false, null), 'local');
    assert.equal(decideRoute(false, '   '), 'local');
});

test('proxyRequest 拼接 URL、带 X-Device-Id、透传 200 JSON', async () => {
    const calls = [];
    const fetcher = async (url, options) => {
        calls.push({ url, options });
        return new Response(JSON.stringify({ choices: [{ message: { content: '你好' } }] }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
        });
    };
    const data = await proxyRequest({
        baseUrl: 'https://quota.example.com/',
        deviceId: 'dev-1',
        body: { model: 'deepseek-chat', messages: [{ role: 'user', content: 'hi' }] },
        fetcher
    });
    assert.equal(data.choices[0].message.content, '你好');
    assert.equal(calls[0].url, 'https://quota.example.com/proxy/chat/completions');
    assert.equal(calls[0].options.method, 'POST');
    assert.equal(calls[0].options.headers['Content-Type'], 'application/json');
    assert.equal(calls[0].options.headers['X-Device-Id'], 'dev-1');
    assert.equal(JSON.parse(calls[0].options.body).model, 'deepseek-chat');
});

test('proxyRequest 402 free 抛 quota_exceeded', async () => {
    const fetcher = async () => new Response('{"error":{"code":"quota_exceeded","kind":"free"}}', { status: 402 });
    await assert.rejects(
        () => proxyRequest({ baseUrl: 'https://quota.example.com', deviceId: 'dev-1', body: {}, fetcher }),
        error => error.code === 'quota_exceeded' && error.kind === 'free'
    );
});

test('proxyRequest 402 daily 抛 quota_exceeded', async () => {
    const fetcher = async () => new Response('{"error":{"code":"quota_exceeded","kind":"daily"}}', { status: 402 });
    await assert.rejects(
        () => proxyRequest({ baseUrl: 'https://quota.example.com', deviceId: 'dev-1', body: {}, fetcher }),
        error => error.code === 'quota_exceeded' && error.kind === 'daily'
    );
});

test('proxyRequest 非 2xx 抛错带 status 与 body', async () => {
    const fetcher = async () => new Response('{"error":{"code":"proxy_error","message":"boom"}}', { status: 500 });
    await assert.rejects(
        () => proxyRequest({ baseUrl: 'https://quota.example.com', deviceId: 'dev-1', body: {}, fetcher }),
        error => error.code === 'quota_proxy_error' && error.status === 500 && error.body.includes('boom')
    );
});

test('fetchQuota 返回额度快照', async () => {
    const snapshot = { freeUsed: 3, freeLimit: 10, proUsed: 0, proLimit: 20, isPro: false, today: '2026-08-09' };
    const calls = [];
    const fetcher = async (url, options) => {
        calls.push({ url, options });
        return new Response(JSON.stringify(snapshot), { status: 200 });
    };
    const data = await fetchQuota({ baseUrl: 'https://quota.example.com', deviceId: 'dev-9', fetcher });
    assert.deepEqual(data, snapshot);
    assert.equal(calls[0].url, 'https://quota.example.com/proxy/quota');
    assert.equal(calls[0].options.headers['X-Device-Id'], 'dev-9');
});

test('fetchQuota 非 2xx 抛错', async () => {
    const fetcher = async () => new Response('bad', { status: 500 });
    await assert.rejects(
        () => fetchQuota({ baseUrl: 'https://quota.example.com', deviceId: 'dev-1', fetcher }),
        error => error.code === 'quota_proxy_error' && error.status === 500
    );
});

test('decideRoute 与代理链路端到端：无 Key + 配置 → proxy 走 fetch', async () => {
    const baseUrl = 'https://quota.example.com';
    assert.equal(decideRoute(false, baseUrl), 'proxy');
    let hit = false;
    const fetcher = async (url, options) => {
        hit = true;
        assert.ok(url.startsWith(baseUrl));
        assert.equal(options.headers['X-Device-Id'], 'dev-42');
        return new Response(JSON.stringify({ choices: [{ message: { content: 'ok' } }] }), { status: 200 });
    };
    const data = await proxyRequest({ baseUrl, deviceId: 'dev-42', body: { model: 'deepseek-chat' }, fetcher });
    assert.equal(hit, true);
    assert.equal(data.choices[0].message.content, 'ok');
});