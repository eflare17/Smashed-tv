extends SceneTree
## The bug sweep's yard fixes, each checked (headless): poo dropped in the gateway's sliver between the yard and the
## run stays by the gate (not in the arena's corner); a hen's view rebuilt when the same id comes back another coat;
## hidden nest boxes' shelves aren't solid; a guest's big worm farm feed isn't cut at the host; the shredder grinds at
## its rate at any frame rate (and its spray isn't restarted every frame); the can waters a plant a fill, not by time;
## no worms out of stone, nor out of dirt put back; a guest's newer dig isn't put back by the host's older chunk; a
## guest joining gets the yard once. Prints "SWY ok/FAIL ..." and "SWY done N passed, M failed". Owned by the voxel
## session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
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
	print("SWY %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

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

func _spot_centre(key: int) -> Vector3:
	var g: VoxelTerrain = arena.yard.ground
	return g.origin + Vector3((float(key / 1000) + 0.5) * VoxelFarm.SPOT, 3.0, (float(key % 1000) + 0.5) * VoxelFarm.SPOT)

# the debris cubes (flying and lying) within r metres (level) of p
func _cubes_near(p: Vector3, r: float) -> int:
	var d: VoxelDebris = arena.debris
	var n := 0
	for i in d._n:
		if Vector2(d._pos[i].x - p.x, d._pos[i].z - p.z).length() <= r:
			n += 1
	for i in d._ln:
		if Vector2(d._lp[i].x - p.x, d._lp[i].z - p.z).length() <= r:
			n += 1
	return n

# the debris cubes' x range within r metres (level) of p: [lowest, highest]
func _x_range(p: Vector3, r: float) -> Array:
	var d: VoxelDebris = arena.debris
	var lo := INF
	var hi := -INF
	for i in d._n:
		if Vector2(d._pos[i].x - p.x, d._pos[i].z - p.z).length() <= r:
			lo = minf(lo, d._pos[i].x)
			hi = maxf(hi, d._pos[i].x)
	for i in d._ln:
		if Vector2(d._lp[i].x - p.x, d._lp[i].z - p.z).length() <= r:
			lo = minf(lo, d._lp[i].x)
			hi = maxf(hi, d._lp[i].x)
	return [lo, hi]

# a transport that keeps what's sent (the host's messages, looked at)
func _fake_tr() -> NetTransport:
	var gs := GDScript.new()
	gs.source_code = "extends NetTransport\nvar sent := []\nfunc send(d: PackedByteArray) -> void:\n\tsent.append(d)\n"
	gs.reload()
	return gs.new()

func _yard_msgs(tr, kind: String) -> int:
	var n := 0
	for d: PackedByteArray in tr.sent:
		if d.size() > 1 and d[0] == 82:
			var m = bytes_to_var(d.slice(1))
			if typeof(m) == TYPE_ARRAY and m.size() > 1 and String(m[0]) == "Y" and String(m[1]) == kind:
				n += 1
	return n

func _units() -> void:
	var net: VoxelNet = arena.net
	var yard: VoxelYard = arena.yard
	var ch: VoxelChickens = yard.chickens
	var sh: VoxelShredder = yard.shredder
	var farm: VoxelFarm = yard.farm
	var g: VoxelTerrain = yard.ground
	# (61) the same hen id another coat (the host's flock over ours): its view rebuilt in the new coat
	var d: Dictionary = ch.to_data()
	var id := int(d.hens[0].id)
	ch._show(0.0)
	var c0: int = (ch._views[id] as VoxelChicken).coat
	d.hens[0].c = (c0 + 1) % VoxelChicken.COATS.size()
	d.hens[0].age = 1.0
	ch.from_data(d)
	ch._show(0.0)
	check((ch._views[id] as VoxelChicken).coat == int(d.hens[0].c), "a hen id back in another coat: drawn in it (%d, was %d)" % [(ch._views[id] as VoxelChicken).coat, c0])
	# (111) the nest boxes not there yet: their shelves not solid either
	ch.level = 0
	ch._show(0.0)
	var ok0 := true
	for k in ch._nest_nodes.size():
		var cs: CollisionShape3D = ch._nest_nodes[k][2]
		if cs.disabled != (k >= ch.nest_count()):
			ok0 = false
	check(ok0, "coop level 0: the two nest boxes' shelves solid, the four hidden ones' not")
	ch.level = 1
	ch._show(0.0)
	check(not (ch._nest_nodes[3][2] as CollisionShape3D).disabled and (ch._nest_nodes[4][2] as CollisionShape3D).disabled, "coop level 1: four shelves solid, the last two not")
	ch.level = 0
	ch._show(0.0)
	# (54) a guest's worm farm feed worth more than FEED_MOST (bags, poo): all of it at the host's
	var f0 := float(farm.worms.food)
	net.linked = true
	net.role = "host"
	farm.on_net(["wfeed", 0, 4500.0])
	var f1 := float(farm.worms.food)
	farm.on_net(["wfeed", 0, 1e12])
	var f2 := float(farm.worms.food)
	net.linked = false
	net.role = ""
	check(is_equal_approx(f1 - f0, 4500.0), "a guest's 30 bags in the host's worm farm: 4500 food, not cut to 3000 (%.0f)" % (f1 - f0))
	check(f2 - f1 <= VoxelFarm.FEED_MOST * VoxelShredder.BAG_SCRAPS + 0.5, "a silly guest feed still capped (%.0f)" % (f2 - f1))
	farm.worms.food = f0
	# (60) the shredder's rate at any frame rate (the frames' fractions kept), several kinds in too
	var t0 := sh.tier
	var b0 := sh.bags
	var p0 := sh.points
	sh.tier = 0
	var rates := []
	for fps in [60, 165, 240, 500]:
		sh.queue = {"meat": 4000}
		sh._acc = 0.0
		var gr0 := sh.ground
		for i in fps:
			sh._grind(1.0 / fps)
		rates.append(int(round(sh.ground - gr0)))
	var r_ok := true
	for r in rates:
		if absi(int(r) - 300) > 1:
			r_ok = false
	check(r_ok, "the mincer grinds 300 a second at 60, 165, 240 and 500 frames a second (%s)" % str(rates))
	sh.queue = {"meat": 4000, "bone": 4000, "brain": 4000}
	sh._acc = 0.0
	var gr1 := sh.ground
	for i in 165:
		sh._grind(1.0 / 165.0)
	check(absi(int(round(sh.ground - gr1)) - 300) <= 1, "three kinds in at 165 fps: still 300 a second (%d)" % int(round(sh.ground - gr1)))
	sh.queue = {}
	sh._grind(0.0)
	check(sh._acc == 0.0, "nothing in: no grinding banked")
	sh.points = p0
	sh.bags = b0
	sh.tier = t0
	# (59) the spray's amount set with the tier, not every frame (setting it starts the spray over)
	sh._spray.amount = 7
	sh._show(1.0 / 60.0)
	check(sh._spray.amount == 7, "the shredder's frame doesn't set the spray's amount (it'd wipe the spray)")
	sh._show_tier()
	check(sh._spray.amount == int(VoxelShredder.TIERS[sh.tier].spray), "its tier sets it (%d)" % sh._spray.amount)
	# (55) worms: not out of stone or rock, nor out of dirt put back in
	g.load_chunks({})
	var rock := Vector3i(-1, -1, -1)
	var dirt := Vector3i(-1, -1, -1)
	for z in range(1, VoxelTerrain.NZ - 1):
		for x in range(1, VoxelTerrain.NX - 1):
			for y in range(2, VoxelTerrain.NY - 1):
				if not VoxelTerrain.worm_in(x, y, z):
					continue
				var m := g.at(x, y, z)
				if rock.x < 0 and m in [VoxelTerrain.STONE, VoxelTerrain.ROCK, VoxelTerrain.GOLD]:
					rock = Vector3i(x, y, z)
				elif dirt.x < 0 and m == VoxelTerrain.DIRT:
					dirt = Vector3i(x, y, z)
	check(rock.x >= 0 and dirt.x >= 0, "a worm block in rock and one in dirt found")
	var got := g.dig(g.centre_of(rock.x, rock.y, rock.z), 0.06, 4)
	check((got._cells as Array).size() == 1 and (got._worms as Array).is_empty(), "the pick through a 'worm' block of stone or rock: no worm")
	got = g.dig(g.centre_of(dirt.x, dirt.y, dirt.z), 0.06, 4)
	check((got._worms as Array).size() == 1 and int(got.get("dirt", 0)) == 1, "a worm block of dirt dug: a worm")
	var k1 := g.fill(g.centre_of(dirt.x, dirt.y, dirt.z), 0.06, 1)
	check(k1 == 1 and g.at(dirt.x, dirt.y, dirt.z) == VoxelTerrain.FILL, "filled back in: put-back dirt")
	got = g.dig(g.centre_of(dirt.x, dirt.y, dirt.z), 0.06, 4)
	check((got._worms as Array).is_empty() and int(got.get("dirt", 0)) == 1, "the same block dug again: its dirt back, no second worm")
	var top := Vector3i(32, VoxelTerrain.NY - 1, 32)            # (the middle of spot 5005)
	g.dig(g.centre_of(top.x, top.y, top.z), 0.06, 4)
	g.fill(g.centre_of(top.x, top.y, top.z), 0.06, 1)
	var was := g.at(top.x, top.y, top.z)
	g.till([5005], int(VoxelFarm.SPOT / VoxelTerrain.CELL))
	check(was == VoxelTerrain.FILL and g.at(top.x, top.y, top.z) == VoxelTerrain.TILLED, "put-back dirt at the top hoes like the rest")
	g.finish()
	check(g.meshed > 0, "the ground with put-back dirt in it meshes")
	# (106) a guest's newer dig isn't put back by the host's chunk from before it got there
	g.load_chunks({})
	net.linked = true
	net.role = "guest"
	var cc := (40 / VoxelTerrain.CS) + (40 / VoxelTerrain.CS) * (VoxelTerrain.NX / VoxelTerrain.CS)
	yard.dig(g.centre_of(40, VoxelTerrain.NY - 2, 40), 0.2, 4)
	var theirs := g.hashes()
	theirs[cc] = theirs[cc] + 1
	yard.on_net(["sum", theirs])
	var old := g.chunk_bytes(cc).compress(FileAccess.COMPRESSION_ZSTD)       # (the host's, with that dig, as it answers)
	yard.dig(g.centre_of(44, VoxelTerrain.NY - 2, 44), 0.2, 4)                # (dug again before the answer came)
	yard.on_net(["chunk", cc, old])
	check(g.at(44, VoxelTerrain.NY - 2, 44) == VoxelTerrain.AIR and g.at(40, VoxelTerrain.NY - 2, 40) == VoxelTerrain.AIR, "co-op guest: the host's older chunk doesn't fill in the guest's newer dig")
	theirs = g.hashes()
	theirs[cc] = theirs[cc] + 1
	yard.on_net(["sum", theirs])
	var hb := g.chunk_bytes(cc)
	hb[(1 * VoxelTerrain.NY + VoxelTerrain.NY - 1) * VoxelTerrain.CS + 1] = VoxelTerrain.AIR     # (33, top, 33): the host's
	yard.on_net(["chunk", cc, hb.compress(FileAccess.COMPRESSION_ZSTD)])
	check(g.at(33, VoxelTerrain.NY - 1, 33) == VoxelTerrain.AIR and g.at(44, VoxelTerrain.NY - 2, 44) == VoxelTerrain.AIR, "co-op guest: a chunk with nothing of ours newer is put in")
	net.linked = false
	net.role = ""
	# (57) the host's link coming up doesn't send the yard itself: the guest's hello does, once
	var tr0 = net.tr
	var fake := _fake_tr()
	net.tr = fake
	net.linked = true
	net.role = "host"
	yard._was_role = ""
	yard._process(0.0)
	var n_up := _yard_msgs(fake, "all")
	yard.send_all()
	var n_hello := _yard_msgs(fake, "all") - n_up
	net.tr = tr0
	net.linked = false
	net.role = ""
	yard._was_role = ""
	check(n_up == 0 and n_hello == 1, "a guest joining gets the yard once (link up %d, hello %d)" % [n_up, n_hello])
	g.load_chunks({})
	g.finish()

func _process(dt: float) -> bool:
	if arena.stash and arena.stash.save_path != "":
		arena.stash.save_path = ""       # (this test never writes the game's save)
	t += dt
	if t < 1.0:
		return false
	var farm: VoxelFarm = arena.yard.farm
	var ch: VoxelChickens = arena.yard.chickens
	match step:
		0:
			arena.frozen = true
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			arena.spawn(1)                 # (one standing still: no waves cleared while this runs)
			_units()
			# (110) poo in the gateway's sliver (between the yard's cubes and the run's): by the gate, not in the corner
			v0.corner = Vector3(21.47, 0, 21.47)
			v0.corner0 = _cubes_near(v0.corner, 0.4)
			ch._poo(Vector3(22.58, 0, 30.5), 12345)
			ch._poo(Vector3(22.52, 0, 29.9), 777)
			ch._poo(Vector3(22.62, 0, 31.1), 4242)
			# the can: a row of plants, looked at
			arena.inv.from_data([])
			farm.from_data({})
			v0.k = farm.spot_of(Vector3(12.1, 0, 30.1))
			arena.yard.till([int(v0.k), int(v0.k) - 1])
			arena.inv.add(VoxelFarm.seed_id(0), 2)
			farm.plant(int(v0.k), 0)
			farm.plant(int(v0.k) - 1, 0)
			arena.yard.ground.finish()
			_look_at(_spot_centre(int(v0.k)))
			_tool("can")
			mark = t
			step = 1
		1:
			if t - mark > 0.2:
				arena._camera(0.0)
				var can: VoxelTool = arena.melee.can
				can.water = VoxelFarm.CAN
				can.press(MOUSE_BUTTON_LEFT)
				mark = t
				step = 2
		2:
			if t - mark > 2.0:
				var can: VoxelTool = arena.melee.can
				can.release(MOUSE_BUTTON_LEFT)
				var p = farm.plants.get(int(v0.k))
				var q = farm.plants.get(int(v0.k) - 1)
				check(p != null and float(p.wet) > 170.0 and q != null and float(q.wet) <= 0.0, "the can poured on one plant: it's watered, the next one isn't")
				check(is_equal_approx(can.water, VoxelFarm.CAN - 1.0), "two seconds held on it: one plant's worth gone, not two seconds' (%.2f left)" % can.water)
				check(can.bar_text() == "7/8", "the can's count is plants (\"%s\")" % can.bar_text())
				# the poo
				var near_corner: int = _cubes_near(v0.corner, 0.4) - int(v0.corner0)
				check(near_corner == 0, "poo in the gateway's sliver: none of it in the arena's corner (%d)" % near_corner)
				var a := _x_range(Vector3(22.58, 0, 30.5), 0.3)
				check(_cubes_near(Vector3(22.58, 0, 30.5), 0.3) >= VoxelChickens.POO_CUBES and float(a[0]) >= VoxelChickens.X0, "poo dropped at x 22.58 lies by the gate, in the run (x %.2f..%.2f)" % [a[0], a[1]])
				var b := _x_range(Vector3(22.52, 0, 29.9), 0.3)
				check(_cubes_near(Vector3(22.52, 0, 29.9), 0.3) >= VoxelChickens.POO_CUBES and float(b[1]) <= VoxelYard.X1, "poo dropped at x 22.52 lies by the gate, in the yard (x %.2f..%.2f)" % [b[0], b[1]])
				# the hidden nests' shelves: a ray at shelf height goes through them, the two there stop it
				var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
				var hits := []
				for k in VoxelChickens.LEVELS[-1].nests:
					var nz := VoxelChickens.NEST_Z + k * VoxelChickens.NEST_DZ
					var rq := PhysicsRayQueryParameters3D.create(Vector3(30.4, 0.52, nz), Vector3(31.45, 0.52, nz))
					var hit := space.intersect_ray(rq)
					hits.append(not hit.is_empty() and (hit.position as Vector3).x < 31.3)
				check(hits == [true, true, false, false, false, false], "coop level 0: walking along the wall, only the two nest boxes' shelves are solid (%s)" % str(hits))
				step = 3
		3:
			print("SWY done %d passed, %d failed" % [passed, failed])
			return true
	return false
