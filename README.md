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
| 3 | [WindowServer high CPU + `Invalid window` SkyLight loop](issues/apple-windowserver-invalid-window.md) | Apple WindowServer / SkyLight | 🟡 ✓confirmed | Reduce transparency/motion; restart offending app | Feedback: `FB________` |
| 4 | [Weather.app VFX thread spins ~36% CPU in background](issues/apple-weather-vfx-cpu-spin.md) | Apple Weather.app 6.0 | 🟢 fixed in beta2 | (was) `killall Weather` | resolved on 26A5368g |
| 5 | [OrbStack SwiftUI Charts → AttributeGraph abort](issues/orbstack-charts-attributegraph-crash.md) | Apple SwiftUI ↔ OrbStack 2.2.1 | 🟡 | don't keep usage-chart window open | [orbstack#2526](https://github.com/orbstack/orbstack/issues/2526) + Feedback `FB____` |
| 6 | [Chrome crash via MediaRemote Now-Playing nil](issues/chrome-mediaremote-nowplaying-crash.md) | Apple MediaRemote ↔ Chrome | ⚪ | disable `#hardware-media-key-handling` flag | Feedback: `FB________` |
| 7 | [ToDesk 10s crash-loop → "repeated logout"](issues/todesk-session-proxy-crash-loop.md) | ToDesk 4.9.7.1 (app bug) | 🟡 | `launchctl bootout` the 3 labels | ToDesk support · n/a GitHub |
| 8 | [Codex Dock-tile plugin infinite recursion crash](issues/codex-docktile-recursion-crash.md) | Codex.app (app bug) | 🔴 | harmless; Dock auto-restarts XPC | [openai/codex#27694](https://github.com/openai/codex/issues/27694) |
| 9 | [Telegram (MAS) sluggish / slow to respond](issues/telegram-mas-lag.md) | Telegram 12.8 (282010) MAS | ⚪ | use non-MAS build? (untested) | n/a yet |
| 10 | [WeChat (MAS) crash on launch — FIXED in 4.1.10](issues/wechat-mas-crash-fixed.md) | WeChat 4.1.9 MAS | 🟢 | update to 4.1.10 (or use official build) | resolved |

## Filing readiness / 提交就绪度 (re-verified 2026-06-26, beta2 `26A5368g`)

Each Apple bug was re-tested live on the machine before drafting Feedback, so we don't file stale/wrong reports. Ready drafts live in [`feedback/`](feedback/).

- ✅ **Ready to file** (confirmed reproducing on beta2): **CoreMedia loop** ([draft](feedback/coremedia.md)) · **WindowServer Invalid-window** ([draft](feedback/windowserver.md))
- ⏸ **Intermittent** — fires post-boot then self-settles; file with the captured boot-time evidence: **Shortcuts/Siri storm** ([draft](feedback/shortcuts.md))
- ⛔ **HOLD — do not file yet** (no fresh evidence on beta2):
  - **Weather VFX** — now **0.9–1.9% CPU**, VFX threads parked in `__psynch_cvwait`; **appears fixed/throttled in beta2**. ([note](feedback/weather.md))
  - **OrbStack** — no `OrbStack*.ips` on disk (beta1 crash purged); needs a fresh beta2 crash. ([note](feedback/orbstack.md))
  - **Chrome MediaRemote** — only crashed on .115/beta1; now on **149.0.7827.201** with no crash captured; retest first. ([note](feedback/chrome.md))

## How to contribute / 如何补充

Open an issue or PR with: macOS build (`sw_vers`), app version + whether it's a Mac App Store build, the exact crash/log signature, and any workaround you found. One file per problem under [`issues/`](issues/).

## Notes / 说明

- Most Apple-framework regressions can't be fixed app-side — the realistic action is **Apple Feedback Assistant**. Each Apple entry has an `FB________` slot; once filed, the Feedback ID gets pasted in so progress is traceable across betas.
- "Verified versions" were read from the app bundles on the test machine, not copied from changelogs.

*Not affiliated with Apple. Codename "Golden Gate" per public beta reporting.*
