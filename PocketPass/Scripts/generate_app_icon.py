#!/usr/bin/env python3
"""Generate PocketPass's 1024x1024 App Store icon.

The icon is generated rather than hand-drawn so it can be regenerated or re-tinted
without a design tool. It is rendered at 2x and box-filtered down, which gives clean
edges without any imaging dependency.

Usage:
    python3 Scripts/generate_app_icon.py [output.png]
"""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
SUPERSAMPLE = 2

BACKGROUND_START = (0x1E, 0x7B, 0xBF)
BACKGROUND_END = (0x0B, 0x33, 0x58)
CARD = (0xFF, 0xFF, 0xFF)
INK = (0x0C, 0x3D, 0x63)

# Layout in 1024-point space.
CARD_RECT = (172, 212, 852, 812)
CARD_RADIUS = 84
QR_RECT = (332, 272, 692, 632)  # 360x360, 9x9 modules of 40
QR_MODULES = 9
BARCODE_RECT = (262, 676, 762, 766)

# 9x9 QR-style mark: three finder patterns plus a little data noise.
QR_PATTERN = [
    "111010111",
    "101000101",
    "111010111",
    "000010000",
    "011101100",
    "000010000",
    "111011010",
    "101000110",
    "111010011",
]

# Bar widths (in points) alternating bar/space across the barcode strip.
BAR_WIDTHS = [14, 10, 24, 10, 12, 18, 10, 30, 12, 10, 20, 14, 10, 26, 10, 16,
              12, 10, 22, 14, 10, 18, 12, 28, 10, 12, 20, 10, 16, 10]


def lerp(a: int, b: int, t: float) -> int:
    return int(round(a + (b - a) * t))


def background_color(x: float, y: float) -> tuple[int, int, int]:
    t = min(1.0, max(0.0, (x + y) / (2 * SIZE)))
    return tuple(lerp(BACKGROUND_START[i], BACKGROUND_END[i], t) for i in range(3))


def in_rounded_rect(x: float, y: float, rect, radius: float) -> bool:
    x0, y0, x1, y1 = rect
    if not (x0 <= x <= x1 and y0 <= y <= y1):
        return False
    cx = min(max(x, x0 + radius), x1 - radius)
    cy = min(max(y, y0 + radius), y1 - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def in_qr(x: float, y: float) -> bool:
    x0, y0, x1, y1 = QR_RECT
    if not (x0 <= x < x1 and y0 <= y < y1):
        return False
    module = (x1 - x0) / QR_MODULES
    column = int((x - x0) / module)
    row = int((y - y0) / module)
    return QR_PATTERN[row][column] == "1"


def in_barcode(x: float, y: float) -> bool:
    x0, y0, x1, y1 = BARCODE_RECT
    if not (x0 <= x < x1 and y0 <= y <= y1):
        return False
    offset = x - x0
    cursor = 0.0
    for index, width in enumerate(BAR_WIDTHS):
        if cursor <= offset < cursor + width:
            return index % 2 == 0
        cursor += width
    return False


def sample(x: float, y: float) -> tuple[int, int, int]:
    if in_rounded_rect(x, y, CARD_RECT, CARD_RADIUS):
        if in_qr(x, y) or in_barcode(x, y):
            return INK
        return CARD
    return background_color(x, y)


def render() -> bytes:
    scale = SUPERSAMPLE
    rows = []
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            totals = [0, 0, 0]
            for sy in range(scale):
                for sx in range(scale):
                    x = px + (sx + 0.5) / scale
                    y = py + (sy + 0.5) / scale
                    color = sample(x, y)
                    for i in range(3):
                        totals[i] += color[i]
            samples = scale * scale
            row.extend(bytes(total // samples for total in totals))
        rows.append(bytes(row))
    return encode_png(SIZE, SIZE, rows)


def encode_png(width: int, height: int, rows: list[bytes]) -> bytes:
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        payload = tag + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB, no alpha
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main() -> int:
    default = Path(__file__).resolve().parent.parent / "PocketPass" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(render())
    print(f"Wrote {output} ({output.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
