# Telegram (Mac App Store build) sluggish / slow to respond
# Telegram（Mac App Store 版）异常卡顿、响应慢

> 🔗 **Track / 关注此问题:** [#9 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/9)

| | |
|---|---|
| **Status** | 🟢 Closed / explained — Telegram's own continuous CVDisplayLink redraw loop (app-side inefficiency), **not a build/Apple bug** (see analysis below). The user-perceived Telegram stutter was actually the [#14](apple-click-input-latency-beta.md) panel-dismiss compositing regression — **fixed on beta3 `26A5378j`**. |
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

**Update 2026-06-26 — this was also the dominant WindowServer load driver:** quitting Telegram dropped system `WindowServer` from ~48% to single digits (user-observed). So Telegram's continuous window invalidation/redraw isn't just its own lag — it was forcing WindowServer to recomposite continuously and was the single biggest contributor to the "WindowServer high CPU" investigation (see [apple-windowserver-invalid-window](apple-windowserver-invalid-window.md)). Mitigation worth trying: disable auto-play / animated stickers & emoji in Telegram settings, or close chats with heavy animated content; compare the telegram.org build.

**MAS vs official native build — CLOSED 2026-06-26 (equivalent, not MAS-specific):** ran the **Mac App Store** build (`ru.keepcoder.Telegram`, App Store TeamID 6N38VWS5BX) side-by-side with the **macos.telegram.org standalone** build — both genuine native Telegram-macOS **12.8** (the standalone is Developer-ID-signed + notarized). After a **fair test** (quit both, relaunch fresh, same window size, same conversation), resources are **equivalent**: memory 325 MB (MAS) vs 315 MB (official); CPU ~6–7% on both, with which one is higher flipping between snapshots. An earlier reading showing MAS at 691 MB vs 342 MB was just **cache accumulation from a long-running instance**, not a build difference — it vanished after a fresh restart. So the "MAS is sluggish" framing is wrong: **it's the same native rendering engine; the build/sandbox makes no resource difference.** The actual cost is **animated content in the visible chat** (animated stickers/emoji, auto-playing GIF/video) → continuous redraw → WindowServer recompositing on the Retina XDR display. Real fix: **disable auto-play / animated stickers in Telegram settings** (works on any build); switching MAS↔official or toggling the in-app power-saving did not help. Note: do NOT confuse with **Telegram Desktop** (`com.tdesktop.Telegram`, Qt, v6.9.x) — that's a different, cross-platform client.

**Refinement 2026-06-26 — power saving does NOT fix it; it's a continuous render loop, not just animated content:** with the in-app power-saving ON and animations disabled, Telegram *still* drove WindowServer hard, and the user still saw WindowServer drop ~30% on quit (direct Activity Monitor observation). A `sample` of Telegram in its active state caught the mechanism: a persistent **`CVDisplayLink` thread** (`CVDisplayLink::runIOThread`, ~1967/2000 samples) driving continuous **`CA::Layer::commit` (×51)** + **`_recursiveTickleNeedsDisplay` (×123)** — i.e. Telegram re-commits/redraws its whole window every display frame while the window is active (scrolling or media in view), independent of animation auto-play. WindowServer then recomposites that on the Retina XDR display → ~30%. When the window is static/occluded it idles (~0.4–4%); the cost is tied to *active use*, not content type. So the real lever is the render loop itself (a Telegram-macOS app-side inefficiency, worth reporting to Telegram), not the in-app power-saving toggle.

⚠️ **Measurement caveat:** WindowServer's per-window attribution can't be tool-measured from inside this setup, because every measurement requires responding in the Claude desktop app, whose renderer itself spikes WindowServer 30–50% (a before/after quit test even showed WindowServer going *up* after quitting Telegram — pure Claude-render noise). The trustworthy evidence is the user's direct Activity-Monitor observation (no agent rendering during their observe-then-quit) plus the captured CVDisplayLink/CA-commit mechanism.
