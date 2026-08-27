import webpush from 'web-push';
import fs from 'node:fs';

const sub = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const [pub, priv] = [process.env.VAPID_PUBLIC_KEY, process.env.VAPID_PRIVATE_KEY];
webpush.setVapidDetails('mailto:test@example.com', pub, priv);
const n = process.argv[3] || '1';
const tag = `repro-beta7-${n}-${Date.now()}`;
const payload = JSON.stringify({
  title: `repro beta7 #${n}`,
  options: {
    body: `[beta7 #${n}] click me — the SW pings the server on notificationclick`,
    actions: [{ action: 'settings', title: 'Settings' }],   // forces the Alerts-helper path
    requireInteraction: true,
    tag,
  },
});
const proxy = process.env.HTTPS_PROXY;
const opts = proxy ? { proxy } : {};
try {
  const r = await webpush.sendNotification(sub, payload, opts);
  console.log(`SENT status=${r.statusCode} tag=${tag} at=${new Date().toISOString()}`);
} catch (e) {
  console.log('FAILED', e?.statusCode, e?.body || e?.message || String(e));
  process.exit(1);
}
