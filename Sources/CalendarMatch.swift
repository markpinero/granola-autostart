import Foundation

/// A calendar event reduced to what call matching needs.
struct EventCandidate: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let text: String  // location + notes: where video-call links live
}

/// Picks the event a call starting now most likely belongs to: events overlapping
/// [now-300s, now+900s], all-day ones skipped; events whose text carries a link
/// for the trigger platform win over later starts; otherwise the latest start wins.
func matchEvent(_ candidates: [EventCandidate], now: Date, platform: String?) -> EventCandidate? {
    let windowStart = now.addingTimeInterval(-300)
    let windowEnd = now.addingTimeInterval(900)
    let live = candidates.filter {
        !$0.isAllDay
            // ponytail: 12h cap keeps multi-day timed blocks ("On call" weeks) from titling every call
            && $0.end.timeIntervalSince($0.start) < 12 * 3600
            && $0.start <= windowEnd && $0.end >= windowStart
    }
    let needle = platform == "meet" ? "meet.google.com" : platform == "zoom" ? "zoom.us" : nil
    let linked = needle.map { n in live.filter { $0.text.contains(n) } } ?? []
    return (linked.isEmpty ? live : linked).max { $0.start < $1.start }
}
