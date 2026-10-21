import Cocoa
// AXPress a status item 3 times, then one synthetic click as the control.
// Success = a new on-screen window of that process, never the AX return code.
// usage: axpress-probe <pid> [owner-name-to-allow-clicking-under, e.g. MenuBarAgent]
setvbuf(stdout, nil, _IONBF, 0)
func attr(_ e: AXUIElement, _ n: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil }
let pid = pid_t(CommandLine.arguments[1])!
let allowUnder = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "\u{0}"
let own = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
func wins() -> [Int: String] {
    var r: [Int: String] = [:]
    for w in CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]] where (w[kCGWindowOwnerPID as String] as? pid_t) == pid {
        let b = w[kCGWindowBounds as String] as! [String: CGFloat]
        r[w[kCGWindowNumber as String] as! Int] = "layer \(w[kCGWindowLayer as String]!) \(Int(b["Width"]!))x\(Int(b["Height"]!))"
    }
    return r
}
func newWins(_ base: [Int: String]) -> [String] { wins().filter { base[$0.key] == nil }.map { "#\($0.key) \($0.value)" }.sorted() }
func wait(_ base: [Int: String], _ s: Double) -> (Double, [String])? {
    let t0 = Date(); while Date().timeIntervalSince(t0) < s { let n = newWins(base); if !n.isEmpty { return (Date().timeIntervalSince(t0), n) }; usleep(50_000) }; return nil
}
func escape() { let src = CGEventSource(stateID: .hidSystemState); for d in [true, false] { CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: d)?.post(tap: .cghidEventTap) } }
// macOS 27 overflow button, if this system has one.
func overflow() -> AXUIElement? {
    guard let agent = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "MenuBarAgent" }),
          let bar = attr(AXUIElementCreateApplication(agent.processIdentifier), "AXExtrasMenuBar") else { return nil }
    return (attr(bar as! AXUIElement, "AXChildren") as? [AXUIElement] ?? []).first { (attr($0, "AXIdentifier") as? String ?? "").hasPrefix("menu-bar-overflow-indicator") }
}
var weExpanded = false
func item() -> AXUIElement? {
    func find() -> AXUIElement? { (attr(AXUIElementCreateApplication(pid), "AXExtrasMenuBar") as! AXUIElement?).flatMap { (attr($0, "AXChildren") as? [AXUIElement])?.first } }
    if let i = find() { return i }
    guard let o = overflow(), attr(o, "AXIdentifier") as? String == "menu-bar-overflow-indicator" else { return nil }
    _ = AXUIElementPerformAction(o, kAXPressAction as CFString); weExpanded = true; usleep(1_000_000)
    return find()
}
func frame(_ e: AXUIElement) -> CGRect { var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(attr(e, "AXPosition") as! AXValue, .cgPoint, &pt); AXValueGetValue(attr(e, "AXSize") as! AXValue, .cgSize, &sz); return CGRect(origin: pt, size: sz) }
func close(_ base: [Int: String]) {
    if newWins(base).isEmpty { return }
    if let i = item() { _ = AXUIElementPerformAction(i, kAXPressAction as CFString); usleep(800_000) }
    if newWins(base).isEmpty { print("   closed by AXPress"); return }
    escape(); usleep(800_000); print("   " + (newWins(base).isEmpty ? "closed by Escape" : "STILL OPEN \(newWins(base))"))
}
func topAt(_ c: CGPoint) -> String {
    for w in CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]] {
        let b = w[kCGWindowBounds as String] as! [String: CGFloat]
        if CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!).contains(c) { return "\(w[kCGWindowOwnerName as String] ?? "?")" } }
    return "nothing"
}
print("\(own) pid \(pid), trusted \(AXIsProcessTrusted())")
for n in 1...3 {
    guard let i = item() else { print(" #\(n): icon not in the AX tree"); continue }
    let base = wins()
    let r = AXUIElementPerformAction(i, kAXPressAction as CFString)
    if let (t, w) = wait(base, 3) { print(" AXPress #\(n) at \(frame(i).origin): result \(r.rawValue), opened after \(String(format: "%.2f", t)) s: \(w)"); close(base) }
    else { print(" AXPress #\(n) at \(frame(i).origin): result \(r.rawValue), nothing within 3 s") }
    usleep(500_000)
}
if let i = item() {
    let f = frame(i), c = CGPoint(x: f.midX, y: f.midY), top = topAt(c)
    if ["Window Server", "Control Center", own, allowUnder].contains(where: { top.hasPrefix($0) }) {
        let base = wins(), old = CGEvent(source: nil)!.location, src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(60_000)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(100_000); CGWarpMouseCursorPosition(old)
        if let (t, w) = wait(base, 3) { print(" click (topmost \(top)): opened after \(String(format: "%.2f", t)) s: \(w)"); close(base) }
        else { print(" click (topmost \(top)): nothing within 3 s") }
    } else { print(" click REFUSED at \(c): topmost is \(top)") }
}
if weExpanded, let o = overflow(), attr(o, "AXIdentifier") as? String == "menu-bar-overflow-indicator-expanded" { _ = AXUIElementPerformAction(o, kAXPressAction as CFString); print(" overflow collapsed") }
