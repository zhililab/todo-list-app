export const MANAGED_MODEL = 'deepseek-v4-flash';
export const MAX_BODY_BYTES = 64 * 1024;
export const MAX_MESSAGES = 32;
export const MAX_CONTENT_CHARS = 16_000;
export const MIN_DEVICE_ID_CHARS = 16;
export const MAX_DEVICE_ID_CHARS = 128;
export const MESSAGE_ROLES = new Set(['system', 'user', 'assistant']);

const DEVICE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;
const UUID_DEVICE_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const ROUTES = Object.freeze({
  '/proxy/chat/completions': Object.freeze(['POST']),
  '/proxy/quota': Object.freeze(['GET']),
  '/proxy/register-pro': Object.freeze(['POST']),
  '/proxy/app-store-notifications': Object.freeze(['POST']),
  '/internal/erase-device': Object.freeze(['POST']),
});

export class ContractError extends Error {
  constructor(status, code) {
    super(code);
    this.name = 'ContractError';
    this.status = status;
    this.code = code;
  }
}

export function canonicalDeviceId(value) {
  return UUID_DEVICE_ID_PATTERN.test(value) ? value.toUpperCase() : value;
}

export function parseDeviceId(request) {
  const value = request.headers.get('X-Device-Id');
  if (value === null || value === '') throw new ContractError(401, 'missing_device_id');
  if (
    value.length < MIN_DEVICE_ID_CHARS
    || value.length > MAX_DEVICE_ID_CHARS
    || !DEVICE_ID_PATTERN.test(value)
  ) {
    throw new ContractError(401, 'invalid_device_id');
  }
  return canonicalDeviceId(value);
}

async function readBoundedText(request) {
  const contentLength = request.headers.get('Content-Length');
  if (contentLength !== null && /^\d+$/.test(contentLength) && Number(contentLength) > MAX_BODY_BYTES) {
    throw new ContractError(413, 'request_too_large');
  }

  if (request.body === null) return '';

  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let byteLength = 0;
  let text = '';
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) return text + decoder.decode();

      byteLength += value.byteLength;
      if (byteLength > MAX_BODY_BYTES) {
        try {
          await reader.cancel('request_too_large');
        } catch {
          // The contract response remains stable even if the source rejects cancellation.
        }
        throw new ContractError(413, 'request_too_large');
      }
      text += decoder.decode(value, { stream: true });
    }
  } finally {
    reader.releaseLock();
  }
}

export async function parseJsonObject(request) {
  const text = await readBoundedText(request);
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    throw new ContractError(400, 'invalid_request_body');
  }
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    throw new ContractError(400, 'invalid_request_body');
  }
  return body;
}

export async function parseChatBody(request) {
  const body = await parseJsonObject(request);
  if (
    !Array.isArray(body.messages)
    || body.messages.length === 0
    || body.messages.length > MAX_MESSAGES
    || body.messages.some((message) => (
      message === null
      || typeof message !== 'object'
      || Array.isArray(message)
      || !MESSAGE_ROLES.has(message.role)
      || typeof message.content !== 'string'
      || message.content.length === 0
      || message.content.length > MAX_CONTENT_CHARS
    ))
  ) {
    throw new ContractError(400, 'invalid_messages');
  }
  return { ...body, model: MANAGED_MODEL };
}

function configuredOrigins(env) {
  return new Set(
    String(env?.ALLOWED_ORIGINS || '')
      .split(',')
      .map((value) => value.trim())
      .filter((value) => {
        if (!value || value === '*') return false;
        try {
          const url = new URL(value);
          return (url.protocol === 'https:' || url.protocol === 'http:') && url.origin === value;
        } catch {
          return false;
        }
      }),
  );
}

export function validateOrigin(request, env) {
  const origin = request.headers.get('Origin');
  if (origin === null) return null;
  if (!configuredOrigins(env).has(origin)) {
    throw new ContractError(403, 'origin_not_allowed');
  }
  return origin;
}

export function corsHeaders(origin, methods) {
  if (!origin) return {};
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': `${methods.join(', ')}, OPTIONS`,
    'Access-Control-Allow-Headers': 'Content-Type, X-Device-Id',
    Vary: 'Origin',
  };
}

export function hasQuotaBinding(env) {
  return Boolean(
    env?.QUOTA
    && typeof env.QUOTA.get === 'function'
    && typeof env.QUOTA.put === 'function'
    && typeof env.QUOTA.list === 'function'
    && typeof env.QUOTA.delete === 'function'
  );
}

export function hasProviderSecret(env) {
  return typeof env?.DEEPSEEK_API_KEY === 'string' && env.DEEPSEEK_API_KEY.trim().length > 0;
}
