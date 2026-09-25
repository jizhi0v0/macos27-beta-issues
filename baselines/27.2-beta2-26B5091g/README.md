# macOS 27.2 beta2 `26B5091g` — re-verification of the open issues

macOS 27.2 beta2 **`26B5091g`** replaced the release build `26A428` on
**2026-09-25 07:08:18 UTC** (15:08:18 +0800) per `/Library/Receipts/InstallHistory.plist`,
two minutes after the 15:06:19 boot. The kernel moved for real this time:
**`xnu-13432.40.162~92`**, against `xnu-13432.1.9~1` on release. No 27.1 build was
installed on this machine in between.

Baseline to compare against: [`../release-26A428/`](../release-26A428/README.md).

⚠️ **Clock position.** The 10-minute window is at **T+1h54m → T+2h04m**, the replicates and
probe at T+2h04m → T+2h10m. release was T+6h29m, beta8 T+21h20m, so **no log volume here
is a matched pair** with any earlier build. Not quiesced: load average ~11, 32
`/Applications` bundles running, and the post-update reindex was still going
(`mds_stores`, `mediaanalysisd`, `STExtractionService` reports in the inventory).

| file | contents |
|---|---|
| `steady-state-window.txt` | the 10-minute window, per-issue counts, since-boot cross-checks, the #19 profile diff, the CPU table |
| `contactsd-backlog.txt` | #18 per-source rows, release alongside |
| `eco-replicate.txt` | #23, raw `tools/eco-replicate.sh` output, 3×60 s |
| `shortcuts-since-boot.txt` | #2 over the whole boot, per second and per 10-minute bucket |
| `race-probe.txt` | #26, raw `tools/un-delivered-race-probe` output, 8+8 trials |
| `crash-inventory.txt` | diagnostic reports since the install, incl. `Retired/`, parsed rather than grepped |

Binary archive: `~/Developer/macos27-27.2beta2-binary-archive/` — dyld shared cache (84
files, 6.7 GiB) and sandbox profiles (553 files), both verified by sha256 against the live
source. **The release `26A428` cache was not archived before this upgrade and is gone**; its
sandbox profiles survive in effect, because on 2026-09-16 they were byte-identical to the
beta8 archive apart from one named addition.

---

## Nothing was closed by 27.2 beta2

Five issues were positively re-confirmed. Four produced no observation, which is not the
same thing. The rest need a trigger pulled by hand.

## Confirmed still broken

### #18 contactsd — 🔴 **the backlog crossed a fifth upgrade**

| | beta3 | beta5 08-11 | beta6 | beta7 | beta8 | release | **27.2 b2** |
|---|---|---|---|---|---|---|---|
| unconsumed group-change rows | 53,686 | 76,366 | 91,030 | 98,489 | 102,678 | 110,247 | **115,412** |
| worst single source | 17,918 | 23,849 | 27,388 | 29,289 | 30,471 | 32,489 | **33,836** |

All 12 sources carried over, all 7 non-zero ones up, none reset. `Could not fetch group for
change type` was **0 in the window** — and **9,107 since boot** on an unscoped predicate,
last seen 17:12:31. The window sat between bursts.

### #19 imagent — 🔴 **the profile changed, but not where it matters**

`com.apple.imagent.sb` changed for the first time since this issue was filed: 404 → **405**
lines. The diff is one line, `(global-name "com.apple.sharereportingd")`. Mentions of
`ContactsAccountsService`: still **0**; siblings that name it: still **26**. imagent records
naming the service: **0 in the window, 20,456 since boot**, including 151 `E` records in two
seconds at 17:11:24 (`Code=4099 … was invalidated`).

### #23 ecosystemd — 🔴 **rate signature unchanged**

| rep | eco % | anchors/s | lines/60s | EIO |
|---|---|---|---|---|
| 1 | 15.1 | 35.0 | 8,101 | 504 |
| 2 | 14.4 | 32.5 | 7,519 | 468 |
| 3 | 14.5 | 33.5 | 7,753 | 483 |

Mean CPU 14.7% (sd 0.3). The window gives **19,888 = 33.1/s** (predicate 19,950) against
release 33.3/s and beta8 33.3/s. `ecosystemanalyticsd` 18,354.

### #26 notification race — 🔴 **the OS-side window is still there**

Phase A: **0/8** visible at 0 ms, 3/8 at 5 ms, 8/8 at 25 ms. Phase B first-visible: min
7.28 / **median 9.70** / max 34.72 ms (beta7 8.36, beta6 8.07; macOS 26.6 0.01–0.03 ms).
Chrome is now `154.0.8037.58` and its side was **not** re-checked, so this speaks to the
precondition, not to the click symptom.

### #2 Shortcuts/Siri ToolKit storm — 🟡 **still storming**

98,046 records since boot to 17:17. Boot burst peak **8,813/s**; after it, bursts of
**1,885/s** at T+40m and ~1,550/s as late as T+2h10m, 48 seconds ≥ 500/s. No post-boot
10-minute bucket exceeds 9,411, where release's recurring bursts were ~17k each — a
different clock position on one boot, so that is recorded, not credited.

## Still present, not decidable

- **#1 CoreMedia** — 54 records: WeType, Safari, Mail, 18 each. App mix different again.

## No observation — which is not a fix

- **#15 appstoreagent** — 0 `Code=8`. Seventh consecutive clean build (beta3/5/6/7/8,
  release, 27.2 b2).
- **#24 mds/CoreDuet** — 2.0/s, the idle band.
- **#29 NotificationCenter** — no `cpu_resource` report, 0.8% average CPU over 2 h 05 m.
  release caught it once in 5.5 days; two hours cannot say anything.
- **#16 / #17 and the app-crash entries (#5 #6 #8 #10)** — 0 matching reports in 2 h 15 m.

## Not tested

- **#20, #21, #27, #28** — hand-driven triggers, not attempted.
- **#3 / #12** — WindowServer 46.2%, MenuBarAgent 0.2%, uncontrolled window count. No verdict.
- **#25, #13** — no dedicated window.

## Measurement notes

- **Two in-window zeros were false.** #18's `Could not fetch group` and #19's imagent errors
  both read **0** in the 10-minute window and **9,107 / 20,456** since boot. Every zero here
  was re-queried since boot before being believed; the same trap as #2's lull on release.
- **`--end` leaked once, with a predicate.** The #2 since-boot query with `--end 17:20:00`
  also returned a 2,090-record burst at 17:22:28–17:22:40. Two 1-minute re-queries were
  bounded correctly, so this is not "always ignored" — but a predicate is no longer enough
  on its own. The #2 counts are sliced by timestamp.
- **Copy the 27.2 b2 cache before the next update** — done this time, see above.
