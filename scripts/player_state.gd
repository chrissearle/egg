class_name PlayerState
extends RefCounted

## Per-player persistent state: score, bonus, lives, and which collectables have
## already been taken.
##
## Mirrors `playerdata_t` in the reference implementation's chuckie.c. Each
## player keeps their own copy so 2-player alternating turns (M8) can swap
## between them, and so a lost life re-enters the level without respawning the
## eggs and grain already collected.
##
## Score and bonus are held as decimal digits rather than integers because the
## original does, and the extra-life rule depends on it: a life is awarded when
## a carry propagates into the 10,000s digit, which is a property of the digit
## representation, not of the numeric value.

## Digits of the score, most significant first. Index 5 is hundreds, 6 is tens,
## 7 is units.
const SCORE_DIGITS := 8

## Digits of the bonus. Only the first three count towards it reaching zero;
## the fourth exists in the original's layout but is never part of the total.
const BONUS_DIGITS := 4
const BONUS_COUNTED_DIGITS := 3

## Score digit indices the game adds to.
const DIGIT_HUNDREDS := 5
const DIGIT_TENS := 6

## A carry reaching this digit is worth an extra life.
const DIGIT_EXTRA_LIFE := 3

## Collectable slots per level. Eggs only ever use 12, but the original sizes
## both arrays at 16.
const COLLECTABLE_SLOTS := 16

const STARTING_LIVES := 5
const MAX_STARTING_BONUS := 9
const GRAIN_SCORE_TENS := 5
const MAX_EGG_SCORE_HUNDREDS := 10

var score := PackedByteArray()
var bonus := PackedByteArray()
var eggs_taken := PackedByteArray()
var grain_taken := PackedByteArray()
var lives := STARTING_LIVES

## Extra lives earned but not yet granted. The original defers awarding until
## the end of a level rather than mid-play.
var extra_lives_pending := 0


func _init() -> void:
	score.resize(SCORE_DIGITS)
	bonus.resize(BONUS_DIGITS)
	eggs_taken.resize(COLLECTABLE_SLOTS)
	grain_taken.resize(COLLECTABLE_SLOTS)


## Prepares for a fresh level: full bonus, nothing collected.
##
## Starting bonus is `min(level + 1, 9)` in the hundreds digit, so level 1 opens
## on 200 and level 9 onwards on 900.
func reset_for_level(level_index: int) -> void:
	bonus[0] = mini(level_index + 1, MAX_STARTING_BONUS)
	for i in range(1, BONUS_DIGITS):
		bonus[i] = 0
	for i in COLLECTABLE_SLOTS:
		eggs_taken[i] = 0
		grain_taken[i] = 0


## Adds `value` at digit `digit`, propagating carries upward.
##
## `digit` is an index into `score`, so adding 1 at DIGIT_TENS is worth 10
## points. Ported directly from AddScore.
func add_score(digit: int, value: int) -> void:
	var index := digit
	var carry := value
	while index >= 0:
		# Reaching the 10,000s digit means a carry arrived there, which is what
		# earns the extra life. The check sits before the termination test in
		# the original, and the loop only reaches this digit via a carry.
		if index == DIGIT_EXTRA_LIFE:
			extra_lives_pending += 1
		carry += score[index]
		if carry < 10:
			score[index] = carry
			return
		score[index] = carry - 10
		carry = 1
		index -= 1


## Score for one egg: 100 points per (level / 4) + 1, capped at 1000.
static func egg_score_hundreds(level_index: int) -> int:
	return mini((level_index >> 2) + 1, MAX_EGG_SCORE_HUNDREDS)


func collect_egg(index: int, level_index: int) -> void:
	if index < COLLECTABLE_SLOTS:
		eggs_taken[index] = 1
	add_score(DIGIT_HUNDREDS, egg_score_hundreds(level_index))


func collect_grain(index: int) -> void:
	if index < COLLECTABLE_SLOTS:
		grain_taken[index] = 1
	add_score(DIGIT_TENS, GRAIN_SCORE_TENS)


func bonus_is_zero() -> bool:
	var total := 0
	for i in BONUS_COUNTED_DIGITS:
		total += bonus[i]
	return total == 0


## Decrements the bonus by one, borrowing across digits. Ported from ReduceBonus.
func reduce_bonus() -> void:
	var index := BONUS_COUNTED_DIGITS - 1
	while index >= 0:
		if bonus[index] > 0:
			bonus[index] -= 1
			return
		bonus[index] = 9
		index -= 1


## Converts one unit of remaining bonus into 10 points. Returns false once the
## bonus is exhausted.
##
## Kept as a single step so the end-of-level sequence can be animated later
## rather than resolving instantly.
func award_bonus_step() -> bool:
	if bonus_is_zero():
		return false
	add_score(DIGIT_TENS, 1)
	reduce_bonus()
	return true


## Grants any extra lives earned since the last call. The original defers this
## to the end of a level, hence it being separate from add_score.
func grant_pending_extra_lives() -> int:
	var granted := extra_lives_pending
	lives += granted
	extra_lives_pending = 0
	return granted


func score_value() -> int:
	var total := 0
	for digit in score:
		total = total * 10 + digit
	return total


func bonus_value() -> int:
	var total := 0
	for i in BONUS_COUNTED_DIGITS:
		total = total * 10 + bonus[i]
	return total


func score_text() -> String:
	var text := ""
	for digit in score:
		text += str(digit)
	return text
