// 纯 Node 自测：内存 KV 存根 + fetch 拦截，覆盖生产请求契约和 free/pro 语义。
// 运行：node --test test.mjs
import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import worker, {
  appStoreNotifications,
  chatCompletions,
  quotaCheck,
  registerPro,
  todayUTC,
} from './src/index.js';
import {
  AppStoreJwsError,
  verifyAppStoreTransaction,
} from './src/app-store-jws.js';
import {
  AppStoreNotificationError,
  processAppStoreNotification,
} from './src/app-store-notifications.js';
import { EntitlementCoordinator } from './src/entitlement-coordinator.js';
import { DevicePrivacyCoordinator } from './src/device-privacy-coordinator.js';
import { APPLE_ROOT_CERTIFICATES } from './src/apple-root-certificates.js';
import {
  FIXTURE_EXPIRED_CERT_NOW_MS,
  FIXTURE_NOW_MS,
  alterJwsSegment,
  fixtureCertificates,
  signFixtureJws,
  signSelfSignedFixtureJws,
  validTransaction,
} from './test-fixtures/app-store-pki/fixture.mjs';

const VALID_DEVICE_ID = 'anon-device_1234567890';
const ERASURE_DEVICE_ID = '123E4567-E89B-42D3-A456-426614174000';
const ERASURE_SUPPORT_ID = `TD-${ERASURE_DEVICE_ID}`;
const ERASURE_ADMIN_TOKEN = 'test-admin-token-with-at-least-32-chars';
const ALLOWED_ORIGIN = 'https://todo.example.com';
const MAX_BODY_BYTES = 64 * 1024;
const MAX_MESSAGES = 32;
const MAX_CONTENT_CHARS = 16_000;

async function erasedDeviceKey(deviceId) {
  const digest = new Uint8Array(await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(`todo-erased-device:v1\0${deviceId}`),
  ));
  return `erased-device:${[...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('')}`;
}

class MemKV {
  constructor() {
    this.map = new Map();
    this.getCalls = 0;
    this.putCalls = 0;
    this.listCalls = 0;
  }
  async get(key) {
    this.getCalls += 1;
    return this.map.has(key) ? this.map.get(key) : null;
  }
  async put(key, value) {
    this.putCalls += 1;
    this.map.set(key, String(value));
  }
  async delete(key) {
    this.map.delete(key);
  }
  async list({ prefix = '', cursor } = {}) {
    this.listCalls += 1;
    const matching = [...this.map.keys()].filter((key) => key.startsWith(prefix)).sort();
    const start = cursor ? Number(cursor) : 0;
    const pageSize = this.pageSize || matching.length || 1;
    const page = matching.slice(start, start + pageSize);
    const next = start + page.length;
    return {
      keys: page.map((name) => ({ name })),
      list_complete: next >= matching.length,
      cursor: next >= matching.length ? '' : String(next),
    };
  }
}

class DeterministicDurableStorage {
  constructor() {
    this.map = new Map();
    this.tail = Promise.resolve();
  }
  async get(key) { return this.map.get(key); }
  async put(key, value) { this.map.set(key, structuredClone(value)); }
  async delete(key) { this.map.delete(key); }
  async list({ prefix = '' } = {}) {
    return new Map([...this.map].filter(([key]) => key.startsWith(prefix)));
  }
  async transaction(callback) {
    const run = this.tail.then(() => callback(this));
    this.tail = run.catch(() => {});
    return run;
  }
}

class DeterministicDurableNamespace {
  constructor(env) {
    this.env = env;
    this.instances = new Map();
  }
  idFromName(name) { return name; }
  get(id) {
    if (!this.instances.has(id)) {
      const storage = new DeterministicDurableStorage();
      const instance = new EntitlementCoordinator({ storage }, this.env);
      this.instances.set(id, { instance, storage });
    }
    return { fetch: (request) => this.instances.get(id).instance.fetch(request) };
  }
}

class DeterministicCoordinatorNamespace {
  constructor(env, CoordinatorClass) {
    this.env = env;
    this.CoordinatorClass = CoordinatorClass;
    this.instances = new Map();
  }
  idFromName(name) { return name; }
  get(id) {
    if (!this.instances.has(id)) {
      const storage = new DeterministicDurableStorage();
      const instance = new this.CoordinatorClass({ storage }, this.env);
      this.instances.set(id, { storage, instance });
    }
    return { fetch: (request) => this.instances.get(id).instance.fetch(request) };
  }
}

async function enableDevicePrivacy(env) {
  const { DevicePrivacyCoordinator } = await import('./src/device-privacy-coordinator.js');
  env.DEVICE_PRIVACY = new DeterministicCoordinatorNamespace(env, DevicePrivacyCoordinator);
  return env.DEVICE_PRIVACY;
}

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

function makeEnv({ pro = null, debug = false, key = 'sk-test', quota = true } = {}) {
  const kv = new MemKV();
  const env = {
    DEBUG_PRO_ALLOWED: debug ? '1' : undefined,
    ALLOWED_ORIGINS: `${ALLOWED_ORIGIN}, https://app.example.com`,
    APP_STORE_BUNDLE_ID: 'com.zhili.todo-native',
    APP_STORE_ENVIRONMENT: 'Sandbox',
    TEST_NOW_MS: FIXTURE_NOW_MS,
  };
  env.TEST_CLOCK = { now: () => env.TEST_NOW_MS };
  if (quota) env.QUOTA = kv;
  env.ENTITLEMENTS = new DeterministicDurableNamespace(env);
  env.DEVICE_PRIVACY = new DeterministicCoordinatorNamespace(env, DevicePrivacyCoordinator);
  if (key) env.DEEPSEEK_API_KEY = key;
  if (pro) kv.map.set(`pro:${pro}`, new Date(Date.now() + 86400e3).toISOString());
  return { env, kv };
}

function fixtureVerificationOptions(overrides = {}) {
  return {
    bundleId: 'com.zhili.todo-native',
    environment: 'Sandbox',
    productIds: [
      'com.zhili.todo.premium.monthly',
      'com.zhili.todo.premium.yearly',
    ],
    now: FIXTURE_NOW_MS,
    trustedRoots: [fixtureCertificates.root],
    ...overrides,
  };
}

async function signedNotification({
  notificationType = 'DID_RENEW',
  notificationUUID = '123e4567-e89b-42d3-a456-426614174000',
  transaction = validTransaction({ transactionId: '2000000000000099' }),
  environment = 'Sandbox',
  bundleId = 'com.zhili.todo-native',
  appAppleId,
  nestedJws,
  outerOverrides = {},
} = {}) {
  const signedTransactionInfo = nestedJws ?? await signFixtureJws(transaction);
  return signFixtureJws({
    notificationType,
    notificationUUID,
    version: '2.0',
    signedDate: FIXTURE_NOW_MS,
    data: {
      bundleId,
      environment,
      ...(appAppleId === undefined ? {} : { appAppleId }),
      signedTransactionInfo,
    },
    ...outerOverrides,
  });
}

function notificationDependencies(overrides = {}) {
  return {
    now: FIXTURE_NOW_MS,
    trustedRoots: [fixtureCertificates.root],
    ...overrides,
  };
}

async function expectJwsError(jws, code, overrides = {}) {
  await assert.rejects(
    verifyAppStoreTransaction(jws, fixtureVerificationOptions(overrides)),
    (error) => error instanceof AppStoreJwsError && error.code === code,
  );
}

let upstreamMode;
let upstreamCalls;
let lastUpstreamBody;
let upstreamGate;

beforeEach(() => {
  upstreamMode = 'ok';
  upstreamCalls = 0;
  lastUpstreamBody = null;
  upstreamGate = null;
});

