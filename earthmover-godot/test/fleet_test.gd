extends SceneTree
## Checks the dump truck, the Bobcat and the Dingo against the dirt, with no drawing. Run: godot --headless --path . -s test/fleet_test.gd
## These test how they behave, not whether they feel good: only driving them can tell that.

const DT := 1.0 / 60.0
var fails := 0
var ground := GroundData.new()

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func view_of(s: DirtSim) -> GroundView:
	return GroundView.new(ground, s, ground.height_texture(), ground.data_texture())

func new_truck(s: DirtSim, at: Vector2, dir: Vector2) -> Truck:
	var t := Truck.new()
	root.add_child(t)
	t.setup(s, view_of(s), StandardMaterial3D.new(), at, dir)
	return t

func new_loader(s: DirtSim, at: Vector2, dir: Vector2, kind: String) -> Loader:
	var l := Loader.new()
	root.add_child(l)
	l.setup(s, view_of(s), StandardMaterial3D.new(), at, dir, kind)
	return l

func run(s: DirtSim, machines: Array, seconds: float) -> bool:
	var start := s.total()
	var same := true
	for t in int(seconds / DT):
		for m: Variant in machines:
			m.step(DT)
		s.step(DT, 1000000)
		if s.total() != start:
			same = false
	return same

func _init() -> void:
	truck_tests()
	bobcat_tests()
	dingo_tests()
	spread_over_trench_test()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)

## A filled trench, and SPREAD driven across it: the bucket rides over on the ground either side and doesn't dig the fill back out.
func spread_over_trench_test() -> void:
	var s := DirtSim.new()
	var j0 := DirtSim.cell_of(Vector2(0, 0)).y
	var i0 := DirtSim.cell_of(Vector2(-12, 0)).x
	var i1 := DirtSim.cell_of(Vector2(0, 0)).x
	for i in range(i0, i1):
		for j in range(j0 - 12, j0 + 12):
			var n := j * DirtSim.CELLS + i
			if j == j0 or j == j0 - 1:
				s.bed[n] = -1500
				s.soil[n] = 1520
				s.clean_cut[n] = 1
			else:
				s.soil[n] = 50
	var d := new_loader(s, Vector2(-6.0, 2.5), Vector2(0.0, -1.0), Loader.DINGO)
	var total := s.total()
	d.toggle_spread()
	run(s, [d], 1.0)
	d.throttle = 0.6
	run(s, [d], 6.0)
	d.stop_commands()
	var lowest := 9999
	for i in range(DirtSim.cell_of(Vector2(-6.4, 0)).x, DirtSim.cell_of(Vector2(-5.6, 0)).x):
		for j in [j0 - 1, j0]:
			lowest = mini(lowest, s.bed[j * DirtSim.CELLS + i] + s.soil[j * DirtSim.CELLS + i])
	print("      filled trench after a SPREAD pass across it: lowest %d mm" % lowest)
	check(lowest > -60, "SPREAD across a filled trench leaves it filled")
	check(s.total() == total, "and the total never changes")
	d.queue_free()

