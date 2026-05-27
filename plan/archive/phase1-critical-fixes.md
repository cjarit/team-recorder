# Phase 1 — Critical Bug Fixes (COMPLETED)

Fixes: bug01 (Setup Step 3 deadlock), silent watcher failures, missing clean-uninstall command.

## Requirements

- **R1 (bug01):** Setup Step 3 always allows completion when Calendar is granted; icalBuddy probe is advisory only.
- **R2 (silent watcher failure):** Launch failures surface a ⚠ menu item with reason + recovery actions. Never silently idle.
- **R3 (clean reinstall):** `make uninstall` removes the app, runtime state, and prefs in one command.

## Root Cause Map

| Bug | File:Lines | Cause |
|---|---|---|
| bug01 Finish stuck | `SetupWindowController.swift:441-463` | Finish early-returns into `primeIcalBuddyAndRefresh()` and only advances when `icalBuddyPrimed==true` |
| icalBuddy false-denial | `PermissionChecker.swift:98-153` | Probe parsed keywords instead of trusting exit code; Swift path resolution order differed from Python |
| Watcher silently fails | `WatcherManager.swift:69-103` | stdout/stderr piped to `/dev/null`; no preflight; no early-crash detection |
| No uninstall | `Makefile` | No `uninstall` or `clean-reinstall` targets existed |

## Files Changed

- `menu-bar/Sources/TeamRecorderBar/SetupWindowController.swift` — replaced `icalBuddyPrimed: Bool` with `IcalBuddyProbeState` tri-state; removed Finish deadlock; added Step 3 entry probe auto-run; renamed Skip → "Use system permission only"
- `menu-bar/Sources/TeamRecorderBar/PermissionChecker.swift` — exit-code-based probe; Python-aligned path order (process env → `.env` → `which` → homebrew); timeout 8s→4s; one retry on ambiguous non-zero
- `menu-bar/Sources/TeamRecorderBar/WatcherManager.swift` — `LaunchError` enum; `lastLaunchError` published property; python3 preflight; stderr capture via Pipe; early-exit detection (< 3s); `clearLaunchErrorIfRunning()` for external watcher detection
- `menu-bar/Sources/TeamRecorderBar/StatusBarController.swift` — `launchWarningItem` shown on error; "Retry icalBuddy Access" in Permissions submenu; `updateLaunchWarning()` on every refresh
- `Makefile` — `uninstall` target (stop watcher, quit app, rm .app, clear prefs, rm status.json + PID files, print TCC revoke instructions); `clean-reinstall: uninstall menu-bar-install`
- `docs/user/troubleshooting.md` — "Menu bar shows ⚠ Can't start watcher" table; "Clean uninstall" section
- `README.md` — added `make uninstall` and `make clean-reinstall` to commands table
- `CLAUDE.md` — Known Issues rows for watcher_path.txt, bug01, icalBuddy path

## Key Design Decisions

- `EKEventStore` deallocation in `requestCalendar()` was identified as a bug but was not part of Phase 1 scope — moved to Hotfix field bugs.
- icalBuddy probe one-retry logic extracted to `runIcalBuddyProbe()` helper in `PermissionChecker.swift`.
- `clearLaunchErrorIfRunning()` added after discovering stale warning when using `make run` alongside the menu bar app.

## Verification (QA Matrix)

1. **bug01 repro:** Revoke icalBuddy in Automation. Run Setup Guide; grant Calendar; click Finish → setup completes with yellow advisory.
2. **Step 3 entry probe:** Open Setup Guide with Calendar already granted → probe auto-runs on step entry, Finish stays enabled.
3. **Stale path repro:** Edit `watcher_path.txt` to non-existent path → ⚠ appears, not silent idle.
4. **Early-exit repro:** Remove `python3` from PATH → `.pythonNotFound` surfaced in menu.
5. **icalBuddy path parity:** Set `ICAL_BUDDY_PATH=/tmp/fake-bin` in `.env` → both `make run` (Python) and probe (Swift) report failure against same path.
6. **`make uninstall`:** Removes app, prefs, status.json, PID files; recordings folder untouched; prints TCC instructions.
7. **`make clean-reinstall`:** Full cycle; new `watcher_path.txt` correct; no stale icon state.
