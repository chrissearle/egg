# Roadmap

Progress tracker for the Chuckie Egg remake. Scope comes from `CLAUDE.md`; this file
tracks *state*, not specification — when the two disagree, `CLAUDE.md` is correct and this
file needs updating.

Kept current as work lands. Each milestone is a coherent, verifiable chunk.

**Status:** M1–M13 complete. M14 is the web export, which is done and
[live](https://egg.chrissearle.net); only the macOS native export remains.

The goal is the **complete game**, not the MVP; the MVP was only a staging post. Levels 1–3
are not completable until lifts land, so lifts come before everything else — see the note
under M7.

| | Milestone | Status |
|---|---|---|
| M1 | Foundation & static rendering | ✅ done |
| M2a | Movement: walk & fall | ✅ done |
| M2b | Movement: jump & ladders | ✅ done |
| M3 | Collectables & scoring | ✅ done |
| M4a | Hens roam | ✅ done |
| M4b | Hens interact | ✅ done |
| M5 | Lives & level flow | ✅ done |
| M6 | HUD | ✅ done |
| M7 | Lifts | ✅ done |
| | **— levels 1–3 completable —** | |
| M8 | Sound | ✅ done |
| M9a | In-game sequences | ✅ done |
| M9b | Title, game over & multi-player | ✅ done |
| M10 | Mother duck | ✅ done |
| M11 | Full progression & difficulty | ✅ done |
| M12 | High scores | ✅ done |
| M13 | Settings & key remapping | ✅ done |
| M14 | Export targets | 🔶 web done & live; macOS native remains |

---

## M1 — Foundation & static rendering ✅

Commit `47b5e79`.

- [x] Correct `CLAUDE.md` — native canvas is 320 × 256 with 16 × 8 tiles, not 160 × 200 / 8 × 8
- [x] `project.godot` — viewport, integer scaling, nearest filter, input actions
- [x] `tools/aseprite_to_png.py` — dependency-free decoder → `assets/generated/*.png`
- [x] `tools/leveldata_to_tres.py` + `levels/level_1..8.tres`
- [x] `scripts/resources/level_data.gd`, `scripts/level_map.gd`
- [x] `scenes/playfield.tscn` — tile rendering with reference-accurate draw priority
- [x] Verified: all 8 layouts render, level 1 matches the original, `gdlint` clean

---

## M2a — Movement: walk & fall ✅

Port `MovePlayer` from the reference `chuckie.c` verbatim. Integer logic on a fixed tick —
**not** float/delta movement (decided; jump arcs and ladder grab windows depend on the exact
integer arithmetic).

- [x] Fixed-timestep driver with accumulator
- [x] Player state: `x`, `y`, `partial_x`, `partial_y`, `tile_x`, `tile_y` — all tracked
      redundantly as the original does, not derived from one another
- [x] `MoveSideways` blocking (note: tests `== 1`, so a wall+ladder tile does **not** block)
- [x] `AnimatePlayer` position update
- [x] `WALK`: horizontal movement, walk-off-edge → `FALL`
- [x] `FALL`: slide for the first 3 ticks, then accelerate; landing detection (tests `& 1`)
- [x] Sprite: right-facing frames + `flip_h`; frame `= (x >> 1) & 3`, table `[R, R2, R, R3]`
- [x] Screen-edge clamping (`x == 0`, `x >= 0x98`)

Verified facts:
- `Stand` = `SPRITE_PLAYER_R`, `Walk` = `R2`, `Walk2` = `R3` (bitmap-exact)
- Left-facing sprites are exact horizontal mirrors of right — `flip_h` is correct and produces
  bit-exact `SPRITE_PLAYER_L` output, so no left-facing art is needed
- Reference paces its loop at **30 ms** (`next_time += 30` in `sdl-input.c`), i.e. ~33 Hz,
  not the 50 Hz originally assumed
- Position representations are related by `y = tile_y * 8 + partial_y + 16` and
  `partial_x = (x + 3) & 7`, `tile_x = (x + 3) >> 3` — confirmed at two independent positions

Tested: idle is stable (no drift or sink over 30 ticks); walking tracks tiles correctly; both
screen edges clamp (`x` stops at 0 and 152); walking off a ledge slides 3 wide-pixels outward
then accelerates down, landing snapped exactly to `partial_y = 0`; resting after landing is
stable over 60 ticks.

**Resolved — Harry renders 1 pixel above platforms, and that is kept.** His feet land on row
`254 - 8 * tile_y` while the platform's top is `256 - 8 * tile_y`. This falls straight out of
the reference's own arithmetic (`Do_RenderSprite`'s `y ^ 0xff` combined with `DrawTile`'s
`(y << 3) | 7`), so it is faithful rather than a porting slip. Do not "correct" it.

---

## M2b — Movement: jump & ladders ✅

- [x] `StartPlayerJump` / `PlayerJump`
- [x] `CLIMB` state; `player_face = 0` while climbing
- [x] `PlayerGrabLadder` — auto-grab requires `partial_x == 3`
- [x] Ladder grab from `WALK` (hold Up/Down); jump-onto-ladder mid-air; drop off by jumping
- [x] Climb frames + selection `= (y >> 1) & 3`
- [x] Death when `y < 0x11` (fell off the bottom)

Tested: a standing jump rises 12 units and returns to exactly the start height; walking into
a ladder while holding Up grabs it at `partial_x == 3` and sets `face = 0`; climbing moves 2
units per tick; holding Up or Down against either end of a ladder stops rather than running
off it; jumping while holding Up latches onto a ladder mid-air.

