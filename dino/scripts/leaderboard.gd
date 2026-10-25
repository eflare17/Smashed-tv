class_name Leaderboard
extends Node
## The online leaderboard: kilograms of meat eaten, added up over the day, the week and the month (Melbourne time:
## midnight, Monday, the 1st). Each run's meat is sent when you die; the boards are worked out by the database
## (a Supabase project: a `runs` table anyone can add to but not change, and a `leaderboard(period, me)` function
## that gives the top 10 plus your own spot; the SQL is in dino/leaderboard.sql).
## With no URL set (or in the tests and the demo bot) it's off and the game doesn't show it.

## The Supabase project and its public key (safe in the game: it can only add runs and read the boards).
const URL := "https://ueayzpvgrswltfduxzwd.supabase.co"
const KEY := "sb_publishable_-BwXUOQVEp3bClI3HZLlBA_sy_f4HH4"
const PERIODS := ["day", "week", "month"]

## A board arrived: `rows` is [[rank, name, kg, is it you], ...] (empty if no one's eaten yet), `error` "" or what
## went wrong.
signal loaded(period: String, rows: Array, error: String)

var url := URL
var key := KEY

func enabled() -> bool:
	return url != ""

func _request(path: String, body: Dictionary, done: Callable) -> void:
	var h := HTTPRequest.new()
	h.timeout = 10.0
	add_child(h)
	h.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray):
		h.queue_free()
		done.call(result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, data.get_string_from_utf8()))
	var headers := ["apikey: " + key, "Content-Type: application/json"]
	# an old-style (JWT) anon key also goes as the bearer; the newer "publishable" keys go in apikey only
	if key.begins_with("eyJ"):
		headers.append("Authorization: Bearer " + key)
	if path == "/rest/v1/runs":
		# adding a run: don't send it back (anyone can add, no one can read the table itself)
		headers.append("Prefer: return=minimal")
	if h.request(url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		h.queue_free()
		done.call(false, "")

## Sends one run's meat. With no meat it's only sent with `then` (a new name: it makes the board show it), which
## is called once it's in.
func send_run(player_id: String, player_name: String, kg: float, then := Callable()) -> void:
	if not enabled() or (kg <= 0.0 and not then.is_valid()):
		return
	_request("/rest/v1/runs", {"player": player_id, "name": player_name, "kg": snappedf(clampf(kg, 0.0, 5000.0), 0.1)},
			func(_ok: bool, _text: String):
				if then.is_valid():
					then.call())

## Asks for a board ("day", "week" or "month"), showing `player_id`'s spot; answers with `loaded`.
func fetch(period: String, player_id: String) -> void:
	if not enabled():
		loaded.emit(period, [], "off")
		return
	_request("/rest/v1/rpc/leaderboard", {"period": period, "me": player_id}, func(ok: bool, text: String):
		var data: Variant = JSON.parse_string(text) if ok else null
		if not (data is Array):
			loaded.emit(period, [], "CAN'T REACH THE LEADERBOARD")
			return
		var rows: Array = []
		for r: Variant in data:
			if r is Dictionary:
				rows.append([int(r.get("rank", 0)), str(r.get("name", "?")), float(r.get("kg", 0.0)), bool(r.get("is_me", false))])
		loaded.emit(period, rows, ""))
