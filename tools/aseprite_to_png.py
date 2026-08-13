#!/usr/bin/env python3
"""Decode the .aseprite sources in assets/Sprites/ into flat PNGs.

Godot cannot import .aseprite natively, and the usual importer addons shell out
to the Aseprite binary. These sprites are small, single-frame and simple, so we
decode the format directly instead — no Aseprite install, no addon, no
dependencies beyond the standard library.

The .aseprite files stay the source of truth. Re-run this after editing art:

    python3 tools/aseprite_to_png.py

Format reference: https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md
"""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

ASEPRITE_MAGIC = 0xA5E0
FRAME_MAGIC = 0xF1FA

CHUNK_PALETTE = 0x2019
CHUNK_CEL = 0x2005

CEL_RAW = 0
CEL_LINKED = 1
CEL_COMPRESSED = 2

DEPTH_INDEXED = 8
DEPTH_GRAYSCALE = 16
DEPTH_RGBA = 32

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO_ROOT / "assets" / "Sprites"

# Deliberately not "assets/sprites": macOS is case-insensitive, so that path
# collapses into the Sprites source directory here but stays distinct on Linux
# and in the HTML5 export. "generated" also signals these are build outputs.
OUTPUT_DIR = REPO_ROOT / "assets" / "generated"

Pixel = tuple[int, int, int, int]
TRANSPARENT: Pixel = (0, 0, 0, 0)


class AsepriteError(Exception):
    """Raised when a file does not match the expected Aseprite layout."""


def _read_header(data: bytes) -> tuple[int, int, int, int, int]:
    """Return (frames, width, height, colour_depth, transparent_index)."""
    if len(data) < 128:
        raise AsepriteError("file shorter than the 128-byte header")
    magic = struct.unpack_from("<H", data, 4)[0]
    if magic != ASEPRITE_MAGIC:
        raise AsepriteError(f"bad magic {magic:#06x}, expected {ASEPRITE_MAGIC:#06x}")
    frames, width, height, depth = struct.unpack_from("<HHHH", data, 6)
    transparent_index = data[28]
    return frames, width, height, depth, transparent_index


def _read_palette(body: bytes) -> dict[int, Pixel]:
    """Parse a 0x2019 palette chunk body into {index: rgba}."""
    _size, first, last = struct.unpack_from("<III", body, 0)
    palette: dict[int, Pixel] = {}
    offset = 20  # 3 DWORDs + 8 reserved bytes
    for index in range(first, last + 1):
        flags = struct.unpack_from("<H", body, offset)[0]
        offset += 2
        red, green, blue, alpha = body[offset : offset + 4]
        offset += 4
        if flags & 1:  # entry carries a name we do not need
            name_length = struct.unpack_from("<H", body, offset)[0]
            offset += 2 + name_length
        palette[index] = (red, green, blue, alpha)
    return palette


def _read_cel(body: bytes) -> tuple[int, int, int, int, bytes] | None:
    """Parse a 0x2005 cel chunk body into (x, y, width, height, pixels)."""
    _layer, pos_x, pos_y, _opacity, cel_type = struct.unpack_from("<HhhBH", body, 0)
    if cel_type == CEL_LINKED:
        return None  # only meaningful across frames; these files are single-frame
    if cel_type not in (CEL_RAW, CEL_COMPRESSED):
        raise AsepriteError(f"unsupported cel type {cel_type}")
    width, height = struct.unpack_from("<HH", body, 16)
    payload = body[20:]
    pixels = zlib.decompress(payload) if cel_type == CEL_COMPRESSED else payload
    return pos_x, pos_y, width, height, pixels


def _cel_pixel(
    pixels: bytes, index: int, depth: int, palette: dict[int, Pixel], transparent_index: int
) -> Pixel:
    """Resolve one cel pixel to RGBA, honouring the file's colour depth."""
    if depth == DEPTH_RGBA:
        red, green, blue, alpha = pixels[index * 4 : index * 4 + 4]
        return (red, green, blue, alpha)
    if depth == DEPTH_GRAYSCALE:
        value, alpha = pixels[index * 2 : index * 2 + 2]
        return (value, value, value, alpha)
    entry = pixels[index]
    if entry == transparent_index:
        return TRANSPARENT
    return palette.get(entry, TRANSPARENT)


