// overlay-windows.swift — list on-screen windows that can occlude other UI without being seen.
//
//   swift tools/overlay-windows.swift              # transparent or above-normal-level windows
//   swift tools/overlay-windows.swift --all        # every on-screen window, front to back
//   swift tools/overlay-windows.swift --over NAME  # windows in front of NAME's windows that intersect them
//
// WindowServer decides occlusion by bounding box, not by alpha: Apple's NSWindow.OcclusionState
// docs say "a completely transparent window may also be considered visible". So an alpha-0
// floating panel still covers whatever is under its rectangle. That is how an invisible
// DuoPaste preview panel left the App Store payment sheet "occluded" (see
// issues/app-store-payment-sheet-occluded-by-invisible-window.md).
//
// Owner, layer, alpha and bounds need no permission. Window titles need Screen Recording, so
// the title column is usually empty; it is not needed.
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst()
let showAll = args.contains("--all")
var overName: String?
if let i = args.firstIndex(of: "--over"), args.index(after: i) < args.endIndex {
    overName = args[args.index(after: i)]
}

struct Win {
    let z: Int  // 0 = frontmost
    let owner: String
    let pid: Int
    let title: String
    let layer: Int
    let alpha: Double
    let rect: CGRect
}

// CGWindowListCopyWindowInfo with .optionOnScreenOnly returns windows front to back.
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
let wins: [Win] = info.enumerated().compactMap { z, w in
    guard let b = w[kCGWindowBounds as String] as? [String: Any],
          let rect = CGRect(dictionaryRepresentation: b as CFDictionary),
          rect.width > 1, rect.height > 1 else { return nil }
    return Win(z: z,
               owner: w[kCGWindowOwnerName as String] as? String ?? "?",
               pid: w[kCGWindowOwnerPID as String] as? Int ?? 0,
               title: w[kCGWindowName as String] as? String ?? "",
               layer: w[kCGWindowLayer as String] as? Int ?? 0,
               alpha: w[kCGWindowAlpha as String] as? Double ?? 1,
               rect: rect)
}

func flags(_ w: Win) -> String {
    var f: [String] = []
    if w.alpha < 0.05 { f.append("INVISIBLE") } else if w.alpha < 1 { f.append("translucent") }
    if w.layer > 0 { f.append("above-normal") }
    return f.joined(separator: ",")
}

func pad(_ s: String, _ n: Int) -> String {
    let t = String(s.prefix(n))
    return t + String(repeating: " ", count: n - t.count)
}

func row(_ w: Win, note: String = "") {
    let r = w.rect
    let geo = String(format: "%5.0f,%5.0f %5.0fx%-5.0f", r.minX, r.minY, r.width, r.height)
    let nums = String(format: "%6d  %5d  %4.2f", w.pid, w.layer, w.alpha)
    print(String(format: "%3d  ", w.z) + pad(w.owner, 28) + " " + nums + "  " + geo + "  "
          + pad(flags(w), 24) + " " + (note.isEmpty ? w.title : note))
}

func header() {
    print("  z  " + pad("owner", 28) + "    pid  layer  alpha  " + pad("x,y w×h (points)", 24)
          + pad("flags", 25) + "title / overlap")
}

if let name = overName {
    let targets = wins.filter { $0.owner.localizedCaseInsensitiveContains(name) }
    guard !targets.isEmpty else {
        print("no on-screen window owned by a process matching \"\(name)\"")
        print("owners on screen: " + Set(wins.map(\.owner)).sorted().joined(separator: ", "))
        exit(1)
    }
    header()
    for t in targets {
        row(t, note: "<- target")
        for w in wins where w.z < t.z && w.pid != t.pid {
            let hit = w.rect.intersection(t.rect)
            guard !hit.isNull, hit.width > 0, hit.height > 0 else { continue }
            let pct = 100 * hit.width * hit.height / (t.rect.width * t.rect.height)
            row(w, note: String(format: "covers %.0f%% of target", pct))
        }
    }
    exit(0)
}

header()
for w in wins where showAll || w.alpha < 0.05 || w.layer > 0 {
    row(w)
}
