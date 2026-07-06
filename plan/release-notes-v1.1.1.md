# Team Recorder v1.1.1

## Requirements

- macOS 14 Sonoma or later
- **Architecture:** this build is **arm64 (Apple Silicon)**. Intel Mac users need to build from source: `make menu-bar-install`.

## Install

1. Download **TeamRecorderBar-v1.1.1.zip** and unzip it
2. Drag **TeamRecorderBar.app** to `/Applications/`
3. **Right-click → Open** (required once — Gatekeeper bypass)
4. Follow the Setup Guide: Screen Recording → Microphone → Calendar → Finish

No Terminal, Homebrew, or Python installation needed.

## Updating from v1.1.0

Replace `/Applications/TeamRecorderBar.app` with the new version. Your settings and recording folder are preserved. You will need to re-grant Screen Recording permission once (macOS requires this when the app binary changes), and the first-run Setup Guide may briefly reappear — just click through it, no permissions actually need re-granting if already approved.

## Gatekeeper bypass (first open only)

macOS will show *"TeamRecorderBar cannot be opened because it is from an unidentified developer."*

**Right-click the app → Open → Open** to bypass this once.

On macOS 15 Sequoia: if right-click → Open shows no "Open" button, go to System Settings → Privacy & Security → scroll down → click **"Open Anyway"**.

## SHA256

```
(filled in after `make release`)
```

## What's new in v1.1.1

### Fixed: recordings weren't starting automatically

A recent Microsoft Teams update changed how Teams handles call audio internally, which broke Team Recorder's ability to detect when you were in a meeting — recordings had to be started manually. This is fixed: auto-start and auto-stop work again exactly as before. No action needed beyond updating the app.

## Known issues

- **Architecture-specific binary:** this zip is arm64 only. Intel Mac users: build from source with `make menu-bar-install`.

## Source

Full source: https://github.com/cjarit/team-recorder
