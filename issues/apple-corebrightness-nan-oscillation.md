# `corebrightnessd` toggles a key 1/0 at ~116 Hz for 12 s while every brightness value reads `nan`
# `corebrightnessd` 以 ~116Hz 反复翻转 1/0 持续 12 秒，且所有亮度值均为 `nan`

> 🔗 **Track / 关注此问题:** *(GitHub issue to be created)*

| | |
|---|---|
| **Status** | 🟡 Open · confirmed on beta4, low frequency (once per ~30 min) |
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
