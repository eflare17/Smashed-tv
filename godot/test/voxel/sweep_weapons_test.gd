extends SceneTree
## The bug sweep's weapon fixes, each checked (headless): a bat or hammer blow on a co-op guest freezes its game once
## (the host's copy doesn't send it back); the bat let go with something else out doesn't swing (a let-go swings at once);
## the flamethrower's stream goes past the pieces flying about; a black hole fired at a pillar or a wall close in front
## leaves this side of it, forward (first person and top-down); two gravity guns' holes share the debris well (one's
## burst, or a copy freed, doesn't switch off the other's; a copy freed lets go of what it was pulling); a sticky bomb
## dropped onto a pillar's top lands on it; the harpoon going into a piece mid-drag puts the body down and ends the tug.
## Prints "SWW ok/FAIL ..." and "SWW done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var passed := 0
var failed := 0
var _layer2: StaticBody3D

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("SWW %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _body(key: String, at: Vector3) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup(key, arena._cube_m(key), 1, arena._mat)
	b.position = at
	arena.bodies.append(b)
	b.hp = 1e9
	return b

# a gravity gun held by a made-up other player (top-down, the mouse on the floor at aim)
func _other_gun(at: Vector3, aim: Vector3) -> VoxelWeaponGravity:
	var s := VoxelShooter.new()
	s.arena = arena
	s.local = false
	s.top_down = true
	s.cam = Camera3D.new()
	arena.add_child(s.cam)
	s.player = CharacterBody3D.new()
	s.player.collision_layer = 0
	s.player.collision_mask = 0
	arena.add_child(s.player)
	s.player.global_position = at
	s.avatar = arena.avatar
	s._floor = aim
	var g: VoxelWeaponGravity = load(arena.MELEE["gravity"]).new()
	arena.add_child(g)
	g.setup(arena, s, "gravity")
	return g

# a fired hole's flight run out (a copy of its state): where it opens
func _flown(g: VoxelWeaponGravity) -> Vector3:
	var st: Dictionary = g._hst.duplicate()
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	var ex: Array[RID] = g.shooter.exclude()
	for i in 120:
		if VoxelWeaponGravity.hole_fly(st, 1.0 / 60.0, [], space, ex):
			break
	g._hs = ""
	g._hst = {}
	g._hole.visible = false
	g._hole_cd = 0.0
	return st.p

func _hit_stops() -> void:
	# a guest's bat or hammer blow: the host's copy doesn't send the freeze back (the guest's own swing froze it)
	var net: VoxelNet = arena.net
	var n0: int = net._out.size()
	net.linked = true
	net.role = "host"
	arena.me.local = false
	arena.melee["bat"].hit_stop(0.06, 0.05)
	arena.melee["hammer"].hit_stop(0.1, 0.04)
	var after_blunt: int = net._out.size()
	arena.melee["sword"].hit_stop(0.07, 0.05)
	var after_sword: int = net._out.size()
	arena.me.local = true
	net.linked = false
	net.role = ""
	net._out.resize(n0)
	check(after_blunt == n0, "the host's copy of a guest's bat / hammer doesn't send the freeze back (it froze once there)")
	check(after_sword == after_blunt + 1, "the host's copy of a guest's sword still sends it (only the host finds a cut)")

func _bat() -> void:
	var bat = arena.melee["bat"]
	var lo = arena.loadout
	var cur0: int = lo.current
	var bi: int = lo.index_of("bat")
	if bi >= 0 and lo.current != bi:
		lo.select(bi)
	bat.on_select()
	# let go with something else out (as both switch paths will set it, the new weapon before the bat's let-go): no swing
	arena.me.weapon = "bat"
	bat._cd = 0.0
	bat._mode = VoxelMeleeBat.IDLE
	bat.press(MOUSE_BUTTON_RIGHT)
	for k in 70:
		bat.step(1.0 / 60.0)
	var wound: bool = bat._mode == VoxelMeleeBat.CHARGE
	arena.me.weapon = "pistol"
	bat.release(MOUSE_BUTTON_RIGHT)
	bat.on_deselect()
	bat.step(1.0 / 60.0)
	check(wound and bat._mode == VoxelMeleeBat.IDLE and bat._cd == 0.0,
		"the bat let go wound up with the pistol out: no home run (mode %d, cooldown %.2f)" % [bat._mode, bat._cd])
	# the host's copy's way: a let-go and a switch in one poll still swing (as the guest's bat did in its let-go's frame)
	arena.me.weapon = "bat"
	bat._cd = 0.0
	bat._mode = VoxelMeleeBat.IDLE
	bat.press(MOUSE_BUTTON_RIGHT)
	for k in 40:
		bat.step(1.0 / 60.0)
	bat.release(MOUSE_BUTTON_RIGHT)
	bat.on_deselect()
	arena.me.weapon = "pistol"
	bat.step(1.0 / 60.0)
	check(bat._mode == VoxelMeleeBat.SWING and bat._hr,
		"let go, then switched before the next step: the home run swings at once, as on the guest (mode %d)" % bat._mode)
	for k in 90:
		bat.step(1.0 / 60.0)
	# a plain let-go swings it
	arena.me.weapon = "bat"
	bat._cd = 0.0
	bat._mode = VoxelMeleeBat.IDLE
	bat.on_select()
	bat.press(MOUSE_BUTTON_RIGHT)
	for k in 30:
		bat.step(1.0 / 60.0)
	bat.release(MOUSE_BUTTON_RIGHT)
	check(bat._mode == VoxelMeleeBat.SWING and bat._hr and bat._power > 0.3, "let go wound up: the home run swings (power %.2f)" % bat._power)
	for k in 90:
		bat.step(1.0 / 60.0)
	bat.on_deselect()
	if lo.current != cur0:
		lo.select(cur0)
	Engine.time_scale = 1.0

func _flames() -> void:
	var ft: VoxelWeaponFlamethrower = arena.melee["flamethrower"]
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	var through := ft._wall_d(space, PackedVector3Array([Vector3(0, 1, 12), Vector3(0, 1, 8)]))
	check(absf(through - 4.0) < 0.01, "the flamethrower's stream goes past a piece flying about (layer 2): %.2f m of 4" % through)
	var wall := ft._wall_d(space, PackedVector3Array([Vector3(8, 1, -5), Vector3(8, 1, -9)]))
	check(absf(wall - (3.0 - VoxelArena.PILLAR_HALF)) < 0.05, "... and still stops at a pillar (%.2f m)" % wall)

func _holes() -> void:
	var g: VoxelWeaponGravity = arena.melee["gravity"]
	var cam: Camera3D = arena.cam
	var cam0 := cam.global_transform
	# out in the open: from the mouth, as before
	cam.global_transform = Transform3D(Basis(), Vector3(0, 1.65, 3))
	g._hole_cd = 0.0
	g._hs = ""
	g.fire_hole()
	var from_mouth: bool = (g._hst.p as Vector3).distance_to(g._mouth_world()) < 0.01 and (g._hst.v as Vector3).normalized().dot(Vector3.FORWARD) > 0.9
	_flown(g)
	check(from_mouth, "a black hole out in the open: from the mouth, toward the crosshair")
	# half a metre from a pillar's face (the mouth's inside it)
	cam.global_transform = Transform3D(Basis(), Vector3(8, 1.65, -8 + VoxelArena.PILLAR_HALF + 0.5))
	g.fire_hole()
	var v: Vector3 = g._hst.v
	var p0: Vector3 = g._hst.p
	var at := _flown(g)
	var face := -8.0 + VoxelArena.PILLAR_HALF
	check(v.normalized().dot(Vector3.FORWARD) > 0.5 and p0.z > face and at.z > face - 0.01 and at.z < face + 0.6 and at.y < 2.5,
		"first person, 0.5 m from a pillar: the hole goes forward and opens this side of it (at %s, was flying %s)" % [str(at.snapped(Vector3.ONE * 0.01)), str(v.normalized().snapped(Vector3.ONE * 0.01))])
	# 0.4 m from the north wall
	cam.global_transform = Transform3D(Basis(), Vector3(0, 1.65, -VoxelArena.ARENA + 0.5 + 0.4))
	g.fire_hole()
	var at2 := _flown(g)
	check(at2.z > -VoxelArena.ARENA + 0.5 - 0.01 and at2.z < -VoxelArena.ARENA + 1.2,
		"first person, 0.4 m from the wall: it opens in front, this side of it (z %.2f)" % at2.z)
	cam.global_transform = cam0
	# top-down, Jared up against the north wall facing it
	var g2 := _other_gun(Vector3(0, 0, -VoxelArena.ARENA + 0.5 + 0.35), Vector3(0, 1.2, -30))
	g2.fire_hole()
	var at3 := _flown(g2)
	check(at3.z > -VoxelArena.ARENA + 0.5 - 0.01, "top-down against the wall: the hole opens this side of it, not out past it (z %.2f)" % at3.z)
	var s2: VoxelShooter = g2.shooter
	arena.remove_child(g2)
	g2.free()
	s2.cam.queue_free()
	s2.player.queue_free()

func _wells() -> void:
	var d = arena.debris
	var g: VoxelWeaponGravity = arena.melee["gravity"]
	var g2 := _other_gun(Vector3(-15, 0, 15), Vector3(-15, 1.2, 10))
	var a := Vector3(-15, 2, 15)
	var b := Vector3(15, 2, 15)
	g._hst = {"p": a}
	g._open()
	var first: bool = d.well == a
	g2._hst = {"p": b}
	g2._open()
	var second: bool = d.well == b
	g._well_on()
	var kept: bool = d.well == b
	g._burst()
	check(first and second and kept and d.well == b, "two holes open: the first one's burst leaves the second's well on")
	g2._burst()
	check(d.well == Vector3.INF, "... and the second's burst lets it go")
	g._open()
	g2._open()
	g2._burst()
	g._well_on()
	check(d.well == a, "the second hole bursts first: the first one's well comes back on")
	# a copy that never fired freed (the other player gone): the open hole keeps its well
	var g3 := _other_gun(Vector3(-15, 0, 15), Vector3(-15, 1.2, 10))
	arena.remove_child(g3)
	check(d.well == a, "the other player's gravity gun freed (they left): this game's open hole keeps its well")
	g3.free()
	# a copy freed with its own hole open: what it pulled falls again, and the other hole has the well back
	g2._open()
	var rb := RigidBody3D.new()
	rb.freeze = true
	arena.add_child(rb)
	rb.gravity_scale = 0.0
	g2._pulled_rb[rb.get_instance_id()] = rb
	var pb := _body("grunt", Vector3(-14, 0, 14))
	pb.air_v = Vector3(1, 2, 3)
	g2._pull_pos[pb.get_instance_id()] = pb.position
	var s2: VoxelShooter = g2.shooter
	arena.remove_child(g2)
	var freed_well: bool = d.well == Vector3.INF
	g._well_on()
	check(rb.gravity_scale == 1.0 and pb.air_v == Vector3.ZERO and freed_well and d.well == a,
		"a copy freed with its hole open: its pieces get their gravity back, its bodies fall, the other hole takes the well")
	g2.free()
	g._burst()
	check(d.well == Vector3.INF, "the last hole's burst: no well")
	rb.queue_free()
	arena.bodies.erase(pb)
	pb.queue_free()
	s2.cam.queue_free()
	s2.player.queue_free()
	Engine.time_scale = 1.0

func _bombs() -> void:
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	var ex: Array[RID] = []
	var st := VoxelWeaponGrenades.launch_state("sticky", Vector3(8, 4.2, -8), Vector3.ZERO)
	st.mode = "fall"
	for i in 200:
		VoxelWeaponGrenades.fly(st, 1.0 / 60.0, [], space, ex)
		if st.mode != "fall":
			break
	check(st.mode == "rest" and absf((st.p as Vector3).y - 3.5) < 0.02,
		"a sticky bomb dropped onto a pillar's top lands on it (y %.2f), not inside it at the floor" % (st.p as Vector3).y)
	var st2 := VoxelWeaponGrenades.launch_state("sticky", Vector3(3, 1.5, 3), Vector3.ZERO)
	st2.mode = "fall"
	for i in 200:
		VoxelWeaponGrenades.fly(st2, 1.0 / 60.0, [], space, ex)
		if st2.mode != "fall":
			break
	check(st2.mode == "rest" and absf((st2.p as Vector3).y) < 0.001, "... and onto the floor, on the floor (y %.3f)" % (st2.p as Vector3).y)

func _harpoon() -> void:
	var h: VoxelWeaponHarpoon = arena.melee["harpoon"]
	var b := _body("swarmer", Vector3(0, 0, -6))
	b.position.y = 0.16
	b.airborne = false
	h._mode = "body"
	h._body = b
	h._tug = 0.1
	h._p = b.global_position + Vector3(0, 1, 0)
	h._dir = Vector3.FORWARD
	var rb := RigidBody3D.new()
	rb.freeze = true
	arena.add_child(rb)
	rb.global_position = b.global_position + Vector3(0, 1, 0)
	h._into(rb)
	check(h._mode == "piece" and b.position.y == 0.0, "the harpoon into a piece mid-drag: the lifted body's back on the floor")
	h.press(MOUSE_BUTTON_LEFT)
	check(h._tug < 0.0 and h._mode == "reel", "... the tug cut short: a click lets go again (%s)" % h._mode)
	rb.queue_free()
	arena.bodies.erase(b)
	b.queue_free()

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	match step:
		0:
			arena.frozen = true
			for x in arena.bodies:
				x.queue_free()
			arena.bodies.clear()
			# a piece flying about where the stream goes (pieces are on layer 2)
			_layer2 = StaticBody3D.new()
			_layer2.collision_layer = 2
			_layer2.collision_mask = 0
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3.ONE
			cs.shape = bs
			_layer2.add_child(cs)
			arena.add_child(_layer2)
			_layer2.global_position = Vector3(0, 1, 10)
			t = 0.7
			step = 1
		1:
			_hit_stops()
			_bat()
			_flames()
			_holes()
			_wells()
			_bombs()
			_harpoon()
			_layer2.queue_free()
			step = 99
		99:
			print("SWW done %d passed, %d failed" % [passed, failed])
			return true
	return false
