class_name LookPass
extends Node
## The look pass (1.5): the HTML game's pictures in a lit 3D world, HD-2D style. Owned by the Lighting session;
## LightingInstall adds it.
##
## How the art survives the lighting: the World draws everything unshaded with the HTML game's shading already in
## its pictures. This swaps those materials for lit ones (the same picture, nearest filtered, the same vertex
## colours) whose light is mostly a strong, even ambient (the day's colour) plus a gentler sun, so a sunlit
## floor comes out about as the HTML game drew it and the shade of a wall or a character is a soft darkening of
## it, never black. The surfaces have no normals of their own, so the lit shader works each face's out from the
## screen (flat, always toward the camera: both sides of a wall light the same way).
##
## Characters (every CharSprite, now and later) are lit too, with a normal tipped up to the sky so the sun
## reaches them from any side, and each gets a shadow caster: an invisible copy of its picture that stands
## broadside to the sun (a Y billboard in the light's own view), so the sun throws the character's shape.
## The lounge's props (the cabinets, the slot machine...) are lit the same way; the arcade screens and marquees
## glow. The pool's water ripples and is lit from below at night.
##
## The distance blur (first person, high): no depth texture in the Compatibility renderer, so the lit material does
## it, fading far-off surfaces into a smoothly filtered, softer copy of their picture.
##
## Quality: "high" (desktop: sun shadows in two splits, every lamp, the distance blur in first person, glow)
## or "low" (phones: no shadows, a few lamps, no blur or glow). set_quality() switches; F8 toggles; the web
## build's address can say ?look=low or ?look=high.

const WORLD_SHADER := """
shader_type spatial;
render_mode cull_disabled%RENDER%%MODE%;
%LOWFN%
uniform sampler2D tex : source_color, %FILTER%, repeat_enable;
// the same picture, smoothly filtered: far-off things fade into it (first person's gentle distance blur)
uniform sampler2D tex_soft : source_color, filter_linear_mipmap, repeat_enable;
uniform float far_blur = 0.0;
uniform float blur_start = 12.0;
uniform float blur_full = 45.0;
uniform bool has_tex = false;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool srgb_vertex = true;
uniform float scissor = 0.5;
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void fragment() {
	vec4 c = albedo;
	c.rgb *= srgb_vertex ? to_linear(COLOR.rgb) : COLOR.rgb;
	c.a *= COLOR.a;
	if (has_tex) {
		vec4 t = texture(tex, UV);
		if (far_blur > 0.0) {
			float b = smoothstep(blur_start, blur_full, length(VERTEX)) * far_blur;
			if (b > 0.001) {
				t = mix(t, texture(tex_soft, UV, b * 2.0), b);
			}
		}
		c *= t;
	}
	ALBEDO = c.rgb;
	%ALPHA%
	%LIGHT%
}
"""

## The high look's light: real lights, so a normal. There are none in the mesh: the face's own, worked out on
## screen, turned toward the camera.
const HIGH_LIGHT := """
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, VERTEX) > 0.0 ? -n : n;
	ROUGHNESS = 1.0;
"""

