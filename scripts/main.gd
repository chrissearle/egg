extends Node2D

## The game shell: title, player selection, play, and the sequences between.
##
## The original supports one to four players taking alternate turns, each with
## their own score, lives, bonus and collected eggs. On losing a life a player
## hands over to the next one still alive; on losing their last, they see their
## own GAME OVER and drop out while the others carry on.

## Emitted after the remaining bonus has been converted to score.
signal level_completed(level_index: int)

## Emitted when a level is entered, whether fresh or after a lost life.
signal level_started(level_index: int, restarted: bool)

## Emitted on each death, with the lives left afterwards.
signal life_lost(lives_remaining: int)

## Emitted when a player loses their last life, with their 1-based number.
signal player_finished(player_number: int)

## Emitted once every player is out.
signal game_over

## The phases the game moves through. Everything except PLAYING is a timed or
## input-gated pause.
enum Phase { TITLE, SELECT, KEY_SELECT, READY, PLAYING, DYING, BONUS, FAREWELL, NAME_ENTRY }

## Seconds per logic tick.
##
## Taken from the reference implementation, which paces its loop with
## `next_time += 30` in sdl-input.c — about 33 Hz, not the 50 Hz the BBC's vsync
## might suggest. All the movement constants are tuned against this rate, so
## changing it changes how the whole game feels.
const TICK_SECONDS := 0.03

## Ceiling on catch-up ticks per frame, so a stall cannot spiral.
const MAX_TICKS_PER_FRAME := 5

const LAYOUT_COUNT := 8

## Hen slots per level. The level data always stores five spawn tiles even when
## fewer hens are in play.
const HEN_SLOTS := 5

## Round 2 (levels 8-15) has no hens at all; from level 24 every level has all
## five, regardless of the count in the level data.
const NO_HEN_ROUND := 1
const ALL_HENS_LEVEL := 24

## The mother duck is released from level 9 (index 8) and never caged again:
## the reference is a plain `have_big_duck = current_level > 7`.
const DUCK_LEVEL := 8

## Half-width and vertical span of the hen/Harry overlap box, in BBC units.
##
## The original writes these as unsigned range tricks in CollisionDetect:
## `(duck.x - player_x) + 5 < 0x0b` and `(duck.y - 1) - player_y + 0xe < 0x1d`.
## The box is not symmetric vertically — a hen counts as touching Harry from
## further above than below.
const HEN_HIT_X := 5
const HEN_HIT_Y_MIN := -13
const HEN_HIT_Y_MAX := 15

## Beep pitches per player state, from MakeSound. Jump sweeps up until `fall`
## reaches JUMP_PITCH_TURN and back down after; falling descends without a floor,
## so a long drop drops in pitch further.
const PITCH_WALK := 64
const PITCH_CLIMB := 96
const PITCH_LIFT := 0x64
const JUMP_PITCH_UP := 0x96
const JUMP_PITCH_DOWN := 0xBE
const JUMP_PITCH_TURN := 0x0B
const FALL_PITCH := 0x6E

## Bonus units converted per tick at the end of a level.
##
## The original's loop is unthrottled — it has no `wait_for_interval_timer` — so
## a full bonus converts far faster than 33 Hz can show. Five steps per tick is
## the closest even approximation: the tick sound fires every fifth unit, so
## this lands exactly one sound per tick, evenly spaced.
const BONUS_STEPS_PER_TICK := 5

## The tick sound fires when the bonus's **units** digit is 0 or 5 — every fifth
## unit, which the original labels `fifty_divides_bonus` because the displayed
## bonus is ten times the internal counter.
##
## Two traps here. pbrook's C reads `timer_ticks[3]`, off the end of a
## three-element array. And the disassembly's `bonus_1` is not index 1: its
## variables run `bonus_3`, `bonus_2`, `bonus_1` from &3A upward, and
## `decrement_bonus` starts at the highest address, so `bonus_1` is the least
## significant digit. Reading it as the tens digit makes the ticks come in
## spurts of ten with long gaps, instead of an even stream.
const BONUS_SOUND_DIGITS: Array[int] = [0, 5]
const BONUS_UNITS_DIGIT := 2

## The "Get Ready" pause before each life. The original's `sleep(&14)` is a busy
## wait of about 3.3 seconds on a 2 MHz 6502.
const READY_SECONDS := 3.3

