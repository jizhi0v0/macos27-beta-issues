# Click / input responsiveness regression on macOS 27 beta2 (clicks slow to react; app main thread is idle)
# macOS 27 beta2 点击/输入响应回归:点按钮反应迟钝,但 app 主线程是空闲的

| | |
|---|---|
| **Status** | 🟠 Confirmed macOS-27 regression, NOT load-related — **persists with the system 80% idle** (after killing the 49% appstoreagent loop, clicks still lag). Bottleneck is WindowServer's single `ws_main_thread` serializing event delivery behind compositing. Fine on macOS 26. |
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

## spindump 2026-06-26 — main thread is in the event loop (idle), NOT blocked; WeType was a red herring

`sudo spindump Telegram 8` during continuous clicking:
- The main thread's **stack** is 784/801 samples in `nextEventMatchingMask: → _DPSNextEvent → ReceiveNextEventCommon → RunCurrentEventLoopInMode` — i.e. parked in the AppKit event loop *waiting for events*. Only ~13 samples in `CA::Transaction::commit/flush` (light render). So the main thread is **idle/responsive**, not stuck.
- spindump labeled the main thread `Thread name "(input method 910 com.tencent.inputmethod.wetype)"` — this only marks that the thread holds the **input-method (WeType) TSM connection** (every text-input app does); WeType runs in its own PID 910. The main-thread STACK contains no WeType code. **WeType is not the cause.**
- TG worker threads (Postbox, mtproto, etc.) all had tiny CPU (≤25ms); thread-pool threads were parked ("last ran 59s/4483s ago"). Nothing is CPU-starved on a runnable queue.

## Conclusion — load-induced event-delivery latency, downstream of the filed CPU bugs

Not a Telegram bug, not TG's threading/QoS (SSignalKit is GCD-based, see below), not the "new scheduler vs custom threads" theory, not WeType. The click latency is **macOS 27 delivering input events late when the system is under heavy load**. Decisive corroboration from the user: **screen-recording OR sampling makes it dramatically worse** ("巨卡无比") — the responsiveness is load-sensitive and the system is near saturation. That load is largely the **beta CPU bugs filed from this same investigation** — CoreMedia loop (FB23411581), MenuBarAgent idle spin (FB23411741), Spotlight ranking loop (FB23412497), plus WindowServer compositing. macOS 26 lacks these → responsive.

So this is a **downstream symptom of aggregate beta load**, not an independent root cause. Mitigation: kill the load sources (the filed bugs / heavy-redraw apps); fix is the underlying CPU bugs. Threading note: TG's SSignalKit `Queue` is GCD-based (`DispatchQueue.global(qos: .default/.background)`, no raw pthreads), so it does go through the system scheduler — the "TG's own wheels bypass the new scheduler" hypothesis does not hold.

## DECISIVE UPDATE 2026-06-26 — it is NOT load; it's a WindowServer single-thread regression

A whole-system `spindump` (10s) + killing the top load source disproves the "load-induced" framing:
- The biggest CPU consumer was **`appstoreagent` ~49%** (stuck in a `+[__CFN_CoreSchedulingSetRunnable _run:]` CFNetwork loop — anomalous; killing it did not respawn, likely a stuck App Store network op). After killing it, **the system sits at ~80% idle** (M3 Max, many free cores) — and **clicks are STILL laggy.** So it is **not** CPU saturation / not the filed CPU bugs.
- WindowServer's CPU is concentrated on **`ws_main_thread` = 3.68s / 10s (~37–45%)**, with other WS threads negligible. Event delivery and compositing both run on this single thread, so when it's busy compositing (Liquid Glass + animating windows), input events queue behind it → latency — even though total CPU is 80% idle (other cores can't help a single-threaded bottleneck).
- Same app/actions are responsive on **macOS 26** → macOS 27 regressed how WindowServer prioritises event delivery vs compositing on its main thread.

**Conclusion: a genuine macOS 27 WindowServer/event-delivery regression, independent of system load.** Local mitigation only shaves it (Reduce transparency + Reduce motion; quit continuously-redrawing apps to lighten ws_main_thread). Real fix is Apple's. Worth a standalone Feedback (evidence: whole-system spindump showing ws_main_thread serialization + the macOS-26 control + "persists at 80% idle").
