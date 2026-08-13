#!/usr/bin/env python3
"""Convert the reference implementation's leveldata.c into LevelData resources.

The eight BBC layouts live as raw byte arrays in pbrook/Chuckie-Egg's
leveldata.c. This parses them once and emits levels/level_1.tres ...
level_8.tres so the game has no build-time dependency on the C source.

    python3 tools/leveldata_to_tres.py [path/to/leveldata.c]

With no argument the file is downloaded from GitHub.

Binary layout, parsed strictly sequentially:

    byte 0  num_walls        byte 3  num_grain
    byte 1  num_ladders      byte 4  num_hens
    byte 2  have_lift

    num_walls   x 3 bytes  (y, x_start, x_end)
    num_ladders x 3 bytes  (x, y_start, y_end)
    1 byte lift_x           if have_lift
    12          x 2 bytes  (x, y)  eggs
    num_grain   x 2 bytes  (x, y)  grain
    5           x 2 bytes  (x, y)  hen spawns

All coordinates are BBC tile space (y-up, y = 0 at the bottom).
"""

from __future__ import annotations

import re
import sys
import urllib.request
from pathlib import Path

LEVELDATA_URL = (
    "https://raw.githubusercontent.com/pbrook/Chuckie-Egg/master/leveldata.c"
)

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "levels"
SCRIPT_PATH = "res://scripts/resources/level_data.gd"

EGG_COUNT = 12
HEN_SLOT_COUNT = 5

# Counts verified against the reference during planning; a mismatch means the
# upstream data or our parser drifted, and the generated levels are suspect.
EXPECTED = {
    1: (13, 4, None, 10, 2),
    2: (13, 8, None, 7, 3),
    3: (24, 7, 5, 10, 3),
    4: (26, 5, 11, 6, 4),
    5: (17, 9, 16, 13, 4),
    6: (16, 6, 9, 9, 4),
    7: (23, 7, 18, 4, 3),
    8: (15, 6, None, 16, 3),
}


class Cursor:
    """Sequential reader over the level byte array."""

    def __init__(self, data: list[int]) -> None:
        self._data = data
        self._pos = 0

    def byte(self) -> int:
        value = self._data[self._pos]
        self._pos += 1
        return value

    def triple(self) -> tuple[int, int, int]:
        return self.byte(), self.byte(), self.byte()

    def pair(self) -> tuple[int, int]:
        return self.byte(), self.byte()

    @property
    def consumed(self) -> int:
        return self._pos


def extract_arrays(source: str) -> dict[int, list[int]]:
    """Pull the eight `static const uint8_t levelN[]` byte arrays out of the C."""
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    arrays: dict[int, list[int]] = {}
    pattern = r"static const uint8_t level(\d+)\[\]\s*=\s*\{(.*?)\};"
    for match in re.finditer(pattern, source, re.S):
        number = int(match.group(1))
        arrays[number] = [int(b, 16) for b in re.findall(r"0x([0-9a-fA-F]+)", match.group(2))]
    return arrays


def parse_level(data: list[int]) -> dict:
    """Parse one layout. Trailing bytes beyond the declared counts are ignored.

    level8's array over-reads its real data by 8 bytes of ROM text
    (0x55 0x42 0x28 ... = "UB(4): E"), so the array length is not a reliable
    end marker — only the header counts are.
    """
    cursor = Cursor(data)
    num_walls = cursor.byte()
    num_ladders = cursor.byte()
    have_lift = cursor.byte()
    num_grain = cursor.byte()
    num_hens = cursor.byte()

    walls = [cursor.triple() for _ in range(num_walls)]
    ladders = [cursor.triple() for _ in range(num_ladders)]
    lift_x = cursor.byte() if have_lift else 0
    eggs = [cursor.pair() for _ in range(EGG_COUNT)]
    grain = [cursor.pair() for _ in range(num_grain)]
    hens = [cursor.pair() for _ in range(HEN_SLOT_COUNT)]

    return {
        "walls": walls,
        "ladders": ladders,
        "have_lift": bool(have_lift),
        "lift_x": lift_x,
        "eggs": eggs,
        "grain": grain,
        "hen_starts": hens,
        "base_hen_count": num_hens,
        "consumed": cursor.consumed,
        "length": len(data),
    }


def _vec3_array(triples: list[tuple[int, int, int]]) -> str:
    items = ", ".join(f"Vector3i({a}, {b}, {c})" for a, b, c in triples)
    return f"Array[Vector3i]([{items}])"


def _vec2_array(pairs: list[tuple[int, int]]) -> str:
    items = ", ".join(f"Vector2i({a}, {b})" for a, b in pairs)
    return f"Array[Vector2i]([{items}])"


def write_tres(path: Path, level: dict) -> None:
    body = f"""[gd_resource type="Resource" script_class="LevelData" load_steps=2 format=3]

[ext_resource type="Script" path="{SCRIPT_PATH}" id="1_level_data"]

[resource]
script = ExtResource("1_level_data")
walls = {_vec3_array(level["walls"])}
ladders = {_vec3_array(level["ladders"])}
have_lift = {"true" if level["have_lift"] else "false"}
lift_x = {level["lift_x"]}
eggs = {_vec2_array(level["eggs"])}
grain = {_vec2_array(level["grain"])}
hen_starts = {_vec2_array(level["hen_starts"])}
base_hen_count = {level["base_hen_count"]}
"""
    path.write_text(body)


def main() -> int:
    if len(sys.argv) > 1:
        source = Path(sys.argv[1]).read_text()
    else:
        print(f"downloading {LEVELDATA_URL}")
        with urllib.request.urlopen(LEVELDATA_URL) as response:
            source = response.read().decode("utf-8")

    arrays = extract_arrays(source)
    if len(arrays) != 8:
        print(f"expected 8 level arrays, found {len(arrays)}", file=sys.stderr)
        return 1

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    failures = 0

    for number in sorted(arrays):
        level = parse_level(arrays[number])
        actual = (
            len(level["walls"]),
            len(level["ladders"]),
            level["lift_x"] if level["have_lift"] else None,
            len(level["grain"]),
            level["base_hen_count"],
        )
        status = "ok"
        if actual != EXPECTED[number]:
            status = f"MISMATCH expected {EXPECTED[number]}"
            failures += 1

        slack = level["length"] - level["consumed"]
        slack_note = f", {slack} trailing bytes ignored" if slack else ""
        write_tres(OUTPUT_DIR / f"level_{number}.tres", level)
        print(
            f"  level_{number}.tres  walls={actual[0]:>2} ladders={actual[1]} "
            f"lift={actual[2]} grain={actual[3]:>2} hens={actual[4]}  "
            f"[{status}{slack_note}]"
        )

    print(f"\n{8 - failures}/8 levels written to {OUTPUT_DIR}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