## VDU_MOVE positions from the original's messages, in BBC graphics units.
const READY_AT := Vector2i(352, 500)
const PLAYER_AT := Vector2i(384, 400)

## The most players the original allows.
const MAX_PLAYERS := 4

## How long each message holds, in seconds. The original sleeps &0a then &05
## across the game-over sequence, on the same scale as the &14 Get Ready.
const FAREWELL_SECONDS := 2.2

## VDU_MOVE positions for the front-end messages, in BBC graphics units.
const START_AT := Vector2i(128, 100)
const KEYS_AT := Vector2i(128, 50)
const HOW_MANY_AT := Vector2i(32, 500)

## The player-count row, one 80-unit line below the question — the same step the
## key selection screen uses between its prompts. "1  2  3  4" is ten cells, so
## x = 320 centres it in the 1280-unit width.
const COUNT_ROW_AT := Vector2i(320, 420)

## msg_key_selection's two header lines, spaced out letter by letter as the
## original spells them.
const KEY_HEADER_AT := Vector2i(480, 950)
const KEY_SUBHEADER_AT := Vector2i(96, 850)
const KEY_HEADER := "K E Y"
const KEY_SUBHEADER := "S E L E C T I O N"

## msg_standard_keys — the two controls that are not rebindable.
const HOLD_AT := Vector2i(64, 280)
const ABORT_AT := Vector2i(0, 200)
const HOLD_TEXT := "Hold .. 'H'"
const ABORT_TEXT := "Abort .. Escape +'H'"
const TITLE_AT := Vector2i(352, 700)

## High score screen, from msg_highscores and draw_highscores. The heading sits
## at (288, 800); each entry is one line from x = 32, starting at y = 704 and
## stepping down 48 graphics units, which is 12 screen rows.
const HIGH_SCORES_AT := Vector2i(288, 800)
const HIGH_SCORE_X := 32
const HIGH_SCORE_FIRST_Y := 704
const HIGH_SCORE_STEP_Y := 48

## Characters the name prompt accepts, from the OSWORD 0 block: space to 0x7f.
## The upper bound is one below the original's, because 0x7f is the OS font's
## block character and nothing here needs it.
const NAME_FIRST_CHAR := 0x20
const NAME_LAST_CHAR := 0x7E

## Name entry, from msg_enter_your_name.
const ENTER_NAME_AT := Vector2i(160, 160)
const ENTER_WHO_AT := Vector2i(384, 100)
const NAME_INPUT_AT := Vector2i(160, 60)

## The cage is drawn open once the duck is loose. Cage.aseprite is the *open*
## cage — CageClosed comes from the ROM, since the art has no closed version.
const CAGE_OPEN: Texture2D = preload("res://assets/generated/Cage.png")
const CAGE_CLOSED: Texture2D = preload("res://assets/generated/CageClosed.png")

## Which level to start on. Levels are 0-indexed internally, so 0 is displayed
## level 1, and the layout used is always current_level % 8.
@export var starting_level: int = 0

var current_level := 0
var state := PlayerState.new()
var clock := LevelClock.new()

## Phase the game is in.
var phase: Phase = Phase.TITLE

## One state per player in the game, and whose turn it is.
var players: Array[PlayerState] = []
var current_player := 0

## The high score table, persisted between runs.
var scores := HighScores.new()
var keys := KeyBindings.new()

## Which of KeyBindings.ACTIONS the key selection screen is waiting on.
var _key_index := 0

## How many players the select screen is currently offering. The keyboard
## answers with a digit and never touches this; a pad nudges it and confirms.
var _select_count := 1

## Press-edges for the front-end screens. The actions carry the pad's d-pad and
## stick as well as the keyboard, so all three arrive as one edge; K and the
## digits are raw keys because they are not controls and never will be.
var _front := FrontEndInput.new(
	PackedStringArray(["front_start", "move_left", "move_right", "jump"]),
	[KEY_K, KEY_1, KEY_2, KEY_3, KEY_4] as Array[int],
)

## Whether H has stopped the game. See `_tick_hold`.
var _held := false

var _map := LevelMap.new()
var _random := BbcRandom.new()
var _hens: Array[Hen] = []
var _accumulator := 0.0
var _farewell_ticks := 0

