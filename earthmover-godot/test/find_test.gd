extends SceneTree
## Checks the Buried find job. Run: godot --headless --path . -s test/find_test.gd
## Each find lies inside the pegs, buried; nothing digs or slumps through it; the big excavator's bucket stops on it, a gentle touch
## isn't a knock and a hard one is; the score is what's uncovered less the knocks; and in the whole game the banner names it once
## it's seen, a knock shows, a friend's game gets the same find, and the end says what it was.

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
	picks_test()
	for kind: String in Find.KINDS:
		buried_test(kind)
	bucket_test()
	dozer_test()
	DirtSim.set_world(32.0)
	Engine.set_meta("mission", "buried_find")
	Engine.set_meta("find_seed", 4242)
	Engine.set_meta("find_kind", "car")
	g = load("res://main.tscn").instantiate()
	root.add_child(g)

func _world() -> Array:
	var job := Mission.find("buried_find")
	DirtSim.set_world(48.0)
	var ground := GroundData.new(Mission.site(job), Rect2(), Rect2(), true)
	var s := DirtSim.new()
	ground.fill_sim(s)
	return [ground, s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), job["patch"]]

## A surprise each time, but the same seed's the same find.
func picks_test() -> void:
	var w := _world()
	var s: DirtSim = w[1]
	var patch: Rect2 = w[3]
	var seen := {}
	for seed in 30:
		seen[Find.make(seed, patch, 0.0).kind] = true
	check(seen.size() == 3, "all three finds turn up (%s)" % ", ".join(seen.keys()))
	var a := Find.make(4242, patch, s.height_at(patch.get_center()))
	var b := Find.make(4242, patch, s.height_at(patch.get_center()))
	check(a.kind == b.kind and a.at == b.at and a.angle == b.angle, "the same seed gives the same find, for a friend's game")

## Laid in the ground: inside the pegs, buried, and nothing digs or slumps through it.
func buried_test(kind: String) -> void:
	var w := _world()
	var s: DirtSim = w[1]
	var patch: Rect2 = w[3]
	var f := Find.make(99, patch, s.height_at(patch.get_center()), kind)
	f.lay(s)
	var inside := true
	var highest := -INF
	for k in f.cells.size():
		var n := f.cells[k]
		var p := Vector2(n % DirtSim.CELLS, n / DirtSim.CELLS) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M
		inside = inside and patch.has_point(p)
		highest = maxf(highest, f.tops[k] * 0.001)
	check(f.cells.size() > 30, "%s: it's there, under %d cells" % [kind, f.cells.size()])
	check(inside, "%s: it all lies inside the pegs" % kind)
	check(absf(highest - (0.0 - Find.DEEP[kind])) < 0.05, "%s: buried, its top %.2f m down" % [kind, -highest])
	check(f.uncovered(s) == 0.0 and f.score(s) == 0.0, "%s: none of it's uncovered to start with" % kind)
	var total := s.total()
	# Dug at as hard as it goes, then a deep hole all round it left to slump.
	for k in f.cells.size():
		var n := f.cells[k]
		for r in 40:
			s.take(n % DirtSim.CELLS, n / DirtSim.CELLS, 500)
			s.bite(n % DirtSim.CELLS, n / DirtSim.CELLS, 500, 400)
	var c := DirtSim.cell_of(f.at)
	var reach := int((f.radius + 2.0) / DirtSim.CELL_M)
	for j in range(c.y - reach, c.y + reach + 1):
		for i in range(c.x - reach, c.x + reach + 1):
			var n := j * DirtSim.CELLS + i
			if s.hard[n] == DirtSim.BED_FLOOR:
				s.take(i, j, 3000)
	for k in int(3.0 / DT):
		s.step(DT, 1000000)
	var through := 0
	for n in f.cells:
		if s.bed[n] < s.hard[n]:
			through += 1
	check(through == 0, "%s: dug at hard and left to slump, nothing goes through it (%d cells)" % [kind, through])
	check(f.uncovered(s) > 0.95, "%s: dug off, it's all uncovered (%d%%)" % [kind, int(f.uncovered(s) * 100.0)])
	# A little dirt left on it still counts; more doesn't.
	for k in f.cells.size():
		s.soil[f.cells[k]] = 0
		s.bed[f.cells[k]] = f.tops[k] + 100
	check(f.uncovered(s) > 0.99, "%s: 10 cm of dirt left on it still counts as uncovered" % kind)
	for k in f.cells.size():
		s.bed[f.cells[k]] = f.tops[k] + 200
	check(f.uncovered(s) < 0.01, "%s: 20 cm doesn't" % kind)
	for k in f.cells.size():
		s.bed[f.cells[k]] = s.hard[f.cells[k]]
	f.knocks = 2
	check(absf(f.score(s) - (1.0 - 2.0 * Find.KNOCK_COST)) < 0.001, "%s: two knocks take %d%% off (%d%%)" % [kind, int(2.0 * Find.KNOCK_COST * 100.0), int(f.score(s) * 100.0)])

