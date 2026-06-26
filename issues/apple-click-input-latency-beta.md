# Click / input responsiveness regression on macOS 27 beta2 (clicks slow to react; app main thread is idle)
# macOS 27 beta2 点击/输入响应回归:点按钮反应迟钝,但 app 主线程是空闲的

| | |
|---|---|
| **Status** | 🟠 Confirmed macOS-27-specific regression; exact scope (system-wide vs app-specific) being narrowed |
| **macOS** | 27.0 beta2 `26A5368g` (NOT present on macOS 26 — same app, same hardware-class, responsive) |
| **Component** | Apple — input/event delivery / responsiveness (suspect: WindowServer/event pipeline under load) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max |
| **Report** | Apple Feedback: `FB________` *(pending scope confirmation)* |

## Symptom / 症状

Clicking buttons / switching chats in Telegram (and possibly other apps) is **sluggish to react** on macOS 27 beta2 — you click, and the response comes a beat late. This is *interaction latency*, NOT visual/animation jank.

点按钮、切会话**反应迟钝**(点下去要等一下才响应),指的是**交互延迟**,不是画面卡。

## Key evidence / 关键证据

1. **NOT the app's main thread.** `sample` of Telegram during 6s and 12s of *continuous clicking*: all threads overwhelmingly parked (`__psynch_cvwait` 198k, `mach_msg` 68k), active leaves only single/double digits (`_dispatch_main_queue_push` 16, CA layer animations, a few render frames). The clicks ARE delivered and processed instantly; the main thread is idle/responsive. So the latency is **not** Telegram code blocking.
2. **macOS-27-specific.** The same Telegram, doing the same actions, is **responsive on a separate macOS 26 machine**. The regression appeared on macOS 27.
3. Concurrent context: WindowServer ran hot (40–75%) on the 27 machine, partly driven by Telegram's own continuous CVDisplayLink redraw (see [telegram-mas-lag](telegram-mas-lag.md)). A loaded WindowServer/event pipeline delivering click events late is consistent with "main thread idle but clicks feel late."

## Hypothesis / 推断

A macOS 27 **event-delivery / input-responsiveness regression**: click events reach the app late (system-side), even though the app handles them instantly once received. Likely aggravated by WindowServer/compositing load (feedback loop: heavy-redraw apps load WindowServer → events delivered slower).

## Open question / 待定

System-wide vs app-specific on the 27 machine: do clicks in **Finder / System Settings / Safari** also feel sluggish? If yes → system-wide event-delivery regression (file as such). If only Telegram → a Telegram-on-27 interaction (less likely given the idle main thread).

## Notes / 备注

- Hard to capture in a `sample` precisely *because* the app main thread is idle — the latency is upstream (event delivery). The right artifact for Feedback is a **sysdiagnose taken right after experiencing the lag** + the "fine on macOS 26, laggy on 27, main thread idle" framing.
- Cross-machine caveat: the macOS 26 machine is different hardware/load; "fine on 26" is a strong but not airtight control. The decisive on-machine test is whether reducing WindowServer load (quit heavy-redraw apps) restores click responsiveness on the 27 machine.