## The entry being named, and what has been typed so far.
var _naming := -1
var _typed := ""
## Ticks left of the death pause. The original halts here too, not by an
## explicit delay but because play_tune queues its notes without the flush bit
## and blocks once the BBC's sound buffer fills.
var _death_ticks := 0

## Ticks left of the "Get Ready" pause that opens each life.
var _ready_ticks := 0

@onready var _playfield: Playfield = $Playfield
@onready var _player: Player = $Player
@onready var _hen_root: Node2D = $Hens
@onready var _hud: Hud = $Hud
@onready var _lift: Lift = $Lift
@onready var _sfx: Sfx = $Sfx
@onready var _message: Message = $Message
@onready var _cage: Sprite2D = $Cage
@onready var _duck: MotherDuck = $MotherDuck
@onready var _banner: Banner = $Banner
@onready var _reporter: ScoreReporter = $ScoreReporter


func _ready() -> void:
	_player.egg_collected.connect(_on_egg_collected)
	_player.grain_collected.connect(_on_grain_collected)
	scores.load_saved()
	keys.load_saved()
	show_title()


## Feeds the front-end's edge sampler the press *events*, so a tap too short to
## fall on a tick is not lost. See FrontEndInput; the polling half of that pair
## happens in `_tick`.
func _unhandled_input(event: InputEvent) -> void:
	_front.note_press(event)


## Name entry is the one place the game reads typed characters rather than
## polling held keys.
func _unhandled_key_input(event: InputEvent) -> void:
	if phase != Phase.NAME_ENTRY and phase != Phase.KEY_SELECT:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if phase == Phase.KEY_SELECT:
		# Echoes are the OS repeating a held key. Name entry wants them — that
		# is how holding a letter repeats it, on the BBC too — but binding does
		# not: one held key would otherwise answer every remaining prompt with
		# itself before you let go.
		if not key.echo:
			_capture_key(key.physical_keycode)
		return
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_finish_naming()
		return
	if key.keycode == KEY_BACKSPACE:
		_typed = _typed.substr(0, maxi(0, _typed.length() - 1))
		_show_name_entry()
		return
	# The original's OSWORD 0 block accepts anything from space to 0x7f, and its
	# buffer holds eight characters. The font covers the same range, so names
	# can be mixed case exactly as they could on the BBC.
	if key.unicode >= NAME_FIRST_CHAR and key.unicode <= NAME_LAST_CHAR:
		if _typed.length() < HighScores.NAME_LENGTH:
			_typed += char(key.unicode)
			_show_name_entry()


func _process(delta: float) -> void:
	_accumulator += delta
	var ticks := 0
	while _accumulator >= TICK_SECONDS and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_SECONDS
		ticks += 1
		_tick()
	# Drop any backlog beyond the catch-up ceiling rather than accumulating debt.
	if _accumulator > TICK_SECONDS * MAX_TICKS_PER_FRAME:
		_accumulator = 0.0


## The attract screen.
func show_title() -> void:
	phase = Phase.TITLE
	_hide_level()
	_banner.visible = true
	_sfx.stop_all()
	var lines: Array[Dictionary] = [
		{
			"text": "HIGH SCORES",
			"position": Message.at(HIGH_SCORES_AT.x, HIGH_SCORES_AT.y),
			"colour": Message.COLOUR_READY,
		},
	]
	for index in scores.entries.size():
		lines.append({
			"text": scores.row_text(index),
			"position": Message.at(HIGH_SCORE_X, HIGH_SCORE_FIRST_Y - index * HIGH_SCORE_STEP_Y),
			"colour": Message.COLOUR_SCORES,
		})
	# The original switches colour mid-line: the key you press is highlighted.
	lines.append({
		"position": Message.at(START_AT.x, START_AT.y),
		"segments": [
			{"text": "Press ", "colour": Message.COLOUR_READY},
			{"text": "S", "colour": Message.COLOUR_PLAYER},
			{"text": " to start", "colour": Message.COLOUR_READY},
		],
	})
	lines.append({
		"position": Message.at(KEYS_AT.x, KEYS_AT.y),
		"segments": [
			{"text": "K", "colour": Message.COLOUR_PLAYER},
			{"text": " to change keys", "colour": Message.COLOUR_READY},
		],
	})
	_message.show_lines(lines)


