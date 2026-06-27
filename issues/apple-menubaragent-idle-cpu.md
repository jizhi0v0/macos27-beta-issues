# MenuBarAgent sustains ~10–14% CPU at idle with a static menu bar
# MenuBarAgent 在静态菜单栏下 idle 空转 ~10–14% CPU

> 🔗 **Track / 关注此问题:** [#12 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/12)

| | |
|---|---|
| **Status** | ✅ CONFIRMED beta2 — likely a macOS 27 MenuBarAgent regression (upstream sender unidentified) |
| **macOS** | 27.0 beta2 `26A5368g` |
| **Component** | Apple **MenuBarAgent** (`/System/Library/CoreServices/MenuBarAgent.app`, the macOS 27 menu-bar agent) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max, single internal display |
| **Report** | Apple Feedback: **`FB23411741`** (filed 2026-06-26, Menu Bar → Incorrect/Unexpected Behavior; sysdiagnose + idle `sample` capture attached) |

## Symptom / 症状

`MenuBarAgent` (PID 702) holds **~10–14% CPU sustained** even when no menu-bar app is updating its status item. Cumulative TIME climbs steadily.

`MenuBarAgent` 持续吃 ~10–14% CPU,即使没有任何菜单栏 app 在更新状态项;累计 TIME 稳涨。

## How it was isolated / 怎么排除到它

Removed every known live status-item updater and re-measured — MenuBarAgent did **not** drop:
- Quit Macs Fan Control (live temp/RPM text).
- Set Surge to icon-only (stopped its per-second network-speed text).
- The chatty `ClaudeUsageMenuBar` was fixed (status-item redraws 4→0 at idle, verified) and even its fixed build running doesn't move the number.
- `log show --last 20s` for `StatusItem`/`NSStatusBar`/`drawWithFrame`/`_updateReplicants` → **0 lines** (no app is redrawing the menu bar).

Yet MenuBarAgent stays ~10–14%. With zero menu-bar redraw activity feeding it, the cost is MenuBarAgent's own.

## Evidence / 证据

`sample MenuBarAgent 3`, idle, top-of-stack:
- Mostly parked in `mach_msg2_trap` / `__workq_kernreturn` (receiving messages), BUT with a continuous trickle of small Swift work: `swift_cvw_initWithCopyImpl`, `swift_cvw_destroyImpl`, `Hasher.combine(bytes:)`, `swift_retain`, `_platform_memmove`, tiny mallocs.
- I.e. it's **processing a steady stream of small messages/value-copies at idle**, not pegged on one hot function and not driven by a visible status-item redraw.

## Open question / 未解

The **sender** of that continuous message stream is not identified from MenuBarAgent's side — something keeps handing it small work. Could be a system component re-registering menu-bar state, or a still-running (but non-logging) menu-bar client. A full sysdiagnose / XPC-connection inspection would be needed to name the source.

## Workaround / 临时规避

None app-side that fully clears it (it persists with menu-bar apps removed). Reducing the number of menu-bar items / using less chatty ones lowers the *additional* load on top of this baseline but doesn't remove the ~10–14% floor. Beta regression — expect a fix in a later beta.

## Notes / 备注

- Distinct from [WindowServer high CPU](apple-windowserver-invalid-window.md): that is broader CoreAnimation compositing (dominated by live-rendering apps); MenuBarAgent's ~10–14% is its own process and only a partial contributor to WindowServer.
- Consistent across many measurements this session (~12–14%), independent of which apps are running → reads as a macOS 27 beta2 baseline, not app-fed.
- **Strongest confirmation:** after the user quit nearly all menu-bar apps (only system `ControlCenter` + a couple icon-only items left, `log show` showing **0** status-item redraws), MenuBarAgent still held **12.5%**. With essentially nothing feeding it, the cost is MenuBarAgent's own — confirms a genuine beta2 regression rather than app-driven load.
