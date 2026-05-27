# Overview — Team Recorder

## What it does

macOS-only tool that automatically records Microsoft Teams meetings and names the file after the calendar event. No OBS, no virtual audio driver, no manual start/stop.

**User story:** Start the app, join your Teams call, walk away. When the meeting ends, a `.m4a` file named after the meeting appears in your recordings folder.

## Architecture (one paragraph)

A Python polling loop (`teams_recorder_v2.py`) watches for Teams UDP connections. When a meeting is detected, it sends a `start` command to a Swift binary (`recorder/recorder`) via stdin. The binary captures system audio using ScreenCaptureKit + AVAudioEngine and writes an AAC `.m4a`. On meeting end, Python sends `stop`, waits for `STOPPED_OK`, then renames the file using a calendar event title. A menu-bar app (`TeamRecorderBar`) wraps the watcher with a status icon, first-run permissions guide, and Launch at Login.

## Target users

Internal Thai design team (daily use). Post-v1.0: public GitHub — any macOS designer/developer on a team using Teams.

## Key constraints

- macOS 14 Sonoma+ only
- No new features in v1.0 (packaging, portability, docs cleanup only)
- Python + Swift coexist; Python is the brain, Swift handles audio I/O

## Links

- Full architecture: `project-context/tech-stack.md`
- Folder layout: `project-context/repo-structure.md`
- Current work: `plan/NOW.md`
- User setup guide: `docs/user/setup.md`