## The key selection screen, reached with K from the title.
##
## `select_keys` writes its header, then asks for each control in turn, storing
## whatever is pressed. The prompts appear one at a time as it goes, which is
## why they are drawn up to `_key_index` rather than all at once.
##
## Deliberate deviation: the original echoes nothing, so you get no confirmation
## of what you just bound until the carousel comes round to the KEYS screen.
## Answered prompts here show their key.
func show_key_selection() -> void:
	phase = Phase.KEY_SELECT
	_key_index = 0
	_hide_level()
	_banner.visible = false
	_draw_key_selection()


func _draw_key_selection() -> void:
	var lines: Array[Dictionary] = [
		{
			"text": KEY_HEADER,
			"position": Message.at(KEY_HEADER_AT.x, KEY_HEADER_AT.y),
			"colour": Message.COLOUR_READY,
		},
		{
			"text": KEY_SUBHEADER,
			"position": Message.at(KEY_SUBHEADER_AT.x, KEY_SUBHEADER_AT.y),
			"colour": Message.COLOUR_READY,
		},
	]
	for index in mini(_key_index + 1, KeyBindings.ACTIONS.size()):
		var entry: Dictionary = KeyBindings.ACTIONS[index]
		var at: Vector2i = entry["at"]
		# Already answered: show what it was bound to. Still waiting: the label
		# alone, highlighted so it is clear which one is being asked for.
		var answered := index < _key_index
		lines.append({
			"position": Message.at(at.x, at.y),
			"segments": [
				{"text": entry["label"], "colour": Message.COLOUR_PROMPT},
				{
					"text": keys.label_for(entry["action"]) if answered else "?",
					"colour": Message.COLOUR_SCORES if answered else Message.COLOUR_PLAYER,
				},
			],
		})
	# Deviation: these belong to the carousel's KEYS screen in the original, but
	# that screen does not exist yet and a player looking at the controls should
	# be told about the two that cannot be changed.
	for footer in [[HOLD_TEXT, HOLD_AT], [ABORT_TEXT, ABORT_AT]]:
		var at: Vector2i = footer[1]
		lines.append({
			"text": footer[0],
			"position": Message.at(at.x, at.y),
			"colour": Message.COLOUR_PROMPT,
		})
	_message.show_lines(lines)


## Takes the next binding. Reserved keys are ignored rather than accepted, so
## the prompt simply stays put until something bindable is pressed.
func _capture_key(keycode: int) -> void:
	if keycode == KEY_ESCAPE:
		show_title()
		return
	if not keys.can_bind(keycode):
		return
	keys.bind(KeyBindings.ACTIONS[_key_index]["action"], keycode)
	_key_index += 1
	if _key_index >= KeyBindings.ACTIONS.size():
		keys.save()
		show_title()
		return
	_draw_key_selection()


func show_player_select() -> void:
	phase = Phase.SELECT
	_select_count = 1
	_hide_level()
	_banner.visible = false
	_draw_player_select()


## Deliberate deviation: the original asks the question and takes a bare digit,
## with nothing on screen to say which digits it will take. A pad cannot answer
## that, so the four counts are drawn with the current one picked out — the same
## highlight the title screen uses for its S and K.
func _draw_player_select() -> void:
	var segments: Array[Dictionary] = []
	for count in range(1, MAX_PLAYERS + 1):
		segments.append({
			"text": str(count),
			"colour": (
				Message.COLOUR_PLAYER if count == _select_count else Message.COLOUR_READY
			),
		})
		if count < MAX_PLAYERS:
			segments.append({"text": "  ", "colour": Message.COLOUR_READY})
	_message.show_lines([
		{
			"text": "How many players?",
			"position": Message.at(HOW_MANY_AT.x, HOW_MANY_AT.y),
			"colour": Message.COLOUR_READY,
		},
		{
			"position": Message.at(COUNT_ROW_AT.x, COUNT_ROW_AT.y),
			"segments": segments,
		},
	])


## Starts a new game for the given number of players.
func start_game(player_count: int = 1, level_index: int = 0) -> void:
	players.clear()
	for i in clampi(player_count, 1, MAX_PLAYERS):
		players.append(PlayerState.new())
	current_player = 0
	state = players[0]
	_hud.bind(state, clock)
	load_level(level_index)
	_begin_life()


