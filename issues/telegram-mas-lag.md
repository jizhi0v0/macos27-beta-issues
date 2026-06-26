# Telegram (Mac App Store build) sluggish / slow to respond
# Telegram（Mac App Store 版）异常卡顿、响应慢

| | |
|---|---|
| **Status** | ⚪ Open — needs more characterization |
| **macOS** | 27.0 beta2 `26A5368g` |
| **Component** | **Telegram 12.8 (282010)** — Mac App Store build |
| **Report** | none yet |

## Symptom / 症状

The Mac App Store build of Telegram (12.8, build 282010) feels laggy and slow to respond on macOS 27 beta2 — UI interactions and message rendering have noticeable latency.

Mac App Store 版 Telegram（12.8 / 282010）在 macOS 27 beta2 上明显卡顿、操作和消息渲染有延迟。

## Evidence / 证据

- Observed background CPU in the moderate range (≈1–6% idle, cumulative ~1:00–1:40 over ~20 min uptime) — not a runaway, so the lag is likely **rendering / main-thread responsiveness**, not raw CPU starvation.
- TODO: capture a `sample Telegram` during a lag spike to see whether it's main-thread stalls, WebKit/Metal compositing, or framework waits.

## Workaround / 临时规避

- Untested: try the **non-Mac-App-Store** build from telegram.org (the MAS sandbox sometimes behaves differently on betas, as seen with WeChat MAS vs official).

## TODO

- [ ] `sample` during a stall and attach the busiest stacks.
- [ ] Compare MAS build vs telegram.org build on the same beta.

**Retest 2026-06-26 beta2 26A5368g — characterized (not a main-thread stall):** Telegram (PID 5138) at ~18% CPU after 1h30m uptime. `sample` (3s): most threads parked in `__psynch_cvwait`/`mach_msg` (idle), so it's **not a deadlock**. The active work is continuous UI redraw + media: top non-wait UI frame is `-[NSView _recursiveTickleNeedsDisplay]` (recursive view-dirty marking), alongside live `CVDisplayLink`, `com.apple.coremedia.imagequeue.coreanimation.common` and `coremedia.videomediaconverter` threads. → Consistent with **animated stickers/emoji or auto-playing video/GIF continuously invalidating & re-rendering views** (bursty, hence high average but a mostly-idle instantaneous sample). The "sluggish" feel is redraw churn, not a hang. Next: test with animated-content auto-play disabled, and compare the telegram.org (non-MAS) build.
