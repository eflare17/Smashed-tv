class_name TrackRig
extends Node3D
## A machine's moving tracks: cleats running round the track on each side, and wheels that turn. Each side has its own speed,
## so a turning machine shows one track outrunning the other, and a stuck one shows its tracks spinning.

const CLEAT_GAP := 0.3

var _path := PackedVector2Array()
var _dist := PackedFloat32Array()
var _loop := 0.0
var _count := 0
var _z := 0.0
var _face := 0.0
var _wheels: Array[Vector3] = []     # x, y, radius
var _travel: Array[float] = [0.0, 0.0]
var _cleats: MultiMesh
var _wheel_mesh: MultiMesh

func setup(mat: Material, path: PackedVector2Array, z_mid: float, width: float, face_z: float, wheels: Array[Vector3], gap := CLEAT_GAP) -> void:
	_path = path
	_z = z_mid
	_face = face_z
	_wheels = wheels
	_dist.resize(path.size() + 1)
	for k in path.size():
		_dist[k + 1] = _dist[k] + path[k].distance_to(path[(k + 1) % path.size()])
	_loop = _dist[path.size()]
	_count = int(round(_loop / gap))

	var cleat := MeshKit.new()
	cleat.box(Vector3.ZERO, Vector3(0.13, 0.06, width), Props.BLACK)
	_cleats = _multi(cleat.mesh(), mat, _count * 2)

	var w := MeshKit.new()
	w.cone(Vector3(0, 0, -0.05), Vector3(0, 0, 0.05), 1.0, 1.0, 8, Props.BLACK)
	# Spokes that stand out from the wheel's face, or a turning wheel wouldn't look any different.
	for k in 3:
		w.box(Vector3.ZERO, Vector3(1.5, 0.3, 0.16), Props.STEEL, Basis(Vector3.BACK, k * PI / 3.0))
	_wheel_mesh = _multi(w.mesh(), mat, wheels.size() * 2)
	_draw_side(0)
	_draw_side(1)

func _multi(mesh: Mesh, mat: Material, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.custom_aabb = AABB(Vector3(-4, -1, -3), Vector3(8, 4, 6))
	add_child(inst)
	return mm

## Moves the tracks on: metres a second, left then right. Going forward, the bottom of the track runs back under the machine.
func update(left: float, right: float, dt: float) -> void:
	if absf(left) > 0.001:
		_travel[0] = fposmod(_travel[0] + left * dt, _loop * 8.0)
		_draw_side(0)
	if absf(right) > 0.001:
		_travel[1] = fposmod(_travel[1] + right * dt, _loop * 8.0)
		_draw_side(1)

func _draw_side(side: int) -> void:
	var z := -_z if side == 0 else _z
	var face := -_face if side == 0 else _face
	var gap := _loop / _count
	for c in _count:
		var s := fposmod(_travel[side] + c * gap, _loop)
		var k := 0
		while k < _path.size() - 1 and s >= _dist[k + 1]:
			k += 1
		var a := _path[k]
		var b := _path[(k + 1) % _path.size()]
		var p := a.lerp(b, (s - _dist[k]) / maxf(_dist[k + 1] - _dist[k], 0.001))
		var t := b - a
		_cleats.set_instance_transform(c + side * _count, Transform3D(Basis(Vector3.BACK, atan2(t.y, t.x)), Vector3(p.x, p.y, z)))
	for w in _wheels.size():
		var at: Vector3 = _wheels[w]
		var turn := Basis(Vector3.BACK, -_travel[side] / at.z).scaled(Vector3(at.z, at.z, 1.0))
		_wheel_mesh.set_instance_transform(w + side * _wheels.size(), Transform3D(turn, Vector3(at.x, at.y, face)))
