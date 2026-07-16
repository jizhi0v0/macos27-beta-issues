VERIFICATION: CONFIRMED — 66,626 `error 159 - Sandbox restriction` lines from imagent in 7 h (peak 1,982/min; tightest second 265 lines ≈ 88 retries/s; retry interval 1–2 ms with no backoff), while imagent burns only 19.42 s of CPU over 6 h 53 m (≈0.08%). Captured 2026-07-16, beta3 revision 26A5378n, imagent 10.0 (1000). Episodic, not constant: most recent burst 16:42:21, 96 s after an AddressBookManager spawn at 16:40:45. **The sandbox profile is on disk and demonstrably lacks the global-name** — see below; this is not an inference.

# Title
imagent is entitled to `com.apple.AddressBook.ContactsAccountsService` but `com.apple.imagent.sb` omits it from `(allow mach-lookup)`, so every lookup is denied (`error 159`) — and the Contacts `PersistentStoreBuilder` failure path then retries every 1–2 ms with no backoff (66,626 error lines / 7 h)

# Apple area / component to select
Messages / IMCore (imagent). Sub-areas: App Sandbox (profile `com.apple.imagent.sb`) and Contacts (`PersistentStoreBuilder` / migration retry policy).

# Description
On macOS 27.0 (26A5378n), `imagent` (10.0, build 1000) cannot look up `com.apple.AddressBook.ContactsAccountsService`. Every attempt is denied by its own sandbox, Contacts database preparation fails, and the failure path **retries immediately — at 1–2 ms intervals, with no backoff and no cap** — emitting **three persisted `E`-level lines per attempt**, forever.

**66,626 error lines in 7 hours from a single process.**

This is a **log-volume defect, not a performance one**: imagent burns only **19.42 s of CPU over 6 h 53 m (≈0.08%)**. It is filed for (a) the entitlement/sandbox-profile contradiction and (b) the unbounded retry against a permanently-failing condition.

## 1. The contradiction: entitled to use it, not allowed to look it up

`codesign -d --entitlements -` on `/System/Library/PrivateFrameworks/IMCore.framework/imagent.app/Contents/MacOS/imagent`:

```
[Key] com.apple.AddressBook.ContactsAccountsService
[Value]
    [Bool] true                                   ← the service's own access entitlement: allowed to USE it
```

imagent additionally carries `com.apple.Contacts.database-allow`, `com.apple.private.contacts`, and `kTCCServiceAddressBook` in its TCC allow list. **Every authorization layer grants it Contacts access.**

But `/System/Library/Sandbox/Profiles/com.apple.imagent.sb` (403 lines, on disk) has an explicit `(allow mach-lookup …)` block at line 173 that **does not contain the service**:

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

The profile grants imagent essentially everything Contacts-related — the AddressBook preference domains (lines 39–40, 81, incl. `com.apple.AddressBook.CardDAVPlugin`), `~/Library/Application Support/AddressBook` (line 145), `/T/.AddressBookLocks` (line 140), and the **legacy** `com.apple.AddressBook.abd` lookup (line 177) — but omits the **modern** `ContactsAccountsService` that Contacts' `PersistentStoreBuilder` actually calls. This reads like the profile was never updated when the store-preparation path moved to `ContactsAccountsService`.

## 2. The retry loop

Each denied attempt emits three lines, all at `E` level (persisted by logd):

```
imagent[783:6497] [com.apple.contacts:migration] [Migration] Migration service failed database preparation:
    Error Domain=NSCocoaErrorDomain Code=4099 "The connection to service named
    com.apple.AddressBook.ContactsAccountsService was invalidated: Connection init failed at lookup
    with error 159 - Sandbox restriction."
imagent[783:6497] [com.apple.contacts:PersistentStoreBuilder] Database preparation failed: <same error>
imagent[783:6497] [com.apple.contacts:PersistentStoreBuilder] Skipping XPC store fallback: preparation
    did not produce a URL. Preserving preparation error: <same error>
```

The third line matters: the **XPC store fallback is skipped** because preparation never produced a URL — so the designed fallback cannot rescue this, and control returns straight to a retry.

Consecutive retry timestamps inside one burst (2026-07-16 14:54:36):

```
.033  .035  .037  .038  .039  .041  .042  .044  .046  .051  .052  .063
```

**1–2 ms apart, and the interval never grows.** No exponential backoff, no attempt cap, no give-up.

| Metric | Value |
|---|---|
| Total `Sandbox restriction` errors | **66,626** in 7 h |
| Peak minute | 1,982 lines (10:25) |
| Tightest second | 265 lines (14:54:36) ≈ 88 retries/s |
| Retry interval | **1–2 ms**, constant |
| imagent CPU | **19.42 s over 6 h 53 m** (≈0.08%) |

