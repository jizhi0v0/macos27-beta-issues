# SwiftUI `MenuBarExtra(.window)` ignores AXPress — VoiceOver and automation cannot open the panel, while the press reports success
# SwiftUI `MenuBarExtra(.window)` 对 AXPress 没反应——VoiceOver 和自动化打不开面板，而按下却报告成功

> 🔗 **Track / 关注此问题:** [#34 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/34)

| | |
|---|---|
| **Status** | 🔴 **Confirmed on 27.2 RC1 `26B118`, clean on 26.7 `25G229`** (2026-10-21). The status button of a `.window`-style `MenuBarExtra` has **no target and no action** on 27.2 RC1 (`toggleWindow:` on `WindowMenuBarExtraBehavior` on 26.7), so an accessibility press has nothing to invoke. A real click still opens the panel. `.menu` style and AppKit `NSStatusItem` are not affected. Third-party reports place it on **27.0 `26A428`** and **27.0.1** as well (not re-tested here) |
| **macOS** | Affected: 27.2 RC1 `26B118`. Control: 26.7 `25G229` |
| **Component** | Apple SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)` ↔ AppKit `NSStatusBarButton` accessibility |
| **Hardware** | MacBook Pro `Mac15,11` (27.2 RC1); Mac mini `Mac16,10` (26.7) |
| **Report** | **[FB25269767](https://feedbackassistant.apple.com/feedback/25269767)** (filed 2026-10-21, with a sysdiagnose and the repro zip) — text in [`feedback/swiftui-menubarextra-window-axpress.md`](../feedback/swiftui-menubarextra-window-axpress.md) |

## Symptom / 症状

Pressing a `.window`-style menu bar extra through Accessibility (`AXUIElementPerformAction(item, kAXPressAction)`, VoiceOver's VO-Space, any automation that uses AXPress) **returns `kAXErrorSuccess` (0) and opens nothing**. The item still advertises `AXPress` in its action list. Clicking it with the mouse opens the panel as usual. With the panel open, AXPress does not close it either; Escape does.

用辅助功能「按下」一个 `.window` 样式的菜单栏项（AXPress、VoiceOver 的 VO-空格、任何走 AXPress 的自动化）：返回成功（0），面板不出现；这个项在 AX 里仍然声明自己支持 `AXPress`。用鼠标点照常打开。面板开着时 AXPress 也关不掉，要按 Escape。

## Repro / 复现

[`tools/menubarextra-axpress/`](../tools/menubarextra-axpress/README.md) builds three accessory apps that differ **only** in how the status item is made, a probe that presses each item three times and then clicks it once as the control (success = a new on-screen window of that process, never the AX return code), and `mbxdiag`, which prints the status button's target and action from inside the app.

```bash
tools/menubarextra-axpress/build.sh
open -g tools/menubarextra-axpress/build/MBXWindow.app && sleep 3
tools/menubarextra-axpress/build/axpress-probe $(pgrep -x MBXWindow) MenuBarAgent
```

## Results / 结果 (2026-10-21)

| Status item | 26.7 `25G229` AXPress | 26.7 click | 27.2 RC1 `26B118` AXPress | 27.2 RC1 click |
|---|---|---|---|---|
| **SwiftUI `MenuBarExtra`, `.window`** | 3/3 open, returns `0` | opens | **0/3, returns `0`** | **opens** (same 194×96 panel) |
| SwiftUI `MenuBarExtra`, `.menu` | 3/3 open, returns `-25204` | opens | 3/3 open, returns `-25204` | not run ¹ |
| AppKit `NSStatusItem` → `NSPopover` | 3/3 open, returns `0` | opens | 3/3 open, returns `0` | not run ¹ |

¹ On the 27.2 machine the items sat in the menu bar overflow; the control click was only run for `.window`, the row that needed it.

Two real apps agree: **DuoUpdater** (`.window`) opens 3/3 by AXPress on 26.7 and 0/3 on 27.2 RC1, a synthetic click opens it on both; **ChatGPT** (a menu-style item) opens 3/3 on both.

The return code is not evidence either way: `.menu` returns `-25204` (`kAXErrorCannotComplete`) and opens; `.window` on 27.2 returns `0` and does not.

## Mechanism / 机制 (measured)

`mbxdiag` walks its own windows two seconds after launch and prints the `NSStatusBarButton`'s target and action:

```
26.7 25G229, .window      target: WindowMenuBarExtraBehavior   action: toggleWindow:
27.2 RC1 26B118, .window  target: nil                          action: nil
.menu (both)              target: nil                          action: nil   (the menu is attached separately and opens fine)
```

On 26.7 an accessibility press performs the button's action, `toggleWindow:`. On 27.2 RC1 there is no action to perform, so the press succeeds and does nothing. The mouse path still works, so on 27 the panel is opened by something other than the button's target/action. Third-party write-ups (below) say SwiftUI now presents the window through a private AppKit "expanded interface session"; that part is **their** reading and was not verified here.

27.2 RC1 上 `.window` 样式的状态栏按钮没有 target/action（26.7 上是 `WindowMenuBarExtraBehavior` 的 `toggleWindow:`），辅助功能的「按下」没有东西可调用；鼠标点击走的是另一条路，所以照常能开。

## Is it intentional? / 是不是故意的?

Unknown — [FB25269767](https://feedbackassistant.apple.com/feedback/25269767) asks. What the evidence supports:

- **The change of mechanism looks deliberate**: target/action are gone in a specific way, only for `.window`, and the mouse path was rebuilt to keep working. This is not a crash or a race.
- **The accessibility breakage looks like a side effect, not a decision**:
  - the item still **advertises `AXPress`** and **returns success** — a deliberate removal would drop the action or return an error;
  - the result is that **VoiceOver users cannot open the panel at all** (reported by two projects below; VoiceOver itself was not driven here), and nothing in the API offers them another way in;
  - it is absent from the [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes) — no known issue, no deprecation, no API to open a `.window` extra programmatically in its place.

结论：机制改动像是有意的（只改了 `.window`、鼠标路径特意保留），但辅助功能失效更像副作用——仍然声明 AXPress、仍然返回成功、VoiceOver 用户完全打不开、release notes 一字未提。是否有意只能等 Apple 回答。

## Workarounds / 规避

| | AXPress / VoiceOver | Cost |
|---|---|---|
| Replace the scene with AppKit `NSStatusItem` whose button target/action toggles an `NSPopover` or your own `NSPanel` (hosting the same SwiftUI view) | works (row 3 above) | public API; positioning, dismissal and the panel's look are yours to rebuild. `NSPopover` gets Liquid Glass automatically ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)); a custom panel can use `NSGlassEffectView` |
| `.menu` style | works | only if the content fits a menu |
| Override `NSStatusBarButton.accessibilityPerformPress` to call AppKit's private request (pika-tools) | works, per that project | private API; not App Store safe |
| For automation: synthetic mouse click at the item's centre | works | moves the user's pointer; check the topmost window at that point first (a notch overlay or another window can take the click) |

## Related reports / 相关报告

- [EtanHey/voicelayer#223](https://github.com/EtanHey/voicelayer/pull/223) — same probe on 27.0 `26A428`: `.window` returns 0 and does not open; `NSStatusItem` + `NSPopover` opens. Switched to the AppKit route.
- [dev-pikapik/pika-tools#61](https://github.com/dev-pikapik/pika-tools/pull/61) — VoiceOver press does nothing on 27.0.1; button has no target/action; fixed outside the App Store build with a private method.
- [joaodavidsilva/brightboi#34](https://github.com/joaodavidsilva/brightboi/issues/34) — "VoiceOver can't open the popover".

## Not verified / 未验证

- VoiceOver itself was not driven here; the VoiceOver claim rests on the two reports above and on VO-Space using the same press.
- 27.0 and 27.0.1 were not tested here. One minimal app per style, one machine per OS version.
- Whether any public API (or a later 27.x) restores a programmatic open for `.window` extras.

## Side note: overflowed items leave the AX tree / 附：被收进溢出的项不在 AX 树里

On macOS 27, a status item that does not fit is collapsed behind the menu bar's overflow button and is then **absent from its app's `AXExtrasMenuBar` entirely**, not just off screen. Pressing `MenuBarAgent`'s `AXButton` (`AXIdentifier` `menu-bar-overflow-indicator`, `…-expanded` while open) brings the items back into their apps' AX trees; the expanded items are drawn in a `MenuBarAgent` window. Not a bug as far as this log is concerned, but any test of a status item on 27 has to account for it.
