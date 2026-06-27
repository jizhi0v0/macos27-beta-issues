# `modelmanagerd` crash-loops (`EXC_BREAKPOINT`) on an Apple-Intelligence-ineligible device
# `modelmanagerd` 在不符合 Apple Intelligence 资格的设备上反复崩溃（`EXC_BREAKPOINT`）

> 🔗 **Track / 关注此问题:** [#16 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/16)

| | |
|---|---|
| **Status** | 🔴 Open · confirmed, reproduces across reboot — Apple system bug |
| **macOS** | 27.0 beta2 `26A5368g` |
| **Component** | Apple **`modelmanagerd`** (`/usr/libexec/modelmanagerd`) + `ModelManagerServices.framework` (private) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max (HW-eligible for Apple Intelligence; **region/account-ineligible**) |
| **Report** | Apple Feedback: **[FB23430737](https://feedbackassistant.apple.com/feedback/23430737)** (filed 2026-06-27 via Feedback Assistant — Apple Intelligence → Enabling Apple Intelligence features → "Error or issue using a feature"; sysdiagnose + crash `.ips` + live debug-log capture attached) |

## Symptom / 症状

`modelmanagerd` (the on-device model-management daemon that backs Apple Intelligence **and** Xcode predictive code completion) crashes with `EXC_BREAKPOINT (SIGTRAP)` every ~20 min – 2.5 h, around the clock. launchd restarts it each time, so it crash-loops indefinitely. **138 crashes over 4 days** (2026-06-23 11:46 → 2026-06-27 12:16) on this machine. Apple Intelligence is unusable on the device (no on-device model present).

`modelmanagerd`（支撑 Apple Intelligence **以及** Xcode 预测代码补全的端上模型管理守护进程）以 `EXC_BREAKPOINT (SIGTRAP)` 崩溃，约每 20 分钟～2.5 小时一次，全天不停。launchd 每次拉起 → 无限崩溃循环。本机 **4 天 138 次**（2026-06-23 11:46 → 2026-06-27 12:16）。本机 Apple Intelligence 不可用（端上模型缺失）。

## Evidence / 证据

**Crash signature** (`.ips`, identical across all samples):

```
Exception:   EXC_BREAKPOINT (SIGTRAP), codes 0x1, 0x102e6f5d4
Termination: SIGNAL 5 Trace/BPT trap: 5
Faulting thread queue: com.apple.root.background-qos.cooperative   (Swift async)
```

Faulting backtrace (offsets only — both binaries are stripped release builds, `atos` yields no names):

```
0-6  modelmanagerd            0x575d4 …                       (UUID 7aab2768… matches on-disk)
7-13 ModelManagerServices     0x72699 / 0x716ed / 0x13635 …   (recursion 0x13635↔0x13639)
14   libswift_Concurrency     completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*)
```

- **No error string anywhere.** The `.ips` has empty `asi` / `reason` / `lastExceptionBacktrace`; a persistent `log stream --level debug` running across the crash captured **zero** lines from the crashing PID. → it's a Swift `precondition`/forced-unwrap trap, which traps without emitting `os_log` (so `log show` after the fact is always empty — only a live debug stream sees the daemon at all).
- **What the daemon does on that queue:** the live stream shows `modelmanagerd` on `background-qos.cooperative` running `com.apple.modelcatalog.catalog` sync + `UnifiedAssetFramework` locking of asset set **`com.apple.MobileAsset.UAF.FM.Overrides`** (Foundation Models safety-deny override assets — the only FM asset present on an ineligible device; `/var/db/com.apple.modelcatalog/` holds only empty `sideload`/`tokenStore`, no actual LLM).
- **Eligibility:** `SystemLanguageModel.default.availability` returns **`.unavailable(.deviceNotEligible)`** (not `.modelNotReady` / `.appleIntelligenceNotEnabled`). `os_eligibility.plist` shows the relevant domains failing on `COUNTRY_BILLING` / `COUNTRY_LOCATION` — i.e. **region/account-ineligible, despite eligible M3 Max hardware**.

## Root cause (working theory) / 根因（推断）

On a device that is **ineligible** for Apple Intelligence (here: region/account, not hardware), `modelmanagerd` is still started by launchd and still runs its periodic ModelCatalog / UnifiedAssetFramework reconciliation on a Swift `background-qos.cooperative` task. With no real model catalog to reconcile (only the `FM.Overrides` safety assets), an `async` path hits a Swift trap → `EXC_BREAKPOINT`. The daemon should no-op (or not run that task) on an ineligible device instead of trapping. This is an Apple system bug; nothing app-side can fix it.

在**不符合资格**（这里是区域/账号，非硬件）的设备上，`modelmanagerd` 仍被 launchd 启动，并在 Swift `background-qos.cooperative` 任务里周期性跑 ModelCatalog / UnifiedAssetFramework 理货；由于没有真正的模型目录可理（只剩 `FM.Overrides` 安全资产），某条 `async` 路径触发 Swift trap → `EXC_BREAKPOINT`。本应在不合格设备上 no-op，而不是自陷。Apple 系统 bug，app 侧无法修。

## Reproduction / 复现

1. macOS 27 beta2 on a device that reports `deviceNotEligible` for Apple Intelligence (e.g. ineligible region/account).
2. Watch `~/Library/Logs/DiagnosticReports/modelmanagerd-*.ips` accumulate, or `grep modelmanagerd ~/Library/Logs/crash-notify.log`.
3. **Across reboot:** confirmed — after a clean reboot (12:12:53) `modelmanagerd` crashed within ~2.5 min (PID 663 → crash 12:15:26 → restart PID 2036).
4. Confirm eligibility with a tiny FoundationModels probe:
   ```swift
   import FoundationModels
   print(SystemLanguageModel.default.availability)   // unavailable(.deviceNotEligible)
   ```

## Workaround / 临时规避

None that stops the crashes (can't `kill`/`kickstart` the daemon — SIP-protected, runs as `_modelmanagerd`; only a full reboot resets it, and it re-crashes). Impact is low in practice: launchd auto-restarts it, and the only user-visible loss (Apple Intelligence) is already unavailable on an ineligible device. Xcode predictive code completion is the other casualty. To stop the crash-notify banners, mute `modelmanagerd` in crash-notify.

无法阻止崩溃（守护进程受 SIP 保护、以 `_modelmanagerd` 运行，`kill`/`kickstart` 都不行；只有整机重启能重置，且会再崩）。实际危害低：launchd 自动拉起，且唯一受影响的 Apple Intelligence 本就在不合格设备上不可用；另一受害者是 Xcode 预测补全。想关横幅就在 crash-notify 里静音 `modelmanagerd`。

## Notes / 备注

- Related but **distinct** from the widely-reported Apple-Intelligence-on-beta breakage (Apple Dev Forums [thread 788960](https://developer.apple.com/forums/thread/788960): `ModelManagerServices.ModelManagerError 1019`, "stuck at 100%" downloads). Those are *stuck*/error states; this is a hard **crash-loop**, for which no public report was found — likely an under-reported variant tied to the ineligible-device + empty-catalog state.
- `libswift_Concurrency` `EXC_BREAKPOINT` is a common class on these betas (e.g. [Maccy #1380](https://github.com/p0deje/Maccy/issues/1380), macOS 26.4.1) — but on `modelmanagerd` specifically, in a loop, is what's novel here.
- `modelmanagerd` is not Apple-Intelligence-only: it also serves Xcode's local predictive code-completion model ([WWDC24](https://www.threads.com/@hoitab/post/C8Fwk0ooDWR)).

**Captured 2026-06-27 beta2 26A5368g** via a temporary user LaunchAgent running `log stream --level debug` on `process == "modelmanagerd" OR senderImagePath CONTAINS "ModelManager"` across a reboot — confirmed crash within 2.5 min of boot, on `background-qos.cooperative`, with no emitted error message (trap is silent). Symbolication blocked by stripped binaries.
