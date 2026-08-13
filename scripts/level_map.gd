class_name LevelMap
extends RefCounted

## The 20x25 tile grid for one level, built from a LevelData resource.
##
## Indexing deliberately matches the reference implementation's
## `levelmap[x + y * 20]`: BBC tile space, y-up, y = 0 at the bottom. Keeping
## that convention here means the ported movement code can read this map
## directly without flipping coordinates on every lookup. Conversion to Godot's
## y-down space happens once, at draw time, in Playfield.

const WIDTH := 20
const HEIGHT := 25

const TILE_EMPTY := 0
const TILE_WALL := 1
const TILE_LADDER := 2
const TILE_EGG := 4
const TILE_GRAIN := 8

## Egg and grain tiles pack their collectable index into the high nibble.
const TYPE_MASK := 0x0F
const INDEX_SHIFT := 4

var eggs_left := 0

var _tiles := PackedByteArray()


func _init() -> void:
	_tiles.resize(WIDTH * HEIGHT)


## Reads a tile, returning TILE_EMPTY for anything off the grid.
##
## Out-of-bounds reads are not a bug to guard against upstream: the original
## movement code probes neighbouring tiles at the screen edges and relies on
## them reading as empty. The reference has the same guard in Do_ReadMap.
func read_tile(x: int, y: int) -> int:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
		return TILE_EMPTY
	return _tiles[x + y * WIDTH]


func write_tile(x: int, y: int, value: int) -> void:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
		return
	_tiles[x + y * WIDTH] = value


## The tile's type bits, with any packed collectable index stripped off.
func tile_type(x: int, y: int) -> int:
	return read_tile(x, y) & TYPE_MASK


## Removes a collectable from the map and returns the tile value it had.
##
## Returns TILE_EMPTY when there was nothing to take, so callers can use the
## result as both the test and the payload. Caller-facing detail: the returned
## value still carries the packed index in its high nibble.
func take_collectable(x: int, y: int) -> int:
	var tile := read_tile(x, y)
	if (tile & (TILE_EGG | TILE_GRAIN)) == 0:
		return TILE_EMPTY
	write_tile(x, y, TILE_EMPTY)
	if (tile & TILE_EGG) != 0:
		eggs_left -= 1
	return tile


## True once every egg has been collected.
func is_complete() -> bool:
	return eggs_left == 0


## The collectable index packed into an egg or grain tile.
func tile_index(x: int, y: int) -> int:
	return read_tile(x, y) >> INDEX_SHIFT


## Populates the grid from level data.
##
## `collected_eggs` and `collected_grain` mark items this player has already
## taken; those tiles are left empty, matching how the reference re-enters a
## level after a lost life without respawning what you had picked up.
func build_from(
	data: LevelData,
	collected_eggs: PackedByteArray = PackedByteArray(),
	collected_grain: PackedByteArray = PackedByteArray()
) -> void:
	for i in _tiles.size():
		_tiles[i] = TILE_EMPTY
	eggs_left = 0

	# Walls first: plain writes, inclusive range on x.
	for wall in data.walls:
		var row := wall.x
		for column in range(wall.y, wall.z + 1):
			write_tile(column, row, TILE_WALL)

	# Ladders OR into whatever is already there, so a ladder through a platform
	# becomes TILE_WALL | TILE_LADDER rather than replacing the platform.
	for ladder in data.ladders:
		var column := ladder.x
		for row in range(ladder.y, ladder.z + 1):
			write_tile(column, row, TILE_LADDER | read_tile(column, row))

	# Eggs and grain overwrite. This is not an oversight in the original: an egg
	# sitting on a platform tile replaces the platform, and the tile is drawn as
	# an egg with no wall beneath it.
	for index in data.eggs.size():
		if index < collected_eggs.size() and collected_eggs[index] != 0:
			continue
		var egg: Vector2i = data.eggs[index]
		write_tile(egg.x, egg.y, (index << INDEX_SHIFT) | TILE_EGG)
		eggs_left += 1

	for index in data.grain.size():
		if index < collected_grain.size() and collected_grain[index] != 0:
			continue
		var grain: Vector2i = data.grain[index]
		write_tile(grain.x, grain.y, (index << INDEX_SHIFT) | TILE_GRAIN)
