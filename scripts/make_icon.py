#!/usr/bin/env python3
"""
Generate AppIcon.icns for TeamRecorderBar.
Pure Python stdlib only — no pip installs, no PyObjC needed.
Uses iconutil (macOS built-in) to assemble the final .icns.

Run once and commit the result:
    make icon
"""
import math
import os
import shutil
import struct
import subprocess
import zlib

OUT_ICNS = "menu-bar/Resources/AppIcon.icns"
ICONSET  = "/tmp/TeamRecorderAppIcon.iconset"
SIZES    = [16, 32, 128, 256, 512]


# ── Icon palette ─────────────────────────────────────────────────────────────
BLUE  = (0, 122, 255)   # #007AFF — Apple blue
WHITE = (255, 255, 255)


def make_png_bytes(size: int) -> bytes:
    """
    Render the icon at `size`×`size` and return raw PNG bytes.
    Design: blue circle + 5 white waveform bars (centre-aligned).
    """
    s = size
    pixels = [(0, 0, 0, 0)] * (s * s)   # RGBA, start fully transparent

    # ── Blue circle ────────────────────────────────────────────────────────
    cx = s / 2.0
    cy = s / 2.0
    pad = s * 0.03
    r = (s - pad * 2) / 2.0

    for y in range(s):
        for x in range(s):
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            dist = math.sqrt(dx * dx + dy * dy)
            if dist <= r - 0.5:
                a = 255
            elif dist >= r + 0.5:
                a = 0
            else:
                # sub-pixel anti-alias on the edge
                a = int((r + 0.5 - dist) * 255)
            if a:
                pixels[y * s + x] = (BLUE[0], BLUE[1], BLUE[2], a)

    # ── White waveform bars ────────────────────────────────────────────────
    bar_heights = [0.25, 0.45, 0.65, 0.45, 0.25]
    bar_w = s * 0.09
    gap   = s * 0.04
    total_w = len(bar_heights) * bar_w + (len(bar_heights) - 1) * gap
    start_x = (s - total_w) / 2.0

    for i, rel_h in enumerate(bar_heights):
        bh = s * rel_h
        bx = start_x + i * (bar_w + gap)
        by = (s - bh) / 2.0

        x0 = int(round(bx))
        x1 = max(x0 + 1, int(round(bx + bar_w)))
        y0 = int(round(by))
        y1 = max(y0 + 1, int(round(by + bh)))

        for py in range(y0, y1):
            for px in range(x0, x1):
                if 0 <= px < s and 0 <= py < s:
                    # Inherit the circle's alpha so bars clip to the circle edge
                    _, _, _, a = pixels[py * s + px]
                    pixels[py * s + px] = (WHITE[0], WHITE[1], WHITE[2], a)

    return _encode_png(s, s, pixels)


def _encode_png(width: int, height: int, pixels: list) -> bytes:
    """Minimal RGBA PNG encoder (no external deps)."""

    def chunk(tag: bytes, data: bytes) -> bytes:
        payload = tag + data
        crc = zlib.crc32(payload) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", crc)

    signature = b"\x89PNG\r\n\x1a\n"

    ihdr_data = struct.pack(">II", width, height) + bytes([
        8,   # bit depth
        6,   # colour type: RGBA
        0,   # compression method
        0,   # filter method
        0,   # interlace method
    ])
    ihdr = chunk(b"IHDR", ihdr_data)

    raw = bytearray()
    for y in range(height):
        raw.append(0)           # filter: None
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            raw += bytes([r, g, b, a])

    idat = chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    iend = chunk(b"IEND", b"")

    return signature + ihdr + idat + iend


def run() -> None:
    os.makedirs(ICONSET, exist_ok=True)
    try:
        for sz in SIZES:
            data_1x = make_png_bytes(sz)
            data_2x = make_png_bytes(sz * 2)

            with open(f"{ICONSET}/icon_{sz}x{sz}.png", "wb") as f:
                f.write(data_1x)
            with open(f"{ICONSET}/icon_{sz}x{sz}@2x.png", "wb") as f:
                f.write(data_2x)

        # iconutil expects icon_512x512@2x.png (= 1024×1024) — already written above

        subprocess.run(
            ["iconutil", "-c", "icns", ICONSET, "-o", OUT_ICNS],
            check=True,
        )
        print(f"  ✓  {OUT_ICNS}")
    finally:
        shutil.rmtree(ICONSET, ignore_errors=True)


if __name__ == "__main__":
    run()
