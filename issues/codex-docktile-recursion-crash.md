# Codex.app Dock-tile plugin: infinite recursion → stack overflow → `EXC_BAD_ACCESS`
# Codex.app Dock 角标插件无限递归 → 爆栈 → EXC_BAD_ACCESS

> 🔗 **Track / 关注此问题:** [#8 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/8)

| | |
|---|---|
| **Status** | 🟢 Likely fixed in Codex 26.623.31443 (0 crashes in 7 days) — was a vendor (OpenAI) app bug |
| **macOS** | 27.0 beta (`26A5353q`) |
| **Component** | **Codex.app 26.609.71450 (build 3965)** — `CodexDockTilePlugin.plugin` |
| **Report** | Upstream: [openai/codex#27694](https://github.com/openai/codex/issues/27694) (dup #28438 filed by jizhi0v0, closed) |

## Symptom / 症状

`-[CodexDockTilePlugin_com_openai_codex setDockTile:]` recurses infinitely (depth ~37330), overflows the stack → `EXC_BAD_ACCESS`.

`-[CodexDockTilePlugin_com_openai_codex setDockTile:]` 无限递归（深度 ~37330）爆栈 → `EXC_BAD_ACCESS`。

## Evidence / 证据

- The crash happens inside the system Dock's XPC host `com.apple.dock.external.extra.arm64`, so the **crash report is filed under an Apple process name** — but the offending image is `/Applications/Codex.app/.../CodexDockTilePlugin.plugin`.
- High-frequency known bug: 235 reports accumulated under `Retired/`.

崩在系统 Dock 的 XPC 宿主里，所以崩溃报告挂在 Apple 进程名下，但肇事 image 是 Codex 的 Dock 插件。

## Workaround / 临时规避

Harmless in practice — the Dock auto-restarts the XPC host. Wait for an OpenAI fix.

危害小（Dock 自动重启 XPC），等官方修。

## Notes / 备注

Duplicate issue #28438 (filed as jizhi0v0) was closed as a dup but left a "still reproduces on this build" data point on #27694.

**Retest 2026-06-26 beta2 26A5368g — likely FIXED in Codex 26.623.31443 (build 4441):** Codex updated from 26.609.71450 → 26.623.31443. `com.apple.dock.external.extra.arm64` crash reports on disk are **0 in the last 7 days**; the last batch is all dated 2026-06-19. Previously this was high-frequency (235 reports). 7 days at zero across the update strongly suggests the recursion was fixed in the newer build. Not a hard confirmation (absence of crashes), but status downgraded from 🔴 to 🟢-pending.
