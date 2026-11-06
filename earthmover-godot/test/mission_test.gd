extends SceneTree
## Checks cracker dust and the driveway jobs, with no drawing. Run: godot --headless --path . -s test/mission_test.gd
## A bot does each job with a player's controls. That says the job can be finished, not that it's any fun.

const DT := 1.0 / 60.0
const Bot := preload("res://test/spread_bot.gd")
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	dust_tests()
	drag_tests()
	spread_button_tests()
	save_tests()
	for job: Dictionary in Mission.LIST:
		if Mission.kind(job) == "pipe":
			pipe_job_test(job)
		elif Mission.is_pad_job(job):
			continue
		elif Mission.kind(job) == "flood":
			flood_job_test(job)
			grade_test(job)
			words_test(job)
			too_deep_test(job)
		else:
			job_test(job)
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)

## Against a file of its own, not the real save.
func save_tests() -> void:
	Mission.save_path = "user://test_progress.cfg"
	DirAccess.remove_absolute(Mission.save_path)
	var second: Dictionary = Mission.LIST[1]
	check(Mission.open(Mission.LIST[0]), "the first job is open from the start")
	check(not Mission.open(second), "the next is shut")
	Mission.mark_done("driveway")
	check(Mission.is_done("driveway") and Mission.open(second), "finishing the first opens it")
	check(Mission.after(Mission.LIST[0]) == second, "and it's the one offered next")
	# Stars: 70% one, 80% two, 90% three, and the best is kept.
	check(Mission.stars_for(0.69) == 0 and Mission.stars_for(0.7) == 1 and Mission.stars_for(0.85) == 2 and Mission.stars_for(0.9) == 3, "stars at 70, 80 and 90%")
	check(Mission.stars("driveway") == 3, "done before there were stars counts as three")
	Mission.mark_done("long_driveway", 1)
	check(Mission.stars("long_driveway") == 1, "one star kept")
	Mission.mark_done("long_driveway", 2)
	Mission.mark_done("long_driveway", 1)
	check(Mission.stars("long_driveway") == 2, "the best kept, not the last")
	check(Mission.open(Mission.find("roof_water")), "a star on the long driveway opens the roof water job")
	DirAccess.remove_absolute(Mission.save_path)

func dust_ok(s: DirtSim) -> bool:
	for n in s.dust.size():
		if s.dust[n] > s.soil[n] or s.dust[n] < 0:
			return false
	return true

func dust_tests() -> void:
	var s := DirtSim.new()
	var put_down := s.add_dust_pile(Vector2.ZERO, 1.5)
	print("      pile: asked 1.50 m3, got %.2f m3" % DirtSim.to_m3(put_down))
	check(absf(DirtSim.to_m3(put_down) - 1.5) < 0.15, "a pile is about the size asked for")
	check(s.dust_total() == put_down, "all of it is dust")
	var mid := DirtSim.cell_of(Vector2.ZERO)
	var height := s.soil[mid.y * DirtSim.CELLS + mid.x]
	for k in 300:
		s.step(DT, 1000000)
	print("      top %d mm, then %d mm once settled" % [height, s.soil[mid.y * DirtSim.CELLS + mid.x]])
	check(s.dust_total() == put_down, "slumping keeps every mm of dust")
	check(dust_ok(s), "and no cell has more dust than soil")
	# Dirt on top of a dust pile mixes, moves with it, and none is lost.
	s.put(mid.x, mid.y, 3000)
	for k in 600:
		s.step(DT, 1000000)
	check(s.dust_total() == put_down and dust_ok(s), "dirt slumping through it keeps the dust too")
	# A blade pushes it along as dust.
	var r: Array = s.blade(Vector2(-2, -1), Vector2(2, -1), Vector2(0, 1), 50, 0)
	check(r[0] > 0 and s.dust_total() == put_down and dust_ok(s), "a blade pushes it, and it's still dust")
	# Falling chunks.
	s.launch(Vector3(4, 3, 4), Vector3.ZERO, 500, 500)
	check(s.dust_total() == put_down + 500, "a falling chunk counts as dust")
	for k in 120:
		s.step(DT, 1000000)
	check(s.dust[DirtSim.cell_of(Vector2(4, 4)).y * DirtSim.CELLS + DirtSim.cell_of(Vector2(4, 4)).x] > 0, "and lands as dust")
	check(s.dust_total() == put_down + 500 and dust_ok(s), "with nothing lost")

