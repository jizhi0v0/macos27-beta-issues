# Click / input responsiveness regression on macOS 27 beta2 (clicks slow to react; app main thread is idle)
# macOS 27 beta2 点击/输入响应回归:点按钮反应迟钝,但 app 主线程是空闲的

> 🔗 **Track / 关注此问题:** [#14 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/14)

| | |
|---|---|
| **Status** | 🟢 FIXED on beta3 `26A5378j` (user-confirmed 2026-07-08). Was 🟠 narrowed on beta2: a **compositing stutter on one specific heavy view transition** — Telegram's group-title → group-details → **back** (dismissing the heavy/blurred details panel); NOT load, NOT Telegram main-thread CPU, other apps/navigation fine, macOS 26 fine. |
| **macOS** | present 27.0 beta2 `26A5368g`, absent on macOS 26; **fixed on beta3 `26A5378j`** |
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

## What it is NOT (ruled out)

Not a Telegram bug, not TG's threading/QoS (SSignalKit is GCD-based, see below), not the "new scheduler vs custom threads" theory, not WeType. An early hypothesis that it was **load-induced** (the system under heavy load from the filed CPU bugs) was **tested and disproved** — see the *Decisive Update* below: it persists with the system **80% idle**, so it is not a load/saturation problem. The "screen-recording / sampling makes it worse" observation just reflects extra work landing on the already-bottlenecked single WindowServer thread, not overall CPU saturation. Threading note: TG's SSignalKit `Queue` is GCD-based (`DispatchQueue.global(qos: .default/.background)`, no raw pthreads), so it does go through the system scheduler — the "TG's own wheels bypass the new scheduler" hypothesis does not hold.

## DECISIVE UPDATE 2026-06-26 — it is NOT load; it's a WindowServer single-thread regression

A whole-system `spindump` (10s) + killing the top load source disproves the "load-induced" framing:
- The biggest CPU consumer was **`appstoreagent` ~49%** (stuck in a `+[__CFN_CoreSchedulingSetRunnable _run:]` CFNetwork loop — anomalous; killing it did not respawn, likely a stuck App Store network op). After killing it, **the system sits at ~80% idle** (M3 Max, many free cores) — and **clicks are STILL laggy.** So it is **not** CPU saturation / not the filed CPU bugs.
- WindowServer's CPU is concentrated on **`ws_main_thread` = 3.68s / 10s (~37–45%)**, with other WS threads negligible. Event delivery and compositing both run on this single thread, so when it's busy compositing (Liquid Glass + animating windows), input events queue behind it → latency — even though total CPU is 80% idle (other cores can't help a single-threaded bottleneck).
- Same app/actions are responsive on **macOS 26** → macOS 27 regressed how WindowServer prioritises event delivery vs compositing on its main thread.

**Conclusion: a genuine macOS 27 WindowServer/event-delivery regression, independent of system load.** Local mitigation only shaves it (Reduce transparency + Reduce motion; quit continuously-redrawing apps to lighten ws_main_thread). Real fix is Apple's. Worth a standalone Feedback (evidence: whole-system spindump showing ws_main_thread serialization + the macOS-26 control + "persists at 80% idle").

## NARROWED 2026-06-26 — it's a compositing stutter on ONE specific heavy transition, not general input latency

The user pinpointed the repro: **only** "click group title → open group-details → **Back**" is laggy. Plain message navigation, other Telegram actions, and other native apps are all responsive. So this is NOT general input/event latency (that earlier framing is too broad).

A `sample` taken *specifically during the Back transition* (3rd targeted attempt) again shows Telegram's **main thread idle** (overwhelmingly `__psynch_cvwait`/`mach_msg`; active leaves single digits) → the lag is **not** Telegram main-thread CPU. Combined with the user's observation that **screen-recording makes the lag dramatically worse**, the signal points to a **CoreAnimation / WindowServer compositing stutter**: dismissing the group-details panel plays an animation, and that panel is heavy (member/media lists + blur/Liquid-Glass layers). Compositing that dismiss animation drops frames on macOS 27's WindowServer (`ws_main_thread`), while lighter transitions (message nav) are fine. Screen recording adds frame-capture load to the same compositor → the compositing-bound transition stutters more (confirms it's compositing-bound, not CPU/event).

**Net:** macOS 27's WindowServer/CoreAnimation handles this heavy blurred-panel dismiss animation with dropped frames where macOS 26 did not — exposed specifically by Telegram's heavy group-details panel. Half macOS-27 compositor regression, half Telegram's heavy panel. Not Telegram main-thread CPU, not load, not WeType, not the scheduler. Proper proof would need a CoreAnimation/WindowServer frame trace timed to the ~300ms transition (a plain `sample` can't isolate such a brief one-shot burst).

## Retest on beta3 `26A5378j` (2026-07-08) — FIXED / 已修

**User confirms the stutter is gone on beta3.** The exact narrowed repro — group title → group-details → **Back** (dismissing the heavy blurred panel) — no longer drops frames. Two things make this a clean verdict rather than a vague "feels better":

1. **It's the specific transition.** The user confirmed it's transition #1 (the group-details panel dismiss), i.e. the precise repro they originally pinpointed on beta2 — not a general "Telegram feels faster" impression.
2. **Settings-independent.** Toggling Telegram's animation / auto-play settings makes **no difference** to it on beta3. On beta2 the stutter was already shown to be compositor-side (not content/animation), so "smooth regardless of settings" confirms the *system compositor path* changed — this is beta3's fix, not a Telegram-settings workaround.

**Evidence class / why no log number here:** this is a ~300 ms one-shot compositing burst, so — unlike Spotlight's `Campo_*.spin` — it leaves no `.spin`/`.hang` report, and WindowServer CPU can't be read cleanly (the agent's own desktop-app rendering spikes WindowServer 30–50%, per the measurement caveat above). So user perception of the exact narrowed transition **is** the evidence — the same evidence class the #14 narrowing was built on in the first place. Fits the beta3 compositor-fix cluster alongside #12 (MenuBarAgent) and #13 (Spotlight ghosting). No Apple Feedback was filed (was still `FB____` pending scope) — nothing to file now that beta3 resolved it; noting it here for the record.
