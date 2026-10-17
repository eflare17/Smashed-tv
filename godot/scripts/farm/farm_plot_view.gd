class_name FarmPlotView
extends Node3D
## One plot's look (drawWeedBed and drawWeedPlant in the HTML game): the soil filled in round the hole (dark and
## damp where it's watered), the plant (tools/strains.py's picture for its strain and stage: dry ones droop and go
## yellow, wilted ones droop further and go brown; swaying from its foot in the breeze), a drop bobbing over it
## when it wants water, a glint now and then when it's ready, and a bag mark when it's fertilised.
## The plant stands up in first person and leans back to lie flat seen from above, like the characters.
## Feet on this node's origin (the hole).

const D := preload("res://scripts/farm/farm_data.gd")
const U := 0.025
const SHEET := "res://assets/farm/strains.png"

static var _plant_shader: Shader
static var _soil_shader: Shader
static var _mats := {}
static var _sheet: Texture2D
static var _drop_tex: Texture2D

var _plant: MeshInstance3D
var _soil: MeshInstance3D
var _drop: Sprite3D
var _glint: Sprite3D
var _key := ""
var _soil_key := ""
var _top := 0.0
var _t := 0.0
var _phase := 0.0
var _look := 0

func _ready() -> void:
	_phase = global_position.x * 2.0
	_soil = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(92, 46) * U
	_soil.mesh = q
	_soil.position.y = 0.006
	_soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_soil.visible = false
	add_child(_soil)
	_plant = MeshInstance3D.new()
	var pm := QuadMesh.new()
	pm.size = Vector2(44, 64) * D.PLANT_SCALE * U
	pm.center_offset = Vector3(0.0, (32.0 - 4.0) * D.PLANT_SCALE * U, 0.0)   # its foot (row 60 of 64) on the origin
	_plant.mesh = pm
	_plant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plant.extra_cull_margin = 3.0
	_plant.visible = false
	add_child(_plant)
	if _drop_tex == null:
		_drop_tex = load("res://assets/farm/drop.png")
	_drop = Sprite3D.new()
	_drop.texture = _drop_tex
	_drop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_drop.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_drop.pixel_size = 0.7 * U
	_drop.no_depth_test = true
	_drop.render_priority = 2
	_drop.visible = false
	add_child(_drop)
	_glint = Sprite3D.new()
	_glint.texture = _glint_tex()
	_glint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glint.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_glint.pixel_size = 1.2 * U
	_glint.no_depth_test = true
	_glint.visible = false
	add_child(_glint)

## Show plot p (FarmState's plot dictionary): stage, look (0 healthy, 1 dry, 2 wilted), watered, open (land owned).
func show_plot(p: Dictionary, stg: int, lk: int, wet: bool, open: bool) -> void:
	var planted: bool = p.s >= 0 and open
	var sk := ("wet" if wet else "dry") if planted else ("dry" if open and p.zone != "yard" else "")   # (the yard art has its own holes)
	if sk != _soil_key:
		_soil_key = sk
		_soil.visible = sk != ""
		if sk != "":
			_soil.material_override = soil_mat(wet)
	_plant.visible = planted
	_look = lk if planted else 0
	if planted:
		var key := "%d_%d_%d" % [p.s, stg, lk]
		if key != _key:
			_key = key
			_plant.material_override = plant_mat(p.s, stg, lk)
			_top = _top_of(p.s, stg, lk)
	_drop.visible = planted and lk > 0
	_glint.visible = false
	set_meta("ready", planted and stg == 3)
	set_process(_drop.visible or (planted and stg == 3))   # only the drop and the glint move

func _process(delta: float) -> void:
	_t += delta
	if _drop.visible:
		_drop.position = Vector3(14 * U, (_top + 12.0 + sin(_t * 4.0 + _phase) * 2.0) * U, 0.0)
	if get_meta("ready", false):
		var on := sin(_t * 3.0 + _phase * 0.3) > 0.6
		_glint.visible = on
		if on:
			_glint.position = Vector3(2 * U, (_top - 4.0) * U, 0.0)

## How tall the plant shows, in world units (its top row's height over its foot).
func _top_of(s: int, stg: int, lk: int) -> float:
	var img := _sheet_img()
	var top := 60
	if img:
		for y in 60:
			var found := false
			for x in 44:
				if img.get_pixel(stg * 44 + x, s * 64 + y).a > 0.0:
					found = true
					break
			if found:
				top = y
				break
	var h := (60.0 - top) * D.PLANT_SCALE
	return h * ([1.0, 54.0 / 60.0, 47.0 / 60.0][lk])

static var _img_cache: Image
static func _sheet_img() -> Image:
	if _img_cache == null:
		var t := _sheet_tex()
		if t:
			_img_cache = t.get_image()
			if _img_cache and _img_cache.is_compressed():
				_img_cache.decompress()
	return _img_cache

static func _sheet_tex() -> Texture2D:
	if _sheet == null:
		_sheet = load(SHEET)
	return _sheet

static func _glint_tex() -> Texture2D:
	var img := Image.create(7, 7, false, Image.FORMAT_RGBA8)
	for i in 7:
		img.set_pixel(3, i, Color(1, 1, 1, 0.9))
		img.set_pixel(i, 3, Color(1, 1, 1, 0.9))
	return ImageTexture.create_from_image(img)

