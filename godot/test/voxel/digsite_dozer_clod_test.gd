extends SceneTree
## The bulldozer's wave of dirt as real clods (integration/dirt_physics_plan.md, stage 5; headless:
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_dozer_clod_test.gd -- --nosave
## ). The yard's push (the levelled 24 x 24 m patch, the bulldozer 20 s flat out straight across it, its blade 0.1 m in
## the ground), twice in the one run, back to back: first with the blade as it was before the clods (the dozer's
## clod_share 0: the baseline, stage 4's game), then, the patch levelled again, with the clods (--order=ba: the other
## way round, to see the order doesn't decide it). Passes:
##   not a mm made or lost at any second of the push, nor at its end, nor once every clod's settled;
##   the clods are DsDozer.CLOD_SHARE of what the blade's front moved on; over 200 clods let go; never more awake than DsDirt.FLY_MAX;
##   the heap ahead of the blade at least 0.3 m and at least 80% of the baseline's height;
##   a windrow (over 0 mm of dirt above the patch's level) in the columns 0.5 to 1.5 m outside each end of the blade;
##   at least 80% of stage 4's metres (12.29 m: 9.83), and of the baseline's in this run;
##   the clods' step (DsDirt.step_us) 2.0 ms at the most on average; the frame's p95 no more than the baseline's
##   + 3.0 ms; the ground's own work (DsTerrain.layer_us + show_us) within 20% of the baseline's.
## And: the baseline is stage 4's push (its metres to the cm), the clods come to rest and are gone. Writes
## integration/dirt_shots/dozer_clod.txt (--out=dir). --share=0.35 another share; --debug a line a second.
## Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
var SECS := 20.0
const LIFT := -0.1
const STAGE4_M := 12.29         # m: stage 4's 20 s push (digsite_feel_test (d), digsite_yard_test: the progress log)

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var out := "res://integration/dirt_shots"
var order := "ab"
var share := DsDozer.CLOD_SHARE
var debug := false
var lines := PackedStringArray()
var runs := []                  # the runs to do: the share each
var k := 0
var res := {}                   # by share (0: the baseline; 1: the clods): what was measured
var cur := {}
var timer: Yard.FrameTimer
var both := PackedFloat32Array()    # layer_us + show_us, each frame
var steps := PackedFloat32Array()   # the clods' step_us, each frame with any awake
var steps_all := PackedFloat32Array()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--order="):
			order = a.trim_prefix("--order=")
		elif a.begins_with("--share="):
			share = float(a.trim_prefix("--share="))
		elif a.begins_with("--secs="):
			SECS = float(a.trim_prefix("--secs="))
		elif a == "--debug":
			debug = true
	runs = [share, 0.0] if order == "ba" else [0.0, share]
	y.boot(self)

func say(s: String) -> void:
	lines.append("DSDOZCLOD " + s)
	print("DSDOZCLOD ", s)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		say("ok   " + what)
	else:
		failed += 1
		say("FAIL " + what)

