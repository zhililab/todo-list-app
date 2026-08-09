// 纯 Node 自测：内存 KV 存根 + fetch 拦截，覆盖
//   - free 11 次 → 402（kind: free）
//   - pro 21 次/日 → 402（kind: daily）
//   - 上游非 2xx 透传且不消耗配额
//   - register-pro 验签（debug / 过期 / 白名单 / 正常 exp）
// 运行：node test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  chatCompletions,
  quotaCheck,
  registerPro,
  todayUTC,
} from './src/index.js';

// ---------- 内存 KV 存根（接口兼容 Workers KV） ----------
class MemKV {
  constructor() {
    this.map = new Map();
  }
  async get(key) {
    return this.map.has(key) ? this.map.get(key) : null;
  }
  async put(key, value) {
    this.map.set(key, String(value));
  }
  async delete(key) {
    this.map.delete(key);
  }
}

function makeEnv({ pro = null, debug = false, key = 'sk-test' } = {}) {
  const kv = new MemKV();
  const env = {
    QUOTA: kv,
    DEBUG_PRO_ALLOWED: debug ? '1' : undefined,
  };
  if (key) env.DEEPSEEK_API_KEY = key;
  if (pro) kv.map.set(`pro:${pro}`, new Date(Date.now() + 86400e3).toISOString());
  return { env, kv };
}

