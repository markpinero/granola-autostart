# Granola Auto-start Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start a Granola transcription for every call (Zoom, Meet, Teams, Slack, FaceTime, calendar meetings), including muted joins, with one note per call.

**Architecture:** One Swift background program (`granola-autostart`) launched at login by a LaunchAgent. Every 5 s it collects the set of active "call signals" from four sources (calendar, Zoom helper process, Meet extension heartbeat, mic users) and passes them to a pure `CallTracker` that decides whether to open the Granola deep link. A tiny unpacked Chrome MV3 extension posts heartbeats to the program over localhost.

**Tech Stack:** Swift 6 via `swiftc` (no SwiftPM, no dependencies), EventKit, CoreAudio, Network.framework, launchd, Chrome MV3.

**Spec:** the approved design in this session, copied into `docs/design.md` (Task 1).

## Global Constraints

- macOS 27 (this Mac); CoreAudio process-object APIs need macOS 14+.
- No third-party dependencies. Build with one `swiftc` command in `build.sh`.
- Deep link, exactly: `granola://new-document?creation_source=autostart&auto_transcribe=1`, opened via `/usr/bin/open`.
- Granola's own chat message and watermark are untouched; nothing posts to a meeting.
- Bias: a missed call is worse than an extra note. When in doubt, start.
- Quiet period: a call ends after **120 s** with no active signal.
- Log every start (timestamp + triggering signals) to `~/Library/Logs/granola-autostart.log`.
- No commits unless Mark asks.

## Review Focus

1. Muted join on Zoom (computer audio muted, or no audio at all) must still start via the Zoom signal, not the mic signal. Covered by manual check in Task 6.
2. Muted Meet join must still start via the extension heartbeat. Covered by manual check in Task 6.
3. Granola's own mic use must never count as a call (it holds the mic while transcribing, which would keep a call "alive" forever). `CallTracker` never sees it; `MicSignal` excludes `com.granola.app`. Test in Task 3.
4. A web page must not be able to trigger a note via the localhost port. Server requires a per-install token header; test in Task 4.
5. Back-to-back calls with < 120 s gap share one note. Accepted ceiling; logged, not fixed. Test pins it in Task 1.

---

### Task 0: Prerequisite checks (with Mark watching)

No code. Results go into `docs/design.md`.

