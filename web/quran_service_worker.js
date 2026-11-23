// tool/build_web.mjs fills the version and resource list in the build output.
const cacheVersion = 'development';
const resources = [];
const cacheName = `quran-offline-${cacheVersion}`;

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    if (resources.length === 0) return;
    const cache = await caches.open(cacheName);
    try {
      await cache.addAll(resources.map(resource => new Request(
        new URL(resource, self.registration.scope), {cache: 'reload'})));
    } catch (error) {
      await caches.delete(cacheName);
      throw error;
    }
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    if (resources.length === 0) return;
    for (const key of await caches.keys()) {
      if (key.startsWith('quran-offline-') && key !== cacheName) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' ||
      new URL(event.request.url).origin !== self.location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(cacheName);
    const cached = await cache.match(event.request, {ignoreSearch: true});
    if (cached) return cached;
    return fetch(event.request);
  })());
});