## 3. Trigger (context, not the bug)

The bursts are episodic and driven externally: they track `AddressBookManager` (`com.apple.AddressBook.abd`) spawns. All 5 of imagent's top burst minutes fall on spawn minutes (10:25, 11:54, 12:26, 14:26, 15:50 — 5/5; spawns cover ~18% of uptime minutes, so ≈0.02% by chance), and the most recent burst (16:42:21) followed a spawn at 16:40:45.

Those spawns are themselves a separate contactsd defect (filed separately — contactsd drives `com.apple.AddressBook.abd` against itself in a self-sustaining change-history loop). **imagent is a consequence of that trigger, not its cause**: 19 s of CPU cannot account for the contactsd loop's ~143% bursts. The imagent defects here — the missing profile entry and the unbounded retry — stand on their own regardless of what drives the spawns, and would still be wrong if the trigger fired only once.

# Steps to Reproduce
1. On macOS 27.0 26A5378n, confirm the contradiction statically — no repro state needed:
   ```
   codesign -d --entitlements - /System/Library/PrivateFrameworks/IMCore.framework/imagent.app/Contents/MacOS/imagent | grep -A1 ContactsAccountsService
       → [Key] com.apple.AddressBook.ContactsAccountsService / [Bool] true

   grep -n "ContactsAccountsService" /System/Library/Sandbox/Profiles/com.apple.imagent.sb
       → no matches

   grep -n 'global-name "com.apple.AddressBook.abd"' /System/Library/Sandbox/Profiles/com.apple.imagent.sb
       → 177:     (global-name "com.apple.AddressBook.abd")      (i.e. the legacy service IS allowed)
   ```
2. Observe the loop with a Contacts account configured (7 CardDAV + 1 Exchange here). No user interaction is needed — Messages and Contacts were never opened.
   ```
   /usr/bin/log show --last 1h --predicate 'process == "imagent" AND eventMessage CONTAINS "Sandbox restriction"' | wc -l
   ```
3. Inspect the retry interval inside a burst — timestamps land 1–2 ms apart with no growth:
   ```
   /usr/bin/log show --last 1h --predicate 'process == "imagent" AND eventMessage CONTAINS "Migration service failed"' --style compact
   ```
4. Confirm it is not a CPU problem: `ps -o time=,etime= -p $(pgrep -x imagent)` → ~19 s across ~7 h.

Notes for reproduction: `log` is a **zsh builtin** — use `/usr/bin/log` explicitly or the commands silently return nothing. The loop is **episodic**, so a short window may show 0; sample across an hour, or trigger it by causing an `AddressBookManager` (`com.apple.AddressBook.abd`) spawn.

# Expected vs Actual
- **Expected:** a process holding `com.apple.AddressBook.ContactsAccountsService = true` can look the service up — its sandbox profile should list the global-name (as it already does for the legacy `com.apple.AddressBook.abd`). Failing that, a sandbox denial is a **permanent, non-retryable** condition: fail once, log once at an appropriate level, and stop — or back off exponentially and give up.
- **Actual:** every lookup is denied (`error 159 - Sandbox restriction`); the store-preparation path retries every 1–2 ms with no backoff and no cap, emitting 3 persisted `E`-level lines per attempt — 66,626 lines in 7 h from one process, indefinitely.

# Configuration
- MacBook Pro Mac15,11, M3 Max, 36 GB
- macOS 27.0 beta3 revision 26A5378n
- imagent 10.0 (1000), `/System/Library/PrivateFrameworks/IMCore.framework/imagent.app`
- Sandbox profile: `/System/Library/Sandbox/Profiles/com.apple.imagent.sb` (403 lines)
- 12 Contacts sources configured (7 CardDAV, 1 Exchange, 4 with no group record)

# Suggested attachments
- sysdiagnose captured during a burst
- `codesign -d --entitlements -` output for the imagent binary (shows `ContactsAccountsService = true`)
- `/System/Library/Sandbox/Profiles/com.apple.imagent.sb` — or just the `grep -n` output above showing `AddressBook.abd` present at line 177 and `ContactsAccountsService` absent
- Saved `log show` output for `Sandbox restriction`, showing the 1–2 ms retry timestamps and per-minute counts
- `ps -o time=,etime=` for imagent, demonstrating this is log volume rather than CPU

# Note
`sandboxd` logged **0** lines mentioning imagent across the 7 h window — the denial surfaces only client-side, as the `Code=4099 … error 159 - Sandbox restriction` above. If a sandbox denial of an entitled global-name is expected to be reported by sandboxd, that silence may be a second, smaller issue.
