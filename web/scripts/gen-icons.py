#!/usr/bin/env python3
"""Generate simple Rohomieo PWA icons (blue R on dark background)."""
import struct
import zlib
from pathlib import Path

def png_chunk(tag: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

def write_png(path: Path, size: int) -> None:
  rows = []
  for y in range(size):
    row = bytearray([0])  # filter byte
    for x in range(size):
      # dark bg with blue accent circle
      cx, cy = size / 2, size / 2
      d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
      if d < size * 0.38:
        r, g, b = 61, 158, 255
      else:
        r, g, b = 15, 20, 25
      row.extend([r, g, b, 255])
    rows.append(bytes(row))
  raw = b"".join(rows)
  compressed = zlib.compress(raw, 9)
  ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
  png = b"\x89PNG\r\n\x1a\n"
  png += png_chunk(b"IHDR", ihdr)
  png += png_chunk(b"IDAT", compressed)
  png += png_chunk(b"IEND", b"")
  path.write_bytes(png)

out = Path(__file__).resolve().parent.parent / "public"
out.mkdir(parents=True, exist_ok=True)
write_png(out / "icon-192.png", 192)
write_png(out / "icon-512.png", 512)
print("wrote", out / "icon-192.png", out / "icon-512.png")