func truck_tests() -> void:
	var s := DirtSim.new()
	var t := new_truck(s, Vector2(-20, 0), Vector2(1, 0))
	var total := s.total()
	t.throttle = 1.0
	run(s, [t], 6.0)
	check(t.speed > 6.0, "empty, it gets up to speed (%.1f m/s)" % t.speed)
	var was_angle := t.angle
	t.throttle = 0.0
	run(s, [t], 3.0)
	check(absf(t.speed) < 0.05, "it stops when let go")
	t.steer = 1.0
	run(s, [t], 2.0)
	check(absf(t.angle - was_angle) < 0.01, "it can't turn on the spot like a track machine")
	t.throttle = 1.0
	run(s, [t], 2.0)
	check(t.angle < was_angle - 0.1, "it steers to the right while moving (%.2f rad)" % (was_angle - t.angle))
	t.stop_commands()
	run(s, [t], 3.0)

	# Soil dropped on the tray stays there and is counted.
	var q := DirtSim.new()
	q.store = 200000
	var r := new_truck(q, Vector2(0, 0), Vector2(1, 0))
	var q_total := q.total()
	var mid := r.transform * (Truck.HINGE + Vector3(2.3, 3.0, 0.0))
	var dropped := 0
	for k in 40:
		q.store -= 1600
		dropped += 1600
		q.launch(mid + Vector3(k % 3 - 1.0, 0.0, 0.0) * 0.5, Vector3(0.0, -0.5, 0.0), 1600)
		run(q, [r], 0.1)
	run(q, [r], 2.0)
	check(q.total() == q_total, "dropping soil in: the total never changes")
	check(r.tray_mm == dropped, "soil landing on the tray stays in it (%.1f of %.1f m3)" % [DirtSim.to_m3(r.tray_mm), DirtSim.to_m3(dropped)])
	check(q.held == r.tray_mm, "held soil is what's in the tray")
	check(q.loose_total() == 0, "and none reached the ground")

	# Soil dropped beside it goes on past to the ground.
	q.store -= 800
	q.launch(r.transform * (Vector3(0.0, 2.5, 3.0)), Vector3(0.0, -0.5, 0.0), 800)
	run(q, [r], 1.5)
	check(q.loose_total() == 800, "soil dropped beside it lands on the ground")

	# Heavier and slower, loaded.
	var light := Truck.TOP_SPEED_EMPTY
	r.tray_mm = Truck.CAPACITY
	q.held = Truck.CAPACITY
	q.store = 0
	var full_total := q.total()
	r.throttle = 1.0
	run(q, [r], 6.0)
	r.throttle = 0.0
	check(r.speed < light * 0.75, "loaded, it's slower (%.1f m/s)" % r.speed)
	run(q, [r], 3.0)

	# Tipping pours it all out behind.
	var loose_was := q.loose_total()
	r.tip_cmd = 1.0
	var same := run(q, [r], 8.0)
	r.tip_cmd = 0.0
	same = run(q, [r], 4.0) and same
	check(same and q.total() == full_total, "tipping 8 m3 out: the total never changes")
	check(r.tray_mm == 0 and q.held == 0, "the tray empties (%d mm left)" % r.tray_mm)
	check(q.in_air == 0, "it has all landed")
	check(q.loose_total() - loose_was == Truck.CAPACITY, "it's all on the ground (%.1f m3)" % DirtSim.to_m3(q.loose_total() - loose_was))
	check(r.tip == 0.0, "and the tray comes back down when let go")

	# The excavator fills it.
	var w := DirtSim.new()
	for j in range(90, 170):
		for i in range(148, 200):
			w.soil[j * DirtSim.CELLS + i] = 1500
	var w_total := w.total()
	var e := Excavator.new()
	root.add_child(e)
	e.setup(w, view_of(w), StandardMaterial3D.new(), Vector2(0, 0), Vector2(1, 0))
	var u := new_truck(w, Vector2(0, 6.8), Vector2(1, 0))
	for bite in 2:
		e.curl_cmd = -1.0
		e.reach_cmd = 1.0
		e.raise_cmd = 0.6
		run(w, [e, u], 1.6)
		e.stop_commands()
		e.raise_cmd = -1.0
		run(w, [e, u], 2.2)
		e.stop_commands()
		e.reach_cmd = -1.0
		e.raise_cmd = -0.1
		run(w, [e, u], 2.6)
		e.stop_commands()
		e.raise_cmd = 1.0
		e.curl_cmd = 1.0
		run(w, [e, u], 2.5)
		e.stop_commands()
		e.swing_cmd = 1.0
		run(w, [e, u], 2.1)
		e.stop_commands()
		e.curl_cmd = -1.0
		run(w, [e, u], 2.2)
		e.stop_commands()
		e.curl_cmd = 1.0
		e.swing_cmd = -1.0
		run(w, [e, u], 2.3)
		e.stop_commands()
	run(w, [e, u], 2.0)
	print("      excavator: swing reached %s, tray %.2f m3" % [e.swing, DirtSim.to_m3(u.tray_mm)])
	check(w.total() == w_total, "excavator into truck: the total never changes")
	check(DirtSim.to_m3(u.tray_mm) > 0.6, "the excavator's load lands in the tray (%.2f m3 in 2 bites)" % DirtSim.to_m3(u.tray_mm))

