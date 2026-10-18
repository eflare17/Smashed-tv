class_name VoxelChar
extends Node3D
## A character drawn in blocks instead of a picture. It stands in for a CharSprite: added as the sprite's child, it
## hides the sprite's picture (keeping its contact shadow) and every frame reads what the sprite was told (char_id,
## facing, moving, odo, action, roll_t, the weapon sheet and the weapon actions the fight shows on it, its modulate)
## and poses a voxel model the same way (VoxelAnim). Because it hangs under the sprite, whatever hides or scales the
## sprite (first person, the iframe blink, lobby life's own pictures, the bonus room) does the same to the blocks.
## Owned by the voxel session; VoxelSwitch adds and removes these.
##
## The look: one skinned mesh, one material (vertex colours, lit like the world's pictures on the high look, the
## look's tint and lamps on the low one, which also gets the half-resolution blocks). Seen from above (the top-down
## view) the body leans back toward the camera a little (tip), the way the pictures tip back fully, so the face and
## the singlet read from up there; its depth and its shadow stay the upright body's.

## The CharSprite this stands in for (the parent, normally).
var source: CharSprite
## Lean toward a steeply looking-down camera, as a share of the camera's pitch (0: none).
@export var tip: float = 0.5
## 0 full detail, 1 half (the phones' low look sets it).
var lod: int = 0
## How fast the body turns to a new facing (radians a second, eased).
@export var turn_rate: float = 14.0
## Pose override for the lobby (sit, lie, bench, legpress, swim, carry, carried, lift, victory) or "" for none.
var lobby_pose: String = ""
var lobby_pose_f: float = 0.0
## Pressed flat (north to south) against what's behind: the mirror's reflection, which stands just in front of the
## glass.
var flatten: bool = false
## Face this way instead of the sprite's facing (HTML ground axes), when not zero: the lobby poses, tests.
var facing_override: Vector2 = Vector2.ZERO
## A Player this belongs to (for the fight's weapon), found by itself.
var player: Node = null

var model: VoxelModel
var skeleton: Skeleton3D
var mesh_inst: MeshInstance3D
var yaw: float = 0.0
var model_name := ""
var weapon := ""
var style := "classic"
var _key := ""
var _mat: ShaderMaterial
var _t := 0.0
var _last_pos := Vector3.INF
var _speed := 0.0
var _recoil := 0.0
var _gun := 0
var _shots := -1
var _yaw_set := false
var _high := true
var _print_rev := -1
var _sheet := ""

static var _shaders := {}

## Shown in tests and screenshots: the state handed to VoxelAnim last frame.
var last_state: Dictionary = {}

func _ready() -> void:
	made += 1
	process_priority = 900          # after the Player, the Fight and lobby life have told the sprite what to show
	if source == null and get_parent() is CharSprite:
		source = get_parent()
	if player == null and source and source.get_parent() is Player:
		player = source.get_parent()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	_mat = ShaderMaterial.new()
	_set_shader()
	_process(0.0)

func _exit_tree() -> void:
	_show_picture(true)

func _show_picture(on: bool) -> void:
	if source and is_instance_valid(source):
		var pic = source.get("_spr")
		if pic is Node3D:
			pic.visible = on

## Builds (or reuses) the model and the mesh for what's needed now.
func _ensure(sheet: String) -> bool:
	var mn := VoxelModel.model_for_sheet(sheet)
	if mn == "":
		return false
	if mn != model_name:
		model_name = mn
		model = VoxelModel.get_model(mn)
		if skeleton:
			skeleton.queue_free()
			skeleton = null
		_key = ""
	if model == null:
		return false
	if skeleton == null:
		skeleton = model.make_skeleton()
		if flatten:
			skeleton.scale = Vector3(1.0, 1.0, 0.15)
		add_child(skeleton)
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "Blocks"
		mesh_inst.material_override = _mat
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_inst.extra_cull_margin = 2.0
		skeleton.add_child(mesh_inst)
		mesh_inst.skeleton = NodePath("..")
		mesh_inst.skin = model.make_skin()
	var pal := CharFrames.palette(CharFrames.base_char(sheet))
	var rev := VoxelLook.rev if mn == "jared" else 0
	if mn == "jared":
		style = VoxelLook.style_key()
	var key := "%s|%d|%s|%s|%s|%d" % [mn, lod, style, weapon, str(pal), rev]
	if key != _key:
		_key = key
		if mn == "jared":
			VoxelLook.apply_print(model)
		mesh_inst.mesh = model.build_mesh(key, style, lod, VoxelWeapons.attachments(model, weapon, lod), pal)
	return true

## Frames drawn (for tests).
var frames := 0
static var made := 0

