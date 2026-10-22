extends Node3D
## Smash arcade: death effects. A kill pops into a few voxel chunks (they fly, bounce, settle and shrink away)
## and leaves a blood splat on the floor that fades out. Both are pooled (packed arrays, swap-remove) and drawn
## by one MultiMesh each, with a per-instance colour. When a pool is full the oldest-ish slot is reused.

const Vox := preload("smash_vox.gd")

const MAX_CHUNKS := 3000
const MAX_SPLATS := 600
const CHUNK := 0.2
const CHUNK_LIFE := 2.8
const SPLAT_LIFE := 6.0
const SPLAT_FADE := 2.0
const GRAVITY := 22.0

var half := 12.0
var door_half := 1.5

var chunks := 0
var c_pos := PackedVector3Array()
var c_vel := PackedVector3Array()
var c_age := PackedFloat32Array()
var c_size := PackedFloat32Array()
var c_spin := PackedFloat32Array()
var c_col := PackedColorArray()
var _c_reuse := 0

var splats := 0
var s_pos := PackedVector2Array()
var s_rot := PackedVector2Array()
var s_size := PackedFloat32Array()
var s_age := PackedFloat32Array()
var _s_reuse := 0

var _c_mm: MultiMesh
var _s_mm: MultiMesh
var _c_buf := PackedFloat32Array()
var _s_buf := PackedFloat32Array()

func _init() -> void:
	name = "Gibs"
	c_pos.resize(MAX_CHUNKS)
	c_vel.resize(MAX_CHUNKS)
	c_age.resize(MAX_CHUNKS)
	c_size.resize(MAX_CHUNKS)
	c_spin.resize(MAX_CHUNKS)
	c_col.resize(MAX_CHUNKS)
	s_pos.resize(MAX_SPLATS)
	s_rot.resize(MAX_SPLATS)
	s_size.resize(MAX_SPLATS)
	s_age.resize(MAX_SPLATS)
	_c_buf.resize(MAX_CHUNKS * 16)
	_s_buf.resize(MAX_SPLATS * 16)

	var cmesh := Vox.box_mesh(Vector3.ONE * CHUNK, Color.WHITE)
	cmesh.surface_set_material(0, Vox.flat_material())
	_c_mm = _multimesh(cmesh, MAX_CHUNKS)

	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	smat.vertex_color_is_srgb = true
	smat.albedo_texture = Vox.splat_texture()
	smat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	plane.material = smat
	_s_mm = _multimesh(plane, MAX_SPLATS)

func _multimesh(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 8, 40))
	add_child(mi)
	return mm

func clear() -> void:
	chunks = 0
	splats = 0

## `n` chunks from `colors` bursting out of a body at `p`, pushed along `dir` (the bullet's), plus a splat.
func burst(p: Vector2, dir: Vector2, colors: Array, n: int) -> void:
	for k in n:
		var i := chunks
		if i < MAX_CHUNKS:
			chunks += 1
		else:
			i = _c_reuse
			_c_reuse = (_c_reuse + 1) % MAX_CHUNKS
		var a := randf() * TAU
		var out := Vector2(cos(a), sin(a)) * randf_range(1.0, 3.5) + dir * randf_range(2.0, 5.0)
		c_pos[i] = Vector3(p.x, randf_range(0.3, 0.9), p.y)
		c_vel[i] = Vector3(out.x, randf_range(3.0, 7.0), out.y)
		c_age[i] = randf() * 0.4
		c_size[i] = randf_range(0.7, 1.3)
		c_spin[i] = randf() * TAU
		c_col[i] = colors[randi() % colors.size()]
	var j := splats
	if j < MAX_SPLATS:
		splats += 1
	else:
		j = _s_reuse
		_s_reuse = (_s_reuse + 1) % MAX_SPLATS
	var r := randf() * TAU
	s_pos[j] = p + dir * 0.3
	s_rot[j] = Vector2(cos(r), sin(r))
	s_size[j] = randf_range(1.1, 1.8)
	s_age[j] = 0.0

