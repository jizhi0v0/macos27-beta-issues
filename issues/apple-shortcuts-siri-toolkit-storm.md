# Shortcuts/Siri `ToolKit` action-registration storm (BackgroundShortcutRunner + siriactionsd)
# 快捷指令/Siri 动作注册风暴：BackgroundShortcutRunner + siriactionsd 刷爆日志

> 🔗 **Track / 关注此问题:** [#2 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/2)

| | |
|---|---|
| **Status** | 🟡 **still storming on 27.2 beta2 `26B5091g`** (2026-09-25) — **98,046** records from boot to 17:17, a boot burst peaking at **8,813 lines/s** (T+2m52s), then bursts of **1,885/s** at T+40m and ~1,550/s as late as T+2h10m; 48 seconds ≥ 500/s. No post-boot 10-minute bucket exceeds 9,411, where release's recurring bursts were ~17k each — a different clock position on one boot, so recorded, not credited. See [`../baselines/27.2-beta2-26B5091g/`](../baselines/27.2-beta2-26B5091g/README.md). Prior: 🟡 **still storming on release `26A428`, peak 3,033 lines/s** (2026-09-16) — a since-boot query returns **444,874** records, with ~17k-record bursts recurring from T+40m to at least T+5h50m after the boot burst and a peak second of **3,033/s** at T+2h17m (beta8: 1,644/s at T+21h). The 10-minute T+6h29m window, taken alone, fell in a lull — **182** records, peak 172/s — and would have read as fixed; the since-boot query is what shows it is not. See [`baselines/release-26A428/`](../baselines/release-26A428/README.md). Prior: 🟡 **still storming at T+21h on beta8 `26A5425a`, so it does not self-settle** (2026-09-03) — 15,672 records in a 10-minute steady-state window, peak **1,644 lines/s**. The totals are not comparable to beta7's (different window length and clock position) but the peak second is, and it lands within **9%** of beta7's 1,795/s — which was measured *inside* the boot burst. The standing reading carried since beta2, *"fires post-boot then self-settles"*, **does not hold on this build**. Prior: 🟡 **still present on beta7 `26A5421a` and higher again** (2026-08-27) — **30,699** records in the 8-minute post-boot window against beta6's 16,203 in 7m47s; peak **1,795 lines/s** counting all levels, **1,306** counting `Df` only, against beta6's 864 and beta5's 181. ⚠️ Beta6's figure was recorded without its log-level scope and the two scopes differ by **34%**, so which pair is like-for-like is undecided; and this is still **one window, not replicated, not a verdict** — a caveat now carried unaddressed for two builds. See *Re-test 2026-08-27* below. Prior: 🟡 **still present on beta6 `26A5416b`, and measured worse** (2026-08-19): peak **864 lines/s** against beta5's 181, 16,203 lines in the 7m47s post-boot window, all three peak seconds within ~60 s of boot. Same window shape as the beta5 figure, so comparable — but **one window, not replicated, and not a verdict**. See [the beta6 section](#re-test-2026-08-19--beta6-26a5416b--peak-rate-4.8x-beta5s-one-window). Prior: 🟡 Mitigated — self-settles post-boot; ⚪ not reproduced in a beta3 `26A5378j` window (post-boot transient) |
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

## Re-test 2026-08-27 — beta7 `26A5421a` — higher again, and still one unreplicated window

Measured on the 2026-08-27 13:39:10 boot, three days into the build (beta7 was installed
**2026-08-24 23:33** per `InstallHistory.plist` — the Aug 21 mtime on the system files is the
image build date, not the install date). Raw counts and the capture caveats are in
[`baselines/beta7-26A5421a/`](../baselines/beta7-26A5421a/README.md).

`BackgroundShortcutRunner` + `siriactionsd` in the 8-minute post-boot window:

| | beta5 `26A5406e` | beta6 `26A5416b` | **beta7 `26A5421a`** |
|---|---|---|---|
| records in the post-boot window | — | 16,203 (7m47s) | **30,699** (8m00s) |
| peak lines/s | 181 | 864 | **1,795** (all levels) / **1,306** (`Df` only) |

Peak seconds cluster the same way as before — 13:40:30 (+80 s from boot), 13:39:55, 13:40:22–24
— plus a second smaller bump at 13:46:30–58.

⚠️ **Which pair is the like-for-like comparison is not currently decidable.** Beta6's 16,203 and
864 were recorded without noting their log-level scope, and this build's number differs by 34%
depending on that choice (`Df` only 20,265 vs all levels 30,699). Both are given here and in
[`baselines/beta7-26A5421a/postboot-window.txt`](../baselines/beta7-26A5421a/postboot-window.txt)
so the next comparison can pick a scope and stick to it. ⚠️ Still **one window, not replicated,
not a verdict** — the same caveat the beta6 entry carries, and it has now gone un-addressed for
two builds running.

**A counting trap worth recording**, because the wrong number was entirely plausible: an anchored
`grep -E '^\S+ \S+ \S+ (BackgroundShortcutRunner|siriactionsd)\['` returns **only the `Df`
rows**, because compact style pads a one-character type field (`A `, `E `, `F `) to two columns
and a double space follows it. That undercounted this window by 34%. Split the process field with
awk instead.

2026-08-27 beta7 复测:**又升高了** —— 开机后 8 分钟窗口 30,699 条(beta6 为 7m47s 内 16,203),
峰值 **1,795 行/秒**(全等级)或 1,306(仅 `Df`),对应 beta6 的 864、beta5 的 181。
⚠️ 但**哪一对才是同口径比较,目前判不了**:beta6 那两个数当时没记录日志等级范围,而本次两种口径相差 34%。
两个数都留在这里,下次比较时先定口径。⚠️ 仍是**单窗口、未复现、不构成结论** —— 这条 caveat 已经连续两个 build 没被处理。

## Re-verification 2026-09-03 — beta8 `26A5425a` — running at T+21h, so it does not self-settle

> **Clock position, because it decides what these numbers can be compared to.** beta8
> `26A5425a` was installed **2026-09-02 04:57:15** (`InstallHistory.plist`). Every figure below
> was taken at **T+21h20m** on the 2026-09-02 12:55:26 boot — a **steady-state** window, not the
> post-boot window beta6 (T+9m) and beta7 (T+0→8m) used. Log *volumes* are therefore **not**
> matched pairs with those builds and are not presented as such. Kernel unchanged for a third
> beta: `xnu-13432.1.9~3`. Raw capture: [`baselines/beta8-26A5425a/`](../baselines/beta8-26A5425a/README.md).

`BackgroundShortcutRunner` + `siriactionsd` records in the 10-minute window: **15,672**
(`Df` 10,652 · `A` 3,391 · `E` 1,328 · `F` 300 · `Sd` 1). Peak per second, all levels:

| rate | at |
|---|---|
| **1,644** | 10:21:34 |
| 1,001 | 10:21:53 |
| 1,000 | 10:21:54 |

**The total is not the finding, and is not comparable** — 10 minutes of steady state against
beta7's 8 minutes of post-boot. **The peak second is comparable**, and it lands within **9%** of
beta7's 1,795/s — a figure measured *inside* the boot burst, where this one is 21 hours away from
any boot.

That falsifies the reading this write-up has carried since the beta2 retest — *"storm fires
post-boot then self-settles"*. On beta8 it is still at near-post-boot peak rate a full day in.
Peak rate is the better discriminator here precisely because it survives the window mismatch that
makes the volumes incomparable.

Counted with the awk field-split (`{p=$4; sub(/\[.*/,"",p)}`), not an anchored regex — the
beta7 capture lost 34% of this issue's records to the padded one-character type field.

2026-09-03 beta8 复测:10 分钟稳态窗口内 **15,672** 条,峰值 **1,644 行/秒**。总量与 beta7 的
30,699 **不可比**(窗长与时钟位置都不同),但**峰值可比** —— 距 beta7 在开机爆发期内测得的 1,795/s
只差 **9%**,而本次已距开机 21 小时。这推翻了本条自 beta2 起沿用的判断:**"开机后爆发、随后自行平息"
在 beta8 上不成立**。

## Re-verification 2026-09-16 — release `26A428` — recurring all afternoon, and a window that would have lied

> **Clock position, because it decides what these numbers can be compared to.** The release
> build `26A428` was installed **2026-09-11 04:28:46** (`InstallHistory.plist`). Every figure below
> was taken at **T+6h29m** on the 2026-09-16 11:40:46 boot with ~40 apps running — matched neither
> to beta8's T+21h20m window nor to beta6/beta7's post-boot windows, so log *volumes* are not
> presented as pairs. Kernel `xnu-13432.1.9~1` (beta6–beta8: `~3`). Raw capture:
> [`baselines/release-26A428/`](../baselines/release-26A428/README.md).

### The 10-minute window alone says "fixed"

`BackgroundShortcutRunner` + `siriactionsd` in the 18:09–18:19 window: **182** records
(`Df` 167 · `A` 12 · `E` 3), peak **172/s**. Taken the way beta8's reading was taken, that is a
~99% drop and would have been written up as a fix.

### The since-boot query says otherwise

```
/usr/bin/log show --start "2026-09-16 11:40:46" --style compact \
  --predicate 'process == "BackgroundShortcutRunner" OR process == "siriactionsd"'
```

**444,874** records from 11:41 to 18:14 (`Df` 306,439 · `A` 93,419 · `E` 36,198 · `F` 8,793),
dominated by `shortcuts:ToolKitExecutionPool` (80,475), `ToolKitDatabase` (49,490) and
`ToolKitExecution` (42,906). Peak seconds:

| rate | at | clock |
|---|---|---|
| **3,033** | 13:57:51 | T+2h17m |
| 2,533 | 13:58:48 | T+2h18m |
| 2,384 | 17:01:10 | T+5h20m |
| 2,190 | 14:30:20 | T+2h50m |
| 2,176 | 15:06:31 | T+3h26m |

Per 10-minute bucket, after the 46,601-record boot burst the storm comes back as bursts of roughly
**17k records**, sometimes two or three in one bucket (13:50 holds 57,319), separated by buckets of a
few hundred: 12:20, 12:50, 13:10–14:00, 14:30, 14:50–15:00, 15:40–16:10, 17:00, 17:30. Seconds at or
above 500 records per hour: 43 · 28 · **134** · 42 · 60 · 51 · 28. Full table:
[`shortcuts-since-boot.txt`](../baselines/release-26A428/shortcuts-since-boot.txt).

**Reading.** The peak second is higher than beta8's 1,644/s and beta7's post-boot 1,795/s. Peak
seconds are the one figure this write-up has treated as comparable across mismatched windows, but
they are single samples and this is one boot, so "higher on release" is **not** claimed as a
regression. What is established is the shape: the storm is not a boot transient that settles, it
recurs in bursts for hours, and a single 10-minute window is a lottery on it — the same lesson #24
already taught. The recurrence is not strictly periodic, and no trigger for the individual bursts
was identified.

2026-09-16 正式版 `26A428` 复测:**仍在风暴,峰值 3,033 行/秒**。10 分钟稳态窗口(T+6h29m)恰好落在
间歇期,只有 **182** 条、峰值 172/s —— 单看这个窗口会被误记为"已修复"。开机以来整段查询却有 **444,874** 条:
开机爆发之后,约 17k 条一簇的爆发从 T+40m 一直反复到至少 T+5h50m,峰值 **3,033/s** 出现在 T+2h17m
(beta8 为 T+21h 的 1,644/s)。峰值是单点、仅一次开机,**不据此主张"正式版更严重"**;能确定的是形状 ——
不是开机后自行平息的瞬态,而是持续数小时的反复爆发,单个 10 分钟窗口全凭运气。各次爆发的触发因素未查明。

## Re-verification 2026-09-25 — 27.2 beta2 `26B5091g` — still storming

> **Clock position, because it decides what these numbers can be compared to.** macOS 27.2 beta2
> `26B5091g` was installed **2026-09-25 07:08:18 UTC** (`InstallHistory.plist`), two minutes after
> the 15:06:19 +0800 boot. The window is **T+1h54m → T+2h04m** with 32 apps running and the
> post-update reindex still active — matched to no earlier window, so log *volumes* are not
> presented as pairs. Kernel `xnu-13432.40.162~92` (release: `xnu-13432.1.9~1`). Raw capture:
> [`baselines/27.2-beta2-26B5091g/`](../baselines/27.2-beta2-26B5091g/README.md).

Since-boot query, `process == "BackgroundShortcutRunner" OR process == "siriactionsd"`, default
level, sliced at 17:20:00 (raw: [`shortcuts-since-boot.txt`](../baselines/27.2-beta2-26B5091g/shortcuts-since-boot.txt)):

| | release `26A428` (to T+6h34m) | **27.2 b2 (to T+2h11m)** |
|---|---|---|
| records | 444,874 | **98,046** |
| BackgroundShortcutRunner / siriactionsd | 236,110 / 208,764 | **86,911 / 11,135** |
| peak second | 3,033 at T+2h17m | **8,813 at T+2m52s** (boot burst) |
| peak second after the boot burst | — | **1,885 at T+40m**; 1,549 at T+2h10m |
| recurring bursts | ~17k records per 10-minute bucket | ≤ 9,411 per bucket |

Records per 10-minute bucket: 15:00 **51,979** (boot burst) | 15:10 6,392 | 15:20 0 | 15:30 3,936 |
15:40 5,249 | 15:50 2,100 | 16:00 173 | 16:10 171 | 16:20 3,923 | 16:30 9,411 | 16:40 3,749 |
16:50 4,428 | 17:00 2,623 | 17:10 3,912 (to 17:17). The 15:20 bucket being exactly 0 is unexplained.

The storm is present from boot and still recurring two hours in. The mix shifted toward
BackgroundShortcutRunner (89% of records, release 53%) and the recurring bursts are smaller than
release's, but these are T+2h vs T+6h on a single boot each — **recorded, not credited**. The
status stays 🟡.

⚠️ **Measurement note.** The query carried `--end 17:20:00` *and* a predicate and still returned
a 2,090-record burst at 17:22:28–17:22:40. Two 1-minute re-queries were bounded correctly, so this
is not "always ignored", but the counts above are sliced by timestamp rather than trusting `--end`.

2026-09-25 27.2 beta2 `26B5091g` 复测:开机以来 98,046 条,开机爆发峰值 **8,813/s**,之后 T+40m 仍有
1,885/s、T+2h10m 仍有 ~1,550/s。周期性爆发比 release 小,但时钟位置不同、各只一次开机,只记录不计功。仍记 🟡。
