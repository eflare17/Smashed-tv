extends SceneTree
## Clods in the real Dig Site (integration/dirt_physics_plan.md, stage 3; headless:
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_clod_site_test.gd -- --nosave
## ). In the yard (digsite_yard.gd: a levelled 24 x 24 m patch), the site's own DsDirt, stepped by the site:
## (a) 500 clods poured over 5 s in front of a box the size of the dozer's blade driven across the patch by the script
##     (2 m/s for 6 s): no clod's middle is ever inside the box, none ends inside it, and they go 3 m or more on
##     average from where they were let go to where they settle;
## (b) 300 dropped into the parked tip truck's tray: 95% or more are lying in it 5 s later, none got through its floor;
## (c) 100 let go inside a tunnel dug under the patch: once they've settled the ground over the tunnel has gained 0 mm
##     (their dirt's back in the tunnel, or owed), and not a mm is made or lost;
## (d) land_all() leaves no clods and nothing owed.
## Budgets, over every frame of (a) to (c) with clods awake: DsDirt.step_us (its drawing in it) mean <= 2.0 ms, p95 <=
## 4.0 ms; the whole frame's p95 <= the baseline's + 3.0 ms. The baseline is taken back to back in the same run, and
## is the same dirt arriving with no clods: after (d) the run is played again frame for frame, every clod's dirt laid
## straight on the ground (or put in the tunnel) where and when its clod settled, so the ground's own work (its slump,
## its sections redrawn: most of a frame's cost when dirt lands) is in both and the difference is what the clods cost.
## (The frame with nothing happening at all, 3 s before (a), and stage 1's dozing p95 are printed beside it.) The
## time cap is off (cap_us 0: with it on a loaded box turns clods away, and the run isn't the same twice); step_us is
## then what the clods truly cost. The mass (Yard.mass(), the clods in it) is checked every second and at each part's
## end: what was there and what the test has made, to the mm. --out=dir writes clod_site.txt there.
## Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
const BOX_HALF := Vector3(2.2, 0.92, 0.26)     # (the dozer's blade: DsDozer.keepout_boxes)
const BOX_V := 2.0
const POUR_N := 500
const POUR_S := 5.0
const DRIVE_S := 6.0
const TRAY_N := 300
const TUNNEL_N := 100
const TUNNEL_AT := Vector3(7.0, -0.9, -9.0)    # the tunnel's start from the patch's middle (its axis 0.9 m under the patch), going +z
const TUNNEL_LONG := 5.0
const TUNNEL_R := 0.5

var y := Yard.new()
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var out := ""
var lines: PackedStringArray = []
var v := {}
var base_mm := 0                # everything there was once the yard's made ...
var made_mm := 0                # ... and what the test's let go since
var mass_bad := 0
var mass_checks := 0
var mass_in := 1.0
var skip := true                # (this frame's time isn't a frame's: the mass was added up in it)
var _was := 0
var idle := PackedFloat32Array()
var busy := PackedFloat32Array()
var replay := PackedFloat32Array()
var events: Array = []          # every clod settling in (a) to (c): [the frame, x, y, z, how]
var frame_n := 0
var replay_f := 0
var replay_k := 0
var steps := PackedFloat32Array()
var draws := PackedFloat32Array()
var awake_most := 0
var born := {}                  # a clod's id -> where it was let go
var box_z := 0.0
var box_on := false
var box_xf := Transform3D.IDENTITY
var inside_frames := 0
var ended_inside := 0
var travel_sum := 0.0
var travel_n := 0
var travel_least := INF
var travel_most := 0.0
var poured := 0
var pour_acc := 0.0
var not_clods := 0
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	rng.seed = 7
	y.boot(self)

func say(s: String) -> void:
	print("DSCLODSITE ", s)
	lines.append(s)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	say(("ok   " if ok else "FAIL ") + what)

func _done() -> bool:
	say("done %d passed, %d failed" % [passed, failed])
	if out != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
		var f := FileAccess.open(out.path_join("clod_site.txt"), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(lines) + "\n")
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func dirt() -> DsDirt:
	return y.ds().dirt

# everything there is against what there was and what's been made since
func _mass(what: String, loud := false) -> void:
	var m := y.mass()
	var off: int = int(m.total) - base_mm - made_mm
	mass_checks += 1
	if off != 0:
		mass_bad += 1
		say("mass off by %d mm %s" % [off, what])
	elif loud:
		say("mass exact %s (ground %d, clods and owed %d)" % [what, m.ground, m.clods])
	skip = true

