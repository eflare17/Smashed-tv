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

## Which way his body faces.
func body_basis(d: Ragdoll) -> Basis:
	var p := d.points
	var up := (p[Ragdoll.SH_L] + p[Ragdoll.SH_R] - p[Ragdoll.HIP_L] - p[Ragdoll.HIP_R]).normalized()
	var fw := up.cross(p[Ragdoll.SH_R] - p[Ragdoll.SH_L]).normalized()
	return Basis(fw, up, fw.cross(up))

## How bent each elbow and knee is, in degrees, and each shoulder and hip against his body.
func bends(d: Ragdoll) -> Array[float]:
	var p := d.points
	var up := (p[Ragdoll.SH_L] + p[Ragdoll.SH_R] - p[Ragdoll.HIP_L] - p[Ragdoll.HIP_R]).normalized()
	var out: Array[float] = []
	for k in 2:
		var sh := p[Ragdoll.SH_L + k]
		var el := p[Ragdoll.ELB_L + k]
		var hip := p[Ragdoll.HIP_L + k]
		var kn := p[Ragdoll.KNEE_L + k]
		out.append(rad_to_deg((el - sh).angle_to(p[Ragdoll.HAND_L + k] - el)))
		out.append(rad_to_deg((kn - hip).angle_to(p[Ragdoll.BOOT_L + k] - kn)))
		out.append(rad_to_deg((el - sh).angle_to(-up)))
		out.append(rad_to_deg((kn - hip).angle_to(-up)))
	return out

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

	# MONO: held while going, the front comes up and stays up, it still steers, and let go it's set down gently.
	var mw := DirtSim.new()
	var mb := new_bike(mw, Vector2(-24.0, 0.0), Vector2(1.0, 0.0))
	mb.mono = true
	ride(mw, mb, 0.5, 0.0)
	check(mb.touching[1] and absf(mb.pitch) < 0.05, "MONO held standing still, the front stays down")
	ride(mw, mb, 1.5, 8.0)
	check(not mb.touching[1] and mb.touching[0] and not mb.airborne, "MONO held at 8 m/s, the front comes up off the ground on the back wheel")
	var low_pitch := 99.0
	var high_pitch := 0.0
	var front_down := false
	var gone := mb.spot.x
	for n in 180:
		ride(mw, mb, DT, 8.0)
		low_pitch = minf(low_pitch, rad_to_deg(mb.pitch))
		high_pitch = maxf(high_pitch, rad_to_deg(mb.pitch))
		front_down = front_down or mb.touching[1]
	gone = mb.spot.x - gone
	check(not front_down and absf(low_pitch - rad_to_deg(Bike.MONO_ANGLE)) < 3.0 and absf(high_pitch - rad_to_deg(Bike.MONO_ANGLE)) < 3.0, "and holds it there, %.0f to %.0f degrees, for 3 s" % [low_pitch, high_pitch])
	var word: String = mb.gauge_word()[0]
	check(word.begins_with("MONO") and mb.mono_m > gone, "the readout counts it: %s" % word)
	check(mb.crash_t < 0.0, "with the rider on")
	var mono_heading := mb.angle
	mb.steer = 1.0
	ride(mw, mb, 0.5, 8.0)
	mb.steer = 0.0
	check(absf(mb.angle - mono_heading) > 0.15 and not mb.touching[1], "it steers on the back wheel (%.0f degrees in half a second)" % rad_to_deg(absf(mb.angle - mono_heading)))
	mb.mono = false
	var hit_front := 0.0
	var tdown := 0.0
	while not mb.touching[1] and tdown < 3.0:
		ride(mw, mb, DT, 8.0)
		tdown += DT
	check(tdown < 1.0 and mb.crash_t < 0.0, "let go, the front's set back down in %.2f s" % tdown)
	ride(mw, mb, 1.0, 8.0)
	check(absf(mb.pitch) < 0.05 and mb.touching[1] and mb.gauge_word()[0].begins_with("MONO"), "it rides on on both wheels, the readout still saying how far it went")
	ride(mw, mb, 3.0, 8.0)
	check(not mb.gauge_word()[0].begins_with("MONO"), "and soon goes back to the speed")
	# Up a 20 degree slope on MONO, and full throttle on it.
	var ms := DirtSim.new()
	shape(ms, -6.0, 14.0, func(x: float) -> float: return (x + 6.0) * 0.36)
	shape(ms, 14.0, 30.0, func(_x: float) -> float: return 7.2)
	var up := new_bike(ms, Vector2(-22.0, 0.0), Vector2(1.0, 0.0))
	ride(ms, up, 2.0, 9.0)
	up.mono = true
	var on_slope_lift := 0.0
	var dropped := false
	for n in 150:
		ride(ms, up, DT, 14.0)
		if up.spot.x > 2.0 and up.spot.x < 10.0:
			on_slope_lift = maxf(on_slope_lift, absf(rad_to_deg(up.pitch - Bike.MONO_ANGLE)))
		if up.spot.x > -2.0 and up.spot.x < 12.0:
			dropped = dropped or up.touching[1]
	check(not dropped and on_slope_lift < 3.0 and up.crash_t < 0.0, "MONO up a 20 degree slope at full throttle, it holds the front up off the slope, as high as on the flat (within %.0f degrees)" % on_slope_lift)
	# MONO held off a jump: it flies and lands like any jump, then the front comes back up.
	var mj := jump_site(0.0, 7.0, 30.0)
	var mjb := new_bike(mj, Vector2(-25.0, 0.0), Vector2(1.0, 0.0))
	mjb.mono = true
	var mr := fresh()
	var mt := 0.0
	while mr["jump"] == 0.0 and mt < 6.0:
		ride(mj, mjb, DT, 11.0, 0.0, mr)
		mt += DT
	ride(mj, mjb, 0.3, 11.0, 0.0, mr)
	check(not mr["crashed"] and mr["jump"] > 6.0, "MONO held off a jump at 11 m/s, it jumps %.1f m and lands, the rider on" % mr["jump"])
	check(mjb.gauge_word()[0].begins_with("JUMP"), "the readout shows the jump first (%s)" % mjb.gauge_word()[0])
	ride(mj, mjb, 1.0, 11.0, 0.0, mr)
	check(not mjb.touching[1] and mjb.mono_up and not mr["crashed"], "and the front comes back up after (%.0f degrees)" % rad_to_deg(mjb.pitch))

	print("Coming off, he goes floppy:")
	var fj := jump_site(0.0, 7.0, 30.0)
	var fb := new_bike(fj, Vector2(-25.0, 0.0), Vector2(1.0, 0.0))
	var ft := 0.0
	while fb.crash_t < 0.0 and ft < 8.0:
		ride(fj, fb, DT * 0.5, 11.0, 1.0)
		ft += DT
	var doll := fb._doll
	check(fb.crash_t >= 0.0 and doll.visible and not fb._rider.visible, "leaned back through a jump, he comes off, the floppy rider shown in place of the one on the bike")
	var bend0 := bends(doll)
	var under := 0.0
	var stretched := 0.0
	var most_bend := 0.0
	var broken := false
	var hips_up := 9.0
	var still := 99.0
	var turned := 0.0
	var body_was := body_basis(doll)
	while fb.crash_t >= 0.0:
		var was := doll.points.duplicate()
		fb.step(DT)
		fj.step(DT, 1000000)
		if fb.crash_t < 0.0:
			break
		for dp in doll.points:
			broken = broken or not dp.is_finite()
			under = maxf(under, fj.height_at(Vector2(dp.x, dp.z)) - dp.y)
		stretched = maxf(stretched, doll.worst_stretch())
		var body := body_basis(doll)
		turned += rad_to_deg((body_was.inverse() * body).get_rotation_quaternion().get_angle())
		body_was = body
		var now := bends(doll)
		for n in now.size():
			most_bend = maxf(most_bend, absf(now[n] - bend0[n]))
		if fb.crash_t > Bike.CRASH_TIME - 0.1:
			var hips := (doll.points[Ragdoll.HIP_L] + doll.points[Ragdoll.HIP_R]) * 0.5
			hips_up = minf(hips_up, hips.y - fj.height_at(Vector2(hips.x, hips.z)))
			var fastest := 0.0
			for n in Ragdoll.COUNT:
				fastest = maxf(fastest, doll.points[n].distance_to(was[n]) / DT)
			still = minf(still, fastest)
	print("   deepest under the dirt %.3f m, sticks off length %.0f%%, joints bent up to %.0f degrees from on the bike, hips %.2f m up at the end, quickest bit of him then %.2f m/s" % [under, stretched * 100.0, most_bend, hips_up, still])
	check(not broken and under < 0.03, "no bit of him goes under the dirt")
	check(stretched < 0.08, "his arms and legs keep their length")
	check(most_bend > 25.0, "his arms and legs flop about at the joints")
	check(turned > 270.0, "he tumbles and rolls, not just slides (his body turned over %.0f degrees in all)" % turned)
	check(hips_up < 0.45 and still < 0.6, "and he ends up lying still on the ground")
	check(not doll.visible and fb._rider.visible, "then he's back on the bike")

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
	guest.mono = true
	host.net_take_cmds(guest.net_cmds())
	check(host.mono, "and MONO held")
	guest.mono = false
	host.net_take_cmds(guest.net_cmds())
	check(not host.mono, "and let go")
	host.mono_m = 12.5
	host.mono_show = 2.0
	copy.net_take(host.net_state())
	copy.net_follow(DT)
	check(copy.gauge_word()[0] == "MONO 12.5 m", "the copy's readout shows the wheelie too (%s)" % copy.gauge_word()[0])

	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
