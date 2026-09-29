#!/usr/bin/env python3
import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIN = HERE / "recorder-poc"


def ffprobe_durations(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=index,codec_type,duration",
         "-of", "default=noprint_wrappers=1", str(path)],
        capture_output=True, text=True,
    )
    return out.stdout.strip(), out.stderr.strip()


def volumedetect(path, stream_index):
    out = subprocess.run(
        ["ffmpeg", "-i", str(path), "-map", f"0:{stream_index}",
         "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    lines = [l for l in out.stderr.splitlines() if "mean_volume" in l or "max_volume" in l]
    return "\n".join(lines)


def summarize_stderr(text):
    gaps = re.findall(r"MIC_GAP ([\d.]+)", text)
    stats = re.findall(r"STAT sys_buffers=(\d+) mic_buffers=(\d+)", text)
    print(f"MIC_GAP events: {len(gaps)}", ("(" + ", ".join(gaps) + "s)") if gaps else "")
    if stats:
        last = stats[-1]
        print(f"Last STAT line: sys_buffers={last[0]} mic_buffers={last[1]}")
    else:
        print("No STAT lines seen (recording shorter than 10s, or stalled)")
    fmt_lines = [l for l in text.splitlines() if "mic buffer format" in l]
    for l in fmt_lines:
        print(l)
    stopped_lines = [l for l in text.splitlines() if "didStopWithError" in l]
    for l in stopped_lines:
        print(l)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=None,
                     help="non-interactive self-test: record for N seconds then stop")
    ap.add_argument("--outdir", default=str(HERE / "out"))
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    outfile = outdir / f"poc-{int(time.time())}.m4a"

    if not BIN.exists():
        print(f"ERROR: binary not found at {BIN} — build it first", file=sys.stderr)
        sys.exit(1)

    if args.seconds is not None:
        proc = subprocess.run(
            [str(BIN), "--seconds", str(args.seconds), str(outfile)],
            capture_output=True, text=True, timeout=args.seconds + 30,
        )
        stdout, stderr = proc.stdout, proc.stderr
        print("stdout:", stdout.strip())
    else:
        proc = subprocess.Popen(
            [str(BIN)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1,
        )
        proc.stdin.write(f"start {outfile}\n")
        proc.stdin.flush()
        line = proc.stdout.readline().strip()
        print("recorder:", line)
        if not line.startswith("STARTED"):
            print("ERROR: did not start —", line)
            print(proc.stderr.read())
            sys.exit(1)

        print(">>> recording — join/leave your Teams Meet-now call, then press Enter to stop")
        input()

        t0 = time.time()
        proc.stdin.write("stop\n")
        proc.stdin.flush()
        line = proc.stdout.readline().strip()
        latency = time.time() - t0
        print(f"recorder: {line}  (stop latency {latency:.2f}s)")

        proc.stdin.close()
        proc.wait(timeout=15)
        stderr = proc.stderr.read()
        stdout = line

    print("\n--- stderr summary ---")
    summarize_stderr(stderr)

    if not outfile.exists():
        print(f"ERROR: output file not found: {outfile}", file=sys.stderr)
        sys.exit(1)

    print(f"\n--- ffprobe: {outfile} ---")
    probe_out, probe_err = ffprobe_durations(outfile)
    print(probe_out or probe_err)

    for idx, label in [(0, "system"), (1, "microphone")]:
        print(f"\n--- volumedetect track {idx} ({label}) ---")
        print(volumedetect(outfile, idx))

    print(f"\nOutput file: {outfile}")


if __name__ == "__main__":
    main()
