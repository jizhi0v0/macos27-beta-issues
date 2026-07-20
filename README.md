# macOS 27 (Golden Gate) beta — app & system bug log

> A crowd-searchable log of third-party-app and system-process bugs seen on **macOS 27 "Golden Gate"** developer betas, with verified versions, log signatures, workarounds, and upstream / Apple Feedback links.
>
> macOS 27「Golden Gate」开发者 beta 上撞到的第三方 app / 系统进程问题台账：含实测版本号、日志签名、临时规避、上游 / Apple Feedback 链接。方便后来撞坑的人直接搜到。

If a Google/GitHub search for a crash signature or a process eating CPU on macOS 27 beta brought you here — check the table below, open the matching file in [`issues/`](issues/), and add your own data point via PR or issue.

## Test environment / 测试环境

| | |
|---|---|
| Machine | MacBook Pro `Mac15,11` — Apple M3 Max, 36 GB |
| OS | macOS **27.0** beta — builds seen: `26A5353q` (beta1), `26A5368g` (beta2), `26A5378j` (beta3), **`26A5378n`** (beta3 revision, installed 2026-07-14, live from that day's 10:58 reboot — **current**) |
| Reporter | [@jizhi0v0](https://github.com/jizhi0v0) |

## Status legend / 状态

🔴 Open · confirmed, no fix &nbsp;|&nbsp; 🟡 Mitigated · workaround exists &nbsp;|&nbsp; 🟢 Fixed &nbsp;|&nbsp; ⚪ Needs retest

## Index / 索引

> The **`#`** in each row links to a matching **GitHub Issue** — **Watch / 👍 / comment** there to follow that specific problem. The **Issue title** links to the canonical, continuously-updated write-up in [`issues/`](issues/). (Resolved/not-a-bug entries are tracked as *closed* issues.)
>
> 每行的 **`#`** 链到对应的 **GitHub Issue**(想跟进某个问题就在那 Watch / 👍 / 评论);**问题标题**链到 [`issues/`](issues/) 里持续更新的权威正文。已解决/非 bug 的条目对应 *已关闭* 的 Issue。

| # | Issue | Component / 影响 | Status | Workaround (short) | Report |
|---|---|---|---|---|---|
| [1](https://github.com/jizhi0v0/macos27-beta-issues/issues/1) | [CoreMedia `fpSupport_GetVideoRange…` loop floods logd](issues/apple-coremedia-fpsupport-logd-spam.md) | Apple MediaToolbox / CoreMedia | 🟡 · ⚪ not repro in beta3 window (conditional) | quit the WebKit apps / silence subsystem log | **[FB23411581](https://feedbackassistant.apple.com/feedback/23411581)** |
| [2](https://github.com/jizhi0v0/macos27-beta-issues/issues/2) | [Shortcuts/Siri ToolKit action-registration storm](issues/apple-shortcuts-siri-toolkit-storm.md) | Apple Shortcuts / siriactionsd | 🟡 · ⚪ not repro in beta3 window (post-boot) | self-settles post-boot; silence subsystem log | Feedback: `FB________` |
| [3](https://github.com/jizhi0v0/macos27-beta-issues/issues/3) | [WindowServer high CPU + `Invalid window` SkyLight loop](issues/apple-windowserver-invalid-window.md) | Apple WindowServer / SkyLight | 🟢 was load (Telegram redraw); not a bug | quit/limit animated-content apps | resolved as load |
| [4](https://github.com/jizhi0v0/macos27-beta-issues/issues/4) | [Weather.app VFX thread spins ~36% CPU in background](issues/apple-weather-vfx-cpu-spin.md) | Apple Weather.app 6.0 | 🟢 fixed (build 1435, incl. rain) | (was) `killall Weather` | resolved on 26A5368g |
| [5](https://github.com/jizhi0v0/macos27-beta-issues/issues/5) | [OrbStack SwiftUI Charts → AttributeGraph abort](issues/orbstack-charts-attributegraph-crash.md) | Apple SwiftUI ↔ OrbStack 2.2.1 | 🟢 not repro on beta2 (3h21m) | — | [orbstack#2526](https://github.com/orbstack/orbstack/issues/2526) |
| [6](https://github.com/jizhi0v0/macos27-beta-issues/issues/6) | [Chrome crash via MediaRemote Now-Playing nil](issues/chrome-mediaremote-nowplaying-crash.md) | Apple MediaRemote ↔ Chrome | 🟢 not repro on .201 (2h churn) | — | resolved on .201 |
| [7](https://github.com/jizhi0v0/macos27-beta-issues/issues/7) | [ToDesk 10s crash-loop → "repeated logout"](issues/todesk-session-proxy-crash-loop.md) | ToDesk 4.9.7.1 (app bug) | 🟢 fixed in 4.9.7.2 | update to 4.9.7.2 (build 2064) | resolved |
| [8](https://github.com/jizhi0v0/macos27-beta-issues/issues/8) | [Codex Dock-tile plugin infinite recursion crash](issues/codex-docktile-recursion-crash.md) | Codex.app (app bug) | 🟢 likely fixed in 26.623.31443 | update Codex (0 crashes in 7 days) | [openai/codex#27694](https://github.com/openai/codex/issues/27694) |
| [9](https://github.com/jizhi0v0/macos27-beta-issues/issues/9) | [Telegram lag = animated-content redraw (not MAS-specific)](issues/telegram-mas-lag.md) | Telegram-macOS 12.8 (native) | 🟢 explained | disable auto-play/animated stickers (any build) | not a build/Apple bug |
| [10](https://github.com/jizhi0v0/macos27-beta-issues/issues/10) | [WeChat (MAS) crash on launch — FIXED in 4.1.10](issues/wechat-mas-crash-fixed.md) | WeChat 4.1.9 MAS | 🟢 | update to 4.1.10 (or use official build) | resolved |
| [11](https://github.com/jizhi0v0/macos27-beta-issues/issues/11) | [Swift Charts `if/else` fails to build under macOS 27 SDK](issues/swift-charts-conditionalcontent-macos27-sdk.md) | Apple Swift Charts (SDK/build) | 🟢 by-design SDK behavior (Apple Known Issue + official workaround); verified still on beta3 SDK | use bare `if` / ternary, avoid `if/else` in chart builders | SDK behavior |
| [12](https://github.com/jizhi0v0/macos27-beta-issues/issues/12) | [MenuBarAgent ~10–14% CPU at idle (static menu bar)](issues/apple-menubaragent-idle-cpu.md) | Apple MenuBarAgent | 🟢 fixed on beta3 (`26A5378j`) | (was) none | **[FB23411741](https://feedbackassistant.apple.com/feedback/23411741)** |
| [13](https://github.com/jizhi0v0/macos27-beta-issues/issues/13) | [Spotlight typing lag / ghosting (`insert ranking attr at NSNotFound`)](issues/apple-spotlight-ranking-attr-loop.md) | Apple Spotlight (UI app `Campo`→`Siri AI` on beta3) | 🟢 lag/ghosting fixed on beta3 (log line persists, now benign) | (was) use Raycast/Alfred | **[FB23412497](https://feedbackassistant.apple.com/feedback/23412497)** |
| [14](https://github.com/jizhi0v0/macos27-beta-issues/issues/14) | [Click/input latency — WindowServer `ws_main_thread` serializes events (persists at 80% idle)](issues/apple-click-input-latency-beta.md) | macOS 27 WindowServer / event delivery | 🟢 fixed on beta3 (Telegram panel-dismiss stutter gone; user-confirmed, settings-independent) | (was) Reduce transparency/motion | Feedback candidate `FB____` |
| [15](https://github.com/jizhi0v0/macos27-beta-issues/issues/15) | [appstoreagent + dasd retry-loop (Arcade BG task rejected `Code=8`, no backoff) floods log/CPU](issues/apple-appstoreagent-bgtask-retry-loop.md) | Apple appstoreagent / dasd / BGTaskScheduler | ⚪ not reproduced in beta3 window (conditional) | `killall` = temporary; internal bug | **[FB23413997](https://feedbackassistant.apple.com/feedback/23413997)** |
| [16](https://github.com/jizhi0v0/macos27-beta-issues/issues/16) | [`modelmanagerd` crash-loop (`EXC_BREAKPOINT`) on AI-ineligible device](issues/apple-modelmanagerd-crash-loop.md) | Apple modelmanagerd / ModelManagerServices | 🟢 fixed on beta3 (0 crashes ≥11h, trigger unchanged) | (was) none (SIP daemon) | **[FB23430737](https://feedbackassistant.apple.com/feedback/23430737)** |
| [17](https://github.com/jizhi0v0/macos27-beta-issues/issues/17) | [ViewBridge `NSRemoteView` uncaught ObjC exception on sheet order-on-screen (WeChat image viewer + CleanShot X QuickLook)](issues/wechat-imageviewer-viewbridge-crash.md) | Apple ViewBridge / AppKit (`NSRemoteView`) — hits WeChat 4.1.11 (WeChatAppEx) **&** CleanShot X 4.8.9 (QuickLook) | 🔴 confirmed **cross-app**, **13 crashes** (WeChat ×12 + CleanShot X ×1, byte-identical signature) — **still crashing on `26A5378n`** | none confirmed (retry recovers; ~12×/week in practice) | Feedback candidate `FB____` |
| [18](https://github.com/jizhi0v0/macos27-beta-issues/issues/18) | [contactsd self-sustaining change-history loop on CardDAV collection-groups](issues/apple-contactsd-carddav-group-changehistory-loop.md) | Apple contactsd `3837.100.1` / AddressBookManager / Contacts change-history | 🔴 confirmed on `26A5378n` — **~143% CPU bursts, 13% avg over 4 h**, 840k log lines; 7 CardDAV accounts affected, Exchange clean | **none** (loop is entirely Apple-internal — no app to quit) | Feedback candidate `FB____` |
| [19](https://github.com/jizhi0v0/macos27-beta-issues/issues/19) | [imagent entitled to `ContactsAccountsService` but sandbox blocks the lookup → 1–2 ms no-backoff retry loop](issues/apple-imagent-contactsaccounts-sandbox-retry-loop.md) | Apple imagent `10.0` (IMCore) ↔ ContactsAccountsService | 🔴 confirmed on `26A5378n` — **66,626 errors / 7 h**, but only **19 s CPU** (log-volume bug, *not* CPU); shares #18's trigger | none (SIP daemon; respawns on kill) | Feedback candidate `FB____` |
| [21](https://github.com/jizhi0v0/macos27-beta-issues/issues/21) | [ControlCenter volume runaway — concurrent RMW ratchets volume to 0 or 100%](issues/apple-controlcenter-volume-rmw-race.md) | Apple ControlCenter (`SoundSettings`) ↔ CoreAudio HAL — trigger requires **Alcove 1.7.9** | 🟡 · **not 27-specific** (same symptom on 26.3.1 via [Alcove #675](https://github.com/henrikruscon/alcove-releases/issues/675)) — caught live ×2, **both directions**, 30 Hz, ratchet step 1/16 | `killall ControlCenter`; prevent by quitting Alcove | **[FB23868196](https://feedbackassistant.apple.com/feedback/23868196)** |

## Filing readiness / 提交就绪度 (re-verified 2026-06-26, beta2 `26A5368g`)

Each Apple bug was re-tested live on the machine before drafting Feedback, so we don't file stale/wrong reports. Ready drafts live in [`feedback/`](feedback/).

### Beta3 retest / beta3 复验 (2026-07-07, `26A5378j`, ~2.5 h uptime)

Re-ran the still-open Apple bugs on beta3 (installed 07:54, booted 07:53). Verdicts by live measurement, not changelog:

- 🟢 **#12 MenuBarAgent idle CPU — fixed.** 0.0% now, **43 s cumulative CPU TIME over 2h35m** (≈0.28% avg); beta2 held 10–14% sustained. Cumulative-TIME can't be faked → confirmed fix.
- 🟢 **#16 `modelmanagerd` crash-loop — fixed.** Daemon PID 830 alive **≥11 h with 0 crashes** (many multiples of beta2's 2.5 h max interval); beta2 crashed ≤2.5 min after a clean reboot and every 20 min–2.5 h. **Trigger condition unchanged** — still `deviceNotEligible`, `/var/db/com.apple.modelcatalog/` still only empty `sideload`/`tokenStore` — so the daemon hits the same reconcile path without trapping = a real fix, not changed inputs. Passive durable watch continues (OS `.ips` + launchd `com.jizhi.crash-notify` log every crash); flips back to 🔴 if a late-tail crash appears.
- 🟢 **#13 Spotlight typing lag / ghosting — fixed** (log line persists, now benign). The user-facing bug was **typing lag + a result "ghost" that lingered several seconds**, not the log volume. Beta3: user reports smooth typing, no ghosting, and — objectively — **0 Spotlight-UI spin reports** since boot vs **3× `Campo_*.spin` (`Slow response to HID event`) on beta2 (2026-07-06)**. The `insert ranking attr at NSNotFound` line still logs (peak 1569/sec) but is now **decoupled from UX / benign spam**. UI app renamed **`Campo` → `Siri AI`**.
- 🟢 **#14 Telegram panel-dismiss compositing stutter — fixed** (user-confirmed 2026-07-08). The narrowed beta2 repro (group title → group-details → **Back**, dismissing the heavy blurred panel — a WindowServer/CoreAnimation frame-drop, fine on macOS 26) no longer stutters on beta3. User confirms it's the *specific* transition that's smooth now, and that **toggling Telegram's animation/auto-play settings makes no difference** — so it's the system compositor path that changed, not a content/settings workaround. Fits the beta3 compositor-fix cluster with #12/#13. (Objective note: this ~300 ms one-shot burst leaves no `.spin`/`.hang` report and WindowServer CPU is polluted by the agent's own rendering, so user perception of the exact narrowed repro is the evidence — same evidence class the #14 narrowing was built on.)
- ⚪ **#15 appstoreagent / #1 CoreMedia / #2 Shortcuts — not reproduced in this window (conditional triggers).** Since boot: **0** appstoreagent lines / **0** `Code=8`; **0** CoreMedia `fpSupport` spam; **0** Shortcuts-storm lines. These fire only under specific conditions (Arcade BG task rejection / WebKit DRM video / early post-boot), which didn't occur in the window — "not reproduced," not "confirmed fixed."

### New build `26A5378n` / 新 build(2026-07-14 装,10:58 重启生效)

A beta3 revision **`26A5378n`** replaced `26A5378j` on 2026-07-14. **Every verdict in the retest above was measured on `…j` and has *not* been re-measured on `…n`** — treat them as carrying over unverified. The only entry re-checked on `…n` so far is **#17**, which **is still crashing** (5 crashes on `…n`, latest 07-15).

`26A5378n` 于 2026-07-14 替换 `26A5378j`。**上面的复验结论全部测于 `…j`,尚未在 `…n` 上重测**,请视为"沿用但未验证"。目前唯一在 `…n` 上复验过的是 **#17 —— 仍在崩**(`…n` 上 5 次,最新 07-15)。

- ✅ **Filed to Apple** (confirmed beta2 bugs): **CoreMedia loop** → [FB23411581](https://feedbackassistant.apple.com/feedback/23411581) · **MenuBarAgent idle ~10–14% CPU** → [FB23411741](https://feedbackassistant.apple.com/feedback/23411741)
- ✅ **Filed:** **Spotlight `insert ranking attr at NSNotFound` ~60–160×/sec while typing** (idle=0; intrinsic to ranking code, no Settings fix) → [FB23412497](https://feedbackassistant.apple.com/feedback/23412497)
- ⏸ **Intermittent** — fires post-boot then self-settles; file with the captured boot-time evidence: **Shortcuts/Siri storm** ([draft](feedback/shortcuts.md))
- 🔴 **Ready to file** — **#19 imagent entitled to `ContactsAccountsService` but sandbox omits the lookup** ([draft](feedback/imagent.md)): the contradiction is **provable statically in two greps** — the binary holds `ContactsAccountsService = true`, while `com.apple.imagent.sb`'s `(allow mach-lookup)` block lists the *legacy* `AddressBook.abd` (line 177) and no `ContactsAccountsService` at all. Failure path then retries every **1–2 ms, no backoff** → 66,626 `E`-level lines / 7 h, but only **19 s CPU** (log volume, not performance). No redaction needed.
- ✅ **Filed** — **#21 ControlCenter volume runaway (concurrent RMW race)** (Control Center → *Incorrect/Unexpected Behavior*): caught live ×2 on one boot, ratcheting **up to 100% *and* down to 0%+mute**, on **different devices** (built-in speakers / Bluetooth) — direction and device both arbitrary, which is what rules out a stuck key and points at a lost-update race across **≥7 ControlCenter threads**. Ratchet step is exactly 1/16, ~33 ms apart → full scale in **~0.5 s, no ramp** (hearing-exposure hazard; led with this). Every write during the runaway is ControlCenter's own — the third-party precondition (**Alcove 1.7.9**) issues **0** writes in incident 2. **Not a 27 regression**: same up-direction symptom on **26.3.1** via [Alcove #675](https://github.com/henrikruscon/alcove-releases/issues/675), closed stale, repo archived read-only — no upstream channel left. Report states its own two limits (the "quit Alcove" result is uncounted; no first-discovery claim) → [FB23868196](https://feedbackassistant.apple.com/feedback/23868196) ([draft](feedback/controlcenter-volume.md) · [plain-text submitted body](feedback/controlcenter-volume-paste.txt) · [details](issues/apple-controlcenter-volume-rmw-race.md))
- 🔴 **Ready to file** — **#18 contactsd CardDAV collection-group change-history loop** ([draft](feedback/contactsd.md)): ~143% CPU bursts / 13% avg over 4 h, 840k log lines, 53,686 unconsumed change rows; loop is entirely Apple-internal (TCC AttributionChain proves contactsd is its own requestor), CardDAV-only, Exchange clean. Draft documents the *unanswered* part too — all 5 known failure paths log 0 occurrences, so the fetch failure is none of them; trivial for an engineer with symbols. **Restore the redacted `<DSID>`/`<user>` before submitting.**
- ✅ **Filed** — **`modelmanagerd` crash-loop** (`EXC_BREAKPOINT` on `background-qos.cooperative`, 138× in 4 days, reproduces ≤2.5 min after a clean reboot; `deviceNotEligible` region/account, HW-eligible M3 Max; trap is silent / binaries stripped, so no symbol or message to attach beyond the `.ips` + queue + asset-set context) → [FB23430737](https://feedbackassistant.apple.com/feedback/23430737) ([details](issues/apple-modelmanagerd-crash-loop.md))
- 🟢 **Not reproducing on beta2 — likely fixed** (verified by live repro attempts, no Feedback needed):
  - **Weather VFX** — backgrounded (incl. rain) at ~1% CPU, VFX threads parked; resolved in Weather build 1435.
  - **OrbStack Charts** — kept on the Activity Monitor view **3h21m**, RSS plateaued ~150–185 MB (no runaway), no crash.
  - **Chrome MediaRemote** — **1h45m** of heavy Now-Playing churn on .201 (up to 640 events/min), no crash.
  - **WindowServer high CPU** — RESOLVED as load: quitting Telegram (continuous animated-content redraw) dropped it to single digits. Not a regression — was the sum of continuously-redrawing apps. Only the `Invalid window` log spam is a minor leftover. ([details](issues/apple-windowserver-invalid-window.md))

## How to contribute / 如何补充

Open an issue or PR with: macOS build (`sw_vers`), app version + whether it's a Mac App Store build, the exact crash/log signature, and any workaround you found. One file per problem under [`issues/`](issues/).

## Notes / 说明

- Most Apple-framework regressions can't be fixed app-side — the realistic action is **Apple Feedback Assistant**. Each Apple entry has an `FB________` slot; once filed, the Feedback ID gets pasted in so progress is traceable across betas.
- "Verified versions" were read from the app bundles on the test machine, not copied from changelogs.

*Not affiliated with Apple. Codename "Golden Gate" per public beta reporting.*
