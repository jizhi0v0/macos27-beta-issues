# macOS 27 (Golden Gate) beta — app & system bug log

> A crowd-searchable log of third-party-app and system-process bugs seen on **macOS 27 "Golden Gate"** developer betas, with verified versions, log signatures, workarounds, and upstream / Apple Feedback links.
>
> macOS 27「Golden Gate」开发者 beta 上撞到的第三方 app / 系统进程问题台账：含实测版本号、日志签名、临时规避、上游 / Apple Feedback 链接。方便后来撞坑的人直接搜到。

If a Google/GitHub search for a crash signature or a process eating CPU on macOS 27 beta brought you here — check the table below, open the matching file in [`issues/`](issues/), and add your own data point via PR or issue.

## Test environment / 测试环境

| | |
|---|---|
| Machine | MacBook Pro `Mac15,11` — Apple M3 Max, 36 GB |
| OS | macOS **27.0** beta — builds seen: `26A5353q` (beta1), `26A5368g` (beta2), `26A5378j` (beta3) |
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
| [11](https://github.com/jizhi0v0/macos27-beta-issues/issues/11) | [Swift Charts `if/else` fails to build under macOS 27 SDK](issues/swift-charts-conditionalcontent-macos27-sdk.md) | Apple Swift Charts (SDK/build) | 🟡 still on beta3 SDK (Xcode 27.0 `27A5194q`) | use bare `if` / ternary, avoid `if/else` in chart builders | SDK behavior |
| [12](https://github.com/jizhi0v0/macos27-beta-issues/issues/12) | [MenuBarAgent ~10–14% CPU at idle (static menu bar)](issues/apple-menubaragent-idle-cpu.md) | Apple MenuBarAgent | 🟢 fixed on beta3 (`26A5378j`) | (was) none | **[FB23411741](https://feedbackassistant.apple.com/feedback/23411741)** |
| [13](https://github.com/jizhi0v0/macos27-beta-issues/issues/13) | [Spotlight typing lag / ghosting (`insert ranking attr at NSNotFound`)](issues/apple-spotlight-ranking-attr-loop.md) | Apple Spotlight (UI app `Campo`→`Siri AI` on beta3) | 🟢 lag/ghosting fixed on beta3 (log line persists, now benign) | (was) use Raycast/Alfred | **[FB23412497](https://feedbackassistant.apple.com/feedback/23412497)** |
| [14](https://github.com/jizhi0v0/macos27-beta-issues/issues/14) | [Click/input latency — WindowServer `ws_main_thread` serializes events (persists at 80% idle)](issues/apple-click-input-latency-beta.md) | macOS 27 WindowServer / event delivery | 🟢 fixed on beta3 (Telegram panel-dismiss stutter gone; user-confirmed, settings-independent) | (was) Reduce transparency/motion | Feedback candidate `FB____` |
| [15](https://github.com/jizhi0v0/macos27-beta-issues/issues/15) | [appstoreagent + dasd retry-loop (Arcade BG task rejected `Code=8`, no backoff) floods log/CPU](issues/apple-appstoreagent-bgtask-retry-loop.md) | Apple appstoreagent / dasd / BGTaskScheduler | ⚪ not reproduced in beta3 window (conditional) | `killall` = temporary; internal bug | **[FB23413997](https://feedbackassistant.apple.com/feedback/23413997)** |
| [16](https://github.com/jizhi0v0/macos27-beta-issues/issues/16) | [`modelmanagerd` crash-loop (`EXC_BREAKPOINT`) on AI-ineligible device](issues/apple-modelmanagerd-crash-loop.md) | Apple modelmanagerd / ModelManagerServices | 🟢 fixed on beta3 (0 crashes ≥11h, trigger unchanged) | (was) none (SIP daemon) | **[FB23430737](https://feedbackassistant.apple.com/feedback/23430737)** |

## Filing readiness / 提交就绪度 (re-verified 2026-06-26, beta2 `26A5368g`)

Each Apple bug was re-tested live on the machine before drafting Feedback, so we don't file stale/wrong reports. Ready drafts live in [`feedback/`](feedback/).

### Beta3 retest / beta3 复验 (2026-07-07, `26A5378j`, ~2.5 h uptime)

Re-ran the still-open Apple bugs on beta3 (installed 07:54, booted 07:53). Verdicts by live measurement, not changelog:

- 🟢 **#12 MenuBarAgent idle CPU — fixed.** 0.0% now, **43 s cumulative CPU TIME over 2h35m** (≈0.28% avg); beta2 held 10–14% sustained. Cumulative-TIME can't be faked → confirmed fix.
- 🟢 **#16 `modelmanagerd` crash-loop — fixed.** Daemon PID 830 alive **≥11 h with 0 crashes** (many multiples of beta2's 2.5 h max interval); beta2 crashed ≤2.5 min after a clean reboot and every 20 min–2.5 h. **Trigger condition unchanged** — still `deviceNotEligible`, `/var/db/com.apple.modelcatalog/` still only empty `sideload`/`tokenStore` — so the daemon hits the same reconcile path without trapping = a real fix, not changed inputs. Passive durable watch continues (OS `.ips` + launchd `com.jizhi.crash-notify` log every crash); flips back to 🔴 if a late-tail crash appears.
- 🟢 **#13 Spotlight typing lag / ghosting — fixed** (log line persists, now benign). The user-facing bug was **typing lag + a result "ghost" that lingered several seconds**, not the log volume. Beta3: user reports smooth typing, no ghosting, and — objectively — **0 Spotlight-UI spin reports** since boot vs **3× `Campo_*.spin` (`Slow response to HID event`) on beta2 (2026-07-06)**. The `insert ranking attr at NSNotFound` line still logs (peak 1569/sec) but is now **decoupled from UX / benign spam**. UI app renamed **`Campo` → `Siri AI`**.
- 🟢 **#14 Telegram panel-dismiss compositing stutter — fixed** (user-confirmed 2026-07-08). The narrowed beta2 repro (group title → group-details → **Back**, dismissing the heavy blurred panel — a WindowServer/CoreAnimation frame-drop, fine on macOS 26) no longer stutters on beta3. User confirms it's the *specific* transition that's smooth now, and that **toggling Telegram's animation/auto-play settings makes no difference** — so it's the system compositor path that changed, not a content/settings workaround. Fits the beta3 compositor-fix cluster with #12/#13. (Objective note: this ~300 ms one-shot burst leaves no `.spin`/`.hang` report and WindowServer CPU is polluted by the agent's own rendering, so user perception of the exact narrowed repro is the evidence — same evidence class the #14 narrowing was built on.)
- ⚪ **#15 appstoreagent / #1 CoreMedia / #2 Shortcuts — not reproduced in this window (conditional triggers).** Since boot: **0** appstoreagent lines / **0** `Code=8`; **0** CoreMedia `fpSupport` spam; **0** Shortcuts-storm lines. These fire only under specific conditions (Arcade BG task rejection / WebKit DRM video / early post-boot), which didn't occur in the window — "not reproduced," not "confirmed fixed."

- ✅ **Filed to Apple** (confirmed beta2 bugs): **CoreMedia loop** → [FB23411581](https://feedbackassistant.apple.com/feedback/23411581) · **MenuBarAgent idle ~10–14% CPU** → [FB23411741](https://feedbackassistant.apple.com/feedback/23411741)
- ✅ **Filed:** **Spotlight `insert ranking attr at NSNotFound` ~60–160×/sec while typing** (idle=0; intrinsic to ranking code, no Settings fix) → [FB23412497](https://feedbackassistant.apple.com/feedback/23412497)
- ⏸ **Intermittent** — fires post-boot then self-settles; file with the captured boot-time evidence: **Shortcuts/Siri storm** ([draft](feedback/shortcuts.md))
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
