extends SceneTree
## Dynamite's self-test (stage 9; headless: --fixed-fps 60 -s test/voxel/digsite_dynamite_test.gd -- --nosave). Alone:
## the office sells it; lit in the dirt, it goes off after its fuse: a crater, a shell cracked loose, chunks flying
## that land as loose blocks round it (not a block made or lost); in the stone the hole's much smaller; it hurts you
## close by; set off in a tunnel, the cavern it blows out caves in. With --host=CODE / --join=CODE: the guest lights
## one; the host's game blows it up; both hear it, the guest sees the crater, the grounds match. Owned by the voxel
## session.

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
		print("DSDYN ok   ", role, " ", what)
	else:
		failed += 1
		print("DSDYN FAIL ", role, " ", what)

func _done() -> bool:
	print("DSDYN done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _ds() -> DigSite:
	return arena.digsite

func _total() -> int:
	return _ds().terrain.grid.ground_mm()      # (mm over a column: every block's 125 and the loose layer)

func _top(local: Vector3) -> Vector3:
	var p := DigSite.AT + local
	return Vector3(p.x, _ds().terrain.top_at(p.x, p.z), p.z)

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

func _stand(local: Vector3) -> void:
	_ds()._put(_top(local) + Vector3(0, 0.05, 0), 0.0, 0.0)

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
				arena.godmode = false
				arena.cash = 30
				check(ds.tools.buy_dynamite() and arena.inv.count("dynamite") == 3, "the office sells 3 sticks for $15")
				check(arena.melee.has("dynamite_ds") and arena.loadout.index_of("dynamite_ds") >= 0, "the Dynamite's with the explosives")
				_stand(Vector3(0, 0, 4))
				v.at = _top(Vector3(0, 0, -10))
				v.total = _total()
				v.hp = arena.player_hp
				check(ds.blasts.light(v.at + Vector3(0, 0.02, 0)) and arena.inv.count("dynamite") == 2, "lit (a stick out of the backpack)")
				_next(2)
		2:
			if ds.blasts.booms > 0 and not ds.blasts.busy() and t - mark > DsBlasts.FUSE + 1.0:
				var at: Vector3 = v.at
				# (its loose lining slides in at the angle of repose, filling it part way: the loose layer, since 9 Nov)
				var top := ds.terrain.surface_at(at.x, at.z)
				var last: Dictionary = ds.blasts.last
				check(int(last.n) > 1000, "it goes off in the dirt: %d blocks blown out, %d cracked loose" % [last.n, last.cracked])
				check(top < at.y - 0.6, "a crater (%.2f m deep)" % (at.y - top))
				check(_total() == int(v.total), "the chunks land as loose blocks: not one made or lost (%d, %d)" % [_total(), v.total])
				check(arena.player_hp >= float(v.hp) - 0.01, "14 m off, you're not hurt")
				v.soft = int(last.n)
				# in the stone: a shaft down to it, a stick at its bottom
				ds.terrain.paused = true
				var c := DigSite.AT + Vector3(14, 0, 14)
				var y := ds.terrain.top_at(c.x, c.z)
				var bottom := y - 9.0
				while y > bottom:
					ds.tools.dig_at(Vector3(c.x, y, c.z), 0.6, 9)
					y -= 0.4
				v.stone_at = Vector3(c.x, ds.terrain.top_at(c.x, c.z), c.z)
				print("DSDYN   the shaft's bottom: %s" % DsMats.name_of(ds.terrain.cell_at(v.stone_at + Vector3(0, -0.3, 0))))
				ds.blasts.light(v.stone_at + Vector3(0, 0.02, 0))
				_next(3)
		3:
			if ds.blasts.booms > 1 and not ds.blasts.busy() and t - mark > DsBlasts.FUSE + 1.0:
				var last: Dictionary = ds.blasts.last
				check(int(last.n) < int(v.soft) / 2, "in the stone the hole's much smaller (%d blocks, %d in the dirt)" % [last.n, v.soft])
				ds.terrain.paused = false
				# close by: hurt
				_stand(Vector3(-8, 0, 8))
				v.hp = arena.player_hp
				arena.inv.add("dynamite", 1)
				ds.blasts.light(_top(Vector3(-6.5, 0, 8)) + Vector3(0, 0.02, 0))
				_next(4)
		4:
			if ds.blasts.booms > 2 and t - mark > DsBlasts.FUSE + 1.0:
				check(arena.player_hp < float(v.hp) - 10.0, "1.5 m off, it hurts (%.0f -> %.0f)" % [v.hp, arena.player_hp])
				arena.player_hp = 100.0
				# a 4 m room in the dirt held up by a prop in its middle; a stick at the prop's foot
				var top := _top(Vector3(10, 0, -16)).y - DigSite.AT.y
				v.fl = top - 3.0
				_dig_box(Vector3(8.0, v.fl, -18.0), Vector3(4.0, 2.0, 4.0))
				arena.inv.add("prop_wood", 1)
				check(ds.supports.place(DigSite.AT + Vector3(10.0, v.fl, -16.0), Vector3.UP), "a room held up by a prop")
				v.falls = ds.caves.falls
				v.broke = ds.supports.broke
				arena.inv.add("dynamite", 1)
				_stand(Vector3(0, 0, 10))
				ds.blasts.light(DigSite.AT + Vector3(10.6, v.fl + 0.01, -16.0))
				_next(5)
		5:
			if (ds.caves.falls > int(v.falls) and t - mark > 2.0) or t - mark > 20.0:
				check(ds.supports.broke > int(v.broke), "the blast takes the prop's foot: it gives way")
				check(ds.caves.falls > int(v.falls), "and the room it held caves in (%d falls)" % (ds.caves.falls - int(v.falls)))
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
				v.at = _top(Vector3(-6, 0, -12))
				if role == "guest":
					arena.inv.add("dynamite", 1)
					check(ds.blasts.light(v.at + Vector3(0, 0.02, 0)), "the guest lights a stick")
				_next(3)
		3:
			if (ds.blasts.booms > 0 and not ds.blasts.busy() and t - mark > 2.0) or t - mark > 20.0:
				check(ds.blasts.booms == 1, "%s: it goes off once (%d)" % [role, ds.blasts.booms])
				if role == "host":
					check(int(ds.blasts.last.get("n", 0)) > 500, "the host's game blew it up (%d blocks)" % int(ds.blasts.last.get("n", 0)))
				_next(4)
		4:
			if (role == "host" or ds.net.last_match) and t - mark > 4.0 or t - mark > 15.0:
				var at: Vector3 = v.at
				check(ds.terrain.surface_at(at.x, at.z) < at.y - 0.6, "%s sees the crater" % role)
				if role == "guest":
					check(ds.net.last_match, "the grounds match")
				return _done()
	return false
