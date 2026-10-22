extends SceneTree
## The enemy variety (Stage 11, VoxelKinds; headless): the three kinds' models (recoloured, the shield brute's shield);
## the charger crouches, runs at you, hurts and throws you, is dazed after, and stops dead at a pillar; the thrower lobs
## globs that hurt where they land, and with its throwing arm off comes in instead; the shield takes shots (no health
## lost, its cubes knocked out) and with it chipped away he's angrier. Prints "KINDS ok/FAIL ..." lines and
## "KINDS done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}
var b: VoxelBody

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("KINDS %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _body(key: String, p: Vector3) -> VoxelBody:
	var nb := VoxelBody.new()
	arena.add_child(nb)
	nb.setup(key, arena._cube_m(key), 1, arena._mat)
	nb.position = p
	nb.speed = VoxelKinds.speed_for(key, 1.5)
	nb.died.connect(arena._on_died)
	arena.bodies.append(nb)
	return nb

func _clear() -> void:
	for x in arena.bodies:
		x.queue_free()
	arena.bodies.clear()
	arena.kinds.clear()
	arena.player_hp = VoxelArena.HP_MAX
	arena.down_t = 0.0

func _put_player(p: Vector3) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO

func _cell_col(md: VoxelModel, part: String) -> int:
	var g := md.grid(part)
	for c in (g.cells as PackedInt32Array):
		if c != 0:
			return c
	return 0

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	match step:
		0:
			for k in ["charger", "thrower", "shielder"]:
				check(VoxelModel.has_model(k) and VoxelModel.get_model(k) != VoxelModel.get_model(String(VoxelModel.VARIANTS[k].base)),
					"%s: a model of its own (from the %s's)" % [k, VoxelModel.VARIANTS[k].base])
			check(_cell_col(VoxelModel.get_model("charger"), "torso") != _cell_col(VoxelModel.get_model("swarmer"), "torso"), "the charger recoloured")
			var sm := VoxelModel.get_model("shielder")
			check(sm.parts.has("shield") and sm.bone("shield") >= 0 and sm.bone_parent[sm.bone("shield")] == sm.bone("forearm_l"),
				"the shield brute: a shield part on a bone of its own under the left forearm")
			_clear()
			_put_player(Vector3(0, 0, 6))
			b = _body("shielder", Vector3(0, 0, 0))
			check(b.has_shield() and int(b.parts.shield.start) > 2000, "his shield: %d cubes, up" % int(b.parts.shield.start))
			arena.frozen = true
			mark = t
			step = 1
		1:
			if t - mark < 0.3:
				return false
			# a shot at his chest from the front: the shield takes it
			b.yaw = 0.0
			b.animate(0.016, false)
			var hp0 := b.hp
			var left0 := int(b.parts.shield.left)
			var eye := Vector3(0, 1.4, 6)
			var hits: Array = arena.fire(eye, (Vector3(0, 1.3, 0) - eye).normalized(), 1, 0.0, 1.9)
			check(hits.size() == 1 and String(hits[0].part) == "shield" and is_equal_approx(b.hp, hp0) and int(b.parts.shield.left) < left0,
				"a shot from the front: the shield's (%s), cubes off it (%d), no health lost" % [String(hits[0].part) if hits.size() > 0 else "-", left0 - int(b.parts.shield.left)])
			var back := Vector3(0, 1.4, -6)
			var hits2: Array = arena.fire(back, (Vector3(0, 1.3, 0) - back).normalized(), 1, 0.0, 1.9)
			check(hits2.size() == 1 and String(hits2[0].part) != "shield", "from behind: him (%s)" % (String(hits2[0].part) if hits2.size() > 0 else "-"))
			# chipped away: angrier
			var tries := 0
			while b.has_shield() and tries < 400:
				var aim := Vector3(randf_range(-0.6, 0.9), randf_range(0.5, 1.9), 0)
				arena.fire(eye, (aim - eye).normalized(), 1, 0.0, 3.0)
				tries += 1
			arena.frozen = false
			var mv: Vector3 = arena.kinds.step(b, Vector3(0, 0, 6), 0, Vector3(0, 0, 6), 6.0, Vector3(0, 0, 1), true, 0.016)
			check(not b.has_shield() and mv.length() > 1.2, "the shield shot away (%d shots): he's angrier (%.1fx)" % [tries, mv.length()])
			arena.frozen = false
			_clear()
			_put_player(Vector3(0, 0, 6))
			b = _body("charger", Vector3(0, 0, -1))
			v.hp0 = arena.player_hp
			v.saw_windup = false
			v.saw_charge = false
			mark = t
			step = 2
		2:
			if b.act == VoxelBody.ACT_WINDUP:
				v.saw_windup = true
			if b.act == VoxelBody.ACT_CHARGE:
				v.saw_charge = true
			if arena.player_hp <= float(v.hp0) - 10.0:
				check(v.saw_windup and v.saw_charge and arena.kinds.charged >= 1, "the charger: crouched, then ran at you")
				check(float(v.hp0) - arena.player_hp >= VoxelKinds.CHARGE_HURT - 1.0 and arena._dash_t > 0.0,
					"... it hit: %.0f health, you thrown back" % (float(v.hp0) - arena.player_hp))
				mark = t
				step = 3
			elif t - mark > 6.0:
				check(false, "the charger never hit (act %d, at %s)" % [b.act, str(b.position)])
				step = 3
		3:
			if b.act == VoxelBody.ACT_DAZE:
				check(true, "... and is dazed after")
			if t - mark > 0.3:
				check(b.act == VoxelBody.ACT_DAZE or b.act_cool > 0.0, "... and is dazed after")
				_clear()
				# a pillar between: it runs into it
				_put_player(Vector3(8, 0, -14.5))
				b = _body("charger", Vector3(8, 0, -3.0))
				mark = t
				step = 4
		4:
			if b.act == VoxelBody.ACT_DAZE:
				check(b.act_t > VoxelKinds.DAZE and b.position.z > -8.0 + VoxelArena.PILLAR_HALF,
					"a pillar in the way: it stops dead against it, dazed longer (%.1f s)" % b.act_t)
				_clear()
				_put_player(Vector3(0, 0, 6))
				b = _body("thrower", Vector3(0, 0, -3))
				v.hp0 = arena.player_hp
				mark = t
				step = 5
			elif t - mark > 6.0:
				check(false, "the charger and the pillar (act %d, at %s)" % [b.act, str(b.position)])
				step = 99
		5:
			if arena.player_hp < float(v.hp0) - 2.0:
				check(arena.kinds.thrown >= 1, "the thrower: a glob thrown (%d)" % arena.kinds.thrown)
				check(true, "... it landed on you: %.0f health" % (float(v.hp0) - arena.player_hp))
				var d0: float = Vector2(b.position.x, b.position.z).distance_to(Vector2(0, 6))
				check(d0 > 4.5, "... from a distance (%.1f m)" % d0)
				# its throwing arm off: it comes in
				b.sever("forearm_r")
				v.thrown = arena.kinds.thrown
				v.d0 = d0
				mark = t
				step = 6
			elif t - mark > 8.0:
				check(false, "the thrower never hit (thrown %d)" % arena.kinds.thrown)
				step = 99
		6:
			if t - mark > 4.0:
				var d1: float = Vector2(b.position.x, b.position.z).distance_to(Vector2(0, 6))
				check(not VoxelKinds.can_throw(b) and arena.kinds.thrown == int(v.thrown) and d1 < float(v.d0) - 4.0,
					"its throwing arm off: no more globs, it came in (%.1f m)" % d1)
				step = 99
		99:
			print("KINDS done %d passed, %d failed" % [passed, failed])
			return true
	return false
