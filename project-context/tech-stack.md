# Architecture

> CLAUDE.md is the canonical reference. This file is a readable summary.

## Component map

| Component | File | Role |
|-----------|------|------|
| Python watcher | `teams_recorder_v2.py` | Polls UDP connections; controls recorder via stdin/stdout |
| Swift binary | `recorder/recorder` | Captures system audio + mic via ScreenCaptureKit + AVAudioEngine |
| Menu bar app | `menu-bar/` | UI wrapper; reads `status.json` via FSEvent + 5s poll; launches watcher |
| Status contract | `status.json` | Written atomically by Python (`os.replace`); read by Swift app — primary IPC surface between Python and Swift UI |
| PID files | `team-recorder.pid`, `recorder.pid` | Recovery hints for watcher and recorder child processes; validated by command before use |

## Data flow

```
Teams meeting detected (UDP ≥ 4)
  → Python sends "start <path>" to recorder binary stdin
  → Binary writes AAC .m4a; emits "STARTED" on stdout
  → Python polls UDP; on drop waits STOP_GRACE=8s (prevents false stops)
  → Python sends "stop" stdin → binary emits "STOPPED_OK" (file fully flushed)
  → Python renames file using: calendar title from events-today.json (app bridge) or icalBuddy (Terminal fallback)
    → if no calendar title: Python sends "title" via stdin to the SAME recorder process
      (never a second spawned process — that's a different SCK client and interrupts
      the recording's own SCStream, confirmed by testing). The name comes from
      SCWindow.title (exact, Thai-safe); OCR only reads the call timer to identify
      which window is the live call. Re-asked every ~15s until a name is found,
      because recording often starts on Teams' pre-join screen.
    → if neither: "Teams Meeting" placeholder
```

## Key design decisions

- **Python stays the brain** — no recording logic in Swift menu bar app
- **STOPPED_OK is the sync point** — Python only renames after confirming flush; never rename on timeout
- **Calendar bridge** — TeamRecorderBar writes `APP_SUPPORT_DIR/events-today.json` via EKEventStore; Python reads the file when `TEAM_RECORDER_APP=1` (set by WatcherManager). icalBuddy is the fallback for `make run` / Terminal contexts. This bypasses the Python.framework TCC chain that prevents icalBuddy from accessing Calendar when launched by the app.
- **ScreenCaptureKit** — system audio without virtual drivers; requires app relaunch after granting permission. Also powers the `title` stdin command (v1.2.x): captures the live Teams call window for OCR when calendar has no title, in the SAME process as the recording — same Screen Recording grant, no new permission needed. A standalone `recorder --meeting-title` CLI mode exists for manual/`make doctor` testing only; it must never run concurrently with an active recording (separate SCK client, breaks the recording's stream)
- **Vision (`VNRecognizeTextRequest`)** — reads ONLY the call-timer digits, to identify which Teams window is the live call. The meeting NAME comes from `SCWindow.title` — OCR mangles Thai (proven 2026-09-01). Ships with macOS, no bundled model
- **watcher_path.txt + python_path.txt** — absolute paths to `teams_recorder_v2.py` and the Homebrew Python interpreter, embedded at build time by `make menu-bar`; both are machine-specific so rebuild if the repo moves or Homebrew Python changes. Pinning the interpreter prevents Launch Services from resolving `env python3` to system Python 3.9 (which lacks `python-dotenv`)
- **SCK sleep/wake recovery** — `handleSCKStreamStop` restarts the ScreenCaptureKit stream in-place after display reconnect or sleep/wake; no recording gap
- **`status.json` as app contract** — menu bar app never parses logs; reads only `status.json`; atomic writes via `os.replace` prevent partial reads
- **Menu-bar notification owner** — app-managed watcher launches disable Python notifications; the app sends saved-file notifications with a Finder reveal action

## Full reference

See `CLAUDE.md` → Architecture, stdin/stdout protocol, Threading note, and Known Issues sections.