func drag_tests() -> void:
	# Back-dragging a heap leaves an even layer, and never cuts the firm ground.
	var s := DirtSim.new()
	var ground := GroundData.new()
	var heap := DirtSim.cell_of(Vector2(0, -6))
	for j in range(heap.y - 2, heap.y + 3):
		for i in range(heap.x - 3, heap.x + 4):
			s.put(i, j, 150, 150)
	var total := s.total()
	var dust_was := s.dust_total()
	var l := Loader.new()
	root.add_child(l)
	l.setup(s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), StandardMaterial3D.new(), Vector2(0, -8.0), Vector2(0, -1), Loader.DINGO)
	check(not l.bucket_low(), "the bucket starts up, so driving doesn't spread by accident")
	# Lower, then back up across it, and on past where it ends.
	l.lift_cmd = -1.0
	for k in 60:
		l.step(DT)
		s.step(DT, 1000000)
	l.lift_cmd = 0.0
	check(l.bucket_low(), "lowered, it's ready to spread")
	print("      word: %s" % l.gauge_word()[0])
	var spread_seen := false
	l.throttle = -1.0
	for k in 480:
		l.step(DT)
		s.step(DT, 1000000)
		spread_seen = spread_seen or l.spreading
	check(spread_seen, "backing up with it low spreads")
	check(s.total() == total, "total unchanged")
	check(s.dust_total() == dust_was and dust_ok(s), "and it's all still dust")
	var depths := {}
	for j in range(heap.y + 3, DirtSim.cell_of(l.spot).y):
		var d: int = s.dust[j * DirtSim.CELLS + heap.x]
		depths[d] = depths.get(d, 0) + 1
	print("      depths behind the bucket, down the middle (mm: cells): %s; machine at %s, bed change %d" % [depths, l.spot, s.bed[heap.y * DirtSim.CELLS + heap.x]])
	var firm_same := true
	for n in s.bed.size():
		if s.bed[n] != 0:
			firm_same = false
			break
	check(firm_same, "the firm ground isn't touched")
	l.queue_free()

## A load tipped from a raised bucket stands as a heap, and the SPREAD button flattens it driving forward, with no scooping.
func spread_button_tests() -> void:
	for which: String in [Loader.DINGO, Loader.BOBCAT]:
		var s := DirtSim.new()
		var ground := GroundData.new()
		var l := Loader.new()
		root.add_child(l)
		l.setup(s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), StandardMaterial3D.new(), Vector2(0, -8.0), Vector2(0, -1), which)
		l.bucket_mm = l.capacity
		l.bucket_dust = l.capacity
		s.held += l.capacity
		var total := s.total()
		l.lift_cmd = 1.0
		for k in 90:
			l.step(DT)
			s.step(DT, 1000000)
		l.lift_cmd = 0.0
		l.curl_cmd = -1.0
		for k in 180:
			l.step(DT)
			s.step(DT, 1000000)
		l.curl_cmd = 0.0
		for k in 240:
			l.step(DT)
			s.step(DT, 1000000)
		var top := 0
		var n_top := 0
		for n in s.dust.size():
			if s.dust[n] > top:
				top = s.dust[n]
				n_top = n
		print("      %s: a full bucket (%.2f m3) tipped stands %d mm high" % [which, DirtSim.to_m3(l.capacity), top])
		check(l.bucket_mm == 0, "%s tipped it all out" % which)
		check(top >= (300 if which == Loader.DINGO else 500), "%s: it lands as a real heap" % which)
		l.toggle_spread()
		for k in 240:
			l.step(DT)
			s.step(DT, 1000000)
		check(l.arm <= l.arm_low + 0.01, "SPREAD lowers the bucket by itself")
		var firm_was := s.bed.duplicate()
		l.throttle = 0.6
		var start := l.spot
		var seen := false
		for k in 300:
			l.step(DT)
			s.step(DT, 1000000)
			seen = seen or l.spreading
		l.throttle = 0.0
		var tallest := 0
		for n in s.dust.size():
			tallest = maxi(tallest, s.dust[n])
		print("      drove %.1f m with SPREAD on: tallest now %d mm" % [l.spot.distance_to(start), tallest])
		check(seen and tallest < top, "driving forward flattens it")
		check(l.bucket_mm == 0, "and none goes in the bucket")
		check(s.bed == firm_was, "and the firm ground isn't cut")
		l.throttle = -0.6
		for k in 300:
			l.step(DT)
			s.step(DT, 1000000)
		l.throttle = 0.0
		check(s.total() == total, "total unchanged")
		check(dust_ok(s), "no cell has more dust than soil")
		l.lift_cmd = 1.0
		l.step(DT)
		check(not l.spread_on, "RAISE turns SPREAD off")
		l.queue_free()

