# ControlCenter volume runaway — concurrent read-modify-write ratchets system volume to 0 or 100% and spins at 30 Hz
# ControlCenter 音量失控 —— 并发 read-modify-write 把系统音量棘轮到 0 或 100%,并以 30 Hz 空转

> 🔗 **Track / 关注此问题:** [#21 — watch & discuss on GitHub](https://github.com/jizhi0v0/macos27-beta-issues/issues/21)

| | |
|---|---|
| **Status** | 🟡 Mitigated · confirmed on `26A5378n` (caught live twice, both directions) |
| **macOS** | 27.0 beta3 revision **`26A5378n`** — **not 27-specific**, see [Scope](#scope-not-a-27-regression--并非-27-回归) |
| **Component** | Apple **ControlCenter** (`com.apple.controlcenter`, `SoundSettings`) + CoreAudio HAL volume properties |
| **Trigger (necessary, not causal)** | **Alcove 1.7.9** (build 203, `com.henrikruscon.Alcove`) running; kicked off by a Spotify Connect transfer to this Mac **followed within ~190 ms by a manual volume adjustment** |
| **Hardware** | MacBook Pro `Mac15,11`, M3 Max, 36 GB |
| **Report** | Apple Feedback: **[FB23868196](https://feedbackassistant.apple.com/feedback/23868196)** (filed 2026-07-20 via Feedback Assistant — Control Center → "Incorrect/Unexpected Behavior"; sysdiagnose + ratchet log + concurrent-TID log + HID-absence log + before/after rate table attached) |

## Summary / 摘要

System volume becomes uncontrollable: it ratchets monotonically to **either** 0 % (+ mute) **or** 100 % and stays pinned there, while ControlCenter writes the CoreAudio volume property at **~30 Hz indefinitely**. User volume adjustments are immediately overridden — the ratchet just restarts from the new value.

The **direction** (up or down) varies between occurrences, and the **device** varies *within* a single occurrence — incident 1 thrashed between the AirPods and the built-in speakers six times, including across an AirPods reconnect that reassigned the device ID. Every write during the runaway comes from **ControlCenter's own threads** — the third-party app that is a necessary precondition issues **zero** volume writes while the loop runs.

**Hearing-safety relevance — not theoretical.** The affected output in incident 1 was a pair of **AirPods 4 being worn at the time**; ControlCenter issued **1,158 writes setting that device to `1.000000`** — full scale, in-ear. The ratchet advances one 1/16 step per ~33 ms, so the climb takes **≈0.5 s with no ramp**. Recovery required killing the agent from a terminal, which is not available to a normal user while the sound is painful.

系统音量失控:单向棘轮到 0%(并静音)或 100% 并卡死,ControlCenter 以约 30 Hz 无限写入音量属性。手动调节会被立即覆盖 —— 棘轮只是从新值重新开始。方向(上/下)在两次事故间不同,**设备则在单次事故内来回跳** —— 事故1 在 AirPods 和内置扬声器之间横跳 6 次,期间 AirPods 还断开重连换了设备 ID。失控期间的每一条写入都来自 ControlCenter 自己的线程。

**听力安全:事故1 中被顶到满音量的是正戴着的 AirPods 4**,ControlCenter 向该设备写入 `1.000000` 共 **1,158 次**。

## Symptom / 症状

Two occurrences caught live, 15 minutes apart, on one boot:

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

## Open question / 未解

**How does Alcove's presence push ControlCenter into the racing state, given it issues no writes during the loop?**

Unproven hypothesis: every loop iteration carries `Did activate assertion for VolumeSystemBannerContent` / `Did present banner of type VolumeSystemBannerContent`. Alcove's core function is to replace/suppress the system volume HUD, and it has a documented history of failing to do so cleanly ([#562](https://github.com/henrikruscon/alcove-releases/issues/562), [#517](https://github.com/henrikruscon/alcove-releases/issues/517)). If ControlCenter's volume-apply path is coupled to the banner's presentation lifecycle, an externally disturbed banner callback could re-enter the setter and multiply the in-flight sync tasks.

**This is a hypothesis, not a finding.** Testing it needs either ControlCenter internals or a minimal reproducer that suppresses the volume HUD without Alcove.

## Notes / 备注

- **Reproduction rigor:** the "quitting Alcove prevents it" result is reporter-observed across an unrecorded number of Spotify Connect transfers, not a counted trial series. Treat as strong but not quantified.
- **This loop drives MenuBarAgent too — and that is not a usable signature.** Each iteration presents a volume banner, so `MenuBarAgent` runs at **13,334–18,839 log lines/min** during a runaway versus **33–38** after `killall ControlCenter` (**~500×**), 100% of it `com.apple.menubar:systemBanners`. A machine hitting this shows **both** ControlCenter *and* MenuBarAgent at high CPU.
- **Ruled out: the external report in [#20](https://github.com/jizhi0v0/macos27-beta-issues/issues/20) is *not* this bug.** That report (MenuBarAgent ~60% + ControlCenter ~45% CPU on beta3) matched the CPU shape above, so it was worth checking. [@progzone122 confirmed](https://github.com/jizhi0v0/macos27-beta-issues/issues/21#issuecomment-5018601375) their **volume control works normally** and they run **no Alcove or comparable menu-bar app** — only Tailscale and Nextcloud icons. Two takeaways: (a) a **weak** data point consistent with Alcove being required (no Alcove, no runaway — one sample, not evidence to lean on); (b) **ControlCenter can reach ~45% CPU without this loop**, so high ControlCenter CPU alone is not a signature — the volume symptom is.
- **Not related to [#12](apple-menubaragent-idle-cpu.md)** (MenuBarAgent idle CPU), despite the shared process. #12's beta3 retest measured MenuBarAgent at **0.28%** (43.5 s / 2 h 35 m) *with Alcove installed and running* (present on this machine since 2025-12-28, bundle updated 2026-07-01) — so Alcove cannot be #12's "unidentified sender". And #12 was **sustained 10–14% at idle over hours**, which this loop cannot be: volume would have been pinned at a rail the whole time. **Caveat worth keeping:** #12's hunt for that sender grepped `StatusItem` / `NSStatusBar` / `drawWithFrame` / `_updateReplicants` — **never `systemBanners`**. That open question stays open; if #12 recurs, grep the banner subsystem first.
- **No public report of the ControlCenter-side race was found** — searches for the multi-threaded RMW / arbitrary-direction / cross-device signature turned up nothing. This is absence of evidence from a handful of queries, **not** a first-discovery claim.
- Same defect *shape* as [#18](apple-contactsd-carddav-group-changehistory-loop.md) and [#19](apple-imagent-contactsaccounts-sandbox-retry-loop.md): a self-sustaining in-process loop with no third-party participant once running. Unlike those, this one has a user-visible and safety-relevant effect rather than log volume.
- `log` is a **zsh builtin**: use `/usr/bin/log` for every command here, or they silently return nothing.
- Device IDs are per-boot and get reused — resolve them via `AudioObjectGetPropertyData(kAudioHardwarePropertyDevices)` rather than assuming stability across reboots. The Bluetooth device is identified by its MAC-style UID, which is stable.
