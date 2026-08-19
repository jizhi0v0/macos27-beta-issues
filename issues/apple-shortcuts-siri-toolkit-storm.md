# Shortcuts/Siri `ToolKit` action-registration storm (BackgroundShortcutRunner + siriactionsd)
# 快捷指令/Siri 动作注册风暴：BackgroundShortcutRunner + siriactionsd 刷爆日志

> 🔗 **Track / 关注此问题:** [#2 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/2)

| | |
|---|---|
| **Status** | 🟡 **still present on beta6 `26A5416b`, and measured worse** (2026-08-19): peak **864 lines/s** against beta5's 181, 16,203 lines in the 7m47s post-boot window, all three peak seconds within ~60 s of boot. Same window shape as the beta5 figure, so comparable — but **one window, not replicated, and not a verdict**. See [the beta6 section](#re-test-2026-08-19--beta6-26a5416b--peak-rate-4.8x-beta5s-one-window). Prior: 🟡 Mitigated — self-settles post-boot; ⚪ not reproduced in a beta3 `26A5378j` window (post-boot transient) |
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

## Re-test 2026-08-19 — beta6 `26A5416b` — peak rate 4.8× beta5's (one window)

Captured from the one-shot post-boot window after the beta5→beta6 upgrade (boot 13:12:23,
`log show --start <boot>`; `--last Nm` would have spanned the reboot and mixed the beta5 session in).

| | beta5 `26A5406e` (post-boot capture) | **beta6 `26A5416b`** |
|---|---|---|
| peak rate | 181 lines/s | **864 lines/s** |
| lines in window | 12,421 | 16,203 (in 7m47s) |

Busiest seconds: 864 @ 13:13:19, 725 @ 13:13:21, 640 @ 13:13:55 — all within ~60 s of boot, so the
"lives entirely in the first ~3 minutes" shape is unchanged; only the peak moved.

**Not a verdict.** This is a single window and has not been replicated, and replication needs
another reboot — the post-boot window is one-shot. Raw log archived outside the repo at
`~/Developer/macos27-beta6-postboot/`.

2026-08-19 在 beta5→beta6 升级后的首启窗口复测:峰值 **864 行/秒**(beta5 为 181),7分47秒内
16,203 行,三个峰值秒都在开机 60 秒内 —— 形状不变,只是峰值高了 4.8 倍。**单窗口未复现,不作结论**;
复现需要再次重启,首启窗口是一次性的。