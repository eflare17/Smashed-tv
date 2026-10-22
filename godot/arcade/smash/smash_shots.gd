extends Node3D
## Smash arcade: the player's bullets. Pooled like the grunts (packed arrays, swap-remove, one MultiMesh).
## Bullets fly flat at gun height, stop at the walls (or the end of a corridor) and kill the first grunt they touch.

const Vox := preload("smash_vox.gd")

const MAX := 512
const SPEED := 26.0
const RADIUS := 0.12
const HEIGHT := 0.75

var half := 12.0
var door_half := 1.5
var corridor := 5.0

var count := 0
var pos := PackedVector2Array()
var dir := PackedVector2Array()

var _mm: MultiMesh
var _buf := PackedFloat32Array()

func _init() -> void:
	name = "Shots"
	pos.resize(MAX)
	dir.resize(MAX)
	_buf.resize(MAX * 12)
	for i in MAX:
		_buf[i * 12 + 5] = 1.0
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = Vox.box_mesh(Vector3(0.1, 0.1, 0.45), Color(1.0, 0.95, 0.4))
	_mm.mesh.surface_set_material(0, Vox.flat_material())
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 4, 40))
	add_child(mi)

func clear() -> void:
	count = 0

func fire(p: Vector2, d: Vector2) -> void:
	if count >= MAX:
		return
	pos[count] = p
	dir[count] = d
	count += 1

func step(delta: float, horde) -> void:
	var outer := half + 1.0 + corridor
	var i := 0
	while i < count:
		var p := pos[i] + dir[i] * (SPEED * delta)
		var gone := false
		var ax := absf(p.x)
		var az := absf(p.y)
		if ax > outer or az > outer:
			gone = true
		elif ax > half - RADIUS and az > door_half - RADIUS:
			gone = true
		elif az > half - RADIUS and ax > door_half - RADIUS:
			gone = true
		else:
			var j: int = horde.hit_test(p, RADIUS)
			if j >= 0:
				horde.kill(j, dir[i])
				gone = true
		if gone:
			count -= 1
			pos[i] = pos[count]
			dir[i] = dir[count]
		else:
			pos[i] = p
			i += 1

func draw() -> void:
	for i in count:
		var p := pos[i]
		var f := dir[i]
		var o := i * 12
		_buf[o] = f.y; _buf[o + 2] = f.x; _buf[o + 3] = p.x
		_buf[o + 7] = HEIGHT
		_buf[o + 8] = -f.x; _buf[o + 10] = f.y; _buf[o + 11] = p.y
	_mm.buffer = _buf
	_mm.visible_instance_count = count
