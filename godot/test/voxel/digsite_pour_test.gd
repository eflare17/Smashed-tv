extends SceneTree
## A pour is a stream of clods that can miss (integration/dirt_physics_plan.md, stage 6; headless:
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_pour_test.gd -- --nosave
## ). The yard (the levelled 24 x 24 m patch), the tip truck parked on it, the Dingo beside it with its arms up and a
## full bucket put in it by the script. Twice in the one run, back to back: first with the machines' pour_clods off
## (what's poured lands at once, as before the clods: the baseline, for the frame times), then, the patch levelled
## again, with the clods (--order=ba: the other way round). Each time:
##   (a) the Dingo's lip over the tray's middle, tipped: the tray's load gains at least 85% of what was poured, the
##       rest is on the ground;
##   (b) the bucket filled again, the Dingo 2 m further back (its lip 0.8 m outside the tray's side): the tray gains 0;
##   (c) the truck tips: within 10 s at least 95% of its load is on the ground behind it.
## Not a mm made or lost in any of the three (looked at every second and at each one's end); the clods' step
## (DsDirt.step_us) 2.0 ms at the most on average; the frame's p95 no more than the baseline's + 3.0 ms.
## And, added: (d) the Bobcat nosed up to the truck's side from outside it, its lip over the tray's rim: the tray
## gains at least 85%; (e) backed off so its lip's over the tray's side wall: some lands in the tray and some goes over
## the side; (f) the tray filled to its brim by the script and tipped: all of it out and on the ground, never more
## clods awake than DsDirt.FLY_MAX, their step 2.0 ms at the most on average. Writes integration/dirt_shots/pour.txt (--out=dir). --debug a line a second.
## Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
const OFFSET := 2.0             # m: (b)'s pour, this far off the tray's middle
const TIP_S := 10.0             # s: (c)'s

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
var runs := []                  # the runs to do: clods or not
var k := 0
var res := {}                   # by run (0: the baseline; 1: the clods)
var cur := {}
var timer: Yard.FrameTimer
var steps := PackedFloat32Array()   # the clods' step_us, each frame with any awake
var part := ""                  # which of (a) .. (d) is running

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
	lines.append("DSPOUR " + s)
	print("DSPOUR ", s)

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
	var f := FileAccess.open(dir.path_join("pour.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _truck() -> DsTruck:
	return y.machine("tip truck") as DsTruck

func _dingo() -> DsDingo:
	return y.machine("Dingo") as DsDingo

func _bobcat() -> DsBobcat:
	return y.machine("Bobcat") as DsBobcat

## The tray's middle (its floor's), in the world
func _tray_mid() -> Vector3:
	return _truck().global_transform * DsTruck.TRAY_AT

## A loader put so its lip's over (x, z), facing -x, standing
func _lip_to(d: DsDingo, x: float, z: float) -> void:
	var e := d.edge()
	var at := d.global_position + Vector3(x - e.x, 0.0, z - e.z)
	y.park(d, at.x, at.z, PI * 0.5)
	d._pour_p = Vector3.INF

## A loader's bucket full of dirt (the script's: it's dirt from nowhere, counted from here on)
func _fill(d: DsDingo) -> void:
	d.bucket = {DsMats.DIRT: d.capacity}
	d.load_n = d.capacity
	d.curl = 0.0
	d.curl_cmd = 0.0
	d._pour_acc = 0.0

## The ground's height summed over the columns behind the truck (from 0.5 m ahead of its tray's tail to 8 m behind it,
## 4 m either side), in mm; and how far behind its tail the furthest column that's over the patch's level is (m)
func _behind() -> Array:
	var tr: DsTerrain = y.ds().terrain
	var g = y.grid()
	var tk := _truck()
	var tail: Vector3 = tk.global_position + Vector3(0, 0, 3.55)
	var a := tr.cell_of(tail + Vector3(-4.0, 0, -0.5))
	var b := tr.cell_of(tail + Vector3(4.0, 0, 8.0))
	var level := (y.level_y + 1) * Yard.MM
	var sum := 0
	var far := 0.0
	for z in range(a.z, b.z):
		for x in range(a.x, b.x):
			var hh: int = (int(g.column_top(x, z)) + 1) * Yard.MM + (int(g.get_layer(x, z)) & 255)
			sum += hh
			if hh > level:
				far = maxf(far, tr.centre_of(Vector3i(x, 0, z)).z - tail.z)
	return [sum, far]

func _tick() -> void:
	var d: DsDirt = y.ds().dirt
	timer.tick(y.ds().terrain)
	if d.n > 0:
		steps.append(float(d.step_us))
	cur.awake_most = maxi(int(cur.awake_most), d.n)
	if int(t - mark) > int(cur.sec):
		cur.sec = int(t - mark)
		_mass_now()
		if debug:
			var tk := _truck()
			print("DBG %s %d s: awake %d (held %d), tray %d, dingo %d, bobcat %d, clods %d mm, step %d us" % [part, cur.sec, d.n, d.held_n, tk.load_n, _dingo().load_n, _bobcat().load_n, d.mass_mm(), d.step_us])

func _mass_now() -> void:
	var m := y.mass()
	cur.drift = maxi(int(cur.drift), absi(int(m.total) - int(cur.total)))

func _begin(p: String) -> void:
	part = p
	cur.sec = 0
	cur.total = int(y.mass().total)

func _process(dt: float) -> bool:
	t += dt
	if t > 600.0:
		check(false, "timed out at step %d" % step)
		return _done()
	var d: DsDirt = y.ds().dirt if y.ds() != null else null
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
				var tk := _truck()
				var dg := _dingo()
				var c := y.centre() + Vector3(-2.0, 0.0, -3.0)
				if k == 0:
					check(float(f[0]) >= -1.0 and float(f[1]) <= 1.0, "the patch is flat to +-1 cell (%.2f to %.2f)" % [f[0], f[1]])
					check(tk != null and dg != null and _bobcat() != null, "a tip truck, a Dingo and a Bobcat at the site")
					d.cap_us = 0            # (the same every run: the time cap is by the clock)
				for m: DsMachine in y.ds().machines.list:
					m.pour_clods = bool(runs[k])
				tk.tip = 0.0
				tk.tip_cmd = 0.0
				tk.tray_load = {}
				tk.load_n = 0
				y.park(tk, c.x, c.z, 0.0)
				dg.arm = dg.arm_high
				dg.bucket = {}
				dg.load_n = 0
				dg.curl = 0.0
				y.park(dg, c.x + 2.2, c.z + DsTruck.TRAY_AT.z, PI * 0.5)
				y.mount(dg)
				cur = {"clods": bool(runs[k]), "drift": 0, "awake_most": 0, "sec": 0, "total": 0,
					"direct0": d.direct_n, "shed0": d.shed_n, "taken0": d.taken_n}
				_next(3)
		3:
			# (a) the Dingo's lip over the tray's middle
			if t - mark > 0.5:
				var dg := _dingo()
				var tm := _tray_mid()
				_lip_to(dg, tm.x, tm.z)
				_fill(dg)
				_next(4)
		4:
			if t - mark > 0.3:
				var dg := _dingo()
				var tk := _truck()
				var e := dg.edge()
				var tm := _tray_mid()
				cur.a_off = Vector2(e.x - tm.x, e.z - tm.z).length()
				cur.a_lip = e.y - tm.y
				cur.a_over = tk.over_tray(e)
				cur.a_poured = dg.load_n
				cur.a_tray0 = tk.load_n
				cur.a_ground0 = y.grid().ground_mm()
				timer = Yard.FrameTimer.new()
				timer.start()
				steps.clear()
				_begin("a")
				dg.curl_cmd = -1.0
				_next(5)
		5:
			var dg := _dingo()
			var tk := _truck()
			_tick()
			if dg.load_n == 0 and float(cur.get("a_out", -1.0)) < 0.0:
				cur.a_out = t - mark
			if (dg.load_n == 0 and d.n == 0 and t - mark > 1.0) or t - mark > 14.0:
				dg.curl_cmd = 0.0
				_mass_now()
				cur.a_s = t - mark
				cur.a_left = dg.load_n
				cur.a_awake = d.n
				cur.a_tray = tk.load_n - int(cur.a_tray0)
				cur.a_ground = y.grid().ground_mm() - int(cur.a_ground0)
				cur.a_drift = cur.drift
				cur.drift = 0
				# (b) 2 m further back: its lip outside the tray's side
				var tm := _tray_mid()
				dg.curl = 0.0
				_next(6)
		6:
			if t - mark > 0.4:
				var dg := _dingo()
				var tm := _tray_mid()
				_lip_to(dg, tm.x + OFFSET, tm.z)
				_fill(dg)
				_next(7)
		7:
			if t - mark > 0.3:
				var dg := _dingo()
				var tk := _truck()
				var e := dg.edge()
				var tm := _tray_mid()
				cur.b_off = Vector2(e.x - tm.x, e.z - tm.z).length()
				cur.b_over = tk.over_tray(e)
				cur.b_poured = dg.load_n
				cur.b_tray0 = tk.load_n
				cur.b_ground0 = y.grid().ground_mm()
				_begin("b")
				timer._was = Time.get_ticks_usec()
				dg.curl_cmd = -1.0
				_next(8)
		8:
			var dg := _dingo()
			var tk := _truck()
			_tick()
			if (dg.load_n == 0 and d.n == 0 and t - mark > 1.0) or t - mark > 14.0:
				dg.curl_cmd = 0.0
				_mass_now()
				cur.b_s = t - mark
				cur.b_left = dg.load_n
				cur.b_awake = d.n
				cur.b_tray = tk.load_n - int(cur.b_tray0)
				cur.b_ground = y.grid().ground_mm() - int(cur.b_ground0)
				cur.b_drift = cur.drift
				cur.drift = 0
				# (c) the truck tips
				dg.curl = 0.0
				y.park(dg, dg.global_position.x + 4.0, dg.global_position.z, PI * 0.5)
				y.mount(tk)
				_next(9)
		9:
			if t - mark > 0.5:
				var tk := _truck()
				var bh := _behind()
				cur.c_load = tk.load_n
				cur.c_behind0 = bh[0]
				cur.c_ground0 = y.grid().ground_mm()
				_begin("c")
				timer._was = Time.get_ticks_usec()
				tk.tip_cmd = 1.0
				_next(10)
		10:
			var tk := _truck()
			_tick()
			if tk.load_n == 0 and float(cur.get("c_out", -1.0)) < 0.0:
				cur.c_out = t - mark
			if t - mark >= TIP_S and not cur.has("c_behind"):
				var bh := _behind()
				cur.c_behind = int(bh[0]) - int(cur.c_behind0)
				cur.c_far = bh[1]
				cur.c_ground = y.grid().ground_mm() - int(cur.c_ground0)
				cur.c_left = tk.load_n
				cur.c_awake = d.n
				cur.c_awake_mm = d.mass_mm()
			if cur.has("c_behind") and (d.n == 0 or t - mark > TIP_S + 10.0):
				_mass_now()
				cur.c_s = t - mark
				cur.c_drift = cur.drift
				cur.drift = 0
				cur.c_rest = d.n
				cur.abc_most = cur.awake_most
				var s := timer.stats()
				cur.frame = s.frame
				cur.step = Yard.FrameTimer.of(steps)
				cur.direct = d.direct_n - int(cur.direct0)
				cur.shed = d.shed_n - int(cur.shed0)
				cur.taken = d.taken_n - int(cur.taken0)
				tk.tip_cmd = -1.0
				_next(11)
		11:
			if t - mark > 3.0:
				var tk := _truck()
				tk.tip_cmd = 0.0
				d.land_all()
				if not bool(cur.clods):
					_next(14)
					return false
				# (d) the Bobcat nosed up to the truck's side, from outside it: its nose at the tray's side, its arms up
				# so its lip, tipped, clears the rim
				var bc := _bobcat()
				var tm := _tray_mid()
				bc.arm = 0.7
				bc.curl = 0.0
				bc.bucket = {}
				bc.load_n = 0
				y.park(bc, tm.x + DsTruck.TRAY.x * 0.5 + bc.length * 0.5, tm.z, PI * 0.5)
				y.mount(bc)
				_next(12)
		12:
			if t - mark > 0.6:
				var bc := _bobcat()
				var tk := _truck()
				_fill(bc)
				var e := bc.edge()
				var tm := _tray_mid()
				cur.d_in = DsTruck.TRAY.x * 0.5 - (e.x - tm.x)
				cur.d_lip = e.y - tm.y - DsTruck.TRAY.y
				cur.d_nose = (bc.global_position.x - bc.length * 0.5) - (tm.x + DsTruck.TRAY.x * 0.5)
				cur.d_poured = bc.load_n
				cur.d_tray0 = tk.load_n
				_begin("d")
				bc.curl_cmd = -1.0
				_next(13)
		13:
			var bc := _bobcat()
			var tk := _truck()
			if int(t - mark) > int(cur.sec):
				cur.sec = int(t - mark)
				_mass_now()
				if debug:
					print("DBG d %d s: awake %d (held %d), tray %d, bobcat %d, clods %d mm; lip %.2f m over the rim" % [cur.sec, d.n, d.held_n, tk.load_n, bc.load_n, d.mass_mm(), bc.edge().y - _tray_mid().y - DsTruck.TRAY.y])
			if bc.load_n > 0:
				cur.d_lip_low = minf(float(cur.get("d_lip_low", INF)), bc.edge().y - _tray_mid().y - DsTruck.TRAY.y)
			if (bc.load_n == 0 and d.n == 0 and t - mark > 1.0) or t - mark > 16.0:
				bc.curl_cmd = 0.0
				_mass_now()
				cur.d_s = t - mark
				cur.d_left = bc.load_n
				cur.d_awake = d.n
				cur.d_tray = tk.load_n - int(cur.d_tray0)
				cur.d_drift = cur.drift
				cur.drift = 0
				# (e) badly aimed: backed off so its lip's over the tray's side wall
				bc.curl = 0.0
				y.park(bc, bc.global_position.x + float(cur.d_in) - 0.2, bc.global_position.z, PI * 0.5)
				bc._pour_p = Vector3.INF
				_next(15)
		15:
			if t - mark > 0.6:
				var bc := _bobcat()
				var tk := _truck()
				_fill(bc)
				cur.e_in = DsTruck.TRAY.x * 0.5 - (bc.edge().x - _tray_mid().x)
				cur.e_poured = bc.load_n
				cur.e_tray0 = tk.load_n
				cur.e_ground0 = y.grid().ground_mm()
				_begin("e")
				bc.curl_cmd = -1.0
				_next(16)
		16:
			var bc := _bobcat()
			var tk := _truck()
			if int(t - mark) > int(cur.sec):
				cur.sec = int(t - mark)
				_mass_now()
				if debug:
					print("DBG e %d s: awake %d (held %d), tray %d, bobcat %d, clods %d mm" % [cur.sec, d.n, d.held_n, tk.load_n, bc.load_n, d.mass_mm()])
					if cur.sec > 6:
						var tm := _tray_mid()
						for i in mini(d.n, 6):
							print("DBG    clod %.2f %.2f %.2f from the tray's middle, v %.2f %.2f %.2f, age %.1f held %.1f gnd %d mm %d" % [d.px[i] - tm.x, d.py[i] - tm.y, d.pz[i] - tm.z, d.vx[i], d.vy[i], d.vz[i], d.age[i], d.hld[i], d.gnd[i], d.cmm[i]])
			if (bc.load_n == 0 and d.n == 0 and t - mark > 1.0) or t - mark > 16.0:
				bc.curl_cmd = 0.0
				_mass_now()
				cur.e_s = t - mark
				cur.e_left = bc.load_n
				cur.e_awake = d.n
				cur.e_tray = tk.load_n - int(cur.e_tray0)
				cur.e_ground = y.grid().ground_mm() - int(cur.e_ground0)
				cur.e_drift = cur.drift
				cur.drift = 0
				# (f) the tray full to its brim (the script's), tipped: the most clods a pour makes
				bc.curl = 0.0
				y.park(bc, bc.global_position.x + 5.0, bc.global_position.z, PI * 0.5)
				tk.tip = 0.0
				tk.tip_cmd = 0.0
				tk.tray_load = {DsMats.DIRT: DsTruck.CAPACITY}
				tk.load_n = DsTruck.CAPACITY
				y.mount(tk)
				_next(17)
		17:
			if t - mark > 0.5:
				var tk := _truck()
				cur.f_load = tk.load_n
				cur.f_ground0 = y.grid().ground_mm()
				cur.f_shed0 = d.shed_n
				cur.f_direct0 = d.direct_n
				cur.awake_most = 0
				_begin("f")
				timer = Yard.FrameTimer.new()
				timer.start()
				steps.clear()
				tk.tip_cmd = 1.0
				_next(18)
		18:
			var tk := _truck()
			_tick()
			if tk.load_n == 0 and float(cur.get("f_out", -1.0)) < 0.0:
				cur.f_out = t - mark
			if (tk.load_n == 0 and d.n == 0) or t - mark > 40.0:
				_mass_now()
				cur.f_s = t - mark
				cur.f_left = tk.load_n
				cur.f_awake = d.n
				cur.f_ground = y.grid().ground_mm() - int(cur.f_ground0)
				cur.f_drift = cur.drift
				cur.f_most = cur.awake_most
				cur.f_frame = timer.stats().frame
				cur.f_step = Yard.FrameTimer.of(steps)
				cur.f_shed = d.shed_n - int(cur.f_shed0)
				cur.f_direct = d.direct_n - int(cur.f_direct0)
				var top := -INF
				var tr: DsTerrain = y.ds().terrain
				for i in 80:
					for j in 17:
						top = maxf(top, tr.height_at(tk.global_position.x - 2.0 + j * 0.25, tk.global_position.z + 3.0 + i * 0.125))
				cur.f_high = top - y.level_m()
				tk.tip_cmd = -1.0
				_next(14)
		14:
			res[1 if bool(cur.clods) else 0] = cur
			k += 1
			if k < runs.size():
				y.level()
				_next(2)
			else:
				return _report()
	return false

func _pc(a, b) -> float:
	return 100.0 * float(a) / maxf(float(b), 1.0)

func _line(r: Dictionary, name: String) -> void:
	say("%s: (a) lip %.2f m off the tray's middle, %.2f m over its floor: %d mm poured in %.2f s, the tray %+d (%.1f%%), the ground %+d; at rest %.2f s on (%d awake, %d in the bucket)" % [
		name, r.a_off, r.a_lip, r.a_poured, r.get("a_out", -1.0), r.a_tray, _pc(r.a_tray, r.a_poured), r.a_ground, r.a_s, r.a_awake, r.a_left])
	say("%s: (b) lip %.2f m off the tray's middle: %d mm poured, the tray %+d, the ground %+d; at rest %.2f s on (%d awake, %d in the bucket)" % [
		name, r.b_off, r.b_poured, r.b_tray, r.b_ground, r.b_s, r.b_awake, r.b_left])
	say("%s: (c) the tray's %d mm tipped: empty %.2f s on; at %.0f s the ground behind it %+d mm (%.1f%%), the ground in all %+d, %d mm still in the tray, %d clods awake (%d mm); the heap out to %.1f m behind its tail; all at rest %.2f s on (%d awake)" % [
		name, r.c_load, r.get("c_out", -1.0), TIP_S, r.c_behind, _pc(r.c_behind, r.c_load), r.c_ground, r.c_left, r.c_awake, r.c_awake_mm, r.c_far, r.c_s, r.c_rest])
	say("%s: frames %d, mean %.2f, p95 %.2f, worst %.2f ms; clods awake at the most %d; the clods' step mean %.0f us, p95 %.0f, worst %.0f over %d frames with any; %d taken into loads, %d laid straight down, %d put down by the caps" % [
		name, r.frame.n, r.frame.mean, r.frame.p95, r.frame.worst, r.abc_most, r.step.mean, r.step.p95, r.step.worst, r.step.n, r.taken, r.direct, r.shed])

func _report() -> bool:
	var a: Dictionary = res.get(0, {})
	var b: Dictionary = res.get(1, {})
	say("the order: %s" % ("the clods first, then the baseline" if order == "ba" else "the baseline first, then the clods"))
	_line(a, "baseline (no clods)")
	_line(b, "with clods")
	check(float(b.a_off) < 0.1 and bool(b.a_over), "(a) the Dingo's lip is over the tray's middle (%.2f m off it)" % b.a_off)
	check(int(b.a_left) == 0 and int(b.a_awake) == 0, "(a) the bucket pours empty and the clods come to rest (%.2f s)" % b.a_s)
	check(int(b.a_tray) >= int(0.85 * int(b.a_poured)), "(a) the tray's load gains >= 85%% of the poured mm (%d of %d: %.1f%%)" % [b.a_tray, b.a_poured, _pc(b.a_tray, b.a_poured)])
	check(int(b.a_tray) + int(b.a_ground) == int(b.a_poured), "(a) the rest is on the ground (%d mm; tray + ground = %d of %d)" % [b.a_ground, int(b.a_tray) + int(b.a_ground), b.a_poured])
	check(absf(float(b.b_off) - OFFSET) < 0.1 and not bool(b.b_over), "(b) the lip %.2f m off the tray's middle, outside its side" % b.b_off)
	check(int(b.b_tray) == 0 and int(b.b_left) == 0 and int(b.b_awake) == 0, "(b) poured there, the tray gains 0 (%d mm; the ground %+d of %d poured)" % [b.b_tray, b.b_ground, b.b_poured])
	check(int(b.c_load) > 0 and int(b.c_behind) >= int(0.95 * int(b.c_load)), "(c) tipped, >= 95%% of the tray's load is on the ground behind the truck within %.0f s (%d of %d: %.1f%%)" % [TIP_S, b.c_behind, b.c_load, _pc(b.c_behind, b.c_load)])
	check(int(b.c_rest) == 0, "(c) and the clods come to rest (%.2f s from the tip's start)" % b.c_s)
	check(int(b.a_drift) == 0 and int(b.b_drift) == 0 and int(b.c_drift) == 0, "not a mm made or lost in (a), (b) or (c), at any second or at the end (%d, %d, %d mm)" % [b.a_drift, b.b_drift, b.c_drift])
	check(int(a.a_drift) == 0 and int(a.b_drift) == 0 and int(a.c_drift) == 0 and int(a.abc_most) == 0, "nor in the baseline, which makes no clods (%d, %d, %d mm; %d clods)" % [a.a_drift, a.b_drift, a.c_drift, a.abc_most])
	check(int(b.abc_most) <= DsDirt.FLY_MAX and int(b.shed) == 0, "never more awake than FLY_MAX (%d of %d), none put down by the caps" % [b.abc_most, DsDirt.FLY_MAX])
	check(float(b.step.mean) <= 2000.0, "the clods' step <= 2.0 ms on average (%.0f us with any awake; p95 %.0f)" % [b.step.mean, b.step.p95])
	check(float(b.frame.p95) <= float(a.frame.p95) + 3.0, "frame p95 <= the baseline's + 3.0 ms (%.2f against %.2f: %+.2f; means %.2f against %.2f: %+.2f)" % [
		b.frame.p95, a.frame.p95, float(b.frame.p95) - float(a.frame.p95), b.frame.mean, a.frame.mean, float(b.frame.mean) - float(a.frame.mean)])
	say("with clods: (d) the Bobcat's nose %.2f m from the tray's side, its lip %.2f m inside it and %.2f m over its rim (%.2f at the lowest while it poured): %d mm poured, the tray %+d (%.1f%%); at rest %.2f s on (%d awake, %d in the bucket)" % [
		b.d_nose, b.d_in, b.d_lip, b.get("d_lip_low", 0.0), b.d_poured, b.d_tray, _pc(b.d_tray, b.d_poured), b.d_s, b.d_awake, b.d_left])
	check(float(b.d_nose) >= -0.01 and float(b.get("d_lip_low", -1.0)) > 0.0, "(d) the Bobcat stands outside the tray, its lip over the rim all the pour (%.2f m at the lowest)" % b.get("d_lip_low", -1.0))
	check(int(b.d_left) == 0 and int(b.d_awake) == 0 and int(b.d_tray) >= int(0.85 * int(b.d_poured)), "(d) over the rim, the tray gains >= 85%% of what the Bobcat pours (%d of %d: %.1f%%)" % [b.d_tray, b.d_poured, _pc(b.d_tray, b.d_poured)])
	check(int(b.d_drift) == 0, "(d) not a mm made or lost (%d mm)" % b.d_drift)
	check(int(b.e_tray) > 0 and int(b.e_ground) > 0 and int(b.e_left) == 0 and int(b.e_awake) == 0 and int(b.e_drift) == 0, "(e) its lip over the tray's side wall as it tips (%.2f m inside its outer face, level): some in the tray, some over the side (%d mm in, %.1f%%; %d on the ground; of %d; %d mm drift; at rest %.2f s on)" % [
		b.e_in, b.e_tray, _pc(b.e_tray, b.e_poured), b.e_ground, b.e_poured, b.e_drift, b.e_s])
	say("with clods: (f) a full tray (%d mm) tipped: empty %.2f s on, all at rest %.2f s on (%d awake, %d mm in the tray); the ground %+d; clods awake at the most %d, %d laid straight down, %d put down by the caps; the heap behind it %.2f m high; frames %d, mean %.2f, p95 %.2f, worst %.2f ms; the clods' step mean %.0f us, p95 %.0f, worst %.0f" % [
		b.f_load, b.get("f_out", -1.0), b.f_s, b.f_awake, b.f_left, b.f_ground, b.f_most, b.f_direct, b.f_shed, b.f_high, b.f_frame.n, b.f_frame.mean, b.f_frame.p95, b.f_frame.worst, b.f_step.mean, b.f_step.p95, b.f_step.worst])
	check(int(b.f_left) == 0 and int(b.f_awake) == 0 and int(b.f_ground) == int(b.f_load) and int(b.f_drift) == 0, "(f) a full tray tips out, all of it on the ground, not a mm made or lost (%d of %d mm; %d mm drift at the most)" % [b.f_ground, b.f_load, b.f_drift])
	check(int(b.f_most) <= DsDirt.FLY_MAX and float(b.f_step.mean) <= 2000.0, "(f) never more awake than FLY_MAX (%d of %d), the clods' step <= 2.0 ms on average (%.0f us; p95 %.0f)" % [b.f_most, DsDirt.FLY_MAX, b.f_step.mean, b.f_step.p95])
	return _done()
