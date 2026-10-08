# Overview — Team Recorder

## What it does

macOS-only tool that automatically records Microsoft Teams meetings and names the file after the calendar event. No OBS, no virtual audio driver, no manual start/stop.

**User story:** Start the app, join your Teams call, walk away. When the meeting ends, a `.m4a` file named after the meeting appears in your recordings folder.

## Architecture (one paragraph)

A Python polling loop (`teams_recorder_v2.py`) watches for Teams UDP connections. When a meeting is detected, it sends a `start` command to a Swift binary (`recorder/recorder`) via stdin. The binary captures system audio and the microphone through one ScreenCaptureKit stream (v2.0; AVAudioEngine mic path kept behind `MIC_PATH=engine` for one release) and writes an AAC `.m4a`. On meeting end, Python sends `stop`, waits for `STOPPED_OK`, then renames the file using a calendar event title; `recorder --mixdown` merges the tracks into one mono track. A menu-bar app (`TeamRecorderBar`) wraps the watcher: left-click opens a popover (daily use), right-click a 5-item menu, and "Open Team Recorder…" a Status / General / Calendars / Permissions window. Files are managed in Finder, not in the app.

## Target users

Internal Thai design team (daily use). Post-v1.0: public GitHub — any macOS designer/developer on a team using Teams.

## Key constraints

- Two release lines: **v2.x = macOS 15 (Sequoia)+** on `main`; **v1.2.x = macOS 14**, bug fixes only, branch `release/1.x` (v1.2.4 stays published on GitHub Releases)
- Every build is signed with the self-signed certificate "Team Recorder Signing" (`make cert`, once per Mac) so TCC permissions survive upgrades; not notarized, so first open needs Privacy & Security → Open Anyway
- Python + Swift coexist; Python is the brain, Swift handles audio I/O and the UI

## Links

- Full architecture: `project-context/tech-stack.md`
- Folder layout: `project-context/repo-structure.md`
- Current work: `plan/NOW.md`
- User setup guide: `docs/user/setup.md`
- v2.0 plan, spec, UI inventory: `plan/v2.0-plan.md`, `plan/v2.0-spec.md`, `plan/v2.0-ui-inventory.md`
