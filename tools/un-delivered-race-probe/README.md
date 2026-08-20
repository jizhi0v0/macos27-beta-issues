# `getDeliveredNotifications` visibility-race probe

Minimal, self-contained reproducer for the macOS 27 regression behind [#26](https://github.com/jizhi0v0/macos27-beta-issues/issues/26): after `-[UNUserNotificationCenter addNotificationRequest:withCompletionHandler:]` has **already called back**, `getDeliveredNotificationsWithCompletionHandler:` keeps returning an **empty array** for ~7–24 ms (median ~15 ms) on macOS 27.0 beta5. On macOS 26.6 the notification is visible to the very first query, issued 10–30 µs after the same callback.

This matters because Chromium decides whether it may kill `Google Chrome Helper (Alerts).app` on exactly that query returning empty ([`mac_notification_service_un.mm`](https://chromium.googlesource.com/chromium/src/+/main/chrome/services/mac_notifications/mac_notification_service_un.mm), `MacNotificationServiceUN::OkayToTerminateService`) — so a check landing inside the window kills the helper while its own notification is still on screen, after which clicking that notification does nothing at all.

No Chrome involved: this probe talks straight to the system API.

## Build & run

```bash
APP=UNDVerify.app
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>UNDVerify</string>
  <key>CFBundleIdentifier</key><string>com.example.undverify</string>
  <key>CFBundleName</key><string>UNDVerify</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

xcrun swiftc -O -target arm64-apple-macos13.0 main.swift -o "$APP/Contents/MacOS/UNDVerify"
codesign --force --deep -s - "$APP"

mkdir -p ~/Applications && cp -R "$APP" ~/Applications/
open ~/Applications/UNDVerify.app      # must launch via `open`, see pitfalls
sleep 30 && cat ~/undverify_run.log
```

Click **Allow** on the notification prompt the first time. Results land in `~/undverify_run.log`.

## Reading the output

Two independent measurements per run:

- **Phase A** — fan-out: from the `add()` completion, sample at ~0/5/10/15/25/50/100/250 ms.
  `offset@issuedMs/repliedMs:Y|N(n=count)` — `n` is the size of the whole returned array, and `N(n=0)` is precisely Chrome's kill condition.
- **Phase B** — chained serial polling with no concurrency, to pin first-visible latency without any queueing effects.

## Pitfalls (each one silently corrupts a run)

- **Never block inside a UserNotifications completion handler** waiting on another UN callback — they share a queue, it deadlocks, and every sample comes back negative on *both* OS versions, which looks like a dramatic reproduction and is pure artifact. Schedule samples with `DispatchQueue.global().asyncAfter`.
- **Launch via `open`, not the bare binary.** Running `…/Contents/MacOS/UNDVerify` directly yields `Notifications are not allowed for this application`.
- **Do not `pkill` the app while its permission prompt is up** — that records a *permanent* denial for the bundle id, which is then unusable (verified: `authorizationStatus=1` afterwards). Use a fresh bundle id if you burn one.
- **Avoid `ProcessInfo.processInfo.hostName`** — it does an mDNS reverse lookup, which raises a Local Network permission prompt and stalls the run before it ever reaches `requestAuthorization`.
- Kill stale copies and delete the old log before each run, or you will read a previous build's output.

## Measured (2026-08-12)

| | macOS 27.0 beta5 `26A5406e` | macOS 26.6 `25G72` |
|---|---|---|
| visible at 0 ms | 0 / 16 | 16 / 16 |
| visible at 5 ms | 0 / 16 | 16 / 16 |
| visible at 10 ms | 5 / 16 | 16 / 16 |
| visible at 15 ms | 10 / 16 | 16 / 16 |
| visible at 25 ms | 16 / 16 | 16 / 16 |
| first-visible (serial poll, n=16) | 7.1 / **median 15.4** / 23.7 ms | 0.01–0.03 ms, zero misses |

32 trials per OS across two passes each; both machines `authorization granted=true`, `alertStyle=1 alertSetting=2`; unlocked, on console, no Focus assertion.

**Caveats.** Hardware is not controlled (M3 Max laptop on beta5 vs M4 mini on 26.6) — though the confound runs *opposite* to the effect (the mini was the loaded machine and is the fast one) and a ~1000× gap is not a CPU difference. `add()` completion latency was comparable on both (1.0–5.5 ms vs 0.9–1.9 ms). The probe also cannot distinguish "not yet delivered" from "delivered but the query serves a stale snapshot" — same observation either way, and the Chrome implication is unchanged, but the underlying defect differs. No reboot-to-reboot replication.
