class_name VoxelCarouselTumble
extends Node3D
## Someone thrown off the Carousel when it's stopped dead (the owner, 31 Oct: "they hit the wall then get up and walk
## away"): the rider goes on the way the ride was taking them, as the crowd's ragdoll (SkRagdoll), tumbling off the
## platform into whatever's there (the ride's iron fence); a thump when they hit it. Then the way the crowd gets up
## after a fall: lying there a moment, up again, stood swaying with stars going round their head, and off they walk,
## away from the ride, wobbly at first. Owned by the St Kilda session.

const DOWN := 2.5               # s lying there
const UP := 0.9                 # s getting up
const DIZZY := 2.5              # s stood there, swaying
const WALK := 9.0               # s walking off
const SPEED := 1.1              # m/s
const THUMP := 3.5              # m/s lost in one step: they've hit something

var look: Array = []            # [shirt, pants, hair, skin] (as the crowd's)
var custom := Color()
var size := 0.85
var stage := "flying"           # flying, down, up, dizzy, walk, done
var at := Vector3.ZERO          # their feet
var head_dir := Vector3.FORWARD # lying: which way their head is
var yaw := 0.0
var away := Vector3.FORWARD     # which way they walk off
var hits := 0                   # (thumps heard: tests)
var walk_back := false          # walk off back toward the ride (thrown a long way, into a wall: not on into it)
var _t := 0.0
var _rag: SkRagdoll
var _last_v := 0.0
var _mm: MultiMesh
var _stars: Node3D

## Throw them from `xf` (feet, facing -z) at `v` (m/s), the ride's middle at `mid` (they walk off away from it).
func start(xf: Transform3D, custom_: Color, v: Vector3, mid: Vector3, lift := 2.2, spin := 6.0) -> void:
	custom = custom_
	var shirt := int(floor(fposmod(custom.r, 0.5) * 16.0 + 0.01))
	look = [shirt, int(floor(custom.b * 8.0)), int(floor(fposmod(custom.b * 8.0, 1.0) * 8.0 + 0.01)), custom.a]
	var flat := Vector3(v.x, 0, v.z)
	_rag = SkRagdoll.new()
	_rag.name = "SkRagdoll"
	add_child(_rag)
	_rag.setup(xf, look, flat, lift, spin)
	for p in _rag.get_children():
		if p is RigidBody3D:
			(p as RigidBody3D).continuous_cd = true     # (fast: into a wall, not through it)
			if flat.length() > 12.0:
				(p as RigidBody3D).linear_velocity = flat + Vector3(0, lift, 0)   # (all of them together: a long way, not torn apart)
	_rag.done.connect(_landed.bind(mid))
	# them stood up again: one of the crowd, on their own (hidden till they've landed)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = SkCrowd.person_mesh()
	_mm.instance_count = 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = SkCrowd.material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_put(Transform3D(Basis().scaled(Vector3.ONE * 0.001), xf.origin), false)
	_stars = Node3D.new()
	for k in 3:
		var s := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.09, 0.09, 0.09)
		s.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#ffe14a")
		m.emission_enabled = true
		m.emission = Color("#ffcf1a")
		s.material_override = m
		_stars.add_child(s)
	_stars.visible = false
	add_child(_stars)

# the one of them, in one go (see SkCrowd: the compatibility renderer and custom data)
func _put(xf: Transform3D, walking: bool) -> void:
	var buf := PackedFloat32Array()
	buf.resize(20)
	SkCrowd.put(buf, 0, xf)
	for k in 4:
		buf[12 + k] = 1.0
	var c := custom
	c.r = (0.5 if walking else 0.0) + float(look[0]) / 16.0
	for k in 4:
		buf[16 + k] = c[k]
	_mm.buffer = buf

func _landed(where: Vector3, dir: Vector3, mid: Vector3) -> void:
	_rag = null
	head_dir = dir
	at = where - dir * 1.1 * size
	at.y = 0.0
	yaw = atan2(dir.x, dir.z)
	var off := at - mid
	off.y = 0.0
	away = off.normalized() if off.length() > 0.1 else Vector3.FORWARD
	if walk_back:
		away = -away
	stage = "down"
	_t = 0.0

func _physics_process(_dt: float) -> void:
	if _rag == null or not is_instance_valid(_rag):
		return
	var body := _rag._parts.get("body") as RigidBody3D
	if body == null:
		return
	var sp := body.linear_velocity.length()
	if _last_v - sp > THUMP:
		hits += 1
		var arena = get_tree().root.get_node_or_null("VoxelArena")
		if arena and arena.sound:
			arena.sound.play("thwack" if hits == 1 else "hammer_thud_0", body.global_position, -2.0 if hits == 1 else -8.0, randf_range(0.8, 1.0))
	_last_v = sp

func _process(dt: float) -> void:
	if stage == "flying" or stage == "done":
		return
	_t += dt
	match stage:
		"down", "up":
			var tip := 1.0
			if stage == "up":
				tip = 1.0 - smoothstep(0.0, 1.0, _t / UP)
			var axis := Vector3.UP.cross(head_dir).normalized()
			_put(Transform3D((Basis(axis, tip * PI * 0.5) * Basis(Vector3.UP, yaw)).scaled(Vector3.ONE * size), at + Vector3(0, 0.13 * tip, 0)), false)
			if stage == "down" and _t > DOWN:
				stage = "up"
				_t = 0.0
			elif stage == "up" and _t > UP:
				stage = "dizzy"
				_t = 0.0
				_stars.visible = true
		"dizzy", "walk":
			var wob := 1.0 if stage == "dizzy" else maxf(0.0, 1.0 - _t / 4.0)
			var want := atan2(-away.x, -away.z)              # (the crowd's people face -z, as SkCrowd walks them)
			if stage == "dizzy":
				yaw = lerp_angle(yaw, want, dt * 1.5)
			else:
				yaw = want + sin(_t * 2.3) * 0.5 * wob
				var dir := Vector3(-sin(yaw), 0, -cos(yaw))
				at += dir * SPEED * (0.6 + 0.4 * (1.0 - wob)) * dt
			var lean := Basis(Vector3(cos(yaw), 0, -sin(yaw)), sin(_t * 3.1) * 0.12 * wob) * Basis(Vector3.FORWARD, sin(_t * 2.2) * 0.1 * wob)
			_put(Transform3D((lean * Basis(Vector3.UP, yaw)).scaled(Vector3.ONE * size), at), stage == "walk")
			_stars.visible = wob > 0.05
			_stars.global_position = at + Vector3(0, 1.85 * size, 0)
			for k in _stars.get_child_count():
				var a := _t * 4.0 + k * TAU / 3.0
				(_stars.get_child(k) as Node3D).position = Vector3(cos(a) * 0.22, sin(_t * 6.0 + k) * 0.03, sin(a) * 0.22)
				(_stars.get_child(k) as Node3D).rotation = Vector3(0, a * 2.0, PI / 4.0)
			if stage == "dizzy" and _t > DIZZY:
				stage = "walk"
				_t = 0.0
			elif stage == "walk" and _t > WALK:
				stage = "done"
				_put(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at), false)
