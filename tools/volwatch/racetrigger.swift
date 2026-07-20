// racetrigger — tries to provoke the ControlCenter volume runaway (#21 /
// FB23868196) on demand, so the defect can be demonstrated rather than waited for.
//
// WHAT IT RECREATES, AND WHAT IT CANNOT
//
//   Observed conditions across 6+ runaways on 26A5378n:
//     (a) a second process writing volume at 30 Hz in 1/16 steps, oscillating
//         up and down — Alcove mirroring the user's adjustments
//     (b) the user hammering volume keys right after an output transfer
//     (c) default-output-device resolution churning at the same time
//         (AirPods handing off between iPhone and Mac, virtual drivers
//         competing in HALS_DefaultDeviceManager)
//
//   This tool recreates (a) and (b) directly — concurrent oscillating writers —
//   and approximates (c) by flipping the default output device, which walks the
//   same HALS_DefaultDeviceManager path.
//
//   It CANNOT recreate the Bluetooth handoff itself — and measurement showed
//   that does not matter: the race fired with the AirPods idle.
//
// WHY OPEN-LOOP WRITING IS NOT ENOUGH  (measured 2026-07-20 15:14–15:18)
//
//   Timer-driven writes at 2,508 and 2,571 lines/min with Alcove quit produced
//   NO runaway. Re-launching Alcove — which writes only ~65 times/min, 38x less
//   — produced one within a minute. Write volume is not the trigger.
//
//   The difference is closed loop vs open loop. A timer writes blind; Alcove
//   listens for the volume-changed notification and writes back from inside the
//   callback, so its writes land in the same notification chain ControlCenter is
//   servicing. That is what produces the tight interleaving a lost update needs.
//   (It also explains why Alcove goes silent once the value pins at a rail: no
//   value change, no notification, no echo — while ControlCenter's own loop is
//   already self-sustaining.)
//
//   Hence --mode closed, the default: echo every observed change straight back
//   from the listener callback.
//
// SAFETY
//   Every write this tool makes is clamped to --safe-max (default 0.10). But if
//   the race fires, ControlCenter drives volume to 0 or 100% and this tool
//   cannot stop that — that is the bug. Run it on built-in speakers with
//   nothing playing, and do not wear headphones.
//
// USAGE
//   swiftc -O -o racetrigger racetrigger.swift
//   ./racetrigger                        # 20 s, 4 threads, device flipping on
//   ./racetrigger --duration 60 --threads 8
//   ./racetrigger --no-flip              # writers only, no device churn
//
// Run it with Alcove (or whatever volume-mirroring app you have) RUNNING —
// this tool is only one writer; the collision needs the other one.

import Foundation
import CoreAudio

// MARK: - Args

func arg(_ name: String, _ def: Double) -> Double {
    guard let i = CommandLine.arguments.firstIndex(of: name),
          i + 1 < CommandLine.arguments.count,
          let v = Double(CommandLine.arguments[i + 1]) else { return def }
    return v
}
let duration = arg("--duration", 20)
let threads  = Int(arg("--threads", 2))
let safeMax  = Float32(arg("--safe-max", 0.10))
let doFlip   = !CommandLine.arguments.contains("--no-flip")
let openLoop = CommandLine.arguments.contains("--mode") &&
               CommandLine.arguments.contains("open")
let echoMute = !CommandLine.arguments.contains("--no-mute")
// The stale-read window. An instant echo cannot lose an update — you write back
// what you just read. Alcove reads the notification, runs its HUD animation,
// and only then writes, so its write is based on a value that may already have
// moved. That gap is the defect's raw material, so it is the main dial here.
let echoDelayMs = arg("--echo-delay", 40)
// Cap total echo rate. Measured: 8 immediate echoers did not race ControlCenter,
// they starved it — the whole Control Center went unresponsive. Alcove triggers
// the bug writing ~65 times/MINUTE. Precision beats pressure.
let echoMaxHz   = arg("--echo-hz", 12)

// MARK: - CoreAudio

