import 'reflect-metadata';
import {
  BasicConstraintsExtension,
  KeyUsageFlags,
  KeyUsagesExtension,
  X509Certificate,
} from '@peculiar/x509';
import { APPLE_ROOT_CERTIFICATES } from './apple-root-certificates.js';

const MAX_JWS_BYTES = 64 * 1024;
const MAX_HEADER_BYTES = 32 * 1024;
const MAX_PAYLOAD_BYTES = 16 * 1024;
const MAX_CERTIFICATE_BYTES = 8 * 1024;
const ES256_SIGNATURE_BYTES = 64;
const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000;

const APP_STORE_SIGNING_OID = '1.2.840.113635.100.6.11.1';
const APPLE_WWDR_OID = '1.2.840.113635.100.6.2.1';
const COMMON_CRITICAL_EXTENSION_OIDS = [
  '2.5.29.15', // Key usage
  '2.5.29.19', // Basic constraints
];
const LEAF_CRITICAL_EXTENSION_OIDS = new Set([
  ...COMMON_CRITICAL_EXTENSION_OIDS,
  APP_STORE_SIGNING_OID,
]);
const INTERMEDIATE_CRITICAL_EXTENSION_OIDS = new Set([
  ...COMMON_CRITICAL_EXTENSION_OIDS,
  APPLE_WWDR_OID,
]);
const ROOT_CRITICAL_EXTENSION_OIDS = new Set(COMMON_CRITICAL_EXTENSION_OIDS);

const BASE64URL_PATTERN = /^[A-Za-z0-9_-]+$/;
const BASE64_PATTERN = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const TRANSACTION_ID_PATTERN = /^[1-9][0-9]{0,63}$/;

export class AppStoreJwsError extends Error {
  constructor(code) {
    super(code);
    this.name = 'AppStoreJwsError';
    this.code = code;
  }
}

function fail(code) {
  throw new AppStoreJwsError(code);
}

function byteLength(value) {
  return new TextEncoder().encode(value).byteLength;
}

