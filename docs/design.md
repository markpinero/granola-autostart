# Granola auto-start — design (approved 2026-10-26)

**Goal:** every call (Zoom, Meet, Teams, Slack, FaceTime) gets a Granola transcription, including muted joins. Extra note > missed call. No in-meeting chat notice or watermark.

**How:** one Swift background program (LaunchAgent) with three triggers feeding one launcher:
1. Zoom: Zoom's in-meeting helper process (`CptHost`) is running.
2. Meet: our unpacked Chrome extension sees Meet's in-call controls and pings localhost (token-protected).
3. Mic: Zoom/Chrome/Teams/Slack/FaceTime is using the mic (Granola itself ignored).

Launcher opens `granola://new-document?creation_source=autostart&auto_transcribe=1` once per call; a call ends after 120 s with no signal. Every start is logged to `~/Library/Logs/granola-autostart.log`.

**Removed 2026-10-26:** calendar trigger. Zoom/Meet/mic cover the same calls; it added notes for skipped meetings and needed Calendar permission. Cost: muted Teams/Slack/FaceTime, non-Chrome Meet and phone dial-ins are no longer caught.

**Not doing:** linking notes to calendar events, stopping transcription, Windows.

**Undocumented dependency:** the deep link was found in Granola 7.700.0's app bundle, not in docs; an update can break it.

## Task 0 findings
Confirmed by Mark, 2026-10-26:
- [x] Deep link starts transcription.
- [x] Granola stops on its own when the call ends.
- [x] Zoom in-meeting process is `CptHost` (`/Applications/zoom.us.app/Contents/Frameworks/CptHost.app`).

Install, 2026-10-26: agent running under launchd; first live start logged `start mic,zoom` during a Zoom call.
