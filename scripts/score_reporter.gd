class_name ScoreReporter
extends Node

## Posts a finished score to the site's leaderboard.
##
## Only does anything on the web build. The desktop game is self-contained and
## has no business calling out to a server; `OS.has_feature("web")` is what
## keeps it that way, rather than a URL that happens to be unreachable.
##
## Deliberately fire-and-forget. Nothing in the game waits on the result and a
## failure is logged and dropped: the local high score table is what the game
## itself displays, so a leaderboard that is down, slow, or blocked by an
## extension must not stall the player between lives.
##
## The score's *time* is not sent. The game records none, and one supplied here
## would be trivially editable — the server stamps arrivals with its own clock.

signal submitted(ok: bool)

const ENDPOINT := "/api/scores"

## Read from the page rather than configured, so the same build works on
## localhost and on the real host, and so the request is always same-origin —
## which is why there is no CORS handling on the server.
const ORIGIN_EXPRESSION := "window.location.origin"


func submit(player_name: String, score: int, level: int) -> void:
	if not OS.has_feature("web"):
		return

	var origin := _origin()
	if origin.is_empty():
		push_warning("ScoreReporter: no page origin, score not submitted")
		return

	# One request node per submission, freed when it finishes. An HTTPRequest
	# handles a single request at a time, and this way two scores landing close
	# together — the end of a four-player game — cannot collide.
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_request_completed.bind(request))

	var payload := JSON.stringify({
		"name": player_name,
		"score": score,
		"level": level,
	})

	var error := request.request(
		origin + ENDPOINT,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		payload
	)

	if error != OK:
		push_warning("ScoreReporter: could not start request (%d)" % error)
		request.queue_free()
		submitted.emit(false)


func _origin() -> String:
	var origin: Variant = JavaScriptBridge.eval(ORIGIN_EXPRESSION, true)
	return str(origin) if origin != null else ""


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray,
	request: HTTPRequest
) -> void:
	request.queue_free()

	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code == HTTPClient.RESPONSE_CREATED
	if not ok:
		push_warning("ScoreReporter: submission failed (result %d, HTTP %d)" % [result, response_code])

	submitted.emit(ok)
