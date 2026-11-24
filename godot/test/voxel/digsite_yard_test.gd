extends SceneTree
## The dirt-physics baseline (integration/dirt_physics_plan.md, stage 1; headless:
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_yard_test.gd -- --nosave --phase=1
##   ... the same again with --phase=2
## ). Today's game, measured, so every later stage is judged against it: on a levelled 24 x 24 m patch the bulldozer
## drives 20 s, blade down, straight across. Prints DSYARD frames, mean, p95, worst ms; layer_us, show_us mean and p95;
## metres moved; the heap's height ahead; ground_mm before and after; and writes them to
## integration/dirt_shots/baseline.txt (--out=dir for somewhere else). Passes: the patch flat to +-1 cell before the
## run; the dozer moves >= 10 m; not a mm made or lost; and (--phase=2, after a --phase=1) a second run's ground_mm and
## metres within 1% of the first's. The frame p95 is recorded, no limit on it yet. --lift=-0.1 is the blade's depth
## under the tracks (m), --secs=20 the drive. Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
const SECS := 20.0

var y := Yard.new()
var timer := Yard.FrameTimer.new()
var idle := Yard.FrameTimer.new()      # (2 s on the dozer, standing: what a frame costs with nothing moving)
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var out := "res://integration/dirt_shots"
var phase := 0
var lift := -0.1
var secs := SECS
var v := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--phase="):
			phase = int(a.trim_prefix("--phase="))
		elif a.begins_with("--lift="):
			lift = float(a.trim_prefix("--lift="))
		elif a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
	y.boot(self)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DSYARD ok   ", what)
	else:
		failed += 1
		print("DSYARD FAIL ", what)

