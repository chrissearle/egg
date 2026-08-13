#!/usr/bin/env python3
"""Rewrite a sprite's .aseprite cel from the original ROM bitmap.

The art in assets/Sprites was traced from the BBC ROM sprites, but tracing can
slip. This repairs a source file in place from the authoritative bitmap in the
reference implementation's spritedata.c, so the .aseprite stays the source of
truth and aseprite_to_png.py keeps producing matching output.

    python3 tools/rom_to_aseprite.py PLAYER_UP ClimbUp
    python3 tools/rom_to_aseprite.py --check PLAYER_UP ClimbUp

`--check` reports differences without writing anything.

ROM sprites are stored as 1bpp in BBC wide-pixels. Each wide-pixel becomes two
square pixels here, matching how the rest of the art is authored. Bits are read
as one continuous stream across the whole sprite rather than being re-aligned
per row, exactly as Do_RenderSprite does.

Only the cel chunk is touched — palette, layer and header chunks are preserved
byte for byte.
"""

from __future__ import annotations

import argparse
import struct
import sys
import urllib.request
import zlib
from pathlib import Path

SPRITEDATA_URL = (
    "https://raw.githubusercontent.com/pbrook/Chuckie-Egg/master/spritedata.c"
)

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO_ROOT / "assets" / "Sprites"

CHUNK_CEL = 0x2005
CEL_COMPRESSED = 2
CEL_HEADER_BYTES = 16

## Palette index used for a set pixel. 2 is yellow in the project palette, which
## is the colour of every player, egg, lift and cage sprite.
DEFAULT_COLOUR_INDEX = 2

## Some sources are 32-bit RGBA rather than indexed — the mother duck is — so a
## rewrite has to match the file's own depth or the decoder chokes on it. These
## are the project palette's colours, from Palette.aseprite.
DEPTH_INDEXED = 8
DEPTH_RGBA = 32
PALETTE_RGBA = {
    1: (0, 0, 0, 255),
    2: (255, 255, 0, 255),
    3: (0, 255, 255, 255),
    4: (255, 0, 255, 255),
    5: (0, 255, 0, 255),
}


def fetch_spritedata(path: str | None) -> str:
    if path:
        return Path(path).read_text()
    with urllib.request.urlopen(SPRITEDATA_URL) as response:
        return response.read().decode("utf-8")


def parse_rom_sprites(source: str) -> dict[str, tuple[int, int, list[int]]]:
    """Extract `sprite_t SPRITE_X = { w, h, { bytes } };` definitions."""
    import re

    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    sprites: dict[str, tuple[int, int, list[int]]] = {}
    pattern = r"sprite_t\s+SPRITE_(\w+)\s*=\s*\{(.*?)\}\s*;"
    for match in re.finditer(pattern, source, re.S):
        name = match.group(1)
        body = match.group(2)
        numbers = [int(n, 0) for n in re.findall(r"0x[0-9a-fA-F]+|\d+", body)]
        if len(numbers) < 2:
            continue
        width, height = numbers[0], numbers[1]
        sprites[name] = (width, height, numbers[2:])
    return sprites


def rom_to_pixels(width: int, height: int, data: list[int], colour: int) -> bytes:
    """Expand a 1bpp ROM sprite into indexed pixels at 2x horizontal scale."""
    pixels = bytearray(width * 2 * height)
    bit_source = 0
    bits_left = 0
    index = 0
    out = 0
    for _ in range(height):
        for _ in range(width):
            if bits_left == 0:
                bit_source = data[index]
                index += 1
                bits_left = 8
            value = colour if (bit_source & 0x80) else 0
            bit_source = (bit_source << 1) & 0xFF
            bits_left -= 1
            pixels[out] = value
            pixels[out + 1] = value
            out += 2
    return bytes(pixels)


def read_cel(data: bytes) -> tuple[int, int, int, int, int, bytes]:
    """Locate the cel chunk. Returns (offset, size, width, height, x, pixels)."""
    offset = 128
    old_chunks, new_chunks = struct.unpack_from("<H2xI", data, offset + 6)
    count = new_chunks or old_chunks
    offset += 16
    for _ in range(count):
        chunk_size, chunk_type = struct.unpack_from("<IH", data, offset)
        if chunk_type == CHUNK_CEL:
            body = data[offset + 6 : offset + chunk_size]
            _layer, pos_x, pos_y, _opacity, cel_type = struct.unpack_from("<HhhBH", body, 0)
            if cel_type != CEL_COMPRESSED:
                raise SystemExit(f"unsupported cel type {cel_type}")
            width, height = struct.unpack_from("<HH", body, CEL_HEADER_BYTES)
            return (
                offset,
                chunk_size,
                width,
                height,
                pos_y,
                zlib.decompress(body[CEL_HEADER_BYTES + 4 :]),
            )
        offset += chunk_size
    raise SystemExit("no cel chunk found")


