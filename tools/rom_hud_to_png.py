#!/usr/bin/env python3
"""Generate ROM sprites that have no Aseprite source.

The digits and labels (SCORE, PLAYER, LEVEL, BONUS, TIME) exist only as bitmaps
in the reference implementation's spritedata.c — there is no Aseprite artwork for
them, because they are the original's built-in text rather than drawn sprites.

    python3 tools/rom_hud_to_png.py

Two kinds of thing land here. The HUD glyphs go to assets/generated/hud/, and
the closed cage to assets/generated/ beside the rest of the sprites — the art
only has `Cage.aseprite`, which is the *open* cage, so the closed one has to
come from the ROM.

Unlike everything else in assets/generated/, these have **no .aseprite source**:
they are produced from the ROM directly.
Deliberately so — the alternative was synthesising .aseprite files from scratch,
which cannot be verified here because Aseprite is not installed, and an
unopenable source file is worse than none. If these ever need restyling, draw
real .aseprite files and aseprite_to_png.py takes over.

Colours follow the reference: HUD text and digits use COLOR_HUD (magenta), while
the life markers use PLANE_YELLOW.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from aseprite_to_png import write_png  # noqa: E402
from rom_to_aseprite import fetch_spritedata, parse_rom_sprites, rom_to_pixels  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "assets" / "generated" / "hud"
SPRITE_DIR = REPO_ROOT / "assets" / "generated"

## Sprites with no Aseprite source, emitted alongside the ordinary art.
EXTRA_SPRITES = [("CAGE_CLOSED", "CageClosed", 2)]

## Project palette indices, matching Palette.aseprite.
COLOUR_YELLOW = 2
COLOUR_MAGENTA = 4

PALETTE = {
    COLOUR_YELLOW: (255, 255, 0, 255),
    COLOUR_MAGENTA: (255, 0, 255, 255),
}

## ROM sprite -> output name, and the colour it is drawn in.
LABELS = [
    ("SCORE", "label_score", COLOUR_MAGENTA),
    ("PLAYER", "label_player", COLOUR_MAGENTA),
    ("LEVEL", "label_level", COLOUR_MAGENTA),
    ("BONUS", "label_bonus", COLOUR_MAGENTA),
    ("TIME", "label_time", COLOUR_MAGENTA),
    ("BLANK", "label_blank", COLOUR_MAGENTA),
]


def emit(
    name: str, width: int, height: int, data: list[int], colour: int, directory: Path = None
) -> tuple[int, int]:
    """Expand one ROM sprite to RGBA and write it out."""
    indexed = rom_to_pixels(width, height, data, colour)
    rgba = [PALETTE[colour] if value else (0, 0, 0, 0) for value in indexed]
    target = (directory or OUTPUT_DIR) / f"{name}.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    write_png(target, width * 2, height, rgba)
    return width * 2, height


def main() -> int:
    source = fetch_spritedata(sys.argv[1] if len(sys.argv) > 1 else None)
    sprites = parse_rom_sprites(source)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    written = 0

    # Digits live in a `sprite_t sprite_digit[10]` array, which the generic
    # parser does not pick up, so pull them out of the same source separately.
    digits = parse_digits(source)
    if len(digits) != 10:
        print(f"expected 10 digits, parsed {len(digits)}", file=sys.stderr)
        return 1
    for value, (width, height, data) in enumerate(digits):
        size = emit(f"digit_{value}", width, height, data, COLOUR_MAGENTA)
        print(f"  digit_{value}.png  {size[0]}x{size[1]}")
        written += 1

    for rom_name, out_name, colour in LABELS:
        if rom_name not in sprites:
            print(f"missing ROM sprite SPRITE_{rom_name}", file=sys.stderr)
            return 1
        width, height, data = sprites[rom_name]
        size = emit(out_name, width, height, data, colour)
        print(f"  {out_name}.png  {size[0]}x{size[1]}")
        written += 1

    for rom_name, out_name, colour in EXTRA_SPRITES:
        if rom_name not in sprites:
            print(f"missing ROM sprite SPRITE_{rom_name}", file=sys.stderr)
            return 1
        width, height, data = sprites[rom_name]
        size = emit(out_name, width, height, data, colour, SPRITE_DIR)
        print(f"  {out_name}.png  {size[0]}x{size[1]}  -> {SPRITE_DIR.name}/")
        written += 1

    print(f"\n{written} sprites written")
    return 0


def parse_digits(source: str) -> list[tuple[int, int, list[int]]]:
    """Pull the ten entries out of `sprite_t sprite_digit[10] = { ... }`."""
    import re

    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    match = re.search(r"sprite_t\s+sprite_digit\[10\]\s*=\s*\{(.*?)\n\};", source, re.S)
    if match is None:
        return []
    digits: list[tuple[int, int, list[int]]] = []
    # Each entry is `{ width, height, { bytes } }`. Match the width/height pair
    # explicitly — a bare innermost-brace match would find the byte array first
    # and mistake its first two bytes for the dimensions.
    entry = r"(0x[0-9a-fA-F]+|\d+)\s*,\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*\{([^}]*)\}"
    for found in re.finditer(entry, match.group(1), re.S):
        width = int(found.group(1), 0)
        height = int(found.group(2), 0)
        data = [int(n, 0) for n in re.findall(r"0x[0-9a-fA-F]+|\d+", found.group(3))]
        digits.append((width, height, data))
    return digits


if __name__ == "__main__":
    sys.exit(main())
