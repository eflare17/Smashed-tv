extends Node3D
## Smash arcade: enemy projectiles, one pool (packed arrays, swap-remove), a MultiMesh per kind.
##  - SHOT: a sniper's slow glowing bullet; touching it costs a life; it stops at the walls.
##  - BARREL: the boss's rolling barrel; it explodes (a blast that hurts you too) when it hits you, reaches a wall
##    or runs out of time, and the player can shoot it to set it off early. Blasts are done by the scene root from
##    `booms`.

const SmashVox := preload("smash_vox.gd")

const MAX := 256
const SHOT := 0
const BARREL := 1
const SPEED := [7.0, 5.5]
const RADIUS := [0.15, 0.45]
const BARREL_LIFE := 6.0

var half := 10.0
var door_half := 1.5

var count := 0
var pos := PackedVector2Array()
var dir := PackedVector2Array()
var kind := PackedByteArray()
var age := PackedFloat32Array()
## Where barrels went off this frame (read and cleared by the scene root).
var booms := PackedVector2Array()

var _mm: Array[MultiMesh] = []
var _buf_a := PackedFloat32Array()
var _buf_b := PackedFloat32Array()

func _init() -> void:
	name = "SmashEShots"
	pos.resize(MAX)
	dir.resize(MAX)
	kind.resize(MAX)
	age.resize(MAX)
	_buf_a.resize(MAX * 12)
	_buf_b.resize(MAX * 12)
	var meshes := [SmashVox.box_mesh(Vector3.ONE * 0.24, Color(1.0, 0.3, 0.2)), SmashVox.barrel_mesh()]
	for m: ArrayMesh in meshes:
		m.surface_set_material(0, SmashVox.flat_material())
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
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
	booms.clear()

func fire(p: Vector2, d: Vector2, k: int) -> void:
	if count >= MAX:
		return
	pos[count] = p
	dir[count] = d
	kind[count] = k
	age[count] = 0.0
	count += 1

func _remove(i: int) -> void:
	count -= 1
	pos[i] = pos[count]
	dir[i] = dir[count]
	kind[i] = kind[count]
	age[i] = age[count]

## Moves everything. True if a sniper's bullet touched `target` while `can_touch` (barrels report via `booms`).
func step(delta: float, target: Vector2, player_radius: float, can_touch: bool) -> bool:
	var touched := false
	var lim := half
	var i := 0
	while i < count:
		var k := kind[i]
		var spd: float = SPEED[k]
		var r: float = RADIUS[k]
		var p := pos[i] + dir[i] * (spd * delta)
		age[i] += delta
		var gone := false
		var ax := absf(p.x)
		var az := absf(p.y)
		var wall := (ax > lim - r and az > door_half - r) or (az > lim - r and ax > door_half - r) \
				or ax > lim + 6.0 or az > lim + 6.0
		var hit := (p - target).length_squared() < (r + player_radius) * (r + player_radius)
		if k == SHOT:
			if wall:
				gone = true
			elif hit and can_touch:
				touched = true
				gone = true
		elif wall or hit or age[i] > BARREL_LIFE:
			booms.append(p)
			gone = true
		if gone:
			_remove(i)
		else:
			pos[i] = p
			i += 1
	return touched

## Player bullets can hit barrels (only): returns the barrel's index or -1.
func hit_test(p: Vector2, r: float) -> int:
	for i in count:
		if kind[i] == BARREL:
			var rr: float = r + RADIUS[BARREL]
			if (pos[i] - p).length_squared() < rr * rr:
				return i
	return -1

func bullet_hit(i: int, _dir: Vector2) -> void:
	booms.append(pos[i])
	_remove(i)

## Sets off every barrel within `r` of `p` (chain reactions).
func detonate_radius(p: Vector2, r: float) -> void:
	var i := 0
	while i < count:
		if kind[i] == BARREL and (pos[i] - p).length_squared() < r * r:
			booms.append(pos[i])
			_remove(i)
		else:
			i += 1

func draw() -> void:
	var na := 0
	var nb := 0
	for i in count:
		var p := pos[i]
		var f := dir[i]
		if kind[i] == SHOT:
			var o := na * 12
			na += 1
			_buf_a[o] = 1.0; _buf_a[o + 1] = 0.0; _buf_a[o + 2] = 0.0; _buf_a[o + 3] = p.x
			_buf_a[o + 4] = 0.0; _buf_a[o + 5] = 1.0; _buf_a[o + 6] = 0.0; _buf_a[o + 7] = 0.75
			_buf_a[o + 8] = 0.0; _buf_a[o + 9] = 0.0; _buf_a[o + 10] = 1.0; _buf_a[o + 11] = p.y
		else:
			# the barrel lies across its path (length along local X) and rolls about that axis
			var a := age[i] * SPEED[BARREL] / 0.25
			var c := cos(a)
			var s := sin(a)
			var o := nb * 12
			nb += 1
			# columns: X = (f.y, 0, -f.x), Y = up * c + fwd * s, Z = -up * s + fwd * c
			_buf_b[o] = f.y; _buf_b[o + 1] = f.x * s; _buf_b[o + 2] = f.x * c; _buf_b[o + 3] = p.x
			_buf_b[o + 4] = 0.0; _buf_b[o + 5] = c; _buf_b[o + 6] = -s; _buf_b[o + 7] = 0.27
			_buf_b[o + 8] = -f.x; _buf_b[o + 9] = f.y * s; _buf_b[o + 10] = f.y * c; _buf_b[o + 11] = p.y
	_mm[0].buffer = _buf_a
	_mm[0].visible_instance_count = na
	_mm[1].buffer = _buf_b
	_mm[1].visible_instance_count = nb