⚠️ **Deliberate deviation — jump is edge-triggered.** The reference reads the jump button's
held state directly, so holding it makes Harry hop again the instant he lands. Its own
`button_ack` flag exists to prevent that (`button_ack |= 0x10` in `StartPlayerJump`) but is
never read anywhere in the C port — the SDL input layer only tracks raw held state. Requiring
a fresh press restores what `button_ack` was evidently for. Revert in `Player.tick` if exact
parity with the C port is wanted instead.

### Climb sprite state — resolved

All three climb frames were regenerated from the ROM with `tools/rom_to_aseprite.py` and are
now bit-exact. Before that they all diverged — an earlier note here wrongly called two of them
clean, because they passed the 2:1 doubling check, which is a weaker test than matching the
ROM. The originals were a left/right leaning pair of roughly the same pose, so
`SPRITE_PLAYER_UP3` had no counterpart at all.

| File | Now holds | Was |
|---|---|---|
| `ClimbUp` | `SPRITE_PLAYER_UP` | 16 px off, cel 16×15 (feet row missing) |
| `ClimbUpLeft` | `SPRITE_PLAYER_UP2` | 22 px off (closest to mirrored `UP2`) |
| `ClimbUpRight` | `SPRITE_PLAYER_UP3` | 112 px off (was a second `UP2` variant) |

⚠️ **The `Left`/`Right` file names are now historical and misleading** — they hold `UP2` and
`UP3`, which are not left/right variants. Renaming them would also mean renaming the
`.aseprite` sources; left alone for now, and mapped explicitly in `Player.CLIMB_FRAMES`.

---

## M3 — Collectables & scoring ✅

- [x] Egg pickup → clear tile, decrement `eggs_left`
- [x] Grain pickup → clear tile
- [x] Score as 8 BCD digits (needed for the extra-life rollover rule)
- [x] Egg = `(floor(level / 4) + 1) × 100`, capped at 1000; grain = 50
- [x] Level complete when `eggs_left` hits 0
- [x] Bonus countdown → 10 pts per remaining tick at level end
- [x] Starting bonus `min(level + 1, 9) × 100`, with borrow across digits
- [x] Extra life when a carry reaches the 10,000s digit, granted at level end

`PlayerState` (`scripts/player_state.gd`) mirrors the reference's `playerdata_t`, so M5's
life-lost flow and M8's 2-player alternation can each keep their own instance. `Player`
signals `egg_collected` / `grain_collected` upward; `Main` scores them.

Score and bonus are stored as digits, not integers, because the extra-life rule is defined on
the digit representation — a life is earned when a carry propagates into the 10,000s digit.

⚠️ Superseded by M5: `grant_pending_extra_lives()` was originally called only at level end.
The reference grants immediately, from the per-frame loop.

**Scope note:** the *in-play* bonus and timer countdown is not here. The reference gates it on
`duck_timer == 4`, the same counter that paces hen movement, so it belongs with M4. Only the
end-of-level bonus conversion is implemented. `award_bonus_step()` is deliberately one step
per call so M6 can animate it.

Tested: 30 assertions covering BCD carries, the egg value table from `CLAUDE.md` (levels 1, 5,
9, 37 and the 1000 cap), the 10,000-point rollover and deferred life grant, starting bonus per
level, digit borrow (100 → 99), full countdown, and pickup through the real scene — including
that a collected egg actually disappears from the rendered screen.

---

## M4a — Hens roam ✅

- [x] `LevelClock` — the 8-phase cycle from the head of `MoveDucks`
- [x] In-play timer countdown (deferred from M3), and the bonus dropping with it
- [x] `bonus_hold = 14` pausing the countdown after grain is collected
- [x] Hen entity with `BORED` / `STEP`, spawned from the level data
- [x] Direction choice at junctions: rule out reversing, then pick randomly
- [x] Walking and ladder climbing (both fall out of the same direction logic)
- [x] Sprite frames per `DuckSprite`, left-facing by mirroring
- [x] Round rules: no hens in round 2, all five from level 24

`BbcRandom` ports `FrobRandom` rather than using Godot's RNG, because the original reseeds
`0x767676` / `0x76` every level — so hen behaviour is fully reproducible, which the tests
rely on.

Hen speed is not a per-hen value: `LevelClock` hands out one step at a time from a counter
running down from `hen_interval` (8, or 5 from level 32), and slots past the hen count do
nothing. Fewer hens therefore also means slower ones.

**Correction to an earlier note here:** the hen art is fine. All six frames match the ROM
exactly once matched at the right offsets — the earlier warning about the 28 × 28 canvases
was wrong. The mapping is not what the file names suggest:

Offsets below are of the **generated PNG's** top-left relative to the ROM sprite origin. They
are negative because the art is 14 × 20 on a 28 × 28 canvas.

| File | Actually is | PNG offset |
|---|---|---|
| `HenStand` | `SPRITE_DUCK_R` | (−5, −8) |
| `HenWalk` | `SPRITE_DUCK_R2` | (−5, −8) |
| `HenClimb1` | `SPRITE_DUCK_UP2` | (−6, −6) |
| `HenClimb2` | `SPRITE_DUCK_UP` | (−6, −8) |
| `HenPeck1` | `SPRITE_DUCK_EAT_R` | (2, −8) |
| `HenPeck2` | `SPRITE_DUCK_EAT_R2` | (1, −8) |

The climb frames are swapped relative to their names, and differ vertically because
`DUCK_UP2` is 22 rows against `DUCK_UP`'s 20. `SPRITE_DUCK_L` is an exact mirror of
`SPRITE_DUCK_R`, so left-facing hens use `flip_h` — re-anchored as
`ROM_WIDTH - png_width - offset_x`, or they shift when turning around.

