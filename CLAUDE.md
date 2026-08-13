# Chuckie Egg — Godot 4.6 Remake

A faithful recreation of the 1983 BBC 32K Chuckie Egg game.

**Authoritative reference implementation:** https://github.com/pbrook/Chuckie-Egg (C/SDL)
— **GPL-3.0**, by Paul Brook. We vendor level data derived from it and port its game logic,
so this project is a derivative work and is licensed GPL-3.0. Keep all contributions
GPL-compatible; do not add dependencies under incompatible licences.
**Level layout reference:** https://chuckieegg.org/chuckie-egg/levels.html
**BBC 32K version is the target** — written by Doug Anderson, A&F Software, 1983. (The
original ZX Spectrum 48K version was by Nigel Alderton; behaviour differs, so cite the BBC
release when checking sources.) The Electron was a simplified port; ignore its differences.

---

## Godot Code Standards

The project MUST:
- Use properly typed GDScript throughout
- Be idiomatic Godot 4 (nodes, signals, resources, scene tree)
- Be structured cleanly and elegantly
- Call down and signal up
- Use nodes appropriately

The project MUST NOT use physics-engine-driven movement. All character and object movement is mathematical position manipulation.

The project MAY use custom node classes or resources where appropriate. Plugins require prior approval.

---

## Display & Resolution

The BBC ran Chuckie Egg in MODE 2, whose pixels are **2:1 (twice as wide as tall)**.
The reference implementation renders into `uint8_t pixels[160 * 256]` — 160 wide-pixels
across, 256 scanlines down. The Aseprite art in `assets/Sprites/` is already horizontally
doubled to square pixels (every pixel run is an even pair), so it is authored in the
doubled space.

- **Native viewport:** **320 × 256 square px** (= 160 × 256 BBC wide-pixels)
- **Tile size:** **16 × 8 square px** (8 × 8 wide-pixels). Grid is 20 × 25 tiles.
- **HUD:** viewport rows **0–55**. **Play area:** rows **56–255** (25 × 8 = 200 rows).
- **Display scale:** 3× integer → **960 × 768 px** window
- **Rendering:** Pixel-perfect, nearest-neighbour. No antialiasing, no CRT filter.
  `stretch/mode = canvas_items`, `stretch/scale_mode = integer`, texture filter = Nearest.
- **Export targets:** macOS native + HTML5/web

Motion is isotropic in *square-pixel* space: the original moves 1 unit horizontally per
frame but does `move_y <<= 1` for 2 units vertically, exactly compensating for the 2:1
pixel. Port that as-is; do not "fix" it.

**Known deliberate deviation — aspect ratio.** A real BBC displayed this on a 4:3 CRT; the
reference approximates that in `sdl.c` with an `aspect_hack` that duplicates selected
scanlines. We instead use clean 3× integer scaling (960 × 768 = 5:4), the modern pixel-art
convention, which keeps pixels square and seam-free. This is a chosen trade-off, not an
oversight — revisit only if the taller CRT proportions are wanted.

### Coordinate System

The BBC source uses **y-up** (y=0 at bottom, increases upward). Godot uses **y-down**.

Tile conversion, in **play-area-local** space (i.e. inside a node offset to y = 56):
```
godot_tile_row  = 24 - bbc_tile_y
local_pixel_x   = bbc_tile_x * 16
local_pixel_y   = godot_tile_row * 8
```

In absolute viewport coordinates that is `row_top = 248 - 8 * bbc_tile_y`, which is exactly
what the reference's `DrawTile` produces via `Do_RenderSprite(x << 3, (y << 3) | 7, ...)`
combined with its `y ^= 0xff` flip. So `bbc_tile_y = 24` lands at viewport row 56 (the top
of the play area) and `bbc_tile_y = 0` at row 248 (the bottom).

`Playfield` owns this offset — keep tile maths local and let the node position supply the 56.

### Sprite draw offsets

Trimmed sprites do not sit at their tile's origin. These offsets are derived from the ROM
bitmaps in the reference's `spritedata.c` and verified against the decoded PNGs.

⚠️ **Always derive an offset by matching the generated PNG, never the Aseprite cel.**
`aseprite_to_png.py` writes the whole canvas, so a sprite drawn small on a large canvas has
the content inset — the hens are 14 × 20 of art on a 28 × 28 canvas. Measuring the cel gives
an offset that is wrong by the cel's position inside the canvas (for hens, 7 px right and
8 rows down, which renders them beside the ladder with their legs under the floor). Canvas
offsets are legitimately negative; that is expected, not a sign of an error.

