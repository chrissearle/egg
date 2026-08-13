class_name Playfield
extends Node2D

## Draws the level's tile grid.
##
## The node sits at y = PLAY_AREA_TOP inside the 320x256 viewport, so everything
## here works in play-area-local space and the HUD offset stays out of the tile
## arithmetic. Local row for a BBC tile row is (GRID_TOP_ROW - bbc_y) * TILE_HEIGHT,
## which reproduces the reference's `row_top = 248 - 8 * bbc_y` once the node
## offset is added back.

## A tile is 16x8 square pixels: 8 BBC wide-pixels across, 8 scanlines down.
const TILE_WIDTH := 16
const TILE_HEIGHT := 8

## Rows 0..55 of the viewport belong to the HUD; the play area is rows 56..255.
const PLAY_AREA_TOP := 56

const GRID_TOP_ROW := LevelMap.HEIGHT - 1

## Offsets of each sprite inside its 16x8 tile. Derived from the bitmaps in the
## reference's spritedata.c: Platform and Ladder fill the tile from its top-left,
## while Egg and Grain are trimmed and sit inset. These are not cosmetic tweaks —
## the decoded PNGs match those ROM bitmaps exactly at these offsets.
const PLATFORM_OFFSET := Vector2(0, 0)
const LADDER_OFFSET := Vector2(0, 0)
const EGG_OFFSET := Vector2(2, 1)
const GRAIN_OFFSET := Vector2(2, 3)

const PLATFORM_TEXTURE: Texture2D = preload("res://assets/generated/Platform.png")
const LADDER_TEXTURE: Texture2D = preload("res://assets/generated/Ladder.png")
const EGG_TEXTURE: Texture2D = preload("res://assets/generated/Egg.png")
const GRAIN_TEXTURE: Texture2D = preload("res://assets/generated/Corn.png")

var _map: LevelMap = null


func _ready() -> void:
	position = Vector2(0, PLAY_AREA_TOP)


## Points the playfield at a map and repaints.
func set_map(map: LevelMap) -> void:
	_map = map
	queue_redraw()


## Top-left corner of a BBC tile in play-area-local pixels.
static func tile_origin(tile_x: int, tile_y: int) -> Vector2:
	return Vector2(tile_x * TILE_WIDTH, (GRID_TOP_ROW - tile_y) * TILE_HEIGHT)


func _draw() -> void:
	if _map == null:
		return
	for tile_y in LevelMap.HEIGHT:
		for tile_x in LevelMap.WIDTH:
			_draw_tile(tile_x, tile_y, _map.tile_type(tile_x, tile_y))


## Draws one tile, following the reference DrawTile's priority order.
##
## Ladder beats wall, so a ladder passing through a platform hides the platform
## entirely rather than drawing over it. Egg and grain can never coexist with a
## wall because they overwrite it when the map is built.
func _draw_tile(tile_x: int, tile_y: int, type: int) -> void:
	if type == LevelMap.TILE_EMPTY:
		return
	var origin := tile_origin(tile_x, tile_y)
	if type & LevelMap.TILE_LADDER:
		draw_texture(LADDER_TEXTURE, origin + LADDER_OFFSET)
	elif type & LevelMap.TILE_WALL:
		draw_texture(PLATFORM_TEXTURE, origin + PLATFORM_OFFSET)
	elif type & LevelMap.TILE_EGG:
		draw_texture(EGG_TEXTURE, origin + EGG_OFFSET)
	elif type & LevelMap.TILE_GRAIN:
		draw_texture(GRAIN_TEXTURE, origin + GRAIN_OFFSET)
