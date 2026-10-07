# macOS 27.2 beta3 `26B5101f` — re-verification of the open issues

macOS 27.2 beta3 **`26B5101f`** replaced 27.2 beta2 `26B5091g` on **2026-10-07 12:22:37 +0800**
per `/Library/Receipts/InstallHistory.plist`; the machine booted into it at 12:26:01. Kernel
**`xnu-13432.40.177.0.3~56`**, against 27.2 beta2's `xnu-13432.40.162~92`.

Baseline to compare against: [`../27.2-beta2-26B5091g/`](../27.2-beta2-26B5091g/README.md).

⚠️ **Clock position.** This is a **post-boot** pass: the 10-minute window is at **T+13m → T+23m**,
the replicates and race probe at T+13m → T+17m, the #29 banner burst at T+25m, the CPU table at
T+32m. 27.2 beta2 was T+1h54m, release T+6h29m, beta8 T+21h20m, so **no log volume here is a
matched pair** with any earlier build. Not quiesced: load average 15.65 / 28.18 / 24.75 at the
window's start, 22 `/Applications` bundles running, and the post-update reindex active.

Apple's [macOS 27.2 beta3 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes)
(read 2026-10-07) mention **none** of the open entries and none of our filed FB numbers. The one
Shortcuts known issue (187499433, *Describe a Shortcut* fails) is unrelated to #2.

| file | contents |
|---|---|
| `post-boot-window.txt` | the 10-minute window, per-issue counts, since-boot cross-checks, the #19 profile check, the CPU table |
| `contactsd-backlog.txt` | #18 per-source rows, 27.2 b2 alongside |
| `eco-replicate.txt` | #23, raw `tools/eco-replicate.sh` output, 3×60 s, plus a four-minute determinism check |
| `shortcuts-since-boot.txt` | #2 over the whole boot, per second and per 10-minute bucket |
| `race-probe.txt` | #26, raw `tools/un-delivered-race-probe` output, 8+8 trials |
| `notification-burst.txt` | #29, 20 banners in 60 s with the reporter gesturing nearby |
| `crash-inventory.txt` | diagnostic reports since the install, incl. `Retired/`, parsed rather than grepped |

Binary archive: `~/Developer/macos27-27.2beta3-binary-archive/` — dyld shared cache (84 files,
6.7 GiB) and sandbox profiles (553 files), both verified by sha256 against the live source; #19's
three numbers reproduce from the archive alone. Against the 27.2 beta2 archive, 18 sandbox
profiles changed and none were added or removed.

---

## Nothing was closed by 27.2 beta3

