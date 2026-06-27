# appstoreagent + dasd retry-loop: Arcade usage-summary background task rejected (`BGSystemTaskSchedulerErrorDomain Code=8`) with no backoff → log flood + CPU spikes
# appstoreagent 后台任务被拒(Code=8)无退避死重试 → 刷爆日志 + CPU 阵发飙高

> 🔗 **Track / 关注此问题:** [#15 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/15)

| | |
|---|---|
| **Status** | 🟠 Confirmed beta2 — internal retry loop (NOT network / NOT a proxy app) |
| **macOS** | 27.0 beta2 `26A5368g` |
| **Component** | Apple **appstoreagent** + **dasd** (DuetActivityScheduler) / BGTaskScheduler, around **App Store / Apple Arcade AppUsage** reporting |
| **Report** | Apple Feedback: **`FB23413997`** (filed 2026-06-26, App Store → Incorrect/Unexpected Behavior; sysdiagnose + log capture attached) |

## Symptom / 症状

`appstoreagent` periodically spikes to ~49% CPU and **floods the unified log — ~171,000 lines in 3 minutes (~950/s)**. `dasd` sits at ~30% concurrently. logd / diagnosticd get loaded (and Console.app, if open, chokes). Bursty: calm (0.4%) then heavy.

## Root cause / 根因

`appstoreagent` tries to schedule a background task to post Apple Arcade app-usage summaries, and the system background-task scheduler **rejects it**, then it **retries with no backoff**:

```
[com.apple.appstored:Activity] [ArcadePostSummary] Error occurred attempting to update task
  request; will request upon task completion (error: BGSystemTaskSchedulerErrorDomain Code=8)   ×3724/3min
[com.apple.appstored:AppUsage] [ArcadeSummary] found 6 event(s) → [ArcadeSummary] No events to report
[com.apple.appstored:Activity] [ArcadePostSummary] Reset with reason: Nothing to Post
(AppleMediaServices) AMSMetrics: ... Cannot schedule flush with style 2 ... not allowed         ×11000+/3min
(libxpc) ... invalidated because the current process cancelled the connection                    ×3729/3min
(BiomeFoundation) Created Activity ID ... _BMXPCFileManager._fileHandleForFileAtPath              ×11174/3min
```

The loop: request BG task to post the Arcade summary → `BGSystemTaskSchedulerErrorDomain Code=8` rejection → immediate re-request (no backoff) → hammer `dasd` → repeat thousands of times. `dasd` (the background-task scheduler) burns ~30% being hammered; both processes feed each other.

## NOT network / NOT a proxy app / NOT a network change

Checked explicitly: `appstoreagent`'s log has **no** `nw_`/CFNetwork/timeout/TLS/connection-failure errors; network path events in the window are normal (lo0 loopback, en0 link-quality, iCloud reachability = YES). The failure is `BGSystemTaskSchedulerErrorDomain Code=8` (a background-task scheduling rejection), not a network error. A proxy app (Surge) is not in the failing path. (Investigated because the loop touches Accounts/AMS/XPC, but the controlling error is BGTask scheduling, internal.)

## Impact & workaround

- Floods logd/diagnosticd (Console.app becomes unusable if open), periodic ~49% CPU, contributes to overall system churn.
- `killall appstoreagent` only buys time — launchd relaunches it and the loop resumes.
- No user-side fix; it's an internal beta retry-loop bug (appstoreagent should back off on `Code=8`). Likely related to Apple Arcade usage reporting even when Arcade isn't used.

## Notes / 备注

- Same family as the [Shortcuts/Siri ToolKit storm](apple-shortcuts-siri-toolkit-storm.md): a system service stuck in a retry/scheduling loop on beta.
- Decisive evidence for Feedback: the `BGSystemTaskSchedulerErrorDomain Code=8` ×3724/3min + the ~171k-lines/3min log volume + dasd at ~30%, from a `log show` capture / sysdiagnose.
