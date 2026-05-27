# Feature: Team Recorder v1.0 — Clean-Mac Public Release

> Requirements spec — Phase 3 output. Drives Phase 4 implementation.
> Format: EARS (Easy Approach to Requirements Syntax) + Given/When/Then acceptance criteria.

---

## Overview

A new user with a clean macOS 14 Sonoma machine (no Homebrew, no Python dependencies,
no icalBuddy) downloads `TeamRecorderBar.app` from GitHub Releases, opens it, completes
a guided Setup flow, and records their first Teams meeting — all without touching a terminal.

Today this fails at first launch because the `.app` bakes absolute paths to the developer's
machine and requires external dependencies. This spec defines what must change to make the
install portable and self-contained.

**Constraint:** No new product features. All requirements are portability, packaging, and
first-run UX corrections to existing behaviour.

---

## Functional Requirements

### FR-BUNDLE-001: Bundle-relative watcher resolution
The system shall resolve the path to `teams_recorder_v2.py` (or `watcher.pyz`) exclusively
from `Bundle.main.resourceURL` at runtime.

_Replaces: reading `watcher_path.txt` (absolute path written at build time by Makefile)._

### FR-BUNDLE-002: Bundle-relative Python resolution
The system shall resolve the Python interpreter path by checking `/usr/bin/python3`
(system Python, ships with macOS 14) without reading any baked path file from the bundle.

_Replaces: reading `python_path.txt` (absolute Homebrew path baked at build time)._

### FR-BUNDLE-003: Watcher packaged as zipapp
The system shall bundle `teams_recorder_v2.py` and its pip dependency (`python-dotenv`)
as a single `watcher.pyz` zipapp file inside `TeamRecorderBar.app/Contents/Resources/`.
(`psutil` is not a dependency — stdlib + dotenv only.)

### FR-DEPS-001: Zero Homebrew requirement for .app users
When launched as a `.app`, the system shall start and record successfully on a clean
macOS 14 install with no Homebrew, no `icalBuddy`, and no manually installed pip packages.

### FR-DEPS-002: icalBuddy as developer-path fallback only
While running via `make run` or Terminal, the system shall use `icalBuddy` for calendar
lookups if available, unchanged from current behaviour.

Where `icalBuddy` is unavailable on the `make run` path, the system shall warn and
continue (current `[WARN]` behaviour, unchanged).

### FR-CAL-001: Prefer CalendarEventBridge JSON
When `~/Library/Application Support/Team Recorder/events-today.json` exists and was
written within the last 5 minutes, the system shall read calendar events from that file
instead of invoking `icalBuddy`.

### FR-CAL-002: icalBuddy fallback from .app
While running as `.app`, when `events-today.json` is missing or older than 5 minutes,
the system shall attempt `icalBuddy` as a fallback and log `[WARN] bridge file stale —
falling back to icalBuddy`.

### FR-CAL-003: CalendarEventBridge wired at startup
When `TeamRecorderBar.app` finishes launching, the system shall invoke
`CalendarEventBridge` to write or refresh `events-today.json` if Calendar permission
has been granted.

### FR-ENV-001: App-mode config location
When `TEAM_RECORDER_APP=1` is set in the subprocess environment (set by `WatcherManager`),
the system shall load and write `.env` from the path provided in the `ENV_FILE` env var
(`~/Library/Application Support/Team Recorder/.env`).

### FR-ENV-002: Developer-mode config location
When `TEAM_RECORDER_APP` is unset (i.e., `make run` / Terminal), the system
shall load `.env` from the repository root — current behaviour, unchanged.

### FR-ENV-003: Bootstrap .env on first launch
While `TEAM_RECORDER_APP=1`, when the `ENV_FILE` path does not exist, the system shall
create it with hardcoded defaults (`RECORDING_DIR=~/Documents/Teams Recording` plus
empty optional keys). The bootstrap is idempotent — an existing file is never overwritten.

### FR-SETUP-001: Environment preflight check
When `SetupWindowController` opens, the system shall run a preflight check before
showing permission steps, validating:
- `recorder` binary is present in bundle and executable
- `watcher.pyz` is present in bundle
- `/usr/bin/python3` is version 3.9 or higher

### FR-SETUP-002: Preflight failure — surface actionable error
When any preflight check in FR-SETUP-001 fails, the system shall display a specific
error message and a remediation action, and shall not advance to the permission steps
until the issue is resolved or the user explicitly dismisses.

### FR-SETUP-003: Gatekeeper bypass documented
The system's public README shall document the right-click → Open bypass required for
ad-hoc-signed apps, with a step-by-step description and a screenshot showing the
Gatekeeper dialog.

### FR-LAUNCH-001: WatcherManager sets launch mode
When `WatcherManager` spawns the Python watcher process, the system shall set
`TEAM_RECORDER_APP=1`, `ENV_FILE` (path to App Support `.env`), and `RECORDER_BIN`
(path to the bundled `recorder` binary) in the subprocess environment.

---

## Non-Functional Requirements

