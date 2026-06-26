VERIFICATION: HOLD — NOT-REPRODUCED-on-current build. Retest 2026-06-26 on macOS 27.0 beta2 26A5368g found NO "Google Chrome*.ips" in ~/Library/Logs/DiagnosticReports/ or its Retired/ subfolder. A full-text grep for `MRMediaRemoteSetNowPlayingInfoForPlayer`, `MPNowPlayingInfoCenter`, `NSInvalidArgumentException`, and `com.google.Chrome` across every report on disk returned zero hits. The only known crash was on Chrome 149.0.7827.115 under beta1 26A5353q; that report is no longer on disk. Current installed Chrome is 149.0.7827.201.

# HOLD — needs fresh repro on Chrome 149.0.7827.201 / macOS 27.0 beta2 (26A5368g)

Do NOT file to Apple yet. The original crash was on an older Chrome (.115) and an older OS (beta1). Chrome has since auto-updated to .201 and the OS to beta2; both the app and the framework may have changed. Filing now risks a wrong/duplicate report against a build combination that no longer exists, and there is no current `.ips` to attach. We must confirm the crash still reproduces on .201 + 26A5368g first.

## 1-line repro recipe
On Chrome 149.0.7827.201 with `chrome://flags/#hardware-media-key-handling` set to Default/Enabled, play media in a tab so Chrome pushes Now-Playing metadata to Control Center; watch for a new `Google Chrome-*.ips` and verify its header `OS Version` = `26A5368g` and the stack hits `MRMediaRemoteSetNowPlayingInfoForPlayer` → `MPNowPlayingInfoCenter` with `NSInvalidArgumentException`.

## What to capture before filing
- Fresh `Google Chrome-*.ips` with `OS Version` = `macOS 27.0 (26A5368g)` and Chrome 149.0.7827.201.
- Confirm the exception is `NSInvalidArgumentException` (nil into NSArray) raised inside Apple MediaRemote/MediaPlayer, not Chrome code.
- Then promote to a full Feedback (Apple area: Media / MediaRemote; attach the new .ips). Note the original report had `share_with_app_devs=0` (not sent to Google).
