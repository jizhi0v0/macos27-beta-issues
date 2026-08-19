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

### #3 WindowServer — **blocked on the post-upgrade reindex**

`ws-idle-baseline.sh` returned **45.6 %** (122 s, quiesced desktop), and WindowServer's
since-boot average is **46.2 %** — both inside the 42–46 % floor that originally defined #3,
against the ~4 % clean-idle figure that closed it 🟢 on beta5.

**This is not usable yet.** The run happened 1.5–4.5 minutes after boot, and its own midpoint
sample shows why: `mds_stores` 63 %, `corespotlightd` 42 %, `ANECompilerService` 36 %,
`mediaanalysisd` 18 %, `photolibraryd`, `suggestd` — a full post-upgrade Spotlight/media
reindex. `mds_stores` was still at 84 % at T+10m. Also live throughout: `Claude.app`
(Electron, a known compositing driver) and three screen-capture agents
(AweSun / RustDesk / ToDesk — all with 0 ESTABLISHED connections, so idle, but resident).

**To settle it:** wait for `mds_stores` to fall below ~10 %, then re-run

```bash
bash tools/ws-idle-baseline.sh
```

quitting Claude and the remote-desktop agents as well this time. Landing near 4 % means #3's
🟢 holds; landing at 45 % again means #3 regressed on beta6 and needs a spindump.

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