🐛 **Fixed after first release of M4a:** these offsets were initially derived from the
Aseprite *cel* rather than the PNG, putting every hen 7 px right and 8 rows low — beside the
ladder when climbing, and with legs below the floor when walking. See the warning in
`CLAUDE.md`; the same trap awaits the mother duck (M10) and the HUD digits (M6).

Tested: 22 assertions covering the phase cycle, hen counts per round, timer start values per
level band, digit borrow, the bonus dropping on units 0 and 5, the grain hold, and hens in
the real scene — all moving, none leaving the map, none floating unsupported, and the same
seed reproducing an identical walk.

---

## M4b — Hens interact ✅

- [x] `EAT1`–`EAT4` states; grain removed on `EAT2`, not on the first frame
- [x] Grain detection on the tile the hen faces, horizontal movement only
- [x] Eat frames, including the `x -= 8` shift for left-facing eat sprites
- [x] Collision with Harry → life lost (`CollisionDetect`)

Eating takes priority over moving: a hen part-way through its peck stays put until the cycle
finishes, then resumes walking. Hens mark grain as taken so it does not reappear on re-entry,
but score nothing and do **not** pause the countdown — `bonus_hold` is set only when Harry
collects it himself.

Hens deliberately ignore eggs. The check reads the tile before taking it, because
`LevelMap.take_collectable` would happily remove an egg and decrement `eggs_left`.

The collision box comes from the original's unsigned range tricks and is **not symmetric
vertically**: `|dx| <= 5`, and `-13 <= dy <= 15`, so a hen counts as touching Harry from
further above than below.

The eating sprites are twice as wide, the beak reaching into the next tile, so their ROM
canvas is 32 px rather than 16 — the mirror re-anchoring has to use that wider value.

Tested: 20 assertions covering the peck cycle and its single grain removal, the hen staying
put through it and moving again after, eggs being left alone, all eight edges of the collision
box, and the pecking sprite measured on screen — beak reaching past its own tile in the
direction faced and nothing spilling out behind it, with both facings the same width.

⚠️ The reference calls `abort()` when the timer reaches zero, immediately before the
`is_dead++` that should handle it — an unfinished path in the C port, not behaviour to copy.
Timing out costs a life; `Main` currently resets Harry as a placeholder, along with hen
collisions and falling off the bottom, until M5 owns the life-lost sequence.

---

## M5 — Lives & level flow ✅

- [x] 5 starting lives; life-lost sequence and respawn
- [x] Collected eggs and grain persist across a lost life
- [x] Level advance, layout cycling `current_level % 8`
- [x] Extra life every 10,000 pts
- [x] Game over when the last life goes

**Correction — extra lives are granted immediately, not at level end.** `CLAUDE.md` and the
M3 notes both said they were deferred. The reference calls `MaybeAddExtraLife()` from the
per-frame loop (line 1129), so a life arrives as soon as it is earned; it is called again
inside the end-of-level bonus loop so lives earned from bonus conversion also land. Nothing
in the research snapshots supported the deferred claim. `CLAUDE.md` is now fixed.

What survives a death, from `SavePlayerState` / `RestorePlayerState`:

| | Death | Level advance |
|---|---|---|
| Score | kept | kept |
| Bonus | **kept, still depleted** | refilled to `min(level+1, 9) × 100` |
| Timer | refilled | refilled |
| Collected eggs and grain | **stay collected** | cleared |
| Level | replayed | `current_level + 1` |

Only `ResetPlayer` refills the bonus and clears the collected flags, and the original calls it
solely on advance and at game start — so dying mid-level leaves you with whatever bonus you had
left. `load_level` does the fresh entry; `_enter_level` rebuilds without touching player state
and doubles as the respawn.

Tested: 34 assertions covering the new-game state, a death preserving score and collected eggs
while returning Harry to the start, bonus surviving a death while the timer refills, five
deaths reaching game over with `_tick` inert afterwards, level advance converting bonus at 10
points each and refilling for the next level, layout cycling at level 9, and an extra life
being granted during play rather than at level end.

---

## M6 — HUD ✅

- [x] Digit and label glyphs, generated from the ROM
- [x] Score (six digits), current-player indicator, life markers
- [x] Level number, bonus, time countdown
- [x] Repaints on every change

**The renderer is XOR, and the HUD depends on it.** `Do_RenderSprite` does `*dest ^= color`
into colour-plane bits — which is also why `ErasePlayer` and `DrawPlayer` are the same call.
The HUD labels are inverse-video (a filled bar with the lettering knocked out) and the digits
drawn over them XOR back to black, giving dark text on a magenta bar. Drawn as ordinary
sprites the numbers are magenta on magenta and simply vanish, so `Hud` composites glyph masks
into a plane buffer with XOR and presents it as one image.

The displayed bonus is **ten times** the internal counter: three digits plus a literal trailing
zero. That makes the number on screen equal the points it is worth, since each bonus tick
converts to 10 points.

### HUD glyphs have no Aseprite source — deliberately

The digits and the `SCORE` / `PLAYER` / `LEVEL` / `BONUS` / `TIME` labels exist only as ROM
bitmaps; they are the original's built-in text, not drawn artwork. `tools/rom_hud_to_png.py`
emits them straight to `assets/generated/hud/`.

Synthesising `.aseprite` sources was rejected: `rom_to_aseprite.py` only ever *modifies* files
Aseprite itself wrote, which is safe, but a file built from scratch cannot be verified here
because Aseprite is not installed — and an unopenable source file is worse than none. To
restyle them, draw real `.aseprite` files and `aseprite_to_png.py` takes over.

