// volwatch — detects the ControlCenter volume runaway described in
// issues/apple-controlcenter-volume-rmw-race.md (Apple Feedback FB23868196)
// and records it; optionally restarts ControlCenter to stop it.
//
// WHY THE RULE IS WHAT IT IS  (all measured on 26A5378n, not assumed)
//
//   The runaway ratchets system volume in exact 1/16 steps at ~30 Hz until it
//   pins at 0.0 or 1.0. Three tempting shortcuts were tested and rejected:
//
//   1. "Watch for the 1.0 -> 1.0 spin."  A CoreAudio property listener does NOT
//      fire on writes that leave the value unchanged — 3 trials x 60 no-op
//      writes produced 0 callbacks, against a positive control of 6 real
//      changes producing 12. The pinned phase is invisible to us. Only the
//      ramp is observable, which is fine: the ramp is the actionable window.
//
//   2. "A human can't change volume that fast."  They can. KeyRepeat=2 on this
//      machine means a held volume key repeats at 30 ms — measured at
//      30.3-31.5 changes/sec, in 1/16 steps, monotonic. That is the bug's
//      signature exactly. Rate and step size cannot discriminate.
//
//   3. "Check the step size is 1/16."  Volume keys produce 1/16 steps too.
//
//   What does discriminate is INPUT. During a real runaway a 6 s HID capture
//   returned one key event total; during a human key-hold, seconds-since-last-
//   input reads 0.00-0.01. So: a ratchet with nobody touching the machine is
//   the bug. CGEventSource gives that unprivileged — no Accessibility grant.
//
// MODES
//   observe  (default)  log + notify only. Use this while validating.
//   enforce             also `killall ControlCenter`, with a cooldown.
//
// Deliberately does not write the volume property itself — a watchdog for a
// concurrency bug must not add another writer to the thing it is watching.

import Foundation
import CoreAudio
import CoreGraphics

// MARK: - Tunables

let RATE_MIN      = 15.0   // changes/sec before a burst counts as a ratchet
let INPUT_STALE   = 0.5    // sec since last input to call it unattended
let WINDOW        = 1.0    // sliding window for the rate estimate
let MIN_EVENTS    = 6      // ~200 ms at 30 Hz — fires before full scale (~500 ms)
let COOLDOWN      = 30.0   // sec between enforce actions

let enforce = CommandLine.arguments.contains("enforce")
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/volwatch.log")

// MARK: - Logging

let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    // Local time, not UTC: these lines get read side by side with `log show`
    // output while diagnosing, and mixed zones cost more than they save.
    f.timeZone = .current
    return f
}()

func record(_ line: String) {
    let entry = "\(iso.string(from: Date()))  \(line)\n"
    FileHandle.standardOutput.write(entry.data(using: .utf8)!)
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(entry.data(using: .utf8)!); try? h.close()
    } else {
        try? entry.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

func notify(_ title: String, _ body: String) {
    // osascript rather than UNUserNotificationCenter: this runs unbundled.
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "display notification \"\(body)\" with title \"\(title)\" sound name \"Funk\""]
    try? p.run()
}

// MARK: - CoreAudio

func vaddr() -> AudioObjectPropertyAddress {
    // 'vmvc' — virtual main volume, the property ControlCenter writes.
    AudioObjectPropertyAddress(mSelector: AudioObjectPropertySelector(0x766D7663),
                               mScope: kAudioDevicePropertyScopeOutput,
                               mElement: kAudioObjectPropertyElementMain)
}
func defaultOutAddr() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                               mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}
func defaultOut() -> AudioObjectID {
    var a = defaultOutAddr(); var d = AudioObjectID(0)
    var s = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &s, &d)
    return d
}
func getVol(_ d: AudioObjectID) -> Float32? {
    var a = vaddr(); var v: Float32 = 0; var s = UInt32(MemoryLayout<Float32>.size)
    return AudioObjectGetPropertyData(d, &a, 0, nil, &s, &v) == noErr ? v : nil
}
func uid(_ d: AudioObjectID) -> String {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    var cf: CFString? = nil; var s = UInt32(MemoryLayout<CFString?>.size)
    let err = withUnsafeMutablePointer(to: &cf) {
        AudioObjectGetPropertyData(d, &a, 0, nil, &s, $0)
    }
    return (err == noErr ? (cf as String?) : nil) ?? "unknown"
}
func inputIdle() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                            eventType: .init(rawValue: ~0)!)
}

// MARK: - Detector

final class Detector {
    private var events: [(t: Date, v: Float32)] = []
    private var last: Float32 = -1
    private var burstActive = false
    private var burstStart: Date?
    private var lastAction = Date.distantPast
    private let q = DispatchQueue(label: "volwatch.detector")

    func seed(_ v: Float32) { q.sync { last = v } }

