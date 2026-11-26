extends Node3D
## Smash arcade: floating mines. They drift in through a door and wander toward the player, bouncing off the
## walls. Get within ARM of one and it starts blinking red; FUSE seconds later it goes off (a blast that hurts you,
## and the grunts). One bullet sets it off at once, and a blast nearby sets it off too (chain reactions); the
## blasts themselves are done by the scene root from `booms`. Pooled, one MultiMesh with a per-instance colour.

const SmashVox := preload("smash_vox.gd")

const MAX := 48
const RADIUS := 0.35
const SPEED := 1.3
const ARM := 2.2
const FUSE := 0.8
const INSIDE := 255
const DOOR_N := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]

var half := 10.0
var door_half := 1.5

var count := 0
var pos := PackedVector2Array()
var vel := PackedVector2Array()
## -1 while drifting, else seconds left on the fuse.
var fuse := PackedFloat32Array()
var age := PackedFloat32Array()
var door := PackedByteArray()
## Where mines went off this frame (read and cleared by the scene root), and how many were shot (for score).
var booms := PackedVector2Array()
var shot_down := 0

var _mm: MultiMesh
var _buf := PackedFloat32Array()

func _init() -> void:
	name = "SmashMines"
	pos.resize(MAX)
	vel.resize(MAX)
	fuse.resize(MAX)
	age.resize(MAX)
	door.resize(MAX)
	_buf.resize(MAX * 16)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = SmashVox.mine_mesh()
	_mm.mesh.surface_set_material(0, SmashVox.flat_material())
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 4, 40))
	add_child(mi)

func clear() -> void:
	count = 0
	shot_down = 0
	booms.clear()

func spawn(d: int, depth: float) -> bool:
	if count >= MAX:
		return false
	var n: Vector2 = DOOR_N[d]
	var t := Vector2(n.y, -n.x)
	var i := count
	count += 1
	pos[i] = -n * (half + depth) + t * randf_range(-0.8, 0.8)
	vel[i] = n * SPEED
	fuse[i] = -1.0
	age[i] = randf() * TAU
	door[i] = d
	return true

func spawn_inside(p: Vector2) -> bool:
	if not spawn(0, 1.0):
		return false
	pos[count - 1] = p
	door[count - 1] = INSIDE
	return true

func _remove(i: int) -> void:
	count -= 1
	pos[i] = pos[count]
	vel[i] = vel[count]
	fuse[i] = fuse[count]
	age[i] = age[count]
	door[i] = door[count]

func _explode(i: int) -> void:
	booms.append(pos[i])
	_remove(i)

func step(delta: float, target: Vector2, armed_by_player: bool) -> void:
	var lim := half - RADIUS
	var i := 0
	while i < count:
		age[i] += delta
		var p := pos[i]
		if door[i] != INSIDE:
			var n: Vector2 = DOOR_N[door[i]]
			p += n * (SPEED * delta)
			if p.dot(n) + half > RADIUS + 0.2:
				door[i] = INSIDE
		else:
			# drift toward the player, wobbling, bouncing off the walls
			var to := target - p
			var want := to.normalized() * SPEED if to.length_squared() > 0.01 else Vector2.ZERO
			want = want.rotated(sin(age[i] * 0.7) * 0.9)
			var v := vel[i].lerp(want, minf(1.0, delta * 0.8))
			p += v * delta
			if absf(p.x) > lim:
				p.x = signf(p.x) * lim
				v.x = -v.x
			if absf(p.y) > lim:
				p.y = signf(p.y) * lim
				v.y = -v.y
			vel[i] = v
			if fuse[i] < 0.0 and armed_by_player and to.length() < ARM:
				fuse[i] = FUSE
		if fuse[i] >= 0.0:
			fuse[i] -= delta
			if fuse[i] <= 0.0:
				pos[i] = p
				_explode(i)
				continue
		pos[i] = p
		i += 1

func hit_test(p: Vector2, r: float) -> int:
	var rr := (r + RADIUS) * (r + RADIUS)
	for i in count:
		if (pos[i] - p).length_squared() < rr:
			return i
	return -1

func bullet_hit(i: int, _dir: Vector2) -> void:
	shot_down += 1
	_explode(i)

## Sets off every mine within `r` of `p`.
func detonate_radius(p: Vector2, r: float) -> void:
	var i := 0
	while i < count:
		if (pos[i] - p).length_squared() < (r + RADIUS) * (r + RADIUS):
			_explode(i)
		else:
			i += 1

## The smart bomb: mines just vanish (no blast). Returns how many.
func remove_all() -> int:
	var n := count
	count = 0
	return n

func draw() -> void:
	for i in count:
		var p := pos[i]
		var a := age[i]
		var cs := cos(a)
		var sn := sin(a)
		var c := Color(0.85, 0.85, 0.9)
		if fuse[i] >= 0.0:
			c = Color(1.0, 0.15, 0.1) if int(fuse[i] * 12.0) % 2 == 0 else Color(1.0, 1.0, 0.6)
		elif int(a * 1.5) % 2 == 0:
			c = Color(1.0, 0.55, 0.5)
		var o := i * 16
		_buf[o] = cs; _buf[o + 1] = 0.0; _buf[o + 2] = sn; _buf[o + 3] = p.x
		_buf[o + 4] = 0.0; _buf[o + 5] = 1.0; _buf[o + 6] = 0.0; _buf[o + 7] = 0.5 + sin(a * 2.0) * 0.08
		_buf[o + 8] = -sn; _buf[o + 9] = 0.0; _buf[o + 10] = cs; _buf[o + 11] = p.y
		_buf[o + 12] = c.r; _buf[o + 13] = c.g; _buf[o + 14] = c.b; _buf[o + 15] = 1.0
	_mm.buffer = _buf
	_mm.visible_instance_count = count
