extends SceneTree
## Stage 6.5, the shredder (headless): the hand-crank mincer in the yard; the gore in the backpack put in (E) and
## ground into a bag of blood and bone at its rate; charred cubes worth a third as much (burning trades loot for fun);
## a cut-off forearm thrown in the top taken in, a whole leg too big for the mincer; upgraded at its sign to the electric
## shredder and the industrial woodchipper, which takes a whole corpse; the bags taken (E) and fed to a plant, the worm
## farm and the chickens' feeder; a corpse can go out through the back door into the yard; ash lost (the vacuum gets
## nothing, it doesn't lie about); saved and loaded. With --host=CODE / --join=CODE (two copies, the host first): the
## guest's gore ground in the host's shredder, the bag taken by the guest (theirs, not the host's), the guest upgrading
## the host's machine, a piece thrown in in the host's game. Prints "SHRED ok/FAIL ..." and "SHRED done N passed, M
## failed". Owned by the voxel session.

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
	print("SHRED %s %s" % ["ok" if ok else "FAIL", what])

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

func _sh() -> VoxelShredder:
	return arena.yard.shredder

func _place(p: Vector3) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()

# stand 1.3 m north of world point p, looking at it
func _look_at(p: Vector3) -> void:
	var from := p + Vector3(0, 0, -1.3)
	_place(Vector3(from.x, 0, from.z))
	var to := p - Vector3(from.x, 1.65, from.z)
	arena.look_yaw = atan2(-to.x, -to.z)
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _near() -> String:
	arena._camera(0.0)
	arena._storage_step(0.0)
	return arena._near_shred

func _clear() -> void:
	for b in arena.bodies:
		b.queue_free()
	arena.bodies.clear()

func _grunt(at: Vector3) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
	b.position = at
	arena.bodies.append(b)
	return b

# a part (and what hangs off it) cut off b as a flying piece at world point at
func _piece(b: VoxelBody, part: String, at: Vector3) -> RigidBody3D:
	var r: Dictionary = b.sever(part)
	var rb: RigidBody3D = arena.pieces.spawn(b, r.pieces, Vector3.ZERO, Vector3.ZERO)
	if rb:
		rb.global_position = at
		rb.freeze = true                 # (held there, as if the gravity gun had it)
	return rb

func _pieces_cubes(rb: RigidBody3D) -> int:
	for pc in arena.pieces._pieces:
		if pc.rb == rb:
			var counts := {}
			var bits := VoxelPieces.cubes_of(pc, 1, counts)
			var n := bits.size()
			for v in counts:
				n += int(counts[v])
			return n
	return -1

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if role == "":
		return _solo()
	return _coop()

