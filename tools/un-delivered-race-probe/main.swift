import Foundation
import UserNotifications
import AppKit

// UNDVerify — independent verification probe.
//
// Question: after add(_:withCompletionHandler:) fires its completion handler,
// how long until getDeliveredNotificationsWithCompletionHandler: reports the
// notification we just added?  (Chromium's MacNotificationServiceUN::
// OkayToTerminateService kills the Alerts helper when that array is empty.)
//
// PITFALL avoided: never block inside a UserNotifications completion handler
// waiting on another UN callback — they share a queue and it deadlocks,
// yielding bogus all-negative results.  Everything below is async; the only
// serialisation is an explicit chained-poll that re-dispatches to a global
// queue before issuing the next call.
//
// Two independent measurements:
//   PHASE A — fan-out sampling at fixed offsets (0/5/10/15/25/50/100/250 ms).
//             Matches the methodology of the claim under test.  Confound: 8
//             concurrent XPC queries may queue behind each other, so we log
//             both the issue time and the reply time of every sample.
//   PHASE B — chained polling: one query at a time, each next query issued
//             from the previous reply.  No concurrency, directly measures the
//             first instant the notification becomes visible.

let center = UNUserNotificationCenter.current()
let logPath = ("~/undverify_run.log" as NSString).expandingTildeInPath
let BUILD_TAG = "UNDVerify/v5"

let logQ = DispatchQueue(label: "log")
func logLine(_ s: String) {
    logQ.sync {
        let line = s + "\n"
        if let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); fh.closeFile()
        } else { try? line.write(toFile: logPath, atomically: true, encoding: .utf8) }
    }
}

@inline(__always) func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
@inline(__always) func msSince(_ t: UInt64) -> Double { Double(nowNs() &- t) / 1_000_000.0 }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let CATEGORY = "UNDVERIFY_CAT"
let delaysMs: [Double] = [0, 5, 10, 15, 25, 50, 100, 250]
let TRIALS = 8

func makeRequest(_ tag: String) -> (UNNotificationRequest, String) {
    let content = UNMutableNotificationContent()
    content.title = "UNDVerify \(tag)"
    content.body = "getDeliveredNotifications visibility probe"
    content.categoryIdentifier = CATEGORY          // persistent/alert style, like Chrome
    let id = "undverify-\(tag)-\(UInt64(Date().timeIntervalSince1970 * 1000))"
    return (UNNotificationRequest(identifier: id, content: content, trigger: nil), id)
}

// ---------------------------------------------------------------- PHASE A ---

func phaseATrial(_ n: Int, done: @escaping () -> Void) {
    center.removeAllDeliveredNotifications()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
        let (req, id) = makeRequest("A\(n)")
        let addIssued = nowNs()
        center.add(req) { err in
            let addDone = nowNs()
            let addMs = Double(addDone &- addIssued) / 1_000_000.0
            if let err {
                logLine("A trial \(n): add() error \(err)"); done(); return
            }
            let lock = NSLock()
            var results = [Double: (Bool, Int, Double, Double)]()   // visible, count, issuedMs, repliedMs
            let group = DispatchGroup()
            for d in delaysMs {
                group.enter()
                // Deliberately scheduled off the UN completion queue.
                DispatchQueue.global().asyncAfter(deadline: .now() + d / 1000.0) {
                    let issued = nowNs()
                    center.getDeliveredNotifications { notes in
                        let replied = nowNs()
                        let visible = notes.contains { $0.request.identifier == id }
                        lock.lock()
                        results[d] = (visible, notes.count,
                                      Double(issued &- addDone) / 1_000_000.0,
                                      Double(replied &- addDone) / 1_000_000.0)
                        lock.unlock()
                        group.leave()
                    }
                }
            }
            group.notify(queue: .global()) {
                let parts = delaysMs.map { d -> String in
                    guard let (v, c, i, r) = results[d] else { return "\(Int(d)):??" }
                    return String(format: "%@@%.1f/%.1f:%@(n=%d)",
                                  String(Int(d)), i, r, v ? "Y" : "N", c)
                }
                logLine(String(format: "A trial %d addMs=%.2f  %@", n, addMs,
                               parts.joined(separator: " ")))
                done()
            }
        }
    }
}

// ---------------------------------------------------------------- PHASE B ---
// Chained polling: issue one getDeliveredNotifications at a time, next one
// dispatched from the previous reply (via a global queue, never re-entrant on
// the UN queue).  Records elapsed-since-add-completion of the first sighting.

