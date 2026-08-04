# Vendor email — CleanShot X (MakeTheWeb)

Vendor email draft for the ViewBridge/QuickLook crash ([#17](https://github.com/jizhi0v0/macos27-beta-issues/issues/17)). Not an Apple Feedback — this reports the Apple root cause to the app vendor and suggests a defensive mitigation. Suggested recipient: `support@cleanshot.com`.

**Status: drafted, not sent.** Refreshed 2026-08-04 against the current evidence (31 crashes, 4 apps, 4 UI toolkits, survives into beta4 `26A5388g`).

---

**To:** support@cleanshot.com
**Subject:** CleanShot X 4.8.9 crash on macOS 27 beta — uncaught ObjC exception in Apple ViewBridge during QuickLook preview (root-caused, 3 crashes here + same throw in 3 other apps)

Hi CleanShot team,

I hit a crash in CleanShot X 4.8.9 on the macOS 27.0 betas (Apple silicon / M3 Max). I've root-caused it and I don't think it's a bug in your code — but you're currently the one taking the crash, so I wanted to flag it with a suggested mitigation.

**Environment**
- CleanShot X 4.8.9 (`pl.maketheweb.cleanshotx`)
- macOS 27.0 beta 3, builds `26A5378j` and `26A5378n`
- Mac15,11 (M3 Max), 36 GB
- Crash: `EXC_CRASH (SIGABRT)` — `abort() called`
- **3 crashes**, all with a byte-identical throw site:

  | Time (local) | Build | Incident |
  |---|---|---|
  | 2026-07-13 19:45:55 | `26A5378j` | `EF867893-F3DC-4C3D-B1E6-B6EAA9E3BC58` |
  | 2026-07-19 17:16:46 | `26A5378n` | `E6B283DF-DA79-4A7E-8C29-3399DAA56610` |
  | 2026-07-19 18:07:18 | `26A5378n` | `ACF9295D-5832-4963-AB46-C38FA824F900` |

- (`share_with_app_devs = 0` on all three, so **none** were auto-sent to you — I have the full `.ips` files and can share them.)

**What happens**
Intermittently, when the app brings up the QuickLook "seamless" preview after a capture, the process aborts. It is non-deterministic — repeating the same capture usually works fine, which is what a race in Apple's window order-on-screen path looks like. The 07-19 pair is a crash → reopen → crash-again ~50 minutes later.

Note on frequency: I have not seen a CleanShot X crash on beta 4 (`26A5388g`), but I would not read that as fixed — **the same Apple throw site is still firing on beta 4 in other apps, 12 times between 07-21 and 08-04.** It is more likely I simply hit the QuickLook preview path less often on this build.

**Root cause (it's an Apple beta regression, not CleanShot)**
The crash is an **uncaught Objective-C exception thrown inside Apple's ViewBridge**, on the main thread, while the preview window is being ordered on screen as a sheet:

```
CoreFoundation  __exceptionPreprocess
libobjc         objc_exception_throw
CoreFoundation  _CFBundleGetValueForInfoKey + 0
ViewBridge      -[NSRemoteView containingWindowWillOrderOnScreen:] + 216   ← throws here
CoreFoundation  __CFNOTIFICATIONCENTER_IS_CALLING_OUT_TO_AN_OBSERVER__
Foundation      -[NSNotificationCenter postNotificationName:object:userInfo:]
AppKit          -[NSWindow _doWindowWillBeVisibleAsSheet:]                 ← shown as a sheet
AppKit          -[NSWindow _reallyDoOrderWindow:] / _doOrderWindow:
AppKit          -[NSWindow makeKeyAndOrderFront:]
QuickLookUI     -[QLSeamlessDocumentOpener showWindow:contentFrame:withBlock:] + 184
AppKit          -[NSWindowController showWindow:] + 520
CleanShot X     …
```

ViewBridge's `-[NSRemoteView containingWindowWillOrderOnScreen:]` observer reads a bundle Info-plist key (`_CFBundleGetValueForInfoKey`) and throws; nothing catches it, so it goes `objc_exception_rethrow → std::__terminate → abort()`. The throw is entirely within Apple frameworks (ViewBridge → CFBundle); CleanShot's only role is presenting a QuickLook (out-of-process / XPC-hosted) preview as a sheet.

**Why I'm confident it's Apple, not you**
I have now logged **31 crashes with this byte-identical throw site** (`-[NSRemoteView containingWindowWillOrderOnScreen:] + 216` → `_CFBundleGetValueForInfoKey + 0`, always via `-[NSWindow _doWindowWillBeVisibleAsSheet:]`) across **four unrelated apps built on four different UI toolkits**:

| App | UI stack | Frame that presents the remote view |
|---|---|---|
| WeChat 4.1.11 ×26 | Chromium-based embedded engine | `wechat.dylib` → `makeKeyAndOrderFront:` |
| **CleanShot X 4.8.9 ×3** | Cocoa + Apple **QuickLookUI** | `-[QLSeamlessDocumentOpener showWindow:…]` |
| DingTalk 8.3.15 ×1 | **Qt** (`QtWidgets`/`QtGui`) | DingTalk's own presenter |
| my own app ×1 | plain **Swift/AppKit** | `PreviewPanelController.show(item:…)` |

Every frame above the presenting one is identical in all four, down to the same `+216` offset. There is no third-party engine, framework or toolkit common to all four — the only thing they share is Apple's ViewBridge order-on-screen path. My own app is the clearest case: the presenting code is a few lines of ordinary AppKit fully under my control that do nothing but order a panel on screen, and it still takes the exception.

Two more things worth knowing: the bug has now survived a beta 3 revision *and* the beta 4 update (`26A5378j` → `26A5378n` → `26A5388g`), and CleanShot X's reports are actually the **cleanest** evidence of the three vendors — WeChat installs its own `SIGABRT` handler that rewrites the abort into a null-pointer write, so its crash headers say `EXC_BAD_ACCESS 0x0` and hide the real cause. CleanShot X dies with a plain `EXC_CRASH (SIGABRT)` / `abort() called`, which shows the bug in its unmasked form.

**Suggested mitigation on your side (until Apple fixes it)**
Since the exception is raised synchronously on the main thread during `-[NSWindowController showWindow:]` → `makeKeyAndOrderFront:`, a couple of options that would keep CleanShot alive on affected betas:
1. Present the QuickLook preview **off the sheet path** on macOS 27 — e.g. as a normal window/panel rather than a sheet — since the throw is specifically in `_doWindowWillBeVisibleAsSheet:`.
2. Or guard the `showWindow:` / order-on-screen call so an AppKit/ViewBridge exception during presentation is contained (log + retry/fallback) instead of aborting the whole app.
3. And/or file your own Apple Feedback (area: AppKit / ViewBridge — uncaught exception in `-[NSRemoteView containingWindowWillOrderOnScreen:]` when a remote view is presented as a sheet); vendor reports carry weight with Apple during the beta.

Happy to send the full `.ips` and any other diagnostics. Thanks for a great app — just want to make sure it survives the macOS 27 betas.

Best,
[your name]
