# macOS 27.2 beta4 `26B5112a` — re-verification of the open issues

macOS 27.2 beta4 **`26B5112a`** replaced 27.2 beta3 `26B5101f`; `/Library/Receipts/InstallHistory.plist`
dates the install **2026-10-14 10:16:02 +0800**, and `kern.boottime` is **10:14:00** — the receipt is
two minutes *after* the boot (27.2 b3's was 3.5 minutes before). Recorded, not explained. Kernel
**`xnu-13432.41.4~3`**, against 27.2 beta3's `xnu-13432.40.177.0.3~56`.

Baseline to compare against: [`../27.2-beta3-26B5101f/`](../27.2-beta3-26B5101f/README.md).

⚠️ **Clock position.** The 10-minute window is at **T+33m → T+43m**, the since-boot queries cover
T+0 → T+46m, the #23 replicates and #26 race probe ran at T+45m → T+48m, the CPU table at T+48m.
27.2 b3's window was T+13m, so **no log volume here is a matched pair** with any earlier build.
Not quiesced: load average 56.71 / 26.73 / 33.62 at the window's end, 23 GUI apps running,
`mds_stores` 34.6% — the post-update reindex was active.

Apple's [macOS 27.2 beta4 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes)
(read 2026-10-14) mention **none** of the open entries and none of our filed FB numbers. The one
Shortcuts known issue (187499433, *Describe a Shortcut* fails) is unchanged from beta3 and unrelated to #2.

| file | contents |
|---|---|
| `post-boot-window.txt` | the 10-minute window, per-issue counts, since-boot queries for #2 #15 #18 #19, the #19 profile check, the CPU table, the crash inventory |
| `contactsd-backlog.txt` | #18 per-source rows, 27.2 b3 alongside |
| `eco-replicate.txt` | #23, raw `tools/eco-replicate.sh` output, 3×60 s, plus the since-boot query |
| `race-probe.txt` | #26, raw `tools/un-delivered-race-probe` output, 8+8 trials |

Binary archive: `~/Developer/macos27-27.2beta4-binary-archive/` — dyld shared cache (84 files,
6.7 GiB) and sandbox profiles (553 files), both verified by sha256 against the live source.
Against the 27.2 beta3 archive, 8 sandbox profiles differ; `com.apple.imagent.sb` is not one of them.

---

## One loop stopped; nothing was closed

**#23 ecosystemd's loop did not run on this boot** — the first build since beta4 `26A5388g` on
which it is absent. That is a positive observation, not a missed trigger: on every earlier build
it ran from boot for the whole uptime. It is still **one boot, 45 minutes**, so it is marked ⚪
needs retest, not 🟢. Five issues were positively re-confirmed; #2 measured worse.

## Loop absent — needs a second boot

### #23 ecosystemd — ⚪ **0 anchors since boot**

| | 27.2 b3 | **27.2 b4** |
|---|---|---|
| `eco-replicate.sh` 3×60 s, anchors/s | 32.5 / 32.5 / 34.0 | **0.0 / 0.0 / 0.0** |
| EIO per 60 s | 468 / 468 / 492 | **0 / 0 / 0** |
| ecosystemd CPU | 12.2% | **0.0%** |
| anchors in the 10-minute window | 19,350 | **0** |

The process is alive — pid 13064, started 10:18:37 (T+4m37s) — and had used **0.34 s** of CPU in
40 minutes. Since boot it logged 569 records, 0 `SecTrustCopyAppleTrustAnchors`, 0
`UNIX error exception: 5`. It and `ecosystemanalyticsd` were the machine's #2 and #3 log emitters
on 27.2 b3; here ecosystemd logged **1** record in the window. **Not corroborated by a binary
diff:** the daemon binary lives outside the dyld cache and was never archived.

## Confirmed still broken

### #18 contactsd — 🔴 **the backlog crossed a seventh upgrade**

| | 27.2 b2 | 27.2 b3 | **27.2 b4** |
|---|---|---|---|
| unconsumed group-change rows | 115,412 | 122,126 | **125,914** |
| worst single source | 33,836 | 35,686 | **36,607** |

All 12 sources carried over, all 7 non-zero ones up, none reset. `Could not fetch group for
change type`: **9,254 since boot** from 39 processes (27.2 b3: 3,908 from 33, all in the first six
minutes). This time it is **not front-loaded** — 0 in the 10:40 bucket, then 2,111 more from
T+36m. contactsd read **40.1%** over 120 s at T+48m and **0.0%** in three 30 s samples right
after: bursty, not sustained; 34,192 of its 35,228 window records fell in the single minute 10:56.

### #19 imagent — 🔴 **the profile is byte-identical to 27.2 beta3**

`com.apple.imagent.sb`: 405 lines, `ContactsAccountsService` mentioned **0** times, **26**
siblings name it, `diff` against the 27.2 b3 archive prints nothing. imagent records naming the
service: **8,637 since boot**, 6,480 of them `E`-level carrying
`Connection init failed at lookup with error 159 - Sandbox restriction.` Peak 331 in one second;
2,290 in the window.

### #26 notification race — 🔴 **the OS-side window is still there**

Phase A: **0/8** visible at 0 ms, 3/8 at 5 ms, 5/8 at 10 ms, 7/8 at 15 ms, 8/8 at 25 ms. Phase B
first-visible: min 1.43 / **median 8.12** / max 13.46 ms (27.2 b3 11.62; macOS 26.6 0.01–0.03 ms).
Chrome's side was not re-checked.

### #2 Shortcuts/Siri ToolKit storm — 🟡 **still storming, and measured harder**

**244,437** records in the first 46 minutes (27.2 b3: 148,934 in 34). Peak **14,824/s** at
T+3m53s (27.2 b3: 7,384/s at T+11m12s), **107** seconds ≥ 500/s. It settled to ~1,000 per
10 minutes after T+26m. One boot; recorded, not credited either way.

### #1 CoreMedia — 🟡 **still emitting, still not decidable**

28 records in the window, all **DingTalk**. The count measures the apps.

## No observation — which is not a fix

- **#15 appstoreagent** — 0 hits from appstoreagent since boot. **Ninth** consecutive clean build.
  Two unrelated `Code=8` one-shots appeared (corespeechd 10:17:40, siriactionsd 10:18:28); neither
  is the Arcade task nor a loop.
- **#24 mds/CoreDuet** — 3.2/s, the idle band.
- **#16 / #17 / #29 and the app-crash entries (#5 #6 #8 #10)** — 0 matching reports in 45 minutes.

## Not tested

- **#20, #21, #27, #28, #29** — hand-driven triggers, not attempted.
- **#3 / #12** — WindowServer 48.2%, MenuBarAgent 1.1%, uncontrolled window count. No verdict.
- **#25, #13** — no dedicated window (#13's line: 0 in the window).

## Measurement notes

- **The CPU table's first run printed one row.** A zsh `for n in $names` loop does not word-split
  the variable; the table was recomputed from the same two snapshots with awk. Same trap as the
  `log` flags one recorded earlier.
- **The archive was taken after the upgrade** — it is the beta4 state. Copy again before the next update.
