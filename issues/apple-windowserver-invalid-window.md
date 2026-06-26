# WindowServer high CPU + repeating `_CGXPackagesSetWindowConstraints: Invalid window`
# WindowServer 持续高 CPU + SkyLight 反复报 Invalid window

| | |
|---|---|
| **Status** | ⚪ Needs more isolation |
| **macOS** | 27.0 beta2 `26A5368g` |
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

- **System Settings → Accessibility → Display → Reduce transparency** + **Reduce motion** — cuts Liquid Glass compositing cost.
- Identify the app whose window triggers `Invalid window` and restart that app. **Do not** `killall WindowServer` — that logs you out.
- Close unused windows / Spaces.

## TODO

- [ ] Correlate the `Invalid window` errors to a specific PID/app (e.g. via `sudo log stream` + window-list inspection) before filing Feedback.
