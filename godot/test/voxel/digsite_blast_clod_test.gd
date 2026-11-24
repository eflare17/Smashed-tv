extends SceneTree
## A blast's dirt as real clods (integration/dirt_physics_plan.md, stage 7; headless:
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_blast_clod_test.gd -- --nosave
## ). On the yard (the levelled 24 x 24 m patch), one stick of dynamite at a time, each on fresh ground 12 m from the
## last: twice with the blast as it was before the clods' cost (DsBlasts.clods false: what's blown out laid round the
## crater at once: the baseline) and twice with the clods, turn about (--order=ba: clods first). Then four sticks
## together. Passes, for a stick with the clods:
##   not a mm made or lost at any second, nor once every clod's at rest, nor after land_all();
##   90% or more of what was blown out comes to rest within 3 x the blast's radius (3.9 m) of the stick;
##   never more awake than DsDirt.FLY_MAX; the clods' step (DsDirt.step_us) p95 4.0 ms at the most;
##   the worst frame from the bang to 6 s after no more than the baseline's + 8 ms (the better of the two of each: one
##   stall from another job on this box is not the blast's; all four are printed).
## And: a crater; over 100 clods thrown; all at rest (DsBlasts.busy() false) within 10 s; four sticks together stay
## under FLY_MAX (the lumps get bigger as the air fills) with the mass exact.
## Writes integration/dirt_shots/blast.txt (--out=dir). Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
const WINDOW := 6.0             # s after the bang the frames are looked at
const SPOTS := [Vector3(-6, 0, -8), Vector3(6, 0, -8), Vector3(-6, 0, 4), Vector3(6, 0, 4), Vector3(0, 0, -2)]

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var out := "res://integration/dirt_shots"
var order := "ab"
var lines := PackedStringArray()
var runs := []                  # [clods?, sticks]
var k := 0
var res := []                   # a run each: what was measured
var cur := {}
var timer: Yard.FrameTimer
var steps := PackedFloat32Array()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--order="):
			order = a.trim_prefix("--order=")
	var a := [false, 1]
	var b := [true, 1]
	runs = [b, a, b, a] if order == "ba" else [a, b, a, b]
	runs.append([true, 4])
	y.boot(self)

