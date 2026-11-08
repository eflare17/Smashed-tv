extends SceneTree
## The Bobcat, the excavator and the tip truck (stage 10; headless: --fixed-fps 60 -s test/voxel/digsite_fleet_test.gd
## -- --nosave). Alone: four machines parked; the Bobcat's bucket fills; the excavator digs below its tracks and pours
## into the truck's tray; the truck only turns rolling, drives, tips its load out behind (not a block made or lost);
## parked by the office it's loaded with concrete supports, and one's taken off its back. With --host=CODE /
## --join=CODE: the guest digs with the excavator (the host's game runs it), and takes a support off the truck. Owned
## by the voxel session.

var arena: Node
var role := ""
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host="):
			role = "host"
		elif a.begins_with("--join="):
			role = "guest"
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DSFLEET ok   ", role, " ", what)
	else:
		failed += 1
		print("DSFLEET FAIL ", role, " ", what)

func _done() -> bool:
	print("DSFLEET done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _ds() -> DigSite:
	return arena.digsite

func _m(i: int) -> DsMachine:
	return _ds().machines.by_id(i)

func _ground() -> int:
	return _ds().terrain.grid.count_box(0, 0, 0, 512, 192, 512, -1)

func _on(m: DsMachine) -> void:
	var ds := _ds()
	if ds.machines.driving:
		ds.machines.get_off()
	var at := m.global_position - m.right() * (m.width * 0.5 + 0.8)
	ds._put(Vector3(at.x, m.ground_y(at.x, at.z) + 0.05, at.z), 0.0, 0.0)
	ds.machines._process(0.0)
	ds.machines.use()
	m.auto = true

func _process(dt: float) -> bool:
	t += dt
	if t > 160.0:
		check(false, "timed out at step %d" % step)
		return _done()
	return _solo() if role == "" else _coop()

func _solo() -> bool:
	var ds := _ds()
	match step:
		0:
			if t > 1.5:
				arena.godmode = true
				arena.phone.travel("digsite")
				_next(1)
		1:
			if ds.active and not arena.phone._going and t - mark > 1.0:
				check(ds.machines.list.size() == 4 and _m(2) is DsBobcat and _m(3) is DsExcavator and _m(4) is DsTruck, "four machines parked: the Dingo, a Bobcat, an excavator, a tip truck")
				var b := _m(2) as DsBobcat
				_on(b)
				check(ds.machines.driving == b, "on the Bobcat")
				b.lift_cmd = -1.0
				_next(2)
		2:
			var b := _m(2) as DsBobcat
			if t - mark > 2.5:
				b.lift_cmd = 0.0
				b.curl = 0.0
				b.throttle = 0.6
				_next(3)
		3:
			var b := _m(2) as DsBobcat
			if t - mark > 3.0:
				b.throttle = 0.0
				check(b.load_n > 60, "the Bobcat's bucket fills (%d of %d)" % [b.load_n, b.capacity])
				var x := _m(3) as DsExcavator
				_on(x)
				x.raise_cmd = -1.0
				_next(4)
		4:
			var x := _m(3) as DsExcavator
			if t - mark > 3.0:
				x.raise_cmd = 0.0
				var e := x.edge()
				v.e_under = ds.terrain.top_at(e.x, e.z) - e.y
				check(float(v.e_under) > 0.2, "the excavator's bucket down in the ground (%.2f m under)" % v.e_under)
				x.curl = 1.8
				x.curl_cmd = 1.0
				x.reach_cmd = -0.6
				_next(5)
		5:
			var x := _m(3) as DsExcavator
			if t - mark > 1.4:
				x.curl_cmd = 0.0
				x.reach_cmd = 0.0
				check(x.load_n > 40, "curling in, it digs (%d blocks)" % x.load_n)
				check(x.edge().y < x.global_position.y, "below its own tracks")
				x.raise_cmd = 1.0
				_next(6)
		6:
			var x := _m(3) as DsExcavator
			if t - mark > 4.0:
				x.raise_cmd = 0.0
				# the truck backed up under its bucket
				var tk := _m(4) as DsTruck
				var e := x.pour_point()
				var off := tk.global_transform.basis * DsTruck.TRAY_AT
				tk.global_position = Vector3(e.x - off.x, tk.ground_y(e.x - off.x, e.z - off.z), e.z - off.z)
				tk._pose_now()
				check(tk.over_tray(e), "the truck's tray under the excavator's bucket")
				v.total = _ground() + x.load_n + (_m(2) as DsBobcat).load_n
				v.x_load = x.load_n
				x.curl_cmd = -1.0
				_next(7)
		7:
			var x := _m(3) as DsExcavator
			var tk := _m(4) as DsTruck
			if x.load_n == 0 or t - mark > 4.0:
				x.curl_cmd = 0.0
				check(x.load_n == 0 and tk.load_n == int(v.x_load), "opened, it pours into the truck (%d in the tray)" % tk.load_n)
				_on(tk)
				v.yaw = tk.yaw
				tk.steer = 1.0
				_next(8)
		8:
			var tk := _m(4) as DsTruck
			if t - mark > 1.0:
				check(absf(tk.yaw - float(v.yaw)) < 0.01, "standing still, the truck doesn't turn (steered wheels)")
				tk.steer = 0.0
				# (out of the excavator's hole onto open ground first)
				var o := DigSite.AT + Vector3(-4.0, 0.0, 8.0)
				tk.global_position = Vector3(o.x, tk.ground_y(o.x, o.z), o.z)
				v.at = tk.global_position
				tk.throttle = 1.0
				_next(9)
		9:
			var tk := _m(4) as DsTruck
			if t - mark > 2.5:
				tk.throttle = 0.0
				check(tk.global_position.distance_to(v.at) > 3.0, "it drives (%.1f m%s)" % [tk.global_position.distance_to(v.at), ("; " + tk.blocked) if tk.blocked != "" else ""])
				tk.tip_cmd = 1.0
				_next(10)
		10:
			var tk := _m(4) as DsTruck
			if tk.load_n == 0 or t - mark > 8.0:
				tk.tip_cmd = -1.0
				var now := _ground() + (_m(3) as DsExcavator).load_n + (_m(2) as DsBobcat).load_n + tk.load_n
				check(tk.load_n == 0, "R tips it: the load pours out behind")
				check(now == int(v.total), "not a block made or lost (%d, %d)" % [now, v.total])
				_next(11)
		11:
			var tk := _m(4) as DsTruck
			if t - mark > 2.5:
				tk.tip_cmd = 0.0
				# parked by the office: supports on
				var w: Vector3 = DigSite.AT + DigSite.OFFICE_WINDOW + Vector3(4.0, 0, -2.0)
				tk.global_position = Vector3(w.x, tk.ground_y(w.x, w.z), w.z)
				arena.cash = 100
				check(ds.machines.key(KEY_L) and tk.props == DsTruck.PROPS_MOST and arena.cash == 100 - DsTruck.PROPS_MOST * DsTruck.PROP_COST, "by the office, L loads %d concrete supports" % tk.props)
				ds.machines.get_off()
				var b := tk.spout()
				ds._put(Vector3(b.x, tk.ground_y(b.x, b.z) + 0.05, b.z), 0.0, 0.0)
				var had: int = arena.inv.count("prop_concrete")
				check(ds.machines.line().begins_with("G  take a concrete support"), "at its back: '%s'" % ds.machines.line())
				check(ds.machines.key(KEY_G) and arena.inv.count("prop_concrete") == had + 1 and tk.props == DsTruck.PROPS_MOST - 1, "G takes one off")
				return _done()
	return false

func _coop() -> bool:
	var n = arena.net
	var ds := _ds()
	match step:
		0:
			if n != null and n.linked and (role == "host" or n._got_world) and t > 2.0:
				_next(1)
		1:
			if t - mark > 1.0:
				arena.godmode = true
				if role == "host":
					arena.phone.travel("digsite")
				_next(2)
		2:
			var ok: bool = ds.active and not arena.phone._going and (role == "host" or ds.net.synced)
			if (ok and t - mark > 2.0) or t - mark > 30.0:
				check(ok, "at the Dig Site")
				if role == "guest":
					_on(_m(3))
				else:
					(_m(4) as DsTruck).props = 5
				_next(3)
		3:
			var x := _m(3) as DsExcavator
			if (x.driver == 2 and t - mark > 0.5) or t - mark > 10.0:
				check(x.driver == 2, "the guest's in the excavator")
				if role == "guest":
					x.raise_cmd = -1.0
				_next(4)
		4:
			var x := _m(3) as DsExcavator
			if t - mark > 3.5:
				if role == "guest":
					x.raise_cmd = 0.0
					x.reach_cmd = -0.6
					x.curl_cmd = 1.0
				_next(5)
		5:
			var x := _m(3) as DsExcavator
			if t - mark > 2.5:
				if role == "guest":
					x.curl_cmd = 0.0
					x.reach_cmd = 0.0
				_next(6)
		6:
			var x := _m(3) as DsExcavator
			if (x.load_n > 20 and t - mark > 1.0) or t - mark > 6.0:
				check(x.load_n > 20, "%s: the guest dug with it (%d in its bucket)" % [role, x.load_n])
				if role == "guest":
					ds.machines.get_off()
					var tk := _m(4) as DsTruck
					var b := tk.spout()
					ds._put(Vector3(b.x, tk.ground_y(b.x, b.z) + 0.05, b.z), 0.0, 0.0)
					v.had = arena.inv.count("prop_concrete")
				_next(7)
		7:
			if t - mark > 1.5:
				if role == "guest":
					check(ds.machines.key(KEY_G), "the guest asks for a support off the truck")
				_next(8)
		8:
			var tk := _m(4) as DsTruck
			var done: bool = tk.props == 4 and (role == "host" or arena.inv.count("prop_concrete") == int(v.had) + 1)
			if (done and t - mark > 1.0) or t - mark > 10.0:
				check(tk.props == 4, "%s: one off the truck (%d left)" % [role, tk.props])
				if role == "guest":
					check(arena.inv.count("prop_concrete") == int(v.had) + 1, "it's in the guest's backpack")
				_next(9)
		9:
			if t - mark > 2.0:
				return _done()
	return false
