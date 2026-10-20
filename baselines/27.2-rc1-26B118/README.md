# macOS 27.2 RC1 `26B118` — re-verification of the open issues

macOS 27.2 RC1 **`26B118`** replaced 27.2 beta4 `26B5112a`; `/Library/Receipts/InstallHistory.plist`
dates the install **2026-10-20 10:34:48 +0800**, and `kern.boottime` is **10:31:56** — the receipt is
again dated *after* the boot (27.2 b4: two minutes after). Recorded, not explained. Kernel
**`xnu-13432.41.4~25`**, against 27.2 beta4's `xnu-13432.41.4~3`.

Baseline to compare against: [`../27.2-beta4-26B5112a/`](../27.2-beta4-26B5112a/README.md).

⚠️ **Clock position.** There is **no 10-minute window** this time. Every count is a since-boot
query over **T+0 → T+40m**; the #23 replicates ran at T+40m → T+43m and the #26 race probe at T+42m.
No log volume here is a matched pair with any earlier build. Not quiesced: load average
42.6 (15-min) / 14.3 (1-min) at T+40m, 32 `/Applications` bundles running. No CPU table was taken.

Apple's [macOS 27.2 RC release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes)
(read 2026-10-20) mention **none** of the open entries and none of our filed FB numbers. The one
Shortcuts known issue (187499433, *Describe a Shortcut* fails) is unchanged and unrelated to #2.

| file | contents |
|---|---|
| `post-boot-window.txt` | since-boot counts per issue, the #19 profile check, the crash inventory |
| `contactsd-backlog.txt` | #18 per-source rows, 27.2 b4 alongside |
| `eco-replicate.txt` | #23, raw `tools/eco-replicate.sh` output, 3×60 s, the since-boot query, and the 27.2 b4 uptime read back from the log store |
| `race-probe.txt` | #26, raw `tools/un-delivered-race-probe` output, 8+8 trials |

Binary archive: `<archives>/macos27-27.2rc1-binary-archive/` on the external drive — dyld shared
cache (84 files, 6.7 GiB) and sandbox profiles (553 files), both verified by sha256 against the live
source. Against the 27.2 beta4 archive, 2 sandbox profiles differ
(`com.apple.managedappdistributionagent.sb`, `com.apple.managedappdistributiond.sb`);
`com.apple.imagent.sb` is not one of them.

---

## One loop is gone; one issue closed

**#23 ecosystemd — 🟢.** 27.2 b4 asked for two things before calling it fixed: a longer uptime and a
second boot. Both are now in hand. The 27.2 b4 uptime, read back from the log store after the
upgrade, holds **7,244** ecosystemd / ecosystemanalyticsd records from 2026-10-14 13:35 to
2026-10-20 10:01 (≈5 d 20 h; the first 3 h 21 m had rotated out) with **0** anchor fetches and
**0** EIO. RC1 is the second boot: **0.0 / 0.0 / 0.0** anchors/s, **0** EIO, **0.0%** CPU, and
0 of either across 477 records since boot.

| | 27.2 b3 | 27.2 b4 (T+45m) | 27.2 b4 (≈5 d 20 h) | **RC1** |
|---|---|---|---|---|
| anchors/s, 3×60 s | 32.5 / 32.5 / 34.0 | 0.0 / 0.0 / 0.0 | — | **0.0 / 0.0 / 0.0** |
| EIO per 60 s | 468 / 468 / 492 | 0 / 0 / 0 | — | **0 / 0 / 0** |
| anchors / EIO in the span | 19,350 / — (10 min) | 0 / 0 | **0 / 0** of 7,244 | **0 / 0** of 477 |
| ecosystemd CPU | 12.2% | 0.0% | — | **0.0%** |

