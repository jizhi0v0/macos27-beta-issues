# CoreMedia `fpSupport_GetVideoRangeForCoreDisplayWithPreference` loop floods `logd`
# CoreMedia 查显示色域死循环刷爆 logd / 多个 WebKit app 后台空转

> 🔗 **Track / 关注此问题:** [#1 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/1)

| | |
|---|---|
| **Status** | 🟡 Mitigated (workaround) — present in beta1 **and** beta2 |
| **macOS** | 27.0 beta2 `26A5368g` (also beta1 `26A5353q`) |
| **Component** | Apple **MediaToolbox / CoreMedia** (`com.apple.coremedia`) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max, single built-in Liquid Retina XDR display |
| **Report** | Apple Feedback: **`FB23411581`** (filed 2026-06-26, Displays & Graphics → Incorrect/Unexpected Behavior; sysdiagnose + 90s flood capture attached) |

## Symptom / 症状

Shortly after boot (and after launching certain apps), `logd` burns ~20% CPU sustained and several **unrelated WebKit/Electron-based apps** show elevated background CPU **with no UI rendering**. The common cause is a tight loop inside CoreMedia querying the display's HDR video range, logged at *default* level (so `logd` persists every line to disk).

开机后不久，`logd` 持续吃 ~20% CPU，多个**互不相关的 WebKit/Electron app** 在没有任何 UI 渲染的情况下后台 CPU 偏高。根因是 CoreMedia 在死循环查显示器 HDR 色域，且日志是 default 级别（会被 logd 落盘）。

## Evidence / 证据

Identical log line emitted ~16×/sec **per app**, by four unrelated apps at once:

```
<<<< Alt >>>> fpSupport_GetVideoRangeForCoreDisplayWithPreference: displayID 1 reported
potentialHeadRoom=16 wideColorSupported=YES marz=NO almd=NO deviceAllowsHDR=YES
isBuiltinPanel=YES externalPanel=YES prefersHDR10=NO
```

`log show --last 60s` — emitters of this exact signature (≈2400 lines/60s total):

| process | lines/60s | kind |
|---|---|---|
| WeType (微信输入法 / Tencent input method) | 960 | input method, no window |
| DingTalk (钉钉) | 952 | Electron chat |
| Bob (translation app) | 480 | WebKit |
| Mail | 14 | WebKit content |

- **Tell-tale bug**: `externalPanel=YES` is reported even though the machine has **only the internal panel** — the parameters themselves are wrong, pointing at a framework regression, not the apps.
- `logd` cumulative CPU: 2:35 at 13 min uptime (≈20% avg). The flood is **post-boot / app-init transient** — it quiesced to 0 lines/30s by ~21 min uptime, and `logd` dropped back to ~1.6%.

## Reproduction / 复现

1. Boot into macOS 27 beta2.
2. Launch any mix of WebKit/Electron apps with a window doing color/HDR queries (input methods, Electron chat apps, WebKit browsers/translators).
3. `sudo log stream --predicate 'eventMessage CONTAINS "fpSupport_GetVideoRangeForCoreDisplay"'` — observe ~16/sec per app, then dying down after a few minutes.

## Workaround / 临时规避

- **Quit the WebKit/Electron apps you aren't using** — the loop only runs in live processes (biggest offender here: DingTalk).
- **Cap the `logd` cost** (reversible, needs root; resets on reboot):
  ```bash
  sudo log config --subsystem com.apple.coremedia --mode "level:off"      # silence
  sudo log config --subsystem com.apple.coremedia --mode "level:default"  # restore
  ```
- It self-settles within minutes of boot, so for many users no action is needed.

## Notes / 备注

- The signature `fpSupport_GetVideoRangeForCoreDisplayWithPreference` is a WebKit/WebProcess display-capability log (also seen historically in Electron apps, e.g. loft-sh/devpod#302), confirming the common path is web-content display/HDR detection.
- The `<<<< Alt >>>>` prefix is CoreMedia's internal subsystem tag — unrelated to the AltTab app.

**Retest 2026-06-26 beta2 26A5368g:** CONFIRMED — uptime 39 min; `log show --last 60s` = 1192 lines of `fpSupport_GetVideoRangeForCoreDisplayWithPreference`, all `externalPanel=YES` (wrong param, machine has only internal panel). Per-app rate: WeType[910] 480/60s (~8/s), DingTalk[2782] 472/60s (~8/s), Bob[1000] 240/60s (~4/s); Mail not emitting this run. logd 0.8% / 3:30 cum at sample. Still active well past boot, not self-settled.

**Retest 2026-07-07 beta3 26A5378j:** ⚪ not reproduced this window — **0** `fpSupport_GetVideoRange…` lines since boot (07:53, ~2.5 h). Conditional signature (needs a WebKit/WebProcess client doing display/HDR capability detection); none of the emitting apps hit the path in this window. "Not reproduced," not "confirmed fixed" — recheck with the WebKit apps active.
