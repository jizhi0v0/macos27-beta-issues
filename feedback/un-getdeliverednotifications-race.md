NOT YET FILED. Draft for Apple Feedback Assistant. Companion draft for the Chromium side lives in
`feedback/crbug-alerts-helper-termination.md` — file both, they are two halves of one user-visible bug.

Attach when filing: a sysdiagnose taken while a Chrome notification is in the stuck state, plus
`tools/un-delivered-race-probe/` (the standalone reproducer — it needs no browser at all).

# Title

UNUserNotificationCenter: getDeliveredNotifications returns an empty array for ~15 ms after
addNotificationRequest's completion handler has already fired (macOS 27.0 beta5 26A5406e; macOS 26.6
returns it immediately) — breaks any app that uses it as an "am I idle?" signal

# Apple area / component to select

User Notifications / UNUserNotificationCenter (macOS). Related: usernoted response routing.

# Summary

On macOS 27.0 beta5 (26A5406e), after `-[UNUserNotificationCenter addNotificationRequest:withCompletionHandler:]`
has **already invoked its completion handler with no error**, a subsequent call to
`getDeliveredNotificationsWithCompletionHandler:` still returns an **empty array** for roughly the next
**7–24 ms (median ~15 ms)**.

On macOS 26.6 (25G72) the same code sees the notification on the very first query, issued **10–30 µs**
after that same callback, with zero misses.

This is not merely a cosmetic inconsistency. `getDeliveredNotifications` is the only supported way for an
app to ask "do I still have notifications on screen?", and apps use that answer to decide whether their
notification-serving process may terminate. During the window, the API tells a correctly-written app that
it has no notifications displayed **milliseconds after the system confirmed it just posted one**.

# Measurement

A ~50-line Swift probe (attached; no browser involved) posts one categorized notification, then samples
`getDeliveredNotifications` at increasing delays measured from the moment `add()`'s completion handler fired.

| | macOS 27.0 beta5 `26A5406e` | macOS 26.6 `25G72` |
|---|---|---|
| visible at 0 ms | **0 / 16** | **16 / 16** |
| visible at 5 ms | 0 / 16 | 16 / 16 |
| visible at 10 ms | 5 / 16 | 16 / 16 |
| visible at 15 ms | 10 / 16 | 16 / 16 |
| visible at 25 ms | 16 / 16 | 16 / 16 |
| first-visible latency, serial polling (n=16) | 7.1 / **median 15.4** / max 23.7 ms | **0.01–0.03 ms**, first query, zero misses |

32 trials per OS across two passes on each machine, independently re-implemented and re-run to confirm.
Both machines: `authorization granted=true`, `alertStyle=1`, `alertSetting=2`, unlocked, on console, no
Focus assertion. The returned array is not merely missing the identifier — it comes back **empty (`n=0`)**.

A second, independent reproducer (a two-bundle demo, also attached) shows the same binary taking the
opposite branch on the two OS versions, with the query issued at essentially the same instant:

```
macOS 26.6  25G72     query: count=1 mineVisible=Y issued=+0.52ms  ->  app stays alive
macOS 27.0  26A5406e  query: count=0 mineVisible=N issued=+0.49ms  ->  app exits  (14/14 trials)
```

# Why this breaks real software today

Google Chrome delivers persistent/actionable web notifications from a separate helper process,
`Google Chrome Helper (Alerts).app`, because macOS lets an app register as *either* banner-style *or*
alert-style, not per-notification. Chromium decides whether that helper may exit with exactly this query
([`mac_notification_service_un.mm`](https://chromium.googlesource.com/chromium/src/+/main/chrome/services/mac_notifications/mac_notification_service_un.mm)):

```objc
void MacNotificationServiceUN::OkayToTerminateService(
    OkayToTerminateServiceCallback callback) {
  ...
  GetDisplayedNotifications(                       // -> getDeliveredNotificationsWithCompletionHandler:
      /*profile=*/nullptr, /*origin=*/std::nullopt,
      base::BindOnce([](std::vector<mojom::NotificationIdentifierPtr> notifications) {
        return notifications.empty();              // empty array == safe to terminate
      }).Then(std::move(callback)));
}
```

When that check lands inside the window, Chrome is told it has nothing displayed, and terminates the
helper **while its own notification is still on screen**. Observed helper lifetimes after posting: **42 ms**
and **140 ms**.

The user then clicks the notification and **nothing happens at all** — for minutes, across repeated clicks.

# Second defect: the response-routing recovery cannot recover

Once the registered client has exited, `usernoted` does receive the click and does attempt recovery, but
the recovery is ineffective for this class of client. Measured over one 7-minute stuck window on beta5:

```
clicks received by usernoted ("Received response") : 61
Alerts-helper appDeath events                      : 60      <- ~one relaunch-and-die per click
clicks actually forwarded to the client            :  2
```

RunningBoard / LaunchServices show why, in 78 ms:

```
01:58:48.754  usernoted: Received response <NotificationRecord app:"…helper" …>
01:58:48.758  usernoted: Launching …helper at path <private> for response
01:58:48.827  helper: launched with no arguments -> exit(0) immediately
01:58:48.832  launchservicesd: kLSNotifyApplicationDeath … "LSExitStatus"=0
01:58:48.832  usernoted: Foreground launch of <private> for …helper successful      <- already dead
01:59:20.807  launchservicesd: Launch of App … timed out, but the application is quitting
```

A Chromium helper process launched standalone by LaunchServices receives none of the arguments its
browser process would pass, so it exits immediately by design. `usernoted` logs the relaunch as
**successful** against a process that has already exited, then discards the user's click. On the legacy
`NSUserNotification` client path that Chrome uses, **no error is logged at all** (0 occurrences of
`Failed to notify application …` across the whole stuck window).

Requests:
1. Do not report a launch as successful when the launched process has already exited.
2. When the registered client cannot be revived, fall back to the app's main bundle rather than silently
   discarding the interaction, and/or surface an error.

That said, **the relaunch mechanism itself is sound** — a control run of the attached demo, identical in
every respect except that the helper is permitted to run standalone, had the click delivered 159 ms later.
The primary defect is the visibility race, which is what makes an otherwise-correct app kill its own client.

# Steps to reproduce

1. Build and run `tools/un-delivered-race-probe/` (attached). Grant notification permission when asked.
2. Read `~/undverify.log`.

Expected (macOS 26.6 behaviour): the just-added notification is visible to the first query.
Actual (macOS 27.0 beta5): the query returns an empty array for the first ~7–24 ms.

For the user-visible consequence, install Chrome, subscribe to any site's web push, receive a
persistent notification, wait a few seconds, then click it — roughly half the time nothing happens.

# Environment

- macOS 27.0 beta5 `26A5406e`, MacBook Pro `Mac15,11` (M3 Max) — affected
- macOS 26.6 `25G72`, Mac mini (M4) — not affected
- Google Chrome `151.0.7922.109` (arm64), for the real-world consequence
- Also observed on macOS 27.0 beta4 `26A5388g`; beta1–beta3 not tested

# Caveats stated honestly

- The two machines are different hardware. A same-machine A/B across OS versions was not possible. The
  confound runs *opposite* to the effect (the macOS 26.6 machine was the loaded one and is the fast one),
  `add()` completion latency was comparable on both (1.0–5.5 ms vs 0.9–1.9 ms), and a ~1000× gap is not a
  CPU difference — but it is not controlled.
- The probe cannot distinguish "the notification is not actually delivered yet" from "it is delivered but
  the query serves a stale snapshot". Both produce the same observation and the same consequence for
  callers, but they imply different fixes.
- No reboot-to-reboot replication.
