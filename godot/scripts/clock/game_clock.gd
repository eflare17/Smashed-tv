extends Node
## The game clock (milestone 1.4): the day number and the time of day everything runs on (the sun and lamps, the
## farm's crops, later the trading game's market days). An autoload at /root/GameClock once merged; until then
## the Lighting install adds this node there. Owned by the Lighting session. The interface is PARALLEL.md's.
##
## A game day is day_length_sec real seconds (20 minutes): 7 am to 9 pm takes DAY_SHARE of it (about 14 minutes,
## a game hour a minute) and the night the rest (about 6). The day number goes up at 7 am, not at midnight: a
## game day runs from one morning to the next, so the small hours still belong to the day before, and sleeping
## at 2 am or at 11 pm both wake you at 7 am on the next day (day_started fires then: a new market day).
##
## Online (milestone 4): the host's clock is the one. A guest sets is_host = false (its clock stops ticking by
## itself) and applies the host's save_state() from each snapshot with load_state(), which fires the same
## signals for whatever it moved past.

## The hour the day starts (and you wake), and when night falls.
const MORNING := 7.0
const NIGHTFALL := 21.0
## How much of a day's real time is daytime (7 am to 9 pm).
const DAY_SHARE := 0.7

## The day, from 1. Goes up at 7 am.
var day: int = 1
## The time of day, 0 to 24 (7.5 is half past seven in the morning).
var hour: float = MORNING
## Stops the clock (menus, the arcade, the trip...).
var paused: bool = false
## One game day in real seconds: the one tunable number (20 minutes).
var day_length_sec: float = 1200.0

## The whole hour has changed (also after a skip): 0 to 23.
signal hour_changed(hour: int)
## A new day has begun (7 am): a new market day.
signal day_started(day: int)
## Time was moved on at once, by this many game hours (a wave survived, a sleep, a load).
signal time_skipped(hours: float)

## --- Not in the interface ---

## False on an online guest: the host's snapshots move it (load_state), it doesn't tick by itself.
var is_host: bool = true
## Runs the clock faster (tests, the debug key): game time = real time x speed.
var speed: float = 1.0

func _process(delta: float) -> void:
	if paused or not is_host:
		return
	tick(delta * speed)

## Moves the clock on by real seconds (what _process does each frame).
func tick(real_sec: float) -> void:
	if real_sec <= 0.0:
		return
	var left := real_sec
	# the day and the night go at different rates: step to the next change of rate if it comes first
	while left > 0.0:
		var rate := hours_per_sec()
		var to_edge := _hours_to_rate_change()
		var h := left * rate
		if h <= to_edge:
			_move(h)
			left = 0.0
		else:
			_move(to_edge)
			left -= to_edge / rate

## Game hours a real second just now (14 / 840 by day, 10 / 360 at night).
func hours_per_sec() -> float:
	var day_hours := NIGHTFALL - MORNING
	if is_daytime_hours(hour):
		return day_hours / (day_length_sec * DAY_SHARE)
	return (24.0 - day_hours) / (day_length_sec * (1.0 - DAY_SHARE))

## Moves time on (surviving a wave moves it a few hours; growth counts it).
func advance_hours(h: float) -> void:
	if h <= 0.0:
		return
	_move(h)
	time_skipped.emit(h)

## To 7 am of the next day.
func sleep_to_morning() -> void:
	advance_hours(hours_to_morning())

## Game hours from now to the next 7 am (24 if it's 7 am exactly: tomorrow's).
func hours_to_morning() -> float:
	var h := fposmod(MORNING - hour, 24.0)
	return 24.0 if h < 0.0001 else h

## Night: 9 pm to 7 am.
func is_night() -> bool:
	return not is_daytime_hours(hour)

static func is_daytime_hours(h: float) -> bool:
	return h >= MORNING and h < NIGHTFALL

func save_state() -> Dictionary:
	return {"day": day, "hour": hour}

## Sets the day and time (a save, or the host's snapshot). Moving forward fires the signals for what it passed
## (hour_changed, day_started, then time_skipped); a jump back (a different save) just sets it and fires
## hour_changed and day_started for where it lands.
func load_state(d: Dictionary) -> void:
	var nd := maxi(1, int(d.get("day", day)))
	var nh := clampf(float(d.get("hour", hour)), 0.0, 23.9999)
	var diff := (total_hours_for(nd, nh) - total_hours())
	if diff > 0.0 and diff < 24.0 * 7.0:
		if diff > 1.0 / 60.0:
			advance_hours(diff)       # a big step (a snapshot after a sleep): it was a skip
		else:
			_move(diff)               # the snapshot's usual small step
		return
	day = nd
	hour = nh
	hour_changed.emit(int(hour))
	day_started.emit(day)

## Game hours since 7 am on day 1 (for counting growth, interest...).
func total_hours() -> float:
	return total_hours_for(day, hour)

static func total_hours_for(d: int, h: float) -> float:
	return (d - 1) * 24.0 + fposmod(h - MORNING, 24.0)

## "7:05 am", "12:30 pm".
func time_text() -> String:
	return format_time(hour)

static func format_time(h: float) -> String:
	var mins := int(floor(fposmod(h, 24.0) * 60.0 + 0.0001))
	var hh := mins / 60
	var mm := mins % 60
	var ampm := "am" if hh < 12 else "pm"
	var h12 := hh % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, mm, ampm]

# moves hour on by h, firing hour_changed and day_started for each whole hour passed (within a millionth of an
# hour counts as reached, so float error never leaves it stuck just short of one)
func _move(h: float) -> void:
	while h > 0.0:
		var nxt := floorf(hour) + 1.0
		var to_next := nxt - hour
		if h + 1e-6 < to_next:
			hour += h
			return
		h -= to_next
		hour = nxt
		if hour >= 24.0:
			hour -= 24.0
		if is_equal_approx(hour, MORNING):
			day += 1
		hour_changed.emit(int(hour))
		if is_equal_approx(hour, MORNING):
			day_started.emit(day)

func _hours_to_rate_change() -> float:
	if is_daytime_hours(hour):
		return NIGHTFALL - hour
	return fposmod(MORNING - hour, 24.0)