function decodeBase64Url(value, maximumBytes, code = 'malformed_jws') {
  if (
    typeof value !== 'string'
    || !value
    || !BASE64URL_PATTERN.test(value)
    || value.length % 4 === 1
    || value.length > Math.ceil(maximumBytes * 4 / 3) + 3
  ) fail(code);

  try {
    const padded = value.replace(/-/g, '+').replace(/_/g, '/')
      .padEnd(value.length + ((4 - value.length % 4) % 4), '=');
    const bytes = Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
    if (bytes.byteLength > maximumBytes) fail(code);
    const canonical = btoa(String.fromCharCode(...bytes))
      .replace(/=/g, '')
      .replace(/\+/g, '-')
      .replace(/\//g, '_');
    if (canonical !== value) fail(code);
    return bytes;
  } catch (error) {
    if (error instanceof AppStoreJwsError) throw error;
    fail(code);
  }
}

function decodeCertificate(value) {
  if (
    typeof value !== 'string'
    || !value
    || !BASE64_PATTERN.test(value)
    || value.length > Math.ceil(MAX_CERTIFICATE_BYTES * 4 / 3) + 4
  ) fail('invalid_certificate_chain');

  try {
    const bytes = Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
    if (!bytes.byteLength || bytes.byteLength > MAX_CERTIFICATE_BYTES) {
      fail('invalid_certificate_chain');
    }
    return bytes;
  } catch (error) {
    if (error instanceof AppStoreJwsError) throw error;
    fail('invalid_certificate_chain');
  }
}

function parseJsonObject(bytes, code) {
  let value;
  try {
    const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    value = JSON.parse(text);
  } catch {
    fail(code);
  }
  if (value === null || typeof value !== 'object' || Array.isArray(value)) fail(code);
  return value;
}

function assertKnownCriticalExtensions(certificate, allowedOids) {
  if (certificate.extensions.some((extension) => (
    extension.critical && !allowedOids.has(extension.type)
  ))) fail('invalid_certificate_chain');
}

function assertEndEntityPurpose(certificate) {
  const basicConstraints = certificate.getExtension(BasicConstraintsExtension);
  const keyUsage = certificate.getExtension(KeyUsagesExtension);
  if (
    !certificate.getExtension(APP_STORE_SIGNING_OID)
    || !basicConstraints
    || !basicConstraints.critical
    || basicConstraints.ca
    || !keyUsage
    || !keyUsage.critical
    || keyUsage.usages !== KeyUsageFlags.digitalSignature
  ) fail('invalid_certificate_chain');
}

function assertCertificateAuthorityPurpose(certificate, requireWwdrOid) {
  const basicConstraints = certificate.getExtension(BasicConstraintsExtension);
  const keyUsage = certificate.getExtension(KeyUsagesExtension);
  if (
    !basicConstraints?.ca
    || !basicConstraints.critical
    || !keyUsage
    || !keyUsage.critical
    || (keyUsage.usages & KeyUsageFlags.keyCertSign) === 0
    || (requireWwdrOid && !certificate.getExtension(APPLE_WWDR_OID))
  ) fail('invalid_certificate_chain');
}

async function sha256Hex(bytes, cryptoProvider) {
  const digest = new Uint8Array(await cryptoProvider.subtle.digest('SHA-256', bytes));
  return [...digest].map((value) => value.toString(16).padStart(2, '0')).join('');
}

function equalHex(left, right) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

async function verifyCertificateChain(x5c, verificationDate, trustedRoots, cryptoProvider) {
  let certificates;
  try {
    certificates = x5c.map((encoded) => new X509Certificate(decodeCertificate(encoded)));
  } catch (error) {
    if (error instanceof AppStoreJwsError) throw error;
    fail('invalid_certificate_chain');
  }
  const [leaf, intermediate, root] = certificates;

  assertKnownCriticalExtensions(leaf, LEAF_CRITICAL_EXTENSION_OIDS);
  assertKnownCriticalExtensions(intermediate, INTERMEDIATE_CRITICAL_EXTENSION_OIDS);
  assertKnownCriticalExtensions(root, ROOT_CRITICAL_EXTENSION_OIDS);
  assertEndEntityPurpose(leaf);
  assertCertificateAuthorityPurpose(intermediate, true);
  assertCertificateAuthorityPurpose(root, false);

  if (
    leaf.issuer !== intermediate.subject
    || intermediate.issuer !== root.subject
    || root.issuer !== root.subject
  ) fail('invalid_certificate_chain');

  const rootHash = await sha256Hex(decodeCertificate(x5c[2]), cryptoProvider);
  const trustedHashes = await Promise.all(trustedRoots.map(async (encoded) => (
    sha256Hex(decodeCertificate(encoded), cryptoProvider)
  )));
  if (!trustedHashes.some((hash) => equalHex(hash, rootHash))) fail('invalid_certificate_chain');

  try {
    const date = new Date(verificationDate);
    const [leafValid, intermediateValid, rootValid] = await Promise.all([
      leaf.verify({ publicKey: intermediate.publicKey, date }, cryptoProvider),
      intermediate.verify({ publicKey: root.publicKey, date }, cryptoProvider),
      root.verify({ publicKey: root.publicKey, date }, cryptoProvider),
    ]);
    if (!leafValid || !intermediateValid || !rootValid) fail('invalid_certificate_chain');
  } catch (error) {
    if (error instanceof AppStoreJwsError) throw error;
    fail('invalid_certificate_chain');
  }

  if (leaf.publicKey.algorithm?.name !== 'ECDSA' || leaf.publicKey.algorithm?.namedCurve !== 'P-256') {
    fail('invalid_certificate_chain');
  }
  return leaf;
}

function normalizeTrustOptions(options) {
  const cryptoProvider = options?.crypto || globalThis.crypto;
  if (
    !cryptoProvider?.subtle
  ) fail('service_not_configured');

  const now = options.now instanceof Date ? options.now.getTime() : Number(options.now ?? Date.now());
  if (!Number.isFinite(now)) fail('service_not_configured');
  const trustedRoots = (options.trustedRoots ?? APPLE_ROOT_CERTIFICATES.map((root) => root.derBase64));
  if (!Array.isArray(trustedRoots) || trustedRoots.length === 0) fail('invalid_certificate_chain');
  return { cryptoProvider, now, trustedRoots };
}

function requireSafeTimestamp(value, code) {
  if (!Number.isSafeInteger(value) || value <= 0) fail(code);
  return value;
}

async function hashTransactionIdentity(payload, cryptoProvider) {
  const common = `${payload.bundleId}\0${payload.environment}\0${payload.originalTransactionId}`;
  const transactionHash = await sha256Hex(
    new TextEncoder().encode(`app-store-transaction:v1\0${common}\0${payload.transactionId}\0${payload.productId}`),
    cryptoProvider,
  );
  const originalTransactionHash = await sha256Hex(
    new TextEncoder().encode(`app-store-original:v1\0${common}`),
    cryptoProvider,
  );
  return { transactionHash, originalTransactionHash };
}

export async function verifyAppStoreSignedPayload(jws, options) {
  const { cryptoProvider, now, trustedRoots } = normalizeTrustOptions(options);
  if (typeof jws !== 'string' || !jws || byteLength(jws) > MAX_JWS_BYTES) fail('malformed_jws');

  const parts = jws.split('.');
  if (parts.length !== 3 || parts.some((part) => !part)) fail('malformed_jws');
  const [headerSegment, payloadSegment, signatureSegment] = parts;
  const header = parseJsonObject(
    decodeBase64Url(headerSegment, MAX_HEADER_BYTES),
    'malformed_jws',
  );
  if (header.alg !== 'ES256') fail('unsupported_algorithm');
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) fail('invalid_certificate_chain');

  const payloadBytes = decodeBase64Url(payloadSegment, MAX_PAYLOAD_BYTES);
  const payload = parseJsonObject(payloadBytes, 'invalid_transaction');
  const signedDate = requireSafeTimestamp(payload.signedDate, 'invalid_transaction');
  if (signedDate > now + MAX_CLOCK_SKEW_MS) fail('invalid_transaction');

  const leaf = await verifyCertificateChain(
    header.x5c,
    signedDate,
    trustedRoots,
    cryptoProvider,
  );
  const signature = decodeBase64Url(signatureSegment, ES256_SIGNATURE_BYTES, 'invalid_signature');
  if (signature.byteLength !== ES256_SIGNATURE_BYTES) fail('invalid_signature');

  let publicKey;
  let validSignature = false;
  try {
    publicKey = await leaf.publicKey.export(
      { name: 'ECDSA', namedCurve: 'P-256' },
      ['verify'],
      cryptoProvider,
    );
    validSignature = await cryptoProvider.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      publicKey,
      signature,
      new TextEncoder().encode(`${headerSegment}.${payloadSegment}`),
    );
  } catch {
    fail('invalid_signature');
  }
  if (!validSignature) fail('invalid_signature');

  return { payload, cryptoProvider, signedDate };
}

