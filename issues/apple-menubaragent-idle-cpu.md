# MenuBarAgent sustains ~10–14% CPU at idle with a static menu bar
# MenuBarAgent 在静态菜单栏下 idle 空转 ~10–14% CPU

> 🔗 **Track / 关注此问题:** [#12 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/12)

| | |
|---|---|
| **Status** | ⚪ **NEEDS RETEST on `26A5378n`** — was 🟢 FIXED on beta3 `26A5378j` (was ✅ CONFIRMED beta2 regression). See [Status downgraded](#status-downgraded-2026-07-20--状态降级) |
| **macOS** | seen on 27.0 beta2 `26A5368g`; fixed on beta3 `26A5378j`; **unverified on `26A5378n`** |
| **Component** | Apple **MenuBarAgent** (`/System/Library/CoreServices/MenuBarAgent.app`, the macOS 27 menu-bar agent) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max, single internal display |
| **Report** | Apple Feedback: **`FB23411741`** (filed 2026-06-26, Menu Bar → Incorrect/Unexpected Behavior; sysdiagnose + idle `sample` capture attached) |

## Symptom / 症状

`MenuBarAgent` (PID 702) holds **~10–14% CPU sustained** even when no menu-bar app is updating its status item. Cumulative TIME climbs steadily.

`MenuBarAgent` 持续吃 ~10–14% CPU,即使没有任何菜单栏 app 在更新状态项;累计 TIME 稳涨。

## How it was isolated / 怎么排除到它

Removed every known live status-item updater and re-measured — MenuBarAgent did **not** drop:
- Quit Macs Fan Control (live temp/RPM text).
- Set Surge to icon-only (stopped its per-second network-speed text).
- The chatty `ClaudeUsageMenuBar` was fixed (status-item redraws 4→0 at idle, verified) and even its fixed build running doesn't move the number.
- `log show --last 20s` for `StatusItem`/`NSStatusBar`/`drawWithFrame`/`_updateReplicants` → **0 lines** (no app is redrawing the menu bar).

Yet MenuBarAgent stays ~10–14%. With zero menu-bar redraw activity feeding it, the cost is MenuBarAgent's own.

## Evidence / 证据

`sample MenuBarAgent 3`, idle, top-of-stack:
- Mostly parked in `mach_msg2_trap` / `__workq_kernreturn` (receiving messages), BUT with a continuous trickle of small Swift work: `swift_cvw_initWithCopyImpl`, `swift_cvw_destroyImpl`, `Hasher.combine(bytes:)`, `swift_retain`, `_platform_memmove`, tiny mallocs.
- I.e. it's **processing a steady stream of small messages/value-copies at idle**, not pegged on one hot function and not driven by a visible status-item redraw.

## Open question / 未解

The **sender** of that continuous message stream is not identified from MenuBarAgent's side — something keeps handing it small work. Could be a system component re-registering menu-bar state, or a still-running (but non-logging) menu-bar client. A full sysdiagnose / XPC-connection inspection would be needed to name the source.

## Workaround / 临时规避

None app-side that fully clears it (it persists with menu-bar apps removed). Reducing the number of menu-bar items / using less chatty ones lowers the *additional* load on top of this baseline but doesn't remove the ~10–14% floor. Beta regression — expect a fix in a later beta.

## Notes / 备注

- Distinct from [WindowServer high CPU](apple-windowserver-invalid-window.md): that is broader CoreAnimation compositing (dominated by live-rendering apps); MenuBarAgent's ~10–14% is its own process and only a partial contributor to WindowServer.
- Consistent across many measurements this session (~12–14%), independent of which apps are running → reads as a macOS 27 beta2 baseline, not app-fed.
- **Strongest confirmation:** after the user quit nearly all menu-bar apps (only system `ControlCenter` + a couple icon-only items left, `log show` showing **0** status-item redraws), MenuBarAgent still held **12.5%**. With essentially nothing feeding it, the cost is MenuBarAgent's own — confirms a genuine beta2 regression rather than app-driven load.

## Retest on beta3 `26A5378j` (2026-07-07) — FIXED / 已修

Re-measured on beta3 (installed 07:54, booted 07:53). MenuBarAgent (PID 1172) reads **0.0% CPU** in a `top -l 2` sample, and — the metric that can't be gamed — **43.5 s of cumulative CPU TIME over 2h35m of uptime (≈0.28% average)**. On beta2 the ~10–14% floor would have burned roughly **18+ minutes** of CPU in the same span. So the idle spin is gone: this is a real fix in beta3, not a quiet moment. No Feedback follow-up needed beyond noting the fix on [FB23411741](https://feedbackassistant.apple.com/feedback/23411741).

## Status downgraded (2026-07-20) — needs retest on `26A5378n` / 状态降级

The 🟢 FIXED verdict above was measured **only on `26A5378j`**. This machine moved to `26A5378n` on 2026-07-14 and MenuBarAgent has **never been re-measured on it**. Two things prompted the downgrade:

1. **An external report ([#20](https://github.com/jizhi0v0/macos27-beta-issues/issues/20)) claims MenuBarAgent is not fixed** — ~60% CPU, on `26A5378j`, the *same build* this issue was closed against.
2. **Casual readings here on `26A5378n` came back far above 0.28%.**

### Why today's numbers do NOT settle it / 今天的数字为何不作数

Measurements taken 2026-07-20, in order, with the confound that invalidated each:

| Measurement | Result | Why it does not count |
|---|---|---|
| Cumulative over 3 h uptime | 2.28% | Window contained two [#21](apple-controlcenter-volume-rmw-race.md) volume runaways, which drive MenuBarAgent to **18,000 log lines/min** via `systemBanners` |
| 60 s, apps open | 4.83% | Machine not idle |
| 480 s, user apps quit | 4.93% | Surge still showing per-second network-speed text — the exact confound the original isolation removed |
| 480 s, Surge set to icon-only | **4.79%** | **WindowServer at 46%** and `ClaudeUsageMenuBar` at 9.2%; system-wide load, not an idle machine |
| 120 s, 5 desktops | 4.71% | same |

**The blocker is structural:** every measurement was taken from an agent running inside a heavyweight Electron app, which by itself accounts for ~77% CPU across two processes plus the WindowServer compositing load. **The measuring process is the largest perturbation on the machine.** No number taken this way is comparable to the 0.28% idle figure.

以上所有读数都是在 Claude 桌面端运行期间取得的,该 app 自身加上它引起的 WindowServer 合成开销就是机器上最大的负载源 —— **测量进程本身就是最大的扰动**,因此没有一个数字能与 0.28% 的空闲基线相比。

### What a valid retest needs / 有效复测的条件

Log cumulative CPU TIME unattended and analyse the quiet stretches afterwards, rather than measuring live:

```sh
while :; do
  printf '%s %s\n' "$(date +%s)" "$(ps -o time= -p $(pgrep -x MenuBarAgent) | tr -d ' ')"
  sleep 60
done >> ~/mba-cpu.log
```

Then pick a window where the user was away **and the Claude app was closed**, and compute the slope. Log `WindowServer` and any live-updating menu-bar app alongside it so periods polluted by system-wide load can be excluded. Match the original isolation: Surge icon-only, no chatty status items.

### Note on the external report / 关于外部报告

#20 is **not** [#21](apple-controlcenter-volume-rmw-race.md) — that reporter's logs contain **zero** `systemBanners` lines. It is also not reproducible here: matching their conditions (5 real desktops = `bars=5`, Telegram running, 8× Control Center open/close) produced MenuBarAgent 4.71% / ControlCenter 2.65%, with **zero** `controlcenter-<UUID>` scene fan-out and **zero** `NSSceneFenceAction` — the two signatures that dominate their trace. And `26A5378j` alone cannot explain it: this machine ran `…j` for 7 days at 0.28% with no stutter. Whatever they are hitting is environmental.
