# beta5 `26A5406e` — closing snapshot before the beta6 upgrade

Taken **2026-08-18**, uptime 3 d 11 h, immediately before updating to macOS 27 beta6.
Purpose: make the first beta6 measurements *comparable*, and preserve the things an
OS upgrade destroys.

---

## 1. What is archived **outside** this repo (too large to commit)

`~/Developer/macos27-beta5-binary-archive/`

| Path | Size | Why it cannot be recreated after the upgrade |
|---|---|---|
| `dyld_shared_cache/` (82 files) | 6.6 GB apparent / 2.3 GB on disk | **#17**'s 🟢 rests on a beta4↔beta5 binary diff of `-[NSRemoteView maintainContainingWindowNotifications:]`, and **#19**'s answers on disassembling `ContactsPersistence` 3844.100.1 + `CNRetry`. None of those frameworks exist as files on disk — they live **only** in this cache. Once beta6 overwrites it, the beta5 side of any future diff is gone (short of re-downloading the IPSW). |
| `sandbox-profiles/` (552 files) | 2.3 MB | `com.apple.imagent.sb` — **404 lines** on beta5 (403 on beta3). #19's whole argument is the absence of one global-name line here, plus its presence in **26** sibling profiles (re-verified in this snapshot). |
| `diagnostic-reports/` (`ips/` 9 files, `spin/` 8 files) | 134 MB | Raw `.ips` / `.spin` / `.shutdownStall`. **Deliberately not committed** — this repo is public and spindumps carry the full process list, paths and machine identifiers. `crash-inventory.txt` here holds the committable summary. |
| `meta/dyld_shared_cache.sha256` | — | Integrity. Spot-checked 3 files against the live source incl. the 1.67 GB `.79.dyldlinkedit` — all match. `cp` reported exit=1 but the 83 errors are **all** `chflags: Operation not permitted` (restricted flags), not data errors; 82/82 files present. |

Extraction later: `dyld_shared_cache_util -extract <dir> dyld_shared_cache_arm64e`.

## 2. What is in this directory

| File | Contents |
|---|---|
| `system-facts.txt` | OS/kernel/Xcode/SDK builds, hardware, framework `CFBundleVersion`s (serial + hardware UUID redacted — public repo) |
| `contactsd-backlog.txt` | **#18** per-source unconsumed group-change rows |
| `log-rates-30m.txt` | retrospective 30-min log rates for #1 #3 #18 #19 #23 #24 |
| `cpu-cumulative-300s.txt` | cumulative utime+stime deltas over 300 s, with the load context |
| `crash-inventory.txt` | summary of every `.ips` / `.spin` / `.shutdownStall` left on the machine (the files themselves are in the outside archive — see §1) |
| `app-versions.txt` | trigger-side app versions (4 have already drifted from what issues/ records) |
| `cpu-sample.sh`, `collect-logrates.sh` | re-run these **verbatim** on beta6 |

## 3. beta5 closing numbers → what to compare against

| Issue | Metric | recorded (2026-08-11) | **this snapshot (08-18)** | note |
|---|---|---|---|---|
| #18 | unconsumed group-change rows | 76,366 | **90,209** | beta3 was 53,686. Still climbing: **+18 % in 7 days**. Worst source 23,849 → **27,202** |
| #18 | contactsd log lines | ~218,000 **/ hour** | **223,653 / 30 min** | ≈ 2× the recorded rate |
| #18 | `Could not fetch group`, **all** processes | 7,569 / 30 min | **19,832 / 30 min** | contactsd itself only **77** — never attribute this line to contactsd |
| #19 | imagent `ContactsAccountsService` | 6,522 / 30 min | **14,801 / 30 min** | ≈ 2.3× |
| #19 | imagent sandbox/deny | 4,894 / 30 min | **11,105 / 30 min** | |
| #23 | ecosystemd log lines | "≈ half the beta4 rate" | **147,364 / 30 min** | |
| #3 | `Invalid window` spam | — | **2,091 / 30 min** | CPU was called 🟢 on beta5; the log spam is not gone |
| #1 | `fpSupport_GetVideoRange` | 1,744 / 8 min *(post-boot)* | **131 / 30 min** *(steady state)* | **different windows — not comparable.** See §4 |
| #17 | NSRemoteView crash reports on disk | 32 | **0** | the `.ips` history has rotated away entirely; only 9 `.ips` remain machine-wide, all from 08-18 |
| **#3** | **WindowServer CPU** | **~4 % (clean idle) → 🟢** | **79.7 % over 100 s; 37.4 % lifetime average** | ⚠️ see §7 — **not** a quiesced measurement, so this does not overturn the 🟢 on its own, but it needs settling **before** the upgrade |
| #18 | contactsd CPU | 20.2 % cumulative | **27.0 %** over 100 s | |

