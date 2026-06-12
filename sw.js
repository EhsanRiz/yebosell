// YeboSell service worker — installable buyer app shell + offline fallback
const CACHE = 'yebosell-v1';
const SHELL = [
  '/track/',
  '/manifest.json',
  '/assets/config.js?v=5',
  '/assets/favicon.png',
  '/assets/icon-192.png',
  '/assets/icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL).catch(() => {})).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  // Never cache Supabase / API calls — always go to network.
  if (url.hostname.endsWith('supabase.co') || url.pathname.startsWith('/functions/')) return;

  // Navigations: network-first, fall back to cached /track/ shell when offline.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).catch(() => caches.match('/track/').then((r) => r || caches.match(req)))
    );
    return;
  }

  // Static assets: cache-first, then network (and cache same-origin responses).
  event.respondWith(
    caches.match(req).then((cached) => cached || fetch(req).then((res) => {
      if (url.origin === self.location.origin && res && res.status === 200) {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
      }
      return res;
    }).catch(() => cached))
  );
});
