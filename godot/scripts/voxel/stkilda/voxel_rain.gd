class_name VoxelRain
extends Node3D
## Rain in St Kilda (the owner, 30 Oct: "a raining mod with puddles and relctions"): K starts it, K stops it, easing in
## and out over a few seconds. Rain falls round you (streaks, wherever you go) and splashes on the ground; the sky goes
## grey and the sun dims (by day or night: it's laid over SkDayNight's look); everything goes darker and glossier,
## wet; and puddles fill in the open, flat places (the roads, the paths, between the rides) over the first minute,
## drops ringing them, and dry up again after. The puddles are near mirrors: they and the wet ground reflect what's
## round them (the screen's reflections, SSR, on the Medium setting and up; on Low just the sky). No sound. Owned by
## the St Kilda session.

const EASE_T := 4.0             # seconds the rain takes to come or go
const FILL_T := 60.0            # seconds the puddles take to fill
const DRY_T := 90.0             # ... and to dry up
const PUDDLES := 320            # puddles about (at most: more near the middle)
const NEAR_R := 110.0           # metres round Luna Park they're put in
const AREA := 44.0              # the rain's box round you, across
const DROPS_HI := 9000
const DROPS_LO := 3500
const SPLASHES := 1600

var sk: VoxelStKilda
var raining := false
var w := 0.0                    # 0 dry, 1 pouring
var fill := 0.0                 # how full the puddles are, 0 to 1
var _drops: GPUParticles3D
var _splash: GPUParticles3D
var _puddles: MultiMeshInstance3D
var _puddle_mat: ShaderMaterial
var _placed := false
var _last := Vector2(-1, -1)    # (w, the day-night) last laid on
var _baked_rough := 0.8
var _arrived := 0

func setup(s: VoxelStKilda) -> void:
	sk = s
	name = "VoxelRain"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_baked_rough = SkModels.baked_material().roughness
	_drops = _drops_node()
	_splash = _splash_node()
	add_child(_drops)
	add_child(_splash)
	_puddle_mat = ShaderMaterial.new()
	_puddle_mat.shader = Shader.new()
	_puddle_mat.shader.code = PUDDLE
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2.ONE
	q.material = _puddle_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = PUDDLES
	mm.visible_instance_count = 0
	_puddles = MultiMeshInstance3D.new()
	_puddles.name = "Puddles"
	_puddles.multimesh = mm
	_puddles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puddles.visible = false
	add_child(_puddles)

## You've arrived (VoxelStKilda.go): the puddles get put about in a few frames.
func arrived() -> void:
	_arrived = Engine.get_process_frames()

func toggle() -> void:
	raining = not raining

## Dry again at once (the tests).
func dry() -> void:
	raining = false
	w = 0.0
	fill = 0.0
	_lay()

func _process(dt: float) -> void:
	w = move_toward(w, 1.0 if raining else 0.0, dt / EASE_T)
	fill = move_toward(fill, 1.0 if raining else 0.0, dt / (FILL_T if raining else DRY_T))
	if not _placed and sk.active and (w > 0.0 or Engine.get_process_frames() > _arrived + 10):     # (just after you arrive: a moment's work)
		_place_puddles()
	var cam := get_viewport().get_camera_3d()
	if cam:
		var c := cam.global_position
		_drops.global_position = Vector3(c.x, c.y + 14.0, c.z) + cam.global_transform.basis.z * -8.0
		var ground := sk.global_position.y
		_splash.global_position = Vector3(c.x, ground + 0.04, c.z) + cam.global_transform.basis.z * -6.0
	_drops.emitting = w > 0.01
	_splash.emitting = w > 0.05
	_drops.amount_ratio = w
	_splash.amount_ratio = w
	_puddles.visible = fill > 0.01
	_puddle_mat.set_shader_parameter("fill", fill)
	_puddle_mat.set_shader_parameter("rain", w)
	var dn := sk.day_night
	var now := Vector2(w, dn.t)
	if not now.is_equal_approx(_last):
		_last = now
		_lay()

