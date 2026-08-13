#!/usr/bin/env python3
"""Pack the BBC OS font into one sprite sheet, for the web pages.

The game draws its messages one glyph at a time from assets/generated/font/, but
a web page wants a single image it can mask against — 95 separate requests would
be silly, and CSS has no equivalent of the game's per-glyph draw call.

    python3 tools/font_sheet_to_png.py [path/to/bbc_micro.yaff]

Writes assets/generated/font_sheet.png: one row of glyphs in codepoint order,
white on transparent so CSS tints them with the palette exactly as `Message`
tints the individual PNGs at draw time.

Reads the same YAFF source as yaff_to_png.py and reuses its parser, so the sheet
and the game's own glyphs cannot drift apart.

Emitted at SCALE times the native cell. The game presents at 3x integer scale,
and a mask that a browser has to resample is a mask that comes out blurry — so
the pixels are multiplied here, where it is exact, rather than in CSS.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from aseprite_to_png import write_png  # noqa: E402
from yaff_to_png import (  # noqa: E402
    CELL_WIDTH,
    CLEAR,
    FIRST_CODEPOINT,
    LAST_CODEPOINT,
    WHITE,
    fetch,
    parse,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT = REPO_ROOT / "assets" / "generated" / "font_sheet.png"

## Wide-pixel doubling, as everywhere else in this project: MODE 2 pixels are
## twice as wide as they are tall.
DOUBLE = 2

## Integer multiple applied on top, matching the game's 3x display scale.
SCALE = 3

CELL_HEIGHT = 8


def cell_pixels(rows: list[str]) -> list[list[bool]]:
    """One glyph as a CELL_HEIGHT x CELL_WIDTH grid of set/clear."""
    grid = []
    for y in range(CELL_HEIGHT):
        row = rows[y] if y < len(rows) else ""
        padded = row.ljust(CELL_WIDTH, ".")[:CELL_WIDTH]
        grid.append([cell == "@" for cell in padded])
    return grid


def main() -> int:
    glyphs = parse(fetch(sys.argv[1] if len(sys.argv) > 1 else None))

    codes = list(range(FIRST_CODEPOINT, LAST_CODEPOINT + 1))
    missing = [c for c in codes if c not in glyphs]
    if missing:
        print("missing codepoints: " + " ".join("%#04x" % c for c in missing), file=sys.stderr)
        return 1

    grids = [cell_pixels(glyphs[code]) for code in codes]

    glyph_w = CELL_WIDTH * DOUBLE * SCALE
    glyph_h = CELL_HEIGHT * SCALE
    sheet_w = glyph_w * len(codes)

    pixels: list[tuple[int, int, int, int]] = []
    for y in range(glyph_h):
        source_y = y // SCALE
        for grid in grids:
            for x in range(CELL_WIDTH):
                colour = WHITE if grid[source_y][x] else CLEAR
                # Doubled for the wide pixel, then again for the display scale.
                pixels.extend([colour] * (DOUBLE * SCALE))

    write_png(OUTPUT, sheet_w, glyph_h, pixels)

    print(f"  {len(codes)} glyphs, {glyph_w}x{glyph_h} each at {SCALE}x")
    print(f"  sheet {sheet_w}x{glyph_h}, covering {chr(FIRST_CODEPOINT)!r} to {chr(LAST_CODEPOINT)!r}")
    print(f"\nwritten to {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
