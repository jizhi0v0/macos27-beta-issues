# release 27.0 `26A428` — re-verification of the open issues

macOS 27.0 shipped. The release build **`26A428`** replaced beta8 `26A5425a` on
**2026-09-11 04:28:46** per `/Library/Receipts/InstallHistory.plist`. The kernel
string moved for the first time since beta6, if only in its suffix:
`xnu-13432.1.9~1`, against `xnu-13432.1.9~3` on beta6/beta7/beta8.

Baseline to compare against: [`../beta8-26A5425a/`](../beta8-26A5425a/README.md).

⚠️ **No post-boot window again.** Everything was taken on the 2026-09-16 11:40:46
boot at **T+6h29m → T+6h44m**. beta8's window was T+21h20m, beta7's T+0 → 8m,
beta6's T+9m, so **no log volume here is a matched pair with any earlier build**.
The machine was **not quiesced** either: load average ~12, ~40 `/Applications`
bundles running. Counts are used only where they answer a question that survives
both caveats.

Xcode is now **27.0 `27A266a`** (installed 2026-09-15), but **#11** was not re-tested.

| file | contents |
|---|---|
| `steady-state-window.txt` | the 10-minute window, per-issue counts, cross-checks, the CPU table |
| `notificationcenter-spin.txt` | **#29 caught live** — timeline, OS report excerpt, `sample` breakdown |
| `shortcuts-since-boot.txt` | #2 over the whole boot, per second and per 10-minute bucket |
| `contactsd-backlog.txt` | #18 per-source rows, beta8 alongside |
| `eco-replicate.txt` | #23, raw `tools/eco-replicate.sh` output, 3×60 s |
| `crash-inventory.txt` | diagnostic reports since the install, incl. `Retired/`, parsed rather than grepped |

---

## Nothing was closed by shipping

Five issues were positively re-confirmed as still broken on the release build,
one of them caught live for the first time since August. Four produced no
observation, which is not the same thing. The rest could not be tested without
pulling a trigger by hand.

## Confirmed still broken

### #29 NotificationCenter — 🔴 **caught live, same stack**

The OS wrote its own `cpu_resource` report at 18:15:53 — **97% CPU over 93 s**,
heaviest stack `FocusBridge.preferencesDidChange` → `invalidateKeyViewLoop` →
`updateDefaultKeyViewLoop` → `KeyViewProxyCache.createOrUpdateProxyView`, the chain
recorded on 2026-08-22. Independently measured afterwards:

| | |
|---|---|
| 120 s cumulative utime+stime, 18:22–18:24 | **100.2%** |
| `sample` 10 s, main thread | **5,063 / 5,063** samples inside `FocusBridge.invalidateKeyViewLoop()` |
| spin observed | **≥ 10 min 44 s**, 18:14:19.8 → 18:25:04.3 |
| how it ended | `killall` at 18:25:04; launchd `service inactive`; respawn at 0.0% |

No self-recovery in that interval. The reporter describes the trigger as a
notification arriving while the pointer is near the banner position; pointer
position is not logged, so that is recorded as their account, not verified. The
report's interval opens 0.24 s *before* the nearest `Presenting` record, so this
capture does not pin which banner, if any, started it.

### #18 contactsd — 🔴 **the backlog crossed the release upgrade**

| | beta3 | beta5 08-11 | beta6 | beta7 | beta8 | **release** |
|---|---|---|---|---|---|---|
| unconsumed group-change rows | 53,686 | 76,366 | 91,030 | 98,489 | 102,678 | **110,247** |
| worst single source | 17,918 | 23,849 | 27,388 | 29,289 | 30,471 | **32,489** |

All 12 sources carried over, all 7 non-zero ones up, none reset — a fourth upgrade
the store has survived without draining. ⚠️ Not a rate (T+21h29m vs T+6h38m).

**Changed:** contactsd's own log volume collapsed — 44 records in the window
(1 on a predicate re-query minutes later; the disagreement is unexplained) against
beta8's 45,728, almost all of which was XPC churn. The client-side failure did
**not** change: `Could not fetch group for change type` appears 1,495 times across
the same fan-out of clients (beta8: 1,537). So the store still grows and clients
still fail to read it; what went away is contactsd's XPC noise.

### #19 imagent — 🔴 **the profile is byte-identical to beta8**

`com.apple.imagent.sb`: 404 lines, 0 mentions of `ContactsAccountsService`, 26
siblings that do name it — and `cmp` against the verified beta8 archive says the
file is **identical**. All 552 profiles that existed on beta8 are byte-identical;
the only change to `/System/Library/Sandbox/Profiles` is one added file. 1,058
imagent records naming the service in the window (794 of them `E`).

### #23 ecosystemd — 🔴 **rate signature unchanged**

| rep | eco % | anchors/s | lines/60s | EIO |
|---|---|---|---|---|
| 1 | 11.5 | 35.0 | 7,261 | 504 |
| 2 | 9.9 | 31.3 | 6,509 | 450 |
| 3 | 13.7 | 42.1 | 8,671 | 603 |

Mean CPU 11.7% (sd 1.6). The independent 10-minute window, predicate-pinned,
gives **19,975 = 33.3/s** — beta8's was 19,998 = 33.3/s. `ecosystemanalyticsd`
again emits nearly as many anchor calls (18,377) and remains untested. The two are
the #1 and #2 log emitters on the machine.

### #2 Shortcuts/Siri ToolKit storm — 🟡 **recurring all afternoon, peak 3,033/s**

The 10-minute window fell in a lull: 182 records, which alone would have read as
fixed. The since-boot query does not: 444,874 records, **peak 3,033 lines/s at
T+2h17m**, and ~17k-record bursts recurring from T+40m to at least T+5h50m (see
`shortcuts-since-boot.txt`). beta8's peak was 1,644/s. It does not self-settle on
release either.

## Still present, not decidable

- **#1 CoreMedia** — 74 records, all DingTalk. App-dependent; app mix uncontrolled.

## No observation — which is not a fix

- **#24 mds/CoreDuet** — 2.0/s, the idle band.
- **#15 appstoreagent** — 0 `Code=8`; the one appstoreagent report since install is
  a disk-write report, not this loop.
- **#16 / #17 and the app-crash entries (#5 #6 #8 #10)** — 0 matching reports in
  5 days 14 h, checked against parsed payloads. Ordinary use, triggers not exercised.

## Not tested

- **#21, #26, #27, #28** — hand-driven triggers, not attempted.
- **#3 / #12** — WindowServer 67.8% and MenuBarAgent 0.8%, measured with an
  uncontrolled window count **and** NotificationCenter pegged at the same time.
  No verdict. The OS also wrote two WindowServer `cpu_resource` reports (56%, 61%)
  since install; same caveat.
- **#25**, **#13** — no dedicated window taken.

## Measurement notes

- The first CPU table came back **empty**: the loop ran under zsh, which does not
  word-split an unquoted `$names`, so `pgrep` matched nothing. Re-run under bash.
  Same trap as the `log` flags one already recorded.
- A plain grep for `modelmanagerd` hits all 10 `JetsamEvent` reports, which list
  every process. The inventory checks the parsed `procName` and
  `lastExceptionBacktrace` instead.
- The beta8 binary archive made #19's comparison a byte-level one this round.
  **Copy the release cache before the next update** or the next comparison
  loses its old side.
