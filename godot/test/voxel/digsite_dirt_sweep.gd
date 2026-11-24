extends SceneTree
## The dirt physics' whole-session sweep (integration/dirt_physics_plan.md, stage 9; headless:
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_dirt_sweep.gd -- --nosave
## ). A 60 s scripted session on the yard's levelled patch, twice in the one run, back to back: first as the game was
## before the clods (the dozer's clod_share 0, the machines' pour_clods off, the blasts' clods off, the script's rain
## laid straight on the ground: the baseline), then, the patch levelled again, with the clods (--order=ba: the other
## way round). The session:
##    0 ..  4 s  the Bobcat scoops a bucket off the patch;
##    4 ..  8 s  nosed up to the tip truck's side, it pours it into the tray;
##    8 .. 18 s  the truck tips its tray out behind it;
##   10 .. 40 s  the bulldozer flat out across the patch, its blade 0.1 m in the ground (22 .. 27 s: backed off
##               its heap, blade up, then at it again);
##   14 s        a stick of dynamite lit beside its path (it goes off at 18 s);
##   20 .. 30 s  the cap: the script rains RAIN mm of dirt a frame over the dozer's path, as clods, far more than
##               there's room for (DsDirt.FLY_MAX awake, the time cap): what there's no room for goes straight down;
##   40 .. 60 s  everything comes to rest.
## Passes:
##   the cap was reached and held (awake at FLY_MAX or at the time cap's room: clods refused for want of room);
##   whole-frame p95 over the 60 s no more than the baseline's + 3.0 ms;
##   the clods' step (DsDirt.step_us) 2.0 ms at the most on average, over the session and over the 10 s at the cap;
##   not a mm made or lost at any second, nor at the end (the rain counted in);
##   the session's parts all happened (a bucket scooped and poured into the tray, the tray tipped empty, the blast,
##   the dozer's metres), the clods come to rest;
##   and stage 9's feel: the view behind the dozer drops back with its speed (up to DsMachines.CAM_PULL) and shakes
##   under 3 cm while its tracks slip; clods landing tick.
## The plan's absolute "frame p95 <= 12 ms" is printed as a NOTE, not a check: the baseline alone is over it on this
## box (the progress log, stage 1). Writes integration/dirt_shots/sweep.txt (--out=dir). --debug a line a second.
## Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
const SESSION := 60.0
const RAIN := 8000              # mm a frame, 20 .. 30 s
const RAIN_SPOTS := 4

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var out := "res://integration/dirt_shots"
var order := "ab"
var debug := false
var lines := PackedStringArray()
var runs := []
var k := 0
var res := {}
var cur := {}
var timer: Yard.FrameTimer
var steps := PackedFloat32Array()
var cap_steps := PackedFloat32Array()
var cap_awake := PackedFloat32Array()
var rng := RandomNumberGenerator.new()
var done_bits := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--order="):
			order = a.trim_prefix("--order=")
		elif a == "--debug":
			debug = true
	runs = [true, false] if order == "ba" else [false, true]
	y.boot(self)

