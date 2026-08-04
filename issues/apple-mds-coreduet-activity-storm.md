# `mds` emits ~2,420 CoreDuet activity log lines/second, continuously
# `mds` 持续以 ~2420 行/秒 刷 CoreDuet activity 日志

> 🔗 **Track / 关注此问题:** [#24 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/24)

| | |
|---|---|
| **Status** | 🔴 Open · confirmed on beta4 |
| **macOS** | 27.0 beta4 `26A5388g` |
| **Component** | Apple **Spotlight / `mds`** (`com.apple.metadata`) ↔ **CoreDuet** (`CoreDuetContext`, `contextstored`) |
| **Hardware** | `Mac15,11`, M3 Max, 36 GB, single internal display |
| **Report** | Apple Feedback: `FB________` *(to be filed)* |

## Symptom / 症状

`mds` writes **145,241 log lines in 60 seconds (~2,420/sec)**, all of the same CoreDuet activity-creation message. It accounts for **54% of the entire system log volume** (145,265 of 268,555 timestamped entries in that minute). `mds` sits at 39–43% CPU and `contextstored` — the CoreDuet daemon on the other end — at 24–39%.

`mds` 每 60 秒写 145,241 行日志（~2420 行/秒），全是同一条 CoreDuet activity 创建消息，占全系统日志量的 54%。同期 `mds` 吃 39–43% CPU，对端的 `contextstored` 吃 24–39%。

## Evidence / 证据

```
$ log show --last 60s --style syslog | grep -E '^2026.* mds\[368\]' | wc -l
145265

$ … | sed 's/^.* mds\[368\]: //' | sort | uniq -c | sort -rn | head -1
145241 (CoreDuetContext) Created Activity ID: 0x…, Description: CoreDuet: ClientContext objectForContextualKeyPath:
```

Full line:

```
2026-07-25 17:57:56.640917+0800  localhost mds[368]: (CoreDuetContext) Created Activity ID: 0x6f04e0, Description: CoreDuet: ClientContext objectForContextualKeyPath:
2026-07-25 17:57:56.641246+0800  localhost mds[368]: (CoreDuetContext) Created Activity ID: 0x6f04e1, Description: CoreDuet: ClientContext objectForContextualKeyPath:
```

**Continuous, not bursty** — every one of the 61 seconds in the capture window contains lines, at a steady 2,197–2,882/sec:

```
992 17:57:56    2544 17:57:58    2391 17:58:00    2436 17:58:02
2197 17:57:57   2882 17:57:59    2512 17:58:01   1144 17:58:03
```

Top log emitters in the same minute (timestamped entries only):

| process | lines / 60 s |
|---|---|
| **mds** | **145,265** |
| Mail | 18,469 |
| ecosystemd | 15,885 — see [ecosystemd trust loop](apple-ecosystemd-trust-retry-loop.md) |
| trustd | 11,471 |
| spotlightknowledged.updater | 7,814 |
| BiomeAgent | 5,644 |

Alongside it, `com.apple.mdworker.shared` is launched **341 times in 60 seconds** (~5.7 spawns/sec):

```
$ grep "launchd\[1\].*mdworker" log60.txt | grep -oE "com\.apple\.mdworker\.[a-z]+" | sort | uniq -c
341 com.apple.mdworker.shared
```

The `contextstored` side shows the matching write path:

```
44 (CoreDuetContext) Created Activity ID: …, Parent ID: …, Description: CoreDuet: ContextStore setObject:forContext…
12 (CoreDuetContext) [com.apple.coreduet:context] Sending fired registration <private> to com.apple.das…
11 (KnowledgeMonitor) [com.apple.coreduet:context] Restart preventer: <private>
```

## Impact / 影响

- Saturates the unified log — makes `log show` / `log collect` on this machine nearly unusable for any other investigation, and buries other signals.
- Sustained double-digit CPU on two system daemons (`mds` + `contextstored`) for the entire uptime.
- Contributes to a load average of 30–75 while CPU is ~60% idle (processes blocked, not computing), alongside heavy memory-compressor activity (12 GB compressed, 15.5 M pages decompressed, 676 MB free, swap 0).

## Reproduction / 复现

Not isolated to a specific trigger. Observed continuously across a 3.5-hour uptime on beta4. `mdutil -as` reports indexing enabled on `/` and `/System/Volumes/Data`; `~/Library/Developer/CoreDevice/DeviceFS` and `~/OrbStack` are excluded.

Open question: whether this is Spotlight querying CoreDuet per indexed item (in which case it should scale with indexing volume and stop when indexing settles), or an unbounded re-registration loop. Worth re-checking after Spotlight fully settles — in a later session `mds + mdworker` aggregate CPU did reach **0.0%**, so the storm is not permanent.

## Workaround / 临时规避

None known that keeps Spotlight functional. Silencing the subsystem only hides the log volume, not the CPU:

```sh
sudo log config --subsystem com.apple.duetactivityscheduler --mode 'level:off'
```

## Re-measured 2026-08-04 10:23 (uptime 1 d 0 h 23 m) — NOT active in this window / 次日复测:本轮未发作

The storm is **intermittent**. A 60 s capture on a different day and a different boot:

| Metric | 2026-07-25 (storm) | 2026-08-04 |
|---|---|---|
| `mds` log lines / 60 s | **145,241** | **132** |
| `contextstored` lines / 60 s | (top-tier) | 22 |
| `com.apple.mdworker.shared` spawns / 60 s | **341** (~5.7/s) | 53 (~0.9/s) |
| `mds` instantaneous CPU | 39–43% | 0.0–0.3% |
| Share of total system log volume | **54%** | ~0.3% |

Cumulative CPU over the 24 h uptime: `mds` **36 min** (≈2.5% avg), `mds_stores` **81 min** (≈5.6% avg) — real background work, but nothing like the storm. In the same window [`ecosystemd`](apple-ecosystemd-trust-retry-loop.md) **was** running its loop, so the two are independent and must not be conflated.

风暴是**间歇性**的:换一天、换一次开机后的 60 秒窗口里,`mds` 只有 132 行、CPU 0.0–0.3%,`mdworker.shared` 生成 53 次(风暴时 341 次)。24 小时累计 CPU:`mds` 36 分钟、`mds_stores` 81 分钟 —— 属于真实后台工作,但远非风暴量级。同一窗口里 [`ecosystemd`](apple-ecosystemd-trust-retry-loop.md) 的循环**在跑**,故两者独立,不可混为一谈。

**To file this properly, the storm has to be caught live.** A one-shot `log show` is a lottery; the next step is a polling watcher that snapshots when `mds` lines/sec crosses a threshold.

**要正式提交,必须抓现行。** 单次 `log show` 全靠运气,下一步应做一个按 `mds` 行/秒阈值触发快照的轮询脚本。

### Open lead — user-reported slow indexing / 待查线索:用户反映索引很久不完成

The reporter notes that **Spotlight indexing has recently been taking a very long time to finish**. If true, it would fit the "Spotlight queries CoreDuet per indexed item" hypothesis above — the storm would then be a *symptom* of an indexing run that never settles, and would explain why it is present for hours and then absent entirely.

**This is not corroborated yet.** At the time of writing, `mdutil -s` reports indexing enabled on all volumes but exposes **no progress figure**, and nothing in the current log window shows a stalled or restarting index run. Recorded as a lead to test, **not** as evidence: the next storm capture should be paired with the indexing state at that moment (store size/mtime deltas, `mdbulkimport` activity, `mdworker` spawn rate) before any causal claim is made.

用户反映**最近 Spotlight 索引要跑很久才结束**。若属实,正好契合上面"Spotlight 按条目查询 CoreDuet"的假设 —— 风暴将是"索引迟迟不收敛"的*症状*,也能解释它为何持续数小时后又完全消失。**但目前尚未得到佐证**:`mdutil -s` 只报告索引已启用、不给进度,当前日志窗口里也看不到索引停滞或反复重启的迹象。故记为**待验证线索,而非证据**;下次抓到风暴时应同时记录当刻的索引状态再谈因果。

## Related / 相关

- [ecosystemd trust-evaluation retry loop](apple-ecosystemd-trust-retry-loop.md) — the #3 log emitter in the same capture
- [WindowServer high CPU](apple-windowserver-invalid-window.md) — Spotlight load was explicitly **excluded** as the cause there (`mds+mdworker` = 0.0% during the decisive replicated run)
