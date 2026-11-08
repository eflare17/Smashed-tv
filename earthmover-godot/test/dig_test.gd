extends SceneTree
## Checks the excavator against the dirt, with no drawing. Run: godot --headless --path . -s test/dig_test.gd
## These test how it behaves, not whether it feels good: only working it can tell that.

const DT := 1.0 / 60.0
var fails := 0
var ground := GroundData.new()

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func new_digger(s: DirtSim, at: Vector2, dir: Vector2) -> Excavator:
	var view := GroundView.new(ground, s, ground.height_texture(), ground.data_texture())
	var e := Excavator.new()
	root.add_child(e)
	e.setup(s, view, StandardMaterial3D.new(), at, dir)
	return e

func hold(s: DirtSim, e: Excavator, seconds: float, reach := 0.0, raise := 0.0, curl := 0.0, swing := 0.0) -> bool:
	e.reach_cmd = reach
	e.raise_cmd = raise
	e.curl_cmd = curl
	e.swing_cmd = swing
	var start := s.total()
	var same := true
	for t in int(seconds / DT):
		e.step(DT)
		s.step(DT, 1000000)
		if s.total() != start:
			same = false
	return same

## Reach out, go down, drag in, come up: one bite.
func one_bite(s: DirtSim, e: Excavator) -> bool:
	var same := true
	e.curl = 1.5
	same = hold(s, e, 1.2, 1.0) and same
	same = hold(s, e, 2.5, 0.0, -1.0) and same
	same = hold(s, e, 3.5, -1.0, -0.15) and same
	same = hold(s, e, 2.0, 0.0, 1.0, 1.0) and same
	return same

