class_name VoxelWorm
extends Node3D
## A worm dug up (Stage 4: "worms can be found while digging"): a pink, segmented little thing that wriggles out where
## it was, then (being yours: it's already in your backpack) hops to you and is gone. Owned by the voxel session.

const SEGS := 7
const WRIGGLE_T := 1.4
const GO_T := 0.35

var _segs: Array[MeshInstance3D] = []
var _t := 0.0
var _to: Node3D
var _from := Vector3.ZERO
var _yaw := 0.0

func start(at: Vector3, to: Node3D) -> void:
	global_position = at
	_from = at
	_to = to
	_yaw = randf() * TAU
	var m := StandardMaterial3D.new()
	m.albedo_color = Color8(214, 120, 128)
	m.roughness = 0.5
	var band := StandardMaterial3D.new()
	band.albedo_color = Color8(186, 92, 104)
	band.roughness = 0.5
	for i in SEGS:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w := 0.022 if i == 2 else 0.018
		bm.size = Vector3(w, w, 0.024)
		s.mesh = bm
		s.material_override = band if i == 2 else m
		add_child(s)
		_segs.append(s)

func _process(dt: float) -> void:
	_t += dt
	if _t < WRIGGLE_T:
		# a wave down its length, lifting its head
		for i in SEGS:
			var ph := _t * 12.0 - i * 0.9
			var along := Vector3(sin(_yaw), 0, cos(_yaw)) * (i * 0.022)
			var side := Vector3(cos(_yaw), 0, -sin(_yaw)) * sin(ph) * 0.012
			_segs[i].position = along + side + Vector3(0, maxf(0.0, (2 - i) * 0.01) * (0.5 + 0.5 * sin(_t * 6.0)), 0)
			_segs[i].rotation.y = _yaw + cos(ph) * 0.4
		return
	var k := (_t - WRIGGLE_T) / GO_T
	if k >= 1.0 or not is_instance_valid(_to):
		queue_free()
		return
	var goal := _to.global_position + Vector3(0, 1.0, 0)
	global_position = _from.lerp(goal, k) + Vector3(0, sin(k * PI) * 0.4, 0)
	scale = Vector3.ONE * (1.0 - k * 0.7)
