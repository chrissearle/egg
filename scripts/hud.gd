class_name Hud
extends Node2D

## The status display above the play area.
##
## Occupies viewport rows 0-55; the playfield starts at row 56. Every position
## here comes from DrawHUD, DrawLives, DrawBonus and DrawTimer in the
## reference's raster_4bit.c, converted from its y-up wide-pixel space.
##
## The original composites with XOR (`*dest ^= color` in Do_RenderSprite), into a
## framebuffer of colour-plane bits. That is not decoration: the labels are
## inverse-video — a filled bar with the lettering knocked out — and the digits
## drawn over them XOR back to black, giving dark text on a magenta bar. Drawing
## the glyphs as ordinary sprites paints magenta on magenta and the numbers
## vanish, so this reproduces the XOR compositing rather than working around it.
##
## Everything is composited into one image and drawn in a single call. The
## original redraws individual digits as they change; repainting the lot on any
## change is simpler and indistinguishable at this size.

## Screen row for a given BBC y, matching Do_RenderSprite's `y ^ 0xff`.
const TOP_ROW := 255

## Rows the two HUD lines sit on, in BBC y-up coordinates.
const ROW_LABEL_TOP := 0xF8
const ROW_SCORE := 0xF7
const ROW_LIVES := 0xEE
const ROW_LABEL_BOTTOM := 0xE8
const ROW_VALUES := 0xE7

## Horizontal starts, in BBC wide-pixels.
const X_PLAYER_BLOCK := 0x1B
const X_PLAYER_STRIDE := 0x22
const X_LEVEL_LABEL := 0x24
const X_LEVEL_UNITS := 0x45
const X_LEVEL_TENS := 0x40
const X_LEVEL_HUNDREDS := 0x3B
const X_BONUS_LABEL := 0x4E
const X_BONUS_DIGITS := 0x66
const X_TIME_LABEL := 0x7E
const X_TIME_DIGITS := 0x91

## Digits are spaced five wide-pixels apart; life markers four.
const DIGIT_STRIDE := 5
const LIFE_STRIDE := 4

## The score shows six digits, dropping the two most significant.
const SCORE_FIRST_DIGIT := 2
const SCORE_DIGIT_COUNT := 6

## Bonus prints its three digits plus a trailing zero, so the value on screen is
## ten times the internal counter — and equals the points it is worth.
const BONUS_DIGIT_COUNT := 3
const TIMER_DIGIT_COUNT := 3

## Most lives the display can show, and the count from which DrawLife stops
## removing the topmost marker.
const MAX_LIVES_SHOWN := 8
const LIVES_ALL_SHOWN := 9

const DIGIT_TEXTURES: Array[Texture2D] = [
	preload("res://assets/generated/hud/digit_0.png"),
	preload("res://assets/generated/hud/digit_1.png"),
	preload("res://assets/generated/hud/digit_2.png"),
	preload("res://assets/generated/hud/digit_3.png"),
	preload("res://assets/generated/hud/digit_4.png"),
	preload("res://assets/generated/hud/digit_5.png"),
	preload("res://assets/generated/hud/digit_6.png"),
	preload("res://assets/generated/hud/digit_7.png"),
	preload("res://assets/generated/hud/digit_8.png"),
	preload("res://assets/generated/hud/digit_9.png"),
]

const LABEL_SCORE: Texture2D = preload("res://assets/generated/hud/label_score.png")
const LABEL_PLAYER: Texture2D = preload("res://assets/generated/hud/label_player.png")
const LABEL_LEVEL: Texture2D = preload("res://assets/generated/hud/label_level.png")
const LABEL_BONUS: Texture2D = preload("res://assets/generated/hud/label_bonus.png")
const LABEL_TIME: Texture2D = preload("res://assets/generated/hud/label_time.png")
## An unlabelled bar; it backs the current player's score so the digits knock out.
const LABEL_BLANK: Texture2D = preload("res://assets/generated/hud/label_blank.png")
const LIFE_MARKER: Texture2D = preload("res://assets/generated/Life.png")

## Height of the HUD band, in screen rows.
const BAND_HEIGHT := 56
const BAND_WIDTH := 320

## Colour-plane bits, as raster_4bit.c uses them. XORing the same value twice
## returns a pixel to black, which is what knocks the lettering out.
const PLANE_HUD := 2
const PLANE_LIVES := 4

var _state: PlayerState = null
var _clock: LevelClock = null
var _level := 0
var _player_number := 1

var _plane := PackedByteArray()
var _image: Image = null
var _texture: ImageTexture = null
var _masks: Dictionary = {}


## Points the HUD at the values it should display.
func bind(state: PlayerState, clock: LevelClock) -> void:
	_state = state
	_clock = clock
	queue_redraw()


## Updates the level and player number, and repaints.
func refresh(level_index: int, player_number: int = 1) -> void:
	_level = level_index
	_player_number = player_number
	queue_redraw()


## Converts a BBC wide-pixel x and y-up row to a screen position.
static func at(x: int, y: int) -> Vector2:
	return Vector2(x * 2, TOP_ROW - y)


func _draw() -> void:
	if _state == null or _clock == null:
		return
	_composite()
	if _texture != null:
		draw_texture(_texture, Vector2.ZERO)


