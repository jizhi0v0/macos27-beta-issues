# appstoreagent + dasd retry-loop: Arcade usage-summary background task rejected (`BGSystemTaskSchedulerErrorDomain Code=8`) with no backoff → log flood + CPU spikes
# appstoreagent 后台任务被拒(Code=8)无退避死重试 → 刷爆日志 + CPU 阵发飙高

> 🔗 **Track / 关注此问题:** [#15 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/15)

| | |
|---|---|
| **Status** | ⚪ **still not triggered on release `26A428`** (2026-09-16) — **0** `Code=8` in a 10-minute window, six consecutive clean builds (beta3/5/6/7/8 + release). The one appstoreagent diagnostic report since install is a **disk-writes** report (2,148 MB over 19.6 h), not this retry loop. Not reproduced ≠ fixed. See [`baselines/release-26A428/`](../baselines/release-26A428/README.md). Prior: ⚪ **still not triggered on beta8 `26A5425a`** (2026-09-03) — **0** `Code=8` in a 10-minute window, making beta3/5/6/7/8 five consecutive clean builds. Conditional trigger, last actually seen on beta2. Not reproduced ≠ fixed. Prior: ⚪ **still not triggered on beta7 `26A5421a`** (2026-08-27) — **0** `BGSystemTaskSchedulerErrorDomain Code=8` in the 8-minute post-boot window, making beta3, beta5, beta6 and beta7 all clean. The trigger is conditional and was last actually seen on **beta2**. Four clean windows across four builds are grounds to consider closing this as *cannot reproduce* — they are **not** a positive signal and must not be written up as 🟢. See *Retest on beta7* below. Prior: ⚪ Not reproduced in beta3 `26A5378j` window (conditional trigger); confirmed beta2 |
| **macOS** | confirmed 27.0 beta2 `26A5368g`; not observed in a beta3 `26A5378j` window |
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

## Retest on beta3 `26A5378j` (2026-07-07) — not reproduced this window / 本窗口未复现

Since the beta3 boot (07:53, ~2.5 h): **0** `appstoreagent` log lines, **0** `BGSystemTaskSchedulerErrorDomain Code=8`, **0** `usage-summary` mentions. So the retry-loop is **not currently running**. Caveat: this bug is **conditional** — it fires when `appstoreagent` actually tries to schedule the Arcade usage-summary BG task and gets rejected. That trigger simply didn't occur in this window, so this is **"not reproduced," not "confirmed fixed."** To settle it, force the Arcade summary path (or watch across a longer span that includes one of its scheduling attempts) and recheck for `Code=8`.

## Retest on beta7 `26A5421a` (2026-08-27) — still not triggered

Measured on the 2026-08-27 13:39:10 boot, three days into the build (beta7 was installed
**2026-08-24 23:33** per `InstallHistory.plist` — the Aug 21 mtime on the system files is the
image build date, not the install date). Raw counts and the capture caveats are in
[`baselines/beta7-26A5421a/`](../baselines/beta7-26A5421a/README.md).

**0** `BGSystemTaskSchedulerErrorDomain Code=8`, **0** `appstoreagent` scheduling failures in the
8-minute post-boot window. That now makes beta3, beta5, beta6 and beta7 all clean.

This remains **"not reproduced," not "fixed"** — the trigger is conditional (appstoreagent has to
actually attempt the Arcade usage-summary background task and be rejected), and it has simply not
attempted one in any observed window since beta2. Four clean windows across four builds is worth
recording as a reason to consider closing this as *cannot reproduce*, but it is not a positive
signal and must not be written up as 🟢.

2026-08-27 beta7 复测:开机后 8 分钟窗口 `BGSystemTaskSchedulerErrorDomain Code=8` **0 条**。
beta3、beta5、beta6、beta7 四个 build 全部干净 —— 但触发条件是**条件性**的(要 appstoreagent 真的去调度
Arcade 用量汇总任务并被拒),自 beta2 后就没再触发过。这是 **"未复现" 而非 "已修复"**,
可以据此考虑按 *cannot reproduce* 关闭,但**不能标 🟢**。

## Re-verification 2026-09-03 — beta8 `26A5425a` — still not triggered

> **Clock position, because it decides what these numbers can be compared to.** beta8
> `26A5425a` was installed **2026-09-02 04:57:15** (`InstallHistory.plist`). Every figure below
> was taken at **T+21h20m** on the 2026-09-02 12:55:26 boot — a **steady-state** window, not the
> post-boot window beta6 (T+9m) and beta7 (T+0→8m) used. Log *volumes* are therefore **not**
> matched pairs with those builds and are not presented as such. Kernel unchanged for a third
> beta: `xnu-13432.1.9~3`. Raw capture: [`baselines/beta8-26A5425a/`](../baselines/beta8-26A5425a/README.md).

**0** `BGSystemTaskSchedulerErrorDomain Code=8` in the 10-minute window, as on beta3, beta5,
beta6 and beta7 — five consecutive clean builds. The trigger is conditional (Arcade background
task scheduling) and was last actually observed on beta2.

**Not reproduced ≠ fixed.** Nothing in this window exercised the trigger deliberately, so this is
an absence of observation, not a positive signal, and the status stays ⚪ rather than 🟢.

2026-09-03 beta8 复测:窗口内 **0** 条 `Code=8`,beta3/5/6/7/8 连续第五个干净构建。触发条件是条件性的,
最后一次真正观察到是在 beta2。**未复现 ≠ 已修复** —— 本轮没有刻意触发该路径,因此仍记 ⚪ 而非 🟢。

## Re-verification 2026-09-16 — release `26A428` — still not triggered

> **Clock position, because it decides what these numbers can be compared to.** The release
> build `26A428` was installed **2026-09-11 04:28:46** (`InstallHistory.plist`). Every figure below
> was taken at **T+6h29m** on the 2026-09-16 11:40:46 boot with ~40 apps running — matched neither
> to beta8's T+21h20m window nor to beta6/beta7's post-boot windows, so log *volumes* are not
> presented as pairs. Kernel `xnu-13432.1.9~1` (beta6–beta8: `~3`). Raw capture:
> [`baselines/release-26A428/`](../baselines/release-26A428/README.md).

**0** `BGSystemTaskSchedulerErrorDomain Code=8` in the 10-minute window 18:09–18:19; `appstoreagent`
logged 28 records in the same window and measured 0.0% CPU over a 120 s cumulative sample, `dasd`
0.1%. That makes beta3, beta5, beta6, beta7, beta8 and the release build six consecutive clean
windows. The trigger is conditional and was last actually observed on beta2.

One appstoreagent report exists since the release install, and it is **not** this issue:
`appstoreagent_2026-09-15-104329….diag` is `Event: disk writes` — 2,148.53 MB of file-backed memory
dirtied over 70,621 s, against a limit of 24.86 KB/s over 24 h. Recorded so a filename search does not
mistake it for a recurrence.

**Not reproduced ≠ fixed.** Nothing exercised the trigger, so the status stays ⚪.

2026-09-16 正式版 `26A428` 复测:窗口内 **0** 条 `Code=8`,连续第六个干净构建。安装后唯一一份
appstoreagent 诊断报告是**磁盘写入**报告(19.6 小时写 2,148 MB),不是本条的重试环路,特此记录以免被
按文件名误判为复发。**未复现 ≠ 已修复**,仍记 ⚪。