# a clod let go (500 mm of dirt), remembered if the test wants to know where it ends
func _let_go(p: Vector3, vel: Vector3, keep: bool) -> void:
	made_mm += DsDirt.CLOD
	if dirt().spawn(p, vel, DsMats.DIRT, DsDirt.CLOD):
		if keep:
			born[dirt().last_id] = p
	else:
		not_clods += 1

func _in_box(p: Vector3, grow: float) -> bool:
	var l := box_xf.affine_inverse() * p
	return absf(l.x) < BOX_HALF.x + grow and absf(l.y) < BOX_HALF.y + grow and absf(l.z) < BOX_HALF.z + grow

# the ground over the tunnel: every column's height in mm (its top block and the loose layer on it), added up; and each
func _over_tunnel() -> PackedInt32Array:
	var tr: DsTerrain = y.ds().terrain
	var a := tr.cell_of(y.centre() + TUNNEL_AT + Vector3(-1.5, 0, -1.0))
	var b := tr.cell_of(y.centre() + TUNNEL_AT + Vector3(1.5, 0, TUNNEL_LONG + 1.0))
	var cols := PackedInt32Array()
	for z in range(a.z, b.z + 1):
		for x in range(a.x, b.x + 1):
			cols.append((int(tr.grid.column_top(x, z)) + 1) * 125 + (int(tr.grid.get_layer(x, z)) & 255))
	return cols

func _stats(a: PackedFloat32Array) -> Dictionary:
	return Yard.FrameTimer.of(a)

