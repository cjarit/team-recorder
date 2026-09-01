# Now — Team Recorder

## Current focus

**v1.2.0 — Screen OCR meeting-title fallback.** Calendar can no longer supply
meeting titles for this user's org (Exchange sync blocked; calendar-publish
locked to free/busy-only by tenant policy — see `plan/DECISIONS.md`,
2026-09-01). New fallback: OCR the live Teams call toolbar via
ScreenCaptureKit + Vision when calendar has no match.

## Phase status

| Phase | Status | Description |
|---|---|---|
| 0 — PoC | ✅ Done | Standalone Swift scratch tool validated SCK window capture + Vision OCR on a real meeting; confirmed occlusion-safe, correct title + confidence-gate window selection |
| 1 — Swift `--meeting-title` mode | ✅ Done | `recorder/main.swift` new CLI mode; rebuilt + re-signed; tested live |
| 2 — Python wiring | ✅ Done | `get_meeting_title_from_screen()`; wired at recording-start only (stop-time OCR retry was added then removed — see `plan/DECISIONS.md`, code-review fixes); new `CAL_FROM_OCR`/`CAL_OCR_FAILED` constants; `make doctor` skip-check added |
| 3 — Manual rename UI (menu bar) | ⏸ Deferred to v1.3.0 | Decision: ship OCR fallback alone first; see `plan/DECISIONS.md` |
| 4 — Docs revision | ✅ Done | CLAUDE.md / README / docs/user/ / project-context/ / plan/ all updated |
| 5 — QA | 🔄 In progress | Unit tests done (116 passed, 3 skipped); `/code-review` run and both findings fixed (position-based title extraction, removed pointless OCR retry-at-stop); cross-ref sweep clean. Remaining: live smoke gaps below, upgrade test, clean-install test |
| 6 — Release | ⏳ Not started | Version bump 1.1.1 → 1.2.0, `make release`, SHA256, tag, GitHub Release with explicit upgrade instructions |

## Open items

- [ ] Live-verify OCR correctly returns non-zero/no-title when *not* in a call (couldn't test — was in a live meeting throughout development)
- [ ] Thai-language Teams UI — the position-based extraction (title row above timer row) should be language-independent, but hasn't been observed on an actual Thai-language Teams client; verify when possible
- [ ] Thai-language meeting *title* OCR accuracy — untested, no Thai-titled meeting was live during development
- [ ] Ad-hoc (non-calendar) call title OCR — untested
- [ ] Upgrade test: does replacing the installed v1.1.1 `.app` re-trigger TCC permission prompts? Unknown until tested — document actual result in `docs/user/troubleshooting.md`
- [ ] Gatekeeper screenshot (carried over from v1.0, still open) — `docs/user/images/gatekeeper-bypass.png`

## Blocking decisions made

- OCR lives in the Swift binary (`recorder --meeting-title`), not Python — same TCC-attribution reasoning as the existing Calendar architecture
- Window capture uses `SCContentFilter(desktopIndependentWindow:)`, never coordinate-based `screencapture -R` — proven unsafe (captured an unrelated app's window when Teams moved)
- Confidence gate: only trust an OCR'd title if the same window also shows a live call timer (`HH:MM:SS`) — prevents reading Chat/Calendar window titles instead of the real meeting
- Phase 3 (manual rename UI) deferred to v1.3.0
