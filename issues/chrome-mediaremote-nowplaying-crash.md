# Chrome crash: `NSInvalidArgumentException` via Apple MediaRemote Now-Playing (nil in NSArray)
# Chrome 崩溃：经 Apple MediaRemote 推送「正在播放」时往 NSArray 塞 nil

| | |
|---|---|
| **Status** | ⚪ Needs retest on 149.0.7827.201 (originally seen on .115) |
| **macOS** | 27.0 beta `26A5353q` (2026-06-14) |
| **Component** | Apple **MediaRemote / MediaPlayer** ↔ Google Chrome |
| **Chrome** | crashed on **149.0.7827.115**; machine now on **149.0.7827.201** (non-MAS) — retest needed |
| **Report** | Apple Feedback: `FB________` *(to be filed)* |

## Symptom / 症状

Chrome throws an uncaught Objective-C `NSInvalidArgumentException` (inserting `nil` into an `NSArray`) when a tab pushes "Now Playing" media metadata. The exception is raised **inside Apple's framework**, not Chrome's code.

某标签页播放媒体、向系统推送「正在播放」元数据时，Chrome 抛未捕获的 ObjC 异常 `NSInvalidArgumentException`（往 NSArray 塞 nil）。异常抛自 **Apple 框架内部**，非 Chrome 逻辑。

## Evidence / 证据

Stack: `MRMediaRemoteSetNowPlayingInfoForPlayer` (Apple `MediaRemote`) ← `MPNowPlayingInfoCenter` (`MediaPlayer`). I.e. when Chrome publishes Now-Playing info, the Apple framework internally builds an array containing `nil`.

## Workaround / 临时规避

Disable the hardware media-key / Now-Playing integration in Chrome:

```
chrome://flags/#hardware-media-key-handling  →  Disabled
```

Cost: media keys / Control Center can no longer control Chrome playback — but it avoids the crashing Now-Playing path.

代价：媒体键 / 控制中心不能再控制 Chrome 播放，但绕开了崩溃路径。

## Notes / 备注

- The original crash report had `share_with_app_devs=0` (not auto-sent to Google).
- ⚠️ **Retest on .201**: Chrome auto-updated past .115; confirm whether the media-tab crash still reproduces before/after filing.
