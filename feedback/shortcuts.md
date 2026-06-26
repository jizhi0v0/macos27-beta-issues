VERIFICATION: TRANSIENT — not reproduced at uptime 39 min (0 com.apple.shortcuts / 0 BackgroundShortcutRunner / 0 siriactionsd ToolKit lines in `log show --last 60s`, 2026-06-26 10:32 +0800, beta2 26A5368g); fires post-boot then self-settles. Filed on the basis of the earlier captured storm.

# Title
Shortcuts/App Intents ToolKit registration storm at boot: BackgroundShortcutRunner + siriactionsd flood logd (~370 lines/sec combined) before self-settling

# Apple area / component to select
Siri & Shortcuts (Shortcuts / App Intents). Related: siriactionsd, WorkflowKit/ActionRegistry.

# Description
On macOS 27.0 (26A5368g), shortly after boot `BackgroundShortcutRunner` and `siriactionsd` flood the unified log churning `com.apple.shortcuts:ToolKitExecutionPool` state transitions and re-fetching App Intents action records in a loop, at a measured ~370 lines/sec combined. The daemons' own CPU stays low, but the volume feeds logd (disk + CPU). No user-installed looping automation was running — this is the system App Intents registration path re-enumerating every app's actions, likely tied to macOS 27's deeper Siri / Apple Intelligence integration.

This is intermittent: it fires in the minutes after boot and then quiesces. At a fresh retest (uptime 39 min) the storm was fully settled — `log show --last 60s` returned 0 `com.apple.shortcuts` lines, 0 `BackgroundShortcutRunner` lines, and 0 `siriactionsd` ToolKit lines; only background ToolKit traffic was duetexpertd enumerating an empty toolKit stream (0 events). The storm therefore could not be reproduced live at that moment, and this report is filed on the basis of the earlier capture, included below.

# Steps to Reproduce
1. Boot a Mac into macOS 27.0 26A5368g with several apps installed that vend App Intents / Shortcuts actions.
2. Immediately after login, run `log show --last 30s --style syslog` and count lines from `BackgroundShortcutRunner` and `siriactionsd`.
3. Observe (during the post-boot window) a large burst; repeat the same command ~30+ min later and observe it has settled to ~0.

# Expected vs Actual
- Expected: App Intents / Shortcuts action registration runs once at boot with bounded log volume at debug level.
- Actual (post-boot window): BackgroundShortcutRunner ~6186 lines and siriactionsd ~4820 lines per 30s (≈370/sec combined) of ToolKitExecutionPool state changes and ToolKitDatabase single-record fetches, persisted by logd. Self-settles to ~0 within minutes.

# Prior captured evidence (earlier boot, beta2 26A5368g)
```
siriactionsd  (ToolKit) [com.apple.shortcuts:ToolKitExecutionPool] Executor pool state change from <private> to <private>
siriactionsd  (ToolKit) [com.apple.shortcuts:ToolKitExecutionPool] Queuing new state <private>
BackgroundShortcutRunner  (ToolKit) [com.apple.shortcuts:ToolKitDatabase] Fetching single record using request: <private>
BackgroundShortcutRunner  (WorkflowKit) [com.apple.shortcuts:ActionRegistry] -[WFBundledActionProvider createActionsForRequests:forceLocalActionsOnly:] Found actions: (...)
```
`log show --last 30s` top emitters: BackgroundShortcutRunner 6186 lines, siriactionsd 4820 lines.

# Configuration
- MacBook Pro Mac15,11, M3 Max, 36 GB
- macOS 27.0 26A5368g
- Single internal display, no external monitor

# Suggested attachments
- sysdiagnose taken within the first few minutes of boot (while the storm is active)
- `log collect --last 5m` archive captured immediately post-boot
- Saved `log show --last 30s` output from the post-boot window showing the BackgroundShortcutRunner / siriactionsd line counts
