# `NotificationCenter.app`'s main thread spins at ~100% CPU inside SwiftUI's focus-chain walk when a banner presents — a true beachball, self-heals in neither 15 nor 33 minutes
# `NotificationCenter.app` 主线程在 SwiftUI 的 focus-chain 遍历里空转到 ~100% CPU——真正的彩虹转圈，15 分钟乃至 33 分钟都不会自愈

> 🔗 **Track / 关注此问题:** [#29 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/29)
>
> 🧭 **Landed here from "clicking a notification does nothing"?** This is **not** one of the three shapes in [notification-click-failure-taxonomy.md](notification-click-failure-taxonomy.md) — those are all about a click being silently dropped somewhere in the `usernoted` pipeline while the UI stays responsive. This is the opposite failure: `NotificationCenter.app` itself is pegged at 100% CPU and visibly spinning. See [Why this is not #26 or #27](#why-this-is-not-26-or-27--为什么不是-26-或-27) below.

| | |
|---|---|
| **Status** | 🔴 **Open, not yet filed.** First captured with a live, symbolicated stuck stack on 2026-08-22. Caught by chance while investigating a live report of the spinning-wait-cursor ("beachball") symptom — this is the first time this investigation has had a CPU/stack signature for a notification-adjacent hang, rather than only `usernoted` log-line counts |
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
