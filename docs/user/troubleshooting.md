# Team Recorder — Troubleshooting

## Recording issues

| Problem | Fix |
|---------|-----|
| Recording doesn't start | Check Screen Recording: System Settings → Privacy & Security → Screen Recording → Team Recorder ✓ → relaunch app |
| File named "Teams Meeting" (not meeting title) | Calendar permission missing for Team Recorder or `icalBuddy` — re-run Setup Guide… and allow Full Access |
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
| Calendar prompt appears twice during setup | Expected if the second prompt is for `icalBuddy`; allow it so live meetings do not prompt again |
| Setup Step 3 Calendar — Finish button unresponsive | icalBuddy probe result is now advisory only; click Finish whenever Calendar permission is granted |
| icalBuddy shows warning in menu bar | Open Permissions → Retry icalBuddy Access to re-probe; or run Setup Guide again |

## Menu bar shows ⚠ Can't start watcher

This means the app found a problem before it could launch `teams_recorder_v2.py`. Click the item to see the full error and pick a recovery action.

| Error shown | Cause | Fix |
|-------------|-------|-----|
| `watcher_path.txt not found` | App bundle was not built from the current project folder | Run `make menu-bar-install` from the repo folder |
| `teams_recorder_v2.py not found at …` | Repo was moved, or the app was built on a different machine | Run `make menu-bar-install` from the current repo location |
| `python3 not found` | Python 3 is not on PATH | `brew install python` then reopen the app |
| `Python pinned at … is missing or not executable` | The Python interpreter baked into the app at build time has moved or been removed | Run `make menu-bar-install` from the project folder to re-pin the current interpreter |
| `Watcher crashed immediately (exit …)` with `ModuleNotFoundError` | App was built before the interpreter-pin fix, or `python-dotenv` is not installed in the pinned interpreter | First run `make menu-bar-install` to re-pin the interpreter. If the error persists, run `make setup` then `make menu-bar-install` again. |
| `Watcher crashed immediately (exit …)` (other) | Python syntax error or other import failure | Run `make doctor` in the project folder; if it passes, re-run `make menu-bar-install` |

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
| Automation (icalBuddy) | System Settings → Privacy & Security → Automation → icalBuddy → toggle off |
