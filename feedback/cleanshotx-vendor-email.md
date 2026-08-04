# Vendor email — CleanShot X (MakeTheWeb)

Vendor email draft for the ViewBridge/QuickLook crash (issue #17). Not an Apple Feedback — this reports the Apple root cause to the app vendor and suggests a defensive mitigation. Suggested recipient: `support@cleanshot.com`.

---

**To:** support@cleanshot.com
**Subject:** CleanShot X 4.8.9 crash on macOS 27 beta — uncaught ObjC exception in Apple ViewBridge during QuickLook preview

Hi CleanShot team,

I hit a crash in CleanShot X 4.8.9 on macOS 27.0 beta 3 (build `26A5378j`, Apple silicon / M3 Max). I've root-caused it and I don't think it's a bug in your code — but you're currently the one taking the crash, so I wanted to flag it with a suggested mitigation.

**Environment**
- CleanShot X 4.8.9 (`pl.maketheweb.cleanshotx`)
- macOS 27.0 beta 3, build `26A5378j`
- Mac15,11 (M3 Max), 36 GB
- Crash: `EXC_CRASH (SIGABRT)` — `abort() called`
- Incident ID: `EF867893-F3DC-4C3D-B1E6-B6EAA9E3BC58`
- Crash Reporter Key: `E33E57DD-CF22-CB53-A1DF-059800B67B55`
- (`share_with_app_devs = 0`, so this was **not** auto-sent to you — I have the full `.ips` and can share it.)

**What happens**
Intermittently, when the app brings up the QuickLook "seamless" preview after a capture, the process aborts. It is low-frequency and non-deterministic — I have not found a reliable repro; repeating the same capture usually works fine.

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
I've seen the **byte-identical** throw site (`-[NSRemoteView containingWindowWillOrderOnScreen:] + 216` → `_CFBundleGetValueForInfoKey + 0`, via `-[NSWindow _doWindowWillBeVisibleAsSheet:]`) crash a completely unrelated sandboxed app on the same macOS 27 beta, reached through a *different* remote-view provider. Two unrelated apps, two different presenters, one identical Apple throw site — the fault is in the shared ViewBridge order-on-screen path.

**Suggested mitigation on your side (until Apple fixes it)**
Since the exception is raised synchronously on the main thread during `-[NSWindowController showWindow:]` → `makeKeyAndOrderFront:`, a couple of options that would keep CleanShot alive on affected betas:
1. Present the QuickLook preview **off the sheet path** on macOS 27 — e.g. as a normal window/panel rather than a sheet — since the throw is specifically in `_doWindowWillBeVisibleAsSheet:`.
2. Or guard the `showWindow:` / order-on-screen call so an AppKit/ViewBridge exception during presentation is contained (log + retry/fallback) instead of aborting the whole app.
3. And/or file your own Apple Feedback (area: AppKit / ViewBridge — uncaught exception in `-[NSRemoteView containingWindowWillOrderOnScreen:]` when a remote view is presented as a sheet); vendor reports carry weight with Apple during the beta.

Happy to send the full `.ips` and any other diagnostics. Thanks for a great app — just want to make sure it survives the macOS 27 betas.

Best,
[your name]
