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
  → Python renames file using calendar title from icalBuddy
```

## Key design decisions

- **Python stays the brain** — no recording logic in Swift menu bar app
- **STOPPED_OK is the sync point** — Python only renames after confirming flush; never rename on timeout
- **icalBuddy for calendar** — JXA hangs when Calendar.app is closed (confirmed production bug; do not revert)
- **ScreenCaptureKit** — system audio without virtual drivers; requires app relaunch after granting permission
- **watcher_path.txt + python_path.txt** — absolute paths to `teams_recorder_v2.py` and the Homebrew Python interpreter, embedded at build time by `make menu-bar`; both are machine-specific so rebuild if the repo moves or Homebrew Python changes. Pinning the interpreter prevents Launch Services from resolving `env python3` to system Python 3.9 (which lacks `python-dotenv`)
- **SCK sleep/wake recovery** — `handleSCKStreamStop` restarts the ScreenCaptureKit stream in-place after display reconnect or sleep/wake; no recording gap
- **`status.json` as app contract** — menu bar app never parses logs; reads only `status.json`; atomic writes via `os.replace` prevent partial reads
- **Menu-bar notification owner** — app-managed watcher launches disable Python notifications; the app sends saved-file notifications with a Finder reveal action

## Full reference

See `CLAUDE.md` → Architecture, stdin/stdout protocol, Threading note, and Known Issues sections.
