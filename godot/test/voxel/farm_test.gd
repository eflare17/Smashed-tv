extends SceneTree
## Stage 5, farming (headless): the HTML game's strain numbers, cash from kills, a seed bought at the crate, the hoe
## turning a row of spots, a seed planted (E), the can poured on it and filled again at the tank, growing at full speed
## watered and half dry, wilting after two minutes dry (a bud lost), a wave cleared jumping it ahead, worm castings
## making it grow faster with a bud more, the harvest (E) and the buds sold at the buyer, the worm farm eating scraps
## into castings, a plant whose ground is dug away gone, the farm and the cash saved. With --host=CODE / --join=CODE
## (two copies, the host first): the guest planting in the host's farm, the host's watering seen by the guest, the
## guest harvesting the host's ready plant (the buds the guest's), the guest's worms in the host's worm farm.
## Prints "FARM ok/FAIL ..." and "FARM done N passed, M failed". Owned by the voxel session.

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
	print("FARM %s %s" % ["ok" if ok else "FAIL", what])

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

func _farm() -> VoxelFarm:
	return arena.yard.farm

func _place(p: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

# stand looking down at world point p from 1.3 m away (from +z, looking -z)
func _look_at(p: Vector3) -> void:
	var from := p + Vector3(0, 0, 1.3)
	_place(Vector3(from.x, 0, from.z), 0.0, 0.0)
	var to := p - Vector3(from.x, 1.65, from.z)
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

func _spot_centre(key: int) -> Vector3:
	var g: VoxelTerrain = arena.yard.ground
	return g.origin + Vector3((float(key / 1000) + 0.5) * VoxelFarm.SPOT, 3.0, (float(key % 1000) + 0.5) * VoxelFarm.SPOT)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if role == "":
		return _solo()
	return _coop()

func _solo() -> bool:
	var farm := _farm()
	match step:
		0:
			_clear()
			arena.frozen = true
			arena.spawn(1)                 # (one standing still: no waves cleared while this runs)
			arena.inv.from_data([])
			arena.cash = 0
			arena.yard.ground.load_chunks({})
			arena.yard.ground.finish()
			farm.from_data({})
			var nl: Dictionary = VoxelFarm.STRAINS[0]
			var ww: Dictionary = VoxelFarm.STRAINS[5]
			check(VoxelFarm.STRAINS.size() == 6 and nl.mins == 4.0 and nl.waves == 2 and nl.buds == 3 and nl.price == 40 and nl.seed == 10 and ww.mins == 15.0 and ww.waves == 6, "the HTML game's six strains (NL 4 min / 2 waves / 3 buds / $40, seed $10; WW 15 min / 6 waves)")
			# cash from a kill
			var b := VoxelBody.new()
			arena.add_child(b)
			b.setup("brute", arena._cube_m("brute"), 1, arena._mat)
			b.position = Vector3(0, 0, -5)
			b.died.connect(arena._on_died)
			arena.bodies.append(b)
			b.sever("head")
			check(arena.cash == 5, "a brute killed: $5 (cash $%d)" % arena.cash)
			arena.cash = 12
			_look_at(VoxelFarm.CRATE + Vector3(-0.3, 0.4, 0))
			mark = t
			step = 1
		1:
			if t - mark > 0.15 and step == 1:
				arena._camera(0.0)
				arena._storage_step(0.0)
				check(arena._near_prop == "crate0" and arena._use_label.text.contains("Northern Lights"), "at the seed crate: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.inv.count("seed_nl") == 1 and arena.cash == 2, "E: a Northern Lights seed for $10 ($%d left)" % arena.cash)
				_key(KEY_E)
				check(arena.inv.count("seed_nl") == 1 and arena._say_text.contains("Not enough"), "no cash, no seed")
				arena.inv.add("seed_nl", 3)
				# the hoe: a row
				v0.spot0 = farm.spot_of(Vector3(12.1, 0, 30.1))
				_look_at(_spot_centre(int(v0.spot0)))
				mark = t
				step = 2
		2:
			if t - mark > 0.15 and step == 2:
				arena._camera(0.0)
				var w := _tool("hoe")
				w.press(MOUSE_BUTTON_LEFT)
				mark = t
				step = 3
		3:
			if t - mark > 0.8 and step == 3:
				var k := int(v0.spot0)
				check(farm.spot_top(k) != Vector3.INF and farm.spot_top(k - 1) != Vector3.INF and farm.spot_top(k - 2) != Vector3.INF and farm.spot_top(k + 1000) == Vector3.INF, "the hoe: a row of three spots tilled, the way I face")
				arena.yard.ground.finish()
				mark = t
				step = 4
		4:
			if t - mark > 0.2 and step == 4:
				arena._camera(0.0)
				arena._storage_step(0.0)
				check(arena._near_plant == int(v0.spot0) and arena._use_label.text.contains("plant a Northern Lights"), "at the hoed spot: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				var p = farm.plants.get(int(v0.spot0))
				check(p != null and int(p.s) == 0 and arena.inv.count("seed_nl") == 3, "E: planted (a seed used)")
				mark = t
				step = 5
		5:
			if t - mark > 0.3 and step == 5:
				var view = farm._views.get(int(v0.spot0))
				check(view != null and view.stage == 0 and view.look == 1, "a seedling, dry (a drop over it) [%s]" % ("none" if view == null else "stage %d look %d" % [view.stage, view.look]))
				arena._camera(0.0)
				var can := _tool("can")
				v0.water = can.water
				can.press(MOUSE_BUTTON_LEFT)
				mark = t
				step = 6
		6:
			if t - mark > 0.6 and step == 6:
				var can: VoxelTool = arena.melee.can
				can.release(MOUSE_BUTTON_LEFT)
				var p = farm.plants.get(int(v0.spot0))
				check(float(p.wet) > 170.0 and can.water < float(v0.water), "poured on: watered (%.0f s), the can's lower (%.1f)" % [float(p.wet), can.water])
				can.water = 0.0
				_look_at(VoxelFarm.TANK + Vector3(0, 0.8, -0.6))
				mark = t
				step = 7
		7:
			if t - mark > 0.15 and step == 7:
				arena._camera(0.0)
				arena._storage_step(0.0)
				_key(KEY_E)
				check(arena.melee.can.water == VoxelFarm.CAN, "E at the tank: the can full again")
				# growing
				var p = farm.plants.get(int(v0.spot0))
				p.g = 0.0
				p.wet = VoxelFarm.WET_FOR
				farm._grow(60.0)
				var wet_g := float(p.g)
				p.wet = 0.0
				p.g = 0.0
				p.dry = 0.0
				farm._grow(60.0)
				var dry_g := float(p.g)
				check(absf(wet_g - 0.25) < 0.01 and absf(dry_g - 0.125) < 0.01, "a minute: watered 25%% grown, dry 12.5%% (NL: 4 min)")
				farm._grow(70.0)
				check(int(p.wilt) == 1 and VoxelFarm.buds_of(p) == 2, "two minutes dry: wilted, a bud lost")
				var g0 := float(p.g)
				farm.on_wave()
				check(absf(float(p.g) - g0 - 0.5) < 0.01, "a wave cleared: half grown more (NL: 2 waves)")
				# fertiliser
				p.g = 0.0
				p.wilt = 0
				p.wet = VoxelFarm.WET_FOR
				arena.inv.add("castings", 3)
				check(farm.fertilise(int(v0.spot0)) and farm.fertilise(int(v0.spot0)) and not farm.fertilise(int(v0.spot0)), "fed castings twice (no more than twice)")
				farm._grow(60.0)
				check(absf(float(p.g) - 0.25 * 1.7) < 0.01 and VoxelFarm.buds_of(p) == 5, "fed twice: 70%% faster, 2 buds more (%.3f grown, %d buds)" % [float(p.g), VoxelFarm.buds_of(p)])
				p.g = 1.0
				mark = t
				step = 8
		8:
			if t - mark > 0.3 and step == 8:
				var view = farm._views.get(int(v0.spot0))
				check(view != null and view.stage == 3, "ready: the plant with buds")
				_look_at(_spot_centre(int(v0.spot0)) + Vector3(0, 0.5, 0))
				mark = t
				step = 9
		9:
			if t - mark > 0.2 and step == 9:
				arena._camera(0.0)
				arena._storage_step(0.0)
				check(arena._near_plant == int(v0.spot0) and arena._use_label.text.contains("harvest"), "at it: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.inv.count("bud_nl") == 5 and not farm.plants.has(int(v0.spot0)), "E: harvested, 5 buds")
				arena.cash = 0
				var c := farm.sell()
				check(c == int(round(5 * 40.0 / 3.0)) and arena.cash == c and arena.inv.count("bud_nl") == 0, "sold at the buyer: $%d" % c)
				# the worm farm
				arena.inv.add("worm", 5)
				arena.inv.add("meat", 1000)
				arena.inv.add("charred", 100)
				var r := farm.service_wormery()
				check(r == "fed" and int(farm.worms.n) == 5 and absf(float(farm.worms.food) - 1050.0) < 0.1 and arena.inv.count("worm") == 0, "the worm farm: 5 worms and scraps in (burnt counts half: %.0f)" % float(farm.worms.food))
				for k in 40:
					farm._worms(1.0)
				check(int(farm.worms.cast) >= 1 and float(farm.worms.food) < 1050.0, "the worms eat scraps into castings (%d)" % int(farm.worms.cast))
				var cast := int(farm.worms.cast)
				arena.inv.remove("castings", 99)
				check(farm.service_wormery() == "castings" and arena.inv.count("castings") == cast, "E: the castings taken")
				# a plant on ground dug away goes
				farm.plants[int(v0.spot0) - 1] = {"s": 0, "g": 0.3, "wet": 0.0, "dry": 0.0, "wilt": 0, "fed": 0}
				var top := farm.spot_top(int(v0.spot0) - 1)
				arena.yard.ground.dig(top - Vector3(0, 0.06, 0), 0.3, 4)
				mark = t
				step = 10
		10:
			if t - mark > 1.5 and step == 10:
				check(not farm.plants.has(int(v0.spot0) - 1), "its ground dug away: the plant's gone")
				# saved
				farm.plants[int(v0.spot0) - 2] = {"s": 1, "g": 0.6, "wet": 50.0, "dry": 0.0, "wilt": 0, "fed": 1}
				arena.cash = 77
				arena.stash.save_path = "user://farm_test.json"
				arena.stash.save()
				var before := farm.to_data()
				farm.from_data({})
				arena.cash = 0
				arena.stash.load_save()
				check(JSON.stringify(farm.to_data()) == JSON.stringify(before) and arena.cash == 77, "the farm and the cash saved and loaded")
				step = 99
		99:
			print("FARM done %d passed, %d failed" % [passed, failed])
			return true
	return false

# ---------------------------------------------------------------- co-op

func _coop() -> bool:
	var n = arena.net
	var farm := _farm()
	if step > 0 and step < 99 and not n.linked and not (role == "host" and step == 5):
		check(false, "co-op: the link went before the end (step %d)" % step)
		step = 99
	elif step == 0 and (not n.linked or (role == "guest" and not n._got_world)):
		if role == "host" and not v0.has("prep"):
			v0.prep = true
			arena.yard.ground.load_chunks({})
			farm.from_data({})
			arena.yard.till([farm.spot_of(Vector3(10.1, 0, 28.1)), farm.spot_of(Vector3(10.1, 0, 28.6))])
		if Time.get_ticks_msec() > 60000:
			print("FARM FAIL never linked (%s)" % n.status_text)
			print("FARM done %d passed, %d failed" % [passed, failed + 1])
			return true
		return false
	var k1 := farm.spot_of(Vector3(10.1, 0, 28.1))
	var k2 := farm.spot_of(Vector3(10.1, 0, 28.6))
	if role == "host":
		match step:
			0:
				_clear()
				arena.frozen = true
				arena.inv.from_data([])
				mark = t
				step = 1
			1:
				if farm.plants.has(k1):
					check(int(farm.plants[k1].s) == 1, "co-op: the guest planted in the host's farm (Sour Diesel)")
					farm.water(k1)
					farm.plants[k2] = {"s": 0, "g": 1.0, "wet": 0.0, "dry": 0.0, "wilt": 0, "fed": 0}
					farm._changed(k2)
					mark = t
					step = 2
				elif t - mark > 30.0:
					check(false, "co-op: the guest's planting never came")
					step = 2
			2:
				if not farm.plants.has(k2):
					check(arena.inv.count("bud_nl") == 0, "co-op: the guest harvested the host's plant (the buds aren't the host's)")
					mark = t
					step = 3
				elif t - mark > 30.0:
					check(false, "co-op: never harvested")
					step = 3
			3:
				if int(farm.worms.n) >= 4:
					check(true, "co-op: the guest's worms in the host's worm farm (%d)" % int(farm.worms.n))
					step = 5
					mark = t
				elif t - mark > 30.0:
					check(false, "co-op: the guest's worms never came")
					step = 5
					mark = t
			5:
				if not n.linked or t - mark > 120.0:
					step = 99
			99:
				print("FARM done %d passed, %d failed" % [passed, failed])
				return true
	else:
		match step:
			0:
				arena.inv.from_data([["seed_sd", 2], ["worm", 4], ["meat", 500]])
				check(farm.spot_top(k1) != Vector3.INF, "co-op: the host's hoed rows are here")
				check(farm.plant(k1, 1) and arena.inv.count("seed_sd") == 1, "co-op: planted (the seed out of the guest's backpack)")
				mark = t
				step = 1
			1:
				var p = farm.plants.get(k1)
				if p != null and float(p.wet) > 100.0 and farm.plants.has(k2):
					check(true, "co-op: the host's watering shows on the guest's side")
					v0.h = farm.harvest(k2)
					mark = t
					step = 2
				elif t - mark > 30.0:
					check(false, "co-op: the host's watering / plant never showed")
					step = 2
			2:
				if arena.inv.count("bud_nl") == 3:
					check(true, "co-op: the harvest's buds in the guest's backpack (3)")
					farm.service_wormery()
					mark = t
					step = 3
				elif t - mark > 30.0:
					check(false, "co-op: no buds came (%d)" % arena.inv.count("bud_nl"))
					step = 3
					mark = t
			3:
				if t - mark > 4.0:
					step = 99
			99:
				print("FARM done %d passed, %d failed" % [passed, failed])
				return true
	return false
