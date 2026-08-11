# Clicking a Chrome alert-style notification does nothing: `usernoted` receives the click but silently drops it once the Alerts helper has exited
# 点击 Chrome 的 alert 样式通知没有任何反应：`usernoted` 收到了点击，但因 Alerts helper 已退出而静默丢弃

> 🔗 **Track / 关注此问题:** [#26 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/26)

| | |
|---|---|
| **Status** | 🔴 **Root cause established by controlled experiment** (2026-08-12). Clicking a persistent/actionable Chrome web notification does nothing at all once `Google Chrome Helper (Alerts).app` has exited. `usernoted` **does** receive every click — it just has no live client left to forward it to, and neither relaunches one nor falls back, dropping the click with no error logged. Anything that respawns the helper (a new notification arriving, quitting/reopening Chrome) instantly un-sticks **every** backlogged notification at once. |
| **macOS** | 🔴 27.0 beta5 `26A5406e` — hits roughly **4 of 7** real web-push notifications. Also seen on beta4 `26A5388g`. 🟢 **macOS 26 control: 7/7 clean** on the same harness, same Chrome build, same account |
| **Component** | Apple `usernoted` (notification response routing) ↔ `Google Chrome Helper (Alerts).app` |
| **Chrome** | `151.0.7922.109` (Official Build) (arm64) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max (27 beta5) vs. a second Mac on macOS 26 (control) |
| **Report** | Apple Feedback `FB________` *(to be filed)* · Chromium `crbug.com` UI>Notifications *(to be filed)* — see [Who can fix this](#who-can-fix-this--谁能修) |

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

So the chain is:

1. Chrome delivers a persistent notification via the Alerts helper → helper registers as an `usernoted` client;
2. helper goes idle and **exits**; its registration dies with it;
3. user clicks → **`usernoted` receives the click normally** (so mouse input, WindowServer hit-testing and event dispatch are all fine — this rules out the whole input-latency family of explanations);
4. `usernoted` has no live client for that notification. It does still run its `Search for url to launching … in background` path (59 such lines during the stuck window, so it is *not* that it never tries) — but **no client is ever produced, nothing is forwarded, and no error is logged**. The click is silently discarded;
5. any event that respawns the helper — a new notification arriving, or quitting and reopening Chrome — restores the registration and **instantly un-sticks every backlogged notification simultaneously**.

Point 5 retroactively explains every "it healed by itself after N minutes" observation from this investigation: on one occasion three separately-stuck notifications all became clickable within 21 seconds of each other, exactly when Chrome was restarted.

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
| `usernoted` logging `com.google.Chrome.framework.AlertNotificationService Failed to source application bundle` is the fault | It fires on essentially **every** cold reconnect of the helper — including 3 of the notifications that clicked **fine**. Byte-identical log output either way. Pure noise for this bug |
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

Both sides have something to fix, and the failure is squarely in Apple's process:

- **Apple (`usernoted`)** — it accepts the click, has the notification record, knows the client bundle identifier and its on-disk path, runs a launch-search path, and then silently drops the user's interaction with no error and no fallback. Relaunching the registered client, or falling back to the app's main bundle, would fix it. **This is the actual defect** and is why the same Chrome build is 7/7 clean on macOS 26.
- **Chrome (Chromium)** — its own architecture creates the precondition by letting the Alerts helper exit while notifications it delivered are still on screen and expected to be interactive. Keeping the helper alive while any alert-style notification of its own is still outstanding would sidestep the OS bug entirely.

## Variations honestly recorded / 如实记录的变体

- Usually **only left click** dies; right-click and swipe keep working. **Once**, all three died together, and that instance also survived a full Chrome quit-and-relaunch, self-healing only ~9.6 minutes after delivery. Whether that is the same bug in a worse state or a second, rarer problem is **unresolved**.
- `NotificationCenter.app` was not perfectly idle during one stuck period (~9–10% of one core doing genuine SwiftUI layout work). At that magnitude it looks like ordinary panel refresh, not a hang, and it is **not** treated as evidence here.

## Possibly related, unconfirmed / 可能相关但未确认

A session on **2026-08-04** (beta4 era) recorded the same user-visible symptom on notifications that had **nothing to do with Chrome** — a Samsung T7 disk-eject prompt and a "DuoTranslator.app was prevented from modifying apps" prompt — described verbatim as "无法点击也无法右键关闭". **In that instance `killall usernoted` fixed it**, whereas in the case documented here it did not. So the two may share a root cause with different severities, or may be different bugs that look alike from the user's side. Recorded as a lead, not as evidence. A Finder notification reportedly got stuck at some point too; the unified log buffer no longer reaches back far enough to corroborate that one.

If this class does extend beyond Chrome, the framing above ("Chrome's helper exits") would be a *special case* of a more general `usernoted` response-routing defect — worth testing with any other app that delivers alert-style notifications from a short-lived helper process.

## Relationship to the older Sequoia "click doesn't navigate" bug / 与旧的 Sequoia「点击不跳转」bug 的关系

Superficially the same complaint as the long-running macOS 15 issue ([MacRumors thread](https://forums.macrumors.com/threads/chrome-notifications-not-clickable.2432947/), reported from Sequoia 15.1 beta in 2024-08 through at least 2025-03), which the reporter's own testing found fixed as of macOS 26 beta2. Whether the mechanism documented here is that bug returning or an unrelated regression that presents identically is unknown; no macOS 15 comparison data was collected.

## Open questions / 待定

1. Why does the failure only hit ~50–60% of pushes rather than every push once the helper has exited? Presumably a race between helper exit and the click, but the exact window was not characterised.
2. Does this affect **any** app whose alert-style notifications come from a short-lived helper, or is something Chrome-specific involved? (See the 2026-08-04 lead above.)
3. What exactly happens inside the `Search for url to launching …` path during the stuck window — it runs, but never yields a client. Needs a `usernoted` trace beyond what the public log exposes.
4. The one instance where right-click and swipe also died and a Chrome restart did not fix it — same bug or a second one?
5. Was the equivalent path broken in earlier 27 betas (beta1–3)? Only beta4 and beta5 were tested.