function validateTransactionOptions(options) {
  const productIds = options?.productIds;
  if (
    typeof options?.bundleId !== 'string'
    || !options.bundleId
    || !['Sandbox', 'Production'].includes(options?.environment)
    || !Array.isArray(productIds)
    || productIds.length === 0
    || productIds.some((value) => typeof value !== 'string' || !value)
  ) fail('service_not_configured');
  return productIds;
}

async function verifyTransaction(jws, options, requireActive) {
  const productIds = validateTransactionOptions(options);
  const { payload, cryptoProvider, signedDate } = await verifyAppStoreSignedPayload(jws, options);
  const now = options.now instanceof Date ? options.now.getTime() : Number(options.now ?? Date.now());

  const expiresDate = requireSafeTimestamp(payload.expiresDate, 'invalid_transaction');
  if (requireActive && Object.hasOwn(payload, 'revocationDate')) fail('transaction_revoked');
  if (Object.hasOwn(payload, 'revocationDate')) {
    requireSafeTimestamp(payload.revocationDate, 'invalid_transaction');
  }
  if (payload.bundleId !== options.bundleId || payload.environment !== options.environment) {
    fail('invalid_transaction');
  }
  if (!productIds.includes(payload.productId)) fail('invalid_transaction');
  if (
    typeof payload.transactionId !== 'string'
    || !TRANSACTION_ID_PATTERN.test(payload.transactionId)
    || typeof payload.originalTransactionId !== 'string'
    || !TRANSACTION_ID_PATTERN.test(payload.originalTransactionId)
  ) fail('invalid_transaction');
  if (requireActive && expiresDate <= now) fail('transaction_expired');

  const hashes = await hashTransactionIdentity(payload, cryptoProvider);
  return {
    expiry: new Date(expiresDate).toISOString(),
    productId: payload.productId,
    environment: payload.environment,
    signedDate,
    revoked: Object.hasOwn(payload, 'revocationDate'),
    ...hashes,
  };
}

export async function verifyAppStoreTransaction(jws, options) {
  return verifyTransaction(jws, options, true);
}

export async function verifyAppStoreTransactionForNotification(jws, options) {
  return verifyTransaction(jws, options, false);
}
