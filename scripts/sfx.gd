class_name Sfx
extends Node

## Sound effects, synthesised rather than sampled.
##
## Every sound comes from BbcSound, which reproduces the BBC's own sound chip
## from the original's parameters. There are no audio assets: the movement beep
## changes pitch every tick, so there is nothing fixed to record.
##
## The reference emits a beep every *other* tick while Harry moves, at a pitch
## that depends on his state — walk 64, climb 96, a jump sweeping up then down,
## a fall descending as it lengthens. Main ports that gating; this class only
## renders and plays what it is told.

## Beeps are short and fire constantly, so their streams are cached by pitch
## rather than rebuilt each time.
var _beeps: Dictionary = {}

var _beep_player: AudioStreamPlayer = null
var _pickup: AudioStreamPlayer = null
var _death: AudioStreamPlayer = null

var _egg: AudioStreamWAV = null
var _grain: AudioStreamWAV = null
var _bonus: AudioStreamWAV = null
var _die: AudioStreamWAV = null


func _ready() -> void:
	# Movement beeps retrigger constantly and must cut each other off.
	_beep_player = AudioStreamPlayer.new()
	add_child(_beep_player)
	# Pickups get their own player so a beep cannot swallow them.
	_pickup = AudioStreamPlayer.new()
	add_child(_pickup)
	# The death tune outlives the level teardown, so nothing else touches it.
	_death = AudioStreamPlayer.new()
	add_child(_death)

	_egg = BbcSound.squidge_stream(BbcSound.SQUIDGE_EGG_PITCH)
	_grain = BbcSound.squidge_stream(BbcSound.SQUIDGE_GRAIN_PITCH)
	_bonus = BbcSound.bonus_stream()
	_die = BbcSound.death_stream()


## One movement beep at the given BBC pitch.
func beep(pitch: int) -> void:
	var key := clampi(pitch, 0, BbcSound.MAX_PITCH)
	if not _beeps.has(key):
		_beeps[key] = BbcSound.beep_stream(key)
	_beep_player.stream = _beeps[key]
	_beep_player.play()


func play_egg() -> void:
	_pickup.stream = _egg
	_pickup.play()


func play_grain() -> void:
	_pickup.stream = _grain
	_pickup.play()


## One step of the end-of-level bonus countdown. Wired up in M9, once that
## countdown is animated rather than resolving in a single frame.
func play_bonus_tick() -> void:
	_pickup.stream = _bonus
	_pickup.play()


## The death tune. Deliberately not cut by stop_all, so it plays across the
## level teardown that follows a lost life.
func play_die() -> void:
	_death.stream = _die
	_death.play()


## How long the death tune runs, so the game can hold still for it.
func die_seconds() -> float:
	return _die.get_length() if _die != null else 0.0


## Silences the gameplay sounds, for a death or a level change. The death tune
## is left alone on purpose — it is meant to carry over the respawn.
func stop_all() -> void:
	_beep_player.stop()
	_pickup.stop()
