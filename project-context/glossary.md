# Glossary — Team Recorder

| Term | Definition |
|---|---|
| **SCK / ScreenCaptureKit** | Apple framework (macOS 13+) for capturing display and audio without virtual drivers |
| **AVAudioEngine** | Apple framework that routes and processes audio streams in real time |
| **stdin/stdout protocol** | How Python talks to the recorder binary: `start <path>` in → `STARTED` out; `stop` in → `STOPPED_OK` out |
| **STOPPED_OK** | Signal from the recorder binary that the `.m4a` file is fully flushed and safe to rename |
| **icalBuddy** | CLI tool (Homebrew) that reads Apple Calendar without requiring a GUI app open. Used by `make run` / Terminal flow. Replaced by CalendarEventBridge inside the .app. |
| **CalendarEventBridge** | Swift class inside TeamRecorderBar that reads calendar events via EKEventStore (no icalBuddy needed) and writes `events-today.json` to App Support |
| **events-today.json** | Bridge file written by CalendarEventBridge; Python reads it to get today's meeting titles without needing icalBuddy or Calendar permission itself |
| **status.json** | Written by Python watcher to `~/Library/Application Support/Team Recorder/`; read by TeamRecorderBar to show current recording state in the menu bar |
| **PID file** | `team-recorder.pid` in App Support; lets TeamRecorderBar detect if a watcher is already running |
| **watcher_path.txt** | Resource file inside the .app bundle pointing to `teams_recorder_v2.py`. Being replaced in Phase 4 with Bundle.main resource lookup. |
| **python_path.txt** | Resource file inside the .app bundle pointing to the Homebrew Python interpreter. Being replaced in Phase 4 with zipapp + system Python. |
| **watcher.pyz** | Zipapp bundle (Phase 4): `teams_recorder_v2.py` + dotenv + psutil wheels, runnable by system Python 3 |
| **UDP meeting threshold** | `UDP_MEET_THRESH = 4` — number of established UDP connections that indicates a Teams meeting is active (vs background Teams idle = 1-2) |
| **STOP_GRACE** | 8 seconds Python waits after UDP drops before confirming meeting ended — prevents false stops |
| **ad-hoc signing** | `codesign -s -` — self-signed with no Apple Developer ID. Requires right-click → Open on first launch. |
| **Gatekeeper bypass** | macOS security prompt on first open of an ad-hoc signed .app. Right-click → Open → confirm. One-time only. |
| **SMAppService** | macOS 13.2+ API for registering a Login Item (Launch at Login). Used by TeamRecorderBar. |
| **TCC** | Transparency, Consent, and Control — macOS privacy permission system. Each app's permissions are tied to its bundle ID. |
