# MenuBarAgent sustains ~10–14% CPU at idle with a static menu bar
# MenuBarAgent 在静态菜单栏下 idle 空转 ~10–14% CPU

> 🔗 **Track / 关注此问题:** [#12 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/12)

| | |
|---|---|
| **Status** | 🟢 **fix holds on beta6 `26A5416b`** (2026-08-19) — **0.26% cumulative over 2 h 03 m**, and **0.0–0.2%** across five validated quiesced windows. ⚠️ **But the easy case:** Alcove — the app that fed every high reading historically — was **not running**, so this confirms no regression and must **not** be read as an improvement over beta5's 0.57%. The in-use figure (beta5: 1.3%) has **no beta6 counterpart**. See [the beta6 check](#re-check-2026-08-19--beta6-26a5416b--holds-but-in-the-easy-case). Prior: 🟢 **Fix holds on beta5 `26A5406e`** (2026-08-11) — **0.57% cumulative average over 4 h 42 m**, and 1.3% even while the menu bar is being actively used. Holds across beta3 → beta4 → beta5. The high readings were always app-fed (Alcove). The external report [#20](https://github.com/jizhi0v0/macos27-beta-issues/issues/20) is **still not reproduced here** and is now partly explained: see [interaction condition](#the-interaction-condition--and-what-macos-26-says--交互条件与-macos-26-的对照) |
| **macOS** | seen on 27.0 beta2 `26A5368g`; fixed on beta3 `26A5378j`; **fix confirmed to hold on beta4 `26A5388g`** |
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

## What MenuBarAgent actually is / 这个进程到底是什么

Established by inspection on beta5 `26A5406e`, not inferred:

```
CFBundleIdentifier      com.apple.MenuBarAgent
LSMinimumSystemVersion  27.0                      <- explicitly macOS 27+
LSUIElement             true                      <- background agent, no Dock tile
linked private fwks     MenuBarClient, MenuBarClientCore, ControlCenter, SkyLight
launchd                 com.apple.MenuBarAgent.plist — RunAtLoad, KeepAlive
LimitLoadToSessionType  [LoginWindow, Aqua]       <- runs at the login window too
MachServices            com.apple.MenuBarAgent.systemservices
                        com.apple.PreloginSystemBannerService
on-screen window        layer 24, bounds (0,0) 1728x33
```

**It *is* the menu bar.** That 1728×33 window pinned at the origin is the menu-bar strip itself, sitting at layer 24 (Dock is 20, Notification Center 21, Siri 23). And the dependency runs one way: `ControlCenter` links `MenuBarClient`, not the reverse — so on macOS 27 **ControlCenter is a client of MenuBarAgent**, whereas on macOS 26 ControlCenter drew the menu bar itself.

It is also **feature-flagged**. The launchd job carries:

```
"Disabled" => { "#IfFeatureFlagDisabled" => "MenuBar/MenuBarQFA", "#Then" => true }
```

so the whole agent is gated behind a flag named `MenuBar/MenuBarQFA`, implying a switchable new implementation with the old path likely still present. What `QFA` stands for is **unknown** — not documented anywhere found. **This flag has not been touched and should not be**: flipping a system feature flag that owns menu-bar rendering, on a beta, is not a symmetric risk.

### Inferences (labelled as such, not verified)

- **Decoupling menu-bar rendering from ControlCenter's lifecycle** — if ControlCenter hangs or dies, the menu bar survives. This also makes [#22](https://github.com/jizhi0v0/macos27-beta-issues/issues/22) more plausible: a `KeepAlive` process that owns persistent menu-bar compositing state is exactly the shape of thing where state accumulates and a restart clears it.
- **Drawing the menu bar before login** — `LimitLoadToSessionType` includes `LoginWindow` and it vends `PreloginSystemBannerService`, so it appears to have taken over work previously split between loginwindow and SystemUIServer.
- **Probably tied to the new menu-bar appearance** (transparency, wallpaper-derived tinting, notch handling), which needs continuous compositing. **No direct evidence for this one.**

### What this corrects about earlier readings here

The framing that macOS 27 "added a process that eats CPU" is incomplete. MenuBarAgent took over work that lived in **ControlCenter** on macOS 26, so its CPU is not straightforwardly *additional* cost — and measuring either process alone across the two releases compares different workloads. The right comparison is the pair together, under a stated condition.

**MenuBarAgent 就是菜单栏本身** —— 它持有 layer 24 上那个 (0,0)、1728×33 的窗口。依赖方向是单向的:`ControlCenter` 链接 `MenuBarClient`,反之不成立,即 **27 上 ControlCenter 是它的客户端**,而 26 上菜单栏由 ControlCenter 自己画。它由 launchd `RunAtLoad`+`KeepAlive` 拉起,**在登录窗口会话中也运行**,并提供 `PreloginSystemBannerService`(登录前系统横幅)。整个 agent 挂在 feature flag **`MenuBar/MenuBarQFA`** 下,说明是可切换的新实现;`QFA` 含义未知。**该 flag 未动过,也不建议动** —— 在 beta 上关掉菜单栏实现,风险不对称。**推断(未验证)**:把菜单栏渲染与 ControlCenter 的生命周期解耦(这也让 #22"状态累积、重启即清"更说得通)、接管登录前菜单栏、可能与新的菜单栏视觉有关。**由此更正**:"27 多了个进程吃 CPU"这个读法不完整 —— 它接手的是 26 上属于 ControlCenter 的活,单独比较任一进程的百分比都不是同一份工作量。

## The interaction condition — and what macOS 26 says / 交互条件与 macOS 26 的对照

Every measurement in this file before 2026-08-11 was taken on a **static, untouched** menu bar. The external report [#20](https://github.com/jizhi0v0/macos27-beta-issues/issues/20) says something different in its very title — *"when **interacting** with the top panel"* — and reports **MenuBarAgent 20–70%** plus **ControlCenter ~45%**. Those two conditions had never been compared, which is why the note below said #20 was "unexplained by anything observed here": **the condition it describes had simply never been measured.**

Measured 2026-08-11 on beta5 `26A5406e` (M3 Max MBP), two back-to-back 60 s windows, cumulative `utime+stime` deltas:

| | menu bar untouched | menu bar actively used |
|---|---|---|
| **MenuBarAgent** | 0.3% | **1.3%** |
| **ControlCenter** | 2.1% | **33.5%** |

So on this machine the interaction condition costs **ControlCenter** a great deal and **MenuBarAgent** almost nothing.

### Is ControlCenter's 33.5% a regression? No — macOS 26 costs the same or more

Cross-checked against a **macOS 26.6 `25G72`** machine (Mac16,10, M4 mini) over SSH, same script, same two conditions:

| | ControlCenter untouched | ControlCenter in use | delta |
|---|---|---|---|
| **macOS 26.6** (M4 mini) | 0.5% | **36.4%** | **+35.9** |
| **macOS 27 beta5** (M3 Max MBP) | 2.1% | **33.5%** | **+31.4** |

**macOS 26's interaction cost is slightly *higher*.** Driving the Control Center costs ~30–36% CPU on both releases — that is the intrinsic cost of a live, continuously-redrawing control, not something the beta introduced. #20's ~45% for ControlCenter therefore reads as **normal cost for that action**, and the apparent contradiction with this issue's 0.0–0.1% figures is entirely a condition mismatch (a ~16× swing).

**Caveats, stated rather than buried:** different hardware on each side; interaction vigour was not standardised, so the 36.4 vs 33.5 gap must **not** be read as "26 is more expensive"; the mini had a UURemote screen-sharing session active in *both* windows (it largely cancels in the delta, but if capture cost scales with how much the screen is changing, the mini's delta is inflated); and each cell is a single 60 s window.

### Structural finding: MenuBarAgent does not exist on macOS 26

`MenuBarAgent.app` is **absent** from macOS 26.6 — `/System/Library/CoreServices/MenuBarAgent.app` does not exist and a search of `/System`, `/usr/libexec` and `/Library` returns nothing. It is present on macOS 27. On macOS 26 the menu bar is driven by **ControlCenter** itself.

Two consequences: **(a)** there is no macOS 26 baseline for MenuBarAgent, so its cost on 27 can never be compared like-for-like; **(b)** comparing "ControlCenter CPU" across the two releases is not comparing the same workload, since work that lives in MenuBarAgent on 27 is inside ControlCenter on 26.

### What is still unexplained

**#20's MenuBarAgent 20–70% is not reproduced here under either condition** — 0.3% untouched, 1.3% in use, a 46× gap from their figure. Hardware dependence remains possible but is **untested and unevidenced**; simpler explanations have not been exhausted (their build was beta3 `26A5378j`, three builds back; menu-bar app population; external display). Those are the details worth asking them for.

2026-08-11 补测:本文此前所有数据都测于**静止、无人操作**的菜单栏,而 #20 标题写的是 *"when **interacting** with the top panel"* —— 两个条件从未被放在一起比较过,这正是"该外部报告无法用本机观测解释"的原因:**它描述的条件我们根本没测过。** 实测 beta5:菜单栏被操作时 **ControlCenter 2.1% → 33.5%**,而 **MenuBarAgent 仅 0.3% → 1.3%**。再以 **macOS 26.6**(M4 mini)对照:**0.5% → 36.4%**,**增量比 macOS 27 还略高** —— 说明操作控制中心吃 30%+ CPU 是该控件的固有成本,**不是 beta 回归**,#20 报的 ~45% 属正常范围。另一结构性事实:**`MenuBarAgent` 在 macOS 26 上不存在**,菜单栏由 ControlCenter 自己驱动,故 (a) MenuBarAgent 无跨版本基线可比,(b) 跨版本比较 ControlCenter 的百分比也不是同一份工作量。**仍未解释的是 #20 的 MenuBarAgent 20–70%** —— 本机两种条件下都复现不出(相差 46 倍),机型相关性有可能但**未经验证**,更简单的解释(他用的是三个 build 之前的 beta3、菜单栏第三方 app、外接显示器)尚未排除。

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

## Retest 2026-07-25 — beta4 `26A5388g` — FIX HOLDS, high readings were Alcove-fed

The 2026-07-20 downgrade is resolved. Measured during the [WindowServer](apple-windowserver-invalid-window.md) beta4 investigation, which produced exactly the unattended, app-free conditions this issue's "valid retest" section asked for — the measuring scripts are `disown`ed, so the Claude app (the structural blocker documented above) was **quit** during every reading.

| Condition | MenuBarAgent |
|---|---|
| Alcove + Klack + Surge + apps running | 21.9% / 20.3% / 21.4% |
| **Alcove quit** | **1.6% / 1.9%** |
| All menu-bar apps quit, desktop idle | **0.1% / 0.0%** |

**The ~22% was fed by Alcove**, a notch/Dynamic-Island menu-bar app — not MenuBarAgent's own spin. With nothing feeding it, MenuBarAgent sits at 0.0–0.1%, consistent with the 0.28% idle figure that established the beta3 fix, and nowhere near the beta2 ~10–14% floor.

This also matches the original beta2 isolation logic in reverse: back then, removing every status-item updater did **not** move the number (that was the regression); on beta4, removing one menu-bar app moves it from 21.9% to 1.6%, i.e. the cost now tracks its clients as it should.

**Corollary for [#3](apple-windowserver-invalid-window.md):** MenuBarAgent's 21.9% → 0.1% swing produced **no** reduction in WindowServer (44.8% → 49.3% → 52.3%), which falsified the hypothesis that menu-bar compositing drives the WindowServer floor. Recorded here so that lead is not re-walked.

Caveat: this is a single session's readings on `26A5388g`, and `26A5378n` was never separately re-measured — the build moved on before that could happen. The external report [#20](https://github.com/jizhi0v0/macos27-beta-issues/issues/20) remains unexplained by anything observed here; see below.

### Note on the external report / 关于外部报告

#20 is **not** [#21](apple-controlcenter-volume-rmw-race.md) — that reporter's logs contain **zero** `systemBanners` lines. It is also not reproducible here: matching their conditions (5 real desktops = `bars=5`, Telegram running, 8× Control Center open/close) produced MenuBarAgent 4.71% / ControlCenter 2.65%, with **zero** `controlcenter-<UUID>` scene fan-out and **zero** `NSSceneFenceAction` — the two signatures that dominate their trace. And `26A5378j` alone cannot explain it: this machine ran `…j` for 7 days at 0.28% with no stutter. Whatever they are hitting is environmental.

## Re-check 2026-08-19 — beta6 `26A5416b` — holds, but in the easy case

| | beta5 `26A5406e` | **beta6 `26A5416b`** |
|---|---|---|
| cumulative idle average | 0.57 % over 4 h 42 m | **0.26 % over 2 h 03 m** (18.9 s CPU / 7,402 s) |
| quiesced windows | — | **0.0 – 0.2 %** across five 122 s windows |
| while the menu bar is in use | 1.3 % | **not measured** |

The idle windows come free with [`tools/ws-idle-baseline.sh`](../tools/ws-idle-baseline.sh),
which reports MenuBarAgent alongside WindowServer; all five runs of it today, at both 60 Hz and
120 Hz and with window counts from 1 to 13, put MenuBarAgent at 0.0–0.2 %. A separate paired A/B
that restarted the daemon read 0.0 % before and 0.1 % after.

**The condition was easier than beta5's, and that limits the claim.** This file's own finding is
that the high readings were always app-fed, with **Alcove** the identified driver (~22 % → 0.0–0.1 %
when quit). Alcove was **not running** at any point today. So beta6 was measured without the one
app known to drive this metric, which makes 0.26 % evidence of *no regression* and **not**
evidence of improvement over beta5's 0.57 %. A like-for-like re-test needs Alcove launched — which
is also the state [#21](apple-controlcenter-volume-rmw-race.md) requires, so both can be done in
one sitting.

2026-08-19 在 beta6 复核:空闲累计 **0.26%**(2 小时 03 分),五个静置窗口 **0.0–0.2%**。⚠️ 但**条件比 beta5 宽松** ——
历史上把这个数推高的 **Alcove 今天全程没运行**,所以这只能说明"没有回归",**不能**当作相对 beta5(0.57%)的改善;
"使用中"那个数(beta5 为 1.3%)在 beta6 上**没有测**。要做同条件复测需先启动 Alcove。
