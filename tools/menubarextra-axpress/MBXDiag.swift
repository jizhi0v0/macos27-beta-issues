// MBXWindow plus a self-report: the status bar button's target/action and AX actions, 2 s after launch.
import SwiftUI
import AppKit

final class Diag: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            func walk(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(walk) }
            for w in NSApp.windows {
                for v in walk(w.contentView?.superview ?? w.contentView ?? NSView()) where String(describing: type(of: v)).contains("StatusBarButton") {
                    let b = v as! NSButton
                    print("window \(type(of: w)) button \(type(of: b))")
                    print("  target: \(b.target.map { String(describing: type(of: $0)) } ?? "nil")")
                    print("  action: \(b.action.map { NSStringFromSelector($0) } ?? "nil")")
                    print("  accessibilityActionNames: \(b.accessibilityActionNames())")
                }
            }
            fflush(stdout)
        }
    }
}

@main struct MBXDiagApp: App {
    @NSApplicationDelegateAdaptor(Diag.self) var diag
    var body: some Scene {
        MenuBarExtra("MBXWindow", systemImage: "star.circle") {
            Text("MBXWindow panel").padding(40)
        }
        .menuBarExtraStyle(.window)
    }
}
