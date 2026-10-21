FILED 2026-10-21 as **FB25269767** (https://feedbackassistant.apple.com/feedback/25269767).
Topic Developer Technologies & SDKs; platform macOS; technology SwiftUI; type Incorrect/Unexpected Behavior;
build macOS 27.2 RC Seed (26B118); on device. Attached: macOS sysdiagnose + a zip of tools/menubarextra-axpress/
(sources only). Submitted text = the sections below. Write-up: issues/swiftui-menubarextra-window-axpress-inert.md.

# Title
SwiftUI MenuBarExtra(.window): status item ignores AXPress on macOS 27 (returns success, panel never opens) — VoiceOver users cannot open the extra

# Apple area / component to select
SwiftUI (MenuBarExtra). Also relevant: Accessibility / VoiceOver, AppKit (NSStatusBarButton).

# Description
On macOS 27.2 RC1 (26B118), a `MenuBarExtra` using `.menuBarExtraStyle(.window)` cannot be opened through Accessibility. `AXUIElementPerformAction(item, kAXPressAction)` on its `AXMenuBarItem` returns `kAXErrorSuccess` and no window appears; the item still lists `AXPress` among its actions. A mouse click on the same item opens the panel normally. With the panel open, AXPress does not close it either.

The same build of the same minimal app works on macOS 26.7 (25G229): AXPress opens and closes the panel.

Inside the app, the status item's `NSStatusBarButton` explains it:

    macOS 26.7 25G229     target: WindowMenuBarExtraBehavior   action: toggleWindow:
    macOS 27.2 RC1 26B118 target: nil                          action: nil

On 27 the button has no action, so an accessibility press has nothing to perform, while the mouse path presents the window some other way.

Only the `.window` style is affected. On the same 27.2 RC1 machine, a `.menu`-style `MenuBarExtra` and an AppKit `NSStatusItem` (button target/action → NSPopover) both open by AXPress 3/3.

User impact: VoiceOver users (VO-Space performs the same press) cannot open any app's `.window` menu bar extra, and there is no public API an app can use to present it on their behalf. Other developers report the same on 27.0 (26A428) and 27.0.1.

Question: is the loss of the button's target/action intended? If the new presentation path is deliberate, please make the accessibility press follow it (or expose a public way to present a `.window` MenuBarExtra), and stop advertising `AXPress` / returning success when the press does nothing.

# Steps to reproduce
1. Unzip the attachment and run `./build.sh` (builds MBXWindow, MBXMenu, MBXAppKit — three LSUIElement apps differing only in how the status item is made — plus `axpress-probe` and `mbxdiag`).
2. `open -g build/MBXWindow.app`, wait 3 s.
3. `build/axpress-probe $(pgrep -x MBXWindow) MenuBarAgent` from a terminal that has Accessibility access. It presses the item 3 times (success = a new on-screen window of that process), then clicks it once as a control.
4. Alternatively, turn on VoiceOver, move to the MBXWindow item in the menu bar, and press VO-Space.
5. Run `build/mbxdiag` and read the printed target/action.
6. Repeat 2–3 with MBXMenu and MBXAppKit.

# Expected results
The AXPress opens the `.window` panel (as on macOS 26.7 and as a click does), or, if pressing is unsupported, `AXPress` is not advertised and the call returns an error.

# Actual results
AXPress returns 0 and nothing opens, 0/3 (`.window` only). The control click opens the panel. `NSStatusBarButton` target and action are nil.

# Configuration
- Affected: MacBook Pro Mac15,11 (M3 Max), macOS 27.2 RC1 (26B118)
- Works: Mac mini Mac16,10, macOS 26.7 (25G229)
- Minimal apps built with the default toolchain on each machine; no third-party frameworks.

# Probe output
27.2 RC1, MBXWindow (items were in the menu bar overflow, expanded first):
     AXPress #1: result 0, nothing within 3 s
     AXPress #2: result 0, nothing within 3 s
     AXPress #3: result 0, nothing within 3 s
     click (topmost MenuBarAgent): opened after 0.00 s: ["layer 101 194x96"]
26.7, MBXWindow:
     AXPress #1..#3: result 0, opened after 0.06 s: ["layer 101 194x96"]
     click (topmost Control Center): opened
