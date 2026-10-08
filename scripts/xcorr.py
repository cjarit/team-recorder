#!/usr/bin/env python3
"""Measure speaker bleed in a dual-track recording.

Cross-correlates the system-audio track (0) against the mic track (1) in 10 s
windows and reports the best lag (mic lagging system, 0–400 ms) and the
normalized correlation. Windows with near-silent system audio are skipped.

usage: scripts/xcorr.py <file.m4a> [--start 600] [--dur 180]
Needs ffmpeg/ffprobe on PATH and numpy.
"""
import argparse
import subprocess
import sys

import numpy as np

SR = 16000
MAX_LAG_S = 0.4
WIN_S = 10
SILENCE_RMS = 0.005
BLEED_CORR = 0.3


def track_count(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=index",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout
    return out.count("\n")


def load(path, idx, start, dur):
    r = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(dur), "-i", path,
                        "-map", f"0:{idx}", "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                       capture_output=True)
    return np.frombuffer(r.stdout, dtype=np.float32)


def measure(sysa, mic):
    n = min(len(sysa), len(mic))
    sysa, mic = sysa[:n], mic[:n]
    maxlag, win = int(MAX_LAG_S * SR), WIN_S * SR
    peaks = []
    for s in range(0, n - win - maxlag, win):
        a = sysa[s:s + win]
        a = a - a.mean()
        if np.sqrt(np.mean(a ** 2)) < SILENCE_RMS:
            continue
        best = (0, -1.0)
        for lag in range(0, maxlag, 8):
            b = mic[s + lag:s + lag + win]
            b = b - b.mean()
            c = float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))
            if c > best[1]:
                best = (lag, c)
        peaks.append(best)
    return peaks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--start", type=float, default=600)
    ap.add_argument("--dur", type=float, default=180)
    args = ap.parse_args()

    if track_count(args.file) < 2:
        print("needs a dual-track file (system + mic); this file has fewer than 2 audio tracks")
        return 2
    peaks = measure(load(args.file, 0, args.start, args.dur),
                    load(args.file, 1, args.start, args.dur))
    if not peaks:
        print("no windows with system audio in the chosen range — try another --start")
        return 1
    lags = np.array([p[0] for p in peaks]) / SR * 1000
    cs = np.array([p[1] for p in peaks])
    print(f"windows={len(peaks)} corr median={np.median(cs):.3f} max={cs.max():.3f} "
          f"lag@max={lags[cs.argmax()]:.0f}ms lag median={np.median(lags):.0f}ms "
          f"windows corr>{BLEED_CORR}: {(cs > BLEED_CORR).sum()}")
    print("verdict:", "BLEED" if np.median(cs) > BLEED_CORR else "no bleed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
