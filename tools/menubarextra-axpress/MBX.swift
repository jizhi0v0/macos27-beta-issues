// Minimal menu-bar apps for testing AXPress on a status item.
// -D MBX_WINDOW: SwiftUI MenuBarExtra, .window style (DuoUpdater's shape)
// -D MBX_MENU:   SwiftUI MenuBarExtra, .menu style
// -D MBX_APPKIT: AppKit NSStatusItem + NSPopover
import SwiftUI
import AppKit

#if MBX_APPKIT
final class Delegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    let popover = NSPopover()
    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "star.circle", accessibilityDescription: "MBXAppKit")
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.contentViewController = NSHostingController(rootView: Text("MBXAppKit panel").padding(40))
        popover.behavior = .transient
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let b = item.button { popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }
}
@main enum Main {
    static func main() {
        let app = NSApplication.shared
        let d = Delegate(); app.delegate = d
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
#else
@main struct MBXApp: App {
    var body: some Scene {
        #if MBX_WINDOW
        MenuBarExtra("MBXWindow", systemImage: "star.circle") {
            Text("MBXWindow panel").padding(40)
        }
        .menuBarExtraStyle(.window)
        #else
        MenuBarExtra("MBXMenu", systemImage: "star.circle") {
            Button("First item") {}
            Button("Second item") {}
        }
        .menuBarExtraStyle(.menu)
        #endif
    }
}
#endif