## The plant's material for strain s, stage stg, look lk (shared by every plot showing the same).
static func plant_mat(s: int, stg: int, lk: int) -> ShaderMaterial:
	var key := "p%d_%d_%d" % [s, stg, lk]
	if _mats.has(key):
		return _mats[key]
	if _plant_shader == null:
		_plant_shader = Shader.new()
		_plant_shader.code = PLANT_SHADER
	var m := ShaderMaterial.new()
	m.shader = _plant_shader
	m.set_shader_parameter("tex", _sheet_tex())
	m.set_shader_parameter("region", Vector4(stg / 4.0, s / float(D.STRAINS.size()), 1.0 / 4.0, 1.0 / D.STRAINS.size()))
	m.set_shader_parameter("squash", [1.0, 54.0 / 60.0, 47.0 / 60.0][lk])
	m.set_shader_parameter("tint", [Color(0, 0, 0, 0), Color(176 / 255.0, 154 / 255.0, 58 / 255.0, 0.42), Color(118 / 255.0, 78 / 255.0, 40 / 255.0, 0.6)][lk])
	m.set_shader_parameter("sway", 0.0 if lk else 0.035)
	_mats[key] = m
	return m

static func soil_mat(wet: bool) -> ShaderMaterial:
	var key := "soil_wet" if wet else "soil_dry"
	if _mats.has(key):
		return _mats[key]
	if _soil_shader == null:
		_soil_shader = Shader.new()
		_soil_shader.code = SOIL_SHADER
	var m := ShaderMaterial.new()
	m.shader = _soil_shader
	m.set_shader_parameter("wet", wet)
	m.set_shader_parameter("c_hole", Color("#3b2618") if wet else Color("#5a3d27"))
	m.set_shader_parameter("c_mid", Color("#4a3020") if wet else Color("#6b4a30"))
	_mats[key] = m
	return m

const SOIL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform bool wet = false;
uniform vec4 c_hole : source_color;
uniform vec4 c_mid : source_color;
// the quad is 92 x 46 units: the damp patch (46 x 23 radii), the filled hole (27 x 12), its middle (14 x 6)
float ell(vec2 p, vec2 c, vec2 r) { vec2 d = (p - c) / r; return dot(d, d); }
void fragment() {
	vec2 p = (UV - 0.5) * vec2(92.0, 46.0);
	vec4 col = vec4(0.0);
	if (wet && ell(p, vec2(0.0, 2.0), vec2(46.0, 23.0)) < 1.0) col = vec4(28.0 / 255.0, 16.0 / 255.0, 8.0 / 255.0, 0.42);
	if (ell(p, vec2(0.0, 1.0), vec2(27.0, 12.0)) < 1.0) col = vec4(c_hole.rgb, 1.0);
	if (ell(p, vec2(0.0, -1.0), vec2(14.0, 6.0)) < 1.0) col = vec4(c_mid.rgb, 1.0);
	if (col.a <= 0.0) discard;
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
"""

## The plant: a cut-out standing on its feet that turns to the camera round the vertical and tips back to face
## it as the camera looks down (CharSprite's way, with its depth kept a standing figure's), swaying from its foot.
const PLANT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform vec4 region = vec4(0.0, 0.0, 0.25, 0.1666);
uniform float squash = 1.0;
uniform vec4 tint = vec4(0.0);
uniform float sway = 0.035;
uniform float tip_from = 0.55;
uniform float tip_to = 0.9;
uniform float depth_bias = 0.05;
uniform float depth_reach = 6.0;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cr = INV_VIEW_MATRIX[0].xyz;
	vec3 cu = INV_VIEW_MATRIX[1].xyz;
	vec3 cb = INV_VIEW_MATRIX[2].xyz;
	vec3 right = vec3(cr.x, 0.0, cr.z);
	right = length(right) > 0.0001 ? normalize(right) : vec3(1.0, 0.0, 0.0);
	float tip = smoothstep(tip_from, tip_to, clamp(cb.y, 0.0, 1.0));
	vec3 up = normalize(mix(vec3(0.0, 1.0, 0.0), cu, tip));
	float y = VERTEX.y * squash;
	float x = VERTEX.x - y * sway * sin(TIME * 1.1 + origin.x * 2.0);
	vec3 drawn = origin + right * x + up * y;
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(drawn, 1.0));
	vec3 n = vec3(-right.z, 0.0, right.x);
	bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = ortho ? cb : normalize(cam - drawn);
	float behind = -dot(drawn - origin, n);
	float mu = clamp(behind / max(dot(to_cam, n), 0.0001), 0.0, depth_reach);
	if (!ortho) {
		mu = min(mu, max(0.0, length(cam - drawn) - 0.25));
	}
	vec4 vd = VIEW_MATRIX * vec4(drawn + to_cam * mu, 1.0);
	vd.z += depth_bias;
	vec4 cd = PROJECTION_MATRIX * vd;
	if (cd.w > 0.0001) {
		clip.z = cd.z / cd.w * clip.w;
	}
	POSITION = clip;
}
void fragment() {
	vec4 c = texture(tex, region.xy + UV * region.zw);
	if (c.a < 0.5) discard;
	ALBEDO = mix(c.rgb, tint.rgb, tint.a);
}
"""
