import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const SUPPORT_ID_PATTERN = /^TD-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN_PATTERN = /^[!-~]{32,256}$/;

export async function runErasure({ baseURL, input, fetchImpl = globalThis.fetch }) {
  let base;
  try {
    base = new URL(baseURL);
  } catch {
    return { exitCode: 1, stdout: '', stderr: 'invalid_input\n' };
  }
  const lines = String(input).split(/\r?\n/);
  const token = lines[0] || '';
  const supportId = lines[1] || '';
  const uuid = supportId.slice('TD-'.length);
  if (
    base.protocol !== 'https:'
    || base.username
    || base.password
    || (base.pathname !== '/' && base.pathname !== '')
    || base.search
    || base.hash
    || !TOKEN_PATTERN.test(token)
    || !SUPPORT_ID_PATTERN.test(supportId)
    || (uuid !== uuid.toUpperCase() && uuid !== uuid.toLowerCase())
  ) return { exitCode: 1, stdout: '', stderr: 'invalid_input\n' };
  const canonicalSupportId = `TD-${uuid.toUpperCase()}`;

  let response;
  try {
    response = await fetchImpl(`${base.origin}/internal/erase-device`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ supportId: canonicalSupportId }),
    });
  } catch {
    return { exitCode: 1, stdout: '', stderr: 'request_failed\n' };
  }
  if (response.status === 200) return { exitCode: 0, stdout: 'erased\n', stderr: '' };
  if (response.status === 202) return { exitCode: 2, stdout: 'retry\n', stderr: '' };
  return { exitCode: 1, stdout: '', stderr: `request_failed_${response.status}\n` };
}

async function main() {
  let input = '';
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) {
    input += chunk;
    if (input.length > 512) break;
  }
  const result = await runErasure({ baseURL: process.argv[2], input });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  process.exitCode = result.exitCode;
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : '';
if (invokedPath === import.meta.url) await main();
