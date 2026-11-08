extends SceneTree
## Tunnels and cave-ins in the game (stage 7; headless: --fixed-fps 60 -s test/voxel/digsite_tunnel_test.gd --
## --nosave). Alone: dug sideways into the ground, a 1 m tunnel you can stand in (the hard hat's lamp comes on) holds;
## a 4 m room dug out round you creaks, dust trickles, then its roof comes down on you (you're hurt) as loose dirt.
## With --host=CODE / --join=CODE: the host digs the room; both games hear it creak and see it fall, and the grounds
## match after. Owned by the voxel session.

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
		print("DSTUNNEL ok   ", role, " ", what)
	else:
		failed += 1
		print("DSTUNNEL FAIL ", role, " ", what)

func _done() -> bool:
	print("DSTUNNEL done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _ds() -> DigSite:
	return arena.digsite

# a box dug out (metres from the site's middle: its floor's corner, size), as the tools would (through DsNet)
func _dig_box(at: Vector3, size: Vector3) -> void:
	var ds := _ds()
	var y := 0.06
	while y < size.y:
		var z := 0.06
		while z < size.z:
			var x := 0.06
			while x < size.x:
				ds.tools.dig_at(DigSite.AT + at + Vector3(x, y, z), 0.11, 9)
				x += 0.125
			z += 0.125
		y += 0.125

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
				arena.godmode = false
				arena.phone.travel("digsite")
				_next(1)
		1:
			if ds.active and not arena.phone._going and t - mark > 1.0:
				# a tunnel 1 m wide, 2 m tall, its floor 3 m down (its roof 1 m under the ground), 6 m long
				var top := ds.terrain.top_at(DigSite.AT.x + 10.0, DigSite.AT.z - 10.0)
				v.floor = top - DigSite.AT.y - 3.0
				_dig_box(Vector3(10.0, v.floor, -10.0), Vector3(1.0, 2.0, 6.0))
				ds.terrain.build_now(500.0)
				ds._put(DigSite.AT + Vector3(10.5, v.floor + 0.05, -7.0), 0.0, 0.0)
				_next(2)
		2:
			if t - mark > 3.0:
				var p: Vector3 = arena.player.global_position
				check(absf(p.y - (DigSite.AT.y + v.floor)) < 0.3, "standing in the tunnel (feet %.2f, its floor %.2f)" % [p.y, DigSite.AT.y + v.floor])
				check(ds.lamp.visible, "the hard hat's lamp's on under the ground")
				check(ds.caves.falls == 0, "a 1 m tunnel holds (%d warnings)" % ds.caves.warnings)
				# a 4 m room dug out round you, 2 m tall, its roof 1 m down
				v.hp = arena.player_hp
				_dig_box(Vector3(8.5, v.floor, -9.0), Vector3(4.0, 2.0, 4.0))
				ds._put(DigSite.AT + Vector3(10.5, v.floor + 0.05, -7.0), 0.0, 0.0)
				_next(3)
		3:
			if ds.caves.falls > 0 or t - mark > 15.0:
				check(ds.caves.warnings > 0, "the room creaks first (%d warnings)" % ds.caves.warnings)
				check(ds.caves.falls > 0, "then its roof comes down (%d falls)" % ds.caves.falls)
				_next(4)
		4:
			if t - mark > 2.0:
				check(arena.player_hp < float(v.hp), "you're hurt under it (%.0f -> %.0f)" % [v.hp, arena.player_hp])
				var c := ds.terrain.cell_of(DigSite.AT + Vector3(10.5, v.floor + 0.5, -7.0))
				var loose: int = ds.terrain.grid.count_box(c.x - 20, c.y - 4, c.z - 20, c.x + 20, c.y + 24, c.z + 20, -3)
				check(loose > 100, "it came down loose (%d blocks)" % loose)
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
			if (ok and t - mark > 2.0) or t - mark > 30.0:
				check(ok, "at the Dig Site")
				if role == "host":
					var top := ds.terrain.top_at(DigSite.AT.x - 10.0, DigSite.AT.z - 10.0)
					_dig_box(Vector3(-12.0, top - DigSite.AT.y - 3.0, -12.0), Vector3(4.0, 2.0, 4.0))
				_next(3)
		3:
			if (ds.caves.falls > 0 and t - mark > 3.0) or t - mark > 20.0:
				check(ds.caves.warnings > 0, "%s: it creaks (%d warnings)" % [role, ds.caves.warnings])
				check(ds.caves.falls > 0, "%s: it falls (%d falls)" % [role, ds.caves.falls])
				_next(4)
		4:
			if (role == "host" or ds.net.last_match) and t - mark > 3.0 or t - mark > 15.0:
				if role == "guest":
					check(ds.net.last_match, "the grounds match after")
				return _done()
	return false