func _process(dt: float) -> bool:
	t += dt
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _was) / 1000.0
	_was = now
	if t > 200.0:
		check(false, "timed out at step %d" % step)
		return _done()
	var d := y.ds()
	if step == 10:
		if not skip:
			replay.append(frame_ms)
		skip = false
	if step >= 3 and step <= 9:
		# the frame just gone: its time, the clods' step in it
		var dz: DsDirt = d.dirt
		if step == 3:
			if not skip:
				idle.append(frame_ms)
		elif dz.awake() > 0 or dz.step_us > 0:
			if not skip:
				busy.append(frame_ms)
			steps.append(float(dz.step_us))
			draws.append(float(dz.draw_us))
			awake_most = maxi(awake_most, dz.awake())
		skip = false
		# where clods settled last frame; and none's middle in the box (as it was for that step)
		if box_on:
			for i in dz.n:
				if _in_box(Vector3(dz.px[i], dz.py[i], dz.pz[i]), -0.02):
					inside_frames += 1
					break
		var lg := dz.settle_log
		var k := 0
		while k + 4 < lg.size():
			var id := int(lg[k])
			var p := Vector3(lg[k + 1], lg[k + 2], lg[k + 3])
			if step <= 7:
				events.append([frame_n, p.x, p.y, p.z, int(lg[k + 4])])
			if born.has(id):
				var from: Vector3 = born[id]
				var went := Vector2(p.x - from.x, p.z - from.z).length()
				travel_sum += went
				travel_n += 1
				travel_least = minf(travel_least, went)
				travel_most = maxf(travel_most, went)
				if box_on and _in_box(p, 0.0):
					ended_inside += 1
				born.erase(id)
			elif v.has("tray_ids") and v.tray_ids.has(id):
				v.tray_settled.append(p)
				v.tray_ids.erase(id)
			k += 5
		lg.clear()
		dz.settle_log = lg
		if step >= 4 and step <= 7:
			frame_n += 1
		mass_in -= dt
		if mass_in <= 0.0:
			mass_in = 1.0
			_mass("at %.1f s (step %d)" % [t, step])
	match step:
		0:
			if t > 1.5:
				y.travel()
				_next(1)
		1:
			if y.arrived() and t - mark > 1.0:
				var lv := y.level()
				d.terrain.build_now(2000.0)
				# the truck on the patch; the tunnel dug under it, well clear of both and of the box's way
				var truck := y.machine("tip truck")
				var c := y.centre()
				y.park(truck, c.x - 7.0, c.z + 1.0, 0.0)
				var z := 0.0
				var dug := 0
				while z <= TUNNEL_LONG:
					dug += int(d.terrain.dig(Vector3(c.x + TUNNEL_AT.x, y.level_m() + TUNNEL_AT.y, c.z + TUNNEL_AT.z + z), TUNNEL_R, 9).n)
					z += 0.125
				v.dug = dug
				d._put(Vector3(c.x + 9.0, y.level_m() + 0.05, c.z + 11.0), 0.6, -0.25)
				say("yard: level %d, %d blocks lowered, %d raised; the tunnel %d blocks dug (1 m across, %.1f m long, its roof %.2f m thick)" % [
					lv.level, lv.lowered, lv.raised, dug, TUNNEL_LONG + 2.0 * TUNNEL_R, -TUNNEL_AT.y - TUNNEL_R])
				_next(2)
		2:
			# the ground come to rest (the tunnel stands), everything drawn
			var g = y.grid()
			if t - mark > 2.0 and ((g.awake_count() == 0 and g.layer_awake() == 0) or t - mark > 12.0):
				d.terrain.build_now(2000.0)
				var fl := y.flatness()
				v.over0 = _over_tunnel()
				var m := y.mass()
				base_mm = int(m.total)
				d.dirt.log_on = true
				d.dirt.cap_us = 0
				check(d.dirt != null and d.dirt.awake() == 0 and g.awake_count() == 0, "the site has its DsDirt, no clods yet; the ground's at rest (patch %.2f to %.2f cells off level away from the tunnel's dig)" % [fl[0], fl[1]])
				skip = true
				_next(3)
		3:
			# three seconds of the scene as it is: what a frame costs with no clods
			if t - mark > 3.0:
				var s := _stats(idle)
				say("frame, no clods: %d frames, mean %.2f, p95 %.2f, worst %.2f ms" % [s.n, s.mean, s.p95, s.worst])
				v.idle = s
				box_z = y.centre().z + 8.0
				box_on = true
				_box()
				_next(4)
		4:
			# (a) the box driven across, clods poured in front of it
			var el := t - mark
			if el < DRIVE_S:
				box_z -= BOX_V * dt
			_box()
			if el < POUR_S + dt:
				pour_acc += POUR_N / (POUR_S * 60.0)
				while pour_acc >= 1.0 and poured < POUR_N:
					pour_acc -= 1.0
					poured += 1
					var c := y.centre()
					_let_go(Vector3(c.x + rng.randf_range(-1.9, 1.9), y.level_m() + rng.randf_range(0.5, 1.3), box_z - BOX_HALF.z - rng.randf_range(0.3, 1.3)),
						Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)), true)
			if poured >= POUR_N and d.dirt.awake() == 0 and el > DRIVE_S:
				v.a_secs = el
				var mean := travel_sum / maxf(1.0, float(travel_n))
				say("(a) %d let go in %.1f s in front of the box (%.1f x %.2f x %.2f m, %.1f m/s for %.0f s: %.1f m); %d became clods; the last settled at %.2f s; %d box hits; %d awake at most" % [
					poured, POUR_S, BOX_HALF.x * 2.0, BOX_HALF.y * 2.0, BOX_HALF.z * 2.0, BOX_V, DRIVE_S, BOX_V * DRIVE_S, poured - not_clods, el, d.dirt.hits_n, awake_most])
				check(not_clods == 0 and travel_n == POUR_N, "(a) all %d were clods and all settled (%d not clods, %d settled)" % [POUR_N, not_clods, travel_n])
				check(inside_frames == 0 and ended_inside == 0, "(a) none inside the box: %d frames with a clod's middle in it, %d settled in it" % [inside_frames, ended_inside])
				check(mean >= 3.0, "(a) mean travel %.2f m (>= 3.0; least %.2f, most %.2f)" % [mean, travel_least, travel_most])
				_mass("after (a)", true)
				box_on = false
				d.extra_boxes = []
				v.hits_a = d.dirt.hits_n
				_next(5)
			elif el > 25.0:
				check(false, "(a) %d clods still awake 25 s on" % d.dirt.awake())
				box_on = false
				d.extra_boxes = []
				_next(5)
		5:
			# (b) into the truck's tray
			var truck := y.machine("tip truck") as DsTruck
			if not v.has("tray_ids"):
				v.tray_ids = {}
				v.tray_settled = []
				v.tray_let = 0
				not_clods = 0
			if v.tray_let < TRAY_N:
				for i in 10:
					var l := DsTruck.TRAY_AT + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(1.5, 2.5), rng.randf_range(-1.9, 1.9))
					made_mm += DsDirt.CLOD
					if d.dirt.spawn(truck.global_transform * l, Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3)), DsMats.DIRT, DsDirt.CLOD):
						v.tray_ids[d.dirt.last_id] = true
					else:
						not_clods += 1
				v.tray_let += 10
				mark = t
			elif t - mark > 5.0:
				var inv := truck.global_transform.affine_inverse()
				var dz: DsDirt = d.dirt
				var inside := 0
				var under := 0
				var beside := 0
				var fastest := 0.0
				var pts: Array = []
				for i in dz.n:
					if v.tray_ids.has(dz.cid[i]):
						pts.append([Vector3(dz.px[i], dz.py[i], dz.pz[i]), Vector3(dz.vx[i], dz.vy[i], dz.vz[i]).length()])
				for p: Vector3 in v.tray_settled:
					pts.append([p, 0.0])
				for e: Array in pts:
					var l: Vector3 = inv * (e[0] as Vector3)
					var over := absf(l.x - DsTruck.TRAY_AT.x) < DsTruck.TRAY.x * 0.5 and absf(l.z - DsTruck.TRAY_AT.z) < DsTruck.TRAY.z * 0.5
					if over and l.y >= DsTruck.TRAY_AT.y and l.y < DsTruck.TRAY_AT.y + DsTruck.TRAY.y + 0.3:
						inside += 1
						fastest = maxf(fastest, float(e[1]))
					elif over or (absf(l.x) < truck.width * 0.5 and absf(l.z) < truck.length * 0.5 and l.y < DsTruck.TRAY_AT.y):
						under += 1
					else:
						beside += 1
				say("(b) %d dropped from 1.5 to 2.5 m over the tray's floor; 5 s on: %d lying in it (the fastest going %.2f m/s), %d beside the truck, %d under the tray's floor or in the truck; %d not clods; %d settled into the ground" % [
					TRAY_N, inside, fastest, beside, under, not_clods, v.tray_settled.size()])
				check(not_clods == 0 and pts.size() == TRAY_N, "(b) all %d were clods and all are accounted for (%d)" % [TRAY_N, pts.size()])
				check(inside * 100 >= TRAY_N * 95, "(b) %d of %d rest in the tray (%.1f%%, >= 95%%), none faster than 0.3 m/s (%.2f)" % [inside, TRAY_N, 100.0 * inside / TRAY_N, fastest])
				check(under == 0, "(b) %d through the tray's floor (0)" % under)
				if fastest >= 0.3:
					check(false, "(b) a clod in the tray is still going %.2f m/s" % fastest)
				_mass("after (b)", true)
				v.tray_awake = dz.awake()
				v.buried0 = dz.buried_n
				v.over1 = _over_tunnel()
				_next(6)
		6:
			# (c) in the tunnel
			if not v.has("tun_let"):
				v.tun_let = 0
				not_clods = 0
				var same := true
				for i in v.over0.size():
					if v.over0[i] != v.over1[i]:
						same = false
				say("(c) the ground over the tunnel before: %s since the yard was made" % ("unchanged" if same else "CHANGED"))
			if v.tun_let < TUNNEL_N:
				var c := y.centre()
				for i in 10:
					made_mm += DsDirt.CLOD
					var p := Vector3(c.x + TUNNEL_AT.x + rng.randf_range(-0.2, 0.2), y.level_m() + TUNNEL_AT.y + rng.randf_range(-0.1, 0.25),
						c.z + TUNNEL_AT.z + rng.randf_range(0.3, TUNNEL_LONG - 0.3))
					if not d.dirt.spawn(p, Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-1.5, 1.5)), DsMats.DIRT, DsDirt.CLOD):
						not_clods += 1
				v.tun_let += 10
				mark = t
			elif d.dirt.awake() <= v.tray_awake and t - mark > 1.0:
				v.c_secs = t - mark
				_next(7)
			elif t - mark > 15.0:
				check(false, "(c) %d of the tunnel's clods still awake 15 s on" % (d.dirt.awake() - int(v.tray_awake)))
				_next(7)
		7:
			# (the loose blocks they became come to rest in the tunnel)
			var g = y.grid()
			if t - mark > 1.0 and (g.awake_count() == 0 or t - mark > 8.0):
				var over := _over_tunnel()
				var gained := 0
				var changed := 0
				for i in over.size():
					gained += over[i] - int(v.over1[i])
					if over[i] != v.over1[i]:
						changed += 1
				var dz: DsDirt = d.dirt
				var buried: int = dz.buried_n - int(v.buried0)
				var c := y.centre()
				var tr: DsTerrain = d.terrain
				var a := tr.cell_of(Vector3(c.x + TUNNEL_AT.x - 1.0, y.level_m() + TUNNEL_AT.y - 1.0, c.z + TUNNEL_AT.z - 1.0))
				var b := tr.cell_of(Vector3(c.x + TUNNEL_AT.x + 1.0, y.level_m() - 0.3, c.z + TUNNEL_AT.z + TUNNEL_LONG + 1.0))
				var loose: int = tr.grid.count_box(a.x, a.y, a.z, b.x, b.y, b.z, -3)
				say("(c) %d let go in the tunnel; all settled %.2f s after the last; %d put back under the roof (%d loose blocks in the tunnel now, of %d they made); owed %d mm" % [
					TUNNEL_N, v.c_secs, buried, loose, TUNNEL_N * DsDirt.CLOD / 125, dz.owed_mm()])
				check(not_clods == 0 and buried == TUNNEL_N, "(c) all %d were clods and settled under the roof (%d not clods, %d buried)" % [TUNNEL_N, not_clods, buried])
				check(gained == 0 and changed == 0, "(c) the ground over the tunnel gained %d mm (0), %d of its %d columns changed" % [gained, changed, over.size()])
				check(loose * 125 + dz.owed_mm() == TUNNEL_N * DsDirt.CLOD, "(c) their dirt's in the tunnel: %d mm as loose blocks + %d owed = %d let go" % [loose * 125, dz.owed_mm(), TUNNEL_N * DsDirt.CLOD])
				_mass("after (c)", true)
				v.owed = dz.owed_mm()
				_next(8)
		8:
			_next(9)
		9:
			# (d) everything put down
			var dz: DsDirt = d.dirt
			var before := dz.awake()
			var over := _over_tunnel()
			dz.land_all()
			var after := _over_tunnel()
			var up := 0
			for i in over.size():
				up += after[i] - over[i]
			check(dz.awake() == 0 and dz.mass_mm() == 0 and dz.owed_mm() == 0, "(d) land_all(): %d clods before, %d after, %d mm in clods, %d mm owed" % [before, dz.awake(), dz.mass_mm(), dz.owed_mm()])
			say("(d) what was owed (%d mm) is on the ground now: the columns over the tunnel rose %d mm in all" % [v.owed, up])
			_mass("after land_all()", true)
			skip = true
			_next(10)
		10:
			# the baseline: the same frames again with no clods, each clod's dirt put straight where it settled, when it did
			if replay_f < frame_n:
				var g = y.grid()
				var tr: DsTerrain = d.terrain
				while replay_k < events.size() and int(events[replay_k][0]) <= replay_f:
					var e: Array = events[replay_k]
					made_mm += DsDirt.CLOD
					if int(e[4]) == 1:
						var c: Vector3 = tr.to_cells(Vector3(e[1], e[2], e[3]))
						var put: int = g.fill_sphere(c, pow(4.0, 1.0 / 3.0) + 1.5, DsMats.DIRT, 4, true)
						if put < 4:
							g.put_layer(int(c.x), int(c.z), (4 - put) * 125, DsMats.DIRT)
					else:
						d.dirt._lay(e[1], e[3], DsDirt.CLOD, DsMats.DIRT)
					replay_k += 1
				replay_f += 1
				mass_in -= dt
				if mass_in <= 0.0:
					mass_in = 1.0
					_mass("at %.1f s (the baseline)" % t)
				return false
			var s := _stats(steps)
			var dr := _stats(draws)
			var f := _stats(busy)
			var b := _stats(replay)
			var idle_s: Dictionary = v.idle
			say("step_us with clods awake: %d steps, mean %.0f, p95 %.0f, worst %.0f us (its drawing: mean %.0f, p95 %.0f us); %d awake at most" % [s.n, s.mean, s.p95, s.worst, dr.mean, dr.p95, awake_most])
			say("frame with clods awake: %d frames, mean %.2f, p95 %.2f, worst %.2f ms" % [f.n, f.mean, f.p95, f.worst])
			say("frame, the baseline (the same %d clods' dirt laid where and when each settled, no clods): %d frames, mean %.2f, p95 %.2f, worst %.2f ms" % [events.size(), b.n, b.mean, b.p95, b.worst])
			say("frame, nothing happening: mean %.2f, p95 %.2f ms; stage 1's dozing p95 was 21.85 ms (baseline.txt): against either, clods awake are %+.2f and %+.2f ms" % [idle_s.mean, idle_s.p95, f.p95 - idle_s.p95, f.p95 - 21.85])
			check(s.mean <= 2000.0 and s.p95 <= 4000.0, "step_us mean %.0f (<= 2000), p95 %.0f (<= 4000)" % [s.mean, s.p95])
			check(f.p95 <= b.p95 + 3.0, "frame p95 %.2f ms <= the baseline's %.2f + 3.0 = %.2f" % [f.p95, b.p95, b.p95 + 3.0])
			_mass("after the baseline", true)
			check(mass_bad == 0, "mass exact at all %d checks (every second, and after each part)" % mass_checks)
			return _done()
	return false

func _box() -> void:
	var c := y.centre()
	box_xf = Transform3D(Basis.IDENTITY, Vector3(c.x, y.level_m() + BOX_HALF.y + 0.02, box_z))
	y.ds().extra_boxes = [[box_xf, BOX_HALF, DsDirt.K_BLADE]]
