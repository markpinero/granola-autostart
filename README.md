# granola-autostart

Starts a Granola transcription automatically when you're on a call, including when you join muted (Zoom, and Meet in Chrome). Nothing is posted to the meeting.

A background app checks three things every 5 seconds:

| Trigger | Fires when |
| --- | --- |
| zoom | Zoom's in-meeting helper (`CptHost`) is running |
| meet | The bundled Chrome extension sees Meet's leave-call button |
| mic | Zoom, Chrome, Teams, Slack or FaceTime is using the mic (Granola itself is ignored) |

The first trigger opens `granola://new-document?creation_source=autostart&auto_transcribe=1`. Later triggers are ignored until every trigger has been quiet for 2 minutes, which ends the call. Calls closer together than that share one note.

That deep link is undocumented (found in Granola 7.700.0). If a Granola update breaks it, the log will still show `start` lines but no note appears.

## Install

```bash
./install.sh
```

Then load the Meet extension once: `chrome://extensions` → Developer mode → **Load unpacked** → this repo's `extension/` folder.

## Check what happened

```bash
tail -f ~/Library/Logs/granola-autostart.log
```

Each line names the triggers behind a start, e.g. `start meet,mic`.

Try it without opening Granola: `./build.sh && ./build/granola-autostart --dry-run`. Run the self-test with `./build/granola-autostart --selftest`.

Not covered: muted Teams, Slack huddles or FaceTime (only caught once your mic is on), Meet in browsers other than Chrome, and phone dial-ins.

## Uninstall

```bash
./uninstall.sh
```
