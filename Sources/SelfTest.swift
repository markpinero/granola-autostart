import EventKit
import Foundation

nonisolated(unsafe) var failures = 0

func check(_ cond: Bool, _ msg: String) {
    if !cond { failures += 1; print("FAIL: \(msg)") }
}

func selfTest() -> Never {
    var t = CallTracker()
    let t0 = Date(timeIntervalSince1970: 0)
    check(!t.update(signals: [], now: t0), "idle stays idle")
    check(t.update(signals: ["zoom"], now: t0), "first signal starts")
    check(!t.update(signals: ["zoom", "mic"], now: t0 + 5), "second signal same call: no start")
    check(!t.update(signals: [], now: t0 + 60), "short gap: still in call")
    check(!t.update(signals: ["meet"], now: t0 + 100), "gap < 120s reuses note")
    check(!t.update(signals: [], now: t0 + 105), "call quiet begins")
    check(!t.update(signals: [], now: t0 + 224), "119s quiet: not ended")
    check(!t.update(signals: [], now: t0 + 226), "121s quiet: ended")
    check(t.update(signals: ["zoom"], now: t0 + 230), "next call starts new note")

    let fake = FakeSignal()
    let loop = Loop(signals: [fake])
    check(loop.tick(now: t0) == nil, "loop idle: no start")
    fake.active = true
    check(loop.tick(now: t0 + 5) == ["fake"], "loop starts once")
    check(loop.tick(now: t0 + 10) == nil, "loop no repeat while active")

    check(MicSignal.matches(bundleID: "us.zoom.xos", allowed: MicSignal.defaultAllowed), "zoom mic counts")
    check(!MicSignal.matches(bundleID: "com.granola.app", allowed: MicSignal.defaultAllowed), "granola mic ignored")
    check(!MicSignal.matches(bundleID: "com.apple.VoiceMemos", allowed: MicSignal.defaultAllowed), "voice memos ignored")
    check(MicSignal.matches(bundleID: "com.google.Chrome.helper", allowed: MicSignal.defaultAllowed), "chrome helper counts")


    let ok = "POST /meet HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Autostart-Token: abc\r\n\r\n"
    check(MeetSignal.authorized(requestHead: ok, token: "abc"), "valid token accepted")
    check(!MeetSignal.authorized(requestHead: ok.replacingOccurrences(of: "abc", with: "zzz"), token: "abc"), "bad token rejected")
    check(!MeetSignal.authorized(requestHead: "POST /meet HTTP/1.1\r\n\r\n", token: "abc"), "missing token rejected")
    check(!MeetSignal.authorized(requestHead: ok.replacingOccurrences(of: "POST", with: "GET"), token: "abc"), "GET rejected")
    check(!MeetSignal.authorized(requestHead: ok, token: ""), "empty token never authorizes")

    // Calendar naming: matchEvent picks the event a call most likely belongs to.
    func c(id: String, startMins: Double, endMins: Double) -> EventCandidate {
        EventCandidate(id: id, title: id, start: t0 + startMins * 60, end: t0 + endMins * 60, isAllDay: false, text: "")
    }
    check(matchEvent([], now: t0, platform: nil) == nil, "no candidates: nil")
    check(matchEvent([EventCandidate(id: "a", title: "On call", start: t0 - 86400, end: t0 + 86400, isAllDay: true, text: "")], now: t0, platform: nil) == nil, "all-day skipped")
    check(matchEvent([c(id: "b", startMins: -10, endMins: 20)], now: t0, platform: nil)?.id == "b", "overlapping event matched")
    check(matchEvent([c(id: "c", startMins: -30, endMins: -6)], now: t0, platform: nil) == nil, "ended 6 min ago: no")
    check(matchEvent([c(id: "d", startMins: -30, endMins: -4)], now: t0, platform: nil)?.id == "d", "ended 4 min ago: yes")
    check(matchEvent([c(id: "e", startMins: 14, endMins: 40)], now: t0, platform: nil)?.id == "e", "starts in 14 min: yes")
    check(matchEvent([c(id: "f", startMins: 16, endMins: 40)], now: t0, platform: nil) == nil, "starts in 16 min: no")
    let early = c(id: "g", startMins: -10, endMins: 20)
    let withLink = EventCandidate(id: "h", title: "Standup", start: t0 - 3600, end: t0 + 600, isAllDay: false, text: "https://meet.google.com/abc")
    check(matchEvent([early, withLink], now: t0, platform: "meet")?.id == "h", "meet link preferred over later start")
    check(matchEvent([early, withLink], now: t0, platform: "zoom")?.id == "g", "platform link for other platform ignored")
    check(matchEvent([c(id: "i", startMins: -10, endMins: 20), c(id: "j", startMins: -2, endMins: 20)], now: t0, platform: nil)?.id == "j", "no link: latest start wins")
    check(matchEvent([c(id: "k", startMins: -4320, endMins: 4320)], now: t0, platform: nil) == nil, "3-day timed block skipped")

    // Deep link carries the event JSON Granola titles notes from.
    check(makeDeepLink(event: nil) == deepLink, "no event: link unchanged")
    let tricky = EventCandidate(id: "x1", title: "Q3 + C++ \"planning\" ✅", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1800), isAllDay: false, text: "")
    let url = URL(string: makeDeepLink(event: tricky))!
    let evJSON = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "event" })?.value
    let dict = evJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
    check(dict?["summary"] as? String == "Q3 + C++ \"planning\" ✅", "title survives URL+JSON round-trip")
    check(makeDeepLink(event: tricky).contains("+") == false, "plus encoded (URLSearchParams would read it as space)")
    check(dict?["id"] as? String == "x1", "event id present")
    check((dict?["start"] as? [String: Any])?["dateTime"] as? String == "1970-01-01T00:00:00Z", "start is ISO8601")
    check(makeDeepLink(event: nil).contains("auto_transcribe=1"), "auto_transcribe kept")

    // Calendar source: EKEvent mapping (store init does not prompt).
    let ekStore = EKEventStore()
    let ev = EKEvent(eventStore: ekStore)
    ev.title = "Sync"
    ev.startDate = Date(timeIntervalSince1970: -600)
    ev.endDate = Date(timeIntervalSince1970: 600)
    check(candidate(from: ev)?.title == "Sync", "EKEvent maps to candidate")
    check(!nameable(status: .canceled, title: "Sync", declined: false), "cancelled event dropped")
    check(!nameable(status: .confirmed, title: "Sync", declined: true), "declined event dropped")
    check(!nameable(status: .confirmed, title: nil, declined: false), "untitled event dropped")

    print(failures == 0 ? "selftest ok" : "selftest: \(failures) failed")
    exit(failures == 0 ? 0 : 1)
}

final class FakeSignal: Signal {
    let name = "fake"
    var active = false
    func isActive(now: Date) -> Bool { active }
}
