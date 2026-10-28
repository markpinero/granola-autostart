import Foundation

protocol Signal: AnyObject {
    var name: String { get }
    func isActive(now: Date) -> Bool
}

let deepLink = "granola://new-document?creation_source=autostart&auto_transcribe=1"

/// The deep link, optionally carrying the calendar event Granola titles the note from
/// (event.summary) and dedupes on (event.id + start).
func makeDeepLink(event: EventCandidate?) -> String {
    guard let event else { return deepLink }
    let iso = ISO8601DateFormatter().string(from: event.start)
    let json: [String: Any] = ["id": event.id, "summary": event.title, "start": ["dateTime": iso]]
    let body = (try? JSONSerialization.data(withJSONObject: json)).flatMap { String(data: $0, encoding: .utf8) }
    var comps = URLComponents()
    comps.scheme = "granola"
    comps.host = "new-document"
    comps.queryItems = [
        URLQueryItem(name: "creation_source", value: "autostart"),
        URLQueryItem(name: "auto_transcribe", value: "1"),
        URLQueryItem(name: "event", value: body),
    ]
    // URLSearchParams (Granola's parser) reads a literal + as a space.
    comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return comps.url?.absoluteString ?? deepLink
}
let logPath = NSString(string: "~/Library/Logs/granola-autostart.log").expandingTildeInPath

func log(_ line: String) {
    let entry = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(Data(entry.utf8)); try? h.close()
    } else {
        try? entry.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

func startGranolaNote(reason: Set<String>, dryRun: Bool, event: EventCandidate? = nil) {
    let why = reason.sorted().joined(separator: ",")
    if dryRun { log("would start (dry run) \(why)\(event.map { " \"\($0.title)\"" } ?? "")"); return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = [makeDeepLink(event: event)]
    do { try p.run(); log("start \(why)\(event.map { " \"\($0.title)\"" } ?? "")") } catch { log("start FAILED \(why): \(error)") }
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
