# Team Recorder — Troubleshooting

## Recording issues

| Problem | Fix |
|---------|-----|
| Recording doesn't start | Check Screen Recording: System Settings → Privacy & Security → Screen Recording → Team Recorder ✓ → relaunch app |
| File named "Teams Meeting" (not meeting title) | Calendar permission missing for TeamRecorderBar — re-run Setup Guide… and allow Full Access. If your org blocks Calendar entirely, the app tries reading the title off the Teams call window instead — check Screen Recording is granted, and that the Teams call window wasn't minimized during the meeting |
| No microphone audio | System Settings → Privacy & Security → Microphone → Team Recorder ✓ |
| Recording continues after meeting ends | Expected — watcher waits 8s before confirming meeting ended (false-stop prevention) |
| Red recording icon stays after Stop / app feels stuck | Click menu bar icon → Recover Recorder…; current file may be marked incomplete |

## Menu bar app issues

| Problem | Fix |
|---------|-----|
| Setup Guide doesn't open | Click menu bar icon → Setup Guide… |
| "Launch at Login" does nothing | App must be in `/Applications/` — run `make menu-bar-install`, then re-toggle |
| App not in Login Items after enabling | Check System Settings → General → Login Items — Team Recorder should appear |
| "Relaunch App" shows an error alert | Quit manually from the menu bar, then reopen `/Applications/TeamRecorderBar.app` |
| Grey waveform but no recording | Run `make doctor` in the project folder — shows permission/disk/binary status |
| Setup Guide appeared on an update/reinstall | Expected — clear saved state with `make reset-setup`, then reopen the app |
| Recordings named "Teams Meeting" after granting Calendar | Bridge file may be stale — open Permissions → Calendar: OK (click to refresh), or quit and reopen the app |

## Menu bar shows ⚠ Can't start watcher

This means the app found a problem before it could launch `teams_recorder_v2.py`. Click the item to see the full error and pick a recovery action.

| Error shown | Cause | Fix |
|-------------|-------|-----|
| `App bundle is corrupted — re-download from GitHub Releases` | `watcher.pyz` or `recorder` binary is missing from the downloaded `.app` | Delete the app and re-download the zip from GitHub Releases |
| `Python 3.9+ required` | `/usr/bin/python3` is absent or too old | Install Xcode Command Line Tools: open Terminal and run `xcode-select --install` |
| `Watcher crashed immediately (exit …)` | Python startup failure in the bundled watcher | Re-download from GitHub Releases; if that fails, open Terminal and run `make doctor` in the project folder |

After fixing the root cause, use **Start Watcher** in the menu or reopen the app.

## Uninstall & permissions

### Clean uninstall (one command)

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

1. Quit: click menu bar icon → **Quit**
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
