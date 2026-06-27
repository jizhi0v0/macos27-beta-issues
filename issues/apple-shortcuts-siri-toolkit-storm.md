# Shortcuts/Siri `ToolKit` action-registration storm (BackgroundShortcutRunner + siriactionsd)
# 快捷指令/Siri 动作注册风暴：BackgroundShortcutRunner + siriactionsd 刷爆日志

> 🔗 **Track / 关注此问题:** [#2 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/2)

| | |
|---|---|
| **Status** | 🟡 Mitigated — self-settles post-boot |
| **macOS** | 27.0 beta2 `26A5368g` |
| **Component** | Apple **Shortcuts / App Intents** (`com.apple.shortcuts`), `siriactionsd`, `BackgroundShortcutRunner` |
| **Report** | Apple Feedback: `FB________` *(to be filed)* |

## Symptom / 症状

Post-boot, `BackgroundShortcutRunner` and `siriactionsd` flood the unified log at ~370 lines/sec combined, churning `ToolKitExecutionPool` state transitions and re-fetching App Intents action records in a loop. This feeds `logd` (disk + CPU) even though the daemons' own CPU stays low. Likely tied to macOS 27's deeper Siri / Apple-Intelligence App-Intents integration re-enumerating every app's actions.

开机后 `BackgroundShortcutRunner` + `siriactionsd` 以约 370 行/秒刷系统日志，在死循环里做 `ToolKitExecutionPool` 状态机切换 + 反复拉取 App Intents 动作记录。daemon 自身 CPU 不高，但喂爆了 logd。疑与 macOS 27 集成 Siri AI 后重新枚举所有 app 的快捷指令动作有关。

## Evidence / 证据

`log show --last 30s` top emitters: `BackgroundShortcutRunner` 6186 lines, `siriactionsd` 4820 lines.

```
siriactionsd  (ToolKit) [com.apple.shortcuts:ToolKitExecutionPool] Executor pool state change from <private> to <private>
siriactionsd  (ToolKit) [com.apple.shortcuts:ToolKitExecutionPool] Queuing new state <private>
BackgroundShortcutRunner  (ToolKit) [com.apple.shortcuts:ToolKitDatabase] Fetching single record using request: <private>
BackgroundShortcutRunner  (WorkflowKit) [com.apple.shortcuts:ActionRegistry] -[WFBundledActionProvider createActionsForRequests:forceLocalActionsOnly:] Found actions: (...)
```

- `siriactionsd` own CPU ≈ 0%, cumulative 0:48 — it's a **log-flood**, not a direct CPU hog.
- `BackgroundShortcutRunner` is short-lived (spawns/exits), not resident.

## Workaround / 临时规避

- Mostly self-settles a few minutes after boot — usually no action needed.
- To stop the `logd` cost during the storm (reversible, root, resets on reboot):
  ```bash
  sudo log config --subsystem com.apple.shortcuts --mode "level:off"
  sudo log config --subsystem com.apple.shortcuts --mode "level:default"  # restore
  ```

## Notes / 备注

Appears to be a beta inefficiency in the App Intents registration path rather than a user-installed runaway Shortcut (no looping automation was running on the test machine).

**Retest 2026-06-26 beta2 26A5368g:** TRANSIENT — uptime 39 min; `log show --last 60s` = 0 `com.apple.shortcuts` lines, 0 `BackgroundShortcutRunner`, 0 `siriactionsd` ToolKit lines (the only 2 `siriactionsd` hits were RunningBoard connection records, not the storm). Only ToolKit/WorkflowKit traffic = duetexpertd enumerating an empty toolKit stream (0 events) + one ShortcutsViewService launch record. Storm fires post-boot then self-settles; cited prior evidence (BackgroundShortcutRunner 6186 / siriactionsd 4820 lines per 30s) stands as the captured signature. Not reproduced live at this uptime.
