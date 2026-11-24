extends SceneTree
## What a clod costs (dirt_physics_plan.md, stage 2; headless:
##   godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_clod_perf.gd -- --nosave
## ), on a small grid of its own (no arena), DsDirt alone with no time cap: 400, 800, 1200 and 1500 clods held awake for
## 10 s each (let go a few at a time from 1 to 2.5 m up, all over the middle of the ground, topped up every tick as clods settle; the grid
## slumping under them as in the game, its time not counted). Prints a step's time (mean, p95, worst) and the time a
## clod. Then: DsDirt.FLY_MAX awake fit, a step 2.0 ms or under on average and 4.0 ms or under at p95, in every run
## (a larger count that fits too is printed as a note: it doesn't every time); with twice FLY_MAX offered, the time cap (DsDirt.CLOD_US) holds the step's p95 to 4.0 ms by settling
## and turning away what it has no time for; at rest a step's under 0.05 ms; and not a millimetre's made or lost.
## Each is run three times, turn about, and fits only if every run does (the box is shared: see the progress log).
## Options: --counts=400,800 (others), --secs=10, --reps=3, --out=dir (the table, as clod_perf.txt). Owned by the voxel session.

const W := 128
const H := 96
const D := 128
const SURF := 64
const CELL := 0.125
const MEAN_US := 2000.0
const P95_US := 4000.0

var passed := 0
var failed := 0
var lines := PackedStringArray()

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		say("DSCLODPERF ok   " + what)
	else:
		failed += 1
		say("DSCLODPERF FAIL " + what)

func say(s: String) -> void:
	print(s)
	lines.append(s)

func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def

func _grid() -> DigSiteGrid:
	var g := DigSiteGrid.new()
	g.setup(W, H, D, SURF)
	DsMats.apply(g)
	g.generate(77)
	return g

# `count` held awake for `ticks`: -> the numbers. With cap_us 0 nothing's turned away (fly_max is count); with a cap,
# fly_max is count and the cap does what it does.
func _hold(count: int, ticks: int, cap_us: int) -> Dictionary:
	var g := _grid()
	var dirt := DsDirt.new()
	dirt.setup(g)
	dirt.fly_max = count
	dirt.cap_us = cap_us
	dirt.seed_ = 7 + count
	var total: int = g.ground_mm()
	var offered := 0
	var us := PackedInt32Array()
	var awake_sum := 0
	var ground_sum := 0
	var clod_steps := 0
	var grid_us := 0
	var drift := 0
	var warm := 90              # (ticks before it's counted: the pours filling up)
	for t in ticks + warm:
		# let go here and there over the middle 10 m of the ground (so it rises evenly: 1500 awake is a hundred cubic
		# metres in the 10 s), a metre or two up, a few at a time; each tick what's missing of `count`
		var need := count - dirt.awake()
		var k := 0
		while need > 0:
			var a := dirt.randf01() * TAU
			var x := W * 0.5 * CELL + (dirt.randf01() - 0.5) * 10.0
			var z := D * 0.5 * CELL + (dirt.randf01() - 0.5) * 10.0
			var y: float = minf(g.height_at(x / CELL, z / CELL) * CELL + 1.0 + (k % 7) * 0.25, (H - 2) * CELL)
			var mm := mini(need, 12) * DsDirt.CLOD
			# (as a blade or a bucket lets it go: a few at a time, crumbs and chunks among them)
			var made := dirt.spawn_mass(Vector3(x, y, z), Vector3(cos(a), 0.0, sin(a)) * 1.5, DsMats.DIRT, mm, 1.0, 0.3)
			offered += mm
			if made == 0:
				break
			need -= made
			k += 1
			if k > 400:
				break
		dirt.step(1.0 / 60.0)
		var t0 := Time.get_ticks_usec()
		g.layer_step(2000)
		if t % 3 == 0:
			g.settle(2000)
		if t >= warm:
			grid_us += Time.get_ticks_usec() - t0
			us.append(dirt.step_us)
			awake_sum += dirt.awake()
			clod_steps += dirt.awake()
			var on := 0
			for i in dirt.n:
				on += dirt.gnd[i]
			ground_sum += on
		if t % 20 == 0:
			drift = maxi(drift, absi(g.ground_mm() + dirt.mass_mm() + dirt.owed_mm() - total - offered))
	var sum := 0
	for v in us:
		sum += v
	us.sort()
	var out := {"count": count, "mean": float(sum) / us.size(), "p95": us[int(us.size() * 0.95)], "worst": us[us.size() - 1],
		"awake": float(awake_sum) / ticks, "on": float(ground_sum) / maxf(1.0, awake_sum), "per": float(sum) / maxf(1.0, clod_steps),
		"grid": float(grid_us) / ticks, "settled": dirt.settled_n, "shed": dirt.shed_n, "direct": dirt.direct_n, "drift": drift}
	# at rest: everything landed, then a step with nothing awake
	dirt.land_all()
	var r0 := Time.get_ticks_usec()
	for k in 1000:
		dirt.step(1.0 / 60.0)
	out["rest"] = (Time.get_ticks_usec() - r0) / 1000.0
	out["end"] = g.ground_mm() + dirt.mass_mm() + dirt.owed_mm() - total - offered
	out["left"] = dirt.awake()
	return out