func _init() -> void:
	# The arm goes where it's sent, and stops at what it can reach.
	var a := DirtSim.new()
	var e := new_digger(a, Vector2(0, 0), Vector2(1, 0))
	e._solve(Vector2(6.0, 1.0))
	var check_elbow := Excavator.SHOULDER + Vector2(cos(e._boom_a), sin(e._boom_a)) * Excavator.BOOM
	check(absf(check_elbow.distance_to(e.wrist) - Excavator.STICK) < 0.01, "the boom and stick stay joined (%.2f m)" % check_elbow.distance_to(e.wrist))
	check(e.wrist.distance_to(Vector2(6.0, 1.0)) < 0.02, "the pin gets where it's sent in reach (off by %.3f m)" % e.wrist.distance_to(Vector2(6.0, 1.0)))
	e._solve(Vector2(40.0, 2.0))
	check(e.wrist.x < 9.6, "it can't reach past its length (%.1f m out)" % e.wrist.x)
	e._solve(Vector2(0.5, 1.0))
	check(e.wrist.x >= Excavator.NEAREST - 0.01, "it can't come through the machine (%.1f m out)" % e.wrist.x)
	e._solve(Vector2(5.0, -20.0))
	var deepest := e.wrist.y
	check(deepest < -3.5 and deepest > -7.0, "how deep it reaches is believable (pin at %.1f m)" % deepest)

	# The house turns, and the bucket goes round with it.
	e._solve(Vector2(5.2, 2.7))
	e._pose()
	e.teeth = e._teeth_now()
	var before := e.teeth
	hold(a, e, 2.0, 0.0, 0.0, 0.0, 1.0)
	check(e.swing < -0.5, "the house swings right when told to (%.2f rad)" % e.swing)
	check(Vector2(e.teeth.x, e.teeth.z).distance_to(Vector2(before.x, before.z)) > 2.0, "and takes the bucket with it")
	check(e.teeth.z > before.z, "to the machine's right")
	hold(a, e, 1.5)
	check(absf(e._v_swing) < 0.01, "it comes to a stop when let go")

	# A bite of firm ground: the soil comes out of the ground and into the bucket, and the total never changes.
	var b := DirtSim.new()
	var total := b.total()
	var f := new_digger(b, Vector2(0, 0), Vector2(1, 0))
	var bed_mid := b.bed[DirtSim.cell_of(Vector2(6.0, 0.25)).y * DirtSim.CELLS + DirtSim.cell_of(Vector2(6.0, 0.25)).x]
	var same := one_bite(b, f)
	check(same and b.total() == total, "a whole bite in firm ground: the total never changes")
	check(f.bucket_mm > 2000, "the bucket took some (%.2f m3)" % DirtSim.to_m3(f.bucket_mm))
	check(b.held == f.bucket_mm + f._pour_store, "what's held is what's in the bucket")
	var lowest := 0
	for j in range(100, 160):
		for i in range(128, 180):
			lowest = mini(lowest, b.bed[j * DirtSim.CELLS + i] - bed_mid)
	check(lowest < -150, "and left a hole (%d mm deep)" % -lowest)
	var machine_y := f.position.y
	check(absf(machine_y) < 0.1, "digging ahead of itself the machine stays where it is (%.2f m)" % machine_y)

	# Loose soil comes much quicker than firm ground.
	var c := DirtSim.new()
	for j in range(90, 170):
		for i in range(128, 200):
			c.soil[j * DirtSim.CELLS + i] = 1500
	var c_total := c.total()
	var g := new_digger(c, Vector2(0, 0), Vector2(1, 0))
	same = one_bite(c, g)
	check(same and c.total() == c_total, "a bite in deep loose soil: the total never changes")
	check(g.bucket_mm > f.bucket_mm, "loose soil fills it faster than firm ground (%.2f against %.2f m3)" % [DirtSim.to_m3(g.bucket_mm), DirtSim.to_m3(f.bucket_mm)])
	check(g.bucket_mm <= Excavator.CAPACITY, "and it can't hold more than it holds (%.2f m3)" % DirtSim.to_m3(g.bucket_mm))

	# Swing over and tip it out: it falls as real soil, a heap builds, and the bucket's empty.
	var held_was := g.bucket_mm
	var loose_was := c.loose_total()
	same = hold(c, g, 2.0, 0.0, 0.0, 0.0, 1.0)
	var still := g.bucket_mm
	check(still > held_was * 0.6, "it keeps its load while it swings (%.2f of %.2f m3)" % [DirtSim.to_m3(still), DirtSim.to_m3(held_was)])
	same = hold(c, g, 3.0, 0.0, 0.0, -1.0) and same
	same = hold(c, g, 2.5) and same
	check(same, "tipping it out: the total never changes")
	check(g.bucket_mm == 0 and c.held == 0, "the bucket empties (%d mm left)" % g.bucket_mm)
	check(c.in_air == 0, "and it has all landed")
	check(c.loose_total() > loose_was, "as loose soil on the ground (%.2f m3 more)" % DirtSim.to_m3(c.loose_total() - loose_was))
	check(c.total() == c_total, "still the same total at the end")

	# Rock stops the teeth.
	var d := DirtSim.new()
	for j in range(90, 170):
		for i in range(128, 200):
			d.rock[j * DirtSim.CELLS + i] = 1
	var h := new_digger(d, Vector2(0, 0), Vector2(1, 0))
	h.curl = 1.5
	hold(d, h, 1.0, 1.0)
	hold(d, h, 3.0, 0.0, -1.0)
	var over_rock := h.teeth.y
	hold(d, h, 2.0, -1.0, -0.2)
	check(over_rock > -0.2 and h.teeth.y > -0.2, "rock can't be dug: the teeth stay on it (%.2f m)" % h.teeth.y)
	check(h.bucket_mm == 0, "and nothing comes away")

	# It drives on its tracks, slowly, and not at all in dig mode unless told to.
	var m := DirtSim.new()
	var t := new_digger(m, Vector2(-20, 0), Vector2(1, 0))
	t.dig_mode = false
	t.throttle = 1.0
	hold(m, t, 5.0)
	check(t.spot.x > -15.0, "it drives (%.1f m)" % (t.spot.x + 20.0))
	check(t.speed <= Excavator.TOP_SPEED + 0.01, "at no more than its top speed (%.1f m/s)" % t.speed)

	# The real scene: dig the big pile from the spot it starts at and drop it in the pit.
	var w := DirtSim.new()
	ground.fill_sim(w)
	var w_total := w.total()
	var dir := (GroundData.PILE - GroundData.digger_spot()).normalized()
	var r := new_digger(w, GroundData.digger_spot(), dir)
	same = true
	var dug := 0
	for bite in 4:
		same = hold(w, r, 1.6, 1.0, 0.6, -1.0) and same
		same = hold(w, r, 1.8, 0.0, -1.0) and same
		same = hold(w, r, 2.6, -1.0, -0.1) and same
		same = hold(w, r, 1.2, 0.0, 1.0, 1.0) and same
		dug += r.bucket_mm
		same = hold(w, r, 2.5, 0.0, 0.0, 0.0, -1.0) and same
		same = hold(w, r, 2.0, 0.0, 0.0, -1.0) and same
		same = hold(w, r, 2.5, 0.0, 0.0, 1.0, 1.0) and same
	check(same and w.total() == w_total, "four bites of the real pile: the total never changes")
	check(DirtSim.to_m3(dug) > 2.0, "it moved real soil (%.1f m3 in 4 bites)" % DirtSim.to_m3(dug))
	print("      each bite carried about %.2f m3" % (DirtSim.to_m3(dug) / 4.0))

	# Filled right up and held curled (owner, 9 Nov): the top of the heap tumbles off in little lumps till it's settled, real soil
	# that lands on the ground, and none lost. The soil in it is drawn inside the bucket.
	var u := DirtSim.new()
	ground.fill_sim(u)
	var x := new_digger(u, Vector2(-10.0, 10.0), Vector2(1, 0))
	x.wrist = Vector2(6.0, 2.5)
	x.curl = 3.2
	hold(u, x, 0.2)
	x.bucket_mm = x.capacity()
	u.held += x.capacity()
	var u_total := u.total()
	var flew := 0
	var lumps := 0
	var was_air := 0
	var u_same := true
	for k in int(3.0 / DT):
		x.step(DT)
		u.step(DT, 1000000)
		flew = maxi(flew, u.in_air)
		if u.air_amt.size() > was_air:
			lumps += u.air_amt.size() - was_air
		was_air = u.air_amt.size()
		u_same = u_same and u.total() == u_total
	var kept := x.fill()
	print("      filled right up: kept %d%% of it, %d lumps tumbled off, at most %.2f m3 in the air at once" % [int(kept * 100.0), lumps, DirtSim.to_m3(flew)])
	check(kept > 0.85 and kept < 0.95, "a full bucket settles: a little tumbles off, most stays (%d%%)" % int(kept * 100.0))
	check(lumps >= 5 and flew > 0, "it comes off as little lumps falling, not all at once")
	check(u_same and u.in_air == 0, "they land, and the total never changes")
	check(x._lump.visible and x._loads.find(x._lump.mesh) >= Excavator.LOAD_LEVELS, "the soil in it is drawn as a heap above the bucket's rim")

	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)
