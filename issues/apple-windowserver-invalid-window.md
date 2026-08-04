# WindowServer high CPU + repeating `_CGXPackagesSetWindowConstraints: Invalid window`
# WindowServer 持续高 CPU + SkyLight 反复报 Invalid window

> 🔗 **Track / 关注此问题:** [#3 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/3)

| | |
|---|---|
| **Status** | 🔴 **CONFIRMED regression on beta4 `26A5388g`** (2026-07-25) — stable **~42–46%** floor on a genuinely idle desktop; 10 replicates across two refresh rates, and **independent of refresh rate** (so not per-frame compositing). Supersedes the earlier "resolved as load" verdict. See [beta4 re-test](#re-test-2026-07-25--beta4-26a5388g--confirmed-regression-supersedes-resolved-as-load) |
| **macOS** | seen on 27.0 beta2 `26A5368g`; **re-confirmed on beta4 `26A5388g`** |
| **Component** | Apple **WindowServer / SkyLight** (`com.apple.SkyLight`) |
| **Hardware** | `Mac15,11`, M3 Max, single internal display (no external monitor, no mirroring) |
| **Report** | Apple Feedback: `FB________` *(to be filed)* |

## Symptom / 症状

`WindowServer` holds ~44–69% CPU (sustained ≈48%) well past boot, with no external display attached and with foreground apps mostly idle. The SkyLight log repeats a window-constraint error.

`WindowServer` 在开机很久后仍持续吃 44~69% CPU（稳态 ≈48%），无外接屏、前台 app 基本空闲。SkyLight 日志反复报窗口约束错误。

## Evidence / 证据

`log show --last 30s` — WindowServer messages:

```
(SkyLight) [com.apple.SkyLight:default] _CGXPackagesSetWindowConstraints: Invalid window   ×79
(SkyLight) [com.apple.SkyLight:KeyboardEvent] delivery manager destinations for kCGSEventKeyDown ...
```

- WindowServer cumulative CPU climbed 5:37 → 9:27 → 9:48 across samples (13–21 min uptime) ≈ 48% sustained.
- The repeating `Invalid window` suggests a specific app holds a window in a bad/zombie state, forcing WindowServer to re-evaluate constraints. (The keyboard-event lines were just whichever app had focus during sampling — not the root cause.)
- macOS 27's "Liquid Glass" compositing adds baseline WindowServer cost; some of this is the new translucency/animation pipeline.

## Reproduction / 复现

Not yet isolated to a single trigger. Open to data points: does it correlate with a specific app's window, with external displays, or with Liquid Glass effects?

## Workaround / 临时规避

- **Dropping to 60 Hz does NOT help** — measured 42.0% vs 45.9% at 120 Hz (5 replicates each). Do not bother; see [refresh-rate independence](#the-floor-is-independent-of-refresh-rate--底噪与刷新率无关).
- **System Settings → Accessibility → Display → Reduce transparency** + **Reduce motion** — cuts Liquid Glass compositing cost. (Note: tested on beta2 under confounded conditions and showed no effect; not re-tested on beta4 at the idle floor.)
- **No known workaround removes the ~42–46% floor.** Quitting applications only removes the load stacked on top of it (81% → ~46%).
- Identify the app whose window triggers `Invalid window` and restart that app. **Do not** `killall WindowServer` — that logs you out.
- Close unused windows / Spaces.

## TODO

- [ ] Correlate the `Invalid window` errors to a specific PID/app (e.g. via `sudo log stream` + window-list inspection) before filing Feedback.

**Retest 2026-06-26 beta2 26A5368g:** CONFIRMED — uptime 39 min; WindowServer[445] 61.7% CPU, cumulative TIME 18:16 (≈47% avg over 39 min, consistent with prior ≈48%). `log show --last 60s` = 159 `_CGXPackagesSetWindowConstraints: Invalid window`, steady ~2.6/sec across the whole window (span 10:31:59→10:32:58), NOT a post-boot transient. **Owning-app hypothesis (uncertain, not fact):** strongest correlated signal in the same window is `WindowServer: pid 1437 failed to act on a ping it dequeued before timing out` ×5 — PID 1437 = `/usr/libexec/textunderstandingd` (Apple Intelligence text-understanding daemon). A non-responsive client failing WindowServer pings is consistent with a window stuck in a bad/zombie constraint state. No external display attached. Treat textunderstandingd as a lead, not a confirmed culprit — the `Invalid window` lines themselves carry no PID, so attribution is inferred from the co-occurring ping timeout only.

**Re-check 2026-06-26 (textunderstandingd hypothesis WITHDRAWN):** Re-measured at WindowServer 73.1% CPU, 362 `Invalid window` in 90s (~4/s, worse than before). The "failed to act on a ping" clients are now **five unrelated system services at once** — `textunderstandingd`, `studentd`, `nsattributedstringagent` (×2 PIDs), `universalaccessd`. Five unrelated daemons failing pings simultaneously means the ping timeouts are a **symptom of WindowServer being saturated (slow to answer pings), not the cause** — so `textunderstandingd` was a red herring. **The window that triggers the `Invalid window` loop remains unidentified.** Proper isolation needs a CGWindowList / window-server dump correlating the invalid window id, which the unattributed log line doesn't provide.

**Spindump 2026-06-26 — CPU is generic CoreAnimation compositing, NOT the log line; remote-capture hypothesis CHECKED & REJECTED:** `sudo spindump WindowServer 8` shows `_CGXPackagesSetWindowConstraints` in **0** hot stacks — the `Invalid window` line is a cheap error log, not where CPU goes. WindowServer's real work is continuous CoreAnimation layer compositing (`CA::Render::Updater::prepare_layer0/prepare_sublayer0`, `CA::OGL::prepare_layers`, `ImagingNode::render`). A hypothesis that remote-desktop screen capture (AweSun/ToDesk) forced this was **rejected** on inspection: `replicatord` is iCloud/IDS **data** sync (ReplicatorEngine), not screen replication; `ScreenSharingSubscriber`×2 and `AweSun_Helper` were idle (0 log lines/60s); ToDesk only polls display modes (~36 `SLSGetDisplaysWithOpenGLDisplayMask`/min). The sustained 47–73% reads as **generic compositing load** — most plausibly Liquid Glass + many simultaneously-animating windows (243 on screen; a single playing video forces per-frame compositing). **Not isolated to a distinct, filable regression — downgraded from file-ready to HOLD.** Needs a re-test on a quiesced desktop (no video, minimal windows, idle) to separate a real WindowServer regression from ordinary compositing workload. The only clearly-anomalous leftover is the continuous `Invalid window` log spam (minor).

**RESOLVED 2026-06-26 — high CPU was LOAD, not a regression; Telegram was the dominant driver:** quitting **Telegram** dropped WindowServer to **single digits** (user-observed in Activity Monitor at an idle moment). Telegram's animated stickers / auto-playing media continuously invalidate & redraw its window (`-[NSView _recursiveTickleNeedsDisplay]` + `CVDisplayLink` + CoreMedia video threads — see [telegram-mas-lag](telegram-mas-lag.md)), forcing WindowServer to recomposite every frame. Once the screen is truly idle (Telegram quit, no active chat streaming, no playing video), WindowServer falls to low single digits — so **WindowServer itself is not a beta regression**, the sustained ~48% was the sum of continuously-redrawing apps (Telegram the biggest, plus any playing video and live app rendering). Note: hard to self-measure the idle floor because any measurement requires responding in the Claude desktop app, which itself spikes the renderer/WindowServer. The separate confirmed beta bug in this area is **[MenuBarAgent idle ~10–14%](apple-menubaragent-idle-cpu.md)** (its own process, persists regardless of apps). The `Invalid window` log spam remains a minor cosmetic log issue. **Status → resolved as load; not filing a WindowServer-CPU Feedback.**

**Toggle tests 2026-06-26 — WindowServer pinned at ~47–48% regardless:** reduced Liquid Glass to minimum + disabled "Tint window background with wallpaper color" → no change (~48%). Paused the YouTube video → no change (47%). Quit Spotify → no change (48%, the resumed video refilled the slot). WindowServer holds a ~48% *floor* while many apps continuously re-render. Top live drivers during the session: `kernel_task` ~29%, `Google Chrome Helper` ~25% (playing video), and **the Claude desktop app itself ~48% across two helpers** (renders the live streaming chat — the single biggest, unavoidable driver while in use). Conclusion: most consistent with **aggregate compositing load from continuously-animating apps**, not a single regression. A clean idle baseline is impossible mid-session because the Claude app must stay open and is a top driver.

**⏳ PENDING FOLLOW-UP (decisive test):** re-measure on a genuinely quiesced desktop (close Claude/Chrome/video/Spotify; minimal windows; idle ~20s). Run [`tools/check-windowserver.sh`](../tools/check-windowserver.sh). If WindowServer drops to low-teens → it was workload, **close this issue**. If it stays >~40% while truly idle → real beta regression; capture spindump + sysdiagnose and file. — **RESOLVED below: it stays >40%.**

---

## Re-test 2026-07-25 — beta4 `26A5388g` — CONFIRMED regression (supersedes "resolved as load")

The 2026-06-26 "resolved as load" verdict **does not hold on beta4**. The decisive test above was finally run under control, and WindowServer holds a **stable ~46% floor with nothing animating on screen**.

### The number / 决定性数据

Five back-to-back 60 s windows in one state, cumulative `utime+stime` deltas (immune to the decaying average `ps %cpu` reports), via [`tools/ws-replicate.sh`](../tools/ws-replicate.sh):

| rep | WindowServer | mds+mdworker aggregate |
|---|---|---|
| 1 | 45.5% | 0.0% |
| 2 | 47.3% | 0.0% |
| 3 | 46.4% | 0.0% |
| 4 | 45.0% | 0.0% |
| 5 | 45.1% | 0.0% |

**mean 45.9% · min 45.0% · max 47.3% · sd 0.9 · spread 1.1×**

Conditions: 120.0 Hz, on-screen windows = `WindowManager`×3, `Window Server`×2, `Finder`, `System Settings`, `DuoTerminal` — **nothing animating**. Spotlight fully settled (`mds+mdworker` = 0.0%), so the indexing storm is excluded as a confound.

### What was ruled out / 逐条排除

Each hypothesis was tested and falsified, not assumed:

| Hypothesis | Test | Result |
|---|---|---|
| **MenuBarAgent** menu-bar animation | quit Alcove → MenuBarAgent 21.9% → **1.6%/1.9%/0.1%** | ❌ WindowServer did **not** drop (44.8% → 49.3% → 52.3%); see [#12](apple-menubaragent-idle-cpu.md) |
| **Aggregate app load** (the old verdict) | quit Claude, Chrome, Telegram, DingTalk, Mail, IntelliJ, Spotify, OrbStack, Alcove, Klack | ❌ 81.2% → ~46%, then **floor**; predicted <20% if load explained it — got 45.9% |
| **corebrightnessd / NaN brightness** | 0 brightness frames in hot stacks; burst occurred **once in 30 min** (12 s) | ❌ cannot explain a sustained floor — but is its own bug, see [corebrightness NaN](apple-corebrightness-nan-oscillation.md) |
| **Remote-desktop screen capture** | AweSun + RustDesk + UURemote + ToDesk all at 0.0% CPU; **zero** `CGDisplayStream`/`ScreenCaptureKit`/`SCStream` log lines in 10 min | ❌ (re-confirms the beta2 rejection, now with 4 such apps installed) |
| **Dynamic / aerial wallpaper** | `Provider => "default"`; `WallpaperAerialsExtension` 0.001 s per 10 s | ❌ |
| **Window count** | `CGWindowListCopyWindowInfo`: 80 total, **5–8 on-screen** | ❌ |
| **Spotlight / mds storm** | replicate run had `mds+mdworker` = 0.0% throughout | ❌ |
| **Display sleep during measurement** | `coreaudiod` held `PreventUserIdleDisplaySleep` 18:55:10→19:08:43, bracketing the runs | ❌ display was on |
| **Refresh-rate / effects settings** | user changed them only *after* the last run; no result file postdates the change | ❌ all 9 measurements were at 120 Hz, effects on |

### Where the CPU goes / spindump 签名

`sudo spindump 448 8` — `ws_main_thread` accounts for **4.825 s of 5.744 s** (84%). Sample distribution (772 samples, loaded desktop):

| branch | samples | share |
|---|---|---|
| `mach_msg` (idle) | 307 | 40% |
| `update_display_callback` → `CGXUpdateDisplay` | 435 | **56%** |
| ├ `prepare_coreanimation` → `ca_prepare_begin_window_update` | 206 | 27% |
| ├ `CompositorMetal::composite` → `CA::OGL::render` | 149 | 19% |
| └ `present_update` → IOMFB | 37 | 5% |

The layer-tree walk recurses **~54 stack frames deep** through `CA::Render::Updater::prepare_layer0` / `prepare_sublayer0`.

On the idle desktop (1001 samples) the same structure persists at lower amplitude: 590 idle, 321 in `update_display_callback`, 168 in `prepare_coreanimation` — i.e. **WindowServer keeps running the display-update timer and preparing CoreAnimation layer trees on a static screen**.

`_CGXPackagesSetWindowConstraints: Invalid window` appears in **0** hot stacks (confirming the beta2 finding) but runs continuously at **~4/sec** (690 lines/170 s and 320/73 s in two separate windows), independent of load. It is a cheap log line, not the CPU sink.

### The floor is independent of refresh rate / 底噪与刷新率无关

Halving the display refresh rate does **not** halve WindowServer's CPU. Two 5-replicate runs, app state held constant, refresh rate recorded by the measuring script itself:

| refresh rate | WindowServer | replicates |
|---|---|---|
| 120 Hz | **45.9%** — min 45.0, max 47.3, sd 0.9 | 5 |
| **60 Hz** | **42.0%** — min 34.9, max 44.3, sd 3.6 | 5 |

**42.0 / 45.9 = 0.92.** Halving the frame rate removed ~8% of the cost, not ~50%.

**Interpretation — this is NOT per-frame compositing work.** If the floor were the cost of recompositing every frame, it would track the refresh rate; it does not. Something running at a fixed rate, or continuously, accounts for the bulk of it. That narrows the search considerably and is the most useful diagnostic handle in this report.

**Retracted hypothesis (recorded so it is not re-walked):** an earlier revision of this file claimed the cost scaled linearly with refresh rate, based on a single 22.5% reading at 19:03 believed to have been taken at 60 Hz. The 5-replicate 60 Hz run above falsifies that — 60 Hz gives 42.0%, not 22.5%. The stated retraction criterion ("if the mean lands above 40%, withdraw the scaling claim") was met.

**Still unexplained:** that one 22.5% reading, now across 11+ measurements otherwise spanning 34.9–52.3%. It was the only capture in which `CompositorMetal::composite` recorded **0 samples**. Concurrent `spindump` is not the explanation — the 18:48 capture ran under `spindump` too and read 46.0%.

### Reproduce / 复现

```sh
bash tools/ws-replicate.sh        # 5 x 60s, reports mean/sd/spread
bash tools/ws-idle-baseline.sh    # single 120s window, lists on-screen window owners
sudo bash tools/ws-idle-spindump.sh   # stacks captured during the idle window
```

Quit every app during the lead-in (including menu-bar apps — Alcove, Klack, Surge) and leave the machine alone. Disable screensaver and display sleep first.

### Methodology notes (learned the hard way) / 方法论教训

- **`ps %cpu` is a decaying average, not an instantaneous rate.** All numbers above are cumulative `utime+stime` deltas over a known wall-clock window.
- **A hardcoded app-name list will lie to you.** An earlier version of [`ws-idle-baseline.sh`](../tools/ws-idle-baseline.sh) checked only for `Claude|Chrome|Telegram|…` and silently missed **Alcove**, **Klack** and **Surge** — producing a "desktop is idle" claim while a notch-animation app was committing CoreAnimation transactions the whole time, and a premature "confirmed regression" verdict. It now enumerates every process owning an on-screen window.
- **Single-shot measurements are not decision-grade here.** Two nominally identical states gave 22.5% and 50.0%. Only replication (sd 0.9) settled it.
- Measuring from inside a heavyweight Electron app makes the measuring process the largest perturbation on the machine — the same structural blocker documented in [#12](apple-menubaragent-idle-cpu.md). The scripts above are `disown`ed so the app can be quit while they run.

## Independent corroboration — [#22](https://github.com/jizhi0v0/macos27-beta-issues/issues/22) (different machine, same floor) / 独立佐证

[#22](https://github.com/jizhi0v0/macos27-beta-issues/issues/22) (filed 2026-07-27 by [@andya1lan](https://github.com/andya1lan), independently) reports a **~100% WindowServer state on the same build `26A5388g`** on **different hardware** — MacBook Air, **M4 / 16 GB**, built-in display only — cleared immediately by `killall MenuBarAgent`. The decisive number for *this* issue is what it clears **to**:

```
broken state                          avg  98.5%   (range 87.5–120.2%)
after MenuBarAgent restart, immediate avg  47.6%
after MenuBarAgent restart, settled   avg  44.9%   ← their "recovered" state
```

**Their recovered state (44.9%) sits inside our idle floor (42.0–45.9%).** Two unrelated reporters, two different Macs, same build, same floor — the floor is therefore **not** specific to this `Mac15,11`, to its 36 GB, or to the set of apps installed here. In #22 that number reads as *success*; measured against a genuinely idle baseline it is the bug.

**他们"已恢复"的 44.9% 正落在我们的空闲底噪区间(42.0–45.9%)内。** 两位互不相关的报告者、两台不同的 Mac、同一 build、同一底噪 —— 说明底噪与本机硬件、内存或已装应用无关。

#22 also re-falsifies, by a different method, two things ruled out above:

| Hypothesis | #22's method | Result |
|---|---|---|
| `Invalid window` spam is the CPU hotspot | counted before/after recovery: **626/60 s → 585/60 s** while CPU fell by more than half | ❌ decoupled — matches our spindump (`_CGXPackagesSetWindowConstraints` in **0** hot stacks) |
| Auto-brightness drives it | disabled it → `commitBrightness` 0/60 s, CPU still **98.5%** | ❌ — matches our falsification of the `corebrightnessd` `nan` oscillation |

### Two layers, not one bug / 两层问题,而非同一个

- **The floor (this issue):** ~42–46% on an idle desktop, refresh-rate-independent, present on both machines, no known workaround.
- **The accumulating layer ([#22](https://github.com/jizhi0v0/macos27-beta-issues/issues/22)):** a further ~55% stacked on top, building over ~2 d 9 h, cleared by rebuilding MenuBarAgent state; their `sample` shows repeated `_XAddStructuralRegionOfType` / structural-region renumbering under `CGXUpdateDisplay`.

`killall MenuBarAgent` removes the second layer and **not** the first — which is why #22 bottoms out at our floor instead of at single digits. Tracked separately on that basis; this issue owns the floor.

`killall MenuBarAgent` 只清得掉第二层、清不掉第一层 —— 这正是 #22 恢复后停在我们的底噪上、而非停在个位数的原因。故两者分开跟踪,本 issue 负责底噪部分。
