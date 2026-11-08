extends SceneTree
## Checks the Farm road job. Run: godot --headless --path . -s test/road_test.gd
## The road's a smooth curve inside the fence, over the paddock's rises; it's done 10 cm under the ground as it was, and forgiving
## (a bit high or quite a bit deeper still counts); the big dozer's CUT boxes it out without going too deep; and in the whole game
## the farmer's ute drives the road at the end before the end card shows.

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
	DirtSim.set_world(32.0)
	Engine.set_meta("mission", "farm_road")
	g = load("res://main.tscn").instantiate()
	root.add_child(g)

func _world() -> Array:
	var job := Mission.find("farm_road")
	DirtSim.set_world(48.0)
	var ground := GroundData.new(Mission.site(job), Rect2(), Rect2(), true)
	var s := DirtSim.new()
	ground.fill_sim(s)
	s.mark_start_ground()
	return [ground, s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), job]

## Where it goes: a smooth curve, inside the fence, over the rises, with the machines and shed clear of it.
func layout_test() -> void:
	var w := _world()
	var s: DirtSim = w[1]
	var job: Dictionary = w[3]
	var track := Mission.track(job)
	var length := 0.0
	var sharpest := 0.0
	for k in track.size() - 1:
		length += track[k].distance_to(track[k + 1])
		if k > 0:
			sharpest = maxf(sharpest, absf((track[k + 1] - track[k]).angle_to(track[k] - track[k - 1])))
	var inside := true
	var low := INF
	var high := -INF
	for p in track:
		inside = inside and absf(p.x) + 4.0 < Machine.AREA and absf(p.y) + 4.0 < Machine.AREA
		low = minf(low, s.height_at(p))
		high = maxf(high, s.height_at(p))
	print("      road %.0f m long, %d points, sharpest bend %.0f degrees per 2 m, ground along it %.2f to %.2f m" % [length, track.size(), rad_to_deg(sharpest), low, high])
	check(length > 55.0 and length < 80.0, "the road's about 60 m long (%.0f m)" % length)
	check(sharpest < deg_to_rad(15.0), "it curves smoothly (%.0f degrees in 2 m at the most)" % rad_to_deg(sharpest))
	check(inside, "it's inside the fence")
	check(high - low > 0.8, "it goes over the rises: %.1f m from its lowest to its highest" % (high - low))
	for spot: Array in [["start", "the big dozer", 3.0], ["digger", "the big excavator", 11.0], ["ute", "the ute", 5.0]]:
		var off := Mission.off_track(track, job[spot[0]])
		check(off > float(job["road_half"]) + float(spot[2]) or (spot[0] == "start" and off < 8.0), "%s starts %s (%.1f m from the middle of the road)" % [spot[1], "at the start of the road" if spot[0] == "start" else "clear of it", off])
	check(job["start"].distance_to(track[0]) < 9.0, "the dozer starts at the start of the road")
	check(job["shed"].distance_to(track[track.size() - 1]) < 10.0, "the road ends at the shed")

## The score: 10 cm under the ground as it was, from 5 cm high to 15 cm deep, anywhere along it.
func score_test() -> void:
	var w := _world()
	var s: DirtSim = w[1]
	var p := Mission.pad_for(s, w[3])
	var cells := p.cells.size()
	var shown := p.shown.size()
	print("      %d cells pegged out, %d counting" % [shown, cells])
	check(cells > 0.75 * shown and cells < 0.95 * shown, "all but the edges count (%d of %d)" % [cells, shown])
	check(p.score(s) < 0.01, "untouched, none of it's done (%d%%)" % int(p.score(s) * 100.0))
	for c: Array in [[0.1, true, "boxed out 10 cm"], [0.06, true, "only 6 cm down"], [0.22, true, "22 cm down, a bit deep"], [0.03, false, "only 3 cm down"], [0.3, false, "30 cm down"]]:
		for n in p.shown:
			s.bed[n] = s.start_ground[n] - int(float(c[0]) * 1000.0) - s.soil[n]
		var got := p.score(s)
		check((got > 0.99) == c[1], "%s %s (%d%%)" % [c[2], "counts" if c[1] else "doesn't count", int(got * 100.0)])
	var r := Pad.along(PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0)]), 4.0, 0.5, 0.05, 0.15)
	check(r.inside(Vector2(5.0, 3.9)) and not r.inside(Vector2(5.0, 4.2)) and not r.inside(Vector2(-0.5, 0.0)), "a road's pegs run down both sides and stop at its ends")

