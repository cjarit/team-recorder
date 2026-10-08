#!/bin/bash
# Phase 1 gate (plan/v2.0-plan.md): one rebuild → reinstall → relaunch cycle, then print
# the permission snapshot the app writes on launch (permissions.json) and the app's
# designated requirement. Run from the repo root. Label is free text for the log.
#   scripts/tcc-persist-test.sh "cert cycle 2"
#   SIGN_ID=- scripts/tcc-persist-test.sh "adhoc control"
set -euo pipefail

LABEL="${1:-cycle}"
APP=/Applications/TeamRecorderBar.app
SNAP="$HOME/Library/Application Support/Team Recorder/permissions.json"
LOG=plan/phase1-tcc-log.md

osascript -e 'tell application "TeamRecorderBar" to quit' >/dev/null 2>&1 || true
sleep 1
rm -f "$SNAP"
make menu-bar-install >/dev/null
sleep 5

DR=$(codesign -dr - "$APP" 2>&1 | grep designated)
SIG=$(codesign -dvv "$APP" 2>&1 | grep -E "^(Signature|Authority)" | head -2 | tr '\n' ' ')
SNAPTXT=$(cat "$SNAP" 2>/dev/null || echo '{"error":"no snapshot written"}')

{
  echo "## $LABEL — $(date '+%Y-%m-%d %H:%M')"
  echo '```'
  echo "$DR"
  echo "$SIG"
  echo "$SNAPTXT"
  echo '```'
  echo
} | tee -a "$LOG"
