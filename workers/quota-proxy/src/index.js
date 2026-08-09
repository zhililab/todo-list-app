// Todo AI 额度代理 Worker
// 持有 DeepSeek API Key，按设备（X-Device-Id）代理计数：
//   免费用户：终身 10 条（free:{deviceId}）
//   Pro 用户：每日 20 条（daily:{deviceId}:{YYYY-MM-DD}，以 UTC 日期为界）
//   Pro 状态：pro:{deviceId} → ISO 到期时间（register-pro 写入）
//
// 安全：DEEPSEEK_API_KEY 只从 env 读取，代码中不出现任何真实密钥。

export const FREE_LIMIT = 10;
export const DAILY_LIMIT = 20;
export const PRO_PRODUCT_IDS = [
  'com.zhili.todo.premium.monthly',
  'com.zhili.todo.premium.yearly',
];
const DEEPSEEK_URL = 'https://api.deepseek.com/chat/completions';
// 开发仿真（DEBUG_PRO_ALLOWED=1 + payload.debugPro=true）时的假到期时间：1 年
const DEBUG_PRO_DURATION_MS = 365 * 24 * 60 * 60 * 1000;

// 今天（UTC）：new Date().toISOString().slice(0,10)
export function todayUTC() {
  return new Date().toISOString().slice(0, 10);
}

