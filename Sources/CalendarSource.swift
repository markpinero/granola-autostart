import EventKit
import Foundation

/// Events that may name a note: titled, not cancelled, not declined by Mark.
func nameable(status: EKEventStatus, title: String?, declined: Bool) -> Bool {
    status != .canceled && !(title ?? "").isEmpty && !declined
}

/// Maps an EKEvent to a match candidate, dropping events that must not name a note.
func candidate(from event: EKEvent) -> EventCandidate? {
    let declined = (event.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined }
    guard nameable(status: event.status, title: event.title, declined: declined),
          let start = event.startDate, let end = event.endDate
    else { return nil }
    return EventCandidate(
        id: event.eventIdentifier ?? "", title: event.title ?? "",
        start: start, end: end, isAllDay: event.isAllDay,
        text: "\(event.location ?? "") \(event.notes ?? "")")
}

/// Reads the system calendar store (needs the calendar account under Internet
/// Accounts plus a one-time Calendars permission grant). Until access is granted
/// every lookup returns nil and notes start untitled, as before.
final class CalendarSource {
    private let store = EKEventStore()
    private var access: EKAuthorizationStatus = .notDetermined

    init() {
        // Fire-and-forget: the prompt. Grants made later in System Settings are
        // picked up by the authorizationStatus check in currentEvent.
        store.requestFullAccessToEvents { ok, error in
            log(ok ? "calendar access granted" : "calendar access denied\(error.map { ": \($0.localizedDescription)" } ?? "")")
        }
    }

    func currentEvent(now: Date, platform: String?) -> EventCandidate? {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess && access != .fullAccess { store.reset() }  // store snapshot predates the grant
        access = status
        guard status == .fullAccess else { return nil }
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-300), end: now.addingTimeInterval(900), calendars: nil)
        return matchEvent(store.events(matching: predicate).compactMap { candidate(from: $0) }, now: now, platform: platform)
    }
}
