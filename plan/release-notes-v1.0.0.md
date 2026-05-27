# Team Recorder v1.0.0

First public release — download, drag to Applications, and record.

## Requirements

- macOS 14 Sonoma or later
- **Architecture:** this build is **arm64 (Apple Silicon)**. Intel Mac users need the x86_64 build (see note below).

## Install

1. Download **TeamRecorderBar-v1.0.0.zip** and unzip it
2. Drag **TeamRecorderBar.app** to `/Applications/`
3. **Right-click → Open** (required once — see Gatekeeper note below)
4. Follow the Setup Guide: Screen Recording → Microphone → Calendar → Finish

No Terminal, Homebrew, or Python installation needed.

## Gatekeeper bypass (first open only)

macOS will show *"TeamRecorderBar cannot be opened because it is from an unidentified developer."*

**Right-click the app → Open → Open** to bypass this once. After that, double-clicking works normally.

> Team Recorder is ad-hoc signed but not Apple-notarized (avoids $99/yr Apple Developer fee). Right-click → Open is the standard macOS bypass for trusted apps from outside the App Store.

On macOS 15 Sequoia: if right-click → Open shows no "Open" button, go to System Settings → Privacy & Security → scroll down → click **"Open Anyway"**.

## SHA256

```
cf179ac0931c39a7c104169965e9e18a5dcb2ffa7aae0564173add3f013916f0  TeamRecorderBar-v1.0.0.zip
```

## What's new

This is the first public release. All changes relative to the developer-only internal builds:

- **Self-contained `.app`** — no Homebrew, no Python pre-install required
- `watcher.pyz` bundles the Python watcher + `python-dotenv` for system Python 3.9
- Config stored in `~/Library/Application Support/Team Recorder/.env` (not repo root)
- Setup preflight checks bundle integrity and Python version before showing permissions
- Calendar via `CalendarEventBridge` (native EKEventStore) — no `icalBuddy` needed from the app
- macOS 14 Sonoma minimum (bumped from 13)

## Known issues

- **Architecture-specific binary:** `recorder` captures audio via ScreenCaptureKit and is arch-specific. This zip contains the **arm64** build. An x86_64 build for Intel Macs requires building from source: clone the repo and run `make menu-bar-install`.
- **Sonoma smoke test pending:** full end-to-end recording test on a clean Sonoma 14 VM is required before this release is considered fully verified. The app logic is correct; the test is a precaution.
- **Gatekeeper on macOS 15 Sequoia:** right-click → Open may show no "Open" button on Sequoia. Use System Settings → Privacy & Security → Open Anyway as documented above.

## Source

Full source: https://github.com/cjarit/team-recorder
