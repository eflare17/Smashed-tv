class_name LobbyPic
extends Node3D
## An upright picture standing on its feet (this node's origin), drawn like the characters (CharSprite's shader:
## upright and turning to face you at eye level, tipping back to lie flat as the camera looks down, sorted like a
## standing figure). For lobby life's own art: plates, ducks, the bong, cards, snags, Jared lifting...
## Owned by the Lobby life session.
##
## Size: units_per_px HTML units for each pixel (the HTML game draws most of its little pictures at half size:
## 0.5). The feet are the picture's bottom row unless foot_px says how many pixels up from the bottom they are.

var texture: Texture2D:
	set(v):
		texture = v
		_apply()
var units_per_px: float = 0.5:
	set(v):
		units_per_px = v
		_apply()
## Pixels from the bottom of the picture to where it stands.
var foot_px: float = 0.0:
	set(v):
		foot_px = v
		_apply()
## Lift off the ground (HTML units) without moving the node.
var lift: float = 0.0:
	set(v):
		lift = v
		_apply()
## Shift across (HTML units, the picture's own right) without moving the node.
var shift_x: float = 0.0:
	set(v):
		shift_x = v
		_apply()
var flip: bool = false:
	set(v):
		flip = v
		if _spr:
			_spr.flip_h = v
var modulate: Color = Color.WHITE:
	set(v):
		modulate = v
		if _mat:
			_mat.set_shader_parameter("modulate", v)
## Tornado Tyson's singlet colours (CharSprite's recolour) when the picture is Jared's.
var recolour_for: String = "":
	set(v):
		recolour_for = v
		_apply()
## Always face the camera fully (flat to the screen), like a sign, rather than standing up.
var flat_to_camera: bool = false:
	set(v):
		flat_to_camera = v
		if _mat:
			_mat.set_shader_parameter("tip_from", -1.0 if v else 0.55)
			_mat.set_shader_parameter("tip_to", 0.0 if v else 0.9)
## Lit by the scene (false: its own colours, like the characters).
var shaded: bool = false

var _spr: Sprite3D
var _mat: ShaderMaterial

static func make(tex: Texture2D, upp: float = 0.5, foot: float = 0.0) -> LobbyPic:
	var p := LobbyPic.new()
	p.texture = tex
	p.units_per_px = upp
	p.foot_px = foot
	return p

func _init() -> void:
	_spr = Sprite3D.new()
	_spr.name = "Picture"
	_spr.centered = true
	_spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_spr.double_sided = true
	_spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spr.extra_cull_margin = 3.0
	_mat = ShaderMaterial.new()
	_mat.shader = CharSprite._shader(false)
	_mat.set_shader_parameter("modulate", Color.WHITE)
	_mat.set_shader_parameter("tip_from", 0.55)
	_mat.set_shader_parameter("tip_to", 0.9)
	_mat.set_shader_parameter("recolour", false)
	_spr.material_override = _mat
	add_child(_spr)

func _apply() -> void:
	if _spr == null:
		return
	_spr.texture = texture
	_mat.set_shader_parameter("tex", texture)
	if texture == null:
		return
	var h := float(texture.get_height())
	_spr.pixel_size = units_per_px * GameData.UNIT
	_spr.offset = Vector2(shift_x / maxf(units_per_px, 0.0001), h / 2.0 - foot_px + lift / maxf(units_per_px, 0.0001))
	_spr.flip_h = flip
	var pal := CharFrames.palette(recolour_for) if recolour_for != "" else {}
	if pal.is_empty():
		_mat.set_shader_parameter("recolour", false)
	else:
		_mat.set_shader_parameter("recolour", true)
		_mat.set_shader_parameter("pal_green", float(pal.get("green", 0.0)))
		_mat.set_shader_parameter("pal_blue", float(pal.get("blue", 0.0)))
		_mat.set_shader_parameter("pal_boost", float(pal.get("boost", 1.0)))
		_mat.set_shader_parameter("rows", Vector3(0, h - 1, h))

## How tall it stands, HTML units.
func height_units() -> float:
	return 0.0 if texture == null else texture.get_height() * units_per_px

## Load a picture of lobby life's own (scripts/lobby_life/art/...), or from the manifest's assets.
static func art(path: String) -> Texture2D:
	if path.begins_with("res://"):
		return load(path) if ResourceLoader.exists(path) else null
	if path.begins_with("assets/"):
		return GameData.tex(path)
	var p := "res://scripts/lobby_life/art/" + path
	return load(p) if ResourceLoader.exists(p) else null