# the day's (or night's) look, then the rain's laid over it: grey sky, dim sun, haze; wet, darker and glossier
func _lay() -> void:
	var dn := sk.day_night
	dn._apply()
	var k := smoothstep(0.0, 1.0, w)
	var night := smoothstep(0.0, 1.0, dn.t)
	var e := sk.env
	sk.sun.light_energy *= lerpf(1.0, 0.28, k)
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	var grey_top := Color("#5d6670").lerp(Color("#0b0f17"), night)
	var grey_low := Color("#8e979f").lerp(Color("#1a2130"), night)
	sm.sky_top_color = sm.sky_top_color.lerp(grey_top, k * 0.85)
	sm.sky_horizon_color = sm.sky_horizon_color.lerp(grey_low, k * 0.85)
	sm.sky_cover_modulate = Color(1, 1, 1, lerpf(sm.sky_cover_modulate.a, 1.0, k))
	sm.sun_angle_max = lerpf(sm.sun_angle_max, 1.0, k)
	e.fog_light_color = e.fog_light_color.lerp(grey_low, k)
	e.fog_density = lerpf(0.0009, 0.0045, k)
	e.ambient_light_energy *= lerpf(1.0, 0.85, k)
	# (the screen's reflections: on in the rain, Medium and up, and the Forward+ renderer)
	var s = sk.arena.settings_menu.s if sk.arena and sk.arena.settings_menu else null
	var good: bool = s == null or String(s.preset) != "low"
	e.ssr_enabled = k > 0.05 and good and RenderingServer.get_current_rendering_method() == "forward_plus"
	e.ssr_max_steps = 256                     # (far enough up the screen to reach a building across the square)
	e.ssr_fade_in = 0.15
	e.ssr_fade_out = 2.0
	e.ssr_depth_tolerance = 1.2
	# (the sky in the wet: St Kilda's dry look has no reflections of it at all)
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if k > 0.05 else Environment.REFLECTION_SOURCE_DISABLED
	# wet: the town's and the park's own paint darker and glossier
	var bm := SkModels.baked_material()
	bm.roughness = lerpf(_baked_rough, 0.32, k)
	bm.albedo_color = Color(1, 1, 1).lerp(Color(0.72, 0.74, 0.78), k)
	bm.metallic_specular = lerpf(0.5, 0.7, k)
	# (the drops and splashes catch less light at night)
	var lit := lerpf(1.0, 0.35, night)
	((_drops.draw_pass_1 as QuadMesh).material as StandardMaterial3D).albedo_color = Color(0.82 * lit, 0.86 * lit, 0.92 * lit, 0.3)
	((_splash.draw_pass_1 as QuadMesh).material as StandardMaterial3D).albedo_color = Color(0.85 * lit, 0.9 * lit, 0.95 * lit)

# the streaks: falling straight down (a little slant), round wherever you are
func _drops_node() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Drops"
	var hi := true
	if sk.arena and sk.arena.settings_menu:
		hi = String(sk.arena.settings_menu.s.preset) not in ["low", "medium"]
	p.amount = DROPS_HI if hi else DROPS_LO
	p.lifetime = 1.3
	p.preprocess = 1.3
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-AREA, -30, -AREA), Vector3(AREA * 2, 40, AREA * 2))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(AREA * 0.5, 2.0, AREA * 0.5)
	m.direction = Vector3(0.08, -1, 0.04)
	m.spread = 2.0
	m.initial_velocity_min = 16.0
	m.initial_velocity_max = 20.0
	m.gravity = Vector3(0, -6, 0)
	m.particle_flag_align_y = true
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.013, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.82, 0.86, 0.92, 0.32)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.use_particle_trails = false
	q.material = mat
	p.draw_pass_1 = q
	p.emitting = false
	return p

# the splashes: little white bursts on the ground round you
func _splash_node() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Splashes"
	p.amount = SPLASHES
	p.lifetime = 0.28
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-AREA, -2, -AREA), Vector3(AREA * 2, 4, AREA * 2))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(AREA * 0.35, 0.0, AREA * 0.35)
	m.direction = Vector3.UP
	m.spread = 35.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 1.4
	m.gravity = Vector3(0, -9.8, 0)
	m.scale_min = 0.6
	m.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.3))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	m.color_ramp = ft
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.03)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.85, 0.9, 0.95)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	p.draw_pass_1 = q
	p.emitting = false
	return p

# where the puddles go: the open, flat ground near Luna Park (straight down from above, the first thing hit is the
# ground: not a roof, a ride or a bench)
func _place_puddles() -> void:
	_placed = true
	var space := get_world_3d().direct_space_state
	var mid := sk.arrive_spot()[0] as Vector3
	var ground := sk.global_position.y
	var rng := RandomNumberGenerator.new()
	rng.seed = 30101
	var tops := _ground_tops(mid, NEAR_R + 6.0)
	var mm := _puddles.multimesh
	var n := 0
	var tries := 0
	while n < PUDDLES and tries < PUDDLES * 12:
		tries += 1
		var a := rng.randf() * TAU
		var r := pow(rng.randf(), 0.8) * NEAR_R
		var at := mid + Vector3(cos(a) * r, 0, sin(a) * r)
		var size := rng.randf_range(1.6, 5.5)
		var ok := true
		var top := INF
		# its middle and four points round its edge, each straight onto open ground, all on the one surface (as drawn:
		# the road, the paving, the grass are each a little higher or lower)
		for off in [Vector3.ZERO, Vector3(size * 0.4, 0, 0), Vector3(-size * 0.4, 0, 0), Vector3(0, 0, size * 0.4), Vector3(0, 0, -size * 0.4)]:
			var q := PhysicsRayQueryParameters3D.create(at + off + Vector3.UP * 30.0, at + off + Vector3.DOWN * 2.0)
			q.collision_mask = 1 | SkData.LAYER_WORLD
			var hit := space.intersect_ray(q)
			if hit.is_empty() or absf((hit.position as Vector3).y - ground) > 0.25 or (hit.normal as Vector3).y < 0.97:
				ok = false
				break
			var c := Vector2i(floori((at.x + off.x) / CELL), floori((at.z + off.z) / CELL))
			if not tops.has(c) or (top != INF and absf(float(tops[c]) - top) > 0.012):
				ok = false
				break
			top = float(tops[c])
		if not ok:
			continue
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, 1, size * rng.randf_range(0.55, 1.0)))
		mm.set_instance_transform(n, Transform3D(b, Vector3(at.x, top + 0.012, at.z)))
		mm.set_instance_custom_data(n, Color(rng.randf(), rng.randf(), rng.randf_range(0.3, 1.0), 0))
		n += 1
	mm.visible_instance_count = n

