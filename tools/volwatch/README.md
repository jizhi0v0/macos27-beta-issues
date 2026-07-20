# volwatch

Passive watchdog for the ControlCenter volume runaway in
[#21](https://github.com/jizhi0v0/macos27-beta-issues/issues/21) / [FB23868196](https://feedbackassistant.apple.com/feedback/23868196).

The bug ratchets system volume in 1/16 steps at ~30 Hz until it pins at 0 % or
100 %, and it is **probabilistic** — five deliberate attempts with the full
trigger sequence failed to reproduce it. Forcing it is unreliable and each
attempt risks hearing, so this records occurrences passively instead.

针对 #21 的被动观测工具。该 bug 是概率性的(5 次主动复现全部失败),硬凑代价高且有听力风险,所以改为常驻记录。

## Why the detection rule is what it is

Three obvious rules were tested on `26A5378n` and **rejected**:

| Rule | Why it fails |
|---|---|
| Watch for the `1.0 -> 1.0` spin | A CoreAudio property listener does **not** fire on writes that leave the value unchanged — 3 trials × 60 no-op writes → **0 callbacks**, against a positive control of 6 real changes → 12. The pinned phase is invisible. |
| "A human can't change volume that fast" | They can. `KeyRepeat=2` here means a held volume key repeats every 30 ms — measured at **30.3–31.5 changes/sec**, in 1/16 steps, monotonic. Identical to the bug. |
| Check the step is 1/16 | Volume keys produce 1/16 steps too. |

What does separate them is **input**. During a real runaway a 6 s HID capture
returned one key event total; during a human key-hold, seconds-since-last-input
reads 0.00–0.01. So:

> a ratchet **with nobody touching the machine** is the bug.

`CGEventSource.secondsSinceLastEventType` provides that unprivileged — no
Accessibility grant needed.

Validated both directions on this machine:

- fires ~200 ms into a simulated ratchet (before full scale at ~500 ms)
- **correctly ignored real volume-key input measured at 30.3 changes/sec** —
  the bug's exact rate — during ordinary use

It deliberately never writes the volume property: a watchdog for a concurrency
bug must not become another writer to the thing it is watching.

## Build

```sh
swiftc -O -o volwatch volwatch.swift
```

## Run

```sh
./volwatch            # observe — log + notify only
./volwatch enforce    # also `killall ControlCenter`, 30 s cooldown
```

Start in `observe`. Only move to `enforce` once you have seen it behave on your
own machine — a false positive there kills ControlCenter for no reason.

Log: `~/Library/Logs/volwatch.log`

```
2026-07-20T13:54:00.626+08:00  BIND    device 100 uid=BuiltInSpeakerDevice volume=0.3
2026-07-20T13:55:11.098+08:00  DETECT  dir=up rate=23.2/s value=0.0312 device=... inputIdle=98.7s mode=observe
2026-07-20T13:55:14.029+08:00  SETTLE  burst lasted 3.0s, final value 1.0000
```

## Install as a LaunchAgent

`~/Library/LaunchAgents/com.jizhi.volwatch.plist` — adjust the path:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jizhi.volwatch</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/tools/volwatch/volwatch</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key>
    <string>/Users/YOU/Library/Logs/volwatch.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/YOU/Library/Logs/volwatch.stderr.log</string>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
```

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jizhi.volwatch.plist
launchctl print   gui/$(id -u)/com.jizhi.volwatch | grep -E 'state|pid'
launchctl bootout  gui/$(id -u)/com.jizhi.volwatch   # uninstall
```

## Known limits

- **Cannot protect hearing.** The climb to full scale takes ~0.5 s; detection
  needs ~200 ms and `killall` needs more. It bounds exposure from *indefinite*
  to about a second — it does not prevent the first blast.
- **Blind to an already-pinned runaway.** If it starts while volume is already
  stuck, there are no value changes to observe. Only the ramp is visible.
- **One device at a time.** It follows the default output across changes (the
  runaway migrates), but does not watch non-default devices.
