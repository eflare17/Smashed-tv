extends SceneTree
## Checks the big machines and their site, with no drawing. Run: godot --headless --path . -s test/big_test.gd
## The big dozer and excavator are the small ones scaled up: these check they do the same work, only more of it, and that the farm
## dam can be dug out to its floor.

const DT := 1.0 / 60.0
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	var small_push := push_test(1.0)
	var big_push := push_test(1.9)
	check(big_push > small_push * 4.0, "the big dozer pushes far more ahead of its blade (%.1f t against %.1f)" % [big_push, small_push])
	var small_dig := dig_test(1.0)
	var big_dig := dig_test(1.9)
	check(big_dig > small_dig * 3.0, "the big excavator takes far more in a bite (%.2f m3 against %.2f)" % [big_dig, small_dig])
	dam_test()
	DirtSim.set_world(32.0)
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)

func _world(big: bool, site := Rect2()) -> Array:
	DirtSim.set_world(48.0 if big else 32.0)
	var ground := GroundData.new(site, Rect2(), Rect2(), true)
	var s := DirtSim.new()
	ground.fill_sim(s)
	return [ground, s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture())]

## Blade down, 8 s straight ahead into flat paddock: how much it moved.
func push_test(k: float) -> float:
	var w := _world(k > 1.0)
	var s: DirtSim = w[1]
	if k > 1.0:
		check(DirtSim.CELLS == 385 and is_equal_approx(Machine.AREA, 42.0), "the big site is 96 m across, %d cells, machines go %.0f m out" % [DirtSim.CELLS, Machine.AREA])
	var total := s.total()
	var d := Dozer.new()
	d.make_big(k)
	root.add_child(d)
	d.setup(s, w[2], StandardMaterial3D.new(), Vector2(-20.0, 0.0), Vector2(1.0, 0.0))
	d.throttle = 1.0
	d.lift_cmd = -1.0
	var highest := -INF
	var lowest := INF
	for t in int(8.0 / DT):
		if t == 60:
			d.lift_cmd = 0.0
		d.step(DT)
		s.step(DT, 1000000)
		highest = maxf(highest, d.position.y - s.height_at(d.spot))
		lowest = minf(lowest, d.position.y - s.height_at(d.spot))
	print("      %s: went %.1f m, moved %.1f m3, load %.1f t, sat %.2f to %.2f m off the ground" % [d.machine_name, d.spot.x + 20.0, d.moved_m3, d.load_t, lowest, highest])
	check(s.total() == total, "%s: no soil lost" % d.machine_name)
	check(highest < 1.0 * k and lowest > -0.6 * k, "%s: stays on the ground" % d.machine_name)
	check(d.spot.x > -20.0 + 3.0 * k, "%s: keeps going with a load" % d.machine_name)
	d.queue_free()
	return d.load_t

## One bite: reach out, down, drag in, up. How much ended up in the bucket.
func dig_test(k: float) -> float:
	var w := _world(k > 1.0)
	var s: DirtSim = w[1]
	var total := s.total()
	var e := Excavator.new()
	e.make_big(k)
	root.add_child(e)
	e.setup(s, w[2], StandardMaterial3D.new(), Vector2(0.0, 0.0), Vector2(1.0, 0.0))
	e.curl = 1.5
	_hold(s, e, 1.2, 1.0)
	_hold(s, e, 2.5, 0.0, -1.0)
	_hold(s, e, 2.6, -1.0, -0.1)
	_hold(s, e, 1.2, 0.0, 1.0, 1.0)
	var got := DirtSim.to_m3(e.bucket_mm)
	print("      %s: a bite of %.2f m3 (it holds %.2f), teeth went %.2f m deep" % [e.machine_name, got, DirtSim.to_m3(e.capacity()), e.teeth_depth()])
	# Swung round and tipped out.
	_hold(s, e, 2.0, 0.0, 0.0, 0.0, 1.0)
	_hold(s, e, 2.5, 0.0, 0.0, -1.0)
	_hold(s, e, 3.0)
	check(e.bucket_mm == 0, "%s: tips it all out" % e.machine_name)
	check(s.total() == total, "%s: no soil lost" % e.machine_name)
	e.queue_free()
	return got

func _hold(s: DirtSim, e: Excavator, seconds: float, reach := 0.0, raise := 0.0, curl := 0.0, swing := 0.0) -> void:
	e.reach_cmd = reach
	e.raise_cmd = raise
	e.curl_cmd = curl
	e.swing_cmd = swing
	for t in int(seconds / DT):
		e.step(DT)
		s.step(DT, 1000000)

## The farm dam: the big dozer on CUT, pass after pass inside the pegs. It gets dug down, and never past the floor.
func dam_test() -> void:
	var job := Mission.find("farm_dam")
	check(not job.is_empty() and Mission.is_pad_job(job), "there's a farm dam job, scored on its pegs")
	var w := _world(true, Mission.site(job))
	var s: DirtSim = w[1]
	Mission.lay_out(s, job)
	var pad := Mission.pad_for(s, job)
	var r: Rect2 = job["dam"]
	check(absf(pad.level - (s.height_at(r.get_center()) - 1.0)) < 0.05, "its floor is 1 m down (%.2f m)" % pad.level)
	check(pad.score(s) < 0.05, "none of it's dug to start with")
	var total := s.total()
	var d := Dozer.new()
	d.make_big(1.9)
	root.add_child(d)
	d.setup(s, w[2], StandardMaterial3D.new(), Vector2(r.position.x - 9.0, r.get_center().y), Vector2(1.0, 0.0))
	d.pad = pad
	d.set_cut(true)
	d.change_cut(20)
	check(d.cut_cm == 100, "the big dozer can CUT a metre (%d cm)" % d.cut_cm)
	var lanes := [-3.0, 0.0, 3.0, -1.5, 1.5]
	var below := 0
	for lap in 10:
		var z: float = r.get_center().y + lanes[lap % lanes.size()]
		d.reposition_for_test(Vector2(r.position.x - 9.0, z), Vector2(1.0, 0.0))
		d.set_cut(true)
		d.throttle = 1.0
		for t in int(14.0 / DT):
			d.step(DT)
			s.step(DT, 1000000)
		d.throttle = 0.0
		for n in pad.cells:
			if s.bed[n] + s.soil[n] < int((pad.level - Mission.DAM_TOL - 0.05) * 1000.0):
				below += 1
		print("      pass %d: %d%% of the floor dug, at %.1f m along" % [lap + 1, int(pad.score(s) * 100.0), d.spot.x - r.position.x])
	check(pad.score(s) > 0.15, "passes with CUT get the floor going (%d%%)" % int(pad.score(s) * 100.0))
	check(below == 0, "CUT never digs below the floor (%d cells too deep)" % below)
	check(s.total() == total, "no soil lost digging the dam")
	# Dug too deep, as with the blade pushed down on LOWER, it still counts: a deeper dam's still a dam.
	for n in pad.cells:
		s.bed[n] = int((pad.level - 0.6) * 1000.0)
		s.soil[n] = 0
	check(pad.score(s) > 0.99, "a floor dug 0.6 m too deep still counts (%d%%)" % int(pad.score(s) * 100.0))
	for n in pad.cells:
		s.bed[n] = int((pad.level + 0.4) * 1000.0)
	check(pad.score(s) < 0.01, "but one 0.4 m short doesn't (%d%%)" % int(pad.score(s) * 100.0))