## Enters a level fresh, refilling the bonus and clearing what was collected.
## The original does this in ResetPlayer, only on advance and at game start.
func load_level(level_index: int) -> void:
	current_level = level_index
	state.reset_for_level(level_index)
	_enter_level(false)


## Builds the level and places everyone. Score, lives, bonus and the collected
## flags are untouched, so this doubles as the respawn after a lost life.
func _enter_level(restarted: bool) -> void:
	var layout_index := current_level % LAYOUT_COUNT
	var path := "res://levels/level_%d.tres" % (layout_index + 1)
	var data: LevelData = load(path)
	if data == null:
		push_error("Could not load level data at %s" % path)
		return

	_sfx.stop_all()
	_map.build_from(data, state.eggs_taken, state.grain_taken)
	_playfield.set_map(_map)
	_player.set_map(_map)
	_player.set_lift(_lift)
	_player.reset()
	_lift.setup(data.lift_x << 3, data.have_lift)
	var duck_out := current_level >= DUCK_LEVEL
	_duck.reset(duck_out)
	# The cage stands open once she is out of it.
	_cage.texture = CAGE_OPEN if duck_out else CAGE_CLOSED
	_random.reset()
	_spawn_hens(data, current_level)
	clock.reset(current_level, _hens.size())
	_hud.refresh(current_level, player_number())
	# Entering a level always means play. Callers that want a Get Ready pause
	# first — a new life or a player handover — set it afterwards. Without this
	# the phase survives from whatever ended the previous level, and coming out
	# of BONUS leaves the next level converting its own bonus immediately.
	phase = Phase.PLAYING
	level_started.emit(current_level, restarted)


## How many hens this level runs, applying the round rules over the level data.
static func hen_count_for(data: LevelData, level_index: int) -> int:
	if (level_index >> 3) == NO_HEN_ROUND:
		return 0
	if level_index >= ALL_HENS_LEVEL:
		return HEN_SLOTS
	return data.base_hen_count


func _spawn_hens(data: LevelData, level_index: int) -> void:
	for hen in _hens:
		hen.queue_free()
	_hens.clear()

	var count := hen_count_for(data, level_index)
	for i in count:
		var hen := Hen.new()
		_hen_root.add_child(hen)
		hen.grain_eaten.connect(_on_grain_eaten)
		hen.spawn(data.hen_starts[i], _map, _random)
		_hens.append(hen)


## True when any hen is overlapping Harry.
func hen_touching_player() -> bool:
	for hen in _hens:
		var dx: int = hen.x - _player.x
		if dx < -HEN_HIT_X or dx > HEN_HIT_X:
			continue
		var dy: int = hen.y - _player.y
		if dy >= HEN_HIT_Y_MIN and dy <= HEN_HIT_Y_MAX:
			return true
	return false


## True when no game is in progress: before one starts, and once the last player
## has finished. The phase carries this now, so there is no separate flag.
func is_game_over() -> bool:
	return phase == Phase.TITLE


## 1-based number of whoever is playing, for the HUD and messages.
func player_number() -> int:
	return current_player + 1


## True while any player still has lives.
func anyone_alive() -> bool:
	for p in players:
		if p.lives > 0:
			return true
	return false


func _tick() -> void:
	# Unconditionally, before the phase dispatch: see FrontEndInput. Sampling
	# only in the phases that ask would let a control held across a transition
	# read as a fresh press on the screen it lands on.
	_front.sample()
	match phase:
		Phase.TITLE:
			_tick_title()
		Phase.SELECT:
			_tick_select()
		Phase.READY:
			_tick_ready()
		Phase.DYING:
			_tick_dying()
		Phase.BONUS:
			_convert_bonus()
		Phase.FAREWELL:
			_tick_farewell()
		Phase.NAME_ENTRY, Phase.KEY_SELECT:
			pass  # both driven by _unhandled_key_input
		Phase.PLAYING:
			_tick_playing()


## The attract screen. The original cycles a banner, the high scores and the key
## bindings here; that carousel needs M12 and M13, so for now it is the prompt
## alone.
func _tick_title() -> void:
	if _front.action_pressed("front_start"):
		show_player_select()
		return
	if _front.key_pressed(KEY_K):
		show_key_selection()