## The roof water job with the real Dingo and its real controls: trench from the downpipe to the drain, lay pipe along it, then fill
## it in with SPREAD from the side the dirt went, in strips across it, twice over.
func pipe_job_test(job: Dictionary) -> void:
	print("--- %s" % job["title"])
	var ground := GroundData.new(Mission.site(job), job["rect"], Mission.road(job))
	var s := DirtSim.new()
	ground.fill_sim(s)
	Mission.lay_out(s, job)
	var total := s.total()
	var pipes := Pipes.new()
	root.add_child(pipes)
	pipes.setup(StandardMaterial3D.new())
	var d := Loader.new()
	root.add_child(d)
	d.setup(s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), StandardMaterial3D.new(), job["start"], job["dir"], job["machine"])
	d.pipes = pipes
	var line_x: float = (job["downpipe"] as Vector2).x
	var drain_z: float = (job["drain"] as Vector2).y
	check(is_zero_approx(Mission.filled_in(s, job)) and not Mission.joined(pipes.points(), job), "nothing's done to start with")
	# The trencher, from as near the downpipe as the house lets it get, out to the drain.
	d.reposition(Vector2(line_x, 0.95), Vector2(0.0, 1.0))
	d.toggle_attachment()
	d.lift_cmd = -1.0
	_run(d, s, 1.0)
	d.lift_cmd = 0.0
	d.throttle = 1.0
	var t := 0.0
	while d.teeth.z < drain_z - 0.1 and t < 60.0:
		_run(d, s, 0.1)
		t += 0.1
	d.stop_commands()
	d.lift_cmd = 1.0
	_run(d, s, 2.0)
	d.stop_commands()
	print("      trench cut in %.0f s, %.1f m of it" % [t, d.trench_m])
	# Pipe, driving along it from the house end.
	d.toggle_attachment()
	d.reposition(Vector2(line_x, 0.95), Vector2(0.0, 1.0))
	d.throttle = 1.0
	t = 0.0
	while d.spot.y < drain_z + 0.9 and t < 40.0:
		_run(d, s, 0.1)
		t += 0.1
	d.stop_commands()
	var pts := pipes.points()
	print("      pipe laid: %.1f m, from %s to %s" % [pipes.length_m, pts[0] if pts.size() > 0 else "-", pts[pts.size() - 1] if pts.size() > 0 else "-"])
	check(Mission.joined(pts, job), "the pipe joins the downpipe to the drain")
	# Back to the bucket and fill it in: SPREAD from the side the dirt went, across the trench.
	d.toggle_attachment()
	var right := 0
	var left := 0
	for z in range(2, 8):
		right += s.soil[DirtSim.cell_of(Vector2(line_x + 1.4, z)).y * DirtSim.CELLS + DirtSim.cell_of(Vector2(line_x + 1.4, z)).x]
		left += s.soil[DirtSim.cell_of(Vector2(line_x - 1.4, z)).y * DirtSim.CELLS + DirtSim.cell_of(Vector2(line_x - 1.4, z)).x]
	var from_side := 1.0 if right > left else -1.0
	for round in 2:
		var z := 0.9
		while z < drain_z + 0.4:
			d.reposition(Vector2(line_x + from_side * 3.6, z), Vector2(-from_side, 0.0))
			d.toggle_spread()
			_run(d, s, 1.0)
			d.throttle = 0.6
			t = 0.0
			while (d.spot.x - line_x) * from_side > -1.2 and t < 15.0:
				_run(d, s, 0.1)
				t += 0.1
			d.stop_commands()
			if d.spread_on:
				d.toggle_spread()
			z += 0.6
		_run(d, s, 2.0)
		print("      filled in after SPREAD round %d: %.0f%%" % [round + 1, Mission.filled_in(s, job) * 100.0])
	var short := ""
	for n in s.bed.size():
		if s.clean_cut[n] == 1 and s.bed[n] + s.soil[n] < s.start_ground[n] - Mission.FILLED_MM:
			short += "(%.2f,%.2f):%d " % [(n % DirtSim.CELLS) * 0.25 - 32.0, (n / DirtSim.CELLS) * 0.25 - 32.0, s.bed[n] + s.soil[n] - s.start_ground[n]]
	print("      short cells: " + short)
	check(Mission.filled_in(s, job) >= Mission.FILL_PASS, "the trench can be filled back in (%.0f%%, need %.0f%%)" % [Mission.filled_in(s, job) * 100.0, Mission.FILL_PASS * 100.0])
	check(s.total() == total, "the total never changes")
	d.queue_free()
	pipes.queue_free()

