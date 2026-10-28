import Foundation

let args = CommandLine.arguments
if args.contains("--selftest") { selfTest() }
let dryRun = args.contains("--dry-run")

let tokenPath = NSString(string: "~/.config/granola-autostart/token").expandingTildeInPath
let token = ((try? String(contentsOfFile: tokenPath, encoding: .utf8)) ?? "")
    .trimmingCharacters(in: .whitespacesAndNewlines)

var signals: [Signal] = [ZoomSignal(), MicSignal()]
if token.isEmpty {
    log("no token at \(tokenPath); Meet extension disabled (run build.sh)")
} else {
    do { signals.append(try MeetSignal(token: token)) } catch { log("meet listener: \(error)") }
}

let loop = Loop(signals: signals)
log("running\(dryRun ? " (dry run)" : "") with \(signals.map(\.name).joined(separator: ","))")
let calendar = CalendarSource()
let timer = Timer(timeInterval: 5, repeats: true) { _ in
    if let why = loop.tick(now: Date()) {
        let platform = why.contains("meet") ? "meet" : why.contains("zoom") ? "zoom" : nil
        startGranolaNote(reason: why, dryRun: dryRun, event: calendar.currentEvent(now: Date(), platform: platform))
    }
}
RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
