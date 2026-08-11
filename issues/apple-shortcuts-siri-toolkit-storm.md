# Shortcuts/Siri `ToolKit` action-registration storm (BackgroundShortcutRunner + siriactionsd)
# 快捷指令/Siri 动作注册风暴：BackgroundShortcutRunner + siriactionsd 刷爆日志

> 🔗 **Track / 关注此问题:** [#2 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/2)

| | |
|---|---|
| **Status** | 🟡 Mitigated — self-settles post-boot; ⚪ not reproduced in a beta3 `26A5378j` window (post-boot transient) |
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

**Retest 2026-07-07 beta3 26A5378j:** ⚪ same TRANSIENT profile — at ~2.5 h uptime, **0** `siriactionsd` / ToolKit registration lines since boot. The storm is a post-boot burst that self-settles (as on beta2), so a mid-session window can't confirm fix or regression; it would need a capture starting at the next clean boot.

## Retest 2026-08-11 — beta5 `26A5406e` — STILL PRESENT, storm lives in the first ~3 minutes / 仍在,风暴集中在开机头三分钟

Captured in a **deliberate post-boot window**. Per-minute `siriactionsd` volume from boot (17:29:08):

| minute | lines | rate |
|---|---|---|
| 17:29 (partial) | 6 | 0.1/s |
| **17:30** | **10,863** | **181/s** |
| 17:31 | 840 | 14/s |
| 17:32 | 85 | 1.4/s |
| 17:33 onwards | ~0 | — |

12,421 lines total in the window, **6,994 of them `ToolKit`**; `BackgroundShortcutRunner`, `BiomeAgent` and `intelligenceflowd` also participate. `siriactionsd` costs **1.77%** cumulative since boot.

The self-settling behaviour is exactly as documented — and it is also why this entry sat at ⚪ for three builds: **the storm is over within ~3 minutes of boot**, so any retest that does not start at boot will report "not reproduced". That is a missed window, not a fix.

2026-08-11 于 beta5 专门重启后取样:**仍复现**。开机后第一个整分钟 **10,863 行(181/秒)**,随后 14/秒 → 1.4/秒,**三分钟内收敛**。窗口内共 12,421 行,其中 `ToolKit` 6,994 条;`siriactionsd` 累计仅 1.77% CPU。自行平息的行为与原记录一致 —— 这也正是本条在三个 build 里停留于 ⚪ 的原因:**风暴只存在于开机后约 3 分钟内**,任何不从开机起算的复测都会报"未复现",那是**错过窗口**,不是修复。