## "How many players?", answered with 1 to 4.
##
## The keyboard answers directly with the digit, as the original does. A pad has
## no digits, so it nudges the count left and right and confirms with jump —
## which is why this screen has a row the original's does not.
func _tick_select() -> void:
	for count in range(1, MAX_PLAYERS + 1):
		if _front.key_pressed(KEY_0 + count):
			start_game(count, starting_level)
			return
	var moved := 0
	if _front.action_pressed("move_right"):
		moved += 1
	if _front.action_pressed("move_left"):
		moved -= 1
	if moved != 0:
		# Clamped rather than wrapped: four options read as a row, and running
		# off the end of a row should stop, not reappear at the other end.
		_select_count = clampi(_select_count + moved, 1, MAX_PLAYERS)
		_draw_player_select()
		return
	if _front.action_pressed("jump") or _front.action_pressed("front_start"):
		start_game(_select_count, starting_level)


func _tick_ready() -> void:
	_ready_ticks -= 1
	if _ready_ticks <= 0:
		_show_level()
		phase = Phase.PLAYING


func _tick_dying() -> void:
	_death_ticks -= 1
	if _death_ticks <= 0:
		_after_death()


func _tick_farewell() -> void:
	_farewell_ticks -= 1
	if _farewell_ticks <= 0:
		# check_highscore runs as each player finishes, not at the end.
		# The insert is for the local board only and may not place at all; what
		# decides the name prompt is the fixed submission bar, so a good run
		# still reaches the site once the local table has filled up.
		_naming = scores.insert(state.score)
		if state.score_value() > HighScores.SUBMIT_FLOOR:
			_typed = ""
			_show_name_entry()
			return
		_next_player()


## Prompts the finishing player for their name.
func _show_name_entry() -> void:
	phase = Phase.NAME_ENTRY
	_hide_level()
	_banner.visible = false
	_message.show_lines([
		{
			"text": "ENTER YOUR NAME",
			"position": Message.at(ENTER_NAME_AT.x, ENTER_NAME_AT.y),
			"colour": Message.COLOUR_READY,
		},
		{
			"text": "Player %d" % player_number(),
			"position": Message.at(ENTER_WHO_AT.x, ENTER_WHO_AT.y),
			"colour": Message.COLOUR_PLAYER,
		},
		{
			"text": ">" + _typed,
			"position": Message.at(NAME_INPUT_AT.x, NAME_INPUT_AT.y),
			"colour": Message.COLOUR_SCORES,
		},
	])


## Commits the name and, on the web build, sends the score to the leaderboard.
##
## This is the only place a completed name and score exist together, which is
## why it is the submission point. The reporter is fire-and-forget and does
## nothing at all on desktop, so the hand-over below is not delayed by it.
##
## `_naming` is -1 when the run cleared the submission bar without placing on
## the local board. `name_entry` ignores that, and the score comes from the
## player rather than from a table slot that may not exist. `state` is still the
## finishing player: the hand-over is the last thing this does.
func _finish_naming() -> void:
	var entered := _typed if _typed != "" else HighScores.DEFAULT_NAME
	scores.name_entry(_naming, entered)
	scores.save()
	_reporter.submit(entered, state.score_value(), current_level + 1)
	_naming = -1
	_message.clear()
	_next_player()


## Any control being pressed, which is what resumes from a hold.
func _any_control_pressed() -> bool:
	for entry in KeyBindings.ACTIONS:
		if Input.is_action_pressed(entry["action"]):
			return true
	return false


## H stops the game, as `test_keys` does. Returns true when the tick should be
## skipped, which freezes everything at once — the original simply never reaches
## update_harry, so the timer, the hens and the sound all stop with it.
##
## The resume is the original's and is easy to misread: while H is still down
## the controls are not polled at all, so releasing H comes first and a control
## key then resumes. Escape while H is held aborts to the title instead.
func _tick_hold() -> bool:
	if not _held:
		if not Input.is_physical_key_pressed(KEY_H):
			return false
		_held = true
		_sfx.stop_all()
		return true
	if Input.is_physical_key_pressed(KEY_H):
		if Input.is_physical_key_pressed(KEY_ESCAPE):
			_held = false
			show_title()
		return true
	if _any_control_pressed():
		_held = false
		return false
	return true


