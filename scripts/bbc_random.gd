class_name BbcRandom
extends RefCounted

## The original's pseudo-random generator, ported from FrobRandom.
##
## Deliberately not Godot's RandomNumberGenerator: the seed is fixed and reset
## at the start of every level, so hen behaviour is completely reproducible.
## That is a property worth keeping — it makes the hens testable, and it is what
## the original does.

const SEED_HIGH := 0x767676
const SEED_LOW := 0x76

const HIGH_MASK := 0xFFFFFFFF
const LOW_MASK := 0xFF

var _high := SEED_HIGH
var _low := SEED_LOW


func _init() -> void:
	reset()


## Restores the fixed seed. Called at the start of each level, as SetupLevel does.
func reset() -> void:
	_high = SEED_HIGH
	_low = SEED_LOW


## Advances the generator and returns the low byte.
##
## `_high` is 32-bit and `_low` is 8-bit in the original, and `_low` is updated
## from the already-shifted `_high`, so the order and the masking both matter.
func next() -> int:
	var carry := 1 if ((((_low & 0x48) + 0x38) & 0x40) != 0) else 0
	_high = ((_high << 1) | carry) & HIGH_MASK
	_low = ((_low << 1) | ((_high >> 24) & 1)) & LOW_MASK
	return _low
