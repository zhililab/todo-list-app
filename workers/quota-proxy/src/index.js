// Todo AI 额度代理 Worker
// 持有 DeepSeek API Key，按设备（X-Device-Id）代理计数：
//   免费用户：终身 10 条（free:{deviceId}）
//   Pro 用户：每日 20 条（daily:{deviceId}:{YYYY-MM-DD}，以 UTC 日期为界）
//   Pro 状态：KV 设备指针发现 + original hash 对应 Durable Object 强一致判定
//
// 安全：DEEPSEEK_API_KEY 只从 env 读取，代码中不出现任何真实密钥。

import {
  ContractError,
  ROUTES,
  canonicalDeviceId,
  corsHeaders,
  hasProviderSecret,
  hasQuotaBinding,
  parseChatBody,
  parseDeviceId,
  parseJsonObject,
  validateOrigin,
} from './contract.js';
import {
  AppStoreJwsError,
  verifyAppStoreTransaction,
} from './app-store-jws.js';
import {
  AppStoreNotificationError,
  processAppStoreNotification,
} from './app-store-notifications.js';
import {
  callEntitlementCoordinator,
  hasEntitlementCoordinator,
} from './entitlement-coordinator.js';
import {
  deviceIdentityHash,
  ackDevicePrivacyResource,
  eraseDevicePrivacy,
  getDevicePrivacyCleanupState,
  hasDevicePrivacyCoordinator,
  markDevicePrivacyResourcePending,
  recordDevicePrivacyCleanup,
  trackDevicePrivacyResources,
  withDevicePrivacyLease,
} from './device-erasure.js';
export { EntitlementCoordinator } from './entitlement-coordinator.js';
export { DevicePrivacyCoordinator } from './device-privacy-coordinator.js';

const FREE_LIMIT = 10;
const DAILY_LIMIT = 20;
const PRO_PRODUCT_IDS = [
  'com.zhili.todo.premium.monthly.v2',
  'com.zhili.todo.premium.yearly.v2',
];
const DEEPSEEK_URL = 'https://api.deepseek.com/chat/completions';
const ENTITLEMENT_LIST_LIMIT = 100;
const ERASURE_BATCH_LIMIT = 25;
const SUPPORT_ID_PATTERN = /^TD-([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i;

// 今天（UTC）：new Date().toISOString().slice(0,10)
export function todayUTC() {
  return new Date().toISOString().slice(0, 10);
}

function json(status, payload, headers = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}

function contractFailure(error) {
  if (error instanceof ContractError) {
    return json(error.status, { error: { code: error.code } });
  }
  console.error('quota-proxy internal error');
  return json(500, { error: { code: 'internal_error' } });
}

function configurationFailure() {
  return json(503, { error: { code: 'service_not_configured' } });
}

function addHeaders(response, headers) {
  if (Object.keys(headers).length === 0) return response;
  const merged = new Headers(response.headers);
  for (const [name, value] of Object.entries(headers)) merged.set(name, value);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: merged,
  });
}

async function matchesAdminToken(request, env) {
  const configured = env?.ERASURE_ADMIN_TOKEN;
  if (typeof configured !== 'string' || configured.length < 32 || configured.length > 256) {
    return null;
  }
  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return false;
  const provided = authorization.slice('Bearer '.length);
  if (provided.length < 32 || provided.length > 256) return false;
  const encoder = new TextEncoder();
  const [configuredHash, providedHash] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(configured)),
    crypto.subtle.digest('SHA-256', encoder.encode(provided)),
  ]);
  const expected = new Uint8Array(configuredHash);
  const actual = new Uint8Array(providedHash);
  let mismatch = expected.length ^ actual.length;
  for (let index = 0; index < expected.length; index += 1) {
    mismatch |= expected[index] ^ (actual[index] ?? 0);
  }
  return mismatch === 0;
}