func vaddr() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: AudioObjectPropertySelector(0x766D7663), // 'vmvc'
                               mScope: kAudioDevicePropertyScopeOutput,
                               mElement: kAudioObjectPropertyElementMain)
}
func defOutAddr() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                               mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}
func defaultOut() -> AudioObjectID {
    var a = defOutAddr(); var d = AudioObjectID(0)
    var s = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &s, &d)
    return d
}
func setDefaultOut(_ d: AudioObjectID) {
    var a = defOutAddr(); var v = d
    AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                               UInt32(MemoryLayout<AudioObjectID>.size), &v)
}
// Virtual drivers (SunLogin's OrayVirtualAudioDevice, ToDesk's, loopback tools)
// are real CoreAudio devices with real volume controls, so a naive "first other
// device" pick lands on one — and then audio routes somewhere inaudible, and a
// killed run can leave it there. Flip between physical outputs only.
func isVirtual(_ d: AudioObjectID) -> Bool {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    var t: UInt32 = 0; var s = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(d, &a, 0, nil, &s, &t) == noErr else { return true }
    return t == kAudioDeviceTransportTypeVirtual || t == kAudioDeviceTransportTypeAggregate
}

func allOutputDevices() -> [AudioObjectID] {
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
    return ids.filter { getVol($0) != nil && !isVirtual($0) }
}
func getVol(_ d: AudioObjectID) -> Float32? {
    var a = vaddr(); var v: Float32 = 0; var s = UInt32(MemoryLayout<Float32>.size)
    return AudioObjectGetPropertyData(d, &a, 0, nil, &s, &v) == noErr ? v : nil
}
@discardableResult func setVol(_ d: AudioObjectID, _ v: Float32) -> OSStatus {
    var a = vaddr(); var val = max(0, min(v, safeMax))     // hard clamp, always
    return AudioObjectSetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &val)
}
func uid(_ d: AudioObjectID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    var cf: CFString? = nil; var s = UInt32(MemoryLayout<CFString?>.size)
    let e = withUnsafeMutablePointer(to: &cf) { AudioObjectGetPropertyData(d, &a, 0, nil, &s, $0) }
    return (e == noErr ? (cf as String?) : nil) ?? "?"
}

// Is ControlCenter spinning right now? Same probe volwatch uses.
func controlCenterSpinning() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    p.arguments = ["show", "--last", "3s", "--style", "compact", "--predicate",
                   "process == \"ControlCenter\" AND eventMessage CONTAINS \"set system volume\""]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return String(decoding: d, as: UTF8.self)
        .split(separator: "\n").filter { $0.contains("set system volume") }.count > 30
}

// MARK: - Run

let origDevice = defaultOut()
guard let origVol = getVol(origDevice) else {
    print("error: default output exposes no volume control"); exit(1)
}
let devices = allOutputDevices()
let explicitFlip = CommandLine.arguments.firstIndex(of: "--flip-to").flatMap {
    $0 + 1 < CommandLine.arguments.count ? AudioObjectID(CommandLine.arguments[$0 + 1]) : nil
}
let flipTarget = explicitFlip ?? devices.first { $0 != origDevice }

print("""
racetrigger — provoking the ControlCenter volume RMW race

  device      \(origDevice) (\(uid(origDevice)))
  volume now  \(origVol)
  mode        \(openLoop ? "open loop (timer)" : "CLOSED LOOP (echo from listener)")\n  writers     \(threads)\n  echo delay  \(Int(echoDelayMs)) ms (jittered ±50%) — the stale-read window\n  echo rate   max \(Int(echoMaxHz))/s
  duration    \(Int(duration)) s
  safe-max    \(safeMax)   (every write by this tool is clamped here)
  flipping    \(doFlip && flipTarget != nil ? "yes -> \(flipTarget!) (\(uid(flipTarget!)))" : "no")

  ⚠️  If the race fires, ControlCenter — not this tool — will drive volume to
      0 or 100%. Use built-in speakers, play nothing, wear no headphones.
  ℹ️  In closed-loop mode this tool supplies the echo itself, so Alcove is
      not required. Quit it for a clean self-contained test.

physical outputs available (virtual drivers excluded from flipping):
\(devices.map { "    \($0)  \(uid($0))\($0 == origDevice ? "   [current]" : "")" }.joined(separator: "\n"))
  override with --flip-to <id>, or disable with --no-flip

starting in 3 s — ^C to abort
""")
Thread.sleep(forTimeInterval: 3)

let stop = DispatchSemaphore(value: 0)
var fired = false
let lock = NSLock()
let deadline = Date().addingTimeInterval(duration)

// THE WRITERS.
//
// closed loop (default): register N listeners on the volume property and echo
// every observed change straight back from inside the callback, nudged by one
// 1/16 step. This is what Alcove does, and it is what open-loop timer writing
// at 38x the rate failed to do. Each echo raises another notification, so our
// writes land in the very chain ControlCenter is servicing.
//
// open loop (--mode open): the original timer-driven version, kept so the
// negative result stays reproducible.

