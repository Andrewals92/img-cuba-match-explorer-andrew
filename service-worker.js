// Cuba Match Explorer service worker (v3.3)
// FIX: the previous worker intercepted every GET, including Supabase API
// calls, and its cache name never changed, so users could keep running an
// old app.js after a deploy. It now only handles same-origin static files,
// always tries the network first, and the cache name is versioned.
const CACHE = 'cuba-match-explorer-v3.7';
const ASSETS = ['./', './index.html', './styles.css', './app.js', './cloud-config.js', './manifest.webmanifest', './app-icon.svg'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // never touch Supabase/API traffic
  e.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok && res.type === 'basic') {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() => caches.match(req).then((r) => r || caches.match('./index.html')))
  );
});
