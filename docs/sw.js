// shade – speichert die App, damit sie schnell startet und auch offline öffnet.
const CACHE = "shade-v9";
const SHELL = ["./", "index.html", "manifest.webmanifest", "icon-192.png", "icon-512.png", "apple-touch-icon.png"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  const url = new URL(req.url);
  // Videos direkt laden (Safari braucht dafür Teil-Anfragen), fremde Seiten nicht anfassen
  if (req.method !== "GET" || url.origin !== location.origin || url.pathname.endsWith(".mp4")) return;
  // Erst Netz (für Updates), bei Offline die gespeicherte Version
  event.respondWith(
    fetch(req)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((cache) => cache.put(req, copy));
        return res;
      })
      .catch(() => caches.match(req).then((hit) => hit || caches.match("index.html")))
  );
});

// Benachrichtigungen (auch wenn shade geschlossen ist)
self.addEventListener("push", (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch { d = { body: event.data && event.data.text() }; }
  event.waitUntil(self.registration.showNotification(d.title || "shade", {
    body: d.body || "", icon: "icon-192.png", badge: "icon-192.png", tag: d.tag, renotify: !!d.tag, data: { url: d.url || "./" }
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = new URL((event.notification.data && event.notification.data.url) || "./", self.registration.scope).href;
  event.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
    for (const c of list) { if ("focus" in c) { c.postMessage({ type: "open", url }); return c.focus(); } }
    return self.clients.openWindow(url);
  }));
});
