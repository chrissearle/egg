class_name Message
extends Node2D

## Full-screen text, for the messages between lives.
##
## The font is the BBC's own OS font, which is what the original's messages went
## through — see tools/yaff_to_png.py. It is an 8 x 8 character *cell*, so text
## lays out at fixed pitch: every character advances the same distance whatever
## its shape, which is what keeps the high score table's columns aligned.
##
## It covers ASCII 0x20-0x7e, so the messages can be in the original's own mixed
## case rather than shouted in capitals.
##
## Positions and colours are the original's. Its VDU_MOVE coordinates are in the
## BBC's 1280 x 1024 graphics space, which maps to the 160 x 256 wide-pixel
## screen by dividing x by 8 and y by 4, and the graphics cursor sits at the
## *bottom* of the character cell. Colours come from the game's palette_table:
## logical 4 is yellow and logical 8 is cyan.

const GLYPH_ROWS := 8

## One character cell, in BBC wide-pixels — the OS font's fixed pitch.
const CHAR_PITCH := 8

const TOP_ROW := 255

## BBC graphics units per screen pixel.
const GRAPHICS_X_SCALE := 8
const GRAPHICS_Y_SCALE := 4

const COLOUR_READY := Color(1, 1, 0)
const COLOUR_PLAYER := Color(0, 1, 1)
## The high score entries use GCOL 0,3, which palette_table maps to green.
const COLOUR_SCORES := Color(0, 1, 0)
## The key screens use GCOL 0,2, which palette_table maps to magenta — the same
## ink as the ladders and the HUD labels.
const COLOUR_PROMPT := Color(1, 0, 1)

const GLYPH_DIR := "res://assets/generated/font/"

## The printable range the font covers.
const FIRST_CODEPOINT := 0x20
const LAST_CODEPOINT := 0x7E

var _lines: Array[Dictionary] = []
var _glyphs: Dictionary = {}


func _ready() -> void:
	for code in range(FIRST_CODEPOINT, LAST_CODEPOINT + 1):
		_glyphs[char(code)] = load(GLYPH_DIR + ("u%04x.png" % code))


## Converts a BBC VDU_MOVE position to the top-left of the text in screen pixels.
static func at(graphics_x: int, graphics_y: int) -> Vector2:
	# Integer division on purpose: the BBC's graphics grid divides exactly into
	# pixels, eight units across and four down.
	@warning_ignore("integer_division")
	var wide_x := graphics_x / GRAPHICS_X_SCALE
	@warning_ignore("integer_division")
	var y_up := graphics_y / GRAPHICS_Y_SCALE
	# The graphics cursor is the baseline, so step up by the glyph height.
	return Vector2(wide_x * 2, TOP_ROW - y_up - (GLYPH_ROWS - 1))


## Replaces what is on screen. Each line is {text, position, colour}.
func show_lines(lines: Array[Dictionary]) -> void:
	_lines = lines
	visible = true
	queue_redraw()


func clear() -> void:
	_lines = []
	visible = false
	queue_redraw()


## Width of a string in screen pixels, at the fixed cell pitch.
func measure(text: String) -> int:
	return text.length() * CHAR_PITCH * 2


func _draw() -> void:
	for line in _lines:
		var origin: Vector2 = line["position"]
		var pen := origin.x
		# A line is either one coloured string, or a run of differently coloured
		# segments — the original switches GCOL mid-message, so "Press S to
		# start" is yellow with a cyan S.
		var segments: Array = line.get("segments", [{
			"text": line.get("text", ""),
			"colour": line.get("colour", Color.WHITE),
		}])
		for segment in segments:
			var colour: Color = segment["colour"]
			var text: String = segment["text"]
			for i in text.length():
				var glyph: Texture2D = _glyphs.get(text[i])
				if glyph != null:
					draw_texture(glyph, Vector2(pen, origin.y), colour)
				# Fixed pitch: every character takes a whole cell, drawn or not.
				pen += CHAR_PITCH * 2