## 4. ⚠️ The beta6 first-boot window is a one-shot resource

**#1** and **#2** only produce their real numbers in the **post-boot** window. #1's earlier ⚪
was a *missed window*, not a fix. The upgrade reboot is the one clean post-boot window
available — miss it and you wait for the next reboot.

So on beta6, **before doing anything else**:

```bash
/usr/bin/log show --last 8m --style syslog | grep -c fpSupport_GetVideoRange
```
and per-emitter:
```bash
/usr/bin/log show --last 8m --predicate 'eventMessage CONTAINS "fpSupport_GetVideoRange"' --style syslog | awk '{print $4}' | sort | uniq -c | sort -rn | head
```

## 5. beta6 retest order

1. **First boot, first 8 minutes** — #1 / #2 post-boot capture (above). One shot.
2. **Immediately after** — `contactsd-backlog.txt` re-run. An upgrade may migrate or rebuild
   the Contacts stores: **a zeroed backlog is not a fix.** Only "stays at 0 and does not start
   climbing again over days" is a fix.
3. `./collect-logrates.sh <out>` once the machine reaches its normal working load.
4. `./cpu-sample.sh <out> 300` with a comparable app set (see the load context line).
5. `wc -l /System/Library/Sandbox/Profiles/com.apple.imagent.sb` — 404 → 405 with the
   global-name line added would be #19 fixed at the source.
6. `grep -l NSRemoteView` across all `.ips` (**under bash**, see §6) — any hit flips #17 to 🔴.

## 6. Methodology traps that bit during *this* snapshot

- `log` is a **zsh builtin** — always `/usr/bin/log`. (Already recorded, still true.)
- **zsh aborts a command on an unmatched glob**, faking a 0 result. The first crash inventory
  came back empty for exactly this reason; it must run under `bash` with `shopt -s nullglob`.
- **macOS ships bash 3.2 — no associative arrays.** The first `cpu-sample.sh` used `declare -A`
  and emitted a table with a header and **zero rows**, no error. Fixed to temp files.
- `ps %CPU` is a decaying average and is **not decision-grade**; sample cumulative
  `utime+stime` deltas instead.
- Pin `process ==` before attributing any framework-emitted log line (#18's 19,832 vs 77).

## 7. ⚠️ Unfinished business: #3 must be re-measured **before** upgrading

`cpu-cumulative.txt` puts **WindowServer at 79.7 %** over the 100 s window, and its
**lifetime average is 37.4 %** (112,796 s of CPU across 3 d 11 h of uptime). #3 was closed
🟢 on beta5 at *~4 % on a clean idle desktop*. 37.4 % sits just under the 42–46 % floor that
#3 originally described.

This is **not** decision-grade yet and is **not** being written into #3: the desktop was not
quiesced (load average 30–94, 33 apps running, Claude among them). But it cannot be left
unmeasured either — after the upgrade there is no way to go back and get the beta5 number.

**Run this in Terminal — not through Claude — before starting the beta6 install:**

```bash
bash tools/ws-idle-baseline.sh
```

then quit Claude, Chrome and everything else and leave the machine alone for ~3 minutes
(disable display sleep first). Read `/tmp/ws_idle_baseline.txt` afterwards and drop it in
this directory. If it lands near 4 %, #3's 🟢 holds and the 79.7 % above was workload.
If it lands in the 40 % band, #3 regressed on beta5 and that has to be recorded **as a beta5
fact**, before beta6 muddies the attribution.

Related methodology point, already demonstrated in `cpu-cumulative.txt`: `ps %CPU` showed
`ecosystemd` 42.7 % and `trustd` 21.8 % minutes earlier, while the cumulative-delta method
puts them at **0.94 %** and **0.43 %**. The `ps` numbers were artifacts. WindowServer, by
contrast, is high under *both* methods — which is why it is the one that needs settling.

## 8. Machine state at snapshot time — read the numbers with this in mind

Load average **60–94** across the snapshot, `mds_stores` and `WindowServer` both high in `ps`,
**3 JetsamEvent** reports and 5 `ExcUserFault` crashes on 2026-08-18 alone. This is **not** a
quiet machine, and the rate doublings in §3 may partly reflect that rather than a beta5 drift.
The beta6 comparison should be taken under a comparable load, or the difference is not
attributable. This is stated as an open confound, not resolved.
