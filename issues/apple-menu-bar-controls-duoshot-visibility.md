# Menu Bar Controls switch stays off but DuoShot remains visible — identical bundle obeys it outside `/Applications`
# 系统菜单栏开关保持关闭，DuoShot 图标却仍显示——同一安装包在测试目录可正常隐藏

> 🔗 **Track / 关注此问题:** [#36 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/36)

| | |
|---|---|
| **Status** | 🔴 **Confirmed on 27.3 beta 1 `26C5035r`** (2026-11-12–13). Unchanged signed bundle obeys the switch in the repository test directory, but fresh instances from two `/Applications` paths do not. Exact system-side cause unknown; first affected build not established. |
| **macOS** | 27.3 beta 1 `26C5035r`; no older-OS control for this symptom |
| **Component** | Apple System Settings → Menu Bar Controls / MenuBarAgent ↔ application association and visibility management |
| **App** | DuoShot **0.1**, build **`202610221558`**, bundle ID `com.boli.duoshot`; Developer ID signed, Team `RS59HDH7Y3` |
| **Hardware** | MacBook Pro `Mac15,11`, Apple M3 Max, 36 GB |
| **Report** | Apple Feedback not yet filed |

## Symptom / 症状

Turn DuoShot off in **System Settings → Menu Bar → Menu Bar Controls**. The
switch stays off, but the camera / CLI status icon remains visible. Expanding
menu-bar overflow does not change that. The user reports that DuoPaste and
DuoSub obey their switches on the same Mac.

系统设置中 DuoShot 的开关保持关闭，图标却留在菜单栏；不是开关自动弹回。
展开溢出区后仍然如此。同机 DuoPaste、DuoSub 的系统开关正常（用户确认）。

Expected: the switch controls whether the app's menu-bar icons appear, as
described in [Apple's Menu Bar settings guide](https://support.apple.com/en-asia/guide/mac-help/mchlad96d366/mac).

## Decisive unchanged-bundle control / 同一安装包的关键对照

Keep the user's original instance running and launch one extra instance by
exact path. Check its PID's executable path. Copy the **complete installed
bundle with `ditto`**, without rebuilding, changing Info.plist or entitlements,
or re-signing. Exercise the real system switch, read it back, and capture the
expanded menu bar in each state.

In the sequence below, a passing round shows **two DuoShot icons with the
switch on → only the original icon with it off → two with it on**. A failing
round keeps both icons with the switch off. Each extra process is terminated
before starting the next control.

| Extra instance launched from | Successful hide/restore rounds | Evidence |
|---|---|---|
| Repository `tools/menu-bar-visibility/build/FullDuoShot.app` — untouched installed bundle | **3/3** | [on](../baselines/27.3-beta1-26C5035r/menu-bar-visibility/untouched-bundle-same-test-path/DuoShot-baseline.png) / [off](../baselines/27.3-beta1-26C5035r/menu-bar-visibility/untouched-bundle-same-test-path/DuoShot-1-off.png) |
| Original `/Applications/DuoShot.app` — fresh additional process | **0/2** | [on](../baselines/27.3-beta1-26C5035r/menu-bar-visibility/original-path-after-copy/DuoShot-baseline.png) / [off](../baselines/27.3-beta1-26C5035r/menu-bar-visibility/original-path-after-copy/DuoShot-1-off.png) |
| `/Applications/DuoShot Menu Bar Test.app` — untouched installed bundle | **0/2** | [on](../baselines/27.3-beta1-26C5035r/menu-bar-visibility/alternate-name-in-applications/DuoShot-baseline.png) / [off](../baselines/27.3-beta1-26C5035r/menu-bar-visibility/alternate-name-in-applications/DuoShot-1-off.png) |
| Repository `tools/menu-bar-visibility/build/DuoShot.app` — original basename retained | **2/2** | [on](../baselines/27.3-beta1-26C5035r/menu-bar-visibility/same-name-in-test-directory/DuoShot-baseline.png) / [off](../baselines/27.3-beta1-26C5035r/menu-bar-visibility/same-name-in-test-directory/DuoShot-1-off.png) |

All four regular files in both repository copies are byte-identical to the
installed bundle, including its executable and signature. CDHash:
`9fc8a401747faa0718aa28391c13e725456866f4`. See the recorded
[bundle comparison](../baselines/27.3-beta1-26C5035r/menu-bar-visibility/bundle-comparison.json).

同一个未改代码、未重签名的安装包，在测试目录能隐藏，在 `/Applications`
中两个不同文件名的位置都不能隐藏。原路径的新进程也失败，因此不能只用
“原进程运行太久”解释。此结果支持系统侧的应用关联／菜单栏显隐管理异常；
尚未定位到具体哪条内部记录。

## Other controls / 其他对照

[Probe source and instructions](../tools/menu-bar-visibility/README.md) ·
[complete experiment ledger](../baselines/27.3-beta1-26C5035r/menu-bar-visibility/README.md)

- Seven minimal variants all hide and reappear: plain AppKit `NSStatusItem`,
  drag-destination subview, `sharingType = .readOnly`, both plus a CLI title,
  SwiftUI lifecycle with an AppKit item, that combined variant under SwiftUI,
  and SwiftUI `MenuBarExtra(.window)`. The combined AppKit variant passed three
  rounds; a probe under DuoShot's bundle ID and Developer ID also passed three.
- Older SDK linkage metadata, installed Info.plist fields, early drop/window
  setup, and screen-capture preflight did not reproduce the failure in the test
  directory. These are controls for the tested variants, not universal claims
  about those APIs.
- The original installed instance fails three initial rounds. Recreating its
  status item, restarting MenuBarAgent, and launching another original-path
  process do not resolve the failure.
- The app's `NSStatusItem.isVisible` stays true even in successful hidden
  states. After MenuBarAgent restarts, AX may also expose hidden menu proxies.
  The screenshots, with overflow expanded, are the visibility check.
- A stale ControlCenter preference entry associated an old DuoShot build path
  with DuoTerminal. Turning DuoTerminal off three times did not hide DuoShot,
  so this entry is **not an established cause**. No system preference file was
  edited; the complete preference snapshot is not published.

## Workaround and limits / 规避与边界

**No validated in-place fix.** Recreating the status item and restarting
MenuBarAgent did not help. The copy experiment changes menu-bar behavior, but
capture, CLI, login items, and updating were not validated from that location;
it is a diagnostic control, not a recommended replacement installation.

This does not show that every app in `/Applications` is affected, or that the
issue started in 27.3. No older-OS comparison was run. The same-bundle results
do not support rewriting DuoShot's menu-bar structure as the fix, but do not
identify the faulty private system field either.

No DuoShot, DuoPaste, or DuoSub source was changed. All switches were restored,
test processes exited, and the temporary `/Applications` copy was removed.
The user's original process and screenshot editor were preserved.

Distinct from [#35](apple-menubaragent-menu-bar-unclickable.md), where the whole
menu bar stops receiving clicks and a MenuBarAgent restart helps, and
[#34](swiftui-menubarextra-window-axpress-inert.md), where AXPress cannot open
a SwiftUI panel. Here the system application-visibility switch is ineffective.
