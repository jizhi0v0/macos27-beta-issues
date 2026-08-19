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

## Confirmed: `Remote` tracks an app resident on the iPhone / 已确认:`Remote` 由手机上驻留的 app 决定

Closing Spotify **on the iPhone** moved the remote score immediately and the Mac started winning:

```
16:55:07   Score 301, Remote 801     <- iOS Spotify still resident
16:55:58   Score 301, Remote  -1
16:56:34   Score 301, Remote 801     Route VirtualBluetooth  NumofApp 2
16:57:04   Score 301, Remote 801
17:00:58   Score 301, Remote 100     <- after closing it on the phone
```

Verified stable afterwards: **20 consecutive evaluations over 60 s, all `Score 301, Remote 100`**,
the AirPods staying connected to the Mac throughout. (`Route Speaker` persists only because
nothing was playing on the Mac at the time, so there was no reason to switch.)

So the arbitration itself works — it is the **input** that is wrong. While a media app is resident
on the phone it contributes **801**, which no Mac-side score of 301 can beat, and the headphones
are pulled back every three seconds regardless of `inEarStatus yes` or a manual connection made
seconds earlier.

**Workaround:** fully close the media app on the iPhone (not just pause it). `Remote` drops to
100 and the Mac holds the AirPods.

**Open, and it decides how bad this is:** whether iOS Spotify was *playing* or merely
*backgrounded/paused* when it was reporting 801. A playing app outscoring an idle Mac is arguably
correct; **a paused one doing so is not**, and that is the version consistent with the reported
symptom — audio was being handed *back* to the Mac, so the phone was not playing. This was not
instrumented on the phone side and needs a check there.

关闭 **iPhone 上的** Spotify 后,`Remote` 从 801 掉到 100,本机 301 立即胜出,AirPods 保持连接
(60 秒内 20 次评估全部本机胜)。所以仲裁逻辑本身没问题,**错的是输入**:手机上只要驻留着媒体 app
就贡献 801 分,Mac 的 301 永远打不过。**临时规避:在 iPhone 上彻底关闭该 app,而不是暂停。**
**待确认**:报 801 时 iOS Spotify 是在播放还是仅后台驻留 —— 后者才构成缺陷,而症状(音频正被交还给 Mac)
指向后者。

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
