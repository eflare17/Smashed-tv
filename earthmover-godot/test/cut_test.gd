extends SceneTree
## Checks the dozer's CUT setting, with no drawing. Run: godot --headless --path . -s test/cut_test.gd
## Drives a real dozer over rolling ground and measures what's left against where the ground began.

const DT := 1.0 / 60.0
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	var s := DirtSim.new()
	var ground := GroundData.new()
	# Rolling land along the way it drives: 30 cm up and down over 16 m, with 10 cm of loose soil on it.
	for j in DirtSim.CELLS:
		var z := -DirtSim.HALF_M + j * DirtSim.CELL_M
		for i in DirtSim.CELLS:
			var n := j * DirtSim.CELLS + i
			s.bed[n] = int(300.0 * sin(z * TAU / 16.0))
			s.soil[n] = 100
	s.mark_start_ground()
	var total := s.total()
	var d := Dozer.new()
	root.add_child(d)
	d.setup(s, GroundView.new(ground, s, ground.height_texture(), ground.data_texture()), StandardMaterial3D.new(), Vector2(0.0, 22.0), Vector2(0.0, -1.0))
	check(d.cut_cm == 20, "it starts at 20 cm")
	d.change_cut(-20)
	check(d.cut_cm == 5, "no shallower than 5 cm")
	d.change_cut(20)
	check(d.cut_cm == 50, "no deeper than 50 cm")
	d.cut_cm = 20
	d.set_level(true)
	d.set_cut(true)
	check(d.cut_on and not d.level_on, "CUT and LEVEL are one or the other")
	d.set_level(true)
	check(not d.cut_on, "either way round")
	d.set_cut(true)

	_pass(d, s, -1.0, -14.0, "first pass")
	var first := _measure(s)
	print("      after one pass: on average %.0f mm below where it began, least %d, most %d" % [first[0], first[1], first[2]])
	check(absf(first[0] - 200.0) < 30.0, "it takes off about 20 cm")
	check(first[2] - first[1] < 110, "evenly, up and down the land")

	# Back over the same strip, the way a player overlaps.
	_back(d, s, 22.0)
	_pass(d, s, -1.0, -14.0, "over it again")
	var second := _measure(s)
	print("      second pass: average %.0f mm, least %d, most %d" % [second[0], second[1], second[2]])
	check(second[0] < first[0] + 15.0 and second[2] < first[2] + 30, "going over it again doesn't go deeper")

	_back(d, s, 22.0)
	d.cut_cm = 40
	_pass(d, s, -1.0, -14.0, "at 40 cm")
	var third := _measure(s)
	print("      at 40 cm: average %.0f mm, least %d, most %d" % [third[0], third[1], third[2]])
	check(absf(third[0] - 400.0) < 40.0, "set deeper, it takes the next layer")

	check(s.total() == total, "total unchanged")
	d.lift_cmd = 1.0
	d.step(DT)
	check(not d.cut_on, "RAISE turns CUT off")
	d.queue_free()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)

func _pass(d: Dozer, s: DirtSim, dir: float, to_z: float, what: String) -> void:
	d.throttle = 1.0
	var ticks := 0
	var slow := 0
	while d.spot.y * -dir > to_z * -dir and ticks < 6000:
		d.step(DT)
		s.step(DT, 1000000)
		ticks += 1
		if d.speed < 0.1:
			slow += 1
	d.throttle = 0.0
	print("      %s: %.0f s, stopped or nearly for %.1f s, at z %.1f, pushing %.1f t" % [what, ticks * DT, slow * DT, d.spot.y, d.load_t])

func _back(d: Dozer, s: DirtSim, to_z: float) -> void:
	d.throttle = -1.0
	var ticks := 0
	while d.spot.y < to_z and ticks < 3000:
		d.step(DT)
		s.step(DT, 1000000)
		ticks += 1
	d.throttle = 0.0
	for k in 60:
		d.step(DT)
		s.step(DT, 1000000)

## How far below where it began the middle of the strip stands, along the part clear of where it started and stopped: [average, least, most].
func _measure(s: DirtSim) -> Array:
	var a := DirtSim.cell_of(Vector2(-1.0, -6.0))
	var b := DirtSim.cell_of(Vector2(1.0, 18.0))
	var sum := 0
	var cells := 0
	var least := 99999
	var most := -99999
	for j in range(a.y, b.y):
		for i in range(a.x, b.x + 1):
			var n := j * DirtSim.CELLS + i
			var down := s.start_ground[n] - s.bed[n] - s.soil[n]
			sum += down
			cells += 1
			least = mini(least, down)
			most = maxi(most, down)
	return [float(sum) / cells, least, most]
