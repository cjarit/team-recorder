# Release Checklist

## Version bump (do first)

1. Update both fields in `menu-bar/Resources/Info.plist`:
   - `CFBundleShortVersionString` — human-readable (e.g. `1.1`)
   - `CFBundleVersion` — build number (e.g. `2`; increment each release)
2. Commit: `git commit -m "bump version to X.Y"`

## Build & test

- [ ] `make test` — 116 passed, 3 skipped (baseline as of v1.2.0; reconcile this number each release rather than letting it drift)
- [ ] `make menu-bar` — clean build, zero warnings
- [ ] `make doctor` — no errors on a clean machine
- [ ] `make release` — `dist/TeamRecorderBar-v*.zip` created; SHA256 emitted

## Setup flow verification

- [ ] Screen Recording step: instructions box + "Open System Settings" + "Relaunch App" shown; no "Grant Access"
- [ ] Mic step: "Grant Access" when undetermined; "Open System Settings" when denied; no relaunch button
- [ ] Calendar step: grants Calendar access → status shows "Calendar bridge ready — recordings will use meeting titles." → `events-today.json` written to Application Support
- [ ] Skip for Now: disabled until required Screen Recording permission/relaunch path is complete
- [ ] Close button (×): app remains idle if setup is incomplete
- [ ] Recover Recorder… clears stale `recording` / stuck `stopping` state without restarting the app
- [ ] Saved-recording notification opens Finder with the `.m4a` selected

## Cross-reference sweep (must be zero hits before release)

```bash
grep -rn "docs/dev\|docs/plans\|docs/archive\|packaging/" \
  --include="*.md" --include="*.swift" --include="*.py" \
  --include="Makefile" --include="*.sh" . \
  --exclude-dir=plan --exclude-dir=project-context --exclude-dir=archive
```

Hits in `plan/archive/` or `plan/DECISIONS.md` are intentional historical references — only active files matter.

## After release

- [ ] Tag commit: `git tag vX.Y`
- [ ] Archive phase plan to `plan/archive/`
