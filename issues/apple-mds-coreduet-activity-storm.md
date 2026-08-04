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

### Post-boot hypothesis — tested against the log archive and NOT supported / "开机后持续很久"假设:查历史日志,不成立

The reporter's recollection was that the heavy period usually **runs for a long time after a reboot**, while Spotlight *search itself* keeps working normally. The first storm capture fit that shape — it was taken at ~3.5 h uptime. So the hypothesis was: this is a post-boot indexing run that floods for hours and then settles.

**Tested directly against the unified log for the 2026-08-03 10:00:33 boot** (`mds` CoreDuet activity lines per 60 s window):

| Window | Uptime at window | `mds` CoreDuet lines / 60 s |
|---|---|---|
| 08-03 10:05 | +4 min | **0** |
| 08-03 10:30 | +30 min | **0** |
| 08-03 11:00 | +1 h | **0** |
| 08-03 13:00 | +3 h | **0** ← same uptime as the storm capture |
| 08-03 16:00 | +6 h | **0** |
| 08-03 22:00 | +12 h | 64 |

**Not a silent zero:** in the same windows `mds` *was* logging other messages (2 lines/60 s at 11:00, 70 at 22:00), so the query and retention are sound — `mds` simply was not emitting the CoreDuet activity message at all. Compare the storm: **145,241 lines/60 s**.

**Conclusion: uptime-since-boot does not predict the storm.** The 3-hour mark of this boot — the same uptime at which the storm was captured on 07-25 — is completely silent. Whatever triggers it, it is not "every boot re-indexes and floods for hours." The trigger remains unidentified.

Consistent with this: the reporter reports **Spotlight search results stay correct and usable** throughout, which argues against a broken or perpetually-restarting index and in favour of a chatty-but-functional path.

用户的印象是"重启后会持续很久",而搜索本身一直正常;首次抓到风暴时正好是开机约 3.5 小时,与该印象吻合。**但直接查 2026-08-03 那次开机的历史日志:开机后 4 分钟、30 分钟、1 小时、3 小时、6 小时的窗口里,`mds` 的 CoreDuet 行数全为 0**(同期 `mds` 仍在写其它日志,故 0 是真 0,不是查询或保留期造成的假阴性),12 小时窗口也仅 64 行 —— 对比风暴时的 145,241 行/60 秒。**结论:开机时长不能预测风暴的发生**,尤其是与首次抓到风暴相同的 3 小时节点完全安静。触发条件仍未定位。用户反映搜索结果始终正常可用,这也不支持"索引损坏/反复重启"的解释。

### Catching it live / 如何抓现行

Because uptime doesn't predict it and a one-shot `log show` is a lottery, use the watcher:

```sh
bash tools/mds-storm-watch.sh        # stops after the first burst it catches
bash tools/mds-storm-watch.sh -k     # keeps watching, one snapshot per burst
```

It probes `mds`'s CoreDuet rate every 60 s (idle ≈2/s, storm ≈2,420/s; trigger defaults to 300/s) and only then takes the full snapshot: a 60 s log capture, top emitters, per-second `mds` rate (continuous vs bursty), `mdworker.shared` spawn count, **cumulative-CPU deltas** for `mds`/`mds_stores`/`contextstored`, and — the piece missing from every capture so far — **`mdutil -as` and the Spotlight process state both before and after the window**, so the next storm can finally be paired with the indexing state at that moment. Output lands in `/tmp/mds-storm/<timestamp>/`.

由于开机时长无法预测该风暴、单次 `log show` 全靠运气,改用触发式监控:每 60 秒探测 `mds` 的 CoreDuet 速率(空闲 ≈2/s,风暴 ≈2420/s,默认阈值 300/s),越阈值才做完整快照 —— 含 60 秒日志、头号日志来源、每秒速率(判断持续还是爆发)、`mdworker.shared` 生成次数、`mds`/`mds_stores`/`contextstored` 的**累计 CPU 增量**,以及此前每次抓取都缺的一环:**窗口前后各一次 `mdutil -as` 与 Spotlight 进程状态**,以便下次终于能把风暴与当刻索引状态对上。


## Related / 相关

- [ecosystemd trust-evaluation retry loop](apple-ecosystemd-trust-retry-loop.md) — the #3 log emitter in the same capture
- [WindowServer high CPU](apple-windowserver-invalid-window.md) — Spotlight load was explicitly **excluded** as the cause there (`mds+mdworker` = 0.0% during the decisive replicated run)
