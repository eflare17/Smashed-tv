extends SceneTree
## The Dingo's self-test (stage 6; headless: --fixed-fps 60 -s test/voxel/digsite_dingo_test.gd -- --nosave). Alone: E
## near it gets you on; it drives; its bucket low, it bites the ground into the bucket and tipped it pours it out in a
## pile, not a block made or lost; it won't climb out of a pit with straight sides; E gets you off beside it. With
## --host=CODE / --join=CODE (two copies, the host first): the guest gets on (the host says yes), drives it and the
## host's game moves it, gets off; the host drives it and digs, and the guest sees the hole. Owned by the voxel session.

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
		print("DSDINGO ok   ", role, " ", what)
	else:
		failed += 1
		print("DSDINGO FAIL ", role, " ", what)

func _done() -> bool:
	print("DSDINGO done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _ds() -> DigSite:
	return arena.digsite

func _dingo() -> DsDingo:
	return _ds().machines.list[0] as DsDingo

func _total(g: DigSiteGrid) -> int:
	return g.count_box(0, 0, 0, 512, 192, 512, -1)

func _beside() -> void:
	var d := _dingo()
	var at := d.global_position - d.right() * 1.6
	_ds()._put(Vector3(at.x, d.ground_y(at.x, at.z) + 0.05, at.z), 0.0, 0.0)

func _process(dt: float) -> bool:
	t += dt
	if t > 150.0:
		check(false, "timed out at step %d" % step)
		return _done()
	return _solo() if role == "" else _coop()

func _solo() -> bool:
	var ds := _ds()
	match step:
		0:
			if t > 1.5:
				arena.phone.travel("digsite")
				_next(1)
		1:
			if ds.active and not arena.phone._going and t - mark > 1.0:
				check(ds.machines.list.size() >= 1 and ds.machines.list[0] is DsDingo, "a Dingo parked at the site")
				_beside()
				_next(2)
		2:
			if t - mark > 0.3:
				check(ds.machines.near == _dingo() and ds.machines.line().begins_with("E  drive the Dingo"), "beside it: '%s'" % ds.machines.line())
				ds.machines.use()
				check(ds.machines.driving == _dingo() and ds.driving(), "E: on it, driving")
				var d := _dingo()
				d.auto = true
				v.at = d.global_position
				d.throttle = 1.0
				_next(3)
		3:
			var d := _dingo()
			if t - mark > 2.0:
				d.throttle = 0.0
				var moved := Vector2(d.global_position.x - v.at.x, d.global_position.z - v.at.z).length()
				check(moved > 1.5, "it drives (%.1f m)" % moved)
				check(arena.player.global_position.distance_to(d.seat_world()) < 0.2, "the driver rides on it")
				d.lift_cmd = -1.0           # (the arms right down, the bucket level)
				_next(4)
		4:
			var d := _dingo()
			if t - mark > 2.0:
				d.lift_cmd = 0.0
				d.curl = 0.0                     # (the bucket's floor level)
				v.total = _total(ds.terrain.grid)
				v.e0 = d.edge()
				check(d.arm <= d.arm_low + 0.01 and d.ground_y(d.edge().x, d.edge().z) - d.edge().y < DsDingo.DIG_MOST + 0.05 and d.edge().y < d.ground_y(d.edge().x, d.edge().z), "arms down: the bucket's edge in the ground (%.2f under)" % (d.ground_y(d.edge().x, d.edge().z) - d.edge().y))
				d.throttle = 0.6
				_next(5)
		5:
			var d := _dingo()
			if t - mark > 3.0 or d.load_n >= DsDingo.CAPACITY:
				d.throttle = 0.0
				var tot := _total(ds.terrain.grid)
				check(d.load_n > 30, "driving in, the bucket fills (%d blocks)" % d.load_n)
				check(tot + d.load_n == int(v.total), "every block out of the ground is in the bucket (%d + %d = %d)" % [tot, d.load_n, v.total])
				v.loose0 = ds.terrain.grid.count_box(0, 0, 0, 512, 192, 512, -3)
				v.n = d.load_n
				d.lift_cmd = 1.0
				_next(6)
		6:
			var d := _dingo()
			if t - mark > 1.0:
				d.lift_cmd = 0.0
				d.curl_cmd = -1.0
				_next(7)
		7:
			var d := _dingo()
			if d.load_n == 0 or t - mark > 4.0:
				d.curl_cmd = 0.0
				var loose: int = ds.terrain.grid.count_box(0, 0, 0, 512, 192, 512, -3) - int(v.loose0)
				check(d.load_n == 0 and loose >= int(v.n), "tipped: it all pours out, loose (%d loose now, %d poured)" % [loose, v.n])
				check(_total(ds.terrain.grid) == int(v.total), "not a block made or lost")
				_next(8)
		8:
			if t - mark > 3.0:
				var g := ds.terrain.grid
				var c := ds.terrain.cell_of(_dingo().global_position + Vector3(0, -0.05, 0))
				var p := ds.terrain.cell_of(Vector3(c.x, c.y, c.z))
				var _u := p
				check(ds.terrain.settle_moves > 0, "the pile slumps (%d moves)" % ds.terrain.settle_moves)
				# a pit with straight sides round it: down in, it can't climb out
				ds.terrain.paused = true        # (its dirt walls would cave in under it: right, but not what's tested)
				var d := _dingo()
				var at := d.global_position
				for x in range(-3, 4):
					for z in range(-3, 4):
						var p2 := at + Vector3(x * 0.5, 0, z * 0.5)
						for k in 5:
							ds.terrain.dig(Vector3(p2.x, at.y - 0.3 - k * 0.35, p2.z), 0.5, 9)
				var _g := g
				_next(9)
		9:
			var d := _dingo()
			if t - mark > 1.5:
				v.y = d.global_position.y
				v.p = d.global_position
				d.throttle = 1.0
				_next(10)
		10:
			var d := _dingo()
			if t - mark > 3.0:
				d.throttle = 0.0
				check(d.global_position.y < float(v.y) + 0.3, "down in a pit, it can't climb its straight side (rose %.2f m: '%s')" % [d.global_position.y - float(v.y), d.blocked])
				ds.machines.use()
				check(ds.machines.driving == null and not ds.driving() and d.driver == 0, "E again: off it")
				check(arena.player.global_position.distance_to(d.global_position) < 2.5, "stood beside it")
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
				if role == "host":
					arena.phone.travel("digsite")
				_next(2)
		2:
			var ok: bool = ds.active and not arena.phone._going and (role == "host" or ds.net.synced)
			if (ok and t - mark > 1.0) or t - mark > 30.0:
				check(ok, "at the Dig Site")
				v.at = _dingo().global_position
				if role == "guest":
					_beside()
				_next(3)
		3:
			if t - mark > 0.5:
				if role == "guest":
					ds.machines.use()
				_next(4)
		4:
			var d := _dingo()
			if (d.driver == 2 and t - mark > 0.5) or t - mark > 10.0:
				check(d.driver == 2, "the guest's on the Dingo (the host said yes)")
				if role == "guest":
					check(ds.machines.driving == d, "the guest drives it")
					d.auto = true
					d.throttle = 1.0
				_next(5)
		5:
			var d := _dingo()
			if t - mark > 4.5:
				d.throttle = 0.0
				var moved := Vector2(d.global_position.x - v.at.x, d.global_position.z - v.at.z).length()
				check(moved > 1.5, "it's moved (%.1f m in the %s's game)" % [moved, role])
				if role == "guest":
					ds.machines.use()
				_next(6)
		6:
			var d := _dingo()
			if (d.driver == 0 and t - mark > 0.5) or t - mark > 10.0:
				check(d.driver == 0 and (role == "host" or ds.machines.driving == null), "the guest's off it")
				if role == "host":
					_beside()
					ds.machines.use()
					d.auto = true
					d.lift_cmd = -1.0
				_next(7)
		7:
			var d := _dingo()
			if t - mark > 2.5:
				if role == "host":
					d.lift_cmd = 0.0
					d.curl = 0.0
					d.throttle = 0.6
				v.ground = _total(ds.terrain.grid)
				_next(8)
		8:
			var d := _dingo()
			if t - mark > 3.0:
				d.throttle = 0.0
				if role == "host":
					check(d.load_n > 30, "the host digs with it (%d blocks in the bucket)" % d.load_n)
				_next(9)
		9:
			if t - mark > 2.0:
				var d := _dingo()
				check(d.load_n > 30, "%s: the bucket's load shown (%d)" % [role, d.load_n])
				if role == "guest":
					check(_total(ds.terrain.grid) < int(v.ground) - 30 or ds.net.last_match, "the guest sees the hole it dug")
				_next(10)
		10:
			if t - mark > 2.0:
				return _done()
	return false
