# macOS 27 (Golden Gate) beta — app & system bug log

> A crowd-searchable log of third-party-app and system-process bugs seen on **macOS 27 "Golden Gate"** developer betas, with verified versions, log signatures, workarounds, and upstream / Apple Feedback links.
>
> macOS 27「Golden Gate」开发者 beta 上撞到的第三方 app / 系统进程问题台账：含实测版本号、日志签名、临时规避、上游 / Apple Feedback 链接。方便后来撞坑的人直接搜到。

If a Google/GitHub search for a crash signature or a process eating CPU on macOS 27 beta brought you here — check the table below, open the matching file in [`issues/`](issues/), and add your own data point via PR or issue.

## Test environment / 测试环境

| | |
|---|---|
| Machine | MacBook Pro `Mac15,11` — Apple M3 Max, 36 GB |
| OS | macOS **27.0** beta — builds seen: `26A5353q` (beta1), `26A5368g` (beta2) |
| Reporter | [@jizhi0v0](https://github.com/jizhi0v0) |

## Status legend / 状态

🔴 Open · confirmed, no fix &nbsp;|&nbsp; 🟡 Mitigated · workaround exists &nbsp;|&nbsp; 🟢 Fixed &nbsp;|&nbsp; ⚪ Needs retest

## Index / 索引

| # | Issue | Component / 影响 | Status | Workaround (short) | Report |
|---|---|---|---|---|---|
| 1 | [CoreMedia `fpSupport_GetVideoRange…` loop floods logd](issues/apple-coremedia-fpsupport-logd-spam.md) | Apple MediaToolbox / CoreMedia | 🟡 | quit the WebKit apps / silence subsystem log | Feedback: `FB________` |
| 2 | [Shortcuts/Siri ToolKit action-registration storm](issues/apple-shortcuts-siri-toolkit-storm.md) | Apple Shortcuts / siriactionsd | 🟡 | self-settles post-boot; silence subsystem log | Feedback: `FB________` |
| 3 | [WindowServer high CPU + `Invalid window` SkyLight loop](issues/apple-windowserver-invalid-window.md) | Apple WindowServer / SkyLight | 🟢 was load (Telegram redraw); not a bug | quit/limit animated-content apps | resolved as load |
| 4 | [Weather.app VFX thread spins ~36% CPU in background](issues/apple-weather-vfx-cpu-spin.md) | Apple Weather.app 6.0 | 🟢 fixed (build 1435, incl. rain) | (was) `killall Weather` | resolved on 26A5368g |
| 5 | [OrbStack SwiftUI Charts → AttributeGraph abort](issues/orbstack-charts-attributegraph-crash.md) | Apple SwiftUI ↔ OrbStack 2.2.1 | 🟢 not repro on beta2 (3h21m) | — | [orbstack#2526](https://github.com/orbstack/orbstack/issues/2526) |
| 6 | [Chrome crash via MediaRemote Now-Playing nil](issues/chrome-mediaremote-nowplaying-crash.md) | Apple MediaRemote ↔ Chrome | 🟢 not repro on .201 (2h churn) | — | resolved on .201 |
| 7 | [ToDesk 10s crash-loop → "repeated logout"](issues/todesk-session-proxy-crash-loop.md) | ToDesk 4.9.7.1 (app bug) | 🟢 fixed in 4.9.7.2 | update to 4.9.7.2 (build 2064) | resolved |
| 8 | [Codex Dock-tile plugin infinite recursion crash](issues/codex-docktile-recursion-crash.md) | Codex.app (app bug) | 🟢 likely fixed in 26.623.31443 | update Codex (0 crashes in 7 days) | [openai/codex#27694](https://github.com/openai/codex/issues/27694) |
| 9 | [Telegram lag = animated-content redraw (not MAS-specific)](issues/telegram-mas-lag.md) | Telegram-macOS 12.8 (native) | 🟢 explained | disable auto-play/animated stickers (any build) | not a build/Apple bug |
| 10 | [WeChat (MAS) crash on launch — FIXED in 4.1.10](issues/wechat-mas-crash-fixed.md) | WeChat 4.1.9 MAS | 🟢 | update to 4.1.10 (or use official build) | resolved |
| 11 | [Swift Charts `if/else` fails to build under macOS 27 SDK](issues/swift-charts-conditionalcontent-macos27-sdk.md) | Apple Swift Charts (SDK/build) | 🟡 | use bare `if` / ternary, avoid `if/else` in chart builders | SDK behavior |
| 12 | [MenuBarAgent ~10–14% CPU at idle (static menu bar)](issues/apple-menubaragent-idle-cpu.md) | Apple MenuBarAgent | ✅ confirmed | none (beta regression) | Feedback: `FB________` |

## Filing readiness / 提交就绪度 (re-verified 2026-06-26, beta2 `26A5368g`)

Each Apple bug was re-tested live on the machine before drafting Feedback, so we don't file stale/wrong reports. Ready drafts live in [`feedback/`](feedback/).

- ✅ **Ready to file** (confirmed reproducing on beta2): **CoreMedia loop** ([draft](feedback/coremedia.md)) · **MenuBarAgent idle ~10–14% CPU** ([details](issues/apple-menubaragent-idle-cpu.md))
- ⏸ **Intermittent** — fires post-boot then self-settles; file with the captured boot-time evidence: **Shortcuts/Siri storm** ([draft](feedback/shortcuts.md))
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
