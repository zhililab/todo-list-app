const STATE_KEY = 'privacy-state';
const LEASE_PREFIX = 'lease:';
const RESOURCE_PREFIX = 'resource:';
const OPERATION_ID_PATTERN = /^[1-9][0-9]*$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const HASH_PATTERN = /^[a-f0-9]{64}$/;
const VERIFICATION_DELAY_MS = 65_000;
const CATALOG_LIMIT = 10;

function initialState() {
  return {
    v: 1,
    erased: false,
    nextOperationId: 1,
    cleanupPhase: 0,
    cleanupBatch: 0,
    legacyDirty: false,
    legacyEmptyPasses: 0,
    legacyNextScanAt: 0,
    cleanupComplete: false,
  };
}

function normalizedState(state) {
  return {
    ...initialState(),
    ...state,
    cleanupPhase: Number.isSafeInteger(state?.cleanupPhase) && state.cleanupPhase >= 0
      ? state.cleanupPhase
      : 0,
    cleanupBatch: Number.isSafeInteger(state?.cleanupBatch) && state.cleanupBatch >= 0
      ? state.cleanupBatch
      : 0,
    legacyDirty: state?.legacyDirty === true,
    legacyEmptyPasses: Number.isSafeInteger(state?.legacyEmptyPasses) && state.legacyEmptyPasses >= 0
      ? state.legacyEmptyPasses
      : 0,
    legacyNextScanAt: Number.isSafeInteger(state?.legacyNextScanAt) && state.legacyNextScanAt >= 0
      ? state.legacyNextScanAt
      : 0,
    cleanupComplete: state?.cleanupComplete === true,
  };
}

function resourceKey(resource) {
  if (resource?.kind === 'free') return `${RESOURCE_PREFIX}quota:free`;
  if (resource?.kind === 'daily' && DATE_PATTERN.test(resource.date || '')) {
    return `${RESOURCE_PREFIX}quota:daily:${resource.date}`;
  }
  if (resource?.kind === 'entitlement' && HASH_PATTERN.test(resource.originalHash || '')) {
    return `${RESOURCE_PREFIX}entitlement:${resource.originalHash}`;
  }
  return null;
}

function publicResource(key, value, now) {
  const suffix = key.slice(RESOURCE_PREFIX.length);
  let resource;
  if (suffix === 'quota:free') resource = { kind: 'free' };
  else if (suffix.startsWith('quota:daily:') && DATE_PATTERN.test(suffix.slice(12))) {
    resource = { kind: 'daily', date: suffix.slice(12) };
  } else if (suffix.startsWith('entitlement:') && HASH_PATTERN.test(suffix.slice(12))) {
    resource = { kind: 'entitlement', originalHash: suffix.slice(12) };
  } else throw new Error('invalid privacy resource');
  const pending = value?.status === 'pending' && Number.isSafeInteger(value.verifyAfterMs);
  return {
    id: suffix,
    ...resource,
    revision: Number.isSafeInteger(value?.revision) && value.revision > 0 ? value.revision : 1,
    status: pending ? 'pending' : 'tracked',
    ready: pending && now >= value.verifyAfterMs,
  };
}

function json(status, value) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

async function readJson(request) {
  try {
    const body = await request.json();
    return body && typeof body === 'object' && !Array.isArray(body) ? body : null;
  } catch {
    return null;
  }
}

