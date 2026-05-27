# Hotfix-2 — Field Followups (bug03 retry, bug05 retry, bug07)

Re-install from GitHub confirmed Hotfix 1 closed bug01/02/04/06, but bug03 and bug05 still happen. A new issue (bug07) was also observed: silently revoking icalBuddy gives no feedback.

## Bug Summary

| Bug | Symptom | Real Root Cause | File |
|---|---|---|---|
| bug03 (retry) | Login Items / Finder shows blank/template icon despite committed icns + lsregister | macOS Launch Services cache is sticky for file-copied bundles; `lsregister -f` alone doesn't always invalidate it | `Makefile` (menu-bar-install target) |
| bug05 (retry) | Notification "Show" opens Script Editor (iCloud) when file missing | `NSWorkspace.shared.open(dir)` on a non-existent or iCloud-synced `~/Documents/Teams Recording/` falls through to a wrong handler instead of Finder | `AppDelegate.swift:92-99` |
| bug07 (new) | Toggle off icalBuddy → no visible indicator anywhere in the app | Probe only runs during Setup and on explicit "Retry icalBuddy Access" — never re-checked passively | `StatusBarController.swift:175-185, 477-495` |

## Requirements

- **R9 (bug03):** Real app icon appears in Finder, Login Items, and About-this-Mac after `make clean-reinstall` — no logout required (best-effort; see caveat).
- **R10 (bug05):** Notification "Show" always opens Finder, regardless of whether `~/Documents/Teams Recording/` exists, contains the file, or is iCloud-synced.
- **R11 (bug07):** User sees current icalBuddy permission status without needing to manually click "Retry".

## Implementation

### bug03 — `Makefile` menu-bar-install: add `touch` before lsregister

Adding `touch` updates the bundle's mtime, which signals to Launch Services that the bundle changed and should be re-evaluated.

```makefile
menu-bar-install: menu-bar
	@echo "  ⏳  Installing TeamRecorderBar.app..."
	@rm -rf /Applications/TeamRecorderBar.app
	@cp -r "$(MENU_BAR_APP)" /Applications/
	@touch /Applications/TeamRecorderBar.app   # ← NEW: bump mtime so LS notices
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
	    -f /Applications/TeamRecorderBar.app 2>/dev/null || true
	@echo "  ✓  Installed → /Applications/TeamRecorderBar.app"
	@echo "  ⏳  Opening Team Recorder..."
	@open /Applications/TeamRecorderBar.app
	...
```

### bug05 — `AppDelegate.swift` notification fallback: create dir + `selectFile`

`NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath:)` is explicit — it always opens Finder rooted at the given path, never falls through to another handler.

Replace the current `didReceive` body:

```swift
func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
    let path = response.notification.request.content.userInfo["filePath"] as? String ?? ""
    if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    } else {
        // File missing — open the recordings folder explicitly in Finder
        let dir = WatcherManager.shared.recordingDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }
    completionHandler()
}
```

Why `selectFile(nil, inFileViewerRootedAtPath:)` over `open()`:
- `open(url)` consults LaunchServices for the default handler — for a URL inside iCloud Drive (`~/Library/Mobile Documents/...` or a Documents folder synced to iCloud), this can resolve to an unexpected app.
- `selectFile(nil, inFileViewerRootedAtPath:)` always uses Finder by contract.

`createDirectory(withIntermediateDirectories: true)` is a no-op if the dir already exists, so it's safe to call every time.

### bug07 — `StatusBarController.swift` icalBuddy status indicator

Two parts:

**Part 1 — Show last-known state in the menu item title immediately**

The existing "Retry icalBuddy Access" item already lives in the Permissions submenu (lines 175-182). Reword its title based on the cached `UserDefaults.standard.bool(forKey: "icalBuddyVerified")` (already set by `SetupWindowController.swift:421`).

Store the menu item as a property so it can be updated later:
```swift
private var icalBuddyStatusItem: NSMenuItem!
```

