#!/bin/bash
# Phase 5 gate (plan/v2.0-plan.md): sample levels.json once per second for the whole
# recording and report mic continuity, then decode the saved file end to end.
#   scripts/phase5-bt-gate.sh            # waits for a recording to start, samples until it stops
# Setup for the Bluetooth test (LESSONS v1.2.4 #5): system input = MacBook mic,
# Teams mic = BT headset, MIC_PATH=sck in the App Support .env, watcher restarted.
set -uo pipefail
SUP="$HOME/Library/Application Support/Team Recorder"
LOG=plan/phase5-bt-gate-log.md

state() { python3 -I -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('state',''), d.get('lastRecordingPath') or '')" "$SUP/status.json" 2>/dev/null; }

echo "waiting for a recording to start…"
until [ "$(state | cut -d' ' -f1)" = "recording" ]; do sleep 1; done
echo "recording started $(date '+%H:%M:%S') — sampling"
samples=0; alive=0; dead=0; maxgap=0; path=""; stale=0
while [ "$(state | cut -d' ' -f1)" = "recording" ]; do
  if [ -f "$SUP/levels.json" ]; then
    read -r a g p <<<"$(python3 -I -c "import json,sys;d=json.load(open(sys.argv[1]));print(int(d['micAlive']), d.get('micMaxGap',0), d.get('micPath','?'))" "$SUP/levels.json" 2>/dev/null || echo "0 0 ?")"
    samples=$((samples+1)); path=$p
    if [ "$a" = "1" ]; then alive=$((alive+1)); else dead=$((dead+1)); fi
    maxgap=$(python3 -I -c "import sys;print(max(float(sys.argv[1]), float(sys.argv[2])))" "$maxgap" "$g" 2>/dev/null || echo "$maxgap")
  else
    stale=$((stale+1))
  fi
  sleep 1
done
echo "recording stopped $(date '+%H:%M:%S') — waiting for the file"
sleep 15
file=$(state | cut -d' ' -f2-)
dur_hdr=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null)
decode=$(ffmpeg -v error -i "$file" -f null - 2>&1 | wc -l | tr -d ' ')
dur_dec=$(ffmpeg -i "$file" -f null - 2>&1 | grep -o "time=[0-9:.]*" | tail -1)
{
  echo "## BT gate run — $(date '+%Y-%m-%d %H:%M') — micPath=$path"
  echo '```'
  echo "seconds sampled: $samples  micAlive: $alive  mic dead: $dead  levels.json missing: $stale"
  echo "max gap between mic buffers: ${maxgap}s  (gate: ≤ 0.5s, mic dead: 0)"
  echo "file: $file"
  echo "header duration: ${dur_hdr}s  decoded to: $dur_dec  decode errors: $decode"
  echo '```'
  if [ "$dead" = "0" ] && python3 -I -c "import sys;sys.exit(0 if float(sys.argv[1])<=0.5 else 1)" "$maxgap" && [ "$decode" = "0" ]; then echo "**RESULT: PASS**"; else echo "**RESULT: FAIL**"; fi
  echo
} | tee -a "$LOG"
