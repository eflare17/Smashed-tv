extends SceneTree
## Machine weight (integration/dirt_physics_plan.md, stage 4; headless:
##   /root/godot/godot --headless --path godot --fixed-fps 60 -s res://test/voxel/digsite_feel_test.gd -- --nosave
## ). The bulldozer in the yard, driven by script, and how it moves measured from where it IS each frame (its place a
## frame ago to its place now), not only from what it says its speed is:
## (a) on the flat, blade up, full throttle 6 s: its top speed within 10% of stage 1's (3.2 m/s); then let go: it rolls
##     to a stop;
## (b) standing, turned hard one way, then hard the other, then let go: its turning never changes by more than
##     turn_rate * dt * 6 from one frame to the next, and it does get up to its turning rate;
## (c) full throttle into a 1.5 m bank the test builds: it gets over 2 m/s, and from the last frame over 2 m/s to the
##     first under 0.3 m/s is more than 0.3 s; no frame loses more than 25% of its top speed; stalled against the bank
##     its tracks slip (over 0.5); its body's nose dips and comes back, 1.5 to 5 degrees at the most;
## (e) (before the bank) let go from a metre up it lands with a thud: its body goes down on its springs and comes back;
## (f) (after it) the Bobcat, its bucket up, flat out at the same bank: no frame loses more than 25% of its top speed
##     either (the hard stop every machine had at a bank), and it ends up at the bank, its wheels spinning;
## (d) the yard test's 20 s push (blade 0.1 m in the ground, straight across the levelled patch): at least 80% of the
##     baseline's metres, the frame's p95 no more than 0.5 ms over the baseline's.
## Not a mm of dirt made or lost in any of it. The baseline (stage 3's game, the same test run on it the same hour:
## --write-base, with --out= where to leave it) is read from integration/dirt_shots/feel_base.txt: "p95 metres top".
## Writes integration/dirt_shots/feel.txt. On a game without the weight (no slip, no sway) it runs and fails (c): that's
## the "before". Owned by the voxel session.

const Yard := preload("res://test/voxel/digsite_yard.gd")
const STAGE1_TOP := 3.2         # m/s: the bulldozer's top speed in stage 1 (its max_speed, reached: checked on stage 3's game)
const BANK := 12                # cells: 1.5 m
const BANK_Z := -5.0            # the bank's face, from the patch's middle (the dozer comes at it from +z) ...
const BANK_DEEP := 6.0          # ... and how far back it goes
const BANK_HALF := 7.0          # ... and to each side

var y := Yard.new()
var timer := Yard.FrameTimer.new()
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var out := "res://integration/dirt_shots"
var base_path := ""
var write_base := false
var debug := false
var lines := PackedStringArray()
var v := {}
var was := Vector3.INF
var yaw_was := 0.0
var rate_was := 0.0
# what's kept each frame of a run: its real speed along its nose (m/s), the speed it says, its slip, its body's sway
# (rad), its ground pitch (rad)
var real := PackedFloat32Array()
var said := PackedFloat32Array()
var slip := PackedFloat32Array()
var sway := PackedFloat32Array()
var pit := PackedFloat32Array()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--base="):
			base_path = a.trim_prefix("--base=")
		elif a == "--write-base":
			write_base = true
		elif a == "--debug":
			debug = true
	y.boot(self)

