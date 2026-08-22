# AirPods connect to the Mac but never publish an audio device — A2DP stays at `0 Kbps`, `Codc SBC`, `Freq Unknown`
# AirPods 能连上 Mac 但从不发布音频设备 —— A2DP 停在 `0 Kbps`、回退 SBC、采样率未协商

> 🔗 **Track / 关注此问题:** [#28 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/28)

| | |
|---|---|
| **Status** | 🔴 Open · **workaround found: case → close → open** (a Bluetooth-menu reconnect is *not* enough) · reproduced repeatedly on 2026-08-19 · **attributed to iOS 27 beta6 on the paired iPhone, not to macOS** — the reporter first saw it after upgrading the *phone*, while the Mac was still on macOS 27 beta5 `26A5406e` |
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
the AirPods staying connected to the Mac throughout. (`Route Speaker` was **wrongly** explained here as "nothing was playing on the Mac" — see the
correction below; Spotify **was** playing on the Mac.)

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

## Correction, and the actual failure / 更正:真正的故障

With Spotify **playing on the Mac**, the AirPods Bluetooth-connected, `inEarStatus yes`, and the
arbitration now won by the Mac 30/30 (`Score 301, Remote 100`), audio **still** goes to the
speakers. The reason is not arbitration at all:

**The AirPods are absent from CoreAudio's device list entirely.**

```
默认输出: id=107  MacBook Pro Speakers
可用设备: id=119 Bobby's iPhone Microphone
          id=114 MacBook Pro Microphone
          id=107 MacBook Pro Speakers
          id=59  OrayVirtualAudioDevice
```

No AirPods output device exists, so `Route Speaker` is the only option available — it is not a
routing decision being lost. Meanwhile Bluetooth reports the headset as **Connected**, with A2DP
advertised:

```
Services: 0x980019 < HFP AVRCP A2DP AACP GATT ACL >
```

and the link-quality snapshot shows why nothing is published:

```
17:05:00.132  GetControllerInfo: AuLQ [{ AoS 0, BtRt 0 Kbps,
              Codc SBC, Freq Unknown, DvNm 'Bobby's AirPods' }]
```

- **`BtRt 0 Kbps`** — no audio is streaming;
- **`Codc SBC`** — the codec fell back to SBC, where AirPods on Apple hardware normally use AAC;
- **`Freq Unknown`** — no sample rate was negotiated.

So the ACL link is up and A2DP is advertised, but **the A2DP stream never establishes**. Without
a stream there is no audio device to publish, and therefore nothing for SmartRouting to route to.

### What this does to the `Score 301, Remote 801` finding

It is demoted from "the defect" to "an observation whose relationship to the defect is
unresolved". Both states have now been seen:

| phase | `Remote` | Bluetooth | CoreAudio device | audio |
|---|---|---|---|---|
| iOS Spotify resident | **801** | connects, then drops repeatedly | never seen | speakers |
| iOS Spotify closed | **100** | **stays connected** | **still absent** | speakers |

Closing the app on the phone genuinely fixed the *connection flapping* — that part reproduced and
held for 20 consecutive evaluations. It did **not** produce a working audio device. Whether the
score war and the dead A2DP stream are one failure or two is **not established**.

**Everything above about the Mac being a bystander still holds**, and the SBC fallback plus
`Freq Unknown` point at the negotiation itself rather than at either OS's routing policy.

Spotify **在 Mac 上正在播放**、AirPods 蓝牙已连接、`inEarStatus yes`、仲裁本机 30/30 胜出的情况下,
声音**仍然**走扬声器。原因不是仲裁 —— **AirPods 根本不在 CoreAudio 的设备列表里**。蓝牙报告已连接、
A2DP 已广告,但链路快照显示 `BtRt 0 Kbps`、`Codc SBC`、`Freq Unknown`:**A2DP 流从未真正建立**,
没有流就没有可发布的音频设备。因此 `Score 301, Remote 801` 从"缺陷本身"降级为"关系未定的观察":
关闭手机上的 app 确实治好了**连接抖动**,但**没有**让音频设备出现。两者是一个故障还是两个,未确定。

## Recovery: forcing a fresh negotiation fixes it / 恢复:强制重新协商即可

Putting the AirPods back in the case, closing it and taking them out again — which forces a fresh
A2DP negotiation — resolved it immediately:

```
id=128  Bobby's AirPods
id=122  Bobby's AirPods      <- selected as default output
id=108  MacBook Pro Speakers
id=60   OrayVirtualAudioDevice
```

Two AirPods entries now exist where there were none, one of them is the **default output device**,
and the arbitration moved from `Route Speaker` to `Route Bluetooth`.

**`Score 301, Remote 100` did not change across the recovery.** The arbitration said the Mac won
both before and after, so the score has no bearing on whether a device exists — which is the final
piece confirming the failure is in the **A2DP negotiation**, not in routing policy on either OS.

**Workaround:** case → close → open. Reconnecting from the Bluetooth menu is *not* enough; that
re-establishes the ACL link without renegotiating the stream, which is exactly the broken state.

**Not captured:** a healthy `AuLQ` snapshot for numeric contrast against the failing
`AoS 0, BtRt 0 Kbps, Codc SBC, Freq Unknown` — the line stopped appearing once the stream was
working. Anyone reproducing this should grab `GetControllerInfo … AuLQ` in **both** states.

把 AirPods 放回充电盒、合盖、再取出(强制重新协商 A2DP)后立即恢复:设备列表中出现两个 AirPods 条目,
其一成为默认输出,路由从 `Route Speaker` 转为 `Route Bluetooth`。**`Score 301, Remote 100` 在恢复
前后完全没变** —— 仲裁与"设备是否存在"无关,这是确认故障出在 **A2DP 协商**而非路由策略的最后一块拼图。
**规避:放回盒子合盖再取出;从蓝牙菜单重连不够**,那只重建 ACL 链路而不重新协商流,正是坏掉的那个状态。

## Expected vs Actual / 预期与实际

- **Expected:** AirPods that report as Connected with A2DP advertised should negotiate a stream
  and appear as a CoreAudio output device, so that audio playing on the Mac can reach them.
- **Actual:** the ACL link is up and Bluetooth calls them Connected, but A2DP stays at `0 Kbps`
  with `Codc SBC` and `Freq Unknown`, no output device is ever published, and audio plays out of
  the speakers while the user is wearing the headphones. Separately, while a media app is resident
  on the paired iPhone the connection also flaps, driven by `Score 301` against `Remote 801`.

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