func bobcat_tests() -> void:
	# Drives quick, spins on the spot.
	var s := DirtSim.new()
	var b := new_loader(s, Vector2(-20, 0), Vector2(1, 0), Loader.BOBCAT)
	b.lift_cmd = 1.0
	run(s, [b], 0.8)
	b.lift_cmd = 0.0
	b.throttle = 1.0
	run(s, [b], 4.0)
	check(b.speed > 3.0, "the Bobcat gets moving (%.1f m/s)" % b.speed)
	b.throttle = 0.0
	run(s, [b], 2.0)
	var was_spot := b.spot
	var was_angle := b.angle
	b.steer = 1.0
	run(s, [b], 2.0)
	check(absf(b.angle - was_angle) > 2.0, "it spins on the spot (%.1f rad)" % absf(b.angle - was_angle))
	check(b.spot.distance_to(was_spot) < 0.5, "without going anywhere")
	b.queue_free()

	# Into a layer of loose soil with the bucket low: it fills, and the soil's gone from the ground.
	var c := DirtSim.new()
	for j in range(90, 170):
		for i in range(90, 200):
			c.soil[j * DirtSim.CELLS + i] = 400
	var c_total := c.total()
	var l := new_loader(c, Vector2(-14, 0), Vector2(1, 0), Loader.BOBCAT)
	l.arm = l.arm_low
	l.curl = -0.02
	l.throttle = 1.0
	var same := run(c, [l], 5.0)
	check(same and c.total() == c_total, "scooping: the total never changes")
	print("      bobcat edge at %.2f m, went %.1f m, bucket %.2f m3, %.1f m/s" % [l.teeth.y, l.spot.x + 14.0, DirtSim.to_m3(l.bucket_mm), l.speed])
	check(l.fill() > 0.9, "the bucket fills (%.2f m3)" % DirtSim.to_m3(l.bucket_mm))
	check(c.held == l.bucket_mm + l._pour_store, "what's held is what's in the bucket")
	check(l.bucket_mm <= l.capacity, "and it can't hold more than it holds")

	# Curl, lift, tip: it falls out in front.
	l.throttle = 0.0
	l.curl_cmd = 1.0
	l.lift_cmd = 1.0
	run(c, [l], 1.5)
	l.curl_cmd = 0.0
	l.lift_cmd = 0.0
	var held := l.bucket_mm
	check(held > l.capacity * 0.85, "it keeps its load lifted and curled (%.2f m3)" % DirtSim.to_m3(held))
	check(l.teeth.y > 0.8, "the bucket comes up off the ground (%.1f m)" % l.teeth.y)
	l.curl_cmd = -1.0
	same = run(c, [l], 2.0)
	l.curl_cmd = 0.0
	same = run(c, [l], 2.0) and same
	check(same and c.total() == c_total, "tipping it out: the total never changes")
	check(l.bucket_mm == 0 and c.held == 0, "the bucket empties")
	l.queue_free()

	# A real pile from where it starts.
	var r := DirtSim.new()
	ground.fill_sim(r)
	var r_total := r.total()
	var p := new_loader(r, GroundData.bobcat_spot(), (GroundData.PILE - GroundData.bobcat_spot()).normalized(), Loader.BOBCAT)
	p.lift_cmd = -1.0
	p.curl_cmd = -0.2
	run(r, [p], 1.0)
	p.stop_commands()
	p.throttle = 1.0
	var from := p.spot
	run(r, [p], 6.0)
	print("      real pile: went %.1f m, bucket %.2f m3, %.2f m/s" % [p.spot.distance_to(from), DirtSim.to_m3(p.bucket_mm), p.speed])
	check(p.fill() > 0.9, "driven at the real pile, it fills (%.2f m3)" % DirtSim.to_m3(p.bucket_mm))
	check(p.position.y - r.firm_at(p.spot) < 3.0, "and it doesn't climb into the sky")
	check(r.total() == r_total, "the total never changes")
	p.queue_free()