// ---------- 上游 fetch 拦截 ----------
let upstreamMode = 'ok'; // 'ok' | 'error'
globalThis.fetch = async (url, init) => {
  assert.equal(url, 'https://api.deepseek.com/chat/completions');
  const body = JSON.parse(init.body);
  assert.equal(body.model, 'deepseek-v4-flash');
  assert.ok(init.headers.Authorization === 'Bearer sk-test');
  if (upstreamMode === 'error') {
    return new Response('{"error":{"message":"upstream boom"}}', {
      status: 507,
      headers: { 'content-type': 'application/json' },
    });
  }
  return new Response(JSON.stringify({ id: 'chatcmpl-test', choices: [] }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
};

function chatReq(deviceId, body = { messages: [{ role: 'user', content: 'hi' }] }) {
  const headers = { 'Content-Type': 'application/json' };
  if (deviceId) headers['X-Device-Id'] = deviceId;
  return new Request('https://todo-quota-proxy.test.workers.dev/proxy/chat/completions', {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
}

// ---------- StoreKit JWT 构造（base64url，payload 自定） ----------
function makeJwt(payload) {
  const enc = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  return `${enc({ alg: 'RS256', typ: 'JWT' })}.${enc(payload)}.ZmFrZXNpZw`;
}

function makeValidPayload(overrides = {}) {
  return {
    exp: Math.floor(Date.now() / 1000) + 3600,
    productId: 'com.zhili.todo.premium.monthly',
    bundleId: 'com.zhili.todo',
    expiresDate: Date.now() + 3600e3,
    ...overrides,
  };
}

// ---------- 测试 ----------
test('无 X-Device-Id → 401 missing_device_id', async () => {
  const { env } = makeEnv();
  const res = await chatCompletions(env, chatReq(null));
  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { error: { code: 'missing_device_id' } });
});

test('free：10 次成功，第 11 次 → 402 quota_exceeded(free)', async () => {
  const { env, kv } = makeEnv();
  for (let i = 0; i < 10; i++) {
    const res = await chatCompletions(env, chatReq('dev-free'));
    assert.equal(res.status, 200);
  }
  assert.equal(kv.map.get('free:dev-free'), '10');
  const res = await chatCompletions(env, chatReq('dev-free'));
  assert.equal(res.status, 402);
  assert.deepEqual(await res.json(), { error: { code: 'quota_exceeded', kind: 'free' } });
  // 402 不消耗
  assert.equal(kv.map.get('free:dev-free'), '10');
});

test('pro：register 后当日 20 次成功，第 21 次 → 402 quota_exceeded(daily)', async () => {
  const { env, kv } = makeEnv();
  const reg = await registerPro(env, 'dev-pro', {
    transactionJwt: makeJwt(makeValidPayload()),
  });
  assert.equal(reg.ok, true);
  const today = todayUTC();
  assert.equal(kv.map.get(`pro:dev-pro`), reg.expiry);
  for (let i = 0; i < 20; i++) {
    const res = await chatCompletions(env, chatReq('dev-pro'));
    assert.equal(res.status, 200, `第 ${i + 1} 次应成功`);
  }
  assert.equal(kv.map.get(`daily:dev-pro:${today}`), '20');
  const res = await chatCompletions(env, chatReq('dev-pro'));
  assert.equal(res.status, 402);
  assert.deepEqual(await res.json(), { error: { code: 'quota_exceeded', kind: 'daily' } });
});

test('上游非 2xx → 原样透传状态码与 body，不消耗配额', async () => {
  const { env, kv } = makeEnv();
  upstreamMode = 'error';
  const res = await chatCompletions(env, chatReq('dev-fail'));
  assert.equal(res.status, 507);
  assert.deepEqual(await res.json(), { error: { message: 'upstream boom' } });
  assert.equal(kv.map.get('free:dev-fail'), undefined);
  upstreamMode = 'ok';
  // 失败过后仍可正常使用
  const ok = await chatCompletions(env, chatReq('dev-fail'));
  assert.equal(ok.status, 200);
  assert.equal(kv.map.get('free:dev-fail'), '1');
});

test('quota 接口：free 计数显示 free/pro 字段', async () => {
  const { env, kv } = makeEnv();
  kv.map.set('free:dev-q', '7');
  const { quota } = await quotaCheck(env, 'dev-q');
  assert.deepEqual(quota, {
    freeUsed: 7,
    freeLimit: 10,
    proUsed: 0,
    proLimit: 20,
    isPro: false,
    today: todayUTC(),
  });
});

test('quota 接口：pro 过期 → isPro=false 且回落到 free', async () => {
  const { env, kv } = makeEnv();
  kv.map.set('free:dev-exp', '10');
  kv.map.set('pro:dev-exp', new Date(Date.now() - 1000).toISOString());
  const { quota, exceeded, kind } = await quotaCheck(env, 'dev-exp');
  assert.equal(quota.isPro, false);
  assert.equal(exceeded, true);
  assert.equal(kind, 'free');
});

test('register-pro：debugPro=true + DEBUG_PRO_ALLOWED=1 → 直接通过', async () => {
  const { env, kv } = makeEnv({ debug: true });
  const reg = await registerPro(env, 'dev-debug', {
    transactionJwt: makeJwt({ debugPro: true, productId: 'whatever' }),
  });
  assert.equal(reg.ok, true);
  assert.ok(Date.parse(reg.expiry) > Date.now());
  assert.ok(kv.map.has('pro:dev-debug'));
});

test('register-pro：debugPro 但未开 DEBUG_PRO_ALLOWED → 拒绝', async () => {
  const { env } = makeEnv();
  const reg = await registerPro(env, 'dev-n', {
    transactionJwt: makeJwt({ debugPro: true, productId: 'whatever' }),
  });
  assert.equal(reg.ok, false);
});

test('register-pro：exp 过期 → 拒绝', async () => {
  const { env } = makeEnv();
  const reg = await registerPro(env, 'dev-n', {
    transactionJwt: makeJwt(makeValidPayload({ exp: Math.floor(Date.now() / 1000) - 60 })),
  });
  assert.equal(reg.ok, false);
});

test('register-pro：productId 不在白名单 → 拒绝', async () => {
  const { env } = makeEnv();
  const reg = await registerPro(env, 'dev-n', {
    transactionJwt: makeJwt(makeValidPayload({ productId: 'com.other.app' })),
  });
  assert.equal(reg.ok, false);
});

test('register-pro：yearly productId 可接受', async () => {
  const { env, kv } = makeEnv();
  const reg = await registerPro(env, 'dev-y', {
    transactionJwt: makeJwt(makeValidPayload({ productId: 'com.zhili.todo.premium.yearly' })),
  });
  assert.equal(reg.ok, true);
  assert.ok(kv.map.has('pro:dev-y'));
});

test('register-pro：缺 transactionJwt → 拒绝', async () => {
  const { env } = makeEnv();
  assert.equal((await registerPro(env, 'dev-n', null)).ok, false);
  assert.equal((await registerPro(env, 'dev-n', {})).ok, false);
});

test('缺 DEEPSEEK_API_KEY → 500 proxy_error，且不消耗', async () => {
  const { env, kv } = makeEnv({ key: null });
  const res = await chatCompletions(env, chatReq('dev-nokey'));
  assert.equal(res.status, 500);
  const body = await res.json();
  assert.equal(body.error.code, 'proxy_error');
  assert.equal(kv.map.get('free:dev-nokey'), undefined);
});

test('非法 JSON body → 400，不消耗', async () => {
  const { env, kv } = makeEnv();
  const req = new Request('https://x/proxy/chat/completions', {
    method: 'POST',
    headers: { 'X-Device-Id': 'dev-bad' },
    body: 'not json',
  });
  const res = await chatCompletions(env, req);
  assert.equal(res.status, 400);
  assert.equal(kv.map.get('free:dev-bad'), undefined);
});
