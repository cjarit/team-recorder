# Team Recorder — Daily Use

> How to use once the app is installed and permissions are granted.

## Normal workflow

1. Open TeamRecorderBar from `/Applications/` (or use Launch at Login)
2. Join your Teams meeting — recording starts automatically
3. Leave the meeting — recording stops and is named after the calendar event
4. Find your recordings at `~/Documents/Teams Recording/`

## Menu bar icons

| Icon | Meaning |
|------|---------|
| ○ waveform (grey) | Idle — waiting for a Teams meeting |
| ● record.circle (red) | Recording in progress |
| ⚠ ! (orange) | Error |

## Useful menu items

- **▶ Start Recording** — start immediately without waiting for Teams detection
- **■ Stop Recording** — stop manually
- **📁 Recordings Folder → Change Folder…** — move recordings to a different folder
- **Launch at Login** — toggle auto-start when you log in (requires app in `/Applications/`)
- **Setup Guide…** — re-run the permission setup if something is wrong

## Recording file names

```
Sprint Planning - 10-00_21-05-2026.m4a          ← matched calendar event
Teams Meeting - 14-30_21-05-2026.m4a            ← no calendar event found
Teams Call (Short) - 09-15_21-05-2026.m4a       ← call under 3 minutes
```