## The backyard flood with the real Dingo. First the trench at one depth all the way, as a player might: over the rise the floor
## goes up, so the water stops, and it says where. Then the trencher run again deeper under the rise, the pipe drops into the new
## floor, and the water gets through. Then it's filled in.
func flood_job_test(job: Dictionary) -> void:
	print("--- %s" % job["title"])
	var ground := GroundData.new(Mission.site(job), job["rect"], Mission.road(job))
	var s := DirtSim.new()
	ground.fill_sim(s)
	Mission.lay_out(s, job)
	var total := s.total()
	var flood: Vector2 = job["flood"]
	var drain: Vector2 = job["drain"]
	check(s.firm_at(flood) < Mission.water_y(job) - 0.1 and s.firm_at(job["rise"]) > Mission.water_y(job) + 0.1, "the yard's under water (%.2f m) and the rise stands out of it (%.2f m)" % [s.firm_at(flood), s.firm_at(job["rise"])])
	check(s.firm_at(drain) > Mission.water_y(job), "and the drain pit's dry")
	var pipes := Pipes.new()
	root.add_child(pipes)
	pipes.setup(StandardMaterial3D.new())
	var d := Loader.new()
	root.add_child(d)
	d.setup(s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), StandardMaterial3D.new(), job["start"], job["dir"], job["machine"])
	d.pipes = pipes
	var way := (drain - flood).normalized()
	var length := flood.distance_to(drain)
	# The first try: the chain kept at 0.5 m the whole way.
	_trench_along(d, s, flood, drain, func(_k: float) -> float: return -99.0)
	_lay_along(d, s, flood, drain)
	pipes.settle(s)
	var run := Mission.pipe_run(pipes.points(), job)
	var stops := Mission.water_stops_at(run, job)
	print("      one depth all the way: joined %s, water stops at point %d of %d (%s)" % [not run.is_empty(), stops, run.size(), run[stops] if stops >= 0 else "-"])
	check(not run.is_empty() and stops > 0, "the same depth over the rise: joined up, but the water stops partway")
	# Again, the trencher back along it, its depth worked so the floor falls the whole way.
	var top_floor := -0.8
	var low_floor := -1.1
	# A little past the first one's end, as a player would make sure of.
	_trench_along(d, s, flood - way * 0.3, drain + way * 0.3, func(k: float) -> float: return lerpf(top_floor, low_floor, k))
	pipes.settle(s)
	run = Mission.pipe_run(pipes.points(), job)
	stops = Mission.water_stops_at(run, job)
	print("      dug again, falling: joined %s, water stops at %d" % [not run.is_empty(), stops])
	check(not run.is_empty() and stops == -1, "dug deeper under the rise, the pipe drops and the water gets through")
	# Fill it in: SPREAD across it in strips, from the side the dirt went.
	while d.trencher_on or d.pipe_on:
		d.toggle_attachment()
	var across := Vector2(-way.y, way.x)
	var heap := 0
	var other := 0
	for k in range(2, int(length) - 1):
		var c := DirtSim.cell_of(flood + way * k + across * 1.4)
		heap += s.soil[c.y * DirtSim.CELLS + c.x]
		c = DirtSim.cell_of(flood + way * k - across * 1.4)
		other += s.soil[c.y * DirtSim.CELLS + c.x]
	var side := across if heap > other else -across
	for round in 2:
		var k := -0.6
		while k < length + 0.6:
			var mid := flood + way * k
			d.reposition(mid + side * 3.6, -side)
			d.toggle_spread()
			_run(d, s, 1.0)
			d.throttle = 0.6
			var t := 0.0
			while (d.spot - mid).dot(side) > -1.2 and t < 15.0:
				_run(d, s, 0.1)
				t += 0.1
			d.stop_commands()
			if d.spread_on:
				d.toggle_spread()
			k += 0.6
		_run(d, s, 2.0)
		print("      filled in after SPREAD round %d: %.0f%%" % [round + 1, Mission.filled_in(s, job) * 100.0])
	check(Mission.filled_in(s, job) >= Mission.FILL_PASS, "the trench can be filled back in (%.0f%%)" % (Mission.filled_in(s, job) * 100.0))
	check(s.total() == total, "the total never changes")
	d.queue_free()
	pipes.queue_free()

