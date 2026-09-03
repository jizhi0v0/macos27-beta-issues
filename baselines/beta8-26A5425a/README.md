# beta8 `26A5425a` — re-verification of the open issues

Upgraded from beta7 `26A5421a` on **2026-09-02 04:57:15** per
`/Library/Receipts/InstallHistory.plist`. The kernel did **not** move — still
`xnu-13432.1.9~3`, the same string beta6 and beta7 carried. That is now three
consecutive betas with an unchanged kernel.

Baseline to compare against: [`../beta7-26A5421a/`](../beta7-26A5421a/README.md).

⚠️ **This round has no post-boot window.** Every measurement was taken at
**T+21h20m** on the 2026-09-02 12:55:26 boot, because the build had already been
running for a day when the re-verification started. beta6's window was T+9m and
beta7's was T+0 → T+8m, so **none of the log-volume figures here are matched
pairs with those**. What a steady-state window *is* good for is the opposite
question — whether a loop is still running long after any boot burst could
explain it — and that is the only way the counts are used below.

Xcode is still `27A5237l`, so SDK-tracked entries (**#11**) are untouched and not
re-tested.

| file | contents |
|---|---|
| `steady-state-window.txt` | the 10-minute T+21h window, per-issue counts, capture method |
| `contactsd-backlog.txt` | #18 per-source rows |
| `eco-replicate.txt` | #23, raw `tools/eco-replicate.sh` output, 3×60s |
| `crash-inventory.txt` | crash/spin/hang reports since the install, incl. `Retired/` |

---

## Nothing was closed this round

Four issues were positively re-confirmed as still broken. Five produced no
observation, which is not the same thing and is not recorded as one. Four could
not be tested at all without pulling a trigger by hand.

## Confirmed still broken

### #18 contactsd — 🔴 **the backlog crossed a third upgrade**

| | beta3 | beta5 08-11 | beta5 08-18 | beta6 08-19 | beta7 08-27 | **beta8 09-03** |
|---|---|---|---|---|---|---|
| unconsumed group-change rows | 53,686 | 76,366 | 90,209 | 91,030 | 98,489 | **102,678** |
| worst single source | 17,918 | 23,849 | 27,202 | 27,388 | 29,289 | **30,471** |

All 12 sources carried over, all 7 non-zero ones up, **none reset** — the same
check that ruled out "the upgrade rebuilt the stores and cleared it" on beta6 and
beta7, now passed a third time. The store has never drained across five OS builds
and seven weeks.

⚠️ The three readings are at T+9m, T+1h56m and T+21h29m. The +4,189 delta is
**not** a rate.

New this round, because the subsystem mix was finally counted:
**33,971 of contactsd's 45,728 window records are `com.apple.xpc:connection`**,
not Contacts traffic at all. The fan-out described in the issue is visible as XPC
churn, which is a better handle on the mechanism than the raw line count was.

### #19 imagent — 🔴 **the profile is unchanged for the third build running**

`com.apple.imagent.sb`: **404 lines**, **0** mentions of `ContactsAccountsService`,
still the outlier against **26** sibling profiles that do name it. Identical to
beta6 and beta7 on all three numbers. 1,586 imagent records naming the service in
the window. The one-line fix was not applied.

### #23 ecosystemd — 🔴 **rate signature unchanged, and a new emitter surfaced**

`tools/eco-replicate.sh`, 3×60s, 10:25–10:28:

| rep | eco % | anchors/s | lines/60s | EIO |
|---|---|---|---|---|
| 1 | 12.8 | 32.9 | 7,616 | 474 |
| 2 | 13.7 | 38.2 | 8,784 | 552 |
| 3 | 11.2 | 32.7 | 7,593 | 471 |

Mean CPU **12.6%** (min 11.2, max 13.7, sd 1.0) against beta7's 33.1/32.5/32.5,
468–477 EIO, 13.1% mean. Unchanged to the precision the method supports.

Two things this round did better than beta7's: **the three reps are genuinely
distinct** — beta7's reps 2 and 3 returned byte-identical triples, the
flush-boundary artefact that made it effectively n=2 — and the independent
window count agrees, 19,998 anchors in 10 minutes = **33.3/s**.

⚠️ Machine **not quiesced** (load average 27, ~34 `/Applications` bundles). The
anchors/s and EIO columns are not load-sensitive; the CPU column is.

⚠️ **New and untested:** unpinned, the anchors message returns 47,887 for the
window, of which **`ecosystemanalyticsd` accounts for 20,721 — more than
ecosystemd's 19,998**. That process has never been counted in this issue.
Whether it is a second participant in the same retry loop or an unrelated caller
is unknown and needs its own pinned measurement. Not claimed either way.

### #2 Shortcuts/Siri ToolKit storm — 🟡 **running at T+21h, so it does not self-settle**

15,672 records in the 10-minute window, peak **1,644 lines/s**. The totals are not
comparable to beta7's 30,699 (different window length, different clock position),
but the peak second is, and it is within **9%** of beta7's post-boot peak of
1,795/s — at T+21h, where beta7's figure was taken inside the boot burst.

That is the finding: the write-up's standing reading, *"storm fires post-boot then
self-settles"* (carried since beta2), **does not hold on beta8**. Peak rate is a
better discriminator here than volume, because it survives the window mismatch.

## No observation — which is not a fix

Recorded so the next round does not mistake these for closed:

- **#29 NotificationCenter** — 0.0% CPU over 30s and 120s. Intermittent by
  nature; has to be caught live. **Absence is not evidence.**
- **#24 mds/CoreDuet** — 2,205 CoreDuet records = 3.7/s, inside the ~2/s idle band
  (storm is ~2420/s). Bursty by construction; one window decides nothing, which is
  exactly why `tools/mds-storm-watch.sh` exists.
- **#15 appstoreagent** — 0 `Code=8`, a fifth consecutive clean build. Trigger is
  conditional and was last seen on beta2.
- **#25 corebrightnessd** — 23 lines / 0 `nan` in a 5-minute `--info --debug`
  window. Already classified ⚪ not-a-defect.
- **#1 CoreMedia** — 54 records (~324/h), emitters Mail 20 / DingTalk 16 /
  DuoUpdater 12 / textunderstandingd 6. WeType and Raycast, beta7's two largest
  emitters, are **absent**. The trigger is app-dependent, so a lower count under a
  different app mix measures the app mix. Same non-verdict as beta7.

## Not tested

- **#21** (ControlCenter volume runaway) — needs the Bluetooth trigger and a
  verified-clean start; not attempted.
- **#26 / #27** (notification click failure / inert banner) — need
  `tools/notif-preflight.sh` plus a hand-driven notification; not attempted.
- **#28** (AirPods A2DP) — needs the hardware paired and in-ear.
- **#3 / #12** (WindowServer, MenuBarAgent) — WindowServer sampled at 46.3% and
  MenuBarAgent at 1.1%, but with **~34 apps up and an uncontrolled window count**
  neither is decision-grade. An uncontrolled window count already manufactured a
  false #3 regression once that survived five replicates, a spindump and a binary
  diff. Use `tools/ws-idle-baseline.sh`. **No verdict on #3 or #12 this round.**

## Two things worth carrying forward

**1. The attribution trap fired twice more.** `SecTrustCopyAppleTrustAnchors`
unpinned reads 47,887; pinned to ecosystemd it is 19,998. `Could not fetch group
for change type` unpinned reads 1,537 across ~30 clients. Both are the same trap
the #18 write-up documented in August. Pin `process ==` or split `$4` with awk —
every time.

**2. contactsd's log volume and CPU cost have decoupled.** It emitted 45,728
records in 10 minutes while measuring **0.0%** CPU over a 120-second sample,
against the 20.2% recorded on beta5. Both numbers were cross-checked (the
predicate-pinned count agrees at 46,094; the CPU delta is cumulative
utime+stime, not `ps %cpu`). No explanation is offered here — it is flagged
because either the loop got cheap or one of the two measurements means something
other than what it did on beta5.

## Archive gap — partly closed

**The beta6 and beta7 `dyld_shared_cache`s were never archived and are gone for
good.** Nothing recovers them: the cache only exists on the running system, so
once a build is replaced its side of any binary diff ceases to exist anywhere.
#17's and #19's binary comparisons therefore have exactly two reachable points,
beta5 and beta8.

**beta8's side is now archived**, 2026-09-03:
`~/Developer/macos27-beta8-binary-archive/` — 82 files, 6.55 GiB, mirroring the
layout of `~/Developer/macos27-beta5-binary-archive/`.

It is **verified**, not merely copied: `shasum -a 256` was run over both the live
source and the copy and the two sorted lists are identical for all 82 files.
That check matters here because `cp -Rp` **exits 1** on this tree — it cannot
reproduce the SIP flags, so every file logs a `chflags` failure. The beta5
archive shows the same `exit=1` and was never verified this way, so its exit
code alone never established anything. Provenance and the exact commands are in
that archive's `meta/build-facts.txt`.

⚠️ **Copy the cache BEFORE the beta9 upgrade.** Afterwards the beta8 side is
unrecoverable, exactly as beta6's and beta7's now are.

Not archived this round, and present in the beta5 archive: `sandbox-profiles/`
(`/System/Library/Sandbox/Profiles`, the direct input to **#19**) and
`diagnostic-reports/`.