Still **no binary diff** behind it: the daemon (`Ecosystem.framework/Support/ecosystemd`) is outside
the dyld cache and was never archived locally. The third-party
[ipsw-diffs/macos-27](https://github.com/ipsw-diffs/macos-27) repo does not fill that gap either: its
27.2 b3 → b4 diff has no `filesystem` MachO section at all (only the SystemOS, AppOS and ExclaveOS
cryptexes), so it cannot say whether ecosystemd changed when the loop stopped. Its b4 → RC1 diff does
cover the filesystem and does not list ecosystemd among the 440 updated binaries.

## Confirmed still broken

### #18 contactsd — 🔴 **the backlog crossed an eighth upgrade**

| | 27.2 b3 | 27.2 b4 | **RC1** |
|---|---|---|---|
| unconsumed group-change rows | 122,126 | 125,914 | **128,836** |
| worst single source | 35,686 | 36,607 | **37,448** |

All 12 sources carried over, all 7 non-zero ones up, none reset. The +2,922 accrued over six days
of 27.2 b4 uptime, not on RC1. `Could not fetch group for change type`: **7,780 since boot** from 44
processes, in the same shape as 27.2 b4: a burst, quiet from 10:44 to 11:04, then back at T+32m.

### #19 imagent — 🔴 **the profile is byte-identical to 27.2 beta4**

`com.apple.imagent.sb`: 405 lines, `ContactsAccountsService` mentioned **0** times, **26** siblings
name it, `diff` against the 27.2 b4 archive prints nothing. imagent records naming the service:
**6,881 since boot**, 5,167 carrying `error 159 - Sandbox restriction`. Its resumption at 11:04:49
is the same second as #18's. The imagent binary itself did change in RC1 (ipsw-diffs: build string
`1491.200.101.1.2` → `.3`, same `__text` size) — the sandbox profile, which is what blocks the
lookup, did not.

### #26 notification race — 🔴 **the OS-side window is still there**

Phase A: **0/8** visible at 0 ms, 5/8 at 5 ms, 6/8 at 10 ms, 7/8 at 15 ms, **7/8 at 25 ms** (one trial
invisible until the 50 ms sample), 8/8 at 50 ms. Phase B first-visible: min 2.32 / **median 4.53** /
max 11.19 ms (27.2 b4 8.12; macOS 26.6 0.01–0.03 ms). The median is lower, the tail is not;
one run, recorded, not credited. Chrome's side was not re-checked.

### #2 Shortcuts/Siri ToolKit storm — 🟡 **still storming, and harder again**

**454,793** records in the first 40 minutes (27.2 b4: 244,437 in 46). Peak **15,952/s** at
T+4m20s (27.2 b4: 14,824/s), **205** seconds ≥ 500/s (27.2 b4: 107). It dropped to ~200 per
10 minutes after 10:50 (T+18m).

### #1 CoreMedia — 🟡 **still emitting, still not decidable**

47 records since boot, 32 of them **DingTalk**. The count measures the apps.

## No observation — which is not a fix

- **#15 appstoreagent** — 0 `Code=8` from appstoreagent since boot. **Tenth** consecutive clean
  build. The same two unrelated `Code=8` one-shots as 27.2 b4 (corespeechd, siriactionsd).
- **#24 mds/CoreDuet** — a burst: 51,052 records in 10:50–11:00, peak **1,088/s** at 10:56:48, below
  the ~2,420/s storm. An `mds_stores` diagnostic was written at 10:47; the post-update reindex is the
  likely cause (not verified).
- **#16 / #17 / #29 and the app-crash entries (#5 #6 #8 #10)** — 0 matching reports in 40 minutes.

## Not tested

- **#20, #21, #27, #28, #29** — hand-driven triggers, not attempted.
- **#3 / #12 / #22** — no CPU table; a WindowServer `cpu_resource` diagnostic was written at 10:46 and
  not read. No verdict.
- **#25, #13** — no dedicated window (#13's line: 3,205 since boot, benign since beta3).

## Measurement notes

- **`cp -p` of the dyld cache aborts under `set -e`.** `chflags` cannot reproduce the SIP flags, so
  the first archive attempt died after the first file. A plain `cp` plus a sha256 comparison of
  both sides is what was kept.
- **The log store had rotated out the first 3 h 21 m of the 27.2 b4 boot** for ecosystemd's
  processes. The b4 uptime figure starts at 13:35 on 2026-10-14; the 10:14 → 11:00 stretch is covered by
  the capture taken that day.
