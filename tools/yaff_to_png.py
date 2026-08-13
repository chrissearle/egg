#!/usr/bin/env python3
"""Build the message font from the BBC Micro's OS font.

The game has no font of its own: its messages go through the machine's OS font,
which lives in the OS ROM rather than in the game. This reads that font from
robhagemans/hoard-of-bitfonts, a preservation project that ships it as YAFF —
a plain-text bitmap format — extracted from `os01.rom`.

    python3 tools/yaff_to_png.py [path/to/bbc_micro.yaff]

Writes assets/generated/font/u<hex>.png, white on transparent so callers tint.

The font is an 8 x 8 character cell covering ASCII 0x20-0x7f, so it has
lowercase and punctuation that the game's own lettering never contained. Every
character advances a whole cell, which is why the messages lay out at fixed
pitch.

On licensing, that repository's LICENSE.md states that bitmap typefaces are not
copyrightable in the USA, that the UK's 25-year typeface term has expired for
these, and dedicates the author's own contribution under CC0. It also advises
checking your own jurisdiction.
"""

from __future__ import annotations

import re
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from aseprite_to_png import write_png  # noqa: E402

YAFF_URL = (
    "https://raw.githubusercontent.com/robhagemans/hoard-of-bitfonts"
    "/master/acorn/bbc/bbc_micro.yaff"
)

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "assets" / "generated" / "font"

## The printable range the messages draw from.
FIRST_CODEPOINT = 0x20
LAST_CODEPOINT = 0x7E

CELL_WIDTH = 8
CELL_HEIGHT = 8

WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def fetch(path: str | None) -> str:
    if path:
        return Path(path).read_text()
    with urllib.request.urlopen(YAFF_URL) as response:
        return response.read().decode("utf-8")


def parse(source: str) -> dict[int, list[str]]:
    """Read YAFF into {codepoint: rows of '.' and '@'}.

    A glyph is one or more labels followed by indented bitmap lines. Only the
    `u+XXXX` labels matter here; the format also repeats the source codepoint.
    """
    glyphs: dict[int, list[str]] = {}
    pending: list[int] = []
    rows: list[str] = []

    def flush() -> None:
        if pending and rows:
            for code in pending:
                glyphs[code] = list(rows)

    for line in source.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[0].isspace():
            stripped = line.strip()
            if set(stripped) <= {".", "@"}:
                rows.append(stripped)
            continue
        # A label at column zero starts a new glyph.
        if rows:
            flush()
            pending, rows = [], []
        match = re.match(r"u\+([0-9A-Fa-f]+):", line.strip())
        if match:
            pending.append(int(match.group(1), 16))
    flush()
    return glyphs


def emit(code: int, rows: list[str]) -> tuple[int, int]:
    """Write one glyph, doubled horizontally into MODE 2's square pixels."""
    pixels: list[tuple[int, int, int, int]] = []
    for row in rows:
        cells = row.ljust(CELL_WIDTH, ".")[:CELL_WIDTH]
        for cell in cells:
            colour = WHITE if cell == "@" else CLEAR
            pixels.append(colour)
            pixels.append(colour)
    height = len(rows)
    write_png(OUTPUT_DIR / ("u%04x.png" % code), CELL_WIDTH * 2, height, pixels)
    return CELL_WIDTH * 2, height


def main() -> int:
    glyphs = parse(fetch(sys.argv[1] if len(sys.argv) > 1 else None))

    missing = [c for c in range(FIRST_CODEPOINT, LAST_CODEPOINT + 1) if c not in glyphs]
    if missing:
        print("missing codepoints: " + " ".join("%#04x" % c for c in missing), file=sys.stderr)
        return 1

    # Replace whatever was there: the derived alphabet this supersedes used
    # different filenames, and leaving it behind would just confuse.
    if OUTPUT_DIR.exists():
        for stale in OUTPUT_DIR.glob("*.png*"):
            stale.unlink()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    written = 0
    for code in range(FIRST_CODEPOINT, LAST_CODEPOINT + 1):
        emit(code, glyphs[code])
        written += 1

    print(f"  {written} glyphs, {CELL_WIDTH * 2}x{CELL_HEIGHT} each")
    print(f"  covering {chr(FIRST_CODEPOINT)!r} to {chr(LAST_CODEPOINT)!r}, with lowercase")
    print(f"\nwritten to {OUTPUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
