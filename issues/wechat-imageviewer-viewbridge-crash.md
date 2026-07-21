# WeChat crash opening the image viewer — uncaught ObjC exception in Apple ViewBridge `-[NSRemoteView containingWindowWillOrderOnScreen:]`
# 微信点开图片查看器时崩溃 —— Apple ViewBridge `-[NSRemoteView containingWindowWillOrderOnScreen:]` 抛未捕获 ObjC 异常

> 🔗 **Track / 关注此问题:** [#17 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/17)

| | |
|---|---|
| **Status** | 🔴 Open — confirmed recurring & **cross-app** (WeChat ×17 + CleanShot X ×3 = **20 verified crashes**, 2026-07-09 → 07-21, **byte-identical throw site**); **survives two beta3 builds AND beta4** (`26A5378j` → `26A5378n` → `26A5388g`); root throw is 100% in Apple frameworks |
| **macOS** | 27.0 — **beta3 `26A5378j`** (8 crashes) → **beta3 rev `26A5378n`** (11 crashes) → **beta4 `26A5388g`** (1 crash, 07-21). Fixed by neither the 07-14 beta3 revision nor the beta4 update. |
| **Component** | Apple **ViewBridge / AppKit** (`NSRemoteView`) — reproduced via **WeChat 4.1.11** (WeChatAppEx / `flue` engine) **and** **CleanShot X 4.8.9** (QuickLookUI `QLSeamlessDocumentOpener`) |
| **Reproducers** | **WeChat 4.1.11 (269136)** MAS (`adam_id` 836500024) · **CleanShot X 4.8.9** (`pl.maketheweb.cleanshotx`, team `AFJU4P8ZV4`) |
| **Machine** | `Mac15,11` — Apple M3 Max, 36 GB |
| **Report** | Apple Feedback: `FB________` *(candidate — now cross-app reproducible)* · vendor email to CleanShot X drafted |

## Symptom / 症状

WeChat **quits unexpectedly when opening the full-screen image viewer** (clicking an image in a chat). **17 WeChat crashes over 13 days (2026-07-09 → 07-21)**, up to **4 in a single day** (07-14) — routine, not a one-off. On 07-17 it crashed **3 times in a chain**, each report launched ~4–6 s after the previous crash (auto-relaunch → re-crash).

在聊天里**点击图片、打开全屏看图**时微信直接闪退。**13 天内 17 次(2026-07-09 → 07-21)**,单日最多 **4 次**(07-14)—— 属于常态,不是孤例。07-17 出现**连崩 3 次**:每份报告都在上一次崩溃后约 4–6 秒启动(自动重启 → 再崩)。

## Occurrences / 复现记录

All 20 entries below were **verified programmatically**, not by grep: the ViewBridge frame sits at index 3 of `lastExceptionBacktrace` (the actual throw site) in every one, and every one goes through `_doWindowWillBeVisibleAsSheet:`. Every WeChat crash is the same build **4.1.11 (269136)**; both CleanShot X are **4.8.9**.

下列 20 条均经**程序化校验**(非 grep):每一份的 `lastExceptionBacktrace` 第 3 帧都正是 ViewBridge 抛点,且都经 `_doWindowWillBeVisibleAsSheet:`。微信侧全部为同一版本 **4.1.11 (269136)**;CleanShot X 均为 **4.8.9**。

| # | Time (local) | Build | App | pid | Uptime at crash | Incident |
|---|---|---|---|---|---|---|
| 1 | 2026-07-09 11:16:16 | `26A5378j` | WeChat | 17187 | 16h35m | `E5D623CB-7A5F-4BC7-BACB-1A04E18B124B` |
| 2 | 2026-07-09 17:51:48 | `26A5378j` | WeChat | 7367 | 4h03m | `9BE1B09F-315B-4E06-ADE7-C9D1AFA3750F` |
| 3 | 2026-07-10 10:41:41 | `26A5378j` | WeChat | 26189 | 16h19m | `526C40E1-5D3C-4C22-8045-9E1EA78992E2` |
| 4 | 2026-07-10 16:48:42 | `26A5378j` | WeChat | 39541 | 6h04m | `7DB6E35A-6327-4C9D-90B0-956E8C58822E` |
| 5 | 2026-07-13 10:49:35 | `26A5378j` | WeChat | 7323 | 66h00m | `E1023A7A-9DA8-4A72-B48B-9ADBC8CDFE8E` |
| 6 | 2026-07-13 18:15:14 | `26A5378j` | WeChat | 3639 | 7h09m | `C0264F4C-E12B-4F4F-84F5-5A292052F774` |
| 7 | 2026-07-13 19:45:55 | `26A5378j` | **CleanShot X** | 53292 | 2h04m | `EF867893-F3DC-4C3D-B1E6-B6EAA9E3BC58` |
| 8 | 2026-07-14 10:17:36 | `26A5378j` | WeChat | 4351 | 14h30m | `FC741D75-ADDA-43BC-BCF6-1BFC7B04AB72` |
| — | *2026-07-14 02:55:50 — `macOS 27.0` installed (`…j` → `…n`); activated at the 10:58 reboot* | | | | | |
| 9 | 2026-07-14 13:59:08 | `26A5378n` | WeChat | 24895 | 2h48m | `7FF497C0-B596-497B-B51F-81D77C8C743A` |
| 10 | 2026-07-14 14:22:09 | `26A5378n` | WeChat | 14661 | 0h22m | `37DF5B93-6BF5-40C1-BDBE-8D1FB6C77F48` |
| 11 | 2026-07-14 15:06:20 | `26A5378n` | WeChat | 63251 | 0h41m | `69F90A59-BA5E-4621-8568-4D41FB59D9B0` |
| 12 | 2026-07-14 17:54:11 | `26A5378n` | WeChat | 60254 | 2h41m | `F4B3908D-0244-4822-A072-AC1F2588C551` |
| 13 | 2026-07-15 18:26:03 | `26A5378n` | WeChat | 22430 | 24h30m | `6E4A70E1-BDE5-4DC9-A79D-799D0CBE9E5D` |
| 14 | 2026-07-16 14:17:51 | `26A5378n` | WeChat | — | 4h09m | `9941EDFE-43AD-4838-A1FF-2AD8C86DF121` |
| 15 | 2026-07-17 10:30:35 | `26A5378n` | WeChat | — | 20h13m | `7F666349-6E2A-44EC-9A4E-F9CDE48AB041` |
| 16 | 2026-07-17 16:32:46 | `26A5378n` | WeChat | — | 6h02m | `AB9D9EBC-7997-48ED-A69D-4706F9096895` |
| 17 | 2026-07-17 17:25:28 | `26A5378n` | WeChat | — | 0h52m | `BABA5ABA-1AC7-456B-9CAB-8EF115405E5D` |
| 18 | 2026-07-19 17:16:46 | `26A5378n` | **CleanShot X** | — | ~79h | `E6B283DF-DA79-4A7E-8C29-3399DAA56610` |
| 19 | 2026-07-19 18:07:18 | `26A5378n` | **CleanShot X** | — | 0h50m | `ACF9295D-5832-4963-AB46-C38FA824F900` |
| — | *2026-07-2x — beta4 `26A5388g` installed (`…n` → `…g`)* | | | | | |
| 20 | 2026-07-21 17:47:34 | **`26A5388g`** | WeChat | 50320 | 4h11m | `600F54BC-FE44-4053-85F6-BEDE7AF3A198` |

**Survives two OS updates.** The `26A5378j` → `26A5378n` update (07-14) did **not** fix it (11 crashes on `…n`), and neither did the **beta4 `26A5388g`** update — WeChat crashed with the identical throw on 07-21 (entry 20). So this has now survived a beta3 revision *and* a full beta bump. Uptime at crash ranges 0h22m → ~79h, so it is not a "stale process" / long-uptime decay effect.

**熬过两次系统更新。** `26A5378j` → `26A5378n`(07-14)**未**修复(`…n` 上 11 次),**beta4 `26A5388g`** 同样没修 —— 07-21 微信以相同抛点再崩(第 20 条)。即它已经熬过一次 beta3 修订 *和* 一次完整的 beta 版本升级。崩溃时进程运行时长从 0h22m 到 ~79h 不等,故与"进程跑太久劣化"无关。

Throw site identical across all 13; only the AppKit sub-path varies slightly (some go through `__27-[NSWindow _doOrderWindow:]_block_invoke.766` + `NSPerformVisuallyAtomicChange`, others hit `-[NSWindow _doOrderWindow:]` directly) — the exception origin is the same.

13 次抛点完全一致;仅 AppKit 子路径略有差别(有的走 `_doOrderWindow:` 的 `block_invoke` + `NSPerformVisuallyAtomicChange`,有的直连 `_doOrderWindow:`),异常来源相同。

## What actually crashed / 真正的崩溃原因

The header says `EXC_BAD_ACCESS (SIGSEGV) … KERN_INVALID_ADDRESS at 0x0` — **red herring.** The real cause is an **uncaught Objective-C exception thrown inside Apple's ViewBridge**; WeChat's own signal handler then rewrites the resulting `abort()` into a null write to force a crash report.

崩溃头写 `EXC_BAD_ACCESS (SIGSEGV) … 0x0` 是**假象**。真因是 **Apple ViewBridge 内部抛未捕获 ObjC 异常** 导致 `abort()`,微信自带信号处理器再把它改写成空指针写入以强制生成报告。

### Throw site (Last Exception Backtrace) / 异常抛出点

```
0  CoreFoundation  __exceptionPreprocess
1  libobjc.A.dylib objc_exception_throw
2  CoreFoundation  _CFBundleGetValueForInfoKey + 0
3  ViewBridge      -[NSRemoteView containingWindowWillOrderOnScreen:] + 216   ← throws here
4  CoreFoundation  __CFNOTIFICATIONCENTER_IS_CALLING_OUT_TO_AN_OBSERVER__
8  Foundation      -[NSNotificationCenter postNotificationName:object:userInfo:]
9  AppKit          -[NSWindow _doWindowWillBeVisibleAsSheet:]                 ← window shown as a SHEET
…  AppKit          -[NSWindow _doOrderWindow:]
   WeChatAppEx Framework  (com.tencent.flue.framework)                        ← WeChat's embedded engine
   AppKit          -[NSWindow makeKeyAndOrderFront:]                          ← WeChat brings the viewer on screen
   wechat.dylib …
```

### Unwind → terminate (crashing thread 0) / 展开 → 终止

```
objc_exception_rethrow
-[NSRemoteView containingWindowWillOrderOnScreen:]
std::__terminate → demangling_terminate_handler → abort()
ilink_wrapper  ilink_nostl::ForceCrashOnSigAbort(int)   ← WeChat SIGABRT handler → deliberate write to 0x0
```

The `far: 0x0`, `byte write Translation fault` in the header comes from that last frame — **WeChat's crash reporter, not a WeChat pointer bug.**

## Diagnosis / 判断

`NSRemoteView` is **ViewBridge's out-of-process (XPC-hosted) view**. WeChat's 4.x image viewer is drawn by the embedded **WeChatAppEx `flue` engine** (`com.tencent.flue.framework`; the process is full of `ANGLE-Worker` / `libGLESv2` / `webview_io_thread` threads). "View image" presents a **sheet window that embeds a remote WeChatAppEx view**. When AppKit posts *will-order-on-screen*, the ViewBridge observer `-[NSRemoteView containingWindowWillOrderOnScreen:]` reads a bundle Info-plist key (`_CFBundleGetValueForInfoKey`) and throws — unhandled → `terminate` → `abort`.

**The faulting throw is 100% inside Apple frameworks** (ViewBridge → CFBundle). WeChat's only role is presenting an XPC-hosted view as a sheet on macOS 27. Same shape as **[#6 (Chrome ↔ MediaRemote)](chrome-mediaremote-nowplaying-crash.md)**: an uncaught ObjC exception raised *inside* an Apple framework during a system callback, killing the third-party app.

**抛异常那一步完全在 Apple 框架内**(ViewBridge → CFBundle),微信只是负责在 macOS 27 上把 XPC 托管视图作为 sheet 呈现。形态同 **[#6(Chrome ↔ MediaRemote)](chrome-mediaremote-nowplaying-crash.md)**。

## Second app — CleanShot X (same throw, no WeChat involved) / 第二个 app —— CleanShot X(同一抛点,与微信无关)

**CleanShot X 4.8.9** (`pl.maketheweb.cleanshotx`) has now crashed with the **byte-identical throw site 3 times** — a completely unrelated, sandbox-free app, reached through a **different remote-view provider**: the system's own **QuickLook** seamless preview (`QLSeamlessDocumentOpener`), presented after a capture. Two apps, two remote-view providers, one throw site — this all but rules out any single third-party app being at fault.

**CleanShot X 4.8.9**(`pl.maketheweb.cleanshotx`)现已以**逐字相同的抛点崩溃 3 次** —— 一个与微信毫不相关的 app,经由**另一套 remote-view 提供方**触达:系统自带的 **QuickLook** 无缝预览(`QLSeamlessDocumentOpener`),截图/录屏后弹预览时崩。两个 app、两套 remote-view 提供方、同一个抛点,几乎彻底排除某个第三方 app 单独背锅的可能。

| | #7 | #18 | #19 |
|---|---|---|---|
| Time (local) | 2026-07-13 19:45:55 | 2026-07-19 17:16:46 | 2026-07-19 18:07:18 |
| Build | `26A5378j` | `26A5378n` | `26A5378n` |
| pid | 53292 | — | — |
| Incident | `EF867893-…` | `E6B283DF-…` | `ACF9295D-…` |
| Uptime at crash | ~2 h 04 m | ~79 h | ~0 h 50 m (relaunch after #18) |
| Exception | `EXC_CRASH (SIGABRT)` — `abort() called` (**unmasked**) | same | same |

The 07-19 pair is the same relaunch-and-recrash shape WeChat shows: #18 crashed, CleanShot X was reopened, and ~50 min later #19 hit the identical throw again.

07-19 这一对与微信一样是"重启即再崩":#18 崩后重开 CleanShot X,约 50 分钟后 #19 又撞上同一抛点。

### Why CleanShot X is the *cleaner* data point / 为什么 CleanShot X 是更干净的证据

WeChat installs its own SIGABRT handler (`ilink_nostl::ForceCrashOnSigAbort`) that rewrites the `abort()` into a write to `0x0`, so its header lies (`EXC_BAD_ACCESS 0x0`). CleanShot X does **not** — it dies with a plain `EXC_CRASH (SIGABRT)` / `abort() called`, so its report shows the bug in its **native, unmasked form**: `objc_exception_rethrow → std::__terminate → demangling_terminate_handler → abort()`.

微信自带 SIGABRT 处理器把 `abort()` 改写成写 `0x0`,崩溃头是假象(`EXC_BAD_ACCESS 0x0`)。CleanShot X **没有**改写,直接 `EXC_CRASH (SIGABRT)` / `abort() called`,所以它的报告呈现该 bug 的**原始、未掩盖形态**。

### Side-by-side / 逐帧对照

```
                          WeChat 4.1.11                         CleanShot X 4.8.9
throw   ViewBridge  -[NSRemoteView containingWindowWillOrderOnScreen:] + 216   ← identical, same +216
        CoreFoundation  _CFBundleGetValueForInfoKey + 0                        ← identical
sheet   AppKit  -[NSWindow _doWindowWillBeVisibleAsSheet:]                     ← identical (shown as SHEET)
order   AppKit  -[NSWindow _doOrderWindow:] → makeKeyAndOrderFront:            ← identical
provider  WeChatAppEx (com.tencent.flue.framework)   |   QuickLookUI -[QLSeamlessDocumentOpener showWindow:…]   ← only this frame differs
present   wechat.dylib …                             |   -[NSWindowController showWindow:] → CleanShot X
```

The **only** difference is the one frame that presents the out-of-process view (WeChat's `flue` engine vs Apple's own `QLSeamlessDocumentOpener`). Everything from `_doWindowWillBeVisibleAsSheet:` up through the throw is identical — so the fault lives in the shared Apple path, not in either app.

**唯一**的差别是呈现跨进程视图那一帧(微信 `flue` 引擎 vs 苹果自己的 `QLSeamlessDocumentOpener`)。从 `_doWindowWillBeVisibleAsSheet:` 到抛点完全一致 → 根因在共享的 Apple 路径,不在任何一个 app。

### Same behavioural fingerprint / 行为指纹一致

Both apps are **non-deterministic and recover on retry**: repeating the exact action (WeChat: re-click the image / CleanShot X: capture + show preview again) does **not** reliably re-hit the throw. A deterministic app bug would crash every time on the same action; a race inside ViewBridge's order-on-screen path is exactly this flaky-but-identical shape.

**Not low-frequency, though** — that earlier characterisation was based on 2 known crashes and is now retired: WeChat alone hit it **12 times in 7 days, 4× on 07-14**. Per *attempt* it is intermittent; per *day of normal use* it is routine.

两个 app 都表现为**非确定、重试即恢复**:重复同样操作(微信再点图 / CleanShot X 再截图弹预览)都**不**稳定重现。确定性 app bug 会每次必崩;ViewBridge 上屏路径里的竞态才是这种"时崩时不崩、签名却逐字一致"的形态。

**但并非"低频"** —— 之前"低频"的判断基于当时仅知的 2 次,现已作废:光微信就 **7 天 12 次、07-14 单日 4 次**。按"每次操作"看是偶发,按"每天正常使用"看是常态。

## Not the `duo-pasted` crash / 与 `duo-pasted` 崩溃无关

A grep for `containingWindowWillOrderOnScreen` / `NSRemoteView` across all reports also matched `duo-pasted-2026-07-07-083914.ips`, but that is an **unrelated `EXC_BREAKPOINT`/SIGTRAP** (an uncaught exception during `NSView` **layout**, `+[NSApplication _crashOnException:]`), with `NSRemoteView` only on a live background thread — a different throw site, not a second data point for this bug.

对全部报告 grep 还命中 `duo-pasted-2026-07-07-083914.ips`,但那是**无关的 `EXC_BREAKPOINT`/SIGTRAP**(NSView **布局**期抛异常),`NSRemoteView` 只在其空闲后台线程上,抛点不同,不算本 bug 的数据点。

## Workaround / 临时规避

None confirmed. It crashes while *presenting* the viewer (an out-of-process sheet), so **retrying — click the image again — usually reopens it**; a fresh order-on-screen doesn't reliably re-hit the throw. To view a stubborn image, drag it out / save then open in Preview to avoid the WeChatAppEx sheet.

暂无确认规避。崩在**呈现**看图器(跨进程 sheet)时,**再点一次通常就能打开**;实在打不开就把图拖出/另存后用「预览」看,绕开 WeChatAppEx sheet。

## Notes / 备注

- Every crash report has `share_with_app_devs = 0` — none auto-sent to either vendor. (Re-verified on the 9 reports still on disk 2026-07-21; the 11 older `…j`/early-`…n` reports have since rotated out of `DiagnosticReports`, but were 0 when logged.)
- Distinct from **[#10](wechat-mas-crash-fixed.md)** (a 4.1.9 MAS *launch* crash, fixed in 4.1.10). This is a *4.1.11* image-viewer crash — a different bug.
- **Cross-app** (WeChat `flue` engine + Apple's own QuickLook), byte-identical throw → strengthens the Apple Feedback: the exception fires in ViewBridge's own order-on-screen observer regardless of who presents the remote view. Worth a Feedback (ViewBridge exception on window order-on-screen as sheet) + a minimal repro (any remote/XPC-hosted view presented as a sheet).
- **Feedback is now overdue and the case only keeps getting stronger:** 20 verified crashes across two unrelated apps, and **persistence across two OS updates** — the `…j` → `…n` beta3 revision *and* the **beta4 `26A5388g`** bump (i.e. Apple has now shipped two builds and this survived both). The `FB____` placeholder should be filed — this is the only 🔴 entry left in the log.
- A vendor-facing email to **CleanShot X** (MakeTheWeb) is drafted — reports the Apple root cause and suggests they present the QuickLook preview off the sheet path / guard the `showWindow:` call so an AppKit exception during order-on-screen doesn't abort the whole app.
- 现已**跨 app**(微信 `flue` 引擎 + 苹果自家 QuickLook),抛点逐字一致 → 加强 Apple Feedback:无论谁来呈现 remote view,异常都在 ViewBridge 自己的上屏 observer 里触发。值得提 Feedback + 做最小复现(任意 XPC 托管视图作为 sheet 呈现)。
- 已为 **CleanShot X**(MakeTheWeb)起草一封厂商邮件:说明 Apple 根因,并建议把 QuickLook 预览挪出 sheet 路径 / 给 `showWindow:` 加保护,避免上屏时的 AppKit 异常把整个 app 拖崩。
