# ControlCenter volume runaway — concurrent read-modify-write ratchets system volume to 0 or 100% and spins at 30 Hz
# ControlCenter 音量失控 —— 并发 read-modify-write 把系统音量棘轮到 0 或 100%,并以 30 Hz 空转

> 🔗 **Track / 关注此问题:** [#21 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/21)

| | |
|---|---|
| **Status** | 🔴 **reproduced on beta6 `26A5416b`** (2026-08-19 16:11–16:14) — signature identical: `setLevel` at exactly **33.3 ms intervals = 30 Hz**, step size exactly **1/16**, both directions, railing at 1.0 and **continuing to write 1.0 at 30 Hz indefinitely** while railed. 3,395 `set system volume` lines in 6 min, sustained 30/s at peak; 4,265 `Setting main volume` lines in the 25-minute capture. Alcove 1.7.9 running, as the trigger requires. Machine became visibly stuck: `coreaudiod` **145%**, ControlCenter 27%. See [the beta6 capture](#reproduction-2026-08-19--beta6-26a5416b--signature-unchanged). Prior: 🔴 Not fixed · confirmed on `26A5378n` (beta3), `26A5388g` (beta4) **and `26A5406e` (beta5)** — **10+ runaways captured in one day**, both directions, both output devices; reproducible on demand (see [Reproduction](#reproduction--复现)). **Still firing 2026-08-04** ([incident 3](#incident-3--2026-08-04-bluetooth-reconnect-full-up-then-down-cycle-in-one-runaway--事故-3蓝牙重连触发单次事故内先冲顶再坠底): 4,849 writes / 170.7 s, up to full scale **and** down to zero in one runaway, `coreaudiod` dragged to 150–180% CPU) . **Again 2026-08-05 (incident 4): 107,675 writes over 63 min**, triggered by an iPhone→Mac hand-off, with the ratchet demonstrably starting **before** any key press. **Survives into beta5 ([incident 5](#incident-5--2026-08-11-beta5-26a5406e-device-switch-alone-pinned-at-full-scale-while-repeatedly-un-muting-itself--事故-5仅靠设备切换触发钉在满刻度并反复自行取消静音), 2026-08-11)**: 60 writes/s across **11 ControlCenter threads**, pinned at full scale on worn Bluetooth headphones, `coreaudiod` at **185.8%** |
| **macOS** | 27.0 beta3 revision **`26A5378n`**, reconfirmed on **beta4 `26A5388g`** (2026-07-22) and **beta5 `26A5406e`** (2026-08-11) — **not 27-specific**, see [Scope](#scope-not-a-27-regression--并非-27-回归) |
| **Component** | Apple **ControlCenter** (`com.apple.controlcenter`, `SoundSettings`) + CoreAudio HAL volume properties |
| **Trigger** | **Alcove 1.7.9** (`com.henrikruscon.Alcove`, build 203) must be running — established by A/B, both directions. Fires on an **output-device change**: a Spotify Connect transfer (incident 1), the on-demand recipe's device switch + rapid manual adjustment, or — new in [incident 3](#incident-3--2026-08-04-bluetooth-reconnect-full-up-then-down-cycle-in-one-runaway--事故-3蓝牙重连触发单次事故内先冲顶再坠底) — a **Bluetooth headphone reconnect with no transfer involved**. **[Incident 5](#incident-5--2026-08-11-beta5-26a5406e-device-switch-alone-pinned-at-full-scale-while-repeatedly-un-muting-itself--事故-5仅靠设备切换触发钉在满刻度并反复自行取消静音) narrows this further: the device switch *alone* is enough** — no synthetic writer, no rapid key adjustment, ratchet within 0.3 s of the switch. Mechanism by which Alcove contributes is **unidentified**; see [Open question](#open-question--未解) |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max, 36 GB |
| **Report** | Apple Feedback: **[FB23868196](https://feedbackassistant.apple.com/feedback/23868196)** (filed 2026-07-20 via Feedback Assistant — Control Center → "Incorrect/Unexpected Behavior"; sysdiagnose + ratchet log + concurrent-TID log + HID-absence log + before/after rate table attached)  · **follow-up 2 drafted 2026-08-04, extended 2026-08-11** — generalised trigger, both directions, coreaudiod CPU cost, a retraction of the torn-read evidence, and now a beta5 section (device switch alone suffices; the loop cancels the user's own mute ~30×/s) ([paste text](../feedback/controlcenter-volume-followup2.txt)), **still not submitted**|

## Summary / 摘要

System volume becomes uncontrollable: it ratchets monotonically to **either** 0 % (+ mute) **or** 100 % and stays pinned there, while ControlCenter writes the CoreAudio volume property at **~30 Hz indefinitely**. User volume adjustments are immediately overridden — the ratchet just restarts from the new value.

The **direction** (up or down) varies between occurrences, and the **device** varies *within* a single occurrence — incident 1 thrashed between the AirPods and the built-in speakers six times, including across an AirPods reconnect that reassigned the device ID. Every write during the runaway comes from **ControlCenter's own threads** — the third-party app that is a necessary precondition issues **zero** volume writes while the loop runs.

**Hearing-safety relevance — not theoretical.** The affected output in incident 1 was a pair of **AirPods 4 being worn at the time**; ControlCenter issued **1,158 writes setting that device to `1.000000`** — full scale, in-ear. The ratchet advances one 1/16 step per ~33 ms, so the climb takes **≈0.5 s with no ramp**. Recovery required killing the agent from a terminal, which is not available to a normal user while the sound is painful.

系统音量失控:单向棘轮到 0%(并静音)或 100% 并卡死,ControlCenter 以约 30 Hz 无限写入音量属性。手动调节会被立即覆盖 —— 棘轮只是从新值重新开始。方向(上/下)在两次事故间不同,**设备则在单次事故内来回跳** —— 事故1 在 AirPods 和内置扬声器之间横跳 6 次,期间 AirPods 还断开重连换了设备 ID。失控期间的每一条写入都来自 ControlCenter 自己的线程。

**听力安全:事故1 中被顶到满音量的是正戴着的 AirPods 4**,ControlCenter 向该设备写入 `1.000000` 共 **1,158 次**。

## Symptom / 症状

The two earliest occurrences are broken down below because they were captured with the fullest instrumentation and between them show every axis of variation — direction, device, and mid-runaway device migration. They are **representative, not exhaustive**: 8 further runaways followed the same shape. Full timestamp list under [Reproduction](#reproduction--复现).

最早两次在下面详细拆解 —— 它们的仪表数据最完整,且合起来涵盖了全部变化维度(方向、设备、失控中途的设备迁移)。这是**代表性样本而非全部**,后续另有 8 次同型发作。

| | Incident 1 | Incident 2 |
|---|---|---|
| Wall time | 10:39:26 → 10:44 (ended by `killall`) | ~10:52 → 10:54 (ended by `killall`) |
| Direction | ratchets **up** → pinned `1.000000` | ratchets **down** → pinned `0.000000` + `muted=true` |
| Device | **thrashes across 3 IDs**: `198`→`100`→`198`→`100`→`212`→`100` (198/212 = same **AirPods 4**, reconnected mid-runaway; 100 = `BuiltInSpeakerDevice`) | `C4-B3-49-AA-E7-97` — the same **AirPods 4** |
| Per-device totals | 100: **14,533** · 198: **2,182** · 212: **865** | **0 writes to device 100** |
| ControlCenter threads writing | multiple | **7 distinct** |
| Rate | 1,800 `set system volume` lines/min = **30 Hz** | 493 client-side writes / 8 s ≈ **30 Hz** each for `vmvc` + `mute` |

The ratchet step is exactly **1/16** — the standard macOS volume increment:

```
10:39:26.849  set system volume: 0.435000 -> 0.500000
10:39:27.116  set system volume: 0.500000 -> 0.562500
10:39:27.149  set system volume: 0.562500 -> 0.625000
10:39:27.182  set system volume: 0.625000 -> 0.687500
10:39:27.215  set system volume: 0.687500 -> 0.750000
10:39:27.249  set system volume: 0.750000 -> 0.812500
10:39:27.285  set system volume: 0.490000 -> 0.500000   ← read side is a non-1/16 value; ratchet restarts from 0.5
10:39:27.315  set system volume: 0.500000 -> 0.562500
...
```

Once the rail is reached it spins forever without changing anything:

```
232 ×  set system volume: 1.000000 -> 1.000000
```

## Root cause / 根因

A **lost-update race on the volume property inside ControlCenter**. Several ControlCenter threads concurrently perform read-modify-write:

```
thread A: read 0.500 ─┐
thread B: read 0.500 ─┼─ each computes "current + 1/16"
thread C: read 0.500 ─┘         │
                                ▼
              all three write 0.5625 … but against a value
              that has already moved → updates are lost,
              the net effect is monotonic and one-directional
                                │
                                ▼
              ControlCenter's own write raises a property-changed
              notification → schedules another sync → more concurrent
              RMW → self-sustaining at 30 Hz
```

Evidence for the race specifically (rather than an external "volume up" source):

1. **Direction is arbitrary.** Incident 1 ratcheted up, incident 2 down. A stuck key or a repeating HID event can only go one way. A lost-update race has no preferred direction — whichever thread lands last wins.
2. **A single runaway migrates between devices.** Incident 1 alternated AirPods ↔ built-in speakers six times, and *followed the AirPods across a disconnect/reconnect* from device ID `198` to `212`. A per-device state machine driven by real input would neither migrate mid-runaway nor track the same physical device through an ID change.
3. **Distinct threads do the writing.** In incident 2, seven ControlCenter TIDs (`54625`, `5498c`, `5467e`, `5386f`, `5498a`, `5499c`, `5498e`) all issue `AudioObjectSetPropertyData`. The bookkeeping line (`set system volume: X -> Y`) comes from a *different* thread (`1b1b`) than the threads doing the CoreAudio writes.
4. **Non-1/16 values appear on the *read* side.** `0.435000 -> 0.5`, `0.490000 -> 0.5`: the write side only ever emits multiples of 1/16, so these were current when a thread read but replaced by the time it wrote. **Weaker than it looks** — `0.435` could equally be the AirPods' own pre-existing level when the transfer landed. Offered as *consistent with* a race, not proof; points 1–3 carry the argument.
5. **No HID input.** A 6-second HID capture during an active runaway returned **one** key event total. No `NX_KEYTYPE_SOUND_UP` stream, no injected events.
6. **The loop is closed inside ControlCenter.** Each iteration is `syncMute → updateMute → setLevel → set system volume → present VolumeSystemBannerContent`, all in-process.

## The trigger is a precondition, not the driver / 触发源是前提,不是驱动

**Quitting Alcove prevents the bug** (reporter-verified — see [Open question](#open-question--未解)). But Alcove does **not** issue the runaway commands:

| | Incident 1 | Incident 2 |
|---|---|---|
| Alcove volume writes **during** the runaway | all occur **after** onset (`10:39:28.333`+, onset was `10:39:26.849`) | **0** |
| Alcove volume writes **before** onset | 2, at `10:39:17` (~10 s earlier), to `BuiltInSpeakerDevice` | — |
| ControlCenter writes | all of them | 493 of 496 (other 3 = the investigator's `osascript`) |

In incident 2 Alcove was running for the entire runaway and wrote **nothing**. In incident 1 its writes land *after* the loop had already started, and target the Bluetooth device — i.e. Alcove is **reacting** to the volume changes, not causing them.

**Reading:** Alcove is the seed that gets ControlCenter into the racing state; ControlCenter is the engine that sustains it. Once started, the loop needs no external participant.

Alcove 在事故2 中全程运行却零写入,失控照常发生;事故1 中它的写入全部晚于失控起点。它是把 ControlCenter 推进竞态的**种子**,而不是失控指令的来源。

### Onset timing / 起爆时刻

```
10:39:26.646  coreaudiod    >>> NEGOTIATE [com.spotify.client]        ← Spotify Connect transfer to this Mac
10:39:26.665  Spotify       AUHAL HALListener registers
10:39:26.835  ControlCenter (DeviceID 198) setLevel: main vol 0.500000  ← the manual volume adjustment
10:39:26.849  ControlCenter set system volume: 0.435 -> 0.5           ← +14 ms, runaway begins
```

**No volume write of any kind appears between 10:39:20 and 10:39:26.835**, so the adjustment at `.835` is the first mutation in the sequence — it lands ~190 ms after the device negotiation, inside ControlCenter's post-transfer re-sync. That collision is the most likely source of the concurrent mutation paths. *The log cannot distinguish a user-initiated `setLevel` from ControlCenter's own re-sync* — both log identically — but it matches the reporter's account (transfer → reflexively adjust volume → runaway).

Spotify itself never writes a volume property — a full-window grep for Spotify volume writes returns **nothing**. It contributes the *audio-device renegotiation*, which is what makes ControlCenter re-sync volume state.

## Incident 3 — 2026-08-04, Bluetooth reconnect, full up-then-down cycle in one runaway / 事故 3:蓝牙重连触发,单次事故内先冲顶再坠底

Caught live on **beta4 `26A5388g`** and captured end to end. This is the most complete capture so far: a single runaway that ratchets **to full scale, spins there, reverses, and pins at zero**, where every previous incident went one direction only.

在 **beta4 `26A5388g`** 上抓到现行并完整记录。这是迄今最完整的一次:同一次失控里先棘轮到满刻度、在顶端空转、再反向坠到 0 并卡死 —— 此前每次事故都只有单一方向。

| | |
|---|---|
| Window | `11:02:15.360987` → `11:05:06.031483` = **170.7 s** |
| Writes | **4,849** `set system volume` lines = **28.4/s** (~30 Hz) |
| Direction | **both, in one incident** — up to `1.000000`, then down to `0.000000` |
| Ended by | `killall ControlCenter` (writes in the following 5 s: **0**) |
| Output device | Bluetooth headphones, just reconnected |
| Alcove | 1.7.9 running (the established precondition) |

### Timeline / 时序

```
11:02:15.360987  ControlCenter  set system volume: 0.215000 -> 0.250000   ← first write; read side is NOT a 1/16 value
11:02:15.462071  coreaudiod     BTUnifiedAudioDevice: Connected device <private>
11:02:15.565448  coreaudiod     Smart Route: Tipi Connection Changed to Connected
11:02:15.930699  ControlCenter  set system volume: 0.937500 -> 1.000000   ← FULL SCALE, 570 ms after onset
   …             35 × 1.000000 -> 1.000000                                ← spins at the top rail ~1.2 s
11:02:17.099573  ControlCenter  last write at 1.0, ratchet reverses
11:02:19.996664  ControlCenter  set system volume: 0.062500 -> 0.000000   ← bottom reached
   …             4,604 × 0.000000 -> 0.000000                             ← pinned + muted for 166 s
11:05:06.031483  ControlCenter  last write — killall ControlCenter
```

Step size is exactly **1/16 (0.0625)** on all 208 real transitions; the only two non-1/16 deltas are on the **read** side (`0.215`, one other), the same read-side signature described in [Root cause](#root-cause--根因).

208 次真实变化的步长全部恰为 **1/16**;仅有的两个非 1/16 值都出现在**读**侧,与[根因](#root-cause--根因)里描述的读侧签名一致。

### Trigger: a Bluetooth reconnect, with no Spotify/AirPlay transfer involved / 触发:蓝牙重连,不涉及 Spotify/AirPlay 切换

The reporter had walked away and come back; the headphones reconnected on their own. The first volume write lands **101 ms before** the `BTUnifiedAudioDevice: Connected` line and ~200 ms before `Smart Route ... Connected` — i.e. inside the same device-change window, on the leading edge of it.

This matters because it **generalises the trigger**. Incident 1 arrived via a Spotify Connect transfer; the [on-demand recipe](#the-recipe--复现配方) uses an output-device change followed by rapid manual volume adjustment. Here there was no Spotify transfer and no AirPlay hand-off — just a Bluetooth device reconnecting after an absence, followed 150 ms later by a volume-key press (see below). What the three share is an **output-device change** immediately followed by a volume mutation; the *kind* of device change is evidently irrelevant, which is the part worth putting in front of Apple.

**RESOLVED — the volume key *was* pressed.** ControlCenter logs hot-key presses distinctly, so this did not have to stay open:

```
11:02:14.930156  ControlCenter  system volume of 64 updated: 0.500000 -> 0.562500
11:02:15.184629  ControlCenter  system-banners: show smart routing connected … C4:B3:49:AA:E7:97   ← AirPods connect
11:02:15.191594  ControlCenter  system volume of 22d updated: 0.562500 -> 0.215000   ← re-sync to the AirPods' OWN level
11:02:15.340920  ControlCenter  [HotKeys] Notifying observer … for hot key 'volumeUp (builtin, down)'   ← USER PRESSES VOLUME-UP
11:02:15.341310  ControlCenter  <SoundSettings> (DeviceID 557) setLevel: Setting main volume to 0.250000
11:02:15.360987  ControlCenter  set system volume: 0.215000 -> 0.250000              ← +20 ms, runaway begins
```

So incident 3 **does** contain the rapid manual adjustment, ~150 ms after the device change — it does *not* remove that condition from the recipe. The reporter's own reasoning for why is worth recording: *"if you don't adjust it, you wouldn't notice"* — which is an **observation bias**, not evidence of necessity. Manual adjustment may be present in every observed incident simply because it is the detection path. That question stays open; what is now settled is that this incident is not a counter-example.

**Methodology correction:** the [Onset timing](#onset-timing--起爆时刻) section states that the log cannot distinguish a user `setLevel` from ControlCenter's own re-sync. That is **wrong as stated** — `[com.apple.controlcenter:HotKeys] Notifying observer … for hot key 'volumeUp (builtin, down)'` identifies a hardware volume-key press explicitly, at `--info` level. Future incidents should be checked against the `HotKeys` subsystem before the input question is called unanswerable. (It remains true that a *slider drag* in the Control Center UI would not produce a HotKeys line.)

**Bonus — the non-1/16 read value is now explained.** [Root cause](#root-cause--根因) point 4 offers `0.435`/`0.490` as *possibly* the accessory's own pre-existing level rather than a torn read, and rates that alternative as weaker. Here it is confirmed outright: `system volume of 22d updated: 0.562500 -> 0.215000` is ControlCenter adopting the AirPods' own stored level on connect, and `0.215` is exactly the read side of the first runaway write. **The non-1/16 read values are accessory levels, not torn reads** — point 4 should be retired as evidence for the race. Points 1–3 (concurrent TIDs, 1/16 write side, 30 Hz self-sustain) carry the argument unchanged.

**已解决 —— 音量键确实按了。** ControlCenter 会单独记录热键事件:设备变更后约 150 毫秒,`hot key 'volumeUp (builtin, down)'` 明确记录了硬件音量+键按下,20 毫秒后失控开始。故事故 3 **包含**快速手动调节,并未把该条件从配方中剔除。报告者的解释值得记录:"不调节应该发现不了" —— 这是**观察偏倚**,而非必要性的证据:手动调节可能只是"发现该 bug 的途径",而非触发的必要条件。该问题仍未决,已确定的只是这次事故不构成反例。

**方法学更正:**[起爆时刻](#onset-timing--起爆时刻)一节称"日志无法区分用户 setLevel 与自动重同步",该说法**有误** —— `HotKeys` 子系统在 `--info` 级别明确记录硬件音量键。今后应先查 `HotKeys` 再判定输入不可知。(但 Control Center 界面上的拖动滑块确实不会产生 HotKeys 记录。)

**附带收获 —— 非 1/16 读值有解释了。**[根因](#root-cause--根因)第 4 点把 `0.435`/`0.490` 列为"可能是配件自身既有音量而非撕裂读取",并自评为较弱证据。这次直接坐实:`system volume of 22d updated: 0.562500 -> 0.215000` 就是 ControlCenter 在连接时采用 AirPods 自身存储的音量,而 `0.215` 正是首条失控写入的读侧值。**非 1/16 读值是配件音量,不是撕裂读取** —— 第 4 点应作为竞态证据撤下;第 1–3 点(并发 TID、写侧恒为 1/16、30 Hz 自持)不受影响。

### Alcove's role, observed in an unstaged incident / Alcove 的角色:一次非人为安排的事故里的观察

Every previous statement about Alcove came from **deliberately staged** A/B runs with `racetrigger`. Incident 3 was not staged, so the same question can be asked of a naturally-occurring runaway. Client-side volume writes across the full 170.7 s window:

| Process | `LogVolumeChangeForClientSide` writes |
|---|---|
| **ControlCenter** | **9,947** |
| Alcove | 211 |
| coreaudiod | 5 |

**Alcove was writing**, so incident 3 is not a counter-example to [Alcove must be *writing*](#alcove-must-be-writing-not-merely-running--alcove-必须在写) — that record is now **6/6**. The timing is the informative part:

```
11:02:14.927718  Alcove         ['vmvc'] volume: 0.562500                          <- Alcove writes
11:02:14.930156  ControlCenter  system volume of 64 updated: 0.500000 -> 0.562500  <- +2.4 ms, CC observes it
11:02:15.13-.16  coreaudiod     AirPods connect; writes 0.215000 (accessory's own level)
11:02:15.340920  ControlCenter  [HotKeys] hot key 'volumeUp (builtin, down)'
11:02:15.360987  ControlCenter  set system volume: 0.215000 -> 0.250000            <- runaway begins
   ...           Alcove silent for 3.9 s                                           <- the entire climb, the
                                                                                      top-rail spin, and the
                                                                                      start of the reversal
11:02:18.826959  Alcove         ['vmvc'] volume: 0.937500                          <- reappears, tracking the
                                                                                      ratchet downward
```

Two things follow:

1. **Alcove initiates a volume change 433 ms before onset**, and ControlCenter observes that value 2.4 ms later — the ordering expected if Alcove wrote it and ControlCenter followed, not the reverse. It lands immediately before the device change and the key press.
2. **Alcove is silent for the first 3.9 s of the runaway** — through `0.215 -> 1.000000`, the 35 no-op writes at the top rail, and the reversal. The 30 Hz self-sustaining loop is **entirely ControlCenter's own writes**, confirming [the trigger is a precondition, not the driver](#the-trigger-is-a-precondition-not-the-driver--触发源是前提不是驱动) in an incident nobody arranged.

**Not claimed:** that Alcove's 139 writes of `1.000000` at 11:03:18–24, while ControlCenter was pinned at zero, represent a tug-of-war. That window overlaps the reporter trying to restore volume *and* the investigator running capture commands, so Alcove-initiated and Alcove-reacting cannot be separated there. Recorded as uninterpretable rather than as evidence.

**Limit of this data point:** it is a correlation within a single incident. Alcove is a HUD app that follows volume changes by design, so "it was writing" cannot by itself establish causation — that still rests on the 2026-07-20 A/B, where a synthetic writer at **38× Alcove's rate** with Alcove quit produced nothing. Incident 3 is another positive case, not an independent proof.

此前关于 Alcove 的每一条结论都来自**人为安排**的 A/B。事故 3 并非安排出来的,因此可以在一次自然发生的失控里问同样的问题。全窗口客户端写入:ControlCenter 9,947 次、Alcove 211 次、coreaudiod 5 次。**Alcove 确在写**,故事故 3 不构成反例,该记录现为 **6/6**。

关键在时序:Alcove 在失控前 433 毫秒主动写入 0.5625,ControlCenter 于 2.4 毫秒后才观察到该值 —— 顺序正是"Alcove 写、CC 跟随",而非相反;而失控开始后 **Alcove 沉默 3.9 秒**,覆盖整个冲顶、顶端空转与反转起点,说明 30 Hz 自持循环**完全是 ControlCenter 自己的写入**。这在一次无人安排的事故里印证了"触发源是前提,不是驱动"。

**不作主张的部分:** 11:03:18–24 期间 Alcove 139 次写入 `1.000000` 与 CC 钉零并存,但该时段与报告者尝试恢复音量、调查者执行抓取命令重叠,无法区分自发与响应,记为不可解读而非证据。

**本数据点的局限:** 这是单次事故内的相关性。Alcove 本就是设计成跟随音量变化的 HUD 应用,"它在写"本身不能确立因果 —— 因果仍依赖 07-20 那组 A/B(Alcove 退出 + 写压力为其 38 倍的合成写入器 → 不触发)。事故 3 是又一个正例,不是独立证明。

### Hearing-safety: full scale on in-ear headphones in 570 ms / 听力安全:570 毫秒内在入耳式耳机上冲到满刻度

The ratchet went from `0.215` to `1.000000` in **570 ms**, on **headphones the reporter had just put back on**, with no ramp. This is the second incident to drive a worn in-ear/headphone device to full scale (incident 1 did it to AirPods 4 with 1,158 writes at `1.000000`). The user-facing complaint this time was the *stuck-at-zero* tail, which is the harmless end — but the dangerous end happened first and lasted only a second, which is exactly why it is easy to under-report.

棘轮在 **570 毫秒**内从 `0.215` 冲到 `1.000000`,发生在报告者刚戴回的耳机上,无渐变。这是第二次把佩戴中的入耳/头戴设备推到满刻度。用户这次感知到的是"卡在 0"的尾段(无害的一端),而危险的一端发生在最前面、只持续约一秒 —— 这正是它容易被漏报的原因。

### New observation: `coreaudiod` is dragged to 150–180% CPU / 新观察:`coreaudiod` 被拖到 150–180% CPU

Previous write-ups measured ControlCenter's own spin. During this incident:

| Process | During runaway | After `killall ControlCenter` |
|---|---|---|
| `coreaudiod` | **150–181%** | 112% and falling |
| `ControlCenter` | 13.6–20.8% | **0.3%** |

So the 30 Hz write loop costs roughly **1.5–1.8 cores in the HAL**, an order of magnitude more than in the agent doing the writing. Worth adding to the Feedback: the impact is not just "volume misbehaves", it is a sustained system-wide CPU cost for as long as it runs.

30 Hz 写循环在 HAL 侧的代价约为 **1.5–1.8 个核**,比发起写入的 agent 本身高一个数量级。值得补进 Feedback:影响不止"音量失控",还有持续的全系统 CPU 开销。

### Recovery / 恢复

`killall ControlCenter` again worked, immediately: **0** volume writes in the 5 s after the agent respawned, volume restored to a sane 75% and unmuted, ControlCenter back to 0.3% CPU.

## Incident 4 — 2026-08-05, iPhone→Mac auto-switch; the ratchet starts BEFORE any key press / 事故 4:iPhone→Mac 自动切换,棘轮先于按键启动

The longest and most informative occurrence so far: **63 minutes, 107,675 writes** — 22× incident 3. It answers, in the negative, the question incident 3 left open about whether the user's volume adjustment is what starts the ratchet.

迄今最长、信息量最大的一次:**63 分钟、107,675 次写入**,是事故 3 的 22 倍。它以否定的方式回答了事故 3 遗留的问题:棘轮并非由用户的音量调节启动。

| | |
|---|---|
| Window | `12:45:08.315` → `13:48:08.704` = **63.0 min** |
| Writes | **107,675** `set system volume` = 1,800/min sustained (30 Hz) for the whole hour |
| Direction | down; pinned at `0.000000` + `mute: 1.000000` |
| Trigger | **iPhone → Mac automatic route switch** (AirPods hand-off) |
| Ended by | `killall ControlCenter` — it did **not** stop on its own |
| Alcove | 1.7.9 running; **18 writes** in the entire 63 min |

### Onset — Alcove ratchets first, the key press arrives 1.7 s later / 起爆:Alcove 先棘轮,按键晚 1.7 秒

```
12:44:57.844  ControlCenter  system-banners: show smart routing REVERSE ROUTE,
                             C4:B3:49:AA:E7:97                      <- iPhone -> Mac auto-switch
12:45:06.594  Alcove         ['vmvc'] volume: 0.467500   ┐
12:45:06.617  ControlCenter  system volume of 223 updated: 0.530000 -> 0.467500   (+23 ms, CC observes)
12:45:06.894  Alcove         ['vmvc'] volume: 0.405000   │  four clean 1/16 steps,
12:45:07.305  Alcove         ['vmvc'] volume: 0.342500   │  ~300 ms apart, ALL from Alcove
12:45:07.587  Alcove         ['vmvc'] volume: 0.280000   ┘
12:45:08.146  AVRouting      configUpdateReasonEndedBottomUpRouteChange   <- route switch completes
12:45:08.152  ControlCenter  system volume of 65 updated: 0.280000 -> 0.176838   (device changes)
12:45:08.289  ControlCenter  [HotKeys] hot key 'volumeDown (builtin, down)'      <- the ONLY key event
12:45:08.295  ControlCenter  <SoundSettings> (DeviceID 101) setLevel: 0.062500
12:45:08.315  ControlCenter  set system volume: 0.176838 -> 0.062500             <- runaway begins
   …          107,675 writes, pinned at 0 + muted, for 63 minutes
```

**A descending 1/16 ratchet was already running 1.7 s before the only key press, and every step of it was written by Alcove** — each Alcove write preceding ControlCenter's observation of that value by ~23 ms, the same write→observe ordering seen in [incident 3](#alcoves-role-observed-in-an-unstaged-incident--alcove-的角色一次非人为安排的事故里的观察).

**What this settles, and what it does not.** It settles that the user's volume adjustment does **not** initiate the ratchet — the ratchet predates it. It does **not** establish that the runaway can reach its self-sustaining state with *zero* input: there is exactly one `volumeDown` HotKeys event, 26 ms before ControlCenter's first runaway write, so input is present at the moment ControlCenter takes over. The honest reading is that manual adjustment is **not the initiator** but has not yet been excluded as a **contributor at the handover**. The reporter's recollection was that they had not adjusted the volume at all; the HotKeys line says otherwise, and the log is the record. Their perception is nevertheless explained by the data — the volume genuinely was falling on its own for 1.7 s before any key was touched.

**已确定与未确定。** 已确定:用户的音量调节**不是**棘轮的起点 —— 棘轮先于它 1.7 秒,且每一步都由 Alcove 写出。**未确定**:失控能否在**零输入**下进入自持状态 —— 起爆前 26 毫秒确实有且仅有一次 `volumeDown` 硬件键事件。诚实的表述是:手动调节**不是发起者**,但尚不能排除它在"交接时刻"起作用。报告者的印象是完全没有调过音量,日志显示有一次按键,以日志为准;但其感知有数据支持 —— 在任何按键之前,音量确实已自行下降了 1.7 秒。

### The loop outlives the device that triggered it / 循环比触发它的设备活得更久

During the runaway the AirPods disconnected and the system fell back to **MacBook Pro Speakers** — and ControlCenter **kept spinning at 30 Hz on the built-in device** for the remainder of the hour. Once established, the loop is independent of the device whose arrival triggered it. Incident 3 showed the loop was independent of Alcove's participation; this shows it is independent of the audio endpoint too.

失控期间 AirPods 断开、系统退回内置扬声器,而 ControlCenter **在内置设备上继续以 30 Hz 空转**直到被终止。循环一旦建立即与触发它的设备无关。事故 3 证明它不依赖 Alcove 的持续参与,这次证明它也不依赖音频端点。

### Third distinct trigger path / 第三条互不相同的触发路径

| Incident | Device-change path |
|---|---|
| 1 | Spotify Connect transfer to this Mac |
| 3 | unattended Bluetooth reconnect (AirPods returning) |
| **4** | **iPhone → Mac automatic hand-off** (`reverse route`, `configUpdateReasonEndedBottomUpRouteChange`) |

Three unrelated mechanisms, one shape. This is now solid support for stating the trigger as **any output-device change**, rather than anything Spotify- or Bluetooth-specific.

### Recovery differed from incident 3 / 恢复表现与事故 3 不同

`killall ControlCenter` stopped the loop immediately (**0** writes in the following 5 s, ControlCenter back to 0.4% CPU). But unlike incident 3, **the volume did not restore itself** — it stayed at `0` and `muted: true` after the agent respawned, and had to be raised by hand. Worth noting for anyone using the workaround: stopping the runaway and recovering the volume are two separate steps.

`killall ControlCenter` 立即止住循环(其后 5 秒 **0** 次写入),但与事故 3 不同,**音量没有自行恢复** —— agent 重启后仍为 `0` 且静音,需手动调回。使用该规避手段的人需注意:止住失控与恢复音量是两件事。

## Incident 5 — 2026-08-11, beta5 `26A5406e`: device switch alone, pinned at full scale while repeatedly un-muting itself / 事故 5:仅靠设备切换触发,钉在满刻度并反复自行取消静音

**First occurrence on beta5 `26A5406e`** (installed 2026-08-11), and the cleanest trigger yet: **an output-device switch with nothing else running**.

| | |
|---|---|
| Wall time | 13:37:47.284 → 13:38:49 (~62 s, ended by `killall`) |
| Direction | ratchets **up** → pinned `1.000000` |
| Device | `C4-B3-49-AA-E7-97:output` — **AirPods, Bluetooth**; no device migration this time |
| ControlCenter threads writing | **11 distinct** (previous maximum was 7) |
| Rate | **60 writes/s sustained** for the whole runaway — 2,215 writes in the capture window |
| Values written | `volume: 1.000000` ×973 · **`mute: 0.000000` ×1,098** · `mute: 1.000000` ×18 |
| `coreaudiod` | **185.8%** — above the 150–180% band recorded in incident 3 |
| ControlCenter | 24.6% |
| Detection | `volwatch` `DETECT PINNED at 1.0000` ×5, each with the log probe confirming ControlCenter was still writing |

### The trigger was the device switch, and only the device switch / 触发就是设备切换,别无其他

`volwatch`'s `BIND` lines (emitted only when the default output device changes) bracket the onset:

```
13:37:24  BIND  device 155 uid=C4-B3-49-AA-E7-97:output  volume=0.27999997
13:37:38  BIND  device 100 uid=BuiltInSpeakerDevice      volume=0.0
13:37:47  BIND  device 155 uid=C4-B3-49-AA-E7-97:output  volume=0.3225
13:37:50  DETECT PINNED at 1.0000
```

The ratchet's first write lands at **13:37:47.284 — within 0.3 s of the switch back to Bluetooth** — and it is ControlCenter's own, a clean monotonic 1/16 climb:

```
13:37:47.284  ControlCenter  ['vmvc']  0.250000
13:37:47.400  ControlCenter  ['vmvc']  0.312500
13:37:47.767  ControlCenter  ['vmvc']  0.375000
13:37:47.832  ControlCenter  ['vmvc']  0.437500
13:37:47.861  ControlCenter  ['vmvc']  0.500000
13:37:47.894  ControlCenter  ['vmvc']  0.562500   … unbroken to 1.000000, then pinned
```

**What was *not* present, verified in the same log:**

- **No synthetic writer.** `racetrigger`'s last write was **13:31:10** — 6 min 37 s before onset, process long gone.
- **No rapid manual adjustment.** Alcove wrote only 2–13 lines/s in the seconds before onset (a few key presses), not the "hammer the volume keys" of [the recipe](#the-recipe--复现配方).

This retires step 3 of the recipe as a requirement. **A default-output-device change, on its own, is sufficient.** It is also the single most ordinary user action in the whole report — putting headphones on.

事故 5 是 beta5 上首次发作,也是迄今最干净的触发:**只有一次输出设备切换,别无其他**。`volwatch` 的 `BIND` 行(仅在默认设备变化时打)夹住了起爆点 —— 棘轮首条写入落在切回蓝牙后 **0.3 秒内**,且出自 ControlCenter 自己。同一份日志确认:`racetrigger` 早在 6 分 37 秒前就退出了,Alcove 起爆前只有每秒 2–13 条的零星写入(几下按键),**没有复现配方里的"猛敲音量键"**。因此配方第 3 步不再是必要条件 —— **单独一次默认输出设备切换就够**,而这恰是整份报告里最日常的用户动作:戴上耳机。

### New: it repeatedly cancels the user's own mute / 新现象:它反复撤销用户自己的静音

While pinned at `1.000000`, ControlCenter also wrote **`mute: 0.000000` 1,098 times** — actively *un*-muting, ~30 times a second, for the duration.

Incidents 1–4 pinned either at full scale, or at zero *with* mute asserted. This is the first occurrence where the loop holds full scale **and** tears down the one mitigation a user can reach without a terminal. Pressing mute does not stop it; the next write cancels it ~33 ms later. On worn Bluetooth headphones this removes the last non-expert escape from a full-scale output.

钉在满刻度的同时,ControlCenter 还写了 **1,098 次 `mute: 0.000000`** —— 以约 30 Hz 主动**取消**静音。事故 1–4 要么钉在满刻度,要么钉在 0 并置静音;这是第一次出现"满刻度 + 持续撤销静音"。用户按静音压不住,约 33 毫秒后就被下一条写入撤销 —— 在正戴着的蓝牙耳机上,这拆掉了非专业用户最后一条自救路径。

### Recovery / 恢复

`killall ControlCenter` stopped it — ControlCenter writes ceased at 13:38:49 and were **0** over the following 30 s; `coreaudiod` fell **185.8% → 18.2%**. Volume did not restore itself (matching incident 4, not incident 3) and was set back by hand.

### Same-day negatives, recorded so they are not re-run / 当日负结果,记下以免重跑

Three `racetrigger --mode open --duration 60 --threads 8` rounds against built-in speakers on beta5, Alcove running **and writing** (135 / ~910 / 2,340 writes — the middle and upper rounds exceed the 65 writes/min of the run that fired in the [writing A/B](#alcove-must-be-writing-not-merely-running--alcove-必须在写)), with continuous manual volume-key hammering throughout: **no runaway**, ControlCenter 0–16 writes. See [Reproduction on demand](#reproduction-on-demand--按需复现) for why.

One negative control was also run **with Alcove quit**: 3 device switches (confirmed by 3 `BIND` lines, 168 writes to `BuiltInSpeakerDevice`), ControlCenter peaking at 26 writes/s — **no runaway**. This is **weak and must not be cited as confirming Alcove's necessity**: incident 5 fired after the same number of switches (3), so the two runs are indistinguishable on sample size. A positive control — the identical 3-switch sequence with Alcove restarted — was **not** run.

## Scope: not a 27 regression / 并非 27 回归

The closest public prior art is **[Alcove #675](https://github.com/henrikruscon/alcove-releases/issues/675)** — "volume stuck at maximum, Alcove blocks it from going down" — reported on **macOS 26.3.1** with Alcove 1.6.12 on a MacBook Pro M2 Max. Symptom shape matches the up-direction case, so the defect **predates macOS 27**.

Differences that stop this from being a confirmed duplicate:

| | Alcove #675 | This report |
|---|---|---|
| Device | USB-C headphones | built-in speakers **and** Bluetooth |
| Direction | max only | **both** max and min |
| macOS | 26.3.1 | 27.0 `26A5378n` |
| Mechanism | not investigated | ControlCenter-internal RMW race, log-level evidence |

**#675 was closed as `not planned` / `closed:stale`, and the Alcove repository was archived read-only on 2026-06-01** — the app is not open source and that tracker no longer accepts reports. There is no upstream channel left, which is part of why this is filed against Apple.

## Ruled out / 已排除

- **Stuck volume key / HID injection** — 6 s HID capture during an active runaway: 1 key event total. Direction also reverses between incidents, which no key-repeat can do.
- **Virtual audio drivers** — `OrayVirtualAudioDevice` (device 52, SunLogin) was the *default system output* and `ToDeskOutputDriver` was loaded, which looks damning. Device 52 accounted for **2 of 490** writes in incident 1 and none of the runaway. Not involved.
- **Spotify as the volume writer** — zero volume-property writes from Spotify in either window. It supplies the device renegotiation only.
- **MediaRemote / paired-device remote volume** — no relevant traffic in either window.
- **Alcove as the runaway driver** — see above; 0 writes during incident 2.

## Workaround / 临时规避

**`killall ControlCenter`** — ControlCenter is a user-level agent and respawns automatically. Verified on both incidents; volume held at the set value afterwards, and the 30 Hz log loop dropped from ~240 lines / 8 s to **1**.

Incident 2 confirmed this works **with the triggering conditions still live** (Spotify still running, Alcove still running) — the loop does not immediately re-establish.

**Prevention:** quit Alcove, or disable its volume-HUD/volume-control feature. Reporter-verified as preventing recurrence.

If the runaway left the device muted, `killall ControlCenter` alone will not unmute — clear it explicitly:

```sh
osascript -e 'set volume without output muted'
```

## Expected vs Actual / 预期与实际

- **Expected:** concurrent volume-sync requests serialize, each observing the true current value. A third-party app that watches or writes volume cannot drive system output to a rail.
- **Actual:** unsynchronized read-modify-write across ≥7 threads produces a monotonic ratchet to 0 % or 100 %, self-sustains at 30 Hz, and overrides all user input until the agent is restarted.

### On the fix / 关于修法

Rate-limiting the setter would be the **wrong** fix — it slows the ratchet without removing its direction, so output still reaches the rail, just later. The defect is the lost update, not the update frequency.

Serializing volume mutations on a single queue/actor removes the race outright, at no perceptible cost: volume changes occur at human rates (a few per second; 30 Hz in the pathological case), and serialization overhead is microseconds. Additionally, decoupling `VolumeSystemBannerContent` presentation from the volume-apply path would stop an externally-disturbed HUD from re-entering the setter.

限流是错解 —— 只会让棘轮变慢,方向不变,照样触顶/触底。正解是把音量 mutation 串行化(单一队列/actor),竞态直接消失,且开销是微秒级、不可感知。此外应把 banner 呈现与音量写入解耦。

## Reproduction / 复现

**Ten-plus runaways captured on 2026-07-20**, all on `26A5378n`, identified by ControlCenter emitting ≥300 `set system volume` lines/min (idle is single digits):

```
10:39–10:44 · 10:53–10:54 · 14:14–14:16 · 14:25–14:28 · 14:33–14:43
14:56–15:02 · 15:18 · 15:36–15:40 · 15:55–16:00 · 16:07–16:09
```

The last three were provoked by [`racetrigger`](../tools/volwatch/racetrigger.swift) rather than by hand — see [Reproduction on demand](#reproduction-on-demand--按需复现) below.

### The recipe / 复现配方

Reporter's own sequence, which produced most of the later occurrences:

1. Spotify playing on an **iPhone**, output to AirPods
2. In the Spotify desktop app on the Mac, switch playback to **"This Computer"**
3. **Immediately hammer the volume keys** — up and down, repeatedly

Step 3 is not contrived. In the reporter's words: *"因为这种流转操作,音频可能会发生一些变化,可能 macOS 处于 max volume,所以我会下意识一直按音量"* — when you move audio to a device whose current level you cannot know, pressing volume repeatedly is the natural reflex. This is ordinary use, not a stress test.

**Still probabilistic.** Five deliberate attempts with the full sequence (14:03–14:15) produced nothing; later attempts produced runaways within seconds. Expected for a lost-update race, which needs a specific interleaving.

### Alcove is necessary — controlled, and reversible / Alcove 是必要条件

Run twice on 2026-07-20, in both directions:

| | Alcove | External volume writes | Result |
|---|---|---|---|
| Morning | quit | manual (Spotify Connect recipe) | **no runaway** across repeated attempts |
| 15:15–15:16 | **quit** | `racetrigger` at **2,508–2,571 writes/min** | **no runaway** (ControlCenter 33–143 lines/min) |
| 15:17–15:18 | **running** (~65 writes/min) | same tool, same settings | **runaway within a minute** (1,078 lines/min) |

**Write pressure is not the trigger.** A synthetic writer at **38× Alcove's rate** produced nothing; Alcove's sparse writes produced a runaway. Whatever Alcove contributes is qualitative, not volumetric.

### What does NOT reproduce it / 已验证无法触发的路径

Recorded so Apple can skip these, and so this report is not read as "some app writes volume, therefore chaos":

| Attempted | Result |
|---|---|
| Timer-driven concurrent writes, 8 threads, 2,500+/min | no runaway |
| Same writes plus default-output-device flipping | no runaway |
| Echo-from-listener (closed loop), immediate write-back, 8 threads | **ControlCenter became unresponsive** — Control Center and Notification Center both froze until it respawned. A denial of service, not the ratchet. |
| Echo-from-listener with a 40 ms stale-read window, rate-limited to 12/s | no runaway (30 s) |
| Bluetooth handoff (AirPods moving between iPhone and Mac) | **not required** — runaways occurred with AirPods idle, and on built-in speakers |
| ToDesk app running | **not required** — the ToDesk app was quit for later runaways (its root service `ToDesk_Service` was still loaded, so ToDesk is not fully excluded) |
| `racetrigger` + continuous volume-key hammering, 3 rounds on beta5 (2026-08-11) | no runaway — and **ControlCenter never wrote at all** (0 `set system volume` in the heaviest round). Mechanism identified below: [Alcove intercepts the media keys](#why-racetrigger-cannot-reach-the-race-on-this-machine--为什么-racetrigger-在这台机器上够不到那个-race) |

The write signatures are identical where it matters: both Alcove and the synthetic tool issue `AudioObjectSetPropertyData` on `['vmvc', 'outp', 0]` against the same devices. Alcove additionally writes `['mute', 'outp', 0]`. Banner behaviour is also identical — `VolumeSystemBannerContent` events track volume writes at a ratio of ~2.0 with Alcove both running and quit, so Alcove is **not** suppressing the system HUD in a way that matters here.

**Consequence: no self-contained reproducer exists yet.** Concurrent writes to the same property, by themselves, do not provoke it. Something specific to Alcove does, and it is not visible from outside a closed-source, now-archived app.

### Reproduction on demand / 按需复现

```sh
swiftc -O -o racetrigger tools/volwatch/racetrigger.swift
./racetrigger --mode open --duration 60 --threads 8
```

Built-in speakers are enough — no Bluetooth device, no audio playing, no Spotify. **Alcove must be running *and writing*** (next section). The tool clamps every write it makes to `0.10` in code, so a volume that ends at `0` or `1.0` cannot have come from it: that value is ControlCenter's, which is the cleanest confirmation of a real runaway.

Recovery: `killall ControlCenter`, then `osascript -e 'set volume without output muted'`.

### Alcove must be *writing*, not merely running / Alcove 必须在写

Sharpened by five paired observations on 2026-07-20 (16:03–16:09), all with `racetrigger --mode open --duration 45..60 --threads 8` against built-in speakers:

| Run by | racetrigger writes/min | **Alcove writes/min** | ControlCenter | Result |
|---|---|---|---|---|
| investigator (non-interactive shell) | 7,759 | **0** | 0 | — |
| investigator | 9,338 | **0** | 0 | — |
| investigator | 7,498 | **0** | 30 | — |
| **reporter (interactive terminal)** | **1,252** | **65** | **480** | **runaway** |
| reporter, earlier (15:35) | high | 38–45 | 1,718 | **runaway** |

**5/5: Alcove writing → runaway; Alcove silent → nothing.** The investigator's runs pushed **6× more** volume writes and never fired.

Two things this rules out that look plausible:

- **HID input is not the variable.** The investigator's non-firing run had **50** input events in the minute; the reporter's firing run had **14**.
- **Launching Alcove is not enough.** A run where Alcove was started programmatically (`open -a Alcove`, 6 s settle) recorded 0 Alcove writes across 9 trials and 0 runaways — the process existed but never participated. Any trial harness must verify Alcove is *writing* before treating a negative as meaningful.

**Unexplained:** why Alcove writes when `racetrigger` is launched from the reporter's interactive terminal but not when launched from a non-interactive shell, despite identical arguments. Process QoS/scheduling differences between the two launch contexts are a candidate, untested. This is the current edge of the investigation.

### Why `racetrigger` cannot reach the race on this machine / 为什么 `racetrigger` 在这台机器上够不到那个 race

Established 2026-08-11 on beta5, by A/B on Alcove with the same manual action (pressing volume keys) — measured on ControlCenter's **own** `set system volume` line, not the CoreAudio HAL line:

| Alcove | Action | ControlCenter writes |
|---|---|---|
| **running** | continuous volume-key hammering, ~2 min, `racetrigger` also writing 25,422× | **0** |
| **quit** | volume-key presses, ~2 min | **218** HAL writes / **104** `set system volume` |

**Alcove intercepts the media keys.** With it running, the volume keys never reach ControlCenter's `SoundSettings` path; Alcove consumes the event and issues the HAL write itself. (Ruled out at the same time: the alternative that volume keys simply never route through ControlCenter — they clearly do, once Alcove is gone.)

This explains the negative rounds, and retroactively explains an older result. The defect is a lost update **among ControlCenter's own concurrent threads** — so ControlCenter has to be performing a read-modify-write for there to be an update to lose. `racetrigger` writes at the **HAL layer**: it changes the property, but never induces ControlCenter to run that path. With Alcove also eating the key presses, the three beta5 rounds contained **no ControlCenter RMW at all** — the tool was contending with nothing. That is a better account of "[write pressure is not the trigger](#alcove-is-necessary--controlled-and-reversible--alcove-是必要条件)" (38× the rate, no runaway) than volume-vs-quality: the synthetic writes were never landing in the racing code path.

**Consequence for the recipe:** step 3 ("immediately hammer the volume keys") **contributes nothing on this machine while Alcove is running**. It was in the recipe because it is what the reporter actually did, not because it was isolated. A default-output-device change is a path Alcove cannot intercept — ControlCenter must re-read and re-apply that device's volume and mute state — which is consistent with all three of incidents 3, 4 and 5 starting at a device change.

**This deepens the [open question](#open-question--未解) rather than settling it.** If Alcove *reduces* ControlCenter's participation in the volume path, the established "Alcove is necessary" A/B (5/5 and 6/6) becomes harder, not easier, to explain — one would expect quitting Alcove to make ControlCenter do *more* RMW and race *more*. The narrowest hypothesis that fits every observation so far is that **two things must coincide: ControlCenter performing its own RMW (forced by a device change) *and* a second HAL writer contending with it (Alcove)** — but this is **untested**, and it does not explain the [beta4 confirmation](#beta4-confirmation--beta4-复现确认), where a runaway followed `racetrigger` plus a few key taps with Alcove running. Both stand; neither is discarded.

2026-08-11 在 beta5 上用 Alcove 开/关做 A/B(同一个动作:按音量键,统计 ControlCenter **自己**的 `set system volume` 行)测得:**Alcove 会拦截媒体键** —— 它在时,音量键根本到不了 ControlCenter,由 Alcove 自己发 HAL 写入。这解释了 beta5 三轮为何全阴:该缺陷是 ControlCenter **自身并发线程间**的 lost update,得它自己在做读-改-写才有更新可丢;而 `racetrigger` 只在 HAL 层写属性,从不诱发 ControlCenter 走那条路径,再加上 Alcove 吃掉了按键,三轮里 **ControlCenter 一次 RMW 都没做**,工具是在跟空气抢。这也给"写入压力不是触发条件"提供了比"质而非量"更好的解释:合成写入压根没落到出错的代码路径上。**配方第 3 步在 Alcove 运行时不起作用**;而默认输出设备切换是 Alcove 拦不住的路径 —— 与事故 3、4、5 全部起于设备切换一致。**但这加深而非解决了[未解问题](#open-question--未解)**:若 Alcove 反而减少了 ControlCenter 的参与,原本"Alcove 是必要条件"的 A/B 就更难解释了。目前唯一能兼容全部观测的最窄假设是"**需要两件事同时发生:ControlCenter 自己在做 RMW(由设备切换强制)+ 有第二个 HAL 写手与之竞争(Alcove)**",但该假设**未经验证**,且解释不了 beta4 那次复现。两者并列保留。

### Tools / 工具

[`tools/volwatch/`](../tools/volwatch/) — LaunchAgent that records occurrences passively. Detection rule and the three rejected alternatives are documented in the source header; it has caught every runaway since the pinned-phase probe was added. [`racetrigger.swift`](../tools/volwatch/racetrigger.swift) in the same directory implements the negative results above and is kept so they stay reproducible.

### beta4 confirmation / beta4 复现确认

**Still present, unfixed, on `26A5388g` (2026-07-22).** Reproduced with the same [on-demand recipe](#reproduction-on-demand--按需复现) — `racetrigger --mode open --duration 60 --threads 8` against built-in speakers, Alcove running, a handful of manual volume-key taps to get Alcove writing — while `volwatch` ran in the foreground in observe mode.

```
15:03:15.611  set system volume: 0.500000 -> 0.562500      ← clean 1/16 climb starts
15:03:15.863  set system volume: 0.125000 -> 0.187500
  ...
15:03:16.528  set system volume: 0.937500 -> 1.000000       ← rail reached, 0.9 s after onset
15:03:16.556  set system volume: 1.000000 -> 1.000000        ← spin begins
  ...                                                          (unbroken 30 Hz spin, single TID 0x1b02)
15:03:37.224  set system volume: 1.000000 -> 1.000000        ← last line before the process died
15:03:37.275  launchd: [gui/501/com.apple.controlcenter [738]:] exited due to SIGTERM | sent by killall[2771]
15:03:37.292  launchd: Successfully spawned ControlCenter[2772] because semaphore
```

**~21 s continuous unbroken spin** at the rail (`738` never stopped emitting `1.000000 -> 1.000000` from 16.556 to 37.224) before the reporter ran `killall ControlCenter` by hand to recover — the same workaround documented above, applied live. Corroborated at the CoreAudio layer during the same window: `LogVolumeChangeForClientSide from AudioObjectSetPropertyData` on `['vmvc','outp',0]` and `['mute','outp',0]` against `BuiltInSpeakerDevice`, matching incident 2's signature from the original beta3 capture.

This was deliberately cross-checked against `volwatch`'s own detector output before being trusted — the tool's `DETECT` line alone is not sufficient evidence (a human tapping keys can produce a similar rate/idle signature, see [README](../tools/volwatch/README.md#why-the-detection-rule-is-what-it-is)) — by pulling `/usr/bin/log show --info --debug` for `ControlCenter` (PID `738`) independently and confirming the monotonic 1/16 climb, the sustained rail spin, and that the final value (`1.000000`) is not reachable from `racetrigger`'s own writes, which are hard-clamped to `0.10` in code.

A second, weaker signal followed: after the `killall`-triggered respawn (new PID `2772`), `volwatch` detected a down-direction burst (rate 15.6/s, settling at `0.5000`) about 3 s later. No corresponding `set system volume` log lines were found from PID `2772` in that window — plausibly the freshly-spawned process's `SoundSettings` still initializing, plausibly something else. **Not treated as confirmed** — the up-direction episode above stands on its own regardless.

**Reporter's residual state after the session: output volume pinned at `0` and `output muted:true`**, cleared manually with `set volume without output muted` — consistent with the "recovery required" note in [Workaround](#workaround--临时规避).

beta4(`26A5388g`,2026-07-22)复现确认:同一套按需复现配方触发,单线程(`0x1b02`)以 30Hz 连续空转 **约 21 秒**才被手动 `killall ControlCenter` 打断,CoreAudio 层日志佐证。复现前先用 `log show` 独立核实了日志,不是单凭 `volwatch` 的 DETECT 行下的结论(那条信号单独看可能是人在按键的假阳性)。

### beta5 confirmation / beta5 复现确认

**Still present, unfixed, on `26A5406e` (2026-08-11)** — see [incident 5](#incident-5--2026-08-11-beta5-26a5406e-device-switch-alone-pinned-at-full-scale-while-repeatedly-un-muting-itself--事故-5仅靠设备切换触发钉在满刻度并反复自行取消静音) for the full capture. Two things changed about *how* it was reproduced:

- The on-demand recipe (`racetrigger`) **failed three times** and is now understood not to reach the racing code path — see [above](#why-racetrigger-cannot-reach-the-race-on-this-machine--为什么-racetrigger-在这台机器上够不到那个-race).
- A plain **output-device switch reproduced it on the first attempt**, with no tooling at all.

Apple's beta5 release notes do not mention this defect; nothing in the ledger's [beta5 diff](../README.md#new-build-26a5406e-beta5--新-buildbeta52026-08-11-装) covers it either.

beta5(`26A5406e`,2026-08-11)确认仍存在。复现方式有两处变化:按需复现工具 `racetrigger` **三轮全部失败**(原因见上节:它够不到出错的代码路径);而**单纯切换输出设备一次就复现**,未借助任何工具。

## Open question / 未解

**What does Alcove do that a synthetic writer does not?**

Alcove is necessary (A/B, both directions, twice) but the mechanism is unidentified. **Harder as of 2026-08-11:** Alcove is now known to *intercept the media keys*, i.e. to make ControlCenter do **less** volume work, not more — so "quitting it prevents the runaway" runs against the naive expectation. See [Why `racetrigger` cannot reach the race](#why-racetrigger-cannot-reach-the-race-on-this-machine--为什么-racetrigger-在这台机器上够不到那个-race) for the measurement and the narrowest hypothesis that still fits (untested). Everything observable from outside matches between Alcove and a synthetic writer that fails to trigger it: same API (`AudioObjectSetPropertyData`), same property (`['vmvc', 'outp', 0]`), same devices, same banner-to-write ratio. Alcove also writes `['mute', 'outp', 0]`; mirroring that did not close the gap.

Hypotheses tested and **rejected** during this investigation, listed so they are not re-run:

1. Virtual audio drivers (Oray/ToDesk) are the writers — 2 of 490 writes; not involved.
2. Alcove issues the runaway commands — 0 writes during incident 2's entire runaway.
3. Alcove's off-grid values (`0.435`, `0.490`) are its fingerprint — 1,194 of its 1,324 daily writes are clean 1/16 multiples.
4. ToDesk is required — later runaways occurred with the app quit.
5. The Bluetooth handoff is required — runaways occurred on built-in speakers with AirPods idle.
6. Enough concurrent write pressure suffices — 38× Alcove's rate produced nothing. *(2026-08-11: now has a mechanism — the synthetic writer works at the HAL layer and never induces ControlCenter's own RMW, so it contends with nothing. See [Why `racetrigger` cannot reach the race](#why-racetrigger-cannot-reach-the-race-on-this-machine--为什么-racetrigger-在这台机器上够不到那个-race).)*
7. The stale-read window is the missing ingredient — a 40 ms read-then-write-back loop produced nothing.
8. Alcove suppresses the volume HUD and breaks the banner lifecycle — banner-to-write ratio is ~2.0 with Alcove running *and* quit.

Resolving this needs ControlCenter's internals (Apple) or Alcove's (closed source, [repo archived read-only 2026-06-01](https://github.com/henrikruscon/alcove-releases)). It is out of reach from the outside.

## Notes / 备注

- **The HUD desyncs from the actual volume.** During one runaway the menu-bar slider rendered at **maximum** while the device was actually at `0.0` and muted — `VolumeSystemBannerContent` was being presented **58×/sec** and never dismissing. The visible control and the real state disagree, so a user cannot tell what the volume is.
- **Klack 2.1.4 (`com.henrikruscon.Klack`, same developer as Alcove) crashed during a runaway** — `EXC_BAD_ACCESS (SIGSEGV)` at `0x0000…00fc` on queue `com.henrikruscon.Klack.SoundManager.control`, at 14:14:18, **2.4 s after** that runaway began, having created ~10 `AudioConverter`s in the preceding 0.5 s. Klack never writes system volume (0 writes all day), so it is **collateral damage** of the device churn, not a participant. One crash only — not tracked separately yet.
- **Reproduction rigor:** the morning's "quitting Alcove prevents it" result was reporter-observed and uncounted. It was later replaced by the controlled A/B above, which is the citable evidence.
- **This loop drives MenuBarAgent too — and that is not a usable signature.** Each iteration presents a volume banner, so `MenuBarAgent` runs at **13,334–18,839 log lines/min** during a runaway versus **33–38** after `killall ControlCenter` (**~500×**), 100% of it `com.apple.menubar:systemBanners`. A machine hitting this shows **both** ControlCenter *and* MenuBarAgent at high CPU.
- **Ruled out: the external report in [#20](https://github.com/jizhi0v0/macos27-beta-issues/issues/20) is *not* this bug.** That report (MenuBarAgent ~60% + ControlCenter ~45% CPU on beta3) matched the CPU shape above, so it was worth checking. [@progzone122 confirmed](https://github.com/jizhi0v0/macos27-beta-issues/issues/21#issuecomment-5018601375) their **volume control works normally** and they run **no Alcove or comparable menu-bar app** — only Tailscale and Nextcloud icons. Two takeaways: (a) a **weak** data point consistent with Alcove being required (no Alcove, no runaway — one sample, not evidence to lean on); (b) **ControlCenter can reach ~45% CPU without this loop**, so high ControlCenter CPU alone is not a signature — the volume symptom is.
- **Not related to [#12](apple-menubaragent-idle-cpu.md)** (MenuBarAgent idle CPU), despite the shared process. #12's beta3 retest measured MenuBarAgent at **0.28%** (43.5 s / 2 h 35 m) *with Alcove installed and running* (present on this machine since 2025-12-28, bundle updated 2026-07-01) — so Alcove cannot be #12's "unidentified sender". And #12 was **sustained 10–14% at idle over hours**, which this loop cannot be: volume would have been pinned at a rail the whole time. **Caveat worth keeping:** #12's hunt for that sender grepped `StatusItem` / `NSStatusBar` / `drawWithFrame` / `_updateReplicants` — **never `systemBanners`**. That open question stays open; if #12 recurs, grep the banner subsystem first.
- **No public report of the ControlCenter-side race was found** — searches for the multi-threaded RMW / arbitrary-direction / cross-device signature turned up nothing. This is absence of evidence from a handful of queries, **not** a first-discovery claim.
- Same defect *shape* as [#18](apple-contactsd-carddav-group-changehistory-loop.md) and [#19](apple-imagent-contactsaccounts-sandbox-retry-loop.md): a self-sustaining in-process loop with no third-party participant once running. Unlike those, this one has a user-visible and safety-relevant effect rather than log volume.
- `log` is a **zsh builtin**: use `/usr/bin/log` for every command here, or they silently return nothing.
- Device IDs are per-boot and get reused — resolve them via `AudioObjectGetPropertyData(kAudioHardwarePropertyDevices)` rather than assuming stability across reboots. The Bluetooth device is identified by its MAC-style UID, which is stable.

## Reproduction 2026-08-19 — beta6 `26A5416b` — signature unchanged

Caught live and captured before clearing it. Raw 25-minute log window archived outside the repo
at `~/Developer/macos27-beta6-postboot/issue21/` (24 MB gz).

### Machine state at capture

```
coreaudiod                              145.2 %
Core Audio Driver (ToDeskOutputDriver)   49.8 %
WindowServer                             45.8 %
ControlCenter                            27.3 %
MenuBarAgent                             20.4 %
load average 52.08          Alcove 1.7.9 running
```

The machine was visibly stuck — this is the first time the runaway has been recorded alongside a
user-perceived hang rather than only as a volume symptom.

### The ratchet, from `SoundSettings … Setting main volume to`

```
16:11:57.651  0.6250
16:11:57.662  0.6875   +1/16
16:11:57.915  0.7500   +1/16
16:11:57.948  0.8125   +1/16
16:11:58.015  0.7500   -1/16   <- the two writers overwriting each other
16:11:58.115  1.0000   railed
16:11:58.182  0.9375   -1/16
16:11:58.215  1.0000   +1/16   <- oscillating against the rail
...
16:12:00.482  0.4375           then walking back down
```

Every transition is an exact multiple of **1/16 (0.0625)**, matching the documented step size.

### Rate

| | |
|---|---|
| `setLevel` interval | 33.3 ms — **30 Hz**, exactly as recorded on beta4/beta5 |
| `set system volume` | 3,395 lines / 6 min, **30/s sustained** at peak |
| `Setting main volume` | 4,265 lines in the 25-minute capture |

### The detail that satisfies the discriminator

The known trap with this issue is that a railed 0.0 or 1.0 reading proves nothing, because Alcove
and the synthetic race-trigger both write those values. What distinguishes the defect is that the
loop **keeps writing** after railing: sampled at 0.5 s intervals for 7 s the volume read 100 the
whole time, while the log shows `setLevel: 1.000000` being issued **30 times a second throughout**.
A single writer setting the volume to maximum does not do that.

### Workaround confirmed

`killall ControlCenter` clears it; quitting Alcove prevents it. Both unchanged from beta5.

2026-08-19 在 beta6 上完整复现,签名不变:`setLevel` 间隔精确 **33.3ms = 30Hz**,步长精确 **1/16**,双向,
撞顶后**仍以 30Hz 持续写 1.0**。Alcove 1.7.9 运行中(触发条件)。本次机器出现可感知的卡顿(`coreaudiod` 145%),
这是该问题第一次与用户可感的卡死一同记录,而非仅表现为音量异常。25 分钟原始日志已归档(仓库外)。

### 2026-08-19 — the virtual-audio HAL driver lead is DEAD, and the trigger is Bluetooth

**Control run settled it.** The drivers were restored and `coreaudiod` restarted, and it *still*
did not reproduce. So neither removing the drivers nor restarting coreaudiod was the cure — the
**trigger condition itself had stopped occurring**. The section below is kept for the record with
that correction; its "control pending" is now resolved, negatively.

**What the trigger appears to be.** Not "AirPods failed to reconnect" — that was tested and
**does not hold**: the reporter reproduced the failed hand-back from Spotify, AirPods did not
appear, and **no storm followed**. The refined version fits that negative result. Per minute
across the capture:

| minute | HAL property-read failures | `BTAudioHALPlugin` (A2DP) | `Setting main volume` |
|---|---|---|---|
| 16:07–16:09 | 0 | 0 | 0 |
| **16:10** | **256** | **852** | 0 |
| **16:11** | **381** | **2,139** | 65 |
| 16:12 | 24 | 9 | **1,800** |
| 16:13 | 0 | 147 | **1,799** |

The failures are

```
16:10:22.503  HALS_UCPlugIn.cpp:1177  HALS_UCPlugIn::ObjectGetPropertyData: failed:
              [<private>/<private>/0], Error: 2003329396
```

and `2003329396` = `0x77686174` = **`'what'` = `kAudioHardwareUnspecifiedError`**.

So the sequence is: **a Bluetooth audio (A2DP) negotiation happens; during it, HAL property reads
fail with `kAudioHardwareUnspecifiedError`; volume writes start; then the Bluetooth activity and
the failures both collapse while the volume storm runs on at full rate.** A read-modify-write
whose *read* fails is exactly the fuel this race needs — a writer acting on a failed or stale read
will write back a wrong value, and two such writers ratchet.

That also explains the reporter's negative test cleanly: **AirPods that never appear at all
produce no A2DP negotiation, hence no failing reads, hence no trigger.** The dangerous state is a
device *negotiating*, not a device *absent*.

Seven seconds before the first volume write, Alcove is enumerating paired Bluetooth devices:

```
16:11:50.202  CBMsgIdRetrievePairedPeersWithOptions       com.henrikruscon.Alcove-classic
16:11:50.203  CBMsgIdPairingAgentRetrievePairedDevices    com.henrikruscon.Alcove-central
16:11:50.203  CBMsgIdRetrieveAddressForPeripheral  ×4     com.henrikruscon.Alcove-central
```

`bluetoothd` emitted **35,944 lines** across the 25-minute window (~24/s), and `corespeechd`'s
`CSDefaultAudioRouteChangeMonitorMac` fires repeatedly through it.

**The shape is trigger-then-self-sustaining.** The Bluetooth burst *leads* the storm by 1–2
minutes and has decayed to almost nothing (4 calls) by the time the storm is at full 30 Hz. So
the race does **not** need its trigger to keep running — which is why every previous capture found
a runaway with no obvious cause in the same window, and why `killall ControlCenter` clears it.

This is consistent with the trigger description already in this file ("generalises to any
output-device change") and narrows it: **a Bluetooth audio device that fails to reconnect makes
Alcove poll, which produces the device churn that starts the race.**

**A clean negative, same day: the refined trigger is NOT sufficient.** The reporter manually
connected the AirPods and they disconnected again on their own — a flapping device, which is the
state this hypothesis calls dangerous. Every known precondition was present: Alcove running and
polling (89 bluetoothd XPC calls), Spotify running, all three HAL drivers restored, volume at a
normal 44. Per minute:

| minute | `BTAudioHALPlugin` | HAL read failures | `Setting main volume` |
|---|---|---|---|
| 16:47–16:48 | 3 | 30 | 0 |
| **16:50** | **446** | **197** | **0** |
| **16:51** | **529** | **208** | **0** |
| **16:52** | **677** | **316** | **0** |

A2DP negotiation happened, HAL reads failed hundreds of times, and **no storm followed**.

Media keys were checked as the missing ingredient and ruled out — **zero** media/volume key events
in *either* window. The other differences (Alcove volume lines 1,860 vs 225, ControlCenter 77,622
vs 4,580, `SoundSettings` 46,594 vs 1,104) are all **products of the storm**, not precursors.

**So the trigger is still unidentified.** The score for the day is one positive episode and two
negatives, and the A2DP-plus-failing-reads pattern is at best necessary, not sufficient. What
would settle it is not another hypothesis but a **continuous watcher** recording the precursor
metrics — `BTAudioHALPlugin` rate, `ObjectGetPropertyData` failures, Alcove→bluetoothd XPC rate,
`Setting main volume` rate, per minute — so that several episodes can be compared instead of one.
Every capture so far has been retrospective, which is why the precursor keeps being ambiguous.

**Not established:** that the failing reads *cause* the writes**Separately worth filing:** the reporter's own observation that **AirPods stopped auto-reconnecting
when Spotify hands audio back to the Mac after the beta6 upgrade** is a candidate defect in its own
right, independent of this race.

2026-08-19:**虚拟音频驱动这条线索已排除** —— 驱动放回并重启 coreaudiod 后仍不复现,说明治好它的既不是
移除驱动也不是重启,而是**触发条件本身没有再发生**。按分钟对齐后发现:Alcove 对 bluetoothd 的枚举爆发
**领先音量风暴 1–2 分钟**,随后衰减到几乎为零而风暴升至满速 30Hz 并自持。形态是「触发→自持」:竞争一旦
启动就不再需要触发源。这解释了以往每次抓到失控都找不到当时的诱因。报告者观察:升级 beta6 后,Spotify
把音频交还 Mac 时 AirPods 不再自动重连 —— 与 Alcove 反复轮询配对设备吻合。**未证实**:设备确为 AirPods、
枚举是因而非果、以及 beta6 具体改了什么。n=1。

### Preliminary (superseded by the control run above), 2026-08-19 — removing the virtual-audio HAL drivers stopped it (confounded)

All three third-party HAL plugins were moved out of `/Library/Audio/Plug-Ins/HAL/`
(`ToDeskOutputDriver`, `OrayVirtualAudioDevice`, `ParrotAudioPlugin`) and `coreaudiod` was
restarted. The audio device list went from 4 devices to 3, and `BuiltInSpeakerDevice` — the sole
target of all 4,265 writes in the capture above — changed id from 100 to 74.

Result: **4–5 deliberate trigger attempts produced nothing**, and a clean 249 s window after the
`coreaudiod` restart contains **zero** `Setting main volume` lines, with the volume sitting at a
normal 25 rather than railed. Against a defect previously described as *reproducible on demand*,
with 10+ runaways captured in a single day, that is a large change.

**It is not yet a finding, because two variables moved together.** `killall coreaudiod` was
required to unload the drivers, and restarting coreaudiod on its own clears whatever state the
race is holding. Nothing here separates "the drivers participate in the trigger" from "the
restart cured it".

**The control that separates them:** move the drivers back, restart `coreaudiod` again, and
attempt the trigger the same way.

- **Triggers again** → the restart is ruled out (it happened here too and did not prevent it), so
  the drivers participate in the *trigger*, not merely in the cost. That would rewrite this
  issue's trigger description, which currently names only Alcove and an output-device change.
- **Still does not trigger** → the cure was the `coreaudiod` restart, this lead is dead, and the
  workaround section gains a more thorough remedy than `killall ControlCenter`.

Also worth recording either way: `coreaudiod`'s lifetime average was **14.7 %** (36.64 s over
249 s) with the drivers absent, which includes its startup cost. If it jumps once they are
restored, that is independent evidence of plugin fan-out cost regardless of what the trigger
test shows.

2026-08-19 初步结果:移除三个第三方 HAL 虚拟音频驱动并重启 coreaudiod 后,4–5 次刻意触发均未复现,
249 秒干净窗口内 `Setting main volume` 写入为 **0**,音量停在正常值 25。对一个原本"可按需复现、
一天抓到 10+ 次"的缺陷,这个变化很大。**但两个变量是一起动的** —— 卸载驱动必须重启 coreaudiod,
而重启本身就会清掉竞争持有的状态。需要把驱动放回、再次重启 coreaudiod 后重试,才能区分
"驱动参与触发"与"重启治好了它"。