func _process(delta: float) -> void:
	frames += 1
	if source == null or not is_instance_valid(source):
		return
	var sheet := source.char_id
	weapon = _weapon_of(sheet)
	_update_quality()
	if not _ensure(sheet):
		visible = false
		_show_picture(true)
		return
	visible = true
	_show_picture(false)
	_t += delta
	# speed from how far the owner moved (smoothed), for the run's stride
	var gp := global_position
	if _last_pos != Vector3.INF and delta > 0.0:
		var d := Vector2(gp.x - _last_pos.x, gp.z - _last_pos.z).length() / GameData.UNIT / delta
		_speed = lerpf(_speed, minf(d, 400.0), 1.0 - exp(-delta * 10.0))
	_last_pos = gp
	# facing: turn smoothly toward the sprite's facing
	var f := source.facing if facing_override == Vector2.ZERO else facing_override
	if f.length_squared() > 0.0001:
		var want := atan2(f.x, f.y)
		if not _yaw_set:
			yaw = want
			_yaw_set = true
		else:
			yaw = yaw + wrapf(want - yaw, -PI, PI) * (1.0 - exp(-delta * turn_rate))
	_recoil = maxf(0.0, _recoil - delta * 7.0)
	_read_fight()
	var st := {
		"t": _t, "moving": source.moving, "speed": _speed if source.moving else 0.0, "odo": source.odo,
		"action": source.action, "roll_t": source.roll_t, "weapon": weapon, "recoil": _recoil, "gun": _gun,
		"pose": lobby_pose, "pose_f": lobby_pose_f,
	}
	_actions(st)
	last_state = st
	var p := VoxelAnim.pose(st)
	_apply(p)
	if _mat:
		_mat.set_shader_parameter("modulate", source.modulate)

# the weapon actions the fight shows on the sprite (its frame key), as VoxelAnim acts
func _actions(st: Dictionary) -> void:
	var key := source.current_key
	var n := 1
	if key != "" and CharFrames.has(source.char_id, key):
		n = maxi(1, CharFrames.frame_count(source.char_id, key))
	var fr := float(source.current_frame + 0.5) / float(n)
	if key.begins_with("reload"):
		st["act"] = "reload"
		st["act_f"] = fr
	elif key.begins_with("throw"):
		var ff = _fighter()
		if ff and ff.charging:
			st["act"] = "charge"
		else:
			st["act"] = "throw"
			st["act_f"] = fr
	elif key == "pickup":
		st["act"] = "pickup"
		st["act_f"] = fr
	else:
		var f2 = _fighter()
		if f2 and weapon == "fists" and f2.punch > 0.0:
			st["act"] = "punch"
			st["act_f"] = clampf(1.0 - f2.punch / maxf(0.05, WeaponDefs.t("punchTime", 0.22)), 0.0, 1.0)

func _fighter():
	if player == null or Fight.me == null or Fight.me.sim == null:
		return null
	if player == Fight.me.player:
		return Fight.me.f
	if player == Fight.me.p2:
		return Fight.me.get("f2")
	return null

func _read_fight() -> void:
	var ff = _fighter()
	if ff == null:
		return
	if ff.shots != _shots:
		if _shots >= 0 and ff.shots > _shots:
			_recoil = 1.0
			_gun = int(ff.last_gun)
		_shots = ff.shots

# the weapon the blocks hold: the fight's own (fists and blasters share the plain sheet), else the sheet's
func _weapon_of(sheet: String) -> String:
	var ff = _fighter()
	if ff != null:
		var w := String(ff.weapon)
		if w == "blaster" and int(ff.blasters) <= 0:
			return "fists"
		return w
	if sheet.ends_with("_spud"):
		return "spud"
	if sheet.ends_with("_shotgun"):
		return "shotgun"
	if sheet.ends_with("_launcher"):
		return "launcher"
	if CharFrames.base_char(sheet) in ["juicy", "tyson2"]:
		return "blaster"         # the plain sheets hold the blasters
	return ""

func _apply(p: Dictionary) -> void:
	if skeleton == null:
		return
	var m := model.voxel_m
	var rot: Dictionary = p.rot
	for i in model.bone_names.size():
		var nm := model.bone_names[i]
		if model.bone_parent[i] >= 0:
			skeleton.set_bone_pose_rotation(i, rot.get(nm, Quaternion.IDENTITY))
	# the root bone carries the whole body: turned about the pose's pivot, lifted, then faced (in the bone, not the
	# node: a node's transform set every frame under the physics-interpolated Player wouldn't show)
	var root := maxi(0, model.bone("hips"))
	var face := Quaternion(Vector3.UP, yaw)
	var turn: Quaternion = p.turn
	var pv: Vector3 = p.pivot
	var ph: Vector3 = model.bone_pivot[root]
	var at: Vector3 = pv + (p.pos as Vector3) + turn * (ph - pv)
	skeleton.set_bone_pose_position(root, face * (at * m))
	skeleton.set_bone_pose_rotation(root, face * turn * (rot.get("hips", Quaternion.IDENTITY) as Quaternion))

# ---------------------------------------------------------------- the look

func _update_quality() -> void:
	var lp := _look_pass()
	var high := true
	if lp:
		high = String(lp.get("quality")) == "high"
	var want_lod := 0 if high else 1
	if high != _high or _mat.shader == null:
		_high = high
		_set_shader()
	if want_lod != lod:
		lod = want_lod
		_key = ""

