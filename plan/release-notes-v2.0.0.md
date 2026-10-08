# Team Recorder v2.0.0

## Requirements

- **macOS 15 Sequoia or later.** Still on macOS 14? Use [v1.2.4](https://github.com/cjarit/team-recorder/releases/tag/v1.2.4) — that line keeps receiving bug fixes.
- **Architecture:** this build is **arm64 (Apple Silicon)**. Intel Mac users build from source: `make cert` once, then `make menu-bar-install`.

## Install

1. Download **TeamRecorderBar-v2.0.0.dmg** (or the `.zip`)
2. Open it and drag **TeamRecorderBar.app** to **Applications**
3. First open: macOS blocks the app (it is signed but not notarized) → System Settings → Privacy & Security → scroll down → **Open Anyway**
4. Follow the Setup Guide: Screen Recording → Microphone → Calendar (can be skipped) → Finish

No Terminal, Homebrew or Python installation needed.

## Updating from v1.2.x — one last permission round

Quit TeamRecorderBar, replace the app in `/Applications`, open it. Your settings, tracked calendars and recordings are kept; the app stops the old watcher by itself.

macOS will ask for the three permissions **one more time**, because the signing identity changed. For **Screen Recording** the old TeamRecorderBar row is still listed and ticked but no longer works: select it, click **−**, click **+** and add the app again, then relaunch. The Setup Guide shows this exact instruction.

**From v2.0 on, upgrades keep their permissions.** Every build is signed with the same identity (verified: 7 reinstalls on one Mac and a Mac without the certificate, zero re-prompts).

## SHA256

```
c4c03e6c102b12f556c1d39b75a12bcd188a1d06ab052382033a27f8d9b814db  TeamRecorderBar-v2.0.0.dmg
caad6bfe7316d271b179b50089308ae9ce8a17fdd6fad58fa1f6f8bde1452ac7  TeamRecorderBar-v2.0.0.zip
```

## What's new in v2.0.0

### Control
- **Popover** on left-click: state, meeting name, elapsed time, two live level bars (**Others** / **My mic**), Stop / Start Recording Now, last recording, permissions when something is missing.
- **Team Recorder window** (right-click → Open Team Recorder…): Status (everything `make doctor` showed, plus disk space, version and Check for Updates), General (recordings folder, Launch at Login, notifications, **Microphone picker**, **Record my voice** switch), Calendars, Permissions.
- Right-click menu reduced to five items. File management stays in Finder.
- **Uninstall Team Recorder…** in the menu: stops the watcher, moves the app to Trash, keeps recordings and settings.

### Audio
- **Microphone is captured through ScreenCaptureKit** — the Bluetooth-headset hang that cost meetings in v1.2.3 is structurally gone (tested: AirPods Max join/leave, mic alive 60/60 s, max gap 24 ms). `MIC_PATH=engine` in `.env` restores the previous path for one release.
- **Echo fix:** recordings no longer drift. The system-audio track used to run ahead of the mic track by about 1 % (23 s in a 34-minute meeting), which with speakers sounded like every sentence repeated a second later. Positions are now clock-anchored.
- **Speaker bleed is reduced at mixdown:** when the mic clearly carries a copy of the other side, it is turned down while they talk. Headphone recordings are untouched.
- **Empty recordings** (no speech, 3 minutes or longer — e.g. you joined to test and left) move to an **Empty** subfolder. Nothing is deleted.
- Notification when your mic is not being captured for 60 s during a recording.

### Setup and install
- Stable code-signing identity: grant permissions once.
- `.dmg` download, self-healing upgrade, Calendar step can be skipped.
- macOS 15 floor; Swift 6 toolchain.

### Known limitations
- Not notarized: first open still needs "Open Anyway".
- While the other side talks, your own interjections are quieter in speaker recordings (that is the bleed reduction working). Headphones give the cleanest result.
- "My mic" bar shows **off** when Record my voice is disabled in General.
