import Foundation

protocol Signal: AnyObject {
    var name: String { get }
    func isActive(now: Date) -> Bool
}

let deepLink = "granola://new-document?creation_source=autostart&auto_transcribe=1"
let logPath = NSString(string: "~/Library/Logs/granola-autostart.log").expandingTildeInPath

func log(_ line: String) {
    let entry = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(Data(entry.utf8)); try? h.close()
    } else {
        try? entry.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

func startGranolaNote(reason: Set<String>, dryRun: Bool) {
    let why = reason.sorted().joined(separator: ",")
    if dryRun { log("would start (dry run) \(why)"); return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = [deepLink]
    do { try p.run(); log("start \(why)") } catch { log("start FAILED \(why): \(error)") }
}

final class Loop {
    let signals: [Signal]
    var tracker = CallTracker()
    init(signals: [Signal]) { self.signals = signals }

    /// Returns the signals that caused a new note, or nil.
    func tick(now: Date) -> Set<String>? {
        let active = Set(signals.filter { $0.isActive(now: now) }.map(\.name))
        return tracker.update(signals: active, now: now) ? active : nil
    }
}
