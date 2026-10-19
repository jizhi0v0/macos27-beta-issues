# App Store "Get" sheet shows only Cancel — no Touch ID, no password — because an invisible window covers it
# App Store 获取/购买弹窗只有「取消」、不弹指纹也不弹密码——被一个看不见的窗口挡住了

> 🔗 **Track / 关注此问题:** [#30 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/30)

| | |
|---|---|
| **Status** | 🟡 **Cause found, workaround and app-side fix verified.** The payment sheet refuses to authenticate while another window covers it, and that includes a fully transparent one. Read as **by design**: a transparent window over a payment UI is the classic clickjacking setup, so PassKit is right to refuse. Recorded so people who hit it can find the cause. |
| **macOS** | 27.2 beta4 `26B5112a`; App Store 3.0. Not tested on other builds |
| **Component** | Apple PassKit `PaymentAuthorizationUIExtension` (the App Store purchase sheet) ↔ any app that leaves a transparent window on screen. Here: DuoPaste's Space-preview panel |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max, Touch ID |
| **Report** | not filed. If filed, the ask is "say why and recover", not "ignore transparent windows" |

## Symptom / 症状

Click **Get** on a free app (seen here; paid purchases use the same PassKit sheet but were not tried). The App Store sheet comes up with the app icon, name and `Account:` line, then **nothing**: no "Double-click / Touch ID to install" prompt, no password field, only **Cancel**. Every retry looks the same. Nothing tells you why.

点 App Store 的「获取」，弹窗出现了图标、名字和 `Account:`，但下面空白：不提示指纹，也没有密码框，只有「取消」。重试多少次都一样，没有任何报错。

## Diagnose in one command / 一条命令判型

Open the sheet once, cancel, then:

```bash
/usr/bin/log show --last 10m --style compact --predicate 'process == "com.apple.PassKit.PaymentAuthorizationUIExtension" AND category == "PaymentAuth" AND (eventMessage CONTAINS "occluded" OR eventMessage CONTAINS "change state" OR eventMessage CONTAINS "cancel reason")'
```

(`/usr/bin/log`, not `log`: in zsh `log` is a builtin and prints nothing.)

**This issue** looks like this — `occluded: true`, the state machine leaves `Authenticate`, and **no `occluded: false` ever follows** until you cancel:

```
10:53:28.163 State Events: Payment UI is occluded: true
10:53:28.163 State machine change state from PKPaymentAuthorizationStateAuthenticate to PKPaymentAuthorizationStateInactive
10:53:31.396 Setting state machine cancel reason to "user"
```

A **healthy** sheet also logs `occluded: true` briefly while it animates in, then `occluded: false` within about half a second, and goes on to `Authorized`:

```
10:59:47.310 State Events: Payment UI is occluded: true
10:59:47.722 State Events: Payment UI is occluded: false
10:59:51.212 … PKPaymentAuthorizationStateAuthenticate to PKPaymentAuthorizationStateAuthorized
```

So `occluded: true` alone proves nothing; **no `occluded: false` before your cancel** does.

## Find the window / 找出是哪个窗口

```bash
swift tools/overlay-windows.swift
```

[`tools/overlay-windows.swift`](../tools/overlay-windows.swift) lists on-screen windows front to back and flags the ones that can cover things unseen: `INVISIBLE` (alpha < 0.05) and `above-normal` (window layer > 0, i.e. floating panels, HUDs, notch/menu-bar overlays). No permissions needed. Before the fix, an ad-hoc listing of the same data (layer, owner, alpha, x y w×h, pid) showed:

```
25 NotchBadge  alpha=1.0 707 36 314 x 104 pid 91701
3 DuoPaste  alpha=0.0 86 325 720 x 420 pid 6912
```

The tool flags such a window as `INVISIBLE,above-normal`. That was checked against a test alpha-0 floating panel, not against DuoPaste itself, which had been fixed by then.

A 720×420 floating window with alpha 0 is the suspect. To see what lies in front of a specific app's windows and how much of each it covers, run `swift tools/overlay-windows.swift --over "App Store"` with the sheet open. (The sheet may be drawn by a PassKit or AMS process rather than by App Store; if `--over` finds nothing, run with `--all` and look for it. Not checked which owner the sheet has.)

To confirm, **quit one candidate at a time** and click Get again. Here quitting DuoPaste alone fixed it; NotchBadge stayed running.

找元凶：跑上面的脚本，看 `INVISIBLE` / `above-normal` 的窗口；**一次只退出一个**候选 app 再点「获取」，能弹指纹的那次就是它。

## Why a window you cannot see counts / 为什么看不见的窗口也算遮挡

WindowServer computes occlusion by window rectangles, not by pixels or alpha. Apple's documentation for [`NSWindow.OcclusionState.visible`](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct/visible) states it outright: a window counts as visible if its bounding box falls in a visible region, and *"a completely transparent window may also be considered visible."* So an alpha-0 panel occludes whatever is under its rectangle exactly as an opaque one would.

Not verified: whether PassKit's `Payment UI is occluded` comes from `NSWindow.occlusionState` or from a stricter overlap check of its own. The log only says it decided "occluded".

Why refusing is right: a transparent window over a payment sheet is how clickjacking works. It can take the click, or make you click something other than what you see. DuoPaste's panel set `ignoresMouseEvents = true`, so it was harmless, but PassKit cannot tell a harmless overlay from a hostile one. What it could do better is the failure: it waits silently in `Inactive`, never says a window is in the way, and offers no password fallback.

## Evidence / 证据 (27.2 beta4 `26B5112a`, 2026-10-19)

The sheet itself was healthy and asked for biometrics. `AMSUIPaymentViewService_macOS` started it with a `biometricsRequest` and `disablePasswordFallback = false`, then `Presenting payment authorization controller` → `Payment sheet has presented`. It was **not** the "free downloads: don't require password" setting.

In `PaymentAuthorizationUIExtension`, the Touch ID preflight ran as it should (`evaluateAccessControl` → `-1004 User interaction required`, `BiometricIdle`). **4 ms later** the sheet logged `Payment UI is occluded: true` and went `Authenticate → Inactive`. After that it logged `Host Application became active` → `resumeAuthenticatorEvaluation` → **`Not in authenticate state, not resuming authentication`**: becoming active again does not bring it back into Authenticate. Cancel then ended the purchase with `AMSErrorDomain code=6`.

**4 of 4** attempts that afternoon (10:52:33, 10:52:44, 10:53:14, 10:53:28) show the same `occluded: true → Inactive` with no `occluded: false`. After quitting DuoPaste, one attempt (10:59:47) got `occluded: false` 0.4 s in and installed. That is a single before/after: one change, one success.

## Fix for app developers / 给 app 开发者的修法

Hiding a window by `alphaValue = 0` leaves it in the window list, so it still occludes. Call **`orderOut(_:)`** when it is hidden. If you use alpha for a no-flash show/hide, set alpha and then order it out. DuoPaste's fix is [`61cc0fd`](https://github.com/jizhi0v0/duo-paste/commit/61cc0fd): `hide()` keeps the instant alpha hide and calls `orderOut` on the next runloop turn. The deferral keeps window ordering out of the SwiftUI layout pass; see [#17](wechat-imageviewer-viewbridge-crash.md) for the ViewBridge exception that ordering during layout can throw.

After the fix, with the new build running and a preview opened and closed, `overlay-windows.swift` lists no DuoPaste window.

退出那个 app 即可临时绕过；app 侧的根治是隐藏时调用 `orderOut`，不要只把 alpha 设成 0。
