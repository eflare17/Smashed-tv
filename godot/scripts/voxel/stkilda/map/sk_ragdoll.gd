# (Copied from stkilda-godot scripts/town/ragdoll.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkRagdoll
extends Node3D
## Someone from the crowd knocked flying (the owner: "fall more dramatically, with a ragdoll"): the blocky townsperson
## (SkCrowd.person_mesh) as six loose bodies (body, head, two arms, two legs) pinned together at the neck, shoulders and
## hips, thrown by the knock and left to tumble and flop on the ground. When they've settled (or after a few seconds)
## `done` says where they lie, and which way their head is, for the crowd to get them back up. They land on the
## world's solid things but not on each other, you, or the car.

signal done(at: Vector3, head_dir: Vector3)

const LIFE := 4.5                        # s at most
const SETTLE := 0.8                      # s lying still before they get up
const PANTS := [Color(0.11, 0.14, 0.24), Color(0.06, 0.06, 0.07), Color(0.45, 0.4, 0.3), Color(0.3, 0.33, 0.38), Color(0.24, 0.3, 0.45), Color(0.55, 0.52, 0.48)]
const HAIR := [Color(0.06, 0.04, 0.03), Color(0.22, 0.12, 0.06), Color(0.65, 0.5, 0.25), Color(0.45, 0.18, 0.06), Color(0.6, 0.6, 0.58)]
const SHIRTS := [Color(0.78, 0.19, 0.17), Color(0.18, 0.37, 0.7), Color(0.95, 0.94, 0.92), Color(0.11, 0.12, 0.13), Color(0.88, 0.69, 0.16), Color(0.25, 0.54, 0.29), Color(0.88, 0.48, 0.66), Color(0.42, 0.31, 0.64)]

var _parts := {}
var _t := 0.0
var _still := 0.0

## Build them where `xf` stands (feet at its origin, facing -z), dressed as `look` [shirt, pants, hair, skin 0..1],
## and throw them: `push` (m/s, which way and how hard), `lift` (m/s up), `spin` (how much they tumble).
func setup(xf: Transform3D, look: Array, push: Vector3, lift: float, spin: float) -> void:
	var skin := Color(0.78, 0.55, 0.42).lerp(Color(0.32, 0.2, 0.13), float(look[3]) * float(look[3]))
	var shirt: Color = SHIRTS[clampi(look[0], 0, SHIRTS.size() - 1)]
	var pants: Color = PANTS[clampi(look[1], 0, PANTS.size() - 1)]
	var hair: Color = HAIR[clampi(look[2], 0, HAIR.size() - 1)]
	var body := _part("Body", xf, Vector3(0, 1.15, 0), Vector3(0.42, 0.62, 0.24), 3.0, [[Vector3.ZERO, Vector3(0.42, 0.62, 0.24), shirt]])
	var head := _part("Head", xf, Vector3(0, 1.64, 0), Vector3(0.26, 0.3, 0.26), 1.0, [[Vector3(0, 0, 0), Vector3(0.26, 0.26, 0.26), skin],
		[Vector3(0, 0.15, 0.02), Vector3(0.28, 0.06, 0.28), hair], [Vector3(0, 0.02, 0.13), Vector3(0.28, 0.24, 0.04), hair],
		[Vector3(0, -0.14, 0), Vector3(0.12, 0.08, 0.12), skin]])
	var arms := []
	var legs := []
	for x in [-0.28, 0.28]:
		arms.append(_part("Arm", xf, Vector3(x, 1.12, 0), Vector3(0.13, 0.66, 0.15), 0.6, [[Vector3(0, 0.21, 0), Vector3(0.13, 0.24, 0.15), shirt],
			[Vector3(0, -0.12, 0), Vector3(0.11, 0.42, 0.12), skin]]))
	for x in [-0.1, 0.1]:
		legs.append(_part("Leg", xf, Vector3(x, 0.47, 0), Vector3(0.17, 0.86, 0.2), 1.2, [[Vector3(0, 0.04, 0), Vector3(0.16, 0.78, 0.18), pants],
			[Vector3(0, -0.39, -0.03), Vector3(0.17, 0.08, 0.26), Color(0.05, 0.05, 0.06)]]))
	_pin(body, head, xf * Vector3(0, 1.48, 0))
	for k in 2:
		_pin(body, arms[k], xf * Vector3(-0.24 if k == 0 else 0.24, 1.42, 0))
		_pin(body, legs[k], xf * Vector3(-0.1 if k == 0 else 0.1, 0.86, 0))
	# the knock: the top half goes with it hardest, the feet get left behind (so they go over, not just slide)
	var up := Vector3(0, lift, 0)
	var turn := Vector3(push.z, 0, -push.x).normalized() * spin
	body.linear_velocity = push + up
	head.linear_velocity = push * 1.15 + up * 1.1
	for a in arms:
		(a as RigidBody3D).linear_velocity = push * 1.1 + up + Vector3(randf_range(-1, 1), randf_range(0, 1.5), randf_range(-1, 1))
	for l in legs:
		(l as RigidBody3D).linear_velocity = push * 0.35 + up * 0.8
	body.angular_velocity = turn + Vector3(0, randf_range(-2, 2), 0)
	_parts = {"body": body, "head": head}

func _part(nm: String, xf: Transform3D, at: Vector3, size: Vector3, mass: float, boxes: Array) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = nm
	b.mass = mass
	b.collision_layer = 0                 # (nothing bumps into them, not even each other)
	b.collision_mask = SkData.LAYER_WORLD
	b.angular_damp = 1.2
	b.linear_damp = 0.2
	b.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.15
	b.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	for bx in boxes:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bx[1]
		mi.mesh = bm
		mi.position = bx[0]
		var m := StandardMaterial3D.new()
		m.albedo_color = bx[2]
		m.roughness = 0.85
		mi.material_override = m
		b.add_child(mi)
	add_child(b)
	b.global_transform = Transform3D(xf.basis.orthonormalized(), xf * at)
	return b

func _pin(a: RigidBody3D, b: RigidBody3D, at: Vector3) -> void:
	var j := PinJoint3D.new()
	add_child(j)
	j.global_position = at
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	j.set_param(PinJoint3D.PARAM_BIAS, 0.6)
	j.set_param(PinJoint3D.PARAM_DAMPING, 1.0)

func _physics_process(dt: float) -> void:
	_t += dt
	var body: RigidBody3D = _parts.get("body")
	if body == null:
		return
	if body.linear_velocity.length() < 0.35 and _t > 0.8:
		_still += dt
	else:
		_still = 0.0
	if _still > SETTLE or _t > LIFE:
		var head: RigidBody3D = _parts.head
		var at := body.global_position
		var dir := head.global_position - at
		dir.y = 0.0
		done.emit(Vector3(at.x, 0, at.z), dir.normalized() if dir.length() > 0.05 else Vector3.FORWARD)
		set_physics_process(false)
		queue_free()