## The low look (phones): unshaded, no light passes at all. The day's light is one colour (look_tint), and up to
## four lamps add warm pools by distance, worked out right in the material (global uniforms LookPass sets).
const LOW_FN := """
global uniform vec3 look_tint;
global uniform vec3 look_lamp_color;
global uniform float look_lamp_level;
global uniform vec4 look_lamp0;
global uniform vec4 look_lamp1;
global uniform vec4 look_lamp2;
global uniform vec4 look_lamp3;
float look_lamp(vec4 l, vec3 wp) {
	if (l.w <= 0.0) return 0.0;
	vec3 d = (l.xyz - wp) / l.w;
	float f = max(0.0, 1.0 - dot(d, d));
	return f * f;
}
vec3 look_light(vec3 wp) {
	float f = look_lamp(look_lamp0, wp) + look_lamp(look_lamp1, wp) + look_lamp(look_lamp2, wp) + look_lamp(look_lamp3, wp);
	return look_tint + look_lamp_color * look_lamp_level * f;
}
"""
const LOW_LIGHT := """
	ALBEDO *= look_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
"""
## The names and types of the low look's globals.
const GLOBALS := {"look_tint": RenderingServer.GLOBAL_VAR_TYPE_VEC3, "look_lamp_color": RenderingServer.GLOBAL_VAR_TYPE_VEC3,
	"look_lamp_level": RenderingServer.GLOBAL_VAR_TYPE_FLOAT, "look_lamp0": RenderingServer.GLOBAL_VAR_TYPE_VEC4,
	"look_lamp1": RenderingServer.GLOBAL_VAR_TYPE_VEC4, "look_lamp2": RenderingServer.GLOBAL_VAR_TYPE_VEC4,
	"look_lamp3": RenderingServer.GLOBAL_VAR_TYPE_VEC4}

## The normal that lights an upright picture (a character, a prop): toward the camera across the ground, tipped
## well up to the sky, so the sun lights it from behind as well (wrap lighting does the rest).
const PICTURE_NORMAL := """
	{
		vec3 back = INV_VIEW_MATRIX[2].xyz;
		vec3 hz = vec3(back.x, 0.0, back.z);
		hz = length(hz) > 0.001 ? normalize(hz) : vec3(0.0, 0.0, 1.0);
		vec3 nw = normalize(hz * 0.55 + vec3(0.0, 1.0, 0.0));
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
		ROUGHNESS = 1.0;
	}
"""

