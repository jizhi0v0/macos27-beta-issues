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

**Retest 2026-06-26 beta2 26A5368g:** CONFIRMED — uptime 39 min; WindowServer[445] 61.7% CPU, cumulative TIME 18:16 (≈47% avg over 39 min, consistent with prior ≈48%). `log show --last 60s` = 159 `_CGXPackagesSetWindowConstraints: Invalid window`, steady ~2.6/sec across the whole window (span 10:31:59→10:32:58), NOT a post-boot transient. **Owning-app hypothesis (uncertain, not fact):** strongest correlated signal in the same window is `WindowServer: pid 1437 failed to act on a ping it dequeued before timing out` ×5 — PID 1437 = `/usr/libexec/textunderstandingd` (Apple Intelligence text-understanding daemon). A non-responsive client failing WindowServer pings is consistent with a window stuck in a bad/zombie constraint state. No external display attached. Treat textunderstandingd as a lead, not a confirmed culprit — the `Invalid window` lines themselves carry no PID, so attribution is inferred from the co-occurring ping timeout only.

**Re-check 2026-06-26 (textunderstandingd hypothesis WITHDRAWN):** Re-measured at WindowServer 73.1% CPU, 362 `Invalid window` in 90s (~4/s, worse than before). The "failed to act on a ping" clients are now **five unrelated system services at once** — `textunderstandingd`, `studentd`, `nsattributedstringagent` (×2 PIDs), `universalaccessd`. Five unrelated daemons failing pings simultaneously means the ping timeouts are a **symptom of WindowServer being saturated (slow to answer pings), not the cause** — so `textunderstandingd` was a red herring. **The window that triggers the `Invalid window` loop remains unidentified.** Proper isolation needs a CGWindowList / window-server dump correlating the invalid window id, which the unattributed log line doesn't provide.

**Spindump 2026-06-26 — CPU is generic CoreAnimation compositing, NOT the log line; remote-capture hypothesis CHECKED & REJECTED:** `sudo spindump WindowServer 8` shows `_CGXPackagesSetWindowConstraints` in **0** hot stacks — the `Invalid window` line is a cheap error log, not where CPU goes. WindowServer's real work is continuous CoreAnimation layer compositing (`CA::Render::Updater::prepare_layer0/prepare_sublayer0`, `CA::OGL::prepare_layers`, `ImagingNode::render`). A hypothesis that remote-desktop screen capture (AweSun/ToDesk) forced this was **rejected** on inspection: `replicatord` is iCloud/IDS **data** sync (ReplicatorEngine), not screen replication; `ScreenSharingSubscriber`×2 and `AweSun_Helper` were idle (0 log lines/60s); ToDesk only polls display modes (~36 `SLSGetDisplaysWithOpenGLDisplayMask`/min). The sustained 47–73% reads as **generic compositing load** — most plausibly Liquid Glass + many simultaneously-animating windows (243 on screen; a single playing video forces per-frame compositing). **Not isolated to a distinct, filable regression — downgraded from file-ready to HOLD.** Needs a re-test on a quiesced desktop (no video, minimal windows, idle) to separate a real WindowServer regression from ordinary compositing workload. The only clearly-anomalous leftover is the continuous `Invalid window` log spam (minor).
