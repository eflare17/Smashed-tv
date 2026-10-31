class_name VoxelCarouselTumble
extends Node3D
## Someone thrown off the Carousel when it's stopped dead (the owner, 31 Oct: "they hit the wall then get up and walk
## away"): the rider goes on the way the ride was taking them, as the crowd's ragdoll (SkRagdoll), tumbling off the
## platform into whatever's there (the ride's iron fence); a thump when they hit it. Then the way the crowd gets up
## after a fall: lying there a moment, up again, stood swaying with stars going round their head, and off they walk,
## away from the ride, wobbly at first. Or (hang_at set: thrown at a window of Luna Palace, the owner: "his leg gets
## caught on the window sill and he gets stuck hanging upside down"): into the wall above it, upside down, stuck there
## a moment, then sliding down it till a foot catches on the sill ("hit above the window sill then kinda slide down"),
## left hanging upside down below it, swinging a little, arms waving. Owned by the St Kilda session.

const DOWN := 2.5               # s lying there
const UP := 0.9                 # s getting up
const DIZZY := 2.5              # s stood there, swaying
const WALK := 9.0               # s walking off
const SPEED := 1.1              # m/s
const THUMP := 3.5              # m/s lost in one step: they've hit something

var look: Array = []            # [shirt, pants, hair, skin] (as the crowd's)
var custom := Color()
var size := 0.85
var stage := "flying"           # flying, down, up, dizzy, walk, done; or (at a window) flying, splat, slide, hang
var at := Vector3.ZERO          # their feet
var head_dir := Vector3.FORWARD # lying: which way their head is
var yaw := 0.0
var away := Vector3.FORWARD     # which way they walk off
var hits := 0                   # (thumps heard: tests)
var walk_back := false          # walk off back toward the ride (thrown a long way, into a wall: not on into it)
var hang_at := Vector3.INF      # a window sill's top, at its front edge: caught on it by a foot (INF: not)
var hang_out := Vector3.ZERO    # out from the wall there
var _t := 0.0
var _rag: SkRagdoll
var _last_v := 0.0
var _mm: MultiMesh
var _stars: Node3D
var _mmi: MultiMeshInstance3D
var mid_now := Vector3.ZERO     # (flying at a window: their middle now, for the view to follow)
var _fly_from := Vector3.ZERO   # (flying at a window: an exact arc, head over heels one and a half times, so they come
var _fly_v := Vector3.ZERO      # feet first and upside down to the sill: not the ragdoll, which falls short)
var _fly_T := 1.0
var _fly_side := Vector3.RIGHT
var _fly_yaw := 0.0

const FLY_SPEED := 26.0         # m/s across, at a window
const TURNS := PI * 3.0         # head over heels on the way there
const SLIDE := 1.7              # m above the sill they hit the wall (their feet), and slide down
const SPLAT_T := 0.35           # s stuck flat to it first
const SLIDE_T := 1.0            # s sliding down

## Throw them from `xf` (feet, facing -z) at `v` (m/s), the ride's middle at `mid` (they walk off away from it).
func start(xf: Transform3D, custom_: Color, v: Vector3, mid: Vector3, lift := 2.2, spin := 6.0) -> void:
	custom = custom_
	var shirt := int(floor(fposmod(custom.r, 0.5) * 16.0 + 0.01))
	look = [shirt, int(floor(custom.b * 8.0)), int(floor(fposmod(custom.b * 8.0, 1.0) * 8.0 + 0.01)), custom.a]
	var flat := Vector3(v.x, 0, v.z)
	# them stood up again: one of the crowd, on their own (hidden till they've landed)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = SkCrowd.person_mesh()
	_mm.instance_count = 1
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = SkCrowd.material()
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	_put(Transform3D(Basis().scaled(Vector3.ONE * 0.001), xf.origin), false)
	if hang_at != Vector3.INF:
		_arc(xf)
	else:
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
	if hang_at != Vector3.INF and body.global_position.distance_to(hang_at + hang_out * 0.4 + Vector3(0, 0.6, 0)) < 1.4:
		_hang()
		return
	var sp := body.linear_velocity.length()
	if _last_v - sp > THUMP:
		hits += 1
		var arena = get_tree().root.get_node_or_null("VoxelArena")
		if arena and arena.sound:
			arena.sound.play("thwack" if hits == 1 else "hammer_thud_0", body.global_position, -2.0 if hits == 1 else -8.0, randf_range(0.8, 1.0))
	_last_v = sp

