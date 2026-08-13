class_name LevelClock
extends RefCounted

## The eight-phase cycle that paces everything except Harry.
##
## Ported from the head of MoveDucks. Each tick advances one phase:
##
##   phase 8 -> the mother duck moves (M10), and the cycle resets
##   phase 4 -> the timer counts down, and with it the bonus
##   otherwise -> one hen gets a step
##
## Which hen is chosen comes from a counter running down from `hen_interval`.
## Slots past the hen count do nothing, so a larger interval means each hen is
## picked less often — that is how hen speed is expressed, rather than by any
## per-hen speed value.

enum Phase { MOTHER_DUCK, TIMER, HEN, IDLE }

const PHASE_COUNT := 8
const TIMER_PHASE := 4

## Timer digits, most significant first.
const TIMER_DIGITS := 3

## Hens step less often below this level, so they run slower.
const HEN_INTERVAL_SLOW := 8
const HEN_INTERVAL_FAST := 5
const HEN_SPEEDUP_LEVEL := 32

## Ticks the countdown pauses for after grain is eaten.
const GRAIN_BONUS_HOLD := 14

## The bonus drops one whenever the timer's units digit reaches either of these.
const BONUS_STEP_UNITS := [0, 5]

var timer := PackedByteArray()

## Ticks remaining before the countdown resumes.
var bonus_hold := 0

## Index of the hen chosen by the most recent HEN phase.
var hen_index := 0

var _phase := 0
var _hen_slot := 0
var _hen_interval := HEN_INTERVAL_SLOW
var _hen_count := 0


func _init() -> void:
	timer.resize(TIMER_DIGITS)


## Resets for a new level. Timer starts at `9 - min(level >> 4, 8)` hundreds,
## so it runs longer on early levels and speeds up every 16.
func reset(level_index: int, hen_count: int) -> void:
	timer[0] = 9 - mini(level_index >> 4, 8)
	for i in range(1, TIMER_DIGITS):
		timer[i] = 0
	bonus_hold = 0
	hen_index = 0
	_phase = 0
	_hen_slot = 0
	_hen_count = hen_count
	_hen_interval = HEN_INTERVAL_SLOW if level_index < HEN_SPEEDUP_LEVEL else HEN_INTERVAL_FAST


## Advances one phase and reports what should happen.
##
## A HEN result leaves the chosen hen in `hen_index`; IDLE means the slot landed
## past the hens in play and nothing moves.
func advance() -> Phase:
	_phase += 1
	if _phase == PHASE_COUNT:
		_phase = 0
		return Phase.MOTHER_DUCK
	if _phase == TIMER_PHASE:
		return Phase.TIMER

	if _hen_slot == 0:
		_hen_slot = _hen_interval
	else:
		_hen_slot -= 1
	if _hen_slot >= _hen_count:
		return Phase.IDLE
	hen_index = _hen_slot
	return Phase.HEN


## Runs the countdown for a TIMER phase. Returns true if time has run out.
##
## `bonus_should_drop` is set when the bonus should also tick down, which the
## original keys off the timer's units digit reaching 0 or 5.
func count_down(bonus_should_drop: Array[bool]) -> bool:
	bonus_should_drop[0] = false
	if bonus_hold > 0:
		bonus_hold -= 1
		return false

	var index := TIMER_DIGITS - 1
	while index >= 0:
		if timer[index] > 0:
			timer[index] -= 1
			break
		timer[index] = 9
		index -= 1

	if timer_value() == 0:
		return true

	bonus_should_drop[0] = timer[TIMER_DIGITS - 1] in BONUS_STEP_UNITS
	return false


## Pauses the countdown, as collecting grain does.
func hold_for_grain() -> void:
	bonus_hold = GRAIN_BONUS_HOLD


## The current phase, 0-7. MakeSound beeps only on even phases, and reads this
## before the clock advances — hence Main calling it in that order.
func phase() -> int:
	return _phase


func timer_value() -> int:
	var total := 0
	for digit in timer:
		total = total * 10 + digit
	return total
