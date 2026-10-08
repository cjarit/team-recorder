# Team Recorder — Troubleshooting

## Recording issues

| Problem | Fix |
|---------|-----|
| Recording doesn't start | Check Screen Recording: System Settings → Privacy & Security → Screen Recording → Team Recorder ✓ → relaunch app |
| Screen Recording is ticked but nothing records, right after upgrading from 1.2.x | macOS kept the old TeamRecorderBar row, but it no longer works with the 2.0 app. In System Settings → Privacy & Security → Screen Recording select the TeamRecorderBar row, click **−**, click **+**, choose `/Applications/TeamRecorderBar.app`, turn it on, then Relaunch App. One time only — later upgrades keep the permission. The Setup Guide shows these steps by itself |
| A recording is missing from the recordings folder | Look in the `Empty` subfolder. Files of 3 minutes or longer with no speech at all are moved there (never deleted); shorter calls are never moved. If a real recording ended up there, drag it back out in Finder |
| Popover shows "My mic: off" | *Record my voice* is switched off. Right-click the icon → Open Team Recorder… → General → turn on Record my voice (locked while a recording is running) |
| Popover shows "My mic: not captured", or you got the "Your mic isn't being captured" notification | The mic is silent or unavailable. Check Microphone permission, and in General → Microphone pick the device you are actually using. Others' voices are still recorded |
| File named "Teams Meeting" (not meeting title) | Calendar permission missing for TeamRecorderBar — re-run Setup Guide… and allow Full Access. If your org blocks Calendar entirely, the app tries reading the title off the Teams call window instead — check Screen Recording is granted, and that the Teams call window wasn't minimized during the meeting |
| No microphone audio | System Settings → Privacy & Security → Microphone → Team Recorder ✓; also check General → Record my voice is on |
| Recording sounds echoey / "same sentence twice" | Fixed in 2.0 (the two tracks used to drift apart). With speakers, a faint copy of the other side can still reach your mic; the app reduces it automatically, headphones remove it |
| Recording continues after meeting ends | Expected — watcher waits 8s before confirming meeting ended (false-stop prevention) |
| Red recording icon stays after Stop / app feels stuck | Left-click the menu bar icon → Recover Recorder…; current file may be marked incomplete |
| File named INCOMPLETE_ | The recorder may have hung during shutdown. The file should still be playable up to the last 10-second fragment. If corrupted, contact support with the file path and timestamps from Open Team Recorder… → Status. This is rare — INCOMPLETE_ files from versions before 1.2.4 were often unplayable |
| Using a Bluetooth headset (AirPods etc.): recording didn't start or a file came out INCOMPLETE (versions before 1.2.4) | When Teams starts or ends a call, the headset switches between call mode and music mode. Older versions could freeze at that moment. 1.2.4 stopped waiting for the mic; 2.0 captures the mic through ScreenCaptureKit, which is not interrupted by that switch, so your own voice is recorded too |

## Menu bar app issues

| Problem | Fix |
|---------|-----|
| Setup Guide doesn't open | Right-click the menu bar icon → Setup Guide… |
| "Launch at Login" does nothing | App must be in `/Applications/` — drag it there (developers: `make menu-bar-install`), then re-toggle in Open Team Recorder… → General |
| App not in Login Items after enabling | Check System Settings → General → Login Items — Team Recorder should appear |
| "Relaunch App" shows an error alert | Quit manually from the menu bar, then reopen `/Applications/TeamRecorderBar.app` |
| Grey waveform but no recording | Run `make doctor` in the project folder — shows permission/disk/binary status |
| Setup Guide appeared again after an upgrade | Expected only when moving from 1.2.x to 2.0 (permissions must be granted one last time). After that, upgrades keep your permissions. If it appears on every upgrade, the app was not built with the "Team Recorder Signing" certificate (developers: `make cert`) |
| Recordings named "Teams Meeting" after granting Calendar | Bridge file may be stale — open Open Team Recorder… → Calendars → **Refresh events**, or quit and reopen the app |

## Popover shows "Can't Start Watcher"

This means the app found a problem before it could launch `teams_recorder_v2.py`. Click **Show Details…** in the popover to see the full error and pick a recovery action.

| Error shown | Cause | Fix |
|-------------|-------|-----|
| `App bundle is corrupted — re-download from GitHub Releases` | `watcher.pyz` or `recorder` binary is missing from the downloaded `.app` | Delete the app and re-download the zip from GitHub Releases |
| `Python 3.9+ required` | `/usr/bin/python3` is absent or too old | Install Xcode Command Line Tools: open Terminal and run `xcode-select --install` |
| `Watcher crashed immediately (exit …)` | Python startup failure in the bundled watcher | Re-download from GitHub Releases; if that fails, open Terminal and run `make doctor` in the project folder |

After fixing the root cause, use **Start Watching** (right-click menu or popover) or reopen the app.

## Uninstall & permissions

### Uninstall from the app (no Terminal)

Right-click the menu bar icon → **Uninstall Team Recorder…** → confirm. The app stops the watcher, removes its runtime files, opens your recordings folder in Finder, moves itself to the Trash and quits. **Your recordings and settings are kept.** macOS permissions stay listed until you remove them yourself (table below).

### Clean uninstall from Terminal (developers)

```bash
make uninstall
```

This stops the watcher, quits the app, removes `/Applications/TeamRecorderBar.app`, clears saved preferences, and removes runtime state files (`status.json`, PID files). **Recordings are not touched.**

Afterwards, follow the printed instructions to revoke macOS permissions manually (macOS does not expose an API to clear TCC entries programmatically).

### Clean reinstall

```bash
make clean-reinstall
```

Runs `make uninstall` then `make menu-bar-install` in one step.

### Manual uninstall (without make)

1. Quit: right-click menu bar icon → **Quit**
2. Stop watcher: `python3 teams_recorder_v2.py --stop`
3. Delete the app: `rm -rf /Applications/TeamRecorderBar.app`
4. Clear settings: `defaults delete com.team-recorder.menu-bar`
5. Clear runtime state: `rm -f ~/Library/Application\ Support/Team\ Recorder/status.json ~/Library/Application\ Support/Team\ Recorder/*.pid`

### Revoking macOS permissions after uninstall

**ไม่หาย** — macOS เก็บสิทธิ์ไว้แม้ลบแอปแล้ว หากต้องการยกเลิก:

| Permission | How to revoke |
|------------|---------------|
| Screen Recording | System Settings → Privacy & Security → Screen Recording → TeamRecorderBar → click **−** |
| Microphone | System Settings → Privacy & Security → Microphone → TeamRecorderBar → toggle off |
| Calendar | System Settings → Privacy & Security → Calendars → TeamRecorderBar → **None** |
| Automation (icalBuddy) | System Settings → Privacy & Security → Automation → icalBuddy → toggle off (only if listed; only relevant when running via Terminal / `make run`) |

## Older macOS (14)

Version 2.x needs macOS 15 or later. On macOS 14 use **v1.2.4** from [GitHub Releases](https://github.com/cjarit/team-recorder/releases); the 1.2.x line only receives bug fixes.
