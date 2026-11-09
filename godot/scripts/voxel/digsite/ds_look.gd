class_name DsLook
extends Node
## How the Dig Site looks (the owner, 8 Nov: "the web version looks miles ahead of it"): the digger game's cel-shaded
## look, brought over. While you're at the site the arena's sky, sun and tonemapping are swapped for the site's own
## (a painted sky with clouds, a warm sun with crisp shadows, flat ambient light, linear tonemapping, deeper SSAO)
## and swapped back when you go home; every Dig Site material is toon lit (shaders/ds_toon.gdshaderinc); black ink
## lines are drawn from the depth buffer (shaders/ds_outline.gdshader); the camera's field of view narrows to the
## digger game's 52 degrees. Owned by the voxel session.

const FOV := 52.0
const SUN_COMPAT := 0.5         # (the digger game's SUN_WEB: the compatibility renderer lights brighter; on it the sun's halved)
const BLADES_PER_M2 := 64.0     # the digger game's "High" grass (its most: a PC has room for it)

static var _noise: ImageTexture
static var _prop: ShaderMaterial
static var _ground: ShaderMaterial
static var _grass: ShaderMaterial
static var _clod: ShaderMaterial
static var _blade: ArrayMesh
static var _clods: Array = []
static var _flats := {}

var site: Node3D
var env: Environment
var _we: WorldEnvironment
var _arena_env: Environment
var _sun_was := {}
var _fov_was := 80.0
var _outline: MeshInstance3D
var on := false

## The shared noise picture (the sky's clouds, the ground's patches)
static func noise() -> ImageTexture:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.seed = 3
		fn.frequency = 0.02
		fn.fractal_octaves = 3
		_noise = ImageTexture.create_from_image(fn.get_seamless_image(256, 256))
	return _noise

## The toon material for vertex-coloured meshes (the machines, the props)
static func prop_mat() -> ShaderMaterial:
	if _prop == null:
		_prop = ShaderMaterial.new()
		_prop.shader = load("res://scripts/voxel/digsite/shaders/ds_prop.gdshader")
	return _prop

## The ground's material (shaders/ds_ground.gdshader): grass, soil, lumpy loose dirt, rock, cavity shade
static func ground_mat() -> ShaderMaterial:
	if _ground == null:
		_ground = ShaderMaterial.new()
		_ground.shader = load("res://scripts/voxel/digsite/shaders/ds_ground.gdshader")
		_ground.set_shader_parameter("noise_tex", noise())
		_ground.set_shader_parameter("clods_tex", load("res://scenes/voxel/digsite/clods.png"))
	return _ground

## The grass blades' material and mesh (a short, wide blade: five corners, three triangles)
static func grass_mat() -> ShaderMaterial:
	if _grass == null:
		_grass = ShaderMaterial.new()
		_grass.shader = load("res://scripts/voxel/digsite/shaders/ds_grass.gdshader")
		_grass.set_shader_parameter("noise_tex", noise())
		_grass.render_priority = 1
	return _grass

static func blade_mesh() -> ArrayMesh:
	if _blade == null:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.045, 0, 0), Vector3(0.045, 0, 0), Vector3(-0.03, 0.12, 0.012), Vector3(0.03, 0.12, 0.012), Vector3(0.008, 0.26, 0.05)])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.46), Vector2(1, 0.46), Vector2(0.5, 1)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3, 2, 3, 4])
		_blade = ArrayMesh.new()
		_blade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _blade

## The clods' material and meshes (three lumps: twelve corners each, nudged)
static func clod_mat() -> ShaderMaterial:
	if _clod == null:
		_clod = ShaderMaterial.new()
		_clod.shader = load("res://scripts/voxel/digsite/shaders/ds_clod.gdshader")
		_clod.render_priority = 1
	return _clod