globalThis.fetch = async (url, init) => {
  upstreamCalls += 1;
  assert.equal(url, 'https://api.deepseek.com/chat/completions');
  lastUpstreamBody = JSON.parse(init.body);
  assert.equal(lastUpstreamBody.model, 'deepseek-v4-flash');
  assert.equal(init.headers.Authorization, 'Bearer sk-test');
  if (upstreamMode === 'throw') {
    throw new Error('network failed with sk-secret and private request body');
  }
  if (upstreamMode === 'defer') {
    upstreamGate.reached.resolve();
    await upstreamGate.release.promise;
  }
  if (upstreamMode === 'error') {
    return new Response('{"error":{"message":"provider secret: sk-live-private"}}', {
      status: 507,
      headers: { 'content-type': 'application/json' },
    });
  }
  return new Response(JSON.stringify({ id: 'chatcmpl-test', choices: [] }), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
};

function chatReq(
  deviceId = VALID_DEVICE_ID,
  body = { messages: [{ role: 'user', content: 'hi' }] },
  headers = {},
) {
  const requestHeaders = { 'Content-Type': 'application/json', ...headers };
  if (deviceId !== null) requestHeaders['X-Device-Id'] = deviceId;
  return new Request('https://todo-quota-proxy.test.workers.dev/proxy/chat/completions', {
    method: 'POST',
    headers: requestHeaders,
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

function routeReq(path, { method = 'GET', deviceId = VALID_DEVICE_ID, origin, body } = {}) {
  const headers = {};
  if (deviceId !== null) headers['X-Device-Id'] = deviceId;
  if (origin) headers.Origin = origin;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  return new Request(`https://todo-quota-proxy.test.workers.dev${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

function erasureReq({ token = ERASURE_ADMIN_TOKEN, supportId = ERASURE_SUPPORT_ID } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token !== null) headers.Authorization = `Bearer ${token}`;
  return new Request('https://todo-quota-proxy.test.workers.dev/internal/erase-device', {
    method: 'POST',
    headers,
    body: JSON.stringify({ supportId }),
  });
}

async function eraseUntilDone(env, options = {}) {
  let response;
  let attempts = 0;
  do {
    response = await worker.fetch(erasureReq(options), env);
    attempts += 1;
    assert.ok(attempts <= 100, 'erasure cleanup must converge');
    if (response.status === 202 && Number.isSafeInteger(env.TEST_NOW_MS)) {
      env.TEST_NOW_MS += 65_000;
    }
  } while (response.status === 202);
  return { response, attempts };
}

function streamingChatReq(chunks, headers = {}) {
  let index = 0;
  const stats = { pulls: 0, cancels: 0 };
  const stream = new ReadableStream({
    pull(controller) {
      stats.pulls += 1;
      if (index >= chunks.length) {
        controller.close();
        return;
      }
      controller.enqueue(chunks[index]);
      index += 1;
    },
    cancel() {
      stats.cancels += 1;
    },
  }, { highWaterMark: 0 });
  const request = new Request('https://todo-quota-proxy.test.workers.dev/proxy/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Device-Id': VALID_DEVICE_ID,
      ...headers,
    },
    body: stream,
    duplex: 'half',
  });
  return { request, stats };
}

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

async function expectError(response, status, code) {
  assert.equal(response.status, status);
  assert.deepEqual(await response.json(), { error: { code } });
}

test('OPTIONS only permits configured origins and advertises bounded CORS contract', async () => {
  const { env } = makeEnv();
  const allowed = await worker.fetch(routeReq('/proxy/chat/completions', {
    method: 'OPTIONS',
    origin: ALLOWED_ORIGIN,
    deviceId: null,
  }), env);
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get('access-control-allow-origin'), ALLOWED_ORIGIN);
  assert.equal(allowed.headers.get('access-control-allow-methods'), 'POST, OPTIONS');
  assert.equal(allowed.headers.get('access-control-allow-headers'), 'Content-Type, X-Device-Id');
  assert.equal(allowed.headers.get('vary'), 'Origin');

  const rejected = await worker.fetch(routeReq('/proxy/chat/completions', {
    method: 'OPTIONS',
    origin: 'https://evil.example',
    deviceId: null,
  }), env);
  await expectError(rejected, 403, 'origin_not_allowed');
  assert.equal(rejected.headers.get('access-control-allow-origin'), null);
});

test('actual browser responses expose CORS only for configured exact origins', async () => {
  const { env } = makeEnv();
  const allowed = await worker.fetch(routeReq('/proxy/quota', { origin: ALLOWED_ORIGIN }), env);
  assert.equal(allowed.status, 200);
  assert.equal(allowed.headers.get('access-control-allow-origin'), ALLOWED_ORIGIN);

  const rejected = await worker.fetch(routeReq('/proxy/quota', { origin: 'https://evil.example' }), env);
  await expectError(rejected, 403, 'origin_not_allowed');
  assert.equal(rejected.headers.get('access-control-allow-origin'), null);
});

test('unknown routes return 404 and known routes reject non-contract methods with 405', async () => {
  const { env, kv } = makeEnv();
  await expectError(await worker.fetch(routeReq('/proxy/nope'), env), 404, 'not_found');
  const wrongMethod = await worker.fetch(routeReq('/proxy/quota', { method: 'POST' }), env);
  await expectError(wrongMethod, 405, 'method_not_allowed');
  assert.equal(wrongMethod.headers.get('allow'), 'GET, OPTIONS');
  assert.equal(kv.getCalls, 0);
  assert.equal(upstreamCalls, 0);
});

test('owner erasure route rejects missing and incorrect bearer tokens without reading device data', async () => {
  const { env, kv } = makeEnv();
  env.ERASURE_ADMIN_TOKEN = 'test-admin-token-with-at-least-32-chars';
  for (const authorization of [null, 'Bearer incorrect-admin-token-with-32-chars']) {
    const headers = { 'Content-Type': 'application/json' };
    if (authorization) headers.Authorization = authorization;
    const response = await worker.fetch(new Request(
      'https://todo-quota-proxy.test.workers.dev/internal/erase-device',
      {
        method: 'POST',
        headers,
        body: JSON.stringify({ supportId: 'TD-123e4567-e89b-42d3-a456-426614174000' }),
      },
    ), env);
    await expectError(response, 401, 'unauthorized');
  }
  assert.equal(kv.getCalls, 0);
  assert.equal(kv.putCalls, 0);
});

test('device id is required, bounded, and opaque before KV or upstream access', async () => {
  const invalidIds = [null, '', '   ', 'short-id', 'a'.repeat(129), 'person@example.com', '../device-id-123456'];
  for (const deviceId of invalidIds) {
    const { env, kv } = makeEnv();
    const response = await chatCompletions(env, chatReq(deviceId));
    const code = deviceId === null || String(deviceId).trim() === ''
      ? 'missing_device_id'
      : 'invalid_device_id';
    await expectError(response, 401, code);
    assert.equal(kv.getCalls, 0, `KV read for invalid id: ${String(deviceId)}`);
    assert.equal(upstreamCalls, 0, `upstream call for invalid id: ${String(deviceId)}`);
  }
});

test('DevicePrivacyCoordinator serializes leases against erase and stores no raw device identity', async () => {
  const { env } = makeEnv();
  const namespace = await enableDevicePrivacy(env);
  const deviceHash = (await erasedDeviceKey(ERASURE_DEVICE_ID)).slice('erased-device:'.length);
  const stub = namespace.get(namespace.idFromName(deviceHash));
  const post = (path, body = {}) => stub.fetch(new Request(`https://privacy.internal${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }));

  const begin = await post('/begin');
  assert.equal(begin.status, 200);
  const lease = await begin.json();
  assert.match(lease.operationId, /^[0-9]+$/);

  const firstErase = await post('/erase');
  assert.equal(firstErase.status, 202);
  assert.deepEqual(await firstErase.json(), { erased: true, activeLeases: 1 });
  assert.equal((await post('/begin')).status, 410);
  assert.equal((await post('/finish', { operationId: lease.operationId })).status, 200);
  const completed = await post('/erase');
  assert.equal(completed.status, 200);
  assert.deepEqual(await completed.json(), { erased: true, activeLeases: 0 });
  assert.equal((await post('/erase')).status, 200, 'duplicate erase is idempotent');

  const persisted = JSON.stringify([...namespace.instances.values()].map(({ storage }) => [...storage.map]));
  assert.doesNotMatch(persisted, new RegExp(ERASURE_DEVICE_ID, 'i'));
});

test('authorized erasure deletes every device key and entitlement mapping, then remains idempotently erased', async () => {
  const { env, kv } = makeEnv();
  env.ERASURE_ADMIN_TOKEN = ERASURE_ADMIN_TOKEN;
  kv.pageSize = 1;
  const dependencies = notificationDependencies();
  const originalTransactionId = '2000000000000990';
  const jws = await signFixtureJws(validTransaction({
    transactionId: '2000000000000991',
    originalTransactionId,
  }));
  assert.equal((await registerPro(env, ERASURE_DEVICE_ID, { transactionJwt: jws }, dependencies)).ok, true);
  const pointerPrefix = `appstore-device-subscription:${ERASURE_DEVICE_ID}:`;
  const originalHash = [...kv.map.keys()].find((key) => key.startsWith(pointerPrefix)).slice(pointerPrefix.length);
  kv.map.set(`appstore-original:${originalHash}:${ERASURE_DEVICE_ID}:legacy-a`, '1');
  kv.map.set(`appstore-original:${originalHash}:${ERASURE_DEVICE_ID}:legacy-b`, '1');
  kv.map.set(`free:${ERASURE_DEVICE_ID}`, '3');
  kv.map.set(`pro:${ERASURE_DEVICE_ID}`, 'legacy');
  kv.map.set(`daily:${ERASURE_DEVICE_ID}:2030-01-01`, '4');
  kv.map.set(`daily:${ERASURE_DEVICE_ID}:2030-01-02`, '5');

  const { response: first, attempts } = await eraseUntilDone(env);
  assert.equal(first.status, 200);
  assert.ok(attempts > 1, 'bounded cleanup requires explicit retries');
  assert.deepEqual(await first.json(), { ok: true, status: 'erased' });
  assert.equal([...kv.map.keys()].some((key) => key.includes(ERASURE_DEVICE_ID)), false);

  const deviceHash = (await erasedDeviceKey(ERASURE_DEVICE_ID)).slice('erased-device:'.length);
  const entitlementStorage = [...env.ENTITLEMENTS.instances.values()][0].storage;
  assert.equal(entitlementStorage.map.has(`device:${deviceHash}`), false);

  await expectError(await worker.fetch(routeReq('/proxy/quota', {
    deviceId: ERASURE_DEVICE_ID,
  }), env), 410, 'device_erased');
  await expectError(await worker.fetch(routeReq('/proxy/register-pro', {
    method: 'POST',
    deviceId: ERASURE_DEVICE_ID,
    body: { transactionJwt: jws },
  }), env), 410, 'device_erased');

  const notification = await signedNotification({
    transaction: validTransaction({
      transactionId: '2000000000000992',
      originalTransactionId,
      expiresDate: Date.UTC(2032, 0, 1),
    }),
  });
  await processAppStoreNotification(env, notification, dependencies);
  assert.equal(entitlementStorage.map.has(`device:${deviceHash}`), false);
  assert.equal([...kv.map.keys()].some((key) => key.includes(ERASURE_DEVICE_ID)), false);

  const duplicate = await worker.fetch(erasureReq(), env);
  assert.equal(duplicate.status, 200);
  assert.deepEqual(await duplicate.json(), { ok: true, status: 'erased' });
  const persisted = JSON.stringify([
    [...kv.map],
    [...entitlementStorage.map],
    [...env.DEVICE_PRIVACY.instances.values()].map(({ storage }) => [...storage.map]),
  ]);
  assert.doesNotMatch(persisted, new RegExp(ERASURE_DEVICE_ID, 'i'));
  assert.doesNotMatch(persisted, new RegExp(jws.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
});

test('UUID device identity is canonical across upper/lower requests and lower Support ID erases the same identity', async () => {
  const lowerDeviceId = ERASURE_DEVICE_ID.toLowerCase();
  const { env, kv } = makeEnv();
  env.ERASURE_ADMIN_TOKEN = ERASURE_ADMIN_TOKEN;

  assert.equal((await worker.fetch(chatReq(lowerDeviceId), env)).status, 200);
  const upperQuota = await worker.fetch(routeReq('/proxy/quota', {
    deviceId: ERASURE_DEVICE_ID,
  }), env);
  assert.equal(upperQuota.status, 200);
  assert.equal((await upperQuota.json()).freeUsed, 1);
  assert.equal(kv.map.has(`free:${ERASURE_DEVICE_ID}`), true);
  assert.equal(kv.map.has(`free:${lowerDeviceId}`), false);
  assert.equal(env.DEVICE_PRIVACY.instances.size, 1);

  const erased = await worker.fetch(erasureReq({
    supportId: `TD-${lowerDeviceId}`,
  }), env);
  assert.ok([200, 202].includes(erased.status));
  let response = erased;
  while (response.status === 202) {
    env.TEST_NOW_MS += 65_000;
    response = await worker.fetch(erasureReq({
      supportId: `TD-${lowerDeviceId}`,
    }), env);
  }
  assert.equal(response.status, 200);
  await expectError(await worker.fetch(routeReq('/proxy/quota', {
    deviceId: ERASURE_DEVICE_ID,
  }), env), 410, 'device_erased');
  await expectError(await worker.fetch(routeReq('/proxy/quota', {
    deviceId: lowerDeviceId,
  }), env), 410, 'device_erased');
  assert.equal(env.DEVICE_PRIVACY.instances.size, 1);
});

test('erasure reverses safely against an in-flight chat lease and blocks later operations strongly', async () => {
  const { env, kv } = makeEnv();
  env.ERASURE_ADMIN_TOKEN = ERASURE_ADMIN_TOKEN;
  upstreamMode = 'defer';
  upstreamGate = { reached: deferred(), release: deferred() };

  const chat = worker.fetch(chatReq(ERASURE_DEVICE_ID), env);
  await upstreamGate.reached.promise;
  const whileInflight = await worker.fetch(erasureReq(), env);
  assert.equal(whileInflight.status, 202);
  assert.deepEqual(await whileInflight.json(), { ok: false, status: 'retry' });
  assert.equal([...kv.map.keys()].some((key) => key.includes(ERASURE_DEVICE_ID)), false);

  upstreamGate.release.resolve();
  assert.equal((await chat).status, 200);
  assert.equal(kv.map.get(`free:${ERASURE_DEVICE_ID}`), '1');
  assert.equal((await eraseUntilDone(env)).response.status, 200);
  assert.equal([...kv.map.keys()].some((key) => key.includes(ERASURE_DEVICE_ID)), false);
  await expectError(await worker.fetch(chatReq(ERASURE_DEVICE_ID), env), 410, 'device_erased');
  assert.equal(upstreamCalls, 1);
});

test('erasure waits for an in-flight registration lease before deleting its pointer and DO mapping', async () => {
  class DelayedPointerKV extends MemKV {
    constructor() {
      super();
      this.pointerReached = deferred();
      this.releasePointer = deferred();
    }
    async put(key, value) {
      if (key.startsWith('appstore-device-subscription:')) {
        this.pointerReached.resolve();
        await this.releasePointer.promise;
      }
      return super.put(key, value);
    }
  }

  const { env } = makeEnv();
  const kv = new DelayedPointerKV();
  env.QUOTA = kv;
  env.ERASURE_ADMIN_TOKEN = ERASURE_ADMIN_TOKEN;
  const jws = await signFixtureJws();
  const registration = registerPro(
    env,
    ERASURE_DEVICE_ID,
    { transactionJwt: jws },
    notificationDependencies(),
  );
  await kv.pointerReached.promise;

  const firstErase = await worker.fetch(erasureReq(), env);
  assert.equal(firstErase.status, 202);
  assert.deepEqual(await firstErase.json(), { ok: false, status: 'retry' });
  kv.releasePointer.resolve();
  assert.equal((await registration).ok, true);

  assert.equal((await eraseUntilDone(env)).response.status, 200);
  assert.equal([...kv.map.keys()].some((key) => key.includes(ERASURE_DEVICE_ID)), false);
  await expectError(await worker.fetch(routeReq('/proxy/register-pro', {
    method: 'POST',
    deviceId: ERASURE_DEVICE_ID,
    body: { transactionJwt: jws },
  }), env), 410, 'device_erased');
});

test('authorized erasure validates bounded Support ID safely and requires privacy configuration', async () => {
  const configured = makeEnv();
  configured.env.ERASURE_ADMIN_TOKEN = ERASURE_ADMIN_TOKEN;
  for (const supportId of ['TD-not-a-uuid', `TD-${'a'.repeat(200)}`]) {
    const response = await worker.fetch(erasureReq({ supportId }), configured.env);
    const safeBody = response.clone();
    await expectError(response, 400, 'invalid_request_body');
    assert.doesNotMatch(await safeBody.text(), new RegExp(supportId.slice(0, 8), 'i'));
  }

  const missing = makeEnv();
  missing.env.ERASURE_ADMIN_TOKEN = ERASURE_ADMIN_TOKEN;
  delete missing.env.DEVICE_PRIVACY;
  await expectError(await worker.fetch(erasureReq(), missing.env), 503, 'service_not_configured');
  assert.equal(missing.kv.getCalls, 0);
  assert.equal(missing.kv.putCalls, 0);

  const noDelete = makeEnv();
  noDelete.env.ERASURE_ADMIN_TOKEN = ERASURE_ADMIN_TOKEN;
  noDelete.env.QUOTA.delete = undefined;
  await expectError(await worker.fetch(erasureReq(), noDelete.env), 503, 'service_not_configured');
  assert.equal(noDelete.env.DEVICE_PRIVACY.instances.size, 0);
});

test('register persists the immutable discovery pointer before DO mapping and never maps after pointer failure', async () => {
  class FailingRegisterNamespace extends DeterministicDurableNamespace {
    get(id) {
      const original = super.get(id);
      return {
        fetch: async (request) => {
          if (new URL(request.url).pathname === '/register') {
            return new Response('{"error":"failed"}', {
              status: 500,
              headers: { 'Content-Type': 'application/json' },
            });
          }
          return original.fetch(request);
        },
      };
    }
  }
  const first = makeEnv();
  first.env.ENTITLEMENTS = new FailingRegisterNamespace(first.env);
  const jws = await signFixtureJws();
  await assert.rejects(registerPro(
    first.env,
    ERASURE_DEVICE_ID,
    { transactionJwt: jws },
    notificationDependencies(),
  ));
  assert.equal([...first.kv.map.keys()].some((key) => key.startsWith(
    `appstore-device-subscription:${ERASURE_DEVICE_ID}:`,
  )), true, 'pointer remains discoverable when DO mapping fails');

  class FailingPointerKV extends MemKV {
    async put(key, value) {
      if (key.startsWith('appstore-device-subscription:')) throw new Error('pointer failed');
      return super.put(key, value);
    }
  }
  const second = makeEnv();
  second.env.QUOTA = new FailingPointerKV();
  await assert.rejects(registerPro(
    second.env,
    ERASURE_DEVICE_ID,
    { transactionJwt: jws },
    notificationDependencies(),
  ));
  const durable = JSON.stringify(
    [...second.env.ENTITLEMENTS.instances.values()].map(({ storage }) => [...storage.map]),
  );
  assert.doesNotMatch(durable, /device:/, 'DO mapping is never written after pointer failure');
});

test('erasure cleanup is bounded and converges across repeated phase retries', async () => {
  const { env, kv } = makeEnv();
  env.ERASURE_ADMIN_TOKEN = ERASURE_ADMIN_TOKEN;
  kv.pageSize = 1;
  for (let day = 1; day <= 4; day += 1) {
    kv.map.set(`daily:${ERASURE_DEVICE_ID}:2030-01-0${day}`, String(day));
  }
  kv.map.set(`free:${ERASURE_DEVICE_ID}`, '2');

  let attempts = 0;
  let response;
  do {
    response = await worker.fetch(erasureReq(), env);
    attempts += 1;
    assert.ok(attempts < 30, 'cleanup must converge');
    if (response.status === 202) env.TEST_NOW_MS += 65_000;
  } while (response.status === 202);

  assert.equal(response.status, 200);
  assert.ok(attempts > 3, 'one request must not collect/delete all phases');
  assert.equal([...kv.map.keys()].some((key) => key.includes(ERASURE_DEVICE_ID)), false);
  const privacyStorage = [...env.DEVICE_PRIVACY.instances.values()][0].storage;
  const state = privacyStorage.map.get('privacy-state');
  assert.equal(state.erased, true);
  assert.ok(Number.isSafeInteger(state.cleanupPhase));
});

test('concurrent owner cleanup retries resolve phase conflicts idempotently', async () => {
  class ConcurrentDeleteKV extends MemKV {
    constructor() {
      super();
      this.freeDeletes = 0;
      this.bothReached = deferred();
      this.release = deferred();
    }
    async delete(key) {
      if (key === `free:${ERASURE_DEVICE_ID}`) {
        this.freeDeletes += 1;
        if (this.freeDeletes === 2) this.bothReached.resolve();
        await this.release.promise;
      }
      return super.delete(key);
    }
  }

  const { env } = makeEnv();
  const kv = new ConcurrentDeleteKV();
  env.QUOTA = kv;
  env.ERASURE_ADMIN_TOKEN = ERASURE_ADMIN_TOKEN;
  kv.map.set(`free:${ERASURE_DEVICE_ID}`, '2');

  const requests = [
    worker.fetch(erasureReq(), env),
    worker.fetch(erasureReq(), env),
  ];
  await kv.bothReached.promise;
  kv.release.resolve();
  const concurrent = await Promise.all(requests);
  assert.deepEqual(concurrent.map(({ status }) => status), [202, 202]);
  for (const response of concurrent) {
    assert.deepEqual(await response.json(), { ok: false, status: 'retry' });
  }
  assert.equal((await eraseUntilDone(env)).response.status, 200);
  assert.equal(kv.map.has(`free:${ERASURE_DEVICE_ID}`), false);
});

test('strong resource catalog prevents false erasure success across delayed KV visibility', async () => {
  class CrossColoKV extends MemKV {
    constructor(now) {
      super();
      this.now = now;
      this.visibleAt = new Map();
      this.deletedAt = new Map();
    }
    settle(key) {
      const deletedAt = this.deletedAt.get(key);
      if (deletedAt !== undefined && this.now() >= deletedAt) {
        this.map.delete(key);
        this.visibleAt.delete(key);
        this.deletedAt.delete(key);
      }
    }
    async get(key) {
      this.getCalls += 1;
      this.settle(key);
      if ((this.visibleAt.get(key) ?? 0) > this.now()) return null;
      return this.map.has(key) ? this.map.get(key) : null;
    }
    async put(key, value) {
      this.putCalls += 1;
      this.map.set(key, String(value));
      this.visibleAt.set(key, this.now() + 60_000);
      this.deletedAt.delete(key);
    }
    async delete(key) {
      if (this.map.has(key)) this.deletedAt.set(key, this.now() + 60_000);
    }
    async list({ prefix = '', cursor } = {}) {
      this.listCalls += 1;
      for (const key of [...this.map.keys()]) this.settle(key);
      const matching = [...this.map.keys()]
        .filter((key) => key.startsWith(prefix) && (this.visibleAt.get(key) ?? 0) <= this.now())
        .sort();
      const start = cursor ? Number(cursor) : 0;
      const pageSize = this.pageSize || matching.length || 1;
      const page = matching.slice(start, start + pageSize);
      const next = start + page.length;
      return {
        keys: page.map((name) => ({ name })),
        list_complete: next >= matching.length,
        cursor: next >= matching.length ? '' : String(next),
      };
    }
  }

  const { env } = makeEnv();
  const kv = new CrossColoKV(() => env.TEST_NOW_MS);
  env.QUOTA = kv;
  env.ERASURE_ADMIN_TOKEN = ERASURE_ADMIN_TOKEN;

  assert.equal((await worker.fetch(chatReq(ERASURE_DEVICE_ID), env)).status, 200);
  const jws = await signFixtureJws();
  assert.equal((await registerPro(
    env,
    ERASURE_DEVICE_ID,
    { transactionJwt: jws },
    notificationDependencies(),
  )).ok, true);

  const privacyStorage = [...env.DEVICE_PRIVACY.instances.values()][0].storage;
  assert.equal(
    [...privacyStorage.map.keys()].filter((key) => key.startsWith('resource:')).length,
    3,
    'free, current daily, and entitlement resources are strongly cataloged',
  );
  assert.equal((await kv.list({ prefix: `appstore-device-subscription:${ERASURE_DEVICE_ID}:` })).keys.length, 0);

  const firstErase = await worker.fetch(erasureReq(), env);
  assert.equal(firstErase.status, 202, 'eventually-consistent empty reads cannot produce 200');
  const { response, attempts } = await eraseUntilDone(env);
  assert.equal(response.status, 200);
  assert.ok(attempts >= 3, 'catalog verification and two legacy empty scans are time-gated');
  assert.equal([...privacyStorage.map.keys()].some((key) => key.startsWith('resource:')), false);
  const entitlementStorage = [...env.ENTITLEMENTS.instances.values()][0].storage;
  assert.equal([...entitlementStorage.map.keys()].some((key) => key.startsWith('device:')), false);
  assert.equal(await kv.get(`free:${ERASURE_DEVICE_ID}`), null);
  assert.equal((await kv.list({ prefix: `appstore-device-subscription:${ERASURE_DEVICE_ID}:` })).keys.length, 0);
  await expectError(await worker.fetch(routeReq('/proxy/quota', {
    deviceId: ERASURE_DEVICE_ID,
  }), env), 410, 'device_erased');
});

test('body byte limit rejects declared and actual oversized bodies before quota reads', async () => {
  for (const request of [
    chatReq(VALID_DEVICE_ID, { messages: [{ role: 'user', content: 'hi' }] }, { 'Content-Length': String(MAX_BODY_BYTES + 1) }),
    chatReq(VALID_DEVICE_ID, 'x'.repeat(MAX_BODY_BYTES + 1)),
  ]) {
    const { env, kv } = makeEnv();
    await expectError(await chatCompletions(env, request), 413, 'request_too_large');
    assert.equal(kv.getCalls, 0);
    assert.equal(upstreamCalls, 0);
  }
});

test('actual oversized stream stops at the first byte over limit and cancels its reader', async () => {
  const { env, kv } = makeEnv();
  const { request, stats } = streamingChatReq([
    new Uint8Array(32 * 1024).fill(97),
    new Uint8Array(32 * 1024).fill(97),
    new Uint8Array([97]),
    new Uint8Array(32 * 1024).fill(98),
  ]);

  await expectError(await chatCompletions(env, request), 413, 'request_too_large');
  assert.equal(stats.pulls, 3, 'must not pull chunks after crossing the byte limit');
  assert.equal(stats.cancels, 1, 'must cancel the source after crossing the byte limit');
  assert.equal(kv.getCalls, 0);
  assert.equal(upstreamCalls, 0);
});

test('bounded stream decoder preserves UTF-8 characters split across chunk boundaries', async () => {
  const { env } = makeEnv();
  const bytes = new TextEncoder().encode(JSON.stringify({
    messages: [{ role: 'user', content: '你好🙂' }],
  }));
  const emojiStart = bytes.indexOf(0xf0);
  const { request } = streamingChatReq([
    bytes.slice(0, emojiStart + 2),
    bytes.slice(emojiStart + 2),
  ]);

  const response = await chatCompletions(env, request);
  assert.equal(response.status, 200);
  assert.equal(lastUpstreamBody.messages[0].content, '你好🙂');
});

test('missing body keeps the stable invalid_request_body response', async () => {
  const { env, kv } = makeEnv();
  const request = new Request('https://todo-quota-proxy.test.workers.dev/proxy/chat/completions', {
    method: 'POST',
    headers: { 'X-Device-Id': VALID_DEVICE_ID },
  });
  await expectError(await chatCompletions(env, request), 400, 'invalid_request_body');
  assert.equal(kv.getCalls, 0);
  assert.equal(upstreamCalls, 0);
});

test('messages must be a bounded array of supported role/content string pairs', async () => {
  const invalidBodies = [
    {},
    { messages: [] },
    { messages: Array.from({ length: MAX_MESSAGES + 1 }, () => ({ role: 'user', content: 'x' })) },
    { messages: [{ role: 'tool', content: 'x' }] },
    { messages: [{ role: 'user', content: { text: 'x' } }] },
    { messages: [{ role: 'user', content: 'x'.repeat(MAX_CONTENT_CHARS + 1) }] },
  ];
  for (const body of invalidBodies) {
    const { env, kv } = makeEnv();
    await expectError(await chatCompletions(env, chatReq(VALID_DEVICE_ID, body)), 400, 'invalid_messages');
    assert.equal(kv.getCalls, 0);
    assert.equal(upstreamCalls, 0);
  }
});

test('invalid JSON is rejected before quota reads or upstream calls', async () => {
  const { env, kv } = makeEnv();
  await expectError(await chatCompletions(env, chatReq(VALID_DEVICE_ID, 'not json')), 400, 'invalid_request_body');
  assert.equal(kv.getCalls, 0);
  assert.equal(upstreamCalls, 0);
});

test('client model is ignored and provider model is always deepseek-v4-flash', async () => {
  const { env } = makeEnv();
  const response = await chatCompletions(env, chatReq(VALID_DEVICE_ID, {
    model: 'attacker-controlled-model',
    messages: [{ role: 'system', content: 'safe' }, { role: 'user', content: 'hello' }],
    stream: false,
  }));
  assert.equal(response.status, 200);
  assert.equal(lastUpstreamBody.model, 'deepseek-v4-flash');
});

test('managed requests force max_tokens to the fixed completion cap', async () => {
  const clientValues = [undefined, 8192, 128, 0, -1, '4096', null];
  for (const maxTokens of clientValues) {
    const { env } = makeEnv();
    const body = {
      messages: [{ role: 'user', content: 'make a short plan' }],
      ...(maxTokens === undefined ? {} : { max_tokens: maxTokens }),
    };
    assert.equal((await chatCompletions(env, chatReq(VALID_DEVICE_ID, body))).status, 200);
    assert.equal(lastUpstreamBody.max_tokens, 2048);
  }
});

test('free: 10 successes then quota_exceeded(free), preserving lifetime semantics', async () => {
  const { env, kv } = makeEnv();
  for (let i = 0; i < 10; i += 1) {
    assert.equal((await chatCompletions(env, chatReq(VALID_DEVICE_ID))).status, 200);
  }
  assert.equal(kv.map.get(`free:${VALID_DEVICE_ID}`), '10');
  const response = await chatCompletions(env, chatReq(VALID_DEVICE_ID));
  assert.equal(response.status, 402);
  assert.deepEqual(await response.json(), { error: { code: 'quota_exceeded', kind: 'free' } });
  assert.equal(kv.map.get(`free:${VALID_DEVICE_ID}`), '10');
});

test('pro: 20 successes per UTC day then quota_exceeded(daily)', async () => {
  const { env, kv } = makeEnv();
  const reg = await registerPro(env, VALID_DEVICE_ID, {
    transactionJwt: await signFixtureJws(),
  }, {
    now: FIXTURE_NOW_MS,
    trustedRoots: [fixtureCertificates.root],
  });
  assert.equal(reg.ok, true);
  for (let i = 0; i < 20; i += 1) {
    assert.equal((await chatCompletions(env, chatReq(VALID_DEVICE_ID))).status, 200);
  }
  assert.equal(kv.map.get(`daily:${VALID_DEVICE_ID}:${todayUTC()}`), '20');
  const response = await chatCompletions(env, chatReq(VALID_DEVICE_ID));
  assert.equal(response.status, 402);
  assert.deepEqual(await response.json(), { error: { code: 'quota_exceeded', kind: 'daily' } });
});

test('provider HTTP and network failures return stable client-safe bodies without consuming quota', async () => {
  for (const mode of ['error', 'throw']) {
    const { env, kv } = makeEnv();
    upstreamMode = mode;
    const response = await chatCompletions(env, chatReq(VALID_DEVICE_ID));
    assert.equal(response.status, 502);
    const text = await response.text();
    assert.deepEqual(JSON.parse(text), {
      error: { code: mode === 'error' ? 'provider_error' : 'provider_unavailable' },
    });
    assert.doesNotMatch(text, /sk-|private|provider secret|request body/i);
    assert.equal(kv.map.get(`free:${VALID_DEVICE_ID}`), undefined);
  }
});

test('missing QUOTA or DEEPSEEK_API_KEY returns safe 503 without KV/upstream work', async () => {
  const missingKv = makeEnv({ quota: false });
  await expectError(await chatCompletions(missingKv.env, chatReq()), 503, 'service_not_configured');
  assert.equal(upstreamCalls, 0);

  const missingKey = makeEnv({ key: null });
  await expectError(await chatCompletions(missingKey.env, chatReq()), 503, 'service_not_configured');
  assert.equal(missingKey.kv.getCalls, 0);
  assert.equal(upstreamCalls, 0);
});

test('quota endpoint validates QUOTA binding and device ID safely', async () => {
  const { env } = makeEnv({ quota: false });
  await expectError(await worker.fetch(routeReq('/proxy/quota'), env), 503, 'service_not_configured');

  const configured = makeEnv();
  await expectError(await worker.fetch(routeReq('/proxy/quota', { deviceId: 'unsafe/id-123456789' }), configured.env), 401, 'invalid_device_id');
  assert.equal(configured.kv.getCalls, 0);
});

test('quota calculation keeps free/pro fields and expired Pro falls back to free', async () => {
  const { env, kv } = makeEnv();
  kv.map.set(`free:${VALID_DEVICE_ID}`, '7');
  assert.deepEqual((await quotaCheck(env, VALID_DEVICE_ID)).quota, {
    freeUsed: 7,
    freeLimit: 10,
    proUsed: 0,
    proLimit: 20,
    isPro: false,
    today: todayUTC(),
  });
  kv.map.set(`free:${VALID_DEVICE_ID}`, '10');
  kv.map.set(`pro:${VALID_DEVICE_ID}`, new Date(Date.now() - 1000).toISOString());
  const expired = await quotaCheck(env, VALID_DEVICE_ID);
  assert.equal(expired.quota.isPro, false);
  assert.equal(expired.exceeded, true);
  assert.equal(expired.kind, 'free');
});

test('register-pro rejects the former debug bypass and accepts a signed yearly product', async () => {
  const debug = makeEnv({ debug: true });
  const debugReg = await registerPro(debug.env, VALID_DEVICE_ID, {
    transactionJwt: makeJwt({ debugPro: true, productId: 'whatever' }),
  });
  assert.equal(debugReg.ok, false);
  assert.equal(debug.kv.map.has(`pro:${VALID_DEVICE_ID}`), false);

  const normal = makeEnv();
  const yearly = await registerPro(normal.env, VALID_DEVICE_ID, {
    transactionJwt: await signFixtureJws(validTransaction({
      productId: 'com.zhili.todo.premium.yearly',
    })),
  }, {
    now: FIXTURE_NOW_MS,
    trustedRoots: [fixtureCertificates.root],
  });
  assert.equal(yearly.ok, true);
});

test('register-pro rejects disabled debug, expired, unknown product, and missing JWT', async () => {
  const { env } = makeEnv();
  const bodies = [
    { transactionJwt: makeJwt({ debugPro: true, productId: 'whatever' }) },
    { transactionJwt: makeJwt(makeValidPayload({ exp: Math.floor(Date.now() / 1000) - 60 })) },
    { transactionJwt: makeJwt(makeValidPayload({ productId: 'com.other.app' })) },
    null,
    {},
  ];
  for (const body of bodies) assert.equal((await registerPro(env, VALID_DEVICE_ID, body)).ok, false);
});

test('App Store verifier accepts valid ES256 monthly and yearly transactions through the injected test root', async () => {
  for (const productId of [
    'com.zhili.todo.premium.monthly',
    'com.zhili.todo.premium.yearly',
  ]) {
    const verified = await verifyAppStoreTransaction(
      await signFixtureJws(validTransaction({ productId })),
      fixtureVerificationOptions(),
    );
    assert.equal(verified.productId, productId);
    assert.equal(verified.expiry, new Date(Date.UTC(2030, 0, 1)).toISOString());
    assert.match(verified.transactionHash, /^[a-f0-9]{64}$/);
    assert.match(verified.originalTransactionHash, /^[a-f0-9]{64}$/);
    assert.equal('jws' in verified, false);
  }
});

test('production Apple roots are exact official DER snapshots and exclude the fixture root', async () => {
  assert.deepEqual(APPLE_ROOT_CERTIFICATES.map((root) => root.name), [
    'Apple Inc. Root',
    'Apple Root CA - G2',
    'Apple Root CA - G3',
  ]);
  const productionHashes = [];
  for (const root of APPLE_ROOT_CERTIFICATES) {
    assert.match(root.sourceUrl, /^https:\/\/(?:www\.)?apple\.com\//);
    const digest = Buffer.from(await crypto.subtle.digest(
      'SHA-256',
      Buffer.from(root.derBase64, 'base64'),
    )).toString('hex');
    assert.equal(digest, root.sha256);
    productionHashes.push(digest);
  }
  const fixtureHash = Buffer.from(await crypto.subtle.digest(
    'SHA-256',
    Buffer.from(fixtureCertificates.root, 'base64'),
  )).toString('hex');
  assert.equal(productionHashes.includes(fixtureHash), false);
});

test('App Store verifier rejects altered payloads and raw ES256 signatures', async () => {
  const jws = await signFixtureJws();
  const [originalHeader, , originalSignature] = jws.split('.');
  const alteredPayload = Buffer.from(JSON.stringify(validTransaction({
    productId: 'com.zhili.todo.premium.yearly',
  }))).toString('base64url');
  await expectJwsError(`${originalHeader}.${alteredPayload}.${originalSignature}`, 'invalid_signature');
  await expectJwsError(alterJwsSegment(jws, 2), 'invalid_signature');
  const [header, payload] = jws.split('.');
  await expectJwsError(`${header}.${payload}.${Buffer.alloc(63).toString('base64url')}`, 'invalid_signature');
  await expectJwsError(`${header}.${payload}.${Buffer.alloc(65).toString('base64url')}`, 'invalid_signature');
});

test('App Store verifier enforces compact JWS, header, x5c count, DER, and byte bounds', async () => {
  const malformed = [
    '',
    'one.two',
    'one.two.three.four',
    `*.${Buffer.from('{}').toString('base64url')}.AA`,
    `${Buffer.from('[]').toString('base64url')}.${Buffer.from('{}').toString('base64url')}.AA`,
    'a'.repeat(64 * 1024 + 1),
  ];
  for (const jws of malformed) await expectJwsError(jws, 'malformed_jws');

  await expectJwsError(await signFixtureJws(validTransaction(), { alg: 'RS256' }), 'unsupported_algorithm');
  for (const x5c of [
    [fixtureCertificates.leaf, fixtureCertificates.intermediate],
    [fixtureCertificates.leaf, fixtureCertificates.intermediate, fixtureCertificates.root, fixtureCertificates.root],
    [fixtureCertificates.leaf, 'not-base64', fixtureCertificates.root],
    [fixtureCertificates.leaf, Buffer.alloc(9000).toString('base64'), fixtureCertificates.root],
  ]) {
    await expectJwsError(await signFixtureJws(validTransaction(), { x5c }), 'invalid_certificate_chain');
  }
});

test('App Store verifier validates every ordered certificate signature, validity, and pinned root', async () => {
  const validJws = await signFixtureJws();
  await expectJwsError(validJws, 'invalid_certificate_chain', {
    trustedRoots: [fixtureCertificates.selfSignedLeaf],
  });
  await expectJwsError(validJws, 'invalid_certificate_chain', { trustedRoots: undefined });
  await expectJwsError(await signSelfSignedFixtureJws(), 'invalid_certificate_chain');
  await expectJwsError(await signFixtureJws(validTransaction(), {
    x5c: [
      fixtureCertificates.intermediate,
      fixtureCertificates.leaf,
      fixtureCertificates.root,
    ],
  }), 'invalid_certificate_chain');
  await expectJwsError(
    await signFixtureJws(validTransaction({
      expiresDate: Date.UTC(2040, 0, 1),
      signedDate: FIXTURE_EXPIRED_CERT_NOW_MS,
    })),
    'invalid_certificate_chain',
    { now: FIXTURE_EXPIRED_CERT_NOW_MS },
  );
});

test('App Store verifier rejects signed chains containing unprocessed critical EKU or unknown extensions', async () => {
  for (const leaf of [
    fixtureCertificates.criticalEkuLeaf,
    fixtureCertificates.unknownCriticalLeaf,
  ]) {
    await expectJwsError(await signFixtureJws(validTransaction(), {
      x5c: [leaf, fixtureCertificates.intermediate, fixtureCertificates.root],
    }), 'invalid_certificate_chain');
  }
});

test('App Store verifier rejects Apple critical purpose OIDs on the wrong certificate role', async () => {
  const cases = [
    {
      x5c: [
        fixtureCertificates.misplacedWwdrLeaf,
        fixtureCertificates.intermediate,
        fixtureCertificates.root,
      ],
    },
    {
      x5c: [
        fixtureCertificates.leaf,
        fixtureCertificates.misplacedAppStoreIntermediate,
        fixtureCertificates.root,
      ],
    },
    {
      x5c: [
        fixtureCertificates.leaf,
        fixtureCertificates.intermediate,
        fixtureCertificates.misplacedAppStoreRoot,
      ],
      trustedRoots: [fixtureCertificates.misplacedAppStoreRoot],
    },
  ];
  for (const { x5c, trustedRoots } of cases) {
    await expectJwsError(
      await signFixtureJws(validTransaction(), { x5c }),
      'invalid_certificate_chain',
      trustedRoots ? { trustedRoots } : {},
    );
  }
});

test('App Store verifier requires leaf Key Usage to be exactly digitalSignature', async () => {
  await expectJwsError(await signFixtureJws(validTransaction(), {
    x5c: [
      fixtureCertificates.extraKeyUsageLeaf,
      fixtureCertificates.intermediate,
      fixtureCertificates.root,
    ],
  }), 'invalid_certificate_chain');
});

test('App Store verifier rejects expired, revoked, cross-app, cross-environment, unknown-product, and invalid-identity transactions', async () => {
  const cases = [
    [validTransaction({ expiresDate: FIXTURE_NOW_MS }), 'transaction_expired'],
    [validTransaction({ revocationDate: FIXTURE_NOW_MS - 1000 }), 'transaction_revoked'],
    [validTransaction({ revocationDate: null }), 'transaction_revoked'],
    [validTransaction({ bundleId: 'com.attacker.app' }), 'invalid_transaction'],
    [validTransaction({ environment: 'Production' }), 'invalid_transaction'],
    [validTransaction({ productId: 'com.attacker.premium' }), 'invalid_transaction'],
    [validTransaction({ transactionId: '../private' }), 'invalid_transaction'],
    [validTransaction({ originalTransactionId: '' }), 'invalid_transaction'],
  ];
  for (const [payload, code] of cases) {
    await expectJwsError(await signFixtureJws(payload), code);
  }
});

test('register-pro stores only a hashed immutable device pointer and never shortens DO expiry', async () => {
  const { env, kv } = makeEnv();
  const dependencies = {
    now: FIXTURE_NOW_MS,
    trustedRoots: [fixtureCertificates.root],
  };
  const firstJws = await signFixtureJws(validTransaction({
    expiresDate: Date.UTC(2028, 0, 1),
    transactionId: '2000000000000001',
  }));
  const newerJws = await signFixtureJws(validTransaction({
    expiresDate: Date.UTC(2029, 0, 1),
    transactionId: '2000000000000002',
  }));
  const olderJws = await signFixtureJws(validTransaction({
    expiresDate: Date.UTC(2028, 6, 1),
    transactionId: '2000000000000003',
  }));

  assert.equal((await registerPro(env, VALID_DEVICE_ID, { transactionJwt: firstJws }, dependencies)).ok, true);
  assert.equal((await registerPro(env, VALID_DEVICE_ID, { transactionJwt: newerJws }, dependencies)).ok, true);
  const extendedExpiry = new Date(Date.UTC(2029, 0, 1)).toISOString();
  assert.equal((await quotaCheck(env, VALID_DEVICE_ID)).entitlementExpiry, extendedExpiry);

  assert.equal((await registerPro(env, VALID_DEVICE_ID, { transactionJwt: olderJws }, dependencies)).ok, true);
  assert.equal((await quotaCheck(env, VALID_DEVICE_ID)).entitlementExpiry, extendedExpiry);

  const beforeDuplicate = new Map(kv.map);
  assert.equal((await registerPro(env, VALID_DEVICE_ID, { transactionJwt: newerJws }, dependencies)).ok, true);
  assert.deepEqual(kv.map, beforeDuplicate);
  assert.equal(kv.map.has(`pro:${VALID_DEVICE_ID}`), false);

  const persisted = [...kv.map.entries()].map(([key, value]) => `${key}\n${value}`).join('\n');
  assert.doesNotMatch(persisted, new RegExp(firstJws.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.doesNotMatch(persisted, /200000000000000[0-9]/);
  assert.match(persisted, /appstore-device-subscription:[A-Za-z0-9_-]+:[a-f0-9]{64}/);
  assert.doesNotMatch(persisted, /appstore-(?:entitlement|original|tx):/);
  const durablePersisted = JSON.stringify(
    [...env.ENTITLEMENTS.instances.values()].map(({ storage }) => [...storage.map]),
  );
  assert.doesNotMatch(durablePersisted, new RegExp(VALID_DEVICE_ID));
  assert.doesNotMatch(durablePersisted, /200000000000000[0-9]/);
  assert.doesNotMatch(durablePersisted, new RegExp(firstJws.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
});

test('Durable Object keeps maximum expiry under concurrent shorter registration', async () => {
  const longExpiry = new Date(Date.UTC(2029, 0, 1)).toISOString();
  const shortExpiry = new Date(Date.UTC(2028, 0, 1)).toISOString();
  const { env, kv } = makeEnv();
  const dependencies = {
    now: FIXTURE_NOW_MS,
    trustedRoots: [fixtureCertificates.root],
  };
  const longJws = await signFixtureJws(validTransaction({
    expiresDate: Date.parse(longExpiry),
    transactionId: '2000000000000011',
  }));
  const shortJws = await signFixtureJws(validTransaction({
    expiresDate: Date.parse(shortExpiry),
    transactionId: '2000000000000012',
  }));

  const [longResult, shortResult] = await Promise.all([registerPro(
    env,
    VALID_DEVICE_ID,
    { transactionJwt: longJws },
    dependencies,
  ), registerPro(
    env,
    VALID_DEVICE_ID,
    { transactionJwt: shortJws },
    dependencies,
  )]);
  assert.equal(longResult.ok, true);
  assert.equal(shortResult.ok, true);
  assert.equal(kv.map.has(`pro:${VALID_DEVICE_ID}`), false);

  const finalQuota = await quotaCheck(env, VALID_DEVICE_ID);
  assert.equal(finalQuota.entitlementExpiry, longExpiry);
  assert.equal(finalQuota.quota.isPro, true);
});

test('quota entitlement aggregation follows every KV list cursor page', async () => {
  const { env, kv } = makeEnv();
  kv.pageSize = 1;
  const dependencies = {
    now: FIXTURE_NOW_MS,
    trustedRoots: [fixtureCertificates.root],
  };
  const expiries = [
    Date.UTC(2028, 0, 1),
    Date.UTC(2030, 0, 1),
    Date.UTC(2029, 0, 1),
  ];
  for (let index = 0; index < expiries.length; index += 1) {
    const jws = await signFixtureJws(validTransaction({
      expiresDate: expiries[index],
      transactionId: `200000000000002${index}`,
      originalTransactionId: `200000000000012${index}`,
    }));
    assert.equal((await registerPro(
      env,
      VALID_DEVICE_ID,
      { transactionJwt: jws },
      dependencies,
    )).ok, true);
  }
  kv.listCalls = 0;

  const result = await quotaCheck(env, VALID_DEVICE_ID);
  assert.equal(result.entitlementExpiry, new Date(Math.max(...expiries)).toISOString());
  assert.equal(result.quota.isPro, true);
  assert.equal(kv.listCalls, expiries.length, 'follows each pointer cursor page');
});

test('the same original transaction restores immutable entitlements to a second anonymous device', async () => {
  const secondDeviceId = 'anon-device_0987654321';
  const { env, kv } = makeEnv();
  const dependencies = {
    now: FIXTURE_NOW_MS,
    trustedRoots: [fixtureCertificates.root],
  };
  const expiry = new Date(Date.UTC(2030, 0, 1)).toISOString();
  const jws = await signFixtureJws();

  for (const deviceId of [VALID_DEVICE_ID, secondDeviceId]) {
    const result = await registerPro(env, deviceId, { transactionJwt: jws }, dependencies);
    assert.deepEqual(result, { ok: true, expiry });
    const quota = await quotaCheck(env, deviceId);
    assert.equal(quota.entitlementExpiry, expiry);
    assert.equal(quota.quota.isPro, true);
  }

  const pointers = [...kv.map.entries()].filter(([key]) => (
    key.startsWith('appstore-device-subscription:')
  ));
  assert.equal(pointers.length, 2);
  for (const deviceId of [VALID_DEVICE_ID, secondDeviceId]) {
    const pointer = pointers.find(([key]) => key.includes(`:${deviceId}:`));
    assert.ok(pointer, `missing device subscription pointer for ${deviceId}`);
    assert.match(pointer[0], new RegExp(`^appstore-device-subscription:${deviceId}:[a-f0-9]{64}$`));
  }
});

test('register-pro fails closed on missing App Store configuration and route errors stay client-safe', async () => {
  const jws = await signFixtureJws();
  const { env, kv } = makeEnv();
  delete env.APP_STORE_BUNDLE_ID;
  const result = await registerPro(env, VALID_DEVICE_ID, { transactionJwt: jws }, {
    now: FIXTURE_NOW_MS,
    trustedRoots: [fixtureCertificates.root],
  });
  assert.deepEqual(result, { ok: false, error: 'service_not_configured' });
  assert.equal(kv.putCalls, 0);

  const response = await worker.fetch(routeReq('/proxy/register-pro', {
    method: 'POST',
    body: { transactionJwt: jws },
  }), env);
  assert.equal(response.status, 503);
  const responseText = await response.text();
  assert.deepEqual(JSON.parse(responseText), { error: { code: 'service_not_configured' } });
  assert.doesNotMatch(responseText, /certificate|transaction|x5c|ES256/i);
});

test('wrangler config declares auto-provisioned QUOTA without an id or placeholder', async () => {
  const config = await readFile(new URL('./wrangler.toml', import.meta.url), 'utf8');
  assert.match(config, /\[\[kv_namespaces\]\]\s+binding\s*=\s*"QUOTA"/m);
  assert.match(config, /\[\[durable_objects\.bindings\]\][\s\S]*name\s*=\s*"ENTITLEMENTS"[\s\S]*class_name\s*=\s*"EntitlementCoordinator"/m);
  assert.match(config, /\[\[migrations\]\][\s\S]*new_sqlite_classes\s*=\s*\["EntitlementCoordinator"\]/m);
  assert.match(config, /\[\[durable_objects\.bindings\]\][\s\S]*name\s*=\s*"DEVICE_PRIVACY"[\s\S]*class_name\s*=\s*"DevicePrivacyCoordinator"/m);
  assert.match(config, /\[\[migrations\]\][\s\S]*tag\s*=\s*"v2"[\s\S]*new_sqlite_classes\s*=\s*\["DevicePrivacyCoordinator"\]/m);
  assert.doesNotMatch(config, /^\s*id\s*=/m);
  assert.doesNotMatch(config, /PASTE_|PLACEHOLDER|namespace ID.*Dashboard/i);
});

test('project pins Wrangler v4 with a lockfile and documents supported Node LTS setup', async () => {
  const packageJson = JSON.parse(await readFile(new URL('./package.json', import.meta.url), 'utf8'));
  const lockText = await readFile(new URL('./package-lock.json', import.meta.url), 'utf8').catch(() => '{}');
  const packageLock = JSON.parse(lockText);
  const readme = await readFile(new URL('./README.md', import.meta.url), 'utf8');
  const version = packageJson.devDependencies?.wrangler;

  assert.match(version || '', /^4\.\d+\.\d+$/);
  assert.equal(packageLock.packages?.['']?.devDependencies?.wrangler, version);
  assert.match(packageLock.packages?.['node_modules/wrangler']?.version || '', /^4\.\d+\.\d+$/);
  assert.match(readme, /Cloudflare.*Node.*LTS/i);
  assert.match(readme, /automatic provisioning|自动.*创建/i);
  assert.match(readme, /回写.*(?:ID|id)/i);
  assert.match(readme, /npx wrangler/);
  assert.doesNotMatch(readme, /Node\s*[≥>]\s*18|Dashboard.*Bindings/i);
});

test('production preparation artifacts contain only blank configuration names and owner-gated commands', async () => {
  const example = await readFile(new URL('./.dev.vars.example', import.meta.url), 'utf8');
  const runbook = await readFile(new URL('./Runbook/production-deployment.md', import.meta.url), 'utf8');
  const gitignore = await readFile(new URL('../../.gitignore', import.meta.url), 'utf8');
  const requiredNames = [
    'DEEPSEEK_API_KEY',
    'APP_STORE_BUNDLE_ID',
    'APP_STORE_ENVIRONMENT',
    'APP_STORE_APPLE_ID',
    'ALLOWED_ORIGINS',
    'ERASURE_ADMIN_TOKEN',
  ];
  const assignments = example.split(/\r?\n/).filter((line) => line && !line.startsWith('#'));
  assert.deepEqual(assignments, requiredNames.map((name) => `${name}=`));
  assert.doesNotMatch(example, /sk-|workers\.dev|https?:\/\//i);
  assert.match(gitignore, /^workers\/quota-proxy\/\.dev\.vars$/m);
  assert.doesNotMatch(gitignore, /^workers\/quota-proxy\/\.dev\.vars\*/m);

  for (const phrase of [
    'owner approval',
    'npx wrangler deploy --dry-run',
    'npx wrangler secret put DEEPSEEK_API_KEY',
    'APP_STORE_APPLE_ID',
    'Send Test Notification',
    'ManagedAIBaseURL',
    'device_erased',
    'DEVICE_PRIVACY',
    'ERASURE_ADMIN_TOKEN',
    'earlier than the privacy migration',
    'rollback',
  ]) assert.match(runbook, new RegExp(phrase, 'i'));
  assert.match(runbook, /https:\/\/<actual-worker-domain>\/proxy\/app-store-notifications/);
  assert.doesNotMatch(runbook, /https:\/\/[A-Za-z0-9.-]+\.(?:workers\.dev|example\.com)\/proxy\/app-store-notifications/);
  assert.doesNotMatch(runbook, /sk-[A-Za-z0-9_-]{8,}/);
});

test('operator erasure helper keeps token and Support ID off argv/output while returning safe status', async () => {
  const { runErasure } = await import('./scripts/erase-device.mjs');
  let captured;
  const valid = await runErasure({
    baseURL: 'https://worker.invalid',
    input: `${ERASURE_ADMIN_TOKEN}\n${ERASURE_SUPPORT_ID}\n`,
    fetchImpl: async (url, init) => {
      captured = { url, init };
      return new Response(JSON.stringify({ ok: true, status: 'erased' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    },
  });
  assert.deepEqual(valid, { exitCode: 0, stdout: 'erased\n', stderr: '' });
  assert.equal(captured.url, 'https://worker.invalid/internal/erase-device');
  assert.equal(captured.init.headers.Authorization, `Bearer ${ERASURE_ADMIN_TOKEN}`);
  assert.deepEqual(JSON.parse(captured.init.body), { supportId: ERASURE_SUPPORT_ID });
  assert.doesNotMatch(`${valid.stdout}${valid.stderr}`, new RegExp(ERASURE_DEVICE_ID, 'i'));
  assert.doesNotMatch(`${valid.stdout}${valid.stderr}`, new RegExp(ERASURE_ADMIN_TOKEN));

  let lowerBody;
  const lower = await runErasure({
    baseURL: 'https://worker.invalid',
    input: `${ERASURE_ADMIN_TOKEN}\n${ERASURE_SUPPORT_ID.toLowerCase()}\n`,
    fetchImpl: async (_url, init) => {
      lowerBody = JSON.parse(init.body);
      return new Response(null, { status: 202 });
    },
  });
  assert.deepEqual(lower, { exitCode: 2, stdout: 'retry\n', stderr: '' });
  assert.deepEqual(lowerBody, { supportId: ERASURE_SUPPORT_ID });

  for (const supportId of [
    'TD-not-a-uuid',
    `TD-${ERASURE_DEVICE_ID.slice(0, 9).toLowerCase()}${ERASURE_DEVICE_ID.slice(9)}`,
  ]) {
    const invalid = await runErasure({
      baseURL: 'https://worker.invalid',
      input: `${ERASURE_ADMIN_TOKEN}\n${supportId}\n`,
      fetchImpl: async () => { throw new Error('must not fetch'); },
    });
    assert.deepEqual(invalid, { exitCode: 1, stdout: '', stderr: 'invalid_input\n' });
  }
});

test('verified renewal extends every mapped device through immutable notification records', async () => {
  const secondDeviceId = 'anon-device_0987654321';
  const { env, kv } = makeEnv();
  const dependencies = notificationDependencies();
  const originalTransactionId = '2000000000000800';
  const registered = await signFixtureJws(validTransaction({
    transactionId: '2000000000000801',
    originalTransactionId,
    expiresDate: Date.UTC(2028, 0, 1),
  }));
  for (const deviceId of [VALID_DEVICE_ID, secondDeviceId]) {
    assert.equal((await registerPro(env, deviceId, { transactionJwt: registered }, dependencies)).ok, true);
  }

  const renewalExpiry = Date.UTC(2031, 0, 1);
  const payload = await signedNotification({
    transaction: validTransaction({
      transactionId: '2000000000000802',
      originalTransactionId,
      expiresDate: renewalExpiry,
    }),
  });
  assert.deepEqual(
    await processAppStoreNotification(env, payload, dependencies),
    { ok: true, status: 'processed' },
  );
  for (const deviceId of [VALID_DEVICE_ID, secondDeviceId]) {
    assert.equal((await quotaCheck(env, deviceId)).entitlementExpiry, new Date(renewalExpiry).toISOString());
  }

  const persisted = [...kv.map.entries()].map(([key, value]) => `${key}\n${value}`).join('\n');
  assert.doesNotMatch(persisted, /20000000000008/);
  assert.doesNotMatch(persisted, new RegExp(payload.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.doesNotMatch(persisted, /appstore-notification:/);
  assert.match(persisted, /appstore-device-subscription:[A-Za-z0-9_-]+:[a-f0-9]{64}/);
});

test('SUBSCRIBED adds entitlement while duplicate delivery is idempotent', async () => {
  const { env, kv } = makeEnv();
  const dependencies = notificationDependencies();
  const registered = await signFixtureJws(validTransaction({
    transactionId: '2000000000000811',
    originalTransactionId: '2000000000000810',
    expiresDate: Date.UTC(2028, 0, 1),
  }));
  await registerPro(env, VALID_DEVICE_ID, { transactionJwt: registered }, dependencies);
  const payload = await signedNotification({
    notificationType: 'SUBSCRIBED',
    transaction: validTransaction({
      transactionId: '2000000000000812',
      originalTransactionId: '2000000000000810',
      expiresDate: Date.UTC(2032, 0, 1),
    }),
    outerOverrides: { subtype: 'INITIAL_BUY' },
  });

  assert.equal((await processAppStoreNotification(env, payload, dependencies)).status, 'processed');
  const afterFirst = new Map(kv.map);
  assert.deepEqual(
    await processAppStoreNotification(env, payload, dependencies),
    { ok: true, status: 'duplicate' },
  );
  assert.deepEqual(kv.map, afterFirst);
});

for (const notificationType of ['EXPIRED', 'REFUND', 'REVOKE']) {
  test(`${notificationType} terminates every mapped device without deleting mappings or another chain`, async () => {
    const secondDeviceId = 'anon-device_0987654321';
    const { env, kv } = makeEnv();
    kv.pageSize = 1;
    const dependencies = notificationDependencies();
    const targetOriginal = '2000000000000820';
    const unrelatedOriginal = '2000000000000830';
    for (const deviceId of [VALID_DEVICE_ID, secondDeviceId]) {
      await registerPro(env, deviceId, {
        transactionJwt: await signFixtureJws(validTransaction({
          transactionId: deviceId === VALID_DEVICE_ID ? '2000000000000821' : '2000000000000822',
          originalTransactionId: targetOriginal,
        })),
      }, dependencies);
    }
    await registerPro(env, VALID_DEVICE_ID, {
      transactionJwt: await signFixtureJws(validTransaction({
        transactionId: '2000000000000831',
        originalTransactionId: unrelatedOriginal,
        expiresDate: Date.UTC(2033, 0, 1),
      })),
    }, dependencies);

    const terminal = await signedNotification({
      notificationType,
      transaction: validTransaction({
        transactionId: '2000000000000823',
        originalTransactionId: targetOriginal,
        expiresDate: FIXTURE_NOW_MS - 1,
        ...(notificationType === 'REFUND' || notificationType === 'REVOKE'
          ? { revocationDate: FIXTURE_NOW_MS - 1 }
          : {}),
      }),
      outerOverrides: notificationType === 'EXPIRED' ? { subtype: 'VOLUNTARY' } : {},
    });
    assert.equal((await processAppStoreNotification(env, terminal, dependencies)).status, 'processed');

    assert.equal((await quotaCheck(env, secondDeviceId)).quota.isPro, false);
    assert.equal((await quotaCheck(env, VALID_DEVICE_ID)).entitlementExpiry, new Date(Date.UTC(2033, 0, 1)).toISOString());
    assert.equal([...kv.map.keys()].some((key) => key.includes(':anon-device_0987654321:')), true);
  });
}

test('notification verification rejects altered outer/nested JWS and mismatched app identity', async () => {
  const { env, kv } = makeEnv();
  const dependencies = notificationDependencies();
  const valid = await signedNotification();
  const alteredNested = await signedNotification({ nestedJws: alterJwsSegment(await signFixtureJws(), 1) });
  const cases = [
    alterJwsSegment(valid, 1),
    alteredNested,
    await signedNotification({ bundleId: 'com.attacker.app' }),
    await signedNotification({ environment: 'Production' }),
  ];
  for (const payload of cases) {
    await assert.rejects(
      processAppStoreNotification(env, payload, dependencies),
      (error) => error instanceof AppStoreNotificationError && error.code === 'invalid_notification',
    );
  }
  assert.equal(kv.putCalls, 0);
});

test('notification type must agree with active, expired, or revoked transaction state', async () => {
  const { env, kv } = makeEnv();
  const cases = [
    await signedNotification({
      notificationType: 'DID_RENEW',
      transaction: validTransaction({ expiresDate: FIXTURE_NOW_MS - 1 }),
    }),
    await signedNotification({
      notificationType: 'EXPIRED',
      transaction: validTransaction({ expiresDate: Date.UTC(2030, 0, 1) }),
      outerOverrides: { subtype: 'VOLUNTARY' },
    }),
    await signedNotification({
      notificationType: 'REFUND',
      transaction: validTransaction(),
    }),
  ];
  for (const payload of cases) {
    await assert.rejects(
      processAppStoreNotification(env, payload, notificationDependencies()),
      (error) => error instanceof AppStoreNotificationError && error.code === 'invalid_notification',
    );
  }
  assert.equal(kv.putCalls, 0);
});

test('Production requires exact numeric APP_STORE_APPLE_ID while Sandbox does not invent one', async () => {
  const { env } = makeEnv();
  env.APP_STORE_ENVIRONMENT = 'Production';
  env.APP_STORE_APPLE_ID = '1234567890';
  const productionTransaction = validTransaction({ environment: 'Production' });
  for (const appAppleId of [undefined, 1234567891, '1234567890']) {
    const payload = await signedNotification({
      environment: 'Production',
      appAppleId,
      transaction: productionTransaction,
    });
    await assert.rejects(
      processAppStoreNotification(env, payload, notificationDependencies()),
      (error) => error instanceof AppStoreNotificationError,
    );
  }

  const validProduction = await signedNotification({
    environment: 'Production',
    appAppleId: 1234567890,
    transaction: productionTransaction,
  });
  assert.equal((await processAppStoreNotification(env, validProduction, notificationDependencies())).status, 'unmapped');

  const sandbox = makeEnv();
  assert.equal((await processAppStoreNotification(
    sandbox.env,
    await signedNotification(),
    notificationDependencies(),
  )).status, 'unmapped');
});

test('unknown verified transaction mapping is safe 2xx and route/body errors are bounded', async () => {
  const { env, kv } = makeEnv();
  const payload = await signedNotification();
  assert.deepEqual(
    await processAppStoreNotification(env, payload, notificationDependencies()),
    { ok: true, status: 'unmapped' },
  );
  assert.equal([...kv.map.keys()].filter((key) => key.startsWith('appstore-entitlement:')).length, 0);

  const routeResponse = await appStoreNotifications(env, routeReq('/proxy/app-store-notifications', {
    method: 'POST',
    deviceId: null,
    body: { signedPayload: payload },
  }), notificationDependencies());
  assert.equal(routeResponse.status, 200);
  assert.deepEqual(await routeResponse.json(), { ok: true });

  const oversized = await worker.fetch(new Request(
    'https://todo-quota-proxy.test.workers.dev/proxy/app-store-notifications',
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: 'x'.repeat(MAX_BODY_BYTES + 1) },
  ), env);
  await expectError(oversized, 413, 'request_too_large');
});

test('terminal notification tombstone prevents a stale registration from reviving entitlement', async () => {
  const { env, kv } = makeEnv();
  kv.pageSize = 1;
  const dependencies = notificationDependencies();
  const originalTransactionId = '2000000000000890';
  const terminal = await signedNotification({
    notificationType: 'REVOKE',
    transaction: validTransaction({
      transactionId: '2000000000000892',
      originalTransactionId,
      expiresDate: Date.UTC(2030, 0, 1),
      revocationDate: FIXTURE_NOW_MS - 1,
    }),
  });
  assert.equal((await processAppStoreNotification(env, terminal, dependencies)).status, 'unmapped');

  const stale = await signFixtureJws(validTransaction({
    transactionId: '2000000000000891',
    originalTransactionId,
    expiresDate: Date.UTC(2030, 0, 1),
    signedDate: FIXTURE_NOW_MS - 10_000,
  }));
  assert.deepEqual(
    await registerPro(env, VALID_DEVICE_ID, { transactionJwt: stale }, dependencies),
    { ok: false, error: 'inactive_transaction' },
  );
  assert.equal((await quotaCheck(env, VALID_DEVICE_ID)).quota.isPro, false);
  assert.equal([...kv.map.keys()].some((key) => key.startsWith('appstore-entitlement:')), false);
});

test('terminal state suppresses an entitlement record that is still visible during KV convergence', async () => {
  const { env, kv } = makeEnv();
  const dependencies = notificationDependencies();
  const originalTransactionId = '2000000000000880';
  await registerPro(env, VALID_DEVICE_ID, {
    transactionJwt: await signFixtureJws(validTransaction({
      transactionId: '2000000000000881',
      originalTransactionId,
      signedDate: FIXTURE_NOW_MS - 10_000,
    })),
  }, dependencies);
  const staleRecords = [...kv.map.entries()].filter(([key]) => (
    key.startsWith('appstore-entitlement:') || key.startsWith('appstore-original:')
  ));
  await processAppStoreNotification(env, await signedNotification({
    notificationType: 'EXPIRED',
    transaction: validTransaction({
      transactionId: '2000000000000882',
      originalTransactionId,
      expiresDate: FIXTURE_NOW_MS - 1,
    }),
    outerOverrides: { subtype: 'VOLUNTARY' },
  }), dependencies);
  for (const [key, value] of staleRecords) kv.map.set(key, value);

  const quota = await quotaCheck(env, VALID_DEVICE_ID);
  assert.equal(quota.quota.isPro, false);
  assert.equal(quota.entitlementExpiry, null);
});

test('an older terminal notification arriving late cannot delete a newer renewal', async () => {
  const { env } = makeEnv();
  const dependencies = notificationDependencies();
  const originalTransactionId = '2000000000000870';
  await registerPro(env, VALID_DEVICE_ID, {
    transactionJwt: await signFixtureJws(validTransaction({
      transactionId: '2000000000000871',
      originalTransactionId,
      signedDate: FIXTURE_NOW_MS - 20_000,
    })),
  }, dependencies);
  const renewedExpiry = Date.UTC(2034, 0, 1);
  await processAppStoreNotification(env, await signedNotification({
    notificationUUID: '123e4567-e89b-42d3-a456-426614174010',
    transaction: validTransaction({
      transactionId: '2000000000000872',
      originalTransactionId,
      expiresDate: renewedExpiry,
    }),
  }), dependencies);
  const staleTerminal = await signedNotification({
    notificationType: 'EXPIRED',
    notificationUUID: '123e4567-e89b-42d3-a456-426614174011',
    transaction: validTransaction({
      transactionId: '2000000000000871',
      originalTransactionId,
      expiresDate: FIXTURE_NOW_MS - 10_000,
      signedDate: FIXTURE_NOW_MS - 10_000,
    }),
    outerOverrides: { signedDate: FIXTURE_NOW_MS - 10_000, subtype: 'VOLUNTARY' },
  });
  assert.equal((await processAppStoreNotification(env, staleTerminal, dependencies)).status, 'stale');
  assert.equal((await quotaCheck(env, VALID_DEVICE_ID)).entitlementExpiry, new Date(renewedExpiry).toISOString());
});

test('quota ignores legacy pro and old entitlement keys in the undeployed v2 contract', async () => {
  const { env, kv } = makeEnv();
  kv.map.set(`pro:${VALID_DEVICE_ID}`, new Date(Date.now() + 86400e3).toISOString());
  kv.map.set(`appstore-entitlement:${VALID_DEVICE_ID}:${'a'.repeat(64)}`, JSON.stringify({
    v: 2,
    expiry: new Date(Date.now() + 86400e3).toISOString(),
  }));
  const result = await quotaCheck(env, VALID_DEVICE_ID);
  assert.equal(result.quota.isPro, false);
  assert.equal(result.entitlementExpiry, null);
});

test('a delayed KV device pointer is fail-closed while Durable Object entitlement is already active', async () => {
  class DelayedPointerKV extends MemKV {
    constructor() {
      super();
      this.pointerReached = deferred();
      this.releasePointer = deferred();
    }
    async put(key, value) {
      if (key.startsWith('appstore-device-subscription:')) {
        this.pointerReached.resolve();
        await this.releasePointer.promise;
      }
      return super.put(key, value);
    }
  }
  const { env } = makeEnv();
  const kv = new DelayedPointerKV();
  env.QUOTA = kv;
  const registration = registerPro(env, VALID_DEVICE_ID, {
    transactionJwt: await signFixtureJws(),
  }, notificationDependencies());
  await kv.pointerReached.promise;
  assert.equal((await quotaCheck(env, VALID_DEVICE_ID)).quota.isPro, false);
  kv.releasePointer.resolve();
  assert.equal((await registration).ok, true);
  assert.equal((await quotaCheck(env, VALID_DEVICE_ID)).quota.isPro, true);
});

test('terminal before restore retains device mapping and a later renewal reactivates it', async () => {
  const { env, kv } = makeEnv();
  const dependencies = notificationDependencies();
  const originalTransactionId = '2000000000000860';
  await processAppStoreNotification(env, await signedNotification({
    notificationType: 'REVOKE',
    notificationUUID: '123e4567-e89b-42d3-a456-426614174020',
    transaction: validTransaction({
      transactionId: '2000000000000862',
      originalTransactionId,
      revocationDate: FIXTURE_NOW_MS - 1,
    }),
  }), dependencies);
  const staleRestore = await registerPro(env, VALID_DEVICE_ID, {
    transactionJwt: await signFixtureJws(validTransaction({
      transactionId: '2000000000000861',
      originalTransactionId,
      signedDate: FIXTURE_NOW_MS - 10_000,
    })),
  }, dependencies);
  assert.deepEqual(staleRestore, { ok: false, error: 'inactive_transaction' });
  assert.equal((await quotaCheck(env, VALID_DEVICE_ID)).quota.isPro, false);
  assert.equal([...kv.map.keys()].some((key) => key.startsWith(
    `appstore-device-subscription:${VALID_DEVICE_ID}:`,
  )), true);

  const renewalExpiry = Date.UTC(2035, 0, 1);
  await processAppStoreNotification(env, await signedNotification({
    notificationType: 'DID_RENEW',
    notificationUUID: '123e4567-e89b-42d3-a456-426614174021',
    transaction: validTransaction({
      transactionId: '2000000000000863',
      originalTransactionId,
      expiresDate: renewalExpiry,
      signedDate: FIXTURE_NOW_MS + 1,
    }),
    outerOverrides: { signedDate: FIXTURE_NOW_MS + 1 },
  }), dependencies);
  assert.equal((await quotaCheck(env, VALID_DEVICE_ID)).entitlementExpiry, new Date(renewalExpiry).toISOString());
});

test('verified TEST notification is a 200 no-op without nested transaction', async () => {
  const { env, kv } = makeEnv();
  const testPayload = await signFixtureJws({
    notificationType: 'TEST',
    notificationUUID: '123e4567-e89b-42d3-a456-426614174030',
    version: '2.0',
    signedDate: FIXTURE_NOW_MS,
    data: { bundleId: 'com.zhili.todo-native', environment: 'Sandbox' },
  });
  assert.deepEqual(
    await processAppStoreNotification(env, testPayload, notificationDependencies()),
    { ok: true, status: 'ignored' },
  );
  assert.equal(kv.putCalls, 0);
  await assert.rejects(
    processAppStoreNotification(env, alterJwsSegment(testPayload, 1), notificationDependencies()),
    (error) => error instanceof AppStoreNotificationError,
  );
});

test('official subtype combinations process while invalid and future combinations are verified then ignored', async () => {
  const { env, kv } = makeEnv();
  const dependencies = notificationDependencies();
  const originalTransactionId = '2000000000000850';
  await registerPro(env, VALID_DEVICE_ID, {
    transactionJwt: await signFixtureJws(validTransaction({
      transactionId: '2000000000000851', originalTransactionId,
    })),
  }, dependencies);
  const ignored = [
    ['DID_RENEW', 'INITIAL_BUY'],
    ['SUBSCRIBED', 'BILLING_RECOVERY'],
    ['REFUND', 'FUTURE_REASON'],
    ['FUTURE_TYPE', undefined],
  ];
  for (let index = 0; index < ignored.length; index += 1) {
    const [notificationType, subtype] = ignored[index];
    const result = await processAppStoreNotification(env, await signedNotification({
      notificationType,
      notificationUUID: `123e4567-e89b-42d3-a456-42661417404${index}`,
      transaction: validTransaction({
        transactionId: `200000000000085${index + 2}`,
        originalTransactionId,
        ...(notificationType === 'REFUND' ? { revocationDate: FIXTURE_NOW_MS - 1 } : {}),
      }),
      outerOverrides: subtype === undefined ? {} : { subtype },
    }), dependencies);
    assert.equal(result.status, 'ignored');
  }
  assert.equal((await quotaCheck(env, VALID_DEVICE_ID)).quota.isPro, true);
  assert.equal([...kv.map.keys()].some((key) => key.startsWith('appstore-notification:')), false);
});

test('Durable Object serializes concurrent out-of-order state and owns notification idempotency', async () => {
  const { env } = makeEnv();
  const originalHash = 'b'.repeat(64);
  const stub = env.ENTITLEMENTS.get(env.ENTITLEMENTS.idFromName(originalHash));
  const call = (path, body) => stub.fetch(new Request(`https://entitlement.internal${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })).then((response) => response.json());
  const [newer, older] = await Promise.all([
    call('/notification', {
      notificationHash: 'c'.repeat(64), signedDate: 200, active: true,
      expiry: '2036-01-01T00:00:00.000Z', transactionHash: 'd'.repeat(64),
    }),
    call('/notification', {
      notificationHash: 'e'.repeat(64), signedDate: 100, active: false,
      expiry: null, transactionHash: 'f'.repeat(64),
    }),
  ]);
  assert.equal(newer.status, 'unmapped');
  assert.equal(older.status, 'stale');
  assert.equal((await call('/notification', {
    notificationHash: 'c'.repeat(64), signedDate: 200, active: true,
    expiry: '2036-01-01T00:00:00.000Z', transactionHash: 'd'.repeat(64),
  })).status, 'duplicate');
  const status = await stub.fetch(new Request('https://entitlement.internal/status'));
  assert.deepEqual(await status.json(), { active: true, expiry: '2036-01-01T00:00:00.000Z' });
});
