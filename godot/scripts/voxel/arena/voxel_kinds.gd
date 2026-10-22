class_name VoxelKinds
extends Node3D
## The arena's enemy variety (Stage 11 of the overnight plan, 22 Oct: "a fast charger, a ranged thrower and a tanky
## shield brute"). Each is an old model recoloured (VoxelModel.VARIANTS), with a move of its own run here, on the host
## (or alone); the guest sees it through the snapshots (VoxelBody.act_k) and the thrown globs (net event "gl").
##
## - CHARGER (a red swarmer): from 3-10 m away it crouches (WINDUP s, the moment to shoot it), then runs headlong the
##   way it was facing at CHARGE_V for up to CHARGE_T s: whoever it runs into is hurt CHARGE_HURT and thrown back; a
##   pillar stops it dead. Dazed after (DAZE s, PILLAR_DAZE into a pillar): free hits. No charging on a lost leg.
## - THROWER (a green grunt): keeps 6-11 m off, sidestepping; every THROW_EVERY s it draws its right arm back (AIM s)
##   and lobs a glob of rot in an arc at you: GLOB_HURT where it lands (GLOB_R m round), a green splash either way.
##   With its throwing arm shot off (or hanging) it comes in to hit you like a grunt.
## - SHIELDER (a blue-steel brute): slow, a steel shield held up in front (a carvable part: shots knock its cubes out
##   with a clang and sparks, not his health; chip it away, shoot through the holes or go round it). Under 40% of it left, or the arm
##   holding it off, he's a brute, angrier (faster).
## Owned by the voxel session.

const CHARGE_RANGE := Vector2(3.0, 10.0)
const WINDUP := 0.6
const CHARGE_V := 11.0
const CHARGE_T := 0.9
const CHARGE_HURT := 15.0
const DAZE := 1.0
const PILLAR_DAZE := 2.2
const THROW_BAND := Vector2(6.0, 11.0)
const THROW_EVERY := Vector2(2.4, 3.6)
const AIM := 0.7
const THROW_FOLLOW := 0.3
const GLOB_HURT := 10.0
const GLOB_R := 1.1
const GLOB_G := 9.8
const SHIELD_SPEED := 0.6       # (of a brute's)
const ANGRY := 1.5              # a shielder with his shield gone: this much faster

var arena: Node3D
var globs: Array = []           # [{mi: MeshInstance3D, p, v, t, real: bool (the host's / alone: it hurts)}]
var thrown := 0                 # (tests) globs thrown here
var charged := 0                # (tests) charges started
var _glob_mesh: BoxMesh
var _glob_mat: StandardMaterial3D

func _ready() -> void:
	_glob_mesh = BoxMesh.new()
	_glob_mesh.size = Vector3(0.16, 0.16, 0.16)
	_glob_mat = StandardMaterial3D.new()
	_glob_mat.albedo_color = Color(0.32, 0.55, 0.12)
	_glob_mat.emission_enabled = true
	_glob_mat.emission = Color(0.25, 0.5, 0.05)
	_glob_mat.emission_energy_multiplier = 0.6
	_glob_mat.roughness = 0.3

## A new body's speed for its kind (spawn).
static func speed_for(key: String, base: float) -> float:
	match key:
		"charger":
			return base * 1.3
		"shielder":
			return base * 0.75 * SHIELD_SPEED
	return base

## The walk (mv) a kind of its own wants this frame, and its move started, carried on, finished. b on its way to
## target pp (to: flat, d its length; ti which player); can: free to act (not stunned, burning, frozen, all down).
## Returns mv (changed or not).
func step(b: VoxelBody, pp: Vector3, ti: int, to: Vector3, d: float, mv: Vector3, can: bool, dt: float) -> Vector3:
	if arena.frozen:
		return mv                   # (F4: everything held where it is, mid-move too)
	b.act_cool = maxf(0.0, b.act_cool - dt)
	match b.key:
		"charger":
			return _charger(b, pp, ti, to, d, mv, can, dt)
		"thrower":
			return _thrower(b, pp, ti, to, d, mv, can, dt)
		"shielder":
			if not b.has_shield():
				return mv * ANGRY
	return mv

func _stop(b: VoxelBody, cool: float) -> void:
	b.act = 0
	b.act_p = 0.0
	b.act_t = 0.0
	b.act_cool = cool