func step(delta: float) -> void:
	var wall := half - CHUNK
	var i := 0
	while i < chunks:
		var age := c_age[i] + delta
		if age >= CHUNK_LIFE:
			chunks -= 1
			c_pos[i] = c_pos[chunks]
			c_vel[i] = c_vel[chunks]
			c_age[i] = c_age[chunks]
			c_size[i] = c_size[chunks]
			c_spin[i] = c_spin[chunks]
			c_col[i] = c_col[chunks]
			continue
		c_age[i] = age
		var v := c_vel[i]
		var p := c_pos[i]
		if v != Vector3.ZERO:
			v.y -= GRAVITY * delta
			p += v * delta
			var floor_y := CHUNK * 0.5 * c_size[i]
			if p.y < floor_y:
				p.y = floor_y
				v = Vector3(v.x * 0.55, -v.y * 0.35, v.z * 0.55)
				if absf(v.y) < 0.8:
					v = Vector3.ZERO
			# bounce off the walls, except through a door gap
			if absf(p.x) > wall and absf(p.z) > door_half:
				p.x = signf(p.x) * wall
				v.x = -v.x * 0.5
			if absf(p.z) > wall and absf(p.x) > door_half:
				p.z = signf(p.z) * wall
				v.z = -v.z * 0.5
			c_spin[i] += delta * 9.0
			c_vel[i] = v
			c_pos[i] = p
		i += 1

	i = 0
	while i < splats:
		var age := s_age[i] + delta
		if age >= SPLAT_LIFE:
			splats -= 1
			s_pos[i] = s_pos[splats]
			s_rot[i] = s_rot[splats]
			s_size[i] = s_size[splats]
			s_age[i] = s_age[splats]
			continue
		s_age[i] = age
		i += 1

func draw() -> void:
	for i in chunks:
		var p := c_pos[i]
		# shrink away over the last half second
		var s := c_size[i] * minf(1.0, (CHUNK_LIFE - c_age[i]) * 2.0)
		var sp := c_spin[i]
		var cs := cos(sp) * s
		var sn := sin(sp) * s
		var col := c_col[i]
		var o := i * 16
		_c_buf[o] = cs; _c_buf[o + 1] = 0.0; _c_buf[o + 2] = sn; _c_buf[o + 3] = p.x
		_c_buf[o + 4] = 0.0; _c_buf[o + 5] = s; _c_buf[o + 6] = 0.0; _c_buf[o + 7] = p.y
		_c_buf[o + 8] = -sn; _c_buf[o + 9] = 0.0; _c_buf[o + 10] = cs; _c_buf[o + 11] = p.z
		_c_buf[o + 12] = col.r; _c_buf[o + 13] = col.g; _c_buf[o + 14] = col.b; _c_buf[o + 15] = 1.0
	_c_mm.buffer = _c_buf
	_c_mm.visible_instance_count = chunks

	var blood := Vox.BLOOD
	for i in splats:
		var p := s_pos[i]
		var r := s_rot[i] * s_size[i]
		var a := minf(1.0, (SPLAT_LIFE - s_age[i]) / SPLAT_FADE) * 0.9
		var o := i * 16
		# newer splats sit a hair higher so overlaps don't flicker
		_s_buf[o] = r.x; _s_buf[o + 1] = 0.0; _s_buf[o + 2] = r.y; _s_buf[o + 3] = p.x
		_s_buf[o + 4] = 0.0; _s_buf[o + 5] = 1.0; _s_buf[o + 6] = 0.0; _s_buf[o + 7] = 0.02 + (SPLAT_LIFE - s_age[i]) * 0.001
		_s_buf[o + 8] = -r.y; _s_buf[o + 9] = 0.0; _s_buf[o + 10] = r.x; _s_buf[o + 11] = p.y
		_s_buf[o + 12] = blood.r; _s_buf[o + 13] = blood.g; _s_buf[o + 14] = blood.b; _s_buf[o + 15] = a
	_s_mm.buffer = _s_buf
	_s_mm.visible_instance_count = splats