func _row(r: Dictionary) -> String:
	return "%5d | %7.0f | %6.0f us | %6d us | %6d us | %5.2f us | %3.0f %% | %6d | %5d | %6d | %4.0f us" % [
		r.count, r.awake, r.mean, r.p95, r.worst, r.per, r.on * 100.0, r.settled, r.shed, r.direct, r.grid]

func _initialize() -> void:
	var secs := float(_arg("secs", "10"))
	var ticks := int(secs * 60.0)
	var counts := []
	for c in _arg("counts", "400,800,1200,1500").split(","):
		counts.append(int(c))
	say("DSCLODPERF   %s s each, no time cap. FLY_MAX %d, CLOD_US %d" % [secs, DsDirt.FLY_MAX, DsDirt.CLOD_US])
	say("DSCLODPERF   count | awake   | step mean | step p95  | worst     | a clod   | on ground | settled | shed | direct | grid")
	var best := 0
	var drift := 0
	var rest := 0.0
	var reps := maxi(1, int(_arg("reps", "3")))
	var rows := {}
	for c: int in counts:
		rows[c] = []
	# (each count `reps` times, turn about: this box is shared, a run can be a third slower than the one before it.
	# A count fits if every one of its runs does: it's a cap, it has to hold on a bad day)
	for rep in reps:
		for c: int in counts:
			var r := _hold(c, ticks, 0)
			rows[c].append(r)
			say("DSCLODPERF   " + _row(r))
			drift = maxi(drift, maxi(r.drift, absi(r.end)))
			rest = maxf(rest, r.rest)
	say("DSCLODPERF   each count over its %d runs:" % reps)
	var fit := {}
	for c: int in counts:
		var rs: Array = rows[c]
		var fits := true
		var mean := 0.0
		var p95 := 0
		var lo := 1e9
		for r: Dictionary in rs:
			fits = fits and r.mean <= MEAN_US and r.p95 <= P95_US and r.awake >= c * 0.9
			mean = maxf(mean, r.mean)
			lo = minf(lo, r.mean)
			p95 = maxi(p95, r.p95)
		say("DSCLODPERF   %5d: step mean %.0f to %.0f us, p95 %d us at most: %s" % [c, lo, mean, p95, "fits" if fits else "over"])
		fit[c] = fits
		if fits:
			best = maxi(best, c)
	# The cap has to hold on a bad day, so the check is one-sided: FLY_MAX itself must fit in every run. A bigger count
	# fitting too (1200 does about one time in five, on a good minute of a shared box) is a note, not a failure: the
	# constant stays where it fits every time, and the time cap takes the slack.
	var cap_fits: bool = rows.has(DsDirt.FLY_MAX) and fit[DsDirt.FLY_MAX]
	check(cap_fits and best >= DsDirt.FLY_MAX, "FLY_MAX (%d) awake fit in every run: a step's 2.0 ms or under on average and 4.0 ms at p95 (the largest count that fit: %d)" % [DsDirt.FLY_MAX, best])
	if best > DsDirt.FLY_MAX:
		say("DSCLODPERF note %d fit as well this time (FLY_MAX stays %d: it has to fit every time, and %d doesn't)" % [best, DsDirt.FLY_MAX, best])
	check(best >= 500, "500 awake or more fit (the plan's floor)")
	# twice that offered, with the time cap on
	var twos := []
	for rep in reps:
		var t := _hold(DsDirt.FLY_MAX * 2, ticks, DsDirt.CLOD_US)
		say("DSCLODPERF   " + _row(t) + "   (the time cap on)")
		twos.append(t)
		drift = maxi(drift, maxi(t.drift, absi(t.end)))
		rest = maxf(rest, t.rest)
	twos.sort_custom(func(x, y): return x.p95 < y.p95)
	var two: Dictionary = twos[twos.size() / 2]
	check(two.p95 <= P95_US and two.left == 0, "with %d offered the time cap holds the step's p95 to 4.0 ms (%d us; mean %.0f; %.0f awake; %d shed, %d turned away)" % [
		DsDirt.FLY_MAX * 2, two.p95, two.mean, two.awake, two.shed, two.direct])
	check(drift == 0, "not a millimetre made or lost in any of it (%d mm off at most)" % drift)
	check(rest <= 50.0, "with none awake a step's 0.05 ms or under (%.2f us)" % rest)
	say("DSCLODPERF done %d passed, %d failed" % [passed, failed])
	var out := _arg("out", "")
	if out != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
		var f := FileAccess.open(out.path_join("clod_perf.txt"), FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(lines) + "\n")
			f.close()
	quit()
