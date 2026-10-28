# Feedback draft — #35 whole menu bar ignores clicks and hover; WindowServer floods "Corrupt tree"; killall MenuBarAgent restores it

**Filed:** [FB25347429](https://feedbackassistant.apple.com/feedback/25347429), 2026-10-28 16:56 +0800. The submitted description differs from the one below in one line: the attached sysdiagnose was taken about 20 minutes **after** the restart (healthy state).

**Area:** macOS → Menu Bar (fallback: Window Server / Desktop)
**Type:** Incorrect/Unexpected Behavior

## Title

Menu bar stops receiving clicks and hover (MenuBarAgent gets no events) while WindowServer logs "WSIDTreeConnectInitializedNodes: unable to resolve bindings parent. Corrupt tree." ~6,500/min; killall MenuBarAgent fixes it

## Description

Build: macOS 27.2 26B123 (also seen once on 27.2 RC1 26B118, 2026-10-23). MacBook Pro Mac15,11 (M3 Max), built-in display only.

**Symptom.** The whole menu bar stops responding: Apple menu, the front app's menus, and every status item (system and third-party). Clicks do nothing and there is no hover highlight. The bar still draws and updates (clock ticks, app menus change with the front app). Everything outside the menu bar works normally. Seen at 2026-10-28 16:26 +0800, uptime ~29 h (boot 2026-10-27 11:38). Onset time unknown.

**Workaround.** `killall MenuBarAgent`: launchd restarts it and the menu bar works again immediately (16:33:07, pid 1388 → 11444).

**Evidence captured in the broken state, before the restart:**

1. **Clicks never reached MenuBarAgent.** `log stream --info --predicate 'process == "MenuBarAgent"'` from 16:26:40 to 16:28:11 while I clicked and hovered status items repeatedly: **0** `com.apple.AppKit:Gestures` lines (227 lines total).
   Healthy control on the same build after the restart: two clicks on app menus gave **50** `AppKit:Gestures` lines, and one click on the Control Center status item gave **25**. So in the broken state, mouse events for the menu bar were not delivered to MenuBarAgent.
2. **MenuBarAgent was idle, not hung.** `sample MenuBarAgent 5`: the main thread sits in `mach_msg` under `-[NSApplication run]` → `_DPSNextEvent` (3,100 of 3,177 samples).
3. **WindowServer was flooding one message.**
   `[com.apple.SkyLight:default] WSIDTreeConnectInitializedNodes: unable to resolve bindings parent. Corrupt tree.`
   17,403 of 22,051 WindowServer lines in the 3 minutes up to 16:30, and **6,563 in the minute before the restart**. In the 55 seconds after `killall MenuBarAgent`: **0**. The message is Info level, so I cannot tell when it started.
4. Not related: `[SetMenuBars]: ignoring menu bars from app …` errors were present for hours before and continued after the fix on 26B118. WindowServer CPU was 71–77% both before and after the restart, so it does not follow the bug.

**My guess (not verified):** WindowServer's ID/bindings tree for MenuBarAgent's menu-bar windows gets into an inconsistent state, so hit-testing over the menu bar no longer resolves to MenuBarAgent. Restarting MenuBarAgent re-creates those nodes. This is one observation, not a reproduction.

**Not captured:** a sysdiagnose from the broken state. I restarted MenuBarAgent first. I will attach one if it happens again.

**Attachments (fb35.zip):**
- `1-broken-MenuBarAgent-stream.log`: MenuBarAgent Info stream while clicking, broken state
- `2-broken-MenuBarAgent-sample.txt`: sample of MenuBarAgent, broken state
- `3-broken-WindowServer-3min.log`: WindowServer Info log, 3 minutes, broken state
- `4-healthy-MenuBarAgent-appmenu-clicks.log`, `5-healthy-MenuBarAgent-statusitem-click.log`: controls after the restart

Public tracking: https://github.com/jizhi0v0/macos27-beta-issues/issues/35