def decode(path: Path) -> tuple[int, int, list[Pixel]]:
    """Decode an .aseprite file into (width, height, flat RGBA canvas)."""
    data = path.read_bytes()
    frames, width, height, depth, transparent_index = _read_header(data)
    if frames != 1:
        raise AsepriteError(f"expected 1 frame, found {frames}")

    canvas: list[Pixel] = [TRANSPARENT] * (width * height)
    palette: dict[int, Pixel] = {}

    offset = 128
    frame_magic = struct.unpack_from("<H", data, offset + 4)[0]
    if frame_magic != FRAME_MAGIC:
        raise AsepriteError(f"bad frame magic {frame_magic:#06x}")
    old_chunks, _duration, new_chunks = struct.unpack_from("<HH2xI", data, offset + 6)
    chunk_count = new_chunks or old_chunks
    offset += 16

    # Cels are composited in file order so multi-layer sources flatten correctly.
    for _ in range(chunk_count):
        chunk_size, chunk_type = struct.unpack_from("<IH", data, offset)
        body = data[offset + 6 : offset + chunk_size]
        if chunk_type == CHUNK_PALETTE:
            palette.update(_read_palette(body))
        elif chunk_type == CHUNK_CEL:
            cel = _read_cel(body)
            if cel is not None:
                _blit(cel, canvas, width, height, depth, palette, transparent_index)
        offset += chunk_size

    return width, height, canvas


def _blit(
    cel: tuple[int, int, int, int, bytes],
    canvas: list[Pixel],
    width: int,
    height: int,
    depth: int,
    palette: dict[int, Pixel],
    transparent_index: int,
) -> None:
    """Composite one cel onto the canvas, clipping to the canvas bounds.

    Cel offsets can be negative and cels can be larger than the canvas —
    Ladder.aseprite is a 12x16 cel at (2, -8) on a 16x8 canvas, framing one
    tile's worth of a taller repeating unit. Clipping reproduces what Aseprite
    shows on screen.
    """
    cel_x, cel_y, cel_w, cel_h, pixels = cel
    for row in range(cel_h):
        target_y = cel_y + row
        if not 0 <= target_y < height:
            continue
        for col in range(cel_w):
            target_x = cel_x + col
            if not 0 <= target_x < width:
                continue
            pixel = _cel_pixel(pixels, row * cel_w + col, depth, palette, transparent_index)
            if pixel[3] != 0:
                canvas[target_y * width + target_x] = pixel


def write_png(path: Path, width: int, height: int, canvas: list[Pixel]) -> None:
    """Write an 8-bit RGBA PNG. No filtering — these images are tiny."""

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0 (None) for this scanline
        for x in range(width):
            raw.extend(canvas[y * width + x])

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def read_png(path: Path) -> tuple[int, int, list[Pixel]]:
    """Read an 8-bit RGBA PNG back, for tools that compose existing output.

    Deliberately narrow: it handles what `write_png` produces plus the standard
    filters, because every PNG it is pointed at in this project came from that
    function. Palette images, 16-bit channels and interlacing are not supported
    and would need a real decoder.
    """
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")

    idat = bytearray()
    width = height = 0
    pos = 8
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        tag = data[pos + 4 : pos + 8]
        payload = data[pos + 8 : pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", payload[:10])
            if depth != 8 or colour != 6:
                raise ValueError(f"{path}: only 8-bit RGBA is supported")
        elif tag == b"IDAT":
            idat.extend(payload)
        pos += 12 + length

    raw = zlib.decompress(bytes(idat))
    stride = width * 4
    pixels: list[Pixel] = []
    previous = bytearray(stride)
    offset = 0

    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        line = bytearray(raw[offset : offset + stride])
        offset += stride

        for i in range(stride):
            left = line[i - 4] if i >= 4 else 0
            up = previous[i]
            up_left = previous[i - 4] if i >= 4 else 0
            if filter_type == 1:
                line[i] = (line[i] + left) & 0xFF
            elif filter_type == 2:
                line[i] = (line[i] + up) & 0xFF
            elif filter_type == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xFF
            elif filter_type == 4:
                estimate = left + up - up_left
                da, db, dc = (
                    abs(estimate - left),
                    abs(estimate - up),
                    abs(estimate - up_left),
                )
                if da <= db and da <= dc:
                    line[i] = (line[i] + left) & 0xFF
                elif db <= dc:
                    line[i] = (line[i] + up) & 0xFF
                else:
                    line[i] = (line[i] + up_left) & 0xFF

        for x in range(width):
            pixels.append(tuple(line[x * 4 : x * 4 + 4]))  # type: ignore[arg-type]
        previous = line

    return width, height, pixels


def main() -> int:
    sources = sorted(SOURCE_DIR.glob("*.aseprite"))
    if not sources:
        print(f"no .aseprite files found in {SOURCE_DIR}", file=sys.stderr)
        return 1

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    failures = 0
    for source in sources:
        try:
            width, height, canvas = decode(source)
        except AsepriteError as error:
            print(f"FAIL {source.name}: {error}", file=sys.stderr)
            failures += 1
            continue
        destination = OUTPUT_DIR / f"{source.stem}.png"
        write_png(destination, width, height, canvas)
        opaque = sum(1 for pixel in canvas if pixel[3] != 0)
        print(f"  {source.name:24} -> {destination.name:24} {width}x{height}  {opaque} px")

    print(f"\n{len(sources) - failures}/{len(sources)} sprites written to {OUTPUT_DIR}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
