extends SceneTree
## Checks the hand tools and the garden patch job, with no drawing. Run: godot --headless --path . -s test/hand_test.gd
## A bot fills the patch: shovelfuls from the pile into the barrow, the barrow tipped into the patch, then raked level. It puts the
## worker and barrow where they need to be rather than walking them there, so it says the tools work and the job can be done.

const DT := 1.0 / 60.0
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("pass  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	var job := Mission.find("garden")
	var ground := GroundData.new(Mission.site(job), job["rect"], Mission.road(job))
	var s := DirtSim.new()
	ground.fill_sim(s)
	Mission.lay_out(s, job)
	var total := s.total()
	var gv := GroundView.new(ground, s, ground.height_texture(), ground.data_texture())
	var pad := Mission.pad_for(s, job)
	check(pad.cells.size() > 40, "the patch has %d cells to fill" % pad.cells.size())
	var start := pad.score(s)
	check(start < 0.3, "it isn't done to start with (%d%%)" % int(start * 100.0))
	var left := pad.still_to_do(s)
	print("      to fill %.2f m3, to take off %.2f m3" % [left.y, left.x])
	var w := Worker.new()
	root.add_child(w)
	w.setup(s, gv, StandardMaterial3D.new(), job["start"], job["dir"])
	w.step_off(job["start"], PI)
	var b := Barrow.new()
	root.add_child(b)
	b.setup(s, gv, StandardMaterial3D.new(), job["barrow"], job["barrow_dir"])

	# Shovelling from the pile into the barrow.
	w.take_tool("shovel")
	check(w.tool == "shovel", "he picks up the shovel")
	var pile: Vector2 = job["fill"]
	var loads := 0
	var tipped_at := [Vector2(-0.45, 0.0), Vector2(0.4, 0.35), Vector2(0.2, -0.45), Vector2(-0.1, 0.1)]
	var scoops := 0
	var missed := 0
	while loads < 4:
		while b.tray_mm + Worker.SCOOP <= Barrow.CAPACITY and scoops < 60:
			# Stand between the pile and the barrow: face the pile to dig, then turn to the barrow to throw.
			var way := (pile - b.spot).normalized()
			w.spot = pile - way * 1.0
			w.angle = atan2(-way.y, way.x)
			var dug := w.dig()
			if dug <= 0:
				break
			_run([w, b], s, 0.5)
			var to := b.tray_middle()
			var face := (Vector2(to.x, to.z) - w.spot).normalized()
			w.angle = atan2(-face.y, face.x)
			var before := b.tray_mm
			w.throw(to)
			_run([w, b], s, 0.8)
			if b.tray_mm <= before:
				missed += 1
			scoops += 1
		if loads == 0:
			check(b.tray_mm >= Barrow.CAPACITY - Worker.SCOOP, "a barrow fills with %d shovelfuls (%d mm in it, %d missed)" % [scoops, b.tray_mm, missed])
		# Pushed to the patch and tipped.
		var aim: Vector2 = job["patch"] + tipped_at[loads] - Vector2(1.0, 0.0)
		b.reposition(aim, Vector2(1.0, 0.0))
		var had := b.tray_mm
		b.tip_cmd = 1.0
		_run([w, b], s, 2.5)
		b.tip_cmd = 0.0
		_run([w, b], s, 1.0)
		if loads == 0:
			check(b.tray_mm == 0 and had > 0, "TIP empties it (%d mm out)" % had)
		b.reposition(job["barrow"], job["barrow_dir"])
		loads += 1
	_run([w, b], s, 3.0)
	var heaped := pad.score(s)
	print("      tipped in: %d%% level" % int(heaped * 100.0))
	check(s.total() == total, "no soil lost shovelling and tipping")

	# Raked level: up and back across it, one way then the other.
	w.take_tool("rake")
	check(w.tool == "rake", "he swaps the shovel for the rake")
	var c: Vector2 = job["patch"]
	var best := heaped
	for pass_n in 6:
		var across := Vector2(1.0, 0.0) if pass_n % 2 == 0 else Vector2(0.0, 1.0)
		var side := Vector2(-across.y, across.x)
		for k in 7:
			var off := (k - 3) * 0.32
			for dir: float in [1.0, -1.0]:
				w.spot = c - across * 2.0 * dir + side * off
				w.angle = atan2(-across.y * dir, across.x * dir)
				w.throttle = 1.0
				_run([w, b], s, 4.0 / (Worker.WALK * Worker.RAKE_WALK))
				w.throttle = 0.0
		_run([w, b], s, 1.0)
		best = maxf(best, pad.score(s))
		print("      raked %d times over: %d%% level" % [pass_n + 1, int(pad.score(s) * 100.0)])
	check(w.raked > 0, "the rake moves soil (%d mm)" % w.raked)
	check(pad.score(s) > heaped, "raking makes it more level")
	check(Mission.stars_for(best) >= 1, "it gets to a star at least (%d%%)" % int(best * 100.0))
	check(s.total() == total, "no soil lost raking")
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(fails)

func _run(list: Array, s: DirtSim, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		t += DT
		for m: Machine in list:
			m.step(DT)
		s.step(DT, 1000000)