`SPRITE_HAT` (the life marker) turned out to be exactly the existing `Life.aseprite` at offset
(0, 0), so lives needed no new art.

Tested: 14 assertions covering every HUD row landing above the playfield, the rightmost digit
fitting inside 320 px, and the display actually changing with score, lives, bonus and timer.

---

## M7 — Lifts ✅

Brought forward from M9. **Levels 3–7 are unplayable without it:** a reachability check over
every layout (walking, ladders, and generous jumps) found level 3 strands 10 of its 12 eggs
without the lift, and levels 6 and 7 strand all 12. Levels 1 and 2, which have no lift, come
out fully reachable — the control that says the check is sound.

- [x] Two lifts sharing one column, from `have_lift` / `lift_x` in the level data
- [x] `MoveLift`: `y += 2` per tick, wrapping from `0xe0` back to `6`, alternating each tick
- [x] Initial positions `lift[0].y = 8`, `lift[1].y = 0x5a`
- [x] `PlayerHitLift` and the `LIFT` branch of `MovePlayer`
- [x] Riding to the top of the screen is lethal (`y >= 0xdc`)
- [x] Draw at the derived tile offset (6, 0)

Lifts move **every tick**, unlike the hens and timer which share `LevelClock`'s eight phases —
`MoveLift` sits in the reference's main loop, not in `MoveDucks`. Only one car moves per tick,
alternating, so each rises two units every other tick and riding one gains exactly one unit per
tick. `PlayerHitLift` is only ever called from `PlayerJump`: a lift can be caught mid-jump, and
no other way.

Tested: 26 assertions covering presence and column on all eight layouts, the alternating
two-unit rise, the exact wrap at `0xe0`, no movement on lift-free layouts, catching a car
mid-jump, riding at one unit per tick, stepping out of the shaft dropping into `FALL`, dying at
the top of the screen, and never entering `LIFT` on a layout without one.

---

## M8 — Sound ✅

Every sound is **synthesised at runtime** by `BbcSound`. There are no audio assets.

- [x] All nine sounds from the reference's parameters
- [x] Beep fires every other tick, only while Harry moves; on a lift only when moving sideways
- [x] Jump and fall sweep with `player_fall`, so a long drop sounds different from a short one
- [x] Death tune, and the game holding still for it before respawning
- [x] The six recorded `.wav` files deleted

### Why the recorded samples went

They were measurably not the BBC's sounds. Autocorrelating their fundamentals against the
pitches `MakeSound` specifies:

| Sample | Measured | Should be |
|---|---|---|
| `walk.wav` | 525 Hz | 262 Hz (pitch 64) — an octave out |
| `climb.wav` | 1076 Hz | 415 Hz (pitch 96) — 2.6× out |

The method was validated first against a stream whose pitches were known by construction,
recovering them to within 1%. So reconstruction was not only more consistent, it was more
correct. The originals remain in commit `c0f41dd` if ever wanted.

### Why synthesis, not pre-rendered files

The movement beep's pitch is computed every tick: walk 64 and climb 96 are constant, but a
jump sweeps `0x96 + fall*2` up then `0xbe - fall*2` down, and a fall descends `0x6e - fall*2`
without a floor. There is no fixed sample for those, and pitch-shifting one distorts its
duration. Synthesising also keeps a single implementation rather than a Python renderer plus a
Godot playback path.

Beep streams are cached per pitch; the pickups, bonus tick and death tune are built once.

### Where the data comes from

Envelopes 1–3 and the 16-note `.dead_tune` are from the annotated BBC disassembly at
https://github.com/mungre/chuckie. The per-state pitches are in the reference's `MakeSound`.
Two cross-checks: `.sound1` in the disassembly is byte-for-byte what pbrook's comment on
`beep()` describes, and the pitch scale agrees with `period_lookup` in `audio.c` to within
that table's integer rounding.

**Provenance note.** Level and sprite data come via pbrook's GPL-3.0 repo. The envelopes and
tune are ~75 bytes from a disassembly with no stated licence; no ROM is shipped.

⚠️ The bonus tick is built but **not yet wired** — it fires once per countdown step, and that
countdown still resolves in a single frame. It gets connected in M9.

⚠️ Verified by test only. Nobody has listened to the synthesised set, and it is a real change
in character from the recordings: per-tick beeping rather than looped samples.

Tested: 26 assertions covering the assets being gone, beep and tune durations, the pitch scale
against the BBC's, rendered waveforms measuring their intended frequency by autocorrelation,
the every-other-tick gating, egg and grain being distinct sounds, and the death tune surviving
the respawn.

---


## M9a — In-game sequences ✅

- [x] Animated end-of-level bonus countdown, with the tick sound
- [x] A font, derived from the game's own lettering
- [x] "Get Ready" / "Player N" screen before each life
- [x] Death pause (landed in M8, alongside the death tune)

### The bonus tick — two traps, both hit

pbrook fires it when `timer_ticks[3]` is 0 or 5, which is off the end of a three-element
array. The disassembly names the real condition `fifty_divides_bonus`.

The second trap is subtler. Its variables run `bonus_3`, `bonus_2`, `bonus_1` from `&3A`
upward, and `decrement_bonus` starts at the *highest* address — so **`bonus_1` is the units
digit**, not index 1. Reading it as the tens digit (as this first did) makes the ticks come in
spurts of ten separated by forty-tick gaps, instead of the even stream the original has. The
name also only makes sense on units: the displayed bonus is ten times the internal counter, so
every fifth unit is a displayed multiple of fifty.