The decoder must keep emitting the canvas rather than the cel: `Ladder.aseprite` has a 12 × 16
cel at (2, −8) on a 16 × 8 canvas and depends on being clipped to it.

| Sprite | PNG size | Offset in tile (square px) |
|---|---|---|
| Platform | 16 × 5 | (0, 0) |
| Ladder | 16 × 8 | (0, 0) |
| Egg | 12 × 6 | (2, 1) |
| Corn | 14 × 4 | (2, 3) |
| Lift | 20 × 4 | (6, 0) |

The cage is drawn at absolute viewport position **(0, 35)** — it hangs below the HUD text
(rows 7 and 23–31) and straddles into the play area.

### Sprite pipeline

Godot cannot import `.aseprite`, and Aseprite is not installed. `tools/aseprite_to_png.py`
decodes the sources directly (no dependencies, no addon) into `assets/generated/*.png`,
which are committed. Re-run it after editing art.

Output goes to `assets/generated/`, **not** `assets/sprites/` — macOS is case-insensitive,
so the latter silently collapses into the `assets/Sprites/` source directory and then breaks
on Linux and in the HTML5 export.

---

## Players & Input

- **1 to 4 players**, taking alternate turns

  **Correction:** this previously said "2-player alternating turns". The reference supports
  four: `select_player_count` accepts keys 1–4, `all_player_data[4]` holds four states, and
  the hand-over is `(player + 1) & 3`, skipping anyone past the count or already out.
- Default controls (remappable via in-game settings menu):
  - Move: Arrow keys
  - Jump: Space
- The settings menu should allow key remapping. It does not need to resemble the original BBC key selection screen — a clean modern menu is fine.

---

## Game Constants

| Constant | Value |
|---|---|
| Starting lives | 5 |
| Eggs per level | 12 |
| Starting bonus | `min(current_level + 1, 9) × 100` |
| Extra life threshold | Every 10,000 pts (awarded immediately) |

### Scoring

| Action | Points |
|---|---|
| Collect egg | `(floor(level / 4) + 1) × 100`, max 1000 |
| Collect grain | 50 |
| Remaining bonus tick | 10 (at level completion) |

Level is 0-indexed internally (level 1 displayed = index 0). So on level 1: egg = 100 pts. On level 5: egg = 200 pts. On level 37+: egg = 1000 pts.