func _done() -> bool:
	say("done %d passed, %d failed" % [passed, failed])
	var dir := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("dozer_clod.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return true

func _next(s: int) -> void:
	step = s
	mark = t

## The dirt standing over the patch's level in the columns 0.5 to 1.5 m outside each end of the blade, along where
## the blade's been (from z0 to z1, the blade's ends at x0 and x1): [mm on the low-x side, mm on the high-x side,
## columns with any on each]
func _windrows(x0: float, x1: float, z0: float, z1: float) -> Array:
	var tr: DsTerrain = y.ds().terrain
	var g = y.grid()
	var level := (y.level_y + 1) * Yard.MM
	var ca := tr.cell_of(Vector3(x0 - 1.5, 0, minf(z0, z1)))
	var cb := tr.cell_of(Vector3(x0 - 0.5, 0, maxf(z0, z1)))
	var cc := tr.cell_of(Vector3(x1 + 0.5, 0, 0))
	var cd := tr.cell_of(Vector3(x1 + 1.5, 0, 0))
	var o := [0, 0, 0, 0]
	for z in range(ca.z, cb.z + 1):
		for side in 2:
			var xa: int = ca.x if side == 0 else cc.x
			var xb: int = cb.x if side == 0 else cd.x
			for x in range(xa, xb):
				var over: int = (int(g.column_top(x, z)) + 1) * Yard.MM + (int(g.get_layer(x, z)) & 255) - level
				if over > 0:
					o[side] += over
					o[2 + side] += 1
	return o

func _process(dt: float) -> bool:
	t += dt
	if t > 400.0:
		check(false, "timed out at step %d" % step)
		return _done()
	match step:
		0:
			if t > 1.5:
				y.travel()
				_next(1)
		1:
			if y.arrived() and t - mark > 1.0:
				y.level()
				_next(2)
		2:
			if t - mark > 1.0:
				var f := y.flatness()
				var dz := y.park_dozer()
				if k == 0:
					check(float(f[0]) >= -1.0 and float(f[1]) <= 1.0, "the patch is flat to +-1 cell (%.2f to %.2f)" % [f[0], f[1]])
					y.mount(dz)
					check(y.ds().machines.driving == dz, "on the bulldozer (id %d)" % dz.id)
					y.ds().dirt.cap_us = 0      # (the same every run: the time cap is by the clock; digsite_clod_perf's)
				dz.clod_share = float(runs[k])
				dz._clod_due = 0.0
				dz.clods_made = 0
				dz.clods_mm = 0
				cur = {"share": float(runs[k]), "flat": f, "at": dz.global_position, "mass0": y.mass(), "moved0": dz.moved, "spill0": dz.spilled, "sp_was": dz.spilled, "mm_was": 0,
					"sec": 0, "drift": 0, "heap_most": 0.0, "awake_most": 0, "blocked": {}, "edge0": dz.edge_ends(),
					"direct0": y.ds().dirt.direct_n, "shed0": y.ds().dirt.shed_n, "settled0": y.ds().dirt.settled_n, "load_most": 0}
				_next(3)
		3:
			if t - mark >= 2.0:
				timer = Yard.FrameTimer.new()
				timer.start()
				both.clear()
				steps.clear()
				steps_all.clear()
				_next(4)
		4:
			var dz := y.dozer()
			var d: DsDirt = y.ds().dirt
			var tr: DsTerrain = y.ds().terrain
			timer.tick(tr)
			both.append(float(tr.layer_us + tr.show_us))
			steps_all.append(float(d.step_us))
			if d.n > 0:
				steps.append(float(d.step_us))
			cur.awake_most = maxi(int(cur.awake_most), d.n)
			cur.load_most = maxi(int(cur.load_most), dz.clod_load)
			y.drive_dozer(dz, 1.0, LIFT)
			if t - mark > 1.0:
				cur.heap_most = maxf(float(cur.heap_most), y.heap_ahead(dz))
			if dz.blocked != "":
				cur.blocked[dz.blocked] = int(cur.blocked.get(dz.blocked, 0)) + 1
			if int(t - mark) > int(cur.sec):
				cur.sec = int(t - mark)
				var m := y.mass()
				cur.drift = maxi(int(cur.drift), absi(int(m.total) - int((cur.mass0 as Dictionary).total)))
				if debug:
					print("DBG   front spill %d mm this second, clods %d mm (%.0f%%)" % [dz.spilled - int(cur.sp_was), dz.clods_mm - int(cur.mm_was), 100.0 * (dz.clods_mm - int(cur.mm_was)) / maxf(dz.spilled - int(cur.sp_was), 1.0)])
					cur.sp_was = dz.spilled
					cur.mm_was = dz.clods_mm
					print("DBG %d s share %.2f z %.2f v %.2f awake %d made %d clods %d mm load %.0f (clods %d mm) heap %.2f full %.2f step %d us '%s'" % [cur.sec, cur.share, dz.global_position.z, dz.speed, d.n, dz.clods_made, m.clods, dz.push_load, dz.clod_load, y.heap_ahead(dz), dz.full, d.step_us, dz.blocked])
			if t - mark >= SECS:
				dz.throttle = 0.0
				_end_push(dz)
				_next(5)
		5:
			# the clods come to rest by themselves (the dozer standing)
			var d: DsDirt = y.ds().dirt
			y.drive_dozer(y.dozer(), 0.0, LIFT)
			if debug and Engine.get_process_frames() % 30 == 0:
				var on := 0
				var hi := 0
				var slow := 0
				var dzr := y.dozer()
				for i in d.n:
					on += int(d.gnd[i] == 1)
					hi += int(d.py[i] > y.level_m() + 1.0)
					slow += int(Vector3(d.vx[i], d.vy[i], d.vz[i]).length() < 0.4)
				print("DBG rest %.1f s: %d awake, %d on the ground, %d over 1 m up, %d slow; dozer v %.2f" % [t - mark, d.n, on, hi, slow, dzr.speed])
				if d.n > 0 and d.n < 8:
					for i in d.n:
						print("DBG    clod at %.2f %.2f %.2f (dozer %.2f %.2f, ground %.2f) v %.2f %.2f %.2f age %.1f rest %.2f gnd %d" % [d.px[i], d.py[i], d.pz[i], dzr.global_position.x, dzr.global_position.z, y.ds().terrain.height_at(d.px[i], d.pz[i]), d.vx[i], d.vy[i], d.vz[i], d.age[i], d.rest[i], d.gnd[i]])
			if d.n == 0 or t - mark > 15.0:
				cur.rest_s = t - mark
				cur.left = d.n
				_next(6)
		6:
			if t - mark > 0.5:
				var d: DsDirt = y.ds().dirt
				cur.rest_us = d.step_us
				d.land_all()
				var m := y.mass()
				cur.drift_end = int(m.total) - int((cur.mass0 as Dictionary).total)
				cur.clods_end = int(m.clods)
				var e0: Array = cur.edge0
				var e1: Array = cur.edge1
				cur.rows_after = _windrows(minf(e0[0].x, e0[1].x), maxf(e0[0].x, e0[1].x), e0[0].z, e1[0].z)
				res[1 if float(cur.share) > 0.0 else 0] = cur
				k += 1
				if k < runs.size():
					y.level()
					_next(2)
				else:
					return _report()
	return false

func _end_push(dz: DsDozer) -> void:
	var d: DsDirt = y.ds().dirt
	var s := timer.stats()
	cur.frame = s.frame
	cur.layer = s.layer
	cur.show = s.show
	cur.both = Yard.FrameTimer.of(both)
	cur.step = Yard.FrameTimer.of(steps)
	cur.step_all = Yard.FrameTimer.of(steps_all)
	cur.metres = dz.global_position.distance_to(cur.at)
	cur.heap = y.heap_ahead(dz)
	cur.speed_end = dz.speed
	cur.push_load = dz.push_load
	cur.made = dz.clods_made
	cur.made_mm = dz.clods_mm
	cur.moved = dz.moved - int(cur.moved0)
	cur.spilled = dz.spilled - int(cur.spill0)
	cur.awake_end = d.n
	cur.direct = d.direct_n - int(cur.direct0)
	cur.shed = d.shed_n - int(cur.shed0)
	cur.settled = d.settled_n - int(cur.settled0)
	var m := y.mass()
	cur.drift = maxi(int(cur.drift), absi(int(m.total) - int((cur.mass0 as Dictionary).total)))
	cur.clods_at_end = int(m.clods)
	cur.edge1 = dz.edge_ends()
	var e0: Array = cur.edge0
	var e1: Array = cur.edge1
	cur.rows = _windrows(minf(e0[0].x, e0[1].x), maxf(e0[0].x, e0[1].x), e0[0].z, e1[0].z)

func _line(r: Dictionary, name: String) -> void:
	var why := ""
	for b in r.blocked:
		why += "'%s' %d frames; " % [b, r.blocked[b]]
	say("%s: %.2f m in %.0f s (at the end %.2f m/s); heap ahead %.2f m at the end, %.2f m at the most; %.0f blocks banked; %d blocks' worth moved; stops: %s" % [
		name, r.metres, SECS, r.speed_end, r.heap, r.heap_most, r.push_load, int(r.moved) / Yard.MM, why if why != "" else "none"])
	say("%s: frames %d, mean %.2f, p95 %.2f, worst %.2f ms; layer_us mean %.0f, p95 %.0f; show_us mean %.0f, p95 %.0f; the two together mean %.0f, p95 %.0f" % [
		name, r.frame.n, r.frame.mean, r.frame.p95, r.frame.worst, r.layer.mean, r.layer.p95, r.show.mean, r.show.p95, r.both.mean, r.both.p95])
	var w: Array = r.rows
	var wa: Array = r.rows_after
	say("%s: windrows 0.5 to 1.5 m outside the blade's ends, along its %.1f m: %d and %d mm over the patch's level (%d and %d columns) at the end of the push; %d and %d once everything's settled" % [
		name, r.metres, w[0], w[1], w[2], w[3], wa[0], wa[1]])

func _report() -> bool:
	var a: Dictionary = res.get(0, {})
	var b: Dictionary = res.get(1, {})
	if a.is_empty() or b.is_empty():
		check(false, "both runs made (a share over 0?)")
		return _done()
	say("the order: %s; the clods' share %.2f; DsDirt.FLY_MAX %d" % ["the clods first, then the baseline" if order == "ba" else "the baseline first, then the clods", b.share, DsDirt.FLY_MAX])
	_line(a, "baseline (no clods)")
	_line(b, "with clods")
	say("with clods: %d let go (%d mm: %.1f%% of the %d mm the blade's front moved on; %.1f%% of all it moved, the sweep behind its edge and all), %d awake at the most, %d at the end of the push (%d mm); %d settled during it, %d laid straight on the ground (no room for them, or under a crumb), %d put down by the caps; at the most %d mm of them in front of the blade as its load" % [
		b.made, b.made_mm, 100.0 * float(b.made_mm) / maxf(float(b.spilled), 1.0), b.spilled, 100.0 * float(b.made_mm) / maxf(float(b.moved), 1.0), b.awake_most, b.awake_end, b.clods_at_end, b.settled, b.direct, b.shed, b.load_most])
	say("with clods: the clods' step mean %.0f us, p95 %.0f, worst %.0f over the %d frames with any awake (mean %.0f over all %d); at rest %d us" % [
		b.step.mean, b.step.p95, b.step.worst, b.step.n, b.step_all.mean, b.step_all.n, b.rest_us])
	say("with clods: the dozer standing, the last clod's settled %.2f s on (%d left awake); then land_all: %d mm in clods" % [b.rest_s, b.left, b.clods_end])
	check(absf(float(a.metres) - STAGE4_M) <= 0.02, "the baseline is stage 4's push (%.2f m; stage 4's %.2f)" % [a.metres, STAGE4_M])
	check(int(a.made) == 0 and int(a.awake_most) == 0, "the baseline makes no clods (%d)" % a.made)
	check(int(b.drift) == 0 and int(a.drift) == 0, "not a mm made or lost at any second of the push or at its end (%d mm at the most; the baseline %d)" % [b.drift, a.drift])
	check(int(b.drift_end) == 0 and int(b.clods_end) == 0 and int(a.drift_end) == 0, "nor once every clod's settled and land_all's called (%d mm; %d mm left in clods)" % [b.drift_end, b.clods_end])
	var got := float(b.made_mm) / maxf(float(b.spilled), 1.0)
	check(absf(got - float(b.share)) <= 0.03, "the clods are their share of what the blade's front moves on (%.1f%%; DsDozer.CLOD_SHARE %.0f%%)" % [100.0 * got, 100.0 * float(b.share)])
	check(int(b.made) > 200, "over 200 clods let go (%d)" % b.made)
	check(int(b.awake_most) <= DsDirt.FLY_MAX, "never more awake than FLY_MAX (%d of %d)" % [b.awake_most, DsDirt.FLY_MAX])
	check(float(b.heap) >= 0.3 and float(b.heap) >= 0.8 * float(a.heap), "the heap ahead >= 0.3 m and >= 80%% of the baseline's (%.2f m of %.2f: %.0f%%)" % [b.heap, a.heap, 100.0 * float(b.heap) / maxf(float(a.heap), 0.001)])
	var w: Array = b.rows
	var wa: Array = a.rows
	check(int(w[0]) > 0 and int(w[1]) > 0, "a windrow in the columns 0.5 to 1.5 m outside each end of the blade (%d and %d mm; the baseline's %d and %d)" % [w[0], w[1], wa[0], wa[1]])
	check(float(b.metres) >= 0.8 * STAGE4_M and float(b.metres) >= 0.8 * float(a.metres), "metres moved >= 80%% of stage 4's (%.2f of %.2f: %.0f%%)" % [b.metres, a.metres, 100.0 * float(b.metres) / float(a.metres)])
	check(float(b.step.mean) <= 2000.0, "the clods' step <= 2.0 ms on average (%.0f us with any awake; p95 %.0f)" % [b.step.mean, b.step.p95])
	check(float(b.frame.p95) <= float(a.frame.p95) + 3.0, "frame p95 <= the baseline's + 3.0 ms (%.2f against %.2f: %+.2f; means %.2f against %.2f: %+.2f)" % [
		b.frame.p95, a.frame.p95, float(b.frame.p95) - float(a.frame.p95), b.frame.mean, a.frame.mean, float(b.frame.mean) - float(a.frame.mean)])
	check(float(b.both.mean) <= 1.2 * float(a.both.mean), "layer_us + show_us within 20%% of the baseline's (mean %.0f us against %.0f: %+.0f%%; p95 %.0f against %.0f: %+.0f%%)" % [
		b.both.mean, a.both.mean, 100.0 * (float(b.both.mean) / float(a.both.mean) - 1.0), b.both.p95, a.both.p95, 100.0 * (float(b.both.p95) / float(a.both.p95) - 1.0)])
	check(int(b.left) == 0 and float(b.rest_s) < 12.0, "the dozer standing, the clods come to rest and are gone (%.2f s)" % b.rest_s)
	return _done()