⚠️ **Deliberate deviation:** the original's countdown loop has no `wait_for_interval_timer`,
so a full bonus converts far faster than 33 Hz can show. `BONUS_STEPS_PER_TICK` is 5 — the
closest even approximation, landing exactly one tick sound per game tick.

### The font is the BBC's own — eventually

The BBC version has **no font of its own**: its messages went through the machine's OS font,
which lives in the OS ROM, not in the game.

The first attempt derived an alphabet from the game's own HUD lettering, because extracting
the OS font seemed to need an Acorn ROM with unclear licensing. That worked, but it was
condensed and capitals-only, and looked visibly wrong beside the real thing.

It is now the genuine OS font, via `tools/yaff_to_png.py` reading
robhagemans/hoard-of-bitfonts — a preservation project that ships it extracted from `os01.rom`
in plain-text YAFF, with a `LICENSE.md` setting out its position on typeface copyright and a
CC0 dedication of the author's own work. Covering ASCII 0x20–0x7e, it brings lowercase, so
the messages read in the original's own case. `tools/build_font.py` and its derived glyphs are
gone.

**Text lays out at fixed pitch**, one character every 8 wide-pixels, because that is what a
character cell means. Spacing it proportionally — as the derived font invited — makes the high
score table's columns drift out of line.

### Get Ready

Shown before every life and every player switch, but **not between levels**: level advance
re-enters `.level_loop` while death and player-switch jump to `.one_life_loop`, where the
message and its `sleep(&14)` live. That sleep is a busy-wait of about 3.3 seconds on a 2 MHz
6502, kept as-is.

The message clears the screen — the original's `msg_get_ready` opens with `VDU_CLG` and the
level is only drawn once the pause ends — so the playfield, Harry, hens, lift and cage are all
hidden behind it.

Positions and colours are the original's. `VDU_MOVE` coordinates are in the BBC's 1280 × 1024
graphics space, mapping to the screen by dividing x by 8 and y by 4, with the cursor at the
character's *baseline*. The `palette_table` resolves the logical colours: **logical 4 is
yellow** ("Get Ready") and **logical 8 is cyan** ("Player N", "GAME OVER") — both already in
the game's palette.

---

## M9b — Title, game over & multi-player ✅

- [x] Title screen with the original's prompts
- [x] Player-count selection, 1 to 4
- [x] Per-player GAME OVER
- [x] Alternating turns, skipping players who are out

**Correction: the game takes 1 to 4 players, not 2.** `CLAUDE.md` said two;
`select_player_count` accepts keys 1–4, `all_player_data[4]` holds four states, and the
hand-over is `(player + 1) & 3`. `CLAUDE.md` is fixed.

`Main` is now a phase machine — `TITLE`, `SELECT`, `READY`, `PLAYING`, `DYING`, `BONUS`,
`FAREWELL` — which replaced the ad-hoc `_complete` / `_finished` flags. `is_game_over()` is
simply `phase == TITLE`; keeping a separate flag was ambiguous once returning to the title
became the end of a game.

### Game over is per player, not per game

From `.harry_died`: losing a life decrements only that player's count. If they have lives
left, play hands straight over. If that was their last, they get their **own** "GAME OVER /
Player N" and drop out, while everyone else carries on. Only when nobody is left does the
game return to the title.

⚠️ **The attract carousel is not built.** The original cycles three screens — a banner, the
high-score table, and the key bindings — via `carousel`, holding each for a count of
`carousel_test_keys_sleep`. Two of the three need M12 and M13, so the title is currently the
prompts alone.

⚠️ **The banner is a set of sprites nobody has extracted.** `draw_chuckie_banner` draws sprite
codes `0x30`–`0x35`, past `SPRITE_HAT` at `0x2f` where pbrook's `spritedata.c` stops. They are
in mungre's `sprites.basm` as `bmp_49` onwards. Until then the title spells the name in the
derived font.

Tested: 20 assertions covering the title and select screens, one through four players being
clamped and allocated, per-player scores and lives staying separate across hand-over, turns
returning to the first player, a finished player getting their farewell while play continues,
and the game ending only when everyone is out.

---

## M10 — Mother duck ✅

- [x] Released from level 9 (`have_big_duck = current_level > 7`) and never caged again
- [x] Cage drawn closed before that, open after
- [x] Flies at Harry, accelerating up to ±5 per axis, bouncing off the screen edges
- [x] Collision → life lost
- [x] Moves on `LevelClock`'s `MOTHER_DUCK` phase

She does not steer, she *accelerates* — one unit per axis per turn, capped at five — so she
drifts, overshoots and swings back rather than homing in. That is the whole character of the
chase and it falls out of the arithmetic.

The collision box is offset oddly and asymmetrically, from `CollisionDetect`: her x is compared
at `+4` and her y at `-5`, and the vertical span runs `-9` to `+19`.

### She is drawn while caged, and that matters

`DrawBigDuck` has no `have_big_duck` check and `big_duck_frame ^= 1` runs unconditionally, so
on levels 1–8 she sits in the cage with her wings still going. Only her movement and her
ability to catch Harry are gated.

This is not cosmetic. `SPRITE_CAGE_CLOSED` is drawn with her footprint **already cleared out
of it** — the original XORs her over the top — so the "missing" bars in the middle are the
ones she covers. Hiding her leaves a duck-shaped hole in the cage, which is exactly what the
first attempt looked like on screen.

### Two art problems found and fixed

**`Cage.aseprite` is the open cage.** It matches `SPRITE_CAGE_OPEN` exactly and is 152 px from
`SPRITE_CAGE_CLOSED` — so every level up to now drew the cage open, including the eight where
the duck is still inside it. There is no closed-cage artwork at all, so `CageClosed.png` now
comes from the ROM.