## The backyard the easy way: the trencher with GRADE on (the same button as SPREAD), driven straight from the start ring to the
## drain without touching its depth, then pipe. The water should get through first time.
func grade_test(job: Dictionary) -> void:
	print("--- %s with GRADE" % job["title"])
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
	d.grade_toward = job["drain"]
	d.plan = Mission.trench_plan(s, job)
	var a: Vector2 = Mission.source(job)[0]
	var b: Vector2 = job["drain"]
	var way := (b - a).normalized()
	d.toggle_attachment()
	d.toggle_spread()
	check(d.grade_on, "with the trencher on, SPREAD is GRADE")
	d.reposition(a - way * 0.75, way)
	d.throttle = 1.0
	var t := 0.0
	var short := false
	while (Vector2(d.teeth.x, d.teeth.z) - a).dot(way) < a.distance_to(b) - 0.1 and t < 90.0:
		_run(d, s, 0.1)
		t += 0.1
		short = short or d.grade_short
	d.stop_commands()
	print("      dug with GRADE in %.0f s, the chain at %.2f m at the end, ran out of depth: %s" % [t, d.chain_depth, short])
	check(not short, "GRADE never runs out of depth on this job")
	_lay_along(d, s, a, b)
	pipes.settle(s)
	var run := Mission.pipe_run(pipes.points(), job)
	check(not run.is_empty() and Mission.water_stops_at(run, job) == -1, "dug with GRADE, the water gets through first time")
	d.lift_cmd = 1.0
	d.toggle_attachment()
	d.toggle_attachment()
	d.toggle_attachment()
	d.toggle_spread()
	check(not d.grade_on, "and changing attachment turns GRADE off")
	d.queue_free()
	pipes.queue_free()

