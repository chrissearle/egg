#!/usr/bin/env python3
"""Extract the CHUCKIE EGG title banner letters.

The banner is drawn by `draw_chuckie_banner` from sprite codes 0x30-0x36, which
sit past `SPRITE_HAT` at 0x2f where the reference implementation's spritedata.c
stops — pbrook never extracted them. They are in the annotated BBC disassembly
at https://github.com/mungre/chuckie as bmp_48 to bmp_54, each 16 wide-pixels by
30 rows.

    python3 tools/rom_banner_to_png.py [path/to/sprites.basm]

Writes assets/generated/banner/*.png. Like the HUD glyphs these have no Aseprite
source; they are ROM artwork with no counterpart in assets/Sprites.

Provenance: the level and sprite data come via pbrook's GPL-3.0 repo. These come
from a disassembly with no stated licence, as the death tune's notes do. No ROM
is shipped.
"""

from __future__ import annotations

import re
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from aseprite_to_png import write_png  # noqa: E402

SPRITES_URL = "https://raw.githubusercontent.com/mungre/chuckie/master/asm/sprites.basm"

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "assets" / "generated" / "banner"

## Sprite code -> the letter it draws, from draw_chuckie_banner's call order.
## Codes 0x30..0x36 are bmp_48..bmp_54.
FIRST_CODE = 0x30
FIRST_BITMAP = 48
LETTERS = "CHUKIEG"

## Every banner letter is this size, per the sprite lookup table.
LETTER_WIDTH = 16
LETTER_HEIGHT = 30

YELLOW = (255, 255, 0, 255)
CLEAR = (0, 0, 0, 0)


def fetch(path: str | None) -> str:
    if path:
        return Path(path).read_text()
    with urllib.request.urlopen(SPRITES_URL) as response:
        return response.read().decode("utf-8")


def parse_bitmap(source: str, index: int) -> list[int]:
    """Pull one `.bmp_N` block's bytes. They are written as binary literals."""
    pattern = r"^\.bmp_%d\b(.*?)(?=^\.bmp_\d|\Z)" % index
    match = re.search(pattern, source, re.S | re.M)
    if match is None:
        raise SystemExit(f"bmp_{index} not found")
    return [int(bits, 2) for bits in re.findall(r"%([01]{8})", match.group(1))]


def emit(letter: str, data: list[int]) -> tuple[int, int]:
    """Expand a 1bpp letter to RGBA, doubled horizontally into square pixels."""
    per_row = LETTER_WIDTH // 8
    expected = per_row * LETTER_HEIGHT
    if len(data) != expected:
        raise SystemExit(f"{letter}: expected {expected} bytes, found {len(data)}")

    pixels: list[tuple[int, int, int, int]] = []
    for row in range(LETTER_HEIGHT):
        for byte_index in range(per_row):
            value = data[row * per_row + byte_index]
            for bit in range(8):
                colour = YELLOW if (value >> (7 - bit)) & 1 else CLEAR
                pixels.append(colour)
                pixels.append(colour)
    write_png(OUTPUT_DIR / f"{letter}.png", LETTER_WIDTH * 2, LETTER_HEIGHT, pixels)
    return LETTER_WIDTH * 2, LETTER_HEIGHT


def main() -> int:
    source = fetch(sys.argv[1] if len(sys.argv) > 1 else None)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for offset, letter in enumerate(LETTERS):
        data = parse_bitmap(source, FIRST_BITMAP + offset)
        width, height = emit(letter, data)
        code = FIRST_CODE + offset
        print(f"  {letter}.png  {width}x{height}  (sprite {code:#04x} = bmp_{FIRST_BITMAP + offset})")

    print(f"\n{len(LETTERS)} banner letters written to {OUTPUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
