VERIFICATION: CONFIRMED — 32:51 cumulative CPU TIME over 4h07m uptime (≈13% avg), peak burst ~143% (28.6 s CPU in 20 s wall, 14:00:45→14:01:05); 839,240 contactsd log lines in 4 h; 89,107 TCC authorization requests vs 85,516 persistence requests (1.04 each); 55 AddressBookManager spawns. Captured 2026-07-16, beta3 revision 26A5378n, contactsd 3837.100.1. Loop still firing during capture (ZTRANSACTIONID advanced 17929 → 17943 mid-session).

NOTE BEFORE FILING: the iCloud DSID and account email are redacted below as <DSID> / <user> because this draft lives in a public repo. Restore the real values (and attach the unredacted sysdiagnose) when submitting to Apple — Apple needs them to identify the account.

# Title
contactsd spawns AddressBookManager against itself in a self-sustaining loop: an unconsumable CardDAV collection-as-group change-history row is re-read every ~2 s, rebroadcasting ABDatabaseChangedExternallyNotification to 109 clients (~143% CPU bursts, 840k log lines / 4 h)

# Apple area / component to select
Contacts / contactsd. Sub-area: change history (Core Data persistent history) / CardDAV account sync.

# Description
On macOS 27.0 (26A5378n), `contactsd` (3837.100.1) burns **32 min 51 s of CPU over 4 h 07 m of uptime (≈13% average)**, in bursts measured at **~143%**, while emitting **839,240 log lines in 4 hours**. It is episodic, not constant: quiet stretches (4 log lines / 10 min) alternate with storms (207,518 lines in one 10-minute bucket).

The cycle is **entirely internal to Apple components — no third-party app is involved**, and therefore there is nothing the user can quit to stop it:

1. `contactsd` performs a mach lookup for `com.apple.AddressBook.abd`; launchd spawns `AddressBookManager` (**55 times in 4 h**, each living ~250 ms).
2. `AddressBookManager` mounts all 12 source stores and opens ~448 connections back to `com.apple.contactsd.persistence` per launch.
3. This touches a malformed CardDAV record (below). `contactsd` logs:
   `(Contacts) Could not fetch group for change type 1 with identifier <private>, making it a delete change type.`
