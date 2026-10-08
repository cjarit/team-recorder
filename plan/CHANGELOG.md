# Changelog — Team Recorder

## v2.0.0 — 2026-10-08

### Two release lines
- `main` = v2.x, macOS 15+ (Swift tools 6.0, language mode 5). `release/1.x` = macOS 14, bug fixes only; v1.2.4 remains published.

### Identity, install, upgrade
- Every build signed with the self-signed `Team Recorder Signing` certificate (`make cert`); TCC grants persist across reinstalls (gate: `plan/phase1-tcc-log.md`)
- Self-healing launch after a version change (stops the previous bundle's watcher, clears stale state, keeps `.env`/calendars/Launch at Login); stale-row instruction for Screen Recording when upgrading from the ad-hoc line
- `make dmg`; `make release` builds zip + dmg; Uninstall… menu item; Calendar step skippable (`PermissionStatus.skipped`)
- pgrep fallback counts only python processes

### UI
- SwiftUI popover (left-click) with live level meters; Settings/Status window (Status · General · Calendars · Permissions) incl. mic picker, Record my voice, Check for Updates (GitHub Releases API); right-click menu reduced to 5 items; all 25 v1.2.4 actions mapped (`plan/v2.0-ui-inventory.md`)
- `permissions.json` snapshot written at launch

### Audio
- Mic via ScreenCaptureKit `captureMicrophone` by default (BT gate passed); `MIC_PATH=engine` fallback; `RECORD_MIC=0` = system audio only
- Clock-anchored track positions (`clockStart`/`appendAligned`): fixes the ~1 %/s skew between tracks (echo on speakers)
- `--mixdown`: speaker-bleed probe + delay-aware mic ducking; writes `<file>.meta.json` (speechRatio at −45 dBFS, bleedCorr, bleedLagMs, ducked)
- `levels.json` sidecar once per second while recording (sys/mic dBFS, micAlive, micPath, micMaxGap, buffer counters)
- App moves speechless recordings ≥ 180 s to `Empty/`; mic-silent notification after 60 s
- `SKIP_MIXDOWN=1` keeps two tracks for measurement (`scripts/xcorr.py`, `scripts/speech_ratio.py`)

### Removed
- `Setup.command`, `Start Recorder.command`
- Tests: 137 passed, 3 skipped

---

## v1.2.4 — 2026-09-29

### Resilient to Bluetooth hangs; single-track output for NotebookLM

- **Mic startup is now async** — all AVAudioEngine work runs on dedicated serial `micQ` queue; `start` emits STARTED immediately without waiting for mic (fixes 2026-09-29: 59-min block on `startMic` during Bluetooth HFP⇄A2DP mode switch)
- **Playable file on binary kill** — finalize AVAssetWriter before tearing down mic/SCK; if binary dies before cleanup, file is already a valid m4a with moov box (fixes 2026-09-28: unplayable file after stop timeout)
- **Mic teardown timeout→respawn** — `stop` waits max 5s for `micQ` cleanup, exits code 3 (planned respawn, not crash) if timeout; Python immediately re-spawns without backoff; status fields survive across respawns
- **Fragment interval = 10s** — `movieFragmentInterval` ensures partial kill leaves playable file up to last fragment
- **Silence-fill mic track** — when no mic data arrives, fill from system-audio clock (prevents AVAssetWriter fragment stalls after ~220s with missing track); max 1.0s lag between tracks
- **Post-record track merge** — `recorder --mixdown` called after each validated stop; merges system-audio + mic into single mono track (NotebookLM reads only first track; pre-v1.2.4 recordings missing user voice in transcripts); original kept if validation fails
- **Removed `cancelWriting()` on timeout** — confirmed it deletes the output file; now unnecessary since finalize happens before teardown
- **Start timeout→immediate respawn** — no ERROR stderr + no STARTED stdout within timeout = dead process; kill and respawn immediately, record as "error" status (one notification per meeting, deduped)
- Tests: 136 passed, 3 skipped (23 new tests covering hang recovery, mixdown, fragment/silence fill)
- Known issue: Bluetooth HFP⇄A2DP collision during recording not yet naturally reproduced (3 meet-now runs clean; 1 switch 6s post-stop = healthy). Confidence rests on design + 350s kill test (playable). PoC B (SCK captureMicrophone, macOS 15+, out-of-process) built unseen — deferred pending demand

---

## v1.1.1 — 2026-07-06

### Bug fix: Teams auto-detection stopped working after a Teams app update

- Microsoft Teams' 2026-07-03 update (build 26163.407.4839.8659) moved call-media UDP sockets (RTP/STUN/TURN) off the main `MSTeams` process onto a separate `Microsoft Teams ModuleHost` (SlimCore) helper process — the watcher was only checking `MSTeams`, so it never saw enough UDP traffic to count as "in a meeting"
- `get_teams_pid()` → `get_teams_pids()`: now unions `pgrep -x MSTeams` with `pgrep -f "Microsoft Teams ModuleHost"` and aggregates UDP connections across the whole process family in one `lsof -a -p <pid1,pid2,...>` call
- No changes to `POLL_INTERVAL`, `STOP_GRACE`, `MIN_DURATION`, or `UDP_MEET_THRESH` — same thresholds, just counted across the right processes now
- Verified live against a real, active Teams meeting before release
- 8 new unit tests covering the process-family resolution and the regression scenario (meeting only detectable via the ModuleHost helper)

---

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
