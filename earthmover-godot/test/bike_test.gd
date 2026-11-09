extends SceneTree
## Checks the dirt bike with no drawing: its speed, brakes and steering, and jumps off a lip onto a landing, ridden hands-off and
## leaned too far. Run: godot --headless --path . -s test/bike_test.gd
## These test how it behaves, not whether it feels good: only riding it can tell that.

const DT := 1.0 / 60.0
var fails := 0
var ground := GroundData.new()

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func new_bike(s: DirtSim, at: Vector2, dir: Vector2) -> Bike:
	var view := GroundView.new(ground, s, ground.height_texture(), ground.data_texture())
	var b := Bike.new()
	root.add_child(b)
	b.setup(s, view, StandardMaterial3D.new(), at, dir)
	b.show_driver(true)
	return b

## Sets the firm ground's height between x0 and x1 (m), all the way across, from a function of x.
func shape(s: DirtSim, x0: float, x1: float, high: Callable) -> void:
	var i0 := int((x0 + DirtSim.HALF_M) / DirtSim.CELL_M)
	var i1 := int((x1 + DirtSim.HALF_M) / DirtSim.CELL_M)
	for i in range(i0, i1 + 1):
		var x := i * DirtSim.CELL_M - DirtSim.HALF_M
		var mm := int(float(high.call(x)) * 1000.0)
		for j in DirtSim.CELLS:
			s.bed[j * DirtSim.CELLS + i] = mm

## A jump along +x: a curved take-off rising 1.5 m to a 30 degree lip at `lip`, a gap, then a landing as high, sloping down at
## `land_deg`. Returns the lip's x.
func jump_site(lip: float, gap: float, land_deg: float, high := 1.5) -> DirtSim:
	var s := DirtSim.new()
	var run := 2.0 * high / tan(deg_to_rad(30.0))
	shape(s, lip - run, lip, func(x: float) -> float: return high * pow((x - (lip - run)) / run, 2.0))
	shape(s, lip, lip + high / tan(deg_to_rad(40.0)), func(x: float) -> float: return high - (x - lip) * tan(deg_to_rad(40.0)))
	var top := lip + gap
	var down := high / tan(deg_to_rad(land_deg))
	shape(s, top - high / tan(deg_to_rad(40.0)), top, func(x: float) -> float: return maxf(high - (top - x) * tan(deg_to_rad(40.0)), 0.0))
	shape(s, top, top + down, func(x: float) -> float: return high - (x - top) * tan(deg_to_rad(land_deg)))
	return s

## Rides for `seconds`, holding a speed with the throttle, and the thumb at `thumb` once it's in the air (0: where it was).
func ride(s: DirtSim, b: Bike, seconds: float, want_speed: float, thumb := 0.0, record := {}) -> void:
	var t := 0.0
	while t < seconds:
		if not b.airborne:
			b.throttle = clampf((want_speed - b.speed) * 0.5 + want_speed / Bike.TOP, 0.0, 1.0) if want_speed > 0.0 else 0.0
		b.thumb_y = -b.throttle + (thumb if b.airborne else 0.0)
		b.step(DT)
		s.step(DT, 1000000)
		t += DT
		if not record.is_empty():
			record["air"] = maxf(record["air"], b.air_t)
			record["high"] = maxf(record["high"], b.y - s.height_at(b.spot))
			record["least"] = minf(record["least"], minf(b.stretch[0], b.stretch[1]))
			if b.crash_t >= 0.0:
				record["crashed"] = true
			if b.jump_show > 0.0:
				record["jump"] = b.jump_m
			record["most_pitch"] = maxf(record["most_pitch"], absf(rad_to_deg(b.pitch)))

func fresh() -> Dictionary:
	return {"air": 0.0, "high": 0.0, "least": 9.0, "crashed": false, "jump": 0.0, "most_pitch": 0.0}

