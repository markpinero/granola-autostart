# Name Notes From Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-started Granola notes get the calendar event's name as their title.

**Architecture:** When a call starts, the app queries EventKit for events overlapping now, a pure matcher picks the best one, and the deep link gains an `event` JSON param (Granola titles the note from `event.summary` and reuses the note when the same event id + start reappears). No event → deep link unchanged.

**Tech Stack:** Swift via `swiftc` (no dependencies), EventKit, existing selftest harness.

**Spec:** `docs/superpowers/specs/2026-10-28-name-note-from-calendar-design.md`

## Global Constraints

- macOS 27; no third-party dependencies; build stays one `swiftc` command in `build.sh`.
- Deep link base, exactly: `granola://new-document?creation_source=autostart&auto_transcribe=1` (+ `&event=` when matched), opened via `/usr/bin/open`.
- Existing behavior when no event matches is byte-identical to today.
- Selftest (`--selftest`) must not trigger any TCC permission prompt — it tests pure logic and EKEvent mapping only, never `requestAccess`.
- Log format unchanged except the matched title appended: `start meet,mic "Q3 planning"` (no match: `start meet,mic`).
- No commits unless Mark asks.

## Review Focus

1. All-day / multi-day events ("On call" week) must not title every note → `isAllDay` skip. Test in Task 1.
2. Titles containing `&`, quotes, emoji must survive URL + JSON encoding → round-trip test in Task 2.
3. Window edges: a meeting that ended 4 min ago still titles the note (late call), one that ended 6 min ago doesn't; a meeting starting in 14 min matches, in 16 min doesn't. Tests in Task 1.
4. Cancelled events and events Mark declined must not name the note. Test in Task 3.
5. Calendar permission denied / not yet granted / no accounts: note still starts untitled, no crash, no repeated prompts. `granted` gate in Task 3, dry-run check.

---

### Task 1: Pure event matcher