func _charger(b: VoxelBody, pp: Vector3, ti: int, to: Vector3, d: float, mv: Vector3, can: bool, dt: float) -> Vector3:
	if not can and b.act != VoxelBody.ACT_DAZE:
		if b.act != 0:
			_stop(b, 1.5)         # (knocked over, set alight, frozen mid-run: it's off)
		return mv
	match b.act:
		0:
			if b.act_cool <= 0.0 and b.legs_lost() == 0 and d >= CHARGE_RANGE.x and d <= CHARGE_RANGE.y:
				b.act = VoxelBody.ACT_WINDUP
				b.act_t = WINDUP
				charged += 1
				arena.sound.play("swoosh_heavy", b.position + Vector3.UP, -6.0, 0.7)
				return Vector3.ZERO
			return mv
		VoxelBody.ACT_WINDUP:
			b.act_t -= dt
			b.act_p = 1.0 - b.act_t / WINDUP
			if b.act_t <= 0.0:
				b.act = VoxelBody.ACT_CHARGE
				b.act_t = CHARGE_T
				b.act_p = 0.0
				b.act_dir = to.normalized() if d > 0.01 else Vector3(sin(b.yaw), 0, cos(b.yaw))
				b.yaw = atan2(b.act_dir.x, b.act_dir.z)
				arena.sound.play("swoosh_bat", b.position + Vector3.UP, -2.0, 0.8)
			return Vector3.ZERO     # (crouched: standing, turning to face you)
		VoxelBody.ACT_CHARGE:
			b.act_t -= dt
			b.act_p = 1.0 - b.act_t / CHARGE_T
			b.yaw = atan2(b.act_dir.x, b.act_dir.z)
			var nxt := b.position + b.act_dir * CHARGE_V * dt
			if VoxelArena.out_of_pillars(nxt, 0.35) != nxt or absf(nxt.x) > VoxelArena.ARENA - 1.0 or absf(nxt.z) > VoxelArena.ARENA - 1.0:
				# into a pillar or the wall: stopped dead, seeing stars
				b.act = VoxelBody.ACT_DAZE
				b.act_t = PILLAR_DAZE
				b.act_p = 0.0
				b.flinch = 1.0
				b.flinch_head = true
				b.hurt(8.0)
				arena.sound.play("slam", b.position + Vector3.UP, -2.0)
				return Vector3.ZERO
			if d < 0.95:
				arena._hurt_target(ti, CHARGE_HURT)
				arena.shove_target(ti, b.act_dir * 9.0, 0.22)
				arena.sound.play("thwack", pp + Vector3.UP, 0.0)
				b.act = VoxelBody.ACT_DAZE
				b.act_t = DAZE
				b.act_p = 0.0
				return Vector3.ZERO
			if b.act_t <= 0.0:
				b.act = VoxelBody.ACT_DAZE
				b.act_t = DAZE
				b.act_p = 0.0
				return Vector3.ZERO
			return b.act_dir * CHARGE_V * b.move_factor()
		VoxelBody.ACT_DAZE:
			b.act_t -= dt
			b.act_p = clampf(1.0 - b.act_t / PILLAR_DAZE, 0.0, 1.0)
			if b.act_t <= 0.0:
				_stop(b, randf_range(2.5, 4.0))
			return Vector3.ZERO
	return mv

## The thrower's right arm whole and on (it throws with it).
static func can_throw(b: VoxelBody) -> bool:
	for n in ["arm_r", "forearm_r", "hand_r"]:
		if not b.parts.has(n) or b.parts[n].gone or b.loose.has(n):
			return false
	return true

