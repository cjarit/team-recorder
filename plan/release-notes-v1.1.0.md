# Team Recorder v1.1.0

## Requirements

- macOS 14 Sonoma or later
- **Architecture:** this build is **arm64 (Apple Silicon)**. Intel Mac users need to build from source: `make menu-bar-install`.

## Install

1. Download **TeamRecorderBar-v1.1.0.zip** and unzip it
2. Drag **TeamRecorderBar.app** to `/Applications/`
3. **Right-click → Open** (required once — Gatekeeper bypass)
4. Follow the Setup Guide: Screen Recording → Microphone → Calendar → Finish

No Terminal, Homebrew, or Python installation needed.

## Updating from v1.0.0

Replace `/Applications/TeamRecorderBar.app` with the new version. Your settings and recording folder are preserved. You will need to re-grant Screen Recording permission once (macOS requires this when the app binary changes).

## Gatekeeper bypass (first open only)

macOS will show *"TeamRecorderBar cannot be opened because it is from an unidentified developer."*

**Right-click the app → Open → Open** to bypass this once.

On macOS 15 Sequoia: if right-click → Open shows no "Open" button, go to System Settings → Privacy & Security → scroll down → click **"Open Anyway"**.

## SHA256

```
823440377e5c20bd6b2e92d2ecad428adc243eb2e4ff743119ffef498ffaab00  TeamRecorderBar-v1.1.0.zip
```

## What's new in v1.1.0

### Smaller recording files

- Audio now captured at 16 kHz mono / 32 kbps AAC — optimised for AI transcription
- ~3× smaller than before (~14 MB/hr vs ~43 MB/hr)
- No loss in NotebookLM or Whisper transcript quality

### Per-user calendar picker

- New **Tracked Calendars** submenu — check or uncheck which Apple Calendars are scanned for meeting names
- Excludes holiday, personal, or squad-shared calendars from polluting recording file names
- Setting is saved per user; default is all calendars (no change from v1.0.0 behaviour)

### Menu bar redesign

- Consistent SF Symbol icons on all actionable menu items
- Status line now uses colored SF Symbols (red = recording, orange = error/stale)
- Cleaner 5-group layout; removed mixed emoji/Unicode/text glyphs

## Known issues

- **Architecture-specific binary:** this zip is arm64 only. Intel Mac users: build from source with `make menu-bar-install`.
- **Live recording smoke test:** the compact recording gate (NotebookLM transcript quality at 32 kbps) is verified by the team in normal usage — no automated gate exists yet.

## Source

Full source: https://github.com/cjarit/team-recorder
