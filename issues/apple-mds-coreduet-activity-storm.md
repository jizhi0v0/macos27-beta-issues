# `mds` emits ~2,420 CoreDuet activity log lines/second, continuously
# `mds` 持续以 ~2420 行/秒 刷 CoreDuet activity 日志

> 🔗 **Track / 关注此问题:** *(GitHub issue to be created)*

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

## Related / 相关

- [ecosystemd trust-evaluation retry loop](apple-ecosystemd-trust-retry-loop.md) — the #3 log emitter in the same capture
- [WindowServer high CPU](apple-windowserver-invalid-window.md) — Spotlight load was explicitly **excluded** as the cause there (`mds+mdworker` = 0.0% during the decisive replicated run)
