# `corebrightnessd` toggles a key 1/0 at ~116 Hz for 12 s while every brightness value reads `nan`
# `corebrightnessd` 以 ~116Hz 反复翻转 1/0 持续 12 秒，且所有亮度值均为 `nan`

> 🔗 **Track / 关注此问题:** [#25 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/25)

| | |
|---|---|
| **Status** | ⚪ **still not a defect on beta6 `26A5416b`** (2026-08-19) — the mechanism re-verified as a **ramp**, exactly as this file concluded: `headroom` climbs ~0.00077 per frame from 1 toward its `potential headroom` of 16, one step every ~8.3 ms at 120 Hz, a full traversal taking ~2.7 min, while `sdr` and `ambient lux` stay constant. **But two numbers changed and one was never measured** — see [the beta6 re-measurement](#re-measurement-2026-08-19--beta6-26a5416b--frequency-up-4-5x-cost-bounded). Prior: ⚪ **Resolved 2026-08-13 — not a defect.** `nan` is an unset-field sentinel; the one permanently-`nan` field (`indicator brightness`) needs the dedicated silicon of [MacBook Neo / A18 Pro](https://support.apple.com/guide/security/mac-on-screen-camera-indicator-light-sec75a2d237d/web), which this Mac does not have (`IOMFBSupportsSecureIndicator = No`). The title's "~116 Hz toggle" is a brightness ramp. See the two 2026-08-13 sections at the bottom. No Feedback filed |
| **macOS** | 27.0 beta4 `26A5388g` |
| **Component** | Apple **CoreBrightness** (`corebrightnessd`) → **QuartzCore** (`com.apple.coreanimation:Brightness`) |
| **Hardware** | `Mac15,11`, M3 Max, built-in Liquid Retina XDR, 120 Hz, **Auto-Brightness ON** |
| **Report** | Apple Feedback: `FB________` *(to be filed)* |

## Symptom / 症状

In a ~12-second episode, `corebrightnessd` flips an unnamed key between `1` and `0` **1,396 times each** — ~116 toggles/second, matching the 120 Hz ProMotion refresh rate, i.e. **once per frame**. Throughout, WindowServer logs the resulting brightness state with **every single field as `nan`**, including `ambient lux` (the ambient-light-sensor reading).

`corebrightnessd` 在约 12 秒内把某个键在 `1`/`0` 之间翻转各 1,396 次（~116 次/秒，与 120Hz 刷新率吻合，即每帧一次）。同期 WindowServer 记录的亮度状态**每个字段都是 `nan`**，包括环境光传感器读数 `ambient lux`。

## Evidence / 证据

`corebrightnessd`, 2,912 lines in the 12-second episode (~250/sec):

```
1396  (CoreBrightness) [com.apple.CoreBrightness.CBDisplayModuleSKL.1:default] key=<private> value=1
1396  (CoreBrightness) [com.apple.CoreBrightness.CBDisplayModuleSKL.1:default] key=<private> value=0
  27  (CoreBrightness) [com.apple.CoreBrightness.ChromaticCorrection:GCP] Lux | RampIsRunning=NO StartLux=…
  23  (CoreBrightness) [com.apple.CoreBrightness.CBAutoBrightnessModuleSKL.1:default] key=AggregatedLux va…
   4  (CoreBrightness) [com.apple.CoreBrightness.CBRampManager.1:default] Insert ramp: SDR_RAMP | <private…
```

WindowServer, same window, 1,329 lines — **all NaN**:

```
2026-07-25 18:18:56.xxxxx+0800  localhost WindowServer[448]: (QuartzCore) [com.apple.coreanimation:Brightness]
  Display 1 swap brightness: nan, limit: nan, indicator brightness: nan, ambient lux: nan,
  low ambient strength: nan, high ambient strength: nan, contrast preservation: nan, contrast enhancer: nan
```

Per-second cadence — one contiguous run, ~115/sec, no gaps:

```
31 18:18:55   117 18:18:57   117 18:18:59   114 18:19:01   110 18:19:03   120 18:19:05   42 18:19:07
109 18:18:56  116 18:18:58   116 18:19:00   109 18:19:02   113 18:19:04   115 18:19:06
```

Occasionally a real value leaks through, with the rest still NaN:

```
1  Display 1 swap brightness: 229.078, limit: nan, indicator brightness: nan, ambient lux: nan, …
1  Display 1 swap brightness: 228.069, limit: nan, …
```

Backlight hardware state at the time was sane (`ioreg -c AppleARMBacklight`): `BrightnessMilliNits value=381794`, `rawBrightness value=1488` of 2047 — so the panel itself has valid values; the CoreBrightness computation does not.

## Frequency / 发生频率

**Rare, not a permanent loop.** Over a 30-minute window the total toggle count was 1,398 `value=1` / 1,396 `value=0` — essentially identical to the single 12-second episode, meaning **it happened exactly once in 30 minutes**. Only 21 of 300 seconds in a separate 5-minute sample contained any brightness lines.

## Not the cause of WindowServer's high CPU / 与 WindowServer 高占用无关

Recorded explicitly so the lead is not re-walked: this was investigated as a candidate driver of the [WindowServer ~46% floor](apple-windowserver-invalid-window.md) and **falsified**. Brightness / ALS / tone-mapping frames appear in **0** hot stacks in the WindowServer spindump, and at ~12 s per 30 min the episode cannot account for a sustained floor. It is a separate, self-contained defect.

## Why it still matters / 为何仍需修

- `ambient lux: nan` means the auto-brightness input is invalid, yet **Auto-Brightness is enabled** — the feature is running on garbage input.
- NaN propagates through every downstream field (limit, contrast preservation, contrast enhancer), so any comparison against a previous value is undefined. NaN never compares equal to itself, which is a classic source of "changed?" checks that always fire.
- 116 toggles/second sustained for 12 seconds is per-frame churn in the display pipeline.

## Reproduction / 复现

Not isolated to a trigger. Observed once during a 2-minute idle measurement window with all applications quit; the machine was not being touched. Auto-Brightness ON, single internal display, no external monitor. Display sleep was held off by a `coreaudiod` `PreventUserIdleDisplaySleep` assertion, so this is not a dim/undim transition at sleep onset.

Untested: whether turning **Auto-Brightness off** eliminates the episodes. That is the obvious next experiment.

## Workaround / 临时规避

Possibly **System Settings → Displays → Automatically adjust brightness → off** (untested).

## CORRECTION 2026-08-12 — not rare at all: 72% of five-minute windows / 更正：完全不罕见，72% 的五分钟窗口都有

This entry previously described the oscillation as **"rare (~once/30 min)"**. That estimate was wrong.

A watcher sampling `log show --last 5m --info --debug --predicate 'process == "corebrightnessd"'` roughly every five minutes, running for **9 h 17 m** on beta5 `26A5406e`, found `nan` lines in:

```
windows sampled : 104
windows with nan:  75      (72%)
total nan lines : 37,088
worst window    :  4,609 lines
```

So any arbitrary five-minute look has about a **7-in-10** chance of catching it, and it is still fully present on beta5 — the entry was previously left at 🟡 on beta4 data alone.

What does **not** change: the beta4 mechanism description (1,396 toggles each way in 12 s — once per frame at 120 Hz; every field including `ambient lux` reading `nan` while Auto-Brightness is ON), and the explicit falsification of this as the cause of [#3](apple-windowserver-invalid-window.md). Only the frequency claim was wrong, and it was wrong because it came from spot checks rather than a continuous watcher.

## CORRECTION 2026-08-13 — the toggle is a brightness ramp; the NaN state is real but is not shown to be a 27 regression / 更正：翻转是亮度斜坡；NaN 状态属实，但没有证据说明它是 27 的回归

Three findings, in the order they overturned each other. Tooling: [`tools/corebrightness-nan-watch.sh`](../tools/corebrightness-nan-watch.sh).

### 1. The "~116 Hz toggle" in the title is a brightness ramp, not an oscillation

Captured whole on beta5 `26A5406e`, with the raw window archived at capture time:

```
17:15:17.798862  CBAutoBrightnessModuleSKL  key=AggregatedLux value=464.2102 -> 392.0533
17:15:17.799283  CBRampManager              Insert ramp: SDR_RAMP
17:15:17.803  ┐
   ...        │  key=<private> value=1 / value=0   ×1,198 lines
17:15:22.796  ┘  240 lines/s = 120 pairs/s = one update per frame at 120 Hz
17:15:22.795930  CBRampManager              Finished ramps / remove ramp: SDR_RAMP
```

The run is bounded by `Insert ramp` and `Finished ramps`, triggered by an ambient-light change, and lasts exactly as long as the ramp (5.0 s here; beta4's 12 s episode was a larger brightness delta). Once-per-frame updates are what a ramp *is*. These lines are emitted below the default log level (`--info --debug` only) and `corebrightnessd` costs **0.25–0.29%** CPU across a 1 h 23 m watcher run. **On this evidence the toggle is normal behaviour**, and the first half of this entry's title no longer describes a defect. (Inference from the log's own structure — CoreBrightness is a private framework with no public documentation to check this against.)

标题里的「~116 Hz 翻转」是一次亮度渐变：环境光变化触发 `SDR_RAMP`，每帧更新一次，`Finished ramps` 结束，全程 5.0 s，且这些行默认日志级别根本不输出，CPU 0.25–0.29%。按现有证据这不是缺陷。

### 2. The NaN state does reproduce on beta5 — and it was being measured on the wrong stream

The all-NaN evidence in this entry comes from **WindowServer**'s `(QuartzCore) [com.apple.coreanimation:Brightness]` lines, not from `corebrightnessd`. The first version of the watcher followed only `corebrightnessd`, whose own lines carry a valid `lux=464.21`, which produced the wrong reading *"`ambient lux: nan` does not reproduce on beta5"*. It does. Querying the stream this entry was actually built on, 30 minutes on `26A5406e`:

```
WindowServer Brightness lines : 24,809   (~14/s sustained)
  containing nan              : 23,843   (96%)
  with `ambient lux: nan`     : 11,761   (47%)
```

Three states interleave: fully NaN, fully valid (`swap brightness: 304.849, ambient lux: 419.227`), and mixed (`swap brightness` valid while `ambient lux: nan`). The watcher now follows **both** streams per window.

原始的 all-NaN 证据来自 **WindowServer** 的 QuartzCore 日志，不是 corebrightnessd。watcher 最初只跟后者，而后者自己的行里 lux 是有效值，于是得出过一个错误结论。查对流之后：30 分钟 24,809 行，96% 含 nan，47% 是 `ambient lux: nan`。

### 3. Not shown to be a 27 regression — and one external report puts it on macOS 15.7

The same log family appears in an unrelated [V2EX report (2026)](https://www.v2ex.com/t/1206384) on **macOS 15.7**, M4 Mac with an external DELL display via a UGREEN CM818 adapter, posted while troubleshooting display wake-up failures:

> "Display 1 swap brightness: nan, limit: 337.678, indicator brightness: nan, ambient lux: nan"

That is two major versions before 27, so "NaN brightness state" is **not new in 27** on the present evidence. A same-family cross-version control could not be run here: the available macOS 26.6 machine (`25G72`, M4 mini) has no internal display or ALS and logs **1** Brightness line in 3 hours, 0 with `nan` — that is the code path not executing, not the defect being absent. Deciding regression-vs-longstanding needs a **macOS 26 laptop with a built-in display and ALS**, which we do not have.

同族日志在 [macOS 15.7 的一份外部报告](https://www.v2ex.com/t/1206384) 里已经出现（M4 + 外接 DELL + 绿联 CM818 转接，排查唤醒失败时贴出），比 27 早两个大版本。本地无法做跨版本对照：26.6 的 M4 mini 无内置屏与环境光传感器，3 小时只有 1 行 Brightness 日志、0 个 nan —— 那是代码路径没跑，不是问题不存在。

### Where that leaves this entry

- **Reproduces on beta5**, at higher volume than this entry ever claimed. That part is solid and now has a rerunnable watcher behind it.
- **No user-visible symptom** observed on this machine, and no CPU cost worth the name. The V2EX poster had a wake failure, but that is a different display path and correlation only.
- **Not established as a beta regression.** No Feedback should be filed on this basis.
- The `nan` values themselves remain unexplained: the panel hardware reads sane (`ioreg -c AppleARMBacklight`: `BrightnessMilliNits 381794`, `rawBrightness 1488/2047`) while the computed state is NaN, and NaN never compares equal to itself, so any "did it change?" check downstream fires every time. That is why this stays open rather than closed.
- Still **not** the cause of [#3](apple-windowserver-invalid-window.md) — unchanged.

### Methodology note: this evidence is perishable

A window recorded live as 2,357 lines / 1,031 `nan`, re-queried 40 minutes later, returned **240 lines / 0 `nan`**. `--info --debug` messages live in an in-memory ring buffer and are evicted oldest-first, and `log show` reports the loss as a smaller plausible number rather than an error. Any window that turns out to be interesting is usually unexaminable by the time you notice it. The watcher therefore gzips every window's raw log at capture time (~50 KB per 5-minute window per stream).

`--info --debug` 级别的日志活在内存环形缓冲里，几十分钟就被挤掉：同一窗口实时记为 2,357 行 / 1,031 nan，40 分钟后重查只剩 240 行 / 0 nan，且失败形式是「返回一个看起来合理的小数字」而非报错。因此 watcher 现在在采样当时就把每个窗口的原始日志 gzip 落盘。

## RESOLVED 2026-08-13 — `indicator brightness: nan` is a hardware capability that this Mac does not have. Not a defect. / 定案：`indicator brightness: nan` 是本机没有的硬件能力，非缺陷

`nan` here is **an unset-field sentinel written by Apple's code**, and the one field that is *never* populated — `indicator brightness` — belongs to a security feature that requires dedicated silicon this machine does not have. Nothing in this entry is a defect. **No Feedback will be filed.**

### The official source

Apple Platform Security, [**Mac on-screen camera indicator light**](https://support.apple.com/guide/security/mac-on-screen-camera-indicator-light-sec75a2d237d/web) (published 2026-03-11):

> MacBook Neo combines system software and dedicated silicon elements within A18 Pro to provide additional security for the camera feed. The architecture is designed to prevent any untrusted software—even with root or kernel privileges in macOS—from engaging the camera without also visibly lighting the on-screen camera indicator light.

[MacBook Neo](https://www.macrumors.com/2026/03/04/apple-announces-low-cost-macbook-neo-with-a18-pro-chip/) shipped 2026-03-11 (A18 Pro, the first A-series Mac) — the same date the guide section was published. So the indicator pipeline present throughout macOS is the *system software* half of a feature whose *silicon* half exists only on that hardware generation.

### Verified on this machine

| check | result |
|---|---|
| `ioreg -c IOMobileFramebuffer -lw0` | **`IOMFBSupportsSecureIndicator = No`** — sibling keys are hardware-capability flags (`SupportsAOTPowerSaving = No`, `PCC2DEnable = Yes`, `calibrationType = 1`) |
| `IODeviceTree:/backlight` (45 properties) | **no indicator property at all** — and that node is what the CoreBrightness gate reads |
| every archived window (`indicator brightness:`) | **70,037 lines, 0 real values** — 8 apparent exceptions are the `-1` sentinel from the other branch |
| corebrightnessd (`Indicator.brightness=`) | **10,501 lines, 0 non-`nan`** |
| **live mic test** (Chrome requests `kTCCServiceMicrophone`, `Dependent controller changed: sensor indicators` fires 3×) | **field stays `nan`** — the on-screen dot lights without touching this channel |
| `PIL` activity in 3 h of log | **0 lines**; no PIL node anywhere in `ioreg` |
| fixed-point decode (16.16) | `BLNitsCap = 26227508` → **400.2 nits**, exactly matching `brightness limit: 400.2` in the logs; `IOMFBIndicatorNitsCap` → 1600 nits (panel HDR peak) |

The mic test is the one that could have overturned this and did not: the indicator lights, the field does not move — consistent with the indicator being rendered on screen and this hardware channel being absent.

### Binary analysis — by **DeepSeek v4 Pro**, partially re-verified here

Static reverse engineering of the shipped binaries (log format string → cross-reference scan → disassembly → symbol archaeology) established:

- both emitters assign NaN as a **literal constant** (`mov x8, #0x7ff8000000000000` / `mov w8, #0x7fc00000`), never as the result of arithmetic — `CA::WindowServer::IOMFBDisplay::swap_brightness()` and `-[CAWindowServerDisplay commitBrightness:withBlock:]_block_invoke`; the same code also *checks* for NaN, so it is a designed-for state;
- three sentinel conventions coexist in one record: NaN, `-1.0`, and integer `-1`;
- `-[CBDisplayModuleSKL displayBrightnessUpdate]` writes the NaN when `CBU_IsSecureIndicatorSupported()` is false, and that gate reads a bool from `IODeviceTree:/backlight`.

**What was re-verified here:** every cited string exists in the shared cache (7/7 including a control), and the `PIL` string family is real — `PIL Camera State Set to`, `PIL Mic State Set to`, `PIL Duty cycle overriden to`, `PIL calibration from EDT`. **What was not:** the disassembly itself, the instruction-level claims, and the function identifications — those rest on DeepSeek's analysis.

### Corrections this supersedes

- **"~116 Hz toggle" (this entry's title)** — a brightness ramp, not an oscillation. See the 2026-08-13 correction above.
- **"every field including `ambient lux` reads `nan`, so Auto-Brightness runs on garbage input"** — false. `commitBrightness` records carry a valid `ambient lux: 419.248` at the same instant a `swap` record shows `nan`, matching corebrightnessd's own `AggregatedLux value=419.2484`. The `swap` record simply does not carry those fields.
- **"a physical LED in the display module"** — wrong, and it was ours as well as DeepSeek's; Apple's own title says **on-screen**. Retracted.
- **"% of windows with nan" as a defect rate** — it is not. It measures how much brightness/EDR churn happened in that period. Display-off silences the stream entirely, and so does a static desktop with the display *on* (observed: 25 minutes of zero lines with the display awake).

### Still unexplained (kept rather than buried)

- The `PIL` string family reads like a physically driven light (PWM duty cycle, calibration from EDT) while Apple's Mac-facing documentation says *on-screen*. Plausibly shared code with platforms that do have a physical indicator — **unverified**.
- What `SILMgr`'s four regions are; the exact EDT property name the gate reads (its string sits behind a PAC'd pointer).
- Dead ends recorded so they are not re-walked: RTTI is stripped and vtables are PAC-signed, so vtable archaeology fails; `lldb image lookup -r -s` on the cache returns nothing for these strings; and `log` is a zsh builtin that silently returns empty through a pipe (already documented in [`tools/mds-storm-watch.sh`](../tools/mds-storm-watch.sh) and hit again independently).

**Status: ⚪ not a defect — expected logging on hardware without the Secure Indicator capability.**

**结论**：`nan` 是苹果代码显式赋的「本字段未设置」哨兵；唯一永远填不上的 `indicator brightness`，对应的是 [MacBook Neo(A18 Pro)专用硅](https://support.apple.com/guide/security/mac-on-screen-camera-indicator-light-sec75a2d237d/web) 才具备的屏内安全摄像头指示灯能力，本机 `IOMFBSupportsSecureIndicator = No`，整条通道关闭，故恒为 `nan`，与 macOS 版本无关。开麦克风实测不改变该字段（橙点是屏幕渲染，不走这条通道）。非缺陷，不报 Feedback。反汇编由 **DeepSeek v4 Pro** 完成，本机复核了其引用的全部字符串与 ioreg 门控，未复核指令级断言。

## Re-measurement 2026-08-19 — beta6 `26A5416b` — frequency up 4–5×, cost bounded

### The mechanism is unchanged, and this file's reading of it was right

A contiguous sample, one line per frame at 120 Hz:

```
15:11:32.693  headroom=1.00023  potential=16  sdr=53.8807  lux=26.8143
15:11:32.697  headroom=1.00099  potential=16  sdr=53.8807  lux=26.8143
15:11:32.708  headroom=1.00138  ...
15:11:32.929  headroom=1.02213  ...
```

`sdr` and `ambient lux` are constant throughout; only `headroom` moves, in ~0.00077 steps
every ~8.3 ms. **A ramp, not an oscillation** — which is what the 2026-08-13 correction in this
file already said. At that step size a full 1 → 16 traversal takes ~2.7 minutes.

### What did change: frequency

| | seconds containing brightness lines |
|---|---|
| beta5 `26A5406e` | 21 of 300 (**7 %**) |
| beta6, spot sample | 46 of 300 (15 %) |
| beta6, 30-minute window | **599 of 1800 (33 %)** — 124,737 lines |

The "rare, not a permanent loop" framing that supported the ⚪ was measured at 7 % coverage.
At 33 % it is no longer rare, though it is still bursty rather than continuous.

### What was never measured: the cost

Paired sampling, 20 s windows, app set and window set held constant across all six:

| window | WindowServer | brightness lines/20 s |
|---|---|---|
| 1 | 49.4 % | 478 |
| 2 | 45.8 % | 0 |
| 3 | 46.5 % | 0 |
| 4 | 49.1 % | 480 |
| 5 | 51.7 % | 471 |
| 6 | 42.8 % | 0 |

Burst mean **50.1 %**, quiet mean **45.0 %** → **~5 points** at ~24 lines/s. The groups do not
overlap (burst min 49.1 > quiet max 46.5) but n = 3 per group, in one session, with Claude.app
open — so the absolute level is inflated by a constant, and only the difference is meaningful.

**A ~20-point figure from earlier the same day is withdrawn.** It came from comparing two single
runs (4.5 % against 24.0 %) that had identical window sets but differed 36× in brightness rate.
The likely cause of that gap is not brightness at all: the 24.0 % run came from a sweep that ran
`killall Finder` before every step and measured 18 s later, so it was catching Finder rebuilding
the desktop. That also contaminates the window-count curve in
`baselines/beta6-26A5416b/`, which used the same sweep.

### Verdict

⚪ stands. The `nan` sentinel analysis is untouched, and the ramp is by design. What is now
documented that was not before: **coverage is 4–5× beta5's, and the ramp costs roughly 5 points
of a core while it runs.** Neither makes it a defect on its own; both are worth carrying if it
grows again.

2026-08-19 在 beta6 复测:机制不变,确认是**斜坡**(每帧 +0.00077,`sdr` 与 `lux` 全程不变),本文 08-13
的更正是对的。变的是**频率** —— 有亮度行的秒数占比从 beta5 的 7% 升到 **33%**(30 分钟窗口 124,737 行)。
另外第一次量了**代价**:配对采样下爆发比安静高约 **5 个点**(不是当天早些时候那个 20 点的估计,该估计已撤回 ——
那两次单跑之间真正的差异更可能是 `killall Finder` 后桌面重建)。⚪ 维持。
