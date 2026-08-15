class_name HighScores
extends RefCounted

## The high score table.
##
## The reference implementation leaves this as a `/* Highscores. */` comment, so
## the behaviour comes from the annotated BBC disassembly instead:
## `init_highscores`, `compare_highscores`, `shift_highscores` and
## `check_highscore`.
##
## Ten entries of sixteen bytes each — eight score digits then an eight
## character name. The table ships filled with "A&F" scoring 1000, which is the
## publisher's own initials.
##
## Scores are compared digit by digit from the most significant, and a score
## ties *downward*: it has to beat an entry outright to take its place, so
## equalling the table changes nothing.
##
## The table is *this browser's board for today* — it is stamped with the local
## calendar date and starts over when that changes. The site holds the permanent
## record, with its own 24 hour, 7 day, 30 day and all time windows.
##
## The table deliberately has no say in what reaches the site. It only ever
## ratchets upward, so gating submission on it would silence the players with
## the most to record; SUBMIT_FLOOR is the fixed bar instead.

const ENTRY_COUNT := 10
const SCORE_DIGITS := 8
const NAME_LENGTH := 8

## What the table holds before anyone plays. `init_highscores` writes 'A', '&',
## 'F' then spaces, and a score of 1000.
const DEFAULT_NAME := "A&F"
const DEFAULT_SCORE_DIGIT := 4
const DEFAULT_SCORE_VALUE := 1

## What a shipped entry is worth, and the permanent bar for submitting to the
## site's leaderboard. Beating "A&F" is what the original asks of you, and it is
## the same ask on a fresh browser and on one with a full table.
const SUBMIT_FLOOR := 1000

const SAVE_PATH := "user://highscores.cfg"

## Entries, best first. Each is {score: PackedByteArray, name: String}.
var entries: Array[Dictionary] = []


func _init() -> void:
	reset()


## Fills the table with the shipped defaults.
func reset() -> void:
	entries.clear()
	for i in ENTRY_COUNT:
		var digits := PackedByteArray()
		digits.resize(SCORE_DIGITS)
		digits[DEFAULT_SCORE_DIGIT] = DEFAULT_SCORE_VALUE
		entries.append({"score": digits, "name": DEFAULT_NAME})


## Where a score would land, or -1 if it does not make the table.
##
## Walks from the top, taking the first entry the score beats outright.
func placing(score: PackedByteArray) -> int:
	for index in entries.size():
		var theirs: PackedByteArray = entries[index]["score"]
		for digit in SCORE_DIGITS:
			if theirs[digit] < score[digit]:
				return index
			if theirs[digit] > score[digit]:
				break
	return -1


## Inserts a score, pushing the rest down and dropping the last. Returns the
## position taken, or -1 if it did not qualify.
func insert(score: PackedByteArray) -> int:
	var index := placing(score)
	if index < 0:
		return -1
	entries.insert(index, {"score": score.duplicate(), "name": ""})
	entries.resize(ENTRY_COUNT)
	return index


## Sets the name on an entry, trimmed to what the table holds.
func name_entry(index: int, value: String) -> void:
	if index < 0 or index >= entries.size():
		return
	entries[index]["name"] = value.substr(0, NAME_LENGTH)


func score_text(index: int) -> String:
	var text := ""
	for digit in entries[index]["score"]:
		text += str(digit)
	return text


## One line of the table as the original writes it: a two-character rank, the
## score with leading zeros blanked out, a space, then the name.
##
## `draw_highscores` emits all of this as one run of characters from a single
## move, rather than positioning columns separately.
func row_text(index: int) -> String:
	var rank := index + 1
	var text := ("%2d" % rank) if rank < ENTRY_COUNT else str(rank)

	var seen := false
	for digit in entries[index]["score"]:
		if digit == 0 and not seen:
			text += " "
		else:
			seen = true
			text += str(digit)

	return text + " " + entries[index]["name"]


func score_value(index: int) -> int:
	var total := 0
	for digit in entries[index]["score"]:
		total = total * 10 + digit
	return total


## Which day a saved table belongs to, as the player's own local calendar date.
##
## `get_datetime_dict_from_system` is local unless asked for UTC, which is what
## we want: the board turning over at the player's midnight rather than at
## someone else's is the whole point.
func _period_id() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [now["year"], now["month"], now["day"]]


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("meta", "period", _period_id())
	for index in entries.size():
		file.set_value("scores", "name_%d" % index, entries[index]["name"])
		file.set_value("scores", "score_%d" % index, Array(entries[index]["score"]))
	file.save(SAVE_PATH)


## Reads the saved table, leaving the defaults in place if there is none, it is
## from an earlier day, or it is malformed.
##
## The day is only checked here, and this runs once at startup, so a session
## left open across midnight keeps the board it has been playing against. That
## is deliberate — nothing should wipe the table out from under a player
## mid-game.
func load_saved() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return
	if file.get_value("meta", "period", "") != _period_id():
		return
	var restored: Array[Dictionary] = []
	for index in ENTRY_COUNT:
		var raw = file.get_value("scores", "score_%d" % index, null)
		var who = file.get_value("scores", "name_%d" % index, null)
		if raw == null or who == null or raw.size() != SCORE_DIGITS:
			return
		var digits := PackedByteArray()
		for value in raw:
			digits.append(clampi(int(value), 0, 9))
		restored.append({"score": digits, "name": str(who)})
	entries = restored
