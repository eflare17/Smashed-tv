extends SceneTree
## Headless logic test of the GameClock:
##   godot --headless --path godot --script res://test/lighting/clock_test.gd
## Prints PASS/FAIL lines and quits with the number of failures.

const ClockScript := preload("res://scripts/clock/game_clock.gd")

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	var c: Node = ClockScript.new()
	root.add_child(c)
	var hours := []
	var days := []
	var skips := []
	c.hour_changed.connect(func(h): hours.append(h))
	c.day_started.connect(func(d): days.append(d))
	c.time_skipped.connect(func(h): skips.append(h))

	check(c.day == 1 and is_equal_approx(c.hour, 7.0), "starts day 1, 7 am")
	check(not c.is_night(), "7 am is day")
	# a whole day of real time, in 1/60 s steps: back to 7 am, day 2
	for i in 1200 * 60:
		c.tick(1.0 / 60.0)
	check(c.day == 2, "a day later it's day 2 (got %d)" % c.day)
	check(absf(c.hour - 7.0) < 0.01, "a day later it's 7 am again (got %.4f)" % c.hour)
	check(hours.size() == 24, "24 hour_changed in a day (got %d)" % hours.size())
	check(days == [2], "day_started(2) once (got %s)" % [days])

	# the split: 7 am to 9 pm takes 840 s, the night 360 s
	c.load_state({"day": 5, "hour": 7.0})
	var t := 0.0
	while c.hour < 21.0 and c.hour >= 7.0:
		c.tick(0.5)
		t += 0.5
	check(absf(t - 840.0) <= 0.5, "7 am to 9 pm takes 14 minutes (got %.1f s)" % t)
	check(c.is_night(), "9 pm is night")
	t = 0.0
	while c.is_night():
		c.tick(0.5)
		t += 0.5
	check(absf(t - 360.0) <= 0.5, "the night takes 6 minutes (got %.1f s)" % t)
	check(c.day == 6, "the night ends on the next day (got %d)" % c.day)

	# the tunable number
	c.day_length_sec = 600.0
	c.load_state({"day": 1, "hour": 7.0})
	for i in 600:
		c.tick(1.0)
	check(c.day == 2 and absf(c.hour - 7.0) < 0.01, "day_length_sec 600: a day in 10 minutes")
	c.day_length_sec = 1200.0

	# sleeping: at 11 pm and at 2 am both wake at 7 am on the next game day
	c.load_state({"day": 3, "hour": 23.0})
	days.clear()
	skips.clear()
	c.sleep_to_morning()
	check(c.day == 4 and is_equal_approx(c.hour, 7.0), "sleep at 11 pm day 3 -> 7 am day 4 (got %d %.2f)" % [c.day, c.hour])
	check(days == [4] and skips.size() == 1 and is_equal_approx(skips[0], 8.0), "sleep fires day_started(4), time_skipped(8)")
	c.load_state({"day": 4, "hour": 2.0})
	check(c.day == 4, "2 am still belongs to day 4")
	c.sleep_to_morning()
	check(c.day == 5 and is_equal_approx(c.hour, 7.0), "sleep at 2 am -> 7 am day 5")
	c.load_state({"day": 5, "hour": 13.5})
	c.sleep_to_morning()
	check(c.day == 6 and is_equal_approx(c.hour, 7.0), "an afternoon nap -> 7 am day 6")

	# advance_hours: a wave moves it on
	c.load_state({"day": 2, "hour": 19.5})
	hours.clear()
	c.advance_hours(3.0)
	check(is_equal_approx(c.hour, 22.5) and c.day == 2, "advance 3 h from 7:30 pm -> 10:30 pm")
	check(hours == [20, 21, 22], "hour_changed for each hour passed (got %s)" % [hours])
	c.advance_hours(30.0)
	check(c.day == 3 and is_equal_approx(c.hour, 4.5), "advance 30 h -> 4:30 am day 3 (got %d %.2f)" % [c.day, c.hour])

	# save and load
	var s: Dictionary = c.save_state()
	var c2: Node = ClockScript.new()
	root.add_child(c2)
	c2.load_state(s)
	check(c2.day == c.day and is_equal_approx(c2.hour, c.hour), "save_state / load_state round trip")
	check(c2.load_state.get_argument_count() == 1, "load_state(d)")

	# a guest following the host's snapshots
	c2.is_host = false
	var d0: int = c2.day
	c2._process(100.0)
	check(c2.day == d0 and is_equal_approx(c2.hour, 4.5), "a guest's clock doesn't tick by itself")
	var gh := []
	c2.hour_changed.connect(func(h): gh.append(h))
	c2.load_state({"day": 3, "hour": 5.01})
	check(gh == [5], "a snapshot moving past 5 am fires hour_changed(5) (got %s)" % [gh])

	# paused
	c.paused = true
	var h0: float = c.hour
	c._process(10.0)
	check(c.hour == h0, "paused: no ticking")
	check(ClockScript.format_time(7.0) == "7:00 am" and ClockScript.format_time(12.5) == "12:30 pm"
		and ClockScript.format_time(0.25) == "12:15 am" and ClockScript.format_time(21.999) == "9:59 pm", "time_text")
	print("clock_test: %d failed" % fails)
	quit(fails)