### Portability
- The release `.app` shall function correctly on any macOS 14+ machine without any
  pre-installation steps beyond granting the three permissions (Screen Recording,
  Microphone, Calendar).
- No absolute paths referencing the build machine shall exist inside the `.app` bundle
  at release time.

### Performance
- `watcher.pyz` bundle size shall not exceed 5 MB.
- Release zip (`TeamRecorderBar-v1.0.0.zip`) shall not exceed 50 MB.
- Setup flow (permissions + first launch) shall complete within 5 minutes on a clean machine.

### Reliability
- The `.env` bootstrap (FR-ENV-003) shall be idempotent: running it multiple times shall
  not overwrite user-edited values already present in the file.
- The CalendarEventBridge fallback to `icalBuddy` (FR-CAL-002) shall not crash or exit
  non-zero if `icalBuddy` is also absent; it shall log a warning and continue.

### Security
- The release `.app` shall be ad-hoc signed (`codesign -s -`) with the screen-capture
  and microphone entitlements from `recorder/entitlements.plist`.
- No credentials, API keys, or `.env` content shall be included in the release zip.

---

## Acceptance Criteria

### AC-001: Clean-Mac install completes without terminal
Given a macOS 14 Sonoma machine with no Homebrew, no Python deps, and no prior
Team Recorder install,
When the user downloads the zip from GitHub Releases, unzips it, drags the `.app` to
`/Applications/`, right-clicks → Open, and follows the Setup Guide,
Then Setup completes without any terminal command required.

### AC-002: Watcher starts from bundle, not from repo path
Given the `.app` is installed on a machine where the source repository does not exist,
When the user starts the watcher via the menu-bar app,
Then the watcher process starts successfully using the bundled `watcher.pyz`.

### AC-003: Recording produces a renamed file on clean machine
Given a clean macOS 14 machine with no icalBuddy installed,
When the user joins a Teams meeting lasting at least 3 minutes and then leaves,
Then a `.m4a` file named after the calendar event (or "Teams Meeting" if calendar
is unavailable) appears in the recordings folder.

### AC-004: CalendarEventBridge is used over icalBuddy when fresh
Given `events-today.json` exists and was written less than 5 minutes ago,
When Python resolves the meeting title for a recording,
Then it reads from `events-today.json` and does not invoke `icalBuddy`.

### AC-005: Stale bridge falls back to icalBuddy
Given `events-today.json` was last written more than 5 minutes ago,
When Python resolves the meeting title,
Then it attempts `icalBuddy` and logs `[WARN] bridge file stale`.

### AC-006: .env written to App Support in app mode
Given the `.app` is launched for the first time with no prior config,
When the watcher starts,
Then `~/Library/Application Support/Team Recorder/.env` is created with default values
and the watcher reads config from that path.

### AC-007: make run still reads repo-root .env
Given a developer has a `.env` in the repository root,
When they run `make run`,
Then the watcher reads config from the repository root `.env`, not from App Support.

