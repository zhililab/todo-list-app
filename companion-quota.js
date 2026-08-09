// 额度客户端纯逻辑（ES module，兼容 Node 测试 & 浏览器）
// 通过 <script type="module"> 引入后挂载到 window，供 app.js 使用

const DEVICE_ID_KEY = 'todo_device_id';

export function getDeviceId(storage) {
    if (storage && typeof storage.getItem === 'function') {
        const existing = storage.getItem(DEVICE_ID_KEY);
        if (existing) return existing;
    }
    let id = '';
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
        id = crypto.randomUUID();
    } else {
        id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}-${Math.random().toString(36).slice(2, 12)}`;
    }
    if (storage && typeof storage.setItem === 'function') {
        storage.setItem(DEVICE_ID_KEY, id);
    }
    return id;
}

export function parseQuotaError(body) {
    let data = body;
    if (typeof body === 'string' && body.trim()) {
        try {
            data = JSON.parse(body);
        } catch (_error) {
            return null;
        }
    }
    if (!data || typeof data !== 'object') return null;
    const error = (data && typeof data.error === 'object' && data.error) || data;
    if (!error || error.code !== 'quota_exceeded') return null;
    return { code: 'quota_exceeded', kind: error.kind === 'daily' ? 'daily' : 'free' };
}

export function classifyQuota(bodyText, status) {
    if (Number(status) !== 402) return null;
    const parsed = parseQuotaError(bodyText);
    return parsed ? parsed.kind : null;
}

export function decideRoute(hasCustomKey, baseUrl) {
    if (hasCustomKey) return 'direct';
    if (typeof baseUrl === 'string' && baseUrl.trim()) return 'proxy';
    return 'local';
}

export async function proxyRequest({ baseUrl, deviceId, body, fetcher = globalThis.fetch }) {
    const url = `${String(baseUrl).replace(/\/+$/, '')}/proxy/chat/completions`;
    const response = await fetcher(url, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-Device-Id': deviceId
        },
        body: JSON.stringify(body)
    });
    const bodyText = await response.text();
    if (response.ok) {
        try {
            return JSON.parse(bodyText);
        } catch (_error) {
            throw { code: 'quota_proxy_error', status: response.status, body: bodyText };
        }
    }
    const kind = classifyQuota(bodyText, response.status);
    if (kind) throw { code: 'quota_exceeded', kind, status: response.status };
    throw { code: 'quota_proxy_error', status: response.status, body: bodyText };
}

export async function fetchQuota({ baseUrl, deviceId, fetcher = globalThis.fetch }) {
    const url = `${String(baseUrl).replace(/\/+$/, '')}/proxy/quota`;
    const response = await fetcher(url, { headers: { 'X-Device-Id': deviceId } });
    const bodyText = await response.text();
    if (!response.ok) throw { code: 'quota_proxy_error', status: response.status, body: bodyText };
    return JSON.parse(bodyText);
}

if (typeof window !== 'undefined') {
    window.getDeviceId = getDeviceId;
    window.parseQuotaError = parseQuotaError;
    window.classifyQuota = classifyQuota;
    window.decideRoute = decideRoute;
    window.proxyRequest = proxyRequest;
    window.fetchQuota = fetchQuota;
}