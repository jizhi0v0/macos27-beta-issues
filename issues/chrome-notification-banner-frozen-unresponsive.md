# Clicking a Chrome alert-style notification does nothing: `usernoted` receives the click but silently drops it once the Alerts helper has exited
# 点击 Chrome 的 alert 样式通知没有任何反应：`usernoted` 收到了点击，但因 Alerts helper 已退出而静默丢弃

> 🔗 **Track / 关注此问题:** [#26 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/26)
>
> 🧭 **Landed here from "clicking a notification does nothing"?** Classify the failure first — [notification-click-failure-taxonomy.md](notification-click-failure-taxonomy.md) tells the three shapes apart from `usernoted`'s log in one command. This file covers **A** (filed) and **C**; the freeze is [#27](notification-banner-inert-except-close.md).
| | |
|---|---|
| **Status** | 🔴 **the OS-side window is still there on 27.2 beta3 `26B5101f`** (2026-10-07) — `tools/un-delivered-race-probe`: **0/8** visible at 0 ms, **0/8** at 5 ms, 4/8 at 10 ms, 7/8 at 15 ms, 8/8 at 25 ms; first-visible min 5.91 / **median 11.62** / max 17.64 ms (27.2 b2 9.70; macOS 26.6 0.01–0.03 ms). ⚠️ The precondition, not the click symptom: Chrome is now **`155.0.8059.40`** and its side was **not** re-checked. See [`../baselines/27.2-beta3-26B5101f/`](../baselines/27.2-beta3-26B5101f/README.md). Prior: 🔴 **the OS-side window is still there on 27.2 beta2 `26B5091g`** (2026-09-25) — `tools/un-delivered-race-probe`: **0/8** visible at 0 ms, 3/8 at 5 ms, 8/8 at 25 ms; first-visible min 7.28 / **median 9.70** / max 34.72 ms (beta7 8.36; macOS 26.6 0.01–0.03 ms). ⚠️ This is the precondition, not the click symptom: Chrome is now **`154.0.8037.58`** (beta7 retest: 152.0.7977.65) and its side was **not** re-checked. See [`../baselines/27.2-beta2-26B5091g/`](../baselines/27.2-beta2-26B5091g/README.md). Prior: 🔴 **not fixed on beta7 `26A5421a` + Chrome `152.0.7977.65`, and the trigger condition is narrower than this file said** (2026-08-27, corrected the same evening). The race is untouched (first-visible median **8.36 ms**; non-Chrome demo 7/7; Chromium's `OkayToTerminateService` and its six call sites unmodified upstream) and the controlled recipe still fails cleanly — **6 clicks → 6 `Received response`, 0 forwarded, 0 errors logged, the service worker's `notificationclick` never fired**. **What decides the outcome is whether any other Chrome notification is already outstanding**, not the origin and not whether relaunch recovery takes: across 5 beta7 samples with the starting state verified from the log, an **empty** delivered list gave a self-kill (49 / 61 / 157 ms) and a **non-empty** one gave survival (>5 min, ≥25 min), with `youtube.com` and `workers.dev` each appearing on both sides. An earlier HTTPS run that appeared to exonerate the real-domain case was **invalid** — an undismissed notification was still in the delivered store — and is retracted below. Practical consequence: leaving notifications in Notification Center **protects** you; keeping it clear **exposes** you. See *Follow-up the same evening* below. Prior: 🔴 **not fixed on beta7 `26A5421a` + Chrome `152.0.7977.65` — but this file has been overstating the user-visible severity** (2026-08-27). Two things it had treated as one, measured three hours apart on the same machine and disagreeing: **(a) the race is untouched** — first-visible latency median **8.36 ms** against beta6's 8.07, the non-Chrome demo **7/7**, and Chromium's `OkayToTerminateService` plus its six `CheckIfServiceCanBeTerminated()` call sites are unmodified upstream; the controlled recipe still fails cleanly (**4 clicks → 4 `Received response`, 0 forwarded, 0 errors logged, and the service worker's `notificationclick` never fired**). **(b) real YouTube notifications do not hit it** — pairing every Alerts-helper `CHECKIN` with its next `appDeath` across the entire retained archive gives **6 real YouTube notifications on beta7, 0 user-visible failures**, including one (08-27 13:42:48) where the helper *did* self-kill in 157 ms and **relaunch recovery took**: a second instance came up 4.4 s later, presented the notification, and lived 1 h 43 m. The discriminator is therefore not whether the helper self-kills but **whether recovery takes** — and why it takes for real Chrome and never for the harness is open. See *Re-test 2026-08-27* below. Prior: 🔴 **still present as of 2026-08-23, verified under controlled conditions on Chrome `151.0.7922.174`** — after several days of casual use produced no dead clicks (2026-08-19→08-22) and the reporter suspected Chrome had fixed it, a same-day re-test settled it the other way: the non-Chrome demo hit the race 7/7, and #27's controlled recipe on real Chrome reproduced shape A exactly (2 clicks received by `usernoted`, 0 forwarded, and — new this round — the service worker's own server-side click log stayed empty, proving `notificationclick` never fired). The Chromium tracker shows no developer response and no code change since the reporter's own #26/#27. See [the 2026-08-23 re-verification](#controlled-re-verification-2026-08-23-shape-a-still-reproduces-cleanly--ruling-out-chrome-fixed-it--2026-08-23-受控复测shape-a-依然干净复现排除chrome-修复的猜测). Prior: 🔴 **still present on beta6 `26A5416b`, window roughly halved** (2026-08-20) — the probe measures first-visible latency at **7.5–9.8 ms, median ~8.1** against beta5's 7.1–23.7 / median 15.4 and macOS 26.6's 0.01–0.03 ms. Still **~270× 26.6**, so the defect is **not fixed**. ⚠️ The narrower window does **not** translate into reliably working clicks: on this same build **2026-08-19 recorded 18 clicks, 0 forwarded** (shape A) while **2026-08-20 had two clicks work**. Shape A depends on whether Chrome's check lands inside the window *for that notification*, so the outcome varies per notification, not per build. See [the beta6 re-measurement](#re-measurement-2026-08-20--beta6-26a5416b--window-halved-not-closed). Prior: 🔴 **Root cause established and isolated to a system API, reproducible without Chrome** (2026-08-12). On macOS 27, `getDeliveredNotifications` returns an **empty array for ~7–24 ms after `add()` has already completed** (0 ms on macOS 26.6, 32 trials per OS) — and Chromium kills its Alerts helper on exactly that answer. Clicking a persistent/actionable Chrome web notification does nothing at all once `Google Chrome Helper (Alerts).app` has exited. `usernoted` **does** receive every click — it just has no live client left to forward it to, and neither relaunches one nor falls back, dropping the click with no error logged. Anything that respawns the helper (a new notification arriving, **reopening** Chrome) instantly un-sticks **every** backlogged notification at once. **Retested on beta6 `26A5416b` 2026-08-19: shape A unchanged — 18 clicks, 0 forwarded**, and the same session produced shape C's first age-measurable failure (62.6 min). See *Beta6 retest* below. |
| **macOS** | 🔴 27.0 beta5 `26A5406e` — hits roughly **4 of 7** real web-push notifications. Also seen on beta4 `26A5388g`. 🔴 27.0 beta6 `26A5416b` — **18 clicks, 0 forwarded** (2026-08-19). 🟢 **macOS 26.6 `25G72` control: 9/9 clean** on the same harness, same Chrome build, same account — and its Alerts helper stays alive while a notification is outstanding (7+ min observed), which is exactly what macOS 27 fails to do. 🔴 27.0 beta7 `26A5421a` — controlled recipe **4 clicks, 0 forwarded** (2026-08-27), but **6 real YouTube notifications, 0 user-visible failures** on the same build |
| **Component** | Apple `usernoted` (notification response routing) ↔ `Google Chrome Helper (Alerts).app` |
| **Chrome** | `151.0.7922.109` (Official Build) (arm64); the 2026-08-14 shape C measurements are on `151.0.7922.138`; the 2026-08-19 beta6 retest on `151.0.7922.170`; the 2026-08-23 controlled re-verification on `151.0.7922.174`; the **2026-08-27 beta7 re-test on `152.0.7977.65`** |
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
| **C** | ✅ | ✅ | work | inside Chrome, after delivery — matches [crbug 370536109](https://issues.chromium.org/issues/370536109). **Measured 2026-08-14: the discriminator is the notification's age, not its content** — see *Shape C, measured for the first time* below |

**A is not a freeze.** Only activation fails; right-click and swipe behave normally. **B is the freeze** — the whole banner stops responding except its `✕`, and it is the symptom that originally started this investigation. Earlier revisions of this file used "stuck"/"frozen" loosely for both; that was sloppy.

### A reliable recipe for shape A / shape A 的可靠复现配方

Shape A was originally hit ~4 times in 7 pushes, seemingly at random. The missing variable was the **service worker's running state**, which was never controlled — the test page stayed open in every early run, keeping the SW warm and the Alerts helper alive. Controlling it makes the failure land:

1. subscribe a page to Web Push, then **close the tab**;
2. wait until `chrome://serviceworker-internals` shows that origin's worker `Running Status: STOPPED` (a push wakes it, so re-check ~60 s after the push — it stays `RUNNING` for a while);
3. send a push and leave the notification alone;
4. click it.

Measured on beta5 `26A5406e` with the SW confirmed `STOPPED`: **15 clicks → 15 `Received response`, 0 forwarded**, `Google Chrome Helper (Alerts)` not running, and the service worker's own server-side probe never pinged. RunningBoard shows the helper dying the same second it was spawned (`13:31:37 Acquiring → proc_exit → appDeath`), then one `appDeath` per subsequent click.

This is worth adding to the filed reports: it converts "roughly half the time" into a procedure.

### Shape C, measured for the first time: notification **age** is the discriminator, not content / 首次量化 shape C：判别式是通知的「年龄」，与内容无关

Shape C had only ever been asserted from the negative (clicks that were forwarded yet did nothing). On **2026-08-14**, beta5 `26A5406e`, Chrome `151.0.7922.138`, uptime 1 d 23 h, a set of five real YouTube web-push clicks was captured where **four failed and one worked**, with the OS side identical in all five.

**All five were received *and* forwarded to a live helper**, and the record was torn down cleanly each time:

| click | tag (`req` after `p#https://www.youtube.com/#1`) | what it was | `Received` → forwarded | `_removeDelivered` | navigated? |
|---|---|---|---|---|---|
| 09:45:37.069 | `iI1XBeAbCGA` | video *"iOS 26.6.1 RC is Out! - What's New?"* | ✅ → pid 46144 | +17 ms | ❌ |
| 09:45:38.180 | `UCTJJX_LQcDED7MZbt9OSeQQ` | a channel | ✅ → pid 46144 | +48 ms | ❌ |
| 09:45:38.966 | `UCTJJX_LQcDED7MZbt9OSeQQ` | same, clicked again | ✅ → pid 46144 | — | ❌ |
| **09:47:49.197** | **`ANDl5Tkru7g`** | **video *"What does AI actually know about you?"*** | ✅ → pid 46144 | +34 ms | **✅** |
| 09:51:44.718 | `UCD_cg9Tak9SvlPHRsWxUIpA` | channel *大耳朵TV* | ✅ → pid 46144 | +26 ms | ❌ |

The helper was **not** the variable: pid 46144 had been alive since the previous evening 21:45 — **12 hours** — and served all five.

**Content is not the variable either.** All five carry a byte-identical `staticCategory:"<LEGACY options=(legacyBehavior, hiddenPreviewShowsTitle) …>"` and an identical `<response action: contents actIdent: foreground: true>` (plain activation, not the `Settings` button). The `req` tag comes in two shapes — an 11-char video ID and a 24-char `UC…` channel ID — but the **success shares its shape with a failure** (`ANDl5Tkru7g` vs `iI1XBeAbCGA`), so tag shape is falsified as a discriminator.

**What does separate them is how old the notification was.** Searching every `Presenting` event `usernoted` logged in the 8 h the buffer reaches back (earliest line 01:57:53), exactly one of the five appears:

```
09:47:45.506  Presenting <… AlertNotificationService … #1ANDl5Tkru7g …>
09:47:49.197  Received response … sent to NSUserNotification client … pid: 46144   ← +3.69 s, navigated
```

The other four have **no `Presenting` record in 8 hours** — they were backlogged Notification Center rows, delivered overnight, and were clicked out of the stacked NC panel. So: **freshly presented banner (3.7 s old) works; rows sitting in Notification Center for 8+ hours are activated, consumed, and dropped.**

**Candidate mechanism, unverified.** An overnight push's service worker has long since been reclaimed, so Chrome cannot replay `notificationclick` against it, while the 09:47 notification's SW had just been woken by its own push and was still warm. This is consistent with everything above but is *not* measured — confirming it needs [`tools/webpush-repro/`](../tools/webpush-repro/)'s server-side receipt with notification age as the controlled variable.

**This gives shape C its first actionable recipe:** let a batch of web-push notifications accumulate overnight, then click them the next morning.

**Do not conflate with [#27](notification-banner-inert-except-close.md).** That issue's one clean crossover runs the *opposite* way (Reminders: 0/5 as a banner, then 1/1 as an NC row). Here every click reached `usernoted`; there none did. Same user-visible complaint, opposite log signature.

**Corollary, and a correction to how these logs were read earlier in this file.** `sent to NSUserNotification client` proves only that `usernoted` handed the response to a live registered client — **it does not prove the user-visible navigation happened.** Four of the five clicks above have that line and did nothing. Wherever the forwarding line is used as a success signal, it establishes the OS half only.

### The last click of that set: the response and the helper's own exit raced / 同一组的最后一次点击：投递与 helper 自杀撞车

Worth recording separately, because it does not fit the mechanism filed above. The 09:51:44 click was forwarded to a helper that had been alive 12 hours, and then:

```
09:51:44.718  usernoted: Received response … sent to NSUserNotification client … pid: 46144
09:51:44.744  usernoted: _removeDelivered: Removing [9B7CFD8E-…]                      (+26 ms)
09:51:44.754  runningboardd: [anon<Google Chrome Helper (Alerts)>(501):46144] termination reported by proc_exit   (+36 ms)
```

The click **killed the helper that was serving it.** The removal at +26 ms emptied the store, `OnNotificationAction()` fired `CheckIfServiceCanBeTerminated()`, `getDeliveredNotifications` now *legitimately* returned empty, and the helper exited 10 ms later. No Alerts helper was running afterwards.

This is the `OnNotificationAction()` self-inflicted path already flagged above, but one step worse than predicted there: it was expected to kill a *neighbouring* notification that was still inside its invisibility window; here it terminated the client mid-flight on **the very click that triggered it**. Note this needs no OS race at all — the empty answer was correct.

**Caveat:** the mojo hop from helper to browser process is not instrumented, so "the helper exited before relaying it" is a plausible 36 ms window, not a proof. n=1.

### Beta6 retest, 2026-08-19: shape A unchanged, and shape C's first age-measurable failure / beta6 复验：A 型原样存在，C 型首次拿到年龄可测的失败样本

macOS 27.0 beta6 `26A5416b`, Chrome `151.0.7922.170`, `usernoted` pid 694 (uptime 6 h 35 m). One real YouTube subscription push (`Sarah Li — A Day in The Life of a Software Engineer`, id `A44A-0492`, `req: r|Default|p#https://www.youtube.com/#1growth-subscription-notification`), presented **19:14:09.525**. It was clicked in three separate episodes on the same record, and the only variable across them is whether the Alerts helper was alive:

| episode | Alerts helper | clicks (`Received response`) | forwarded | shape |
|---|---|---|---|---|
| 19:49:56 → 19:50:08 | dead | **7** | **0** | A |
| 20:15:01 → 20:15:12 | dead (Chrome fully quit) | **11** | **0** | A |
| **20:16:47** | **alive, pid 13035** | **1** | **1** | **C** |

**Shape A is unchanged.** All 18 clicks produced `Launching com.google.Chrome.framework.AlertNotificationService … for legacy response` and none produced `sent to NSUserNotification client`. The relaunched helper's lifetime was measured directly for one of them (pid 84651):

```
19:50:08.1159  launchd:         [gui/501/application.com.google.Chrome.framework.AlertNotificationService…]
19:50:08.121   xpcproxy:        pid 84651
19:50:08.2014  launchservicesd: DEATH: Removing app App:"Google Chrome Helper (Alerts)" … pid=84651
```

**~85 ms**, against ~100 ms measured on beta5 — the same relaunch-and-die cycle. LaunchServices allocated seven ASNs (`0x452…0x458`) and destroyed all seven.

**The `appDeath` discriminator still holds on beta6 — but it is `loginwindow`'s line, not `usernoted`'s.** A claim that it had stopped firing was published here briefly on 2026-08-19 and is **retracted**: it came from grepping only `process == "usernoted"`. The line is emitted by `loginwindow` as `CAS notification for appDeath for com.google.Chrome.framework.AlertNotificationService with asn: … Google Chrome Helper (Alerts).app`, and counted over the two episodes it is **exactly one per click — 7/7 and 11/11**. The death is also visible in `launchservicesd` as `DEATH: Removing app App:"Google Chrome Helper (Alerts)"`. Query it as:

```bash
/usr/bin/log show --start "<t0>" --end "<t1>" --info --debug --predicate 'process == "loginwindow"' \
  | grep -c "appDeath for com.google.Chrome.framework.AlertNotificationService"
```

(`Failed to source application bundle`: 0 occurrences, consistent with it having been falsified as noise.)

**Shape C: a failure at 62.6 minutes, with its `Presenting` record intact.** With the helper alive, the 20:16:47 click went through the OS cleanly end to end:

```
20:16:47.029065  Received response <… AlertNotificationService … A44A-0492 …>
                 <response action: contents actIdent:  foreground: true text: nil>
                 → sent to NSUserNotification client <ClientConnect: … com.google.Chrome.framework.AlertNotification…>
20:16:47.034629  _removeDelivered:  Removing [0EE56AA1-…]          (+5.6 ms)
20:16:47.034812  _removeDisplayed:  Removing [0EE56AA1-…]
```

**User-observed outcome: Chrome came to the front, and no tab opened and no navigation happened.** So the `foreground: true` activation was honoured and only the `notificationclick` navigation was lost. Chrome had been running at click time, so "the app had to cold-launch and missed it" is not available as an explanation here.

Why this data point matters: it **separates notification age from log-buffer absence**, which were confounded on 2026-08-14. There, the four failures had *no* `Presenting` record anywhere in the 8 h buffer, so "old" and "unlogged" could not be told apart. Here the record is **in the buffer, fully logged**, and the click still failed at an age of

```
Presenting 19:14:09.525  →  click 20:16:47.029  =  62 min 37.5 s  (3757.5 s)
```

against the one working click's 3.69 s. That is consistent with the unverified service-worker-reclaimed hypothesis and rules out the buffer artefact — it is **not** a confirmation of the mechanism, which still needs [`tools/webpush-repro/`](../tools/webpush-repro/) with age as the controlled variable.

The helper exited again once it had handled the response (gone by 20:17:04), so any remaining backlog reverts to shape A.

**Shape B ([#27](notification-banner-inert-except-close.md)) was not seen in this session**, consistent with the reporter's own impression that nothing felt frozen. That is **not** evidence it is fixed — B has never been producible on demand, so its absence from one session carries no weight.

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
- **reopen Chrome** — see the correction below.

Both un-stick *all* pending notifications at once.

**Corrected on beta6, 2026-08-19: the quit half of "quit and reopen" does nothing, and has a side effect.** Measured directly: `osascript -e 'quit app "Google Chrome"'` left the helper dead and the notification stuck (11 further clicks, 0 forwarded, with Chrome not running at all). `open -a "Google Chrome"` then respawned the Alerts helper **on its own** within seconds (pid 13035) without any notification arriving. So the working step is the **reopen**. Worse, the quit **cleared 7 of the 8 outstanding Chrome notifications** — every banner-style one registered under `com.google.Chrome` — leaving only the alert-style record under `com.google.Chrome.framework.AlertNotificationService`. Quitting Chrome to un-stick one notification therefore destroys the others. If Chrome is already running, prefer waiting for the next notification, or open a page that pushes one.

**And the reopen itself races against the notification, measured 2026-08-19 22:09.** A freshly spawned Alerts helper calls `removeDeliveredNotifications` on startup, which can delete the very notification you were trying to recover:

```
22:09:20.338  loginwindow appDeath  com.google.Chrome                       ← quit
22:09:34.276  usernoted: Request from <LegacyConnection identifier: com.google.Chrome.framework.AlertNotificationService…>
              … removeDeliveredNotifications → _removeDelivered: Removing [F038293F-…]   ← the notification is gone
22:09:37.415  loginwindow appDeath  …AlertNotificationService               ← that helper exits
```

No click and no user action were involved — an outstanding alert-style record was destroyed ~14 s after the reopen. Contrast the 20:16 episode the same evening, where the click landed ~40 s after the helper appeared and **was** forwarded. So the reopen is a race, not a reliable recovery: **click immediately once the helper appears, or the notification may be deleted instead of delivered.** n=2, mechanism not established — "the helper clears stale alerts at startup because the browser has no matching state yet" is a plausible reading of the `removeDeliveredNotifications` call, not a measured one. Note that restarting the notification daemons does **not** help (see table above) — which is worth stating explicitly, because that is the usual folk remedy for stuck banners, and it was the remedy that worked for a superficially identical problem on 2026-08-04 (see below).

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
8. **Is shape C caused by the notification's age, and if so via the service worker being reclaimed?** The 2026-08-14 set (4 dead ≥8 h old, 1 live at 3.7 s, OS side identical in all five) makes age the only surviving discriminator, but the SW-reclamation mechanism is untested. Controlled A/B with `tools/webpush-repro/`'s server-side receipt would settle it — and would also answer whether this is a macOS 27 issue at all, since nothing in the evidence points at the OS.
9. Does the 09:51:44 pattern — the click's own `_removeDelivered` emptying the store and terminating the helper mid-flight — reproduce? If it does, it is a Chromium bug needing no OS race, and Chromium can fix it by not running the termination check on the same notification it is currently dispatching.

## Re-measurement 2026-08-20 — beta6 `26A5416b` — window halved, not closed

Prompted by the reporter noticing that clicking a YouTube (Chrome) notification **worked**, twice
in a row — the first positive clicks since this was opened. `usernoted` confirms Chrome's Alerts
helper was alive and healthy at the time:

```
10:25:21.465  [delete, [id=C7A3-CBD7,
              bundle=com.google.Chrome.framework.AlertNotificationService],
              Time elapsed=0.001 sec]: NotificationRequest: Completed
```

Two working clicks prove little about a ~15 ms race, so the probe in
[`tools/un-delivered-race-probe/`](../tools/un-delivered-race-probe/) was rebuilt and run — it
measures the API directly, with no Chrome involved.

| | macOS 26.6 `25G72` | beta5 `26A5406e` | **beta6 `26A5416b`** |
|---|---|---|---|
| first-visible (serial poll) | 0.01–0.03 ms | 7.1 / **median 15.4** / 23.7 ms | **7.5 / median 8.1 / 9.8 ms** |
| visible at 0 ms | 16/16 | 0/16 | **0/8** |
| visible at 5 ms | 16/16 | 0/16 | **1/8** |
| visible at 10 ms | 16/16 | 5/16 | **8/8** |
| visible at 25 ms | — | 16/16 | 8/8 |

**The defect is not fixed.** `getDeliveredNotifications` still returns an empty array for ~8 ms
after `add()` has already called back — about **270×** macOS 26.6 — and `N(n=0)` is precisely
Chromium's condition for killing the Alerts helper. What changed is the *size* of the window:
roughly halved, and fully clear by 10 ms where beta5 needed 25 ms.

**What it does not explain is the click outcome.** On this same build, 2026-08-19 recorded
**18 clicks and 0 forwarded** — shape A in full — and 2026-08-20 had **two clicks work**. Whether
a given notification ends up in shape A depends on where Chrome's liveness check falls relative to
*that notification's* window, so a smaller window shifts the odds per notification and settles
nothing per build. Two working clicks and eighteen dead ones are both consistent with an ~8 ms
race; neither is evidence about the other.

**Caveats:** 8 trials per phase on beta6 against 16 on beta5, one pass, same machine. The
macOS 26.6 column is the earlier cross-machine comparison and carries its original hardware
confound.

### Reporter's ongoing use, 2026-08-19 → 08-22: no dead clicks noticed / 日常使用未再撞见

Reporter's own words, unprompted: normal YouTube-notification clicks have been navigating
correctly, with no click-did-nothing case noticed, across the ~3 days since beta6 was installed.
Explicitly **not** a controlled test — this is casual daily use, not the overnight/idle-queue
recipe that reliably produces shape C (see above), and it says nothing about shape A odds either:
the race measurement above still puts the window at ~8 ms on this exact build, unchanged in kind
from beta5. A subjective non-observation over a few days of ordinary use is weak evidence by
itself; recorded here as a data point, not as a resolution — absence of a noticed failure is not
absence of the defect.

**Tool fix:** the probe's README said results land in `~/undverify.log`; the binary actually
writes `~/undverify_run.log`. Corrected — the wrong path reads exactly like a run that produced
nothing.

2026-08-20 复测:竞态**仍在**,但窗口约减半 —— `add()` 回调后 `getDeliveredNotifications` 仍返回空数组
约 **8 毫秒**(beta5 中位 15.4ms,macOS 26.6 为 0.01–0.03ms),仍是 26.6 的约 **270 倍**,**未修复**。
窗口变窄使 Chrome 的检查落入其中的概率下降,这解释了报告者连续两次点击成功,但不构成修复。

### Controlled re-verification, 2026-08-23: shape A still reproduces cleanly — ruling out "Chrome fixed it" / 2026-08-23 受控复测:shape A 依然干净复现,排除"Chrome 修复"的猜测

After several more days of casual use (2026-08-19 → 08-22, recorded above) with no dead click
noticed, the reporter's working hypothesis shifted to **Chrome having fixed it**, reasoned from
timing: the bug was hit right after the beta6 upgrade, then stopped appearing over the following
days on the same OS build — so, absent a macOS-side control, a Chrome update looked like the only
variable left. `Google Chrome.app`'s installed version had in fact moved from `151.0.7922.170`
(the build used for the 2026-08-20 probe measurement above) to `151.0.7922.174` in that window,
which is consistent with an update having happened, though not with any specific fix — checking
[crbug 370536109](https://issues.chromium.org/issues/370536109) the same day found **no developer
response since the reporter's own #26/#27** (posted 2026-08-12): status is still `New`, no
assignee, no `Fixed By Code Changes`, and the only Google comment since (#25, 2026-02-04) says the
Notifications team is in "maintenance mode only, considering only P0s and P1s" for this P2/S2 bug.

Three same-day checks, run to test the hypothesis directly rather than extend the anecdote:

1. **Non-Chrome demo re-run** ([`tools/notifdemo-nonchrome/`](../tools/notifdemo-nonchrome/)),
   macOS 27.0 beta6 `26A5416b`, 20:29–20:31: **7 / 7** trials still landed on `count=0` (the race
   condition itself, no Chrome code involved), replied 0.27–7.41 ms after `add()`'s completion
   fired — same shape as the original 14/14 on beta5 and the 08-20 probe's ~8 ms window. The OS
   defect is unchanged today, independent of whatever Chrome shipped.

2. **Controlled Chrome recipe re-run**, following #27's procedure exactly (subscribe → close the
   tab → wait for `chrome://serviceworker-internals` to show that origin's SW `STOPPED` → send one
   real push with `requireInteraction: true` + an `actions` entry → click), on the actually
   installed `Google Chrome.app` **151.0.7922.174**, real macOS notification, real human click:

   | | result |
   |---|---|
   | notification delivered via | `AlertNotificationService` (the Alerts path, matching Chrome exactly) |
   | Alerts helper running at click time | no |
   | `usernoted` "Received response" | **2** |
   | "sent to NSUserNotification client" | **0** |
   | `loginwindow` `appDeath` for `AlertNotificationService` | **3** |

   Shape A, unchanged.

3. **A stronger corroboration than earlier sessions had**: the harness's service worker logs every
   `notificationclick` server-side to a KV store, independent of anything visible on screen. After
   the click, the store held only `seq:retest0823` and `sub:retest0823` — **no `click:*` key was
   ever written**, proving the page's `notificationclick` handler never fired at all, not merely
   that nothing appeared to happen.

> ⚠️ **Superseded in part, 2026-08-27.** The conclusion below — that the defect was intact — still holds. Its *explanation*, that casual clicking keeps the service worker warm, does **not**: four of six real YouTube notifications on beta7 spawned the Alerts helper fresh, so the discriminator is not SW warmth but whether relaunch recovery takes. See *Re-test 2026-08-27* below.

**Conclusion: the several days of non-reproduction were not evidence of a fix.** Casual clicking
never controlled for the one variable this bug depends on — an isolated notification with a
long-idle service worker (the state casual YouTube-notification clicking rarely produces on its
own, since the tab or a recent visit tends to keep the SW warm, exactly per the *reliable recipe*
recorded earlier in this file) — so days of ordinary use landing outside the failure window says
nothing about whether the window still exists. Put under the known trigger conditions today, on
the current Chrome build, it reproduced exactly as before. **Status unchanged: not fixed.** The
reporter's own assessment after seeing this: "确实很奇怪，我再观察一下" (genuinely puzzling, will
keep watching) — logged here as an open observation, not a resolution.

### Re-test 2026-08-27 — beta7 `26A5421a` + Chrome `152.0.7977.65`: the race is untouched, the controlled recipe still fails 4/4, and **real YouTube notifications do not hit it** / beta7 复测：竞态原样，受控配方 4/4 依旧失败,但**真实 YouTube 通知打不中**

This is the round that separates two things this file had been treating as one: **the race still
existing** and **the user still losing clicks**. Both were measured today, on the same machine,
three hours apart, and they disagree.

**Both variables moved since the 2026-08-23 re-verification above, and both were re-pinned:**
macOS 27.0 **beta7 `26A5421a`** (kernel `xnu-13432.1.9~3`, unchanged from beta6) and Chrome
**`152.0.7977.65`** — a major-version bump from the `151.0.7922.174` that 08-23 tested. A retest
that pins only the OS build is not a retest for this issue.

#### 1. The OS side did not change / OS 侧没变

[`tools/un-delivered-race-probe`](../tools/un-delivered-race-probe/), phase B (chained serial
polling, first-visible latency after `add()`'s completion), n=8 per build:

| build | min | **median** | max |
|---|---|---|---|
| beta5 `26A5406e` | 7.12 ms | **18.62** | 23.72 ms |
| beta6 `26A5416b` | 7.52 ms | **8.07** | 9.77 ms |
| **beta7 `26A5421a`** | 4.30 ms | **8.36** | 11.01 ms |

The beta5→beta6 halving was real; **beta6→beta7 did not move.** The non-Chrome demo
([`tools/notifdemo-nonchrome/`](../tools/notifdemo-nonchrome/)) agrees: **7 / 7** trials returned
`count=0` with the query issued 0.38–0.83 ms after `add()`'s completion had already fired.

#### 2. Chromium's side did not change either / Chromium 侧也没变

Checked against the upstream mirror rather than inferred from behaviour:

- `chrome/services/mac_notifications/mac_notification_service_un.mm` — last **functional** change
  `6c6b0ab49` (2026-06-09); the only later commit, `f977df972` (2026-07-01), adds rollout metrics.
  `OkayToTerminateService` still returns `notifications.empty()`.
- `chrome/browser/notifications/mac/notification_dispatcher_mojo.cc` — **untouched since
  `55696fc18` (2024-10-30)**; the six `CheckIfServiceCanBeTerminated()` call sites tabulated
  earlier in this file are all still there.

So Chrome 152 changed neither the predicate nor when it is asked.

#### 3. The controlled recipe still fails, cleanly / 受控配方依然干净失败

Recipe exactly as recorded above — subscribe, close the tab, leave the service worker idle 3 min,
send one real push with `requireInteraction: true` + an `actions` entry, then click. Harness served
from `http://localhost:8799` (8787 was occupied), push sent from Node because workerd's `fetch`
does not honour the system proxy.

```
15:55:01.005  launchservicesd  CHECKIN:0x0-0x150150 80345 com.google.Chrome.framework.AlertNotificationService
15:55:01.050  usernoted        create  [id=0D7B-4D85, bundle=…AlertNotificationService]
                               req:"r|Default|p#http://localhost:8799/#1repro-beta7-1-1787817299880"
15:55:01.054  loginwindow      appDeath for com.google.Chrome.framework.AlertNotificationService
                               .../Versions/152.0.7977.65/Helpers/Google Chrome Helper (Alerts).app
15:55:01.152  usernoted        Delivering / Presenting  ident:"0D7B-4D85"
```

The helper died **49 ms after the notification was created and 98 ms before it was presented** —
the notification reached the screen with no process left to receive its click. A 0.1 s `ps` poll
saw it appear at +1.09 s and vanish by +1.24 s. Then four clicks:

| | result |
|---|---|
| clicks (15:58:09.868 / 11.035 / 11.615 / 12.702, then 15:59:34.601 and 15:59:35.2xx — all `ident:"0D7B-4D85"`) | **6** |
| `usernoted` "Received response" | **6** |
| "sent to NSUserNotification client" | **0** |
| `Failed to notify application` | **0** — silent, no error logged |
| `appDeath` after each click | **6** (+125 / +90 / +90 / +96 ms for the first four) |
| service worker's server-side `click:*` key | **never written**; no `/api/click-log` request reached the worker |

Shape A, unchanged, and better corroborated than any earlier session: every click respawned the
helper and it self-killed again within ~100 ms, so **macOS's relaunch recovery fired four times and
never took**.

#### 4. But the machine's own logs say real YouTube notifications are fine / 但日志说真实 YouTube 通知没事

The reporter's standing objection — "YouTube 的通知确实没问题" — turns out to be checkable against
`loginwindow`/`launchservicesd`/`runningboardd`, by pairing every Alerts-helper `CHECKIN` with its
next `appDeath` across the retained archive. beta7 was installed **2026-08-24 23:33** (`InstallHistory.plist`), so every row below is beta7:

| real YouTube notification | helper `CHECKIN` | next `appDeath` | helper lived | click would work |
|---|---|---|---|---|
| 08-25 09:58:33.259 | 09:58:33.195 | 10:01:13.618 | 2 m 40 s | ✅ |
| 08-25 11:45:48.281 | 11:45:48.219 | 12:06:28.736 | 20 m 40 s | ✅ |
| 08-25 14:25:15.730 | 14:25:15.687 | 08-26 13:35:50 | ~23 h | ✅ |
| 08-26 18:27:12.884 | 18:27:12.829 | none, until the 08-27 13:39 reboot | ~19 h | ✅ |
| 08-27 09:27:47.300 | **none** — reused the 19 h-old process | — | — | ✅ |
| 08-27 13:42:48 | 13:42:48.731 (pid 5037) | 13:42:48.888 | **157 ms — self-killed** | ✅ see below |

**Six real YouTube notifications on beta7, zero user-visible failures.** The last row is the
interesting one: the race *did* fire on a real YouTube notification, and recovery worked —

```
13:42:48.731  CHECKIN   pid=5037
13:42:48.888  appDeath                       ← first helper self-kills, before the notification is presented
13:42:53.115  CHECKIN   pid=5140             ← the system relaunches one 4.4 s later
13:42:53.264  usernoted Delivering/Presenting  ident:"A44A-0492"  p#https://www.youtube.com/#1growth-subscription-notification
              …next appDeath not until 15:26:13 — the second instance lived 1 h 43 m
```

That is **condition B** from the non-Chrome demo table above, occurring in the wild: identical
race, identical self-kill, and the click still lands because the relaunched instance stayed alive.

> ⚠️ **Superseded, later the same day.** "Relaunch recovery takes" is *not* what separates real
> YouTube notifications from the harness — see *Follow-up the same evening* below. The second
> helper here survived because its termination check landed outside the ~8 ms window, not because
> recovery is reliable; and rows in the table above cannot be checked for the confound that
> actually predicts the outcome, because the relevant records have aged out of the archive.

#### 5. What this falsifies, including in this file / 这一轮推翻了什么(包括本文自己的说法)

- **"YouTube's notifications are banner-style, so shape A never applied"** — no. They are delivered
  by `com.google.Chrome.framework.AlertNotificationService`, and the `NotificationRecord` is
  identical in shape to the harness's, down to
  `staticCategory:"<LEGACY options=(legacyBehavior, hiddenPreviewShowsTitle) actions=[…]"` and
  `source:"FF14E171"`. Same path, same category.
- **"Another Chrome notification was outstanding, so the query returned non-empty"** — no. Between
  08:00 and 09:30 on 08-27 there was **exactly one** Chrome notification, the YouTube one. It was
  as isolated as the harness's.
- **The 2026-08-23 entry's explanation above — "the tab or a recent visit tends to keep the SW
  warm" — is wrong and is superseded by this section.** Four of the six YouTube notifications
  spawned the helper *fresh*, which is not what a warm, helper-retaining session looks like. The
  discriminator is not whether the helper gets spawned; it is **whether relaunch recovery takes**.
- Consequently the framing this file has used since 2026-08-12 — treating the recipe's hit rate as
  the real-world failure model — **overstates the user-visible severity on beta7**. The recipe hits
  100 %; real use on this machine hit the race 1 in 6 and lost 0 clicks.

#### 6. Open, and honestly unresolved / 仍然未解

> ✅ **Answered later the same day, and the answer is "neither":** the origin is not the variable, and
> "recovery taking" is not the phenomenon. See *Follow-up the same evening* below.

**Why does relaunch recovery take for real Chrome and never for the harness?** Same Chrome build,
same OS build, same machine, under three hours apart, same notification path and category. Already
excluded: the delivery path, the category/actions payload, and whether another notification was
outstanding. **Not** excluded: the harness's origin is `http://localhost:8799` rather than
`https://www.youtube.com` (plaintext, loopback, non-default port), and whether Chrome had a live
window for that origin at push time. The obvious next experiment is to re-run the recipe from an
HTTPS origin on a real domain and see whether the second helper survives.

**The beta6 control, recovered — and it does not support "beta7 improved things."** An earlier
draft of this section claimed the archive began after the beta7 upgrade and that no beta6 organic
data survived. That was wrong on both counts: the archive reaches back to **2026-08-23**, and beta7
was installed **2026-08-24 23:33**, so 08-23 → 08-24 23:33 is beta6. Pairing `CHECKIN`/`appDeath`
against the YouTube notification timestamps in that window:

| beta6 real YouTube notification | helper `CHECKIN` | next `appDeath` | helper lived |
|---|---|---|---|
| 08-23 22:05:22.794 | 22:05:22.740 | 08-24 10:17:06.074 | ~12 h |
| 08-24 10:17:26.950 | 10:17:26.906 | 08-25 07:20:46.769 (i.e. through the upgrade reboot) | ~21 h |

Same shape as beta7: freshly spawned, and it survived. The only sub-second self-kills in the beta6
window are 08-23 20:42–20:44 — which is the *controlled re-verification session* recorded in the
previous section, not organic use. So **organic YouTube behaviour looks the same on beta6 and
beta7**, and this data gives no support to "beta7 fixed the real-world case." It also does not
reach back to 2026-08-19, when the reporter's beta6 failures actually occurred, so those remain
unclassified.

⚠️ **Retention caveat:** in the beta6 window the archive retains only `donotdisturb:BehaviorResolution`
records for those notifications — the `unc:application` `Delivering`/`Presenting` lines that the
beta7 rows rely on have aged out. The beta6 rows are therefore reconstructed from helper-lifecycle
plus DND timestamps, one step weaker than the beta7 rows.

#### Method notes / 方法记录

- `/usr/bin/log show --start X --end Y` **silently ignored `--end` when no `--predicate` was
  given** on beta7 — an 8-minute window request returned 1 h 50 m of records. With a predicate it
  honours both bounds (verified against a 1-minute window). Slice by timestamp afterwards, or
  always pass a predicate.
- [`tools/eco-replicate.sh`](../tools/eco-replicate.sh)'s flush-boundary artefact **recurred**
  despite the pinned `--start`/`--end` fix noted in its header: reps 2 and 3 returned byte-identical
  triples (6739 lines / 468 EIO / 32.5 anchors/s). Treat that run as n=2.
- [`tools/webpush-repro`](../tools/webpush-repro/) gained `send-push.mjs`: workerd's `fetch` does
  not use the system proxy, so `/api/push` hangs ~20 s against FCM behind one. The script sends the
  identical payload from Node via `web-push`'s `proxy` option. VAPID keys now live in
  `.dev.vars` (git-ignored).

2026-08-27 在 beta7 `26A5421a` + Chrome `152.0.7977.65` 上复测,把本文一直混为一谈的两件事拆开了:
**竞态是否还在**(还在:窗口中位 8.36 ms,与 beta6 的 8.07 无差别;非 Chrome demo 7/7;Chromium 的
判定式与六个调用点均未改动),与**用户是否还会丢点击**(受控配方下 4 次点击 4 收 0 转发、SW 的
`notificationclick` 完全没触发 —— 但**真实 YouTube 通知 6 条、用户可见失败 0 条**)。
关键差别不是 helper 会不会被拉起来自杀 —— 今天 13:42:48 一条真 YouTube 通知的 helper 就在 157 ms 内
自杀了 —— 而是**系统的重启兜底能不能生效**:真 Chrome 上 4.4 秒后第二个实例被拉起、呈现了通知、
活了 1 小时 43 分;harness 里连续四次点击各拉起一次、各自杀一次,兜底一次都没成。
据此,本文自 2026-08-12 起「按配方命中率描述现实严重性」的写法**高估了 beta7 上的用户可见严重性**;
上面 08-23 那节「tab 开着让 SW 保持热」的解释**是错的,以本节为准**。仍未解:为什么兜底对真 Chrome 生效、
对 harness 一次都不生效(未排除变量:harness 的 origin 是 `http://localhost:8799` 而非真 HTTPS 域名)。
另:日志 archive 只回溯到 08-24,彼时已是 beta7,**beta6 的现实对照数据已不存在**,故不对
「beta7 是否改善了现实表现」作任何断言。

### Follow-up the same evening: the origin hypothesis is falsified, and what actually predicts the outcome / 当晚追测：origin 假说被证伪，真正的判别式是投递列表是否为空

The section above closed with one named unexcluded variable — the harness serving from
`http://localhost:8799` rather than a real HTTPS domain — and the obvious experiment. It was run,
it produced a clean positive on the first try, **and that first result was wrong.** Recording the
whole sequence because the error is more instructive than the answer.

#### The first HTTPS run, and why it was invalid

Re-run of the recipe against the already-deployed
`https://notif-webpush-repro.jizhiovo.workers.dev` (same worker, same VAPID pair, nothing newly
published) at 16:38: the helper spawned at +1.29 s and was **still alive 5 minutes later**, the
click forwarded (`sent to NSUserNotification client` = 1), and the service worker's
`notificationclick` fired — the server-side `click:` key was written and Chrome navigated to
`/?clicked=…`. Every axis was the opposite of the localhost run. It looked decisive.

It was confounded. The localhost notification from 15:55 (`0D7B-4D85`) had **never been
dismissed** — its clicks were being dropped, so nothing ever closed it — and `usernoted`'s
delivered store still held it at 16:38. `getDeliveredNotifications` therefore returned a
**non-empty** array no matter where in the race the query landed, and the helper had no reason to
self-terminate. Origin had nothing to do with it.

Two method notes from that hour, both silent failures:

- reading `~/Library/Group Containers/group.com.apple.usernoted/db2/db` with
  `?mode=ro&immutable=1` **skips the WAL** and returns a stale snapshot — it reported the
  dismissed notification as still present. Copy `db`, `db-wal` and `db-shm` and query the copy.
- a preflight script written to prevent exactly this bug **passed a dirty state**, because its
  SQL errored (aggregate in `GROUP BY`), the output was empty, and empty was read as "nothing
  outstanding". Fail loudly on a non-zero sqlite exit; never treat empty output as a clean result.

#### The controlled re-run

With the delivered store verified empty (0 Chrome records across **all** bundles, no live helper),
the same HTTPS origin, same recipe:

```
16:56:01.815  launchservicesd  CHECKIN  64893 com.google.Chrome.framework.AlertNotificationService
16:56:01.868  usernoted        create   [bundle=…AlertNotificationService]
16:56:01.876  loginwindow      appDeath                     ← 61 ms after CHECKIN, 8 ms after create
16:56:01.976  usernoted        Delivering / Presenting      ← 100 ms AFTER the helper died
```

Identical in shape to the localhost run's 49 ms / 98 ms. **The origin is not the discriminator.**

#### Five samples on beta7 with the starting state verified from the log

Including one that arrived unprompted at 18:29 while a leftover test notification happened to be
outstanding — a natural experiment for the treatment condition, on a **real YouTube push**:

| | time | origin | Chrome delivered list before | helper | outcome |
|---|---|---|---|---|---|
| 1 | 13:42:48 | `youtube.com` | **empty** (`94FD-4A21` removed earlier) | fresh | **self-kill 157 ms**; a second helper 4.4 s later survived |
| 2 | 15:55:01 | `localhost:8799` | **empty** (`A44A-0492` removed; no Chrome creates 13:43→15:55) | fresh | **self-kill 49 ms**; 6 clicks, 0 forwarded |
| 3 | 16:38:28 | `workers.dev` | **non-empty** (`0D7B-4D85`, never dismissed) | fresh | **survived >5 min**; click forwarded, SW fired |
| 4 | 16:56:01 | `workers.dev` | **empty** (preflight-verified) | fresh | **self-kill 61 ms** |
| 5 | 18:29:26 | `youtube.com` | **non-empty** (row 3's leftover) | fresh | **survived ≥25 min** |

**The delivered-list state predicts the outcome 5/5. The origin predicts nothing** — `youtube.com`
appears on both sides and so does `workers.dev`. Both localhost rows are on the same side as an
HTTPS row, and both HTTPS rows land on opposite sides of each other.

#### The mechanism, stated more precisely than before

`OkayToTerminateService` returns `notifications.empty()`, and Chromium's six
`CheckIfServiceCanBeTerminated()` call sites fire at an arbitrary offset from `add()`. Those two
facts compose into a rule the earlier sections did not state:

- **Any other Chrome notification outstanding → the answer is non-empty regardless of when the
  check fires → the helper always survives.** Rows 3 and 5.
- **Delivered list empty → the answer depends entirely on whether the check lands inside the
  ~8 ms window.** Rows 1, 2, 4 — and row 1 shows both outcomes inside one incident: the first
  helper's check landed inside and it self-killed, the second helper's landed outside and it lived
  1 h 43 m. That, not "relaunch recovery is reliable", is why row 1 ended without a lost click.

So the trigger condition recorded earlier in this file — "an isolated notification with a
long-idle service worker" — is **incomplete in the way that matters**. The operative requirement is
**zero other Chrome notifications outstanding**, and the harness satisfies it by construction while
ordinary use frequently does not.

#### What this corrects in the section above

- The claim that **relaunch recovery taking** is what separates real YouTube notifications from the
  harness is **not supported**. It fitted row 1, but rows 3 and 5 show survival with no recovery
  involved at all, and the simpler predictor covers all five.
- The beta7 YouTube table's rows for 08-25 and 08-26 **cannot be checked for this confound**: the
  `NotificationsPipeline` `create` records have aged out of the archive for those days (a
  08-25 00:00→09:58 query returns 60 `com.google.Chrome` records and **zero** creates). Whether
  those helpers survived because the list was non-empty is therefore **unknown**, and the
  "0 user-visible failures" reading of that table should not be attributed to a mechanism.
- The click count for the 15:55 notification is **6, not 4** — 15:58:09.868 / 11.035 / 11.615 /
  12.702 plus 15:59:34.601 and 15:59:35.2xx, all on `0D7B-4D85`, all `Received response`, none
  forwarded, and no removal event ever logged for it.

#### The uncomfortable implication

A user who leaves notifications sitting in Notification Center is **protected** — the list is
never empty, so the helper never self-terminates. A user who keeps it clear is **exposed**. That
inverts the usual intuition and is worth stating in any report, because it also means the
reporter's own "YouTube notifications are fine" may be a property of their notification hygiene
rather than of the OS build. It is offered as the hypothesis the five rows support, not as
something separately tested.

2026-08-27 当晚追测:上一节点名的唯一未排除变量(origin 是 `http://localhost:8799` 而非真 HTTPS 域名)
被测了,**第一次就得到漂亮的阳性结果,而那个结果是错的**。16:38 那轮 HTTPS helper 存活 5 分钟以上、点击送达、
SW 触发 —— 但当时 15:55 那条 localhost 通知**从未被关掉**(它的点击一直在被丢弃,所以没有任何东西关掉它),
仍在投递列表里,于是 `getDeliveredNotifications` 无论落在竞态哪一段都返回非空。清空列表后用**同一个 HTTPS
origin** 重跑:CHECKIN 后 **61 ms** 自杀,与 localhost 的 49 ms 同形。**origin 不是判别式。**
beta7 上五个起点状态经日志验证的样本里,**投递列表是否为空 5/5 命中,origin 零预测力**
(`youtube.com` 和 `workers.dev` 各自在两边都出现过)。更准确的机制:**只要还挂着任何一条别的 Chrome 通知,
答案就恒为非空、helper 必然存活**;**列表为空时,结果完全取决于那次检查有没有落进约 8 ms 的窗口** ——
13:42 那次一个事件里两种结果都出现了(第一个 helper 落进窗口自杀,第二个没落进、活了 1 小时 43 分),
这才是它没丢点击的原因,而不是「兜底可靠」。因此上一节把「真实 YouTube 没事」归因于兜底生效**不成立**;
08-25/08-26 那几行更是**无法复核**(那两天的 `create` 记录已被日志保留策略淘汰)。
另:15:55 那条的点击次数是 **6 次**不是 4 次。**一个反直觉的推论**:通知堆着不清的人反而是安全的,
随手清空通知的人才暴露 —— 报告者「YouTube 通知没问题」有可能是其通知使用习惯的属性,而非 OS build 的属性。

## Re-measurement 2026-09-25 — 27.2 beta2 `26B5091g` — the window is still there

> **Clock position, because it decides what these numbers can be compared to.** macOS 27.2 beta2
> `26B5091g` was installed **2026-09-25 07:08:18 UTC** (`InstallHistory.plist`), two minutes after
> the 15:06:19 +0800 boot. The window is **T+1h54m → T+2h04m** with 32 apps running and the
> post-update reindex still active — matched to no earlier window, so log *volumes* are not
> presented as pairs. Kernel `xnu-13432.40.162~92` (release: `xnu-13432.1.9~1`). Raw capture:
> [`baselines/27.2-beta2-26B5091g/`](../baselines/27.2-beta2-26B5091g/README.md).

[`tools/un-delivered-race-probe`](../tools/un-delivered-race-probe/) (UNDVerify/v5, already
authorized, `auth=2 alertStyle=1 alertSetting=2`), run at T+2h08m. Raw:
[`race-probe.txt`](../baselines/27.2-beta2-26B5091g/race-probe.txt).

Phase A, visible at each offset after `add()`'s completion (n=8):

| 0 ms | 5 ms | 10 ms | 15 ms | 25 ms |
|---|---|---|---|---|
| **0/8** | 3/8 | 4/8 | 5/8 | 8/8 |

Phase B, first-visible latency (n=8):

| build | min | **median** | max |
|---|---|---|---|
| beta5 `26A5406e` | 7.12 ms | **18.62** | 23.72 ms |
| beta6 `26A5416b` | 7.52 ms | **8.07** | 9.77 ms |
| beta7 `26A5421a` | 4.30 ms | **8.36** | 11.01 ms |
| **27.2 b2 `26B5091g`** | 7.28 ms | **9.70** | 34.72 ms |

The 34.72 ms max is a single trial (134 polls); without it the max is 14.75 ms. The median is in
the beta6/beta7 band. **0/8 at 0 ms** is exactly Chromium's kill condition, `N(n=0)`.

⚠️ **What this does and does not cover.** Per this file's own framing, the probe is a worst-case
amplifier of the OS-side window, not a model of Chrome's cadence. Chrome has moved to
**`154.0.8037.58`** since the beta7 controlled re-verification (152.0.7977.65), and neither the
Chromium source nor the controlled recipe was re-run. So this re-confirms the **precondition** on
27.2 beta2; it says nothing new about the click symptom's hit rate. The status stays 🔴 because the
OS-side defect is positively still present.

2026-09-25 27.2 beta2 `26B5091g` 复测:探针 0 ms 时 **0/8** 可见,首次可见中位 **9.70 ms**(beta7 8.36),
OS 侧窗口仍在。Chrome 已升到 154.0.8037.58,Chrome 侧与点击症状本轮**未复测**。仍记 🔴。

## Re-verification 2026-10-07 — 27.2 beta3 `26B5101f` — the OS-side window is still there

> **Clock position, because it decides what these numbers can be compared to.** macOS 27.2 beta3
> `26B5101f` was installed **2026-10-07 12:22:37 +0800** (`InstallHistory.plist`) and booted at
> 12:26:01. This is a **post-boot** pass — the window is **T+13m → T+23m** with 22 apps running and
> the post-update reindex active — matched to no earlier window, so log *volumes* are not presented
> as pairs. Kernel `xnu-13432.40.177.0.3~56` (27.2 b2: `xnu-13432.40.162~92`). Raw capture:
> [`baselines/27.2-beta3-26B5101f/`](../baselines/27.2-beta3-26B5101f/README.md).

`tools/un-delivered-race-probe` (UNDVerify/v5, the installed copy), run at T+16m. Raw:
[`race-probe.txt`](../baselines/27.2-beta3-26B5101f/race-probe.txt).

**Phase A** — is the just-added notification visible after a fixed delay (8 trials each):

| | 0 ms | 5 ms | 10 ms | 15 ms | 25 ms |
|---|---|---|---|---|---|
| 27.2 b2 | 0/8 | 3/8 | 4/8 | 5/8 | 8/8 |
| **27.2 b3** | **0/8** | **0/8** | **4/8** | **7/8** | **8/8** |

**Phase B** — first-visible latency, 8 trials: min **5.91** / median **11.62** / max **17.64** ms
(27.2 b2 7.28 / 9.70 / 34.72; beta7 median 8.36, beta6 8.07; macOS 26.6 0.01–0.03 ms).

Still roughly 400–1,000× macOS 26.6. The median moving 9.70 → 11.62 ms on 8+8 trials is inside
the spread of earlier builds and is **not** read as a change either way.

⚠️ **This is the precondition only.** Chrome is `155.0.8059.40` (27.2 b2 retest: 154.0.8037.58); its
`OkayToTerminateService` side and the click symptom were not re-checked on this build.

**The status stays 🔴.**

2026-10-07 27.2 beta3 `26B5101f` 复测:0 ms 时 0/8 可见,5 ms 时 0/8,25 ms 时 8/8;首次可见中位数
**11.62 ms**(27.2 beta2 9.70,macOS 26.6 为 0.01–0.03 ms)。OS 侧窗口仍在;Chrome 155 侧未复查。仍记 🔴。