func say(s: String) -> void:
	lines.append("DSSWEEP " + s)
	print("DSSWEEP ", s)

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
	var f := FileAccess.open(dir.path_join("sweep.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _truck() -> DsTruck:
	return y.machine("tip truck") as DsTruck

func _bobcat() -> DsBobcat:
	return y.machine("Bobcat") as DsBobcat

func _once(what: String, at: float) -> bool:
	if t - mark >= at and not done_bits.has(what):
		done_bits[what] = true
		return true
	return false

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
			if t - mark > 1.0:
				_setup()
				_next(3)
		3:
			if t - mark > 1.0:
				_begin()
				_next(4)
		4:
			_session(dt)
			if t - mark >= SESSION:
				_end()
				k += 1
				if k < runs.size():
					y.level()
					_next(2)
				else:
					_report()
					return _done()
	return false

# the machines where the session has them, the game as this run wants it
func _setup() -> void:
	var ds := y.ds()
	var d: DsDirt = ds.dirt
	var clods: bool = runs[k]
	if k == 0:
		var f := y.flatness()
		check(float(f[0]) >= -1.0 and float(f[1]) <= 1.0, "the patch is flat to +-1 cell (%.2f to %.2f)" % [f[0], f[1]])
		check(_truck() != null and _bobcat() != null and y.dozer() != null, "a tip truck, a Bobcat and a bulldozer at the site")
		say("the order: %s; DsDirt.FLY_MAX %d, its time cap %d us; DsDozer.CLOD_SHARE %.2f; the rain %d mm a frame for 10 s" % ["the baseline first, then the clods" if not clods else "the clods first, then the baseline", DsDirt.FLY_MAX, d.cap_us, DsDozer.CLOD_SHARE, RAIN])
	d.land_all()
	d.fly_max = DsDirt.FLY_MAX if clods else 0
	for m: DsMachine in ds.machines.list:
		m.pour_clods = clods
	ds.blasts.clods = clods
	var dz := y.park_dozer()
	dz.clod_share = DsDozer.CLOD_SHARE if clods else 0.0
	dz.throttle = 0.0
	var tk := _truck()
	var c := y.centre()
	tk.tip = 0.0
	tk.tip_cmd = 0.0
	tk.tray_load = {}
	tk.load_n = 0
	y.park(tk, c.x - 9.0, c.z + 1.0, 0.0)
	var bc := _bobcat()
	bc.bucket = {}
	bc.load_n = 0
	bc.curl = 0.0
	bc.curl_cmd = 0.0
	bc.lift_cmd = 0.0
	bc.arm = bc.arm_low
	y.park(bc, c.x + 9.0, c.z + 8.0, 0.0)
	y.mount(bc)
	rng.seed = 909
	done_bits = {}

func _begin() -> void:
	var ds := y.ds()
	var d: DsDirt = ds.dirt
	cur = {"clods": bool(runs[k]), "total": int(y.mass().total), "added": 0, "drift": 0, "sec": 0, "awake_most": 0,
		"direct0": d.direct_n, "shed0": d.shed_n, "settled0": d.settled_n, "refused": 0, "pull_most": 0.0, "shake_most": 0.0,
		"ticks0": ds.ticks.played if ds.ticks else 0, "booms0": ds.blasts.booms, "scooped": 0, "tray_most": 0, "tray_end": -1,
		"dz_at": y.dozer().global_position, "rest_s": -1.0, "slip_frames": 0, "shake_still": 0.0}
	timer = Yard.FrameTimer.new()
	timer.start()
	steps.clear()
	cap_steps.clear()
	cap_awake.clear()

func _session(dt: float) -> void:
	var ds := y.ds()
	var d: DsDirt = ds.dirt
	var s := t - mark
	var bc := _bobcat()
	var tk := _truck()
	var dz := y.dozer()
	timer.tick(ds.terrain)
	# the Bobcat: scoops, then pours into the tray
	if s < 0.5:
		bc.arm = bc.arm_low
	elif s < 3.5:
		bc.throttle = 0.6
	elif _once("to_truck", 3.5):
		bc.throttle = 0.0
		cur.scooped = bc.load_n
		var tm: Vector3 = tk.global_transform * DsTruck.TRAY_AT
		bc.arm = 0.7
		y.park(bc, tm.x + DsTruck.TRAY.x * 0.5 + bc.length * 0.5, tm.z, PI * 0.5)
		bc._pour_p = Vector3.INF
	elif s >= 4.2 and s < 8.0:
		bc.curl_cmd = -1.0
	elif _once("to_tip", 8.0):
		bc.curl_cmd = 0.0
		cur.left_in_bucket = bc.load_n
		cur.tray_most = tk.load_n
		y.park(bc, y.centre().x - 9.0, y.centre().z - 9.0, PI * 0.5)     # (out of everyone's way)
		y.mount(tk)
		tk.tip_cmd = 1.0
	if s >= 8.0 and s < 18.0:
		tk.tip_cmd = 1.0
	elif _once("tray_down", 18.0):
		cur.tray_end = tk.load_n
		tk.tip_cmd = -1.0
	elif _once("tray_stop", 22.0):
		tk.tip_cmd = 0.0
	# the bulldozer
	if _once("on_dozer", 9.5):
		tk.auto = true
		y.mount(dz)
		tk.tip_cmd = 1.0
	if s >= 10.0 and s < 40.0:
		# (flat out, its blade in the ground; 22 .. 27 s backed off its heap, blade up, then at it again)
		if s >= 22.0 and s < 27.0:
			y.drive_dozer(dz, -1.0, 0.3)
		else:
			y.drive_dozer(dz, 1.0, -0.1)
		cur.on_dozer = ds.machines.driving == dz
		cur.path = float(cur.get("path", 0.0)) + absf(dz.speed) * dt
		cur.pull_most = maxf(float(cur.pull_most), ds.machines.cam_pull)
		cur.shake_most = maxf(float(cur.shake_most), (ds.machines.cam_shake as Vector3).length())
		if dz.slip > 0.3:
			cur.slip_frames = int(cur.slip_frames) + 1
	elif _once("dozer_stop", 40.0):
		dz.throttle = 0.0
		cur.metres = float(cur.get("path", 0.0))
	elif s > 44.0:
		cur.shake_still = maxf(float(cur.shake_still), (ds.machines.cam_shake as Vector3).length())
	# the blast
	if _once("blast", 14.0):
		var p: Vector3 = y.centre() + Vector3(6.5, 0, -3.0)
		y.arena.inv.add("dynamite", 1)
		cur.total = int(cur.total) + Yard.MM * 0
		cur.pack0 = int(y.mass().pack)
		var before := int(y.mass().total)
		cur.lit = ds.blasts.light(Vector3(p.x, ds.terrain.top_at(p.x, p.z) + 0.02, p.z))
		cur.added = int(cur.added) + int(y.mass().total) - before     # (the stick itself, if the pack counts it: it doesn't)
	# the rain: the cap
	if s >= 20.0 and s < 30.0:
		var c := y.centre()
		for i in RAIN_SPOTS:
			var p := Vector3(c.x + rng.randf_range(-5.0, 5.0), 0.0, c.z + rng.randf_range(-8.0, 4.0))
			p.y = ds.terrain.height_at(p.x, p.z) + rng.randf_range(2.0, 4.0)
			if not d.has_room(1):
				cur.refused = int(cur.refused) + 1
			d.spawn_mass(p, Vector3(rng.randf_range(-1.0, 1.0), -1.0, rng.randf_range(-1.0, 1.0)), DsMats.DIRT, RAIN / RAIN_SPOTS, 1.0, 0.4)
			cur.added = int(cur.added) + RAIN / RAIN_SPOTS
		cap_awake.append(float(d.n))
		if d.n > 0:
			cap_steps.append(float(d.step_us))
	if d.n > 0:
		steps.append(float(d.step_us))
	cur.awake_most = maxi(int(cur.awake_most), d.n)
	if s > 41.0 and float(cur.rest_s) < 0.0 and d.awake() == 0:
		cur.rest_s = s
	if int(s) > int(cur.sec):
		cur.sec = int(s)
		var m := y.mass()
		cur.drift = maxi(int(cur.drift), absi(int(m.total) - int(cur.total) - int(cur.added)))
		if debug:
			print("DBG %d s: awake %d, step %d us, tray %d, bobcat %d, dozer %.2f m/s slip %.2f, pull %.2f shake %.1f mm, drift %d, booms %d" % [cur.sec, d.n, d.step_us, tk.load_n, bc.load_n, dz.speed, dz.slip, ds.machines.cam_pull, (ds.machines.cam_shake as Vector3).length() * 1000.0, int(m.total) - int(cur.total) - int(cur.added), ds.blasts.booms])

func _end() -> void:
	var ds := y.ds()
	var d: DsDirt = ds.dirt
	cur.frame = timer.stats().frame
	cur.step = Yard.FrameTimer.of(steps)
	cur.cap_step = Yard.FrameTimer.of(cap_steps)
	cur.cap_awake = Yard.FrameTimer.of(cap_awake)
	cur.left = d.awake()
	cur.end_drift = int(y.mass().total) - int(cur.total) - int(cur.added)
	d.land_all()
	cur.land_drift = int(y.mass().total) - int(cur.total) - int(cur.added)
	cur.direct = d.direct_n - int(cur.direct0)
	cur.shed = d.shed_n - int(cur.shed0)
	cur.settled = d.settled_n - int(cur.settled0)
	cur.ticks = (ds.ticks.played if ds.ticks else 0) - int(cur.ticks0)
	cur.booms = ds.blasts.booms - int(cur.booms0)
	cur.pull_end = ds.machines.cam_pull
	if ds.machines.driving:
		ds.machines.get_off()
	res[1 if cur.clods else 0] = cur
	say("%s: the Bobcat scooped %d mm and poured it (%d left in it), the tray held %d and tipped to %d; the blast %s; the dozer %.2f m in 30 s; the rain %d mm; clods awake at the most %d (%d settled, %d spawns laid straight down, %d put down by the caps), at rest %.1f s in (%d left at 60 s)" % [
		"with clods" if cur.clods else "baseline (no clods)", cur.scooped, int(cur.get("left_in_bucket", -1)), cur.tray_most, cur.tray_end, "went off" if int(cur.booms) == 1 else "did NOT go off", float(cur.get("metres", 0.0)), cur.added, cur.awake_most, cur.settled, cur.direct, cur.shed, cur.rest_s, cur.left])
	say("%s: frames %d, mean %.2f, p95 %.2f, worst %.2f ms; the clods' step mean %.0f us, p95 %.0f, worst %.0f over %d frames with any; in the 10 s at the cap: awake mean %.0f, most %.0f, step mean %.0f us, p95 %.0f, worst %.0f; %d rain spots found no room; mass drift %d mm at the most, %d at the end, %d after land_all" % [
		"with clods" if cur.clods else "baseline (no clods)", cur.frame.n, cur.frame.mean, cur.frame.p95, cur.frame.worst, cur.step.mean, cur.step.p95, cur.step.worst, cur.step.n,
		cur.cap_awake.mean, cur.cap_awake.worst, cur.cap_step.mean, cur.cap_step.p95, cur.cap_step.worst, cur.refused, cur.drift, cur.end_drift, cur.land_drift])
	say("%s: the view behind the dozer dropped back %.1f%% at the most (%.1f%% at 60 s, standing), shook %.1f mm at the most (%d frames its tracks slipped), %.1f mm standing; %d ticks" % [
		"with clods" if cur.clods else "baseline (no clods)", 100.0 * DsMachines.CAM_PULL * float(cur.pull_most), 100.0 * DsMachines.CAM_PULL * float(cur.pull_end), float(cur.shake_most) * 1000.0, cur.slip_frames, float(cur.shake_still) * 1000.0, cur.ticks])

func _report() -> void:
	var b: Dictionary = res[0]
	var c: Dictionary = res[1]
	var d: DsDirt = y.ds().dirt
	for r: Dictionary in [b, c]:
		var who := "with clods" if r.clods else "the baseline"
		check(int(r.scooped) > 60 * Yard.MM and int(r.tray_most) >= int(float(r.scooped) * 0.85) and int(r.tray_end) == 0, "%s: a bucket scooped (%d mm), poured into the tray (%d: >= 85%%), the tray tipped empty (%d left)" % [who, r.scooped, r.tray_most, r.tray_end])
		check(int(r.booms) == 1 and bool(r.get("on_dozer", false)) and float(r.get("metres", 0.0)) > 6.0, "%s: the blast went off, the dozer driven from its seat %.2f m (forward, back off its heap, forward again)" % [who, float(r.get("metres", 0.0))])
		check(int(r.drift) == 0 and int(r.end_drift) == 0 and int(r.land_drift) == 0, "%s: not a mm made or lost at any second, at 60 s, or after land_all (%d, %d, %d mm; the rain's %d counted in)" % [who, r.drift, r.end_drift, r.land_drift, r.added])
	check(int(b.awake_most) == 0, "the baseline makes no clods (%d)" % int(b.awake_most))
	var room := d._room()
	check(int(c.refused) > 100 and int(c.awake_most) <= DsDirt.FLY_MAX and float(c.cap_awake.mean) >= 0.5 * float(c.awake_most), "the cap was reached and held: %d of the rain's spots found no room; awake %d at the most (FLY_MAX %d; the time cap's room %d at the end), %.0f on average through the 10 s" % [c.refused, c.awake_most, DsDirt.FLY_MAX, room, c.cap_awake.mean])
	check(float(c.step.mean) <= 2000.0, "the clods' step <= 2.0 ms on average over the session (%.0f us with any awake; p95 %.0f)" % [c.step.mean, c.step.p95])
	check(float(c.cap_step.mean) <= 2000.0, "and over the 10 s at the cap (%.0f us; p95 %.0f, worst %.0f)" % [c.cap_step.mean, c.cap_step.p95, c.cap_step.worst])
	check(float(c.frame.p95) <= float(b.frame.p95) + 3.0, "frame p95 <= the baseline's + 3.0 ms (%.2f against %.2f: %+.2f; means %.2f against %.2f: %+.2f)" % [c.frame.p95, b.frame.p95, float(c.frame.p95) - float(b.frame.p95), c.frame.mean, b.frame.mean, float(c.frame.mean) - float(b.frame.mean)])
	say("NOTE the plan's absolute frame p95 <= 12 ms: %.2f with clods, %.2f the baseline (%s; not a check: stage 1 measured the baseline alone over it on this box)" % [c.frame.p95, b.frame.p95, "met" if float(c.frame.p95) <= 12.0 else "not met"])
	check(float(c.rest_s) >= 0.0 and int(c.left) == 0, "the clods come to rest (%.1f s into the session; %d left at 60 s)" % [c.rest_s, c.left])
	check(float(c.pull_most) > 0.3 and float(c.pull_most) <= 1.0 and float(c.pull_end) < 0.1, "the view drops back with the dozer's speed: %.1f%% at the most (never over %.0f%%), %.1f%% standing" % [100.0 * DsMachines.CAM_PULL * float(c.pull_most), 100.0 * DsMachines.CAM_PULL, 100.0 * DsMachines.CAM_PULL * float(c.pull_end)])
	check(float(c.shake_most) > 0.003 and float(c.shake_most) <= DsMachines.CAM_SHAKE_MOST + 0.0001 and float(c.shake_still) == 0.0, "it shakes while the tracks slip, under 3 cm (%.1f mm at the most), and not standing (%.1f mm)" % [float(c.shake_most) * 1000.0, float(c.shake_still) * 1000.0])
	check(int(c.ticks) > 20 and int(b.ticks) == 0, "clods landing tick (%d; the baseline %d)" % [c.ticks, b.ticks])
