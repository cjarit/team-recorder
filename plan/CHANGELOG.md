# Changelog — Team Recorder

## v1.1.0 — 2026-05-29

### Compact recordings

- AAC encoder lowered to 16 kHz mono / 32 kbps — ASR-optimised (Whisper/NotebookLM)
- ~3× smaller files (~14 MB/hr vs ~43 MB/hr); no transcript quality regression
- `kSampleRate` constant used in three places (AAC settings, mic resampling, SCK delivery rate) — single-constant change

### Per-user calendar picker

- `CalendarEventBridge`: new `trackedCalendarIds` UserDefaults allowlist (`nil` = all, `[]` = explicit zero-selection, `[ids]` = filter)
- Stale IDs silently ignored at query time — never auto-removed during 60s timer ticks (guards against transient Exchange/Google sync outages)
- Each event dict now includes `calendar` (display name) and `calendarId` (stable identifier) fields
- New `CalendarsSubmenuDelegate` in `StatusBarController`: dynamic submenu rebuilt on every open; handles no-permission, empty-list, and 9+ calendar states

### Menu bar UX

- `buildMenu()` rewritten: 5 groups, SF Symbol images on all actionable items
- Status line: colored SF Symbol per state (red = recording, orange = error); all Unicode glyphs removed
- `toggleWatcher` dims status icon during 0.5s launch gap (microinteraction feedback)

### Tests

- Live smoke test now asserts output file < 200 KB for ~2s recording (catches accidental bitrate revert)

---

## v1.0.0 — 2026-05-27

First public GitHub release. All changes are packaging and portability — no new recording features.

### Portability

- **Self-contained `.app`** — no Homebrew, no Python pre-install, no `icalBuddy` required for public users
- `watcher.pyz` (zipapp): `teams_recorder_v2.py` + `python-dotenv` bundled for `/usr/bin/python3` (ships with macOS 14)
- `recorder` binary embedded in `TeamRecorderBar.app/Contents/Resources/` and re-signed with entitlements
- `WatcherManager` resolves all paths from `Bundle.main` — no absolute paths baked at build time
- `.env` bootstrapped to `~/Library/Application Support/Team Recorder/.env` on first app launch; developer path (`make run`) still reads repo-root `.env` unchanged

### Calendar

- `CalendarEventBridge` (Swift) wired at app startup and on calendar-change notifications — writes `events-today.json` to App Support
- `_read_events_bridge()` prefers bridge file over `icalBuddy`; falls back after 5-minute staleness
- `icalBuddy` remains available as a fallback on the `make run` / Terminal path

### Setup UX

- Environment preflight added to `SetupWindowController`: checks `watcher.pyz`, `recorder` binary, and `/usr/bin/python3 ≥ 3.9` before showing permission steps
- Specific error messages with remediation actions for each failure case

### macOS target

- Minimum OS bumped to **macOS 14 Sonoma** in both Swift packages and `Info.plist`
- `setup.sh` and runtime version checks updated to gate on 14+

### Docs

- `README.md`: public Releases download is the primary install path; developer path is secondary
- `docs/user/setup.md`: Releases-first rewrite; no Homebrew in primary path
- `docs/user/faq.md`: new file (8 questions covering Gatekeeper, calendar, recording location, error icons)
- `docs/user/troubleshooting.md`: error table updated to match new `LaunchError` messages

---

## Prior releases

All prior work was internal-only (no public GitHub releases before v1.0).
Historical phase plans: see `plan/archive/`.
