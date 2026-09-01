# Decisions — Team Recorder

Architectural and product decisions with rationale. Add new entries chronologically.

---

## 2026-05-26 — v1.0 release decisions

### Code signing: ad-hoc (not Apple Developer ID)
- **Decision:** Sign the .app with ad-hoc (`codesign -s -`). README documents the right-click → Open Gatekeeper bypass.
- **Rationale:** Avoids $99/yr Apple Developer Program cost. Users are internal Thai design team + trusted collaborators who can follow a one-time bypass.
- **Trade-off:** Users see a Gatekeeper warning on first open. Documented clearly in README.

### Minimum macOS: 14 Sonoma
- **Decision:** Bump both `Package.swift` platform targets from `.v13` to `.v14`.
- **Rationale:** Resolves SMAppService 13.0/13.1 ambiguity. EKEventStore full-access API requires 14. Aligns with team's actual hardware.
- **Trade-off:** macOS 13 Ventura users cannot run the app. Not a known user segment.

### Python bundling: Plan A = zipapp + system Python 3
- **Decision:** Bundle `teams_recorder_v2.py` + `dotenv` into `watcher.pyz` via `zipapp`. Use system `/usr/bin/python3` (ships with macOS 14 at 3.9.6).
- **Rationale:** Lightweight (~50KB bundle vs ~30MB PyInstaller), no notarization complications, no additional toolchain required.
- **Fallback (Plan B):** If `/usr/bin/python3` is absent or below 3.9 on Sonoma (must verify on real Sonoma device — open question in requirements spec), switch to PyInstaller `--onefile`. Activate by documenting here and updating `make watcher-pyz`.
- **Implementation note:** `psutil` is NOT a dependency — stdlib + `python-dotenv` only. No native C extensions, no arch-specific wheels needed.

### Template adoption: workspace-doctor structural adoption (with documented deviations)
- **Decision:** Migrate from `docs/dev/` + `docs/plans/` layout to `project-context/` + `plan/` per `~/Documents/Claude/Template/_meta/modules.yml`. This is a structural adoption — all folder modules are aligned, but several file-level items in the template's `core` module are deliberately omitted.
- **Rationale:** Consistency with all other Claude/AI projects on this machine.
- **Deliberate deviations from template `core` module** (not oversights):
  - `.mcp.json` — no MCP servers are project-specific for this repo; all MCP config is in the user's global settings
  - `CLAUDE.local.md.example` — CLAUDE.md is already the full context file; a local example adds no value for this single-maintainer project
  - `.claude/settings.json` (committed) — settings are machine-specific and gitignored intentionally; shared settings are not needed
- **Skipped optional modules:** wiki/, memory/, inbox/, design/, deliverables/, plan/SPEC.md — not needed for this project type.

### No commits until Phase 6
- **Decision:** All work stays as local file edits. GitHub `main` stays untouched until Phase 6 release commit.
- **Rationale:** Current GitHub version is usable by developers via `make setup`. Don't risk breaking it mid-work.

---

## 2026-09-01 — v1.2.0: calendar naming replaced with screen OCR fallback

