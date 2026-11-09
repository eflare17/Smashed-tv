extends SceneTree
## Checks the Bike jumps job. Run: godot --headless --path . -s test/jumps_test.gd
## Three tabletops pegged out on the paddock, about 1, 1.5 and 2 m tall, with heaps of dirt beside the track holding enough to build
## them; scored forgivingly on their shape; the normal dozer's CUT shapes a heaped-up jump without cutting it too low; the bike
## rides all three built; and in the whole game the job starts with the normal machines and the bike on site.
## These check what the job does, not whether it's fun: only playing it can tell that.

const DT := 1.0 / 60.0
var fails := 0
var g: Node
var t := 0

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	# Kept off the real progress: the end of the job marks it done.
	Mission.save_path = "user://test_progress.cfg"
	layout_test()
	score_test()
	dozer_test()
	bike_test()
	DirtSim.set_world(32.0)
	Engine.set_meta("mission", "bike_jumps")
	g = load("res://main.tscn").instantiate()
	root.add_child(g)

func _world(heaps := true) -> Array:
	var job := Mission.find("bike_jumps")
	DirtSim.set_world(48.0)
	var ground := GroundData.new(Mission.site(job), Rect2(), Rect2(), true)
	var s := DirtSim.new()
	ground.fill_sim(s)
	s.mark_start_ground()
	if heaps:
		Mission.lay_out(s, job)
	return [ground, s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), job]

## Builds every jump to its shape, plus `extra` m, as loose dirt sloping off past the pegs.
func build(s: DirtSim, _p: Pad, extra := 0.0) -> void:
	Mission.build_jumps(s, Mission.find("bike_jumps"), extra)

## Where it goes: three tabletops getting bigger along a straight track inside the fence, the heaps beside it holding enough, and
## everything starting clear.
func layout_test() -> void:
	var w := _world()
	var s: DirtSim = w[1]
	var job: Dictionary = w[3]
	var p := Mission.pad_for(s, job)
	var jumps: Array = job["jumps"]
	check(jumps.size() == 3, "three jumps")
	var need := 0.0
	var tall: Array[float] = []
	for j: Array in jumps:
		need += Mission.jump_m3(job, j)
		var most := 0
		var span := Mission.jump_span(j)
		for n in p.shown:
			var u := Mission.along_line(job, Mission._cell_spot(n))
			if u > span.x and u < span.y:
				most = maxi(most, int(p.raise_mm[n]))
		tall.append(most * 0.001)
		var face_deg := rad_to_deg(atan2(float(j[1]), float(j[2])))
		var land_deg := rad_to_deg(atan2(float(j[1]), float(j[4])))
		print("      jump %.1f m tall, %.1f m long: face %.0f deg, top %.1f m, landing %.0f deg, takes about %.0f m3" % [j[1], span.y - span.x, face_deg, j[3], land_deg, Mission.jump_m3(job, j)])
		check(face_deg < 30.0 and land_deg < 25.0, "a %.1f m jump's face (%.0f deg) and landing (%.0f deg) stand as loose dirt does" % [j[1], face_deg, land_deg])
	check(absf(tall[0] - 1.0) < 0.05 and absf(tall[1] - 1.5) < 0.05 and absf(tall[2] - 2.0) < 0.05, "they're 1, 1.5 and 2 m tall (%.2f, %.2f, %.2f)" % [tall[0], tall[1], tall[2]])
	var ends := Mission.jump_line(job)
	var inside := true
	for q in ends:
		inside = inside and absf(q.x) < Machine.AREA - 2.0 and absf(q.y) + float(job["jump_half"]) < Machine.AREA
	check(inside, "the track's inside the fence")
	var bike_u := Mission.along_line(job, job["bike"])
	var first := Mission.jump_span(jumps[0]).x
	check(first - bike_u > 10.0, "the bike starts with a %.0f m run-up to the first jump" % (first - bike_u))
	var end_at: Vector2 = (job["line_from"] as Vector2) + (job["line_dir"] as Vector2) * Mission.jump_span(jumps[2]).y
	var run_out := Machine.AREA - end_at.dot(job["line_dir"])
	print("      %.0f m of run-out past the last jump before the fence" % run_out)
	check(run_out > 12.0, "there's room to land and stop past the last jump (%.0f m)" % run_out)
	# The heaps: enough dirt, beside the track and clear of the pegs, and they stand without slumping onto it.
	var heaped := DirtSim.to_m3(s.loose_total())
	print("      heaps hold %.0f m3; the jumps take about %.0f m3" % [heaped, need])
	check(heaped > need * 1.25, "the heaps hold enough to build them, with some to spare (%.0f m3 for %.0f)" % [heaped, need])
	var on_pegged := 0
	for n in p.shown:
		on_pegged += s.soil[n]
	check(on_pegged == 0, "none of it's on the pegged track to start with")
	for k in int(5.0 / DT):
		s.step(DT, 1000000)
	on_pegged = 0
	for n in p.shown:
		on_pegged += s.soil[n]
	check(DirtSim.to_m3(on_pegged) < 0.2, "the heaps stand: none slumps onto the track (%.2f m3)" % DirtSim.to_m3(on_pegged))
	check(p.score(s) < 0.01, "untouched, none of it's done (%d%%)" % int(p.score(s) * 100.0))
	for spot: Array in [["start", "the dozer"], ["digger", "the excavator"], ["bike", "the bike"], ["ute", "the ute"]]:
		var at: Vector2 = job[spot[0]]
		var under := s.soil[DirtSim.cell_of(at).y * DirtSim.CELLS + DirtSim.cell_of(at).x]
		check(under == 0 and not p.inside(at) or spot[0] == "bike", "%s starts clear of the heaps and the jumps" % spot[1])
	check(not p.inside(job["bike"]) and absf(Mission.along_line(job, job["bike"]) - bike_u) < 0.01 and (job["bike"] - (job["line_from"] as Vector2)).cross(job["line_dir"]) == 0.0, "the bike starts on the track's line, before the pegs")

