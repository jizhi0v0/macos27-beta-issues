# Chrome notification click silently fails to navigate: `usernoted` logs "Failed to source application bundle" for Chrome's Alerts helper, and the site's `notificationclick` never fires
# Chrome 通知点击静默跳转失败：`usernoted` 对 Chrome 的 Alerts helper 报 "Failed to source application bundle"，网站的 `notificationclick` 事件根本没触发

> 🔗 **Track / 关注此问题:** [#26 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/26)

| | |
|---|---|
| **Status** | 🔴 **Root cause confirmed, mechanism reproduced under controlled conditions** (2026-08-11). Clicking a Chrome "alert-style" (persistent/actionable) web notification sometimes does nothing beyond bringing Chrome to the foreground — no navigation to the notification's target page — because macOS's `usernoted` fails to resolve Chrome's Alerts-helper bundle at delivery time, and the site's `notificationclick` handler is never invoked. Confirmed present on beta4 `26A5388g` and beta5 `26A5406e`. Reproduced 1/8 in a controlled test — **intermittent**, not deterministic. |
| **macOS** | 27.0 beta4 `26A5388g` → beta5 `26A5406e` |
| **Component** | Apple `usernoted` (bundle resolution for a freshly-connecting XPC client) ↔ Google Chrome's `Google Chrome Helper (Alerts).app` |
| **Chrome** | `151.0.7922.109` (Official Build) (arm64) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max |
| **Report** | Apple Feedback: `FB________` *(to be filed)* · Chromium: `crbug.com` under UI>Notifications *(to be filed — see "Can Chrome fix this?" below)* |

## Symptom / 症状

A Chrome "alert-style" notification (persistent / has an action button — e.g. a YouTube "For you" recommendation with a **Settings** action) is clicked, macOS switches focus to Chrome, and **nothing else happens** — the notification's target page (e.g. the specific YouTube video/channel) never opens.

点击一条 Chrome 的"alert 样式"通知（持久、带 action 按钮——例如 YouTube 的"为你推荐"通知，带 Settings 按钮），macOS 把焦点切到 Chrome，然后**什么都不再发生**——通知本该跳转到的目标页面（比如具体的 YouTube 视频/频道）不会打开。

Originally reported alongside a second, more severe symptom — the same banner also appearing to never auto-dismiss and being unresponsive to swipe. That total-freeze behavior has **not** been reproduced under controlled testing (see "Also reported, not yet reproduced" below) and is tracked separately from the confirmed mechanism below.

## Root cause (confirmed) / 根因（已确认）

1. **Why this notification goes through a separate helper process at all.** Chromium's macOS notification code routes a notification through the standalone `Google Chrome Helper (Alerts).app` — instead of the main `Google Chrome.app` process — whenever the notification is "persistent" (`IsPersistentNotification()`: `never_timeout()`, i.e. the Notification API's `requireInteraction: true`, or a progress-type notification). This is not a Chrome quirk — it's the Apple-mandated pattern: a single app can only declare itself banner-style *or* alert-style with the system, not per-notification, and only alert-style notifications persist/carry actions, so Chrome must hand persistent ones to a separate process that's registered as alert-style. Source: [`notification_platform_bridge_mac.mm`](https://chromium.googlesource.com/chromium/src/+/66.0.3359.158/chrome/browser/notifications/notification_platform_bridge_mac.mm). Confirmed by our own log capture — the plain "site updated in background" notification (no action, not persistent) went through `bundle=com.google.Chrome` directly with zero errors, while the actionable YouTube notification went through `bundle=com.google.Chrome.framework.AlertNotificationService`.
2. **The helper is not one-shot.** `AlertDispatcherImpl` keeps a persistent `NSXPCConnection`, initialized once and reused for subsequent notifications, and later mojo-era code (`CheckIfServiceCanBeTerminated`, `OnServiceDisconnectedGracefully`) tears it down only when idle. Confirmed empirically: `ps aux` showed `Google Chrome Helper (Alerts)` alive for the full ~10+ minutes of our repeated test firings, and gone only after being idle for a while afterward. (This corrects an earlier hypothesis, credited to a "Codex" analysis pasted into this conversation, that the helper is one-shot and "refuses to run standalone" — that framing doesn't match the source or our own process observation.)
3. **The actual failure, inside macOS.** When `usernoted` (PID 698 here) needs to (re)connect to the helper — e.g. on its first use in a while — it sometimes fails to resolve the helper's bundle:
   ```
   usernoted: [com.apple.unc:server] Connection com.google.Chrome.framework.AlertNotificationService with path:
     /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/151.0.7922.109/Helpers/Google Chrome Helper (Alerts).app
   usernoted: [com.apple.unc:application] com.google.Chrome.framework.AlertNotificationService Failed to source application bundle
   ```
   followed shortly after (during the same delivery) by:
   ```
   usernoted: (Foundation) [com.apple.Foundation:general] NSBundle (null) initWithPath failed because the resolved path is empty or nil
   ```
   This string does not appear anywhere in Chromium's source — it's `usernoted`'s own error, and it fires on a well-formed, correctly-addressed XPC connection from Chrome. **The failure is inside Apple's code**, not in what Chrome sent.
4. **The consequence: click delivery silently breaks for that specific notification.** The notification still gets created, delivered, and presented as a banner normally — so there's no visible sign anything went wrong. But when the user later clicks it, macOS still does its own generic "bring this app forward" step (which only needs the bundle identifier string, not full bundle resolution) — creating the illusion that something happened — while the deeper step that's supposed to deliver a `notificationclick` DOM event back to the site's service worker (so it can call `clients.openWindow(targetURL)`) never fires.

## Confirmed reproduction / 已确认复现

Built a minimal local test harness (`index.html` + `sw.js`, served over `http://127.0.0.1:8934/`, driven in the user's real Chrome — not a sandboxed browser) that registers a service worker and fires `ServiceWorkerRegistration.showNotification()` with `requireInteraction: true` and an `actions` array, to force the same Alerts-helper delivery path. `sw.js`'s `notificationclick` handler does two things: `fetch()`s a URL on the local test server (independent, server-side proof the event fired, regardless of window focus) and calls `clients.matchAll()` + `focus()`/`openWindow()`.

Fired 8 such notifications. **1 of 8** produced the identical `Failed to source application bundle` log line for `com.google.Chrome.framework.AlertNotificationService`, at the same millisecond as that notification's `NotificationsPipeline` create step — confirmed by matching `uuid` between the error's adjacent connection log and the notification record:

```
22:30:24.333908  usernoted: ... Failed to source application bundle
22:30:24.446410  usernoted: ... Presenting <NotificationRecord ... uuid:"ADCB673B" ...> as alert
```

Checking the local test server's access log after the user clicked each of the two notifications (the one that hit the error, and a clean control fired minutes later):

```
$ grep click-log server.log
22:36:01 "GET /click-log?tag=repro-1786458863004&..." 404   ← the CLEAN notification's click fired
$ grep 1786458624211 server.log
(no match)                                                   ← the notification that hit "Failed to source application bundle": click never fired
```

The user confirmed both notifications *looked* the same when clicked (Chrome came to the foreground either way) — the difference only shows up server-side, in whether the page's own click handler actually ran. This matches the original report precisely: clicking switched to Chrome but did not navigate anywhere.

**Sample size caveat:** 1/8 in this run. Real-world frequency over one user-session was 13 occurrences of this exact log line across several hours (all for this same Chrome identifier) — consistent with "intermittent, not rare," but not large enough to state a hit rate.

## Can Chrome fix this themselves? / Chrome 自己能修吗？

**Not the root cause directly — that's inside `usernoted`, Apple's closed-source code.** Chrome's data going into the pipeline is well-formed (verified: real title/subtitle/body/destination URL, correct XPC connection to the correct helper path); the resolution failure happens after that, inside Apple's process. Chrome engineers cannot patch `usernoted`.

**But Chrome could plausibly mitigate it**, since their own architectural choice (spinning up a separate helper process and connecting to `usernoted` fresh) is the precondition that exposes this failure mode:
- Keep the Alerts helper's connection warmer / avoid cold (re)registration — our test showed only the *first* delivery after a gap hit the error; rapid subsequent deliveries within the same warm session did not.
- Detect and retry: if `usernoted`'s registration handshake can be observed to fail or time out, re-establish the connection before considering the notification's click-routing ready.

Realistically this needs **two reports**: an Apple Feedback for the actual defect (bundle resolution failing inside `usernoted`), and a Chromium bug (`crbug.com`, component UI>Notifications) asking for client-side resilience against this known-possible OS-side failure — mirroring how Chromium already tracks related Alerts-helper robustness issues (e.g. [issues.chromium.org/issues/40246993](https://issues.chromium.org/issues/40246993), "macOS Alerts Notification Helper should have a properly...").

## Also reported, not yet reproduced: total freeze (no auto-dismiss, unswipeable) / 也有报告但尚未复现：完全卡死

The original report also described the same class of banner staying on screen indefinitely and being unresponsive to the right-swipe dismiss gesture, not just to click. In this session's controlled testing, **swipe worked normally** on all 8 test notifications, including the one that hit `Failed to source application bundle` — so that more severe behavior was not reproduced here. Whether it's the same root cause at a higher severity, a separate compounding issue, or was affected by macOS's Sleep/Focus mode being active at the time (confirmed to suppress banner presentation during part of this testing) is unresolved. Tracked as an open question, not folded into the confirmed mechanism above.

### DB forensics from the original stuck notification / 原始卡住通知的数据库取证

For the record, this is what was found in `~/Library/Group Containers/group.com.apple.usernoted/db2/db` (SQLite; schema is private/undocumented by Apple, so table semantics below are inferred from field names and behavior, not official docs) for the original real-world stuck notification, before it eventually cleared on its own after several hours:

```
$ sqlite3 "$DB" "SELECT app_id, identifier FROM app WHERE identifier LIKE '%chrome%';"
65|com.google.chrome
66|com.google.chrome.framework.alertnotificationservice

$ sqlite3 "$DB" "SELECT rec_id, app_id, datetime(request_date+978307200,'unixepoch','localtime'), presented FROM record WHERE app_id IN (65,66);"
143413|66|2026-08-11 18:01:00|0
```
Decoded `record.data` (bplist): `title: www.youtube.com`, `subt: For you: Beta Profiles`, `body: iOS 27 has reduced the Liquid Glass button blur so much that it's basically gone. #ios27`, `dest: https://www.youtube.com/` — a well-formed notification, not a contentless placeholder. Its `delivered`/`displayed` per-app BLOBs for `app_id=66` held exactly this one UUID while sibling notifications from the same session had already cleared — i.e. macOS's own bookkeeping still considered it live at the time. Re-checked ~4 hours later: the record was gone from the DB entirely (not merely aged out by the table's rolling window — the row-count math doesn't support that explanation), suggesting it did eventually resolve on its own rather than staying stuck forever, though the on-screen state at that later time wasn't independently confirmed.

## What's ruled out / 已排除

- **Not a general Notification Center outage.** Other apps' notifications, and Chrome's own non-actionable notifications, are unaffected.
- **Not a malformed/contentless payload** — both the original stuck notification and the controlled-test notifications decode to well-formed records with real destinations.
- **Not Chrome's separate "This site has been updated in the background" placeholder** — that's expected behavior for silent push (no destination by design), unrelated to this bug.
- **Not a Background-Items/Login-Items permission problem.** `sfltool dumpbtm` confirms `Google Chrome Helper (Alerts).app` is not a registered Background Task Management item at all (it's a plain child process Chrome spawns on demand, not a LaunchAgent/daemon) — there's no "allow in background" toggle governing it.
- **Not a one-shot-helper-exits-before-macOS-can-use-it problem** — corrected above; the helper is connection-reused, not one-shot.

## Relationship to the older "click doesn't navigate" Sequoia bug / 和旧的「点击不跳转」bug 的关系

Superficially similar to the long-standing macOS 15 Sequoia-era issue where clicking a Chrome notification failed to open the linked page (well documented externally, e.g. [MacRumors: "Chrome Notifications not clickable"](https://forums.macrumors.com/threads/chrome-notifications-not-clickable.2432947/), reported from Sequoia 15.1 beta in 2024-08 through at least 2025-03). The reporter's own prior testing found that older bug fixed as of macOS 26 beta2. Whether this beta4/beta5 mechanism is a regression of the same underlying code path or an unrelated new defect with the same user-visible symptom is unknown — no macOS 26 comparison data for the specific `Failed to source application bundle` signature exists yet.

## Open questions / 待定

1. Hit rate: how often does a "cold" Alerts-helper (re)connection hit `Failed to source application bundle`? Needs many more trials, spaced to force the helper to go idle/exit between each.
2. Does this reproduce with Safari or other browsers using the equivalent "separate alert-style delivery process" pattern, or is it specific to Chrome/Chromium's implementation?
3. Is the "total freeze / unswipeable" symptom the same root cause at higher severity, or unrelated? A Finder notification reportedly got similarly stuck at some point in the past, which — if confirmed with logs — would point toward a general `usernoted` defect rather than something Chrome-specific; no corroborating log evidence found so far (the retained unified-log buffer doesn't reach back far enough to check).
4. Exact **build-to-build window**: confirmed present on beta4 → beta5; beta1–beta3 not retested; no macOS 26 comparison.
5. Would the client-side mitigations suggested above (keep-warm, retry-on-failed-registration) actually work? Untested — would need a Chromium patch to try.
