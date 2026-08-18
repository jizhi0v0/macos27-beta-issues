# imagent is entitled to `ContactsAccountsService` but its sandbox blocks the lookup — then retries every 1–2 ms with no backoff (66,626 errors / 7 h)
# imagent 有 `ContactsAccountsService` 授权却被自己的沙盒挡住 lookup —— 随后以 1–2 毫秒间隔无退避重试(7 小时 66,626 条)

> 🔗 **Track / 关注此问题:** [#19 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/19)

| | |
|---|---|
| **Status** | 🔴 Open · confirmed on `26A5378n` (live — still looping while this was written) |
| **macOS** | 27.0 beta3 revision **`26A5378n`** (measured 2026-07-16; not tested on earlier builds) |
| **Component** | Apple **imagent** `10.0` (1000) (`/System/Library/PrivateFrameworks/IMCore.framework/imagent.app`) ↔ **ContactsAccountsService** / Contacts `PersistentStoreBuilder` |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max, 36 GB |
| **Report** | Feedback candidate `FB________` |

## Summary / 摘要

`imagent` is **explicitly entitled** to use `com.apple.AddressBook.ContactsAccountsService`, but its **sandbox profile does not permit the mach lookup** for that service. The lookup is denied (`error 159 - Sandbox restriction`), database preparation fails — and the failure path **retries immediately, at 1–2 ms intervals, with no backoff and no give-up**, forever.

**66,626 errors in 7 h.** But only **19.4 s of CPU over 6 h 46 m of uptime (≈0.08%)** — this is a **log-volume / logd bug, not a CPU bug**. It is filed for the unbounded retry and the entitlement mismatch, not for performance.

imagent 被明确授权使用 `ContactsAccountsService`,但它自己的沙盒不允许 lookup 该服务 → 被拒(error 159)→ 数据库准备失败 → **立即重试,间隔 1–2 毫秒,无退避、不放弃**。7 小时 66,626 条,但 6h46m 只烧 19.4 秒 CPU(≈0.08%)—— 这是**日志量问题,不是 CPU 问题**。

## The mismatch / 授权与沙盒对不上

`codesign -d --entitlements -` on the imagent binary:

```
[Key] com.apple.AddressBook.ContactsAccountsService
[Value]
    [Bool] true                                   ← the service's own access entitlement: allowed to USE it

[Key] com.apple.security.exception.mach-lookup.global-name
[Value]
    [Array]
        [String] com.apple.lockdownmoded
        [String] com.apple.feedbackd.centralized-feedback
        [String] com.apple.asktod                 ← ContactsAccountsService is NOT in this list
```

imagent also carries `com.apple.Contacts.database-allow`, `com.apple.private.contacts`, and `kTCCServiceAddressBook` under its TCC allow list — i.e. **every authorization layer says yes except the sandbox lookup**.

### Confirmed against the sandbox profile on disk / 沙盒配置文件实证

`/System/Library/Sandbox/Profiles/com.apple.imagent.sb` (403 lines) has an explicit `(allow mach-lookup …)` block whose contents settle it:

```
173: (allow mach-lookup
174:     (global-name "com.apple.lockdownmoded")
175:     (global-name "com.apple.corerecents.recentsd")
176:     (global-name "com.apple.accountsd.accountmanager")
177:     (global-name "com.apple.AddressBook.abd")            ← LEGACY AddressBook service: allowed
     …
232:     (global-name "com.apple.private.contacts")           ← allowed
233:     (global-name "com.apple.Contacts.database-allow")    ← allowed
     …
     com.apple.AddressBook.ContactsAccountsService           ← ABSENT from the entire file
```

`grep -n "ContactsAccountsService" /System/Library/Sandbox/Profiles/com.apple.imagent.sb` → **no matches**.

The profile grants imagent essentially everything Contacts-related — AddressBook preference domains (lines 39–40, 81, incl. `com.apple.AddressBook.CardDAVPlugin`), `~/Library/Application Support/AddressBook` (line 145), `/T/.AddressBookLocks` (line 140), and the **legacy** `com.apple.AddressBook.abd` lookup (line 177) — but omits the **modern** `ContactsAccountsService` that Contacts' `PersistentStoreBuilder` actually calls. Reads like the profile was never updated when store preparation moved to `ContactsAccountsService`.

> This was originally recorded here as a *strong inference*; the on-disk profile upgrades it to **demonstrable**. Remaining caveat: `sandboxd` logged **0** lines mentioning imagent in 7 h, so the denial surfaces only client-side as `error 159` — if an entitled global-name being denied is supposed to be reported by sandboxd, that silence may be a second, smaller issue.

## The error chain / 报错链

Each retry emits **three** error lines (all `E` level, all persisted to disk):

```
imagent[783:6497] [com.apple.contacts:migration] [Migration] Migration service failed database preparation:
    Error Domain=NSCocoaErrorDomain Code=4099 "The connection to service named
    com.apple.AddressBook.ContactsAccountsService was invalidated: Connection init failed at lookup
    with error 159 - Sandbox restriction."
imagent[783:6497] [com.apple.contacts:PersistentStoreBuilder] Database preparation failed: <same error>
imagent[783:6497] [com.apple.contacts:PersistentStoreBuilder] Skipping XPC store fallback: preparation
    did not produce a URL. Preserving preparation error: <same error>
```

Note the third line: the **XPC store fallback is skipped** because preparation never produced a URL — so the designed fallback path cannot rescue this, and the code goes straight back to retrying.

## Evidence / 证据

Measured over one 7 h window (single boot, `26A5378n`):

| Metric | Value |
|---|---|
| Total `Sandbox restriction` errors | **66,626** in 7 h |
| Peak minute | **1,982** lines (10:25) |
| Tightest second | **265** lines (14:54:36) — ≈88 retries/sec (3 lines each) |
| Retry interval inside a burst | **1–2 ms** — `.033 .035 .037 .038 .039 .041 .042 .044 .046 .051 .052 .063` |
| imagent CPU | **19.4 s over 6 h 46 m** (≈0.08%) |
| Still firing | **794** errors in the last 10 min at time of writing |

**No backoff of any kind** — the interval does not grow across a burst, and the loop has run continuously since boot.

## Trigger: shared with [#18](apple-contactsd-carddav-group-changehistory-loop.md) / 触发源与 #18 相同

imagent's bursts are **not independent** — they are driven by the same `AddressBookManager` spawns behind the [contactsd change-history loop (#18)](apple-contactsd-carddav-group-changehistory-loop.md). All **5** of imagent's top burst minutes land on `AddressBookManager` spawn minutes:

```
imagent top burst minutes : 10:25  11:54  12:26  14:26  15:50
AddressBookManager spawns : 10:25  11:54  12:26  14:26  15:50   ← 5/5 overlap
```

Spawns occurred in 75 of ~420 uptime minutes (~18%), so a 5/5 coincidence would be ≈0.02% by chance. Reading: `AddressBookManager` touches the Contacts stores → imagent tries to prepare its Contacts store → sandbox blocks the lookup → tight retry loop.

**imagent is a *consequence* of #18's trigger, not its cause** — and conversely, #18's CPU cost is **not** imagent's doing (19 s of CPU can't produce 143% bursts). The two are separate defects that share a trigger, and should be filed separately.

imagent 的爆发不是独立的,而是被 #18 背后同一批 `AddressBookManager` 拉起驱动。5 个爆发分钟 5/5 全部命中拉起分钟(偶然概率约 0.02%)。**imagent 是 #18 触发源的后果,不是其原因**;反过来 #18 的 CPU 也不是 imagent 造成的(19 秒 CPU 变不出 143% 爆发)。两者是共享触发源的独立缺陷,应分开提交。

## The three questions, answered from the binary / 三问的二进制答案 (beta5 `26A5406e`, 2026-08-13)

Static analysis targets: `/System/Library/Sandbox/Profiles/com.apple.imagent.sb` (404 lines on beta5, was 403 on beta3), imagent's entitlements, and `ContactsPersistence.framework` **3844.100.1** (linked via `Contacts.framework` by imagent) + ContactsFoundation's `CNRetry`. Disassembly via lldb static + a live probe process; all claims below are read from these, not inferred from the log shape.

### Q1 — What the sandbox profile actually denies / 沙盒到底禁了什么

- **Default-deny by omission, not an explicit rule.** Line 11 is `(deny default)`. The *only* explicit `deny mach-lookup` in the file is the WebKit prefix rule (lines 286–288, `(with send-signal SIGKILL)`). There is no deny rule naming the Contacts service — it is blocked simply because the `(allow mach-lookup …)` block (lines 173–283) omits it, while explicitly allowing the **legacy** `com.apple.AddressBook.abd` (line 177).
- **26 other system sandbox profiles** list `com.apple.AddressBook.ContactsAccountsService` explicitly (`contactsd.sb`, `suggestd.sb`, `sharingd.sb`, `gamed.sb`, `assistantd.sb`, `siriactionsd.sb`, `studentd.sb`, `contacts.sb`, `com.apple.iMessage.addressbook.sb`, …). imagent's profile is the outlier.
- The profile contains **no `(require-entitlement …)` rules**, so the `ContactsAccountsService = true` entitlement cannot rescue a mach lookup: for a platform binary the *profile* is the client-side gate, while the *entitlement* is what the **server** (contactsd) checks. The `com.apple.security.exception.mach-lookup.global-name` entitlement array in the binary does not list the service either, so the legacy exception mechanism can't rescue it.

### Q2 — Is there backoff on the retry path? / 重试路径有没有退避

**The retry wrapper around the failing XPC lookup has a designed backoff — but it never engages for this error:**

- `-[CNCDRemotePersistentStoreEndpointFactory newEndpointWithError:]` (ContactsPersistence) wraps `_fetchEndpoint` in ContactsFoundation's `CNRetry`, with the factory itself as the delegate:
  - `maximumNumberOfAttemptsForRetry:` → returns literal **2**
  - `retry:delayAfterError:onAttempt:` → returns literal **2.0 s** (`fmov d0, #2.0; ret`)
  - `retry:shouldContinueAfterError:onAttempt:` → returns YES **only** for `CNErrorDomain` code **1012**. The sandbox error is `NSCocoaErrorDomain 4099` (mach error 159), so the predicate is **false** and this wrapper makes exactly **one** attempt.
- The `CNRetry` engine (`-[CNRetry performAndWait:]`, ContactsFoundation) itself: attempt loop with a cap; the delay is delegate-supplied; a delegate delay of **0.0 skips the sleep entirely** (`fcmp d8, #0.0` → `b.eq` past the wait) → immediate retry. The only other backoff in the Contacts stack is `CNProcessSharedLock lockRetryOnEDEADLK` (`kRetryEDEADLKBackoff` / `kRetryEDEADMax`) — EDEADLK-specific, unrelated.
- Every function on the per-attempt path was checked for backward branches and is **straight-line**: `-[CNCDDatabasePreparationTask run:]`, the out-of-process task block, `__46-[CNCDDatabaseCachingPreparer executeRequest:]_block_invoke`, `_fetchEndpoint`. The 1–2 ms re-invocation loop therefore lives in a **caller layer** (CoreData `NSXPCStoreConnection createConnectionWithOptions:` or the Contacts store-stack rebuild) — **not yet pinned to a specific frame** (stated gap; needs a root stack sample during a burst, which this machine cannot capture without disabling SIP).
- **Live re-verification on beta5** (this machine, 2026-08-13 23:31): burst of **44 attempts** in two sub-bursts ~170 ms apart, **1–2 ms per attempt**, 3 lines each, all on one thread (`8cafac`) — no backoff *within* a sub-burst. Bursts **6/6-correlate** with `AddressBookManager` spawns in a 3 h window ("Successfully spawned AddressBookManager[…] because ipc (mach)", ~6 min cadence, and its launchd plist has **no** `StartInterval`/`KeepAlive` — something actively requests the `com.apple.AddressBook.abd` mach service every ~6 min).

### Q3 — Are entitlement and profile really contradictory? / 授权与沙盒真的矛盾吗

**Yes.** Two independent authorization layers disagree: the **entitlement** — the server-side gate by which contactsd would accept imagent as a client — grants the right; the **profile** — the client-side gate on whether imagent may issue the lookup at all — denies it. The entitlement is not "unused": it is checked by the *service*, which imagent can never reach. One-line fix on either side (add the global-name to the profile, matching all 26 siblings) closes the contradiction.

## Expected vs Actual / 预期与实际

- **Expected:** a process explicitly entitled to `com.apple.AddressBook.ContactsAccountsService` can look it up. Failing that, a sandbox denial is a **permanent, non-retryable** condition — it should fail once, log once, and stop (or back off exponentially and give up), not retry every 1–2 ms indefinitely at `E` level.
- **Actual:** the lookup is denied every time; the code retries at 1–2 ms with no backoff and no cap, emitting 3 persisted error lines per attempt — 66,626 lines in 7 h from one process.

## Workaround / 临时规避

**None.** imagent is a SIP-protected system daemon; `killall imagent` respawns it and the loop resumes. The log volume can be muted locally (`sudo log config --subsystem com.apple.contacts --mode "level:default"` — modifies system logging config), but that hides the symptom rather than fixing it and suppresses unrelated diagnostics.

## Notes / 备注

- **This is log noise, not a CPU problem** — deliberately stated up front because the shape (66k errors, tight loop) invites the opposite conclusion. Cumulative CPU is **19.4 s over 6 h 46 m**. Anyone chasing contactsd CPU on macOS 27 will trip over these lines first; see [#18](apple-contactsd-carddav-group-changehistory-loop.md) for the actual CPU story.
- Same defect *shape* as [#15](apple-appstoreagent-bgtask-retry-loop.md) (appstoreagent/dasd: rejected background task, no backoff, floods log) — a rejected/denied operation treated as retryable. Different component and different denial, so tracked separately.
- The failing PID changed across the session (815 early, 783 later) — imagent respawns, and the fresh instance re-enters the same loop.
- `log` is a **zsh builtin**: use `/usr/bin/log` for every command here, or they silently return nothing.
