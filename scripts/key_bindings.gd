class_name KeyBindings
extends RefCounted

## The five rebindable controls, and the screens that manage them.
##
## `select_keys` in the original prompts for them one at a time — up, down,
## left, right, jump — and stores whatever key is pressed. `draw_key_selection`
## renders the same five with their current bindings as one of the title
## carousel's screens.
##
## The original's own defaults are negative INKEY codes: jump &9D (-99, which is
## SPACE), up &BE, down &9E, left &99, right &98. Only jump carries across.
## CLAUDE.md sets the arrow keys for movement, a deliberate deviation — the BBC
## had no arrow keys a 1983 game could use, so its letter defaults would be an
## odd thing to inflict on a modern player.
##
## Bindings are stored as *physical* keycodes, matching project.godot, so a
## layout that moves Z and Y keeps the key in the same place under the hand.

const SAVE_PATH := "user://keys.cfg"

## Action, prompt label, and the original's VDU_MOVE position for it. The x
## positions differ per row because it right-aligns the labels against the "
## .. " so the key names line up in a column.
const ACTIONS: Array[Dictionary] = [
	{"action": "move_up", "label": "Up .. ", "at": Vector2i(196, 700)},
	{"action": "move_down", "label": "Down .. ", "at": Vector2i(64, 620)},
	{"action": "move_left", "label": "Left .. ", "at": Vector2i(64, 540)},
	{"action": "move_right", "label": "Right .. ", "at": Vector2i(0, 460)},
	{"action": "jump", "label": "Jump .. ", "at": Vector2i(64, 380)},
]

## Keys that cannot be bound to a control, because the game reads them itself
## *while Harry is moving*.
##
## Only these two qualify. `_tick_hold` polls H every tick of PLAYING, so binding
## it to a control would freeze the game every time you used that control, and
## Escape is the other half of the Escape+H abort — as well as being the key
## selection screen's cancel, so it could never be captured as a binding anyway.
##
## Deliberate deviation: the original reserves S, K and the digits 1-4 as well,
## because its front-end reads hardwired scan codes and could be made unreachable.
## Here those keys are read only in TITLE and SELECT, which are disjoint from
## PLAYING, and the front-end is edge-triggered — so a key held from one phase
## cannot leak into the next. Freeing S is what makes WASD bindable, which is
## worth more than matching the original's constraint.
const RESERVED_KEYS: Array[int] = [KEY_H, KEY_ESCAPE]

## What each action started as, taken from project.godot so `reset` has
## somewhere to go back to.
##
## Snapshotted once, statically, because `apply` overwrites the InputMap: an
## instance built after any rebinding would otherwise read the *rebound* keys
## and treat those as the defaults, quietly making `reset` a no-op.
static var _defaults: Dictionary = {}

## action -> physical keycode.
var _bound: Dictionary = {}


func _init() -> void:
	if _defaults.is_empty():
		for entry in ACTIONS:
			var action: String = entry["action"]
			_defaults[action] = _keycode_in_map(action)
	reset()


## The physical keycode InputMap currently holds for an action, or 0.
static func _keycode_in_map(action: String) -> int:
	if not InputMap.has_action(action):
		return 0
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.physical_keycode
	return 0


## Every action back to its project.godot default.
func reset() -> void:
	_bound = _defaults.duplicate()
	apply()


func keycode_for(action: String) -> int:
	return _bound.get(action, 0)


## The action currently using a key, or "" if none does.
func action_using(keycode: int) -> String:
	for action in _bound:
		if _bound[action] == keycode:
			return action
	return ""


## How the key prints on the KEYS screen. The original looks the code up in the
## OS's key-code-to-ASCII table and has spelled-out names for Tab and Escape;
## Godot's own naming covers the same ground, so it is used as-is.
##
## Translated to the user's layout, so a French keyboard shows A where a US one
## shows Q, which is what is actually printed on the key they press.
func label_for(action: String) -> String:
	var physical := keycode_for(action)
	if physical == 0:
		return "?"
	var local := DisplayServer.keyboard_get_keycode_from_physical(physical)
	return OS.get_keycode_string(local if local != 0 else physical)


## Rejects the keys the front-end needs for itself. Rebinding is otherwise
## unconstrained — in particular a key already in use is accepted; see `bind`.
func can_bind(keycode: int) -> bool:
	return keycode != 0 and keycode not in RESERVED_KEYS


## Binds a key to an action.
##
## Duplicates are allowed, deliberately. `select_keys` stores each scan code
## straight into `key_up`..`key_jump` with no comparison against the others, so
## binding Up and Jump to the same key leaves both firing off it, and nothing
## warns you. Detecting the clash here would be kinder but would be our
## invention; `action_using` is provided for anything that wants to spot one.
func bind(action: String, keycode: int) -> void:
	if not can_bind(keycode):
		return
	_bound[action] = keycode
	apply()


## Pushes the bindings into InputMap, which is what the game actually reads
## through `Input.is_action_pressed`.
##
## Only the *key* events are replaced. The gamepad events declared in
## project.godot live on these same actions, and a blanket `action_erase_events`
## would take them with it — silently, on every launch, since `_init` and
## `load_saved` both call this before the player touches anything.
func apply() -> void:
	for action in _bound:
		if not InputMap.has_action(action):
			continue
		for existing in InputMap.action_get_events(action):
			if existing is InputEventKey:
				InputMap.action_erase_event(action, existing)
		var event := InputEventKey.new()
		event.physical_keycode = _bound[action]
		InputMap.action_add_event(action, event)


func save() -> void:
	var file := ConfigFile.new()
	for action in _bound:
		file.set_value("keys", action, _bound[action])
	file.save(SAVE_PATH)


## Reads saved bindings, keeping the defaults if there is no file or it is
## malformed. A key that has since become reserved is dropped rather than
## honoured, so a stale file cannot strand the player on the title screen.
func load_saved() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return
	for entry in ACTIONS:
		var action: String = entry["action"]
		# has_section_key first: get_value's default is only consulted when it
		# is non-null, so a missing entry would otherwise log an error per key.
		if not file.has_section_key("keys", action):
			continue
		var value: Variant = file.get_value("keys", action)
		if typeof(value) != TYPE_INT:
			continue
		if can_bind(int(value)):
			_bound[action] = int(value)
	apply()