**Files:**
- Create: `Sources/CalendarMatch.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `struct EventCandidate: Equatable { let id: String; let title: String; let start: Date; let end: Date; let isAllDay: Bool; let text: String }` (`text` = location + notes, the video-link search space) and `func matchEvent(_ candidates: [EventCandidate], now: Date, platform: String?) -> EventCandidate?`. Consumed by Tasks 2 and 3.

- [ ] **Step 1: Write failing selftest checks**

Append to `selfTest()` in `Sources/SelfTest.swift` (t0 = `Date(timeIntervalSince1970: 0)`; helper `c(id:startMins:endMins:)` builds a non-all-day candidate with empty `text`):

```swift
check(matchEvent([], now: t0, platform: nil) == nil, "no candidates: nil")
check(matchEvent([EventCandidate(id: "a", title: "On call", start: t0 - 86400, end: t0 + 86400, isAllDay: true, text: "")], now: t0, platform: nil) == nil, "all-day skipped")
check(matchEvent([c(id: "b", startMins: -10, endMins: 20)], now: t0, platform: nil)?.id == "b", "overlapping event matched")
check(matchEvent([c(id: "c", startMins: -30, endMins: -6)], now: t0, platform: nil) == nil, "ended 6 min ago: no")
check(matchEvent([c(id: "d", startMins: -30, endMins: -4)], now: t0, platform: nil)?.id == "d", "ended 4 min ago: yes")
check(matchEvent([c(id: "e", startMins: 14, endMins: 40)], now: t0, platform: nil)?.id == "e", "starts in 14 min: yes")
check(matchEvent([c(id: "f", startMins: 16, endMins: 40)], now: t0, platform: nil) == nil, "starts in 16 min: no")
let early = c(id: "g", startMins: -10, endMins: 20)
let withLink = EventCandidate(id: "h", title: "Standup", start: t0 - 60, end: t0 + 600, isAllDay: false, text: "https://meet.google.com/abc")
check(matchEvent([early, withLink], now: t0, platform: "meet")?.id == "h", "meet link preferred over later start")
check(matchEvent([early, withLink], now: t0, platform: "zoom")?.id == "g", "platform link for other platform ignored")
check(matchEvent([c(id: "i", startMins: -10, endMins: 20), c(id: "j", startMins: -2, endMins: 20)], now: t0, platform: nil)?.id == "j", "no link: latest start wins")
```

- [ ] **Step 2: Run to verify failure**

Run: `swiftc -O Sources/*.swift -o /tmp/ga && /tmp/ga --selftest`
Expected: FAIL — `matchEvent`/`EventCandidate` undefined.

- [ ] **Step 3: Implement in `Sources/CalendarMatch.swift`**

Window: `[now-300, now+900]` s; overlap = `start <= windowEnd && end >= windowStart`; skip `isAllDay`. Preferred tier: candidates whose `text` contains `meet.google.com` when platform is `"meet"`, `zoom.us` when `"zoom"`; if the preferred tier is non-empty pick from it, else from all. Within the tier, latest `start` wins.

- [ ] **Step 4: Run selftest**

Run: `swiftc -O Sources/*.swift -o /tmp/ga && /tmp/ga --selftest`
Expected: `selftest ok`

### Task 2: Deep link with event param

**Files:**
- Modify: `Sources/Launcher.swift`, `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `EventCandidate` (Task 1).
- Produces: `func makeDeepLink(event: EventCandidate?) -> String` replacing direct uses of the `deepLink` constant (which stays as the nil-case value).

- [ ] **Step 1: Write failing selftest checks**

```swift
check(makeDeepLink(event: nil) == deepLink, "no event: link unchanged")
let tricky = EventCandidate(id: "x1", title: "Q3 & \"planning\" ✅", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1800), isAllDay: false, text: "")
let url = URL(string: makeDeepLink(event: tricky))!
let evJSON = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "event" })?.value
let dict = evJSON.flatMap { JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
check(dict?["summary"] as? String == "Q3 & \"planning\" ✅", "title survives URL+JSON round-trip")
check(dict?["id"] as? String == "x1", "event id present")
check((dict?["start"] as? [String: Any])?["dateTime"] as? String == "1970-01-01T00:00:00Z", "start is ISO8601")
check(makeDeepLink(event: nil).contains("auto_transcribe=1"), "auto_transcribe kept")
```

- [ ] **Step 2: Run to verify failure**

Run: `swiftc -O Sources/*.swift -o /tmp/ga && /tmp/ga --selftest`
Expected: FAIL — `makeDeepLink` undefined.

- [ ] **Step 3: Implement `makeDeepLink(event:)` in `Sources/Launcher.swift`**

Build with `URLComponents` (scheme `granola`, host `new-document`, query items `creation_source`, `auto_transcribe`, and `event` = `JSONSerialization` of `{"id": id, "summary": title, "start": {"dateTime": iso}}`, ISO via `ISO8601DateFormatter` with `.withInternetDateTime`). Route `startGranolaNote` through it.

- [ ] **Step 4: Run selftest**

Run: `swiftc -O Sources/*.swift -o /tmp/ga && /tmp/ga --selftest`
Expected: `selftest ok`

### Task 3: EventKit source and wiring

**Files:**
- Create: `Sources/CalendarSource.swift`
- Modify: `Sources/main.swift`, `Sources/Launcher.swift`, `Sources/SelfTest.swift`, `Info.plist`, `README.md`

**Interfaces:**
- Consumes: `matchEvent` / `EventCandidate` (Task 1), `makeDeepLink` (Task 2).
- Produces: `final class CalendarSource { init(); func currentEvent(now: Date, platform: String?) -> EventCandidate? }` and `startGranolaNote(reason: Set<String>, dryRun: Bool, calendar: CalendarSource)`.

- [ ] **Step 1: Write failing selftest check (EKEvent mapping)**

```swift
let store = EKEventStore() // init does not prompt
let ev = EKEvent(eventStore: store); ev.eventIdentifier = "z1"; ev.title = "Sync"; ev.startDate = Date(timeIntervalSince1970: -600); ev.endDate = Date(timeIntervalSince1970: 600)
check(candidate(from: ev)?.id == "z1", "EKEvent maps to candidate")
ev.status = .canceled
check(candidate(from: ev) == nil, "cancelled event dropped")
```
(Constructing a declined attendee for the last check is fiddly; implement the `.declined` drop in the same function and cover it in the live check instead.)

- [ ] **Step 2: Run to verify failure**

Run: `swiftc -O Sources/*.swift -o /tmp/ga && /tmp/ga --selftest`
Expected: FAIL — `candidate(from:)` undefined.

- [ ] **Step 3: Implement**

`Sources/CalendarSource.swift`:
- `candidate(from: EKEvent) -> EventCandidate?` (pure; nil for `.canceled` status or own attendee `.declined`; `text` = `location + " " + notes`).
- `CalendarSource`: `EKEventStore()`, `requestAccess(to: .event)` fired once in `init` (result only flips a private `granted` flag; completion runs later — until then `granted` is false, calls return nil). `currentEvent` returns nil unless `granted`; otherwise `store.events(matching: store.predicateForEvents(withStart: now-300, end: now+900))`, map via `candidate(from:)`, delegate to `matchEvent`.

`Sources/main.swift`: construct `CalendarSource()` at startup, log calendar granted/denied when the request completes, pass it to `startGranolaNote`. Platform: `"meet"` if triggers contain `meet`, else `"zoom"` if `zoom`, else nil.

`Sources/Launcher.swift`: `startGranolaNote` takes the source, resolves the event, calls `makeDeepLink(event:)`, logs `start <reasons>` or `start <reasons> "<title>"`.

`Info.plist`: add `NSCalendarsUsageDescription` → `Names auto-started Granola notes after the meeting in your calendar.`

`README.md`: one line under the trigger table noting calendar naming + the Internet Accounts prerequisite.

- [ ] **Step 4: Build, selftest, dry-run**

Run: `./build.sh && ./build/granola-autostart --selftest && ./build/granola-autostart --dry-run` (let it run a few seconds, Ctrl-C)
Expected: `selftest ok`; dry-run logs `running (dry run) …`; no crash before/after granting permission.

- [ ] **Step 5: Live check with Mark**

Prereq (Mark, once): System Settings → Internet Accounts → Google → Calendars on. Then `./install.sh`, create a calendar event titled "Autostart test" 5 min ago→+30 min with any link in location, join a Meet/Zoom call, accept the Calendars prompt, verify the Granola note is titled "Autostart test" and the log shows `start … "Autostart test"`. Decline-test: mark the event declined, rejoin after quiet period → untitled note.
