class_name Player
extends Sprite2D

## Hen House Harry.
##
## This is a deliberately literal port of `MovePlayer` and its helpers from the
## reference implementation's chuckie.c. The arithmetic is integer and runs on a
## fixed tick; jump distances, ledge-slide behaviour and ladder grab windows all
## fall out of the exact operations below, so resist "tidying" them into float
## velocity or Godot physics.
##
## Coordinates are BBC space throughout: `x` is in wide-pixels (0..0x98) and `y`
## is y-up. Conversion to Godot's screen space happens once, in _refresh_sprite.
##
## Riding a lift is PLAYER_LIFT; Harry only catches one mid-jump.

## Emitted when Harry walks over an egg. `index` is the egg's slot in the level
## data, so a lost life can leave already-taken eggs collected.
signal egg_collected(index: int)

## Emitted when Harry walks over a grain.
signal grain_collected(index: int)

enum Mode { WALK, CLIMB, JUMP, FALL, LIFT }

const START_X := 0x3C
const START_Y := 0x20
const START_TILE_X := 7
const START_TILE_Y := 2
const START_PARTIAL_X := 7

## Rightmost `x` Harry may reach. The original compares against this directly.
const MAX_X := 0x98

## Below this `y` Harry has dropped off the bottom of the screen and is dead.
const DEATH_Y := 0x11

## Touching this `y` is the top of the screen; a jump is cut short there.
const CEILING_Y := 0xDC

## `player_fall` is forced to this when a jump hits the ceiling, putting the arc
## straight into its descent.
const CEILING_FALL := 0x0C

## Harry only latches onto a ladder when he is centred on it.
const LADDER_ALIGN := 3

## How far past the lift column Harry can still be and catch it, against the
## narrower span that keeps him on it once riding. The original uses 10 and 9.
const LIFT_CATCH_REACH := 10
const LIFT_RIDE_REACH := 9

## Vertical offsets used when matching Harry against a lift car.
const LIFT_FOOT_OFFSET := 0x11
const LIFT_HEAD_OFFSET := 0x13

## `y` is the sprite's top row in y-up space, so screen row = TOP_ROW - y.
const TOP_ROW := 255

## Walk animation table, indexed by `(x >> 1) & 3` — the stand frame appears
## twice, giving the original's stand/step/stand/step gait.
const TEXTURE_STAND: Texture2D = preload("res://assets/generated/Stand.png")
const TEXTURE_WALK: Texture2D = preload("res://assets/generated/Walk.png")
const TEXTURE_WALK2: Texture2D = preload("res://assets/generated/Walk2.png")
const WALK_FRAMES: Array[Texture2D] = [
	TEXTURE_STAND,
	TEXTURE_WALK,
	TEXTURE_STAND,
	TEXTURE_WALK2,
]

## Climb animation table, indexed by `(y >> 1) & 3`. The file names are
## historical: these hold SPRITE_PLAYER_UP, UP2 and UP3 respectively, not
## left/right variants.
const TEXTURE_CLIMB: Texture2D = preload("res://assets/generated/ClimbUp.png")
const TEXTURE_CLIMB2: Texture2D = preload("res://assets/generated/ClimbUpLeft.png")
const TEXTURE_CLIMB3: Texture2D = preload("res://assets/generated/ClimbUpRight.png")
const CLIMB_FRAMES: Array[Texture2D] = [
	TEXTURE_CLIMB,
	TEXTURE_CLIMB2,
	TEXTURE_CLIMB,
	TEXTURE_CLIMB3,
]

var mode: Mode = Mode.WALK
var x := START_X
var y := START_Y
var tile_x := START_TILE_X
var tile_y := START_TILE_Y
var partial_x := START_PARTIAL_X
var partial_y := 0

## -1 facing left, +1 facing right, 0 facing the screen while climbing.
var face := 1

## Ticks spent falling or airborne. Drives the fall's sideways slide, the
## downward acceleration, and the jump arc.
var fall := 0

## Horizontal drift retained through a fall or jump, so leaving a ledge carries
## you outwards rather than dropping straight down.
var slide := 0

var _move_x := 0
var _move_y := 0
var _jump_held := false
var _killed := false
var _map: LevelMap = null
var _lift: Lift = null


func _ready() -> void:
	centered = false
	reset()


func set_map(map: LevelMap) -> void:
	_map = map


func set_lift(lift: Lift) -> void:
	_lift = lift


