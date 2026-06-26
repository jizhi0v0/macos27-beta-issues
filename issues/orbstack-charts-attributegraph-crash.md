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

**Don't keep the usage-chart window open long.** Closing/avoiding the charts view dodges the AttributeGraph path.

不要让「使用率图表」窗口长期开着；避开 charts 视图即可绕过。

## Notes / 备注

- Confirmed still present on beta2 by inference (no SwiftUI Charts fix in beta2 changelog); explicit beta2 reproduction TODO.
- issue #2526 kept open as an anchor to track across betas.