func _tick_playing() -> void:
	if _tick_hold():
		return
	var input_x := 0
	if Input.is_action_pressed("move_right"):
		input_x += 1
	if Input.is_action_pressed("move_left"):
		input_x -= 1

	# Positive input_y is up: the player's state is kept in BBC y-up space.
	var input_y := 0
	if Input.is_action_pressed("move_up"):
		input_y += 1
	if Input.is_action_pressed("move_down"):
		input_y -= 1

	_player.tick(input_x, input_y, Input.is_action_pressed("jump"))
	# MakeSound runs between the player and the rest in the reference, so it
	# sees the clock phase from the previous tick.
	_make_sound()
	# The lifts move every tick, unlike the hens and the timer which share the
	# eight-phase clock.
	_lift.step()
	_advance_clock()

	# The original grants earned lives from the main loop, so they arrive
	# almost immediately rather than waiting for the level to end.
	state.grant_pending_extra_lives()

	if _player.is_dead() or hen_touching_player() or _duck.touching(_player.x, _player.y):
		_lose_life()
		return

	if _map.is_complete():
		_finish_level()


## Ported from MakeSound: one beep every other tick while Harry is moving, at a
## pitch that depends on his state.
##
## Jump and fall sweep with `fall`, so the sound of a long drop differs from a
## short one. That is why nothing here is a fixed sample.
func _make_sound() -> void:
	var moved := _player.movement()
	if moved.x == 0 and moved.y == 0:
		return
	if (clock.phase() & 1) != 0:
		return

	var pitch := 0
	match _player.mode:
		Player.Mode.WALK:
			pitch = PITCH_WALK
		Player.Mode.CLIMB:
			pitch = PITCH_CLIMB
		Player.Mode.JUMP:
			# Rises through the ascent, then falls away again.
			if _player.fall >= JUMP_PITCH_TURN:
				pitch = JUMP_PITCH_DOWN - _player.fall * 2
			else:
				pitch = JUMP_PITCH_UP + _player.fall * 2
		Player.Mode.FALL:
			pitch = FALL_PITCH - _player.fall * 2
		Player.Mode.LIFT:
			# Silent while simply riding; only walking along it beeps.
			if moved.x == 0:
				return
			pitch = PITCH_LIFT
	_sfx.beep(pitch)


## Opens a life with the "Get Ready" screen, as the original does before every
## life and every player switch — but not between levels, which re-enter the
## level loop further down.
##
## The message clears the screen: the original's msg_get_ready begins with a
## VDU_CLG and the level is only drawn once the pause ends.
func _begin_life() -> void:
	phase = Phase.READY
	_ready_ticks = maxi(1, ceili(READY_SECONDS / TICK_SECONDS))
	_hide_level()
	_message.show_lines([
		{
			"text": "Get Ready",
			"position": Message.at(READY_AT.x, READY_AT.y),
			"colour": Message.COLOUR_READY,
		},
		{
			"text": "Player %d" % player_number(),
			"position": Message.at(PLAYER_AT.x, PLAYER_AT.y),
			"colour": Message.COLOUR_PLAYER,
		},
	])


func _hide_level() -> void:
	_playfield.visible = false
	_player.visible = false
	_hen_root.visible = false
	_lift.visible = false
	_cage.visible = false
	_duck.visible = false
	_banner.visible = false
	# The original clears the whole screen for these: the carousel opens with a
	# VDU 16, and msg_get_ready with a plain VDU_CLG. The HUD is redrawn by
	# RenderBackground when the level comes back.
	_hud.visible = false


func _show_level() -> void:
	_message.clear()
	_playfield.visible = true
	_player.visible = true
	_hen_root.visible = true
	_lift.visible = true
	_cage.visible = true
	_duck.visible = true
	_hud.visible = true


## Runs one phase of the non-player cycle: a hen step, the countdown, or the
## mother duck's turn.
func _advance_clock() -> void:
	match clock.advance():
		LevelClock.Phase.HEN:
			if clock.hen_index < _hens.size():
				_hens[clock.hen_index].step()
		LevelClock.Phase.TIMER:
			_count_down()
		LevelClock.Phase.MOTHER_DUCK:
			_duck.step(_player.x, _player.y)
		LevelClock.Phase.IDLE:
			pass