const CELL := 0.5               # the ground's height map's cell

# How high the ground's drawn, CELL by CELL, within r of mid: the highest flat (facing up), low (under 0.4 m) bit of
# any mesh there (the roads, paving, grass, the kerbs' tops, shade patches)
func _ground_tops(mid: Vector3, r: float) -> Dictionary:
	var tops := {}
	for mi in sk.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null or not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		var gx := (mi as MeshInstance3D).global_transform
		var box := gx * m.get_aabb()
		if box.position.y > 0.4 or box.position.x > mid.x + r or box.end.x < mid.x - r or box.position.z > mid.z + r or box.end.z < mid.z - r:
			continue
		for s in m.get_surface_count():
			if m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := m.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var tris := ix.size() / 3 if ix.size() > 0 else vs.size() / 3
			for t in tris:
				var a := gx * vs[ix[t * 3] if ix.size() > 0 else t * 3]
				var b := gx * vs[ix[t * 3 + 1] if ix.size() > 0 else t * 3 + 1]
				var c := gx * vs[ix[t * 3 + 2] if ix.size() > 0 else t * 3 + 2]
				if maxf(a.y, maxf(b.y, c.y)) > 0.4 or absf((b - a).cross(c - a).normalized().y) < 0.97:
					continue
				var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
				var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
				if lo.x > mid.x + r or hi.x < mid.x - r or lo.y > mid.z + r or hi.y < mid.z - r:
					continue
				var y := (a.y + b.y + c.y) / 3.0
				for cx in range(floori(maxf(lo.x, mid.x - r) / CELL), floori(minf(hi.x, mid.x + r) / CELL) + 1):
					for cz in range(floori(maxf(lo.y, mid.z - r) / CELL), floori(minf(hi.y, mid.z + r) / CELL) + 1):
						var p := Vector2((cx + 0.5) * CELL, (cz + 0.5) * CELL)
						if Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)):
							var k := Vector2i(cx, cz)
							if not tops.has(k) or y > float(tops[k]):
								tops[k] = y
	return tops

## How many puddles there are (the tests).
func puddles() -> int:
	return _puddles.multimesh.visible_instance_count

const PUDDLE := """
shader_type spatial;
render_mode cull_disabled;
// a puddle: an irregular patch of near-mirror water (opaque, so the screen's reflections land on it), its size the fill
// (the low middle first), drops ringing it while it rains

uniform float fill = 1.0;
uniform float rain = 1.0;
varying vec4 seed;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	seed = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 uv = UV - 0.5;
	vec2 s = seed.xy * 40.0;
	float shape = 0.5 - length(uv) * 1.05 + (vnoise(uv * 3.0 + s) - 0.5) * 0.5 + (vnoise(uv * 7.0 + s * 1.7) - 0.5) * 0.18;
	float need = mix(0.42, 0.0, fill * seed.z);
	if (shape < need || fill * seed.z < 0.02) {
		discard;
	}
	// rings: a few drops a second in each cell, each a ring spreading and fading
	vec2 wp = (MODEL_MATRIX * vec4(UV.x - 0.5, 0.0, UV.y - 0.5, 1.0)).xz;
	vec2 nrm = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 g = wp * 1.6 + float(k) * 17.3;
		vec2 cell = floor(g);
		for (int dx = -1; dx <= 1; dx++) {
			for (int dy = -1; dy <= 1; dy++) {
				vec2 c = cell + vec2(float(dx), float(dy));
				float r = h21(c + float(k) * 3.1);
				vec2 centre = c + vec2(h21(c * 1.7), h21(c * 2.3));
				float t = fract(TIME * 0.9 + r);
				vec2 d = g - centre;
				float dist = length(d);
				float ring = sin((dist - t * 0.9) * 40.0) * smoothstep(0.12, 0.0, abs(dist - t * 0.9)) * (1.0 - t);
				nrm += normalize(d + 1e-4) * ring;
			}
		}
	}
	nrm *= 0.12 * rain;
	vec3 n = normalize(vec3(nrm.x, 1.0, nrm.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float edge = smoothstep(need, need + 0.08, shape);
	// (more of a mirror than real water is: in a game puddles should read as reflections)
	ALBEDO = mix(vec3(0.08, 0.08, 0.09), vec3(0.62, 0.64, 0.67), edge);
	ROUGHNESS = mix(0.3, 0.02, edge);
	METALLIC = mix(0.0, 0.9, edge);
	SPECULAR = 0.8;
}
"""
