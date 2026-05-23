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

## Uninstall & permissions

### วิธีถอนการติดตั้ง

1. Quit: click menu bar icon → **Quit**
2. Delete the app: `rm -rf /Applications/TeamRecorderBar.app`
3. (Optional) Clear saved settings: `make reset-setup`

### สิทธิ์ที่ให้ไปจะหายไปไหมเมื่อ Uninstall?

**ไม่หาย** — macOS เก็บสิทธิ์ไว้แม้ลบแอปแล้ว หากต้องการยกเลิก:

| Permission | How to revoke |
|------------|---------------|
| Screen Recording | System Settings → Privacy & Security → Screen Recording → Team Recorder → click **−** |
| Microphone | System Settings → Privacy & Security → Microphone → Team Recorder → toggle off |
| Calendar | System Settings → Privacy & Security → Calendars → Team Recorder → **None** |