function json(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

// base64url 解码（Web Worker / Node 通用，不依赖 Buffer）
function base64UrlDecode(str) {
  let b64 = str.replace(/-/g, '+').replace(/_/g, '/');
  b64 = b64.padEnd(b64.length + ((4 - (b64.length % 4)) % 4), '=');
  const bin = atob(b64);
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

// KV 计数：读当前值 +1 写回。跨请求竞态下可能少计（个人 app，近似可接受）。
async function consumeQuota(env, deviceId, isPro) {
  const key = isPro
    ? `daily:${deviceId}:${todayUTC()}`
    : `free:${deviceId}`;
  const current = await env.QUOTA.get(key);
  await env.QUOTA.put(key, String((Number(current) || 0) + 1));
}

// 解析并校验 StoreKit 交易 JWT（jwsRepresentation）。
// 简化验签：仅解析 payload + 校验 exp + productId 白名单（契约允许）。
// 正式上线前建议升级为 WebCrypto RS256 + Apple x5c 证书链验签。
// 开发仿真：DEBUG_PRO_ALLOWED=1 且 payload.debugPro === true 时直接放行。
export function parseStoreJwt(jws, env) {
  const parts = String(jws).split('.');
  if (parts.length !== 3) throw new Error('malformed_jwt');

  let payload;
  try {
    payload = JSON.parse(base64UrlDecode(parts[1]));
  } catch {
    throw new Error('invalid_payload');
  }

  const debugAllowed = env.DEBUG_PRO_ALLOWED === '1' && payload.debugPro === true;
  if (debugAllowed) {
    return new Date(Date.now() + DEBUG_PRO_DURATION_MS).toISOString();
  }

  // exp：payload 字段（秒）；须未过期
  const expSec = Number(payload.exp);
  if (!Number.isFinite(expSec) || expSec * 1000 <= Date.now()) {
    throw new Error('jwt_expired');
  }
  // productId：payload 字段，白名单
  if (!PRO_PRODUCT_IDS.includes(payload.productId)) {
    throw new Error('unknown_product');
  }
  // 到期时间：优先 payload.expiresDate（毫秒），否则用 exp（秒）；bundleId 忽略
  const expMs = Number(payload.expiresDate) || expSec * 1000;
  if (!Number.isFinite(expMs) || expMs <= Date.now()) {
    throw new Error('subscription_expired');
  }
  return new Date(expMs).toISOString();
}

// 额度判定：返回 { quota, exceeded, kind }
// kind: 'free' | 'daily'；exceeded=true 时不可用
export async function quotaCheck(env, deviceId) {
  const today = todayUTC();
  const [freeRaw, proRaw, dailyRaw] = await Promise.all([
    env.QUOTA.get(`free:${deviceId}`),
    env.QUOTA.get(`pro:${deviceId}`),
    env.QUOTA.get(`daily:${deviceId}:${today}`),
  ]);
  const isPro = proRaw !== null && Date.parse(proRaw) > Date.now();
  const freeUsed = Number(freeRaw) || 0;
  const proUsed = Number(dailyRaw) || 0;
  const quota = {
    freeUsed,
    freeLimit: FREE_LIMIT,
    proUsed,
    proLimit: DAILY_LIMIT,
    isPro,
    today,
  };
  const exceeded = isPro ? proUsed >= DAILY_LIMIT : freeUsed >= FREE_LIMIT;
  return { quota, exceeded, kind: isPro ? 'daily' : 'free' };
}

// POST /proxy/chat/completions 核心逻辑（可独立测试）
export async function chatCompletions(env, request) {
  const deviceId = request.headers.get('X-Device-Id');
  if (!deviceId) {
    return json(401, { error: { code: 'missing_device_id' } });
  }
  if (!env.DEEPSEEK_API_KEY) {
    return json(500, { error: { code: 'proxy_error', message: 'DEEPSEEK_API_KEY not configured' } });
  }

  // 1. 额度检查
  const { quota, exceeded, kind } = await quotaCheck(env, deviceId);
  if (exceeded) {
    return json(402, { error: { code: 'quota_exceeded', kind } });
  }

  // 2. 解析并强制 model
  let body;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: { code: 'invalid_request_body', message: 'body must be valid JSON' } });
  }
  body.model = 'deepseek-v4-flash';

  // 3. 转发上游
  let upstream;
  try {
    upstream = await fetch(DEEPSEEK_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${env.DEEPSEEK_API_KEY}`,
      },
      body: JSON.stringify(body),
    });
  } catch (err) {
    return json(500, { error: { code: 'proxy_error', message: `upstream fetch failed: ${err?.message || 'unknown'}` } });
  }
  const upstreamText = await upstream.text();

  // 4. 非 2xx：原样透传状态码与 body，不消耗配额
  if (!upstream.ok) {
    return new Response(upstreamText, {
      status: upstream.status,
      headers: {
        'content-type': upstream.headers.get('content-type') || 'application/json; charset=utf-8',
      },
    });
  }

  // 5. 成功：递增计数后返回上游原文
  try {
    await consumeQuota(env, deviceId, quota.isPro);
  } catch {
    // KV 写入失败不阻塞成功响应（计数近似可接受）
  }
  return new Response(upstreamText, {
    status: 200,
    headers: {
      'content-type': upstream.headers.get('content-type') || 'application/json; charset=utf-8',
    },
  });
}

// POST /proxy/register-pro 核心逻辑（可独立测试）
// 返回 { ok: true, expiry } 或 { ok: false, error }
export async function registerPro(env, deviceId, body) {
  if (!body || typeof body.transactionJwt !== 'string' || !body.transactionJwt.trim()) {
    return { ok: false, error: 'missing_jwt' };
  }
  let expiry;
  try {
    expiry = parseStoreJwt(body.transactionJwt, env);
  } catch (err) {
    return { ok: false, error: err.message || 'invalid_jwt' };
  }
  await env.QUOTA.put(`pro:${deviceId}`, expiry);
  return { ok: true, expiry };
}

// Worker 入口
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/proxy/chat/completions' && request.method === 'POST') {
        return await chatCompletions(env, request);
      }
      if (url.pathname === '/proxy/quota' && request.method === 'GET') {
        const deviceId = request.headers.get('X-Device-Id');
        if (!deviceId) return json(401, { error: { code: 'missing_device_id' } });
        const { quota } = await quotaCheck(env, deviceId);
        return json(200, quota);
      }
      if (url.pathname === '/proxy/register-pro' && request.method === 'POST') {
        const deviceId = request.headers.get('X-Device-Id');
        if (!deviceId) return json(401, { error: { code: 'missing_device_id' } });
        let body = null;
        try {
          body = await request.json();
        } catch {
          body = null;
        }
        const res = await registerPro(env, deviceId, body);
        if (!res.ok) return json(401, { error: { code: 'invalid_jwt' } });
        return json(200, { ok: true, expiry: res.expiry });
      }
      return json(404, { error: { code: 'not_found' } });
    } catch (err) {
      console.error('quota-proxy error:', err);
      return json(500, { error: { code: 'proxy_error', message: err?.message || 'internal error' } });
    }
  },
};