Six issues were positively re-confirmed. Three produced no observation, which is not the same
thing — and one of those (#29) had its trigger deliberately exercised and still decides nothing,
because there is no recipe that provably triggered it before. The rest need a trigger pulled by hand.

## Confirmed still broken

### #18 contactsd — 🔴 **the backlog crossed a sixth upgrade**

| | beta3 | beta5 08-11 | beta6 | beta7 | beta8 | release | 27.2 b2 | **27.2 b3** |
|---|---|---|---|---|---|---|---|---|
| unconsumed group-change rows | 53,686 | 76,366 | 91,030 | 98,489 | 102,678 | 110,247 | 115,412 | **122,126** |
| worst single source | 17,918 | 23,849 | 27,388 | 29,289 | 30,471 | 32,489 | 33,836 | **35,686** |

All 12 sources carried over, all 7 non-zero ones up, none reset. `Could not fetch group for
change type`: **0 real in the window**, **3,908 since boot** from 33 processes, all of it in the
first six minutes (last 12:32:28). contactsd read 0.0% over 120 s at T+32m but had already
spent **146.7 s** of CPU since boot — 7.6% averaged over the half hour.

### #19 imagent — 🔴 **the profile is byte-identical to 27.2 beta2**

`com.apple.imagent.sb`: 405 lines, `ContactsAccountsService` mentioned **0** times, **26**
siblings name it, and `diff` against the 27.2 beta2 archive prints nothing. imagent records
naming the service: **3,529 since boot** (0 in the window), 2,648 of them `E`-level with the
failure stated outright — `Connection init failed at lookup with error 159 - Sandbox restriction.`
Peak 259 in one second.

### #23 ecosystemd — 🔴 **rate signature unchanged, and the loop is deterministic per minute**

| rep | eco % | anchors/s | lines/60s | EIO |
|---|---|---|---|---|
| 1 | 11.1 | 32.5 | 6,295 | 468 |
| 2 | 11.9 | 32.5 | 6,295 | 468 |
| 3 | 13.6 | 34.0 | 6,603 | 492 |

Mean CPU 12.2% (sd 1.0); 13.7% in the separate 120 s sample. The window gives **19,350 =
32.3/s** (predicate 19,350) against 27.2 b2's 33.1/s. Reps 1–2 being identical looked like the
tool's old flush-boundary defect, so four consecutive clock minutes were queried independently:
each returned **exactly 6,139 lines / 1,950 anchors / 468 EIO** with different first and last
timestamps. The loop runs a fixed amount of work per minute; the identical reps are real.

### #26 notification race — 🔴 **the OS-side window is still there**

Phase A: **0/8** visible at 0 ms, 0/8 at 5 ms, 4/8 at 10 ms, 7/8 at 15 ms, 8/8 at 25 ms. Phase B
first-visible: min 5.91 / **median 11.62** / max 17.64 ms (27.2 b2 9.70; macOS 26.6 0.01–0.03 ms).
Chrome is now `155.0.8059.40` and its side was **not** re-checked.

### #2 Shortcuts/Siri ToolKit storm — 🟡 **still storming**

**148,934** records in the first 34 minutes. Peak **7,384/s** at T+11m12s (27.2 b2: 8,813/s at
T+2m52s), an earlier 3,291/s burst at T+1m, and **116** seconds ≥ 500/s. One boot; the shape
differences are recorded, not credited.

### #1 CoreMedia — 🟡 **still emitting, still not decidable**

22 records in the window, all **DuoMail** — a new single emitter. The count measures the apps.

## No observation — which is not a fix

- **#15 appstoreagent** — 0 `Code=8` in the window and **0 since boot**. **Eighth** consecutive
  clean build (beta3/5/6/7/8, release, 27.2 b2, 27.2 b3).
- **#24 mds/CoreDuet** — 4.2/s, the idle band.
- **#29 NotificationCenter** — 20 banners in 60 s with the reporter gesturing near them: **no
  beachball**. NotificationCenter averaged ~29% while presenting and fell to ~0.9% the moment
  the banners stopped; 0.0% at T+32m; no `cpu_resource` report. One negative attempt at a
  trigger that has no recipe.
- **#16 / #17 and the app-crash entries (#5 #6 #8 #10)** — 0 matching reports in 36 minutes.

## Not tested

- **#20, #21, #27, #28** — hand-driven triggers, not attempted.
- **#3 / #12** — WindowServer 45.8%, MenuBarAgent 0.7%, uncontrolled window count. No verdict.
- **#25, #13** — no dedicated window.

## Measurement notes

- **`log` logs its own command line.** Every `/usr/bin/log` invocation writes a `Df` record
  containing its full argument list, predicate included — so an `eventMessage CONTAINS "X"` query
  matches every *earlier* query for `X`. It turned #15's since-boot count from 0 into 2, and was
  the only in-window hit for #18. Every since-boot count here excludes process `log`. Earlier
  baselines do not record excluding it; an unscoped since-boot count there can be inflated by at
  most the number of prior queries for the same string — negligible against #18/#19's thousands,
  decisive against a zero.
- **`--end` returned a record past its bound again** — the #18 query bounded at 13:00:00 returned
  a 13:00:31 record, which was that query's own `log` self-record. Whether this is the same leak
  as 27.2 b2's 2,090-record #2 burst is not established. Counts are sliced by timestamp.
- **The archive was taken after the upgrade, not before the next one** — it is the beta3 state,
  and is what makes a beta3 ↔ next-build diff possible. Copy again before the next update.