const CASTER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// A character's shadow: its picture as a Y billboard turned to whoever is looking. Only ever drawn into the
// sun's shadow map, where the one looking is the sun, so it stands broadside to the light.
uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cr = INV_VIEW_MATRIX[0].xyz;
	vec3 right = vec3(cr.x, 0.0, cr.z);
	right = length(right) > 0.0001 ? normalize(right) : vec3(1.0, 0.0, 0.0);
	vec3 p = origin + right * VERTEX.x * sx + vec3(0.0, 1.0, 0.0) * VERTEX.y * sy;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p, 1.0));
}
void fragment() {
	if (texture(tex, UV).a < 0.5) discard;
	ALBEDO = vec3(0.0);
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx, diffuse_lambert;
// The pool's water: its piece of the lounge picture, rippling, with a little shine; lit from below at night.
uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform float glow = 0.0;          // 0 by day, 1 at night (the pool light)
uniform vec3 glow_color : source_color = vec3(0.25, 0.85, 1.0);
void fragment() {
	vec2 uv = UV;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	uv += vec2(sin(wp.z * 9.0 + t * 1.7), cos(wp.x * 8.0 + t * 1.3)) * 0.0012;
	vec3 c = texture(tex, uv).rgb;
	float caus = sin(wp.x * 13.0 + t * 1.1) * sin(wp.z * 11.0 - t * 0.9);
	caus = smoothstep(0.55, 1.0, caus * 0.5 + 0.5);
	ALBEDO = c * (1.0 + caus * 0.18);
	ROUGHNESS = 0.25;
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(sin(wp.x * 20.0 + t) * 0.05, 1.0, cos(wp.z * 18.0 + t * 1.2) * 0.05, 0.0)).xyz);
	EMISSION = glow * glow_color * (0.35 + caus * 0.45) * (0.6 + c);
}
"""


## The arcade cabinets' glowing parts, as rectangles of their pictures (u0, v0, u1, v1): the screen and the
## marquee (read off scripts/world/props/cab_*.png).
const GLOW_RECTS := {
	"cab_miner": [Vector4(0.179, 0.212, 0.821, 0.5), Vector4(0.12, 0.045, 0.88, 0.115)],
	"cab_bricks": [Vector4(0.179, 0.212, 0.821, 0.5), Vector4(0.12, 0.045, 0.88, 0.115)],
	"slot": [Vector4(0.2, 0.25, 0.8, 0.55)],
}

var quality: String = "high"
## Drops to the low look by itself if the high one runs slowly (set false when the quality was asked for).
var auto_quality: bool = true
## The frame time (ms, the median) the high look must keep under, or it drops to low.
const SLOW_MS := 26.0
var _watch_t := 0.0
var _watch: Array = []
var _watch_last := 0
var main: Node
var day_night: DayNight
## The ambient's strength, the sun's, by quality (the day's colours come from DayNight).
var sun_shadows: bool = true

var _shaders: Dictionary = {}
var _chars: Array = []            # [CharSprite, caster Sprite3D, caster material]
var _props: Array = []            # ShaderMaterials of the lit props (their glow follows the time of day)
var _water: ShaderMaterial
var _blur_on := -1.0
var _full_caster: MeshInstance3D
var _full_mesh: MeshInstance3D
var _lit_nodes: Dictionary = {}   # instance id -> true: done

# ---------------------------------------------------------------- setting up

func setup(main_: Node, dn: DayNight) -> void:
	main = main_
	day_night = dn
	register_globals()
	_set_low_lamps.call_deferred()
	process_priority = 200        # after the World has shown or hidden its house for this frame's camera
	var world: Node = main.get("world")
	if world:
		light_tree(world)
		_world_extras(world)
	var tramp = main.get("trampoline")
	if tramp:
		light_tree(tramp)
		for mi in tramp.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON   # (its blended net and shadow can't)
	for n in main.get_tree().root.find_children("*", "CharSprite", true, false):
		_add_char(n)
	main.get_tree().node_added.connect(_on_node_added)
	var env: Environment = world.get("environment") if world else null
	if env:
		env.glow_enabled = true
		env.glow_intensity = 0.55
		env.glow_strength = 1.0
		env.glow_bloom = 0.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		env.glow_hdr_threshold = 0.95
		env.glow_hdr_scale = 1.5
		env.fog_depth_begin = 16.0
		env.fog_depth_end = 75.0
		env.fog_density = 0.55
		env.fog_sky_affect = 0.0
	var sun: DirectionalLight3D = main.get("sun")
	if sun:
		sun.shadow_enabled = true
		sun.shadow_bias = 0.03
		sun.shadow_normal_bias = 1.2
		sun.shadow_blur = 1.6
		sun.shadow_opacity = 0.85
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 40.0
		sun.directional_shadow_split_1 = 0.25
		sun.directional_shadow_blend_splits = false
		sun.light_specular = 0.0
	set_quality(quality)

func _on_node_added(n: Node) -> void:
	if n is CharSprite:
		_add_char.call_deferred(n)    # (its picture is made in its _ready)

## Lights every unshaded StandardMaterial3D in a tree (meshes' surfaces and overrides).
func light_tree(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		light_mesh(mi)
	if root is MeshInstance3D:
		light_mesh(root)

func light_mesh(mi: MeshInstance3D) -> void:
	if _lit_nodes.has(mi.get_instance_id()):
		return
	_lit_nodes[mi.get_instance_id()] = true
	if mi.material_override is StandardMaterial3D:
		var lm := lit_material(mi.material_override)
		if lm:
			mi.material_override = lm
	if mi.mesh:
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m == null:
				m = mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				var lm := lit_material(m)
				if lm:
					mi.set_surface_override_material(i, lm)
	if mi.material_override is ShaderMaterial and mi.name.begins_with("Prop_"):
		_light_prop(mi)

var _mat_cache: Dictionary = {}

## The lit version of an unshaded StandardMaterial3D (null to leave it: already lit, or added blending).
func lit_material(m: StandardMaterial3D) -> ShaderMaterial:
	if m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or m.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
		return null
	if _mat_cache.has(m):
		return _mat_cache[m]
	var mode := "opaque"
	if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		mode = "scissor"
	elif m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		mode = "alpha"
	var linear := m.texture_filter in [BaseMaterial3D.TEXTURE_FILTER_LINEAR, BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
		BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC]
	var sm := ShaderMaterial.new()
	sm.shader = _world_shader(mode, linear, quality == "high")
	sm.set_meta("look_variant", [mode, linear])
	sm.set_shader_parameter("albedo", m.albedo_color)
	sm.set_shader_parameter("has_tex", m.albedo_texture != null)
	if m.albedo_texture:
		sm.set_shader_parameter("tex", m.albedo_texture)
		sm.set_shader_parameter("tex_soft", m.albedo_texture)
	sm.set_shader_parameter("srgb_vertex", m.vertex_color_is_srgb if m.vertex_color_use_as_albedo else false)
	if not m.vertex_color_use_as_albedo:
		sm.set_shader_parameter("srgb_vertex", false)
	sm.set_shader_parameter("scissor", m.alpha_scissor_threshold)
	sm.render_priority = m.render_priority
	_mat_cache[m] = sm
	return sm

func _world_shader(mode: String, linear: bool, high: bool = true) -> Shader:
	var key := "w" + mode + str(linear) + str(high)
	if _shaders.has(key):
		return _shaders[key]
	var s := Shader.new()
	var alpha := ""
	var extra := ""
	match mode:
		"scissor":
			alpha = "ALPHA = c.a; ALPHA_SCISSOR_THRESHOLD = scissor;"
		"alpha":
			alpha = "ALPHA = c.a;"
			extra = ", depth_draw_opaque"
	s.code = WORLD_SHADER.replace("%MODE%", extra).replace("%ALPHA%", alpha) \
		.replace("%FILTER%", "filter_linear_mipmap" if linear else "filter_nearest_mipmap") \
		.replace("%RENDER%", ", specular_disabled, diffuse_lambert" if high else ", unshaded") \
		.replace("%LOWFN%", "" if high else LOW_FN).replace("%LIGHT%", HIGH_LIGHT if high else LOW_LIGHT)
	_shaders[key] = s
	return s

# ---------------------------------------------------------------- the world's extras

func _world_extras(world: Node) -> void:
	# the house's shadows in first person: its walls, not its roof and ceiling (the rooms stay sunlit, as the
	# view from above shows them), in a copy that only casts
	for c in world.get_children():
		if c is MeshInstance3D:
			match String(c.name):
				"WorldMesh", "CutMesh":
					c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				"FullMesh":
					_full_mesh = c
					c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_full_caster = _caster_without_roof(c)
					if _full_caster:
						world.add_child(_full_caster)
	# the water
	var pw = world.get("pool_water")
	if pw is MeshInstance3D:
		var old = pw.material_override
		_water = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = WATER_SHADER
		_water.shader = sh
		if old is ShaderMaterial and old.get_shader_parameter("tex"):
			_water.set_shader_parameter("tex", old.get_shader_parameter("tex"))
		elif old is StandardMaterial3D:
			_water.set_shader_parameter("tex", old.albedo_texture)
		pw.material_override = _water
		pw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## A shadow-only copy of the house at full height without what lies on top (the ceiling, the roofs, the tops of
## the walls): every surface with a vertex below the wall's top, so walls, lintels and fences.
func _caster_without_roof(full: MeshInstance3D) -> MeshInstance3D:
	var src: ArrayMesh = full.mesh as ArrayMesh
	if src == null:
		return null
	var wall_top: float = float(GameData.data.get("SHROOM_WALL", 150)) * GameData.UNIT - 0.01
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var arr := src.surface_get_arrays(i)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var keep := PackedVector3Array()
		var keep_uv := PackedVector2Array()
		var uvs = arr[Mesh.ARRAY_TEX_UV]
		# per triangle: keep the ones that aren't flat up at the wall's top or above (the house's lid)
		for t in range(0, verts.size() - 2, 3):
			var a := verts[t]
			var b := verts[t + 1]
			var c := verts[t + 2]
			var flat := absf(a.y - b.y) < 0.001 and absf(a.y - c.y) < 0.001
			var inside_house := _in_house(a) and _in_house(b) and _in_house(c)
			if flat and a.y >= wall_top and inside_house:
				continue
			if inside_house and minf(a.y, minf(b.y, c.y)) >= wall_top:
				continue                   # the roof's slopes
			keep.append(a); keep.append(b); keep.append(c)
			if uvs is PackedVector2Array and uvs.size() == verts.size():
				keep_uv.append(uvs[t]); keep_uv.append(uvs[t + 1]); keep_uv.append(uvs[t + 2])
		if keep.is_empty():
			continue
		var na := []
		na.resize(Mesh.ARRAY_MAX)
		na[Mesh.ARRAY_VERTEX] = keep
		if keep_uv.size() == keep.size():
			na[Mesh.ARRAY_TEX_UV] = keep_uv
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
		var m := full.get_surface_override_material(i)
		if m == null:
			m = src.surface_get_material(i)
		out.surface_set_material(out.get_surface_count() - 1, m)
	var mi := MeshInstance3D.new()
	mi.name = "HouseShadow"
	mi.mesh = out
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	return mi

func _in_house(p: Vector3) -> bool:
	# the house's blocks (the lounge, and the bedroom wing down to the yard), with its eaves round them
	var h := GameData.from_3d(p)
	var d: Dictionary = GameData.data
	var A: Dictionary = d.get("ARENA", {"w": 860})
	var areas: Array = d.get("calls", {}).get("lobbyAreas", [])
	var hy: float = float(areas[4].y0) if areas.size() > 4 else 566.0
	var wy: float = float(areas[6].y0) if areas.size() > 6 else 884.0
	var wx: float = float(d.get("BEDROOM", {}).get("x1", 458)) + float(A.get("wall", 18))
	const M := 70.0
	if h.x >= -M and h.x <= float(A.w) + M and h.y >= -M and h.y <= hy + M:
		return true
	return h.x >= -M and h.x <= wx + M and h.y >= -M and h.y <= wy + M

# ---------------------------------------------------------------- props

func _light_prop(mi: MeshInstance3D) -> void:
	var sm: ShaderMaterial = mi.material_override
	if sm.shader == null:
		return
	if _prop_src == "":
		_prop_src = sm.shader.code
	var n := String(mi.name).trim_prefix("Prop_")
	var nm := sm.duplicate() as ShaderMaterial
	nm.shader = _prop_shader(quality == "high")
	if GLOW_RECTS.has(n):
		var r: Array = GLOW_RECTS[n]
		nm.set_shader_parameter("glow_a", r[0])
		nm.set_shader_parameter("glow_b", r[1] if r.size() > 1 else Vector4.ZERO)
	_props.append(nm)
	mi.material_override = nm

var _prop_src := ""

## The props' shader (the World's PROP_SHADER), lit (high) or tinted (low), with the glowing rectangles.
func _prop_shader(high: bool) -> Shader:
	var key := "prop" + str(high)
	if _shaders.has(key):
		return _shaders[key]
	var code := _prop_src
	if high:
		code = code.replace("render_mode unshaded, ", "render_mode diffuse_lambert_wrap, specular_disabled, ")
	code = code.replace("uniform sampler2D tex", ("" if high else LOW_FN) + "uniform vec4 glow_a = vec4(0.0);\nuniform vec4 glow_b = vec4(0.0);\nuniform float glow = 0.0;\nuniform sampler2D tex")
	var tail := "ALPHA_SCISSOR_THRESHOLD = 0.5;"
	var glow := """
	float ga = step(glow_a.x, UV.x) * step(UV.x, glow_a.z) * step(glow_a.y, UV.y) * step(UV.y, glow_a.w);
	float gb = step(glow_b.x, UV.x) * step(UV.x, glow_b.z) * step(glow_b.y, UV.y) * step(UV.y, glow_b.w);
	float g = glow * max(ga, gb);
