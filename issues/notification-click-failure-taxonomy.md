# "Clicking a notification does nothing" — how to tell the three failures apart
# 「点击通知没反应」——三种失败形态的判别索引

> **This file is an index, not an issue.** It exists because one user-visible complaint covers at least three unrelated defects with different owners, and most of the wasted time in this investigation came from treating them as one. Nothing here is new evidence; each shape's canonical write-up is linked below.
>
> 这份文件是索引,不是 issue。同一句「点击通知没反应」底下至少压着三个互不相干、责任方也不同的缺陷,本次排查里绝大部分弯路都源于把它们当成一个。此处不含新证据,每种形态的权威正文见下方链接。

## Decide first, describe later / 先判型,再描述

Do **not** classify from what the screen appeared to do. `usernoted`'s log separates the three cleanly, and the screen does not. Run this right after the failed click:

```bash
/usr/bin/log show --predicate 'process == "usernoted"' --info --debug --last 5m | grep -c "Received response"
```

| that count | then check | shape | owner |
|---|---|---|---|
| **0** | — | **B** | Apple — [#27](notification-banner-inert-except-close.md) |
| **> 0** | `grep -c "sent to NSUserNotification client"` → **0** | **A** | Apple + Chrome — [#26](chrome-notification-banner-frozen-unresponsive.md) |
| **> 0** | same grep → **equal count**, yet nothing happened | **C** | Chrome — [#26](chrome-notification-banner-frozen-unresponsive.md), *Shape C* section |

[`tools/shapeAB-watch.sh report`](../tools/shapeAB-watch.sh) automates this and classifies an episode from the log rather than from perception.

⚠️ `log` is a zsh builtin — use `/usr/bin/log` explicitly, or you get a silent "0 results".

## The three shapes / 三种形态

| | click reaches `usernoted` | forwarded to app | right-click / swipe | `✕` | is it a "freeze"? |
|---|---|---|---|---|---|
| **A** — no client left to receive it | ✅ | ❌ | **still work** | works | **no** — only activation fails |
| **B** — dropped before `usernoted` | ❌ | — | **also dead** | **works** | **yes** — this is the freeze |
| **C** — lost inside Chrome after delivery | ✅ | ✅ | work | works | **no** |

### A — the client is gone / 客户端已经不在了

**Signature:** `Received response` counts up, `sent to NSUserNotification client` stays at 0, `ps aux | grep "Chrome Helper (Alerts)"` finds nothing, and one `appDeath` appears per click.

**Root cause, established:** on macOS 27 `getDeliveredNotifications` returns an **empty array for ~7–24 ms after `add()`'s completion handler has already fired** (0 ms on 26.6; 32 trials per OS). Chromium kills its Alerts helper on exactly that answer. `usernoted` then relaunches the helper via LaunchServices on every click, and a Chromium helper cannot run standalone, so it dies in ~100 ms and the click is discarded.

**Reproducible without Chrome** — a two-bundle demo sharing none of its code hits the race 14/14.

**Filed:** Apple [FB24273686](https://feedbackassistant.apple.com/feedback/24273686) · Chromium [370536109 #26](https://issues.chromium.org/issues/370536109#c26). This is the only one of the three with a root cause.

**Recovery:** anything that respawns the helper — a new Chrome notification arriving, or quitting and reopening Chrome — un-sticks **all** backlogged notifications at once. `killall usernoted` does **not** help.

**Full write-up:** [chrome-notification-banner-frozen-unresponsive.md](chrome-notification-banner-frozen-unresponsive.md)

### B — the freeze / 真正的冻结

**Signature:** clicks never reach `usernoted` at all (`0 of 5` measured). Right-click and swipe-to-file are dead too. Only the `✕` works, and it tears down cleanly (`_removeDelivered` → `_removeDisplayed` → Spotlight de-index), which proves the banner↔`usernoted` channel is open the whole time.

**Not app-specific** — reproduced on Apple's own **Reminders** as well as Chrome. **This is the symptom that started the whole investigation, and #26's filed reports do not cover it.**

**Mechanism unknown.** Six hypotheses falsified (banner expiry, lock/unlock cycle, `UserNotificationCenter` liveness — withdrawn as reverse causality, elapsed time, uptime, crash-looping). The evidence shape suggests a **state the machine intermittently enters**, not a property of any individual notification. Cannot be produced on demand, so nothing has been filed.

**No automated test is possible:** macOS ignores synthetic clicks on notification banners, so every data point needs a human click.

**Full write-up:** [notification-banner-inert-except-close.md](notification-banner-inert-except-close.md)

### C — delivered, then lost inside Chrome / 送到了,然后在 Chrome 内部丢了

**Signature:** `Received response` and `sent to NSUserNotification client` counts are **equal**, `_removeDelivered` fires normally within tens of ms, the notification disappears from screen — and no navigation happens. The OS side is clean end to end.

**Discriminator measured 2026-08-14: the notification's age, not its content.** Five real YouTube web-push clicks, four dead and one working, all forwarded to the same helper (alive 12 h). Identical `staticCategory` and identical `<response action: contents>` across all five; the `req` tag comes in two shapes (video ID vs `UC…` channel ID) but the success shares its shape with a failure, so tag shape is falsified. The only survivor: the working one had been presented **3.69 s** earlier; the four failures have **no `Presenting` record in the 8 h the log buffer reaches back** — they were overnight backlog clicked out of the Notification Center stack.

**Recipe:** let web-push notifications accumulate overnight, then click them the next morning.

**Candidate mechanism, unverified:** an overnight push's service worker has long been reclaimed, so `notificationclick` cannot be replayed against it. Confirming this needs [`tools/webpush-repro/`](../tools/webpush-repro/)'s server-side receipt with notification age as the controlled variable.

**Nothing in shape C points at macOS.** It matches [crbug 370536109](https://issues.chromium.org/issues/370536109)'s original symptom and may not belong in a macOS-27 log at all — pending the A/B above.

**Full write-up:** [chrome-notification-banner-frozen-unresponsive.md](chrome-notification-banner-frozen-unresponsive.md), *Shape C, measured for the first time*

## Not yet classified / 尚未归类

Two observations that fit none of the three. Recorded so they are not silently absorbed into a shape they do not belong to.

- **2026-08-04, non-Chrome freeze that `killall usernoted` fixed.** A Samsung T7 disk-eject prompt and a "DuoTranslator.app was prevented from modifying apps" prompt, both "无法点击也无法右键关闭". Looks like B, but B is **immune** to `killall usernoted` (14 further clicks received, 0 forwarded, after the daemon restarted with a new PID). Same symptom, opposite remedy → either a milder severity of B or a fourth defect.
- **The instance where right-click and swipe also died *and* a Chrome restart did not fix it**, self-healing ~9.6 min after delivery. Its helper (pid 87903) was alive for **165 s**, which contradicts shape A's mechanism outright. Unexplained; tracked as open question 6 in #26.

## Traps in reading these logs / 读日志时的坑

- **`sent to NSUserNotification client` proves the OS half only.** It means `usernoted` handed the response to a live registered client — **not** that the user-visible navigation happened. Four of the five clicks on 2026-08-14 have that line and did nothing. This distinction is exactly what separates A from C.
- **That clause is legacy-path-only.** It is a valid success signal for the `NSUserNotification` path Chrome's helper uses. On the modern UN client path the equivalents are `Notifying UserNotifications client <bundle>:<pid> about response` → `Received … reply for response`; its absence there proves nothing.
- **`Presenting` fires at delivery, not at click.** Its absence in a window means the notification is older than the window, which is how notification age was established for shape C — it is not a defect signal.
- **A persisting log line is not the user-visible symptom.** Corroborate with `.spin` / `.hang` reports and with what actually happened on screen, not with line counts.
- **macOS ignores synthetic clicks on banners.** A `CGEvent` at the banner's exact centre (coordinates read live from the accessibility tree) registers nothing at all — no `Received response`, no service-worker ping, banner stays put. The tree exposes text and geometry but no `AXPress`, and `NotificationCenter` cannot be granted automation permission. Sensible platform hardening, but it caps every sample here at what a human clicked.
- **Do not launch `UserNotificationCenter.app` manually.** It carries a launch constraint; the kernel `SIGKILL`s it ~100 ms in with `Launch Constraint Violation` and auto-reports the crash to Apple.

## Environment these were measured on / 测量环境

MacBook Pro `Mac15,11` (M3 Max), macOS **27.0** beta5 `26A5406e` (shape A also seen on beta4 `26A5388g`), Chrome `151.0.7922.109` and `151.0.7922.138`. macOS 26.6 `25G72` control exists for shape A only (9/9 clean, plus the probe's 32 trials); shapes B and C have **no macOS 26 control**.
