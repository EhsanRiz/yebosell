// Minimal static file server for Playwright E2E. Serves the repo root so the app's
// absolute asset paths (/assets/config.js, /dashboard/, /terms/, ...) resolve exactly
// as they do on the deployed site. No external dependencies.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PORT || 4321);

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json',
  '.txt': 'text/plain; charset=utf-8',
};

const server = http.createServer((req, res) => {
  try {
    let pathname = decodeURIComponent((req.url || '/').split('?')[0]);
    if (pathname.endsWith('/')) pathname += 'index.html';
    // Resolve within ROOT and block path traversal.
    const filePath = path.normalize(path.join(ROOT, pathname));
    if (!filePath.startsWith(ROOT)) { res.writeHead(403); return res.end('forbidden'); }
    fs.readFile(filePath, (err, data) => {
      if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }); return res.end('not found'); }
      const type = TYPES[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
      res.end(data);
    });
  } catch (e) { res.writeHead(500); res.end('error'); }
});

server.listen(PORT, () => console.log('static-server: http://127.0.0.1:' + PORT + ' (root: ' + ROOT + ')'));
