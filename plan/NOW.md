# Now — Team Recorder

## Current focus

**v1.2.3 — Meeting name from window title; pre-join root cause fixed.**
Calendar can no longer supply meeting titles for this user's org (Exchange
sync blocked; calendar-publish locked to free/busy-only by tenant policy —
see `plan/DECISIONS.md`, 2026-09-01). Fallback: read the meeting name off
the Teams window when calendar has no match.

Three releases (v1.2.0–v1.2.2) shipped fixes reasoned from plausibility
rather than evidence, and all were wrong about the cause. A
`--diagnose-title` mode was added and settled it in one 30-second capture:
**recording starts while the user is still on Teams' pre-join / green-room
screen**, which already opens call-media UDP sockets. No call, no toolbar,
no timer — but the meeting name is right there in the window title.

The same capture proved **OCR cannot read Thai reliably** (`ครับ` → `Ašu`,
then `nu` on the next sample), while `SCWindow.title` carried it exactly.
So the name now comes from the window title and OCR only reads the call
timer (digits — language-independent). Python re-asks every ~15s for the
whole meeting, so pre-join → in-call resolves on its own.

Full evidence and reasoning in `plan/DECISIONS.md`.

## Phase status

| Phase | Status | Description |
|---|---|---|
| 0 — PoC | ✅ Done | Validated SCK window capture + Vision OCR; confirmed occlusion-safe window-targeted capture |
| 1 — Swift title capture | ✅ Done | `meetingNameFromWindowTitle()` / `isPreJoinWindow()` / `captureMeetingTitleOnce()` ranked selection; `captureMeetingTitle(attempts:)` shared by the `title` stdin command and the `--meeting-title` CLI; `--diagnose-title` added |
| 2 — Python wiring | ✅ Done | `get_meeting_title_from_screen(proc)` over stdin; retry every `TITLE_RETRY_EVERY` (~15s) across the whole meeting; `CAL_FROM_OCR`/`CAL_OCR_FAILED`; `make doctor` skip-check |
| 3 — Manual rename UI (menu bar) | ⏸ Deferred to v1.3.0 | Ship the naming fix alone first; see `plan/DECISIONS.md` |
| 4 — Docs revision | ✅ Done | CLAUDE.md / README / docs/user/ / project-context/ / plan/ updated for the window-title architecture |
| 5 — QA | ✅ Done | 118 passed, 3 skipped; `/code-review` findings fixed; concurrency test confirms no SCStream interruption; live end-to-end on a real Thai-named meeting returns the exact title twice with clean stderr |
| 6 — Release | 🔄 In progress | v1.2.0 + v1.2.2 published (both still mis-name recordings that start on pre-join). v1.2.1 never published. v1.2.3 pending publish |

## Open items

- [x] OCR returns nothing when not in a call — confirmed (`no_teams_windows_found`, exit 1)
- [x] Capture doesn't disturb an active recording — confirmed broken via subprocess-spawn, fixed in-process, re-verified clean
- [x] Thai meeting-title accuracy — **OCR fails** (`ครับ` → `Ašu`/`nu`); fixed by sourcing the name from `SCWindow.title`, verified exact end-to-end
- [x] Root cause of "still named Teams Meeting" — pre-join screen, confirmed by `--diagnose-title`
- [ ] Thai-language Teams **UI** (menu/section names in Thai) — window-title parsing strips only `" | Microsoft Teams"` / `"Meeting join | "`, which are likely localized too; unverified, would need a Thai-UI Teams client
- [ ] The user reported some failures while genuinely in-call — never reproduced; the ~15s retry loop should cover it regardless of cause, but watch for recurrence
- [ ] Upgrade test: does replacing the installed `.app` re-trigger TCC prompts? Still unverified — document the real result in `docs/user/troubleshooting.md`
- [ ] Gatekeeper screenshot (carried over from v1.0) — `docs/user/images/gatekeeper-bypass.png`

## Blocking decisions made

- **Meeting NAME comes from `SCWindow.title`, never OCR** — OCR mangles Thai, differently each sample (proven). OCR's only job is reading the call timer to identify the live-call window.
- Recording commonly starts on Teams' **pre-join screen** (it opens UDP media sockets before "Join now") — a `"Meeting join | …"` window is an accepted name source, and Python keeps re-asking until the call proper is joined
- OCR during an active recording MUST run in-process (the `title` stdin command) — a separate spawned `recorder --meeting-title` process is a different ScreenCaptureKit client and interrupts the recording's own SCStream (was a real shipped bug in v1.2.0)
- Window capture uses `SCContentFilter(desktopIndependentWindow:)`, never coordinate-based `screencapture -R` — proven unsafe (captured an unrelated app's window when Teams moved)
- Build the diagnostic before shipping the fix — three releases were spent on unverified hypotheses; `--diagnose-title` settled it in minutes
- Phase 3 (manual rename UI) deferred to v1.3.0