## Drives the trencher in a straight line from a to b. `floor_at` gives the floor wanted at each share of the way along, or a
## number under -50 to keep the chain at 0.5 m; the chain's raised and lowered to suit, as a player would.
## Without GRADE, a player who does only what the trench picture says: LOWER while it says to, otherwise just drive. The water
## should get through first time, and the picture should never have had to say a stretch went uphill.
func words_test(job: Dictionary) -> void:
	print("--- %s doing what the trench picture says" % job["title"])
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
	d.grade_toward = job["drain"]
	d.plan = Mission.trench_plan(s, job)
	var b := BucketView.new()
	b.machine = d
	root.add_child(b)
	var a: Vector2 = Mission.source(job)[0]
	var c: Vector2 = job["drain"]
	var way := (c - a).normalized()
	d.toggle_attachment()
	d.reposition(a - way * 0.75, way)
	d.throttle = 1.0
	var t := 0.0
	var said_red := false
	var lowered := 0.0
	var words := {}
	while (Vector2(d.teeth.x, d.teeth.z) - a).dot(way) < a.distance_to(c) - 0.1 and t < 120.0:
		var line := b.trench_line(d)
		var word: String = b.trench_word(d, line["any_uphill"])[0]
		words[word.get_slice(" ", 0)] = true
		if word.begins_with("RED") and not said_red:
			var xs: Array = line["xs"]
			var bits := []
			for k in xs.size():
				if line["cut"][k]:
					bits.append("%.2f:%.3f%s" % [xs[k], line["floors"][k], "!" if line["uphill"][k] else ""])
			print("      first red at %.1f s, chain %.2f aim %.2f: %s" % [t, d.chain_depth, d.aim_depth, " ".join(bits)])
		said_red = said_red or word.begins_with("RED")
		d.lift_cmd = -1.0 if word.begins_with("LOWER") or word.begins_with("GO DEEPER") else (1.0 if word.begins_with("TOO DEEP") else 0.0)
		if d.lift_cmd < 0.0:
			lowered += 0.1
		_run(d, s, 0.1)
		t += 0.1
	d.stop_commands()
	print("      dug in %.0f s, LOWER held %.1f s in all, the chain at %.2f m at the end; it said: %s" % [t, lowered, d.chain_depth, ", ".join(words.keys())])
	check(not said_red, "doing what it says, it never has to say a stretch goes uphill")
	_lay_along(d, s, a, c)
	pipes.settle(s)
	var run := Mission.pipe_run(pipes.points(), job)
	check(not run.is_empty() and Mission.water_stops_at(run, job) == -1, "doing what the trench picture says, the water gets through first time")
	# And a stretch dug going up shows red: lift the chain partway along a fresh cut.
	d.toggle_attachment()
	while not d.trencher_on:
		d.toggle_attachment()
	var a2 := a + Vector2(0.0, 2.0)
	d.reposition(a2 - way * 0.75, way)
	d.throttle = 1.0
	d.lift_cmd = -1.0
	_run(d, s, 0.6)
	d.lift_cmd = 0.0
	_run(d, s, 4.0)
	d.lift_cmd = 1.0
	_run(d, s, 0.3)
	d.lift_cmd = 0.0
	_run(d, s, 3.0)
	d.stop_commands()
	var after := b.trench_line(d)
	print("      lifted the chain partway: it says %s" % b.trench_word(d, after["any_uphill"])[0])
	check(after["any_uphill"], "lifting the chain partway along shows a red stretch")
	b.queue_free()

