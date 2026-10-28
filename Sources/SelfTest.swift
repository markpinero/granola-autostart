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

    print(failures == 0 ? "selftest ok" : "selftest: \(failures) failed")
    exit(failures == 0 ? 0 : 1)
}

final class FakeSignal: Signal {
    let name = "fake"
    var active = false
    func isActive(now: Date) -> Bool { active }
}