    func onChange(device: AudioObjectID) {
        q.sync {
            guard let v = getVol(device) else { return }
            guard abs(v - last) > 0.0001 else { return }   // no-op notifications
            let now = Date()
            events.append((now, v)); last = v
            events.removeAll { now.timeIntervalSince($0.t) > WINDOW }

            guard events.count >= MIN_EVENTS else { return }
            let span = now.timeIntervalSince(events.first!.t)
            guard span > 0.15 else { return }
            let rate = Double(events.count - 1) / span

            var deltas: [Float32] = []
            for i in 1..<events.count { deltas.append(events[i].v - events[i-1].v) }
            let up = deltas.allSatisfy { $0 > 0 }, down = deltas.allSatisfy { $0 < 0 }
            guard rate >= RATE_MIN, up || down else { return }

            let idle = inputIdle()
            guard idle > INPUT_STALE else {
                if burstActive { burstActive = false; burstStart = nil }
                return   // someone is at the keyboard — this is a person
            }

            if !burstActive {
                burstActive = true; burstStart = now
                let dir = up ? "up" : "down"
                record(String(format:
                    "DETECT  dir=%@ rate=%.1f/s value=%.4f device=%@ inputIdle=%.1fs mode=%@",
                    dir, rate, v, uid(device), idle, enforce ? "enforce" : "observe"))
                notify("Volume runaway detected",
                       "Ratcheting \(dir) with no input. " +
                       (enforce ? "Restarting ControlCenter." : "Observe mode — not acting."))
                if enforce && now.timeIntervalSince(lastAction) > COOLDOWN {
                    lastAction = now
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                    p.arguments = ["ControlCenter"]
                    try? p.run(); p.waitUntilExit()
                    record("ACTION  killall ControlCenter -> status \(p.terminationStatus)")
                }
            }
        }
    }

    func reportPinned(value: Float32, device: AudioObjectID) {
        q.sync {
            guard !burstActive else { return }
            burstActive = true; burstStart = Date()
            record(String(format:
                "DETECT  PINNED at %.4f device=%@ (log probe: ControlCenter still writing) mode=%@",
                value, uid(device), enforce ? "enforce" : "observe"))
            notify("Volume stuck", "Volume pinned at \(value <= 0.0001 ? "0%" : "100%"). " +
                   (enforce ? "Restarting ControlCenter." : "Observe mode — not acting."))
            if enforce && Date().timeIntervalSince(lastAction) > COOLDOWN {
                lastAction = Date()
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                p.arguments = ["ControlCenter"]
                try? p.run(); p.waitUntilExit()
                record("ACTION  killall ControlCenter -> status \(p.terminationStatus)")
            }
        }
    }

    func settle() {
        q.sync {
            guard burstActive, let s = burstStart else { return }
            let now = Date()
            guard now.timeIntervalSince(events.last?.t ?? s) > 2.0 else { return }
            record(String(format: "SETTLE  burst lasted %.1fs, final value %.4f",
                          now.timeIntervalSince(s), last))
            burstActive = false; burstStart = nil
        }
    }
}

let detector = Detector()

// MARK: - Device binding (the runaway migrates across devices, so follow it)

var bound: AudioObjectID = 0
var boundAddr = vaddr()
let cbQueue = DispatchQueue(label: "volwatch.ca")
var volBlock: AudioObjectPropertyListenerBlock!

func bind(_ dev: AudioObjectID) {
    if bound != 0 {
        AudioObjectRemovePropertyListenerBlock(bound, &boundAddr, cbQueue, volBlock)
    }
    bound = dev
    guard dev != 0 else { record("BIND    no default output device"); return }
    guard let v = getVol(dev) else {
        record("BIND    device \(dev) (\(uid(dev))) exposes no volume control — fixed-volume output")
        return
    }
    detector.seed(v)
    AudioObjectAddPropertyListenerBlock(dev, &boundAddr, cbQueue, volBlock)
    record("BIND    device \(dev) uid=\(uid(dev)) volume=\(v)")
}

volBlock = { _, _ in detector.onChange(device: bound) }

let deviceChanged: AudioObjectPropertyListenerBlock = { _, _ in
    let d = defaultOut()
    if d != bound { bind(d) }
}
var dAddr = defaultOutAddr()
AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                    &dAddr, cbQueue, deviceChanged)

record("START   volwatch mode=\(enforce ? "enforce" : "observe") log=\(logURL.path)")
bind(defaultOut())

// Periodic sweep. Does three things the listener cannot.
//
// (1) REBIND BY POLLING. Relying on the default-device notification alone was
//     observed to fail: on 2026-07-20 14:14 a runaway ran on device 321 while
//     volwatch was still bound to 202 — the AirPods had reconnected under a new
//     CoreAudio ID and no rebind happened. Polling the default device is cheap
//     and does not depend on that notification arriving.
//
// (2) PINNED-PHASE PROBE. Once the ratchet reaches a rail it writes the same
//     value forever, which raises no property notifications — the same 14:14
//     runaway was emitting 598 `0.000000 -> 0.000000` writes/20 s completely
//     invisibly. When volume sits at a rail with nobody at the keyboard, ask
//     the unified log directly whether ControlCenter is spinning. Gated behind
//     those two conditions so the log query stays rare.
//
// (3) Burst-end bookkeeping.

var lastProbe = Date.distantPast

func controlCenterSpinning() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    p.arguments = ["show", "--last", "3s", "--style", "compact",
                   "--predicate", "process == \"ControlCenter\" AND eventMessage CONTAINS \"set system volume\""]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let lines = String(decoding: data, as: UTF8.self)
        .split(separator: "\n").filter { $0.contains("set system volume") }.count
    return lines > 30          // 3 s of a 30 Hz loop is ~90; idle is single digits
}

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    detector.settle()

    let d = defaultOut()
    if d != bound { record("REBIND  default output changed \(bound) -> \(d) (poll)"); bind(d) }

    guard let v = getVol(bound) else { return }
    let atRail = v <= 0.0001 || v >= 0.9999
    guard atRail, inputIdle() > INPUT_STALE,
          Date().timeIntervalSince(lastProbe) > 10 else { return }
    lastProbe = Date()
    if controlCenterSpinning() {
        detector.reportPinned(value: v, device: bound)
    }
}

RunLoop.main.run()
