# Now — Team Recorder

## Current focus

**v1.2.2 — Screen OCR meeting-title fallback, in-process capture (critical fix).**
Calendar can no longer supply meeting titles for this user's org (Exchange
sync blocked; calendar-publish locked to free/busy-only by tenant policy —
see `plan/DECISIONS.md`, 2026-09-01). Fallback: OCR the live Teams call
toolbar via ScreenCaptureKit + Vision when calendar has no match.

v1.2.0 shipped with two real-world gaps found in immediate post-release
testing: (1) a join-transition race (single-pass OCR missed the toolbar
during Teams' post-join transition on short calls), and (2) a **critical**
concurrency bug — OCR spawned a *second* `recorder` process while the first
was actively recording, and two `recorder` processes are two different
ScreenCaptureKit clients, so the second interrupted the first's SCStream on
every recording (since OCR runs on every recording for this user). Both are
fixed in v1.2.2: OCR now runs via a `title` stdin command sent to the
*already-recording* process (no second process, no interruption — verified
by a direct concurrency test), with the join-transition retry logic moved
into the same in-process path. v1.2.1 was never published. See
`plan/DECISIONS.md` for full evidence and reasoning on both fixes.

## Phase status

| Phase | Status | Description |
|---|---|---|
| 0 — PoC | ✅ Done | Standalone Swift scratch tool validated SCK window capture + Vision OCR on a real meeting; confirmed occlusion-safe, correct title + confidence-gate window selection |
| 1 — Swift title capture | ✅ Done | `recorder/main.swift`: shared `captureMeetingTitle()` used by the in-process `title` stdin command (production) and standalone `--meeting-title` CLI mode (manual/doctor testing only); rebuilt + re-signed; tested live |
| 2 — Python wiring | ✅ Done | `get_meeting_title_from_screen(proc)` sends `"title\n"` to the already-recording process via stdin, wired at recording-start only; new `CAL_FROM_OCR`/`CAL_OCR_FAILED` constants; `make doctor` skip-check added |
| 3 — Manual rename UI (menu bar) | ⏸ Deferred to v1.3.0 | Decision: ship OCR fallback alone first; see `plan/DECISIONS.md` |
| 4 — Docs revision | ✅ Done | CLAUDE.md / README / docs/user/ / project-context/ / plan/ all updated for the in-process architecture |
| 5 — QA | 🔄 In progress | Unit tests done (116 passed, 3 skipped); `/code-review` run, findings fixed; direct concurrency test confirms no SCStream interruption via the `title` stdin command (was reproducibly broken via the old subprocess-spawn approach). Remaining: live smoke gaps below, upgrade test, clean-install test |
| 6 — Release | 🔄 In progress | v1.2.0 published, has the concurrency bug (undetected in normal use — recovery masks it). v1.2.1 built but never published (superseded before tagging). v1.2.2 pending: version bump, `make release`, SHA256, tag, GitHub Release explaining the fix |

## Open items

- [x] Live-verify OCR correctly returns non-zero/no-title when *not* in a call — confirmed: `ERROR: no_teams_windows_found`, exit 1, no stdout
- [x] Verify OCR capture doesn't disturb an active recording — **confirmed it DID disturb it** via the old subprocess-spawn design; fixed via the in-process `title` command; re-confirmed clean with the fix
- [ ] Thai-language Teams UI — the position-based extraction (title row above timer row) should be language-independent, but hasn't been observed on an actual Thai-language Teams client; verify when possible
- [ ] Thai-language meeting *title* OCR accuracy — untested, no Thai-titled meeting was live during development
- [ ] Ad-hoc (non-calendar) call title OCR, end to end with v1.2.2 — the 2026-09-01 test ("Test for Team Record ครับ") hit both bugs above before a title could be confirmed; retest now that both are fixed
- [ ] Upgrade test: does replacing the installed `.app` re-trigger TCC permission prompts? Unknown until tested — document actual result in `docs/user/troubleshooting.md`
- [ ] Gatekeeper screenshot (carried over from v1.0, still open) — `docs/user/images/gatekeeper-bypass.png`

## Blocking decisions made

- OCR during an active recording MUST run in-process (the `title` stdin command on the already-recording `recorder` process) — a separate spawned `recorder --meeting-title` process is a different ScreenCaptureKit client and interrupts the recording's own SCStream (confirmed, was a real shipped bug in v1.2.0)
- The standalone `--meeting-title` CLI mode still exists for `make doctor` / manual testing, but must never run while a recording is in progress
- Window capture uses `SCContentFilter(desktopIndependentWindow:)`, never coordinate-based `screencapture -R` — proven unsafe (captured an unrelated app's window when Teams moved)
- Confidence gate: only trust an OCR'd title if the same window also shows a live call timer (`HH:MM:SS`) — prevents reading Chat/Calendar window titles instead of the real meeting
- Title extraction is position-based (longest line above the timer's row), not an English word list — language-independent, doesn't misclassify numeric/short titles
- Phase 3 (manual rename UI) deferred to v1.3.0
