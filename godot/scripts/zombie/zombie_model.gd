class_name ZombieModel
extends Node3D
## One zombie as the owner's model (assets/models/zombie/zombie.fbx, "Skeletonzombie T Avelange"): the imported
## mesh on its mixamorig Skeleton3D, played by a ZombieAnim, wearing the game's look: lit for real in the "high"
## look (the sun or moon, the lamps, a normal map, its glowing scratches at night), and in the phones' "low" look
## unshaded with LookPass's global day tint and lamp pools (LOW_FN) plus a soft shape light of its own.
## Its feet are at this node's origin; it faces +z (turn the node to face it).

const SCENE := "res://assets/models/zombie/zombie.fbx"
const ALBEDO := "res://assets/models/zombie/zombie_albedo.png"
const NORMAL := "res://assets/models/zombie/zombie_normal.png"
const CLOTH := "res://assets/models/zombie/zombie_cloth.png"
const GLOW := "res://assets/models/zombie/zombie_glow.png"
## Its height in the game (metres): the model is 2.06 m; the players stand about 1.6 m.
const HEIGHT := 1.85

const HIGH_SHADER := """
shader_type spatial;
render_mode %CULL%, diffuse_lambert_wrap, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D glow_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float glow = 0.0;
uniform float flash = 0.0;
uniform float fade = 1.0;
void fragment() {
	vec4 a = texture(albedo_tex, UV);
	if (fade < 0.999) {
		// fading out without blending (no sorting): a fine ordered dither
		vec2 p = mod(FRAGCOORD.xy, 4.0);
		float th = (mod(p.x + p.y * 2.0, 4.0) * 4.0 + mod(p.x * 2.0 + p.y, 4.0) + 0.5) / 16.0;
		if (fade < th) discard;
	}
	%ALPHA%
	ALBEDO = mix(a.rgb * tint, vec3(1.0), flash * 0.55);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = 0.78;
	SPECULAR = 0.3;
	EMISSION = texture(glow_tex, UV).rgb * glow * 2.5 + vec3(0.6, 0.15, 0.1) * flash;
}
"""

const LOW_SHADER := """
shader_type spatial;
render_mode %CULL%, unshaded;
%LOWFN%
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D glow_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float glow = 0.0;
uniform float flash = 0.0;
uniform float fade = 1.0;
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec4 a = texture(albedo_tex, UV);
	if (fade < 0.999) {
		vec2 p = mod(FRAGCOORD.xy, 4.0);
		float th = (mod(p.x + p.y * 2.0, 4.0) * 4.0 + mod(p.x * 2.0 + p.y, 4.0) + 0.5) / 16.0;
		if (fade < th) discard;
	}
	%ALPHA%
	// the shape: a soft light from above and the north, so it reads as round without real lights
	vec3 n = normalize(wnorm);
	float shape = 0.58 + 0.42 * clamp(dot(n, normalize(vec3(0.25, 1.0, -0.45))) * 0.5 + 0.5, 0.0, 1.0);
	vec3 c = mix(a.rgb * tint, vec3(1.0), flash * 0.55);
	ALBEDO = c * look_light(wpos + n * 0.15) * shape + texture(glow_tex, UV).rgb * glow * 1.6 + vec3(0.5, 0.1, 0.08) * flash;
}
"""

static var _scene: PackedScene
static var _shaders: Dictionary = {}

var skel: Skeleton3D
var mesh: MeshInstance3D
var anim: ZombieAnim
var quality := ""
var _mats: Array[ShaderMaterial] = []
var _body: Node3D
var _flash := 0.0
var _fade := 1.0
var _glow := 0.0

func _init(seed_: float = 0.37) -> void:
	if _scene == null:
		_scene = load(SCENE)
	_body = _scene.instantiate()
	_body.name = "Body"
	var s := HEIGHT / 2.06
	_body.scale = Vector3(s, s, s)
	add_child(_body)
	skel = _body.find_children("*", "Skeleton3D", true, false).front()
	mesh = _body.find_children("*", "MeshInstance3D", true, false).front()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# the T-pose's arms reach 1.5 m out; posed they don't, but give the culling room for a swipe
	mesh.extra_cull_margin = 0.5
	anim = ZombieAnim.new(skel)
	anim.seed = seed_
	for i in mesh.mesh.get_surface_count():
		var m := ShaderMaterial.new()
		m.set_meta("cloth", i == 1)
		m.set_shader_parameter("albedo_tex", load(CLOTH if i == 1 else ALBEDO))
		m.set_shader_parameter("normal_tex", load(NORMAL))
		m.set_shader_parameter("glow_tex", load(GLOW))
		m.set_shader_parameter("tint", Color(0.92, 0.92, 0.9))
		mesh.set_surface_override_material(i, m)
		_mats.append(m)
	set_quality("high")

## "high" (lit) or "low" (the phone look).
func set_quality(q: String) -> void:
	if q == quality:
		return
	quality = q
	for m in _mats:
		m.shader = shader_for(q == "high", bool(m.get_meta("cloth")))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if q == "high" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func shader_for(high: bool, cloth: bool) -> Shader:
	var key := str(high) + str(cloth)
	if _shaders.has(key):
		return _shaders[key]
	var s := Shader.new()
	var alpha := "if (a.a < 0.5) discard;" if cloth else ""
	var cull := "cull_disabled" if cloth else "cull_back"
	if high:
		s.code = HIGH_SHADER.replace("%ALPHA%", alpha).replace("%CULL%", cull)
	else:
		LookPass.register_globals()
		s.code = LOW_SHADER.replace("%LOWFN%", LookPass.LOW_FN).replace("%ALPHA%", alpha).replace("%CULL%", cull)
	_shaders[key] = s
	return s

## White-hot for a moment when hit (0..1).
func set_flash(v: float) -> void:
	if absf(v - _flash) < 0.01:
		return
	_flash = v
	for m in _mats:
		m.set_shader_parameter("flash", v)

## 1 solid, 0 gone (dithered out).
func set_fade(v: float) -> void:
	if absf(v - _fade) < 0.01:
		return
	_fade = v
	for m in _mats:
		m.set_shader_parameter("fade", v)

## Its scratches glowing (0 by day, 1 at night).
func set_glow(v: float) -> void:
	if absf(v - _glow) < 0.01:
		return
	_glow = v
	for m in _mats:
		m.set_shader_parameter("glow", v)
