class_name CharSprite
extends Node3D
## CONTRACT. A character drawn the HTML game's way: an upright picture that always faces the camera, showing
## whichever of its five directions (front, diag, side, bdiag, back; the other side flipped) matches the angle
## between where the character faces and where the camera is. Feet on this node's origin.
## Owned by the Characters task.
##
## How it follows the HTML game (Smashed.html): the facing is turned by the angle to the viewer the way
## shroomCharacter() turns a character for the first-person view, then sectorOf() (eight sectors, held until
## the facing is clearly in another) and poseFor()/cyclePose() pick the frame: a run cycle stepped by odo
## every T.runStride units, or the a/b stand pair every 26; the roll is rollPhase() over roll1..4 with its hop;
## victory is the breather dance. Sizes are drawJared's (80 units, 2 m, for the new art's 160 px sheets).
##
## The picture is a Sprite3D (nearest filtering, alpha cut) with its own shader: seen from about eye level it
## stands upright and turns only round the vertical (a Y billboard); as the camera looks steeply down it tips
## back to face the camera fully, so a top-down view shows the whole picture like the HTML game. Its depth is
## always a standing figure's: each pixel is as deep as the upright Y-billboard's plane (through the feet, as
## tall as it needs to be) where the camera's ray crosses it. So, like the HTML game's y-sort, things south of
## him (nearer the camera) cover him and things north of him (a wall he stands against) never cut into him,
## however far the picture tips.

## Which character: a key of the manifest's CHARS ("juicy", "tyson2", "goth", ...).
@export var char_id: String = "juicy":
	set(v):
		if v != char_id:
			char_id = v
			_path = ""
			_sector = -1
## Where the character faces, on the ground, in HTML axes (x across, y down the screen).
var facing: Vector2 = Vector2(0, 1)
## Running (walk cycle) or standing.
var moving: bool = false
## Distance walked, in HTML units: the walk cycle steps through frames with it, like the HTML game's odo.
var odo: float = 0.0
## "" normally; "roll" (0..1 through it in roll_t), "victory".
## (Also "tumble": the roll frames cycled by odo, for being sent flying or falling, like drawJared.)
var action: String = ""
var roll_t: float = 0.0

## Not contract, optional: how high the feet are off the floor in HTML units when the owner lifts this node
## (the trampoline): the contact shadow stays on the floor and shrinks, as in drawJared.
var air: float = 0.0
## Lit by the scene's lights (true) or drawn flat, the picture's own colours (false, like the HTML game).
@export var shaded: bool = false:
	set(v):
		shaded = v
		if _mat:
			_mat.shader = _shader(v)
## A soft dark ellipse on the floor under the feet, like the HTML game's contact shadow.
@export var show_shadow: bool = true:
	set(v):
		show_shadow = v
		if _shadow:
			_shadow.visible = v
## Pick the frame by itself every frame (with the viewport's camera) if nobody calls update_view.
@export var auto_update: bool = true
## How steeply the camera must look down (the sine of its pitch: 0 level, 1 straight down) before the picture
## starts tipping back from upright, and where it fully faces the camera. First person stays below the first.
@export_range(0.0, 1.0) var tip_from: float = 0.55:
	set(v):
		tip_from = v
		if _mat:
			_mat.set_shader_parameter("tip_from", v)
@export_range(0.0, 1.0) var tip_to: float = 0.9:
	set(v):
		tip_to = v
		if _mat:
			_mat.set_shader_parameter("tip_to", v)
## Multiplies the picture's colours (a hit flash, a tint). Alpha is ignored: the picture is cut, not blended.
var modulate: Color = Color.WHITE:
	set(v):
		modulate = v
		if _mat:
			_mat.set_shader_parameter("modulate", v)

## What's showing (read only, for others and for tests): view ("front", "diag", "side", "bdiag", "back",
## "roll", "victory"), frame key, frame index, flipped, the manifest path, and the sector 0..7 (0 = facing
## the camera's right, 2 = toward the camera, 6 = away).
var current_view: String = ""
var current_key: String = ""
var current_frame: int = 0
var current_flip: bool = false
var current_path: String = ""
var current_sector: int = 2

var _spr: Sprite3D
var _shadow: MeshInstance3D
var _mat: ShaderMaterial
var _shadow_mat: ShaderMaterial
var _sector: int = -1
var _path: String = ""
var _updated_frame: int = -1
var _victory_t: float = 0.0
var _last_ms: int = -1

