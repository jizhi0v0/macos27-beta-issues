# AirPods refuse to stay on the Mac — SmartRouting arbitration loses to the iPhone every 3 s (`Score 301, Remote 801`)
# AirPods 连上 Mac 后立刻被抢走 —— SmartRouting 仲裁每 3 秒判给 iPhone

> 🔗 **Track / 关注此问题:** issue not yet filed — see "Filing" below

| | |
|---|---|
| **Status** | 🔴 Open · reproduced repeatedly on 2026-08-19 · **attributed to iOS 27 beta6 on the paired iPhone, not to macOS** — the reporter first saw it after upgrading the *phone*, while the Mac was still on macOS 27 beta5 `26A5406e` |
| **macOS** | observed on 27.0 beta5 `26A5406e` and beta6 `26A5416b` — the Mac side is a bystander |
| **iOS** | 27.0 beta6 on the paired iPhone (the device reporting `Remote 801`) |
| **Component** | Apple `audioaccessoryd` / `BTSmartRoutingDaemon` (AirPods automatic device switching) |
| **Hardware** | AirPods `C4:B3:49:AA:E7:97`, Product ID `0x2019`, firmware `9A336b`; `Mac15,11` M3 Max |
| **Reporter** | [@jizhi0v0](https://github.com/jizhi0v0) |

## Symptom / 症状

AirPods will not stay connected to the Mac. Handing audio back from the iPhone (e.g. pausing
Spotify there and playing on the Mac) does not bring them over at all; connecting them by hand
from the Bluetooth menu works for a moment and then **they drop back to the phone on their own**.

AirPods 无法留在 Mac 上。从 iPhone 交还音频时它们根本不过来;从蓝牙菜单手动连接会成功一瞬,
随后**自动掉回手机**。

## What the log shows / 日志证据

`audioaccessoryd`'s `BTSmartRoutingDaemon` prints its arbitration state every ~3 seconds:

```
16:41:31.308  Smart Routing device C4:B3:49:AA:E7:97 inEarStatus yes
16:41:31.308  AudioStateSnapshot: BtState PoweredOn Route Speaker
              App com.spotify.client, Score 301, Remote 801 NumofApp 1
16:41:34.308  Smart Routing device C4:B3:49:AA:E7:97 inEarStatus yes
16:41:34.308  AudioStateSnapshot: BtState PoweredOn Route Speaker
              App com.spotify.client, Score 301, Remote 801 NumofApp 1
```

Three facts hold simultaneously in every one of these snapshots:

- **`inEarStatus yes`** — the AirPods are in the ear;
- **`Route Speaker`** — yet audio is routed to the built-in speakers;
- **`Score 301, Remote 801`** — the local (Mac) score is **301** while the remote (iPhone) score
  is **801**, i.e. the phone outscores the Mac by 2.7× on every evaluation.

The arbitration therefore decides the AirPods belong to the phone, every three seconds, forever.
A manual connection from the Mac survives only until the next evaluation. `Remote 801` is a value
**reported by the phone**, which is consistent with the reporter's observation that this began
after the *iPhone* was upgraded to iOS 27 beta6 — the Mac was still on macOS 27 beta5 at the time.

**Rate:** 773 routing-related lines in 15 minutes on an otherwise idle Mac, i.e. the arbitration
never settles.

## Expected vs Actual / 预期与实际

- **Expected:** with the AirPods in the ear and an app actively playing on the Mac, the Mac should
  win the arbitration, or at minimum a *manual* connection should be honoured until the user
  changes it. Automatic switching exists to follow the user's attention, not to override an
  explicit choice every three seconds.
- **Actual:** the remote score is high enough that the Mac can never win, and manual connections
  are undone by the next evaluation. Audio stays on `Route Speaker` while the user is wearing the
  headphones.

## Reproduction / 复现

1. Pair AirPods with both a Mac (macOS 27 beta5/beta6) and an iPhone on **iOS 27 beta6**.
2. Play audio on the iPhone, then stop and start playback on the Mac — the AirPods do not come over.
3. Connect them manually from the Mac's Bluetooth menu — they connect, then drop back.
4. Watch the arbitration:

```bash
/usr/bin/log stream --predicate 'process == "audioaccessoryd"' --style syslog | grep -E "Smart Routing|AudioStateSnapshot"
```

or retrospectively, `/usr/bin/log show --last 15m --predicate 'process == "audioaccessoryd"'`.
(`log` is a zsh builtin — use `/usr/bin/log`.)

## Not established / 尚未确定

- Which inputs feed `Score` and `Remote`, and why the phone's is 801. Both are printed but
  undocumented.
- Whether the phone's score is *inflated* by iOS 27 beta6 or the Mac's is *deflated* — only the
  gap is observable from this side.
- Whether it reproduces with a non-beta iPhone, which is the cleanest control available and has
  not been run.

## Relationship to [#21](apple-controlcenter-volume-rmw-race.md) / 与 #21 的关系

The same AirPods address `C4:B3:49:AA:E7:97` appears in #21's own capture logs
(`BIND device 155 uid=C4-B3-49-AA-E7-97:output`), recorded there before anyone identified it as
this headset. #21's volume runaway was captured during a window with heavy SmartRouting churn
(1,230–1,634 lines/min against 182–658 in a quiet comparison). **That is a correlation, not a
mechanism** — a separate window with the same churn produced no runaway at all, so this issue is
*not* offered as #21's trigger. It is recorded because the two share a device and a subsystem.

## Filing / 提交

Not yet filed. This is primarily an **iOS** report even though every observation here was made
from the Mac, so a Feedback should be filed against iOS with a sysdiagnose from **both** devices
captured while the arbitration is flapping.
