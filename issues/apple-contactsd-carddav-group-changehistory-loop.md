# contactsd self-sustaining change-history loop on CardDAV collection-groups (~143% CPU bursts, 840k log lines / 4h)
# contactsd 在 CardDAV 集合伪 group 上的自激变更历史循环(爆发 ~143% CPU,4 小时 84 万行日志)

> 🔗 **Track / 关注此问题:** [#18 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/18)

| | |
|---|---|
| **Status** | 🔴 **still reproducing on beta6 `26A5416b`** (2026-08-19) — the backlog **crossed the upgrade intact and kept growing**: 90,209 → **91,030** rows, all 12 sources carried over, every non-zero one up, **none reset**, which rules out the "the upgrade rebuilt the stores and cleared it" false positive. Worst source 27,202 → **27,388**. Log volume unchanged (~214k lines/h). See [the beta6 section](#re-verification-2026-08-19--beta6-26a5416b--the-backlog-crossed-the-upgrade). Prior: 🔴 Open · **filed with Apple as [FB24264605](https://feedbackassistant.apple.com/feedback/24264605)** (2026-08-11) · confirmed on `26A5378n`, `26A5388g` and **`26A5406e` (beta5)** — and **still accumulating**: 53,686 → **76,366** unconsumed rows between beta3 and beta5 (+42%). See [beta5 re-verification](#re-verification-2026-08-11--beta5-26a5406e--still-growing-and-two-findings-the-original-write-up-missed) |
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

## Re-verification 2026-08-11 — beta5 `26A5406e` — still growing, and two findings the original write-up missed

Measured before filing [FB24264605](https://feedbackassistant.apple.com/feedback/24264605), 23 minutes after a clean boot:

| | beta3 `26A5378n` (2026-07-16) | beta5 `26A5406e` (2026-08-11) |
|---|---|---|
| unconsumed group change rows, all sources | 53,686 | **76,366** (+42%) |
| worst single source | 17,918 | **23,849** |
| contactsd CPU (cumulative average) | ≈13% | **20.2%** (273 s / 1349 s) |
| contactsd log volume | ~210k lines/h | **~218k lines/h** (109,025 per 30 min) |

**The backlog grows.** That is stronger evidence than any rate snapshot: the loop has never once drained, across three OS builds and a month.

### Finding 1 — it spans four CardDAV providers, not just iCloud

The original write-up said "7 CardDAV accounts" without identifying them. They are not one provider:

| provider | accounts | stuck rows |
|---|---|---|
| iCloud (`p56-contacts.icloud.com`) | 1 | 23,849 |
| Google (`/carddav/v1/principals/…`) | 4 | ~9,300 each |
| Yahoo (`/dav/…@myyahoo.com/Contacts/`) | 1 | 9,521 |
| one other CardDAV host (`/carddav/<hash>/contacts/`) | 1 | 5,663 |
| **Exchange** | 1 | **1 — consumed normally** |

Four unrelated server implementations produce the identical malformed state, and the only non-CardDAV account is clean. **That rules out a server-side quirk and points at Apple's CardDAV plugin.**

### Finding 2 — 35 processes emit the failing fetch, not contactsd

`Could not fetch group for change type` comes from **Contacts.framework**, so every client that consumes change history hits the same unconsumable row. In one 30-minute window: **7,569 occurrences across 35 distinct processes** —

```
corespotlightd 750 · AddressBookSourceSync 528 · studentd 470 · photoanalysisd 434
Mail 424 · postersyncd 388 · familycircled 381 · searchpartyuseragent 374
suggestd 373 · sharingd 369 · …            contactsd itself: 45
```

This corroborates the fan-out mechanism already described here (the rebroadcast notification re-querying 109 clients), but corrects the attribution: the message is **not** contactsd-specific.

**Method note, recorded because it nearly went into the Feedback wrong:** an unfiltered `log show --predicate 'eventMessage CONTAINS "Could not fetch group…"'` returned **11,277** for the window and was about to be reported as contactsd's rate. It was not — it was the sum across all 35 clients, and the true contactsd figure is ~45. Always pin `process ==` when attributing a framework-emitted message. A separate query was also polluted by the `log` binary's own entries matching the predicate text.

2026-08-11 提交 FB24264605 前于 beta5 复验:**积压仍在增长** —— 全部 source 的未消费变更行 53,686 → **76,366**(+42%),最严重的单个 source 17,918 → 23,849;contactsd CPU **20.2%**,日志 **~218k 行/小时**。**新发现一**:受影响的 7 个账户**横跨四家 CardDAV 服务商**(iCloud ×1、Google ×4、Yahoo ×1、其他 ×1),而唯一的 Exchange 账户完好 —— 四家互不相关的服务端产生同一种畸形状态,**排除服务端问题,指向 Apple 的 CardDAV plugin**。**新发现二**:`Could not fetch group for change type` 出自 **Contacts.framework**,30 分钟内由 **35 个不同进程**发出共 7,569 次(corespotlightd 750、AddressBookSourceSync 528、Mail 424…,contactsd 自己仅 45),原文将其归因于 contactsd 是不准确的。**方法论教训**:未按 `process ==` 过滤的查询给出 11,277,差点被当作 contactsd 的速率写进 Feedback —— 那是 35 个客户端的总和。

## Re-verification 2026-08-19 — beta6 `26A5416b` — the backlog crossed the upgrade

Taken at T+9m after the first boot on beta6, with the same query
(`select count(*) from ACHANGE where ZENTITY=19;` per `Sources/<uuid>/AddressBook-v22.abcddb`).

| | beta3 | beta5 08-11 | beta5 08-18 | **beta6 08-19** |
|---|---|---|---|---|
| unconsumed group-change rows | 53,686 | 76,366 | 90,209 | **91,030** |
| worst single source | 17,918 | 23,849 | 27,202 | **27,388** |

**All 12 sources carried over, every non-zero one increased, none reset.** That is the point of
taking the reading immediately after the upgrade: an OS upgrade that migrated or rebuilt the
Contacts stores would have zeroed the backlog and looked exactly like a fix. It did not.
contactsd's log volume is unchanged too — 27,809 lines in the 8-minute post-boot window ≈ 214k/h,
against beta5's ~218k/h.

Per-source detail: `baselines/beta6-26A5416b/contactsd-backlog.txt`.

2026-08-19 升级到 beta6 后第 9 分钟复验:积压**完好跨过升级并继续增长**(90,209 → 91,030),
12 个 source 全部沿用、非零的每一个都在涨、**没有任何一个被清零**。这正是要在升级后立刻取数的原因 ——
若升级重建了 Contacts store,计数会归零、看起来像修好了。日志量也没变(~214k 行/小时)。