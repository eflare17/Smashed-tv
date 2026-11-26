extends Node3D
## Smash arcade: the brute, the second enemy. Slower and bigger than a grunt, takes HP hits (each one flashes
## him red and knocks him back), shoves grunts out of his way, and is worth more. Pooled like the grunts (packed
## arrays, swap-remove) and drawn by two MultiMeshes (walk frames) with a per-instance colour for the flash.
## There are only ever a few, so they push each other apart pair by pair and bullets test them one by one.

const SmashVox := preload("smash_vox.gd")

const MAX := 128
const RADIUS := 0.5
const HP := 6
const SCALE := 1.35
const INSIDE := 255
const FLASH := 0.1
const DOOR_N := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]

var half := 10.0
var door_half := 1.5

var count := 0
var pos := PackedVector2Array()
var facing := PackedVector2Array()
var speed := PackedFloat32Array()
var phase := PackedFloat32Array()
var hp := PackedInt32Array()
var flash := PackedFloat32Array()
var door := PackedByteArray()

## Kills this frame (read and cleared by the scene root), and hits that didn't kill (for the thud sound).
var kill_pos := PackedVector2Array()
var kill_dir := PackedVector2Array()
var hits := 0

var _mm: Array[MultiMesh] = []
var _buf_a := PackedFloat32Array()
var _buf_b := PackedFloat32Array()

func _init() -> void:
	name = "SmashBrutes"
	pos.resize(MAX)
	facing.resize(MAX)
	speed.resize(MAX)
	phase.resize(MAX)
	hp.resize(MAX)
	flash.resize(MAX)
	door.resize(MAX)
	_buf_a.resize(MAX * 16)
	_buf_b.resize(MAX * 16)
	var mat := SmashVox.flat_material()
	for f in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = SmashVox.brute_mesh(f)
		mm.mesh.surface_set_material(0, mat)
		mm.instance_count = MAX
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 5, 40))
		add_child(mi)
		_mm.append(mm)

func clear() -> void:
	count = 0
	hits = 0
	kill_pos.clear()
	kill_dir.clear()

func spawn(d: int, depth: float, spd: float) -> bool:
	if count >= MAX:
		return false
	var n: Vector2 = DOOR_N[d]
	var t := Vector2(n.y, -n.x)
	var i := count
	count += 1
	pos[i] = -n * (half + depth) + t * randf_range(-door_half + RADIUS, door_half - RADIUS)
	facing[i] = n
	speed[i] = spd
	phase[i] = randf() * TAU
	hp[i] = HP
	flash[i] = 0.0
	door[i] = d
	return true

func spawn_inside(p: Vector2, spd: float) -> bool:
	if not spawn(0, 1.0, spd):
		return false
	pos[count - 1] = p
	door[count - 1] = INSIDE
	return true

## Moves the brutes toward `target`, pushes them apart and shoves grunts aside. True if one touched the target.
func step(delta: float, target: Vector2, touch: float, can_touch: bool, horde) -> bool:
	var touched := false
	var lim := half - RADIUS
	var lat := door_half - RADIUS
	for i in count:
		var p := pos[i]
		var d := door[i]
		var dir: Vector2 = facing[i]
		if d == INSIDE:
			var to := target - p
			if to.length_squared() > 0.0001:
				dir = to.normalized()
		else:
			dir = DOOR_N[d]
		# knocked back while flashing, so he staggers instead of walking through the bullets
		if flash[i] <= 0.0:
			p += dir * (speed[i] * delta)
		flash[i] -= delta
		for j in count:
			if j != i:
				var dd := p - pos[j]
				var l2 := dd.length_squared()
				if l2 < 4.0 * RADIUS * RADIUS and l2 > 0.000001:
					var l := sqrt(l2)
					p += dd * ((RADIUS * 2.0 - l) / l) * 0.5
		if d == INSIDE:
			p = Vector2(clampf(p.x, -lim, lim), clampf(p.y, -lim, lim))
			if can_touch and (p - target).length() < touch:
				touched = true
		else:
			var n: Vector2 = DOOR_N[d]
			var t := Vector2(n.y, -n.x)
			var depth := p.dot(n) + half
			p = n * (depth - half) + t * clampf(p.dot(t), -lat, lat)
			if depth > RADIUS + 0.1:
				door[i] = INSIDE
		pos[i] = p
		facing[i] = dir
		phase[i] += delta * speed[i] * 2.0
		horde.push_out(p, RADIUS)
	return touched

func hit_test(p: Vector2, r: float) -> int:
	var rr := (r + RADIUS) * (r + RADIUS)
	for i in count:
		if hp[i] > 0 and (pos[i] - p).length_squared() < rr:
			return i
	return -1

func bullet_hit(i: int, dir: Vector2) -> void:
	damage(i, 1, dir)

## Takes `amount` HP off brute `i`, knocking him back along `dir`. True if that killed him.
func damage(i: int, amount: int, dir: Vector2) -> bool:
	if hp[i] <= 0:
		return false
	hp[i] -= amount
	flash[i] = FLASH
	pos[i] += dir * 0.18
	if hp[i] <= 0:
		kill_pos.append(pos[i])
		kill_dir.append(dir)
		return true
	hits += 1
	return false

## Damages every brute within `r` of `p`; with `respect_flash` one still flashing from a hit is skipped (contact
## damage from the shield ticks rather than draining him in a few frames).
func damage_radius(p: Vector2, r: float, amount: int, respect_flash: bool) -> void:
	var rr := (r + RADIUS) * (r + RADIUS)
	for i in count:
		var d := pos[i] - p
		if d.length_squared() < rr and not (respect_flash and flash[i] > 0.0):
			damage(i, amount, d.normalized())

## Removes the dead (HP <= 0), swapping the last live one in.
func compact() -> void:
	var i := 0
	while i < count:
		if hp[i] <= 0:
			count -= 1
			pos[i] = pos[count]
			facing[i] = facing[count]
			speed[i] = speed[count]
			phase[i] = phase[count]
			hp[i] = hp[count]
			flash[i] = flash[count]
			door[i] = door[count]
		else:
			i += 1

func draw() -> void:
	var na := 0
	var nb := 0
	for i in count:
		var p := pos[i]
		var f := facing[i] * SCALE
		var ph := phase[i]
		var red := flash[i] > 0.0
		var buf := 0
		var o := 0
		if int(ph / PI) & 1 == 0:
			o = na * 16
			na += 1
		else:
			o = nb * 16
			nb += 1
			buf = 1
		var vals := [f.y, 0.0, f.x, p.x, 0.0, SCALE, 0.0, absf(sin(ph)) * 0.05, -f.x, 0.0, f.y, p.y,
				1.0, 0.3 if red else 1.0, 0.3 if red else 1.0, 1.0]
		if buf == 0:
			for k in 16:
				_buf_a[o + k] = vals[k]
		else:
			for k in 16:
				_buf_b[o + k] = vals[k]
	_mm[0].buffer = _buf_a
	_mm[0].visible_instance_count = na
	_mm[1].buffer = _buf_b
	_mm[1].visible_instance_count = nb
