class_name FrontEndInput
extends RefCounted

## Press-edges for the front-end screens.
##
## The title and player-select screens are driven from `_tick`, which polls. A
## poll fires on whatever is *currently* held, so a control still down across a
## phase change — dying back to the title with jump held — would trigger the new
## screen on its very first tick. This turns those polls into edges: something
## already down when a screen opens has no edge until it is released and pressed
## again.
##
## `Input.is_action_just_pressed` cannot do this job. It is scoped to the frame,
## and `_tick` runs at 33 Hz out of a 60 Hz `_process`, so a press landing on a
## frame that happens to run no tick would never be seen at all, and one landing
## on a frame that runs two ticks could be seen twice.
##
## `sample()` must therefore run every tick in *every* phase, not just the ones
## that ask about edges. Sampling only while the title is up would record no
## previous state for the key that got you there, and the edge would fire.
##
## Actions rather than raw keycodes wherever possible: an action carries the
## gamepad events too, so the d-pad, the stick and the keyboard all arrive here
## as the same edge, with Godot applying the action's deadzone to the stick.
##
## Polling alone is not quite enough, though: a press shorter than one tick —
## about 30 ms — begins and ends between two samples and is never seen. Real
## fingers rarely manage that, but browser automation does it every time, which
## is how it was caught. `note_press` therefore latches the press *event* as
## well, and `sample` treats a latch as an edge.
##
## The two halves cover each other exactly. Polling is what makes a control held
## across a phase change produce no edge; the event latch is what stops a very
## short tap being dropped. Neither mechanism alone is correct here.

## Actions to watch, and raw physical keycodes to watch for the front-end keys
## that are not actions.
var _actions: PackedStringArray = []
var _keys: Array[int] = []

## What was down at the previous sample, and what went down at this one.
var _down: Dictionary = {}
var _edge: Dictionary = {}

## Presses seen as events since the last sample, for taps too short to poll.
var _latched: Dictionary = {}


func _init(actions: PackedStringArray, keys: Array[int]) -> void:
	_actions = actions
	_keys = keys


## Notes a press that arrived as an event, so a tap shorter than a tick is not
## lost between samples. Call from `_unhandled_input`.
##
## Key echoes are ignored: an echo is the OS repeating a key that is *already*
## held, which is exactly the case polling handles and must not produce an edge.
## Joypad *motion* is ignored too — an axis emits a stream of events while it is
## held, each of which reports the action as pressed, so latching them would run
## a menu selection from one end to the other in a single frame. A stick cannot
## be tapped for less than a tick anyway, so it loses nothing.
func note_press(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		return
	var key := event as InputEventKey
	if key != null:
		if not key.pressed or key.echo:
			return
		if key.physical_keycode in _keys:
			_latched[key.physical_keycode] = true
	for action in _actions:
		if event.is_action_pressed(action):
			_latched[action] = true


## Refreshes every tracked input. Call once per tick, unconditionally.
func sample() -> void:
	for action in _actions:
		_record(action, Input.is_action_pressed(action))
	for keycode in _keys:
		_record(keycode, Input.is_physical_key_pressed(keycode))
	_latched.clear()


func _record(key: Variant, down: bool) -> void:
	# A latched event counts as an edge even when the poll missed the press
	# entirely, which is what happens to a tap shorter than one tick.
	_edge[key] = bool(_latched.get(key, false)) or (down and not bool(_down.get(key, false)))
	_down[key] = down


## True on the tick an action went down, false while it stays down.
func action_pressed(action: String) -> bool:
	return bool(_edge.get(action, false))


## True on the tick a raw key went down, false while it stays down.
func key_pressed(keycode: int) -> bool:
	return bool(_edge.get(keycode, false))