func _thrower(b: VoxelBody, pp: Vector3, ti: int, to: Vector3, d: float, mv: Vector3, can: bool, dt: float) -> Vector3:
	if not can_throw(b):
		if b.act != 0:
			_stop(b, 0.0)
		return mv                   # (no arm: it comes in to hit you)
	if not can:
		if b.act != 0:
			_stop(b, 1.0)
		return mv
	match b.act:
		VoxelBody.ACT_AIM:
			b.act_t -= dt
			b.act_p = 1.0 - b.act_t / AIM
			if b.act_t <= 0.0:
				throw_from(b, pp + Vector3(randf_range(-0.4, 0.4), 0.9, randf_range(-0.4, 0.4)))
				b.act = VoxelBody.ACT_THROW
				b.act_t = THROW_FOLLOW
				b.act_p = 0.0
			return Vector3.ZERO
		VoxelBody.ACT_THROW:
			b.act_t -= dt
			b.act_p = 1.0 - b.act_t / THROW_FOLLOW
			if b.act_t <= 0.0:
				_stop(b, randf_range(THROW_EVERY.x, THROW_EVERY.y))
			return Vector3.ZERO
	if b.act_cool <= 0.0 and d >= 3.5 and d <= 16.0:
		b.act = VoxelBody.ACT_AIM
		b.act_t = AIM
		b.act_p = 0.0
		return Vector3.ZERO
	# keeping its distance: in from far off, back when you come close, sidestepping between
	if d < 0.01:
		return mv
	var sp := b.speed * b.move_factor()
	if d > THROW_BAND.y:
		return mv
	if d < THROW_BAND.x:
		return -to / d * sp * 0.8
	var side := Vector3(-to.z, 0, to.x) / d * (1.0 if b.get_instance_id() % 2 == 0 else -1.0)
	return side * sp * 0.5

## A glob thrown from b's right hand to land at at (an arc of a time by how far).
func throw_from(b: VoxelBody, at: Vector3) -> void:
	var hb := b.model.bone("hand_r")
	var from := b.global_position + Vector3.UP * b.height * 0.8
	if hb >= 0:
		from = b.skeleton.global_transform * b.skeleton.get_bone_global_pose(hb).origin + Vector3.UP * 0.15
	var flat := Vector2(at.x - from.x, at.z - from.z).length()
	var tt := clampf(flat / 11.0, 0.45, 1.3)
	var v := (at - from) / tt + Vector3.UP * 0.5 * GLOB_G * tt
	launch(from, v, true)
	arena.sound.play("swoosh_heavy", from, -4.0, 1.2)
	if arena.net and arena.net.linked and arena.net.role == "host":
		arena.net.send_glob(from, v)

## A glob in flight from p at v (real: this game's, it hurts; false: the guest's copy of the host's, looks only).
func launch(p: Vector3, v: Vector3, real: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _glob_mesh
	mi.material_override = _glob_mat
	add_child(mi)
	mi.global_position = p
	globs.append({"mi": mi, "p": p, "v": v, "t": 0.0, "real": real})
	if real:
		thrown += 1

## The globs flying, landing, splashing (both games; only the real ones hurt).
func step_globs(dt: float) -> void:
	for i in range(globs.size() - 1, -1, -1):
		var g: Dictionary = globs[i]
		var p0: Vector3 = g.p
		g.v = (g.v as Vector3) + Vector3.DOWN * GLOB_G * dt
		g.p = p0 + (g.v as Vector3) * dt
		g.t = float(g.t) + dt
		var mi: MeshInstance3D = g.mi
		mi.global_position = g.p
		mi.rotation += Vector3(7.0, 5.0, 3.0) * dt
		var p: Vector3 = g.p
		var hit := p.y <= 0.05 or float(g.t) > 4.0 or VoxelArena.out_of_pillars(p, 0.05) != p
		# (a player it flies into: splat there)
		if not hit and bool(g.real):
			for tp in arena.net.targets():
				if (tp as Vector3 + Vector3.UP * 0.9).distance_to(p) < 0.55:
					hit = true
		if hit:
			_splat(p, bool(g.real))
			mi.queue_free()
			globs.remove_at(i)

func _splat(p: Vector3, real: bool) -> void:
	var bits := []
	for k in 26:
		var c := Color(0.3, 0.5, 0.1).lerp(Color(0.55, 0.75, 0.2), randf())
		bits.append({"pos": p + Vector3(randf_range(-0.07, 0.07), randf_range(0.0, 0.1), randf_range(-0.07, 0.07)), "col": c})
	arena.debris.burst(bits, Vector3.UP, 2.2)
	arena.sound.play("hit_flesh", p, -2.0, 0.7)
	if not real:
		return
	var targets: Array = arena.net.targets()
	for j in targets.size():
		var tp: Vector3 = targets[j] + Vector3.UP * 0.9
		var dd := tp.distance_to(p)
		if dd < GLOB_R:
			arena._hurt_target(j, GLOB_HURT * (1.0 - 0.5 * dd / GLOB_R))

func clear() -> void:
	for g in globs:
		(g.mi as Node).queue_free()
	globs.clear()
