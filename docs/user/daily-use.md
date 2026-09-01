# Team Recorder — Daily Use

> How to use once the app is installed and permissions are granted.

## Normal workflow

1. Open TeamRecorderBar from `/Applications/` (or use Launch at Login)
2. Join your Teams meeting — recording starts automatically
3. Leave the meeting — recording stops and is named after the meeting title (from your calendar, or read off the Teams call window if the calendar has no title)
4. Click the saved-recording notification to reveal the file in Finder, or find recordings at `~/Documents/Teams Recording/`

## Menu bar icons

| Icon | Meaning |
|------|---------|
| ○ waveform (grey) | Idle — waiting for a Teams meeting |
| ● record.circle (red) | Recording in progress |
| ⚠ ! (orange) | Error |

## Useful menu items

- **▶ Start Recording** — start immediately without waiting for Teams detection
- **■ Stop Recording** — stop manually
- **Recover Recorder…** — clear a stale recording state after a crash or stuck stop
- **📁 Recordings Folder → Change Folder…** — move recordings to a different folder
- **Launch at Login** — toggle auto-start when you log in (requires app in `/Applications/`)
- **Setup Guide…** — re-run the permission setup if something is wrong

## Recording file names

```
Sprint Planning - 10-00_21-05-2026.m4a          ← matched calendar event
DX Lead Discuss & Operations - 11-00_21-05-2026.m4a  ← no calendar event, but read off the Teams call window
Teams Meeting - 14-30_21-05-2026.m4a            ← no calendar event AND no title readable from screen
Teams Call (Short) - 09-15_21-05-2026.m4a       ← call under 3 minutes
```

**Naming order:** calendar event → Teams call window (screen) → `"Teams Meeting"` placeholder. The screen fallback needs the Teams call window visible on screen (not minimized) at some point during the recording — it doesn't need to be the frontmost window, just not minimized.