## The big dozer with CUT on, driven down the road and back: it boxes much of it out, and never too deep.
func dozer_test() -> void:
	var w := _world()
	var s: DirtSim = w[1]
	var job: Dictionary = w[3]
	var p := Mission.pad_for(s, job)
	var track := Mission.track(job)
	var total := s.total()
	var d := Dozer.new()
	d.make_big(1.9)
	root.add_child(d)
	d.pad = p
	var way := (track[1] - track[0]).normalized()
	d.setup(s, w[2], StandardMaterial3D.new(), track[0] - way * 6.0, way)
	d.set_cut(true)
	var too_deep := 0
	for k in int(60.0 / DT):
		var near_k := 0
		var best := INF
		for q in track.size():
			if track[q].distance_squared_to(d.spot) < best:
				best = track[q].distance_squared_to(d.spot)
				near_k = q
		var aim := track[mini(near_k + 3, track.size() - 1)]
		var want := aim - d.spot
		d.steer = clampf(-wrapf(atan2(-want.y, want.x) - d.angle, -PI, PI) * 2.5, -1.0, 1.0)
		d.throttle = 1.0
		d.step(DT)
		s.step(DT, 1000000)
		if near_k >= track.size() - 2 and d.spot.distance_to(track[track.size() - 1]) < 4.0:
			break
	var deepest := 0
	var where := {}
	for n in p.cells:
		var under := p.want_mm(s, n) - (s.bed[n] + s.soil[n])
		if under > int(p.tol_down * 1000.0):
			too_deep += 1
			deepest = maxi(deepest, under)
			var at := Vector2(n % DirtSim.CELLS, n / DirtSim.CELLS) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M
			var key := "%d m along" % (int(at.distance_to(track[0]) / 5.0) * 5)
			where[key] = where.get(key, 0) + 1
	if too_deep > 0:
		print("      too deep by up to %d mm more than allowed: %s" % [deepest - int(p.tol_down * 1000.0), where])
	var done := p.score(s)
	print("      one pass with CUT: %d%% boxed out, got %.0f m along, %d cells too deep, blade load %.1f t" % [int(done * 100.0), d.spot.distance_to(track[0]), too_deep, d.load_t])
	check(done > 0.25, "one pass with CUT boxes out a good part of it (%d%%)" % int(done * 100.0))
	check(too_deep < p.cells.size() * 0.03, "the CUT hardly ever takes the road too deep (%d cells of %d)" % [too_deep, p.cells.size()])
	check(s.total() == total, "no soil lost")
	d.queue_free()

## The whole game, on the Farm road.
func _process(_d: float) -> bool:
	if g == null:
		return false
	t += 1
	if t == 30:
		check(g.job_pad != null and g.job_pad.drop > 0.0 and g.banner.text.begins_with("FARM ROAD"), "the job pegs out the road (%s)" % g.banner.text)
		check(g.dozer.pad == g.job_pad and g.digger.pad == g.job_pad, "the dozer's CUT and the excavator's readout work to it")
		check(g.active == g.dozer and g.machines.has(g.ute), "it starts in the big dozer, with the ute on site")
		# Boxed out, it's all done: finished, the ute drives the road before the end card.
		for n in g.job_pad.shown:
			g.sim.bed[n] = g.sim.start_ground[n] - 100 - g.sim.soil[n]
		g.dozer.spot = g.road_points[8]
		g._check_mission(1.0)
		check(g._score() > 0.99, "boxed out, it's all done (%d%%)" % int(g._score() * 100.0))
		g.finish_mission()
		check(g.road_show_t >= 0.0 and g.active == g.ute and g.menu == null, "finished, the farmer's ute takes the road first")
		check(Mission.off_track(g.road_points, g.dozer.spot) > float(Mission.find("farm_road")["road_half"]) + 3.0, "the dozer's moved off the road, out of its way")
	if t > 30 and g.road_show_t >= 0.0 and t % 60 == 0:
		print("      ute at %s, %.1f m/s" % [g.ute.spot, g.ute.speed])
	if t > 30 and g.menu != null:
		var end: Vector2 = g.road_points[g.road_points.size() - 1]
		check(g.ute.spot.distance_to(end) < 4.0, "the ute drives the road to the shed (%.1f m from the end)" % g.ute.spot.distance_to(end))
		check(g._road_skip == null, "then the end card shows")
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