async function eraseDeviceAdmin(env, request) {
  const authorized = await matchesAdminToken(request, env);
  if (authorized === null) return configurationFailure();
  if (!authorized) return json(401, { error: { code: 'unauthorized' } });
  if (!hasQuotaBinding(env) || !hasEntitlementCoordinator(env) || !hasDevicePrivacyCoordinator(env)) {
    return configurationFailure();
  }

  let body;
  try {
    body = await parseJsonObject(request);
  } catch (error) {
    return contractFailure(error);
  }
  const match = SUPPORT_ID_PATTERN.exec(body.supportId || '');
  if (!match) return json(400, { error: { code: 'invalid_request_body' } });
  const enteredDeviceId = match[1];
  if (
    enteredDeviceId !== enteredDeviceId.toUpperCase()
    && enteredDeviceId !== enteredDeviceId.toLowerCase()
  ) return json(400, { error: { code: 'invalid_request_body' } });
  const deviceId = canonicalDeviceId(enteredDeviceId);
  const deviceHash = await deviceIdentityHash(deviceId);
  const privacy = await eraseDevicePrivacy(env, deviceHash);
  if (privacy.activeLeases > 0) return json(202, { ok: false, status: 'retry' });

  const cleanup = await getDevicePrivacyCleanupState(env, deviceHash);
  if (cleanup.cleanupComplete) {
    return json(200, { ok: true, status: 'erased' });
  }
  if (cleanup.resources.length > 0) {
    await eraseCatalogResource(env, deviceId, deviceHash, cleanup.resources[0]);
    return json(202, { ok: false, status: 'retry' });
  }
  if (!cleanup.legacyReady) return json(202, { ok: false, status: 'retry' });

  const legacy = await eraseDeviceRecordsBatch(
    env,
    deviceId,
    deviceHash,
    cleanup.cleanupPhase,
  );
  const progress = await recordDevicePrivacyCleanup(
    env,
    deviceHash,
    cleanup.cleanupPhase,
    legacy.complete,
    legacy.dirty,
  );
  return progress.cleanupComplete
    ? json(200, { ok: true, status: 'erased' })
    : json(202, { ok: false, status: 'retry' });
}

// KV 计数：读当前值 +1 写回。跨请求竞态下可能少计（个人 app，近似可接受）。
async function consumeQuota(env, deviceId, isPro) {
  const key = isPro
    ? `daily:${deviceId}:${todayUTC()}`
    : `free:${deviceId}`;
  const current = await env.QUOTA.get(key);
  await env.QUOTA.put(key, String((Number(current) || 0) + 1));
}

async function effectiveEntitlement(env, deviceId) {
  let effective = null;
  const prefix = `appstore-device-subscription:${deviceId}:`;
  let cursor;

  do {
    const options = { prefix, limit: ENTITLEMENT_LIST_LIMIT };
    if (cursor) options.cursor = cursor;
    const page = await env.QUOTA.list(options);
    if (!page || !Array.isArray(page.keys) || typeof page.list_complete !== 'boolean') {
      throw new Error('invalid entitlement list response');
    }

    for (const entry of page.keys) {
      if (!entry || typeof entry.name !== 'string' || !entry.name.startsWith(prefix)) {
        throw new Error('invalid device subscription pointer');
      }
      const originalTransactionHash = entry.name.slice(prefix.length);
      if (!/^[a-f0-9]{64}$/.test(originalTransactionHash)) {
        throw new Error('invalid device subscription pointer');
      }
      const status = await callEntitlementCoordinator(
        env,
        originalTransactionHash,
        '/status',
      );
      if (
        status.active
        && typeof status.expiry === 'string'
        && Number.isFinite(Date.parse(status.expiry))
        && (!effective || Date.parse(status.expiry) > Date.parse(effective.expiry))
      ) effective = { expiry: status.expiry };
    }

    if (page.list_complete) break;
    if (typeof page.cursor !== 'string' || !page.cursor || page.cursor === cursor) {
      throw new Error('invalid entitlement list cursor');
    }
    cursor = page.cursor;
  } while (true);

  return effective;
}

async function listErasureBatch(kv, prefix) {
  const page = await kv.list({ prefix, limit: ERASURE_BATCH_LIMIT });
  if (!page || !Array.isArray(page.keys) || typeof page.list_complete !== 'boolean') {
    throw new Error('invalid erasure list response');
  }
  const keys = page.keys.map((entry) => {
    if (!entry || typeof entry.name !== 'string' || !entry.name.startsWith(prefix)) {
      throw new Error('invalid erasure key');
    }
    return entry.name;
  });
  return { keys, listComplete: page.list_complete };
}

async function deletePrefixBatch(kv, prefix) {
  const page = await listErasureBatch(kv, prefix);
  for (const key of page.keys) await kv.delete(key);
  return { complete: page.listComplete, dirty: page.keys.length > 0 };
}

