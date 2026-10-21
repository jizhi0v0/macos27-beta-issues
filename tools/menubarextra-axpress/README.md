# menubarextra-axpress

Repro for [SwiftUI `MenuBarExtra(.window)` ignores AXPress / VoiceOver on macOS 27](../../issues/swiftui-menubarextra-window-axpress-inert.md).

```bash
./build.sh
open -g build/MBXWindow.app && sleep 3
build/axpress-probe $(pgrep -x MBXWindow) MenuBarAgent   # 3 × AXPress, then 1 click as the control
build/mbxdiag & sleep 4; kill %1                           # prints the status button's target/action
```

Repeat with `MBXMenu` and `MBXAppKit`. The probe decides by whether a new window of that process appears on screen; the AX return code is printed but is not evidence (`.menu` returns `-25204` and opens, `.window` on 27 returns `0` and does not).

On macOS 27 a status item that does not fit is collapsed into the menu bar's overflow and is then **absent from its app's AX tree**. The probe expands the overflow (`MenuBarAgent`, `AXIdentifier` `menu-bar-overflow-indicator`) when it cannot find the item, and collapses it afterwards. Once expanded, the item is drawn in a `MenuBarAgent` window, which is why the control click is allowed under that owner.

The probe refuses a synthetic click when the topmost on-screen window at the item's centre belongs to another app (a notch utility's overlay, or a window covering the target).
