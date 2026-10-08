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

## Left-click the icon: the popover

The popover is the daily surface. It shows one of these states:

| State | What you see | What you can do |
|-------|--------------|-----------------|
| **Recording** | Meeting name, elapsed time, and two live level bars: **Others** (the people on the call) and **My mic** (your voice) | **Stop Recording** |
| **Ready** | "Recording starts when you join a Teams meeting." | **Start Recording Now** — start immediately without waiting for Teams detection |
| **Paused** | "Meetings won't be recorded." | **Start Watching** |
| **Error** | The reason, or "Recorder Stopped Responding" when the status is stale | **Recover Recorder…** — clears a stuck state after a crash or stuck stop (the current file may be incomplete) |

Below the state card: **Last Recording** (click to reveal the file in Finder), the three **Permissions** rows (click **Allow…** to fix one), **Open Recordings Folder**, **Open Team Recorder…**, and **Quit Team Recorder**.

**Reading the level bars:** if **Others** moves but **My mic** stays flat, your voice is not being captured. "My mic: off" means *Record my voice* is switched off (see General below). "not captured" means the mic is silent or unavailable. If the mic is not captured for 60 seconds during a recording you also get one notification: "Your mic isn't being captured — others' voices are still recorded".

## Right-click the icon: the 5-item menu

| Item | What it does |
|------|--------------|
| **Open Team Recorder…** | Opens the main window (below) |
| **Pause Watching / Start Watching** | Stop or resume watching for meetings (nothing is recorded while paused) |
| **Setup Guide…** | Re-run the permission setup if something is wrong |
| **Uninstall Team Recorder…** | Moves the app to the Trash and stops the watcher; recordings and settings are kept |
| **Quit** | Quit the app (a watcher the app started stops with it) |

## The main window (Open Team Recorder…)

| Tab | What is in it |
|-----|---------------|
| **Status** | Health checks like `make doctor`: watcher running, current state, last error, recorder binary, disk free, the three permissions, last recording (**Show in Finder**), app version. Buttons: **Check for Updates** (opens the release page if a newer version exists; never installs by itself), Pause Watching, Recover Recorder…, Open Setup Guide… |
| **General** | **Recordings folder** (**Change…**), **Launch at Login** (requires the app in `/Applications/`), **Notify when a recording is saved**. Audio group: **Microphone** (Auto = system default, or pick a device), **Record my voice** (switch off to record system audio only), and the current speakers (read-only) |
| **Calendars** | Which calendars are used to name recordings (**Select All**, **Refresh events**) |
| **Permissions** | Screen Recording / Microphone / Calendar status with buttons to open System Settings, and a switch to skip Calendar if your organization blocks it |

Changing something in Audio restarts the watcher for you. The folder, Microphone and Record my voice controls are locked while a recording is in progress ("Change after the current recording").

**Rename and delete files in Finder.** The app deliberately has no file list.

## Recording file names

```
Sprint Planning - 10-00_21-05-2026.m4a          ← matched calendar event
DX Lead Discuss & Operations - 11-00_21-05-2026.m4a  ← no calendar event, but read off the Teams call window
Teams Meeting - 14-30_21-05-2026.m4a            ← no calendar event AND no title readable from screen
Teams Call (Short) - 09-15_21-05-2026.m4a       ← call under 3 minutes
```

**Naming order:** calendar event → Teams call window (screen) → `"Teams Meeting"` placeholder. The screen fallback needs the Teams call window visible on screen (not minimized) at some point during the recording — it doesn't need to be the frontmost window, just not minimized.

## The `Empty` folder

A recording that is **3 minutes or longer** and contains no speech at all is moved (never deleted) to an `Empty/` subfolder of your recordings folder, and you get a notification "No speech detected — moved to Empty". Calls under 3 minutes ("Teams Call (Short)") are never moved. If a file landed there by mistake, drag it back out in Finder.

## Tips for a clean recording

- Use headphones when you can. With laptop speakers, the other side leaks into your mic; the app reduces this automatically when it detects it, but headphones give the cleanest result.
- If you use a Bluetooth headset, nothing special is needed — the microphone is captured in a way that is not interrupted when the headset switches mode at the start and end of a call.