async function eraseDevicePointerBatch(env, deviceId, deviceHash) {
  const prefix = `appstore-device-subscription:${deviceId}:`;
  const page = await listErasureBatch(env.QUOTA, prefix);
  for (const key of page.keys) {
    const originalHash = key.slice(prefix.length);
    if (!/^[a-f0-9]{64}$/.test(originalHash)) throw new Error('invalid erasure pointer');
    const originalIndexes = await deletePrefixBatch(
      env.QUOTA,
      `appstore-original:${originalHash}:${deviceId}:`,
    );
    await callEntitlementCoordinator(env, originalHash, '/erase-device', { deviceHash });
    if (!originalIndexes.complete) return { complete: false, dirty: true };
    await env.QUOTA.delete(key);
  }
  return { complete: page.listComplete, dirty: page.keys.length > 0 };
}

async function eraseLegacyEntitlementBatch(env, deviceId, deviceHash) {
  const prefix = `appstore-entitlement:${deviceId}:`;
  const page = await listErasureBatch(env.QUOTA, prefix);
  for (const key of page.keys) {
    const hashes = new Set();
    const keyHash = key.slice(prefix.length).split(':')[0];
    if (/^[a-f0-9]{64}$/.test(keyHash)) hashes.add(keyHash);
    const value = await env.QUOTA.get(key);
    try {
      const parsed = JSON.parse(value);
      if (/^[a-f0-9]{64}$/.test(parsed?.originalTransactionHash || '')) {
        hashes.add(parsed.originalTransactionHash);
      }
    } catch {
      // Malformed legacy data never broadens deletion scope.
    }
    let originalIndexesComplete = true;
    for (const originalHash of hashes) {
      const result = await deletePrefixBatch(
        env.QUOTA,
        `appstore-original:${originalHash}:${deviceId}:`,
      );
      if (!result.complete) originalIndexesComplete = false;
      await callEntitlementCoordinator(env, originalHash, '/erase-device', { deviceHash });
    }
    if (!originalIndexesComplete) return { complete: false, dirty: true };
    await env.QUOTA.delete(key);
  }
  return { complete: page.listComplete, dirty: page.keys.length > 0 };
}

function catalogResourceKey(deviceId, resource) {
  if (resource.kind === 'free') return `free:${deviceId}`;
  if (resource.kind === 'daily') return `daily:${deviceId}:${resource.date}`;
  if (resource.kind === 'entitlement') {
    return `appstore-device-subscription:${deviceId}:${resource.originalHash}`;
  }
  throw new Error('invalid catalog resource');
}

async function deleteCatalogResource(env, deviceId, deviceHash, resource, key) {
  await env.QUOTA.delete(key);
  if (resource.kind === 'entitlement') {
    await deletePrefixBatch(
      env.QUOTA,
      `appstore-original:${resource.originalHash}:${deviceId}:`,
    );
    await callEntitlementCoordinator(env, resource.originalHash, '/erase-device', { deviceHash });
  }
}

async function eraseCatalogResource(env, deviceId, deviceHash, resource) {
  const key = catalogResourceKey(deviceId, resource);
  if (resource.status === 'tracked') {
    await deleteCatalogResource(env, deviceId, deviceHash, resource, key);
    await markDevicePrivacyResourcePending(env, deviceHash, resource.id, resource.revision);
    return;
  }
  if (resource.status !== 'pending' || !resource.ready) return;
  const pointerVisible = await env.QUOTA.get(key) !== null;
  const originalIndexes = resource.kind === 'entitlement'
    ? await deletePrefixBatch(
      env.QUOTA,
      `appstore-original:${resource.originalHash}:${deviceId}:`,
    )
    : { complete: true, dirty: false };
  if (pointerVisible || originalIndexes.dirty || !originalIndexes.complete) {
    await deleteCatalogResource(env, deviceId, deviceHash, resource, key);
    await markDevicePrivacyResourcePending(env, deviceHash, resource.id, resource.revision);
    return;
  }
  if (resource.kind === 'entitlement') {
    await callEntitlementCoordinator(env, resource.originalHash, '/erase-device', { deviceHash });
  }
  await ackDevicePrivacyResource(env, deviceHash, resource.id, resource.revision);
}

