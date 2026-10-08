import csv
import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np

FFMPEG = "/opt/homebrew/bin/ffmpeg"
FFPROBE = "/opt/homebrew/bin/ffprobe"
SAMPLE_RATE = 16000
FRAME = SAMPLE_RATE // 10
THRESH_DBFS = -45.0
MIX_GAIN = 0.8
SKIP_MARKERS = ("INCOMPLETE", "(recovered)")


def audio_track_count(path):
    out = subprocess.run(
        [FFPROBE, "-v", "error", "-select_streams", "a", "-show_entries", "stream=index",
         "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True).stdout
    return len([l for l in out.splitlines() if l.strip()])


def decode_track(path, index):
    raw = subprocess.run(
        [FFMPEG, "-v", "error", "-i", str(path), "-map", f"0:a:{index}", "-ac", "1",
         "-ar", str(SAMPLE_RATE), "-f", "f32le", "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def decode_mixed(path):
    tracks = audio_track_count(path)
    if tracks == 0:
        raise RuntimeError("no audio track")
    if tracks == 1:
        return decode_track(path, 0)
    a = decode_track(path, 0)
    b = decode_track(path, 1)
    n = max(len(a), len(b))
    mixed = np.zeros(n, dtype=np.float32)
    mixed[:len(a)] += MIX_GAIN * a
    mixed[:len(b)] += MIX_GAIN * b
    return mixed


def measure(path, cutoff=THRESH_DBFS):
    samples = decode_mixed(path)
    frames = len(samples) // FRAME
    if frames == 0:
        raise RuntimeError("shorter than one frame")
    block = samples[:frames * FRAME].reshape(frames, FRAME).astype(np.float64)
    rms = np.sqrt((block ** 2).mean(axis=1))
    dbfs = 20.0 * np.log10(np.maximum(rms, 1e-10))
    return {
        "file": Path(path).name,
        "speechRatio": round(float((dbfs > cutoff).sum() / frames), 6),
        "durationSec": round(len(samples) / SAMPLE_RATE, 1),
        "p50dBFS": round(float(np.percentile(dbfs, 50)), 2),
        "p95dBFS": round(float(np.percentile(dbfs, 95)), 2),
    }


def run_directory(directory, cutoff=THRESH_DBFS):
    files = sorted(p for p in Path(directory).glob("*.m4a")
                   if not any(m in p.name for m in SKIP_MARKERS))
    skipped = sorted(p.name for p in Path(directory).glob("*.m4a")
                     if any(m in p.name for m in SKIP_MARKERS))
    writer = csv.writer(sys.stdout)
    writer.writerow(["file", "speechRatio", "durationSec", "p50dBFS", "p95dBFS"])
    failed = []
    for i, f in enumerate(files, 1):
        try:
            r = measure(f, cutoff)
            writer.writerow([r["file"], r["speechRatio"], r["durationSec"], r["p50dBFS"], r["p95dBFS"]])
        except Exception as e:
            failed.append((f.name, str(e)[:200]))
        sys.stdout.flush()
        if i % 25 == 0:
            print(f"progress {i}/{len(files)}", file=sys.stderr, flush=True)
    for name in skipped:
        print(f"SKIPPED {name}", file=sys.stderr)
    for name, err in failed:
        print(f"FAILED {name} :: {err}", file=sys.stderr)


def main():
    args = sys.argv[1:]
    cutoff = THRESH_DBFS
    if "--cutoff" in args:
        i = args.index("--cutoff")
        cutoff = float(args[i + 1])
        del args[i:i + 2]
    target = Path(args[0])
    if target.is_dir():
        run_directory(target, cutoff)
    else:
        result = measure(target, cutoff)
        result["cutoffDBFS"] = cutoff
        print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
