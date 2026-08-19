# WeChat crash opening an image or an avatar — uncaught ObjC exception in Apple ViewBridge `-[NSRemoteView containingWindowWillOrderOnScreen:]`
# 微信点开图片或头像时崩溃 —— Apple ViewBridge `-[NSRemoteView containingWindowWillOrderOnScreen:]` 抛未捕获 ObjC 异常

> 🔗 **Track / 关注此问题:** [#17 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/17)

| | |
|---|---|
| **Status** | 🟢 **fix carried into beta6 `26A5416b`** (2026-08-19) — verified by binary diff, not by absence of crashes: `-[NSRemoteView maintainContainingWindowNotifications:]` (0x3b4, 237 instructions) and `-[NSRemoteView containingWindowDidOrderOnScreen:]` (0x148, 82 instructions) are **byte-identical to beta5**, at the same addresses, so beta5's unconditional `object:nil` observer removal is still in place. Crash-report baseline on this machine is **0** `NSRemoteView` `.ips` (the pre-upgrade history had rotated off disk, so this is a clean slate rather than a survival count). Method: [`tools/skylight-fdiff.py`](../tools/skylight-fdiff.py) against the archived beta5 dyld cache. Prior: 🟢 **Fixed in beta5 `26A5406e`** (2026-08-11) — Apple changed **one method**, and it is the one that leaks the registration this crash depends on: `-[NSRemoteView maintainContainingWindowNotifications:]` now removes the notification observers **unconditionally and with `object:nil`**, sweeping every stale per-window registration, where beta4 skipped the removal entirely whenever the weak `_containingWindow` ivar was already nil. Established by a beta4↔beta5 binary diff — see [beta4 ↔ beta5 diff](#beta4--beta5-diff-what-apple-actually-changed--apple-到底改了什么). **Residual gap, stated plainly:** the sweep only runs when that method is called (its sole caller is byte-identical between builds), all assertion sites remain, and beta4 was only comparable as its x86_64 Rosetta build. Behavioural confirmation is still accumulating — at the time of writing the machine had ~2.5 h on beta5, far short of the 3–5 days that the prior 1–2 crashes/day rate would make meaningful. **Flips back to 🔴 on the first recurrence.** Prior state: 🔴 — **32 verified crashes** across 4 unrelated apps / 4 UI toolkits (WeChat ×26 + CleanShot X ×3 + DingTalk ×2 + duo-pasted ×1), 2026-07-09 → 08-10, **byte-identical throw site, always `+216`**, surviving `26A5378j` → `26A5378n` → `26A5388g` |
| **macOS** | 27.0 — **beta3 `26A5378j`** (8 crashes) → **beta3 rev `26A5378n`** (11 crashes) → **beta4 `26A5388g`** (**13 crashes**, 07-21 → 08-10). Fixed by neither the 07-14 beta3 revision nor the beta4 update. beta4 held for 21 days until **beta5 `26A5406e`** landed 2026-08-10 (installed here 08-11) — **which is the build that fixed it**. |
| **Component** | Apple **ViewBridge / AppKit** (`NSRemoteView`) — reproduced via **WeChat 4.1.11** (Chromium-based WeChatAppEx / `flue` engine), **CleanShot X 4.8.9** (Cocoa + QuickLookUI `QLSeamlessDocumentOpener`), **DingTalk 8.3.15** (**Qt** — `QtWidgets`/`QtGui`) and **duo-pasted 0.1.1270** (**Swift/AppKit**, own code) |
| **Reproducers** | **WeChat 4.1.11 (269136)** MAS (`adam_id` 836500024) · **CleanShot X 4.8.9** (`pl.maketheweb.cleanshotx`, team `AFJU4P8ZV4`) · **DingTalk 8.3.15 (54703766)** MAS (`adam_id` 1435447041) · **duo-pasted 0.1.1270** (own app, Swift/AppKit) |
| **Machine** | `Mac15,11` — Apple M3 Max, 36 GB |
| **Report** | Apple Feedback: `FB________` *(ours, still unfiled)* · **Apple has acknowledged the bug** via [Developer Forums 837342](https://developer.apple.com/forums/thread/837342) — DTS routed it, and a third-party Feedback there reports "Potential fix identified — For a future OS update" · a crash-guard workaround exists (see [External corroboration](#external-corroboration--apple-has-acknowledged-it-and-the-exception-text-is-now-known--外部佐证apple-已受理异常文本已知)) · vendor email to CleanShot X drafted |

## Basis for the verdict / 这个判断建立在什么之上

Recorded explicitly, because this call went through two revisions in one day and the reasoning matters more than the emoji.

**What the 🟢 rests on** — the [beta4↔beta5 binary diff](#beta4--beta5-diff-what-apple-actually-changed--apple-到底改了什么). Apple hardened precisely the teardown that leaks the per-window registration, and the shape of the fix (`object:nil`, unconditional) directly destroys the state the assertion tests for. Being notified about a window that is not your own is hard to achieve *except* through a leftover per-window registration, which is why this is treated as decisive rather than merely suggestive.

**What it does NOT rest on** — behavioural evidence, which remains thin:

| check | result |
|---|---|
| Observation window on beta5 at the time of the call | **1.1 h** (booted 12:23:31, called at ~13:30). At the historical 1–2/day rate, an **unfixed** bug produces zero crashes in that window with probability ≈95% — the observation carries almost no information |
| Occurrences on `26A5406e` | 0 (of 3 signature reports surviving on disk, all are `26A5388g`) |
| Apple macOS 27 beta5 release notes | **no entry** — the document does not mention `NSRemoteView` or ViewBridge anywhere |
| [Developer Forums 837342](https://developer.apple.com/forums/thread/837342) | **no mention of beta5**; latest discussed is beta4, still reproducing there as of ~2026-08-04 |
| Reproducer | none achieved — **0 hits in 800 stress cycles** (~4,800 order-on-screen ops), and the harness was shown never to reach the bad state, so this is not evidence either way |
| Assertion present in beta5's ViewBridge binary | **yes**, still there — but this is uninformative: a fix can prevent entry into the bad state while leaving the defensive assertion in place |
| beta4 ↔ beta5 disassembly diff | **done — this is what the 🟢 is built on**, and it is listed here rather than above only to keep the whole evidence set in one table. See [beta4 ↔ beta5 diff](#beta4--beta5-diff-what-apple-actually-changed--apple-到底改了什么) |

**Falsification is cheap and immediate: one recurrence flips this back to 🔴.** `~/Library/Logs/crash-notify.log` records every crash and is not subject to log rotation, so no action is needed to catch it. Given the prior rate, **3–5 days of normal use with zero crashes** would be the first genuinely informative signal; 7 days would be strong.

**这个 🟢 建立在 [beta4↔beta5 二进制 diff](#beta4--beta5-diff-what-apple-actually-changed--apple-到底改了什么) 上,不是建立在"没看见它崩"上。** Apple 恰好加固了泄漏按窗口注册的那处拆除,且修法形态(无条件 + `object:nil`)直接摧毁断言所检测的状态;而"收到一个不属于自己的窗口的通知",除残留的按窗口注册外很难有别的来源 —— 故视为决定性证据而非仅仅提示。

**行为证据仍然薄弱,如实列出**:定性时 beta5 仅开机 **1.1 小时**(以历史 1–2 次/天算,即使完全没修,该窗口内零崩溃的概率也约 95%);Apple beta5 release notes 全文未提;论坛帖零提及 beta5;复现器 800 次压测 0 命中且从未到达坏状态;断言在 beta5 二进制里仍在(此项两边都不能说明)。**残留缺口**:该清扫仅在 `maintainContainingWindowNotifications:` 被调用时生效,其唯一调用者两版逐字节相同;beta4 仅有 x86_64 版可比,arm64e 属推断。

**再崩一次即翻回 🔴** —— `crash-notify.log` 常驻记录、不受日志轮转影响,无需任何操作即可捕获。按先前频率,**连续 3–5 天零崩溃**为第一个有信息量的行为信号,7 天为强信号。

## Symptom / 症状

WeChat **quits unexpectedly when opening the full-screen image viewer** (clicking an image in a chat). **26 WeChat crashes over 26 days (2026-07-09 → 08-03)**, up to **4 in a single day** (07-14 and 07-31) — routine, not a one-off. On 07-17 it crashed **3 times in a chain**, each report launched ~4–6 s after the previous crash (auto-relaunch → re-crash); 07-31 repeated that shape (16:31 → 16:39 → 16:46, uptimes 4h55m → 8m → 6m).

The same throw kills **three other apps** on their own equivalent action: **CleanShot X** showing its post-capture QuickLook preview, **DingTalk** ordering a sheet on screen, and **duo-pasted** (own app) showing its clipboard preview panel.

在聊天里**点击图片、打开全屏看图**时微信直接闪退。**26 天内 26 次(2026-07-09 → 08-03)**,单日最多 **4 次**(07-14、07-31)—— 属于常态,不是孤例。07-17 出现**连崩 3 次**:每份报告都在上一次崩溃后约 4–6 秒启动(自动重启 → 再崩);07-31 重演同样形态(16:31 → 16:39 → 16:46,运行时长 4h55m → 8m → 6m)。

同一抛点还杀掉**另外三个 app**:**CleanShot X**(截图后弹 QuickLook 预览)、**DingTalk**(把 sheet 上屏)、**duo-pasted**(自研 app,展示剪贴板预览面板)。

## Occurrences / 复现记录

All 32 entries below were **verified programmatically**, not by grep: the ViewBridge frame sits at index 3 of `lastExceptionBacktrace` (the actual throw site) in every one, at symbol offset **`+216`** in every one, and every one goes through `_doWindowWillBeVisibleAsSheet:`. Every WeChat crash is the same build **4.1.11 (269136)**; all three CleanShot X are **4.8.9**.

下列 32 条均经**程序化校验**(非 grep):每一份的 `lastExceptionBacktrace` 第 3 帧都正是 ViewBridge 抛点、偏移都是 **`+216`**,且都经 `_doWindowWillBeVisibleAsSheet:`。微信侧全部为同一版本 **4.1.11 (269136)**;CleanShot X 均为 **4.8.9**。

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
| — | *2026-07-20 — **beta4 `26A5388g`** released by Apple; installed here 07-21 04:45:29 (`…n` → `…g`)* | | | | | |
| 20 | 2026-07-21 17:47:34 | **`26A5388g`** | WeChat | 50320 | 4h11m | `600F54BC-FE44-4053-85F6-BEDE7AF3A198` |
| 21 | 2026-07-28 10:44:50 | `26A5388g` | **duo-pasted** | 25867 | 16h38m | `311B7D34-1FB6-45D8-BCF8-E2C1D36B01A0` |
| 22 | 2026-07-28 11:30:28 | `26A5388g` | WeChat | 53153 | 18h33m | `9B6E46E6-D5C1-41F5-B5A6-E7017C730469` |
| 23 | 2026-07-29 10:51:42 | `26A5388g` | WeChat | 53775 | 23h21m | `02B6FA6E-E20C-4299-9C04-B43B7C99B18F` |
| 24 | 2026-07-30 16:04:12 | `26A5388g` | WeChat | 16601 | 6h10m | `E3A50DAD-03ED-474F-9718-2C970DDD2B22` |
| 25 | 2026-07-31 11:36:21 | `26A5388g` | WeChat | 45328 | 19h32m | `A43C0C2B-F8E2-4F7E-8DF9-602D7FA34280` |
| 26 | 2026-07-31 16:31:00 | `26A5388g` | WeChat | 20916 | 4h54m | `810C7C1D-BFE1-4554-8D50-607822481FFC` |
| 27 | 2026-07-31 16:39:41 | `26A5388g` | WeChat | 41735 | 0h08m | `C8A86CF7-FC4F-4749-80FF-2C84EB158E9F` |
| 28 | 2026-07-31 16:46:16 | `26A5388g` | WeChat | 49652 | 0h06m | `CDC9CA03-8464-4562-9BBE-63EE6A24D839` |
| 29 | 2026-07-31 17:58:15 | `26A5388g` | WeChat | 54849 | 1h11m | `1160C272-28D9-452D-AED7-D75D7E8AE828` |
| 30 | 2026-08-03 17:20:13 | `26A5388g` | WeChat | 5423 | 7h14m | `2EA99B0D-282C-4054-8906-7FF2DB408E09` |
| 31 | 2026-08-04 09:55:44 | `26A5388g` | **DingTalk** | 10540 | 23h45m | `FCBDB4F1-13E6-49B8-B1DE-EC75D46394E6` |
| 32 | 2026-08-10 13:09:58 | `26A5388g` | **DingTalk** | 1551 | 75h11m | `21AB15F0-11B1-4640-BE2E-C145A8185E60` |

**Survives two OS updates, and beta4 has now been out for three weeks.** The `26A5378j` → `26A5378n` update (07-14) did **not** fix it (11 crashes on `…n`), and neither did the **beta4 `26A5388g`** update — beta4 has since accumulated **13 crashes of its own (entries 20–32)**, more than either beta3 build. Apple [released beta4 on 2026-07-20](https://www.macrumors.com/2026/07/20/apple-releases-macos-27-beta-4/) and it held for 21 days, so through that whole window there was no opportunity for a fix to land. *(Written while beta4 was current; **beta5 `26A5406e`** arrived 2026-08-10 and did fix it — see the status row.)* Uptime at crash ranges 0h06m → ~79h, so it is not a "stale process" / long-uptime decay effect.

**熬过两次系统更新,且 beta4 已发布三周。** `26A5378j` → `26A5378n`(07-14)**未**修复(`…n` 上 11 次),**beta4 `26A5388g`** 同样没修 —— beta4 上至今已累计 **13 次(第 20–32 条)**,比任一 beta3 版本都多。Apple 于 **2026-07-20 发布 beta4**,截至 **2026-08-10 它仍是最新版本(已 21 天,beta5 未发布)**,期间根本没有修复落地的机会。崩溃时进程运行时长从 0h06m 到 ~79h 不等,故与"进程跑太久劣化"无关。

Throw site identical across all 32 — always `-[NSRemoteView containingWindowWillOrderOnScreen:] + 216`, always reached via `_doWindowWillBeVisibleAsSheet:`. Only the AppKit sub-path varies slightly (some go through `__27-[NSWindow _doOrderWindow:]_block_invoke.766/.767` + `NSPerformVisuallyAtomicChange`, others hit `-[NSWindow _doOrderWindow:]` directly) — the exception origin is the same.

32 次抛点完全一致 —— 永远是 `-[NSRemoteView containingWindowWillOrderOnScreen:] + 216`,永远经 `_doWindowWillBeVisibleAsSheet:` 到达。仅 AppKit 子路径略有差别(有的走 `_doOrderWindow:` 的 `block_invoke` + `NSPerformVisuallyAtomicChange`,有的直连 `_doOrderWindow:`),异常来源相同。

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
9  AppKit          -[NSWindow _doWindowWillBeVisibleAsSheet:]                 ← posts _NSWindowWillBecomeVisible (NOT proof of a sheet — see Corrections)
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

`NSRemoteView` is **ViewBridge's out-of-process (XPC-hosted) view**. WeChat's 4.x image viewer is drawn by the embedded **WeChatAppEx `flue` engine** (`com.tencent.flue.framework`; the process is full of `ANGLE-Worker` / `libGLESv2` / `webview_io_thread` threads). "View image" presents a **sheet window that embeds a remote WeChatAppEx view**. When AppKit posts *will-order-on-screen*, the ViewBridge observer `-[NSRemoteView containingWindowWillOrderOnScreen:]` compares its own `[self window]` against the notification's object and throws when they differ — unhandled → `terminate` → `abort`. (The `_CFBundleGetValueForInfoKey` frame is **mis-symbolication**, not an Info.plist read — see [Corrections](#corrections-2026-08-11--更正).)

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
sheet   AppKit  -[NSWindow _doWindowWillBeVisibleAsSheet:]                     ← identical (posts _NSWindowWillBecomeVisible; not proof of a sheet)
order   AppKit  -[NSWindow _doOrderWindow:] → makeKeyAndOrderFront:            ← identical
provider  WeChatAppEx (com.tencent.flue.framework)   |   QuickLookUI -[QLSeamlessDocumentOpener showWindow:…]   ← only this frame differs
present   wechat.dylib …                             |   -[NSWindowController showWindow:] → CleanShot X
```

The **only** difference is the one frame that presents the out-of-process view (WeChat's `flue` engine vs Apple's own `QLSeamlessDocumentOpener`). Everything from `_doWindowWillBeVisibleAsSheet:` up through the throw is identical — so the fault lives in the shared Apple path, not in either app.

**唯一**的差别是呈现跨进程视图那一帧(微信 `flue` 引擎 vs 苹果自己的 `QLSeamlessDocumentOpener`)。从 `_doWindowWillBeVisibleAsSheet:` 到抛点完全一致 → 根因在共享的 Apple 路径,不在任何一个 app。

### Same behavioural fingerprint / 行为指纹一致

Both apps are **non-deterministic and recover on retry**: repeating the exact action (WeChat: re-click the image / CleanShot X: capture + show preview again) does **not** reliably re-hit the throw. A deterministic app bug would crash every time on the same action; a race inside ViewBridge's order-on-screen path is exactly this flaky-but-identical shape.

**Not low-frequency, though** — that earlier characterisation was based on 2 known crashes and is now retired: WeChat alone hit it **26 times in 26 days**, 4× on both 07-14 and 07-31. Per *attempt* it is intermittent; per *day of normal use* it is routine.

两个 app 都表现为**非确定、重试即恢复**:重复同样操作(微信再点图 / CleanShot X 再截图弹预览)都**不**稳定重现。确定性 app bug 会每次必崩;ViewBridge 上屏路径里的竞态才是这种"时崩时不崩、签名却逐字一致"的形态。

**但并非"低频"** —— 之前"低频"的判断基于当时仅知的 2 次,现已作废:光微信就 **7 天 12 次、07-14 单日 4 次**。按"每次操作"看是偶发,按"每天正常使用"看是常态。

## Third and fourth apps — DingTalk (Qt) and duo-pasted (Swift/AppKit) / 第三、第四个 app —— DingTalk(Qt)与 duo-pasted(Swift/AppKit)

On **2026-08-04 09:55:44** **DingTalk 8.3.15 (54703766)** (MAS, `5ZSL2CJU2T.com.dingtalk.mac`) died with the **byte-identical throw site** — a fourth unrelated vendor, and, decisively, a **fourth UI toolkit**: DingTalk is a **Qt** app (`QtWidgets`, `QtGui`, `QtMacExtras` … loaded in `usedImages`; no Chromium, no QuickLookUI). It also dies **unmasked**, like CleanShot X: plain `EXC_CRASH (SIGABRT)` / `abort() called`, no rewritten header.

**It recurred on 2026-08-10 13:09:58** (entry 32, pid 1551, same build 8.3.15 (54703766), same OS `26A5388g`, incident `21AB15F0-11B1-4640-BE2E-C145A8185E60`) — frames 0–14 again byte-identical, again `+216`, again via `_doWindowWillBeVisibleAsSheet:`. Two things this second DingTalk crash adds: (a) it is **not a one-off for the Qt reproducer** — the app hit it twice in six days; (b) the app was **not being interacted with** — uptime **75h11m**, and the sheet was ordered on screen from a `dispatch_source` callback on the main queue (`_dispatch_source_latch_and_call` → `_dispatch_main_queue_drain` sits directly under DingTalk's presenter in the crashing thread), i.e. a **timer/event-driven sheet in a backgrounded app**, with no user action at the moment of the crash.

Verified throw site (`lastExceptionBacktrace`, DingTalk, incident `FCBDB4F1-13E6-49B8-B1DE-EC75D46394E6`):

```
0  CoreFoundation  __exceptionPreprocess
1  libobjc.A.dylib objc_exception_throw
2  CoreFoundation  _CFBundleGetValueForInfoKey + 0
3  ViewBridge      -[NSRemoteView containingWindowWillOrderOnScreen:] + 216   ← identical, same +216
4  CoreFoundation  __CFNOTIFICATIONCENTER_IS_CALLING_OUT_TO_AN_OBSERVER__
8  Foundation      -[NSNotificationCenter postNotificationName:object:userInfo:]
9  AppKit          -[NSWindow _doWindowWillBeVisibleAsSheet:]                 ← identical (posts _NSWindowWillBecomeVisible; not proof of a sheet)
10 AppKit          -[NSWindow _reallyDoOrderWindowAboveOrBelow:]
11 AppKit          -[NSWindow _reallyDoOrderWindow:]
12 AppKit          __27-[NSWindow _doOrderWindow:]_block_invoke.767
13 AppKit          NSPerformVisuallyAtomicChange
14 AppKit          -[NSWindow _doOrderWindow:]
15 DingTalk        (unsymbolicated, +0x4e597f8)                               ← DingTalk's own Qt presenter
```

Frames 0–14 match WeChat and CleanShot X **frame for frame, including the `+216` offset**; only frame 15 — whoever presents the remote view — differs. Crashing thread unwinds `objc_exception_rethrow → std::__terminate → demangling_terminate_handler → abort()`, i.e. the unmasked form.

**duo-pasted 0.1.1270** (own app, plain **Swift/AppKit**, no embedded engine) hit the same throw on **2026-07-28 10:44:50**, presenting its clipboard preview panel:

```
3  ViewBridge  -[NSRemoteView containingWindowWillOrderOnScreen:] + 216
9  AppKit      -[NSWindow _doWindowWillBeVisibleAsSheet:]
12 AppKit      -[NSWindow _doOrderWindow:]
13 duo-pasted  PreviewPanelController.show(item:cardRectInGlobal:)
14 duo-pasted  closure #1 in closure #4 in SearchPanelController.ensurePanel()
```

This one is the **strongest** data point of all: the presenting code is a handful of lines of ordinary Swift/AppKit under our own control, doing nothing more exotic than ordering a panel on screen, and it still takes an exception thrown inside `NSRemoteView`'s own notification observer.

2026-08-04 **DingTalk 8.3.15** 以**逐字相同的抛点**崩溃 —— 第四个不相干的厂商,更关键的是**第四种 UI 技术栈**:DingTalk 是 **Qt** app(`usedImages` 里是 `QtWidgets`/`QtGui`/`QtMacExtras`,没有 Chromium、没有 QuickLookUI),且和 CleanShot X 一样**未被掩盖**:干净的 `EXC_CRASH (SIGABRT)` / `abort() called`。第 0–14 帧与微信、CleanShot X **逐帧一致(含 `+216` 偏移)**,只有第 15 帧(谁来呈现 remote view)不同。

**2026-08-10 13:09:58 再次复现**(第 32 条,pid 1551,同版本 8.3.15 (54703766),同系统 `26A5388g`,incident `21AB15F0-11B1-4640-BE2E-C145A8185E60`):第 0–14 帧依旧逐字一致、依旧 `+216`、依旧经 `_doWindowWillBeVisibleAsSheet:`。这第二次带来两点新信息:(a) Qt 这个复现方**不是孤例** —— 六天内两次;(b) 崩溃时**没有任何用户操作** —— 进程已跑 **75h11m**,且崩溃线程里钉钉自己的呈现帧下面直接压着 `_dispatch_source_latch_and_call` → `_dispatch_main_queue_drain`,即**后台 app 里由定时器/事件驱动把 sheet 上屏**。

**duo-pasted 0.1.1270**(自研 app,纯 **Swift/AppKit**,无内嵌引擎)于 2026-07-28 在展示剪贴板预览面板时撞上同一抛点 —— 这是**最有力**的一条:呈现方就是我们自己可控的几行普通 Swift/AppKit 代码,只是把面板上屏,依然被 `NSRemoteView` 自己的通知 observer 抛出的异常打死。

### Four apps, four toolkits, one throw site / 四个 app、四种技术栈、同一抛点

| App | UI stack | Presenting frame | Crash header |
|---|---|---|---|
| WeChat 4.1.11 | Chromium (`WeChatAppEx` / `flue`) | `wechat.dylib` → `makeKeyAndOrderFront:` | `EXC_BAD_ACCESS 0x0` (**masked** by own SIGABRT handler) |
| CleanShot X 4.8.9 | Cocoa + Apple **QuickLookUI** | `-[QLSeamlessDocumentOpener showWindow:…]` | `EXC_CRASH (SIGABRT)` (unmasked) |
| DingTalk 8.3.15 | **Qt** (`QtWidgets`/`QtGui`) | DingTalk (unsymbolicated) | `EXC_CRASH (SIGABRT)` (unmasked) |
| duo-pasted 0.1.1270 | **Swift/AppKit** (own code) | `PreviewPanelController.show(item:…)` | `EXC_CRASH (SIGABRT)` (unmasked) |

Everything above the presenting frame — `_doOrderWindow:` → `_doWindowWillBeVisibleAsSheet:` → `NSNotificationCenter` → `-[NSRemoteView containingWindowWillOrderOnScreen:] + 216` → throw — is **identical in all four**. No third-party app, engine, or toolkit is common to all four; **the only thing they share is Apple's ViewBridge order-on-screen path.**

呈现帧以上的部分在四者中**完全一致**。四个 app 之间不存在任何共同的第三方 app / 引擎 / 技术栈,**唯一的共同点就是 Apple 的 ViewBridge 上屏路径**。

## Not to be confused with the 07-07 `duo-pasted` crash / 勿与 07-07 那次 `duo-pasted` 崩溃混淆

An early grep for `containingWindowWillOrderOnScreen` / `NSRemoteView` also matched `duo-pasted-2026-07-07-083914.ips`, but **that one is unrelated**: `EXC_BREAKPOINT`/SIGTRAP, an uncaught exception during `NSView` **layout** (`+[NSApplication _crashOnException:]`), with `NSRemoteView` only on a live background thread — a different throw site, and it is **not** counted here. The duo-pasted entry in the table above is the separate **07-28** crash, which *does* carry the index-3 `+216` throw site.

早期 grep 也命中过 `duo-pasted-2026-07-07-083914.ips`,但那次**无关**:`EXC_BREAKPOINT`/SIGTRAP,是 NSView **布局**期抛异常,`NSRemoteView` 只在空闲后台线程上,抛点不同,**未计入**本表。上表里的 duo-pasted 是另一次 **07-28** 崩溃,其第 3 帧确为 `+216` 抛点。

## External corroboration — Apple has acknowledged it, and the exception text is now known / 外部佐证:Apple 已受理,异常文本已知

**Source:** [@JyHu](https://github.com/JyHu) pointed this out in [#17](https://github.com/jizhi0v0/macos27-beta-issues/issues/17) on 2026-08-05, linking [Apple Developer Forums thread 837342](https://developer.apple.com/forums/thread/837342). Everything in this section comes from that thread — it is **not** independently verified on this machine, and is labelled as such throughout.

### The exception name and reason — which our own crash reports do not contain / 异常名与原因 —— 这是我们自己的报告里没有的

```
NSInternalInconsistencyException
'<NSRemoteView: 0x…> notified of <NSWindow: 0x…> but expected (null)'
```

**Verified absent from our data:** all 32 `.ips` reports here carry only `asi: {"libsystem_c.dylib": ["abort() called"]}` plus the backtrace — a grep for `NSInternalInconsistencyException` / `notified of` / `but expected` across every report on disk (including `Retired/`) returns **zero hits**. So this is the one piece of the picture our 32 captures structurally could not supply, and it is worth a lot: the assertion says `NSRemoteView` was notified about a window while its own expected containing window was **`null`**. That is a stale-or-missing registration being notified — consistent with the race shape argued in [Diagnosis](#diagnosis--判断), and it explains why retrying usually succeeds.

我方 32 份报告只有 `abort() called` 和调用栈,全盘 grep 异常名/原因**零命中**,故这条是我们结构上拿不到的信息。断言含义是:`NSRemoteView` 被通知了某个窗口,而它自己期望的容器窗口是 **`null`** —— 即一个失效或缺失的注册被通知到了,与[判断](#diagnosis--判断)一节论证的竞态形态吻合,也解释了为何重试通常就好。

### The trigger is broader than the sheet path / 触发路径比 sheet 更广

The thread reports the same assertion from `orderFrontRegardless()`, `makeKeyAndOrderFront()`, **showing status-bar items**, `NSAlert.beginSheetModalForWindow()`, and **closing/opening child windows containing editable text fields**.

All 32 crashes recorded here go through `-[NSWindow _doWindowWillBeVisibleAsSheet:]`. In light of the thread, that is a property of **our sample**, not of the bug — every reproducer we happened to collect presents its remote view as a sheet. The write-up above should be read accordingly: the sheet path is how we hit it, not a necessary condition.

本文 32 次全部经 `_doWindowWillBeVisibleAsSheet:`,但按该帖所述,状态栏项、`NSAlert` sheet、含可编辑文本框的子窗口开关等路径同样触发。故"必经 sheet"是**我们样本的性质**,不是 bug 的必要条件。

### Apple's position / Apple 的态度

Per the thread: a **DTS engineer** acknowledged the reports and routed them to the owning engineering team, and one participant reports their Feedback (**FB23642313**, quoted in-thread — not ours, not verified by us) moved to **"Potential fix identified — For a future OS update."**

This changes what filing is for. It is no longer about establishing that the bug exists — Apple has it. DTS explicitly noted that multiple reports help drive priority, and the evidence assembled here is stronger on one specific axis than anything in that thread: **four unrelated apps across four different UI toolkits, byte-identical throw site at the same `+216`, 32 occurrences, one of them in an app whose source we control.** That is the cross-app argument, and it is worth filing on top of the existing reports rather than instead of them.

据该帖:**Apple DTS 工程师**已确认并转交对应团队;有参与者称其 Feedback(**FB23642313**,帖内引用,非我方、未经我方核实)状态已变为 **"Potential fix identified — For a future OS update"**。这改变了提交 Feedback 的意义:不再是证明 bug 存在(Apple 已掌握),而是加权重。DTS 明确表示报告数量影响优先级,而本文在一个维度上强于该帖任何单条:**四个互不相关的 app、四种 UI 技术栈、逐字相同且偏移同为 `+216` 的抛点、32 次记录,其中一次发生在我们掌握源码的 app 上**。

### Workaround posted in the thread — read the trade-offs before adopting / 帖中给出的规避手段 —— 采用前请权衡

@JyHu posted a guard that **swizzles `-[NSRemoteView containingWindowWillOrderOnScreen:]`** and wraps the original IMP in `@try/@catch`, suppressing **only** an `NSInternalInconsistencyException` whose reason contains `NSRemoteView`, re-`@throw`ing everything else, and installing only when `operatingSystemVersion.majorVersion == 27`. They report 3+ weeks in production. Scoping-wise this is about as disciplined as swizzling gets — narrow exception match, version-gated, non-matching exceptions preserved.

**Trade-offs it does not remove:**

- **It swizzles a private class and a private method.** `NSRemoteView` is not API. `NSClassFromString`/`NSSelectorFromString` avoid a static symbol reference, but this remains private-API use — a real consideration for Mac App Store review, and it can break silently whenever Apple changes that method.
- **Suppressing an assertion is not the same as fixing the state.** The assertion fires because the remote view's expected containing window is `null`. Swallowing it lets the process continue with the view in exactly the state AppKit considered inconsistent; the visible outcome (does the panel draw correctly, does it leak, does it misbehave later) is unverified here.
- **It is a crash guard, not a fix.** The underlying race is untouched.

Reasonable stopgap for a non-MAS app whose alternative is aborting; harder to justify for a sandboxed App Store submission, and it should be removed once Apple ships the fix.

### Two defects in the circulating guard — both verified here / 流传版本的两个缺陷

An improved version is in [`tools/RemoteViewCrashGuard.m`](../tools/RemoteViewCrashGuard.m) (compiled and run on `26A5406e`; log output below is real). It fixes two problems the forum version has:

**1. It installs nothing if called at the recommended time.** `ViewBridge` is loaded **lazily** — the first remote view (open/save panel, QuickLook, share sheet, status item, autofill…) pulls it in. Install at `applicationWillFinishLaunching:` and `NSClassFromString(@"NSRemoteView")` returns `nil`, so the guard hits its `if (!cls) return;` and **silently does nothing** — and the forum version logs nothing on that path, so you would never know. Verified:

```
E  guardtest[2595] [dev.jizhi.remoteviewguard] not installed: NSRemoteView not found
```

Fix: `dlopen("/System/Library/PrivateFrameworks/ViewBridge.framework/ViewBridge", RTLD_LAZY)` first — it works even though the binary exists only in the dyld shared cache.

**2. It guards one of at least three assertion sites.** The Will handler has one; **`-[NSRemoteView containingWindowDidOrderOnScreen:]` has two more** (`handleFailureIn` at +220 and +260), downstream of its own `[self window] != [note object]` compare at +64. If the bad state survives into the Did handler, the forum guard does not stop it. Guard both.

Also verified, and worth knowing before relying on either version: **swallowing the Will assertion does not cascade.** It skips `_expectWindowOrderingState:0 andAdvanceTo:2`, but that method has **zero** assertion sites — on mismatch it only calls `vbLog(kLogDomain_WindowVisibility)`. That is consistent with the forum reports of 3+ weeks without failures. Whether the panel then *draws and behaves* correctly remains unverified.

**The guard doubles as a probe**, which is its main value here: it logs `isValid` / `window` / `note.object` / whether they matched on every invocation, so a quiet period yields a *positive* record ("the bad input never occurred") instead of mere absence of crashes — and a suppressed assertion logs `exception.reason` in full, which names the remote view's **service** and the containing window's class, the one piece our 32 reports structurally could not capture. Verified end-to-end:

```
I  guarded containingWindowWillOrderOnScreen:
I  guarded containingWindowDidOrderOnScreen:
I  installed for macOS 27.x
I  containingWindowWillOrderOnScreen: rv=0x7ceccc2d00 isValid=YES window=0x7ceccc1500 note.object=0x7ceccc1500 match=YES
I  containingWindowDidOrderOnScreen:  rv=0x7ceccc2d00 isValid=YES window=0x7ceccc1500 note.object=0x7ceccc1500 match=YES
```

Read with `log show --info --predicate 'subsystem == "dev.jizhi.remoteviewguard"'`. Note it must be `os_log_info`, not `os_log_debug` — debug-level messages are memory-only and get dropped, which would leave the probe recording nothing.

流传的那版守卫有两个缺陷,均已在本机验证:**(1) 按推荐时机安装会静默失效** —— ViewBridge 是懒加载,进程启动时 `NSRemoteView` 类还不存在,`if (!cls) return;` 直接走掉且不打日志;修法是先 `dlopen`。**(2) 只挡了三处断言中的一处** —— Did 处理器另有两处(`+220`/`+260`),坏状态延续过去照样崩,应当两个方法都包。另已验证:吞掉 Will 的异常**不会级联**,状态机 `_expectWindowOrderingState:andAdvanceTo:` 零断言站点,失配只走 `vbLog`。改进版见 [`tools/RemoteViewCrashGuard.m`](../tools/RemoteViewCrashGuard.m),它同时是**探针**(记录每次调用的 `isValid`/`window`/`note.object`/是否相等),使"安静期"能产出**正面记录**而非仅仅"没崩"。

该规避手段以 swizzle 包裹私有方法并只吞掉特定断言,作者称已在生产环境跑了三周以上,作用域控制得相当克制。但仍有三点无法回避:**(1)** 它 swizzle 的是私有类与私有方法,对 App Store 审核是实打实的风险,且 Apple 一改该方法就可能静默失效;**(2)** 吞掉断言 ≠ 修复状态 —— 断言之所以触发,正是因为该 remote view 期望的容器窗口为 `null`,吞掉之后进程带着 AppKit 认为不一致的状态继续跑,界面是否正常、是否泄漏,本文未做验证;**(3)** 它是崩溃防护,不是修复,底层竞态未动。对于崩溃已成常态的非 MAS 应用是合理的临时手段,对沙盒 App Store 提交则较难论证,且应在 Apple 修复后移除。

## beta4 ↔ beta5 diff: what Apple actually changed / Apple 到底改了什么

Apple changed **one method**, and it is the one that owns the registration this bug leaks.

**How the comparison was obtained.** No APFS local snapshot survived the upgrade, so beta4 came from the official restore image — `UniversalMac_27.0_26A5388g_Restore.ipsw`, sha256 verified against [appledb](https://github.com/littlebyteorg/appledb). Its **Rosetta system cryptex** dmg is unencrypted (the main system dmg is `.aea`-encrypted), and it carries a full `dyld_shared_cache_x86_64`; this machine has the matching beta5 cryptex at `/System/Volumes/Preboot/Cryptexes/Rosetta/`. So the comparison is **x86_64 vs x86_64, same source, different OS build** — the encrypted main image is never needed. Dylibs were extracted with the system's own `/usr/lib/dsc_extractor.bundle` (a ~30-line `dlopen` wrapper; no third-party tooling).

**Control for a stale cryptex.** If the Rosetta cryptex had simply not been rebuilt, "ViewBridge unchanged" would be meaningless. It was rebuilt: AppKit, Foundation, CoreFoundation and libobjc all differ by sha256 between the two builds.

**The change**, in `-[NSRemoteView maintainContainingWindowNotifications:]`:

```objc
// beta4 26A5388g — the whole teardown sits inside the nil-guard
old = objc_loadWeak(&self->_containingWindow);
if (old != nil) {
    objc_storeWeak(&self->_containingWindow, nil);
    [center _removeObserver:self notificationNamesAndSelectors:notifications object:old];
    [old removeObserver:self forKeyPath:@"level"];
    [old removeObserver:self forKeyPath:@"backgroundColor"];
}

// beta5 26A5406e — the notification removal is hoisted OUT of the guard,
// and object: changes from the old window to nil
[center _removeObserver:self notificationNamesAndSelectors:notifications object:nil];
old = objc_loadWeak(&self->_containingWindow);
if (old != nil) {
    objc_storeWeak(&self->_containingWindow, nil);
    [old removeObserver:self forKeyPath:@"level"];
    [old removeObserver:self forKeyPath:@"backgroundColor"];
}
```

It is **not an added call** — the removal exists in both. What changed is that it now runs **unconditionally**, at the convergence point of both paths, and with `object:nil`. `_removeObserver:notificationNamesAndSelectors:object:` is an AppKit category that loops the dictionary calling `-removeObserver:name:object:`, and per Apple's docs a `nil` object means the receiver "does not use a sender as criteria for removal" — so beta5 sweeps **every** stale per-window registration of this view for those six notification names. Corroborating detail: the adjacent `vbLog` format string drops one argument (`"…removed containing %@ observers %@, %@, and %@"` → `"…removed containing %@ KVO observers %@ and %@"`), because notification-observer removal no longer happens inside that block.

**Where the edit landed, pinned independently of the diff.** Extracting every `handleFailureIn` `__LINE__` constant attributed to `NSRemoteView.m` in both builds and plotting the shift against source line: **+0 through beta4 line 3217, then +10 from line 3235** — both inside this method. So ~10 source lines were inserted **inside `maintainContainingWindowNotifications:` and nowhere before it**. (Later steps at 3947/8441/8491 are unrelated edits further down the file.)

**Why it fits this bug.** Under beta4, if the weak `_containingWindow` ivar was already nil at teardown — zeroed, or overwritten without passing through this path — the entire removal block was skipped and the `object:oldWindow` registration leaked. The view keeps receiving `_NSWindowWillBecomeVisible` for a window that is no longer `[self window]`, and `[self window]` is now `nil` → exactly the forum's reason string, `"… notified of <NSWindow: 0x…> but expected (null)"`.

**What this does and does not establish.** It establishes that **Apple hardened precisely the spot our hypothesis blames**. It does **not** establish that the bug is fixed:

- The sweep only helps when `maintainContainingWindowNotifications:` is actually called. Its only caller, `-[NSRemoteView _maintainWindowNotifications:]`, is **byte-identical** between builds; whether a stale registration can arise on a path that never calls it is unverified.
- "Stale per-window registration causes this crash" remains our hypothesis. The diff shows Apple hardened that spot; it does not prove that spot was the cause.
- All assertion sites remain present in beta5.
- beta4 is only available here as the x86_64 Rosetta build. Same source, so the arm64e change is expected to match — *a guess*, though beta5's arm64e and x86_64 builds do agree with each other.

**Everything else in ViewBridge is unrelated.** Of 4,838 functions, 688 differ, but **502 are pure `__LINE__`/immediate shifts** and none of the 186 real code changes touch the order-on-screen path. Notably **byte-identical** — i.e. *not* hardened alongside: `viewWillMoveToWindow:`, `_invalidate`, `invalidate`, `dealloc`, `_maintainWindowNotifications:`, and the sibling registrars `maintainKeyTestWindowNotifications:`, `maintainAppWideNotifications:`, `-[NSViewServiceMarshal maintainNotificationsForWindow:]`. The siblings still carry beta4's conditional-teardown shape, so this was a **targeted one-method fix, not a systematic sweep** — consistent with fixing the reported bug, and it means the same pattern still exists elsewhere.

Apple **只改了一个方法**,正是持有本 bug 所泄漏注册的那个。beta4 把整段拆除放在 `if (old != nil)` 里,弱引用一旦已被清零就整块跳过,`object:oldWindow` 的注册便泄漏;beta5 把通知注销**提到判断之外无条件执行,且 `object:` 改为 `nil`**(按 Apple 文档即"不以发送者为移除条件"),从而清扫全部残留注册。行号偏移分析独立佐证:**beta4 第 3217 行前偏移为 0、第 3235 行起为 +10**,两处均在该方法内 —— 即约 10 行源码恰好插在此方法内部,之前一行未动。对比方式为 **x86_64 ↔ x86_64**(beta4 取自官方 IPSW 内未加密的 Rosetta cryptex,beta5 取自本机同名 cryptex),并以 AppKit/Foundation/CoreFoundation/libobjc 四者哈希均不同**排除了"cryptex 根本没更新"**这一伪阴性。**但这只证明代码改了,不证明 bug 修好了**:该清扫仅在此方法被调用时生效,其唯一调用者 `_maintainWindowNotifications:` 两版逐字节相同;且"注册泄漏导致此崩溃"仍是我们的假设。兄弟方法(`maintainKeyTestWindowNotifications:` 等)**未同步修改**,说明这是**针对性单点修复**,同样的形态在别处依然存在。

## Corrections (2026-08-11) / 更正

Four claims in earlier revisions of this file were wrong. All four were found by disassembling ViewBridge on this machine (macOS 27.0 beta5 `26A5406e`); the method lives only in the dyld shared cache, so it has to be `dlopen`ed first:

```bash
# holder.c: a 3-line program that dlopens ViewBridge, so lldb has something attachable
# (/usr/bin/true is SIP-protected and cannot be attached to)
lldb -b -o "b main" -o run \
  -o 'expr (void*)dlopen("/System/Library/PrivateFrameworks/ViewBridge.framework/ViewBridge", 2)' \
  -o 'disassemble -n "-[NSRemoteView containingWindowWillOrderOnScreen:]"' -o quit ./holder
```

**What the method actually does** (69 instructions, one assertion site):

```objc
-[NSRemoteView containingWindowWillOrderOnScreen:](self, _cmd, note) {
    if (![self isValid]) return;                                    // +32
    if ([self window] != [note object]) {                           // +44/+56/+64
        e = handleFailureIn(..., NSRemoteView.m, 4232,
                            @"%@ notified of %@ but expected %@");  // +208
        [e raise];                                                  // +212  → return addr +216
    }
    [self _expectWindowOrderingState:0 andAdvanceTo:2 caller:...];  // +88
}
```

1. **"The window is shown as a SHEET" — wrong.** `_doWindowWillBeVisibleAsSheet:` takes a `BOOL` (`tbnz w20, #0` at +48) saying *whether* it is a sheet; the method runs on **every** order-on-screen because it is simply where AppKit posts `_NSWindowWillBecomeVisible`. Its presence in 100% of our reports proves nothing about sheets. Two of our own WeChat reports reach it from `-[NSWindow makeKeyAndOrderFront:]`, which is not a sheet path. **Sheets remain one real trigger** — `NSAlert.beginSheetModalForWindow:` is reported on the forum — just not a necessary one.
2. **"The observer reads a bundle Info-plist key (`_CFBundleGetValueForInfoKey`) and throws" — wrong.** There is no Info.plist read. That frame is **mis-symbolication** of an address inside a neighbouring CoreFoundation function on the `[NSException raise]` path. The real predicate is `[self window] != [note object]`.
3. **`+216` is the return address of `[e raise]` at +212**, not of the `handleFailureIn` call at +208.
4. **Same bug as the forum thread — now proven, not assumed.** The method contains exactly **one** assertion call site, and the format string loaded at +200 is verbatim the forum's `@"%@ notified of %@ but expected %@"`. Since backtraces record return addresses, our invariant `+216` frame *is* that one assertion. This matters: the claim "Apple has acknowledged it" rests entirely on the two being the same bug, and until now that was an untested assumption. (Our binary reports line **4232**; the forum quotes 4221, from an earlier build — consistent source drift.)

**Registration side**, from `-[NSRemoteView maintainContainingWindowNotifications:]` — six notification→selector pairs, registered **per containing window**, not `object:nil`:

```
_NSWindowWillBecomeVisible                  → containingWindowWillOrderOnScreen:   ← ours
_NSWindowDidBecomeVisible                   → containingWindowDidOrderOnScreen:
NSWindowWillOrderOffScreenNotification      → containingWindowWillOrderOffScreen:
NSWindowDidOrderOffScreenNotification       → containingWindowDidOrderOffScreen:
NSWindowDidMoveNotification                 → containingWindowDidMove:
NSWindowDidChangeOcclusionStateNotification → containingWindowDidChangeOcclusionState:
```

**WeChat's presenting frame is one presenter, not "the image viewer".** Both surviving WeChat reports carry the identical frame 15 — `WeChatAppEx Framework +11729020` — under `-[NSWindow makeKeyAndOrderFront:] + 40`. The reporter confirms **clicking an avatar crashes as well as clicking an image**, and that it happens **on opening, not on dismissal, and not necessarily the first time**. Both UI actions funnel through that one presenter, so the trigger is "WeChat orders its AppEx-hosted window on screen". DingTalk's is different again: its frames sit under `_dispatch_main_queue_drain` — timer-driven, no user action.

以上四条是本机反汇编得出的更正:**(1)** "以 sheet 呈现"是**误读方法名** —— `_doWindowWillBeVisibleAsSheet:` 带 BOOL 参数,任何一次上屏都会走它,它就是 AppKit 发 `_NSWindowWillBecomeVisible` 的地方(但 sheet 确实是触发路径**之一**,只是非必要条件);**(2)** 根本没有读 Info.plist,那一帧是**符号化错误**,真实判据是 `[self window] != [note object]`;**(3)** `+216` 是 `[e raise]` 的返回地址;**(4)** 与论坛同一 bug **已被证明**(方法内仅一处断言,格式字符串逐字一致)—— 这条关系到"Apple 已受理"能否成立,此前只是未经检验的假设。另:微信点**图片**与点**头像**经由同一个呈现器(`WeChatAppEx +11729020` → `makeKeyAndOrderFront:`),**崩在打开时、且不一定是第一次**。

## Workaround / 临时规避

None confirmed. It crashes while *presenting* the viewer (an out-of-process sheet), so **retrying — click the image again — usually reopens it**; a fresh order-on-screen doesn't reliably re-hit the throw. To view a stubborn image, drag it out / save then open in Preview to avoid the WeChatAppEx sheet.

暂无确认规避。崩在**呈现**看图器(跨进程 sheet)时,**再点一次通常就能打开**;实在打不开就把图拖出/另存后用「预览」看,绕开 WeChatAppEx sheet。

## Notes / 备注

- Every crash report has `share_with_app_devs = 0` — none auto-sent to any vendor. (Re-verified on the 11 reports still on disk 2026-08-04, i.e. entries 21–31; the older ones have since rotated out of `DiagnosticReports`, but were 0 when logged. Entry 32 checked the same way on 2026-08-10: `share_with_app_devs = 0`.)
- Distinct from **[#10](wechat-mas-crash-fixed.md)** (a 4.1.9 MAS *launch* crash, fixed in 4.1.10). This is a *4.1.11* image-viewer crash — a different bug.
- **Cross-app across four UI toolkits** (Chromium `flue` engine, Apple's own QuickLook, Qt, plain Swift/AppKit), byte-identical throw at the same `+216` → strengthens the Apple Feedback: the exception fires in ViewBridge's own order-on-screen observer regardless of who presents the remote view. Worth a Feedback (ViewBridge exception on window order-on-screen as sheet) + a minimal repro (any remote/XPC-hosted view presented as a sheet) — **and duo-pasted gives us a repro we fully own**, so the Feedback can ship with source, not just other vendors' stack traces.
- **We never filed our Feedback, and the bug got fixed anyway.** The case had become strong — 32 verified crashes across **four** unrelated apps, persisting across the `…j` → `…n` beta3 revision *and* the **beta4 `26A5388g`** bump, with 13 crashes on beta4 alone — but the fix landed in **beta5 `26A5406e`** without us. Apple had it from the [forum thread](https://developer.apple.com/forums/thread/837342) (FB23642313 / FB23794308, DTS-routed) — third-party reports were enough. Worth recording as a lesson about the cost of leaving `FB____` unfiled: **we contributed nothing to the fix we spent a month documenting.**
- A vendor-facing note to **DingTalk** has *not* been drafted; given the root cause is Apple's, the Feedback comes first.
- A vendor-facing email to **CleanShot X** (MakeTheWeb) is drafted — reports the Apple root cause and suggests they present the QuickLook preview off the sheet path / guard the `showWindow:` call so an AppKit exception during order-on-screen doesn't abort the whole app.
- 现已**跨 app**(微信 `flue` 引擎 + 苹果自家 QuickLook),抛点逐字一致 → 加强 Apple Feedback:无论谁来呈现 remote view,异常都在 ViewBridge 自己的上屏 observer 里触发。值得提 Feedback + 做最小复现(任意 XPC 托管视图作为 sheet 呈现)。
- 已为 **CleanShot X**(MakeTheWeb)起草一封厂商邮件:说明 Apple 根因,并建议把 QuickLook 预览挪出 sheet 路径 / 给 `showWindow:` 加保护,避免上屏时的 AppKit 异常把整个 app 拖崩。