In `buildMenu()`, store the reference instead of letting it go out of scope:
```swift
icalBuddyStatusItem = NSMenuItem(
    title: icalBuddyMenuTitle(verified: UserDefaults.standard.bool(forKey: "icalBuddyVerified")),
    action: #selector(retryIcalBuddyAccess),
    keyEquivalent: ""
)
icalBuddyStatusItem.target = self
icalBuddyStatusItem.toolTip = "Click to re-probe icalBuddy Calendar access."
permSubmenu.addItem(icalBuddyStatusItem)
```

Helper:
```swift
private func icalBuddyMenuTitle(verified: Bool) -> String {
    verified ? "icalBuddy: Verified ✓  (click to re-check)"
             : "icalBuddy: No Access ⚠  (click to re-check)"
}
```

**Part 2 — Re-probe on menu open, update title async**

Make `StatusBarController` conform to `NSMenuDelegate` and set itself as the Permissions submenu's delegate:
```swift
permSubmenu.delegate = self
```

Implement:
```swift
func menuWillOpen(_ menu: NSMenu) {
    // Only re-probe when the Permissions submenu opens
    guard menu === icalBuddyStatusItem.menu else { return }
    PermissionChecker.primeIcalBuddyCalendar(
        projectDirectory: WatcherManager.shared.projectDirectory
    ) { [weak self] ok, _ in
        DispatchQueue.main.async {
            UserDefaults.standard.set(ok, forKey: "icalBuddyVerified")
            self?.icalBuddyStatusItem.title = self?.icalBuddyMenuTitle(verified: ok) ?? ""
        }
    }
}
```

This is fire-and-forget — the menu shows the cached state immediately (no blocking) and updates the title within ~4s of opening the submenu. If the user closes the menu before the probe finishes, the next open reflects the fresh state.

**Why not poll periodically?** Polling icalBuddy every N seconds wakes the calendar daemon and contributes to permission prompt fatigue. Probing only when the user opens the Permissions submenu is the right scope.

## Files Touched

- `Makefile` — bug03 (one-line `touch` added)
- `menu-bar/Sources/TeamRecorderBar/AppDelegate.swift` — bug05 (notification fallback rewritten)
- `menu-bar/Sources/TeamRecorderBar/StatusBarController.swift` — bug07 (NSMenuDelegate, status item property, helper, menuWillOpen)

## Verification

1. **bug03:** `make clean-reinstall`. Check:
   - `/Applications/TeamRecorderBar.app` in Finder Get Info shows the blue waveform icon
   - System Settings → General → Login Items shows Team Recorder with real icon (after toggling Launch at Login)
   - No logout/reboot required
2. **bug05 — file present:** Record a meeting end-to-end. Click "Show" on the notification within a second — Finder opens with the file selected.
3. **bug05 — file missing:** Record a meeting, manually delete the .m4a file, click "Show" — Finder opens to the recordings folder, **never Script Editor**.
4. **bug05 — folder missing:** With `~/Documents/Teams Recording/` removed, simulate a notification (or remove file & click Show) — fallback creates the folder and opens Finder.
5. **bug07 — initial state:** Fresh install with icalBuddy granted. Open Permissions submenu — item reads "icalBuddy: Verified ✓ (click to re-check)".
6. **bug07 — revoked detection:** System Settings → Privacy & Security → Automation → toggle icalBuddy off. Re-open Permissions submenu. Item reads "icalBuddy: Verified ✓" instantly (cached), then updates to "icalBuddy: No Access ⚠" within ~4s. Close and re-open the submenu — now reads "No Access ⚠" instantly.
7. **bug07 — re-grant:** Toggle icalBuddy back on in System Settings. Re-open Permissions submenu — within ~4s updates to "Verified ✓".
8. **Regression:** `make test` → 78 passed, 3 skipped.

## Caveats

- **bug03:** macOS icon cache is genuinely unpredictable for ad-hoc-signed apps installed by file copy. `touch + lsregister` materially improves the success rate but cannot guarantee 100%. The complete fix requires Phase 3 (signed installer with a stable identity). If the icon still shows blank after this fix, document `killall Finder` or logout as the manual recovery.
- **bug07:** The probe runs `icalBuddy` as a subprocess each time the menu opens. That's lightweight (~100 ms when granted, up to 4s on denial timeout) but if a user pumps the submenu open/close rapidly, multiple probes can stack. Mitigation: track an `icalBuddyProbeInFlight: Bool` and skip if true.
