import { ContractError } from './contract.js';

const HASH_CONTEXT = 'todo-erased-device:v1\0';

export async function deviceIdentityHash(deviceId, cryptoProvider = globalThis.crypto) {
  const digest = new Uint8Array(await cryptoProvider.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(`${HASH_CONTEXT}${deviceId}`),
  ));
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

export function hasDevicePrivacyCoordinator(env) {
  return Boolean(
    env?.DEVICE_PRIVACY
    && typeof env.DEVICE_PRIVACY.idFromName === 'function'
    && typeof env.DEVICE_PRIVACY.get === 'function',
  );
}

function privacyStub(env, deviceHash) {
  if (!hasDevicePrivacyCoordinator(env) || !/^[a-f0-9]{64}$/.test(deviceHash || '')) {
    throw new Error('device privacy coordinator unavailable');
  }
  return env.DEVICE_PRIVACY.get(env.DEVICE_PRIVACY.idFromName(deviceHash));
}

async function privacyCall(env, deviceHash, path, body = {}) {
  return privacyStub(env, deviceHash).fetch(new Request(`https://privacy.internal${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  }));
}

export async function withDevicePrivacyLease(env, deviceId, operation, cryptoProvider = globalThis.crypto) {
  const deviceHash = await deviceIdentityHash(deviceId, cryptoProvider);
  const begin = await privacyCall(env, deviceHash, '/begin');
  if (begin.status === 410) throw new ContractError(410, 'device_erased');
  if (!begin.ok) throw new Error('device privacy lease failed');
  const lease = await begin.json();
  if (!/^[1-9][0-9]*$/.test(lease.operationId || '')) {
    throw new Error('invalid device privacy lease');
  }
  try {
    return await operation(deviceHash, lease.operationId);
  } finally {
    const finish = await privacyCall(env, deviceHash, '/finish', {
      operationId: lease.operationId,
    });
    if (!finish.ok) throw new Error('device privacy lease release failed');
  }
}

export async function trackDevicePrivacyResources(env, deviceHash, operationId, resources) {
  const response = await privacyCall(env, deviceHash, '/track', { operationId, resources });
  if (!response.ok) throw new Error('device privacy resource tracking failed');
}

export async function eraseDevicePrivacy(env, deviceHash) {
  const response = await privacyCall(env, deviceHash, '/erase');
  if (response.status !== 200 && response.status !== 202) {
    throw new Error('device privacy erase failed');
  }
  const result = await response.json();
  if (result.erased !== true || !Number.isSafeInteger(result.activeLeases) || result.activeLeases < 0) {
    throw new Error('invalid device privacy erase response');
  }
  return result;
}

export async function getDevicePrivacyCleanupState(env, deviceHash) {
  const response = await privacyCall(env, deviceHash, '/cleanup-state');
  if (!response.ok) throw new Error('device privacy cleanup state failed');
  const result = await response.json();
  if (
    !Number.isSafeInteger(result.cleanupPhase)
    || result.cleanupPhase < 0
    || !Number.isSafeInteger(result.cleanupBatch)
    || result.cleanupBatch < 0
    || !Array.isArray(result.resources)
    || typeof result.legacyReady !== 'boolean'
    || !Number.isSafeInteger(result.legacyEmptyPasses)
    || result.legacyEmptyPasses < 0
    || typeof result.cleanupComplete !== 'boolean'
  ) throw new Error('invalid device privacy cleanup state');
  return result;
}

export async function markDevicePrivacyResourcePending(env, deviceHash, resourceId, revision) {
  const response = await privacyCall(env, deviceHash, '/mark-pending', { resourceId, revision });
  if (!response.ok && response.status !== 409) {
    throw new Error('device privacy resource pending failed');
  }
  return response.status !== 409;
}

export async function ackDevicePrivacyResource(env, deviceHash, resourceId, revision) {
  const response = await privacyCall(env, deviceHash, '/ack-resource', { resourceId, revision });
  if (!response.ok && response.status !== 409) {
    throw new Error('device privacy resource ack failed');
  }
  return response.status !== 409;
}

export async function recordDevicePrivacyCleanup(env, deviceHash, phase, complete, dirty) {
  const response = await privacyCall(env, deviceHash, '/record-cleanup', {
    phase,
    complete,
    dirty,
  });
  if (!response.ok && response.status !== 409) {
    throw new Error('device privacy cleanup progress failed');
  }
  const result = await response.json();
  if (
    !Number.isSafeInteger(result.cleanupPhase)
    || result.cleanupPhase < 0
    || !Number.isSafeInteger(result.cleanupBatch)
    || result.cleanupBatch < 0
    || typeof result.legacyReady !== 'boolean'
    || !Number.isSafeInteger(result.legacyEmptyPasses)
    || result.legacyEmptyPasses < 0
    || typeof result.cleanupComplete !== 'boolean'
  ) throw new Error('invalid device privacy cleanup progress');
  return { ...result, conflict: response.status === 409 };
}