## The score: built to the shape counts, from 20 cm low to 20 cm high; the flat between the jumps doesn't count.
func score_test() -> void:
	var w := _world(false)
	var s: DirtSim = w[1]
	var job: Dictionary = w[3]
	var p := Mission.pad_for(s, job)
	print("      %d cells pegged out, %d counting" % [p.shown.size(), p.cells.size()])
	check(p.cells.size() > 0.3 * p.shown.size() and p.cells.size() < 0.7 * p.shown.size(), "only the jumps count, not the flat between them or the edges (%d of %d)" % [p.cells.size(), p.shown.size()])
	for c: Array in [[0.0, true, "built to the shape"], [-0.15, true, "15 cm low"], [0.15, true, "15 cm high"], [-0.3, false, "30 cm low"], [0.3, false, "30 cm high"]]:
		build(s, p, c[0])
		var got := p.score(s)
		check((got > 0.97) == c[1], "%s %s (%d%%)" % [c[2], "counts" if c[1] else "doesn't count", int(got * 100.0)])
	# Just the biggest built: that's a good part of it, but not a star.
	for n in p.shown:
		s.soil[n] = 0
	var big := Mission.jump_span(job["jumps"][2])
	for n in p.shown:
		var u := Mission.along_line(job, Mission._cell_spot(n))
		if u > big.x and u < big.y:
			s.soil[n] = p.want_mm(s, n) - s.bed[n]
	var part := p.score(s)
	check(part > 0.3 and part < 0.7, "the biggest jump alone is %d%%: not a star yet" % int(part * 100.0))

## The normal dozer with CUT on, driven along the track over jumps heaped too high: it climbs them, shapes them toward the pegs and
## never cuts one too low.
func dozer_test() -> void:
	var w := _world(false)
	var s: DirtSim = w[1]
	var job: Dictionary = w[3]
	var p := Mission.pad_for(s, job)
	build(s, p, 0.45)
	# Rounded off, as a heap pushed up would be: no steeper than loose dirt stands.
	for k in int(3.0 / DT):
		s.step(DT, 1000000)
	var before := p.score(s)
	var total := s.total()
	var d := Dozer.new()
	root.add_child(d)
	d.pad = p
	var dir: Vector2 = job["line_dir"]
	var from: Vector2 = job["line_from"]
	d.setup(s, w[2], StandardMaterial3D.new(), from + dir * (Mission.jump_span(job["jumps"][0]).x - 6.0), dir)
	d.set_cut(true)
	var highest := 0.0
	var line_side := Vector2(-dir.y, dir.x)
	var said := ""
	for k in int(70.0 / DT):
		var off := (d.spot - from).dot(line_side)
		d.steer = clampf(-off * 0.8 + wrapf(d.angle - atan2(-dir.y, dir.x), -PI, PI) * 2.0, -1.0, 1.0)
		d.throttle = 1.0
		d.step(DT)
		s.step(DT, 1000000)
		highest = maxf(highest, d.transform.origin.y)
		if d.at_pad and said == "":
			said = "at the pad"
		if Mission.along_line(job, d.spot) > Mission.jump_span(job["jumps"][2]).y + 4.0:
			break
	var too_low := 0
	for n in p.cells:
		if s.bed[n] + s.soil[n] < p.want_mm(s, n) - int(p.tol_down * 1000.0):
			too_low += 1
	var after := p.score(s)
	var got := Mission.along_line(job, d.spot)
	print("      one pass with CUT: %d%% right before, %d%% after; got %.0f m along, rode up to %.2f m, %d cells cut too low" % [int(before * 100.0), int(after * 100.0), got, highest, too_low])
	check(got > Mission.jump_span(job["jumps"][2]).y, "it climbs over all three jumps (got %.0f m along)" % got)
	check(after > before + 0.3, "one pass with CUT shapes them a good deal nearer (%d%% to %d%%)" % [int(before * 100.0), int(after * 100.0)])
	check(too_low < p.cells.size() * 0.05, "it hardly ever cuts a jump too low (%d cells of %d)" % [too_low, p.cells.size()])
	check(s.total() == total, "no dirt lost")
	d.queue_free()