func dingo_tests() -> void:
	# Small and slower than the Bobcat. Its bucket fills too, a much smaller one.
	var c := DirtSim.new()
	for j in range(90, 170):
		for i in range(90, 200):
			c.soil[j * DirtSim.CELLS + i] = 300
	var c_total := c.total()
	var l := new_loader(c, Vector2(-14, 0), Vector2(1, 0), Loader.DINGO)
	l.arm = l.arm_low
	l.curl = -0.02
	l.throttle = 1.0
	run(c, [l], 4.0)
	print("      dingo edge at %.2f m, went %.1f m, bucket %.3f m3, %.1f m/s" % [l.teeth.y, l.spot.x + 14.0, DirtSim.to_m3(l.bucket_mm), l.speed])
	check(l.fill() > 0.9, "the Dingo's bucket fills (%.2f m3)" % DirtSim.to_m3(l.bucket_mm))
	check(DirtSim.to_m3(l.capacity) < 0.2, "and it's a small one")
	check(c.total() == c_total, "the total never changes")
	# Swapping to the trencher with soil in the bucket: nothing is lost.
	l.throttle = 0.0
	l.toggle_attachment()
	run(c, [l], 1.0)
	check(c.total() == c_total and c.held == 0, "swapping attachments with a full bucket loses nothing")
	check(l.trencher_on and not l._bucket.visible and l._chain.visible, "the trencher replaces the bucket")
	l.toggle_attachment()
	check(l.pipe_on and not l.trencher_on and l._spool.visible and not l._chain.visible, "next comes the pipe layer")
	l.toggle_attachment()
	check(not l.pipe_on and not l.trencher_on and l._bucket.visible, "and back to the bucket")
	l.queue_free()

	# The Bobcat's big trencher (owner, 9 Nov): a wider, deeper slot than the Dingo's, and the big pipe down it.
	var b0 := DirtSim.new()
	var b0_total := b0.total()
	var bc := new_loader(b0, Vector2(-10, 0), Vector2(1, 0), Loader.BOBCAT)
	bc.toggle_attachment()
	check(bc.trencher_on and bc._chain.visible and not bc._bucket.visible and bc._arms.visible, "the Bobcat takes its big trencher, on the end of its arms")
	bc.lift_cmd = -1.0
	run(b0, [bc], 3.0)
	bc.lift_cmd = 0.0
	check(bc.chain_depth >= 1.95, "LOWER takes its chain down to 2 m (%.2f m)" % bc.chain_depth)
	bc.throttle = 1.0
	var b_same := run(b0, [bc], 20.0)
	bc.stop_commands()
	check(b_same and b0.total() == b0_total, "cutting the big trench: the total never changes")
	var mid_c := DirtSim.cell_of(Vector2(bc.spot.x - 0.6, 0.0))
	var wide_cells := 0
	var deepest_b := 0
	for j in range(mid_c.y - 4, mid_c.y + 5):
		var hb := b0.bed[j * DirtSim.CELLS + mid_c.x]
		if hb < -1000:
			wide_cells += 1
		deepest_b = mini(deepest_b, hb)
	var at_wheel := b0.soil[DirtSim.cell_of(Vector2(bc.spot.x - 0.6, 0.84)).y * DirtSim.CELLS + mid_c.x]
	var heap_b := 0
	for j in range(mid_c.y + 4, mid_c.y + 12):
		heap_b = maxi(heap_b, b0.soil[j * DirtSim.CELLS + mid_c.x])
	print("      big trench: %d cells wide, floor %d mm, went %.1f m; dirt %d mm under the right wheels, %d mm at most further out" % [wide_cells, deepest_b, bc.spot.x + 10.0, at_wheel, heap_b])
	check(wide_cells == 3, "its slot is three cells wide, half as wide again as the Dingo's two (%d)" % wide_cells)
	check(deepest_b < -1850 and deepest_b > -2150, "and as deep as it's set, 2 m, its walls standing (%d mm)" % deepest_b)
	check(heap_b > at_wheel * 2, "the dirt's thrown out past its right-hand wheels (%d mm under them, %d further out)" % [at_wheel, heap_b])
	var bp := Pipes.new()
	root.add_child(bp)
	bp.setup(StandardMaterial3D.new(), Pipes.BIG_RADIUS)
	bc.pipes = bp
	bc.lift_cmd = 1.0
	run(b0, [bc], 3.0)
	bc.lift_cmd = 0.0
	bc.toggle_attachment()
	check(bc.pipe_on and bc._spool.visible and not bc._chain.visible, "next, the big pipe")
	bc.throttle = -1.0
	run(b0, [bc], 12.0)
	bc.stop_commands()
	print("      big pipe: %.1f m in %d lengths" % [bp.length_m, bp.segments()])
	check(bp.length_m > 2.0, "backing along the trench lays it (%.1f m)" % bp.length_m)
	var mid_b: Vector3 = bp._points[bp._points.size() / 2]
	var sits := b0.firm_at(Vector2(mid_b.x, mid_b.z)) + Pipes.BIG_RADIUS + 0.02
	check(absf(mid_b.y - sits) < 0.06, "it lies on the trench floor, all 40 cm of it (%.2f m off)" % absf(mid_b.y - sits))
	bc.toggle_attachment()
	check(not bc.pipe_on and not bc.trencher_on and bc._bucket.visible, "and round to the bucket again")
	check(bc.top_speed > 3.0, "at full speed again with it (%.1f m/s)" % bc.top_speed)
	bc.queue_free()
	bp.queue_free()

	# A straight trench through firm ground.
	var t := DirtSim.new()
	var t_total := t.total()
	var d := new_loader(t, Vector2(-10, 0), Vector2(1, 0), Loader.DINGO)
	d.toggle_attachment()
	d.lift_cmd = -1.0
	run(t, [d], 2.0)
	d.lift_cmd = 0.0
	var set_depth := d.chain_depth
	check(set_depth >= 1.45, "LOWER sets the chain right down (%.2f m)" % set_depth)
	d.throttle = 1.0
	var same := run(t, [d], 20.0)
	d.stop_commands()
	check(same and t.total() == t_total, "cutting a trench: the total never changes")
	check(d.speed <= 0.61, "it crawls with the chain in the ground (%.2f m/s)" % d.speed)
	var cut_from := -9.0
	var cut_to := d.spot.x - 0.5
	print("      trench from x %.1f to %.1f at %.2f m set" % [cut_from, cut_to, set_depth])
	check(cut_to - cut_from > 3.0, "it covered some ground (%.1f m)" % (cut_to - cut_from))
	var deepest := 0.0
	var shallowest := 99.0
	var x := cut_from
	while x < cut_to:
		var h := t.firm_at(Vector2(x, 0.0))
		deepest = minf(deepest, h)
		shallowest = minf(shallowest, -h)
		x += DirtSim.CELL_M
	var run_cells := DirtSim.cell_of(Vector2(cut_from + 1.0, 0.0))
	var floor_h := (t.bed[run_cells.y * DirtSim.CELLS + run_cells.x] + t.soil[run_cells.y * DirtSim.CELLS + run_cells.x]) * 0.001
	check(floor_h < -set_depth * 0.8, "the trench goes down as deep as set (floor %.2f m, set %.2f m)" % [floor_h, set_depth])
	var beside := t.bed[(run_cells.y - 2) * DirtSim.CELLS + run_cells.x]
	check(beside == 0, "it's narrow: the firm ground 50 cm to the left is untouched (%d mm)" % beside)
	var ridge := 0
	for j in range(run_cells.y + 2, run_cells.y + 8):
		ridge = maxi(ridge, t.soil[j * DirtSim.CELLS + run_cells.x])
	check(ridge > 30, "the dirt lands to the right (%d mm)" % ridge)
	# Dug ground swells, so there's more than enough to fill the trench again.
	var dug := 0
	var loose := 0
	for n in t.bed.size():
		dug += maxi(-t.bed[n], 0)
		loose += t.soil[n]
	check(loose > dug * 1.3, "dug dirt swells: %.2f m3 loose from a %.2f m3 trench" % [DirtSim.to_m3(loose), DirtSim.to_m3(dug)])

	# The walls hold: left a while, a metre-deep slot doesn't cave in.
	var wall_before := t.bed[run_cells.y * DirtSim.CELLS + run_cells.x]
	run(t, [d], 10.0)
	var wall_after := t.bed[run_cells.y * DirtSim.CELLS + run_cells.x] + t.soil[run_cells.y * DirtSim.CELLS + run_cells.x]
	check(wall_after < -set_depth * 0.6, "the cut walls stand up (%d mm before, %d mm after 10 s)" % [wall_before, wall_after])
	check(t.total() == t_total, "still the same total")

	# Pipe goes down a trench, joined up, and nowhere else.
	var pp := Pipes.new()
	root.add_child(pp)
	pp.setup(StandardMaterial3D.new())
	d.pipes = pp
	d.toggle_attachment()
	check(d.pipe_on, "on to the pipe layer")
	var total_before := t.total()
	d.throttle = -1.0
	var pipe_same := run(t, [d], 14.0)
	d.stop_commands()
	print("      pipe: %.1f m in %d lengths, machine at x %.1f, trench %s" % [pp.length_m, pp.segments(), d.spot.x, d.in_trench])
	check(pp.length_m > 2.0, "driving back along it lays pipe (%.1f m)" % pp.length_m)
	check(pipe_same and t.total() == total_before, "laying pipe moves no soil")
	# The middle of the run, as its ends ride up the ramps at each end of the trench.
	var mid_p: Vector3 = pp._points[pp._points.size() / 2]
	var mid_ground := t.height_at(Vector2(mid_p.x, mid_p.z))
	check(absf(mid_p.y - mid_ground) < 0.4, "the pipe lies on the trench floor (%.2f m off)" % absf(mid_p.y - mid_ground))
	var lowest_pipe := 0.0
	for pt: Vector3 in pp._points:
		lowest_pipe = minf(lowest_pipe, pt.y)
	check(lowest_pipe < -1.0, "well below the surface (%.2f m)" % lowest_pipe)
	var flat := DirtSim.new()
	var g2 := new_loader(flat, Vector2(-8, 0), Vector2(1, 0), Loader.DINGO)
	var pp2 := Pipes.new()
	root.add_child(pp2)
	pp2.setup(StandardMaterial3D.new())
	g2.pipes = pp2
	g2.toggle_attachment()
	g2.toggle_attachment()
	g2.throttle = 1.0
	run(flat, [g2], 6.0)
	check(pp2.length_m == 0.0, "on flat ground it lays nothing")
	g2.queue_free()

	# Filling it back in: a bucket of the dirt from the ridge, tipped over the slot, goes down it.
	var bob := new_loader(t, Vector2(-7.0, 1.55), Vector2(0.0, -1.0), Loader.BOBCAT)
	var fill_total := t.total()
	var sample := Vector2(-7.0, 0.0)
	var floor_before := t.height_at(sample)
	for trip in 2:
		for j in range(DirtSim.cell_of(Vector2(0.0, 1.0)).y, DirtSim.cell_of(Vector2(0.0, 3.5)).y):
			for i in range(DirtSim.cell_of(Vector2(-10.0, 0.0)).x, DirtSim.cell_of(Vector2(-4.0, 0.0)).x):
				if bob.bucket_mm < bob.capacity and t.soil[j * DirtSim.CELLS + i] > 0:
					var r: Array = t.bite(i, j, mini(t.soil[j * DirtSim.CELLS + i], bob.capacity - bob.bucket_mm), 0)
					bob.bucket_mm += r[0]
		bob.arm = lerpf(bob.arm_low, bob.arm_high, 0.3)
		bob.curl = 0.1
		bob.curl_cmd = -1.0
		run(t, [bob], 2.5)
		bob.stop_commands()
		run(t, [bob], 1.5)
	var floor_after := t.height_at(sample)
	print("      filling: floor %.2f to %.2f m, bucket left %.2f, edge over z %.2f, in air %d" % [floor_before, floor_after, DirtSim.to_m3(bob.bucket_mm), bob.teeth.z, t.air_amt.size()])
	check(t.total() == fill_total, "filling the trench: the total never changes")
	check(floor_after > floor_before + 0.3, "a Bobcat can tip soil back in the trench (%.2f to %.2f m)" % [floor_before, floor_after])
	bob.queue_free()

	# Steering while it cuts must not dig it into a crater: the owner would do this at once.
	var sc := DirtSim.new()
	var ms := new_loader(sc, Vector2(-14, -4), Vector2(1, 0), Loader.DINGO)
	ms.toggle_attachment()
	ms.lift_cmd = -1.0
	run(sc, [ms], 1.0)
	ms.lift_cmd = 0.0
	var depth_set := ms.chain_depth
	ms.throttle = 1.0
	var lowest_machine := 0.0
	var clock := 0.0
	for k in 1800:
		clock += DT
		ms.steer = sin(clock * 0.9)
		ms.step(DT)
		sc.step(DT, 1000000)
		lowest_machine = minf(lowest_machine, ms.position.y)
	var lowest_floor := 0
	for n in sc.bed.size():
		lowest_floor = mini(lowest_floor, sc.bed[n])
	print("      steering: set %.2f m, floor reached %.2f m, machine lowest %.2f m, went %.1f m, %.2f m/s, pitch %.1f deg" % [depth_set, lowest_floor * 0.001, lowest_machine, ms.spot.x + 14.0, ms.speed, rad_to_deg(ms.transform.basis.x.y)])
	check(lowest_floor * 0.001 > -depth_set - 0.1, "steering, the cut stays at the depth set (%.2f m, set %.2f m)" % [lowest_floor * 0.001, depth_set])
	check(lowest_machine > -0.25, "and the machine rides over it, not into it (%.2f m)" % lowest_machine)
	check(ms.spot.x + 14.0 > 3.0, "and it keeps going (%.1f m)" % (ms.spot.x + 14.0))
	ms.queue_free()

	# Rock stops it.
	var r := DirtSim.new()
	for j in range(110, 150):
		for i in range(136, 150):
			r.rock[j * DirtSim.CELLS + i] = 1
	var z := new_loader(r, Vector2(-1, 0), Vector2(1, 0), Loader.DINGO)
	z.toggle_attachment()
	z.lift_cmd = -1.0
	run(r, [z], 1.0)
	z.lift_cmd = 0.0
	z.throttle = 1.0
	var saw_rock := false
	for k in 600:
		z.step(DT)
		r.step(DT, 1000000)
		saw_rock = saw_rock or z.on_rock
	check(saw_rock, "the trencher reports rock")
	z.queue_free()
	d.queue_free()
