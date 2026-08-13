class_name Hen
extends Sprite2D

## One hen — a "small duck" in the reference implementation.
##
## Ported from the per-duck half of MoveDucks in chuckie.c. Hens do not move
## every tick: LevelClock hands out one step at a time, so their speed comes
## from how often they are picked rather than from any speed value here.
##
## Positions are BBC space, matching Player: `x` in wide-pixels, `y` y-up.

## Emitted when this hen swallows a grain, so it stays eaten if the level is
## re-entered after a lost life.
signal grain_eaten(index: int)

enum Mode { BORED, STEP, EAT1, EAT2, EAT3, EAT4 }

const DIR_L := 1
const DIR_R := 2
const DIR_UP := 4
const DIR_DOWN := 8
const DIR_HORIZ := DIR_L | DIR_R

## Half a tile per step; the tile position updates on every second step.
const STEP_PIXELS := 4

## Hens spawn 0x14 above their tile's base, unlike Harry's +16.
const SPAWN_Y_OFFSET := 0x14

const TOP_ROW := 255

## Width of a hen sprite's ROM canvas, in square pixels. Trimmed art has to be
## re-anchored against this when mirrored.
const ROM_WIDTH := 16

## The eating sprites are twice as wide, the head reaching into the next tile.
const ROM_WIDTH_EAT := 32

## Facing left, the eating sprite is drawn a tile further left so the head
## reaches the right way. DrawDuck does this as `x -= 8` in wide-pixels.
const EAT_LEFT_SHIFT := 16

const TEXTURE_STAND: Texture2D = preload("res://assets/generated/HenStand.png")
const TEXTURE_WALK: Texture2D = preload("res://assets/generated/HenWalk.png")
## Names are historical: HenClimb1 holds SPRITE_DUCK_UP2 and HenClimb2 holds
## SPRITE_DUCK_UP, so they are swapped relative to what the file names suggest.
const TEXTURE_CLIMB_A: Texture2D = preload("res://assets/generated/HenClimb2.png")
const TEXTURE_CLIMB_B: Texture2D = preload("res://assets/generated/HenClimb1.png")
const TEXTURE_PECK_A: Texture2D = preload("res://assets/generated/HenPeck1.png")
const TEXTURE_PECK_B: Texture2D = preload("res://assets/generated/HenPeck2.png")

## Where each PNG's top-left corner sits relative to the ROM sprite's origin.
##
## The decoded PNGs are the full 28 x 28 Aseprite canvas, not the trimmed cel —
## the hen occupies only part of it — so these offsets are negative. They were
## derived by matching each **PNG** against the ROM bitmap in spritedata.c;
## deriving them from the cel instead puts every hen 7 px right and 8 rows low.
##
## The two climb frames differ vertically because SPRITE_DUCK_UP2 is 22 rows
## tall against SPRITE_DUCK_UP's 20.
const OFFSET_STAND := Vector2(-5, -8)
const OFFSET_WALK := Vector2(-5, -8)
const OFFSET_CLIMB_A := Vector2(-6, -8)
const OFFSET_CLIMB_B := Vector2(-6, -6)
const OFFSET_PECK_A := Vector2(2, -8)
const OFFSET_PECK_B := Vector2(1, -8)

var x := 0
var y := 0
var tile_x := 0
var tile_y := 0
var mode: Mode = Mode.BORED
var dir := DIR_R

var _map: LevelMap = null
var _random: BbcRandom = null


func _ready() -> void:
	centered = false


## Places the hen at its spawn tile, as StartLevel does.
func spawn(tile: Vector2i, map: LevelMap, random: BbcRandom) -> void:
	_map = map
	_random = random
	tile_x = tile.x
	tile_y = tile.y
	x = tile.x << 3
	y = (tile.y << 3) + SPAWN_Y_OFFSET
	mode = Mode.BORED
	dir = DIR_R
	_refresh_sprite()


## Advances this hen by one step.
##
## Eating takes priority over moving: a hen part-way through its peck animation
## stays put until the cycle finishes.
func step() -> void:
	if _map == null:
		return

	if mode >= Mode.EAT1:
		# The grain vanishes on the second frame of the peck, not the first.
		if mode == Mode.EAT2:
			_swallow_grain()
	elif mode == Mode.BORED:
		_choose_direction()
		_look_for_grain()

	if mode >= Mode.EAT1:
		mode = Mode.BORED if mode == Mode.EAT4 else ((mode + 1) as Mode)
		_refresh_sprite()
		return

	_walk()
	_refresh_sprite()


## The tile a hen pecks at: the one it is facing.
func _grain_tile() -> Vector2i:
	var ahead := tile_x - 1 if (dir & DIR_L) != 0 else tile_x + 1
	return Vector2i(ahead, tile_y)