async function eraseDeviceRecordsBatch(env, deviceId, deviceHash, phase) {
  if (phase === 0) {
    const key = `free:${deviceId}`;
    const dirty = await env.QUOTA.get(key) !== null;
    if (dirty) await env.QUOTA.delete(key);
    return { complete: true, dirty };
  }
  if (phase === 1) {
    const key = `pro:${deviceId}`;
    const dirty = await env.QUOTA.get(key) !== null;
    if (dirty) await env.QUOTA.delete(key);
    return { complete: true, dirty };
  }
  if (phase === 2) return deletePrefixBatch(env.QUOTA, `daily:${deviceId}:`);
  if (phase === 3) return eraseDevicePointerBatch(env, deviceId, deviceHash);
  if (phase === 4) return eraseLegacyEntitlementBatch(env, deviceId, deviceHash);
  throw new Error('invalid erasure cleanup phase');
}

async function putImmutable(kv, key, value) {
  const existing = await kv.get(key);
  if (existing === null) {
    await kv.put(key, value);
    return;
  }
  if (existing !== value) throw new Error('immutable entitlement conflict');
}

// 额度判定：返回 { quota, exceeded, kind }
// kind: 'free' | 'daily'；exceeded=true 时不可用
async function quotaCheckWithinLease(env, deviceId) {
  const today = todayUTC();
  const [freeRaw, dailyRaw, entitlement] = await Promise.all([
    env.QUOTA.get(`free:${deviceId}`),
    env.QUOTA.get(`daily:${deviceId}:${today}`),
    effectiveEntitlement(env, deviceId),
  ]);
  const isPro = entitlement !== null && Date.parse(entitlement.expiry) > Date.now();
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
  return {
    quota,
    exceeded,
    kind: isPro ? 'daily' : 'free',
    entitlementExpiry: entitlement?.expiry ?? null,
  };
}

export async function quotaCheck(env, deviceId) {
  if (!hasQuotaBinding(env) || !hasEntitlementCoordinator(env) || !hasDevicePrivacyCoordinator(env)) {
    throw new Error('service not configured');
  }
  const canonicalId = canonicalDeviceId(deviceId);
  return withDevicePrivacyLease(env, canonicalId, async (deviceHash, operationId) => {
    const today = todayUTC();
    await trackDevicePrivacyResources(env, deviceHash, operationId, [
      { kind: 'free' },
      { kind: 'daily', date: today },
    ]);
    return quotaCheckWithinLease(env, canonicalId);
  });
}

// POST /proxy/chat/completions 核心逻辑（可独立测试）
export async function chatCompletions(env, request) {
  try {
    // 输入契约必须先于 KV 读取和上游调用。
    const deviceId = parseDeviceId(request);
    const body = await parseChatBody(request);
    if (
      !hasQuotaBinding(env)
      || !hasEntitlementCoordinator(env)
      || !hasDevicePrivacyCoordinator(env)
      || !hasProviderSecret(env)
    ) {
      return configurationFailure();
    }
    return await withDevicePrivacyLease(env, deviceId, async (deviceHash, operationId) => {
      const today = todayUTC();
      await trackDevicePrivacyResources(env, deviceHash, operationId, [
        { kind: 'free' },
        { kind: 'daily', date: today },
      ]);
      const { quota, exceeded, kind } = await quotaCheckWithinLease(env, deviceId);
      if (exceeded) {
        return json(402, { error: { code: 'quota_exceeded', kind } });
      }

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
      } catch {
        return json(502, { error: { code: 'provider_unavailable' } });
      }

      if (!upstream.ok) return json(502, { error: { code: 'provider_error' } });
      const upstreamText = await upstream.text();
      try {
        await consumeQuota(env, deviceId, quota.isPro);
      } catch {
        // KV writes are approximate, while the privacy lease still orders erasure safely.
      }
      return new Response(upstreamText, {
        status: 200,
        headers: { 'content-type': 'application/json; charset=utf-8' },
      });
    });
  } catch (error) {
    return contractFailure(error);
  }
}

