# Now — Team Recorder

## Current focus

**v1.2.4 — Resilient to Bluetooth hangs; single-track output for NotebookLM.**
Two critical incidents identified and fixed:
- (2026-09-28 14:52) Stop hung indefinitely → Python killed binary after 30s → file had no moov, marked INCOMPLETE_, meeting name lost. Recovered with untrunc but audio was chopped (tracks misaligned).
- (2026-09-29 14:00) StartMic blocked for 59 minutes during BT HFP⇄A2DP switch → STARTED never arrived → meeting lost.

Root cause: AVAudioEngine calls (installTap/start/removeTap/stop) can block for hours during Bluetooth headset mode switching, which Teams triggers exactly at meeting join/leave.

Fixes (v1.2.4):
- All AVAudioEngine work on dedicated `micQ` serial queue; `start` emits STARTED without waiting.
- `stop` finalizes writer first (playable file), waits max 5s for mic teardown, exits code 3 on timeout (planned respawn).
- `movieFragmentInterval=10s`: killed recorder still leaves playable file up to last fragment.
- Silence-fill mic track from system-audio clock to prevent fragment stalls after ~220s with no mic.
- New `recorder --mixdown`: NotebookLM reads only first track, so pre-v1.2.4 recordings were missing user's voice in transcripts.
- Status fields survive respawns; Python immediately re-spawns on start timeout.

Tests: 136 passed, 3 skipped. Tests show files playable; natural BT collision not yet reproduced on demand (3 real meet-now runs no hang, one switch 6s after stop = healthy).

## Phase status (v1.2.4)

| Phase | Status | Description |
|---|---|---|
| 0 — Root cause analysis | ✅ Done | AVAudioEngine blocking on BT HFP⇄A2DP during meeting join/leave identified via incident post-mortems (2026-09-28/29) |
| 1 — Playable files under kill | ✅ Done | `movieFragmentInterval=10s`; finalizer-first stop order; no `cancelWriting()` |
| 2 — Mic async + timeout | ✅ Done | All AVAudioEngine on `micQ` serial queue; `start` non-blocking (STARTED immediate); `stop` waits max 5s then exits 3 |
| 3 — Silence fill | ✅ Done | Mic track filled from system-audio clock (kMicMaxLag=1s, chunk ≤10s) prevents fragment stalls after ~220s |
| 4 — Track merge | ✅ Done | `recorder --mixdown` post-recording (NotebookLM single-track read); original kept if validation fails |
| 5 — Python respawn path | ✅ Done | Start timeout (no ERROR token) → terminate + respawn immediately; status "error" + one notification per meeting |
| 6 — Docs + tests | ✅ Done | CLAUDE.md stdin/CLI/constants/Known Issues updated; 136 passed, 3 skipped |
| 7 — Release | ⏳ Pending | v1.2.4 committed on branch, awaiting final install + user go to publish |

## Open items (v1.2.4+)

- [x] Mic blocking forever on BT switch — fixed with async `micQ` + 5s timeout (exit 3)
- [x] Killed recorder leaves corrupt file — fixed with fragment intervals (playable)
- [x] NotebookLM missing user voice — fixed with `--mixdown` post-record
- [ ] Natural BT HFP⇄A2DP collision during recording still unobserved: 3 real Meet-now runs, including 1 switch 6s after stop (process stayed healthy). Confidence rests on the design, the 350s no-mic kill test, and the healthy-path tests.
- [ ] **v1.2.5 — PoC B: mic via ScreenCaptureKit `captureMicrophone` (macOS 15+, out-of-process in replayd), so a stuck BT switch can't cost the user's own voice.** Source is in `plan/poc-sck-mic/` (`main.swift`, `run.py`, `entitlements.plist`); it is untested.
  - Build with `swiftc -O main.swift -o recorder-poc`, then codesign with the entitlements. SPM needs tools-version ≥ 6.0 for `.macOS(.v15)`.
  - A run from Claude's Bash hit a Screen Recording TCC error that the production binary did not hit. Run it from the user's Terminal instead so the prompt can appear.
  - Test: stop the watcher, set system input = MacBook mic and Teams mic = BT headset, run `python3 run.py`, then join and leave Meet now, and check the `MIC_GAP`/`STAT` lines.
  - Decision needed: keep AVAudioEngine as the macOS 14 fallback? Does anyone on the team still run 14?
- [ ] Thai-language Teams **UI** (menu/section names in Thai) — window-title parsing strips only `" | Microsoft Teams"` / `"Meeting join | "`, which are likely localized too; unverified, would need a Thai-UI Teams client
- [x] Upgrade test: does replacing the installed `.app` re-trigger TCC prompts? Observed 2× on 2026-09-28/29: after `make menu-bar-install` the ad-hoc signature changes, `setupCompleted` reads 0 and the watcher does not start until Setup Guide is completed again. Document this in `docs/user/troubleshooting.md` for public upgrades.

## Blocking decisions made (v1.2.4)

- **AVAudioEngine work on dedicated `micQ`, never awaited unbounded.** Teardown can block for hours on BT mode switch. `start` emits STARTED immediately, mic startup async. `stop` waits max 5s then respawns (exit 3), not fatal.
- **Playable file first, cleanup second.** Writer finalized before mic/SCK teardown; file safe even if binary dies. On timeout, `movieFragmentInterval=10s` ensures up-to-the-last-fragment playability.
- **No `cancelWriting()` on timeout.** Confirmed it deletes the output file entirely — was a false fix attempt.
- **Mic track silence-filled from system-audio clock.** Without mic data, fragments stall after ~220s (AVAssetWriter implementation detail, unfixable from user side). Fill with silence (0 amplitude) on system clock to keep fragments flowing, max `kMicMaxLag=1.0s` lag.
- **Post-record mixdown, not retroactive.** NotebookLM reads first track only; pre-v1.2.4 recordings never re-mixed by user choice (evidence trail, not limitation). `recorder --mixdown` available on demand.
- **Start timeout (no ERROR stderr) triggers respawn.** Python immediately re-spawns, surfaces as "error" status + one notification. Not a crash; status fields (last_start, etc.) survive.
- Existing naming/pre-join decisions (v1.2.3) unchanged.
