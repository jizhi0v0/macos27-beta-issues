# beta7 `26A5421a` — first measurements

Upgraded from beta6 `26A5416b` on **2026-08-24 23:33** per
`/Library/Receipts/InstallHistory.plist`. The kernel did **not** move — still
`xnu-13432.1.9~3`, the same string beta6 carried.

⚠️ The system files carry an **Aug 21 14:26** mtime. That is the image *build* date, not the
install date; reading it as the install date put the beta6/beta7 boundary three days early once
already and briefly turned a surviving beta6 control into "no control exists". Use
`InstallHistory.plist`.

These measurements were taken on the **2026-08-27 13:39:10 boot**, i.e. three days into the
build, not on its first boot. Xcode is still `27A5237l`, so SDK-tracked entries (**#11**) are
untouched and not re-tested.

Baseline to compare against: [`../beta6-26A5416b/`](../beta6-26A5416b/README.md).

| file | contents |
|---|---|
| `postboot-window.txt` | the one-shot post-boot window, T+0 → T+8m00s, with per-issue counts |
| `contactsd-backlog.txt` | #18 per-source rows, taken T+1h56m |

---

## Two capture traps this round walked into, both silent

1. **`log show --start X --end Y` ignored `--end` with no `--predicate`** — an 8-minute request
   returned 1 h 50 m. The window was cut out afterwards with awk. With a predicate both bounds
   are honoured.
2. **An anchored `^\S+ \S+ \S+ (name)\[` regex counts only `Df` rows**, because compact style
   pads a one-character type field (`A `, `E `, `F `) to two columns. It undercounted #2 by 34%
   (20,267 vs 30,699) and the wrong number looked entirely plausible.

Also confirmed, because it decides comparability: **default `log show` already returns `Df`
records on this machine** — the same one-minute `ecosystemd` query returned 6,060 with and
without `--info --debug`. So these counts sit at the same level scope as the beta5/beta6 ones.

---

## Decided

### #23 ecosystemd — 🔴 **unchanged from beta6, to three significant figures**

`tools/eco-replicate.sh`, 15:33–15:36:

| rep | eco % | anchors/s | lines/60s | EIO |
|---|---|---|---|---|
| 1 | 13.5 | 33.1 | 6,859 | 477 |
| 2 | 12.9 | 32.5 | 6,739 | 468 |
| 3 | 12.8 | 32.5 | 6,739 | 468 |

Mean CPU **13.1%** (min 12.8, max 13.5, sd 0.3) against beta6's 33.1/s, 476 EIO, 12.7% mean.

⚠️ **Effectively n=2.** Reps 2 and 3 returned byte-identical triples (6,739 / 468 / 32.5), the
flush-boundary artefact the script's own header claims was fixed by pinning `--start`/`--end`.
It recurred. ⚠️ The machine was **not quiesced** — 25 `/Applications` bundles running, load
average ~6–8. Per the script's own note the anchors/s and EIO columns are not load-sensitive;
the CPU column is, so read 13.1% as an upper-ish bound, not a matched comparison.

### #18 contactsd — 🔴 **backlog crossed a second upgrade and kept growing**

| | beta3 | beta5 08-11 | beta5 08-18 | beta6 08-19 | **beta7 08-27** |
|---|---|---|---|---|---|
| unconsumed group-change rows | 53,686 | 76,366 | 90,209 | 91,030 | **98,489** |
| worst single source | 17,918 | 23,849 | 27,202 | 27,388 | **29,289** |

All 12 sources carried over, every non-zero one up, **none reset**. Log volume up too: 45,697
contactsd records in the post-boot window (~343k/h) against beta6's 27,809 (~214k/h).

⚠️ The beta6 reading was T+9m; this one is T+1h56m. The backlog is monotonic between resets so
the comparison holds, but it is not the same clock position and the two should not be treated as
a matched pair.

### #19 imagent — 🔴 **the profile is byte-for-byte the same argument as beta6**

`com.apple.imagent.sb` is still **404 lines** with **0** mentions of `ContactsAccountsService`,
still the outlier against the **26** sibling profiles that do name it. 3,096 imagent records
naming the service in the post-boot window, against beta6's 2,383. The one-line fix was not
applied.

### #2 Shortcuts/Siri ToolKit storm — 🟡 **worse again, and still one unreplicated window**

30,699 records in the 8-minute post-boot window against beta6's 16,203 in 7m47s; peak **1,795
lines/s** across all levels (1,306 counting `Df` only) against beta6's 864 and beta5's 181.
Both totals are recorded in `postboot-window.txt` because beta6's level scope was never written
down, so which pair is the like-for-like comparison is not currently decidable. **One window,
not replicated, not a verdict** — same caveat the beta6 entry carries.

### #1 CoreMedia `fpSupport_GetVideoRange` — 🟡 **much quieter, but the emitter mix changed too**

**219** records in the post-boot window against beta5's 1,744 in 8 minutes. But the emitters are
not the same set: across the whole 1 h 50 m session it is WeType 1,095, DingTalk 978, Raycast
358, DuoUpdater 78, textunderstandingd 15, Mail 11. Beta5's were DingTalk 1,338, WeType 263,
Mail 136. Since the trigger is app-dependent, **a lower count with a different app mix is not
evidence of an OS-side fix** and is not claimed as one.

### #15 appstoreagent — ⚪ **still not triggered**

**0** `BGSystemTaskSchedulerErrorDomain Code=8` in the post-boot window, as on beta3/beta5/beta6.
Conditional trigger; last actually seen on beta2. Not reproduced ≠ fixed.
