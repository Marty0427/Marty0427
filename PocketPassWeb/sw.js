/**
 * Service worker: makes PocketPass work with no connection at all.
 *
 * A wallet is most needed in a supermarket basement or a departure gate, so every file the
 * app needs is cached on install. The strategy is cache-first with a background refresh:
 * what is stored always wins for speed, and a newer copy replaces it for next time.
 */

const CACHE = "pocketpass-v1";

const SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./manifest.webmanifest",
  "./js/app.js",
  "./js/barcode.js",
  "./js/render.js",
  "./js/scanner.js",
  "./js/store.js",
  "./vendor/bwip-js.min.js",
  "./vendor/zxing.min.js",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      // addAll fails the whole install if any single file 404s, which would leave the app
      // half-cached; adding them one by one keeps a missing icon from breaking offline mode.
      .then((cache) => Promise.all(SHELL.map((path) => cache.add(path).catch(() => null))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) => Promise.all(names.filter((name) => name !== CACHE).map((name) => caches.delete(name))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET" || new URL(request.url).origin !== self.location.origin) return;

  event.respondWith(
    caches.match(request).then((cached) => {
      const fromNetwork = fetch(request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => cached ?? caches.match("./index.html"));

      return cached ?? fromNetwork;
    })
  );
});
