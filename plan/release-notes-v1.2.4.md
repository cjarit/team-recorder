# Team Recorder v1.2.4

## Requirements

- macOS 14 Sonoma or later
- **Architecture:** this build is **arm64 (Apple Silicon)**. Intel Mac users need to build from source: `make menu-bar-install`.

## Install

1. Download **TeamRecorderBar-v1.2.4.zip** and unzip it
2. Drag **TeamRecorderBar.app** to `/Applications/`
3. **Right-click → Open** (required once — Gatekeeper bypass)
4. Follow the Setup Guide: Screen Recording → Microphone → Calendar → Finish

No Terminal, Homebrew, or Python installation needed.

## Updating from an earlier version

**Recommended for everyone, especially if you use a Bluetooth headset (AirPods etc.).**

Quit TeamRecorderBar first (menu bar icon → Quit), then replace `/Applications/TeamRecorderBar.app` with the new version. Your settings and recording folder are preserved.

**After updating, the Setup Guide will appear again and recording will not start until you finish it.** macOS treats the new build as a new app, so Screen Recording, Microphone and Calendar need to be granted once more. This happened on every reinstall during testing.

## Gatekeeper bypass (first open only)

macOS will show *"TeamRecorderBar cannot be opened because it is from an unidentified developer."*

**Right-click the app → Open → Open** to bypass this once.

On macOS 15 Sequoia: if right-click → Open shows no "Open" button, go to System Settings → Privacy & Security → scroll down → click **"Open Anyway"**.

## SHA256

```
67ef48651e50a2d28b22e41d8f9afc7a3869a0e027c2c178aefa17e6bf3a4d30  TeamRecorderBar-v1.2.4.zip
```

## What's new in v1.2.4

### Fixed: meetings lost or files that won't open when using a Bluetooth headset

When Teams starts or ends a call, a Bluetooth headset switches between "call" and "music" mode. At that exact moment macOS's microphone engine can freeze — we measured one freeze lasting **59 minutes**. Because recording starts and stops at exactly those moments, this caused two real failures:

- a recording whose stop froze, leaving a file named `INCOMPLETE_…` that could not be opened
- a meeting that was never recorded at all, while the menu bar still said "Waiting"

Now:

- **Recording no longer waits for the microphone.** Recording starts immediately; if the mic is stuck, other participants' audio is still recorded and the mic joins as soon as it can.
- **Files stay playable even if something goes wrong.** The recording is written in 10-second pieces, so even if the recorder is force-stopped, everything up to the last 10 seconds can be played.
- **Stopping never loses the file.** The file is closed first, then the microphone is released. A code path that could delete the whole file after a slow stop has been removed.
- **If the recorder stops responding it is restarted automatically,** and you get a notification instead of a silent failure.
- `INCOMPLETE_` files (if they ever happen) now keep the meeting name.

Known limit: if the microphone engine freezes mid-meeting, **your own voice** is missing for that stretch (others are fine). Using the MacBook mic or a wired mic avoids this completely. A fix that captures the mic a different way is planned for v1.2.5.

### Fixed: your own voice was missing from NotebookLM transcripts

Recordings had two audio tracks: other participants and your microphone. **NotebookLM only reads the first track**, so your voice was never transcribed (confirmed with a test file). Recordings are now merged into a single track automatically after each meeting, so NotebookLM and other tools that read only the first track now hear both sides. Files are also about half the size.

Older recordings are not changed. To merge one yourself:

```bash
/Applications/TeamRecorderBar.app/Contents/Resources/recorder --mixdown "/path/to/recording.m4a"
```

## What's new in v1.2.3

### Fixed: recordings were still named "Teams Meeting" — the actual cause

v1.2.0 added naming from the Teams window, but it kept failing in real use. The reason turned out to be simple once measured: **recording starts while you're still on Teams' pre-join screen** (the camera/mic setup screen, before you press "Join now"). That screen already opens the network connections Team Recorder watches for, so recording begins — but there's no call yet, so there was nothing to read the name from, and the app only looked once, at the very start.

Now the meeting name is taken from the Teams window title, which already contains it on the pre-join screen, and the app keeps re-checking every ~15 seconds for the whole meeting. So it works whether you join instantly or sit on the pre-join screen first, and it recovers if the Teams window was minimized when the recording started.

### Fixed: Thai meeting names were garbled

Names were previously read by optical character recognition, which mangled Thai text — a meeting called `Test for Team Record ครับ` was read as `Test for Team Record Ašu`, and differently again on the next attempt. The name is now read directly from the Teams window title as real text, so Thai (and any other language) comes through exactly as written. Character recognition is now only used to spot the call timer, which is just digits and reads reliably.

### Also in this release

- New `--diagnose-title` command for troubleshooting: if naming ever misbehaves, it shows exactly what the app can see. Run `recorder/recorder --diagnose-title` while in a meeting, with the watcher stopped.

## What's new in v1.2.2

### Fixed: the naming step could interrupt system audio during a recording

Reading the meeting title used to spawn a second background process, which briefly interrupted the recording's own audio capture. The app recovered automatically and recordings still completed, but system audio could be silently gapped for a second or two. The title is now read by the same process that's already recording, so there's no interruption.

## What's new in v1.2.0

### New: recordings can be named without Calendar access

Some organizations block Exchange calendar sync to Apple Calendar, and separately lock Outlook's calendar-sharing to "free/busy only" — no meeting titles at all, by IT policy. Previously this meant every recording was named "Teams Meeting" with no way around it.

Team Recorder now reads the meeting name directly from the Teams window when Calendar has no title to offer — using the same Screen Recording permission the app already needs to capture audio, so there's no new permission to grant. Nothing is sent anywhere; it's read locally on your Mac.

**Naming order:** Calendar event → Teams window → "Teams Meeting" placeholder.

## Known issues

- **Architecture-specific binary:** this zip is arm64 only. Intel Mac users: build from source with `make menu-bar-install`.
- If your Microsoft Teams interface language is set to Thai (or another non-English language), window-title parsing is unverified — it strips the English `"| Microsoft Teams"` and `"Meeting join |"` markers, which are likely translated. Please report if naming looks wrong.
- Manual rename UI (for recordings that still land as "Teams Meeting") is planned for a future release.

## Source

Full source: https://github.com/cjarit/team-recorder
