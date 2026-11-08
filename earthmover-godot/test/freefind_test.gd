extends SceneTree
## Checks free play's hidden finds, and that free play's sites are the bigger size. Run: godot --headless --path . -s test/freefind_test.gd
## Free play on the house site and at the mine: one each of a car, bones and gold, each on open ground inside the fence, apart,
## and well buried; the same seed puts them in the same places (for a friend's game); the beep goes near one from a bucket, the
## blade or a shovel, and not far off; a knock leaves a mark; and each one uncovered is counted and said, up to all three.

var fails := 0
var g: Node
var t := 0
var stage := 0
var first_spots := []

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	_start(false, 777)

func _start(big: bool, seed: int) -> void:
	if g != null:
		root.remove_child(g)
		g.queue_free()
	Engine.set_meta("free_play", true)
	if big:
		Engine.set_meta("big_site", true)
	elif Engine.has_meta("big_site"):
		Engine.remove_meta("big_site")
	Engine.set_meta("find_seed", seed)
	g = load("res://main.tscn").instantiate()
	root.add_child(g)
	t = 0

func _process(_d: float) -> bool:
	t += 1
	if t != 20:
		return false
	match stage:
		0:
			check(is_equal_approx(DirtSim.HALF_M * 2.0, 80.0), "free play's house site is 80 m across (%.0f)" % (DirtSim.HALF_M * 2.0))
			_laid_test("the house site", "#777")
			for f: Find in g.free_finds:
				first_spots.append(f.at)
			_play_test()
			stage = 1
			_start(false, 777)
		1:
			var same: bool = g.free_finds.size() == first_spots.size()
			for k in g.free_finds.size():
				same = same and g.free_finds[k].at == first_spots[k]
			check(same, "the same seed puts them in the same places, for a friend's game")
			stage = 2
			_start(false, 778)
		2:
			check(g.free_finds.size() == 3 and g.free_finds[0].at != first_spots[0], "another seed puts them somewhere else")
			stage = 3
			_start(true, 31)
		3:
			check(is_equal_approx(DirtSim.HALF_M * 2.0, 120.0), "the mine is 120 m across (%.0f)" % (DirtSim.HALF_M * 2.0))
			_laid_test("the mine", "big#31")
			var clear := true
			for f: Find in g.free_finds:
				for r: Rect2 in [GroundData.MINE_BENCH, GroundData.MINE_ROAD, GroundData.MINE_PARK, GroundData.MINE_DUMP, GroundData.mine_ramp_rect()]:
					clear = clear and not r.grow(f.radius).has_point(f.at)
			check(clear, "at the mine they're clear of the pit, ramp, roads, parking and dump")
			for meta_name: String in ["free_play", "big_site", "find_seed"]:
				if Engine.has_meta(meta_name):
					Engine.remove_meta(meta_name)
			DirtSim.set_world(32.0)
			print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
			quit(fails)
	return false

## Where they went: one of each, inside the fence, apart, under untouched ground, deep enough not to show.
func _laid_test(where: String, place: String) -> void:
	var finds: Array = g.free_finds
	var kinds := {}
	for f: Find in finds:
		kinds[f.kind] = true
	check(finds.size() == 3 and kinds.size() == 3, "%s hides one each of a car, bones and gold (%s)" % [where, ", ".join(kinds.keys())])
	var inside := true
	var apart := true
	var shallowest := INF
	var loose := 0
	for k in finds.size():
		var f: Find = finds[k]
		inside = inside and absf(f.at.x) + f.radius <= Machine.AREA and absf(f.at.y) + f.radius <= Machine.AREA
		for other in range(k + 1, finds.size()):
			apart = apart and f.at.distance_to(finds[other].at) > f.radius + finds[other].radius + 5.0
		for c in f.cells.size():
			var n: int = f.cells[c]
			shallowest = minf(shallowest, (g.sim.bed[n] + g.sim.soil[n] - f.tops[c]) * 0.001)
			if g.sim.soil[n] > 0:
				loose += 1
	check(inside, "%s: all of them inside the fence" % where)
	check(apart, "%s: well apart" % where)
	check(shallowest > 0.6, "%s: all buried, at least %.2f m under" % [where, shallowest])
	check(loose == 0, "%s: under untouched ground, not under a heap or the pit (%d loose cells)" % [where, loose])
	check(g.place_id() == place, "%s: a friend's game is told where they are (%s)" % [where, g.place_id()])
	check(g.finds_label != null and g.finds_label.text == "FINDS: 0 OF 3" and g.finds_label.visible, "%s: the counter shows 0 of 3" % where)

## Playing it on the house site: the beep, a knock, and finding them.
func _play_test() -> void:
	var f: Find = g.free_finds[0]
	# The excavator's bucket right over it beeps, and far off doesn't.
	g.active = g.digger
	g.sfx.beep.stop()
	g._beep_wait = 0.0
	g.digger.teeth = Vector3(f.at.x, g.sim.height_at(f.at), f.at.y)
	g._find_step(0.016)
	check(g.sfx.beep.playing and g.beep_light.visible, "the bucket over one beeps and the light flashes")
	g.sfx.beep.stop()
	g._beep_wait = 0.0
	var far := Vector2(-Machine.AREA, -Machine.AREA)
	for other: Find in g.free_finds:
		if other.at.distance_to(far) < 15.0:
			far = Vector2(Machine.AREA, -Machine.AREA)
	g.digger.teeth = Vector3(far.x, 0.0, far.y)
	g._find_step(0.016)
	check(not g.sfx.beep.playing, "far from any, it doesn't")
	# On foot with the shovel, it beeps too.
	var w: Worker = g.workers[0]
	w.tool = "shovel"
	w.spot = f.at - w.forward() * Worker.DIG_AT
	g.active = w
	g.sfx.beep.stop()
	g._beep_wait = 0.0
	g._find_step(0.016)
	check(g.sfx.beep.playing, "the shovel over one beeps")
	g.active = g.digger
	# A hard knock leaves a mark on the nearest one, and that's all.
	g.digger.teeth = Vector3(f.at.x, f.base + f.height, f.at.y)
	g.digger.touch_speed = 5.0
	g._find_step(0.016)
	check(f.knocks == 1 and g._marks_look != null and g.say_text.begins_with("KNOCK"), "a hard knock marks it")
	# Uncovered, each is counted and said.
	for k in g.free_finds.size():
		var one: Find = g.free_finds[k]
		for n in one.cells:
			g.sim.bed[n] = g.sim.hard[n]
			g.sim.soil[n] = 0
		g._check_free_finds()
		var what := String(Find.NAMES[one.kind]).to_lower()
		if k == 0:
			check(g.free_found == 1 and g.finds_label.text == "FINDS: 1 OF 3", "the first one uncovered counts (%s)" % g.finds_label.text)
			check(g.say_text == "You found %s! 1 of 3 found" % what, "and says what it is (%s)" % g.say_text)
	check(g.free_found == 3 and g.finds_label.text == "FINDS: 3 OF 3", "all three found (%s)" % g.finds_label.text)
	check(g.say_text.ends_with("That's all 3 found"), "and it says that's all of them (%s)" % g.say_text)
	g._check_free_finds()
	check(g.free_found == 3, "each is only counted once")