static var _lp_ref: WeakRef
static var _lp_frame := -100

static func _look_pass() -> Node:
	if _lp_ref and _lp_ref.get_ref():
		return _lp_ref.get_ref()
	var fr := Engine.get_process_frames()
	if fr - _lp_frame < 60:
		return null
	_lp_frame = fr
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var found := (ml as SceneTree).root.find_children("*", "LookPass", true, false)
		if found.size() > 0:
			_lp_ref = weakref(found[0])
			return found[0]
	return null

func _set_shader() -> void:
	var low := not _high and _look_pass() != null
	_mat.shader = shader_for(low)
	_mat.set_shader_parameter("tip", tip)
	_mat.set_shader_parameter("modulate", Color.WHITE)

static func shader_for(low: bool) -> Shader:
	if _shaders.has(low):
		return _shaders[low]
	var s := Shader.new()
	var code := SHADER
	if low:
		LookPass.register_globals()
		code = code.replace("%RENDER%", "unshaded").replace("%LOWFN%", LookPass.LOW_FN) \
			.replace("%LIGHT%", "ALBEDO *= look_light(wpos + vec3(0.0, 0.4, 0.0));")
	else:
		code = code.replace("%RENDER%", "diffuse_lambert_wrap, specular_disabled, shadows_disabled").replace("%LOWFN%", "") \
			.replace("%LIGHT%", LIGHT_NORMAL)
	s.code = code
	_shaders[low] = s
	return s

## The high look's light: mostly the normal LookPass gives the pictures (toward the camera across the ground, well
## up to the sky: even light, as the pixel art has its shading drawn in), a little of the blocks' own for shape.
const LIGHT_NORMAL := """
	{
		vec3 back = INV_VIEW_MATRIX[2].xyz;
		vec3 hz = vec3(back.x, 0.0, back.z);
		hz = length(hz) > 0.001 ? normalize(hz) : vec3(0.0, 0.0, 1.0);
		vec3 pic = normalize((VIEW_MATRIX * vec4(normalize(hz * 0.55 + vec3(0.0, 1.0, 0.0)), 0.0)).xyz);
		NORMAL = normalize(pic + NORMAL * 0.15);
		ROUGHNESS = 1.0;
	}
"""

const SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque, %RENDER%;
%LOWFN%
uniform float tip = 0.5;          // lean toward a steeply looking-down camera, as a share of its pitch
uniform float tip_from = 0.55;    // the camera's look-down (sine of its pitch) where the lean starts
uniform float tip_to = 0.9;       // and where it's full
uniform vec4 modulate : source_color = vec4(1.0);
uniform bool srgb_colors = false;  // true: convert the colours from sRGB (they arrive linear in the Compatibility renderer)
varying vec3 wpos;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wpos = wp;
	vec3 cb = INV_VIEW_MATRIX[2].xyz;
	vec3 cr = INV_VIEW_MATRIX[0].xyz;
	vec3 right = vec3(cr.x, 0.0, cr.z);
	right = length(right) > 0.0001 ? normalize(right) : vec3(1.0, 0.0, 0.0);
	// no lean in an orthographic pass (the sun's shadow map): the shadow is the upright body's
	float ortho = step(0.5, PROJECTION_MATRIX[3][3]);
	float a = (1.0 - ortho) * tip * smoothstep(tip_from, tip_to, clamp(cb.y, 0.0, 1.0)) * asin(clamp(cb.y, 0.0, 1.0));
	vec3 v = wp - origin;
	// turned about 'right' through the feet: the top tips back, away from the camera, toward facing it
	a = -a;
	vec3 drawn = origin + v * cos(a) + cross(right, v) * sin(a) + right * dot(right, v) * (1.0 - cos(a));
	// its own parts sort as drawn (leaning), but the whole body sits as deep as the upright one at chest height,
	// so it sorts with the world like the pictures (things south of him cover him, a wall behind him doesn't)
	vec3 chest = vec3(0.0, 1.0, 0.0);
	vec3 chest_drawn = chest * cos(a) + cross(right, chest) * sin(a) + right * dot(right, chest) * (1.0 - cos(a));
	float dz = (VIEW_MATRIX * vec4(origin + chest, 1.0)).z - (VIEW_MATRIX * vec4(origin + chest_drawn, 1.0)).z;
	vec4 vd = VIEW_MATRIX * vec4(drawn, 1.0);
	vec4 cd = PROJECTION_MATRIX * vd;
	vec4 ca = PROJECTION_MATRIX * (vd + vec4(0.0, 0.0, dz, 0.0));
	POSITION = vec4(cd.xy / cd.w * ca.w, ca.z, ca.w);
}

void fragment() {
	ALBEDO = (srgb_colors ? to_linear(COLOR.rgb) : COLOR.rgb) * modulate.rgb;
	%LIGHT%
}
"""
