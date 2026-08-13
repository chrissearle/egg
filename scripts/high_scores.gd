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

const ENTRY_COUNT := 10
const SCORE_DIGITS := 8
const NAME_LENGTH := 8

## What the table holds before anyone plays. `init_highscores` writes 'A', '&',
## 'F' then spaces, and a score of 1000.
const DEFAULT_NAME := "A&F"
const DEFAULT_SCORE_DIGIT := 4
const DEFAULT_SCORE_VALUE := 1

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


func save() -> void:
	var file := ConfigFile.new()
	for index in entries.size():
		file.set_value("scores", "name_%d" % index, entries[index]["name"])
		file.set_value("scores", "score_%d" % index, Array(entries[index]["score"]))
	file.save(SAVE_PATH)


## Reads the saved table, leaving the defaults in place if there is none or it
## is malformed.
func load_saved() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
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
