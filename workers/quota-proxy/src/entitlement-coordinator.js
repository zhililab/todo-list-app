const HASH_PATTERN = /^[a-f0-9]{64}$/;
const STATE_KEY = 'state';

function json(status, value) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

function validExpiry(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
}

function candidateWins(candidate, current) {
  if (!current) return true;
  if (candidate.signedDate !== current.signedDate) {
    return candidate.signedDate > current.signedDate;
  }
  if (candidate.active !== current.active) return !candidate.active;
  if (candidate.active && candidate.expiry !== current.expiry) {
    return Date.parse(candidate.expiry) > Date.parse(current.expiry);
  }
  return candidate.identityHash > current.identityHash;
}

function safeState(state) {
  if (!state?.active) return { active: false, expiry: null };
  return { active: true, expiry: state.expiry };
}

async function readJson(request) {
  let body;
  try {
    body = await request.json();
  } catch {
    return null;
  }
  return body && typeof body === 'object' && !Array.isArray(body) ? body : null;
}

export function hasEntitlementCoordinator(env) {
  return Boolean(
    env?.ENTITLEMENTS
    && typeof env.ENTITLEMENTS.idFromName === 'function'
    && typeof env.ENTITLEMENTS.get === 'function',
  );
}

export function entitlementCoordinator(env, originalTransactionHash) {
  if (!hasEntitlementCoordinator(env) || !HASH_PATTERN.test(originalTransactionHash || '')) {
    throw new Error('entitlement coordinator unavailable');
  }
  return env.ENTITLEMENTS.get(env.ENTITLEMENTS.idFromName(originalTransactionHash));
}

export async function callEntitlementCoordinator(env, originalTransactionHash, path, body) {
  const response = await entitlementCoordinator(env, originalTransactionHash).fetch(
    new Request(`https://entitlement.internal${path}`, {
      method: body === undefined ? 'GET' : 'POST',
      headers: body === undefined ? undefined : { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
  );
  if (!response.ok) throw new Error('entitlement coordinator failed');
  return response.json();
}

export class EntitlementCoordinator {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/status') {
      return json(200, safeState(await this.ctx.storage.get(STATE_KEY)));
    }
    if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });
    const body = await readJson(request);
    if (!body) return json(400, { error: 'invalid_request' });

    if (url.pathname === '/register') return this.register(body);
    if (url.pathname === '/notification') return this.notification(body);
    if (url.pathname === '/erase-device') return this.eraseDevice(body);
    return json(404, { error: 'not_found' });
  }

  async register(body) {
    if (
      !HASH_PATTERN.test(body.deviceHash || '')
      || !HASH_PATTERN.test(body.transactionHash || '')
      || !Number.isSafeInteger(body.signedDate)
      || !validExpiry(body.expiry)
    ) return json(400, { error: 'invalid_request' });

    const result = await this.ctx.storage.transaction(async (transaction) => {
      await transaction.put(`device:${body.deviceHash}`, { v: 2 });
      const current = await transaction.get(STATE_KEY);
      const candidate = {
        v: 1,
        signedDate: body.signedDate,
        active: true,
        expiry: body.expiry,
        identityHash: body.transactionHash,
      };
      if (candidateWins(candidate, current)) await transaction.put(STATE_KEY, candidate);
      const effective = candidateWins(candidate, current) ? candidate : current;
      const accepted = Boolean(effective?.active);
      return { accepted, ...safeState(effective) };
    });
    return json(200, result);
  }

  async eraseDevice(body) {
    if (!HASH_PATTERN.test(body.deviceHash || '')) {
      return json(400, { error: 'invalid_request' });
    }
    await this.ctx.storage.transaction(async (transaction) => {
      await transaction.delete(`device:${body.deviceHash}`);
    });
    return json(200, { ok: true });
  }

  async notification(body) {
    if (
      !HASH_PATTERN.test(body.notificationHash || '')
      || !HASH_PATTERN.test(body.transactionHash || '')
      || !Number.isSafeInteger(body.signedDate)
      || typeof body.active !== 'boolean'
      || (body.active ? !validExpiry(body.expiry) : body.expiry !== null)
    ) return json(400, { error: 'invalid_request' });

    const result = await this.ctx.storage.transaction(async (transaction) => {
      const notificationKey = `notification:${body.notificationHash}`;
      if (await transaction.get(notificationKey)) {
        const devices = [...(await transaction.list({ prefix: 'device:' })).keys()]
          .map((key) => key.slice('device:'.length));
        return { status: 'duplicate', devices, ...safeState(await transaction.get(STATE_KEY)) };
      }
      await transaction.put(notificationKey, { v: 1 });
      const current = await transaction.get(STATE_KEY);
      const candidate = {
        v: 1,
        signedDate: body.signedDate,
        active: body.active,
        expiry: body.expiry,
        identityHash: body.notificationHash,
      };
      const wins = candidateWins(candidate, current);
      if (wins) await transaction.put(STATE_KEY, candidate);
      const devices = [...(await transaction.list({ prefix: 'device:' })).keys()]
        .map((key) => key.slice('device:'.length));
      return {
        status: wins ? (devices.length ? 'processed' : 'unmapped') : 'stale',
        devices,
        ...safeState(wins ? candidate : current),
      };
    });
    return json(200, result);
  }
}
