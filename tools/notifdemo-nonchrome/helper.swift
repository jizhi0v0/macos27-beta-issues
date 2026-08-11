import Foundation
import UserNotifications
import AppKit

// NotifDemoHelper — a non-Chrome stand-in for `Google Chrome Helper (Alerts).app`.
//
// Shape copied from Chromium, code copied from nothing:
//   * separate app bundle, own bundle id, LSUIElement, launched by a parent app;
//   * it is the process that calls UNUserNotificationCenter.add(), so it is the
//     registered notification client that usernoted must call back into;
//   * right after add()'s completion handler fires it evaluates Chromium's
//     MacNotificationServiceUN::OkayToTerminateService, i.e.
//         return notifications.empty();
//     over getDeliveredNotificationsWithCompletionHandler:, and exit(0)s if true;
//   * it refuses to run standalone: without the `--from-parent` argv marker it
//     exits immediately.  This is the property that defeats the OS's
//     relaunch-based recovery when usernoted tries to deliver a click to a
//     client that is gone.
//
// PITFALL (see ../un-delivered-race-probe/README.md): never block inside a
// UserNotifications completion handler waiting on another UN callback.  The
// delivered-query below is dispatched onto a global queue first.

let argv = Array(CommandLine.arguments.dropFirst())
let tag = argv.firstIndex(of: "--tag").map { $0 + 1 < argv.count ? argv[$0 + 1] : "?" } ?? "-"
let stayAlive = argv.contains("--stay-alive")

// A relaunch performed by LaunchServices on usernoted's behalf carries no
// arguments, so the "may I run standalone?" switch has to live outside argv.
let allowStandalonePath = ("~/.notifdemo_allow_standalone" as NSString).expandingTildeInPath
let allowStandalone = FileManager.default.fileExists(atPath: allowStandalonePath)

let isStandalone = !argv.contains("--from-parent")
Log.line("helper", "launched argv=\(argv) standalone=\(isStandalone) "
         + "allowStandaloneFile=\(allowStandalone)")

// ---- Chromium-faithful refusal to run standalone ---------------------------
// A relaunch triggered by usernoted/LaunchServices to deliver a click arrives
// here with no arguments.  Chromium's alerts helper cannot run that way and
// quits, which is what defeats the OS's relaunch-based recovery.  The
// ~/.notifdemo_allow_standalone file turns the refusal off so the two cases
// can be compared.
if isStandalone && !allowStandalone {
    Log.line("helper", "STANDALONE LAUNCH (no --from-parent marker) -> exit(0) immediately, "
             + "the way Google Chrome Helper (Alerts) does. Any click relaunch dies here.")
    exit(0)
}

let center = UNUserNotificationCenter.current()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let CATEGORY = "NOTIFDEMO_ALERT"

func postAndDecide() {
    // Start each trial from a clean slate so the array we test is exactly
    // "our own notification, or nothing" — which is the situation a real
    // alerts helper with a single outstanding notification is in.
    center.removeAllDeliveredNotifications()

    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
        center.getDeliveredNotifications { pre in
            Log.line("helper", "pre-add delivered count=\(pre.count)")

            let content = UNMutableNotificationContent()
            content.title = "NotifDemo \(tag)"
            content.body = "Click me. Posted by NotifDemoHelper (a non-Chrome alerts helper)."
            content.categoryIdentifier = CATEGORY          // action button => alert path
            let id = "notifdemo-\(tag)-\(UInt64(Date().timeIntervalSince1970 * 1000))"
            let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)

            let addIssued = nowNs()
            center.add(req) { err in
                let addDone = nowNs()
                if let err {
                    Log.line("helper", "add() error \(err)"); exit(3)
                }
                Log.line("helper", String(format: "add() completion fired, id=%@ addMs=%.2f",
                                          id, msBetween(addIssued, addDone)))

                // Chromium's OkayToTerminateService, evaluated the instant the
                // add completion returns.  Hop off the UN queue first.
                DispatchQueue.global().async {
                    let qIssued = nowNs()
                    center.getDeliveredNotifications { notes in
                        let qDone = nowNs()
                        let mine = notes.contains { $0.request.identifier == id }
                        Log.line("helper", String(format:
                            "OkayToTerminateService query: count=%d mineVisible=%@ "
                            + "issued=+%.2fms replied=+%.2fms ids=%@",
                            notes.count, mine ? "Y" : "N",
                            msBetween(addDone, qIssued), msBetween(addDone, qDone),
                            notes.map { $0.request.identifier }.description))

                        if notes.isEmpty && !stayAlive {
                            Log.line("helper", "DECISION: notifications.empty() == true -> "
                                     + "OkayToTerminateService returns YES -> exit(0) "
                                     + "WHILE THE NOTIFICATION IS STILL ON SCREEN")
                            exit(0)
                        } else if notes.isEmpty {
                            Log.line("helper", "DECISION: notifications.empty() == true, but "
                                     + "--stay-alive given -> NOT exiting (positive control: "
                                     + "a live client should receive the click)")
                        } else {
                            Log.line("helper", "DECISION: notifications.empty() == false -> "
                                     + "OkayToTerminateService returns NO -> staying alive")
                        }
                        // Alive path: hang around so the click has somewhere to land.
                        DispatchQueue.global().asyncAfter(deadline: .now() + 600) {
                            Log.line("helper", "idle timeout, exiting")
                            exit(0)
                        }
                    }
                }
            }
        }
    }
}

// A live client must be able to receive the click, so register a delegate.
final class Delegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ c: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        Log.line("helper", "*** didReceive response: id=\(response.notification.request.identifier) "
                 + "action=\(response.actionIdentifier)")
        done()
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter,
                               willPresent n: UNNotification,
                               withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }
}
let delegate = Delegate()
center.delegate = delegate

func begin() {
    center.setNotificationCategories([
        UNNotificationCategory(identifier: CATEGORY,
                               actions: [UNNotificationAction(identifier: "demo.action",
                                                              title: "Do Something", options: [])],
                               intentIdentifiers: [], options: [])
    ])
    center.getNotificationSettings { s in
        Log.line("helper", "settings auth=\(s.authorizationStatus.rawValue) "
                 + "alertStyle=\(s.alertStyle.rawValue) alertSetting=\(s.alertSetting.rawValue)")
        if isStandalone {
            // Relaunched by the system to service a click: do not post anything,
            // just be a live, registered client and wait for the response.
            Log.line("helper", "standalone-but-allowed: registered as a client, waiting for "
                     + "usernoted to hand over the pending response")
            DispatchQueue.global().asyncAfter(deadline: .now() + 600) { exit(0) }
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { postAndDecide() }
        }
    }
}

Log.line("helper", "bundle=\(Bundle.main.bundleIdentifier ?? "nil") tag=\(tag) "
         + "os=\(ProcessInfo.processInfo.operatingSystemVersionString)")

center.getNotificationSettings { s in
    Log.line("helper", "initial authorizationStatus=\(s.authorizationStatus.rawValue) "
             + "(0=notDetermined 1=denied 2=authorized)")
    switch s.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
        begin()
    case .denied:
        Log.line("helper", "ABORT: notifications DENIED for this bundle id.")
        exit(2)
    default:
        Log.line("helper", "notDetermined — requesting authorization; PROMPT WILL APPEAR. "
                 + "Do NOT kill this process while the prompt is up.")
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, err in
            Log.line("helper", "authorization granted=\(granted) err=\(String(describing: err))")
            guard granted else { Log.line("helper", "ABORT: not granted"); exit(1) }
            begin()
        }
    }
}

app.run()