## The bike over the three jumps built, at a steady speed and flat out: it flies them and doesn't come off.
func bike_test() -> void:
	for speed: float in [9.0, 13.0, 16.0]:
		var w := _world(false)
		var s: DirtSim = w[1]
		var job: Dictionary = w[3]
		var p := Mission.pad_for(s, job)
		build(s, p)
		var b := Bike.new()
		root.add_child(b)
		b.setup(s, w[2], StandardMaterial3D.new(), job["bike"], job["bike_dir"])
		b.show_driver(true)
		var jumps: Array = []
		b.landed.connect(func(length: float, hit: float) -> void: jumps.append([length, hit]))
		var crashed := false
		var air := 0.0
		var tt := 0.0
		while tt < 20.0:
			if not b.airborne:
				b.throttle = clampf((speed - b.speed) * 0.5 + speed / Bike.TOP, 0.0, 1.0)
			b.thumb_y = -b.throttle
			var off := (b.spot - (job["line_from"] as Vector2)).dot(Vector2(0.0, 1.0))
			b.steer = clampf(-off * 0.5 + wrapf(b.angle, -PI, PI) * 1.5, -1.0, 1.0)
			b.step(DT)
			s.step(DT, 1000000)
			tt += DT
			air += DT if b.airborne else 0.0
			crashed = crashed or b.crash_t >= 0.0
			if Mission.along_line(job, b.spot) > Mission.jump_span(job["jumps"][2]).y + 8.0:
				break
		var lengths := []
		for j: Array in jumps:
			if j[0] > 2.0:
				lengths.append("%.1f m" % j[0])
		print("      at %.0f km/h: jumps %s, %.1f s in the air, got %.0f m along, came off: %s" % [speed * 3.6, lengths, air, Mission.along_line(job, b.spot), crashed])
		check(lengths.size() >= 3 and not crashed, "at %.0f km/h it flies all three and stays on" % (speed * 3.6))
		b.queue_free()

## The whole game, on the Bike jumps.
func _process(_d: float) -> bool:
	if g == null:
		return false
	t += 1
	if t == 30:
		var job := Mission.find("bike_jumps")
		check(g.job_pad != null and not g.job_pad.raise_mm.is_empty() and g.banner.text.begins_with("BIKE JUMPS"), "the job pegs out the jumps (%s)" % g.banner.text)
		check(g.dozer.pad == g.job_pad and g.digger.pad == g.job_pad, "the dozer's CUT and the excavator's readout work to them")
		check(g.active == g.dozer and g.dozer.size == 1.0 and g.digger.size == 1.0, "it starts in the dozer, and the dozer and excavator are the normal ones")
		check(g.machines.has(g.bike) and g.bike.visible and g.bike.spot.distance_to(job["bike"]) < 0.5, "the bike's on site, at the start of the track")
		check(Mission.is_pad_job(job) and Mission.crew(job).contains("bike"), "the menu says who's on it: %s" % Mission.crew(job))
		check(Mission.after(Mission.find("farm_road"))["id"] == "bike_jumps", "it comes after the Farm road")
		# Built, it's all done: finished, the end card shows.
		build(g.sim, g.job_pad)
		g._check_mission(1.0)
		check(g._score() > 0.97, "built, it's all done (%d%%)" % int(g._score() * 100.0))
		g.finish_mission()
	if t > 30 and g.menu != null:
		check(g.menu_kind == "done", "then the end card shows")
		for meta_name: String in ["mission"]:
			if Engine.has_meta(meta_name):
				Engine.remove_meta(meta_name)
		DirtSim.set_world(32.0)
		print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
		quit(fails)
	if t > 30 * 60 + 60:
		check(false, "the end card shows within 30 s")
		print("%d FAILED" % fails)
		quit(fails)
	return false
