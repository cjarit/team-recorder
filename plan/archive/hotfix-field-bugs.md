# Hotfix — Field Bug Fixes (bug02–bug06)

Second round of field-reported bugs from a non-developer teammate after Phase 1 shipped.

## Bug Summary

| Bug | Symptom | Root Cause | File |
|---|---|---|---|
| bug02 | Setup Step 1: app not in Screen Recording list; user stuck | Instructions don't mention clicking "+" to add the app manually | `SetupWindowController.swift:55-59` |
| bug03 | Menu bar shows blank/template icon | `AppIcon.icns` is a placeholder; Launch Services cache doesn't update on fresh install | `Makefile`, `menu-bar/Resources/AppIcon.icns` |
| bug04 | Calendar permission dialog shows but app stays "not determined" | `EKEventStore` created as local var in `requestCalendar()` — deallocated before async callback fires | `PermissionChecker.swift:79` |
| bug05 | Notification "Show" opens Script Editor or wrong folder | Fallback `url.deletingLastPathComponent()` resolves wrong when `filePath` is empty | `AppDelegate.swift:97` |
| bug06 | Rejoin meeting within 3s after manual stop → no auto-record | `suppress_auto_start` reset requires `not active` — never fires if leave+rejoin faster than 3s poll | `teams_recorder_v2.py:1342` |

## Requirements

- **R4 (bug02):** Instructions tell user to click "+" if app is missing from Screen Recording list.
- **R5 (bug03):** Real icon on every `make menu-bar-install`. No manual `make icon` step.
- **R6 (bug04):** Calendar permission request always delivers its callback — no stuck "undetermined".
- **R7 (bug05):** Notification "Show" opens the recording file in Finder, or the recordings folder if file is gone.
- **R8 (bug06):** Manual stop then rapid rejoin auto-starts recording reliably.

## Implementation

### bug02 — `SetupWindowController.swift` Step 1 instructions (lines 55-59)

Replace the `instructions` string in the step 0 `StepInfo`:

```swift
instructions: "1. Click \"Add Team Recorder to Screen Recording\" below\n"
            + "2. macOS opens System Settings — find Team Recorder in the list\n"
            + "   If it's not there: click the + button and select TeamRecorderBar.app\n"
            + "3. Turn on the toggle next to Team Recorder\n"
            + "4. Come back here and click \"Relaunch App\"\n"
            + "   (macOS requires a relaunch after enabling this permission)",
```

### bug03 — Committed icon + `lsregister` in `make menu-bar-install`

1. Run `make icon` once and commit `menu-bar/Resources/AppIcon.icns`.
2. In `Makefile`, make `menu-bar` depend on `icon` so builds always include the latest icns.
3. Add after the `cp -r` in `menu-bar-install`:
   ```makefile
   @/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
       -f /Applications/TeamRecorderBar.app 2>/dev/null || true
   ```

### bug04 — `PermissionChecker.swift` retain `EKEventStore` (lines 78-93)

Add a static property to keep the store alive until the callback fires:

```swift
private static var calendarStore: EKEventStore?

static func requestCalendar(completion: @escaping (PermissionStatus) -> Void) {
    let store = EKEventStore()
    calendarStore = store
    if #available(macOS 14.0, *) {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                Self.calendarStore = nil
                completion(granted ? .granted : .denied)
            }
        }
    } else {
        store.requestAccess(to: .event) { granted, _ in
            DispatchQueue.main.async {
                Self.calendarStore = nil
                completion(granted ? .granted : .denied)
            }
        }
    }
}
```

### bug05 — `AppDelegate.swift` notification click fallback (lines 89-101)

```swift
func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
    let path = response.notification.request.content.userInfo["filePath"] as? String ?? ""
    if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    } else {
        NSWorkspace.shared.open(WatcherManager.shared.recordingDirectory())
    }
    completionHandler()
}
```

Add `recordingDirectory() -> URL` to `WatcherManager.swift` if it doesn't exist — reads `RECORDING_DIR` from `.env` (expanding `~`), falls back to `~/Documents/Teams Recording`.

### bug06 — `teams_recorder_v2.py` suppress_auto_start expiry (line 1274, 1342-1343, all `= True` sites)

Add timestamp alongside the flag (line 1274 region):
```python
suppress_auto_start    = False
suppress_auto_start_at = 0.0
```

Wherever `suppress_auto_start = True` is set (lines ~1417, ~1422, ~1442, ~1448), also set:
```python
suppress_auto_start_at = time.time()
```

Replace the reset block (lines 1342-1343):
```python
# Reset when inactive, OR after 30s expiry (handles leave+rejoin within poll window)
if not active and not in_meeting:
    suppress_auto_start = False
elif suppress_auto_start and (time.time() - suppress_auto_start_at) > 30:
    suppress_auto_start = False
    log("[INFO] suppress_auto_start expired — ready to auto-start again")
```

## Verification

1. **bug02:** Fresh install, Screen Recording revoked. Click "Add Team Recorder". If not in list, click "+" → select app → toggle on → Relaunch. Works.
2. **bug03:** `make clean-reinstall`. Menu bar shows Team Recorder icon immediately, no logout needed.
3. **bug04:** Revoke Calendar. Open Setup Guide, reach Step 3, click "Grant Calendar Access". Prompt appears; click Allow. Chip turns green — callback fired.
4. **bug05:** Delete a recording file. Click "Show" on its notification → Finder opens the recordings folder (not Script Editor).
5. **bug06:** Auto-start a recording. Manual stop. Rejoin within 3s. Next poll (≤3s) auto-starts again. Separately: manual stop with no rejoin → suppress expires after 30s, log line confirms.
6. **Regression:** `make test` → 78 passed, 3 skipped.