let step = safeMax / 8.0
var echoCount = 0
let echoLock = NSLock()

if openLoop {
    for t in 0..<threads {
        Thread.detachNewThread {
            var i = t * 3
            while Date() < deadline {
                lock.lock(); let done = fired; lock.unlock()
                if done { break }
                setVol(defaultOut(), Float32(i % 8) * step)
                i += 1
                usleep(useconds_t(25_000 + (t * 2_000)))
            }
        }
    }
} else {
    var vAddr = vaddr()
    var lastEcho = Date.distantPast
    let rateLock = NSLock()

    for t in 0..<threads {
        let q = DispatchQueue(label: "echo.\(t)")
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            lock.lock(); let done = fired; lock.unlock()
            if done || Date() >= deadline { return }

            // Rate limit — a starved ControlCenter cannot race.
            rateLock.lock()
            let now = Date()
            if now.timeIntervalSince(lastEcho) < 1.0 / echoMaxHz { rateLock.unlock(); return }
            lastEcho = now
            rateLock.unlock()

            let dev = defaultOut()
            guard let stale = getVol(dev) else { return }        // READ

            // ...then wait. During this window ControlCenter (or another echoer)
            // may write. Our write below is computed from the value we read
            // BEFORE that, so it silently discards whatever landed in between:
            // a lost update, which is exactly the defect being provoked.
            let jitter = echoDelayMs * Double.random(in: 0.5...1.5)
            usleep(useconds_t(jitter * 1000))

            echoLock.lock(); echoCount += 1; let n = echoCount; echoLock.unlock()
            setVol(dev, (n % 2 == 0) ? stale + step : stale - step)   // WRITE (stale)

            if echoMute && n % 7 == 0 {
                // The observed loop writes 'mute' alongside 'vmvc' every
                // iteration; mirror that so the same code paths are exercised.
                var ma = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyMute,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: kAudioObjectPropertyElementMain)
                var off: UInt32 = 0
                AudioObjectSetPropertyData(dev, &ma, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
            }
        }
        AudioObjectAddPropertyListenerBlock(origDevice, &vAddr, q, block)
    }

    // Seed: without a first change there is no notification to echo.
    Thread.detachNewThread {
        while Date() < deadline {
            lock.lock(); let done = fired; lock.unlock()
            if done { break }
            setVol(defaultOut(), Float32.random(in: 0...1) * safeMax)
            usleep(300_000)
        }
    }
}

// Device flipping — walks the same default-device resolution path the AirPods
// handoff walks. Slower than the writers so it lands mid-sweep.
if doFlip, let other = flipTarget {
    Thread.detachNewThread {
        var useOther = true
        while Date() < deadline {
            lock.lock(); let done = fired; lock.unlock()
            if done { break }
            setDefaultOut(useOther ? other : origDevice)
            useOther.toggle()
            usleep(400_000)
        }
    }
}

// Watch for the race actually firing, and stop early when it does.
Thread.detachNewThread {
    while Date() < deadline {
        Thread.sleep(forTimeInterval: 2)
        let v = getVol(defaultOut()) ?? -1
        if (v <= 0.0001 || v >= 0.9999), controlCenterSpinning() {
            lock.lock(); fired = true; lock.unlock()
            print("\n*** RACE FIRED — volume pinned at \(v), ControlCenter still writing ***")
            stop.signal(); return
        }
    }
    stop.signal()
}

_ = stop.wait(timeout: .now() + duration + 5)
Thread.sleep(forTimeInterval: 0.5)

// Restore what we can. If the race fired, ControlCenter will fight this — say so
// rather than pretending the restore worked.
setDefaultOut(origDevice)
Thread.sleep(forTimeInterval: 0.3)
setVol(origDevice, origVol)
Thread.sleep(forTimeInterval: 0.5)

let final = getVol(origDevice) ?? -1
print("""

result      \(fired ? "RACE FIRED" : "no runaway observed")\nechoes      \(echoCount)
volume now  \(final)\(abs(final - origVol) > 0.01 ? "  (could not restore \(origVol) — expected if the race is live)" : "")

\(fired
  ? "Stop it with:  killall ControlCenter\n  then:          osascript -e 'set volume without output muted'"
  : "Not conclusive. The trigger may need the Bluetooth handoff this tool cannot\n  simulate — AirPods moving between iPhone and Mac. Try again during real\n  device churn, or leave tools/volwatch running and catch it in the wild.")
""")
