class_name MotherDuck
extends Sprite2D

## The mother duck, released from level 9 onwards.
##
## Ported from the big-duck branch of MoveDucks in chuckie.c. She does not walk
## the platforms: she flies straight at Harry, accelerating by one unit per axis
## each turn up to a limit, so she drifts, overshoots and comes back round.
##
## She moves on one phase in eight, which is why she is slower than she looks.
##
## **She is always drawn, caged or not.** `DrawBigDuck` has no `have_big_duck`
## check and the wing beat toggles unconditionally, so on levels 1-8 she sits in
## the cage flapping. Only her movement and her ability to catch Harry are gated.
## SPRITE_CAGE_CLOSED is drawn with her footprint already cleared out of it — the
## original XORs her over the top — so hiding her leaves a duck-shaped hole.

## Acceleration limit per axis.
const MAX_SPEED := 5

## Where she starts, from StartLevel.
const START_X := 4
const START_Y := 0xCC

## She bounces off these bounds rather than leaving the screen.
const FLOOR_Y := 0x28
const MAX_X := 0x90

## Harry's hit box against her, from CollisionDetect. Note the offsets: her x is
## compared at +4 and her y at -5, and the vertical span is asymmetric.
const HIT_X_OFFSET := 4
const HIT_X := 5
const HIT_Y_OFFSET := -5
const HIT_Y_MIN := -9
const HIT_Y_MAX := 19

## Harry's own position is compared at +4 vertically when she chases him.
const CHASE_Y_OFFSET := 4

const TOP_ROW := 255

const TEXTURE_CLOSED: Texture2D = preload("res://assets/generated/DuckClosedBeak.png")
const TEXTURE_OPEN: Texture2D = preload("res://assets/generated/DuckOpenBeak.png")

## True only from level 9 onwards. Before that she is caged: still drawn and
## still flapping, but stationary and harmless.
var present := false

var x := START_X
var y := START_Y

## Facing, as the original stores it: 0 right, 1 left.
var facing := 0

var _dx := 0
var _dy := 0
var _frame := 0


func _ready() -> void:
	centered = false
	reset(false)


## Returns her to the cage mouth. `has_duck` is `current_level > 7`.
func reset(has_duck: bool) -> void:
	present = has_duck
	x = START_X
	y = START_Y
	_dx = 0
	_dy = 0
	_frame = 0
	facing = 0
	_refresh()


## One turn of the chase, on the clock's mother-duck phase.
##
## The position and the wing beat advance whether or not she is out, matching
## the original — with no duck her speed stays zero, so nothing moves.
func step(player_x: int, player_y: int) -> void:
	if present:
		_steer(player_x, player_y)
	x += _dx
	y += _dy
	_frame ^= 1
	_refresh()


func _steer(player_x: int, player_y: int) -> void:
	# Accelerate towards Harry, one unit per turn, and face the way she is going.
	if x + HIT_X_OFFSET < player_x:
		_dx = mini(_dx + 1, MAX_SPEED)
		facing = 0
	else:
		_dx = maxi(_dx - 1, -MAX_SPEED)
		facing = 1

	if player_y + CHASE_Y_OFFSET >= y:
		_dy = mini(_dy + 1, MAX_SPEED)
	else:
		_dy = maxi(_dy - 1, -MAX_SPEED)

	# Bounce rather than leave the screen. The original reverses the speed, so
	# she keeps her momentum and swings back.
	if y + _dy < FLOOR_Y:
		_dy = -_dy
	var next_x := x + _dx
	if next_x < 0 or next_x >= MAX_X:
		_dx = -_dx


## True when she is overlapping Harry.
func touching(player_x: int, player_y: int) -> bool:
	if not present:
		return false
	var dx := x + HIT_X_OFFSET - player_x
	if dx < -HIT_X or dx > HIT_X:
		return false
	var dy := y + HIT_Y_OFFSET - player_y
	return dy >= HIT_Y_MIN and dy <= HIT_Y_MAX


func _refresh() -> void:
	texture = TEXTURE_OPEN if _frame == 1 else TEXTURE_CLOSED
	flip_h = facing == 1
	position = Vector2(x * 2, TOP_ROW - y)