func _done() -> bool:
	print("DSYARD done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _process(dt: float) -> bool:
	t += dt
	if t > 120.0:
		check(false, "timed out at step %d" % step)
		return _done()
	match step:
		0:
			if t > 1.5:
				y.travel()
				_next(1)
		1:
			if y.arrived() and t - mark > 1.0:
				var l := y.level()
				print("DSYARD   the patch: %.0f x %.0f m at cell %d (it stood from %d to %d; %d cells filled, %d cut off; at rest in %d ticks)" % [Yard.PATCH, Yard.PATCH, l.level, l.was_min, l.was_max, l.raised, l.lowered, l.rest_ticks])
				_next(2)
		2:
			if t - mark > 1.0:          # (a second of the game's own ticks: still flat?)
				var f := y.flatness()
				check(float(f[0]) >= -1.0 and float(f[1]) <= 1.0, "the patch is flat to +-1 cell before the run (%.2f to %.2f cells off its level)" % [f[0], f[1]])
				var dz := y.park_dozer()
				check(dz != null and dz is DsDozer, "the bulldozer found by its type (id %d), parked on the patch's edge" % dz.id)
				y.mount(dz)
				check(y.ds().machines.driving == dz, "on it")
				v.at = dz.global_position
				v.mass0 = y.mass()
				v.moved0 = dz.moved
				idle.start()
				_next(3)
		3:
			idle.tick(y.ds().terrain)
			if t - mark >= 2.0:
				y.drive_dozer(y.dozer(), 1.0, lift)
				timer.start()
				v.heap_most = 0.0
				v.speed_min = INF
				v.blocked = {}
				_next(4)
		4:
			var dz := y.dozer()
			timer.tick(y.ds().terrain)
			y.drive_dozer(dz, 1.0, lift)
			if t - mark > 1.0:
				v.heap_most = maxf(float(v.heap_most), y.heap_ahead(dz))
				v.speed_min = minf(float(v.speed_min), dz.speed)
			if dz.blocked != "":
				v.blocked[dz.blocked] = int(v.blocked.get(dz.blocked, 0)) + 1
			if t - mark >= secs:
				dz.throttle = 0.0
				return _report(dz)
	return false

func _report(dz: DsDozer) -> bool:
	var s := timer.stats()
	var m0: Dictionary = v.mass0
	var m1 := y.mass()
	var metres: float = dz.global_position.distance_to(v.at)
	var side: float = absf(dz.global_position.x - (v.at as Vector3).x)
	var heap := y.heap_ahead(dz)
	var lines := PackedStringArray()
	lines.append("DSYARD frames %d, mean %.2f, p95 %.2f, worst %.2f ms" % [s.frame.n, s.frame.mean, s.frame.p95, s.frame.worst])
	var si := idle.stats()
	lines.append("DSYARD standing (2 s before): frames %d, mean %.2f, p95 %.2f, worst %.2f ms" % [si.frame.n, si.frame.mean, si.frame.p95, si.frame.worst])
	lines.append("DSYARD layer_us mean %.0f, p95 %.0f; show_us mean %.0f, p95 %.0f" % [s.layer.mean, s.layer.p95, s.show.mean, s.show.p95])
	lines.append("DSYARD metres moved %.2f (%.2f off its line), slowest %.2f m/s, at the end %.2f m/s" % [metres, side, v.speed_min, dz.speed])
	lines.append("DSYARD heap height ahead %.2f m at the end, %.2f m at most; banked against the blade %.0f blocks; %d blocks' worth moved" % [heap, v.heap_most, dz.push_load, (dz.moved - int(v.moved0)) / Yard.MM])
	lines.append("DSYARD ground_mm before %d, after %d; loads before %d, after %d; total before %d, after %d" % [m0.ground, m1.ground, m0.loads + m0.falling, m1.loads + m1.falling, m0.total, m1.total])
	var why := ""
	for k in v.blocked:
		why += "'%s' %d frames; " % [k, v.blocked[k]]
	lines.append("DSYARD stops: %s" % (why if why != "" else "none"))
	lines.append("DSYARD run: %.0f s, blade %.2f m, patch %.0f m at cell %d, phase %d" % [secs, lift, Yard.PATCH, y.level_y, phase])
	for l in lines:
		print(l)
	check(metres >= 10.0, "the dozer moves >= 10 m (%.2f)" % metres)
	# (from the dirt physics' stage 5 the dozer's blade lets go clods, and the last of them are still rolling when the
	# push ends: the ground, every load and the clods together are what's the same)
	check(int(m1.total) == int(m0.total), "ground_mm, every load and the clods still loose the same before and after: %d mm drift (%d mm in clods at the end)" % [int(m1.total) - int(m0.total), int(m1.clods)])
	check(float(s.frame.p95) > 0.0, "frame p95 recorded: %.2f ms (no limit yet)" % s.frame.p95)
	# the pair: phase 1 leaves its numbers, phase 2 checks its own against them
	var dir := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	var run1 := "user://digsite_yard_run1.txt"      # (phase 1's ground_mm and metres, for phase 2)
	if phase == 2:
		var was := FileAccess.get_file_as_string(run1).split(" ")
		if was.size() >= 2:
			var g0 := float(was[0])
			var d0 := float(was[1])
			var dg := absf(float(m1.ground) - g0) / maxf(g0, 1.0) * 100.0
			var dd := absf(metres - d0) / maxf(d0, 0.001) * 100.0
			lines.append("DSYARD the run before: ground_mm %d, metres %.2f; this one: %d, %.2f (%.4f%%, %.2f%% apart)" % [int(g0), d0, m1.ground, metres, dg, dd])
			print(lines[lines.size() - 1])
			check(dg <= 1.0 and dd <= 1.0, "two runs give the same ground_mm and metres moved within 1%% (%.4f%%, %.2f%%)" % [dg, dd])
		else:
			check(false, "two runs: no first run's numbers at %s (run --phase=1 first)" % run1)
	else:
		var f1 := FileAccess.open(run1, FileAccess.WRITE)
		f1.store_string("%d %.4f" % [m1.ground, metres])
		f1.close()
		print("DSYARD   (the pair: run it again with --phase=2 to check a second run against this one)")
	lines.append("DSYARD done %d passed, %d failed" % [passed, failed])
	var f := FileAccess.open(dir.path_join("baseline.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return _done()
