# Notification banner goes inert — activate and swipe-to-file are silently dropped before reaching `usernoted`, while `✕` still works
# 通知横幅失效：激活与右滑在到达 `usernoted` 之前被静默丢弃，唯独 `✕` 仍然有效

> 🔗 **Track / 关注此问题:** [#27 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/27)
>
> 🧭 **Landed here from "clicking a notification does nothing"?** Classify the failure first — [notification-click-failure-taxonomy.md](notification-click-failure-taxonomy.md) tells the three shapes apart from `usernoted`'s log in one command. This file is **B**, the freeze; **A** and **C** are [#26](chrome-notification-banner-frozen-unresponsive.md).

| | |
|---|---|
| **Status** | 🔴 **Real and reproduced repeatedly, mechanism unknown.** Split out of [#26](chrome-notification-banner-frozen-unresponsive.md) on 2026-08-12 because it is a *different* failure from the one filed there. Not app-specific: seen on Apple's own **Reminders** and on Chrome web-push notifications. **No trigger has been isolated — four hypotheses were tested and falsified**, and it cannot be produced on demand |
| **macOS** | 27.0 beta5 `26A5406e`; the original sighting was on beta4 `26A5388g`. macOS 26.6 `25G72` not tested for this variant |
| **Component** | Apple — notification banner interaction, upstream of `usernoted` |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max |
| **Report** | not filed — there is no reproduction procedure to give Apple yet |

## Symptom / 症状

A notification banner sits on screen and stops responding:

- **left click** — nothing, indefinitely, however many times you click;
- **right click** — nothing;
- **swipe to file into Notification Center** — nothing;
- **`✕` (hover, top-left)** — **still works**, and works properly.

The banner also stays on screen rather than filing itself away. It recovers on its own eventually, at an unpredictable time.

一条通知横幅停留在屏幕上并失去响应：**左键点击**无反应（点多少次都一样）、**右键**无反应、**右滑归档**划不动，唯独 **`✕`（悬浮后左上角）仍然有效**。横幅同时不会自己收进通知中心，之后会在不可预测的时刻自行恢复。

## Why this is not [#26](chrome-notification-banner-frozen-unresponsive.md) / 为什么这不是 #26

`usernoted`'s log separates them decisively — the two fail on opposite sides of it:

| | click reaches `usernoted` | forwarded to app | right-click / swipe |
|---|---|---|---|
| **#26 (filed)** | ✅ 61, later 15 | ❌ 0 | **still work** |
| **this issue** | ❌ **0 of 5** | — | **also dead** |

#26 is a client-lifecycle bug: the click arrives and there is nobody left to hand it to. Here the click never arrives at all, and the failure covers gestures that #26 leaves untouched. #26 is also *not a freeze* — only activation fails there. This one is the freeze, and **it is the symptom that originally started the whole investigation**, so the reports filed for #26 do not cover it.

## What is established / 已确认

**Not app-specific.** Reproduced on Apple's own **Reminders** (a TIME SENSITIVE alert) and on Chrome web-push notifications, in the same session.

**Not a lost-event or frozen-UI problem — the banner↔`usernoted` channel is open the whole time.** Dismissing an inert banner with `✕` produced a complete, clean teardown:

```
12:00:25.787  usernoted: _removeDelivered: Removing [E1F9E9CC-…]
12:00:25.787  usernoted: _removeDisplayed: Removing
12:00:25.788  usernoted: Spotlight: Removing index
```

So events do reach the banner and the banner does talk to `usernoted`. What fails is specifically the **activate** and **swipe-to-file** branches, dropped before `usernoted` ever sees them.

**Not a global event-dispatch failure.** Telegram notifications stayed interactive throughout one episode, and `NotificationCenter.app` (pid 821, owner of the on-screen notification window) sampled clean — main thread parked in its normal `nextEventMatchingMask` event loop, `NSEventThread` normal, zero blocking calls.

**The notification is live in the store while inert.** `delivered = 1`, `displayed = 1`, record present — the system still considers it outstanding.

**Cross-over on a single notification.** The same Reminders alert: **0 of 5** clicks reached `usernoted` while shown as a banner; minutes later, as a row in Notification Center, **1 of 1** reached it and launched the app in **13 ms** (`Received response` → `Search for url to launching com.apple.reminders` → `Launching`).

## What was tested and falsified / 已证伪的假设

Recorded because several looked convincing and each cost real time:

| Hypothesis | How it died |
|---|---|
| **The banner "expires" a few seconds after presentation** | Controlled pushes clicked as banners worked at **59 s** and **65 s**. A separate case was already inert when clicked **within ~5 s** of `Presenting` — so neither a short nor a long lifetime explains it |
| **A screen lock/unlock cycle breaks it** | Locked, immediately unlocked, then clicked: **worked**. (Lock/unlock does *re-present* the banner, which is what made this look promising) |
| **`UserNotificationCenter.app` liveness is the cause** | Withdrawn as **reverse causality**: verifying "is it alive?" requires interacting with the notification, and interaction may itself be what spawns that process. The correlation is confounded by the act of measuring. A `killall` control could not run — the processes are not owned by the invoking user |
| **Elapsed time** | Notifications clicked 5 min and 8 min 50 s after presentation worked (caveat: those two were clicked 4 s apart and were probably list rows, not banners) |
| **Uptime / accumulated state** | Failed **8 minutes after a boot**, and also after 7–8 hours of uptime, with a healthy stretch in between |
| **`UserNotificationCenter` crash-looping** | No crash reports exist for it other than one this investigation caused itself (see below). Its rapid PID churn is ordinary on-demand spawn/exit |

## What the evidence now suggests / 目前的推断

Not a property of any individual notification, but a **state the machine intermittently enters**, during which banners stop accepting activation while everything else about them keeps working. Outside that state, banners survive minutes and a lock cycle without trouble. **What puts the machine into that state is unknown.** Being displayed as a banner appears to be *necessary* — every confirmed failure was a banner, and the one clean cross-over recovered as a list row — but it is plainly **not sufficient**, since banners clicked at 59 s, 65 s and across a lock cycle all worked.

## Why there is no automated test / 为什么没有自动化测试

macOS **ignores synthetic clicks on notification banners**. A `CGEvent` posted at the banner's exact centre — coordinates read live from the accessibility tree — registered **nothing**: no `Received response`, no service-worker ping, and the banner stayed on screen. The accessibility tree exposes the banner's text and geometry but no `AXPress` action, and `NotificationCenter` cannot be granted through the automation permission path (it is not in the application index, so its windows are also filtered out of screenshots). This is sensible platform hardening, not a defect — but it means **every data point needs a human click**, which is why the sample here is small.

⚠️ **Do not try to launch `UserNotificationCenter.app` manually** to test this. It carries a launch constraint: the kernel `SIGKILL`s it ~100 ms after launch with `Namespace CODESIGNING, Code 4, Launch Constraint Violation`, and the crash is auto-reported to Apple. An earlier version of [`tools/unc-revive-test.sh`](../tools/unc-revive-test.sh) did exactly that and produced a crash rather than a measurement.

## Catching the next occurrence / 下次如何取证

[`tools/shapeAB-watch.sh`](../tools/shapeAB-watch.sh) polls for the state in which this issue and #26 can be told apart on the same notification, and `report` classifies an episode objectively from `usernoted`'s log rather than from what the screen appeared to do:

```bash
tools/shapeAB-watch.sh          # waits, alerts when the test is possible
tools/shapeAB-watch.sh report   # run right after clicking; classifies the outcome
```

The single most valuable open experiment: on **one** inert notification, click it **as a banner** and then **as a Notification Center row**, and see whether it shows this issue's signature in the first case and #26's in the second. If it does, the two are one root cause seen through two presentations. That has never been tried on a single notification.

## Open questions / 待定

1. **What puts the machine into the bad state?** Nothing found. Six hypotheses falsified.
2. Does it occur on macOS 26? Untested for this variant — worth checking, since #26's defect does not exist there.
3. Is it the same root cause as #26 seen through a different presentation, or genuinely separate? See the experiment above.
4. Does the `✕`-still-works asymmetry point at where the drop happens — i.e. is close handled by a different code path than activate/swipe? Not investigated.
5. Was it present in beta1–beta3? Only beta4 and beta5 observed.

## Reporter's ongoing use, 2026-08-19 → 08-22: not noticed since beta6 / 日常使用未再撞见

Reporter's own words, unprompted, 2026-08-22: has not run into this specific freeze — the kind
that self-recovers on its own — since beta6 (`26A5416b`) was installed 2026-08-19, about 3 days of
ordinary use. Explicitly distinguished by the reporter from the *same-day* [FocusBridge CPU-spin
beachball](apple-notificationcenter-focusbridge-cpu-spin.md), which does **not** self-recover and
is a different failure. A ~3-day subjective non-observation is weak evidence — this issue was
already known to be intermittent and non-reproducible on demand, so a quiet stretch is consistent
with either "less frequent on beta6" or plain chance. Not treated as a fix; no mechanism was found
that would explain a change, and status stays 🔴 pending either a recurrence or a longer quiet
window.
