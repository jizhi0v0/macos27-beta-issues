# OrbStack crash: SwiftUI Charts → `AttributeGraph` extended-attribute alloc abort
# OrbStack 崩溃：SwiftUI Charts 触发 AttributeGraph 属性分配失败 abort

| | |
|---|---|
| **Status** | 🟡 Mitigated — Apple framework regression, no app-side fix |
| **macOS** | 27.0 beta1 `26A5353q` (retest on beta2 pending) |
| **Component** | Apple **SwiftUI / AttributeGraph** ↔ OrbStack **2.2.1 (20628)** (non-MAS) |
| **Hardware** | `Mac15,11`, M3 Max, 36 GB |
| **Report** | Upstream: [orbstack#2526](https://github.com/orbstack/orbstack/issues/2526) · Apple Feedback: `FB________` |

## Symptom / 症状

After OrbStack's GUI has been running for a while (~2h50m, reliably), the app aborts. The crash is inside SwiftUI Charts rendering the usage chart — `AttributeGraph` fails to allocate an extended attribute table and calls `abort()`.

OrbStack GUI 正常运行一段时间后（约 2h50m，稳定复现）崩溃。崩在 SwiftUI Charts 渲染使用率图表时——`AttributeGraph` 扩展属性表分配失败 → `abort()`。

## Evidence / 证据

Crash originates in Apple's `AttributeGraph` / SwiftUI Charts stack, not OrbStack logic. OrbStack author **kdrag0n** (2026-06-13) confirmed it's a SwiftUI/framework bug, could not reproduce it himself, and recommended filing with Apple.

## Workaround / 临时规避

**Don't sit on the charts view for hours.** The specific screen is the sidebar's **General → Activity Monitor** view — its bottom four panels (Total CPU / Memory / Network / Disk) are live SwiftUI Charts time-series that continuously re-render and accumulate AttributeGraph attributes. Switch back to any static list page (Containers / Images / Volumes / Pods / Machines) when done; those don't draw the live charts.

具体界面是左侧栏 **General → Activity Monitor**：底部四块 Total CPU / Memory / Network / Disk 面板是 SwiftUI Charts 实时曲线，持续重绘会累积 AttributeGraph 属性 → 几小时后 abort。看完切回任意静态列表页（Containers/Images/Volumes/Pods/Machines）即可绕过；别把 OrbStack 长期停在 Activity Monitor 这一屏。

## Notes / 备注

- Confirmed still present on beta2 by inference (no SwiftUI Charts fix in beta2 changelog); explicit beta2 reproduction TODO.
- issue #2526 kept open as an anchor to track across betas.

**Retest 2026-06-26 beta2 26A5368g:** HOLD / NO FRESH EVIDENCE — no OrbStack*.ips anywhere in `~/Library/Logs/DiagnosticReports/` or `Retired/`; grep for `AttributeGraph`/`OrbStack`/`Charts` across all reports returned zero hits. Newest crash report on disk is 2026-06-25 (non-OrbStack). The prior beta1 `26A5353q` crash report is no longer on disk (purged). OrbStack 2.2.1 still installed. No crash captured on beta2 — needs fresh repro before filing.

**Live repro attempt 2026-06-26 — NOT REPRODUCED on beta2 (likely fixed):** OrbStack 2.2.1 kept on the **General → Activity Monitor** charts view and monitored for **3h21m** (well past the beta1 ~2h50m crash point). RSS trend (sampled每60s): grew briefly to ~197 MB early, then **fell back and plateaued at ~150–185 MB for the remaining 2.5h** — the opposite of beta1's unbounded `AttributeGraph` growth → alloc-abort. CPU 0% at idle, no crash, no `.ips`. Memory is being reclaimed instead of accumulating unbounded → the SwiftUI Charts / AttributeGraph leak does **not** reproduce on beta2. Caveat: idle CPU was 0% (charts may have been throttled while the window was occluded/backgrounded), so this is "doesn't crash under normal use" rather than a guaranteed code-level fix — but the plateau (vs runaway) is strong evidence. Status → 🟢 likely fixed on beta2.
