extends SceneTree
## Supports' self-test (stage 8; headless: --fixed-fps 60 -s test/voxel/digsite_support_test.gd -- --nosave). Alone:
## the site office sells wooden props, makes concrete supports, buys your ore; a room in the dirt that would cave in
## holds with a prop put up in its middle; deep down a wooden prop groans and gives way, a concrete one holds. With
## --host=CODE / --join=CODE: the guest puts a prop up (it's in the host's game too, and on its list); deep down the
## guest's wooden prop gives way in the host's game and the guest hears it and sees it go. Owned by the voxel session.

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
		print("DSSUP ok   ", role, " ", what)
	else:
		failed += 1
		print("DSSUP FAIL ", role, " ", what)

func _done() -> bool:
	print("DSSUP done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _ds() -> DigSite:
	return arena.digsite

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

func _floor(local: Vector3) -> Vector3:
	return DigSite.AT + local + Vector3(0, 0.0, 0)

func _count(m: int, at: Vector3, r: int) -> int:
	var tr := _ds().terrain
	var c := tr.cell_of(at)
	return tr.grid.count_box(c.x - r, c.y - 2, c.z - r, c.x + r, c.y + 40, c.z + r, m)

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
				arena.godmode = true
				arena.phone.travel("digsite")
				_next(1)
		1:
			if ds.active and not arena.phone._going and t - mark > 1.0:
				var tl := ds.tools
				arena.cash = 12
				check(tl.buy_props() and arena.inv.count("prop_wood") == 5 and arena.cash == 2, "the office sells 5 wooden props for $10")
				check(not tl.make_concrete(), "concrete needs stone, sand, gravel")
				arena.inv.add("stone", 16)
				arena.inv.add("sand", 8)
				arena.inv.add("gravel", 8)
				check(tl.make_concrete() and arena.inv.count("prop_concrete") == 1, "... and makes a concrete support of them")
				arena.inv.add("coal", 10)
				arena.inv.add("gem", 1)
				check(tl.sell_ore() == 25 and arena.cash == 27, "it buys your ore ($%d)" % arena.cash)
				check(ds.tools.shop_line().begins_with("B  5 wooden props"), "its line: '%s'" % ds.tools.shop_line())
				arena.inv.remove("prop_concrete", 1)
				# a 3.5 m room in the dirt, 2 m tall, its roof 1 m down: a prop up in its middle as soon as it's dug
				var top := ds.terrain.top_at(DigSite.AT.x + 12.0, DigSite.AT.z - 12.0)
				v.fl = top - DigSite.AT.y - 3.0
				_dig_box(Vector3(10.25, v.fl, -13.75), Vector3(3.5, 2.0, 3.5))
				var props: int = arena.inv.count("prop_wood")
				var ok: bool = ds.supports.place(_floor(Vector3(12.0, v.fl, -12.0)), Vector3.UP)
				check(ok and arena.inv.count("prop_wood") == props - 1, "a prop up in the middle (one out of the backpack)")
				v.wood = _count(DsMats.WOOD, _floor(Vector3(12.0, v.fl, -12.0)), 3)
				check(int(v.wood) >= 4 * 12, "it's a post of wood blocks floor to roof (%d)" % v.wood)
				_next(2)
		2:
			if t - mark > 7.0:
				check(ds.caves.falls == 0, "the room holds with it (%d warnings, %d held, %d falls)" % [ds.caves.warnings, ds.caves.held, ds.caves.falls])
				# deep down (the stone, 10 m): a wooden prop and a concrete one, the weight on fast
				var top := ds.terrain.top_at(DigSite.AT.x - 12.0, DigSite.AT.z + 6.0)
				v.dfl = top - DigSite.AT.y - 10.0
				_dig_box(Vector3(-14.0, v.dfl, 4.0), Vector3(4.0, 2.0, 2.0))
				ds.supports.stress_k = 8.0
				check(ds.supports.place(_floor(Vector3(-13.0, v.dfl, 5.0)), Vector3.UP), "a wooden prop deep down")
				arena.inv.add("prop_concrete", 1)
				check(ds.supports.place(_floor(Vector3(-11.0, v.dfl, 5.0)), Vector3.UP), "a concrete one beside it")
				v.heard = ds.supports.heard
				_next(3)
		3:
			if ds.supports.broke > 0 or t - mark > 15.0:
				check(ds.supports.broke == 1 and ds.supports.heard > int(v.heard) + 1, "deep down the wooden prop groans and gives way (%d sounds)" % (ds.supports.heard - int(v.heard)))
				_next(4)
		4:
			if t - mark > 4.0:
				var c0 := _count(DsMats.CONCRETE, _floor(Vector3(-11.0, v.dfl, 5.0)), 2)
				check(c0 >= 48 and ds.supports.posts.size() >= 1, "the concrete one holds (%d blocks)" % c0)
				var tr := ds.terrain
				var c := tr.cell_of(_floor(Vector3(-13.0, v.dfl, 5.0)))
				check(tr.grid.count_box(c.x - 8, c.y - 2, c.z - 8, c.x + 8, c.y + 20, c.z + 8, -3) > 20, "the wood's come down loose")
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
				ds.supports.stress_k = 8.0
				var top := ds.terrain.top_at(DigSite.AT.x - 12.0, DigSite.AT.z + 6.0)
				v.dfl = top - DigSite.AT.y - 10.0
				if role == "guest":
					_dig_box(Vector3(-14.0, v.dfl, 4.0), Vector3(4.0, 2.0, 2.0))
				_next(3)
		3:
			if t - mark > 2.0:
				if role == "guest":
					arena.inv.add("prop_wood", 1)
					check(ds.supports.place(_floor(Vector3(-13.0, v.dfl, 5.0)), Vector3.UP), "the guest puts a wooden prop up deep down")
				_next(4)
		4:
			if (t - mark > 2.0 and (role == "guest" or ds.supports.added > 0)) or t - mark > 20.0:
				if role == "host":
					check(ds.supports.added == 1, "the guest's prop went up in the host's game, on its list (%d)" % ds.supports.added)
				v.heard = ds.supports.heard
				_next(5)
		5:
			var cc := ds.terrain.cell_of(_floor(Vector3(-13.0, v.dfl, 5.0)))
			var gone: bool = ds.terrain.grid.count_box(cc.x - 8, cc.y - 2, cc.z - 8, cc.x + 8, cc.y + 20, cc.z + 8, -3) > 20 and ds.supports.heard > int(v.heard)
			if (gone and t - mark > 2.0) or t - mark > 20.0:
				check(ds.supports.heard > int(v.heard), "%s hears it groan (%d)" % [role, ds.supports.heard - int(v.heard)])
				var tr := ds.terrain
				var c := tr.cell_of(_floor(Vector3(-13.0, v.dfl, 5.0)))
				check(tr.grid.count_box(c.x - 8, c.y - 2, c.z - 8, c.x + 8, c.y + 20, c.z + 8, -3) > 20, "%s: it gave way, its wood down loose" % role)
				_next(6)
		6:
			if t - mark > 2.0:
				return _done()
	return false
