# beta6 `26A5416b` — first measurements

Upgraded from beta5 `26A5406e` on **2026-08-19**, boot at **13:12:23**.
Xcode deliberately left at `27A5237l`, so the OS row moves and the toolchain row does not —
SDK-tracked entries (**#11**) are untouched and not re-tested here.

Baseline to compare against: [`../beta5-final/`](../beta5-final/README.md).

| file | contents |
|---|---|
| `postboot-window.txt` | the one-shot post-boot window, T+0 → T+7m47s |
| `contactsd-backlog.txt` | #18 per-source rows, taken T+9m |

Raw post-boot log (32 MB gz) is at `~/Developer/macos27-beta6-postboot/` — not committed
(public repo; a full system log carries paths and identifiers). Captured with
`log show --start <boot>`: `--last 8m` **spans the reboot** and mixes the beta5 session in,
which is what the first two ad-hoc counts did.

---

## Decided

### #18 contactsd — 🔴 **still broken on beta6, decisively**

| | beta3 | beta5 08-11 | beta5 08-18 | **beta6 T+9m** |
|---|---|---|---|---|
| unconsumed group-change rows | 53,686 | 76,366 | 90,209 | **91,030** |
| worst single source | 17,918 | 23,849 | 27,202 | **27,388** |

**All 12 sources carried over, every non-zero one increased, none reset.** That settles the
question this snapshot was built to answer: the upgrade did **not** migrate or rebuild the
Contacts stores, so there is no "cleared by the upgrade" false positive to rule out — the same
backlog crossed an OS upgrade and kept growing. contactsd log volume is unchanged too
(27,809 lines in the 8-minute window ≈ 214k/h, against beta5's ~218k/h).

### #19 imagent — 🔴 unchanged **at the source level**

`com.apple.imagent.sb` is still **404 lines** and still the outlier against **26** sibling
profiles that name `com.apple.AddressBook.ContactsAccountsService` (both re-verified on beta6).
The one-line fix was not applied. 2,383 `ContactsAccountsService` lines in the post-boot window.

### #2 Shortcuts / siriactionsd — measured **worse**, one window

| | beta5 (post-boot capture) | **beta6 (post-boot)** |
|---|---|---|
| peak rate | 181 lines/s | **864 lines/s** |
| lines in window | — | 16,203 |

Busiest seconds: 864 @ 13:13:19, 725 @ 13:13:21, 640 @ 13:13:55 — i.e. within ~60 s of boot.
Same window *shape* as beta5's figure, so the comparison is fair, but this is **one window**
and has not been replicated. Not a verdict yet.

## Not decidable yet

### #3 WindowServer — 🔴 **regressed on beta6**

Third run is clean and the verdict is in.

| run | WindowServer | window valid? |
|---|---|---|
| 13:14–13:16:56 | 45.6 % | ✗ post-upgrade reindex (`mds_stores` 63→84 %, `corespotlightd` 42 %), and idle reset mid-window (`actualUserIdle` 8.2 → 27.2) — the machine was touched |
| 13:28:28–13:31:17 | 47.5 % | ✗ screen saver started 13:30:28, 75 s into the 122 s window (~39 % of it). A hand-launched `caffeinate -du -t 420 &` had died at age 00:00:12 |
| **13:36:38–13:39:29** | **46.5 %** | ✅ **valid** |

**Why run 3 counts:** the script held its own assertion for **2 m 04 s**, covering the whole
122 s window (powerd: `Created` → `ClientDied age:00:02:04`, killed by the script afterwards).
loginwindow logged `PMNoDisplaySleepEnabled so do not launch screen saver` — the screen saver
was *suppressed by the assertion*, not merely late. `actualUserIdle` was sampled once at 82.6 s
and **never reset**, so there was no input during the window. Reindex was finished, Claude was
quit, and the only processes owning on-screen windows were Finder (13), Surge (2), WindowServer
(2), WindowManager and DuoTerminal.

**The comparison:**

| | WindowServer, quiesced |
|---|---|
| beta4 `26A5388g` (the original regression) | 42–46 % floor, min 42.0 % across 10 replicates |
| beta5 `26A5406e` → closed 🟢 | **~4 %** clean idle, 7.7 % with menu-bar apps |
| **beta6 `26A5416b`** | **46.5 %** |

Same machine, same script, same method. beta6 is back inside the beta4 band — a 10×
regression against beta5, far too large to be explained by the two things still running
(Activity Monitor at 5.5 %, `ecosystemd` at 18 % at midpoint). `MenuBarAgent` is 0.2 %, so
this is **not** [#22](https://github.com/jizhi0v0/macos27-beta-issues/issues/22)'s mechanism.
`Invalid window` spam is 9/60 s, still decoupled from the CPU as always.

**Caveat, stated:** this is **one** valid run. The two contaminated runs landed at 45.6 % and
47.5 %, which corroborates but does not replicate — beta4's original verdict took 10 replicates.
The 🔴 is called on the size of the gap (4 % → 46.5 %), not on n.

**Next:** capture the stack while it reproduces —

```bash
sudo spindump WindowServer 8 -o ~/ws_spindump_beta6.txt
```

### #1 CoreMedia — emitter set did not match, retest needed

56 hits in the post-boot window (Mail 31, WeType 22, UURemote 3) against beta5's **1,744 in
8 min**. **Not comparable:** 77 % of beta5's count was DingTalk (1,338), and DingTalk was not
running — it had been quit for the WindowServer test. Re-run with DingTalk, WeType and Mail
all up before reading anything into this. (UURemote is a new emitter not in the write-up.)

## Other post-boot counts, recorded without interpretation

| | beta6 post-boot window (7m47s) |
|---|---|
| total log lines | 1,569,559 |
| `ecosystemd` (#23) | 56,808 |
| `mds` + `mds_stores` (#24) | 8,792 |
| `Invalid window` (#3 spam) | 296 |
| `Could not fetch group`, all processes (#18) | 1,054 |
| `AddressBookManager` spawns | 1 |