Score is stored as 8 BCD digits, and the extra-life rule is defined on that representation:
a life is earned when a carry propagates into the 10,000s digit (`AddScore`'s `if (n == 3)`).

**Correction:** an earlier version of this file said extra lives were "only awarded at the end
of a level". That is wrong — the reference calls `MaybeAddExtraLife()` from the main loop
every frame, so a life arrives essentially as soon as it is earned. It is also called inside
the end-of-level bonus loop, so lives earned from bonus conversion land too.

### Timer

`timer_speed = 9 - floor(current_level / 16)`, minimum 1.

This controls how fast the countdown decreases. At level 0–15 the timer is slowest; it steps up every 16 levels. From level 128+ the timer is at maximum speed (1 tick = fastest decrement).

---

## Level Structure & Progression

8 distinct layouts cycle with increasing difficulty. Levels are 0-indexed internally.

Difficulty is **not** organised in rounds. Each setting has its own independent threshold, and
they do not line up with each other or with the 8-level layout cycle. Straight from
`SetupLevel`, `LoadLevel` and `StartLevel`, using the 0-indexed level:

| Setting | Rule | Source |
|---|---|---|
| Layout | `current_level & 7` — cycles every 8 levels, from level 1 onwards | `LoadLevel` |
| Hen count | `0` when `(level >> 3) == 1` (indices 8–15); `5` from index 24; otherwise the level data's count | `StartLevel` |
| Hen speed | `duck_speed = (level < 32) ? 8 : 5` — **one step, at index 32** | `SetupLevel` |
| Mother duck | present when `level > 7` — **from index 8 onwards, permanently** | `SetupLevel` |
| Timer start | `9 - min(level >> 4, 8)` in the hundreds digit — steps every 16 levels, floor at index 128 | `LoadLevel` |

A larger `duck_speed` means *slower* hens: it is the size of the round-robin the clock cycles
through, and slots beyond the hen count do nothing.

**Corrections — the earlier round table here was wrong in three ways:**

- It claimed the duck's cage was closed again for indices 16–23. It is not: `have_big_duck` is
  a plain `level > 7`, so once the duck appears it never leaves.
- It claimed hens get "faster" at index 16 and "fastest" at 24. Hen *speed* changes only at
  index 32; what changes at 24 is the hen *count*.
- It claimed layouts start repeating after level 40. They repeat every 8 levels from the
  start; nothing happens at level 40. (The "about 40 levels" in interviews is 5 rounds of 8
  before every difficulty threshold has been passed, not a mechanic.)

---

## Level Data Format

**Source:** `leveldata.c` in the pbrook/Chuckie-Egg repo contains all 8 layouts as raw byte arrays.

Binary format (parsed sequentially):

```
byte 0:   num_walls
byte 1:   num_ladders
byte 2:   have_lift  (0 or 1)
byte 3:   num_grain
byte 4:   num_ducks  (base count; overridden per-round by difficulty rules above)

num_walls × 3 bytes:
  (y, x_start, x_end)  — horizontal platform, inclusive range

num_ladders × 3 bytes:
  (x, y_start, y_end)  — vertical ladder, inclusive range

if have_lift: 1 byte  — lift_x (tile column)

12 × 2 bytes:  (x, y)  — egg positions
num_grain × 2 bytes:  (x, y)  — grain positions
5 × 2 bytes:  (tile_x, tile_y)  — hen starting positions
              (always 5 stored even if num_ducks < 5)
```

All coordinates are in BBC tile space (y-up, y=1 is floor). Convert to Godot on load.

**Parse strictly by the header counts, not by array length.** `level8`'s array in
`leveldata.c` over-reads its real data by 8 trailing bytes
(`0x55 0x42 0x28 0x34 0x29 0x3a 0x20 0x45` = ASCII `"UB(4): E"`, ROM text past the table).
Every other layout consumes exactly. Do not assert the array is fully consumed.

The data is converted once by `tools/leveldata_to_tres.py` into `levels/level_1..8.tres`
(`LevelData` resources), so the game has no build-time dependency on the C source. That
script also asserts these counts, which are the regression check for the parser:

| Level | Walls | Ladders | Lift x | Grain | Hens |
|---|---|---|---|---|---|
| 1 | 13 | 4 | – | 10 | 2 |
| 2 | 13 | 8 | – | 7 | 3 |
| 3 | 24 | 7 | 5 | 10 | 3 |
| 4 | 26 | 5 | 11 | 6 | 4 |
| 5 | 17 | 9 | 16 | 13 | 4 |
| 6 | 16 | 6 | 9 | 9 | 4 |
| 7 | 23 | 7 | 18 | 4 | 3 |
| 8 | 15 | 6 | – | 16 | 3 |

### Tile Flags (combinable with bitwise OR)

| Flag | Value |
|---|---|
| TILE_WALL   | 1 |
| TILE_LADDER | 2 |
| TILE_EGG    | 4 |
| TILE_GRAIN  | 8 |

A tile can be both wall and ladder (e.g. a platform with a ladder through it = 3).
Egg and grain tiles additionally store their index in bits 7–4: `(index << 4) | tile_type`.

**Build order matters** (from the reference's `LoadLevel`):

1. Walls are written plainly.
2. Ladders are **OR-ed** into whatever is already there → a ladder through a platform gives `3`.
3. Eggs and grain **overwrite** the tile. An egg sitting on a platform tile *replaces* the
   platform; it is not OR-ed. This is deliberate, not a bug in the original.

**Draw priority** (from `DrawTile`) is `LADDER > WALL > EGG > GRAIN`. A wall+ladder tile
renders as ladder **only** — no platform is drawn beneath it.

---

## Lifts

- Present only on **levels 3–7** (and their repeating equivalents) — `have_lift` flag in data
- Two lifts share one x-column, alternating: one rises while the other wraps
- Initial pixel positions: lift[0].y = 8, lift[1].y = 90
- Harry can ride a lift. Reaching the top of the screen while on a lift is lethal.

---

## Characters

### Hen House Harry (player)

States: `WALK`, `CLIMB`, `JUMP`, `FALL`, `LIFT`

Key movement rules:
- Horizontal walk: constant pixel speed
- Jump: upward impulse, gravity pulls down
- Climb: on ladders only; horizontal movement disabled
- Auto-grab ladder: hold Up or Down while walking toward a ladder
- Jump-onto-ladder: jump + hold Up or Down while passing a ladder mid-air
- Drop off ladder: jump while climbing (releases ladder, falls)
- Falls are lethal only if onto a hen or duck (not from height)

Starting position, from the reference's `StartLevel`: `player_x = 0x3c (60)`,
`player_y = 0x20 (32)`, `player_tilex = 7`, `player_tiley = 2`, `player_partial_x = 7`,
`player_partial_y = 0`. Note `player_x` is in **wide-pixels** (multiply by 2 for the square-px
canvas) and `player_y` is y-up. The original tracks tile, partial and pixel position
redundantly — port all three rather than deriving one from another.

### Hens (small ducks in source)

Up to 5 per level (see round table above). States: `BORED`, `STEP`, `EAT1`–`EAT4`.

Behaviour:
- Walk left/right along platforms at constant speed
- Turn at platform edges and screen edges
- Can climb ladders (chase Harry vertically)
- Peck at grain when adjacent (eat animation)
- Contact with Harry = life lost

### Mother Duck (big duck in source)

- Housed in cage at top-left of play area
- Released from level 9 (round 2) onwards
- Flies directly toward Harry's current position each frame
- Speed varies with level progression
- Contact with Harry = life lost

---

## Sprites

All source files are Aseprite in `assets/Sprites/`. The game loads the decoded PNGs in
`assets/generated/` — see *Sprite pipeline* above. Never reference `.aseprite` from a scene.

### Palette — authentic, do not tweak

`Palette.aseprite` is the source of truth and holds the real BBC MODE 2 hardware colours
(fully saturated RGB, no in-between values). Verified identical to the `#define`s in the
reference's `sdl.c`:

| Index | RGB | Reference | Used for |
|---|---|---|---|
| 0 | — | — | transparent |
| 1 | `0,0,0` | — | black |
| 2 | `255,255,0` | `YELLOW` | Harry, eggs, cage, lift, mother duck |
| 3 | `0,255,255` | `BLUE` (cyan) | hens |
| 4 | `255,0,255` | `PURPLE` | ladders, corn, HUD text |
| 5 | `0,255,0` | `GREEN` | platforms |

Colour is baked into the generated PNGs, so no modulation is needed at draw time — and
nothing should be re-tinted, softened, or "improved". Keep colours as close to the original
as possible.

**`Player.tset` and `Duck.tset` are not colour-authoritative.** They store the same artwork
but with a softened yellow (`255,253,84`). Treat them as reference/scratch material only;
the `.aseprite` files and their palette win.

**Hen sprite caveat:** the hen canvases are 28 × 28 with the cel at an *odd* x offset (7),
which breaks wide-pixel alignment — unlike every other sprite, they are not cleanly framed
to the tile grid. The reference's `SPRITE_DUCK_R` is 8 × 20 wide-pixels. Re-derive the hen
offsets against `spritedata.c` when implementing hens rather than trusting the canvas.

| Character | Files |
|---|---|
| Harry | `Stand.aseprite`, `Walk.aseprite`, `Walk2.aseprite`, `ClimbUp.aseprite`, `ClimbUpLeft.aseprite`, `ClimbUpRight.aseprite` |
| Hen | `HenStand.aseprite`, `HenWalk.aseprite`, `HenPeck1.aseprite`, `HenPeck2.aseprite`, `HenClimb1.aseprite`, `HenClimb2.aseprite` |
| Mother Duck | `DuckOpenBeak.aseprite`, `DuckClosedBeak.aseprite` |
| Objects | `Egg.aseprite`, `Corn.aseprite`, `Cage.aseprite`, `Ladder.aseprite`, `Platform.aseprite`, `Lift.aseprite`, `Life.aseprite` |

⚠️ **`Cage.aseprite` is the *open* cage** — it matches `SPRITE_CAGE_OPEN` exactly and is 152 px
from `SPRITE_CAGE_CLOSED`. There is no closed-cage artwork, so `CageClosed.png` comes from the
ROM via `tools/rom_hud_to_png.py`. The closed cage is what levels 1–8 show; the open one
appears once the mother duck is loose.

There are also `Palette.aseprite`, `Duck.tset`, `Player.tset` — treat these as reference/source material.

---

## Message Font

The game has **no font of its own** — the HUD's words are pre-rendered sprites, and every
message goes through the **BBC's OS font**, an 8 × 8 character cell living in the OS ROM.

`tools/yaff_to_png.py` builds it from robhagemans/hoard-of-bitfonts, which ships the font
extracted from `os01.rom` in the plain-text YAFF format. It covers ASCII 0x20–0x7e, so the
messages keep the original's own mixed case: "Get Ready", "Press S to start", "Player 1".

**Text lays out at fixed pitch**, one character every 8 wide-pixels, because that is what a
character cell means. Spacing proportionally makes the high score columns drift out of line.

An earlier attempt derived an alphabet from the HUD label sprites instead, on the belief that
the OS font was unavailable. That worked but was condensed and capitals-only; it has been
replaced and `tools/build_font.py` removed.

---

## Sound Effects

**There are no audio assets.** Everything is synthesised at runtime by `BbcSound`, which
reproduces the BBC's sound chip: OSWORD 7 (channel, amplitude, pitch, duration) with
amplitudes 1–4 selecting an OSWORD 8 `ENVELOPE`. Channel 0 is noise; 1–3 are square-wave
tones. Pitch is 48 units to the octave with 64 as middle C.

**Correction:** this section previously listed six `.wav` files in `assets/`. Those were
recorded samples of unknown provenance and measurably wrong — `walk.wav`'s fundamental was
525 Hz against the BBC's 262 Hz (an octave out), and `climb.wav`'s 1076 Hz against 415 Hz.
They have been deleted; recover from commit `c0f41dd` if ever needed.

| Sound | Reference source | Channel | Envelope | Pitch |
|---|---|---|---|---|
| Walking | `MakeSound` case 0 | tone | 1 | 64 |
| Climbing | `MakeSound` case 1 | tone | 1 | 96 |
| Jumping | `MakeSound` case 2 | tone | 1 | `0x96 + fall*2` rising, `0xbe - fall*2` after `fall >= 0x0b` |
| Falling | `MakeSound` case 3 | tone | 1 | `0x6e - fall*2` |
| On a lift | `MakeSound` case 4 | tone | 1 | `0x64`, and only while moving sideways |
| Egg | `squidge(6)` | noise | 3 | 6 |
| Grain | `squidge(5)` | noise | 3 | 5 |
| Death tune | `PlayTune(0x2fa6)` | tone | 2 | 16 notes from `.dead_tune` |
| Bonus tick | `sound(0xcb0)` | noise | 1 | 4 |

The movement beep fires every *other* tick and only while Harry is moving. Jump and fall
sweep with `player_fall`, so a long drop sounds different from a short one — which is why
nothing can be a fixed sample.

Envelopes and the death tune's notes come from the annotated BBC disassembly at
https://github.com/mungre/chuckie; the per-state pitches are in the reference's `MakeSound`.
`PlayTune` and the bonus tick are empty stubs in the reference, so those two are reconstructed
from that data rather than ported.

No music — the reference's only tune call is the death jingle above.

---

## HUD

Occupies viewport rows 0–55. Positions come from `DrawHUD`, `DrawLives`, `DrawBonus` and
`DrawTimer` in `raster_4bit.c`.

- One score block per player, at `0x1b + 0x22 * player` — so player 2's sits beside player 1's
- Lives, as small hat markers above each player's score
- Current player number, level number, bonus, time countdown

**Correction:** this section previously listed "High score (running best)" in the HUD. There is
no high-score slot in the reference's HUD — the second score block is *player 2's*. High scores
appear after game over instead, where the reference leaves `/* Highscores. */` unimplemented,
so that screen has to be designed rather than ported.

**The renderer XORs** (`*dest ^= color`), and the HUD depends on it: the labels are
inverse-video bars with the lettering knocked out, and digits drawn over them XOR back to
black. Drawn as ordinary sprites the numbers disappear into the bars. `Hud` reproduces the XOR
compositing rather than working around it.

The displayed bonus is **ten times** the internal counter — three digits plus a literal
trailing zero — which makes the number on screen equal the points it is worth.

---

## MVP Scope (Levels 1–3)

First milestone covers:
- Full player movement (walk, jump, climb, fall)
- Hens active (round 1 only — no duck needed yet)
- Egg and grain collection with scoring
- Lives system and life-lost handling
- HUD (score, level, bonus, time, lives)
- Sound effects
- Title screen and game-over screen
- 1–4 players alternating

Lifts and Mother Duck are post-MVP.
