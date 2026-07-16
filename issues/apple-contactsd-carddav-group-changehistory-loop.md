# contactsd self-sustaining change-history loop on CardDAV collection-groups (~143% CPU bursts, 840k log lines / 4h)
# contactsd 在 CardDAV 集合伪 group 上的自激变更历史循环(爆发 ~143% CPU,4 小时 84 万行日志)

> 🔗 **Track / 关注此问题:** [#18 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/18)

| | |
|---|---|
| **Status** | 🔴 Open · confirmed on `26A5378n` (live, still firing during investigation) |
| **macOS** | 27.0 beta3 revision **`26A5378n`** (first measured 2026-07-16; not yet tested on earlier builds) |
| **Component** | Apple **contactsd** `3837.100.1` (`/System/Library/Frameworks/Contacts.framework/Support/contactsd`) + **AddressBookManager** (`com.apple.AddressBook.abd`) + Contacts change-history (`_CNCDChangeHistoryResultIncrementalSyncQuery`) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max, 36 GB |
| **Report** | Feedback candidate `FB________` |

> **Privacy note:** the iCloud DSID in collection paths and the account email are redacted below as `<DSID>` / `<user>`. Source/group UUIDs are per-machine random identifiers, kept for evidence value.

## Symptom / 症状

`contactsd` is **not** constantly pegged — it is **episodic**, which is why Activity Monitor reads it as "sometimes high": quiet stretches (4 log lines per 10 min) alternate with storms (**207,518 lines in the 12:20–12:30 bucket**).

Over one 4 h 07 m session (single boot):

| Metric | Value |
|---|---|
| Cumulative CPU TIME | **32:51** over 4 h 07 m uptime (**≈13% average**) |
| Peak measured burst | **~143%** (28.6 s CPU in 20 s wall, 14:00:45→14:01:05) |
| Log lines emitted | **839,240** in 4 h (796,976 from the single long-lived PID 1984) |
| `contactsd.persistence` connections | **85,516** (~6/sec sustained, 109 distinct client processes) |
| TCC authorization requests | **89,107** — ratio **1.04 per persistence request** |
| SQLite store re-adds | 836 |
| `AddressBookManager` spawns | **55** in 4 h (each lives ~250 ms) |

contactsd 不是持续高占用,而是**间歇性风暴**——安静时 10 分钟 4 行日志,爆发时 10 分钟 20 万行。4 小时累计烧 32 分 51 秒 CPU(均值约 13%),峰值实测 143%。

## Root cause / 根因

A **self-sustaining loop with no third-party app involved**. `contactsd` is both the victim and the initiator:

```
contactsd ──mach lookup com.apple.AddressBook.abd──▶ launchd spawns AddressBookManager
    ▲                                                          │
    │                              mounts all 12 source stores; 448 connections back
    │                              to com.apple.contactsd.persistence per launch
    │                                                          │
    │                                                          ▼
    │                              touches the malformed CardDAV collection-group
    │                                                          │
    │        FetchingChangeHistory → "Could not fetch group for change type 1
    │        with identifier <private>, making it a delete change type."
    │        → rewrites the group record (Z_OPT++) → emits a NEW change row
    │        → Rebroadcasting ABDatabaseChangedExternallyNotification
    │        → 109 client daemons re-query; each re-query = one fresh TCC IPC
    └──────────────────────────────────────────────────────────┘
                          cycle repeats every ~2 s
```

The change row is **never consumable** — the group fetch fails every pass, so the row is re-read forever, and each pass writes a new one.

### The trigger is contactsd itself — proven via TCC AttributionChain

`launchd` only logs `Successfully spawned AddressBookManager[…] because ipc (mach)` and never names the requestor. The debug-level XPC lookup log is **not persisted**, and `log stream` **drops messages** on this loaded machine. Captured instead by polling for the 250 ms process and snapshotting the in-memory buffer with `log collect --last 45s` (works without sudo, includes debug):

```
tccd: AttributionChain: accessing={identifier=com.apple.AddressBook.abd, pid=92637,
        binary_path=…/AddressBookManager.app/Contents/MacOS/AddressBookManager},
      requesting={identifier=com.apple.contactsd, pid=1984,
        binary_path=/System/Library/Frameworks/Contacts.framework/Support/contactsd}
```

Requestor tally in that capture: **`com.apple.contactsd` ×59**, `com.apple.sandboxd` ×3, `com.apple.AddressBook.abd` ×2 (itself). **No third-party app appears.**

This also explains every red herring: the only app on the machine holding Contacts TCC access (Spark.app, the only app linking legacy `AddressBook.framework`) had **zero log activity for 5 h** — it never ran. All AddressBook TCC decisions in the window are Apple daemons with `AuthRight: Allowed, Reason: Entitled`.

**Consequence: there is no app the user can quit to stop this.**

## Scope: CardDAV-only / 精确命中 CardDAV

Every CardDAV source that has a collection-level group record has thousands of unconsumed group changes. **Exchange is clean** (1 group, 1 change — consumed normally). Sources with no group record have 0 changes.

| Source | Account type | Group name | Group `ZUNIQUEID` | Unconsumed group changes |
|---|---|---|---|---|
| `40AC609A-77C9-4543-93C2-8A788B9679ED` | CardDAV | `card` | `973F0C78-EEF8-4D00-94D8-6CFA2C9F3DD4:ABGroup` | **17,918** |
| `14028166-A347-4393-A26E-34060814D045` | CardDAV | `Contacts` | `070D4544-1980-4E09-9A6C-F9F8AEFEAEE5:ABGroup` | 6,713 |
| `387349B6-8964-466B-936B-7C2B6987F6FE` | CardDAV | `Address Book` | `4D7DB4FC-89FC-4789-854F-6A0DFBCC151E:ABGroup` | 6,589 |
| `A78AD44D-26D2-4CE3-A945-41D4E0E7A12B` | CardDAV | `Address Book` | `B383DBBE-921C-4836-B06E-177F683D64C6:ABGroup` | 6,564 |
| `93C7BA0C-984A-464E-889A-6E750BF27199` | CardDAV | `Address Book` | `A8EC569B-B876-4875-A8EF-BE2D0DD0FB50:ABGroup` | 6,544 |
| `50E9CB89-9D54-4BF5-9C72-3620AB23A2F1` | CardDAV | `Address Book` | `BCD98424-9689-4F9B-9276-27705A746169:ABGroup` | 6,539 |
| `C22F8DA4-D902-4EDF-BB4B-CA69994F566B` | CardDAV | `Contacts` | `07C5308D-AF0A-4224-9014-AFFCD9F06C70:ABGroup` | 2,818 |
| `74CA3725-47AC-4550-9D84-B78F0DA5C174` | **Exchange** | `Contacts` | — | **1** ✅ normal |

**Total: 53,686 unconsumed group change rows.** 7 CardDAV accounts × 109 clients is the fan-out multiplier.

## Evidence: the group is not a real group / 关键证据

The "groups" are the **CardDAV collections themselves**, materialized as `ABCDGroup` records. For source `40AC609A`, `migration.log` shows the sync URL:

```
### DOWNLOAD FROM https://<user>@p56-contacts.icloud.com/<DSID>/carddavhome/card/ ###
### Local Groups: 0 ###
### Server Groups: 0 ###
```

The path segment `card` **is** the group's name. The account has **no groups at all**, yet carries one group record plus 17,918 changes against it.

The data model is **inverted** — the collection metadata lives on the group, not the container:

| Field | Container (`Z_PK=1`, `CNCDContainer`) | Group (`Z_PK=6`, `ABCDGroup`) |
|---|---|---|
| `ZNAME` | *(blank)* | `card` |
| `ZEXTERNALCOLLECTIONPATH` | *(blank)* | `/<DSID>/carddavhome/card/` |
| `ZEXTERNALGROUPBEHAVIOR` | — | `1` |
| `ZTYPE` | `0` | *(null)* |

Other hard evidence:

- **`Z_OPT = 17918` on the group record — exactly equal to the change count.** Core Data's optimistic-locking counter proves each loop pass *rewrites* the record.
- **`ZTRANSACTIONID` spans 5 → 17943**: from transaction #5 onward, essentially this store's entire lifetime is this one group.
- The change rows carry **no identifier** — `ZCHANGETYPE=1`, `ZENTITYPK=6`, tombstones `NULL`, `ZCOLUMNS=X'00028000'` (same two columns every pass). The identifier in the log message is *derived by the failing fetch*.
- The loop was still live during investigation: `ZTRANSACTIONID` advanced 17929 → 17943 within the session, and the last firing (14:00:53) coincides exactly with the measured 143% burst window (14:00:45–14:01:05).

## Ruled out / 已排除

- **Dangling reference** — the group record exists (`referenced_pk_exists=1`, `Z_PK=6`).
- **Broken container link** — container exists (`Z_PK=1`) and `ZCONTAINER=1` points at it correctly.
- **Identifier mismatch in the change row** — change rows reference by `ZENTITYPK`, carry no identifier at all.
- **Third-party app trigger** — see AttributionChain above.
- **The five ordinary failure paths of `_CNCDChangeHistoryResultIncrementalSyncQuery`.** Disassembly of `Contacts` (`3837.100.1`) yields exactly five error branches around the group fetch:

  | Function | Message (`__TEXT,__oslogstring`) | Occurrences in 6 h of logs |
  |---|---|---|
  | `-[… groupChangeForHistoryChange:].cold.1` | `Group history change missing required info: .uniqueId is nil: %{public}@` | **0** |
  | `-[… groupDictionaryForObjectID:].cold.1` | `Found more than one group for objectID %{public}@. That's unexpected.` | **0** |
  | `-[… groupDictionaryForObjectID:].cold.2` | `Did not find the group for objectID %{public}@. That's unusual, but not beyond the realm of possibility.` | **0** |
  | `-[… groupDictionaryForObjectID:].cold.3` | `Exception fetching group for current change: %{public}@` | **0** |
  | `-[… groupDictionaryForObjectID:].cold.4` | `Error fetching group for current change: %{public}@` | **0** |

  **None of them fire.** This is a useful negative: the failure is *not* the ordinary "group not found" path, and not a thrown exception or Core Data error either. Whatever emits the observed message is a different code path.

## Open question / 未解 — why the fetch fails

**Not determined.** The observed message is:

```
contactsd[1984:181e0b] (Contacts) Could not fetch group for change type 1
  with identifier <private>, making it a delete change type.
```

Facts established about it:

- The `(Contacts)` tag in `log --style compact` is the **sender library** → the code is in **Contacts.framework**, logged with no subsystem/category.
- The exact format string is `Could not fetch group for change type %@ with identifier %@, making it a delete change type.` — **`%@`, not `%d`**, so "change type 1" is an `NSNumber`. A sibling `Could not fetch contact for change type %@ …` exists, so this is a generic "fetch failed → downgrade to delete" pattern.
- It lives at **`0x19c69a4c3`** in **`__TEXT,__cstring`** — *not* `__oslogstring`. So it is an NSString literal / C format handed to a logging wrapper (which is why `%@` args render as `<private>`: os_log redacts non-scalars by default).
- **Consequently there is no `adrp`+`add #0x4c3` xref anywhere in `Contacts`** — the code references the `__cfstring` object, whose data pointer is a chained fixup. Decoding those to recover the xref is the remaining step.

An Apple engineer with symbols resolves this in seconds; it defeated static analysis here. **`lldb` is not an option**: `contactsd` is a SIP-protected platform binary — `attach failed (Not allowed to attach to process.)` — and lifting it requires `csrutil enable --without debug` from Recovery.

## Workaround / 临时规避

**None known.** No app can be quit (the loop is entirely Apple-internal). Disabling Contacts for the CardDAV accounts would presumably rebuild the source stores and clear the backlog, but that touches real contact data, all 7 CardDAV accounts are affected, and — with the fetch failure not understood — there is no reason to believe a rebuilt store wouldn't re-materialize the same collection-group. Not recommended until the root cause is known.

## Notes / 备注

- **Separate bug found alongside, not the cause → now tracked as [#19](apple-imagent-contactsaccounts-sandbox-retry-loop.md):** `imagent` (`IMCore`) is in an **unbounded no-backoff retry loop** (1–2 ms interval) against `com.apple.AddressBook.ContactsAccountsService` — it *is* entitled to the service, but its sandbox profile blocks the lookup: `Connection init failed at lookup with error 159 - Sandbox restriction` → `Migration service failed database preparation` → immediate retry. **66,626 errors in 7 h** — but only **19 s of CPU**. It is log noise, **not** a CPU contributor to this issue. **The two share this issue's trigger**: all 5 of imagent's top burst minutes land on `AddressBookManager` spawn minutes (5/5; ≈0.02% by chance), i.e. imagent is another *consequence* of the same spawns — but a distinct defect, filed separately. Anyone chasing contactsd CPU will hit imagent's 66k lines first; they are a red herring for *this* bug.
- The machine was under heavy unrelated load during measurement (Xcode `swift-frontend`, WindowServer ~78%, load average 43). contactsd's ~13% average is *additive* to that and independent of it — cumulative CPU TIME can't be gamed.
- **Methodology traps that produced false negatives here** (all fail *silently*, mimicking "nothing found"): `log` is a **zsh builtin** — bare `log show` errors or returns nothing through a pipe; use `/usr/bin/log` (exporting `PATH` does **not** help — builtins win). macOS has **no `timeout(1)`** — `timeout N log stream …` yields 0 lines. `otool -L` / `lsof` / `vmmap` **cannot** identify which process uses a system framework: everything is in the dyld shared cache, so `lsof` sees nothing and `vmmap` matches ~every process (false positives incl. Finder, Chrome). `grep -rl` silently missed a string in a 6.3 GB extract that `strings` found.
- Shared-cache disassembly recipe used: Xcode's `dsc_extractor.bundle` via a 12-line `dlopen` shim extracts all 4,080 dylibs with **cache VM addresses preserved** (verified: `Contacts` `__TEXT` at `0x19c473000`); `ipsw dyld str <DSC> "<needle>"` (fast byte search) confirms the owning image and address without extracting.