def encode_pixels(pixels: bytes, depth: int, colour: int) -> bytes:
    """Match the file's colour depth: indexed files take the palette index,
    32-bit ones take the palette entry expanded to RGBA."""
    if depth == DEPTH_INDEXED:
        return pixels
    if depth != DEPTH_RGBA:
        raise SystemExit(f"unsupported colour depth {depth}")
    rgba = PALETTE_RGBA.get(colour)
    if rgba is None:
        raise SystemExit(f"no palette entry for colour {colour}")
    out = bytearray()
    for value in pixels:
        out += bytes(rgba) if value else bytes(4)
    return bytes(out)


def rewrite(path: Path, width: int, height: int, pixels: bytes, colour: int) -> None:
    """Replace the cel's geometry and pixel data, fixing up the size fields."""
    data = bytearray(path.read_bytes())
    depth = struct.unpack_from("<H", data, 12)[0]
    pixels = encode_pixels(pixels, depth, colour)
    offset, chunk_size, _w, _h, _y, _old = read_cel(bytes(data))

    header = data[offset + 6 : offset + 6 + CEL_HEADER_BYTES]
    struct.pack_into("<hh", header, 2, 0, 0)  # reset cel position to the origin
    body = bytes(header) + struct.pack("<HH", width, height) + zlib.compress(pixels, 9)
    chunk = struct.pack("<IH", len(body) + 6, CHUNK_CEL) + body

    data[offset : offset + chunk_size] = chunk
    delta = len(chunk) - chunk_size

    frame_size = struct.unpack_from("<I", data, 128)[0]
    struct.pack_into("<I", data, 128, frame_size + delta)
    struct.pack_into("<I", data, 0, len(data))
    path.write_bytes(bytes(data))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rom_name", help="ROM sprite name without the SPRITE_ prefix")
    parser.add_argument("aseprite_name", help="target file in assets/Sprites, without .aseprite")
    parser.add_argument("--check", action="store_true", help="report differences, write nothing")
    parser.add_argument("--colour", type=int, default=DEFAULT_COLOUR_INDEX)
    parser.add_argument("--spritedata", help="local spritedata.c instead of downloading")
    args = parser.parse_args()

    sprites = parse_rom_sprites(fetch_spritedata(args.spritedata))
    if args.rom_name not in sprites:
        print(f"unknown ROM sprite {args.rom_name!r}", file=sys.stderr)
        print(f"available: {', '.join(sorted(sprites))}", file=sys.stderr)
        return 1

    width, height, rom = sprites[args.rom_name]
    expected = rom_to_pixels(width, height, rom, args.colour)

    path = SOURCE_DIR / f"{args.aseprite_name}.aseprite"
    raw = path.read_bytes()
    depth = struct.unpack_from("<H", raw, 12)[0]
    _off, _size, cel_w, cel_h, cel_y, current = read_cel(raw)
    if depth == DEPTH_RGBA:
        # Compare set/clear, not exact bytes, so a colour difference does not
        # masquerade as a shape difference.
        current = bytes(1 if current[i * 4 + 3] else 0 for i in range(len(current) // 4))
        expected = bytes(1 if v else 0 for v in expected)

    print(f"ROM SPRITE_{args.rom_name}: {width}x{height} wide-px -> {width * 2}x{height} square")
    print(f"{path.name} cel: {cel_w}x{cel_h} at y={cel_y}")

    if (cel_w, cel_h, cel_y) == (width * 2, height, 0) and current == expected:
        print("already matches the ROM; nothing to do")
        return 0

    differing = sum(
        1
        for i in range(min(len(current), len(expected)))
        if (current[i] != 0) != (expected[i] != 0)
    )
    print(f"differs: geometry {(cel_w, cel_h)} vs {(width * 2, height)}, {differing} pixels")

    if args.check:
        print("--check given, not writing")
        return 1

    rewrite(path, width * 2, height, expected, args.colour)
    print(f"rewrote {path.name} from SPRITE_{args.rom_name}")
    print("now re-run: python3 tools/aseprite_to_png.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