func say(s: String) -> void:
	lines.append("DSBLAST " + s)
	print("DSBLAST ", s)

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
	var f := FileAccess.open(dir.path_join("blast.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _spot(i: int) -> Vector3:
	var p: Vector3 = DigSite.AT + SPOTS[i]
	return Vector3(p.x, y.ds().terrain.top_at(p.x, p.z), p.z)

func _process(dt: float) -> bool:
	t += dt
	if t > 400.0:
		check(false, "timed out at step %d" % step)
		return _done()
	var ds := y.ds()
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
			if t - mark > 1.5:
				var f := y.flatness()
				check(float(f[0]) >= -1.0 and float(f[1]) <= 1.0, "the patch is flat to +-1 cell (%.2f to %.2f)" % [f[0], f[1]])
				ds._put(DigSite.AT + Vector3(0, 0.1, 16), 0.0, 0.0)
				ds.dirt.cap_us = 0          # (the same every run: the time cap is by the clock)
				ds.dirt.log_on = true
				_next(3)
		3:
			# a run: its stick (or four) lit
			if t - mark > 1.0:
				var d: DsDirt = ds.dirt
				var bl: DsBlasts = ds.blasts
				bl.clods = bool(runs[k][0])
				var at := _spot(k)
				var n: int = runs[k][1]
				y.arena.inv.add("dynamite", n)
				var lit := 0
				for i in n:
					var o := Vector3.ZERO if n == 1 else Vector3(cos(TAU * i / n), 0, sin(TAU * i / n)) * 0.9
					if bl.light(at + o + Vector3(0, 0.02, 0)):
						lit += 1
				d.settle_log.clear()
				cur = {"clods": bool(runs[k][0]), "sticks": n, "lit": lit, "at": at, "mass0": y.mass(), "booms0": bl.booms, "thrown0": bl.thrown,
					"thrown_mm0": bl.thrown_mm, "laid0": bl.laid_mm, "direct0": d.direct_n, "shed0": d.shed_n, "sec": 0, "drift": 0,
					"awake_most": 0, "by_id": {}, "blown": 0, "rest_s": -1.0, "bang": -1.0, "step_most": 0}
				timer = Yard.FrameTimer.new()
				_next(4)
		4:
			# the fuse, the bang, the clods, till they're at rest
			var d: DsDirt = ds.dirt
			var bl: DsBlasts = ds.blasts
			if float(cur.bang) < 0.0:
				if bl.booms >= int(cur.booms0) + int(cur.sticks):
					cur.bang = t
					cur.blown = int(bl.last.n) * (1 if int(cur.sticks) == 1 else 0)
					for i in d.n:
						cur.by_id[d.cid[i]] = d.cmm[i]
					# (the frame the bang was in is the one just gone: it's counted)
					var last := (Time.get_ticks_usec() - timer._was) / 1000.0 if timer._was > 0 else 0.0
					timer.start()
					timer.frames.append(last)
				else:
					timer._was = Time.get_ticks_usec()      # (the last frame's start, kept for the bang's own)
				return false
			var since: float = t - float(cur.bang)
			if since <= WINDOW:
				timer.tick(ds.terrain)
				if d.n > 0:
					steps.append(float(d.step_us))
					cur.step_most = maxi(int(cur.step_most), d.step_us)
			cur.awake_most = maxi(int(cur.awake_most), d.n)
			if int(since) > int(cur.sec):
				cur.sec = int(since)
				cur.drift = maxi(int(cur.drift), absi(int(y.mass().total) - int(cur.mass0.total)))
			if float(cur.rest_s) < 0.0 and not bl.busy():
				cur.rest_s = since
			if (float(cur.rest_s) >= 0.0 and since > WINDOW + 1.0) or since > 30.0:
				_measure()
				k += 1
				_next(3 if k < runs.size() else 5)
		5:
			if t - mark > 0.5:
				_report()
				return _done()
	return false

# a run's over: where its dirt came to rest, its crater, the mass
func _measure() -> void:
	var ds := y.ds()
	var d: DsDirt = ds.dirt
	var bl: DsBlasts = ds.blasts
	var at: Vector3 = cur.at
	var far := 0                # mm in clods that came to rest beyond 3 x the radius
	var furthest := 0.0
	var seen := 0
	var lg := d.settle_log
	for i in range(0, lg.size() - 4, 5):
		var id := int(lg[i])
		if not cur.by_id.has(id):
			continue
		seen += 1
		var r := Vector2(lg[i + 1] - at.x, lg[i + 3] - at.z).length()
		furthest = maxf(furthest, r)
		if r > DsBlasts.RADIUS * 3.0:
			far += int(cur.by_id[id])
	cur.far = far
	cur.furthest = furthest
	cur.seen = seen
	cur.still = d.n
	cur.thrown = bl.thrown - int(cur.thrown0)
	cur.thrown_mm = bl.thrown_mm - int(cur.thrown_mm0)
	cur.laid = bl.laid_mm - int(cur.laid0)
	cur.direct = d.direct_n - int(cur.direct0)
	cur.shed = d.shed_n - int(cur.shed0)
	cur.frame = timer.stats().frame
	cur.crater = at.y - ds.terrain.surface_at(at.x, at.z)
	cur.end_drift = int(y.mass().total) - int(cur.mass0.total)
	cur.ground_drift = int(y.mass().ground) - int(cur.mass0.ground) + (int(cur.mass0.pack) - int(y.mass().pack)) * 0
	d.land_all()
	cur.land_drift = int(y.mass().total) - int(cur.mass0.total)
	cur.left = d.mass_mm() + d.owed_mm()
	say("run %d: %s, %d stick(s): %d blocks blown out, %d clods (%d mm) thrown, %d mm laid straight; awake %d at the most; at rest %.2f s after the bang; crater %.2f m; frames mean %.2f p95 %.2f worst %.2f ms; step worst %.2f ms" % [
		k, "clods" if cur.clods else "baseline", cur.sticks, cur.blown, cur.thrown, cur.thrown_mm, cur.laid, cur.awake_most, cur.rest_s, cur.crater,
		cur.frame.mean, cur.frame.p95, cur.frame.worst, int(cur.step_most) / 1000.0])
	res.append(cur)

func _report() -> void:
	var base := []
	var clod := []
	var four := {}
	for r: Dictionary in res:
		if int(r.sticks) > 1:
			four = r
		elif bool(r.clods):
			clod.append(r)
		else:
			base.append(r)
	var st := Yard.FrameTimer.of(steps)
	var i := 0
	for r: Dictionary in clod:
		i += 1
		var blown: int = int(r.blown) * Yard.MM
		check(int(r.lit) == 1 and blown > 1000 * Yard.MM and float(r.crater) > 0.6, "stick %d goes off: %d blocks blown out, a crater %.2f m deep" % [i, r.blown, r.crater])
		check(int(r.drift) == 0 and int(r.end_drift) == 0 and int(r.land_drift) == 0 and int(r.left) == 0,
			"stick %d: not a mm made or lost (each second %d, at rest %d, after land_all %d; %d mm left in clods)" % [i, r.drift, r.end_drift, r.land_drift, r.left])
		check(int(r.thrown_mm) + int(r.laid) == blown, "stick %d: all of it thrown or laid (%d + %d of %d mm)" % [i, r.thrown_mm, r.laid, blown])
		check(int(r.thrown) > 100 and int(r.seen) == int(r.thrown), "stick %d: over 100 clods thrown (%d; %d of them seen to rest)" % [i, r.thrown, r.seen])
		var near: float = 100.0 * (blown - int(r.far)) / maxf(1.0, blown)
		check(near >= 90.0, "stick %d: 90%% or more comes to rest within %.1f m (%.1f%%: %d of %d mm beyond; the furthest %.2f m)" % [i, DsBlasts.RADIUS * 3.0, near, r.far, blown, r.furthest])
		check(int(r.awake_most) <= DsDirt.FLY_MAX and int(r.shed) == 0, "stick %d: never more awake than %d (%d at the most; %d put down by the caps, %d never clods)" % [i, DsDirt.FLY_MAX, r.awake_most, r.shed, r.direct])
		check(float(r.rest_s) >= 0.0 and float(r.rest_s) <= 10.0 and int(r.still) == 0, "stick %d: all at rest %.2f s after the bang" % [i, r.rest_s])
	for r: Dictionary in base:
		check(int(r.drift) == 0 and int(r.end_drift) == 0 and int(r.thrown) == 0, "the baseline: no clods, not a mm made or lost (%d blocks blown out)" % int(r.blown))
	check(float(st.p95) <= 4000.0, "the clods' step: p95 %.2f ms (4.0 at the most), mean %.2f, worst %.2f, over %d frames" % [st.p95 / 1000.0, st.mean / 1000.0, st.worst / 1000.0, st.n])
	var bw := INF
	var cw := INF
	var all := []
	for r: Dictionary in base:
		bw = minf(bw, float(r.frame.worst))
		all.append("baseline %.2f" % float(r.frame.worst))
	for r: Dictionary in clod:
		cw = minf(cw, float(r.frame.worst))
		all.append("clods %.2f" % float(r.frame.worst))
	check(cw <= bw + 8.0, "the worst frame from the bang to %d s after: %.2f ms with the clods, the baseline's %.2f (+%.2f; 8 more at the most; each: %s)" % [int(WINDOW), cw, bw, cw - bw, ", ".join(all)])
	if not four.is_empty():
		check(int(four.lit) == 4 and int(four.awake_most) <= DsDirt.FLY_MAX and int(four.drift) == 0 and int(four.end_drift) == 0 and int(four.land_drift) == 0,
			"four sticks together: %d clods (%d mm) thrown, %d awake at the most (%d at the most), mass exact (%d, %d, %d); at rest %.2f s on; worst frame %.2f ms, step worst %.2f ms" % [
			four.thrown, four.thrown_mm, four.awake_most, DsDirt.FLY_MAX, four.drift, four.end_drift, four.land_drift, four.rest_s, four.frame.worst, int(four.step_most) / 1000.0])
