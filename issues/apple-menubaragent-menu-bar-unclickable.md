# Whole menu bar ignores clicks and hover while the rest of the UI works — `killall MenuBarAgent` restores it
# 整个菜单栏点不动、没有悬浮反应，其他操作都正常——`killall MenuBarAgent` 可恢复

> 🔗 **Track / 关注此问题:** [#35 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/35)

| | |
|---|---|
| **Status** | 🟡 **Workaround works, cause unknown** (2026-10-23). Seen **once**. Restarting `MenuBarAgent` fixed it immediately. We could not tell whether clicks were reaching MenuBarAgent, because the Info-level logs that would show it had already aged out |
| **macOS** | 27.2 RC1 `26B118`, uptime 2 d 23 h (booted 2026-10-20 10:34) |
| **Component** | Apple `MenuBarAgent` (`/System/Library/CoreServices/MenuBarAgent.app`) ↔ WindowServer |
| **Hardware** | MacBook Pro `Mac15,11` (M3 Max), built-in display only (3456 × 2234); MenuBarAgent's own log reports the menu bar mode as `alwaysVisible` (not auto-hidden) |
| **Report** | Not filed with Apple yet — there is nothing actionable without a capture from the broken state (see [Capture](#if-you-hit-this-capture-before-restarting--复现时先取证再重启)) |

## Symptom / 症状

The whole menu bar stops responding: the Apple menu, the frontmost app's menus (`Telegram`, `Edit`, `View`, `Window`) and every status item, Apple's and third-party alike. A click does nothing and **there is no hover highlight either**. The menu bar still draws normally and keeps updating: the clock read 10:03:16 in the user's screenshot and 10:07:26 in a `screencapture` four minutes later, and the app menus switched from Telegram to WeChat when the front app changed. Clicks and keystrokes everywhere else (windows, typing) work normally.

整个菜单栏没反应：苹果菜单、前台 App 的菜单、所有状态栏图标（系统的和第三方的）都点不开，**鼠标悬停也没有高亮**。菜单栏照常绘制、时钟照走、切换前台 App 后菜单也会跟着变。菜单栏以外的点击、打字都正常。

We do not know when it started; the user noticed it at about 10:00 on 2026-10-23.

## Workaround / 临时解决

```bash
killall MenuBarAgent
```

MenuBarAgent is a `keepalive` LaunchAgent (`/System/Library/LaunchAgents/com.apple.MenuBarAgent.plist`), so launchd starts a new one immediately: here pid 1369 → 35035 at 10:07:44, and the user confirmed the menu bar worked again. No logout, no reboot.

If that does not help, these have not been tried for this symptom here (untested, in order of disruption): `killall ControlCenter` (also restarts itself), then log out and back in. Restarting `SystemUIServer` is a common suggestion for older macOS versions. Here the only windows over the menu bar belonged to WindowServer and MenuBarAgent (measured below), so we would not expect it to help (untested).

MenuBarAgent 是 launchd 托管的 keepalive 进程，杀掉后立即自动重启，菜单栏随即恢复，无需注销或重启电脑。只见过一次，是一个数据点，不是保证。

## What we checked / 我们查了什么

All measurements below were taken **while the menu bar was broken** (10:03–10:07), except where marked.

### 1. Nothing covers the menu bar — ruled out / 没有窗口挡住菜单栏

`CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, every on-screen window with layer > 0:

| Layer | Owner | Frame (x, y, w, h) | |
|---|---|---|---|
| 102 | DuoTranslator (pid 7604) | 1248, **34**, 480, 405 | a panel, **below** the menu bar |
| 25 | NotchBadge (pid 7601) | 707, **36**, 314, 104 | **below** the menu bar |
| 24 | Window Server — `Menubar` | 0, 0, 1728, 33 | |
| 24 | MenuBarAgent (pid 1369) | 0, 0, 1728, 33 | |

Only WindowServer's `Menubar` window and MenuBarAgent's own window sit over the strip. Compare [#33](app-store-payment-sheet-occluded-by-invisible-window.md), where an invisible window *was* the cause.

### 2. MenuBarAgent was not hung — ruled out / 进程没卡死

`sample 1369 2`: the main thread spent all 1,299 samples blocked in `mach_msg` under `-[NSApplication run]` → `_DPSNextEvent`, i.e. idle, waiting for events. A hang would show the main thread busy somewhere else.

### 3. Event taps — nothing slow, and not touched by the fix / 事件拦截：没有真实延迟，修复也没动它们

`CGGetEventTapList`, enabled taps only:

| Tapper | Tap | Events | `avgUsecLatency` field |
|---|---|---|---|
| WeType 3.0.0 (pid 1735, input method) | **active** (`options 0`), HID level | mouse-down (left/right/other), key down/up, flags | 4,378,446 → 1,709,717 → 1,271,546 µs across three reads — **not a real delay, see below** |
| Klack (pid 7609) | listen-only, two taps | mouse buttons; keys and flags | 0 |
| ViewBridgeAuxiliary, universalaccessd | listen-only | | 0 |

WeType's tap is not the cause: the fix did not touch it, it is still installed with the same mask, and the menu bar works.

**The seconds-scale "latency" is not delay that events experience.** An earlier version of this write-up called it a 1–4 s tap; that was wrong. The header only says `Average latency in microseconds` (`CGEventTypes.h`); what is measured is undocumented. Measured on 2026-10-23 after the fix, with WeType running, using a listen-only tap at `kCGAnnotatedSessionEventTap` (after WeType's HID tap) that compares each event's `timestamp` with its arrival time:

| Event | n | avg | max |
|---|---|---|---|
| key down | 328 | 0.61 ms | 5.18 ms |
| key up | 320 | 0.37 ms | 2.48 ms |
| mouse down | 2 | 4.01 ms | 6.80 ms |
| all | 654 | p50 0.33 ms, p99 2.40 ms | |

Over the same 40 s, the field read 0–5 ms (once 62 ms) while typing was going on, then climbed to 730 → 1,811 → 8,688 ms once typing stopped, and later showed 17 s on an idle machine. Min, avg and max are always identical. It grows with idle time, so it is not per-event latency. A control run without WeType was not clean: macOS relaunched WeType 6 s in, because it was still an enabled input source.

KeyRemap's daemon (`/Library/Application Support/KeyRemap/KeyRemap.app --daemon`) spawns `hidutil` about **80 times a minute** — 800 per 10 minutes, steady from at least 04:00 to 10:00. It was not new, and the fix did not touch it either.

### 4. WindowServer `[SetMenuBars]` errors — unrelated / 无关

```
E  WindowServer[649:1644] [com.apple.SkyLight:packages] 77a2f3[SetMenuBars]: ignoring menu bars from app 77a2f3
```

First appeared at **09:55** (none from 06:00 to 09:55), 2–13 per minute after that. This looked like the onset, but the errors **kept coming after the fix** (6, 16 and 2 per minute at 10:08, 10:09, 10:10), so they are not what broke the menu bar.

### 5. MenuBarAgent's own errors — not discriminating / 区分不出

The broken process (pid 1369) logged, from 09:30 to its death:

| Count | Message |
|---|---|
| 76 | `[com.apple.coreanimation:API] cannot add handler to 4 from 0 - dropping` |
| 7 | `[com.apple.menubar:applications] Unable to look up LSASN from auditToken` |
| 1 | `[FrontBoard:ProcessScene] … systembanner-… No scene exists for this identity` |

The working replacement (pid 35035) logs the first two as well (24 and 3 in its first few minutes), so they do not mark the broken state. It also logged things the old one did not — 78 × `[com.apple.menubar:general] Unknown Display ID '…'` and 6 Faults from `BoardServices:Bootstrap` — probably side effects of starting fresh, since the menu bar works.

### 6. The question we could not answer / 没能回答的问题

**Did clicks reach MenuBarAgent?** A working MenuBarAgent logs every press at Info level:

```
MenuBarAgent: (AppKit) [com.apple.AppKit:Gestures] [0x7930219800 _mouseDown<private>]
MenuBarAgent: (AppKit) [com.apple.AppKit:Gestures] [0x7930219800 _mouseDown] correct buttons down
MenuBarAgent: (AppKit) [com.apple.AppKit:Gestures] [0x7930219800 _mouseDown] valid button down - cont...
```

The new process logged 162 `AppKit:Gestures` lines; the old one logged **none** — but that is not evidence. Info-level messages are kept in memory only briefly, and the old process's surviving Info lines cover only 10:07:29–10:07:41, the last 12 seconds before it was killed. Its clicks from the broken period had already aged out.

So both of these remain open:

- **A. Clicks never reached MenuBarAgent.** WindowServer stopped routing menu-bar events to it (hit-testing / event routing). The missing hover points this way: hover needs mouse-moved events, not just clicks.
- **B. Clicks reached it but it ignored them.** MenuBarAgent's own tracking state was stuck.

The capture below tells these apart.

### Not useful as evidence / 不能当证据

WindowServer used **68–88% CPU** while broken and 44–58% at 10:13 after the fix. The window count was not controlled between the two readings, and an uncontrolled window count has produced a false WindowServer CPU regression in this repo before (see [#3](apple-windowserver-invalid-window.md)), so do not read this as a cause or a fix.

## If you hit this: capture before restarting / 复现时先取证再重启

Restarting MenuBarAgent destroys the evidence. Before you do it:

```bash
# 1. Live log while you click and hover the menu bar 3–4 times, then Ctrl-C
log stream --info --predicate 'process == "MenuBarAgent"' > ~/Desktop/mba-stream.log

# 2. Count presses that reached MenuBarAgent (this pattern matches one line per press)
grep -c '_mouseDown<' ~/Desktop/mba-stream.log

# 3. Is MenuBarAgent busy or idle? Look at the main thread
sample MenuBarAgent 3 -file ~/Desktop/mba.sample

# 4. Then fix it
killall MenuBarAgent
```

How to read step 2:

| `_mouseDown<` count | Meaning |
|---|---|
| **0** after several clicks | **A** — events never reached MenuBarAgent; WindowServer side |
| **≥ 1** but no menu opened | **B** — MenuBarAgent received them and did nothing; MenuBarAgent side |

Healthy baseline (10:11–10:12, after the fix): **2** presses logged (`_mouseDown<`), 6 `_mouseDown` lines in total, out of 3,740 lines.

Please comment on [#35](https://github.com/jizhi0v0/macos27-beta-issues/issues/35) with the count, your macOS build, and whether `killall MenuBarAgent` fixed it for you.

## Possibly related / 可能相关（未确认是同一问题）

- [#22](https://github.com/jizhi0v0/macos27-beta-issues/issues/22) — WindowServer ~100% CPU cleared by restarting MenuBarAgent (27.0 beta4). Same remedy, different symptom.
- [#12](apple-menubaragent-idle-cpu.md), [#20](https://github.com/jizhi0v0/macos27-beta-issues/issues/20) — MenuBarAgent CPU.
- [Apple Community (de) 256360385](https://communities.apple.com/de/thread/256360385) — on 27.0, Notification Center and *some* menu bar icons stop responding to clicks; survived a reboot and a reinstall, then went away by itself. Partial, not the whole bar, and no MenuBarAgent restart was tried.
- [Apple Developer Forums 851315](https://developer.apple.com/forums/thread/851315) — on 27, an *open* native menu stops responding after a mouse sequence in TextEdit. Different scope; no replies.
