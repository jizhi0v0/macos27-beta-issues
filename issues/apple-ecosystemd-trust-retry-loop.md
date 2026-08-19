# `ecosystemd` re-evaluates Apple trust anchors ~85×/second with failures, burning 26–57% CPU
# `ecosystemd` 每秒重复约 85 次证书信任评估并持续报错，吃 26–57% CPU

> 🔗 **Track / 关注此问题:** [#23 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/23)

| | |
|---|---|
| **Status** | 🔴 **still reproducing on beta6 `26A5416b`** (2026-08-19) — the loop's rate signature is **unchanged from beta5**: `SecTrustCopyAppleTrustAnchors` **33.1/s** mean (beta5 ~32.5), **476** `UNIX error exception: 5` per 60 s (beta5 468), **6,504** lines/60 s (beta5 7,519), CPU **12.7%** mean over 8 windows (beta5 16.4%). Not fixed and not further mitigated. See [the beta6 re-measurement](#re-measurement-2026-08-19--beta6-26a5416b--rate-signature-unchanged). Prior: 🔴 **still reproducing on beta5 `26A5406e`, at roughly half the beta4 rate on every axis** (2026-08-11, 5 replicates on a quiesced desktop via [`tools/eco-replicate.sh`](../tools/eco-replicate.sh)) — CPU **16.4%** (min 13.9, max 17.2, sd 1.3) against beta4's 26–57%; `SecTrustCopyAppleTrustAnchors` **~32.5/s** against ~68–85/s; **7,519** lines/60 s against 15,885; **468** `UNIX error exception: 5` against 1,227. The failing-and-retrying shape is unchanged, so this is **mitigation, not a fix**. **Not yet re-tested on beta6 `26A5416b`.** Prior: 🔴 Open · confirmed on beta4 |
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