- [ ] **Step 1:** With Granola open and signed in, run `open "granola://new-document?creation_source=autostart&auto_transcribe=1"`. Expected: a new note opens and transcription starts. If not, stop and report; the whole plan depends on it.
- [ ] **Step 2:** Start a short Zoom test meeting (Zoom's "New meeting" alone), trigger the link, leave the meeting. Record whether Granola stops transcribing on its own, and after how long.
- [ ] **Step 3:** In that test call, mute, then run `ps -axo comm | grep -i cpthost` while in the meeting and after leaving. Expected: present in-call, absent after. Record the exact process name.

### Task 1: Project skeleton and call tracker

**Files:**
- Create: `docs/design.md` (approved design + Task 0 findings)
- Create: `Sources/CallTracker.swift`
- Create: `Sources/main.swift` (entry; `--selftest` runs tests)
- Create: `Sources/SelfTest.swift`
- Create: `build.sh`

**Interfaces:**
- Produces: `struct CallTracker { init(quietPeriod: TimeInterval = 120); mutating func update(signals: Set<String>, now: Date) -> Bool }` — returns `true` exactly when a new note should start.
- Produces: `func check(_ cond: Bool, _ msg: String)` helper in SelfTest.swift; `selfTest()` exits 1 on any failure.

- [ ] **Step 1: Write failing tests in `SelfTest.swift`**

```swift
var t = CallTracker()
let t0 = Date(timeIntervalSince1970: 0)
check(!t.update(signals: [], now: t0), "idle stays idle")
check(t.update(signals: ["zoom"], now: t0), "first signal starts")
check(!t.update(signals: ["zoom", "mic"], now: t0 + 5), "second signal same call: no start")
check(!t.update(signals: [], now: t0 + 60), "short gap: still in call")
check(!t.update(signals: ["meet"], now: t0 + 100), "gap < 120s reuses note")   // Review Focus 5
check(!t.update(signals: [], now: t0 + 105), "call quiet begins")
check(!t.update(signals: [], now: t0 + 224), "119s quiet: not ended")
check(!t.update(signals: [], now: t0 + 226), "121s quiet: ended")
check(t.update(signals: ["calendar"], now: t0 + 230), "next call starts new note")
```

- [ ] **Step 2:** `./build.sh && ./build/granola-autostart --selftest` → fails to compile (no `CallTracker`).
- [ ] **Step 3:** Implement `CallTracker` (fields: `inCall: Bool`, `lastActive: Date?`). `build.sh`: `swiftc -O Sources/*.swift -o build/granola-autostart -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist` (Info.plist added in Task 3; create a minimal one now with `CFBundleIdentifier = com.markpinero.granola-autostart`).
- [ ] **Step 4:** Re-run → prints `selftest ok`, exit 0.

### Task 2: Launcher and main loop

**Files:**
- Create: `Sources/Launcher.swift`
- Modify: `Sources/main.swift`

**Interfaces:**
- Consumes: `CallTracker.update`.
- Produces: `protocol Signal { var name: String { get }; func isActive(now: Date) -> Bool }`; `func startGranolaNote(reason: Set<String>)` (runs `/usr/bin/open <deep link>`, appends `ISO8601 start <sorted signals>` to the log).
- `main.swift` with no args: builds `[Signal]`, then a 5 s `Timer` on the main RunLoop: `active = signals.filter { $0.isActive(now:) }.map(\.name)`; if `tracker.update` → `startGranolaNote`. `--dry-run` flag logs instead of opening.

- [ ] **Step 1:** Add a `FakeSignal` in SelfTest and assert the loop body (extracted as `func tick(now:) -> Set<String>?`, returns the signals that caused a start or nil) returns `["fake"]` once, then nil while still active.
- [ ] **Step 2:** Run selftest → fails; implement; run → passes.

### Task 3: Zoom, mic and calendar signals

**Files:**
- Create: `Sources/ZoomSignal.swift`, `Sources/MicSignal.swift`, `Sources/CalendarSignal.swift`
- Modify: `Info.plist` (add `NSCalendarsFullAccessUsageDescription` = "Starts a Granola note when a meeting with a call link begins.")

**Interfaces:**
- Produces: `ZoomSignal` (name `"zoom"`): active iff a process whose name equals the one recorded in Task 0 Step 3 (expected `CptHost`) exists; use `sysctl(KERN_PROC_ALL)` or `proc_listallpids` + `proc_name`, not a shelled `pgrep`.
- Produces: `MicSignal(allowed: Set<String>)` (name `"mic"`): active iff any CoreAudio process object (`kAudioHardwarePropertyProcessObjectList`) has `kAudioProcessPropertyIsRunningInput == 1` and its `kAudioProcessPropertyBundleID` starts with an allowed prefix. Allowed: `us.zoom.`, `com.google.Chrome`, `com.microsoft.teams`, `com.tinyspeck.slackmacgap`, `com.apple.FaceTime`. Expose `static func matches(bundleID: String, allowed:) -> Bool`.
- Produces: `CalendarSignal` (name `"calendar"`): requests full access once at startup; refreshes every 60 s; active iff an event with `start <= now < end` and not all-day has a call link in `url`, `location` or `notes` matching `zoom\.us/j/|meet\.google\.com/[a-z]{3}-|teams\.microsoft\.com/l/meetup-join|teams\.live\.com/meet`. Skip events you declined. Expose `static func hasCallLink(_ text: String) -> Bool`.

- [ ] **Step 1: Failing tests**

```swift
check(MicSignal.matches(bundleID: "us.zoom.xos", allowed: MicSignal.defaultAllowed), "zoom mic counts")
check(!MicSignal.matches(bundleID: "com.granola.app", allowed: MicSignal.defaultAllowed), "granola mic ignored") // Review Focus 3
check(!MicSignal.matches(bundleID: "com.apple.VoiceMemos", allowed: MicSignal.defaultAllowed), "voice memos ignored")
check(CalendarSignal.hasCallLink("Join: https://meet.google.com/abc-defg-hij"), "meet link")
check(CalendarSignal.hasCallLink("https://us02web.zoom.us/j/123?pwd=x"), "zoom link")
check(!CalendarSignal.hasCallLink("Lunch at Zoom Cafe"), "plain text not a link")
```

- [ ] **Step 2:** Selftest fails → implement → passes.
- [ ] **Step 3:** `./build/granola-autostart --dry-run` for 30 s with Zoom test meeting open (muted). Expected log line containing `zoom`. Calendar permission prompt appears once; approve.

### Task 4: Localhost endpoint and Meet extension

**Files:**
- Create: `Sources/MeetSignal.swift`
- Create: `extension/manifest.json`, `extension/content.js`, `extension/background.js`
- Modify: `build.sh` (generate token, see below)

**Interfaces:**
- Produces: `MeetSignal(port: 47615, token: String)` (name `"meet"`): `NWListener` bound to `127.0.0.1:47615`. Accepts `POST /meet` only when header `X-Autostart-Token` equals the token; otherwise 403. Active iff last accepted heartbeat < 20 s ago. Expose `static func authorized(requestHead: String, token: String) -> Bool` (pure, parses the raw HTTP head).
- Token: `build.sh` creates `~/.config/granola-autostart/token` (random 32 hex via `openssl rand -hex 16`) if missing and writes `extension/config.js` with `const TOKEN = "<token>";` (`config.js` is git-ignored). The program reads the same file.
- Extension (MV3): `content_scripts` on `https://meet.google.com/*` runs `content.js`: every 10 s, if the in-call leave button exists (`button[aria-label*="Leave call" i]`, also accept `[jsname="CQylAd"]`), `chrome.runtime.sendMessage("in-call")`. `background.js` (`importScripts("config.js")`) forwards to `fetch("http://127.0.0.1:47615/meet", {method:"POST", headers:{"X-Autostart-Token": TOKEN}})`. `host_permissions: ["http://127.0.0.1:47615/*"]`.

- [ ] **Step 1: Failing tests**

```swift
let ok = "POST /meet HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Autostart-Token: abc\r\n\r\n"
check(MeetSignal.authorized(requestHead: ok, token: "abc"), "valid token accepted")
check(!MeetSignal.authorized(requestHead: ok.replacingOccurrences(of: "abc", with: "zzz"), token: "abc"), "bad token rejected") // Review Focus 4
check(!MeetSignal.authorized(requestHead: "POST /meet HTTP/1.1\r\n\r\n", token: "abc"), "missing token rejected")
check(!MeetSignal.authorized(requestHead: ok.replacingOccurrences(of: "POST", with: "GET"), token: "abc"), "GET rejected")
```

- [ ] **Step 2:** Selftest fails → implement → passes.
- [ ] **Step 3:** `curl -s -o /dev/null -w '%{http_code}' -X POST 127.0.0.1:47615/meet` → `403`; with `-H "X-Autostart-Token: $(cat ~/.config/granola-autostart/token)"` → `204`.

### Task 5: Install script and LaunchAgent

**Files:**
- Create: `install.sh`, `uninstall.sh`, `README.md`, `.gitignore`

**Interfaces:**
- `install.sh`: runs `build.sh`, copies binary to `~/.local/bin/granola-autostart`, writes `~/Library/LaunchAgents/com.markpinero.granola-autostart.plist` (`RunAtLoad`, `KeepAlive`, stdout/stderr to the log), `launchctl bootstrap gui/$(id -u)` it, and prints: "Load the extension: chrome://extensions → Developer mode → Load unpacked → <abs path>/extension".
- `uninstall.sh`: `launchctl bootout`, remove plist and binary. Leaves the token and log.
- `README.md`: what it does, install/uninstall, log location, the 120 s ceiling, and the two-line Chrome step. Note Calendar permission prompt.

- [ ] **Step 1:** `./install.sh` → `launchctl print gui/$(id -u)/com.markpinero.granola-autostart` shows `state = running`.
- [ ] **Step 2:** `./uninstall.sh` → same command reports not found; then reinstall.

### Task 6: End-to-end checks (with Mark)

- [ ] Zoom test meeting, joined muted with computer audio → one note starts; log shows `zoom` (and maybe `mic`).
- [ ] Zoom joined with no audio → one note starts via `zoom`.
- [ ] Meet test meeting, mic off in waiting room → no note in the waiting room; one note after joining; log shows `meet`.
- [ ] Leave, wait > 2 min, join again → second note.
- [ ] Granola transcribing alone (no call) → no extra notes for 3 min.
- [ ] Granola's chat message setting is off; confirm nothing posted in the Meet chat.
