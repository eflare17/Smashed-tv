class_name VoxelDebris
extends MultiMeshInstance3D
## The cubes a shot knocks out: thousands of little cubes in one draw call (a MultiMesh with a colour each), flung
## out, falling, bouncing and settling on the floor, then gone after a few seconds. Owned by the voxel session.

const MAX := 8000

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _col := PackedColorArray()
var _rot := []
var _need := PackedByteArray()        # its transform must be set again (moving, shrinking, or swapped into this slot)
var _n := 0
var _floor := 0.0
var prof_us := 0
var last_ms := 0.0

func setup(cube_m: float) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * cube_m
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	bm.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = bm
	multimesh.instance_count = MAX
	multimesh.visible_instance_count = 0
	_pos.resize(MAX)
	_vel.resize(MAX)
	_life.resize(MAX)
	_col.resize(MAX)
	_rot.resize(MAX)
	_need.resize(MAX)
	_floor = cube_m * 0.5
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func count() -> int:
	return _n

## Flings cubes out from where they were: bits = [{pos, col}], out along dir (the shot), with some spread.
func burst(bits: Array, dir: Vector3, power: float = 3.5) -> void:
	for b in bits:
		var i := _n
		if _n >= MAX:
			i = randi() % MAX            # full: reuse a random one
		else:
			_n += 1
		_pos[i] = b.pos
		var v := dir * power * randf_range(0.4, 1.2) + Vector3(randf_range(-1, 1), randf_range(0.5, 2.5), randf_range(-1, 1)) * power * 0.35
		_vel[i] = v
		_life[i] = randf_range(4.0, 7.0)
		_col[i] = b.col
		_rot[i] = Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
		_need[i] = 1

func _process(dt: float) -> void:
	if multimesh == null:
		return
	var t0 := Time.get_ticks_usec()
	var i := 0
	while i < _n:
		_life[i] -= dt
		if _life[i] <= 0.0:
			_n -= 1
			_pos[i] = _pos[_n]
			_vel[i] = _vel[_n]
			_life[i] = _life[_n]
			_col[i] = _col[_n]
			_rot[i] = _rot[_n]
			_need[i] = 1
			continue
		var v := _vel[i]
		var p := _pos[i]
		var moving := v.length_squared() > 0.0001 or p.y > _floor + 0.001
		if moving:
			v.y -= 9.8 * dt
			p += v * dt
			if p.y < _floor:
				p.y = _floor
				v.y = -v.y * 0.25
				v.x *= 0.55
				v.z *= 0.55
				if absf(v.y) < 0.3:
					v = Vector3.ZERO
			_vel[i] = v
			_pos[i] = p
		var s := clampf(_life[i] / 0.6, 0.0, 1.0)      # shrinks away at the end
		if moving or s < 1.0 or _need[i] == 1:
			multimesh.set_instance_transform(i, Transform3D((_rot[i] as Basis).scaled(Vector3.ONE * s), p))
			if _need[i] == 1:
				multimesh.set_instance_color(i, _col[i])
			_need[i] = 0
		i += 1
	multimesh.visible_instance_count = _n
	prof_us += Time.get_ticks_usec() - t0
	last_ms = lerpf(last_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)
