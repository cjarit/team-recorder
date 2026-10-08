#!/bin/bash
# Phase 2 verify: orphan the current watcher (kill -9 the app), force a version change,
# reinstall, and check the self-heal started a fresh watcher with settings intact.
set -uo pipefail
SUP="$HOME/Library/Application Support/Team Recorder"
PAT='watcher.py''z'
osascript -e 'tell application "TeamRecorderBar" to quit' >/dev/null 2>&1; sleep 1
open /Applications/TeamRecorderBar.app; sleep 6
APP=$(pgrep -x TeamRecorderBar); W=$(pgrep -f "$PAT" | head -1)
echo "before: app=$APP watcher=${W:-none}"
[ -n "$W" ] || { echo "FAIL: no watcher running before the test"; exit 1; }
kill -9 "$APP"; sleep 1
echo "orphan watcher alive: $(kill -0 "$W" 2>/dev/null && echo yes || echo no)"
defaults write com.team-recorder.menu-bar lastRunVersion "1.9-test"
scripts/tcc-persist-test.sh "Phase 2 upgrade: orphan watcher + forced version change" | grep -E '"(screenRecording|microphone|calendar)"'
sleep 5
NEW=$(pgrep -f "$PAT" | head -1)
echo "after: old $W alive: $(kill -0 "$W" 2>/dev/null && echo yes || echo no) | new watcher: ${NEW:-none} | pidfile: $(cat "$SUP/team-recorder.pid" 2>/dev/null || echo none)"
echo "lastRunVersion: $(defaults read com.team-recorder.menu-bar lastRunVersion)"
echo "trackedCalendarIds: $(defaults read com.team-recorder.menu-bar trackedCalendarIds | tr -d '\n ')"
echo "status: $(grep '"state"' "$SUP/status.json" 2>/dev/null || echo none)"
echo "env RECORDING_DIR present: $(grep -c RECORDING_DIR "$SUP/.env")"
echo "recordings (.m4a): $(ls "$HOME/Documents/Teams Recording"/*.m4a | wc -l | tr -d ' ')"
if [ -n "$NEW" ] && [ "$NEW" != "$W" ] && ! kill -0 "$W" 2>/dev/null; then echo "RESULT: PASS"; else echo "RESULT: FAIL"; exit 1; fi