func say(s: String) -> void:
	lines.append("DSFEEL " + s)
	print("DSFEEL ", s)

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
	var f := FileAccess.open(dir.path_join("feel_base_run.txt" if write_base else "feel.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _num(m: Object, what: String) -> float:
	var x = m.get(what)
	return float(x) if x != null else NAN

## A frame of a run kept: how far it really went along its nose since the last, and what it says of itself
func _keep(dz: DsDozer, dt: float) -> void:
	var p := dz.global_position
	if was != Vector3.INF:
		var d := p - was
		real.append(Vector3(d.x, 0, d.z).dot(dz.forward()) / dt)
		said.append(dz.speed)
		slip.append(_num(dz, "slip"))
		sway.append(_num(dz, "sway"))
		pit.append(dz.pitch)
	was = p

func _fresh() -> void:
	was = Vector3.INF
	real.clear()
	said.clear()
	slip.clear()
	sway.clear()
	pit.clear()

## The most a frame lost of a's speed (from one frame to the next, toward standing)
static func _drop(a: PackedFloat32Array) -> float:
	var most := 0.0
	for i in range(1, a.size()):
		most = maxf(most, absf(a[i - 1]) - absf(a[i]))
	return most

func _mass_same(m0: Dictionary, what: String) -> void:
	var m1 := y.mass()
	check(int(m1.total) == int(m0.total), "%s: not a mm made or lost (%d mm drift; ground %d, loads %d, clods %d)" % [what, int(m1.total) - int(m0.total), m1.ground, m1.loads + m1.falling, m1.clods])

## The bank: firm dirt BANK cells over the patch's level, its face across the dozer's way. To rest after.
func _build_bank() -> void:
	var g = y.grid()
	var tr: DsTerrain = y.ds().terrain
	var c := y.centre()
	var a := tr.cell_of(c + Vector3(-BANK_HALF, 0, BANK_Z - BANK_DEEP))
	var b := tr.cell_of(c + Vector3(BANK_HALF, 0, BANK_Z))
	for z in range(a.z, b.z):
		for x in range(a.x, b.x):
			for yy in range(y.level_y + 1, y.level_y + 1 + BANK):
				g.set_cell(x, yy, z, DsMats.DIRT)
			g.set_layer(x, z, 0, 0)
	var n := 0
	while n < 600 and (g.awake_count() > 0 or g.layer_awake() > 0):
		g.layer_step(1000000)
		if n % 3 == 0:
			g.settle(1000000)
		n += 1
	v.bank_rest = n

## How high the bank's face stands over the patch (m): just in from its face, in the dozer's way
func _bank_high() -> float:
	var tr: DsTerrain = y.ds().terrain
	var c := y.centre()
	var lo := INF
	for i in 9:
		lo = minf(lo, tr.height_at(c.x - 2.0 + i * 0.5, c.z + BANK_Z - 0.4))
	return lo - y.level_m()

func _process(dt: float) -> bool:
	t += dt
	if t > 200.0:
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
				check(float(f[0]) >= -1.0 and float(f[1]) <= 1.0, "the patch is flat to +-1 cell (%.2f to %.2f)" % [f[0], f[1]])
				var dz := y.park_dozer()
				y.mount(dz)
				check(y.ds().machines.driving == dz, "on the bulldozer (id %d): top speed %.1f m/s, turns %.2f rad/s" % [dz.id, dz.max_speed, dz.turn_rate])
				v.mass0 = y.mass()
				_fresh()
				_next(3)
		3:
			# (a) the flat, blade up: 6 s flat out, then let go
			var dz := y.dozer()
			var going := t - mark < 6.0
			y.drive_dozer(dz, 1.0 if going else 0.0, DsDozer.START_LIFT)
			_keep(dz, dt)
			if going:
				v.a_n = real.size()
			if t - mark >= 9.0:
				var top := 0.0
				var t90 := -1.0
				var n: int = v.a_n
				for i in n:
					top = maxf(top, real[i])
				for i in n:
					if real[i] >= 0.9 * top:
						t90 = i * dt
						break
				var stop_t := -1.0
				var roll := 0.0
				for i in range(n, real.size()):
					roll += real[i] * dt
					if absf(real[i]) < 0.05 and stop_t < 0.0:
						stop_t = (i - n) * dt
				v.top = top
				say("(a) flat out on the flat, blade up: top speed %.2f m/s (it says %.2f), 90%% of it in %.2f s; let go, it stands in %.2f s, %.2f m on; the most a frame lost: %.3f m/s" % [top, dz.max_speed, t90, stop_t, roll, _drop(real)])
				check(absf(top - STAGE1_TOP) <= 0.1 * STAGE1_TOP, "(a) top speed within 10%% of stage 1's %.1f m/s (%.2f)" % [STAGE1_TOP, top])
				check(stop_t > 0.0, "(a) let go, it comes to a stand (%.2f s)" % stop_t)
				_mass_same(v.mass0, "(a)")
				y.park_dozer()
				dz.throttle = 0.0
				yaw_was = dz.yaw
				rate_was = 0.0
				v.jerk = 0.0
				v.rate_most = 0.0
				v.rate_end = 0.0
				_next(4)
		4:
			# (b) standing: hard right 1.5 s, hard left 1.5 s, let go 1 s
			var dz := y.dozer()
			var k := t - mark
			dz.throttle = 0.0
			dz.lift_cmd = 0.0
			dz.steer = 1.0 if k < 1.5 else (-1.0 if k < 3.0 else 0.0)
			var rate := wrapf(dz.yaw - yaw_was, -PI, PI) / dt
			yaw_was = dz.yaw
			if k > 2.0 * dt:
				v.jerk = maxf(float(v.jerk), absf(rate - rate_was))
			rate_was = rate
			v.rate_most = maxf(float(v.rate_most), absf(rate))
			if k >= 4.0:
				v.rate_end = absf(rate)
				var lim: float = dz.turn_rate * dt * 6.0
				say("(b) standing, hard over one way, then the other, then let go: turning %.3f rad/s at the most (its rate: %.2f), %.3f rad/s a second after letting go; the most its turning changed in a frame: %.4f rad/s (limit %.4f)" % [v.rate_most, dz.turn_rate, v.rate_end, v.jerk, lim])
				check(float(v.jerk) <= lim, "(b) its turning changes by no more than turn_rate * dt * 6 a frame (%.4f <= %.4f rad/s)" % [v.jerk, lim])
				check(float(v.rate_most) >= 0.9 * dz.turn_rate and float(v.rate_end) < 0.05 * dz.turn_rate, "(b) it gets up to its turning rate and stops turning (%.3f of %.2f; %.3f after)" % [v.rate_most, dz.turn_rate, v.rate_end])
				dz.steer = 0.0
				# (e) let go from a metre up
				y.park_dozer()
				dz.global_position.y += 1.0
				v.bob_lo = 0.0
				v.land_at = -1.0
				v.fell = dz.global_position.y
				_next(40)
		40:
			var dz := y.dozer()
			dz.throttle = 0.0
			var bob := _num(dz, "bob")
			v.bob_lo = minf(float(v.bob_lo), bob)
			if float(v.land_at) < 0.0 and dz.global_position.y < float(v.fell) - 0.98:
				v.land_at = t - mark
			if t - mark >= 2.5:
				say("(e) let go from 1 m up: down in %.2f s; its body goes down %.1f cm on its springs, and is %.1f cm off 1.5 s and more after" % [v.land_at, -100.0 * float(v.bob_lo), 100.0 * absf(bob)])
				check(float(v.land_at) > 0.0 and float(v.bob_lo) <= -0.02 and float(v.bob_lo) >= -0.1 and absf(bob) < 0.005, "(e) it lands with a thud: its body 2 to 10 cm down on its springs, and back (%.1f cm, then %.1f)" % [-100.0 * float(v.bob_lo), 100.0 * absf(bob)])
				_build_bank()
				_next(5)
		5:
			if t - mark > 1.0:
				var high := _bank_high()
				check(high > 1.4 and high < 1.6, "(c) the bank stands: %.2f m over the patch at its face (at rest in %d ticks)" % [high, v.bank_rest])
				var dz := y.park_dozer()
				v.mass_c = y.mass()
				v.face = y.centre().z + BANK_Z
				v.gap = dz.global_position.z - DsDozer.EDGE_X - float(v.face)
				_fresh()
				v.stall_at = -1
				v.blocked = {}
				_next(6)
		6:
			# (c) into the bank, flat out, the blade as it's carried
			var dz := y.dozer()
			y.drive_dozer(dz, 1.0, DsDozer.START_LIFT)
			_keep(dz, dt)
			if dz.blocked != "":
				v.blocked[dz.blocked] = int(v.blocked.get(dz.blocked, 0)) + 1
			var n := real.size()
			if debug and n > 0 and dz.global_position.z - DsDozer.EDGE_X - float(v.face) < 1.5:
				print("DBG %3d z %.2f v %.2f said %.2f r %.2f slip %.2f tv %.2f full %.2f bank %.2f jam %.2f load %.0f cut %.0f sway %.2f gap %.2f '%s'" % [n, dz.global_position.z - DsDozer.EDGE_X - float(v.face), real[n - 1], dz.speed, _num(dz, "resist"), _num(dz, "slip"), _num(dz, "track_v"), _num(dz, "full"), _num(dz, "bank"), _num(dz, "_jam_r"), dz.push_load, dz.cut_rate, rad_to_deg(_num(dz, "sway")), _num(dz, "_wall_gap"), dz.blocked])
			if int(v.stall_at) < 0 and n > 60 and real[n - 1] < 0.3:
				var fast := false
				for i in n:
					fast = fast or real[i] > 2.0
				if fast:
					v.stall_at = n - 1
			if (int(v.stall_at) >= 0 and n - int(v.stall_at) > 150) or t - mark > 14.0:
				_bank_report(dz, dt)
				dz.throttle = 0.0
				# (f) the Bobcat, its bucket up over the bank, at the bank beside where the dozer bit
				var bc: DsMachine = y.machine("Bobcat")
				y.park(bc, y.centre().x - 5.0, y.centre().z + 3.0, 0.0)
				bc.set("arm", bc.get("arm_high"))
				y.mount(bc)
				_fresh()
				v.stall_at = -1
				v.blocked = {}
				_next(60)
		60:
			var bc: DsMachine = y.machine("Bobcat")
			bc.throttle = 1.0
			bc.steer = 0.0
			var p := bc.global_position
			if was != Vector3.INF:
				real.append(Vector3(p.x - was.x, 0, p.z - was.z).dot(bc.forward()) / dt)
				said.append(bc.speed)
				slip.append(_num(bc, "slip"))
			was = p
			if bc.blocked != "":
				v.blocked[bc.blocked] = int(v.blocked.get(bc.blocked, 0)) + 1
			var n := real.size()
			if int(v.stall_at) < 0 and n > 60 and real[n - 1] < 0.1:
				v.stall_at = n - 1
			if (int(v.stall_at) >= 0 and n - int(v.stall_at) > 90) or t - mark > 10.0:
				var top := 0.0
				for i in n:
					top = maxf(top, real[i])
				var at: int = maxi(int(v.stall_at), 0)
				var hi := 0
				for i in at:
					if real[i] > 2.0:
						hi = i
				var s_lo := INF
				for i in range(at + 30, n):
					s_lo = minf(s_lo, slip[i])
				var why := ""
				for k in v.blocked:
					why += "'%s' %d frames; " % [k, v.blocked[k]]
				var off: float = p.z - bc.length * 0.5 - float(v.face)
				say("(f) the Bobcat, bucket up, flat out at the bank: top %.2f m/s (its: %.1f); from the last frame over 2 m/s to standing: %.2f s; the most a frame lost: %.3f m/s as it moved, %.3f as it says (limit %.2f); it stands %.2f m off the bank's face, slip %.2f at the least; %s" % [
					top, bc.max_speed, (at - hi) * dt, _drop(real), _drop(said), 0.25 * bc.max_speed, off, s_lo, why if why != "" else "no stops said"])
				check(int(v.stall_at) >= 0 and top > 2.0 and _drop(real) <= 0.25 * bc.max_speed and _drop(said) <= 0.25 * bc.max_speed, "(f) a bank stops the Bobcat without a frame losing more than 25%% of its top speed (%.3f, %.3f; limit %.2f)" % [_drop(real), _drop(said), 0.25 * bc.max_speed])
				check(off > -0.05 and off < 0.6 and s_lo > 0.5, "(f) it's stopped at the bank, not short of it or in it (%.2f m off), its wheels spinning (%.2f)" % [off, s_lo])
				bc.throttle = 0.0
				_mass_same(v.mass_c, "(f)")
				y.mount(y.dozer())
				y.level()
				_next(7)
		7:
			if t - mark > 1.0:
				var f := y.flatness()
				check(float(f[0]) >= -1.0 and float(f[1]) <= 1.0, "(d) the patch levelled again: flat to +-1 cell (%.2f to %.2f)" % [f[0], f[1]])
				var dz := y.park_dozer()
				v.mass_d = y.mass()
				v.at = dz.global_position
				_next(8)
		8:
			if t - mark >= 2.0:
				timer.start()
				_fresh()
				v.sec = 0
				v.drift = 0
				v.blocked = {}
				_next(9)
		9:
			# (d) the yard's push: 20 s, blade 0.1 m in the ground
			var dz := y.dozer()
			timer.tick(y.ds().terrain)
			y.drive_dozer(dz, 1.0, -0.1)
			_keep(dz, dt)
			if dz.blocked != "":
				v.blocked[dz.blocked] = int(v.blocked.get(dz.blocked, 0)) + 1
			if debug and real.size() % 30 == 1:
				print("DBGD %.1f s z %.2f v %.2f r %.2f slip %.2f full %.2f bank %.2f jam %.2f load %.0f cut %.0f sway %.2f '%s'" % [t - mark, dz.global_position.z, real[real.size() - 1], _num(dz, "resist"), _num(dz, "slip"), _num(dz, "full"), _num(dz, "bank"), _num(dz, "_jam_r"), dz.push_load, dz.cut_rate, rad_to_deg(_num(dz, "sway")), dz.blocked])
			if int(t - mark) > int(v.sec):
				v.sec = int(t - mark)
				v.drift = maxi(int(v.drift), absi(int(y.mass().total) - int((v.mass_d as Dictionary).total)))
			if t - mark >= 20.0:
				dz.throttle = 0.0
				return _push_report(dz)
	return false

func _bank_report(dz: DsDozer, dt: float) -> void:
	var n := real.size()
	var at: int = v.stall_at
	var top := 0.0
	for i in n:
		top = maxf(top, real[i])
	var why := ""
	for k in v.blocked:
		why += "'%s' %d frames; " % [k, v.blocked[k]]
	if at < 0:
		check(false, "(c) it never got over 2 m/s and then under 0.3 m/s (top %.2f, at the end %.2f; %s)" % [top, real[n - 1], why])
		return
	var hi := 0
	for i in at:
		if real[i] > 2.0:
			hi = i
	var span := (at - hi) * dt
	var went := 0.0
	for i in range(hi, at):
		went += real[i] * dt
	var drop_real := _drop(real)
	var drop_said := _drop(said)
	# stalled: from half a second after it stopped to the end (the throttle still full on)
	var s_lo := INF
	var s_sum := 0.0
	var s_n := 0
	var v_most := 0.0
	for i in range(at + 30, n):
		s_lo = minf(s_lo, slip[i])
		s_sum += slip[i]
		s_n += 1
		v_most = maxf(v_most, absf(real[i]))
	var sw_most := 0.0
	var sw_at := 0
	var sw_end := 0.0
	var pit_most := 0.0
	for i in n:
		if absf(sway[i]) > sw_most:
			sw_most = absf(sway[i])
			sw_at = i
		pit_most = maxf(pit_most, absf(pit[i]))
	sw_end = sway[n - 1]
	var edge_in: float = float(v.face) - dz.edge().z       # (how far its blade's edge is past the bank's face)
	say("(c) into the bank flat out (%.1f m off, blade %.2f m up): top %.2f m/s; the last frame over 2 m/s to the first under 0.3 m/s: %.2f s, %.2f m; the most a frame lost: %.3f m/s as it moved, %.3f m/s as it says (limit %.2f)" % [
		v.gap, DsDozer.START_LIFT, top, span, went, drop_real, drop_said, 0.25 * STAGE1_TOP])
	say("(c) stalled (%.1f s, throttle full on): slip %.2f at the least, %.2f mean; creeping %.2f m/s at the most; its blade's edge %.2f m into the bank's face; nose %.2f deg at the most (%.2f s %s it stopped), %.2f deg at the end; the ground under it pitched it %.2f deg at the most; %s" % [
		s_n * dt, s_lo, s_sum / maxi(s_n, 1), v_most, edge_in, rad_to_deg(sw_most), absf(sw_at - at) * dt, "before" if sw_at < at else "after", rad_to_deg(sw_end), rad_to_deg(pit_most), why if why != "" else "no stops said"])
	v.c_span = span
	check(top > 2.0 and span > 0.3, "(c) from over 2 m/s to under 0.3 m/s takes more than 0.3 s (%.2f s)" % span)
	check(drop_real <= 0.25 * STAGE1_TOP and drop_said <= 0.25 * STAGE1_TOP, "(c) no frame loses more than 25%% of its top speed (%.3f m/s moved, %.3f said; limit %.2f)" % [drop_real, drop_said, 0.25 * STAGE1_TOP])
	check(s_n > 0 and s_lo > 0.5, "(c) its tracks slip while it's stalled (%.2f at the least, over 0.5)" % s_lo)
	var deg := rad_to_deg(sw_most)
	check(deg >= 1.5 and deg <= 5.0, "(c) its nose dips 1.5 to 5 degrees at the most (%.2f)" % deg)
	_mass_same(v.mass_c, "(c)")

func _push_report(dz: DsDozer) -> bool:
	var s := timer.stats()
	var metres: float = dz.global_position.distance_to(v.at)
	var heap := y.heap_ahead(dz)
	var lo := INF
	var sl := 0.0
	for i in real.size():
		if i > 60:
			lo = minf(lo, real[i])
		sl += slip[i]
	var why := ""
	for k in v.blocked:
		why += "'%s' %d frames; " % [k, v.blocked[k]]
	say("(d) the yard's push, 20 s, blade 0.10 m in: %.2f m; slowest %.2f m/s, at the end %.2f m/s; mean slip %.2f; the most a frame lost %.3f m/s; heap ahead %.2f m, %.0f blocks banked; stops: %s" % [
		metres, lo, dz.speed, sl / maxi(real.size(), 1), _drop(real), heap, dz.push_load, why if why != "" else "none"])
	say("(d) frames %d, mean %.2f, p95 %.2f, worst %.2f ms; layer_us mean %.0f, p95 %.0f; show_us mean %.0f, p95 %.0f" % [s.frame.n, s.frame.mean, s.frame.p95, s.frame.worst, s.layer.mean, s.layer.p95, s.show.mean, s.show.p95])
	check(int(v.drift) == 0, "(d) not a mm made or lost at any second of it (%d mm at the most)" % v.drift)
	_mass_same(v.mass_d, "(d)")
	var dir := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	if write_base:
		var f := FileAccess.open(dir.path_join("feel_base.txt"), FileAccess.WRITE)
		f.store_string("%.3f %.3f %.3f" % [s.frame.p95, metres, v.top])
		f.close()
		say("(the baseline written: p95 %.2f ms, %.2f m, top %.2f m/s)" % [s.frame.p95, metres, v.top])
		return _done()
	var b := FileAccess.get_file_as_string(base_path if base_path != "" else dir.path_join("feel_base.txt")).split(" ")
	if b.size() < 3:
		check(false, "(d) no baseline to read (run the test on stage 3's game with --write-base)")
		return _done()
	var b_p95 := float(b[0])
	var b_m := float(b[1])
	say("(d) the baseline (stage 3's game, this test): p95 %.2f ms, %.2f m, top %.2f m/s" % [b_p95, b_m, float(b[2])])
	check(metres >= 0.8 * b_m, "(d) the 20 s push moves >= 80%% of the baseline's metres (%.2f of %.2f: %.0f%%)" % [metres, b_m, 100.0 * metres / b_m])
	check(float(s.frame.p95) <= b_p95 + 0.5, "(d) frame p95 <= the baseline's + 0.5 ms (%.2f against %.2f: %+.2f)" % [s.frame.p95, b_p95, float(s.frame.p95) - b_p95])
	return _done()