func _trench_along(d: Loader, s: DirtSim, a: Vector2, b: Vector2, floor_at: Callable) -> void:
	var way := (b - a).normalized()
	if not d.trencher_on:
		while not d.trencher_on:
			d.toggle_attachment()
	d.reposition(a - way * 0.75, way)
	var length := a.distance_to(b)
	var t := 0.0
	d.throttle = 0.0
	while t < 90.0:
		var cut_at := Vector2(d.teeth.x, d.teeth.z)
		var k := clampf((cut_at - a).dot(way) / length, 0.0, 1.0)
		if (cut_at - a).dot(way) > length - 0.1:
			break
		var want: float = floor_at.call(k)
		var side := Vector2(-way.y, way.x)
		var sides := minf(s.firm_at(cut_at + side * 0.65), s.firm_at(cut_at - side * 0.65))
		var depth := 0.5 if want < -50.0 else clampf(sides - want, 0.05, Loader.CHAIN_MOST)
		d.lift_cmd = -1.0 if d.chain_depth < depth - 0.02 else (1.0 if d.chain_depth > depth + 0.02 else 0.0)
		d.throttle = 1.0 if absf(d.chain_depth - depth) < 0.1 else 0.0
		_run(d, s, 1.0 / 60.0)
		t += 1.0 / 60.0
	d.stop_commands()
	d.lift_cmd = 1.0
	_run(d, s, 2.0)
	d.stop_commands()

## The pipe layer along the same line.
func _lay_along(d: Loader, s: DirtSim, a: Vector2, b: Vector2) -> void:
	var way := (b - a).normalized()
	while not d.pipe_on:
		d.toggle_attachment()
	d.reposition(a - way * 0.2, way)
	d.throttle = 1.0
	var t := 0.0
	while (d.spot - a).dot(way) < a.distance_to(b) + 0.9 and t < 60.0:
		_run(d, s, 0.1)
		t += 0.1
	d.stop_commands()

func _run(d: Loader, s: DirtSim, seconds: float) -> void:
	for k in int(seconds / DT):
		d.step(DT)
		s.step(DT, 1000000)

func job_test(job: Dictionary) -> void:
	print("--- %s" % job["title"])
	var ground := GroundData.new(Mission.site(job), job["rect"], Mission.road(job))
	var s := DirtSim.new()
	ground.fill_sim(s)
	var had := s.add_dust_pile(job["pile"], job["pile_m3"])
	var total := s.total()
	var r: Rect2 = job["rect"]
	var a := DirtSim.cell_of(r.position)
	var flat := true
	for j in range(a.y, DirtSim.cell_of(r.end).y):
		for i in range(a.x, DirtSim.cell_of(r.end).x):
			if absi(s.bed[j * DirtSim.CELLS + i]) > 20:
				flat = false
	check(flat, "the driveway is flat")
	var road_at := DirtSim.cell_of(Vector2(0.0, 12.0))
	check(s.rock[road_at.y * DirtSim.CELLS + road_at.x] == 1, "the road can't be dug")
	check(is_zero_approx(Mission.coverage(s, job)), "nothing's done to start with")
	var l := Loader.new()
	root.add_child(l)
	l.setup(s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), StandardMaterial3D.new(), job["start"], job["dir"], job["machine"])
	l.reposition(job["start"], job["dir"])
	var bot := Bot.new(l, s, job)
	var t := 0.0
	var finished_at := -1.0
	var same := true
	var last_print := 0.0
	while t < 1500.0 and bot.trip < bot.want_trips * 3:
		t += DT
		bot.tick(DT)
		l.step(DT)
		s.step(DT, 1000000)
		var cover := Mission.coverage(s, job) if int(t * 60.0) % 30 == 0 else -1.0
		if cover >= Mission.PASS and finished_at < 0.0:
			finished_at = t
			break
		if bot.state == "back_up" and absf(l.speed) < 0.01 and bot.clock > 3.0 and int(t * 60.0) % 600 == 0:
			print("      STUCK %.0f: thr %.2f drive %.2f speed %.3f back %.2f cap %.2f rock %s slip %s pitch %.2f y %.2f at %s teeth %s" % [t, l.throttle, l.drive, l.speed, l.back_speed, l._speed_cap, l.on_rock, l.slipping, l.transform.basis.x.y, l.y_smooth, l.spot, l.teeth])
		if t - last_print > 60.0:
			last_print = t
			print("      %.0f s: trip %d of %d, covered %.0f%%, state %s, at %s, bucket %.2f m3" % [t, bot.trip, bot.want_trips, Mission.coverage(s, job) * 100.0, bot.state, l.spot, DirtSim.to_m3(l.bucket_mm)])
	if s.total() != total:
		same = false
	var cover_now := Mission.coverage(s, job)
	var least := 99999
	var most := 0
	var sum := 0
	var cells := 0
	for j in range(a.y, DirtSim.cell_of(r.end).y):
		for i in range(a.x, DirtSim.cell_of(r.end).x):
			var d := s.dust[j * DirtSim.CELLS + i]
			least = mini(least, d)
			most = maxi(most, d)
			sum += d
			cells += 1
	var carrying := l.bucket_dust + l._pour_dust
	print("      finished at %.0f s after %d trips: covered %.1f%%. On the driveway least %d mm, average %d mm, most %d mm. Dust left off it %.2f m3" % [finished_at, bot.trip, cover_now * 100.0, least, sum / cells, most, DirtSim.to_m3(had - sum * 1)])
	check(finished_at > 0.0, "%s can be finished with %s" % [job["title"], job["machine"]])
	check(same, "the total never changes")
	check(s.dust_total() + carrying == had, "no dust is lost (%d of %d)" % [s.dust_total() + carrying, had])
	check(dust_ok(s), "and no cell has more dust than soil")
	l.queue_free()