## Returns Harry to the level's start position and state.
func reset() -> void:
	mode = Mode.WALK
	x = START_X
	y = START_Y
	tile_x = START_TILE_X
	tile_y = START_TILE_Y
	partial_x = START_PARTIAL_X
	partial_y = 0
	face = 1
	fall = 0
	slide = 0
	_move_x = 0
	_move_y = 0
	_jump_held = false
	_killed = false
	_refresh_sprite()


## How far Harry actually moved this tick, in BBC units. Sound keys off this:
## the original only beeps while he is moving.
func movement() -> Vector2i:
	return Vector2i(_move_x, _move_y)


## True once Harry has fallen off the bottom of the screen, or been carried into
## the top of it by a lift.
func is_dead() -> bool:
	return y < DEATH_Y or _killed


## Advances one logic tick. `input_x` and `input_y` are -1, 0 or +1, with
## positive `input_y` meaning up (BBC y-up).
func tick(input_x: int, input_y: int, jump_pressed: bool) -> void:
	if _map == null:
		return

	# Edge-triggered jump. The reference reads the button's held state directly,
	# which makes Harry hop again the instant he lands if you keep the key down.
	# Its own `button_ack` flag exists to prevent exactly that but is never read
	# in the C port, so requiring a fresh press restores the intended behaviour.
	var jump_started := jump_pressed and not _jump_held
	_jump_held = jump_pressed

	_move_x = input_x
	# Vertical input moves two units per tick against one horizontal, which
	# exactly compensates for the BBC's 2:1 wide pixels. Do not "fix" this.
	_move_y = input_y << 1

	match mode:
		Mode.WALK:
			_tick_walk(jump_started)
		Mode.FALL:
			_tick_fall()
		Mode.CLIMB:
			_tick_climb(jump_started)
		Mode.JUMP:
			_tick_jump()
		Mode.LIFT:
			_tick_lift(jump_started)
		_:
			_tick_walk(jump_started)

	_animate()
	_refresh_sprite()


func _tick_walk(jump_started: bool) -> void:
	if jump_started:
		_start_jump()
		return

	if _move_y != 0:
		# Grabbing a ladder from the ground needs Harry centred on it. The tile
		# checked is two above when climbing up, one below when climbing down.
		if partial_x == LADDER_ALIGN:
			var probe_y := tile_y + 2 if _move_y >= 0 else tile_y - 1
			if (_map.read_tile(tile_x, probe_y) & LevelMap.TILE_LADDER) != 0:
				_move_x = 0
				mode = Mode.CLIMB
				return
		_move_y = 0

	# Look at the tile below the one Harry is stepping into. If it is not solid
	# he has walked off an edge.
	var probe_x := tile_x
	var carry := partial_x + _move_x
	if carry < 0:
		probe_x -= 1
	elif carry >= 8:
		probe_x += 1

	if (_map.read_tile(probe_x, tile_y - 1) & LevelMap.TILE_WALL) == 0:
		# Which way he topples depends on how far into the tile he was.
		if ((_move_x + partial_x) & 7) < 4:
			slide = 1
			fall = 1
		else:
			slide = -1
			fall = 0
		mode = Mode.FALL

	if _blocked_sideways():
		_move_x = 0
	if _move_x != 0:
		face = _move_x


func _tick_fall() -> void:
	fall += 1
	if fall < 4:
		# Early in the fall Harry keeps drifting the way he stepped off.
		_move_x = slide
		_move_y = -1
	else:
		_move_x = 0
		_move_y = -(mini(fall >> 2, 3) + 1)

	# Land when the descent would reach or cross the top of a solid tile.
	# Note this tests any wall bit, unlike _blocked_sideways below.
	var landing := _move_y + partial_y
	if landing == 0:
		if (_map.read_tile(tile_x, tile_y - 1) & LevelMap.TILE_WALL) != 0:
			mode = Mode.WALK
	elif landing < 0:
		if (_map.read_tile(tile_x, tile_y - 1) & LevelMap.TILE_WALL) != 0:
			mode = Mode.WALK
			# Snap exactly onto the surface rather than overshooting into it.
			_move_y = -partial_y


## How many ticks after take-off a direction can still be adopted. Two ticks is
## about 60ms — inside the window a person perceives as "at the same time", and
## well short of anything that would feel like mid-air steering.
const LATE_DIRECTION_TICKS := 2