## Rebuilds the HUD image by XORing every glyph into a colour-plane buffer.
func _composite() -> void:
	if _plane.is_empty():
		_plane.resize(BAND_WIDTH * BAND_HEIGHT)
	for i in _plane.size():
		_plane[i] = 0

	_stamp(LABEL_SCORE, 0, ROW_LABEL_TOP, PLANE_HUD)
	_stamp(LABEL_PLAYER, 0, ROW_LABEL_BOTTOM, PLANE_HUD)
	_stamp(LABEL_LEVEL, X_LEVEL_LABEL, ROW_LABEL_BOTTOM, PLANE_HUD)
	_stamp(LABEL_BONUS, X_BONUS_LABEL, ROW_LABEL_BOTTOM, PLANE_HUD)
	_stamp(LABEL_TIME, X_TIME_LABEL, ROW_LABEL_BOTTOM, PLANE_HUD)
	# The blank bar sits behind the score so its digits knock out of it.
	_stamp(LABEL_BLANK, _player_origin(), ROW_LABEL_TOP, PLANE_HUD)

	_draw_score()
	_draw_lives()
	_digit(X_PLAYER_BLOCK, ROW_VALUES, _player_number)
	_draw_level()
	_draw_bonus()
	_draw_timer()

	_present()


## XORs one glyph into the plane buffer at a BBC wide-pixel position, clipping
## to the band. Only the alpha channel matters — the glyph PNGs carry a colour,
## but here they are masks.
func _stamp(texture: Texture2D, x: int, y: int, plane: int) -> void:
	if texture == null:
		return
	var mask: Dictionary = _mask_for(texture)
	var bits: PackedByteArray = mask["bits"]
	var width: int = mask["width"]
	var height: int = mask["height"]
	var origin := at(x, y)
	var left := int(origin.x)
	var top := int(origin.y)

	for row in height:
		var target_y := top + row
		if target_y < 0 or target_y >= BAND_HEIGHT:
			continue
		for column in width:
			if bits[row * width + column] == 0:
				continue
			var target_x := left + column
			if target_x < 0 or target_x >= BAND_WIDTH:
				continue
			var index := target_y * BAND_WIDTH + target_x
			_plane[index] = _plane[index] ^ plane


## Caches a glyph's set-pixel mask, so the image is only decoded once.
func _mask_for(texture: Texture2D) -> Dictionary:
	if _masks.has(texture):
		return _masks[texture]
	var image := texture.get_image()
	var width := image.get_width()
	var height := image.get_height()
	var bits := PackedByteArray()
	bits.resize(width * height)
	for row in height:
		for column in width:
			bits[row * width + column] = 1 if image.get_pixel(column, row).a > 0.0 else 0
	var mask := {"bits": bits, "width": width, "height": height}
	_masks[texture] = mask
	return mask


## Turns the colour-plane buffer into the drawable texture.
func _present() -> void:
	if _image == null:
		_image = Image.create_empty(BAND_WIDTH, BAND_HEIGHT, false, Image.FORMAT_RGBA8)
	for row in BAND_HEIGHT:
		for column in BAND_WIDTH:
			_image.set_pixel(column, row, _plane_colour(_plane[row * BAND_WIDTH + column]))
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
	else:
		_texture.update(_image)


## Maps a colour-plane value to its BBC colour. Zero is background, so it stays
## transparent rather than painting black over the screen.
static func _plane_colour(value: int) -> Color:
	match value:
		0:
			return Color(0, 0, 0, 0)
		PLANE_LIVES:
			return Color(1, 1, 0)
		_:
			return Color(1, 0, 1)


func _digit(x: int, y: int, value: int) -> void:
	if value < 0 or value > 9:
		return
	_stamp(DIGIT_TEXTURES[value], x, y, PLANE_HUD)


func _player_origin() -> int:
	return X_PLAYER_BLOCK + X_PLAYER_STRIDE * (_player_number - 1)


func _draw_score() -> void:
	var origin := _player_origin() + 1
	for i in SCORE_DIGIT_COUNT:
		_digit(origin + i * DIGIT_STRIDE, ROW_SCORE, _state.score[SCORE_FIRST_DIGIT + i])


## Life markers: one per life *in hand*, not counting the one being played.
##
## The original arrives at that indirectly. DrawLives stamps one marker per life,
## capped at eight; then StartLevel calls DrawLastLife, which XORs the marker at
## position `lives` straight back off again. So five lives shows four markers,
## and the last go shows none. DrawLife bails out at nine, so from nine lives up
## nothing is removed and eight markers stay.
func _draw_lives() -> void:
	var x := _player_origin()
	var shown := mini(_state.lives, MAX_LIVES_SHOWN)
	if _state.lives < LIVES_ALL_SHOWN:
		shown -= 1
	for i in maxi(shown, 0):
		_stamp(LIFE_MARKER, x + i * LIFE_STRIDE, ROW_LIVES, PLANE_LIVES)


## Level number, one-indexed for display. The third digit only appears past
## level 110, reproducing the original's `if (tmp > 10)` check.
func _draw_level() -> void:
	var value := _level + 1
	_digit(X_LEVEL_UNITS, ROW_VALUES, value % 10)
	# Integer division throughout: these are decimal digits, so the remainder is
	# meant to be dropped.
	@warning_ignore("integer_division")
	var rest := value / 10
	_digit(X_LEVEL_TENS, ROW_VALUES, rest % 10)
	if rest > 10:
		@warning_ignore("integer_division")
		var hundreds := rest / 10
		_digit(X_LEVEL_HUNDREDS, ROW_VALUES, hundreds)


func _draw_bonus() -> void:
	for i in BONUS_DIGIT_COUNT:
		_digit(X_BONUS_DIGITS + i * DIGIT_STRIDE, ROW_VALUES, _state.bonus[i])
	# The trailing zero is literal: the display is always a multiple of ten.
	_digit(X_BONUS_DIGITS + BONUS_DIGIT_COUNT * DIGIT_STRIDE, ROW_VALUES, 0)


func _draw_timer() -> void:
	for i in TIMER_DIGIT_COUNT:
		_digit(X_TIME_DIGITS + i * DIGIT_STRIDE, ROW_VALUES, _clock.timer[i])
