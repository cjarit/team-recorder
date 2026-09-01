# Team Recorder v1.2.2

## Requirements

- macOS 14 Sonoma or later
- **Architecture:** this build is **arm64 (Apple Silicon)**. Intel Mac users need to build from source: `make menu-bar-install`.

## Install

1. Download **TeamRecorderBar-v1.2.2.zip** and unzip it
2. Drag **TeamRecorderBar.app** to `/Applications/`
3. **Right-click → Open** (required once — Gatekeeper bypass)
4. Follow the Setup Guide: Screen Recording → Microphone → Calendar → Finish

No Terminal, Homebrew, or Python installation needed.

## Updating from v1.2.0 or v1.1.x

**If you installed v1.2.0, please update — see "Fixed" below.**

Replace `/Applications/TeamRecorderBar.app` with the new version. Your settings and recording folder are preserved. You may need to re-grant Screen Recording permission once (macOS requires this when the app binary changes), and the first-run Setup Guide may briefly reappear — just click through it, no permissions actually need re-granting if already approved.

## Gatekeeper bypass (first open only)

macOS will show *"TeamRecorderBar cannot be opened because it is from an unidentified developer."*

**Right-click the app → Open → Open** to bypass this once.

On macOS 15 Sequoia: if right-click → Open shows no "Open" button, go to System Settings → Privacy & Security → scroll down → click **"Open Anyway"**.

## SHA256

```
e0e342a55f1943d6aef54f7114a088122dab8142d344351e16b1457600a9db06  TeamRecorderBar-v1.2.2.zip
```

## What's new in v1.2.2

### Fixed: the screen-title fallback could interrupt system audio during a recording

**If you use the screen-title fallback (Calendar unavailable), please update from v1.2.0.** In v1.2.0, reading the meeting title off the Teams window spawned a second background process momentarily. That second process briefly interrupted the recording's own audio capture — the app recovered automatically and the recording still completed, but system audio could be silently gapped for a second or two while it did. This is fixed: the title is now read by the same process that's already recording, so there's no interruption at all.

### Fixed: screen-title fallback missed short calls

Calls joined and left again within seconds could get no title from the screen fallback — Teams shows a brief "connecting..." animation right after joining, before the call toolbar (and its timer) actually renders, and the fallback only looked once. It now retries a few times over a couple of seconds before giving up, so short test calls and quick meetings are covered too.

## What's new in v1.2.0

### New: recordings can now be named without Calendar access

Some organizations block Exchange calendar sync to Apple Calendar, and separately lock Outlook's calendar-sharing feature to "free/busy only" — no meeting titles available at all, by deliberate IT policy. Previously this meant every recording was named "Teams Meeting" with no way around it.

Team Recorder now reads the meeting title directly off the Teams call window on screen when Calendar has no title to offer — the same Screen Recording permission the app already uses to capture audio, no new permission needed. Nothing is sent anywhere; the title is read locally, the same way the app already captures your meeting audio.

**Naming order:** Calendar event → Teams call window (screen) → "Teams Meeting" placeholder.

This requires the Teams call window to be visible on screen (not minimized) at some point during the recording — it doesn't need to be the frontmost window.

## Known issues

- **Architecture-specific binary:** this zip is arm64 only. Intel Mac users: build from source with `make menu-bar-install`.
- The screen-title fallback hasn't been verified on a Thai-language Teams UI or with a Thai-language meeting title — the mechanism is designed to be language-independent (it locates the title by position on the toolbar, not by matching English words) but this hasn't been observed directly yet. If naming looks wrong in one of these cases, please report it.
- Manual rename UI (for recordings that still land as "Teams Meeting") is planned for a future release, not included here.

## Source

Full source: https://github.com/cjarit/team-recorder
