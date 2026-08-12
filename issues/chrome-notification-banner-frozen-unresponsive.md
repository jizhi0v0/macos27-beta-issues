# Clicking a Chrome alert-style notification does nothing: `usernoted` receives the click but silently drops it once the Alerts helper has exited
# 点击 Chrome 的 alert 样式通知没有任何反应：`usernoted` 收到了点击，但因 Alerts helper 已退出而静默丢弃

> 🔗 **Track / 关注此问题:** [#26 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/26)

| | |
|---|---|
| **Status** | 🔴 **Root cause established and isolated to a system API, reproducible without Chrome** (2026-08-12). On macOS 27, `getDeliveredNotifications` returns an **empty array for ~7–24 ms after `add()` has already completed** (0 ms on macOS 26.6, 32 trials per OS) — and Chromium kills its Alerts helper on exactly that answer. Clicking a persistent/actionable Chrome web notification does nothing at all once `Google Chrome Helper (Alerts).app` has exited. `usernoted` **does** receive every click — it just has no live client left to forward it to, and neither relaunches one nor falls back, dropping the click with no error logged. Anything that respawns the helper (a new notification arriving, quitting/reopening Chrome) instantly un-sticks **every** backlogged notification at once. |
| **macOS** | 🔴 27.0 beta5 `26A5406e` — hits roughly **4 of 7** real web-push notifications. Also seen on beta4 `26A5388g`. 🟢 **macOS 26.6 `25G72` control: 9/9 clean** on the same harness, same Chrome build, same account — and its Alerts helper stays alive while a notification is outstanding (7+ min observed), which is exactly what macOS 27 fails to do |
| **Component** | Apple `usernoted` (notification response routing) ↔ `Google Chrome Helper (Alerts).app` |
| **Chrome** | `151.0.7922.109` (Official Build) (arm64) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max (27 beta5) vs. a second Mac on macOS 26 (control) |
| **Report** | Chromium: **posted 2026-08-12 as [comment #26](https://issues.chromium.org/issues/370536109#c26) and follow-up [#27](https://issues.chromium.org/issues/370536109#c27) (the reliable repro) on issue 370536109** — that issue has been open since 2024-10-01 with the identical symptom, was reproduced by Google in #12, and had no root cause in 16 months. Apple: **filed 2026-08-12 as `FB24273686`** (macOS / Notification Center), with both reproducers attached — draft kept in [`feedback/un-getdeliverednotifications-race.md`](../feedback/un-getdeliverednotifications-race.md) |

## Symptom / 症状

A Chrome notification that has an action button (i.e. a *persistent* notification — `requireInteraction: true` and/or `actions`, which is what YouTube's "For you" push notifications use) sits on screen, and then:

- **Left click does nothing.** Not a slow click, not a wrong target — single click, double click, repeated clicks, all produce no visible effect whatsoever, indefinitely.
- **Right-click and swipe-to-dismiss usually still work** (in one extreme instance neither did — see [Variations](#variations-honestly-recorded--如实记录的变体)).
- It recovers **all at once**, without user action, at an unpredictable time — from ~2 minutes to ~16 minutes later.

一条带按钮的 Chrome 通知（即 *persistent* 通知，`requireInteraction: true` 和/或 `actions`，YouTube 的"为你推荐"推送就是这类）弹出后：**左键点击完全没有反应**——不是慢，不是点偏，单击、双击、连点都没有任何效果，可以持续十几分钟；**右键和右滑通常仍然正常**；之后会在某个不可预测的时刻（2～16 分钟）**突然一次性全部恢复**。

## Root cause / 根因

**`usernoted` receives the click, finds no live XPC client to hand it to, and drops it silently.**

Chrome must route persistent notifications through a separate `Google Chrome Helper (Alerts).app` process, because macOS only lets a single app register as *either* banner-style *or* alert-style, and only alert-style notifications persist and carry action buttons (Chromium's `IsPersistentNotification()` gate — [`notification_platform_bridge_mac.mm`](https://chromium.googlesource.com/chromium/src/+/66.0.3359.158/chrome/browser/notifications/notification_platform_bridge_mac.mm)). That helper **exits once it goes idle**, taking its `usernoted` client registration with it. If the user clicks after that point, the response has nowhere to go.

The decisive evidence is a single pair of log counters, taken over the same stuck notification:

```
# WHILE STUCK — user clicked 16 times:
$ log show --predicate 'process == "usernoted"' --info --debug --last 4m | grep -c "Received response.*mac27"
16                                    ← every click WAS received by usernoted
$ log show --predicate 'process == "usernoted"' --info --debug --last 4m | grep -c "sent to NSUserNotification client"
0                                     ← not one of them was ever forwarded

$ ps aux | grep "Chrome Helper (Alerts)"
NOT RUNNING                           ← the registered client is gone
```

Then, **without touching the stuck notification**, a fresh push was sent purely to respawn the helper:

```
=== helper before push ===  NOT RUNNING
push sent to mac27: 201
=== helper after push  ===  RUNNING pid=4210
```

The user clicked the **old, previously dead** notification — and it worked immediately, with the forwarding line finally appearing:

```
Response <...mac27-1...> sent to NSUserNotification client
  <ClientConnect: ... identifier: com.google.Chrome.framework.AlertNotificationService pid: 4210 ...>
```

confirmed independently server-side (the service worker's `notificationclick` handler pinged the test server for `webpush-repro-mac27-1-…` only at that point, ~13 minutes after delivery).

### Why the OS recovery path can never work / 为什么系统的兜底路径注定失败

`usernoted` does **not** just give up — it tries to relaunch the client on every single click, and the relaunched helper dies within ~100 ms each time. Counted over the same stuck window:

```
clicks received by usernoted : 61
helper appDeath events        : 60      ← ~1 relaunch-and-die per click
clicks forwarded to client    : 2
```

RunningBoard shows the pattern in the raw:

```
00:25:50.081  Acquiring assertion targeting [anon<Google Chrome Helper (Alerts)>(501):147]
00:25:50.123  [anon<Google Chrome Helper (Alerts)>(501):147] termination reported by proc_exit   ← 42 ms
00:25:50.229  usernoted: Delivering / Presenting the notification
00:25:58, 00:25:59, 00:26:00, 00:26:12, 00:26:13 …   appDeath, appDeath, appDeath …   ← one per click
```

The reason is structural: a Chromium helper process launched **standalone by LaunchServices** has none of the mojo channel arguments its browser process would pass it, so it exits immediately by design. macOS's "relaunch the registered client and deliver the response to it" recovery is therefore fundamentally incompatible with how Chrome's Alerts helper works — the OS relaunches it, it dies, the response is dropped, forever.

*(Credit where due: an early hypothesis in the investigation — that the helper "refuses to run standalone" and so the system cannot fall back — was dismissed here on the grounds that the helper is connection-reused rather than one-shot. The connection-reuse point was right, but the standalone-launch point was **also** right, and is exactly the mechanism above.)*

### The full chain / 完整链条

1. Chrome delivers a persistent notification via the Alerts helper → helper registers as an `usernoted` client;
2. the helper **exits while the notification is still outstanding** — on macOS 27 sometimes only **140 ms** after posting (see lifetimes below); its registration dies with it;
3. user clicks → **`usernoted` receives the click normally** (so mouse input, WindowServer hit-testing and event dispatch are all fine — this rules out the whole input-latency family of explanations);
4. `usernoted` runs its `Search for url to launching … in background` path, LaunchServices starts the helper standalone, and it dies in ~100 ms. **Nothing is forwarded, and no error is logged.** The click is silently discarded — and this repeats identically for every subsequent click;
5. any event that gets Chrome itself to spawn a *proper* helper — a new notification arriving, or quitting and reopening Chrome — restores the registration and **instantly un-sticks every backlogged notification simultaneously**.

### Step 2 is where the versions diverge / 两个版本的分水岭在第 2 步

Helper lifetimes measured from RunningBoard on macOS 27 beta5 are wildly erratic — three orders of magnitude apart under nominally identical conditions:

```
pid 74467   38.62s
pid 78969    3.28s
pid 79617    0.14s   ← died instantly
pid 87903  164.85s
pid 147      0.14s   ← died instantly; this is the stuck mac27-1 notification
pid 4210    19.16s   ← the click that worked
```

On macOS 26, by contrast, the helper simply **stays alive as long as a notification of its own is outstanding** — observed alive for 7+ minutes with one undismissed notification, exiting only after it was handled. That is the correct behaviour, and it is why the OS's broken relaunch path is never exercised there.

### Answered: macOS 27 hides a just-posted notification from its own query for ~15 ms / 已解答：macOS 27 上刚投递的通知会有约 15 毫秒查不到

Chromium decides helper termination itself, and the decision is one line ([`mac_notification_service_un.mm`](https://chromium.googlesource.com/chromium/src/+/main/chrome/services/mac_notifications/mac_notification_service_un.mm)):

```objc
void MacNotificationServiceUN::OkayToTerminateService(
    OkayToTerminateServiceCallback callback) {
  ...
  GetDisplayedNotifications(                       // -> getDeliveredNotificationsWithCompletionHandler:
      /*profile=*/nullptr, /*origin=*/std::nullopt,
      base::BindOnce([](std::vector<mojom::NotificationIdentifierPtr> notifications) {
        return notifications.empty();              // empty array == safe to kill the helper
      }).Then(std::move(callback)));
}
```

So the question reduces to a testable property of the OS API, with no browser involved — and it fails on 27. A ~50-line Swift probe ([`tools/un-delivered-race-probe/`](../tools/un-delivered-race-probe/)) posts one notification and then samples `getDeliveredNotifications` from the moment `add()`'s **completion handler has already fired**:

| | macOS **27.0 beta5** `26A5406e` | macOS **26.6** `25G72` |
|---|---|---|
| visible at 0 ms | **0 / 16** | **16 / 16** |
| visible at 5 ms | 0 / 16 | 16 / 16 |
| visible at 10 ms | 5 / 16 | 16 / 16 |
| visible at 15 ms | 10 / 16 | 16 / 16 |
| visible at 25 ms | 16 / 16 | 16 / 16 |
| first-visible latency (serial poll, n=16) | 7.1 / **median 15.4** / 23.7 ms | **0.01–0.03 ms**, first query, zero misses |

32 trials per OS across two passes each, independently re-implemented and re-run to confirm. On beta5 the array does not merely omit the identifier — it comes back **`n=0`, empty**, which is exactly Chrome's kill condition. On 26.6 the very first query, issued **10–30 µs** after the same callback, already returns it: there is no window at all.

**That closes the chain.** Chrome asks "is anything still displayed?"; on macOS 27 the OS answers "no" for the first ~15 ms even though it has just confirmed the add; Chrome believes it and kills the helper (observed dying at **42 ms** and **140 ms**); the user's later click then has no client to go to, and `usernoted`'s relaunch attempt cannot produce one. It also explains the ~50–60 % hit rate directly: whether the bug fires depends on which side of a ~15 ms boundary Chrome's check happens to land.

**Caveats, stated plainly.** Hardware is not controlled (M3 Max laptop on beta5 vs M4 mini on 26.6); the confound runs *opposite* to the effect (the mini was the loaded machine and is the fast one) and a ~1000× gap is not a CPU difference, but same-machine A/B across OS versions was not possible here. The probe also cannot distinguish "not yet actually delivered" from "delivered, but the query serves a stale snapshot" — identical observation, same consequence for Chrome, but a different underlying defect. No reboot-to-reboot replication.

Point 5 retroactively explains every "it healed by itself after N minutes" observation from this investigation: on one occasion three separately-stuck notifications all became clickable within 21 seconds of each other, exactly when Chrome was restarted.

## Why Chrome only fails ~half the time, while the demo fails 14/14 / 为什么 Chrome 只有一半中招，而 demo 是 14/14

The race itself is deterministic — inside the window the query *always* answers empty. So the hit rate is decided entirely by **when Chrome happens to ask**, and Chromium's check is **not** tied to posting a notification. [`notification_dispatcher_mojo.cc`](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/notifications/mac/notification_dispatcher_mojo.cc) calls `CheckIfServiceCanBeTerminated()` from six places, and *showing* a notification is not one of them:

| call site | when it fires |
|---|---|
| constructor | Chrome start-up |
| `CloseNotificationWithId()` | after closing one notification |
| `CloseNotificationsWithProfileId()` | after closing a profile's notifications |
| **`OnNotificationAction()`** | **right after the user interacts with any notification** |
| `DispatchGetNotificationsReply()` / `DispatchGetAllNotificationsReply()` | when a displayed-notifications query comes back empty |
| `service_restart_timer_` | after an unexpected service teardown |

So the check lands at an essentially arbitrary offset from the last `add()`. Sometimes that is a few milliseconds later — inside the ~15 ms window — and the helper kills itself; usually it is seconds later, when the notification is long since visible, and nothing happens. That accounts for all three otherwise-puzzling observations at once:

- **~50–60 % hit rate on Chrome**, rather than the 100 % the race alone would predict;
- **helper lifetimes scattered across three orders of magnitude** (0.14 s / 0.14 s / 3.3 s / 19 s / 39 s / 165 s) — these are different *events* firing the check at different times, not an idle countdown;
- **the demo's 14/14**, because it queries ~0.5 ms after `add()` completes by construction and therefore never misses the window. The demo is a worst-case amplifier, not a model of Chrome's cadence.

**The `OnNotificationAction()` entry deserves special attention**, because it makes the bug partly self-inflicted and contagious between notifications: *interacting with one notification triggers an immediate termination check*. If a second notification was posted moments earlier and is still inside its invisibility window, that check reads empty, the helper exits — and the **second** notification is the one that becomes permanently unclickable. Dismissing or clicking one notification can therefore break another one that arrived just before it. This is a plausible mechanism for the original real-world report, where several notifications were involved and only some went dead, though it was not isolated experimentally here.

## Three distinct failure shapes — do not conflate them / 三种必须区分的失败形态

Most of the confusion in this investigation came from treating one symptom ("clicking a notification does nothing") as one bug. `usernoted`'s log separates them cleanly, and the distinction decides who can fix what:

| | click reaches `usernoted` | forwarded to the app | right-click / swipe | where it breaks |
|---|---|---|---|---|
| **A** | ✅ (61, and later 15) | ❌ 0 | **still work** | client process gone — **this is the filed bug** |
| **B** | ❌ 0 of 5 | — | **also dead** | before `usernoted` — **unexplained** |
| **C** | ✅ | ✅ | work | inside Chrome, after delivery — matches [crbug 370536109](https://issues.chromium.org/issues/370536109) |

**A is not a freeze.** Only activation fails; right-click and swipe behave normally. **B is the freeze** — the whole banner stops responding except its `✕`, and it is the symptom that originally started this investigation. Earlier revisions of this file used "stuck"/"frozen" loosely for both; that was sloppy.

### A reliable recipe for shape A / shape A 的可靠复现配方

Shape A was originally hit ~4 times in 7 pushes, seemingly at random. The missing variable was the **service worker's running state**, which was never controlled — the test page stayed open in every early run, keeping the SW warm and the Alerts helper alive. Controlling it makes the failure land:

1. subscribe a page to Web Push, then **close the tab**;
2. wait until `chrome://serviceworker-internals` shows that origin's worker `Running Status: STOPPED` (a push wakes it, so re-check ~60 s after the push — it stays `RUNNING` for a while);
3. send a push and leave the notification alone;
4. click it.

Measured on beta5 `26A5406e` with the SW confirmed `STOPPED`: **15 clicks → 15 `Received response`, 0 forwarded**, `Google Chrome Helper (Alerts)` not running, and the service worker's own server-side probe never pinged. RunningBoard shows the helper dying the same second it was spawned (`13:31:37 Acquiring → proc_exit → appDeath`), then one `appDeath` per subsequent click.

This is worth adding to the filed reports: it converts "roughly half the time" into a procedure.

### Independent corroboration of the filed mechanism / 对已提交机制的旁证

Two notifications outstanding at once were observed to **both** stay clickable, while single outstanding notifications went dead. That is exactly what the filed mechanism predicts — a non-empty `getDeliveredNotifications` makes `OkayToTerminateService` return false, so the helper survives — and it independently reproduces what reporters in comments #22/#23 of crbug 370536109 noticed years earlier without an explanation ("when multiple notifications are present simultaneously, notificationclick becomes effective").

### Things that look related but are not / 看着相关其实无关

- **Chrome's "This site has been updated in the background" placeholder.** It appeared repeatedly on one site during this session, which looked like a lead. It is Chrome's mandated fallback when a service worker takes a push event but does not call `showNotification()` in time — i.e. that site's SW is slow to wake, a property of that SW's own workload. Our harness, whose push handler does nothing but `showNotification()`, never produced it across 4 rapid pushes with the SW cold. It also cannot explain shape C, where the notification's real content displayed correctly (so the SW *did* wake and complete) and only the later click did nothing.

## Proof it is not Chrome-specific: a non-Chrome app reproduces it end to end / 与 Chrome 无关的自建 demo 完整复现

A two-bundle demo sharing **none of Chrome's code** ([`tools/notifdemo-nonchrome/`](../tools/notifdemo-nonchrome/)): a parent app launches `NotifDemoHelper.app` with a `--from-parent` marker; the helper posts one categorized notification, then evaluates Chromium's exact `OkayToTerminateService` predicate against its own `getDeliveredNotifications` and exits if the array is empty.

**The race hits it every time: 14 / 14** `add()` cycles on beta5 returned `count=0`, queried 0.35–2.23 ms after `add()`'s completion handler had already fired:

```
02:03:05.740 add() completion fired, id=notifdemo-CLICKC-… addMs=2.28
02:03:05.741 OkayToTerminateService query: count=0 mineVisible=N issued=+0.49ms replied=+1.07ms ids=[]
```

**The same binary takes the opposite branch on macOS 26.6**, with the query issued at essentially the same instant — this is the cleanest single comparison in the whole investigation:

```
macOS 26.6  25G72     query: count=1 mineVisible=Y issued=+0.52ms  ->  returns NO  -> staying alive
macOS 27.0  26A5406e  query: count=0 mineVisible=N issued=+0.49ms  ->  returns YES -> exit(0)  (14/14)
```

Three click conditions were then run on beta5, differing **only** in whether the helper can survive a standalone relaunch:

| | helper alive at click? | `Received response` | forwarded? | `appDeath` on click | user-visible |
|---|---|---|---|---|---|
| **A** exits, refuses standalone (Chrome-faithful) | no | yes | **no** | **yes, +78 ms** | **click does nothing** |
| **B** exits, standalone allowed | no → relaunched | yes | **yes, +159 ms** | no | works |
| **C** stays alive | yes | yes | **yes, +2 ms** | no | works |

Condition **A**, the whole failure in 78 ms:

```
01:58:48.754307 usernoted: Received response <NotificationRecord app:"com.jizhi0v0.notifdemo.helper" …>
01:58:48.754759 usernoted: Error  Failed to notify application with com.jizhi0v0.notifdemo.helper for response
01:58:48.758848 usernoted: Launching com.jizhi0v0.notifdemo.helper at path <private> for response
01:58:48.827    helper pid=9617: STANDALONE LAUNCH (no --from-parent marker) -> exit(0) immediately
01:58:48.832877 launchservicesd: kLSNotifyApplicationDeath … "LSExitStatus"=0, "pid"=9617
01:58:48.832514 usernoted: Foreground launch of <private> for com.jizhi0v0.notifdemo.helper successful   ← already dead
01:59:20.807817 launchservicesd: Launch of App:"NotifDemoHelper" … timed out, but the application is quitting
```

**Condition B is the important one.** Identical race, identical self-kill, identical `Failed to notify` — and the click still lands, 159 ms later, purely because the relaunched instance stayed alive. So **macOS's relaunch-based recovery is sound in principle and fails only for clients that cannot run standalone.** Chromium's helper is exactly such a client, which is what puts Chrome in condition A.

**Correction to an earlier claim in this file.** "No error is logged" is true of **Chrome's** case specifically — `Failed to notify application …` appears **0 times** across the 7-minute Chrome stuck window (61 clicks, 60 `appDeath`) — but not of the OS in general: the demo, which registers on the *modern* UN client path, does get that error logged. Correspondingly, `sent to NSUserNotification client` is a valid success signal only for the **legacy** `NSUserNotification` path Chrome's helper uses; on the modern path the equivalents are `Notifying UserNotifications client <bundle>:<pid> about response` → `Received … reply for response`. The demo never emits the legacy clause **even in condition C where delivery demonstrably worked**, so its absence there proves nothing — the Chrome-side inference stands on Chrome's own logs, where the successful click at 00:29:06 does carry `sent to NSUserNotification client … pid: 4210`.

**Demo caveats.** Per-app presentation style resolved to `alertStyle=1` (banner) rather than Chrome's Alerts, so the clicks came from Notification Center rather than a persistent alert panel — the response path is the same but it is not a byte-identical match. A/B/C are one click each (the 14/14 figure covers the race, not the click conditions). The macOS 26.6 arm covers the race/decision only (n=1, `count=1` → helper stays alive); A/B/C were not re-run there, since with the helper alive there is nothing to test.

## Reproduction / 复现

There is no deterministic trigger, but there is a **reliable recipe with a ~50–60% per-notification hit rate**: send a *real* web push (which wakes the service worker from a suspended state) rather than calling `showNotification()` from an open page.

A Cloudflare Worker harness was built for this: a page that registers a service worker, subscribes to real Web Push with a VAPID key, and a `/api/push` endpoint that sends a genuine push whose payload sets `requireInteraction: true` plus an `actions` button. The service worker's `notificationclick` handler `fetch()`es a logging endpoint, so **whether the click actually reached the page is proven server-side**, independent of anything visible on screen. Device labels (`?label=…`) let the same deployment target two machines separately for A/B.

| Environment | Result |
|---|---|
| macOS **27.0 beta5** `26A5406e`, Chrome 151.0.7922.109 | **4 of 7** notifications stuck |
| macOS **26** (control machine), same Chrome build, same harness | **7 of 7** clean, zero failures |
| Local page calling `showNotification()` directly (SW already warm, never suspended) | only 1 of 10 stuck — **much** weaker trigger, don't use this path |

The real-push path being so much stronger than the local-page path is itself a hint that the suspended-service-worker wake sequence matters — but that was not isolated further.

## What was falsified / 被证伪的假设

Recorded deliberately, because several of these looked convincing and cost real time:

| Hypothesis | How it died |
|---|---|
| `usernoted` logging `com.google.Chrome.framework.AlertNotificationService Failed to source application bundle` is the fault | It fires on essentially **every** cold reconnect of the helper — including 3 of the notifications that clicked **fine**. Byte-identical log output either way. **Settled cross-version:** the macOS 26 control machine logs the *same* error for the *same* bundle (11 times in 2 h) while being 9/9 clean. Pure noise for this bug |
| The Alerts helper must stay alive *at delivery time* | Force-killed the helper immediately after one delivery → that notification clicked **fine**. What matters is the helper's state *at click time*, not delivery time |
| Service-worker version changed between delivery and click | Built on a contaminated data point: the "dead" notification had **already been clicked and consumed** at 22:32:29 (visible in `usernoted`'s `_removeDelivered` log), so the later "retest" wasn't clicking a live notification at all |
| Elapsed time alone | Fired a push, waited 4 minutes untouched, then clicked → **worked fine** |
| WindowServer single-thread contention (cf. [#14](apple-click-input-latency-beta.md) / [#3](apple-windowserver-invalid-window.md)) | A `sudo sample` of WindowServer during a stuck period did show `ws_main_thread` ~53% in compositing — but quitting most heavy apps (WindowServer ~100% → 44%) did **not** prevent the next reproduction, and decisively: **`usernoted` receives every click**, so nothing upstream is dropping input. Correlation only; not the cause |
| `killall usernoted` | **No effect.** The restarted daemon (new PID) reloaded the same record from its store and behaved identically — 14 further clicks received, 0 forwarded. The bad state is not runtime state inside `usernoted` |
| `killall NotificationCenter` | No effect either |

## Recovery / 恢复方法

Anything that gets the Alerts helper running again, which re-registers the client:

- **wait for any other Chrome notification to arrive** (it spawns the helper), or
- **quit and reopen Chrome**.

Both un-stick *all* pending notifications at once. Note that restarting the notification daemons does **not** help (see table above) — which is worth stating explicitly, because that is the usual folk remedy for stuck banners, and it was the remedy that worked for a superficially identical problem on 2026-08-04 (see below).

## Who can fix this / 谁能修

The failure needs **both** halves to happen, and each half has an owner:

- **Chrome (Chromium) — has a fix available today, without waiting for Apple.** Two independent ones, in fact: (1) don't treat a single `getDeliveredNotifications` empty result as authoritative milliseconds after being told its own `add()` succeeded; (2) **let the Alerts helper survive an argument-less relaunch** — condition B above shows that alone is sufficient, because macOS's recovery then works and the queued click is delivered. Chrome is being lied to by the OS, so this is not where the defect originates, but either change makes it immune. On macOS 26 the same code never trips, because the OS never returns empty.
- **Apple — two separate defects, both required.** First, `getDeliveredNotifications` reports **empty for ~15 ms after `add()` has already completed** (measured above; absent on macOS 26.6) — this is the trigger, and the more serious bug, since it makes any app's "do I still have notifications displayed?" logic unreliable. Second, `usernoted`'s recovery path is a dead end by construction: it relaunches the registered client through LaunchServices, which for a Chromium helper means a process that exits in ~100 ms, and then it drops the user's click with **no retry against the app's main bundle and no user-visible feedback** — and, on the legacy client path Chrome uses, with no error logged either (0 `Failed to notify application` lines across the Chrome stuck window), while still logging the relaunch as `successful` against a process that has already exited. 61 clicks, 60 relaunch-and-die cycles, 2 forwarded. Even granting Chrome's premature exit, silently discarding every interaction is the OS's own defect.

## Variations honestly recorded / 如实记录的变体

- Usually **only left click** dies; right-click and swipe keep working. **Once**, all three died together, and that instance also survived a full Chrome quit-and-relaunch, self-healing only ~9.6 minutes after delivery. Whether that is the same bug in a worse state or a second, rarer problem is **unresolved**.

- **2026-08-12, corrected twice more.** Two things were claimed here this morning that later measurement does not support, and one that survives.

  **Survives:** every confirmed failure of this variant happened while the notification was showing as an **on-screen banner**, and in each case the banner was *stuck there* — not auto-dismissing when it should have. Banner state is a **necessary** condition as far as the evidence goes. The one clean cross-over remains the Reminders notification: 0 of 5 clicks reached `usernoted` as a banner, then 1 of 1 reached it minutes later as a Notification Center row and launched the app in 13 ms.

  **Withdrawn — "banner state is what determines it".** It is necessary but plainly **not sufficient**. Controlled pushes through the harness in [`tools/webpush-repro/`](../tools/webpush-repro/), each `requireInteraction: true` with an action button, were clicked as banners and worked normally: **59 s ✅, 65 s ✅, and 24 s with a full screen lock/unlock cycle in between ✅**. (Two further successes at 5 min and 8 min 50 s are *excluded* from this count — they were clicked 4 seconds apart, which suggests they were clicked from an open Notification Center list rather than as banners, and no measurement distinguishes the two.)

  **Withdrawn — every mechanism proposed for it so far.** Each was tested and failed:
  - *banner "expires" some seconds after presentation* — falsified: 65 s as a banner, still fine;
  - *a screen lock/unlock cycle breaks it* — falsified: locked and immediately unlocked, then clicked, worked;
  - *`UserNotificationCenter` liveness causes it* — withdrawn as reverse causality (checking liveness requires interacting, which may itself spawn the process);
  - *elapsed time* — falsified.

  **What the shape of the evidence now suggests:** not a property of an individual notification at all, but a **system state the machine intermittently enters**, during which notifications displayed as banners stop accepting activation while everything else about them keeps working (the `✕` still dismisses cleanly, with a full `_removeDelivered` → `_removeDisplayed` → Spotlight de-index sequence). Outside that state, banners survive minutes and a lock cycle without trouble. **What puts the machine into that state is unknown.**

  **Automated measurement is not available for this.** macOS ignores synthetic clicks on notification banners — a `CGEvent` posted at the banner's exact centre (obtained live from the accessibility tree) registered **nothing**: no `Received response`, no service-worker ping, and the banner stayed on screen. The accessibility tree exposes the banner's text and geometry but no `AXPress` action, and `NotificationCenter` cannot be granted through the automation permission path (it is not in the application index). This is sensible platform hardening, not a defect — but it means every data point for this variant needs a human click, which is why the sample is small.

  **Bearing on the filed reports:** none of the above affects them. The `getDeliveredNotifications` race (FB24273686, crbug 370536109 comment) was measured independently of all of this and stands. But it remains true that the symptom which *started* this investigation is this variant, not the one filed.

## Possibly related, unconfirmed / 可能相关但未确认

A session on **2026-08-04** (beta4 era) recorded the same user-visible symptom on notifications that had **nothing to do with Chrome** — a Samsung T7 disk-eject prompt and a "DuoTranslator.app was prevented from modifying apps" prompt — described verbatim as "无法点击也无法右键关闭". **In that instance `killall usernoted` fixed it**, whereas in the case documented here it did not. So the two may share a root cause with different severities, or may be different bugs that look alike from the user's side. Recorded as a lead, not as evidence. A Finder notification reportedly got stuck at some point too; the unified log buffer no longer reaches back far enough to corroborate that one.

If this class does extend beyond Chrome, the framing above ("Chrome's helper exits") would be a *special case* of a more general `usernoted` response-routing defect — worth testing with any other app that delivers alert-style notifications from a short-lived helper process.

## Relationship to the older Sequoia "click doesn't navigate" bug / 与旧的 Sequoia「点击不跳转」bug 的关系

Superficially the same complaint as the long-running macOS 15 issue ([MacRumors thread](https://forums.macrumors.com/threads/chrome-notifications-not-clickable.2432947/), reported from Sequoia 15.1 beta in 2024-08 through at least 2025-03), which the reporter's own testing found fixed as of macOS 26 beta2. Whether the mechanism documented here is that bug returning or an unrelated regression that presents identically is unknown; no macOS 15 comparison data was collected.

## Open questions / 待定

1. ~~Why does the Alerts helper exit while its own notification is still outstanding?~~ — **answered:** `getDeliveredNotifications` returns empty for ~7–24 ms after `add()` completes on macOS 27 (0 ms on 26.6), and Chrome kills the helper on exactly that answer. See the measurement above.
2. ~~Why only ~50–60% of pushes?~~ — **answered from the source:** `CheckIfServiceCanBeTerminated()` is event-driven and is never called on *posting* a notification, so the check lands at an arbitrary offset from `add()` and only sometimes falls inside the ~15 ms window. See the table above.
3. Is the underlying OS defect "the notification is not actually delivered yet" or "it is delivered but the query serves a stale snapshot"? The probe cannot tell them apart, and they imply different fixes on Apple's side.
4. Does this affect **any** app whose alert-style notifications come from a short-lived helper, or is something Chrome-specific involved? (See the 2026-08-04 lead above.)
5. ~~What happens inside the `Search for url to launching …` path~~ — **answered:** it launches the helper via LaunchServices and the helper dies in ~100 ms (60 `appDeath` events for 61 clicks), because a Chromium helper cannot run standalone.
6. The one instance where right-click and swipe also died and a Chrome restart did not fix it — same bug or a second one? Its helper (pid 87903) was alive for 165 s, which does **not** fit the mechanism above, so it is likely something else.
7. Was the equivalent path broken in earlier 27 betas (beta1–3)? Only beta4 and beta5 were tested.