## The owner's go: LOWER held down at the start, as if to the bottom. The depth stop holds the chain at the job's line, the aim
## stays that line all the way (it once followed the chain down and asked for more than the trencher has), and doing what the
## picture says gets the water through with no red on the way.
func too_deep_test(job: Dictionary) -> void:
	print("--- %s, LOWER held down at the start" % job["title"])
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
	d.grade_toward = job["drain"]
	d.plan = Mission.trench_plan(s, job)
	var b := BucketView.new()
	b.machine = d
	root.add_child(b)
	var a: Vector2 = Mission.source(job)[0]
	var c: Vector2 = job["drain"]
	var way := (c - a).normalized()
	d.toggle_attachment()
	d.reposition(a - way * 0.75, way)
	d.lift_cmd = -1.0
	_run(d, s, 6.0)
	d.lift_cmd = 0.0
	var first: String = b.trench_word(d, false)[0]
	print("      chain %.2f m, aim %.2f m: \"%s\"" % [d.chain_depth, d.aim_depth, first])
	check(d.chain_depth <= d.aim_depth + 0.03 and not first.begins_with("TOO DEEP"), "LOWER held down, the chain stops at the aim (%.2f m, aim %.2f m)" % [d.chain_depth, d.aim_depth])
	d.throttle = 1.0
	var t := 0.0
	var aim_most := 0.0
	var said_red := false
	while (Vector2(d.teeth.x, d.teeth.z) - a).dot(way) < a.distance_to(c) - 0.1 and t < 120.0:
		var line := b.trench_line(d)
		var word: String = b.trench_word(d, line["any_uphill"])[0]
		aim_most = maxf(aim_most, d.aim_depth)
		said_red = said_red or word.begins_with("RED")
		d.lift_cmd = -1.0 if word.begins_with("LOWER") or word.begins_with("GO DEEPER") else (1.0 if word.begins_with("TOO DEEP") else 0.0)
		_run(d, s, 0.1)
		t += 0.1
	d.stop_commands()
	print("      deepest aim on the way: %.2f m, chain at the end %.2f m" % [aim_most, d.chain_depth])
	check(aim_most < 1.1 and aim_most < Loader.CHAIN_MOST, "the aim stays the job's own line (deepest %.2f m), however deep it was dug" % aim_most)
	check(not said_red, "no stretch goes uphill")
	_lay_along(d, s, a, c)
	pipes.settle(s)
	var run := Mission.pipe_run(pipes.points(), job)
	check(not run.is_empty() and Mission.water_stops_at(run, job) == -1, "and the water gets through first time")
	d.queue_free()
	pipes.queue_free()
	b.queue_free()