## Starts the peck animation if there is grain in front of the hen. Only hens
## walking horizontally stop to eat.
func _look_for_grain() -> void:
	if (dir & DIR_HORIZ) == 0:
		return
	var tile := _grain_tile()
	if (_map.read_tile(tile.x, tile.y) & LevelMap.TILE_GRAIN) != 0:
		mode = Mode.EAT1


func _swallow_grain() -> void:
	var tile := _grain_tile()
	# Check before taking: take_collectable would also remove an egg, and hens
	# only ever eat grain.
	var value := _map.read_tile(tile.x, tile.y)
	if (value & LevelMap.TILE_GRAIN) == 0:
		return
	_map.take_collectable(tile.x, tile.y)
	grain_eaten.emit(value >> LevelMap.INDEX_SHIFT)


## Picks the next direction at a junction.
##
## Collects every direction that is possible from here, then narrows: with more
## than one option, reversing is ruled out first, and if that still leaves a
## choice the original picks randomly.
func _choose_direction() -> void:
	var options := 0
	if (_map.read_tile(tile_x - 1, tile_y - 1) & LevelMap.TILE_WALL) != 0:
		options |= DIR_L
	if (_map.read_tile(tile_x + 1, tile_y - 1) & LevelMap.TILE_WALL) != 0:
		options |= DIR_R
	if (_map.read_tile(tile_x, tile_y - 1) & LevelMap.TILE_LADDER) != 0:
		options |= DIR_DOWN
	if (_map.read_tile(tile_x, tile_y + 2) & LevelMap.TILE_LADDER) != 0:
		options |= DIR_UP

	if _popcount(options) != 1:
		# Mask out the reverse of the current heading. The original does this
		# with XOR constants: 0xfc for horizontal, 0xf3 for vertical.
		var keep := (dir ^ 0xFC) if (dir & DIR_HORIZ) != 0 else (dir ^ 0xF3)
		options &= keep

	if _popcount(options) != 1:
		# Still ambiguous, so choose randomly among what is left. The loop
		# retries until exactly one bit survives, as the original does.
		var candidates := options
		if candidates == 0:
			return
		while _popcount(options) != 1:
			options = _random.next() & candidates

	dir = options


## Moves half a tile in the current direction.
##
## The tile position only advances on the second of each pair of steps, which is
## what `flag` tracks in the original — hence alternating BORED and STEP.
func _walk() -> void:
	var crossing := 0
	if mode == Mode.STEP:
		mode = Mode.BORED
		crossing = 1
	else:
		mode = Mode.STEP

	match dir:
		DIR_L:
			x -= STEP_PIXELS
			tile_x -= crossing
		DIR_R:
			x += STEP_PIXELS
			tile_x += crossing
		DIR_UP:
			y += STEP_PIXELS
			tile_y += crossing
		DIR_DOWN:
			y -= STEP_PIXELS
			tile_y -= crossing


func _popcount(value: int) -> int:
	var count := 0
	var bits := value
	while bits != 0:
		count += bits & 1
		bits >>= 1
	return count


## Chooses the frame, following DuckSprite. Left-facing frames are mirrors of
## the right-facing art, as SPRITE_DUCK_L is of SPRITE_DUCK_R.
func _refresh_sprite() -> void:
	var frame_offset: Vector2
	var rom_width := ROM_WIDTH
	var left_shift := 0

	if mode >= Mode.EAT1:
		# EAT3 is the open beak; EAT2 and EAT4 both use the closed one.
		var open_beak := mode == Mode.EAT3
		texture = TEXTURE_PECK_B if open_beak else TEXTURE_PECK_A
		frame_offset = OFFSET_PECK_B if open_beak else OFFSET_PECK_A
		flip_h = (dir & DIR_L) != 0
		rom_width = ROM_WIDTH_EAT
		if flip_h:
			left_shift = EAT_LEFT_SHIFT
	elif (dir & DIR_HORIZ) != 0:
		var stepping := mode == Mode.STEP
		texture = TEXTURE_WALK if stepping else TEXTURE_STAND
		frame_offset = OFFSET_WALK if stepping else OFFSET_STAND
		flip_h = dir != DIR_R
	else:
		var stepping := mode == Mode.STEP
		texture = TEXTURE_CLIMB_B if stepping else TEXTURE_CLIMB_A
		frame_offset = OFFSET_CLIMB_B if stepping else OFFSET_CLIMB_A
		flip_h = false

	# Mirroring happens inside the ROM canvas, so trimmed art has to be
	# re-anchored from the opposite edge or the hen shifts as it turns around.
	var offset_x := frame_offset.x
	if flip_h and texture != null:
		offset_x = rom_width - texture.get_width() - frame_offset.x

	position = Vector2(x * 2 - left_shift + offset_x, TOP_ROW - y + frame_offset.y)
