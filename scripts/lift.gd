class_name Lift
extends Node2D

## The paired lifts, on layouts 3-7.
##
## Ported from MoveLift in the reference's chuckie.c. Both cars share one column
## and rise continuously, wrapping to the bottom rather than coming back down —
## so at any moment one is usually available somewhere in the shaft.
##
## Only one car moves per tick, alternating, which is why each rises two units
## every other tick and Harry riding one gains exactly one unit per tick.

const CAR_COUNT := 2

## Starting heights, from StartLevel.
const START_Y: Array[int] = [8, 0x5A]

## A car that reaches this height wraps back to the bottom of the shaft.
const WRAP_Y := 0xE0
const RESET_Y := 6
const STEP := 2

## Offset of Lift.png inside the ROM sprite, derived from the PNG in M1.
const DRAW_OFFSET := Vector2(6, 0)

const TOP_ROW := 255

const LIFT_TEXTURE: Texture2D = preload("res://assets/generated/Lift.png")

## True only on layouts that have lifts.
var present := false

## Shared column, in BBC wide-pixels.
var x := 0

## Height of each car, y-up.
var car_y: Array[int] = [START_Y[0], START_Y[1]]

## Which car moves on the next tick.
var active := 0

var _sprites: Array[Sprite2D] = []


func _ready() -> void:
	for i in CAR_COUNT:
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = LIFT_TEXTURE
		add_child(sprite)
		_sprites.append(sprite)
	_refresh()


## Configures for a level and returns the cars to their starting heights.
func setup(lift_x: int, has_lift: bool) -> void:
	present = has_lift
	x = lift_x
	car_y[0] = START_Y[0]
	car_y[1] = START_Y[1]
	active = 0
	_refresh()


## Advances one car. Called every tick, unlike the hen and timer phases.
func step() -> void:
	if not present:
		return
	var height: int = car_y[active] + STEP
	if height == WRAP_Y:
		height = RESET_Y
	car_y[active] = height
	active = 1 - active
	_refresh()


## True when `player_x` is within the shaft. The reference uses a slightly wider
## span when catching a lift than when checking whether Harry has left one.
func spans(player_x: int, reach: int) -> bool:
	return not (x > player_x or x + reach < player_x)


func _refresh() -> void:
	if _sprites.is_empty():
		return
	for i in CAR_COUNT:
		_sprites[i].visible = present
		_sprites[i].position = Vector2(x * 2, TOP_ROW - car_y[i]) + DRAW_OFFSET