## Deliberate deviation, for a timing artefact rather than a rule.
##
## `StartPlayerJump` fixes the direction at take-off — `player_slide = move_x` —
## and that much is faithful; you cannot steer or reverse in mid-air, here or in
## the original. But pressing jump and a direction "together" resolves to
## whichever landed first inside a 30ms tick, so a straight-up hop you did not
## want came out roughly half the time, with no way to correct it.
##
## The reference never shows this because its jump is *level*-triggered: holding
## the button hops again on every landing, so a mistimed jump quietly fixes
## itself on the next hop once the direction has caught up. We edge-trigger the
## jump on purpose (see `tick`), which removed that safety net along with the
## unwanted bouncing.
##
## So the near-simultaneous press is honoured, and only that: the direction is
## adopted just for the first couple of ticks, and only while `slide` is still
## zero. A jump that already has a direction is never redirected.
func _adopt_late_direction() -> void:
	if slide != 0 or _move_x == 0 or fall > LATE_DIRECTION_TICKS:
		return

	slide = _move_x
	face = _move_x


func _start_jump() -> void:
	fall = 0
	mode = Mode.JUMP
	slide = _move_x
	if _move_x != 0:
		face = _move_x
	_tick_jump()


func _tick_jump() -> void:
	# The vertical input is consumed before _move_y is overwritten, because a
	# jump can still be steered onto a ladder in mid-air.
	var wanted := _move_y

	_adopt_late_direction()
	_move_x = slide
	# The arc: +2 at take-off, easing down to -4 once falling.
	_move_y = 2 - mini(fall >> 2, 6)
	fall += 1

	if y == CEILING_Y:
		# Hit the top of the screen; drop straight into the descent.
		_move_y = -1
		fall = CEILING_FALL
	else:
		_grab_ladder(wanted)
		if mode == Mode.CLIMB:
			return

	var landing := _move_y + partial_y
	if landing == 0:
		if (_map.read_tile(tile_x, tile_y - 1) & LevelMap.TILE_WALL) != 0:
			mode = Mode.WALK
	elif landing > 0:
		# Rising through a tile boundary into a solid tile stops the ascent.
		if landing == 8 and (_map.read_tile(tile_x, tile_y) & LevelMap.TILE_WALL) != 0:
			mode = Mode.WALK
	else:
		if (_map.read_tile(tile_x, tile_y - 1) & LevelMap.TILE_WALL) != 0:
			mode = Mode.WALK
			_move_y = -partial_y

	_catch_lift()
	if mode == Mode.LIFT:
		return

	if _blocked_sideways():
		# Hitting a wall in mid-air bounces Harry back the other way.
		_move_x = -_move_x
		slide = _move_x


func _tick_climb(jump_started: bool) -> void:
	if jump_started:
		_start_jump()
		return

	# Stepping off a ladder sideways is only allowed at a tile boundary, and
	# only where there is solid ground to step onto.
	if _move_x != 0 and partial_y == 0:
		if (_map.read_tile(tile_x, tile_y - 1) & LevelMap.TILE_WALL) != 0:
			_move_y = 0
			mode = Mode.WALK

	if mode != Mode.WALK:
		_move_x = 0
		if _move_y != 0 and partial_y == 0:
			# Do not climb past either end of the ladder.
			var probe_y := tile_y + 2 if _move_y >= 0 else tile_y - 1
			if (_map.read_tile(tile_x, probe_y) & LevelMap.TILE_LADDER) == 0:
				_move_y = 0

	face = 0


## Latches onto a ladder mid-jump. `wanted` is the vertical input from before
## the jump arc overwrote it.
func _grab_ladder(wanted: int) -> void:
	if partial_x + _move_x != LADDER_ALIGN:
		return
	if wanted == 0:
		return

	if wanted > 0:
		var probe_y := tile_y + 1
		if (_map.read_tile(tile_x, probe_y) & LevelMap.TILE_LADDER) == 0:
			# Try one tile further down when Harry straddles a boundary.
			if partial_y >= 4:
				probe_y += 1
			if (_map.read_tile(tile_x, probe_y) & LevelMap.TILE_LADDER) == 0:
				return
		mode = Mode.CLIMB
		# Nudge onto an even step so climbing stays aligned to the rungs.
		if (partial_y + _move_y) & 1:
			_move_y += 1
		return

	if (_map.read_tile(tile_x, tile_y) & LevelMap.TILE_LADDER) == 0:
		return
	if (_map.read_tile(tile_x, tile_y + 1) & LevelMap.TILE_LADDER) == 0:
		return
	mode = Mode.CLIMB
	if (partial_y + _move_y) & 1:
		_move_y -= 1


