extends SceneTree
## Stage 4, digging (headless): the yard through the back door (a safe place), the tools on key 6, the rusty shovel
## scooping dirt into the backpack, the shovel clanging off stone and the pick breaking it, a worm dug up, the shovel
## filling a hole back in from the backpack, the tool bench making the good and then the golden shovel (bigger scoops,
## through stone), falling into a hole dug, the dug ground and the shovel saved, and what a dig costs. With --host=CODE
## / --join=CODE (two copies, the host first): ground dug before the guest came is there for the guest, each one's
## digs show in the other's game (block for block), what comes up is the digger's only, and the ground fingerprints
## agree. Prints "DIG ok/FAIL ..." and "DIG done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var role := ""
var v0 := {}

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("DIG %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host"):
			role = "host"
		elif a.begins_with("--join"):
			role = "guest"
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	arena._unhandled_input(e)

func _hold(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _place(p: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

func _ground() -> VoxelTerrain:
	return arena.yard.ground

# stand so the eye looks down at world point p from 1.4 m away (level)
func _look_at_ground(p: Vector3) -> void:
	var from := p + Vector3(0, 0, 1.4)
	_place(Vector3(from.x, 0, from.z), 0.0, 0.0)
	var eye := Vector3(from.x, 1.65, from.z)
	var to := p - eye
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _tool(id: String) -> VoxelTool:
	var i: int = arena.loadout.index_of(id)
	arena._switch(func(): arena.loadout.select(i))
	arena.loadout.switch_t = 0.0
	var w: VoxelTool = arena.melee[id]
	w._cd = 0.0
	return w

func _clear() -> void:
	for b in arena.bodies:
		b.queue_free()
	arena.bodies.clear()

# a patch of the ground's top made of material m (a test spot), meshed
func _patch(c: Vector3, r: int, m: int) -> void:
	var g := _ground()
	var cc := g.cell_of(c)
	for z in range(cc.z - r, cc.z + r + 1):
		for x in range(cc.x - r, cc.x + r + 1):
			for y in range(VoxelTerrain.NY - 4, VoxelTerrain.NY):
				g.cells[VoxelTerrain.idx(x, y, z)] = m
				g._touch(x, z)
	g.finish()

func _air_near(c: Vector3, r: float) -> int:
	var g := _ground()
	var n := 0
	var lo := g.cell_of(c - Vector3.ONE * r)
	var hi := g.cell_of(c + Vector3.ONE * r)
	for z in range(lo.z, hi.z + 1):
		for y in range(maxi(0, lo.y), mini(VoxelTerrain.NY, hi.y + 1)):
			for x in range(lo.x, hi.x + 1):
				if g.at(x, y, z) == VoxelTerrain.AIR:
					n += 1
	return n

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if role == "":
		return _solo()
	return _coop()

func _solo() -> bool:
	match step:
		0:
			_clear()
			arena.frozen = true
			arena.inv.from_data([])
			arena.set_shovel_tier(0)
			_ground().load_chunks({})
			_ground().finish()
			check(arena.yard != null and _ground().cells.size() == VoxelTerrain.NX * VoxelTerrain.NY * VoxelTerrain.NZ, "the yard and its ground")
			check(VoxelArena.safe(Vector3(13, 0, 30)), "a safe place (the enemies keep out)")
			_place(Vector3(12.7, 0, 19.5), PI, 0.0)
			_hold(KEY_W, true)
			mark = t
			step = 1
		1:
			if arena.player.global_position.z > 24.0 or t - mark > 6.0:
				_hold(KEY_W, false)
				check(arena.player.global_position.z > 24.0, "through the back door into the yard (z %.1f)" % arena.player.global_position.z)
				_key(KEY_6)
				check(arena.loadout.id() == "shovel" and arena.melee.shovel.tier == 0, "6: the rusty shovel")
				v0.spot = Vector3(14.0, 0.0, 30.0)
				_look_at_ground(v0.spot)
				mark = t
				step = 2
		2:
			if t - mark > 0.15 and step == 2:
				var w := _tool("shovel")
				arena._camera(0.0)
				v0.air = _air_near(v0.spot, 0.6)
				w.press(MOUSE_BUTTON_LEFT)
				w.release(MOUSE_BUTTON_LEFT)
				mark = t
				step = 3
		3:
			if t - mark > 0.8:
				var dirt: int = arena.inv.count("dirt")
				check(dirt > 0 and _air_near(v0.spot, 0.6) - int(v0.air) == dirt, "a scoop: %d blocks of dirt into the backpack (the ground's %d emptier)" % [dirt, _air_near(v0.spot, 0.6) - int(v0.air)])
				# stone: the shovel can't, the pick can
				v0.stone_at = Vector3(17.0, 0.0, 33.0)
				_patch(v0.stone_at, 4, VoxelTerrain.STONE)
				_look_at_ground(v0.stone_at)
				mark = t
				step = 4
		4:
			if t - mark > 0.15 and step == 4:
				arena._camera(0.0)
				var w := _tool("shovel")
				v0.air = _air_near(v0.stone_at, 0.6)
				w.press(MOUSE_BUTTON_LEFT)
				mark = t
				step = 5
		5:
			if t - mark > 0.8 and step == 5:
				check(_air_near(v0.stone_at, 0.6) == int(v0.air) and arena._say_text.contains("Too hard"), "the shovel clangs off stone: \"%s\"" % arena._say_text)
				var w := _tool("pick")
				w.press(MOUSE_BUTTON_LEFT)
				mark = t
				step = 6
		6:
			if t - mark > 0.8 and step == 6:
				check(arena.inv.count("stone") > 0, "the pick breaks it: %d stone" % arena.inv.count("stone"))
				# a worm: dig where one lives
				var g := _ground()
				var found := Vector3i(-1, -1, -1)
				for z in range(20, 100):
					for x in range(20, 100):
						for y in range(VoxelTerrain.NY - 3, VoxelTerrain.NY - 1):
							if VoxelTerrain.worm_in(x, y, z) and g.at(x, y, z) in [VoxelTerrain.DIRT, VoxelTerrain.GRASS]:
								found = Vector3i(x, y, z)
								break
						if found.x >= 0:
							break
					if found.x >= 0:
						break
				check(found.x >= 0, "a worm lives in the dirt somewhere near the top")
				v0.worm_at = g.centre_of(found.x, VoxelTerrain.NY - 1, found.z) + Vector3(0, VoxelTerrain.CELL * 0.5, 0)
				v0.worm_cell = found
				_look_at_ground(v0.worm_at)
				mark = t
				step = 7
		7:
			if t - mark > 0.15 and step == 7:
				arena._camera(0.0)
				var w := _tool("shovel")
				arena.set_shovel_tier(2)                 # (a big scoop, so it reaches the worm's block)
				w.press(MOUSE_BUTTON_LEFT)
				mark = t
				step = 8
		8:
			if t - mark > 0.8 and step == 8:
				var c: Vector3i = v0.worm_cell
				check(_ground().at(c.x, c.y, c.z) == VoxelTerrain.AIR, "dug out the worm's block")
				var worms := 0
				for n in arena.get_children():
					if n is VoxelWorm:
						worms += 1
				check(arena.inv.count("worm") >= 1 and worms >= 1, "a worm wriggles out, into the backpack (%d)" % arena.inv.count("worm"))
				# fill the hole back in
				var w := _tool("shovel")
				v0.dirt = arena.inv.count("dirt")
				v0.air = _air_near(v0.worm_at, 0.9)
				w.press(MOUSE_BUTTON_RIGHT)
				mark = t
				step = 9
		9:
			if t - mark > 0.8 and step == 9:
				var used: int = int(v0.dirt) - arena.inv.count("dirt")
				check(used > 0 and int(v0.air) - _air_near(v0.worm_at, 0.9) == used, "right click fills it back: %d dirt from the backpack, the ground %d fuller" % [used, int(v0.air) - _air_near(v0.worm_at, 0.9)])
				# the tool bench
				arena.set_shovel_tier(0)
				_place(VoxelYard.BENCH + Vector3(0, 0, 1.3), 0.0, -0.45)
				mark = t
				step = 10
		10:
			if t - mark > 0.15 and step == 10:
				arena._camera(0.0)
				arena._storage_step(0.0)
				check(arena._near_bench and arena._use_label.text.contains("Good shovel"), "at the bench: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.shovel_tier == 0, "not enough: no shovel made")
				arena.inv.add("stone", 200)
				arena.inv.add("bone", 600)
				var stone0: int = arena.inv.count("stone")
				arena._storage_step(0.0)
				_key(KEY_E)
				check(arena.shovel_tier == 1 and arena.melee.shovel.tier == 1 and arena.inv.count("stone") == stone0 - 150 and arena.inv.count("bone") == 100, "E: the good shovel made (150 stone and 500 bone used)")
				arena.inv.add("gold", 80)
				arena.inv.add("brain", 500)
				_key(KEY_E)
				check(arena.shovel_tier == 2 and arena.inv.count("gold") == 0, "then the golden one")
				# the golden one goes through stone
				_look_at_ground(v0.stone_at + Vector3(0.6, 0, 0))
				mark = t
				step = 11
		11:
			if t - mark > 0.15 and step == 11:
				arena._camera(0.0)
				var w := _tool("shovel")
				v0.stone = arena.inv.count("stone")
				var t0 := Time.get_ticks_usec()
				w.press(MOUSE_BUTTON_LEFT)
				mark = t
				step = 12
		12:
			if t - mark > 0.8 and step == 12:
				check(arena.inv.count("stone") > int(v0.stone), "the golden shovel goes through stone (%d more)" % (arena.inv.count("stone") - int(v0.stone)))
				# a big hole: fall in
				var hole := Vector3(10.0, 0, 36.0)
				var g := _ground()
				var t0 := Time.get_ticks_usec()
				for k in 6:
					g.dig(hole + Vector3(0, -0.3 - k * 0.25, 0), 0.75, 4)
				v0.dig_ms = (Time.get_ticks_usec() - t0) / 1000.0 / 6.0
				g.finish()
				_place(hole + Vector3(0, 0.3, 0), 0.0, 0.0)
				mark = t
				step = 13
		13:
			if t - mark > 1.5 and step == 13:
				check(arena.player.global_position.y < -0.8, "fell into the hole dug (feet at %.2f m)" % arena.player.global_position.y)
				check(float(v0.dig_ms) < 4.0, "a big dig costs %.2f ms (the meshing is off on worker threads)" % v0.dig_ms)
				# saved
				arena.stash.save_path = "user://dig_test.json"
				arena.stash.save()
				var before: PackedInt64Array = _ground().hashes()
				_ground().load_chunks({})
				arena.set_shovel_tier(0)
				arena.stash.load_save()
				check(_ground().hashes() == before and arena.shovel_tier == 2, "the dug ground and the shovel saved and loaded")
				_place(Vector3(13, 0, 30), 0, 0)
				step = 99
		99:
			print("DIG done %d passed, %d failed" % [passed, failed])
			return true
	return false

# ---------------------------------------------------------------- co-op

func _coop() -> bool:
	var n = arena.net
	if role == "host" and step == 0 and not v0.has("early"):
		# dug before the guest comes
		v0.early = true
		_ground().load_chunks({})
		arena.yard.dig(Vector3(9.0, -0.2, 27.0), 0.6, 4)
	if step > 0 and step < 99 and not n.linked and not (role == "host" and step == 5):
		check(false, "co-op: the link went before the end (step %d)" % step)
		step = 99
	elif step == 0 and (not n.linked or (role == "guest" and not n._got_world)):
		if Time.get_ticks_msec() > 60000:
			print("DIG FAIL never linked (%s)" % n.status_text)
			print("DIG done %d passed, %d failed" % [passed, failed + 1])
			return true
		return false
	var g := _ground()
	if role == "host":
		match step:
			0:
				_clear()
				arena.frozen = true
				arena.inv.from_data([])
				mark = t
				step = 1
			1:
				# the guest's dig at (16, 29) shows here
				if _air_near(Vector3(16.0, 0.0, 29.0), 0.4) > 5:
					check(arena.inv.count("dirt") == 0, "co-op: the guest's dig shows in the host's ground, and what came up isn't the host's")
					arena.yard.dig(Vector3(11.0, -0.1, 33.0), 0.4, 2)
					mark = t
					step = 2
				elif t - mark > 30.0:
					check(false, "co-op: the guest's dig never showed here")
					step = 2
			2:
				if t - mark > 8.0:
					print("DIG fp ", hash(g.hashes()))
					step = 5
					mark = t
			5:
				if not n.linked or t - mark > 120.0:
					step = 99
			99:
				print("DIG done %d passed, %d failed" % [passed, failed])
				return true
	else:
		match step:
			0:
				check(_air_near(Vector3(9.0, -0.2, 27.0), 0.5) > 20, "co-op: the ground the host dug before the guest came is dug here")
				arena.inv.from_data([])
				_look_at_ground(Vector3(16.0, 0.0, 29.0))
				mark = t
				step = 1
			1:
				if t - mark > 0.2 and step == 1:
					arena._camera(0.0)
					var w := _tool("shovel")
					arena.set_shovel_tier(1)
					w.press(MOUSE_BUTTON_LEFT)
					mark = t
					step = 2
			2:
				if t - mark > 0.8 and step == 2:
					check(arena.inv.count("dirt") > 0, "co-op: the guest's own dig: dirt in the guest's backpack (%d)" % arena.inv.count("dirt"))
					mark = t
					step = 3
			3:
				if _air_near(Vector3(11.0, -0.1, 33.0), 0.3) > 5:
					check(true, "co-op: the host's dig shows in the guest's ground")
					mark = t
					step = 4
				elif t - mark > 30.0:
					check(false, "co-op: the host's dig never showed")
					step = 4
					mark = t
			4:
				if t - mark > 7.0:
					print("DIG fp ", hash(g.hashes()))
					step = 99
			99:
				print("DIG done %d passed, %d failed" % [passed, failed])
				return true
	return false