func _init() -> void:
	# Flat ground: it gets up to speed, stops when let go, and turns.
	var a := DirtSim.new()
	var b := new_bike(a, Vector2(-24.0, -10.0), Vector2(1.0, 0.0))
	ride(a, b, 1.0, 0.0)
	var rest_y := b.y
	check(absf(b.y - Bike.COM_UP) < 0.05 and absf(b.pitch) < 0.02, "it sits on its springs on flat ground (middle %.2f m up, pitch %.1f deg)" % [b.y, rad_to_deg(b.pitch)])
	b.throttle = 1.0
	var t := 0.0
	while b.speed < Bike.TOP * 0.9 and t < 12.0:
		b.step(DT)
		a.step(DT, 1000000)
		t += DT
	check(t < 7.0, "flat out, it's at 90%% of top speed in %.1f s" % t)
	check(not b.airborne and b.crash_t < 0.0, "and stays on the ground and on its wheels")
	b.throttle = 0.0
	var from := b.spot.x
	ride(a, b, 6.0, 0.0)
	check(absf(b.speed) < 0.05, "let go, it comes to a stop (%.2f m/s, rolled %.0f m)" % [b.speed, b.spot.x - from])
	b.throttle = -1.0
	b.step(DT)
	b.throttle = 0.0

	var c := DirtSim.new()
	var d := new_bike(c, Vector2(-20.0, 0.0), Vector2(1.0, 0.0))
	ride(c, d, 3.0, 8.0)
	var heading := d.angle
	d.steer = 1.0
	ride(c, d, 1.0, 8.0)
	d.steer = 0.0
	check(absf(d.angle - heading) > 0.4, "at 8 m/s with the bars full over, it turns (%.0f degrees in a second)" % rad_to_deg(absf(d.angle - heading)))
	check(absf(d.roll_vis) > 0.3, "and leans into the turn (%.0f degrees)" % rad_to_deg(absf(d.roll_vis)))

	# A slope: let go on it and it holds on the brake.
	var e := DirtSim.new()
	shape(e, -10.0, 10.0, func(x: float) -> float: return (x + 10.0) * 0.36)
	shape(e, 10.0, 30.0, func(_x: float) -> float: return 7.2)
	var f := new_bike(e, Vector2(-14.0, 0.0), Vector2(1.0, 0.0))
	ride(e, f, 3.5, 7.0)
	ride(e, f, 3.0, 0.0)
	var held := f.spot.x
	ride(e, f, 3.0, 0.0)
	check(absf(f.spot.x - held) < 0.05 and f.spot.x > -10.0, "let go on a 20 degree slope, it stays put on the brake (at %.1f, moved %.2f m)" % [f.spot.x, f.spot.x - held])

	# Jumps: a 1.5 m take-off with a 30 degree lip, a landing as high 7 m on sloping away at 30 degrees.
	print("Jumps, hands off (the thumb left where it was):")
	var best := 0.0
	for want: float in [10.0, 12.0, 14.0]:
		var j := jump_site(0.0, 7.0, 30.0)
		var bike := new_bike(j, Vector2(-25.0, 0.0), Vector2(1.0, 0.0))
		var r := fresh()
		ride(j, bike, 7.0, want, 0.0, r)
		print("   run at %.0f m/s: %.2f s in the air, %.1f m up, jump %.1f m, springs to %.2f m, crashed %s, now at x %.1f" % [want, r["air"], r["high"], r["jump"], r["least"], r["crashed"], bike.spot.x])
		check(not r["crashed"], "at %.0f m/s, hands off, it lands and rides away" % want)
		best = maxf(best, r["jump"])
	check(best > 8.0, "and the quickest run jumps a good way (%.1f m)" % best)

	print("Leaned too far all the way through the air:")
	for lean: float in [1.0, -1.0]:
		var j := jump_site(0.0, 7.0, 30.0)
		var bike := new_bike(j, Vector2(-25.0, 0.0), Vector2(1.0, 0.0))
		var r := fresh()
		# The thumb slid down a whole reach leans it back; up, forward.
		ride(j, bike, 6.0, 11.0, lean, r)
		print("   thumb %s: crashed %s, most pitch %.0f" % ["down (back)" if lean > 0.0 else "up (forward)", r["crashed"], r["most_pitch"]])
		check(r["crashed"], "leaned right %s through a jump, the rider comes off" % ("back" if lean > 0.0 else "forward"))
		ride(j, bike, Bike.CRASH_TIME + 0.3, 0.0)
		check(bike.crash_t < 0.0 and bike.spot.x < -3.0 and absf(bike.speed) < 0.1, "then it's put back before the jump, stopped (x %.1f)" % bike.spot.x)
		check(bike._rider.visible and not bike._rider.top_level, "with the rider back on")
		ride(j, bike, 1.0, 0.0)
		check(not bike.airborne and bike.crash_t < 0.0, "and it sits there on its wheels")

	# A big drop onto the flat: hard, but he stays on.
	var g := DirtSim.new()
	shape(g, -30.0, 0.0, func(_x: float) -> float: return 2.5)
	var drop := new_bike(g, Vector2(-20.0, 0.0), Vector2(1.0, 0.0))
	var dr := fresh()
	ride(g, drop, 5.0, 9.0, 0.0, dr)
	print("   off a 2.5 m table onto the flat at 9 m/s: %.2f s in the air, springs to %.2f m, crashed %s" % [dr["air"], dr["least"], dr["crashed"]])
	check(not dr["crashed"], "off a 2.5 m drop onto the flat, it takes the hit and he stays on")
	check(dr["least"] < 0.08, "the springs go near the end of their travel doing it")

	# Ruts in loose soil move dirt about but never make or lose any.
	var h := DirtSim.new()
	for j in range(100, 158):
		for i in range(30, 230):
			h.soil[j * DirtSim.CELLS + i] = 200
	var total := h.total()
	var k := new_bike(h, Vector2(-22.0, 0.0), Vector2(1.0, 0.0))
	ride(h, k, 4.0, 10.0)
	check(h.total() == total, "riding through loose soil, no dirt is made or lost")

	# Parked on a slope with nobody on it, as the game runs parked machines: a big step every fourth tick.
	var p := DirtSim.new()
	shape(p, -10.0, 10.0, func(x: float) -> float: return (x + 10.0) * 0.36)
	var parked := new_bike(p, Vector2(0.0, 0.0), Vector2(1.0, 0.0))
	parked.show_driver(false)
	for n in 30:
		parked.step(DT * 4.0)
	var put := parked.spot
	for n in 150:
		parked.step(DT * 4.0)
	check(parked.spot.distance_to(put) < 0.01 and absf(parked.roll_vis + 0.24) < 0.02, "parked on a 20 degree slope it settles, then stays put on its stand (moved %.3f m more in 10 s)" % parked.spot.distance_to(put))
	check(parked._rest_t >= 1.0, "and rests, working nothing out")
	parked.show_driver(true)
	ride(p, parked, 2.0, 5.0)
	check(parked.spot.distance_to(put) > 1.5, "someone gets on and it rides off up the slope (%.1f m)" % parked.spot.distance_to(put))

	# Online: a copy fed what the host sends follows it through a jump, the rider coming off and all; the guest's thumb gets to
	# the host for the lean.
	var host_sim := jump_site(0.0, 7.0, 30.0)
	var host := new_bike(host_sim, Vector2(-25.0, 0.0), Vector2(1.0, 0.0))
	var copy := new_bike(host_sim, Vector2(-25.0, 0.0), Vector2(1.0, 0.0))
	var worst := 0.0
	var worst_pitch := 0.0
	var copy_crashed := false
	var tt := 0.0
	while tt < 8.0:
		host.throttle = 0.75 if not host.airborne else host.throttle
		host.thumb_y = 0.6 if host.airborne else -0.75
		host.step(DT)
		host_sim.step(DT, 1000000)
		copy.net_take(host.net_state())
		copy.net_follow(DT)
		tt += DT
		if tt > 0.5:
			worst = maxf(worst, copy.position.distance_to(host.position))
			worst_pitch = maxf(worst_pitch, absf(rad_to_deg(wrapf(copy.pitch - host.pitch, -PI, PI))))
		copy_crashed = copy_crashed or copy.crash_t >= 0.0
	check(worst < 1.0 and worst_pitch < 12.0, "the copy keeps up with the bike (within %.2f m and %.0f degrees)" % [worst, worst_pitch])
	check(copy_crashed, "and shows the rider coming off when he does")
	var guest := new_bike(host_sim, Vector2(0.0, 5.0), Vector2(1.0, 0.0))
	guest.throttle = 0.5
	guest.thumb_y = 0.3
	host.net_take_cmds(guest.net_cmds())
	check(is_equal_approx(host.thumb_y, 0.3) and is_equal_approx(host.throttle, 0.5), "the guest's thumb gets to the host")
	guest.thumb_y = NAN
	host.net_take_cmds(guest.net_cmds())
	check(is_nan(host.thumb_y), "and so does no thumb at all")

	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