func _process(dt: float) -> void:
	if (stage == "flying" and hang_at == Vector3.INF) or stage == "done":
		return
	_t += dt
	match stage:
		"flying":
			# (at a window) along the arc, turning over
			if _t >= _fly_T:
				_splat()
				return
			mid_now = _fly_from + _fly_v * _t + Vector3(0, -4.9 * _t * _t, 0)
			var b := Basis(_fly_side, TURNS * _t / _fly_T) * Basis(Vector3.UP, _fly_yaw)
			_put(Transform3D(b.scaled(Vector3.ONE * size), mid_now - b * Vector3(0, 0.9 * size, 0)), false)
		"splat", "slide":
			# flat against the wall above the window, upside down, a moment; then sliding down it, faster and faster,
			# till their foot gets to the sill
			var drop := 0.0
			var squash := 1.0
			if stage == "splat":
				squash = 0.75 + 0.25 * smoothstep(0.0, SPLAT_T, _t)       # (flattened by it, coming back)
				if _t >= SPLAT_T:
					stage = "slide"
					_t = 0.0
					_sound("gate_creak", -4.0, 1.7)
			else:
				var k := _t / SLIDE_T
				drop = SLIDE * k * k
				if k >= 1.0:
					_hang()
					return
			var feet := hang_at + Vector3(0, SLIDE - drop + 0.05, 0) - hang_out * 0.05
			var b := _upside_down()
			var flat := Basis(b.x, b.y, b.z * squash)
			_put(Transform3D(flat.scaled(Vector3.ONE * size), feet), false)
			mid_now = feet + Vector3(0, -0.9 * size, 0)
		"hang":
			# upside down: their feet at the sill, their head toward the ground, facing out; swinging a little (more
			# just after), arms waving
			var swing := sin(_t * 1.8) * (0.08 + 0.3 * exp(-_t * 1.2)) + sin(_t * 5.3) * 0.03
			var up := _upside_down()
			var b := Basis(up.x.normalized(), swing) * up
			_put(Transform3D(b.scaled(Vector3.ONE * size), hang_at + Vector3(0, 0.05, 0) - hang_out * 0.05), false)
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

## Caught on the sill by a foot: the ragdoll gone, them hung there upside down (arms waving: the crowd's riders' cheer).
func _hang() -> void:
	if _rag and is_instance_valid(_rag):
		_rag.queue_free()
	_rag = null
	stage = "hang"
	_t = 0.0
	hits += 1
	at = hang_at
	var m := (SkCrowd.material() as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("cheer", 1.0)
	_mmi.material_override = m
	var arena = get_tree().root.get_node_or_null("VoxelArena")
	if arena and arena.sound:
		arena.sound.play("hammer_thud_0", hang_at, -2.0, 1.2)     # (caught: a jolt)

# the arc to the window: from their middle on the horse to the wall SLIDE m above the sill, FLY_SPEED m/s across
func _arc(xf: Transform3D) -> void:
	size = xf.basis.get_scale().x
	_fly_from = xf.origin + Vector3(0, 0.9 * size, 0)
	var to := hang_at + Vector3(0, SLIDE - 0.9 * size, 0)      # (hitting the wall above the window, upside down)
	var across := Vector3(to.x - _fly_from.x, 0, to.z - _fly_from.z)
	_fly_T = maxf(across.length() / FLY_SPEED, 0.3)
	_fly_v = (to - _fly_from + Vector3(0, 4.9 * _fly_T * _fly_T, 0)) / _fly_T
	var dir := across.normalized()
	_fly_yaw = atan2(-dir.x, -dir.z)
	_fly_side = Vector3.UP.cross(dir).normalized()      # (head first, over forward)
	mid_now = _fly_from
	stage = "flying"
	_t = 0.0

# upside down against the wall: their head toward the ground, their back to it, facing out
func _upside_down() -> Basis:
	var down := Vector3.DOWN
	var back := -hang_out
	return Basis(down.cross(back), down, back)

## Into the wall above the window: a smack, stuck flat to it a moment.
func _splat() -> void:
	stage = "splat"
	_t = 0.0
	hits += 1
	_sound("thwack", 0.0, 0.85)

func _sound(nm: String, db: float, pitch: float) -> void:
	var arena = get_tree().root.get_node_or_null("VoxelArena")
	if arena and arena.sound:
		arena.sound.play(nm, hang_at, db, pitch)
