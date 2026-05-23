# Release Checklist

## Version bump (do first)

1. Update both fields in `menu-bar/Resources/Info.plist`:
   - `CFBundleShortVersionString` — human-readable (e.g. `1.1`)
   - `CFBundleVersion` — build number (e.g. `2`; increment each release)
2. Commit: `git commit -m "bump version to X.Y"`

## Build & test

- [ ] `make test` — 76 passed, 3 skipped (baseline)
- [ ] `make menu-bar` — clean build, zero warnings
- [ ] `make doctor` — no errors on a clean machine
- [ ] `make dist` — `dist/TeamRecorder.zip` created; LOCAL MACHINE ONLY warning shown

## Setup flow verification

- [ ] Screen Recording step: instructions box + "Open System Settings" + "Relaunch App" shown; no "Grant Access"
- [ ] Mic step: "Grant Access" when undetermined; "Open System Settings" when denied; no relaunch button
- [ ] Calendar step: same as mic step
- [ ] Skip for Now: watcher starts, `setupCompleted` saved
- [ ] Close button (×): watcher starts, `setupCompleted` saved

## After release

- [ ] Tag commit: `git tag vX.Y`
- [ ] Archive phase plan to `docs/plans/`