### AC-008: Preflight blocks setup on missing recorder binary
Given the `recorder` binary is absent from the `.app` bundle (simulated corruption),
When `SetupWindowController` opens,
Then the user sees a specific error message ("App bundle is corrupted — re-download
from GitHub Releases") and cannot proceed to permission steps.

### AC-009: Preflight blocks setup on Python below 3.9
Given `/usr/bin/python3` is version 3.8 or lower (or absent),
When `SetupWindowController` opens,
Then the user sees a specific error message with a remediation action and cannot
proceed to permission steps.

### AC-010: .env bootstrap is idempotent
Given `~/Library/Application Support/Team Recorder/.env` already exists with a
user-edited `RECORDING_DIR`,
When the app launches and FR-ENV-003 bootstrap runs,
Then the existing `.env` is not overwritten and `RECORDING_DIR` retains its value.

---

## Error Handling

| Error condition | Detected in | User-visible message | Behaviour |
|---|---|---|---|
| `recorder` binary missing from bundle | `SetupWindowController` preflight | "App bundle is corrupted. Re-download from GitHub Releases." | Block setup; show remediation |
| `watcher.pyz` missing from bundle | `SetupWindowController` preflight | "App bundle is corrupted. Re-download from GitHub Releases." | Block setup; show remediation |
| System Python missing or < 3.9 | `SetupWindowController` preflight | "Python 3.9+ required. Install Xcode Command Line Tools: `xcode-select --install`" | Block setup; show terminal command |
| `.env` write failed (permissions) | `WatcherManager` / Python startup | "Could not write config to ~/Library/Application Support/Team Recorder/" | Block watcher start; show path in menu |
| `events-today.json` stale or missing | `teams_recorder_v2.py` | (silent in UI) `[WARN] bridge file stale — falling back to icalBuddy` in log | Fall back to icalBuddy |
| Both bridge and icalBuddy unavailable | `teams_recorder_v2.py` | (silent in UI) `[WARN] calendar unavailable — using "Teams Meeting"` in log | Continue; recording named "Teams Meeting" |
| Gatekeeper blocks first open | macOS / user | Shown by macOS: "TeamRecorderBar cannot be opened because it is from an unidentified developer" | README documents right-click → Open bypass |

---

## Implementation TODO

_This is Phase 4's execution checklist. Each item maps to a file in the codebase._

### Swift — `WatcherManager.swift`
- [ ] Remove reads of `watcher_path.txt` and `python_path.txt`
- [ ] Resolve watcher via `Bundle.main.url(forResource: "watcher", withExtension: "pyz")`
- [ ] Resolve Python via `/usr/bin/python3` (no bundle file needed)
- [x] Set `TEAM_RECORDER_APP=1`, `ENV_FILE`, `RECORDER_BIN` in subprocess environment
- [ ] Verify `recorder` binary path at preflight (pass result to `SetupWindowController`)

### Swift — `SetupWindowController.swift`
- [ ] Add Environment Check as step 0 (before Screen Recording step)
- [ ] Check: `recorder` binary present and executable
- [ ] Check: `watcher.pyz` present in bundle
- [ ] Check: `/usr/bin/python3 --version` returns 3.9+
- [ ] Show specific error + remediation per failed check; block progression
- [ ] Pass preflight results from `WatcherManager` to avoid duplicate checks

### Swift — `AppDelegate.swift` / `CalendarEventBridge.swift`
- [ ] Confirm `CalendarEventBridge.writeEventsIfAuthorized()` is called on launch and on calendar-change notification
- [ ] Confirm write path is `~/Library/Application Support/Team Recorder/events-today.json`

### Python — `teams_recorder_v2.py`
- [ ] Add `read_events_from_bridge_json()` — reads and validates `events-today.json`; returns `None` if missing or > 5 min stale
- [ ] In `find_matching_meeting()`, call bridge reader first; fall back to `icalBuddy` if `None`
- [ ] Add dual-source `.env` loader before `load_dotenv()`: app mode → App Support path; else → repo root
- [ ] Bootstrap App Support `.env` from bundled `.env.example` if absent (app mode only)
- [ ] Keep main loop and all tuned constants untouched (per CLAUDE.md)

### Tests — `test_recorder_v2.py`
- [ ] `test_bridge_json_preferred_when_fresh` — mock fresh `events-today.json`; assert icalBuddy not called
- [ ] `test_bridge_json_fallback_when_stale` — mock stale file; assert icalBuddy called
- [ ] `test_bridge_json_fallback_when_missing` — no file; assert icalBuddy called
- [x] `test_env_bootstrap_creates_defaults_in_app_mode` — `TEAM_RECORDER_APP=1`, file absent; assert created with default RECORDING_DIR
- [x] `test_env_bootstrap_creates_parent_directory` — nested missing dirs; assert created
- [x] `test_env_bootstrap_skipped_without_app_mode` — env var absent; assert no file created
- [x] `test_env_bootstrap_idempotent` — existing `.env` with custom value; assert value preserved after bootstrap

### Makefile
- [ ] Add `watcher-pyz` target: builds `watcher.pyz` using `python3 -m zipapp`
- [ ] Add `watcher-pyz` as dependency of `menu-bar` target
- [ ] In `menu-bar` target: copy `watcher.pyz` to `.app/Contents/Resources/`
- [ ] In `menu-bar` target: copy `recorder/recorder` binary to `.app/Contents/Resources/`
- [ ] In `menu-bar` target: copy `.env.example` to `.app/Contents/Resources/`
- [ ] Remove lines that write `watcher_path.txt` and `python_path.txt` into bundle
- [ ] Add `release` target (Phase 6): builds portable zip + SHA256

### Docs — `README.md`
- [ ] Add Gatekeeper right-click → Open bypass description (text + screenshot placeholder)

---

## Out of Scope

- Apple Developer ID notarization (ad-hoc signing + Gatekeeper bypass docs is the chosen approach)
- Bundling a full Python runtime (PyInstaller/PyApp) — Plan A (zipapp + system Python) is used; Plan B is fallback only if system Python proves unreliable
- Replacing `icalBuddy` on the `make run` / developer path — it stays as fallback
- New recording features (transcription, cloud sync, multi-meeting batching)
- Refactoring `teams_recorder_v2.py` main loop (CLAUDE.md: do not refactor)
- Support for macOS 13 Ventura or earlier

---

## Open Questions

- [ ] **Smoke test (Phase 2):** Sonoma 14 device unavailable — must be completed before Phase 6 release. Record a real Teams meeting on clean Sonoma 14; confirm rename.
- [ ] **System Python version on Sonoma:** macOS 14 ships `/usr/bin/python3` at 3.9.6. Confirm this is still the case on a Sonoma 14 VM before finalising FR-BUNDLE-002. If Apple has removed it, fallback Plan B (PyInstaller) activates.
- [x] **watcher.pyz wheel compatibility:** `psutil` is NOT a dependency — stdlib + `python-dotenv` only (pure Python). No arch-specific wheels needed. `make watcher-pyz` confirmed working.
