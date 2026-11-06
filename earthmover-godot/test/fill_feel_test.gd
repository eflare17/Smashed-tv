extends SceneTree
## Filling a trench in, as it feels: how far the Dingo leans and how jerkily, and how much one
## SPREAD run along the trench fills. Run: godot --headless --path . -s test/fill_feel_test.gd

const DT := 1.0 / 60.0
var roll_most := 0.0
var pitch_most := 0.0
var lean_moved := 0.0
var lean_time := 0.0
var _last_up := Vector3.UP
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	var job := Mission.find("backyard")
	var ground := GroundData.new(Mission.site(job), job["rect"], Mission.road(job))
	var s := DirtSim.new()
	ground.fill_sim(s)
	Mission.lay_out(s, job)
	var pipes := Pipes.new()
	root.add_child(pipes)
	pipes.setup(StandardMaterial3D.new())
	var d := Loader.new()
	root.add_child(d)
	d.setup(s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), StandardMaterial3D.new(), job["start"], job["dir"], job["machine"])
	d.pipes = pipes
	var a: Vector2 = job["inlet"]
	var b: Vector2 = job["drain"]
	var way := (b - a).normalized()
	var across := Vector2(-way.y, way.x)
	_trench(d, s, a - way * 0.3, b + way * 0.3)
	while not d.pipe_on:
		d.toggle_attachment()
	d.reposition(a - way * 0.5, way)
	d.throttle = 1.0
	_run(d, s, 14.0, false)
	d.stop_commands()
	while d.trencher_on or d.pipe_on:
		d.toggle_attachment()
	var heap := 0
	var other := 0
	for k in range(2, int(a.distance_to(b)) - 1):
		var c := DirtSim.cell_of(a + way * k + across * 1.4)
		heap += s.soil[c.y * DirtSim.CELLS + c.x]
		c = DirtSim.cell_of(a + way * k - across * 1.4)
		other += s.soil[c.y * DirtSim.CELLS + c.x]
	var side := across if heap > other else -across
	print("filled after trench and pipe: %.0f%%" % (Mission.filled_in(s, job) * 100.0))
	# Driving along it, the bucket over it, with SPREAD on, there and back.
	for pass_n in 3:
		var from := a - way * 0.8 if pass_n % 2 == 0 else b + way * 0.8
		var dir := way if pass_n % 2 == 0 else -way
		d.reposition(from + side * 0.3, dir)
		if not d.spread_on:
			d.toggle_spread()
		_run(d, s, 1.0, false)
		d.throttle = 0.7
		_reset_lean(d)
		var t := 0.0
		while (d.spot - from).dot(dir) < a.distance_to(b) + 1.4 and t < 30.0:
			# Keeping it on the line, as a player steering would.
			var off := (d.spot - (from + side * 0.3)).dot(side)
			var heading := Vector2(cos(d.angle), -sin(d.angle))
			d.steer = clampf(-off * 2.0 * signf(heading.dot(dir)) + heading.cross(dir) * 3.0, -1.0, 1.0)
			_run(d, s, 0.1, true)
			t += 0.1
		d.stop_commands()
		if pass_n == 0:
			check(Mission.filled_in(s, job) >= Mission.STARS[0] and roll_most <= 8.5, "one SPREAD run along the trench fills a star's worth, leaning no more than 8 degrees")
		elif pass_n == 1:
			check(Mission.filled_in(s, job) >= Mission.FILL_PASS, "two runs fill it for three stars")
		print("along, pass %d: filled %.0f%% in %.0f s   lean: roll most %.1f deg, pitch most %.1f deg, wobble %.1f deg/s" % [pass_n + 1, Mission.filled_in(s, job) * 100.0, t, roll_most, pitch_most, lean_moved / maxf(lean_time, 0.01)])
	funnel_test()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)

## Dirt tipped just beside a trench that's still low goes into it, not on the grass beside it.
func funnel_test() -> void:
	var s := DirtSim.new()
	s.mark_start_ground()
	var slot := DirtSim.cell_of(Vector2(0.0, 0.0))
	for dj in range(-4, 5):
		s.trench(Vector2i(slot.x, slot.y + dj), -400, 10000, Vector2i(slot.x + 20, slot.y))
	var in_slot := func() -> int:
		var t := 0
		for dj in range(-4, 5):
			t += s.soil[(slot.y + dj) * DirtSim.CELLS + slot.x]
		return t
	var low: int = in_slot.call()
	var beside := DirtSim.cell_of(Vector2(0.6, 0.0))
	var was_beside := s.soil[beside.y * DirtSim.CELLS + beside.x]
	for k in 10:
		s.launch(Vector3(0.6, 0.5, 0.0), Vector3(0.0, -1.0, 0.0), 30)
	for k in 120:
		s.step(DT, 1000000)
	check(in_slot.call() - low == 300 and s.soil[beside.y * DirtSim.CELLS + beside.x] == was_beside, "dirt dumped 0.6 m from the trench falls in it (%d of 300 mm)" % (in_slot.call() - low))

func _reset_lean(d: Loader) -> void:
	roll_most = 0.0
	pitch_most = 0.0
	lean_moved = 0.0
	lean_time = 0.0
	_last_up = d.transform.basis.y.normalized()

func _trench(d: Loader, s: DirtSim, a: Vector2, b: Vector2) -> void:
	var way := (b - a).normalized()
	while not d.trencher_on:
		d.toggle_attachment()
	d.reposition(a - way * 0.75, way)
	var length := a.distance_to(b)
	var t := 0.0
	while t < 90.0:
		var cut_at := Vector2(d.teeth.x, d.teeth.z)
		var k := clampf((cut_at - a).dot(way) / length, 0.0, 1.0)
		if (cut_at - a).dot(way) > length - 0.1:
			break
		var want := lerpf(-0.8, -1.1, k)
		var side := Vector2(-way.y, way.x)
		var sides := minf(s.firm_at(cut_at + side * 0.65), s.firm_at(cut_at - side * 0.65))
		var depth := clampf(sides - want, 0.05, Loader.CHAIN_MOST)
		d.lift_cmd = -1.0 if d.chain_depth < depth - 0.02 else (1.0 if d.chain_depth > depth + 0.02 else 0.0)
		d.throttle = 1.0 if absf(d.chain_depth - depth) < 0.1 else 0.0
		_run(d, s, DT, false)
		t += DT
	d.stop_commands()

func _run(d: Loader, s: DirtSim, seconds: float, watch: bool) -> void:
	for k in maxi(int(seconds / DT), 1):
		d.step(DT)
		s.step(DT, 1000000)
		if watch:
			var bs := d.transform.basis
			var up := bs.y.normalized()
			roll_most = maxf(roll_most, rad_to_deg(absf(asin(clampf(bs.z.normalized().y, -1.0, 1.0)))))
			pitch_most = maxf(pitch_most, rad_to_deg(absf(asin(clampf(bs.x.normalized().y, -1.0, 1.0)))))
			lean_moved += rad_to_deg(up.angle_to(_last_up))
			lean_time += DT
			_last_up = up
