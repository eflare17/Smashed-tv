extends Node3D
## Smash arcade: the player's shots. Bullets and rockets share one pool (packed arrays, swap-remove) and are drawn
## by a MultiMesh each. Both fly flat at gun height and stop at the walls (or the end of a corridor). A bullet
## hits the first target it touches (boss, brutes, snipers, mines, barrels, then grunts: anything with `count`,
## hit_test() and bullet_hit()); a rocket explodes on anything, and its blast (radius damage, gibs, sound) is done
## by the scene root from `booms`.

const SmashVox := preload("smash_vox.gd")

const MAX := 512
const BULLET := 0
const ROCKET := 1
const SPEED := [26.0, 15.0]
const RADIUS := 0.12
const HEIGHT := 0.75

var half := 10.0
var door_half := 1.5
var corridor := 5.0

var count := 0
var pos := PackedVector2Array()
var dir := PackedVector2Array()
var kind := PackedByteArray()
## Where rockets went off this frame (read and cleared by the scene root).
var booms := PackedVector2Array()

var _mm: Array[MultiMesh] = []
var _buf_a := PackedFloat32Array()
var _buf_b := PackedFloat32Array()

func _init() -> void:
	name = "SmashShots"
	pos.resize(MAX)
	dir.resize(MAX)
	kind.resize(MAX)
	_buf_a.resize(MAX * 12)
	_buf_b.resize(MAX * 12)
	for i in MAX:
		_buf_a[i * 12 + 5] = 1.0
		_buf_b[i * 12 + 5] = 1.0
	var meshes := [SmashVox.box_mesh(Vector3(0.1, 0.1, 0.45), Color(1.0, 0.95, 0.4)), SmashVox.rocket_mesh()]
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

func fire(p: Vector2, d: Vector2, k := BULLET) -> void:
	if count >= MAX:
		return
	pos[count] = p
	dir[count] = d
	kind[count] = k
	count += 1

## `targets` are tested in order before the grunts (which use their grid).
func step(delta: float, targets: Array, horde) -> void:
	var outer := half + 1.0 + corridor
	var i := 0
	while i < count:
		var k := kind[i]
		var spd: float = SPEED[k]
		var p := pos[i] + dir[i] * (spd * delta)
		var gone := false
		var ax := absf(p.x)
		var az := absf(p.y)
		if ax > outer or az > outer:
			gone = true
		elif (ax > half - RADIUS and az > door_half - RADIUS) or (az > half - RADIUS and ax > door_half - RADIUS):
			gone = true
			if k == ROCKET:
				booms.append(Vector2(clampf(p.x, -half, half), clampf(p.y, -half, half)))
		else:
			for t in targets:
				if t.count > 0:
					var j: int = t.hit_test(p, RADIUS)
					if j >= 0:
						gone = true
						if k == ROCKET:
							booms.append(p)
						else:
							t.bullet_hit(j, dir[i])
						break
			if not gone:
				var j: int = horde.hit_test(p, RADIUS)
				if j >= 0:
					gone = true
					if k == ROCKET:
						booms.append(p)
					else:
						horde.kill(j, dir[i])
		if gone:
			count -= 1
			pos[i] = pos[count]
			dir[i] = dir[count]
			kind[i] = kind[count]
		else:
			pos[i] = p
			i += 1

func draw() -> void:
	var na := 0
	var nb := 0
	for i in count:
		var p := pos[i]
		var f := dir[i]
		if kind[i] == BULLET:
			var o := na * 12
			na += 1
			_buf_a[o] = f.y; _buf_a[o + 2] = f.x; _buf_a[o + 3] = p.x
			_buf_a[o + 7] = HEIGHT
			_buf_a[o + 8] = -f.x; _buf_a[o + 10] = f.y; _buf_a[o + 11] = p.y
		else:
			var o := nb * 12
			nb += 1
			_buf_b[o] = f.y; _buf_b[o + 2] = f.x; _buf_b[o + 3] = p.x
			_buf_b[o + 7] = HEIGHT
			_buf_b[o + 8] = -f.x; _buf_b[o + 10] = f.y; _buf_b[o + 11] = p.y
	_mm[0].buffer = _buf_a
	_mm[0].visible_instance_count = na
	_mm[1].buffer = _buf_b
	_mm[1].visible_instance_count = nb
