import {
  AppStoreJwsError,
  verifyAppStoreSignedPayload,
  verifyAppStoreTransactionForNotification,
} from './app-store-jws.js';
import {
  callEntitlementCoordinator,
  hasEntitlementCoordinator,
} from './entitlement-coordinator.js';

const PRODUCT_IDS = [
  'com.zhili.todo.premium.monthly.v2',
  'com.zhili.todo.premium.yearly.v2',
];
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const APPLE_ID_PATTERN = /^[1-9][0-9]{0,18}$/;
const VALID_SUBTYPES = new Map([
  ['DID_RENEW', new Set([null, 'BILLING_RECOVERY'])],
  ['SUBSCRIBED', new Set(['INITIAL_BUY', 'RESUBSCRIBE'])],
  ['EXPIRED', new Set(['VOLUNTARY', 'BILLING_RETRY', 'PRICE_INCREASE', 'PRODUCT_NOT_FOR_SALE'])],
  ['REFUND', new Set([null])],
  ['REVOKE', new Set([null])],
]);

export class AppStoreNotificationError extends Error {
  constructor(code) {
    super(code);
    this.name = 'AppStoreNotificationError';
    this.code = code;
  }
}

function fail(code = 'invalid_notification') {
  throw new AppStoreNotificationError(code);
}

async function sha256Hex(value, cryptoProvider) {
  const digest = new Uint8Array(await cryptoProvider.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value),
  ));
  return [...digest].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function validateConfiguration(env) {
  if (
    typeof env?.APP_STORE_BUNDLE_ID !== 'string'
    || !env.APP_STORE_BUNDLE_ID
    || env.APP_STORE_BUNDLE_ID.trim() !== env.APP_STORE_BUNDLE_ID
    || !['Sandbox', 'Production'].includes(env.APP_STORE_ENVIRONMENT)
    || !hasEntitlementCoordinator(env)
  ) fail('service_not_configured');
  if (
    env.APP_STORE_ENVIRONMENT === 'Production'
    && (typeof env.APP_STORE_APPLE_ID !== 'string'
      || !APPLE_ID_PATTERN.test(env.APP_STORE_APPLE_ID))
  ) fail('service_not_configured');
}

function validateOuterIdentity(payload, env) {
  if (
    payload.version !== '2.0'
    || !UUID_PATTERN.test(payload.notificationUUID || '')
    || payload.data === null
    || typeof payload.data !== 'object'
    || Array.isArray(payload.data)
    || payload.data.bundleId !== env.APP_STORE_BUNDLE_ID
    || payload.data.environment !== env.APP_STORE_ENVIRONMENT
  ) fail();
  if (
    env.APP_STORE_ENVIRONMENT === 'Production'
    && (!Number.isSafeInteger(payload.data.appAppleId)
      || String(payload.data.appAppleId) !== env.APP_STORE_APPLE_ID)
  ) fail();
}

function isSupportedCombination(payload) {
  const subtypes = VALID_SUBTYPES.get(payload.notificationType);
  if (!subtypes) return false;
  const subtype = Object.hasOwn(payload, 'subtype') ? payload.subtype : null;
  return typeof subtype === 'string' || subtype === null
    ? subtypes.has(subtype)
    : false;
}

function validateTransactionState(type, transaction, now) {
  if (
    ((type === 'DID_RENEW' || type === 'SUBSCRIBED')
      && (transaction.revoked || Date.parse(transaction.expiry) <= now))
    || (type === 'EXPIRED' && Date.parse(transaction.expiry) > now)
    || ((type === 'REFUND' || type === 'REVOKE') && !transaction.revoked)
  ) fail();
}

export async function processAppStoreNotification(env, signedPayload, dependencies = {}) {
  validateConfiguration(env);
  const options = {
    bundleId: env.APP_STORE_BUNDLE_ID,
    environment: env.APP_STORE_ENVIRONMENT,
    productIds: PRODUCT_IDS,
    now: dependencies.now,
    trustedRoots: dependencies.trustedRoots,
    crypto: dependencies.crypto,
  };

  let outer;
  try {
    outer = await verifyAppStoreSignedPayload(signedPayload, options);
    validateOuterIdentity(outer.payload, env);
  } catch (error) {
    if (error instanceof AppStoreNotificationError && error.code === 'service_not_configured') {
      throw error;
    }
    if (error instanceof AppStoreJwsError && error.code === 'service_not_configured') {
      fail('service_not_configured');
    }
    fail();
  }

  if (outer.payload.notificationType === 'TEST') {
    return { ok: true, status: 'ignored' };
  }
  if (!isSupportedCombination(outer.payload)) {
    return { ok: true, status: 'ignored' };
  }
  if (typeof outer.payload.data.signedTransactionInfo !== 'string') fail();

  let transaction;
  try {
    transaction = await verifyAppStoreTransactionForNotification(
      outer.payload.data.signedTransactionInfo,
      options,
    );
  } catch {
    fail();
  }
  validateTransactionState(
    outer.payload.notificationType,
    transaction,
    Number(dependencies.now ?? Date.now()),
  );

  const notificationHash = await sha256Hex(
    `app-store-notification:v2\0${outer.payload.notificationUUID}`,
    outer.cryptoProvider,
  );
  const active = outer.payload.notificationType === 'DID_RENEW'
    || outer.payload.notificationType === 'SUBSCRIBED';
  const coordinated = await callEntitlementCoordinator(
    env,
    transaction.originalTransactionHash,
    '/notification',
    {
      notificationHash,
      transactionHash: transaction.transactionHash,
      signedDate: outer.signedDate,
      active,
      expiry: active ? transaction.expiry : null,
    },
  );
  return { ok: true, status: coordinated.status };
}
