# `ecosystemd` re-evaluates Apple trust anchors ~85×/second with failures, burning 26–57% CPU
# `ecosystemd` 每秒重复约 85 次证书信任评估并持续报错，吃 26–57% CPU

> 🔗 **Track / 关注此问题:** [#23 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/23)

| | |
|---|---|
| **Status** | 🔴 **rate signature unchanged on 27.2 beta2 `26B5091g`** (2026-09-25) — **35.0 / 32.5 / 33.5** anchors/s, **504 / 468 / 483** EIO, CPU mean **14.7%** (sd 0.3). The 10-minute window gives **19,888 = 33.1/s** (predicate cross-check 19,950) against release's 33.3/s and beta8's 33.3/s — a new kernel and the rate did not move. `ecosystemanalyticsd` 18,354. See [`../baselines/27.2-beta2-26B5091g/`](../baselines/27.2-beta2-26B5091g/README.md). Prior: 🔴 **rate signature unchanged on release `26A428`** (2026-09-16) — **35.0 / 31.3 / 42.1** anchors/s, **504 / 450 / 603** EIO, CPU mean **11.7%** (sd 1.6). The reps spread wider than beta8's, but the independent 10-minute window, predicate-pinned to ecosystemd, gives **19,975 = 33.3/s** against beta8's 19,998 = 33.3/s. `ecosystemanalyticsd` again emits nearly as many anchor calls (**18,377**) and is still untested; the two are the machine's #1 and #2 log emitters. ⚠️ Not quiesced (~40 apps). See [`baselines/release-26A428/`](../baselines/release-26A428/README.md). Prior: 🔴 **rate signature unchanged on beta8 `26A5425a`** (2026-09-03) — **32.9 / 38.2 / 32.7** anchors/s, **474 / 552 / 471** EIO, CPU mean **12.6%** (sd 1.0), against beta7's 33.1/32.5/32.5, 468–477, 13.1%. Better than beta7 in two ways: the three reps are genuinely distinct (beta7's reps 2–3 were byte-identical, an artefact that made it effectively n=2), and an independent 10-minute window agrees at **33.3/s**. ⚠️ **New and untested:** unpinned, the anchors message returns 47,887 for that window, of which **`ecosystemanalyticsd` accounts for 20,721 — more than ecosystemd's 19,998**. That process has never been counted in this issue; whether it is a second participant in the same loop or an unrelated caller is unknown. Not claimed either way. Prior: 🔴 **still reproducing on beta7 `26A5421a`, rate signature unchanged from beta6** (2026-08-27) — **33.1 / 32.5 / 32.5** anchors/s, **468–477** `UNIX error exception: 5` per 60 s, CPU **13.1%** mean (beta6: 33.1/s, 476 EIO, 12.7%). ⚠️ Effectively **n=2** — the flush-boundary artefact the script's header claims was fixed recurred, reps 2 and 3 byte-identical — and the machine was **not quiesced**, so the CPU column is not a matched comparison; the anchors/s and EIO columns are load-insensitive and carry the verdict. See *Re-measurement 2026-08-27* below. Prior: 🔴 **still reproducing on beta6 `26A5416b`** (2026-08-19) — the loop's rate signature is **unchanged from beta5**: `SecTrustCopyAppleTrustAnchors` **33.1/s** mean (beta5 ~32.5), **476** `UNIX error exception: 5` per 60 s (beta5 468), **6,504** lines/60 s (beta5 7,519), CPU **12.7%** mean over 8 windows (beta5 16.4%). Not fixed and not further mitigated. See [the beta6 re-measurement](#re-measurement-2026-08-19--beta6-26a5416b--rate-signature-unchanged). Prior: 🔴 **still reproducing on beta5 `26A5406e`, at roughly half the beta4 rate on every axis** (2026-08-11, 5 replicates on a quiesced desktop via [`tools/eco-replicate.sh`](../tools/eco-replicate.sh)) — CPU **16.4%** (min 13.9, max 17.2, sd 1.3) against beta4's 26–57%; `SecTrustCopyAppleTrustAnchors` **~32.5/s** against ~68–85/s; **7,519** lines/60 s against 15,885; **468** `UNIX error exception: 5` against 1,227. The failing-and-retrying shape is unchanged, so this is **mitigation, not a fix**. **Not yet re-tested on beta6 `26A5416b`.** Prior: 🔴 Open · confirmed on beta4 |
| **macOS** | 27.0 beta4 `26A5388g` |
| **Component** | Apple **`ecosystemd`** (`Ecosystem.framework`) ↔ **Security / `trustd`** |
| **Hardware** | `Mac15,11`, M3 Max, 36 GB |
| **Report** | Apple Feedback: `FB________` *(to be filed)* |

## Symptom / 症状

`ecosystemd` runs a continuous certificate-trust-evaluation loop, emitting **15,885 log lines in 60 seconds** and holding **26–57% CPU** for the entire uptime. The loop **is failing**, not merely chatty: 1,227 `UNIX error exception: 5` in the same minute. `trustd` is dragged along at ~6% with 11,471 lines/60 s.

`ecosystemd` 持续重复证书信任评估，60 秒写 15,885 行日志，全程占用 26–57% CPU，且**伴随报错**（同一分钟内 1,227 条 `UNIX error exception: 5`），说明是失败重试而非单纯日志啰嗦。`trustd` 被带到 ~6% CPU / 11,471 行。

## Evidence / 证据

Message breakdown for `ecosystemd` in a single 60-second window:

```
5112  (Security) Created Activity ID: 0x…, Description: SecTrustCopyAppleTrustAnchors
1841  (Security) Created Activity ID: 0x…, Description: SecKeyVerifySignature
1432  (Security) Created Activity ID: 0x…, Description: SecTrustEvaluateIfNecessary
1227  (Security) [com.apple.securityd:security_exception] UNIX error exception: 5
1023  (libsystem_trace.dylib) Created Activity ID: 0x…, Description: Activity for state dumps
```

`SecTrustCopyAppleTrustAnchors` at 5,112/60 s = **~85 evaluations/second**, sustained.

**Continuous, not bursty** — all 61 seconds of the capture window contain `ecosystemd` lines.

Observed CPU across the session:

| sample | ecosystemd | trustd |
|---|---|---|
| 17:58 | 33.9% | 5.9% |
| 18:00 | 41.7% | 6.2% |
| 18:03 | 26.3% | — |
| 18:10 (midpoint of an idle window) | **56.9%** | 8.4% |

It was the **#3 log emitter** system-wide in that minute, behind only [`mds`](apple-mds-coreduet-activity-storm.md) and Mail.

## Impact / 影响

- Sustained 26–57% CPU on a system daemon with no user-visible function, persisting on an otherwise idle machine.
- The `UNIX error exception: 5` (EIO) recurrence suggests each evaluation round fails and is retried, rather than a cache being warmed once.
- Contributes to the same system-wide load picture as the `mds` storm: load average 30–75 with ~60% CPU idle.

## Reproduction / 复现

Not isolated to a trigger. Present continuously across 3.5 h of uptime on beta4, including on a desktop with every user application quit.

Open questions:
- What `ecosystemd` is repeatedly verifying — the log lines carry no subject identifier.
- Whether the `UNIX error exception: 5` originates from a missing/unreadable keychain or trust-store file, which would make this an error-retry loop with a fixable root cause.
- Whether it correlates with a specific iCloud/continuity feature being enabled.

## Workaround / 临时规避

None known. `ecosystemd` is a system daemon; disabling it is not advisable. Silencing the subsystem hides the log volume but not the CPU:

```sh
sudo log config --subsystem com.apple.securityd --mode 'level:off'
```

## Re-measured 2026-08-04 10:23 (uptime 1 d 0 h 23 m) — still running a day later / 次日复测:仍在跑

Second capture, different day and different boot, 60 s window:

| Metric | 2026-08-04 |
|---|---|
| `ecosystemd` log lines / 60 s | **7,177** — **18% of the entire system's log volume** (39,686 lines total) |
| `SecTrustCopyAppleTrustAnchors` / 60 s | **4,061 ≈ 68/s**, sustained |
| Rank among all log emitters | **#1 system-wide** (`ecosystemanalyticsd` #2 at 5,712) |
| Cumulative CPU | **186 min over 24 h uptime ≈ 12.7% of one core, sustained** |

Instantaneous CPU at sample time was 0.5%, which is exactly why the **cumulative** figure is the one to quote: 186 minutes of CPU time cannot be produced by an idle daemon. Same lesson as [#12](apple-menubaragent-idle-cpu.md) — a single `ps %cpu` reading is a decaying average and is not decision-grade.

The [`mds` storm](apple-mds-coreduet-activity-storm.md) captured alongside this in the first session was **not** active in this window (132 lines/60 s), so the two are independent; `ecosystemd` is the one that runs continuously.

取样瞬时 CPU 只有 0.5%,所以该引用的是**累计**值:空闲守护进程烧不掉 186 分钟 CPU。教训同 [#12](apple-menubaragent-idle-cpu.md) —— 单次 `ps %cpu` 是衰减平均值,不足以作判断依据。首轮与之同时抓到的 [`mds` 风暴](apple-mds-coreduet-activity-storm.md)本轮并未发作(132 行/60 秒),两者相互独立,持续在跑的是 `ecosystemd`。

## Related / 相关

- [`mds` CoreDuet activity storm](apple-mds-coreduet-activity-storm.md) — the #1 emitter in the same capture; the two together dominate the machine's log and daemon CPU

## Re-measurement 2026-08-19 — beta6 `26A5416b` — rate signature unchanged

8 windows across two runs of [`tools/eco-replicate.sh`](../tools/eco-replicate.sh) (5×60 s, then
3×45 s after the tool fix below).

| | beta4 `26A5388g` | beta5 `26A5406e` | **beta6 `26A5416b`** |
|---|---|---|---|
| `SecTrustCopyAppleTrustAnchors` | ~68–85/s | ~32.5/s | **33.1/s** (range 26.7–37.0) |
| `UNIX error exception: 5` /60 s | 1,227 | 468 | **476** |
| lines /60 s | 15,885 | 7,519 | **6,504** |
| ecosystemd CPU | 26–57 % | 16.4 % (sd 1.3) | **12.7 %** (range 10.0–14.2, n=8) |

**The loop is unchanged.** Anchors/s and the EIO count — the two columns that describe the loop
itself rather than the machine's load — land on beta5's figures within sampling variance. The
beta4→beta5 halving did not continue into beta6.

**The CPU difference is not claimed as an improvement.** beta5's 16.4 % was measured on a
quiesced desktop; beta6's 12.7 % was measured with 15 applications running. Lower CPU under
*more* load is more consistent with contention than with a fix, and the two distributions are
about 2.5 sd apart, which is not enough to carry a claim either way.

### A defect in the measuring tool, found and fixed

`eco-replicate.sh` carried a note from 2026-08-11 recording that its three log columns came back
byte-identical in 4 of 5 reps, with an unverified guess that `log show --last Ns` resolves
against the log buffer's flush boundary rather than wall-clock now. **That guess was correct.**
Pinning each window with explicit `--start`/`--end` makes the columns vary as independent samples
should — 2050 / 1950 / 2087 anchors and 492 / 468 / 501 EIO across three windows, against the
frozen 32.5 / 468 the old form reported five times running.

**Consequence for the beta5 row above:** it was produced by the unfixed tool, so its
`7,519 lines / 468 EIO` is **one** sample, not five. The beta6 figures are means of six. The
comparison is sound in direction but the beta5 side has no spread attached to it.

2026-08-19 在 beta6 复测:循环的速率签名**与 beta5 一致** —— anchors 33.1/s(beta5 ~32.5)、EIO 476
(beta5 468),beta4→beta5 的减半没有延续。CPU 12.7% 低于 beta5 的 16.4%,但 beta5 是静置桌面、本次开着
15 个应用,**不作为改善主张**。另修复了测量脚本自身的缺陷:`log show --last Ns` 会落在日志缓冲的刷新边界上,
连续调用返回相同区段;改用 `--start/--end` 后各窗口正常独立变动。这也意味着 beta5 那一行的日志列是**一次**
采样而非五次。

## Re-measurement 2026-08-27 — beta7 `26A5421a` — unchanged from beta6 to three significant figures

Measured on the 2026-08-27 13:39:10 boot, three days into the build (beta7 was installed
**2026-08-24 23:33** per `InstallHistory.plist` — the Aug 21 mtime on the system files is the
image build date, not the install date). Raw counts and the capture caveats are in
[`baselines/beta7-26A5421a/`](../baselines/beta7-26A5421a/README.md).

[`tools/eco-replicate.sh`](../tools/eco-replicate.sh), `REPS=3 WIN=60`, 15:33–15:36:

| rep | eco % | anchors/s | lines/60s | EIO |
|---|---|---|---|---|
| 1 | 13.5 | 33.1 | 6,859 | 477 |
| 2 | 12.9 | 32.5 | 6,739 | 468 |
| 3 | 12.8 | 32.5 | 6,739 | 468 |

Mean CPU **13.1%** (min 12.8, max 13.5, sd 0.3). Against beta6's **33.1/s, 476 EIO, 6,504
lines/60 s, 12.7% mean over 8 windows** this is the same loop at the same rate. Not fixed, not
further mitigated.

⚠️ **Two caveats that make this weaker than the beta6 run, both stated because they cut the
other way from the conclusion.** (1) **Effectively n=2**: reps 2 and 3 returned byte-identical
triples (6,739 / 468 / 32.5), which is the flush-boundary artefact this script's own header
claims was fixed by pinning `--start`/`--end`. It recurred, so that fix is not sufficient and the
header is now optimistic. (2) The machine was **not quiesced** — 25 `/Applications` bundles
running, load average ~6–8, against beta6's deliberately idle desktop. Per the script's own
reading guide the anchors/s and EIO columns are not load-sensitive and carry the verdict; the CPU
column is, so 13.1% is not a matched comparison with 12.7%.

Separately, the post-boot window shows **72,829 anchors in 8 minutes (152/s)** — that is a boot
burst, roughly 4.6× the steady state, and is *not* the loop's rate. Anyone re-checking this
issue from a post-boot capture will overstate it by that factor.

2026-08-27 beta7 复测:**速率签名与 beta6 逐项相同**(33.1/32.5 anchors/s、468–477 EIO、
CPU 均值 13.1% vs beta6 的 12.7%),未修复也未进一步缓解。两个削弱本次结论的前提如实记录:
rep2/rep3 三个数字**逐字相同**,是脚本头部声称已修好的 flush-boundary 假象**复发**,故实际 n=2;
且本次机器**未静默**(25 个 app 在跑,load ~6–8),CPU 列不可与 beta6 直接对比,anchors/s 与 EIO 可以。
另:开机后 8 分钟窗口测得 152/s,是开机爆发而非稳态,约为稳态的 4.6 倍 —— 用 post-boot 窗口复查本条会高估。

## Re-verification 2026-09-03 — beta8 `26A5425a` — rate signature unchanged, and a second emitter appears

> **Clock position, because it decides what these numbers can be compared to.** beta8
> `26A5425a` was installed **2026-09-02 04:57:15** (`InstallHistory.plist`). Every figure below
> was taken at **T+21h20m** on the 2026-09-02 12:55:26 boot — a **steady-state** window, not the
> post-boot window beta6 (T+9m) and beta7 (T+0→8m) used. Log *volumes* are therefore **not**
> matched pairs with those builds and are not presented as such. Kernel unchanged for a third
> beta: `xnu-13432.1.9~3`. Raw capture: [`baselines/beta8-26A5425a/`](../baselines/beta8-26A5425a/README.md).

`tools/eco-replicate.sh`, 3×60 s, 10:25–10:28:

| rep | eco % | anchors/s | lines/60s | EIO |
|---|---|---|---|---|
| 1 | 12.8 | 32.9 | 7,616 | 474 |
| 2 | 13.7 | 38.2 | 8,784 | 552 |
| 3 | 11.2 | 32.7 | 7,593 | 471 |

Mean CPU **12.6%** (min 11.2, max 13.7, sd 1.0) against beta7's 33.1/32.5/32.5, 468–477 EIO,
13.1% mean. Unchanged to the precision this method supports.

Two respects in which this round is stronger than beta7's. **The three reps are genuinely
distinct** — beta7's reps 2 and 3 returned byte-identical triples (6,739 / 468 / 32.5), the
flush-boundary artefact that made that reading effectively n=2; it did not recur here. And an
**independent 10-minute window agrees**: 19,998 anchor calls pinned to `ecosystemd` = **33.3/s**,
against the replicated 32.9 / 38.2 / 32.7.

⚠️ The machine was **not quiesced** (load average 27, ~34 `/Applications` bundles). Per the
script's own note `anchors/s` and `EIO` are not load-sensitive; the CPU column is.

### ⚠️ New, and deliberately not a conclusion: `ecosystemanalyticsd`

Unpinned, `SecTrustCopyAppleTrustAnchors` returns **47,887** for the same window. Broken out:

| process | records / 10 min |
|---|---|
| **ecosystemanalyticsd** | **20,721** |
| ecosystemd | 19,998 |
| amfid | 2,734 |
| tccd | 2,060 |
| syspolicyd | 568 |

`ecosystemanalyticsd` emits **more** anchor calls than `ecosystemd` does, and it has never been
counted in this issue. Whether it is a second participant in the same retry loop or an
independent caller that happens to use the same API is **untested** — it needs its own pinned
measurement (and its own EIO count) before anything is claimed. Recorded here so the lead is not
lost. Note also that the unpinned 47,887 vs the pinned 19,998 is the same `process ==`
attribution trap this repo has now walked into three times.

2026-09-03 beta8 复测:**速率签名不变**(32.9/38.2/32.7 anchors/s、474/552/471 EIO、CPU 均值 12.6%,
对比 beta7 的 33.1/32.5/32.5、468–477、13.1%)。本轮比 beta7 强在两点:三个 rep **互不雷同**
(beta7 的 rep2/rep3 逐字相同,实为 n=2),且**独立的 10 分钟窗口互证** —— 钉 `process == ecosystemd`
得 19,998 次 = **33.3/s**。⚠️ 机器**未静默**(load 27、约 34 个 app),CPU 列只能当上界。
⚠️ **新线索,未下结论**:同一条消息不钉进程时是 47,887 次,其中 **`ecosystemanalyticsd` 占 20,721 —
比 ecosystemd 的 19,998 还多**。该进程从未被本条统计过,它究竟是同一重试环路的第二个参与者、
还是碰巧调用同一 API 的独立调用方,**未测**,需要单独钉进程复测后才能说。

## Re-verification 2026-09-16 — release `26A428` — rate signature unchanged

> **Clock position, because it decides what these numbers can be compared to.** The release
> build `26A428` was installed **2026-09-11 04:28:46** (`InstallHistory.plist`). Every figure below
> was taken at **T+6h29m** on the 2026-09-16 11:40:46 boot with ~40 apps running — matched neither
> to beta8's T+21h20m window nor to beta6/beta7's post-boot windows, so log *volumes* are not
> presented as pairs. Kernel `xnu-13432.1.9~1` (beta6–beta8: `~3`). Raw capture:
> [`baselines/release-26A428/`](../baselines/release-26A428/README.md).

`tools/eco-replicate.sh`, 3×60 s, 18:19–18:22 (raw:
[`eco-replicate.txt`](../baselines/release-26A428/eco-replicate.txt)):

| rep | eco % | anchors/s | lines/60s | EIO |
|---|---|---|---|---|
| 1 | 11.5 | 35.0 | 7,261 | 504 |
| 2 | 9.9 | 31.3 | 6,509 | 450 |
| 3 | 13.7 | 42.1 | 8,671 | 603 |

Mean CPU **11.7%** (min 9.9, max 13.7, sd 1.6), against beta8's 12.8 / 13.7 / 11.2 and
32.9 / 38.2 / 32.7 anchors/s. The three reps are distinct (no flush-boundary artefact), but they
spread wider than beta8's did (31.3–42.1/s against 32.7–38.2/s).

The independent check is what carries the verdict: the 10-minute window 18:09–18:19, pinned with
`--predicate 'process == "ecosystemd" AND eventMessage CONTAINS "SecTrustCopyAppleTrustAnchors"'`,
returns **19,975 = 33.3/s**. beta8's was **19,998 = 33.3/s**. The awk field-split count over the
captured window agrees exactly. Nothing about the loop's rate moved with the release.

⚠️ The machine was **not quiesced** (load ~10–12, ~40 `/Applications` bundles), so the CPU column is
an upper bound, not a matched comparison. anchors/s and EIO are load-insensitive.

### `ecosystemanalyticsd`, still untested

Unpinned, the same message comes from:

| process | beta8 | **release** |
|---|---|---|
| ecosystemd | 19,998 | **19,975** |
| **ecosystemanalyticsd** | 20,721 | **18,377** |
| ContextStoreAgent | — | 364 |
| Spotify | — | 234 |
| launchservicesd | — | 202 |
| securityd | — | 118 |

(beta8's amfid 2,734 / tccd 2,060 / syspolicyd 568 are not in the top six this time.)
`ecosystemanalyticsd` is again within ~10% of ecosystemd, and the two are the **#1 and #2 log
emitters on the whole machine** in this window (62,083 and 54,332 records). Whether it is part of the
same retry loop is still **not measured** and not claimed. It used 2.4% CPU over 120 s.

2026-09-16 正式版 `26A428` 复测:**速率签名不变**。3×60 秒:35.0/31.3/42.1 anchors/s、504/450/603 EIO、
CPU 均值 11.7%(sd 1.6),比 beta8 离散;但独立的 10 分钟窗口钉 `process == ecosystemd` 得 **19,975 = 33.3/s**,
beta8 为 19,998 = 33.3/s,awk 计数完全一致。⚠️ 机器未静默,CPU 列只能当上界。`ecosystemanalyticsd`
同一消息 18,377 次(beta8 20,721),与 ecosystemd 同为全机前两大日志源,是否属于同一重试环路**仍未测**。

## Re-verification 2026-09-25 — 27.2 beta2 `26B5091g` — rate signature unchanged

> **Clock position, because it decides what these numbers can be compared to.** macOS 27.2 beta2
> `26B5091g` was installed **2026-09-25 07:08:18 UTC** (`InstallHistory.plist`), two minutes after
> the 15:06:19 +0800 boot. The window is **T+1h54m → T+2h04m** with 32 apps running and the
> post-update reindex still active — matched to no earlier window, so log *volumes* are not
> presented as pairs. Kernel `xnu-13432.40.162~92` (release: `xnu-13432.1.9~1`). Raw capture:
> [`baselines/27.2-beta2-26B5091g/`](../baselines/27.2-beta2-26B5091g/README.md).

`REPS=3 bash tools/eco-replicate.sh`, 17:10:20 → 17:13:55 (raw:
[`eco-replicate.txt`](../baselines/27.2-beta2-26B5091g/eco-replicate.txt)):

| rep | eco % | anchors/s | lines/60s | EIO |
|---|---|---|---|---|
| 1 | 15.1 | 35.0 | 8,101 | 504 |
| 2 | 14.4 | 32.5 | 7,519 | 468 |
| 3 | 14.5 | 33.5 | 7,753 | 483 |

Mean CPU **14.7%** (sd 0.3), a tighter spread than release's 11.7% (sd 1.6). ⚠️ The script's lead-in
asks for apps to be quit; they were not (32 bundles), same as release.

| 10-minute window, `SecTrustCopyAppleTrustAnchors` in ecosystemd | beta8 | release | **27.2 b2** |
|---|---|---|---|
| awk-pinned | 19,998 | 19,975 | **19,888** |
| per second | 33.3 | 33.3 | **33.1** |

The predicate cross-check over 17:00:09 → 17:10:10 gives 19,950, agreeing within the boundary.
`ecosystemanalyticsd` emits the same message 18,354 times (release 18,377); it is still untested
whether that is the same loop. ecosystemd and ecosystemanalyticsd remain the #2 and #3 log emitters
of the whole machine in this window, behind only the kernel.

The rate is within 1% of the last two builds on the first build with a genuinely new kernel.
**The status stays 🔴.**

2026-09-25 27.2 beta2 `26B5091g` 复测:3×60 s 复测 35.0 / 32.5 / 33.5 anchors/s、EIO 504 / 468 / 483、
CPU 均值 14.7%(sd 0.3);10 分钟窗口 33.1/s,与 release / beta8 的 33.3/s 相差不到 1%。仍记 🔴。
