import { writeFileSync, mkdirSync, readFileSync, readdirSync } from 'node:fs';
import { extname, resolve } from 'node:path';

const distDir = resolve(process.cwd(), 'dist');
const runtimeDir = resolve(distDir, 'server');
const appgenDir = resolve(distDir, '_appgen_meta');

mkdirSync(runtimeDir, { recursive: true });
mkdirSync(appgenDir, { recursive: true });

function collectDistFiles(dirPath, relBase = '') {
  const collected = [];
  for (const entry of readdirSync(dirPath, { withFileTypes: true })) {
    if (entry.name === 'server' || entry.name === '_appgen_meta') {
      continue;
    }
    const abs = resolve(dirPath, entry.name);
    const rel = relBase ? `${relBase}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      collected.push(...collectDistFiles(abs, rel));
      continue;
    }
    if (entry.isFile()) {
      collected.push({ abs, rel });
    }
  }
  return collected;
}

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.txt': 'text/plain; charset=utf-8',
  '.ico': 'image/x-icon'
};

const assets = {};
for (const file of collectDistFiles(distDir)) {
  const data = readFileSync(file.abs);
  const ext = extname(file.rel);
  assets[`/${file.rel}`] = {
    type: mimeTypes[ext] || 'application/octet-stream',
    data: data.toString('base64')
  };
}

const serverCode = `const ASSETS = ${JSON.stringify(assets)};

function normalizePath(pathname) {
  try {
    const clean = decodeURIComponent(pathname || '/');
    const withoutQuery = clean.split('?')[0].split('#')[0];
    const normalized = withoutQuery.endsWith('/') ? withoutQuery : withoutQuery.replace(/\\/+$|^\\/$/, match => (match === '/' ? '/' : ''));
    if (!normalized) return '/';
    return normalized.startsWith('/') ? normalized : '/' + normalized;
  } catch (_error) {
    return '/';
  }
}

function decodeBase64(base64) {
  if (globalThis.atob) {
    const binary = globalThis.atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }
  const bytes = Uint8Array.from(Buffer.from(base64, 'base64'));
  return bytes;
}

function getAsset(pathname) {
  const cleaned = normalizePath(pathname);
  const candidates = [cleaned];

  if (cleaned.endsWith('/')) {
    candidates.push(cleaned + 'index.html');
  } else if (!cleaned.includes('.')) {
    candidates.push(cleaned + '/index.html');
  }

  if (cleaned === '/') {
    candidates.unshift('/index.html');
  }

  for (const key of candidates) {
    if (ASSETS[key]) return ASSETS[key];
  }

  return ASSETS['/index.html'];
}

async function fetchHandler(request) {
  try {
    const url = new URL(request.url);
    const asset = getAsset(url.pathname);
    if (!asset) {
      return new Response('Not Found', { status: 404 });
    }
    return new Response(decodeBase64(asset.data), {
      status: 200,
      headers: {
        'Content-Type': asset.type,
        'Cache-Control': 'public, max-age=3600'
      }
    });
  } catch (error) {
    return new Response('Server error: ' + String(error), { status: 500 });
  }
}

export default { fetch: fetchHandler };
if (typeof addEventListener === 'function') {
  addEventListener('fetch', (event) => {
    event.respondWith(fetchHandler(event.request));
  });
} else if (typeof process !== 'undefined' && process.release?.name === 'node' && process.env.PREVIEW_DISABLE_SERVER !== '1') {
  const { createServer } = await import('node:http');
  const host = process.env.HOST || '127.0.0.1';
  const port = Number(process.env.PORT || 4173);
  const server = createServer(async (req, res) => {
    try {
      const origin = 'http://' + (req.headers.host || host + ':' + port);
      const response = await fetchHandler(new Request(origin + (req.url || '/'), { method: req.method }));
      res.writeHead(response.status, Object.fromEntries(response.headers));
      res.end(Buffer.from(await response.arrayBuffer()));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Server error: ' + String(error));
    }
  });
  server.listen(port, host, () => {
    console.log('Preview listening on http://' + host + ':' + port);
  });
}
`;

writeFileSync(resolve(runtimeDir, 'index.js'), serverCode.trimStart());
writeFileSync(resolve(appgenDir, 'appgarden.json'), JSON.stringify({}, null, 2));
