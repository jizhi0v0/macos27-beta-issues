# Weather.app VFX render thread spins ~36% CPU when backgrounded
# 天气 app 的 VFX 渲染线程后台空转吃 ~36% CPU

> 🔗 **Track / 关注此问题:** [#4 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/4)

| | |
|---|---|
| **Status** | 🟡 Mitigated — beta regression in a system app |
| **macOS** | 27.0 beta (`26A5353q`) |
| **Component** | Apple **Weather.app 6.0 (1431.0.1)** — `com.apple.vfx.runtime-thread` |
| **Report** | Apple Feedback: `FB________` *(to be filed)* |

## Symptom / 症状

Weather.app sits at ~36% CPU continuously, even when its window is in the background.

天气 app 持续吃 ~36% CPU，即使窗口挂在后台。

## Evidence / 证据

`sample` shows the **main thread is idle** (parked in `mach_msg` waiting for events). The CPU is entirely in two `com.apple.vfx.runtime-thread` threads — the VFX framework rendering the animated weather background (particle animation). When the window is backgrounded, that animation loop is **not throttled / not frame-capped** and keeps running at full speed (1367 of 1376 samples in the VFX render path).

主线程实际 idle（卡在 `mach_msg` 等事件），CPU 全烧在两条 `com.apple.vfx.runtime-thread`（VFX 框架渲染动态天气背景粒子动画）。窗口挂后台时该动画循环没节流/没降帧，一直满速跑（1376 采样里 1367 在 VFX 渲染路径）。

## Workaround / 临时规避

```bash
killall Weather    # or ⌘Q
```

Don't leave the Weather window backgrounded for long periods.

别让天气窗口长期挂后台。

## Notes / 备注

Beta regression in a system app — can't be fixed locally; expect a fix in a later beta. The menu-bar `WeatherMenu` component was also seen emitting heavy logs (~560 lines/min) in the same period.

**Retest 2026-06-26 beta2 26A5368g:** NOT-REPRODUCED — Weather backgrounded measured 0.9–1.9% CPU (not ~36%). `sample` still shows the two `com.apple.vfx.runtime-thread` threads, but they are now **parked**, not spinning: 2328/2337 and 2314/2337 samples sit in `_pthread_cond_wait` → `__psynch_cvwait` (blocked on a condvar), and `__psynch_cvwait` is the dominant leaf (4642 samples). Main thread idle in `mach_msg` as before. Looks fixed/throttled in beta2 — the VFX render loop is no longer free-running when backgrounded.

**Re-check 2026-06-26 (clear weather):** Weather backgrounded again at **0.1% CPU**. The VFX render path *does* still fire — `sample` shows `NUNIAstronomyVistaView renderOnce` via `ViewGraphRootValueUpdater.render` (SwiftUI) on the VFX thread — but it is throttled, not the beta1 36% spin. **Caveat:** current conditions were clear/no precipitation, so the heavy particle path (rain/snow) was not exercised. Cannot distinguish "fixed" from "only the precipitation-animation case spins" without re-testing during rain/snow. Status: tentatively fixed, pending a rainy-condition re-test.

**Rainy-condition re-test 2026-06-26 — CONFIRMED FIXED:** set Weather to a city with active rain, backgrounded it. CPU **2.2%**, process state S (sleeping). `sample`: the VFX thread is parked — top-of-stack is overwhelmingly `__workq_kernreturn` / `mach_msg` / `__psynch_cvwait` (tens of thousands of wait samples) with only ~35 samples in actual VFX render code. The beta1 36% free-run does **not** reproduce even with the precipitation animation. Binary is now **Weather 6.0 build 1435** (beta1 bug was on build **1431**) — the fix rode in with the app-bundle update. The brief "UI pause" seen when foregrounding is the *correct* new behavior: the animation is throttled/occluded while backgrounded and resumes on foreground (the opposite of the old always-on spin). **Net: resolved on beta2 — no Feedback needed.**
