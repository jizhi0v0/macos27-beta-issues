import Foundation
import AppKit

// NotifDemo — the tiny "browser". It does nothing except launch its alerts
// helper as a separate process with the --from-parent marker, exactly the way
// Chrome launches Google Chrome Helper (Alerts).app, then gets out of the way.

let argv = Array(CommandLine.arguments.dropFirst())
Log.line("parent", "launched argv=\(argv)")

let helperURL = URL(fileURLWithPath:
    ("~/Applications/NotifDemoHelper.app" as NSString).expandingTildeInPath)

let cfg = NSWorkspace.OpenConfiguration()
cfg.arguments = ["--from-parent"] + argv
cfg.createsNewApplicationInstance = true
cfg.activates = false

Log.line("parent", "launching helper at \(helperURL.path) args=\(cfg.arguments)")
NSWorkspace.shared.openApplication(at: helperURL, configuration: cfg) { runningApp, err in
    if let err {
        Log.line("parent", "helper launch FAILED: \(err)")
    } else {
        Log.line("parent", "helper launched pid=\(runningApp?.processIdentifier ?? -1)")
    }
    // Parent's job is done. Chrome would stay alive; for the demo it just leaves,
    // which also lets `open` relaunch it cleanly for the next trial.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