static func clod_mesh(k: int) -> ArrayMesh:
	if _clods.is_empty():
		var gr := RandomNumberGenerator.new()
		gr.seed = 29
		const T := 1.618034
		var corners := [Vector3(-1, T, 0), Vector3(1, T, 0), Vector3(-1, -T, 0), Vector3(1, -T, 0), Vector3(0, -1, T), Vector3(0, 1, T), Vector3(0, -1, -T), Vector3(0, 1, -T), Vector3(T, 0, -1), Vector3(T, 0, 1), Vector3(-T, 0, -1), Vector3(-T, 0, 1)]
		for i in 3:
			var points := PackedVector3Array()
			for c: Vector3 in corners:
				points.append(c.normalized() * gr.randf_range(0.72, 1.12))
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = points
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 5, 11, 0, 1, 5, 0, 7, 1, 0, 10, 7, 0, 11, 10, 1, 9, 5, 5, 4, 11, 11, 2, 10, 10, 6, 7, 7, 8, 1, 3, 4, 9, 3, 2, 4, 3, 6, 2, 3, 8, 6, 3, 9, 8, 4, 5, 9, 2, 11, 4, 6, 10, 2, 8, 7, 6, 9, 1, 8])
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			_clods.append(m)
	return _clods[posmod(k, 3)]

## A toon material in one colour (shared by colour)
static func flat(c: Color) -> Material:
	var k := c.to_html(false)
	if not _flats.has(k):
		var m := ShaderMaterial.new()
		m.shader = load("res://scripts/voxel/digsite/shaders/ds_flat.gdshader")
		m.set_shader_parameter("albedo", Vector3(c.r, c.g, c.b))
		_flats[k] = m
	return _flats[k]

func setup(s: Node3D) -> void:
	site = s
	name = "Look"
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://scripts/voxel/digsite/shaders/ds_sky.gdshader")
	sky_mat.set_shader_parameter("noise_tex", noise())
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a8b8d8")
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.ssao_power = 1.3
	env.ssao_light_affect = 0.15
	env.glow_enabled = false
	# a light haze with distance (the trees and the far fence go a little blue): what a browser doesn't get
	env.fog_enabled = true
	env.fog_light_color = Color("#c4d3e8")
	env.fog_density = 0.0035
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	# the ink: a quad over the whole view, drawn last, that paints only the lines
	var om := ShaderMaterial.new()
	om.shader = load("res://scripts/voxel/digsite/shaders/ds_outline.gdshader")
	om.render_priority = 0
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	q.material = om
	_outline = MeshInstance3D.new()
	_outline.mesh = q
	_outline.extra_cull_margin = 16384.0
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline.visible = false
	add_child(_outline)

## Arriving: the site's sky, sun and camera
func enter() -> void:
	if on:
		return
	on = true
	var a = site.arena
	if _we == null:
		for c in a.get_children():
			if c is WorldEnvironment:
				_we = c
	if _we:
		_arena_env = _we.environment
		_we.environment = env
	var sun: DirectionalLight3D = a.sun
	if sun:
		_sun_was = {"rot": sun.rotation, "col": sun.light_color, "e": sun.light_energy, "blur": sun.shadow_blur, "bias": sun.shadow_bias,
			"nbias": sun.shadow_normal_bias, "mode": sun.directional_shadow_mode, "dist": sun.directional_shadow_max_distance, "split": sun.directional_shadow_split_1}
		sun.rotation_degrees = Vector3(-47.0, -38.0, 0.0)
		sun.light_color = Color("#fff1d2")
		sun.light_energy = 0.72 * (SUN_COMPAT if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1.0)
		sun.shadow_blur = 0.0
		sun.shadow_bias = 0.7
		sun.shadow_normal_bias = 3.5
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 110.0
		sun.directional_shadow_split_1 = 0.22
	_fov_was = a.base_fov
	a.base_fov = FOV
	_outline.visible = true

## Going home: the arena's back
func leave() -> void:
	if not on:
		return
	on = false
	var a = site.arena
	if _we and _arena_env:
		_we.environment = _arena_env
	var sun: DirectionalLight3D = a.sun
	if sun and not _sun_was.is_empty():
		sun.rotation = _sun_was.rot
		sun.light_color = _sun_was.col
		sun.light_energy = _sun_was.e
		sun.shadow_blur = _sun_was.blur
		sun.shadow_bias = _sun_was.bias
		sun.shadow_normal_bias = _sun_was.nbias
		sun.directional_shadow_mode = _sun_was.mode
		sun.directional_shadow_max_distance = _sun_was.dist
		sun.directional_shadow_split_1 = _sun_was.split
	a.base_fov = _fov_was
	_outline.visible = false