func phaseBTrial(_ n: Int, done: @escaping () -> Void) {
    center.removeAllDeliveredNotifications()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
        let (req, id) = makeRequest("B\(n)")
        let addIssued = nowNs()
        center.add(req) { err in
            let addDone = nowNs()
            let addMs = Double(addDone &- addIssued) / 1_000_000.0
            if let err { logLine("B trial \(n): add() error \(err)"); done(); return }

            var polls = 0
            var firstIssued: Double = -1     // issue time of the very first poll
            var lastMissIssued: Double = -1  // issue time of the last poll that missed
            var lastMissReplied: Double = -1

            func poll() {
                let issued = nowNs()
                if firstIssued < 0 { firstIssued = Double(issued &- addDone) / 1_000_000.0 }
                center.getDeliveredNotifications { notes in
                    let replied = nowNs()
                    polls += 1
                    let iMs = Double(issued &- addDone) / 1_000_000.0
                    let rMs = Double(replied &- addDone) / 1_000_000.0
                    if notes.contains(where: { $0.request.identifier == id }) {
                        logLine(String(format:
                            "B trial %d addMs=%.2f firstPollIssued=%.2fms polls=%d "
                            + "VISIBLE issued=%.2fms replied=%.2fms lastMiss(issued=%.2f replied=%.2f) n=%d",
                            n, addMs, firstIssued, polls, iMs, rMs,
                            lastMissIssued, lastMissReplied, notes.count))
                        done(); return
                    }
                    lastMissIssued = iMs; lastMissReplied = rMs
                    if rMs > 3000 {
                        logLine(String(format:
                            "B trial %d addMs=%.2f polls=%d TIMEOUT after %.1fms (never visible)",
                            n, addMs, polls, rMs))
                        done(); return
                    }
                    DispatchQueue.global().async { poll() }   // never re-entrant
                }
            }
            DispatchQueue.global().async { poll() }
        }
    }
}

// ------------------------------------------------------------------ DRIVER ---

var phase = "A"
var trial = 1

func next() {
    if phase == "A" && trial > TRIALS { phase = "B"; trial = 1 }
    if phase == "B" && trial > TRIALS {
        logLine("ALL DONE")
        center.removeAllDeliveredNotifications()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { exit(0) }
        return
    }
    let n = trial; trial += 1
    let f = (phase == "A") ? phaseATrial : phaseBTrial
    f(n) { DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { next() } }
}

// Logged BEFORE the authorization request so an empty-after-startup log
// unambiguously means "prompt pending / user has not answered", not "crashed".
logLine("=== \(BUILD_TAG) ===")
logLine("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
// NOTE: do NOT log ProcessInfo.hostName — it does an mDNS reverse lookup and
// raises a "find devices on local networks" prompt that blocks the run.
logLine("bundle=\(Bundle.main.bundleIdentifier ?? "nil")")
logLine("startup ok, requesting authorization…")

func begin() {
    center.setNotificationCategories([
        UNNotificationCategory(identifier: CATEGORY,
                               actions: [UNNotificationAction(identifier: "settings",
                                                              title: "Settings", options: [])],
                               intentIdentifiers: [], options: [])
    ])
    center.getNotificationSettings { s in
        logLine("settings auth=\(s.authorizationStatus.rawValue) alertStyle=\(s.alertStyle.rawValue) "
                + "alertSetting=\(s.alertSetting.rawValue)")
        // let category registration settle before the first trial
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { next() }
    }
}

// Check current status first, so a re-run after the user has granted permission
// does not depend on the prompt at all.
center.getNotificationSettings { s in
    logLine("initial authorizationStatus=\(s.authorizationStatus.rawValue) "
            + "(0=notDetermined 1=denied 2=authorized 3=provisional 4=ephemeral)")
    switch s.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
        logLine("already authorized — starting trials")
        begin()
    case .denied:
        logLine("ABORT: authorization DENIED for this bundle id. "
                + "Enable it in System Settings > Notifications, or use a fresh bundle id.")
        exit(2)
    default:
        logLine("notDetermined — requesting authorization; PROMPT WILL APPEAR, please click Allow. "
                + "Do NOT kill this process while the prompt is up.")
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, err in
            logLine("authorization granted=\(granted) err=\(String(describing: err))")
            guard granted else { logLine("ABORT: not granted"); exit(1) }
            begin()
        }
    }
}

app.run()