**The duck sprites did not match the ROM** — 89–95 px off at best fit, across all four
`BIGDUCK` frames and both mirrorings, and drawn in an off-palette `(255,255,11)` rather than
the BBC's `(255,255,0)`. Both regenerated from `BIGDUCK_R1` and `R2`; the left-facing frames
are exact mirrors, so `flip_h` covers them.

⚠️ **`rom_to_aseprite.py` could not write these at first.** The duck sources are **32-bit
RGBA** while every sprite repaired before them was 8-bit indexed, so the tool wrote index bytes
into a file whose header said RGBA and the decoder choked. It now reads the target's depth and
encodes to match.

Tested: 37 assertions covering the release level and the cage swap either side of it, her
staying visible and flapping while caged, the
chase accelerating towards Harry and overshooting him, speed caps, a caged duck never moving,
staying on screen across 600 turns of a moving target, and all eight edges of the collision box.

---

## M11 — Full progression & difficulty ✅

**No new code.** Every rule had already landed with the milestone that needed it, so this
turned into a verification pass — which is the useful outcome, since the rules are scattered
across five files and nothing had checked them together.

| Setting | Rule | Landed in |
|---|---|---|
| Layout | `current_level & 7`, forever | M1 |
| Hen count | none in round 2; all five from index 24; else the data's | M4a |
| Hen speed | one step, at index 32 | M4a |
| Mother duck | from index 8, permanently | M10 |
| Timer start | `9 - min(level >> 4, 8)`, floor at index 128 | M4a |
| Egg value | `(level >> 2) + 1` hundreds, capped at 1000 | M3 |
| Starting bonus | `min(level + 1, 9) × 100` | M3 |

✅ **`CLAUDE.md`'s round table was already corrected** back in M7, against the reference: the
duck's cage never closes again, hen speed steps only at 32, and layouts cycle from the start
with nothing special at level 40.

Tested: 59 assertions. Layouts load correctly for all 48 levels checked; hen counts across
every band; the speed step either side of 32; the duck absent then permanently present; timer
values at each 16-level boundary including the floor at 128; egg value and starting bonus
against the `CLAUDE.md` tables; and a live run advancing from level 7 through the round
boundary into level 10, confirming the hens vanish and the duck appears.

---

## M12 — High scores ✅

- [x] Ten-entry table, shown on the title
- [x] Name entry when a player clears the submission bar
- [x] Persisted to `user://highscores.cfg`, stamped with the day and reset when it rolls over
- [x] Submission to the site gated on a fixed bar, not on the local table

pbrook leaves this as a `/* Highscores. */` comment, so everything came from the disassembly's
`init_highscores`, `compare_highscores`, `shift_highscores`, `check_highscore` and
`draw_highscores`.

- **Ten entries of sixteen bytes** — eight score digits then an eight-character name.
- **Defaults are `"A&F"` scoring 1000**, ten times over: the publisher's own initials.
- **Ties go downward.** A score must beat an entry outright to take its place, so equalling
  the table changes nothing.
- **`check_highscore` runs per player** as each finishes, not once at the end of the game.
- Each row is **one run of characters** from a single move at x = 32: a two-character rank,
  the score with **leading zeros written as spaces**, a space, then the name. Positioning the
  score and name as separate columns makes them overlap, which the first attempt did.

Two glyphs had to be added rather than aliased: `&` for the default names and `>` for the name
prompt's caret. Aliasing them to `K` and `I` rendered the defaults as "AKF".

**The table does not decide what reaches the site.** It did originally — `check_highscore`'s
return value was what triggered name entry, and name entry was the only route to
`ScoreReporter.submit`. Since the table is per-browser and only ever ratchets upward, that
inverted the intent of the site's windows: a fresh browser submitted nearly every run while a
regular player's saturated table submitted almost nothing, silencing exactly the scores worth
recording. The prompt now fires on `HighScores.SUBMIT_FLOOR` (1000, the shipped `"A&F"` value),
which is fixed forever and identical for everyone; the local insert still happens alongside and
may place at nothing, so `_naming` can be -1 during name entry. The score therefore comes from
`PlayerState.score_value()` rather than being read back out of a table slot.

**The table is a daily board.** `save` stamps the local calendar date; `load_saved` drops the
file when that no longer matches, falling through to the shipped defaults on the same path a
malformed save takes. Checked only at startup, so midnight never wipes a board mid-session. The
permanent record lives on the site, which is what its 24 hour / 7 day / 30 day / all time
windows are for.

⚠️ **The attract carousel is still not built.** The title now shows the high scores, which was
one of its three screens; the key bindings need M13, and the banner needs the unextracted
sprites noted under M9b.

Tested: 26 assertions covering the defaults, placing and tie behaviour, insertion shifting the
table while keeping ten entries, name trimming, a save/reload round-trip, a missing file
leaving the defaults intact, and the whole flow from a qualifying death through the prompt to
the name landing in the right slot.

---

## M13 — Settings & key remapping ✅

- [x] Settings menu; rebind the five actions already defined in `project.godot`
- [x] Persist overrides to `user://`

`KeyBindings` (`scripts/key_bindings.gd`) holds the five controls; `Main` gained a
`Phase.KEY_SELECT` reached with `K` from the title, which is the original's `select_keys` —
it prompts up, down, left, right, jump one at a time and stores whatever is pressed.
Bindings are **physical** keycodes, matching `project.godot`, so a layout that moves Z and Y
keeps the key under the same finger; `label_for` translates back through
`keyboard_get_keycode_from_physical` so the screen prints what is on the keycap.