static var _shaders := {}
static var _shadow_shader: Shader

const HOLD := PI / 8.0 + PI / 18.0     # sectorOf: 22.5 degrees plus 10 before he turns to the next sector

func _ready() -> void:
	_spr = Sprite3D.new()
	_spr.name = "Picture"
	_spr.centered = true
	_spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED     # the shader does it
	_spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_spr.double_sided = true
	_spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spr.extra_cull_margin = 3.0                             # it tips back past its upright box when seen from above
	_mat = ShaderMaterial.new()
	_mat.shader = _shader(shaded)
	_mat.set_shader_parameter("modulate", modulate)
	_mat.set_shader_parameter("tip_from", tip_from)
	_mat.set_shader_parameter("tip_to", tip_to)
	_spr.material_override = _mat
	add_child(_spr)

	_shadow = MeshInstance3D.new()
	_shadow.name = "Shadow"
	var q := QuadMesh.new()
	var r: float = CharFrames.t("radius") * GameData.UNIT
	q.size = Vector2(r * 0.95 * 2.0, r * 0.6 * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = q
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = _shadow_shader_get()
	_shadow.material_override = _shadow_mat
	_shadow.position.y = 0.012
	_shadow.visible = show_shadow
	add_child(_shadow)
	_apply_pose(get_viewport().get_camera_3d() if is_inside_tree() else null)

func _process(delta: float) -> void:
	if action == "victory":
		_victory_t += delta
	else:
		_victory_t = 0.0
	if auto_update and _updated_frame != Engine.get_process_frames():
		_apply_pose(get_viewport().get_camera_3d())

## Call every frame with the camera that's drawing (it picks the angle).
func update_view(camera: Camera3D) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
	_apply_pose(camera)

## The facing as the camera sees it, in HTML axes: (0, 1) means toward the camera, (1, 0) toward its right.
## shroomCharacter's turn: the facing is rotated by 90 degrees minus the angle from him to the viewer.
func facing_for_view(camera: Camera3D) -> Vector2:
	var f := facing if facing.length_squared() > 0.000001 else Vector2(0, 1)
	var to_viewer := _viewer_dir(camera)
	var turn := PI / 2.0 - atan2(to_viewer.y, to_viewer.x)
	return f.normalized().rotated(turn)

# Where the viewer is from him, on the ground (HTML axes = Godot x, z). Seen from about eye level it's where
# the camera stands (shroomCharacter: me - p); looking steeply down (the top-down view) it's the way the
# camera faces, the same for everyone on screen, like the HTML game where the viewer is always due south.
func _viewer_dir(camera: Camera3D) -> Vector2:
	if camera == null:
		return Vector2(0, 1)
	var b := camera.global_transform.basis
	var back := b.z.normalized()        # from the scene toward the camera
	var up := b.y.normalized()
	var o := Vector2(back.x - up.x, back.z - up.z)    # the camera's own "south"
	o = o.normalized() if o.length_squared() > 0.000001 else Vector2(0, 1)
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return o
	var d3 := camera.global_position - global_position
	var p := Vector2(d3.x, d3.z)
	var w := smoothstep(0.35, 0.7, clampf(back.y, 0.0, 1.0))
	if p.length_squared() < 0.0001:
		return o
	var v := p.normalized().lerp(o, w)
	return v.normalized() if v.length_squared() > 0.000001 else o

# sectorOf: eight sectors (0 = E, 2 = S toward the viewer, 4 = W, 6 = N away), held until the facing is
# clearly inside another one so it doesn't flicker on a boundary.
func _sector_of(v: Vector2) -> int:
	var ang := atan2(v.y, v.x)
	var want := int(round(ang / (PI / 4.0)))
	if want < 0:
		want += 8
	want %= 8
	if _sector < 0 or _sector == want:
		_sector = want
		return want
	var d := wrapf(ang - _sector * (PI / 4.0), -PI, PI)
	if absf(d) < HOLD:
		return _sector
	_sector = want
	return want

func _apply_pose(camera: Camera3D) -> void:
	_updated_frame = Engine.get_process_frames()
	if not is_inside_tree() or _spr == null:
		return
	var id := char_id
	var fv := facing_for_view(camera)
	var oct := _sector_of(fv)
	current_sector = oct
	var key := ""
	var idx := 0
	var flip := false
	var lift := 0.0
	var view := ""
	if action == "roll":
		var ph := CharFrames.roll_phase(roll_t)
		key = "roll%d" % (int(ph["i"]) + 1)
		flip = fv.x < -0.15
		lift = ph["lift"]
		view = "roll"
	elif action == "tumble":
		key = "roll%d" % (int(floor(odo / 26.0)) % 4 + 1)
		flip = fv.x < 0.0
		view = "roll"
	elif action == "victory" and CharFrames.has(id, "victory"):
		key = "victory"
		idx = CharFrames.victory_frame(id, _victory_t)
		view = "victory"
	if key == "" or not CharFrames.has(id, key):
		var p := _pose_for(id, oct)
		key = p[0]
		idx = p[1]
		flip = p[2]
		view = p[3]
		lift = 0.0
	current_view = view
	current_key = key
	current_frame = idx
	current_flip = flip
	_show(id, key, idx, flip, lift)

# poseFor + cyclePose: the view for the sector, its flip, and the frame (a run cycle by odo, else a/b).
func _pose_for(id: String, oct: int) -> Array:
	var fl := CharFrames.flips(id)
	var ab := int(floor(odo / 26.0)) % 2 == 1
	var view: String
	var flip: bool
	match oct:
		0:
			view = "side"; flip = fl["side"]
		1:
			view = "diag"; flip = fl["diag"]
		2:
			view = "front"; flip = false
		3:
			view = "diag"; flip = not fl["diag"]
		4:
			view = "side"; flip = not fl["side"]
		5:
			view = "bdiag"; flip = fl["bdiag"]
		6:
			view = "back"; flip = false
		_:
			view = "bdiag"; flip = not fl["bdiag"]
	var rk := CharFrames.run_key(id, view)
	if rk != "":
		var n := CharFrames.frame_count(id, rk)
		var per := CharFrames.t("runStride")
		return [rk, int(floor(maxf(odo, 0.0) / per)) % n, flip, view]
	var sk := CharFrames.stand_key(id, view, ab)
	if not CharFrames.has(id, sk):
		# a sheet missing a stand frame: the other of the pair, else the front
		var other := CharFrames.stand_key(id, view, not ab)
		sk = other if CharFrames.has(id, other) else ("front_a" if CharFrames.has(id, "front_a") else sk)
	return [sk, 0, flip, view]

func _show(id: String, key: String, idx: int, flip: bool, lift: float) -> void:
	var p := CharFrames.path(id, key, idx)
	if p == "":
		return
	var tex: Texture2D = GameData.tex(p)
	if tex == null:
		return
	var px_h := float(tex.get_height())
	var h_units := CharFrames.draw_height(id, key)
	var units_per_px := h_units / px_h
	if p != _path:
		_path = p
		current_path = p
		_spr.texture = tex
		_mat.set_shader_parameter("tex", tex)
		var pal := CharFrames.palette(id)
		if pal.is_empty():
			_mat.set_shader_parameter("recolour", false)
		else:
			var rows := CharFrames.opaque_rows(p, tex)
			_mat.set_shader_parameter("recolour", true)
			_mat.set_shader_parameter("pal_green", float(pal.get("green", 0.0)))
			_mat.set_shader_parameter("pal_blue", float(pal.get("blue", 0.0)))
			_mat.set_shader_parameter("pal_boost", float(pal.get("boost", 1.0)))
			_mat.set_shader_parameter("rows", Vector3(rows.x, rows.y, px_h))
	_spr.pixel_size = units_per_px * GameData.UNIT
	_spr.scale = Vector3(CharFrames.draw_wide(id), 1, 1)
	_spr.flip_h = flip
	# feet (the frame's floor row) on the origin, lifted by the hop; offset is in pixels, y up
	var foot := CharFrames.foot_frac(id, key)
	_spr.offset = Vector2(0.0, foot * px_h - px_h / 2.0 + lift / units_per_px)
	# the contact shadow stays on the floor and shrinks as he leaves it
	var up := lift + air
	var sf := 1.0 - minf(0.45, maxf(0.0, up) / 22.0)
	_shadow.position.y = 0.012 - air * GameData.UNIT
	_shadow.scale = Vector3(sf, 1, sf)
	_shadow_mat.set_shader_parameter("alpha", 0.35 * sf)

static func _shader(lit: bool) -> Shader:
	if _shaders.has(lit):
		return _shaders[lit]
	var s := Shader.new()
	s.code = _SHADER_CODE.replace("%RENDER%", "cull_disabled, depth_draw_opaque" + ("" if lit else ", unshaded")) \
		.replace("%LIT%", "NORMAL = vec3(0.0, 0.0, 1.0);" if lit else "")
	_shaders[lit] = s
	return s

static func _shadow_shader_get() -> Shader:
	if _shadow_shader == null:
		_shadow_shader = Shader.new()
		_shadow_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform float alpha = 0.35;
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = dot(d, d);
	if (r > 1.0) discard;
	ALBEDO = vec3(0.0);
	ALPHA = alpha * (1.0 - smoothstep(0.75, 1.0, r));
}
"""
	return _shadow_shader

const _SHADER_CODE := """
shader_type spatial;
render_mode %RENDER%;
#include "res://scripts/actors/upright_depth.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform vec4 modulate = vec4(1.0);
// the HTML game's recolourImage(): Tornado Tyson is Juicy's art with the singlet's colours swapped
uniform bool recolour = false;
uniform float pal_green = 22.0;
uniform float pal_blue = 125.0;
uniform float pal_boost = 1.15;
uniform vec3 rows = vec3(0.0, 159.0, 160.0);   // first and last opaque row, picture height
// how steeply the camera looks down (sine of its pitch) where the picture starts and ends tipping back
uniform float tip_from = 0.55;
uniform float tip_to = 0.9;
uniform float depth_bias = 0.06;   // metres toward the camera, so the feet win over the floor they stand on
uniform float depth_reach = 6.0;   // metres: the most a tipped picture's depth is pulled toward the camera

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cr = INV_VIEW_MATRIX[0].xyz;
	vec3 cu = INV_VIEW_MATRIX[1].xyz;
	vec3 cb = INV_VIEW_MATRIX[2].xyz;
	vec3 right = vec3(cr.x, 0.0, cr.z);
	right = length(right) > 0.0001 ? normalize(right) : vec3(1.0, 0.0, 0.0);
	float tip = smoothstep(tip_from, tip_to, clamp(cb.y, 0.0, 1.0));
	vec3 up = normalize(mix(vec3(0.0, 1.0, 0.0), cu, tip));
	vec3 across = right * VERTEX.x * sx;
	vec3 drawn = origin + across + up * VERTEX.y * sy;          // where it shows on screen
	// its depth is the upright figure's (the Y billboard's plane through the feet): the shared upright_depth
	POSITION = upright_clip(drawn, origin, right, VIEW_MATRIX, INV_VIEW_MATRIX, PROJECTION_MATRIX, depth_bias, depth_reach);
}