4. It **rewrites the group record** — `Z_OPT` (Core Data's optimistic-lock counter) equals the change count exactly, **17,918**, proving one rewrite per pass — which emits a *new* change row.
5. It rebroadcasts `ABDatabaseChangedExternallyNotification`; **109 distinct client daemons** re-query.
6. Each re-query costs a **fresh TCC IPC**: 89,107 TCC authorization requests against 85,516 persistence requests = **1.04 per request, i.e. no caching** — while account data *is* cached in the same code path (`Using cached account information` logs per connection).
7. `contactsd` looks up `com.apple.AddressBook.abd` again → back to step 1. Cycle repeats every ~2 s.

The change row is **never consumable**: the group fetch fails on every pass, so the row is re-read forever while each pass appends another.

**The requestor is contactsd itself.** launchd only logs `Successfully spawned AddressBookManager[…] because ipc (mach)` and never names the requestor; the client-side XPC lookup log is debug-level and not persisted; `log stream` drops messages under this load. Captured by polling for the 250 ms process and snapshotting the in-memory buffer with `log collect --last 45s`, tccd's AttributionChain shows:

```
tccd: AttributionChain: accessing={identifier=com.apple.AddressBook.abd, pid=92637,
        binary_path=…/AddressBookManager.app/Contents/MacOS/AddressBookManager},
      requesting={identifier=com.apple.contactsd, pid=1984,
        binary_path=/System/Library/Frameworks/Contacts.framework/Support/contactsd}
```

Requestor tally in that capture: **com.apple.contactsd ×59**, com.apple.sandboxd ×3, com.apple.AddressBook.abd ×2 (itself). No third-party process appears. (The only app on the machine holding Contacts TCC access, Spark.app, had **zero log activity for 5 h** — it never ran. All AddressBook TCC decisions in the window are Apple daemons with `AuthRight: Allowed, Reason: Entitled`.)

## The malformed record: CardDAV collections materialized as ABCDGroup

The "group" is the **CardDAV collection itself**. For the worst source, `migration.log` shows:

```
### DOWNLOAD FROM https://<user>@p56-contacts.icloud.com/<DSID>/carddavhome/card/ ###
### Local Groups: 0 ###
### Server Groups: 0 ###
```

The path segment `card` **is** the group's name. The account has **no groups at all**, yet carries one `ABCDGroup` record plus 17,918 change rows against it.

The data model is **inverted** — collection metadata sits on the group, not the container:

| Field | Container (`Z_PK=1`, `CNCDContainer`) | Group (`Z_PK=6`, `ABCDGroup`, `ZUNIQUEID=973F0C78-…:ABGroup`) |
|---|---|---|
| `ZNAME` | *(blank)* | `card` |
| `ZEXTERNALCOLLECTIONPATH` | *(blank)* | `/<DSID>/carddavhome/card/` |
| `ZEXTERNALGROUPBEHAVIOR` | — | `1` |
| `ZTYPE` | `0` | *(null)* |

`ZTRANSACTIONID` for that store spans **5 → 17943**: from transaction #5 onward, essentially the store's entire lifetime is this one group.

## Scope: CardDAV-only, Exchange unaffected

Every CardDAV source with a collection-level group record has thousands of unconsumed group changes; the Exchange source has 1 group and **1** change, consumed normally. Sources with no group record have 0 changes.

| Account type | Group name | Unconsumed group change rows |
|---|---|---|
| CardDAV | `card` | **17,918** |
| CardDAV | `Contacts` | 6,713 |
| CardDAV | `Address Book` | 6,589 |
| CardDAV | `Address Book` | 6,564 |
| CardDAV | `Address Book` | 6,544 |
| CardDAV | `Address Book` | 6,539 |
| CardDAV | `Contacts` | 2,818 |
| **Exchange** | `Contacts` | **1** ✅ consumed normally |

**Total: 53,686 unconsumed rows.** 7 CardDAV accounts × 109 clients is the fan-out multiplier.

## What the fetch failure is NOT (please skip these paths)

Disassembly of `Contacts` 3837.100.1 shows exactly five error branches around the group fetch. **None of them fires** — each logs **0** occurrences across 6 h:

| Function | Message (`__TEXT,__oslogstring`) | Occurrences |
|---|---|---|
| `-[_CNCDChangeHistoryResultIncrementalSyncQuery groupChangeForHistoryChange:].cold.1` | `Group history change missing required info: .uniqueId is nil: %{public}@` | 0 |
| `-[… groupDictionaryForObjectID:].cold.1` | `Found more than one group for objectID %{public}@. That's unexpected.` | 0 |
| `-[… groupDictionaryForObjectID:].cold.2` | `Did not find the group for objectID %{public}@. That's unusual, but not beyond the realm of possibility.` | 0 |
| `-[… groupDictionaryForObjectID:].cold.3` | `Exception fetching group for current change: %{public}@` | 0 |
| `-[… groupDictionaryForObjectID:].cold.4` | `Error fetching group for current change: %{public}@` | 0 |

So the failure is **not** the ordinary "group not found" path, **not** a nil `uniqueId`, **not** a thrown exception, and **not** a Core Data error. Also ruled out by direct inspection of the store:

- **Not a dangling reference** — the group record exists (`Z_PK=6`).
- **Not a broken container link** — container exists (`Z_PK=1`) and `ZCONTAINER=1` points at it correctly.
- **Not an identifier mismatch** — change rows carry no identifier at all (`ZCHANGETYPE=1`, `ZENTITYPK=6`, tombstones `NULL`, `ZCOLUMNS=X'00028000'` — the same two columns every pass). The identifier in the log message is *derived by the failing fetch*.

**The one question we could not answer: why the fetch fails.** The emitting code is in Contacts.framework (the `(Contacts)` tag in `log --style compact` is the sender library), and the format string — `Could not fetch group for change type %@ with identifier %@, making it a delete change type.` (note `%@`, not `%d`; a sibling `Could not fetch contact for change type %@ …` exists) — lives at `0x19c69a4c3` in `__TEXT,__cstring`, *not* `__oslogstring`. It is therefore an NSString literal handed to a logging wrapper, referenced via a `__cfstring` object whose data pointer is a chained fixup; there is consequently no `adrp`+`add #0x4c3` xref anywhere in the binary and static analysis could not recover the call site. `lldb` cannot attach (`attach failed (Not allowed to attach to process.)` — SIP-protected platform binary). **This should be immediate for an engineer with symbols.**

# Steps to Reproduce
This is environmental rather than a scripted repro — it reproduces continuously on this machine and requires a CardDAV account whose collection has been materialized as an `ABCDGroup`.

1. On macOS 27.0 26A5378n, have one or more iCloud/CardDAV Contacts accounts configured (7 here; all affected).
2. Leave the machine running normally. No user interaction with Contacts is needed — nothing was opened.
3. Observe cumulative CPU: `ps -o time= -p $(pgrep -x contactsd)` climbs ~13% of wall clock. Instantaneous `%CPU` reads 0.0 between bursts, so sample cumulative TIME, not `top`.
4. `/usr/bin/log show --last 1h --predicate 'process == "contactsd"' | wc -l` → hundreds of thousands of lines.
5. `/usr/bin/log show --last 1h --predicate 'eventMessage CONTAINS "Could not fetch group for change type"'` → the loop, ~1 per 2 s during storms, each followed by `Rebroadcasting external notification ABDatabaseChangedExternallyNotification from process (null)`.
6. `/usr/bin/log show --last 1h --predicate 'process == "launchd" AND eventMessage CONTAINS "AddressBookManager"'` → repeated `Successfully spawned … because ipc (mach)`.
7. Confirm the backlog directly:
   ```
   sqlite3 ~/Library/Application\ Support/AddressBook/Sources/<uuid>/AddressBook-v22.abcddb \
     "select count(*) from ACHANGE where ZENTITY=19;"          -- 17918
   sqlite3 … "select Z_PK, Z_OPT, ZNAME, ZEXTERNALCOLLECTIONPATH from ZABCDRECORD where Z_ENT=19;"
                                                                -- Z_OPT == the count above
   ```

Note: `log` is a zsh builtin — use `/usr/bin/log` explicitly, or the commands above silently return nothing.

# Expected vs Actual
- **Expected:** a change-history row whose target cannot be resolved is either consumed once (downgraded to a delete and **retired**) or quarantined, so the anchor advances. A CardDAV collection should be represented by its `CNCDContainer`, not materialized as an `ABCDGroup` with the collection path on it. contactsd should not drive `com.apple.AddressBook.abd` on itself in a cycle. Client authorization should be cached like account data already is.
- **Actual:** the row is never retired — the fetch fails every pass, the record is rewritten (Z_OPT++), a new row is appended, and the notification is rebroadcast to 109 clients, each costing a fresh TCC IPC. 53,686 rows have accumulated; the store's entire transaction history (5 → 17943) is this one group. Self-sustaining, with no external trigger and no user-side mitigation.

# Configuration
- MacBook Pro Mac15,11, M3 Max, 36 GB
- macOS 27.0 beta3 revision 26A5378n
- contactsd 3837.100.1; Contacts.framework 3837.100.1
- 12 Contacts sources: 7 CardDAV (all affected), 1 Exchange (unaffected), 4 with no group record (unaffected)
- Loaded Address Book plug-ins: CardDAVPlugin 1119.100.1, Exchange / LocalSource / DirectoryServices 2759.100.1

# Suggested attachments
- sysdiagnose captured during a storm (unredacted)
- `log collect --last 5m` archive taken while `AddressBookManager` is alive — contains the debug-level tccd AttributionChain naming contactsd as requestor (this is **not** obtainable from `log show` after the fact; it is debug-level and not persisted)
- Copy of `Sources/<uuid>/AddressBook-v22.abcddb` for the worst source (17,918 rows against one group; Z_OPT == count)
- `Sources/<uuid>/migration.log` showing `Local Groups: 0 / Server Groups: 0` against the `carddavhome/card/` collection
- Saved `log show` output for `Could not fetch group for change type` + `Rebroadcasting external notification`, showing the ~2 s cycle
- Cumulative-CPU sampling (`ps -o time=`) across a burst — `top` reads 0.0% between bursts and understates it

# Unrelated bug noticed alongside (file separately, do not conflate)
`imagent` (IMCore) is in an **unbounded, no-backoff retry loop** against `com.apple.AddressBook.ContactsAccountsService`, blocked by its own sandbox: `Connection init failed at lookup with error 159 - Sandbox restriction` → `Migration service failed database preparation` → immediate retry, **multiple times per millisecond** (timestamps `.307/.307/.308/.308`). **44,537 errors in 4 h**, but only **14 s of CPU** — log noise, not a CPU contributor, and not the cause of the contactsd loop.