// POST /proxy/register-pro 核心逻辑（可独立测试）
// 返回 { ok: true, expiry } 或 { ok: false, error }
export async function registerPro(env, deviceId, body, dependencies = {}) {
  if (!body || typeof body.transactionJwt !== 'string' || !body.transactionJwt.trim()) {
    return { ok: false, error: 'missing_jwt' };
  }
  if (
    typeof env.APP_STORE_BUNDLE_ID !== 'string'
    || !env.APP_STORE_BUNDLE_ID
    || env.APP_STORE_BUNDLE_ID.trim() !== env.APP_STORE_BUNDLE_ID
    || !['Sandbox', 'Production'].includes(env.APP_STORE_ENVIRONMENT)
  ) return { ok: false, error: 'service_not_configured' };

  if (!hasQuotaBinding(env) || !hasEntitlementCoordinator(env) || !hasDevicePrivacyCoordinator(env)) {
    return { ok: false, error: 'service_not_configured' };
  }

  const canonicalId = canonicalDeviceId(deviceId);
  return withDevicePrivacyLease(env, canonicalId, async (deviceHash, operationId) => {
    let verified;
    try {
      verified = await verifyAppStoreTransaction(body.transactionJwt, {
        bundleId: env.APP_STORE_BUNDLE_ID,
        environment: env.APP_STORE_ENVIRONMENT,
        productIds: PRO_PRODUCT_IDS,
        now: dependencies.now,
        trustedRoots: dependencies.trustedRoots,
        crypto: dependencies.crypto,
      });
    } catch (error) {
      if (error instanceof AppStoreJwsError && error.code === 'service_not_configured') {
        return { ok: false, error: 'service_not_configured' };
      }
      return { ok: false, error: 'invalid_jws' };
    }
    await trackDevicePrivacyResources(env, deviceHash, operationId, [{
      kind: 'entitlement',
      originalHash: verified.originalTransactionHash,
    }]);
    const pointerKey = `appstore-device-subscription:${canonicalId}:${verified.originalTransactionHash}`;
    await putImmutable(
      env.QUOTA,
      pointerKey,
      JSON.stringify({ v: 3, originalTransactionHash: verified.originalTransactionHash }),
    );
    const coordinated = await callEntitlementCoordinator(
      env,
      verified.originalTransactionHash,
      '/register',
      {
        deviceHash,
        transactionHash: verified.transactionHash,
        signedDate: verified.signedDate,
        expiry: verified.expiry,
      },
    );
    return coordinated.accepted
      ? { ok: true, expiry: coordinated.expiry }
      : { ok: false, error: 'inactive_transaction' };
  }, dependencies.crypto);
}

export async function appStoreNotifications(env, request, dependencies = {}) {
  try {
    const body = await parseJsonObject(request);
    if (!hasQuotaBinding(env)) return configurationFailure();
    if (typeof body.signedPayload !== 'string' || !body.signedPayload) {
      return json(400, { error: { code: 'invalid_request_body' } });
    }
    await processAppStoreNotification(env, body.signedPayload, dependencies);
    return json(200, { ok: true });
  } catch (error) {
    if (error instanceof ContractError) return contractFailure(error);
    if (error instanceof AppStoreNotificationError) {
      return error.code === 'service_not_configured'
        ? configurationFailure()
        : json(401, { error: { code: 'invalid_notification' } });
    }
    return contractFailure(error);
  }
}

// Worker 入口
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const methods = ROUTES[url.pathname];
    if (!methods) return json(404, { error: { code: 'not_found' } });

    let origin;
    try {
      origin = validateOrigin(request, env);
      const responseHeaders = corsHeaders(origin, methods);

      if (request.method === 'OPTIONS') {
        return new Response(null, { status: 204, headers: responseHeaders });
      }
      if (!methods.includes(request.method)) {
        return json(405, { error: { code: 'method_not_allowed' } }, {
          ...responseHeaders,
          Allow: `${methods.join(', ')}, OPTIONS`,
        });
      }

      let response;
      if (url.pathname === '/internal/erase-device') {
        response = await eraseDeviceAdmin(env, request);
      } else if (url.pathname === '/proxy/chat/completions') {
        response = await chatCompletions(env, request);
      } else if (url.pathname === '/proxy/quota') {
        const deviceId = parseDeviceId(request);
        if (!hasQuotaBinding(env) || !hasEntitlementCoordinator(env) || !hasDevicePrivacyCoordinator(env)) response = configurationFailure();
        else {
          const { quota } = await quotaCheck(env, deviceId);
          response = json(200, quota);
        }
      } else if (url.pathname === '/proxy/register-pro') {
        const deviceId = parseDeviceId(request);
        const body = await parseJsonObject(request);
        if (!hasQuotaBinding(env)) response = configurationFailure();
        else {
          const result = await registerPro(env, deviceId, body);
          response = result.ok
            ? json(200, { ok: true, expiry: result.expiry })
            : result.error === 'service_not_configured'
              ? configurationFailure()
              : json(401, { error: { code: 'invalid_jwt' } });
        }
      } else {
        response = await appStoreNotifications(env, request);
      }
      return addHeaders(response, responseHeaders);
    } catch (error) {
      return addHeaders(contractFailure(error), corsHeaders(origin, methods));
    }
  },
};
