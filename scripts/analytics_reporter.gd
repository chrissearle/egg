class_name AnalyticsReporter
extends Node

## Reports game events to the site's analytics.
##
## Only does anything on the web build, for the same reason as ScoreReporter:
## the desktop game is self-contained. The page's `/static/analytics.js`
## provides `window.eggTrack`, which forwards to Umami when the deployment has
## configured it and quietly drops the event otherwise — so this never needs to
## know whether analytics is on, where it lives, or whether it has loaded yet.
##
## Fire-and-forget: nothing in the game waits on it, and a missing tracker
## (blocked by an extension, say) must not cost the player anything.
##
## Levels are reported 1-based, as the score submissions are.

const TRACK_EXPRESSION := "window.eggTrack && window.eggTrack(%s, %s)"


## A new game, with how many players and the level it starts on.
func game_started(player_count: int, level: int) -> void:
	_track("game-start", {"players": player_count, "level": level})


## A level cleared, after its bonus has been counted in.
func level_completed(level: int) -> void:
	_track("level-complete", {"level": level})


## One player out of lives. In a one-player game this is the game over; with
## more, each player reports their own as they drop out.
func player_finished(player: int, player_count: int, score: int, level: int) -> void:
	_track("game-over", {
		"player": player,
		"players": player_count,
		"score": score,
		"level": level,
	})


func _track(event: String, data: Dictionary) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(TRACK_EXPRESSION % [JSON.stringify(event), JSON.stringify(data)], true)