## Rides a lift upward.
##
## Harry drifts off the top of the screen if he stays on too long, which is
## lethal; stepping sideways out of the shaft drops him instead.
func _tick_lift(jump_started: bool) -> void:
	if jump_started:
		_start_jump()
		return

	if _lift == null or not _lift.spans(x, LIFT_RIDE_REACH):
		fall = 0
		slide = 0
		mode = Mode.FALL

	# The car rises two units every other tick, so riding it is one per tick.
	_move_y = 1
	if _move_x != 0:
		face = _move_x
	if _blocked_sideways():
		_move_x = 0
	if y >= CEILING_Y:
		_killed = true


## Catches a passing lift mid-jump, if one is level with Harry's feet.
##
## Ported from PlayerHitLift. The window is between his feet now and where they
## will be after this tick's movement, so a car crossing that span picks him up.
func _catch_lift() -> void:
	if _lift == null or not _lift.present:
		return
	if not _lift.spans(x, LIFT_CATCH_REACH):
		return

	var foot := y - LIFT_FOOT_OFFSET
	var reach := y - LIFT_HEAD_OFFSET + _move_y

	var height: int = _lift.car_y[0]
	if height > foot or height < reach:
		height = _lift.car_y[1]
		if height != foot:
			if height >= foot:
				return
			if height < reach:
				return
		if _lift.active == 0:
			height += 1
	elif _lift.active != 0:
		height += 1

	_move_y = height - foot + 1
	fall = 0
	mode = Mode.LIFT


## True when a wall blocks horizontal movement.
##
## The tile test is `== TILE_WALL` rather than a bitwise AND, so a combined
## wall+ladder tile does **not** block. That is what lets Harry walk through the
## gap a ladder makes in a platform, and it is faithful to the original.
func _blocked_sideways() -> bool:
	if _move_x == 0:
		return false

	var moving_left := _move_x < 0
	if (x == 0) if moving_left else (x >= MAX_X):
		return true

	# Only the leading edge of the sprite can catch on a wall: partial_x < 2
	# when moving left, partial_x >= 5 when moving right.
	if not ((partial_x < 2) if moving_left else (partial_x >= 5)):
		return false

	# _move_x is exactly -1 or +1, so this is the adjacent column.
	return _blocked_by_wall(tile_x + _move_x)


## Tile half of the sideways check, split out only to keep the branch count
## readable. Probes the column Harry is moving into, at the row he will occupy
## once this tick's vertical movement is applied.
func _blocked_by_wall(probe_x: int) -> bool:
	if _move_y == 2:
		return false

	var probe_y := tile_y
	var carry := partial_y + _move_y
	if carry < 0:
		probe_y -= 1
	elif carry >= 8:
		probe_y += 1

	if _map.read_tile(probe_x, probe_y) == LevelMap.TILE_WALL:
		return true
	if _move_y >= 0:
		return false
	# Descending, so the tile below matters too.
	return _map.read_tile(probe_x, probe_y + 1) == LevelMap.TILE_WALL


## Commits the tick's movement, keeping pixel, tile and partial positions in
## step. The original tracks all three rather than deriving them, and the
## collision code reads each of them, so this port does the same.
func _animate() -> void:
	x += _move_x
	var carry := partial_x + _move_x
	if carry < 0:
		tile_x -= 1
	elif carry >= 8:
		tile_x += 1
	partial_x = carry & 7

	y += _move_y
	carry = partial_y + _move_y
	if carry < 0:
		tile_y -= 1
	elif carry >= 8:
		tile_y += 1
	partial_y = carry & 7

	_collect()


## Picks up whatever Harry is standing on.
##
## The tile tested is the one his body occupies, dropping a row once he is more
## than halfway into it — so collectables are taken from roughly his middle
## rather than his feet.
func _collect() -> void:
	var probe_y := tile_y
	if partial_y >= 4:
		probe_y += 1

	var taken := _map.take_collectable(tile_x, probe_y)
	if taken == LevelMap.TILE_EMPTY:
		return

	var index := taken >> LevelMap.INDEX_SHIFT
	if (taken & LevelMap.TILE_GRAIN) != 0:
		grain_collected.emit(index)
	else:
		egg_collected.emit(index)


func _refresh_sprite() -> void:
	if face == 0:
		var climb_index := (y >> 1) & 3
		if _move_y == 0:
			climb_index = 0
		texture = CLIMB_FRAMES[climb_index]
		flip_h = false
		position = Vector2(x * 2, TOP_ROW - y)
		return

	var frame_index := (x >> 1) & 3
	if _move_x == 0:
		frame_index = 0
	texture = WALK_FRAMES[frame_index]
	flip_h = face < 0
	# x is in wide-pixels, so double it; y is the sprite's top row, y-up.
	position = Vector2(x * 2, TOP_ROW - y)
