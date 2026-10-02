// Cuba Match Explorer service worker (v5.0)
// FIX: the previous worker intercepted every GET, including Supabase API
// calls, and its cache name never changed, so users could keep running an
// old app.js after a deploy. It now only handles same-origin static files,
// always tries the network first, and the cache name is versioned.
const CACHE = 'cuba-match-explorer-v5.0-r3';
const ASSETS = ['./', './index.html', './styles.css', './app.js', './workspace.js', './season.js', './calendar-utils.js', './notifications.js', './intelligence.js', './match-intelligence.js', './cloud-config.js', './manifest.webmanifest', './app-icon.svg'];

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
  if (url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return; // never cache API/AI responses
  e.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok && res.type === 'basic' && !/no-store|private/i.test(res.headers.get('Cache-Control')||'')) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      })
      .catch(() => caches.match(req).then((r) => r || (req.mode === 'navigate' ? caches.match('./index.html') : Response.error())))
  );
});

const pushPath=p=>/^#\/(program\/[a-f0-9-]{36}|radar|interviews|notification-settings|notification-center)$/.test(p)?p:'#/notification-center';
self.addEventListener('push',e=>{let d={};try{d=e.data?.json()||{};}catch{}e.waitUntil(self.registration.showNotification('Cuba Match Explorer',{body:'Tienes una nueva alerta. Abre la app para ver los detalles.',icon:'app-icon.svg',tag:d.id||'cme-alert',data:{path:pushPath(d.path)}}));});
self.addEventListener('notificationclick',e=>{e.notification.close();const url=new URL('/'+pushPath(e.notification.data?.path),self.location.origin).href;e.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async cs=>{for(const c of cs){if(new URL(c.url).origin===self.location.origin){await c.navigate(url);return c.focus();}}return self.clients.openWindow(url);}));});