## The big excavator's bucket let down onto the uncovered car: it stops on top. Gently it's a touch, hard it's a knock.
func bucket_test() -> void:
	var w := _world()
	var s: DirtSim = w[1]
	var patch: Rect2 = w[3]
	var f := Find.make(7, patch, s.height_at(patch.get_center()), "car")
	f.lay(s)
	for n in f.cells:
		s.bed[n] = s.hard[n]
		s.soil[n] = 0
	var e := Excavator.new()
	e.make_big(1.9)
	root.add_child(e)
	var dir := Vector2(1.0, 0.3).normalized()
	e.setup(s, w[2], StandardMaterial3D.new(), f.at - dir * 8.0, dir)
	var knock_at := Excavator.KNOCK_SPEED * e.size
	for stick: float in [0.3, 1.0]:
		e.wrist = Vector2(8.0 / 1.9, 3.0)
		e.curl = 2.0
		for k in 30:
			e.step(DT)
			s.step(DT, 1000000)
		e.touch_speed = -1.0
		var met := -1.0
		for k in int(10.0 / DT):
			e.raise_cmd = -stick
			e.step(DT)
			s.step(DT, 1000000)
			if e.touch_speed >= 0.0 and met < 0.0:
				met = e.touch_speed
		# Held down a while longer: it stays on top.
		var top := f.top_at(Vector2(e.teeth.x, e.teeth.z))
		e.raise_cmd = 0.0
		print("      lowered at %d%% stick: met it at %.2f m/s (a knock's over %.2f), teeth at %.2f, its top %.2f" % [int(stick * 100.0), met, knock_at, e.teeth.y, top])
		check(met >= 0.0 and e.teeth.y > top - 0.1, "at %d%% stick the bucket stops on top of it" % int(stick * 100.0))
		if stick < 0.5:
			check(met < knock_at, "lowered gently, it's only a touch")
			# Then dragged in along its top, still held down a little: it slides along it, no lower, and that's no knock.
			var from := e.teeth
			var worst := 0.0
			var lowest := INF
			e.touch_speed = -1.0
			for k in int(1.0 / DT):
				e.reach_cmd = -0.5
				e.raise_cmd = -0.3
				e.step(DT)
				s.step(DT, 1000000)
				worst = maxf(worst, e.touch_speed)
				var under := f.top_at(Vector2(e.teeth.x, e.teeth.z))
				if not is_nan(under):
					lowest = minf(lowest, e.teeth.y - under)
			e.reach_cmd = 0.0
			e.raise_cmd = 0.0
			var slid := Vector2(e.teeth.x - from.x, e.teeth.z - from.z).length()
			print("      dragged along it: %.2f m, never more than %.2f m into it, hardest touch %.2f m/s" % [slid, -lowest, worst])
			check(slid > 0.5 and lowest > -0.1, "dragged in along its top, it slides along without going into it")
			check(worst < knock_at, "and scraping along it isn't a knock")
		else:
			check(met > knock_at, "lowered hard, it's a knock")
		for k in int(2.0 / DT):
			e.raise_cmd = 1.0
			e.step(DT)
			s.step(DT, 1000000)
		e.raise_cmd = 0.0
	e.queue_free()

