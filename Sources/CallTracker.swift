import Foundation

/// Decides when a new Granola note should start. One note per call; a call
/// ends after `quietPeriod` seconds with no active signal.
// ponytail: back-to-back calls < quietPeriod apart share one note; per-signal tracking if that bites.
struct CallTracker {
    let quietPeriod: TimeInterval
    private(set) var inCall = false
    private var lastActive: Date?

    init(quietPeriod: TimeInterval = 120) { self.quietPeriod = quietPeriod }

    mutating func update(signals: Set<String>, now: Date) -> Bool {
        if signals.isEmpty {
            if inCall, let last = lastActive, now.timeIntervalSince(last) > quietPeriod { inCall = false }
            return false
        }
        lastActive = now
        if inCall { return false }
        inCall = true
        return true
    }
}
