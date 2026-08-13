#!/usr/bin/env python3
"""Compose the boot splash from the game's own sprites.

    python3 tools/build_splash.py

Writes assets/generated/splash.png at the game's native 320 x 256, so the
engine only ever scales it by whole numbers and it stays as crisp as the game
itself. Set as `application/boot_splash/image`, which covers both the desktop
boot splash and the `index.png` the web shell shows while the wasm loads.

Nothing here is drawn by hand: the platforms, ladders, eggs, corn, Harry, the
hen and the CHUCKIE EGG lettering are the same PNGs the game draws, placed on
the same 16 x 8 tile grid it uses. The only exception is the small author's
logo in the corner, which has no in-game counterpart and is drawn below.

The layout is a slice of a plausible level rather than a real one — the point
is to look like Chuckie Egg at a glance, not to be level 1.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from aseprite_to_png import read_png, write_png  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
GENERATED = REPO_ROOT / "assets" / "generated"
OUTPUT = GENERATED / "splash.png"

WIDTH = 320
HEIGHT = 256

## The game's tile, in square pixels. Everything sits on this grid.
TILE_W = 16
TILE_H = 8

BLACK = (0, 0, 0, 255)
CLEAR = (0, 0, 0, 0)

## The author's logo. Blue is a real BBC MODE 2 colour — one of the eight the
## machine could display — even though the game itself never uses it.
LOGO_BLUE = (0, 75, 255, 255)
LOGO_YELLOW = (255, 247, 0, 255)
LOGO_BLACK = (0, 0, 0, 255)
LOGO_SIZE = 24

## Banner letters and their columns, exactly as `Banner` places them: x is the
## column doubled, which spans the full 320 across.
BANNER_LETTERS = ["C", "H", "U", "C", "K", "I", "E", "E", "G", "G"]
BANNER_COLUMNS = [0x02, 0x11, 0x20, 0x2F, 0x3E, 0x4D, 0x5C, 0x72, 0x81, 0x90]
BANNER_TOP = 24

## Sprite draw offsets within a tile, from CLAUDE.md.
EGG_OFFSET = (2, 1)
CORN_OFFSET = (2, 3)


class Canvas:
    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.pixels = [BLACK] * (width * height)

    def blit(self, sprite: tuple[int, int, list], x: int, y: int) -> None:
        """Draws a sprite, skipping transparent pixels and clipping to bounds."""
        sprite_w, sprite_h, data = sprite
        for sy in range(sprite_h):
            ty = y + sy
            if not 0 <= ty < self.height:
                continue
            for sx in range(sprite_w):
                tx = x + sx
                if not 0 <= tx < self.width:
                    continue
                pixel = data[sy * sprite_w + sx]
                if pixel[3] == 0:
                    continue
                self.pixels[ty * self.width + tx] = pixel

    def dot(self, x: int, y: int, colour: tuple[int, int, int, int]) -> None:
        if 0 <= x < self.width and 0 <= y < self.height:
            self.pixels[y * self.width + x] = colour


def sprite(name: str) -> tuple[int, int, list]:
    return read_png(GENERATED / f"{name}.png")


def tile_x(column: int) -> int:
    return column * TILE_W


def tile_y(row: int) -> int:
    return row * TILE_H


def draw_banner(canvas: Canvas) -> None:
    for letter, column in zip(BANNER_LETTERS, BANNER_COLUMNS):
        canvas.blit(sprite(f"banner/{letter}"), column * 2, BANNER_TOP)


def draw_platform(canvas: Canvas, row: int, first: int, last: int) -> None:
    plank = sprite("Platform")
    for column in range(first, last + 1):
        canvas.blit(plank, tile_x(column), tile_y(row))


def draw_ladder(canvas: Canvas, column: int, top_row: int, bottom_row: int) -> None:
    rung = sprite("Ladder")
    for row in range(top_row, bottom_row + 1):
        canvas.blit(rung, tile_x(column), tile_y(row))


def draw_logo(canvas: Canvas, x: int, y: int) -> None:
    """The author's logo: a blue disc with two eyes.

    Redrawn here rather than downsampled, because at this size the real file's
    proportions do not survive — its pupils would come out a pixel and a half
    across. These are the measured ratios with the pupils opened up enough to
    read as eyes, which at 24 pixels matters more than being exact.
    """
    radius = LOGO_SIZE / 2 - 0.5
    centre = (LOGO_SIZE - 1) / 2

    eyes = [(LOGO_SIZE * 0.30, LOGO_SIZE * 0.30), (LOGO_SIZE * 0.70, LOGO_SIZE * 0.30)]
    eye_radius = LOGO_SIZE * 0.15
    pupil_radius = LOGO_SIZE * 0.075

    for py in range(LOGO_SIZE):
        for px in range(LOGO_SIZE):
            if (px - centre) ** 2 + (py - centre) ** 2 > radius**2:
                continue

            colour = LOGO_BLUE
            for eye_x, eye_y in eyes:
                distance = (px - eye_x + 0.5) ** 2 + (py - eye_y + 0.5) ** 2
                if distance <= pupil_radius**2:
                    colour = LOGO_BLACK
                    break
                if distance <= eye_radius**2:
                    colour = LOGO_YELLOW
                    break

            canvas.dot(x + px, y + py, colour)


def main() -> int:
    canvas = Canvas(WIDTH, HEIGHT)

    draw_banner(canvas)

    # A slice of a level, spread across the space below the lettering rather
    # than bunched in the middle: four floors on the tile grid, joined by
    # ladders, with the bottom one left clear for the logo.
    draw_platform(canvas, 11, 0, 7)
    draw_platform(canvas, 11, 11, 19)
    draw_platform(canvas, 16, 3, 15)
    draw_platform(canvas, 21, 0, 12)
    draw_platform(canvas, 26, 0, 19)

    draw_ladder(canvas, 5, 12, 16)
    draw_ladder(canvas, 13, 17, 21)
    draw_ladder(canvas, 8, 22, 26)

    # Collectables, sitting on the platform below each one.
    for column, row in ((2, 10), (14, 10), (5, 15), (12, 15), (3, 20), (10, 20), (16, 25)):
        canvas.blit(sprite("Egg"), tile_x(column) + EGG_OFFSET[0], tile_y(row) + EGG_OFFSET[1])
    for column, row in ((9, 15), (6, 20), (12, 25)):
        canvas.blit(sprite("Corn"), tile_x(column) + CORN_OFFSET[0], tile_y(row) + CORN_OFFSET[1])

    # Harry climbing, and a hen further down. The hen's art sits on a 28 x 28
    # canvas with the bird low and left in it, so it is nudged to stand on the
    # platform rather than float above it.
    canvas.blit(sprite("ClimbUp"), tile_x(5), tile_y(14))
    canvas.blit(sprite("HenStand"), tile_x(16) - 6, tile_y(24) - 12)

    draw_logo(canvas, WIDTH - LOGO_SIZE - 8, HEIGHT - LOGO_SIZE - 8)

    write_png(OUTPUT, WIDTH, HEIGHT, canvas.pixels)

    print(f"  {WIDTH}x{HEIGHT}, the game's own resolution")
    print(f"  banner, {len(BANNER_LETTERS)} letters; platforms, ladders, eggs, corn, Harry, a hen")
    print(f"  author's logo {LOGO_SIZE}x{LOGO_SIZE}, bottom right")
    print(f"\nwritten to {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
