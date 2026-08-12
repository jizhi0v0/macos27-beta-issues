import webpush from "web-push";

// Web Push harness for issues/#26. Real push (not showNotification from an open
// page) is what wakes the service worker from suspension, and that path
// reproduces the click failure far more often — roughly 4 of 7 vs 1 of 10.
//
// The service worker's notificationclick handler fetches /api/click-log, so
// whether the click actually reached the page is proven SERVER-SIDE and does
// not depend on what the tester believes they saw on screen. That is the whole
// point: the on-screen symptom is ambiguous, the log entry is not.

const HTML = `<!doctype html>
<html><head><meta charset="utf-8"><title>webpush repro</title></head>
<body>
<h1>Web Push repro harness</h1>
<p>Device label: <input id="labelInput" value="default"></p>
<p>Status: <span id="status">unregistered</span></p>
<button id="subBtn">1. Subscribe</button>
<button id="pushBtn">2. Send a real push</button>
<pre id="log"></pre>
<script>
const logEl = document.getElementById('log');
function log(...a){ logEl.textContent += a.join(' ') + "\\n"; }
const params = new URLSearchParams(location.search);
if (params.get('label')) document.getElementById('labelInput').value = params.get('label');
function b64(s){const p='='.repeat((4-s.length%4)%4);const b=(s+p).replace(/-/g,'+').replace(/_/g,'/');
  return Uint8Array.from([...atob(b)].map(c=>c.charCodeAt(0)));}
let reg;
navigator.serviceWorker.register('/sw.js').then(r=>{reg=r;
  document.getElementById('status').textContent='sw registered'; log('SW registered', r.scope);});
document.getElementById('subBtn').onclick = async () => {
  const perm = await Notification.requestPermission(); log('permission =', perm);
  if (perm !== 'granted') return;
  reg = reg || await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.subscribe({userVisibleOnly:true,
    applicationServerKey: b64('VAPID_PUBLIC_KEY_PLACEHOLDER')});
  const label = document.getElementById('labelInput').value || 'default';
  const res = await fetch('/api/subscribe?label='+encodeURIComponent(label),
    {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(sub)});
  log('subscribed under', label, ':', res.status);
};
document.getElementById('pushBtn').onclick = async () => {
  const label = document.getElementById('labelInput').value || 'default';
  const res = await fetch('/api/push?label='+encodeURIComponent(label), {method:'POST'});
  log('push:', res.status, await res.text());
};
</script></body></html>`;

const SW = `
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (e) {}
  event.waitUntil(self.registration.showNotification(d.title || 'push',
    Object.assign({ body: 'body', tag: 'default' }, d.options || {})));
});

self.addEventListener('notificationclick', (event) => {
  const tag = event.notification.tag;
  const action = event.action;
  event.notification.close();
  event.waitUntil((async () => {
    // Server-side proof the SW actually received the event, independent of
    // whether any window visibly changed.
    try { await fetch('/api/click-log?tag=' + encodeURIComponent(tag)
                      + '&action=' + encodeURIComponent(action) + '&t=' + Date.now()); } catch (e) {}
    const cs = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (cs.length) await cs[0].focus();
    else await clients.openWindow('/?clicked=' + encodeURIComponent(tag));
  })());
});
`;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const label = url.searchParams.get("label") || "default";

    if (url.pathname === "/" || url.pathname === "/index.html") {
      return new Response(HTML.replace("VAPID_PUBLIC_KEY_PLACEHOLDER", env.VAPID_PUBLIC_KEY),
        { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (url.pathname === "/sw.js") {
      return new Response(SW, { headers: { "content-type": "application/javascript; charset=utf-8" } });
    }
    if (url.pathname === "/api/subscribe" && request.method === "POST") {
      await env.PUSH_SUBS.put("sub:" + label, JSON.stringify(await request.json()));
      return new Response("ok " + label);
    }
    if (url.pathname === "/api/push" && request.method === "POST") {
      const subJson = await env.PUSH_SUBS.get("sub:" + label);
      if (!subJson) return new Response("no subscription for " + label, { status: 400 });
      webpush.setVapidDetails(env.VAPID_SUBJECT, env.VAPID_PUBLIC_KEY, env.VAPID_PRIVATE_KEY);
      const n = (parseInt(await env.PUSH_SUBS.get("seq:" + label) || "0", 10) || 0) + 1;
      await env.PUSH_SUBS.put("seq:" + label, String(n));
      const payload = JSON.stringify({
        title: "repro " + label + " #" + n,
        options: {
          body: "[" + label + " #" + n + "] click me — the SW pings the server on notificationclick",
          actions: [{ action: "settings", title: "Settings" }],   // forces the Alerts-helper path
          requireInteraction: true,
          tag: "repro-" + label + "-" + n + "-" + Date.now(),
        },
      });
      try {
        const r = await webpush.sendNotification(JSON.parse(subJson), payload);
        return new Response("push sent to " + label + " #" + n + ": " + r.statusCode);
      } catch (err) {
        return new Response("push failed: " + (err?.message || String(err)), { status: 500 });
      }
    }
    if (url.pathname === "/api/click-log") {
      const tag = url.searchParams.get("tag") || "";
      await env.PUSH_SUBS.put("click:" + tag,
        JSON.stringify({ tag, action: url.searchParams.get("action") || "",
                         t: url.searchParams.get("t"), receivedAt: Date.now() }));
      return new Response("logged");
    }
    return new Response("not found", { status: 404 });
  },
};