export class DevicePrivacyCoordinator {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });
    if (url.pathname === '/begin') return this.begin();
    if (url.pathname === '/erase') return this.erase();
    if (url.pathname === '/track') {
      const body = await readJson(request);
      return body ? this.track(body) : json(400, { error: 'invalid_request' });
    }
    if (url.pathname === '/mark-pending') {
      const body = await readJson(request);
      return body ? this.markPending(body) : json(400, { error: 'invalid_request' });
    }
    if (url.pathname === '/ack-resource') {
      const body = await readJson(request);
      return body ? this.ackResource(body) : json(400, { error: 'invalid_request' });
    }
    if (url.pathname === '/cleanup-state') return this.cleanupState();
    if (url.pathname === '/record-cleanup') {
      const body = await readJson(request);
      return body ? this.recordCleanup(body) : json(400, { error: 'invalid_request' });
    }
    if (url.pathname === '/finish') {
      const body = await readJson(request);
      return body ? this.finish(body) : json(400, { error: 'invalid_request' });
    }
    return json(404, { error: 'not_found' });
  }

  async begin() {
    return this.ctx.storage.transaction(async (transaction) => {
      const state = normalizedState(await transaction.get(STATE_KEY));
      if (state.erased) return json(410, { error: 'device_erased' });
      const operationId = String(state.nextOperationId);
      await transaction.put(STATE_KEY, { ...state, nextOperationId: state.nextOperationId + 1 });
      await transaction.put(`${LEASE_PREFIX}${operationId}`, { v: 1 });
      return json(200, { operationId });
    });
  }

  async finish(body) {
    if (!OPERATION_ID_PATTERN.test(body.operationId || '')) {
      return json(400, { error: 'invalid_request' });
    }
    await this.ctx.storage.transaction(async (transaction) => {
      await transaction.delete(`${LEASE_PREFIX}${body.operationId}`);
    });
    return json(200, { ok: true });
  }

  async erase() {
    return this.ctx.storage.transaction(async (transaction) => {
      const state = normalizedState(await transaction.get(STATE_KEY));
      if (!state.erased) await transaction.put(STATE_KEY, { ...state, erased: true });
      const activeLeases = (await transaction.list({ prefix: LEASE_PREFIX })).size;
      return json(activeLeases > 0 ? 202 : 200, { erased: true, activeLeases });
    });
  }

  now() {
    const injected = this.env?.TEST_CLOCK?.now;
    const value = typeof injected === 'function' ? injected() : Date.now();
    if (!Number.isSafeInteger(value) || value < 0) throw new Error('invalid clock');
    return value;
  }

  async track(body) {
    if (
      !OPERATION_ID_PATTERN.test(body.operationId || '')
      || !Array.isArray(body.resources)
      || body.resources.length < 1
      || body.resources.length > 4
    ) return json(400, { error: 'invalid_request' });
    const entries = body.resources.map((resource) => [resourceKey(resource), resource]);
    if (entries.some(([key]) => key === null)) return json(400, { error: 'invalid_request' });

    return this.ctx.storage.transaction(async (transaction) => {
      if (!await transaction.get(`${LEASE_PREFIX}${body.operationId}`)) {
        return json(409, { error: 'lease_not_active' });
      }
      for (const [key, resource] of entries) {
        const existing = await transaction.get(key);
        const revision = Number.isSafeInteger(existing?.revision) && existing.revision > 0
          ? existing.revision + 1
          : 1;
        await transaction.put(key, { v: 1, ...resource, status: 'tracked', revision });
      }
      return json(200, { ok: true });
    });
  }

  async markPending(body) {
    const key = `${RESOURCE_PREFIX}${body.resourceId || ''}`;
    if (!body.resourceId || !Number.isSafeInteger(body.revision) || body.revision < 1) {
      return json(400, { error: 'invalid_request' });
    }
    return this.ctx.storage.transaction(async (transaction) => {
      const existing = await transaction.get(key);
      if (!existing || (existing.revision ?? 1) !== body.revision) {
        return json(409, { error: 'resource_changed' });
      }
      await transaction.put(key, {
        ...existing,
        status: 'pending',
        revision: body.revision + 1,
        verifyAfterMs: this.now() + VERIFICATION_DELAY_MS,
      });
      return json(200, { ok: true });
    });
  }

  async ackResource(body) {
    const key = `${RESOURCE_PREFIX}${body.resourceId || ''}`;
    if (!body.resourceId || !Number.isSafeInteger(body.revision) || body.revision < 1) {
      return json(400, { error: 'invalid_request' });
    }
    return this.ctx.storage.transaction(async (transaction) => {
      const existing = await transaction.get(key);
      if (!existing || (existing.revision ?? 1) !== body.revision) {
        return json(409, { error: 'resource_changed' });
      }
      await transaction.delete(key);
      return json(200, { ok: true });
    });
  }

  async cleanupState() {
    const state = normalizedState(await this.ctx.storage.get(STATE_KEY));
    if (!state.erased) return json(409, { error: 'device_not_erased' });
    const now = this.now();
    const resources = [...(await this.ctx.storage.list({ prefix: RESOURCE_PREFIX })).entries()]
      .slice(0, CATALOG_LIMIT)
      .map(([key, value]) => publicResource(key, value, now));
    return json(200, {
      cleanupPhase: state.cleanupPhase,
      cleanupBatch: state.cleanupBatch,
      resources,
      legacyReady: now >= state.legacyNextScanAt,
      legacyEmptyPasses: state.legacyEmptyPasses,
      cleanupComplete: state.cleanupComplete,
    });
  }

  async recordCleanup(body) {
    if (
      !Number.isSafeInteger(body.phase)
      || body.phase < 0
      || typeof body.complete !== 'boolean'
      || typeof body.dirty !== 'boolean'
    ) return json(400, { error: 'invalid_request' });

    return this.ctx.storage.transaction(async (transaction) => {
      const state = normalizedState(await transaction.get(STATE_KEY));
      if (!state.erased) return json(409, { error: 'device_not_erased' });
      if (state.cleanupPhase !== body.phase) {
        if (body.dirty) {
          const reset = {
            ...state,
            cleanupPhase: 0,
            cleanupBatch: 0,
            legacyDirty: false,
            legacyEmptyPasses: 0,
            legacyNextScanAt: this.now() + VERIFICATION_DELAY_MS,
            cleanupComplete: false,
          };
          await transaction.put(STATE_KEY, reset);
          return json(200, {
            cleanupPhase: reset.cleanupPhase,
            cleanupBatch: reset.cleanupBatch,
            legacyReady: false,
            legacyEmptyPasses: 0,
            cleanupComplete: false,
          });
        }
        return json(409, {
          error: 'cleanup_phase_conflict',
          cleanupPhase: state.cleanupPhase,
          cleanupBatch: state.cleanupBatch,
          legacyReady: this.now() >= state.legacyNextScanAt,
          legacyEmptyPasses: state.legacyEmptyPasses,
          cleanupComplete: state.cleanupComplete,
        });
      }
      let next;
      if (!body.complete) {
        next = {
          ...state,
          cleanupBatch: state.cleanupBatch + 1,
          legacyDirty: state.legacyDirty || body.dirty,
        };
      } else if (state.cleanupPhase < 4) {
        next = {
          ...state,
          cleanupPhase: state.cleanupPhase + 1,
          cleanupBatch: 0,
          legacyDirty: state.legacyDirty || body.dirty,
        };
      } else {
        const dirty = state.legacyDirty || body.dirty;
        const emptyPasses = dirty ? 0 : state.legacyEmptyPasses + 1;
        next = {
          ...state,
          cleanupPhase: 0,
          cleanupBatch: 0,
          legacyDirty: false,
          legacyEmptyPasses: emptyPasses,
          legacyNextScanAt: this.now() + VERIFICATION_DELAY_MS,
          cleanupComplete: emptyPasses >= 2,
        };
      }
      await transaction.put(STATE_KEY, next);
      return json(200, {
        cleanupPhase: next.cleanupPhase,
        cleanupBatch: next.cleanupBatch,
        legacyReady: this.now() >= next.legacyNextScanAt,
        legacyEmptyPasses: next.legacyEmptyPasses,
        cleanupComplete: next.cleanupComplete,
      });
    });
  }
}
