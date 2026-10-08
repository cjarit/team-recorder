# Release Checklist

## Version bump (do first)

1. Update both fields in `menu-bar/Resources/Info.plist`:
   - `CFBundleShortVersionString` — human-readable (e.g. `2.0.0`)
   - `CFBundleVersion` — build number (increment each release)
2. Set `VERSION` in the `Makefile` to the same value (`2.0.0`) — it names the zip and dmg
3. Commit: `git commit -m "bump version to X.Y.Z"`

v2.x releases are cut from `main`; v1.2.x bug-fix releases from `release/1.x`.

## Build & test

- [ ] `make test` — 137 passed, 3 skipped (baseline as of v2.0.0; reconcile this number each release rather than letting it drift)
- [ ] `make cert-check` — signing identity "Team Recorder Signing" present (on a new Mac: `make cert`, then the `security set-key-partition-list …` command from the README developer section, run by the owner)
- [ ] `make menu-bar` — clean build, zero warnings
- [ ] `codesign -dr - menu-bar/.build/TeamRecorderBar.app` — designated requirement references the certificate and `com.team-recorder.menu-bar`, no `cdhash`
- [ ] `make doctor` — no errors on a clean machine
- [ ] `make release` — `dist/TeamRecorderBar-v*.zip` and `dist/TeamRecorderBar-v*.dmg` created; SHA256 of the zip emitted
- [ ] Open the `.dmg`: app + Applications link present; drag-install works

## Upgrade verification (identity)

- [ ] Rebuild + reinstall over an existing cert-signed install (`scripts/tcc-persist-test.sh "<label>"`): `make doctor` still reports all three permissions granted with no System Settings interaction
- [ ] Install over a build whose watcher is still running (`scripts/phase2-upgrade-check.sh`): the new app stops the old watcher and starts a fresh one, `.env` and tracked calendars intact
- [ ] From a v1.2.x install: Setup Guide shows the "remove the old row with −" instruction; after re-grant, Screen Recording works

## Setup flow verification

- [ ] Screen Recording step: instructions box + "Open System Settings" + "Relaunch App" shown; no "Grant Access"
- [ ] Mic step: "Grant Access" when undetermined; "Open System Settings" when denied; no relaunch button
- [ ] Calendar step: grants Calendar access → status shows "Calendar bridge ready — recordings will use meeting titles." → `events-today.json` written to Application Support
- [ ] Calendar step can be skipped; afterwards Permissions rows and the popover show Calendar as "Skipped", not missing
- [ ] Skip for Now: disabled until required Screen Recording permission/relaunch path is complete
- [ ] Close button (×): app remains idle if setup is incomplete
- [ ] Recover Recorder… clears stale `recording` / stuck `stopping` state without restarting the app
- [ ] Saved-recording notification opens Finder with the `.m4a` selected

## UI verification (on device, light and dark)

- [ ] Popover: Recording (two level bars Others / My mic), Ready (Start Recording Now), Paused, Error (Recover Recorder…)
- [ ] Right-click menu has exactly 5 items: Open Team Recorder…, Pause/Start Watching, Setup Guide…, Uninstall Team Recorder…, Quit
- [ ] Window tabs Status / General / Calendars / Permissions open and match `plan/v2.0-ui-inventory.md` "v2.0 homes"
- [ ] Microphone picker and Record my voice are disabled while recording
- [ ] Uninstall Team Recorder…: app moved to Trash, recordings and settings kept
- [ ] A silent recording of 3 min or more lands in `Empty/` with a notification; a short call is not moved

## Cross-reference sweep (must be zero hits before release)

```bash
grep -rn "docs/dev\|docs/plans\|docs/archive\|packaging/" \
  --include="*.md" --include="*.swift" --include="*.py" \
  --include="Makefile" --include="*.sh" . \
  --exclude-dir=plan --exclude-dir=project-context --exclude-dir=archive
```

Hits in `plan/archive/` or `plan/DECISIONS.md` are intentional historical references — only active files matter.

## After release

- [ ] Tag commit: `git tag vX.Y.Z`
- [ ] GitHub Release: attach the `.dmg` and the `.zip`; release notes in `plan/release-notes-vX.Y.Z.md` (the `make release` hint reads this file)
- [ ] v1.2.4 stays published for macOS 14; do not mark v2.x as replacing it for Sonoma users
- [ ] Archive phase plan to `plan/archive/`