func _solo() -> bool:
	var sh := _sh()
	var mouth := VoxelShredder.AT + Vector3(0, 1.2, 0)
	match step:
		0:
			_clear()
			arena.frozen = true
			arena.spawn(1)
			for b in arena.bodies:
				b.position = Vector3(0, 0, -15)
			arena.inv.from_data([])
			arena.cash = 0
			sh.from_data({})
			check(sh.tier == 0 and sh.bags == 0 and sh.queued() == 0 and VoxelYard.in_yard(VoxelShredder.AT), "the hand-crank mincer in the yard, empty")
			check(VoxelItems.has("blood_bone") and VoxelShredder.points_of({"meat": 1000}) == 1000.0 and is_equal_approx(VoxelShredder.points_of({"charred": 1000}), 350.0) and VoxelShredder.points_of({"bone": 100}) == 200.0, "points: meat 1, bone 2, charred 0.35 a cube")
			_look_at(VoxelShredder.AT + Vector3(0, 1.0, 0))
			mark = t
			step = 1
		1:
			if t - mark > 0.2:
				var n := _near()
				check(n == "machine" and arena._use_label.text.contains("throw limbs"), "at the mincer: \"%s\"" % arena._use_label.text)
				arena.inv.add("meat", 4300)
				arena.inv.add("bone", 100)
				_near()
				check(arena._use_label.text.contains("put in your gore (4400 cubes)"), "with gore: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.inv.count("meat") == 0 and arena.inv.count("bone") == 0 and sh.queued() > 4000, "E: the gore out of the backpack, in the mincer (%d to go)" % sh.queued())
				mark = t
				step = 2
		2:
			if sh.queued() == 0:
				var secs := t - mark
				check(sh.bags == 1 and is_equal_approx(sh.points, 500.0), "ground: a bag of blood and bone dropped out (%.1f s; 500 points to the next)" % secs)
				check(secs > 12.0 and secs < 18.0, "at the mincer's rate (4400 cubes at 300 a second: %.1f s)" % secs)
				# burnt: worth a third
				sh.queue = {"charred": 4000}
				sh.points = 0.0
				sh.bags = 0
				sh._grind(100.0)
				var burnt_bags := sh.bags
				sh.queue = {"meat": 4000}
				sh.points = 0.0
				sh._grind(100.0)
				check(burnt_bags == 0 and sh.bags == 1, "4000 charred cubes make no bag; 4000 meat, one (burning trades loot for fun)")
				sh.bags = 0
				sh.points = 0.0
				# a forearm thrown in the top
				var b := _grunt(Vector3(2, 0, -8))
				var rb := _piece(b, "forearm_l", mouth)
				v0.n = _pieces_cubes(rb)
				v0.rb = rb
				v0.body = b
				v0.g0 = sh.ground
				mark = t
				step = 3
			elif t - mark > 30.0:
				check(false, "never finished grinding (%d to go)" % sh.queued())
				step = 3
		3:
			if t - mark > 0.4:
				var rb = v0.rb
				var took := sh.queued() + int(sh.ground - float(v0.g0))
				check(not is_instance_valid(rb) and took >= int(v0.n) - 1 and int(v0.n) > 500, "a forearm and hand thrown in the top: taken in (%d of %d cubes)" % [took, int(v0.n)])
				sh.queue = {}
				# a whole leg: too big for the mincer
				var leg := _piece(v0.body, "thigh_r", mouth)
				v0.leg = leg
				v0.legn = _pieces_cubes(leg)
				mark = t
				step = 4
		4:
			if t - mark > 0.4:
				var leg = v0.leg
				check(is_instance_valid(leg) and sh.queued() == 0 and arena._say_text.contains("Too big"), "a whole leg (%d cubes) too big for the mincer: \"%s\"" % [int(v0.legn), arena._say_text])
				# the upgrades
				_look_at(VoxelShredder.AT + (VoxelShredder.TIERS[0].sign as Vector3) + Vector3(0, 1.2, 0))
				mark = t
				step = 5
		5:
			if t - mark > 0.2:
				var n := _near()
				check(n == "sign" and arena._use_label.text.contains("electric shredder"), "at its sign: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(sh.tier == 0, "not enough: no upgrade")
				arena.cash = 850
				arena.inv.add("stone", 300)
				arena.inv.add("gold", 60)
				_key(KEY_E)
				check(sh.tier == 1 and arena.cash == 650 and arena.inv.count("stone") == 0 and (sh._models[1] as Node3D).visible and not (sh._models[0] as Node3D).visible, "E: the electric shredder ($200, 300 stone)")
				mark = t
				step = 6
		6:
			if t - mark > 0.4:
				var leg = v0.leg
				check(not is_instance_valid(leg) and sh.queued() > 3000, "the shredder takes the leg (%d)" % sh.queued())
				sh.queue = {}
				check(sh.upgrade() and sh.tier == 2 and arena.cash == 50 and arena.inv.count("gold") == 0, "the industrial woodchipper ($600, 60 gold)")
				# a whole corpse put in the woodchipper's chute
				var c := _grunt(VoxelShredder.AT + Vector3(-1.3, 0, 0))
				c.sever("head")
				v0.corpse = c
				v0.cn = c.cubes_left()
				v0.g0 = sh.ground
				mark = t
				step = 7
		7:
			if t - mark > 0.4:
				var c = v0.corpse
				check(not is_instance_valid(c) or not arena.bodies.has(c), "a whole corpse into the woodchipper")
				var took2 := sh.queued() + int(sh.ground - float(v0.g0))
				check(took2 >= int(v0.cn) - 1, "all of it in (%d of %d cubes)" % [took2, int(v0.cn)])
				mark = t
				step = 8
		8:
			if sh.queued() == 0:
				check(t - mark < 6.0 and sh.bags >= 4, "the woodchipper made short work of it: %d bags in %.1f s" % [sh.bags, t - mark])
				_look_at(VoxelShredder.AT + (VoxelShredder.TIERS[2].pile as Vector3) + Vector3(0, 0.2, 0))
				mark = t
				step = 9
			elif t - mark > 20.0:
				check(false, "the corpse never got ground (%d)" % sh.queued())
				step = 9
				mark = t
		9:
			if t - mark > 0.2:
				var n := _near()
				var nb := sh.bags
				check(n == "bags" and arena._use_label.text.contains("take %d bag" % nb), "at the bags: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.inv.count("blood_bone") == nb and sh.bags == 0, "E: %d bags of blood and bone in the backpack" % nb)
				# a plant, the worm farm, the chickens
				var farm: VoxelFarm = arena.yard.farm
				arena.yard.ground.load_chunks({})
				var key := farm.spot_of(Vector3(10.1, 0, 28.1))
				arena.yard.till([key])
				arena.yard.ground.finish()
				farm.plants[key] = {"s": 0, "g": 0.2, "wet": 100.0, "dry": 0.0, "wilt": 0, "fed": 0}
				arena.inv.add("poo", 40)
				check(farm.feed_with() == "blood_bone" and farm.fertilise(key) and int(farm.plants[key].fed) == 1 and arena.inv.count("blood_bone") == nb - 1 and arena.inv.count("poo") == 40, "a bag fed to a plant (before the poo)")
				arena.inv.remove("poo", 40)
				farm.worms = {"n": 3, "food": 0.0, "eaten": 0.0, "cast": 0, "born": 0.0}
				arena.inv.from_data([["blood_bone", 2]])
				farm.service_wormery()
				check(absf(float(farm.worms.food) - 300.0) < 0.01, "two bags in the worm farm: %d scraps' worth" % int(float(farm.worms.food)))
				var ch: VoxelChickens = arena.yard.chickens
				ch.food = 0.0
				arena.inv.from_data([["blood_bone", 1]])
				ch.use("feeder")
				check(int(ch.food) == VoxelShredder.BAG_FEEDS and arena.inv.count("blood_bone") == 0, "a bag in the chickens' feeder: %d feeds" % int(ch.food))
				# ash: lost
				arena.inv.from_data([])
				arena.debris.take(VoxelBody.ASH, 10)
				check(arena.inv.total() == 0, "ash vacuumed up: nothing (it's lost)")
				v0.lying = arena.debris.lying()
				arena.debris.throw(Vector3(0, 1.0, -10), Vector3.FORWARD, VoxelBody.ASH, 30, 7)
				arena.debris.throw(Vector3(0, 1.0, -10), Vector3.FORWARD, VoxelBody.FLESH[0], 5, 8)
				# corpses out through the back door
				var d := _grunt(Vector3(12.7, 0, 22.2))
				d.sever("head")
				arena._keep_dead(d)
				var in_door := d.position.z > 22.0
				d.position = Vector3(8.0, 0, 22.2)
				arena._keep_dead(d)
				var walled := d.position.z <= VoxelArena.ARENA - 1.0
				d.position = Vector3(15.0, 0, 30.0)
				arena._keep_dead(d)
				var yard_ok := d.position.distance_to(Vector3(15.0, 0, 30.0)) < 0.01
				check(in_door and walled and yard_ok, "a corpse flying or carried goes out the back door into the yard (not through the wall)")
				mark = t
				step = 10
		10:
			if t - mark > 2.5:
				check(arena.debris.lying() - int(v0.lying) == 5, "ash crumbles away where it lands (5 meat cubes lie, 30 ash don't: %d)" % (arena.debris.lying() - int(v0.lying)))
				# saved and loaded
				sh.queue = {"meat": 1234}
				sh.bags = 3
				sh.points = 777.0
				arena.stash.save_path = "user://shredder_test_save.json"
				arena.stash.save()
				sh.from_data({})
				arena.stash.load_save()
				check(sh.tier == 2 and sh.bags == 3 and int(sh.queue.get("meat", 0)) == 1234 and int(sh.points) == 777 and (sh._models[2] as Node3D).visible, "the shredder saved and loaded (the woodchipper, 3 bags, what's in it)")
				DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shredder_test_save.json"))
				sh.queue = {}
				step = 99
		99:
			print("SHRED done %d passed, %d failed" % [passed, failed])
			return true
	return false

func _coop() -> bool:
	var n = arena.net
	var sh := _sh()
	if step > 0 and step < 99 and not n.linked and not (role == "host" and step == 9):
		check(false, "co-op: the link went before the end (step %d)" % step)
		step = 99
	elif step == 0 and (not n.linked or (role == "guest" and not n._got_world)):
		if role == "host" and not v0.has("prep"):
			v0.prep = true
			sh.from_data({})
		if Time.get_ticks_msec() > 60000:
			print("SHRED FAIL never linked (%s)" % n.status_text)
			print("SHRED done %d passed, %d failed" % [passed, failed + 1])
			return true
		return false
	if role == "host":
		match step:
			0:
				_clear()
				arena.frozen = true
				arena.inv.from_data([])
				mark = t
				step = 1
			1:
				if sh.queued() > 0 or sh.bags > 0:
					check(true, "co-op: the guest's gore in the host's shredder")
					mark = t
					step = 2
				elif t - mark > 30.0:
					check(false, "co-op: the guest's gore never came")
					step = 2
			2:
				# (a bag made and taken between two frames of this test counts: the ground total shows it was made)
				if sh.bags == 0 and sh.queued() == 0 and (v0.has("had") or sh.ground >= 4000):
					check(arena.inv.count("blood_bone") == 0, "co-op: the guest took the bag (not the host)")
					mark = t
					step = 3
				elif sh.bags > 0:
					v0.had = true
				elif t - mark > 40.0:
					check(false, "co-op: the bag was never taken")
					step = 3
			3:
				if sh.tier == 1:
					check(true, "co-op: the guest upgraded the host's machine")
					var b := _grunt(Vector3(2, 0, -8))
					var rb := _piece(b, "thigh_l", VoxelShredder.AT + Vector3(0, 1.4, 0))
					v0.rb = rb
					mark = t
					step = 4
				elif t - mark > 30.0:
					check(false, "co-op: no upgrade came")
					step = 4
			4:
				if t - mark > 0.5:
					check(not is_instance_valid(v0.rb) and sh.queued() > 0, "co-op: a leg thrown in in the host's game: taken in")
					mark = t
					step = 9
			9:
				if not n.linked or t - mark > 120.0:
					step = 99
			99:
				print("SHRED done %d passed, %d failed" % [passed, failed])
				return true
	else:
		match step:
			0:
				arena.inv.from_data([["meat", 4100]])
				arena.cash = 200
				arena.inv.add("stone", 300)
				check(sh.feed() == 4100 and arena.inv.count("meat") == 0, "co-op: the guest's gore out of their backpack")
				mark = t
				step = 1
			1:
				if sh.bags >= 1:
					check(true, "co-op: the host's shredder ground it: a bag on the guest's pile")
					sh.take_bags()
					mark = t
					step = 2
				elif t - mark > 40.0:
					check(false, "co-op: no bag showed (%d to go)" % sh.queued())
					step = 2
					mark = t
			2:
				if arena.inv.count("blood_bone") == 1:
					check(true, "co-op: the bag in the guest's backpack")
					check(sh.upgrade() and arena.cash == 0, "co-op: the guest paid for the upgrade")
					mark = t
					step = 3
				elif t - mark > 30.0:
					check(false, "co-op: the bag never came (%d)" % arena.inv.count("blood_bone"))
					step = 3
					mark = t
			3:
				if t - mark > 6.0:
					check(sh.tier == 1, "co-op: the guest's game shows the shredder")
					step = 99
			99:
				print("SHRED done %d passed, %d failed" % [passed, failed])
				return true
	return false