### Root cause: Exchange/calendar publishing blocked by org policy
- **Finding:** User's org blocked Exchange account sync to Apple Calendar. Investigated "Publish a calendar" (Outlook Web) as a workaround — publishing itself works, but the tenant's sharing policy locks the permission level to **free/busy only** ("Can view when I'm busy"), with no "titles and locations" option available. This is a deliberate server-side tenant policy, not a device restriction — no client-side workaround exists.
- **Conclusion:** Calendar can no longer supply meeting titles for this user (and any teammate under the same tenant policy). `find_matching_meeting()` / icalBuddy / `CalendarEventBridge` path is kept as-is (still works for anyone whose org doesn't block it) but is no longer assumed to be the primary title source.

### New title source: OCR the Teams call toolbar (chosen over 3 alternatives)
- **Decision:** Add a screen-OCR fallback — capture the live Teams meeting window via ScreenCaptureKit, crop the toolbar strip, run Vision OCR, extract the title. Implemented as `recorder --meeting-title`, called from `teams_recorder_v2.py` only when calendar returns no match (start-of-recording and the existing stop-time retry).
- **Alternatives considered and rejected:**
  - **Accessibility (AXUIElement) window/text reading** — New Teams is Chromium/Electron-based; its content renders as a generic `AXGroup` to macOS Accessibility, not proper `AXStaticText` elements. A basic AppleScript/System Events text query returned nothing. A native recursive `AXUIElement` tree walk might work but is materially more engineering effort for an uncertain payoff, given OCR was already proven working. Not pursued.
  - **Coordinate-based screenshot (`screencapture -R`)** — proven unsafe during testing: a coordinate rect captures whatever window is on-screen at that location, not a specific app's window. When the Teams window moved, the same rect captured an unrelated app's window (containing what appeared to be password-manager UI). This confirmed `SCContentFilter(desktopIndependentWindow:)` (captures a specific window by reference, works even when occluded/backgrounded) is required, not coordinates.
  - **Manual rename UI (menu bar)** — deferred to v1.3.0 (see below), not rejected — still the intended universal fallback for whatever OCR misses.
  - **Local ASR title inference** — shelved. Heavy (model + CPU cost per recording) for a problem OCR already solves for free and more precisely.
- **Confidence gate:** OCR only trusts a candidate window if its toolbar text includes a live call timer (`HH:MM:SS` pattern). This is necessary because New Teams can have multiple windows open simultaneously (Chat, Calendar, an active meeting) — without the gate, OCR could read a Chat or Calendar window's title instead of the actual live meeting.
- **Where the OCR code lives:** `recorder/main.swift` (new `--meeting-title` CLI mode), not Python. Same TCC-attribution reasoning as the existing Calendar architecture — a bare CLI tool invoked by Python/Terminal would have its own permission-attribution quirks; the `recorder` binary already holds the Screen Recording entitlement used for actual recording, so reusing it needs no new permission grant from users.
- **Privacy note (flagged to user, acknowledged):** this reads meeting titles by OCR-ing the user's own screen locally — nothing leaves the Mac, no new data is transmitted anywhere. It does route around a block the org's IT set deliberately for calendar title sharing. Flagged once for the record; user chose to proceed.

### Phase 3 (manual rename UI) deferred to v1.3.0
- **Decision:** Ship OCR fallback alone in v1.2.0. Manual rename UI (menu bar: rename recordings still named "Teams Meeting" / "Teams Call (Short)") deferred to a later release.
- **Rationale:** Calendar → OCR → existing "Teams Meeting" placeholder already covers every case with no naming *gap* (worst case is unchanged from today's behavior). Shipping the OCR win alone is faster and lets real usage show whether manual rename is actually needed before investing in the menu-bar UI work.

### Build gotchas discovered (recorded for future reference)
- `SCScreenshotManager.captureImage` (single-shot capture) crashes with `CGS_REQUIRE_INIT` in a bare SPM CLI executable unless something touches `NSApplication.shared` first. The existing continuous `SCStream` recording path does not need this — only the new single-shot `--meeting-title` mode does.
- Test suite baseline was stale in two places: `CLAUDE.md` said "99 passed, 3 skipped", `project-context/release-checklist.md` said "93 passed" — actual baseline (confirmed via `make test` before any v1.2.0 changes) is 107 passed, 3 skipped. Final v1.2.0 baseline (after adding OCR tests) is **116 passed, 3 skipped**. Both docs corrected in this release.

### Post-implementation `/code-review` fixes (before release)
Ran `/code-review` (medium effort, inline angles) on the diff before shipping. Two real issues found and fixed on the spot:
- **Title-extraction heuristic was an English word list.** The initial `extractMeetingTitle()` excluded OCR lines matching a hardcoded set of English toolbar labels ("chat", "people", "camera", ...) plus a numeric-noise regex and a length cutoff. This breaks for a Thai-language Teams UI (plausible risk specifically *because* this is a Thai team's tool with th-TH OCR already wired in), and separately misclassifies numeric-only or very short legitimate titles as noise. **Fix:** switched to a position-based heuristic — the real capture showed the title always renders on the row *above* the timer, while every toolbar label sits on the timer's row or below. Using each OCR line's `boundingBox.midY`, the title is now "the longest line strictly above the timer's row" — language-independent, and no longer excludes titles by content pattern. This is a deeper fix (one mechanism) rather than patching three separate word-list/regex special cases.
- **OCR retry-at-stop was structurally pointless and blocked the main loop.** The original plan called for reusing the OCR fallback in the existing stop-time calendar-retry block. On review this doesn't make sense for OCR specifically: by the time `stop_recording_v2` runs, `STOP_GRACE` (8s) has already confirmed the meeting ended, so the Teams call toolbar's live timer — which the confidence gate requires — is already gone. The retry could essentially never succeed, yet `stop_recording_v2` runs synchronously in the single-threaded main loop *and* is called directly from the SIGINT/SIGTERM handler (`handle_exit`), so this could hang Ctrl+C shutdown for up to the full 25s subprocess timeout for no realistic benefit. **Fix:** removed the OCR retry at stop; OCR only runs at recording-start now. Calendar retry at stop is unaffected — it stays, because calendar data can genuinely arrive late (a real scenario, unlike a call that has already ended).
