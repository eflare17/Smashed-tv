class_name Pipes
extends Node3D
## Every length of pipe laid on the site. A pipe is only a thing lying in the ground: it takes no soil and moves none, so dirt can
## be pushed back over it and it's simply buried. Lengths laid one after another join up into a run.

const MOST := 500
const JOIN_WITHIN := 1.3        # m: a new point this close to the end of the last run carries on from it
const RADIUS := 0.11

var length_m := 0.0
var _mesh: MultiMesh
var _points := PackedVector3Array()   # the last point of the run being laid is the last in here
var _used := 0
var _seg_from := PackedInt32Array()   # for each length laid, the point it starts from

func setup(mat: Material) -> void:
	var kit := MeshKit.new()
	var white := Props.c("#e9e6dc")
	var collar := Props.c("#3f7fbf")
	# Along +x from 0 to 1, stretched to length when it's placed. A coloured collar at the joint.
	kit.cone(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), RADIUS, RADIUS, 8, white)
	kit.cone(Vector3(-0.03, 0.0, 0.0), Vector3(0.09, 0.0, 0.0), RADIUS * 1.3, RADIUS * 1.3, 8, collar)
	_mesh = MultiMesh.new()
	_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_mesh.mesh = kit.mesh()
	_mesh.instance_count = MOST
	_mesh.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = _mesh
	inst.material_override = mat
	inst.custom_aabb = AABB(Vector3(-40, -12, -40), Vector3(80, 30, 80))
	add_child(inst)

func segments() -> int:
	return _used

## Lays pipe up to this point, joined to the last run if it's close enough. Returns whether it laid a length.
func lay_to(p: Vector3) -> bool:
	if _points.is_empty() or _points[_points.size() - 1].distance_to(p) > JOIN_WITHIN:
		_points.append(p)
		return false
	if _used >= MOST:
		return false
	var from := _points[_points.size() - 1]
	var along := p - from
	var size := along.length()
	if size < 0.01:
		return false
	_seg_from.append(_points.size() - 1)
	_place(_used, from, p)
	_used += 1
	_mesh.visible_instance_count = _used
	length_m += size
	_points.append(p)
	return true

func _place(k: int, from: Vector3, to: Vector3) -> void:
	var along := to - from
	var size := maxf(along.length(), 0.01)
	var x := along / size
	var up_axis := Vector3.UP if absf(x.y) < 0.9 else Vector3.RIGHT
	var z := x.cross(up_axis).normalized()
	var y := z.cross(x).normalized()
	_mesh.set_instance_transform(k, Transform3D(Basis(x * size, y, z), from))

## Pipe lies on the firm floor of its trench: cut that deeper under it and it drops down to the new floor. Returns whether any moved.
func settle(sim: DirtSim) -> bool:
	var moved := false
	for k in _points.size():
		var p := _points[k]
		var floor_y := sim.firm_at(Vector2(p.x, p.z)) + RADIUS + 0.02
		if p.y > floor_y + 0.005:
			p.y = floor_y
			_points[k] = p
			moved = true
	if moved:
		for k in _used:
			_place(k, _points[_seg_from[k]], _points[_seg_from[k] + 1])
	return moved

## Every point it's been laid to, in order: laying them again elsewhere gives the same pipe.
func points() -> PackedVector3Array:
	return _points

## The end of the last run, or null.
func last_end() -> Variant:
	return null if _points.is_empty() else _points[_points.size() - 1]