**Duplicates are allowed, deliberately.** `select_keys` stores each scan code with no
comparison against the others, so binding Up and Jump to the same key leaves both firing off
it and nothing warns you. `action_using` is there for anything that wants to spot a clash,
but no clash detection is wired in — that would be our invention, not the original's
behaviour. Do not add it.

What *is* refused is `RESERVED_KEYS` — S, K, H, Escape and the digits 1–4. The original
hardwires those scan codes for the same reason: if the front-end's own keys could be
rebound, the title screen could be made unreachable. A reserved key is ignored rather than
accepted, so the prompt simply stays put. A stale `keys.cfg` naming a since-reserved key is
dropped on load for the same reason.

Two bugs the tests caught:

- **`_defaults` has to be `static`.** `apply()` overwrites the `InputMap`, so an instance
  built after any rebinding read the *rebound* keys as its defaults, quietly making `reset()`
  a no-op. It is now snapshotted once, on first construction.
- **`load_saved` needs `has_section_key` before `get_value`.** `ConfigFile.get_value`'s
  default is only consulted when it is non-null, so a `null` default logged an error per
  missing key.

Deviations from the original, both noted in the code: the answered prompts echo the key they
were bound to (the original echoes nothing until the carousel's KEYS screen comes round), and
the two fixed controls — `Hold .. 'H'` and `Abort .. Escape +'H'` — are shown as a footer
here, because they belong to that same unbuilt carousel screen and a player looking at the
controls should be told about the ones that cannot be changed.

Column alignment is load-bearing and works out through `Message.at`'s integer division:
`Up`'s x of 196 truncates to wide-pixel 24, so its six-character label ends at 72 — exactly
where `Down`, `Left`, `Right` and `Jump` end from their own x positions.

Tested: 27 assertions covering the defaults snapshot, reset after rebinding, reserved-key
refusal, duplicates being accepted, `label_for`'s fallback, and a save/reload round trip
including a malformed and a missing file. Verified in the running game as well — the screen
renders with the key column aligned, S is ignored mid-prompt, the completed set lands in
`user://keys.cfg`, and Harry climbs on the rebound key with the old one dead.

⚠️ **The attract carousel is still not built.** Its KEYS screen now has all its content
(`_draw_key_selection` renders exactly that), but the rotation itself, and the banner screen
noted under M9b, are still missing.

### Follow-up — gamepad, and freeing the reserved keys

Landed after M13 closed, as one change: `RESERVED_KEYS` shrank to `[KEY_H, KEY_ESCAPE]` so
that `S` — and therefore WASD — became bindable, and the five actions gained d-pad, left-stick
and A-button events in `project.godot`.

**The two are one change, not two.** `apply()` used to call `InputMap.action_erase_events`,
which erases *everything* on the action. It runs from `_init` and again from `load_saved`,
both before the player touches anything, so the pad mapping would have been destroyed on every
launch. It now erases only the `InputEventKey` events and leaves the rest alone — that is the
single assertion the whole feature rests on.

**Freeing `S` required making the front end edge-triggered first.** `_tick_title` and
`_tick_select` level-polled at 33 Hz, so anything still held when a screen opened fired on its
first tick. Harmless while `S` could not be a control; a guaranteed instant restart once it
could — die on your last life with `S` (down) held and the title screen starts a new game
under you. `FrontEndInput` (`scripts/front_end_input.gd`) samples every watched input once per
tick, **in every phase**, and reports edges: something already down when a screen opens has no
edge until it is released. Sampling unconditionally is what makes "ignore what was already
held" fall out for free, with no per-screen gate to remember.

`Input.is_action_just_pressed` cannot do this — it is frame-scoped, and `_tick` runs at 33 Hz
out of a 60 Hz `_process`, so a press landing on a frame that runs no tick is never seen.

An event-driven front end was tried on paper first and does not work either: `InputEvent`'s
`is_action_pressed` is not edge-aware across events, so a held stick emits a stream of
`InputEventJoypadMotion` that each report the action as pressed, and the player-count selector
would run from 1 to 4 in a frame.

Two smaller things came with it:

- **Movement deadzone raised 0.2 → 0.5.** At 0.2 an off-axis or drifting stick reads as a
  diagonal, which an 8-way digital game shows as an unwanted second direction. `jump` stays at
  0.2, being a button.
- **Key repeat is now ignored while rebinding.** `_unhandled_key_input` did not check
  `key.echo`, so holding a key through the KEY SELECTION screen answered every remaining
  prompt with that same key. Name entry still *wants* echo — that is how holding a letter
  repeats it — so the guard is on the capture branch only.

Deviation: the player-select screen now draws the four counts with one highlighted, since a
pad cannot type a digit. `front_start` is a fixed action (S, Start, A) and is not rebindable.

Tested: 47 assertions, extending M13's 27 — the pad events surviving construction, rebinding,
`load_saved` and `reset`; exactly one key event left on an action after a rebind; `S`/`K`/`1`-`4`
bindable and `H`/`Escape` still refused; `S` round-tripping through `keys.cfg`; and
`FrontEndInput` reporting an edge on a fresh press but not while held.

Verified on real hardware after the fact: the d-pad indices, A, Start, the stick axes and the
0.5 deadzone all behave, and the pad still works after a rebind and a restart — which is the
`load_saved` → `apply()` path that used to wipe the joypad events.

### Follow-up — the jump's direction, and a timing artefact

Playing with the pad turned up a real complaint: jumping and pressing left or right *from
standing* often produced a straight-up hop instead of a diagonal one, on keyboard as well.

**The rule is faithful and was not the problem.** `StartPlayerJump` fixes the direction at
take-off — `player_slide = move_x` — and nothing can steer or reverse a jump in mid-air, here
or in the original.

**What we had removed was the original's accident.** The reference tests the jump button
*level*-triggered every tick (`chuckie.c:581`), so holding it hops again on every landing. A
mistimed jump therefore fixed itself: the unwanted vertical hop landed, the direction key had
caught up by then, and the next automatic hop went the right way. Nobody ever noticed the race.
We edge-trigger the jump deliberately — `button_ack` exists in the ROM to stop that bouncing
and the C port never tests it — and that took the safety net with it, leaving a straight ~30ms
coin flip on which input landed in the tick first, with no way to recover.

`_adopt_late_direction` restores the forgiveness without the bouncing: for the first two ticks
after take-off, and **only while `slide` is still zero**, a direction press is adopted. A jump
that already has a direction is never redirected, so the no-steering rule is untouched. Two
ticks is about 60ms — inside what a person perceives as simultaneous.

Tested: 10 assertions — a direction at take-off, one and two ticks late (adopted), three ticks
late (ignored), reversing refused twice over, and releasing the direction not killing the drift.

---

## M14 — Export targets 🔶

- [ ] macOS native
- [x] HTML5 / web
- [x] Confirm no case-sensitivity breakage in the web export (see the `assets/generated`
      note in `CLAUDE.md`)
- [x] Web specifics: audio needs a user gesture before it can start, and the canvas must hold
      keyboard focus

**Live at [egg.chrissearle.net](https://egg.chrissearle.net).** `chuckie-egg.chrissearle.net`
redirects there — one canonical origin, because the browser keeps high scores and key bindings
per-origin and two names would give a player two separate sets of them.

Both web caveats turned out to be already satisfied rather than needing work. Nothing plays at
boot — `Sfx._ready` only builds players and pre-renders streams, and the title screen calls
`stop_all()` — so the first sound cannot happen before a keypress and the autoplay gate is
never hit. The shell sets `body { overflow: hidden }`, so the arrow keys cannot scroll the
page out from under the canvas. Case sensitivity was settled long ago by the `assets/generated`
naming; the Linux container and the browser both load every glyph and letter.

**The export preset.** Threads are **off**, which is what makes `web_nothreads_*` the template
Godot asks for. A threaded build needs cross-origin isolation (`COOP: same-origin` plus
`COEP: require-corp`), and a 320 x 256 2D game gains nothing from it. `focus_canvas_on_start`
is on, and `canvas_resize_policy` is **Project** rather than Adaptive — see below.

**The canvas needed `!important`.** With the Project policy the engine writes the canvas size
into its *inline* style on load and on every resize, pinning it to the 960 x 768 window
override — which overflows any smaller window and ignores a stylesheet entirely, because
inline styles lose only to `!important`. With that, `object-fit: contain` scales the buffer
into whatever box is left and letterboxes it.

**The game sits at `/play`, not `/`.** The root is a landing page carrying the controls, the
credits and — not optional — the offer of source that GPL-3.0 requires when the WebAssembly
build is handed to a visitor. That is conveying a copy of the program, not the "network use is
not distribution" case. `/play` is a path rather than a second origin, so the move disturbed
nobody's stored scores or key bindings.

**The nav bar is injected, not templated.** `html/head_include` points at `/static/play.css`
and `/static/play.js`; Godot regenerates `index.html` on every export, so anything edited
there would be silently reverted by the next build.

### The hosting, which was not in the original scope

A leaderboard over four time windows cannot come from the game: `high_scores.gd` entries are
`{score, name}` with **no timestamp**, and the project has no networking at all. So the site
carries a small Kotlin/Ktor service in `server/` that owns the clock.

- **Scores are stored as JSON Lines** at `/data/scores.jsonl`, one object per line, so a name
  that turns out to be rude is fixed by opening the file in `vi`. A malformed line is skipped
  rather than fatal — a slip in an editor must cost one entry, not the board.
- **The page renders live** on each request, cached on the file's `(mtime, length)`. There is
  no cron and no generated output, so an edit shows up on the next refresh with nothing to
  re-run.
- **The server stamps the time.** The client has no clock worth trusting and a supplied one
  would be trivially forged.
- **Submissions are rejected, not sanitised** — a plausible ceiling, a multiple of ten (every
  award in the game is), a name inside the font's own 0x20-0x7e, and a per-IP rate limit read
  from `X-Forwarded-For` since Traefik fronts it.
- **The lettering is the game's own.** `tools/font_sheet_to_png.py` packs the BBC OS font into
  one sheet from the same YAFF source `yaff_to_png.py` uses, and the pages mask each character
  to its cell and tint it from the palette — the same thing `Message` does at draw time. The
  heading uses the real ROM banner letters at `Banner`'s own column offsets.

Deployed by Flux from `apps/egg.chrissearle.net` in the infrastructure repo: one replica with
`strategy: Recreate`, because the store is a file on a hostPath and two pods would race it.
Two Ingresses rather than one with two hosts — a Traefik middleware annotation applies to every
router an Ingress produces, so one object carrying both names would send the canonical redirect
to the canonical host as well, which is a redirect loop.

⚠️ **The score store is not backed up.** It is a single file on one node's `/srv/egg`, with no
replication and nothing copying it anywhere.

⚠️ **`current_level` is shared between players, not per-player.** `_next_player` re-enters the
level in play rather than that player's own, so in a two-player game the second player resumes
wherever the first got to. It predates all of this and is a divergence from the original; the
level recorded with a submitted score inherits it.
