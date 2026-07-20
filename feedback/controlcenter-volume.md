VERIFICATION: CONFIRMED — caught live twice on one boot, 2026-07-20, macOS 27.0 beta3 revision 26A5378n. Incident 1 (10:39:26.849): system volume ratchets **up** in exact 1/16 steps to `1.000000` and spins at 30 Hz (1,800 `set system volume` lines/min) for ~4.5 min until `killall ControlCenter` — **thrashing across three device IDs** (`198`→`100`→`198`→`100`→`212`→`100`; 198/212 are the same **AirPods 4** before and after a mid-runaway reconnect, 100 is `BuiltInSpeakerDevice`). **1,158 of those writes set the worn AirPods to `1.000000`.** Incident 2 (~10:52): same signature ratcheting **down** to `0.000000` + `muted=true` on the same AirPods, 493 client-side writes in 8 s across **7 distinct ControlCenter threads**. Every write during both runaways originates from ControlCenter itself. HID capture during an active runaway: **1 key event in 6 s** — there is no input driving this. After `killall ControlCenter` the 30 Hz loop drops from ~240 lines / 8 s to **1**.

**Not a macOS 27 regression** — the up-direction symptom is publicly reported on macOS 26.3.1 (see Note).

# Title
*(Feedback Assistant's title field is short — use this, 86 chars, plain ASCII hyphen so nothing mangles on paste:)*

```
ControlCenter: concurrent read-modify-write ratchets system volume to 0 or 100 percent
```

Fallback if that still won't fit (72 chars):

```
ControlCenter volume race: output ratchets to 0 or full scale and sticks
```

The full framing — *"…unsynchronized RMW across >=7 threads, direction arbitrary across occurrences and device arbitrary within one, self-sustains at 30 Hz, overrides all user input until the agent is restarted"* — goes in the Description field below, which has room.

# Form fields
- **Which area are you seeing an issue with?** → **Control Center** if the picker offers it; otherwise **Sound** / **Audio**. Rationale: the defect is in `com.apple.controlcenter`'s `SoundSettings` volume-apply path, not in CoreAudio — coreaudiod faithfully applies every write it is handed. Say so in the Description either way; the report names the component explicitly.
- **What type of issue are you reporting?** → **Incorrect/Unexpected Behavior.**

  There is no "safety" category, so state it in the Description instead: **the affected output was a worn pair of AirPods 4, driven to `1.000000` by 1,158 writes, reaching full scale in roughly half a second with no ramp.** That framing belongs in the text, not smuggled into the wrong picker.

# Description
On macOS 27.0 (26A5378n), system volume becomes uncontrollable: it ratchets monotonically to **either 0 % (plus mute) or 100 %**, pins there, and ControlCenter continues writing the CoreAudio volume property at **~30 Hz indefinitely**. Manual adjustment is overridden within a second — the ratchet simply restarts from whatever value the user set.

The **direction** varies between occurrences and the **target device** varies *within* an occurrence. This is the signature of a **lost-update race**, not of a stuck input.

## 1. The ratchet

The step is exactly **1/16** — the standard macOS volume increment — advancing about one step per 33 ms:

```
10:39:26.849  set system volume: 0.435000 -> 0.500000
10:39:27.116  set system volume: 0.500000 -> 0.562500
10:39:27.149  set system volume: 0.562500 -> 0.625000
10:39:27.182  set system volume: 0.625000 -> 0.687500
10:39:27.215  set system volume: 0.687500 -> 0.750000
10:39:27.249  set system volume: 0.750000 -> 0.812500
10:39:27.285  set system volume: 0.490000 -> 0.500000   <-- read side is non-1/16; ratchet restarts from 0.5
10:39:27.315  set system volume: 0.500000 -> 0.562500
```

At ~33 ms per 1/16 step, a full-scale climb completes in **roughly 0.5 s**.

Once a rail is reached it spins forever without changing anything:

```
232 x   set system volume: 1.000000 -> 1.000000
```

Each iteration is closed inside ControlCenter: `syncMute` -> `updateMute` -> `setLevel` -> `set system volume` -> `Did present banner of type VolumeSystemBannerContent`. ControlCenter's own write raises a property-changed notification, which schedules another sync, which races again.

## 2. Why this is a race and not an input problem

1. **Direction is arbitrary.** Incident 1 ratcheted up to `1.000000`; incident 2 down to `0.000000` + `muted=true`. No key repeat or stuck HID line can reverse direction.
2. **A single runaway thrashes across devices.** Incident 1 alternated AirPods ↔ `BuiltInSpeakerDevice` six times and followed the AirPods across a disconnect/reconnect (`198`→`212`). Incident 2 stayed on the AirPods with **0 writes to device 100**.
3. **Multiple threads write concurrently.** Incident 2: seven ControlCenter TIDs (`54625`, `5498c`, `5467e`, `5386f`, `5498a`, `5499c`, `5498e`) all issue `AudioObjectSetPropertyData`. The bookkeeping line `set system volume: X -> Y` comes from a *different* TID (`1b1b`) than the threads performing the CoreAudio writes.
4. **Non-1/16 values appear on the *read* side.** `0.435000`/`0.490000` — the write side only emits multiples of 1/16. **Weaker than it looks:** `0.435` could be the AirPods' own pre-existing level. Consistent with a race, not proof of one.
5. **There is no input.** A 6 s HID capture during an active runaway returned **one** key event total: no `NX_KEYTYPE_SOUND_UP` stream, no injected events.

## 3. The third-party precondition — and what it is *not*

A third-party menu-bar app (**Alcove 1.7.9**, `com.henrikruscon.Alcove`, build 203) must be running for this to occur; quitting it prevents recurrence. **But it does not issue the runaway commands:**

| | Incident 1 | Incident 2 |
|---|---|---|
| Alcove volume writes **during** the runaway | all land **after** onset (10:39:28.333+, onset 10:39:26.849) | **0** |
| Alcove volume writes **before** onset | 2, at 10:39:17 (~10 s earlier) | — |
| ControlCenter writes | all of them | 493 of 496 (other 3 = investigator's `osascript`) |

In incident 2 Alcove ran for the entire runaway and wrote **nothing**. In incident 1 its writes land *after* the loop had already started. It is a **seed that gets ControlCenter into the racing state**, not the driver — once started the loop needs no external participant.

**The defect being reported is ControlCenter's**, and it stands on its own: no third-party app, privileged or not, should be able to drive system output to a rail. Alcove requires no special entitlement to do whatever it is doing.

**How the seed works is not established.** One untested hypothesis, offered only because it may shorten triage: every loop iteration carries `Did activate assertion for VolumeSystemBannerContent`, and Alcove's core function is to replace/suppress the system volume HUD. If the volume-apply path is coupled to the banner's presentation lifecycle, an externally disturbed banner callback could re-enter the setter and multiply in-flight sync tasks. **This is a guess, not a finding** — I have no visibility into ControlCenter internals.

## 4. Severity

**Not theoretical.** The affected output in incident 1 was a pair of **AirPods 4 being worn at the time**, and ControlCenter issued **1,158 writes setting them to `1.000000`** — full scale, in-ear, reached in ~0.5 s with no ramp. The user cannot correct it: every manual adjustment is overwritten in under a second, and the only recovery found was killing the agent from a terminal — not available to a normal user while the sound is painful.

# Steps to Reproduce
Reproduction currently requires the third-party app; the log-level signature below is diagnosable from a sysdiagnose without it.

1. On macOS 27.0 26A5378n, run **Alcove 1.7.9** (`com.henrikruscon.Alcove`). Connect AirPods (AirPods 4 here) as the active output.
2. Start Spotify playback **on an iPhone** — not on the Mac.
3. In the Spotify desktop app on the Mac, use the device picker to switch playback to **"This Computer"** (the Spotify Connect transfer — this supplies the audio-device renegotiation; Spotify itself never writes a volume property, a full-window grep returns nothing).
4. **Immediately adjust the system volume**, within ~1 s of the transfer. The timing matters: the adjustment lands inside ControlCenter's post-transfer re-sync, which is what appears to put two mutation paths in flight at once.
5. Observe the runaway begin ~200 ms after the negotiation and ~14 ms after the adjustment:
   ```
   10:39:26.646  coreaudiod    >>> NEGOTIATE [com.spotify.client]
   10:39:26.835  ControlCenter (DeviceID 198) setLevel: main vol 0.500000   ← the adjustment
   10:39:26.849  ControlCenter set system volume: 0.435 -> 0.5           ← +14 ms, runaway
   ```
   No volume write appears between 10:39:20 and `.835`, so the adjustment is the first mutation in the sequence. The log cannot distinguish a user-initiated `setLevel` from ControlCenter's own re-sync — both log identically — but it matches the reporter's account.
6. Capture the loop:
   ```
   /usr/bin/log stream --style compact --predicate 'process == "ControlCenter" AND eventMessage CONTAINS "set system volume"'
       -> ~30 lines/sec, ratcheting in 1/16 steps, then "1.000000 -> 1.000000" (or 0.000000) forever
   ```
7. Confirm the concurrent writers — note the multiple distinct TIDs:
   ```
   /usr/bin/log stream --style compact --predicate 'eventMessage CONTAINS "LogVolumeChangeForClientSide"'
       -> ControlCenter[<pid>:<many different tids>] AudioObjectSetPropertyData ... ['vmvc', 'outp']
   ```
8. Confirm there is no input driving it:
   ```
   /usr/bin/log stream --style compact --predicate 'subsystem CONTAINS "hid" OR eventMessage CONTAINS[c] "NX_KEYTYPE"'
       -> ~1 event per 6 s; no volume keys
   ```
9. Recover: `killall ControlCenter` (respawns automatically). The loop stops and volume holds. If the runaway left the device muted, clear it separately: `osascript -e 'set volume without output muted'`.

Notes for reproduction: `log` is a **zsh builtin** — use `/usr/bin/log` explicitly or the commands silently return nothing. Device IDs are per-boot and reused; resolve them via `AudioObjectGetPropertyData(kAudioHardwarePropertyDevices)` rather than assuming stability. Direction and target device are **not** deterministic across occurrences — expect either rail on either output.

# Expected vs Actual
- **Expected:** concurrent volume-sync requests serialize, each observing the true current value. A running third-party app cannot drive system output to a rail, and user volume input is authoritative.
- **Actual:** unsynchronized read-modify-write across >=7 threads produces a monotonic ratchet to 0 % or 100 %, self-sustains at 30 Hz, and overrides all user input until ControlCenter is restarted.

## On the fix
Rate-limiting the setter would be the **wrong** remedy: it slows the ratchet without removing its direction, so output still reaches the rail, just later. The defect is the lost update, not the update frequency.

Serializing volume mutations on a single queue/actor removes the race outright at no perceptible cost — volume changes occur at human rates (a few per second; 30 Hz in this pathological case), and serialization overhead is microseconds. Separately, decoupling `VolumeSystemBannerContent` presentation from the volume-apply path would prevent an externally disturbed HUD from re-entering the setter.

# Configuration
- MacBook Pro Mac15,11, M3 Max, 36 GB
- macOS 27.0 beta3 revision 26A5378n
- ControlCenter (`com.apple.controlcenter`), `SoundSettings`
- Alcove 1.7.9 (build 203, `com.henrikruscon.Alcove`) — required precondition
- Affected outputs: built-in speakers (`BuiltInSpeakerDevice`) and a Bluetooth audio device
- Also installed but **ruled out**: `OrayVirtualAudioDevice` (SunLogin virtual driver, was default *system* output) and `ToDeskOutputDriver` — together 2 of 490 writes in incident 1, none during either runaway

# Suggested attachments
- sysdiagnose captured **during** an active runaway (the 30 Hz loop is unmistakable in the ControlCenter log)
- Saved `log show` output for `set system volume`, showing the 1/16 ratchet, the stale intermediates, and the terminal `1.000000 -> 1.000000` spin
- Saved `LogVolumeChangeForClientSide` output showing the multiple concurrent ControlCenter TIDs
- HID capture from the same window demonstrating the absence of input events
- Before/after `log` line counts across `killall ControlCenter` (~240 lines / 8 s -> 1)

# Note
**This is not a macOS 27 regression.** The up-direction symptom is publicly reported against **macOS 26.3.1** with Alcove 1.6.12 on a MacBook Pro M2 Max — "volume stuck at maximum, the app blocks it from going down" — at https://github.com/henrikruscon/alcove-releases/issues/675. That report was closed as `not planned` / stale, and the Alcove repository was **archived read-only on 2026-06-01** (the app is closed-source; that tracker hosted only changelogs). There is no upstream channel left, which is part of why this is filed against Apple.

It is **not confirmed to be the same defect** — #675 involves USB-C output and reports only the max direction, and the mechanism was never investigated there. Treated here as prior art establishing that the symptom predates macOS 27, not as a duplicate.

Two limits on this report, stated plainly:
1. **The "quitting Alcove prevents it" result is observational** — recorded across an uncounted series of Spotify Connect transfers, not a controlled trial with a stated N.
2. **No public report of the ControlCenter-side race was found** (multi-threaded RMW, arbitrary direction, cross-device). That is the result of a handful of searches and is **not** a first-discovery claim.
