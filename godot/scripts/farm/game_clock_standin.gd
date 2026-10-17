extends Node
## A stand-in for the Lighting session's GameClock (PARALLEL.md, "The game clock"), with exactly its shape, so the
## farm runs before the real one is merged. FarmInstall adds it at /root/GameClock only when nothing's there; once
## the real autoload is in, this file is never used (and can go).
##
## The day: 7 am to 9 pm takes 14/20 of day_length_sec (one game hour a real minute at 1200 s), the night the rest.

signal hour_changed(hour: int)
signal day_started(day: int)
signal time_skipped(hours: float)

var day: int = 1
var hour: float = 7.0
var paused: bool = false
var day_length_sec: float = 1200.0

const DAY_START := 7.0
const NIGHT_START := 21.0
const STANDIN := true             # (the farm saves the stand-in's time with the farm; the real clock saves its own)

func _process(delta: float) -> void:
	if paused:
		return
	var day_share := 14.0 / 20.0
	var secs_per_hour: float
	if is_night():
		secs_per_hour = day_length_sec * (1.0 - day_share) / 10.0
	else:
		secs_per_hour = day_length_sec * day_share / 14.0
	_move(delta / maxf(0.001, secs_per_hour))

func _move(h: float) -> void:
	var before := int(floor(hour))
	hour += h
	while hour >= 24.0:
		hour -= 24.0
	# the day number turns at 7 am (a day is 7 am to 7 am, like sleeping to morning)
	var crossed := false
	if before < int(DAY_START) and hour >= DAY_START and h < 24.0:
		crossed = true
	elif h >= 24.0:
		crossed = true
	if int(floor(hour)) != before:
		hour_changed.emit(int(floor(hour)))
	if crossed:
		day += 1
		day_started.emit(day)

## Surviving a wave moves time on.
func advance_hours(h: float) -> void:
	if h <= 0.0:
		return
	var left := h
	while left > 0.0:
		var step := minf(left, 1.0)
		_move(step)
		left -= step
	time_skipped.emit(h)

## To 7 am of the next day.
func sleep_to_morning() -> void:
	var h := DAY_START - hour
	if h <= 0.0:
		h += 24.0
	advance_hours(h)

func is_night() -> bool:
	return hour >= NIGHT_START or hour < DAY_START

func save_state() -> Dictionary:
	return {"day": day, "hour": hour}

func load_state(d: Dictionary) -> void:
	day = maxi(1, int(d.get("day", 1)))
	hour = clampf(float(d.get("hour", DAY_START)), 0.0, 23.999)
