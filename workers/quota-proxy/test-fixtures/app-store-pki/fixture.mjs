import { readFile } from 'node:fs/promises';

const fixtureUrl = new URL('./', import.meta.url);

async function read(name) {
  return readFile(new URL(name, fixtureUrl), 'utf8');
}

function pemBody(pem) {
  return pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
}

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');
}

async function importSigningKey(pem) {
  return crypto.subtle.importKey(
    'pkcs8',
    Buffer.from(pemBody(pem), 'base64'),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
}

const [
  rootPem,
  intermediatePem,
  leafPem,
  criticalEkuLeafPem,
  unknownCriticalLeafPem,
  misplacedWwdrLeafPem,
  extraKeyUsageLeafPem,
  misplacedAppStoreIntermediatePem,
  misplacedAppStoreRootPem,
  leafKeyPem,
  selfSignedLeafPem,
  selfSignedLeafKeyPem,
] =
  await Promise.all([
    read('root-cert.pem'),
    read('intermediate-cert.pem'),
    read('leaf-cert.pem'),
    read('leaf-critical-eku-cert.pem'),
    read('leaf-unknown-critical-cert.pem'),
    read('leaf-misplaced-wwdr-cert.pem'),
    read('leaf-extra-key-usage-cert.pem'),
    read('intermediate-misplaced-app-store-cert.pem'),
    read('root-misplaced-app-store-cert.pem'),
    read('leaf-key.pem'),
    read('self-signed-leaf-cert.pem'),
    read('self-signed-leaf-key.pem'),
  ]);

export const FIXTURE_NOW_MS = Date.UTC(2027, 0, 1, 0, 0, 0);
export const FIXTURE_EXPIRED_CERT_NOW_MS = Date.UTC(2037, 0, 1, 0, 0, 0);

export const fixtureCertificates = Object.freeze({
  root: pemBody(rootPem),
  intermediate: pemBody(intermediatePem),
  leaf: pemBody(leafPem),
  criticalEkuLeaf: pemBody(criticalEkuLeafPem),
  unknownCriticalLeaf: pemBody(unknownCriticalLeafPem),
  misplacedWwdrLeaf: pemBody(misplacedWwdrLeafPem),
  extraKeyUsageLeaf: pemBody(extraKeyUsageLeafPem),
  misplacedAppStoreIntermediate: pemBody(misplacedAppStoreIntermediatePem),
  misplacedAppStoreRoot: pemBody(misplacedAppStoreRootPem),
  selfSignedLeaf: pemBody(selfSignedLeafPem),
});

const leafSigningKey = await importSigningKey(leafKeyPem);
const selfSignedLeafSigningKey = await importSigningKey(selfSignedLeafKeyPem);

export function validTransaction(overrides = {}) {
  return {
    bundleId: 'com.zhili.todo-native',
    environment: 'Sandbox',
    productId: 'com.zhili.todo.premium.monthly.v2',
    expiresDate: Date.UTC(2030, 0, 1, 0, 0, 0),
    signedDate: FIXTURE_NOW_MS,
    transactionId: '2000000000000001',
    originalTransactionId: '2000000000000000',
    ...overrides,
  };
}

export async function signFixtureJws(payload = validTransaction(), options = {}) {
  const x5c = options.x5c || [
    fixtureCertificates.leaf,
    fixtureCertificates.intermediate,
    fixtureCertificates.root,
  ];
  const headerSegment = base64UrlJson({ alg: options.alg || 'ES256', x5c });
  const payloadSegment = base64UrlJson(payload);
  const signingInput = `${headerSegment}.${payloadSegment}`;
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    options.signingKey || leafSigningKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${Buffer.from(signature).toString('base64url')}`;
}

export async function signSelfSignedFixtureJws(payload = validTransaction()) {
  return signFixtureJws(payload, {
    x5c: [
      fixtureCertificates.selfSignedLeaf,
      fixtureCertificates.intermediate,
      fixtureCertificates.root,
    ],
    signingKey: selfSignedLeafSigningKey,
  });
}

export function alterJwsSegment(jws, index) {
  const parts = jws.split('.');
  const segment = parts[index];
  parts[index] = `${segment.slice(0, -1)}${segment.endsWith('A') ? 'B' : 'A'}`;
  return parts.join('.');
}
