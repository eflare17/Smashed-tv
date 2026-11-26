extends Node3D
## Smash arcade: snipers. They walk in through a door, take a post a little way inside, and shoot slow bullets
## (SmashEShots) at the player: each shot is telegraphed by a short yellow glow, so you can step aside. Every few
## shots they move to a new post. 2 hits kill. Pooled (packed arrays, swap-remove), two MultiMeshes (walk frames)
## with a per-instance colour for the hit flash and the aim glow.

const SmashVox := preload("smash_vox.gd")

const MAX := 32
const RADIUS := 0.35
const HP := 2
const SPEED := 2.4
const INSIDE := 255
const AIM := 0.45
const FLASH := 0.1
const DOOR_N := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]

var half := 10.0
var door_half := 1.5
## Seconds between shots (the wave director tightens it with the room).
var gap := 2.0

var count := 0
var pos := PackedVector2Array()
var facing := PackedVector2Array()
var post := PackedVector2Array()
var hp := PackedInt32Array()
var flash := PackedFloat32Array()
var cool := PackedFloat32Array()
var shots_left := PackedInt32Array()
var phase := PackedFloat32Array()
var door := PackedByteArray()

var kill_pos := PackedVector2Array()
var kill_dir := PackedVector2Array()
## Shots fired this frame (for the sound).
var fired := 0

var _mm: Array[MultiMesh] = []
var _buf_a := PackedFloat32Array()
var _buf_b := PackedFloat32Array()

func _init() -> void:
	name = "SmashSnipers"
	pos.resize(MAX)
	facing.resize(MAX)
	post.resize(MAX)
	hp.resize(MAX)
	flash.resize(MAX)
	cool.resize(MAX)
	shots_left.resize(MAX)
	phase.resize(MAX)
	door.resize(MAX)
	_buf_a.resize(MAX * 16)
	_buf_b.resize(MAX * 16)
	var mat := SmashVox.flat_material()
	for f in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = SmashVox.sniper_mesh(f)
		mm.mesh.surface_set_material(0, mat)
		mm.instance_count = MAX
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 4, 40))
		add_child(mi)
		_mm.append(mm)

func clear() -> void:
	count = 0
	fired = 0
	kill_pos.clear()
	kill_dir.clear()

func spawn(d: int, depth: float) -> bool:
	if count >= MAX:
		return false
	var n: Vector2 = DOOR_N[d]
	var t := Vector2(n.y, -n.x)
	var i := count
	count += 1
	pos[i] = -n * (half + depth) + t * randf_range(-0.6, 0.6)
	facing[i] = n
	post[i] = _new_post(d)
	hp[i] = HP
	flash[i] = 0.0
	cool[i] = gap * randf_range(0.8, 1.3)
	shots_left[i] = randi_range(3, 5)
	phase[i] = 0.0
	door[i] = d
	return true

func spawn_inside(p: Vector2) -> bool:
	if not spawn(0, 1.0):
		return false
	pos[count - 1] = p
	post[count - 1] = p
	door[count - 1] = INSIDE
	return true

## A standing spot a few metres inside door `d`, off to one side.
func _new_post(d: int) -> Vector2:
	var n: Vector2 = DOOR_N[d]
	var t := Vector2(n.y, -n.x)
	return -n * (half - randf_range(1.5, 3.5)) + t * randf_range(-4.0, 4.0)

func step(delta: float, target: Vector2, touch: float, can_touch: bool, eshots) -> bool:
	var touched := false
	var lat := door_half - RADIUS
	for i in count:
		var p := pos[i]
		flash[i] -= delta
		var d := door[i]
		if d != INSIDE:
			# walk in through the corridor
			var n: Vector2 = DOOR_N[d]
			var t := Vector2(n.y, -n.x)
			p += n * (SPEED * delta)
			var depth := p.dot(n) + half
			p = n * (depth - half) + t * clampf(p.dot(t), -lat, lat)
			facing[i] = n
			phase[i] += delta * 6.0
			if depth > RADIUS + 0.1:
				door[i] = INSIDE
		else:
			var to_post := post[i] - p
			if to_post.length() > 0.15:
				facing[i] = to_post.normalized()
				p += facing[i] * minf(SPEED * delta, to_post.length())
				phase[i] += delta * 6.0
			else:
				# at the post: face the player, glow, shoot
				phase[i] = 0.0
				var aim := target - p
				if aim.length_squared() > 0.01:
					facing[i] = aim.normalized()
				cool[i] -= delta
				if cool[i] <= 0.0:
					eshots.fire(p + facing[i] * 0.7, facing[i], eshots.SHOT)
					fired += 1
					cool[i] = gap * randf_range(0.8, 1.2)
					shots_left[i] -= 1
					if shots_left[i] <= 0:
						shots_left[i] = randi_range(3, 5)
						post[i] = _new_post(randi() % 4)
			var lim := half - RADIUS
			p = Vector2(clampf(p.x, -lim, lim), clampf(p.y, -lim, lim))
			if can_touch and (p - target).length() < touch:
				touched = true
		pos[i] = p
	return touched

func hit_test(p: Vector2, r: float) -> int:
	var rr := (r + RADIUS) * (r + RADIUS)
	for i in count:
		if hp[i] > 0 and (pos[i] - p).length_squared() < rr:
			return i
	return -1

func bullet_hit(i: int, dir: Vector2) -> void:
	damage(i, 1, dir)

func damage(i: int, amount: int, dir: Vector2) -> void:
	if hp[i] <= 0:
		return
	hp[i] -= amount
	flash[i] = FLASH
	if hp[i] <= 0:
		kill_pos.append(pos[i])
		kill_dir.append(dir)

func damage_radius(p: Vector2, r: float, amount: int) -> void:
	var rr := (r + RADIUS) * (r + RADIUS)
	for i in count:
		var d := pos[i] - p
		if d.length_squared() < rr:
			damage(i, amount, d.normalized())

func compact() -> void:
	var i := 0
	while i < count:
		if hp[i] <= 0:
			count -= 1
			pos[i] = pos[count]
			facing[i] = facing[count]
			post[i] = post[count]
			hp[i] = hp[count]
			flash[i] = flash[count]
			cool[i] = cool[count]
			shots_left[i] = shots_left[count]
			phase[i] = phase[count]
			door[i] = door[count]
		else:
			i += 1

func draw() -> void:
	var na := 0
	var nb := 0
	for i in count:
		var p := pos[i]
		var f := facing[i]
		var c := Color.WHITE
		if flash[i] > 0.0:
			c = Color(1.0, 0.3, 0.3)
		elif door[i] == INSIDE and cool[i] < AIM and phase[i] == 0.0:
			c = Color(1.0, 1.0, 0.35)
		var vals := [f.y, 0.0, f.x, p.x, 0.0, 1.0, 0.0, 0.0, -f.x, 0.0, f.y, p.y, c.r, c.g, c.b, 1.0]
		if int(phase[i] / PI) & 1 == 0:
			for k in 16:
				_buf_a[na * 16 + k] = vals[k]
			na += 1
		else:
			for k in 16:
				_buf_b[nb * 16 + k] = vals[k]
			nb += 1
	_mm[0].buffer = _buf_a
	_mm[0].visible_instance_count = na
	_mm[1].buffer = _buf_b
	_mm[1].visible_instance_count = nb
