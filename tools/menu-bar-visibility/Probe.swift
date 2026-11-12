import AppKit
import SwiftUI

// All AppKit variants share this implementation. Only the application lifecycle
// and the named DuoShot features vary; none writes NSStatusItem.isVisible.
@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var observation: NSKeyValueObservation?
    private var timer: Timer?
    private var samples = 0
    private var preflightResult: Bool?
    private let mode = Bundle.main.object(forInfoDictionaryKey: "ProbeMode") as! String
    private var directory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("menu-bar-visibility")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--preflight") {
            preflightResult = CGPreflightScreenCaptureAccess()
        }
        if CommandLine.arguments.contains("--edit-menu") {
            let edit = NSMenu(title: "Edit")
            edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            let editItem = NSMenuItem()
            editItem.submenu = edit
            let menu = NSMenu()
            menu.addItem(NSMenuItem())
            menu.addItem(editItem)
            NSApp.mainMenu = menu
        }
        #if !EXTRA
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = status
        if CommandLine.arguments.contains("--sharing-first") {
            // DuoShot touches the item's window before assigning its image/menu.
            status.button?.window?.sharingType = .readOnly
        }
        let earlyDrop = CommandLine.arguments.contains("--drop-first")
        if earlyDrop, let button = status.button {
            button.addSubview(DropView(frame: button.bounds))
        }
        status.button?.image = NSImage(systemSymbolName: "star.circle", accessibilityDescription: mode)
        status.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(withTitle: mode, action: nil, keyEquivalent: "")
        let quit = menu.addItem(withTitle: "Quit probe", action: #selector(quitProbe), keyEquivalent: "")
        quit.target = self
        status.menu = menu
        if !earlyDrop && (mode.contains("Drop") || mode.contains("Shot")) {
            if let button = status.button {
                button.addSubview(DropView(frame: button.bounds))
            }
        }
        if mode.contains("Sharing") || mode.contains("Shot") {
            status.button?.window?.sharingType = .readOnly
        }
        if mode.contains("Shot") { status.button?.title = " CLI" }
        observation = status.observe(\.isVisible, options: [.old, .new]) { _, change in
            MainActor.assumeIsolated {
                self.write("visibility", extra: ["old": change.oldValue ?? false, "new": change.newValue ?? false])
            }
        }
        if CommandLine.arguments.contains("--cycle-sharing") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                status.button?.window?.sharingType = .none
                self.write("sharing-none")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                status.button?.window?.sharingType = .readOnly
                self.write("sharing-readOnly")
            }
        }
        #endif
        write("launch")
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.samples += 1
                self.write("sample")
            }
        }
    }

    private func write(_ event: String, extra: [String: Any] = [:]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var state: [String: Any] = [
            "event": event, "timestamp": ISO8601DateFormatter().string(from: Date()),
            "uptime": ProcessInfo.processInfo.systemUptime,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "bundleID": Bundle.main.bundleIdentifier!, "mode": mode,
            "applicationClass": NSStringFromClass(type(of: NSApp!)), "samples": samples,
            "arguments": Array(CommandLine.arguments.dropFirst()),
        ]
        if let preflightResult { state["screenCapturePreflight"] = preflightResult }
        if let item {
            state["isVisible"] = item.isVisible
            state["autosaveName"] = item.autosaveName ?? "nil"
            state["behavior"] = item.behavior.rawValue
            state["buttonClass"] = item.button.map { NSStringFromClass(type(of: $0)) }
            state["subviews"] = item.button?.subviews.map { NSStringFromClass(type(of: $0)) }
            if let window = item.button?.window {
                state["windowNumber"] = window.windowNumber
                state["windowIsVisible"] = window.isVisible
                state["sharingType"] = window.sharingType.rawValue
                state["frame"] = NSStringFromRect(window.frame)
            }
        }
        state.merge(extra) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent("\(mode).json"), options: .atomic)
        // Preserve transitions; polling state is available separately without an unbounded log.
        if event != "sample" {
            let path = directory.appendingPathComponent("\(mode).jsonl")
            if !FileManager.default.fileExists(atPath: path.path) {
                FileManager.default.createFile(atPath: path.path, contents: nil)
            }
            if let file = try? FileHandle(forWritingTo: path) {
                _ = try? file.seekToEnd()
                try? file.write(contentsOf: data + Data([10]))
                try? file.close()
            }
        }
    }

    @objc private func quitProbe() { NSApp.terminate(nil) }
}

// Matches DuoShot's hit-testable, constrained drag destination, including mouse forwarding.
final class DropView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let superview else { return }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            topAnchor.constraint(equalTo: superview.topAnchor),
            bottomAnchor.constraint(equalTo: superview.bottomAnchor),
        ])
    }
    override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
}

#if COCOA
@main enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#else
@main struct ProbeApp: App {
    @NSApplicationDelegateAdaptor(ProbeDelegate.self) var delegate
    var body: some Scene {
        #if EXTRA
        MenuBarExtra("MBHExtra", systemImage: "star.circle") { Text("MBHExtra").padding(30) }
            .menuBarExtraStyle(.window)
        #else
        // Matches DuoPaste: SwiftUI lifecycle, AppKit status item, no inserted SwiftUI item.
        MenuBarExtra("unused", isInserted: .constant(false)) { EmptyView() }
        #endif
    }
}
#endif