func _count_down() -> void:
	var drop_bonus: Array[bool] = [false]
	if clock.count_down(drop_bonus):
		# Running out of time costs a life. The reference calls abort() here,
		# just before the is_dead++ that should handle it — an unfinished path.
		_lose_life()
		return
	_hud.queue_redraw()
	if drop_bonus[0]:
		state.reduce_bonus()


## Takes a life and restarts the level, or ends the game.
##
## The level is rebuilt but the player's state is not reset: eggs and grain
## already collected stay collected and the bonus keeps its depleted value.
## Only the timer refills, because the original reloads it every LoadLevel.
func _lose_life() -> void:
	phase = Phase.DYING
	_sfx.stop_all()
	_sfx.play_die()
	# Hold everything still until the tune finishes, then hand over.
	_death_ticks = maxi(1, ceili(_sfx.die_seconds() / TICK_SECONDS))


## Runs once the death tune has finished playing.
##
## The life is taken here rather than at the moment of death, because that is
## the order in `.harry_died`: play_tune first, then DEC player_lives. Nothing
## redraws the HUD in between, and the next screen opens with a CLG, so the
## marker never visibly pops off — it is simply one fewer when the level comes
## back. Decrementing on impact makes a hat vanish under Harry's corpse.
##
## A player who still has lives simply hands over to the next; one who has just
## lost their last sees their own GAME OVER first, and the others carry on.
func _after_death() -> void:
	state.lives -= 1
	life_lost.emit(state.lives)
	if state.lives > 0:
		_next_player()
		return
	_say_farewell()


## "GAME OVER / Player N", for the player who has just run out.
func _say_farewell() -> void:
	phase = Phase.FAREWELL
	_farewell_ticks = maxi(1, ceili(FAREWELL_SECONDS / TICK_SECONDS))
	player_finished.emit(player_number())
	_hide_level()
	_message.show_lines([
		{
			"text": "GAME OVER",
			"position": Message.at(READY_AT.x, READY_AT.y),
			"colour": Message.COLOUR_PLAYER,
		},
		{
			"text": "Player %d" % player_number(),
			"position": Message.at(PLAYER_AT.x, PLAYER_AT.y),
			"colour": Message.COLOUR_PLAYER,
		},
	])


## Hands over to the next player with lives left, or ends the game.
##
## The original walks round with `(player + 1) & 3`, skipping anyone past the
## player count or already out.
func _next_player() -> void:
	if not anyone_alive():
		_message.clear()
		game_over.emit()
		show_title()
		return

	var next := current_player
	for i in MAX_PLAYERS:
		next = (next + 1) % MAX_PLAYERS
		if next < players.size() and players[next].lives > 0:
			break
	current_player = next
	state = players[current_player]
	_hud.bind(state, clock)
	_enter_level(true)
	_begin_life()


## Ends the level. The bonus is then converted a few units per tick by
## _convert_bonus, rather than all at once.
func _finish_level() -> void:
	phase = Phase.BONUS
	_sfx.stop_all()


## Turns remaining bonus into score, a few units at a time.
func _convert_bonus() -> void:
	var sound := false
	for i in BONUS_STEPS_PER_TICK:
		if not state.award_bonus_step():
			_after_bonus()
			return
		state.grant_pending_extra_lives()
		if state.bonus[BONUS_UNITS_DIGIT] in BONUS_SOUND_DIGITS:
			sound = true
	if sound:
		_sfx.play_bonus_tick()
	_hud.queue_redraw()


## Once the bonus is spent, move to the next level.
func _after_bonus() -> void:
	level_completed.emit(current_level)
	load_level(current_level + 1)


func _on_egg_collected(index: int) -> void:
	state.collect_egg(index, current_level)
	_sfx.play_egg()
	_playfield.queue_redraw()
	_hud.queue_redraw()


func _on_grain_collected(index: int) -> void:
	state.collect_grain(index)
	_sfx.play_grain()
	clock.hold_for_grain()
	_playfield.queue_redraw()
	_hud.queue_redraw()


## A hen ate a grain. It stays eaten, but scores nothing and does not pause the
## countdown — only Harry collecting it does that.
func _on_grain_eaten(index: int) -> void:
	if index < state.grain_taken.size():
		state.grain_taken[index] = 1
	_playfield.queue_redraw()
