# Spotlight ("Campo") spams `Attempted to insert ranking attr at NSNotFound` ~60×/sec while typing → search lag
# 新版 Spotlight 打字时狂报 `insert ranking attr at NSNotFound`(~60次/秒)→ 搜索卡顿

| | |
|---|---|
| **Status** | ✅ CONFIRMED beta2 — clean idle-vs-typing contrast |
| **macOS** | 27.0 beta2 `26A5368g` |
| **Component** | Apple **Spotlight** — `com.apple.SpotlightServices` / `com.apple.spotlight.ui`; the macOS 27 Spotlight UI process is **`Campo`** (`/System/Applications/Campo.app`) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max |
| **Report** | Apple Feedback: `FB________` *(to be filed)* |

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

## Notes / 备注

- `Campo` is the macOS 27 Spotlight UI app (codename); confirmed by its log subsystems `com.apple.SpotlightServices` + `com.apple.spotlight.ui`.
- No public report of this exact signature found (2026-06-26) — only generic "Spotlight is slow" complaints. Likely an early capture of this specific beta regression.
- Distinct from `corespotlightd` AI-suggestion work (`Pommes_Suggestions`, background suggestions model) seen in the same period; the lag signal is the UI-side ranking-attr loop.

**Workaround test 2026-06-26 — NOT the suggestions layer; no Settings fix:** disabling **System Settings → Spotlight → "Show Related Content"** (the Apple-partner/web-suggestions toggle) had **no effect** — typing still produced 498 occurrences (vs 484 with it on). With Related Content off, `Campo` is seen ranking basic `[com.apple.spotlight:Apps][Settings] found items` + CoreSpotlight query results and the `insert ranking attr at NSNotFound` error still fires. So the bug is in the **core query/result-ranking path**, not the suggestions/related-content layer, and cannot be tuned away in Settings. The only effective workaround is to avoid the Spotlight UI entirely (use a third-party launcher like Raycast/Alfred); real fix is up to Apple. This rules-out the suggestions layer — useful for the Feedback.

**Intermittency note 2026-06-26:** the error is **query/state-dependent, not every keystroke.** Repeated typing tests gave both ~484–498 occurrences in ~3s (heavy burst, ~60/sec) AND 0 in another typing window where Spotlight still ranked results normally (`[SpotlightRanking] <Model> preparing N items` present, no NSNotFound). So: idle = always 0; typing = intermittently bursts to ~60/sec on some queries, 0 on others. The residual lag the user still feels even on a 0-error query is likely the ranking-model work itself (`SpotlightRanking Model preparing items`), which runs regardless. (Also note: a "quit Mail" test was inconclusive — the Mail process was still alive despite closing its window.)
