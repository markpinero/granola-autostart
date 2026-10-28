# Name auto-started notes from calendar — design

**Goal:** when a call triggers an auto-start, the Granola note is titled with the matching calendar event's name instead of the default.

**How (approved approach A: EventKit):**
- One-time manual step: Google calendar added to macOS Internet Accounts (Fantastical syncs separately and is invisible to EventKit).
- On call start, query events overlapping now (5 min before → 15 min after), skip all-day and cancelled. Prefer events whose location/notes contain a `meet.google.com` / `zoom.us` link matching the trigger platform; tie-break by latest start.
- Append `&event=<urlencoded JSON {id, summary, start:{dateTime}}>` to the deep link. Granola sets the note title from `summary` and reuses the note if the same event id + start is seen again (rejoin = same note, verified in Granola 7.700.0 asar).
- No match → deep link unchanged, note untitled as today.

**Constraints:** EventKit Calendars permission prompt once (needs `NSCalendarsUsageDescription` in Info.plist; unsigned binary may reprompt after rebuilds). Matching is heuristic; overlapping meetings can pick the wrong one — acceptable, the note is still created.

**Non-goals:** Google OAuth/API, reading Fantastical's private store, changes to the Meet extension.

**Approaches rejected:** B Google Calendar API direct (~200+ lines + credentials to babysit); reading Fantastical containers (undocumented, fragile).

**Left to builder:** none material.
