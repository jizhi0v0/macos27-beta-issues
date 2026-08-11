import Foundation

// Shared append-only logger.  Both processes write to the same file, so use a
// single O_APPEND write(2) per line — atomic for small writes, unlike
// FileHandle.seekToEndOfFile which races across processes.
enum Log {
    static let path = ("~/notifdemo.log" as NSString).expandingTildeInPath

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func line(_ who: String, _ s: String) {
        let msg = "\(fmt.string(from: Date())) [\(who) pid=\(getpid())] \(s)\n"
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        _ = msg.withCString { write(fd, $0, strlen($0)) }
        close(fd)
    }
}

@inline(__always) func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
@inline(__always) func msBetween(_ a: UInt64, _ b: UInt64) -> Double { Double(b &- a) / 1_000_000.0 }
