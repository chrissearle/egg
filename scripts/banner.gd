class_name Banner
extends Node2D

## The CHUCKIE EGG title logo.
##
## Ported from `draw_chuckie_banner`, which places ten letter sprites at fixed
## wide-pixel columns along a single row. The letters are ROM artwork with no
## Aseprite source — see tools/rom_banner_to_png.py.

## Row the whole banner sits on, y-up.
const ROW := 0xF0
const TOP_ROW := 255

## Letter and column for each of the ten sprites, in draw order. The wider gap
## before the eighth is the space in "CHUCKIE EGG".
const LETTERS := ["C", "H", "U", "C", "K", "I", "E", "E", "G", "G"]
const COLUMNS := [0x02, 0x11, 0x20, 0x2F, 0x3E, 0x4D, 0x5C, 0x72, 0x81, 0x90]

const GLYPH_DIR := "res://assets/generated/banner/"

var _glyphs: Dictionary = {}


func _ready() -> void:
	for letter in LETTERS:
		if not _glyphs.has(letter):
			_glyphs[letter] = load(GLYPH_DIR + letter + ".png")
	queue_redraw()


func _draw() -> void:
	for index in LETTERS.size():
		var glyph: Texture2D = _glyphs.get(LETTERS[index])
		if glyph == null:
			continue
		draw_texture(glyph, Vector2(COLUMNS[index] * 2, TOP_ROW - ROW))
