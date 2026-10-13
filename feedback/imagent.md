FILED 2026-10-13 as **FB25167334** (https://feedbackassistant.apple.com/feedback/25167334). Area: Messages → Something else not on this list; type: Incorrect/Unexpected Behavior. Attachments: sysdiagnose, System Information Report, imagent-evidence.txt (entitlements, profile greps, sibling-profile list, one hour of attempt timestamps). The text below is what was submitted.

VERIFICATION: CONFIRMED on 27.2 beta3 `26B5101f` (2026-10-13), first captured on 27.0 beta3 `26A5378n` (2026-07-16) and present on every build in between. Current build: entitlement `ContactsAccountsService = true`, profile 405 lines with **0** mentions of the service, **26** sibling profiles that name it; **6,492** `error 159` lines from imagent in one hour (2,156 attempts), in runs of exactly **44** back-to-back attempts (median gap 1 ms), while imagent used **1.79 s** of CPU over 22 m 45 s.

Correction to the earlier draft, made before filing: it said the retry has "no cap" and runs "forever". On `26B5101f` each trigger produces a run of exactly 44 attempts (42 of the hour's runs; the 77/88 counts are adjacent runs merged by the 0.5 s split), so a run *is* bounded — it is the 44 attempts within it that have no delay, and the runs recur on every trigger, indefinitely. The beta5 note of "44 attempts in a live burst" was the same number. What 44 is (a retry cap, or 44 distinct callers) is not known.

# Title
*(Feedback Assistant's title field is short — use this, 93 chars, plain ASCII hyphen so nothing mangles on paste:)*

```
imagent: sandbox omits ContactsAccountsService lookup it is entitled to; retries every 1-2 ms
```

Fallback if that still won't fit (79 chars):

```
imagent: no-backoff retry loop on sandbox-denied ContactsAccountsService lookup
```

# Form fields
- **Which area are you seeing an issue with?** → **Messages**. Rationale: the offending binary and the misconfigured profile are both IMCore's (`imagent.app`, `com.apple.imagent.sb`), so this routes to the team that owns the file that needs the one-line fix. (Alternatives, if Messages doesn't fit the picker: *Contacts* — the retry policy lives in Contacts' `PersistentStoreBuilder`.)
- **What type of issue are you reporting?** → **Incorrect/Unexpected Behavior.** (Not a performance report — imagent's CPU use is negligible. The defect is the denial plus the undelayed retry.)

# Description
On macOS 27.2 beta 3 (26B5101f) — and on every build since 27.0 beta 3 (26A5378n) — `imagent` (10.0, build 1000) cannot look up `com.apple.AddressBook.ContactsAccountsService`. Every attempt is denied by its own sandbox, Contacts database preparation fails, and the failure path **retries immediately: runs of 44 attempts, median 1 ms apart, with no backoff inside a run**. Each attempt emits **three persisted `E`-level lines**. The runs recur on every trigger, for as long as the machine is up.

**6,492 error lines in one hour on 26B5101f; 66,626 in 7 hours on 26A5378n.**

This is a **log-volume defect, not a performance one**: imagent used 1.79 s of CPU over 22 m 45 s (26B5101f) and 19.42 s over 6 h 53 m (26A5378n). It is filed for (a) the entitlement/sandbox-profile contradiction and (b) the undelayed retry against a permanently-failing condition.

## 1. The contradiction: entitled to use it, not allowed to look it up

`codesign -d --entitlements -` on `/System/Library/PrivateFrameworks/IMCore.framework/imagent.app/Contents/MacOS/imagent`:

```
[Key] com.apple.AddressBook.ContactsAccountsService
[Value]
    [Bool] true                                   ← the service's own access entitlement: allowed to USE it
```

imagent additionally carries `com.apple.Contacts.database-allow`, `com.apple.private.contacts`, and `kTCCServiceAddressBook` in its TCC allow list. **Every authorization layer grants it Contacts access.**

But `/System/Library/Sandbox/Profiles/com.apple.imagent.sb` (405 lines on 26B5101f) has an explicit `(allow mach-lookup …)` block at line 173 that **does not contain the service**:

```
173: (allow mach-lookup
177:     (global-name "com.apple.AddressBook.abd")            ← LEGACY AddressBook service: allowed
     …
233:     (global-name "com.apple.private.contacts")           ← allowed
234:     (global-name "com.apple.Contacts.database-allow")    ← allowed
     …
     com.apple.AddressBook.ContactsAccountsService           ← ABSENT from the entire file
```

`grep -n "ContactsAccountsService" /System/Library/Sandbox/Profiles/com.apple.imagent.sb` → **no matches**.

`com.apple.AddressBook.ContactsAccountsService` is listed in **26 other** system sandbox profiles (`contactsd.sb`, `suggestd.sb`, `sharingd.sb`, `gamed.sb`, `assistantd.sb`, `siriactionsd.sb`, `studentd.sb`, …). imagent's profile is the outlier: it grants the **legacy** `com.apple.AddressBook.abd` lookup, the AddressBook preference domains and `~/Library/Application Support/AddressBook`, but omits the **modern** `ContactsAccountsService` that Contacts' `PersistentStoreBuilder` actually calls. The profile contains no `(require-entitlement …)` rules, so the entitlement cannot rescue the lookup: the entitlement is what the service checks, and the profile stops imagent from ever reaching it. Adding the one global-name line, matching the 26 siblings, closes the contradiction.

The profile has been unchanged on this point across 27.0 beta 3 → 27.2 beta 3; the only edit in that span was 27.2 beta 2 adding `(global-name "com.apple.sharereportingd")`.

## 2. The retry

Each denied attempt emits three lines, all at `E` level (persisted by logd):

```
imagent [com.apple.contacts:migration] [Migration] Migration service failed database preparation:
    Error Domain=NSCocoaErrorDomain Code=4099 "The connection to service named
    com.apple.AddressBook.ContactsAccountsService was invalidated: Connection init failed at lookup
    with error 159 - Sandbox restriction."
imagent [com.apple.contacts:PersistentStoreBuilder] Database preparation failed: <same error>
imagent [com.apple.contacts:PersistentStoreBuilder] Skipping XPC store fallback: preparation
    did not produce a URL. Preserving preparation error: <same error>
```

The third line matters: the **XPC store fallback is skipped** because preparation never produced a URL, so the designed fallback cannot rescue this.

Measured on 26B5101f over one hour (09:57:57–10:48:14):

| Metric | Value |
|---|---|
| Attempts (`Migration service failed` lines) | **2,156** (6,492 `error 159` lines) |
| Attempts per run | **44** in 42 of the runs (the rest are adjacent runs merged, or cut by the window edge) |
| Gap between attempts inside a run | median **1 ms**, 90th percentile 6 ms; 1,697 of 2,106 gaps under 2.5 ms |
| Does the gap grow across a run? | No — e.g. one run's gaps: `13 16 10 3 14 5 5 4 3 6 4 1 3 1 1 2 0 1 0 1 0 3 1 1 9 2 1 1 1 0 2 0 3 1 2 0 2 0 1 0 1 0 1` ms |
| Runs | often back-to-back, ~1.5 s apart (e.g. 15 runs between 10:28:07 and 10:28:26) |

### The retry policy, read from the binary (27.0 beta 5, 26A5406e)

- The XPC lookup is wrapped in `-[CNCDRemotePersistentStoreEndpointFactory newEndpointWithError:]`, which runs through `-[CNRetry performAndWait:]` with the factory as delegate. That delegate **does implement a backoff**: `maximumNumberOfAttemptsForRetry:` → 2, `retry:delayAfterError:onAttempt:` → **2.0 s**, but `retry:shouldContinueAfterError:onAttempt:` → retry **only if** the error is `CNErrorDomain` **1012**.
- The sandbox error is `NSCocoaErrorDomain` 4099 (mach error 159), so that wrapper makes exactly one attempt — **the 2.0 s backoff is never engaged for this failure**. The repetition comes from a caller layer that re-invokes the whole prepare attempt with no delay. The exact outer frame is not pinned: imagent is SIP-protected, so it could not be stack-sampled during a run.
- `CNRetry` skips the sleep entirely when the delegate's delay is 0.0, so the engine has no built-in default backoff either.

## 3. Trigger (context, not the bug)

The runs are driven externally: on 26A5378n they tracked `AddressBookManager` (`com.apple.AddressBook.abd`) spawns — all 5 of imagent's top burst minutes fell on spawn minutes (≈0.02% by chance). Those spawns are a separate contactsd defect, already filed as **FB24264605** (contactsd change-history loop on CardDAV collection-groups). The imagent defects here — the missing profile entry and the undelayed retry — stand on their own and would still be wrong if the trigger fired only once.

## 4. A possible user-visible symptom (reported by another user, not reproduced here)

On the public tracker for this issue (https://github.com/jizhi0v0/macos27-beta-issues/issues/19), another user on 26B5101f (M1 Pro) reported that Messages showed phone numbers instead of contact names in every conversation, while contact photos still appeared, at the same time as this error was looping; a reboot restored the names. On my machine the error fires at the rate above while Messages shows the correct name for every conversation whose number is a saved contact. So the denial alone is not sufficient to hide names. I include the report as a correlation for whoever owns Messages name resolution, not as a confirmed consequence.

# Steps to Reproduce
1. Confirm the contradiction statically — no repro state needed:
   ```
   codesign -d --entitlements - /System/Library/PrivateFrameworks/IMCore.framework/imagent.app/Contents/MacOS/imagent | grep -A2 ContactsAccountsService
       → [Key] com.apple.AddressBook.ContactsAccountsService / [Bool] true

   grep -n "ContactsAccountsService" /System/Library/Sandbox/Profiles/com.apple.imagent.sb
       → no matches

   grep -n 'global-name "com.apple.AddressBook.abd"' /System/Library/Sandbox/Profiles/com.apple.imagent.sb
       → 177:    (global-name "com.apple.AddressBook.abd")      (the legacy service IS allowed)

   grep -l ContactsAccountsService /System/Library/Sandbox/Profiles/*.sb | wc -l
       → 26
   ```
2. With Contacts accounts configured (7 CardDAV + 1 Exchange here), count the denials. No interaction is needed:
   ```
   /usr/bin/log show --last 1h --style compact --predicate 'process == "imagent" AND eventMessage CONTAINS "error 159"' | grep -c 'error 159'
   ```
3. Inspect a run — 44 attempts, ~1 ms apart, no growth:
   ```
   /usr/bin/log show --last 1h --style compact --predicate 'process == "imagent" AND eventMessage CONTAINS "Migration service failed"'
   ```
4. Confirm it is not a CPU problem: `ps -o time=,etime= -p $(pgrep -x imagent)`.

Note: in zsh, `log` is a shell builtin — use `/usr/bin/log` or the commands silently return nothing. The runs are episodic; sample across an hour.

# Expected vs Actual
- **Expected:** a process holding `com.apple.AddressBook.ContactsAccountsService = true` can look the service up — its sandbox profile lists the global-name, as it already does for the legacy `com.apple.AddressBook.abd` and as 26 other profiles do. Failing that, a sandbox denial is a permanent, non-retryable condition: fail once, log once, and stop — or back off.
- **Actual:** every lookup is denied (`error 159 - Sandbox restriction`); each trigger produces 44 back-to-back attempts about 1 ms apart, 3 persisted `E`-level lines each — 6,492 lines in one hour from one process.

# Configuration
- MacBook Pro Mac15,11, M3 Max, 36 GB
- macOS 27.2 beta 3 (26B5101f); first seen on 27.0 beta 3 (26A5378n)
- imagent 10.0 (1000), `/System/Library/PrivateFrameworks/IMCore.framework/imagent.app`
- Sandbox profile: `/System/Library/Sandbox/Profiles/com.apple.imagent.sb` (405 lines)
- 12 Contacts sources (7 CardDAV, 1 Exchange, 4 with no group record)

# Attachments
- sysdiagnose
- `imagent-evidence.txt`: entitlements, profile greps, sibling-profile list, one hour of `Migration service failed` timestamps

# Note
`sandboxd` logged **0** lines mentioning imagent across the original 7 h window — the denial surfaces only client-side, as the `Code=4099 … error 159 - Sandbox restriction` above. If a denial of an entitled global-name is supposed to be reported by sandboxd, that silence may be a second, smaller issue.
