class_name VoxelFlames
extends MultiMeshInstance3D
## Flames as little glowing cubes (one draw call): each rises from where it was lit, wavering, shrinking, going from
## white-yellow through orange to a dull red as it dies. Burning bodies (VoxelBody.status_step's flames) and the
## flamethrower's stream light them. Owned by the voxel session.

const MAX := 2500

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _span := PackedFloat32Array()
var _size := PackedFloat32Array()
var _n := 0
var _cube := 0.03

func setup(cube_m: float) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cube = cube_m
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = bm
	multimesh.instance_count = MAX
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pos.resize(MAX)
	_vel.resize(MAX)
	_life.resize(MAX)
	_span.resize(MAX)
	_size.resize(MAX)

func count() -> int:
	return _n

## n flames lit at p, thrown at vel (plus a little rise and spread), size times a cube (about), living about life s.
func emit(p: Vector3, n: int = 1, vel: Vector3 = Vector3.ZERO, size: float = 2.5, life: float = 0.7) -> void:
	for k in n:
		var i := _n
		if _n >= MAX:
			i = randi() % MAX
		else:
			_n += 1
		_pos[i] = p + Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)) * _cube * 1.5
		_vel[i] = vel + Vector3(randf_range(-0.25, 0.25), randf_range(0.5, 1.2), randf_range(-0.25, 0.25))
		var sp := life * randf_range(0.6, 1.3)
		_life[i] = sp
		_span[i] = sp
		_size[i] = size * randf_range(0.6, 1.4)

func _process(dt: float) -> void:
	if multimesh == null:
		return
	var i := 0
	while i < _n:
		_life[i] -= dt
		if _life[i] <= 0.0:
			_n -= 1
			_pos[i] = _pos[_n]
			_vel[i] = _vel[_n]
			_life[i] = _life[_n]
			_span[i] = _span[_n]
			_size[i] = _size[_n]
			continue
		var k := _life[i] / _span[i]                     # 1 just lit .. 0 out
		var v := _vel[i]
		v.y += 1.6 * dt                                   # hot air rises
		v *= exp(-dt * 1.5)
		_vel[i] = v
		_pos[i] += v * dt + Vector3(sin(_life[i] * 23.0 + i), 0, cos(_life[i] * 19.0 + i)) * 0.15 * dt
		var col := Color(1.0, 0.85, 0.45).lerp(Color(1.0, 0.45, 0.08), clampf((1.0 - k) * 1.6, 0.0, 1.0))
		col = col.lerp(Color(0.5, 0.08, 0.02), clampf((0.45 - k) * 2.2, 0.0, 1.0))
		col.a = clampf(k * 1.4, 0.0, 1.0)
		var s := _cube * _size[i] * (0.4 + 0.6 * k)
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), _pos[i]))
		multimesh.set_instance_color(i, col)
		i += 1
	multimesh.visible_instance_count = _n
