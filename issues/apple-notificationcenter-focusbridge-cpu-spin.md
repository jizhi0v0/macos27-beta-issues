# `NotificationCenter.app`'s main thread spins at ~100% CPU inside SwiftUI's focus-chain walk when a banner presents — a true beachball, self-heals in neither 15 nor 33 minutes
# `NotificationCenter.app` 主线程在 SwiftUI 的 focus-chain 遍历里空转到 ~100% CPU——真正的彩虹转圈，15 分钟乃至 33 分钟都不会自愈

> 🔗 **Track / 关注此问题:** [#29 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/29)
>
> 🧭 **Landed here from "clicking a notification does nothing"?** This is **not** one of the three shapes in [notification-click-failure-taxonomy.md](notification-click-failure-taxonomy.md) — those are all about a click being silently dropped somewhere in the `usernoted` pipeline while the UI stays responsive. This is the opposite failure: `NotificationCenter.app` itself is pegged at 100% CPU and visibly spinning. See [Why this is not #26 or #27](#why-this-is-not-26-or-27--为什么不是-26-或-27) below.

| | |
|---|---|
| **Status** | 🔴 **not caught on 27.2 beta2 `26B5091g`, which decides nothing** (2026-09-25) — no NotificationCenter `cpu_resource` report since the install, and **61.5 s** of total CPU over 2 h 05 m of uptime (**0.8%** average; 3.9% over one 120 s sample). release caught it once in 5.5 days; two hours cannot rule it in or out. See [`../baselines/27.2-beta2-26B5091g/`](../baselines/27.2-beta2-26B5091g/README.md). Prior: 🔴 **caught live on release `26A428`, same stack** (2026-09-16) — the OS wrote its own `cpu_resource` report (**97% CPU over 93 s**, heaviest stack `FocusBridge.invalidateKeyViewLoop()` → `updateDefaultKeyViewLoop()` → `KeyViewProxyCache.createOrUpdateProxyView(_:)`), and independently **100.2%** over a 120 s cumulative sample with **5,063 / 5,063** main-thread `sample` frames inside `FocusBridge.invalidateKeyViewLoop()`. Spun for **≥ 10 min 44 s** until a manual `killall`; no self-recovery in that interval. The banners presented around onset came from a HomeKit app and Claude, not the menu-bar app of the first capture — but the report's interval opens 0.24 s *before* the nearest `Presenting` record, so which banner (if any) set it off is not pinned. The reporter again describes a notification arriving with the pointer nearby; still not verifiable from logs. See [`baselines/release-26A428/`](../baselines/release-26A428/README.md). Prior: 🔴 **Open — not caught on beta8 `26A5425a`** (2026-09-03) — 0.0% CPU over both a 30 s and a 120 s sample. The spin is intermittent and has to be caught live, so **absence here is not evidence of a fix**. Prior: 🔴 **Open, not yet filed.** First captured with a live, symbolicated stuck stack on 2026-08-22. Caught by chance while investigating a live report of the spinning-wait-cursor ("beachball") symptom — this is the first time this investigation has had a CPU/stack signature for a notification-adjacent hang, rather than only `usernoted` log-line counts |
| **macOS** | 27.0 beta6 `26A5416b` |
| **Component** | Apple `NotificationCenter.app` (`com.apple.notificationcenterui` 1.0, build `1674.0.7.0.400`) — AppKit/SwiftUI interop, specifically `SwiftUI`'s `FocusBridge` / `KeyViewProxyCache` |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max |
| **Report** | not yet filed — no reproduction recipe exists, this is a single capture |

## Symptom / 症状

Reporter's own words: **"又卡住了，转彩虹，似乎是通知刚好准备弹出的时候，鼠标在附近有一些手势导致的"** — stuck again, spinning rainbow cursor, seemingly triggered by a mouse gesture near where a notification was just about to pop up.

Confirmed **local, not global**: the beachball only shows up interacting with the notification / that window; other apps' windows kept accepting clicks and typing normally throughout. This rules out a system-wide WindowServer stall like [#3](apple-windowserver-invalid-window.md) — the machine as a whole stayed usable.

## Why this is not #26 or #27 / 为什么不是 #26 或 #27

Both existing notification issues are characterized entirely from `usernoted`'s log — a click either does or doesn't show up there, and in both cases the UI itself is not doing anything abnormal. This capture is the opposite: `NotificationCenter.app`'s **own main thread** is the thing spinning, at ~100% CPU, doing real (if useless) work.

[#27](notification-banner-inert-except-close.md) explicitly ruled this out for *its* episodes — its write-up states `NotificationCenter.app` "sampled clean — main thread parked in its normal `nextEventMatchingMask` event loop … zero blocking calls" during a #27 freeze. Here the opposite is true: two samples 90 s apart are **100% identical, pegged stack**, and CPU never dropped below ~98% across a 15-minute unattended poll. So whatever this is, it is not #27's mechanism, and it is not #26's either (that one is `usernoted` ↔ Chrome's Alerts helper; nothing here touches either). This is a **fourth, distinct failure shape** — not yet added to the taxonomy index pending a second occurrence.

## Timeline / 时间线

| time | event |
|---|---|
| 16:32:02.325857 | `usernoted` logs `Presenting <NotificationRecord app:"com.jizhi0v0.claude-usage.menubar" ident:"3F1F-52B8" … category:"CLAUDE_SESSION"> as banner` — this is the notification the reporter says was mid-animation when the mouse gesture happened |
| 16:32:23 | first `sample NotificationCenter 3` (pid 95926): **1798/1798** samples in one identical stuck stack |
| 16:34:13 | second `sample`, 90 s later: **same stack**, still ~99% CPU — proves a sustained loop, not a coincidence of sampling the same code path twice |
| 16:35:27 – 16:50:24 | unattended poll, every 5 s: **NotificationCenter 98–101% CPU at every single sample**, WindowServer fluctuating 24–99% alongside it (compositing cost of the churn, not itself stuck — see below); recovery threshold (<15%) never hit before the poll's 15-minute cap expired |
| 16:50:52 | still 100.0% CPU, confirmed live |
| 17:05:17 | `killall NotificationCenter` issued — **33 min 15 s after `Presenting`, no self-recovery ever observed** |
| 17:05:19 | new `NotificationCenter` process (pid 20348) up; 4 s later settled to **0.1% CPU** |

This is a materially different recovery profile from #26 and #27, both of which self-heal (unpredictably, but observed within 2–16 minutes in every prior capture). Whether this one would eventually have self-healed past 33 minutes is unknown — it was killed rather than left to find out, on the reporter's own call.

## The stuck stack / 卡死的调用栈

Two `sample NotificationCenter.app <pid> 3` captures, 90 seconds apart, both **100% of samples in the same frames**. All the way from the run loop down to a display-cycle commit:

```
-[NSApplication run]
  → _DPSNextEvent → __CFRunLoopRun → __CFMachPortPerform
  → UC::DriverCore::continueProcessing()          (UpdateCycle)
  → stepTransactionFlush                          (AppKit)
  → CA::Transaction::flush() / commit()           (QuartzCore)
  → NSDisplayCycleFlush → -[NSWindow layoutIfNeeded]
  → -[NSView layoutSubtreeIfNeeded] (several nested NSPerformVisuallyAtomicChange layers)
  → NSHostingView.layout()                        (SwiftUI)
  → ViewGraphRootValueUpdater.render(...)         (SwiftUICore)
  → ViewGraph.updateOutputs(at:)
  → NSHostingView.preferencesDidChange()
  → FocusBridge.preferencesDidChange(_:)
  → FocusBridge.invalidateKeyViewLoop()
```

and from there the 1798/1798 samples split across two overlapping SwiftUI-internal frames doing the same underlying work:

```
FocusBridge.updateDefaultKeyViewLoop()             — 1175/1798
KeyViewProxyCache.createOrUpdateProxyView(_:)      — 1164/1798
  → configureProxy(_:for:) → layoutProxy(_:) → container(for:) → rootContainer(for:)
  → BaseFocusResponder.enclosingScrollView.getter
  → ResponderNode.firstAncestor<A>(ofType:)         (SwiftUICore)
  → Sequence.first<A>(ofType:)
  → UnfoldSequence.next()  ⇄  swift_dynamicCast / tryCastToSwiftClass /
    swift_getGenericMetadata / LockingConcurrentMap::getOrInsert / swift_retain / swift_release
```

Reading this: every focus/key-view invalidation re-walks the window's responder chain from scratch, via `firstAncestor(ofType:)` implemented as a lazy `UnfoldSequence` — and each step of that walk pays full generic-metadata-cache-lookup and dynamic-cast overhead rather than a cheap pointer chase. That alone would just be *slow*, not stuck; what makes it a hang is that `preferencesDidChange()` → `invalidateKeyViewLoop()` is being re-entered continuously (the two SwiftUI frames above are siblings under the same parent, both saturated), consistent with each pass invalidating the state that triggers the next pass — i.e. the loop is regenerating its own invalidation, not merely walking a long chain once.

**Not measured, stated as open questions rather than conclusions:**
- Whether the responder/key-view chain it is walking is unusually long, or cyclic (a cycle would make `firstAncestor` never terminate on its own, matching "no self-recovery in 33 minutes" better than a merely-long-but-finite chain would);
- Whether the specific `CLAUDE_SESSION`-category banner (or its being a *third-party* menu-bar-app notification, distinct from Chrome/Reminders/WeChat which is what #26/#27 were captured on) has anything to do with triggering it, or whether any banner would have done;
- **The mouse-gesture correlation is the reporter's own real-time perception, not confirmed from logs.** A check of the unified log around `16:31:55`–`16:32:15` for HID/gesture activity found nothing — ordinary mouse movement and trackpad gestures are not logged at this level by default, so their absence from the log is expected and proves nothing either way. The only independently-verified fact is the *timing* coincidence: the stuck stack's entry point is a focus/key-view-loop invalidation, which is exactly the kind of thing hover/mouse-move-driven focus changes would trigger, but no causal mechanism was traced from an actual input event to `invalidateKeyViewLoop()`.

## WindowServer's role / WindowServer 的角色

WindowServer ran elevated the whole time (24–99% across the 15-minute poll, no stable floor) but was **not itself sampled** — its fluctuation looks like it is doing real compositing work reacting to `NotificationCenter`'s continuous `CATransaction` commits, not that it is independently stuck; the beachball being confirmed *local* (other apps stayed interactive) is consistent with WindowServer still servicing everyone else normally. This is a hypothesis, not a measured claim — no `sudo sample WindowServer` was taken (needs `sudo`, not available non-interactively in this session).

## Recovery / 恢复方法

**`killall NotificationCenter`** — immediate, clean, the system relaunches it automatically (new PID within ~2 s, settled to <1% CPU within another ~4 s). No side effects observed.

⚠️ **This is the opposite finding from #26's own falsification table**, which recorded `killall NotificationCenter` as having **no effect** there. That is not a contradiction — in #26 the broken state lives in `usernoted` and Chrome's Alerts helper, neither of which `NotificationCenter.app` restarting touches. Here, `NotificationCenter.app` **is** the broken process, so restarting it is a direct fix rather than a shot in the dark. The same command means something different depending on which of these shapes you're looking at — check which process is actually pegged before reaching for a remedy.

## Open questions / 待定

1. Is the underlying walk over a genuinely cyclic structure (would explain unbounded non-recovery) or just a very long one that happens to regenerate its own invalidation? Would need a heap/object-graph inspection of the responder chain mid-hang, not attempted here.
2. Does any notification banner trigger this, or specifically ones from certain apps/categories? n=1 so far.
3. Was the mouse gesture actually causal, or did the reporter's gesture happen to land in the same window the notification was invalidating anyway? No independent confirmation either way.
4. Does this reproduce on macOS 26.6? Untested.
5. Would it ever have self-recovered past 33 minutes? Unknown — it was killed rather than observed further, on the reporter's call, to restore usability.
6. Relationship to #27 open question 3 ("is #26 and #27 the same root cause seen through two presentations?") — this capture adds a plausible **third** presentation (SwiftUI focus-chain hang) to that same family of "something about banners breaks", but with a CPU signature strong enough that it should probably be treated as independent until shown otherwise.

## Re-verification 2026-09-03 — beta8 `26A5425a` — not caught; absence is not evidence

> **Clock position, because it decides what these numbers can be compared to.** beta8
> `26A5425a` was installed **2026-09-02 04:57:15** (`InstallHistory.plist`). Every figure below
> was taken at **T+21h20m** on the 2026-09-02 12:55:26 boot — a **steady-state** window, not the
> post-boot window beta6 (T+9m) and beta7 (T+0→8m) used. Log *volumes* are therefore **not**
> matched pairs with those builds and are not presented as such. Kernel unchanged for a third
> beta: `xnu-13432.1.9~3`. Raw capture: [`baselines/beta8-26A5425a/`](../baselines/beta8-26A5425a/README.md).

`NotificationCenter` measured **0.0%** CPU over both a 30-second and a 120-second cumulative
utime+stime sample (not `ps %cpu`, which decays and has reported 0.0% for a process provably
burning 12%). It emitted 5,030 log records in the 10-minute window, i.e. it was alive and
working, simply not spinning.

**This is not a fix signal and the status stays 🔴.** The spin was originally caught live and
identified by two captures 90 seconds apart showing the *identical* stuck stack
(`FocusBridge.updateDefaultKeyViewLoop()`); it is intermittent, and a sample taken at an
arbitrary moment says nothing about whether the state can still be entered. Closing it needs
either a positive signal (a period of use that provably would have triggered it before) or a
source-level argument — not a quiet sample.

2026-09-03 beta8 复测:两次采样(30 秒与 120 秒累计 utime+stime 增量,**不是** `ps %cpu` ——
后者是衰减平均,曾对实际烧 12% 的进程报 0.0%)均为 **0.0%**;同期它在 10 分钟窗口内发出 5,030 条日志,
说明进程活着、只是没在空转。**这不是修复信号,状态维持 🔴** —— 该 spin 本就是间歇性的,
当初是抓现行、靠相隔 90 秒的两次采样拿到**完全相同**的卡住栈才定位的。要关闭它需要正向信号或源码级论证,
而不是一次安静的采样。

## Re-verification 2026-09-16 — release `26A428` — caught live, same stack

> **Clock position, because it decides what these numbers can be compared to.** The release
> build `26A428` was installed **2026-09-11 04:28:46** (`InstallHistory.plist`). Every figure below
> was taken at **T+6h29m** on the 2026-09-16 11:40:46 boot with ~40 apps running — matched neither
> to beta8's T+21h20m window nor to beta6/beta7's post-boot windows, so log *volumes* are not
> presented as pairs. Kernel `xnu-13432.1.9~1` (beta6–beta8: `~3`). Raw capture:
> [`baselines/release-26A428/`](../baselines/release-26A428/README.md).

**Caught live on the shipped build.** Nothing was done to provoke it; the machine was in ordinary
use. Full timeline and excerpts: [`notificationcenter-spin.txt`](../baselines/release-26A428/notificationcenter-spin.txt).

| evidence | result |
|---|---|
| OS `cpu_resource` report, 18:14:19.8 → 18:15:52.4 | **90 s CPU over 93 s (97%)**, limit 50% over 180 s |
| its heaviest stack (32 of 96 microstackshot steps) | `NSHostingView.preferencesDidChange()` → `FocusBridge.preferencesDidChange(_:)` → `invalidateKeyViewLoop()` → `updateDefaultKeyViewLoop()` → `KeyViewProxyCache.createOrUpdateProxyView(_:)` → `configureProxy(_:for:)` → `layoutProxy(_:)` → `ResponderNode.firstAncestor(ofType:)` → `UnfoldSequence.next()` |
| cumulative utime+stime, 18:22:06 → 18:24:06 | **100.2%** |
| `/usr/bin/sample` 10 s at 18:21:14, main thread | **5,063 / 5,063** samples inside `FocusBridge.invalidateKeyViewLoop()`; 3,196 + 1,589 in `updateDefaultKeyViewLoop()` |
| top of stack | Swift runtime overhead — `swift_getEnumCaseMultiPayload`, refcount slow paths, `tryCastToSwiftClass`, `objc_msgSend` |
| end | `killall` at 18:25:04.258; every XPC peer logs pid 846 exited at .262; launchd `service inactive` at .274; respawned at 0.0% |

This is the same `preferencesDidChange()` → `invalidateKeyViewLoop()` → `updateDefaultKeyViewLoop()`
chain as the 2026-08-22 capture. Spin duration observed **≥ 10 min 44 s**,
ended by hand. Shipping did not fix it, and the beta8 "not caught" reading was, as recorded then, just
a quiet sample.

**What this capture adds to the open questions.**

- *Q2, does any banner trigger it?* The `Presenting` records nearest onset were
  `com.lumiunited.pre.homekit` (18:11:57, 18:14:20.092) and `com.anthropic.claudefordesktop` (18:14:45),
  with `com.nssurge.surge-mac` at 18:11:02 — none of them the `CLAUDE_SESSION` menu-bar banner of the
  first capture. That weakens an app- or category-specific trigger, **but only if one of these banners
  was the trigger**, and this capture cannot show that: the OS report's interval opens at 18:14:19.849,
  0.24 s *before* the 18:14:20.092 record. The report's start is where the over-limit interval begins,
  not necessarily the spin's onset, so the order is suggestive at most.
- *Q3, the mouse?* The reporter's account on 2026-09-16 is the same as in August: it locks up when a
  notification arrives while the pointer is near where the banner appears. Pointer position is not
  logged at any level used here, so it remains **their account, not a verified trigger** — now
  consistent across two occurrences, which makes it the lead to test first, not a result.

2026-09-16 正式版 `26A428` 复测:**当场抓到,调用栈相同**。系统自己写了 `cpu_resource` 报告
(93 秒内 90 秒 CPU,97%),最重栈为 `FocusBridge.invalidateKeyViewLoop()` → `updateDefaultKeyViewLoop()`
→ `KeyViewProxyCache`;独立复测 120 秒累计 **100.2%**,10 秒 `sample` 主线程 **5,063/5,063** 帧落在
`FocusBridge.invalidateKeyViewLoop()`。持续 **≥ 10 分 44 秒**,期间未自愈,最终手动 `killall` 结束。
起始附近弹出的是 HomeKit 与 Claude 的通知,不是首次捕获时的菜单栏 app —— 但报告区间比最近一条
`Presenting` 早 0.24 秒开始,触发它的是哪条通知**未能钉死**。报告人再次描述为"通知到达时鼠标在附近";
日志不记录指针位置,**仍属本人描述、未验证**,但两次一致,是下一步最该先测的线索。

## Re-verification 2026-09-25 — 27.2 beta2 `26B5091g` — not caught, which decides nothing

> **Clock position, because it decides what these numbers can be compared to.** macOS 27.2 beta2
> `26B5091g` was installed **2026-09-25 07:08:18 UTC** (`InstallHistory.plist`), two minutes after
> the 15:06:19 +0800 boot. The window is **T+1h54m → T+2h04m** with 32 apps running and the
> post-update reindex still active — matched to no earlier window, so log *volumes* are not
> presented as pairs. Kernel `xnu-13432.40.162~92` (release: `xnu-13432.1.9~1`). Raw capture:
> [`baselines/27.2-beta2-26B5091g/`](../baselines/27.2-beta2-26B5091g/README.md).

| | |
|---|---|
| NotificationCenter pid | 1196, alive since boot (elapsed 2 h 05 m at 17:11) |
| cumulative CPU at that point | 54.96 s user + 6.55 s system = **61.5 s** → **0.8%** average |
| 120 s cumulative sample, 17:14:33 → 17:16:33 | **3.9%** |
| NotificationCenter `cpu_resource` reports since install | **0** |

No spin was observed. On release the OS wrote one `cpu_resource` report in 5 days 14 h of
exposure; this build has had 2 h 15 m. The trigger (a banner presenting, per the reporter near the
pointer) was not exercised deliberately. **Absence over two hours is not evidence**; the status
stays 🔴 on the strength of the release capture until a build is watched long enough to mean
something.

2026-09-25 27.2 beta2 `26B5091g` 复测:安装后无 NotificationCenter `cpu_resource` 报告,2 小时 05 分平均
CPU 0.8%。release 版 5.5 天才抓到一次,两小时说明不了什么。仍记 🔴。
