# Spotlight ("Campo") spams `Attempted to insert ranking attr at NSNotFound` ~60×/sec while typing → search lag
# 新版 Spotlight 打字时狂报 `insert ranking attr at NSNotFound`(~60次/秒)→ 搜索卡顿

> 🔗 **Track / 关注此问题:** [#13 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/13)

| | |
|---|---|
| **Status** | 🟢 User-facing typing lag / ghosting FIXED on beta3 `26A5378j` (residual benign log spam remains); confirmed beta2 |
| **macOS** | lag confirmed 27.0 beta2 `26A5368g`; lag gone on beta3 `26A5378j` (log line persists) |
| **Component** | Apple **Spotlight** — `com.apple.SpotlightServices` / `com.apple.spotlight.ui`; UI app was **`Campo`** on beta2, **renamed to `Siri AI`** on beta3 (internal framework still `CampoUIServices`, same subsystems) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max |
| **Report** | Apple Feedback: **`FB23412497`** (filed 2026-06-26, Spotlight → Incorrect/Unexpected Behavior; sysdiagnose + before/after capture attached) |

## Symptom / 症状

Typing in Spotlight (⌘Space) is noticeably laggy on macOS 27 beta2.

⌘Space 调出 Spotlight 打字明显卡顿。

## Evidence — idle vs typing / 证据：空闲 vs 打字

Not fresh-boot reindexing: uptime was 6h+, and `mds` / `mds_stores` were idle (<1.5% CPU), `mdutil -s /` = indexing enabled (not in progress).

| State | `insert ranking attr at NSNotFound` | Campo (Spotlight UI) CPU |
|---|---|---|
| **Idle** (not typing), 20s | **0** | 0.4% |
| **Typing** (~3s), 8s window | **484 (~60/sec)** | spikes |

While typing, the Spotlight UI process `Campo` emits, at default level, ~60 times/second:
```
(SpotlightServices) [com.apple.SpotlightServices:General] Attempted to insert ranking attr at NSNotFound, value=<private>
```
plus continuous `(SpotlightUIInternal) [com.apple.spotlight.ui:WindowExpansion] Invalidating size for Spotlight queries!`. When idle the error count is **zero** — it fires per keystroke/query. The ranking code is repeatedly trying to insert a ranking attribute at an invalid index (`NSNotFound`), which lines up exactly with the per-keystroke typing lag.

## Reproduction / 复现

1. macOS 27.0 26A5368g, idle for a while (so it's not boot-time reindexing).
2. `⌘Space`, type a query continuously for a few seconds.
3. `log show --start <t0> --end <t1> --predicate 'eventMessage CONTAINS "insert ranking attr at NSNotFound"'` over the typing window → dozens/sec; zero when idle.

## Expected vs Actual / 期望 vs 实际

- **Expected:** ranking attributes inserted at valid indices, no error; responsive typing.
- **Actual:** `Attempted to insert ranking attr at NSNotFound` ~60×/sec while typing, search UI laggy.

## Candidate sets being ranked (from the 484-error window) / 报错窗口里的候选规模

`[SpotlightRanking] <Model> preparing N items for bundle …` during the burst:

| candidates | bundle |
|---|---|
| **395** | **com.apple.systempreferences** ← by far the largest |
| 104 / 59 / 29 / 25 / 20 | `<private>` (redacted content types) |
| 21 | com.apple.applications |
| 2 | com.apple.Notes |
| 1 | com.apple.spotlight.tophits |

Per keystroke the ranking model prepares ~395 **System Settings** items plus several hundred `<private>` items. The `insert ranking attr at NSNotFound` errors cluster while ranking these large candidate sets — suggesting the ranking-attribute array indexing fails (overflows to `NSNotFound`) on large sets, with **System Settings (systempreferences) the prime suspect source**. (To de-redact the `<private>` bundles, capture with `sudo log config --mode private_data:on`.)

**Correction 2026-06-26 — systempreferences was a RED HERRING; categories don't gate the error:** disabled the **System Settings + Clipboard + Developer** result categories (so `systempreferences`'s 395 items no longer enter ranking — confirmed gone from the `preparing … bundle` lines) and re-tested. The `insert ranking attr at NSNotFound` rate did **not** drop — **1233 occurrences in a ~9s typing window (~137/sec, same as the ~160/sec seen before)**, now while ranking `com.apple.applications` / `tophits` / `<private>` / syndicatedPhotos instead. So the error is **intrinsic to the ranking code and independent of which candidate bundles are present** — no Settings/category toggle reduces it. The user *did* perceive Spotlight as snappier with System Settings off, but that is **fewer results to render**, not fewer ranking errors — a usability tweak, not a fix. Net: the only real workaround remains a third-party launcher; the bug is Apple's to fix.

## Notes / 备注

- `Campo` is the macOS 27 Spotlight UI app (codename); confirmed by its log subsystems `com.apple.SpotlightServices` + `com.apple.spotlight.ui`.
- No public report of this exact signature found (2026-06-26) — only generic "Spotlight is slow" complaints. Likely an early capture of this specific beta regression.
- Distinct from `corespotlightd` AI-suggestion work (`Pommes_Suggestions`, background suggestions model) seen in the same period; the lag signal is the UI-side ranking-attr loop.

**Workaround test 2026-06-26 — NOT the suggestions layer; no Settings fix:** disabling **System Settings → Spotlight → "Show Related Content"** (the Apple-partner/web-suggestions toggle) had **no effect** — typing still produced 498 occurrences (vs 484 with it on). With Related Content off, `Campo` is seen ranking basic `[com.apple.spotlight:Apps][Settings] found items` + CoreSpotlight query results and the `insert ranking attr at NSNotFound` error still fires. So the bug is in the **core query/result-ranking path**, not the suggestions/related-content layer, and cannot be tuned away in Settings. The only effective workaround is to avoid the Spotlight UI entirely (use a third-party launcher like Raycast/Alfred); real fix is up to Apple. This rules-out the suggestions layer — useful for the Feedback.

## Retest on beta3 `26A5378j` (2026-07-07) — LAG/GHOSTING FIXED; log spam remains / 卡顿+残影已修,日志噪声还在

**Correction to first pass:** the initial beta3 retest looked only at the *log signature* and wrongly called the bug "still present, worse." The log line **does** persist — a live capture around a real typing burst still produced **14,798** `insert ranking attr at NSNotFound`, peak **1,569/sec** (beta2 was ~60–160/sec), with ranking running (`[SpotlightRanking] preparing N items …`, incl. the ~369-item `systempreferences` sets). **But log volume was never the user-facing bug** — the felt symptom was typing lag + a result "ghost"/afterimage that lingered several seconds.

**On the actual symptom, beta3 is fixed** — corroborated by the user (typing now feels smooth, no ghosting) *and* by an objective signal:

| | beta2 `26A5368g` | beta3 `26A5378j` |
|---|---|---|
| Spotlight-UI **spin/hang reports** | **3× `Campo_*.spin` on 2026-07-06**, `Reason: Slow response to HID event`, heavy in `Campo` + `SpotlightUIShared` | **0** since boot (07:53), despite active typing |
| Felt typing lag / multi-sec ghosting | yes (user-reported + spin reports) | **no** (user-reported) |
| `insert ranking attr at NSNotFound` | ~60–160/sec while typing | still fires (peak 1569/sec) — **now benign** |

The beta2 `.spin` reports (`Slow response to HID event`, stuck in `SpotlightUIShared`) are the objective fingerprint of the keyboard lag/ghosting. Beta3 produces none, so the UI no longer spins on keystrokes even though the ranking-attr line keeps logging → the log error is now **decoupled from UX / harmless log noise**, not the cause of lag.

**Net:** user-impacting bug (the reason [FB23412497](https://feedbackassistant.apple.com/feedback/23412497) was filed) is **fixed on beta3**. What remains is a cosmetic `insert ranking attr at NSNotFound` log line at high rate — worth a note to Apple to clean up the logging, but no longer a perf/UX problem. UI app renamed **`Campo` → `Siri AI`** (PID 1513; internal framework still `CampoUIServices`).

**Intermittency note 2026-06-26:** the error is **query/state-dependent, not every keystroke.** Repeated typing tests gave both ~484–498 occurrences in ~3s (heavy burst, ~60/sec) AND 0 in another typing window where Spotlight still ranked results normally (`[SpotlightRanking] <Model> preparing N items` present, no NSNotFound). So: idle = always 0; typing = intermittently bursts to ~60/sec on some queries, 0 on others. The residual lag the user still feels even on a 0-error query is likely the ranking-model work itself (`SpotlightRanking Model preparing items`), which runs regardless. (Also note: a "quit Mail" test was inconclusive — the Mail process was still alive despite closing its window.)
