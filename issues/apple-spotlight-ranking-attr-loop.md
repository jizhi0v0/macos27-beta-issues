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

## Notes / 备注

- `Campo` is the macOS 27 Spotlight UI app (codename); confirmed by its log subsystems `com.apple.SpotlightServices` + `com.apple.spotlight.ui`.
- No public report of this exact signature found (2026-06-26) — only generic "Spotlight is slow" complaints. Likely an early capture of this specific beta regression.
- Distinct from `corespotlightd` AI-suggestion work (`Pommes_Suggestions`, background suggestions model) seen in the same period; the lag signal is the UI-side ranking-attr loop.