## The big dozer on CUT, a metre down, across the buried car: it strips the dirt off but can't cut into it.
func dozer_test() -> void:
	var w := _world()
	var s: DirtSim = w[1]
	var patch: Rect2 = w[3]
	var f := Find.make(7, patch, s.height_at(patch.get_center()), "car")
	f.lay(s)
	var total := s.total()
	var d := Dozer.new()
	d.make_big(1.9)
	root.add_child(d)
	d.setup(s, w[2], StandardMaterial3D.new(), f.at - Vector2(14.0, 0.0), Vector2(1.0, 0.0))
	d.set_cut(true)
	d.change_cut(20)
	for lap in 4:
		d.reposition_for_test(f.at - Vector2(14.0, 0.0), Vector2(1.0, 0.0))
		d.set_cut(true)
		d.throttle = 1.0
		for k in int(10.0 / DT):
			d.step(DT)
			s.step(DT, 1000000)
		d.throttle = 0.0
	var through := 0
	for n in f.cells:
		if s.bed[n] < s.hard[n]:
			through += 1
	print("      dozer: %d%% of it uncovered, at %.1f m along" % [int(f.uncovered(s) * 100.0), d.spot.x - f.at.x])
	check(through == 0, "the dozer's CUT strips over it without cutting into it (%d cells)" % through)
	check(s.total() == total, "no soil lost")
	d.queue_free()

## The whole game, on the job with the old car.
func _process(_d: float) -> bool:
	if g == null:
		return false
	t += 1
	if t == 30:
		check(g.buried != null and g.buried.kind == "car", "the job lays the find picked")
		check(g.place_id() == "buried_find#4242", "a friend's game is told which find (%s)" % g.place_id())
		check(g.banner.text.begins_with("BURIED FIND"), "the banner doesn't give it away (%s)" % g.banner.text)
		check(g.active == g.digger, "it starts in the big excavator")
		# The bucket's teeth brought right over it: the beep goes.
		g.sfx.beep.stop()
		g._beep_wait = 0.0
		g.digger.teeth = Vector3(g.buried.at.x, -0.5, g.buried.at.y)
		g._find_step(0.016)
		check(g.sfx.beep.playing and g.beep_light.visible, "with the bucket near it, it beeps and the light flashes")
		g._beep_wait = 0.0
		g.digger.teeth = Vector3(g.buried.at.x + 20.0, 0.5, g.buried.at.y + 20.0)
		g.sfx.beep.stop()
		g._find_step(0.016)
		check(not g.sfx.beep.playing, "far off, it doesn't")
		# Uncovered: it says what it is.
		var b: Find = g.buried
		for n in b.cells:
			g.sim.bed[n] = g.sim.hard[n]
			g.sim.soil[n] = 0
		g._check_find()
		g._show_banner()
		check(g.find_seen and g.banner.text.begins_with("OLD CAR"), "uncovered, the banner names it (%s)" % g.banner.text)
		check(g.say_text.begins_with("It's an old car!"), "and says so (%s)" % g.say_text)
		# A hard knock from the bucket counts once, however it bounces.
		g.digger.touch_speed = 3.0
		g._find_step(0.016)
		g.digger.touch_speed = 3.0
		g._find_step(0.016)
		g.digger.touch_speed = 0.5
		g._knock_wait = 0.0
		g._find_step(0.016)
		g._check_find()
		g._show_banner()
		check(b.knocks == 1 and g.banner.text.begins_with("OLD CAR, 1 KNOCK"), "a hard knock counts once, a soft touch not at all (%s)" % g.banner.text)
		check(absf(g.find_done - (1.0 - Find.KNOCK_COST)) < 0.01, "and costs %d%% (%d%%)" % [int(Find.KNOCK_COST * 100.0), int(g.find_done * 100.0)])
		g.finish_mission()
	if t == 40:
		var words := []
		for l in g.menu.find_children("*", "Label", true, false):
			words.append((l as Label).text)
		check(words.has("IT WAS AN OLD CAR, 1 KNOCK"), "the end says what it was (%s)" % " / ".join(words))
		for meta_name: String in ["mission", "find_kind", "find_seed"]:
			if Engine.has_meta(meta_name):
				Engine.remove_meta(meta_name)
		root.remove_child(g)
		g.queue_free()
		DirAccess.remove_absolute(Mission.save_path)
		print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
		quit(fails)
	return false