"""
	if high:
		code = code.replace(tail, tail + PICTURE_NORMAL + "{" + glow + "EMISSION = c.rgb * g;}")
	else:
		code = code.replace(tail, tail + "{" + glow + "ALBEDO = ALBEDO * look_light(MODEL_MATRIX[3].xyz + vec3(0.0, 1.0, 0.0)) + c.rgb * g * 0.6;}")
	var s := Shader.new()
	s.code = code
	_shaders[key] = s
	return s

# ---------------------------------------------------------------- characters

var _caster_shader: Shader

## The characters' shader (CharSprite's own), lit (high) or tinted (low).
func _char_shader_for(high: bool) -> Shader:
	var key := "char" + str(high)
	if _shaders.has(key):
		return _shaders[key]
	var s := Shader.new()
	if high:
		s.code = CharSprite._SHADER_CODE.replace("%RENDER%", "cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_disabled") \
			.replace("%LIT%", PICTURE_NORMAL)
	else:
		s.code = CharSprite._SHADER_CODE.replace("render_mode %RENDER%;", "render_mode cull_disabled, depth_draw_opaque, unshaded;\n" + LOW_FN) \
			.replace("%LIT%", "ALBEDO *= look_light(MODEL_MATRIX[3].xyz + vec3(0.0, 1.0, 0.0));")
	_shaders[key] = s
	return s

func _add_char(cs: Node) -> void:
	if not is_instance_valid(cs) or not cs.is_inside_tree():
		return
	for e in _chars:
		if e[0] == cs:
			return
	var mat = cs.get("_mat")
	var pic: Sprite3D = cs.get_node_or_null("Picture") as Sprite3D
	if not (mat is ShaderMaterial) or pic == null:
		return
	if _caster_shader == null:
		_caster_shader = Shader.new()
		_caster_shader.code = CASTER_SHADER
	mat.shader = _char_shader_for(quality == "high")
	var caster := Sprite3D.new()
	caster.name = "SunShadow"
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.centered = true
	caster.double_sided = true
	caster.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	caster.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var cm := ShaderMaterial.new()
	cm.shader = _caster_shader
	caster.material_override = cm
	caster.extra_cull_margin = 4.0
	cs.add_child(caster)
	_chars.append([cs, caster, cm, pic])

func _sync_chars() -> void:
	for i in range(_chars.size() - 1, -1, -1):
		var e: Array = _chars[i]
		if not is_instance_valid(e[0]):
			_chars.remove_at(i)
			continue
		var pic: Sprite3D = e[3]
		var caster: Sprite3D = e[1]
		caster.visible = sun_shadows and pic.visible
		if not caster.visible:
			continue
		if caster.texture != pic.texture:
			caster.texture = pic.texture
			e[2].set_shader_parameter("tex", pic.texture)
		caster.pixel_size = pic.pixel_size
		caster.offset = pic.offset
		caster.flip_h = pic.flip_h
		caster.scale = pic.scale
		caster.position = pic.position

# ---------------------------------------------------------------- each frame

func _process(dt: float) -> void:
	_watch_speed(dt)
	_sync_chars()
	if _full_caster and _full_mesh:
		_full_caster.visible = _full_mesh.visible
	var rig = main.get("rig") if main else null
	var fp: bool = rig != null and rig.mode == CameraRig.Mode.FIRST_PERSON
	var blur := 1.0 if fp and quality == "high" else 0.0
	if blur != _blur_on:
		_blur_on = blur
		for m in _mat_cache.values():
			m.set_shader_parameter("far_blur", blur)
	if day_night:
		var cut: bool = main.world.is_cut_away() if main and main.get("world") else false
		for l in day_night.lamps:
			if l.has("glow"):
				l.glow.visible = l.glow.visible and not cut
	if quality != "high":
		_update_low()
	var night := 0.0
	if day_night:
		night = day_night.lamp_level
	if _water:
		_water.set_shader_parameter("glow", night)
	for m in _props:
		m.set_shader_parameter("glow", 0.35 + 0.9 * night)

## For a few seconds after it starts (and after a switch back to high): if the median frame takes longer than
## SLOW_MS, go low. Real time, not the engine's delta (held to 8 physics steps).
func _watch_speed(dt: float) -> void:
	if not auto_quality or quality != "high":
		return
	_watch_t += dt
	var now := Time.get_ticks_usec()
	if _watch_t > 3.0 and _watch_last > 0:
		_watch.append((now - _watch_last) / 1000.0)
	_watch_last = now
	if _watch.size() >= 90:
		var w := _watch.duplicate()
		w.sort()
		var med: float = w[w.size() / 2]
		auto_quality = false
		if med > SLOW_MS:
			print("LookPass: frames take %.1f ms on the high look: going low" % med)
			set_quality("low")
		else:
			print("LookPass: high look, %.1f ms a frame" % med)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("look_quality") and not event.is_echo():
		auto_quality = false
		set_quality("low" if quality == "high" else "high")
		print("LookPass: quality ", quality)

## "high" or "low" (see above).
func set_quality(q: String) -> void:
	quality = q
	var high := q == "high"
	sun_shadows = high
	var sun: DirectionalLight3D = main.get("sun") if main else null
	if sun:
		sun.shadow_enabled = high
		sun.light_cull_mask = 0xFFFFF if high else 0     # low: the sun lights nothing (look_tint does it)
	var world = main.get("world") if main else null
	var env: Environment = world.get("environment") if world else null
	if env:
		env.glow_enabled = high
	if day_night:
		day_night.lamp_filter = func(l: Dictionary) -> bool: return high and l.get("which", "both") != "low"
	for m in _mat_cache.values():
		var v: Array = m.get_meta("look_variant")
		m.shader = _world_shader(v[0], v[1], high)
	for m in _props:
		m.shader = _prop_shader(high)
	for e in _chars:
		if is_instance_valid(e[0]):
			e[0].get("_mat").shader = _char_shader_for(high)
	_blur_on = -1.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if high else 1024, true)

## The low look's globals, from the day's look and the lamps.
func _update_low() -> void:
	if day_night == null or day_night.look.is_empty():
		return
	var lk: Dictionary = day_night.look
	var amb: Color = (lk.amb as Color).srgb_to_linear()
	var li: Color = (lk.light as Color).srgb_to_linear()
	var t: Color = amb * day_night.ambient_energy + li * (lk.le * day_night.light_scale * 0.8)
	RenderingServer.global_shader_parameter_set("look_tint", Vector3(t.r, t.g, t.b))
	RenderingServer.global_shader_parameter_set("look_lamp_level", day_night.lamp_level)

## Registers the low look's globals (before any shader using them is made).
static var _globals_done := false
static func register_globals() -> void:
	if _globals_done:
		return
	_globals_done = true
	for n in GLOBALS:
		if not ProjectSettings.has_setting("shader_globals/" + n):
			var def = 0.0
			match GLOBALS[n]:
				RenderingServer.GLOBAL_VAR_TYPE_VEC3: def = Vector3.ONE if n == "look_tint" else Vector3.ZERO
				RenderingServer.GLOBAL_VAR_TYPE_VEC4: def = Vector4.ZERO
			RenderingServer.global_shader_parameter_add(n, GLOBALS[n], def)

## The low look's lamps: the first four that are on in the low look ("low" or "both"), as position and reach.
func _set_low_lamps() -> void:
	var i := 0
	var col := Color(1.0, 0.8, 0.6).srgb_to_linear()
	RenderingServer.global_shader_parameter_set("look_lamp_color", Vector3(col.r, col.g, col.b) * 0.85)
	if day_night:
		for l in day_night.lamps:
			if i >= 4 or l.get("which", "both") == "high":
				continue
			var o: OmniLight3D = l.light
			RenderingServer.global_shader_parameter_set("look_lamp%d" % i, Vector4(o.global_position.x, o.global_position.y, o.global_position.z, o.omni_range))
			i += 1
	while i < 4:
		RenderingServer.global_shader_parameter_set("look_lamp%d" % i, Vector4.ZERO)
		i += 1