vec3 rgb2hsl(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float l = (mx + mn) / 2.0;
	if (mx == mn) return vec3(0.0, 0.0, l);
	float dd = mx - mn;
	float s = l > 0.5 ? dd / (2.0 - mx - mn) : dd / (mx + mn);
	float h;
	if (mx == c.r) h = (c.g - c.b) / dd + (c.g < c.b ? 6.0 : 0.0);
	else if (mx == c.g) h = (c.b - c.r) / dd + 2.0;
	else h = (c.r - c.g) / dd + 4.0;
	return vec3(h * 60.0, s, l);
}
float hue2rgb(float p, float q, float t) {
	if (t < 0.0) t += 1.0;
	if (t > 1.0) t -= 1.0;
	if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
	if (t < 0.5) return q;
	if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
	return p;
}
vec3 hsl2rgb(vec3 hsl) {
	float h = hsl.x / 360.0, s = hsl.y, l = hsl.z;
	if (s == 0.0) return vec3(l);
	float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
	float p = 2.0 * l - q;
	return vec3(hue2rgb(p, q, h + 1.0 / 3.0), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3.0));
}
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) discard;
	vec3 col = c.rgb;
	if (recolour) {
		vec3 hsl = rgb2hsl(to_srgb(col));   // the picture's own (sRGB) values, as the HTML game's canvas sees them
		float y = floor(UV.y * rows.z);
		float frac = (y - rows.x) / max(1.0, rows.y - rows.x);
		float nh = -1.0;
		if (hsl.x >= 75.0 && hsl.x < 185.0 && hsl.y > 0.2) nh = pal_green;
		else if (hsl.x >= 185.0 && hsl.x < 265.0 && hsl.y > 0.28 && frac > 0.22 && frac < 0.58) nh = pal_blue;
		if (nh >= 0.0) col = to_linear(hsl2rgb(vec3(nh, min(1.0, hsl.y * pal_boost), hsl.z)));
	}
	ALBEDO = col * modulate.rgb;
	%LIT%
}
"""
