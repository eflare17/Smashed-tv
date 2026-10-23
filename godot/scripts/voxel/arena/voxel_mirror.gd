class_name VoxelMirror
extends Node3D
## A full-length mirror that really reflects (the HTML game's bedroom mirror; the owner, 21 Oct: "as graphics heavy as
## possible"). A second camera stands where your eye's reflection is, behind the glass, looking out through it with a
## frustum cut to exactly the glass (an off-axis projection whose near plane is the glass itself, so nothing behind
## the mirror shows); what it sees is drawn on the glass, flipped. In first person you see yourself in it: Jared, who
## otherwise only shows from above, stands where you are on a layer only the mirror's camera sees. It only renders
## while you're near enough to see it. Owned by the voxel session.

const LAYER_SELF := 2           # render layer (bit index + 1) the player's own Jared is on in first person
const RES := 360                # the reflection's height in pixels to start with (the width follows the glass) ...
## ... then as many as the glass covers on screen (close up, nearly all of it: drawn at 360 and stretched it was
## blurry), in steps of 64, up to max_res (the settings: the anti-aliasing's level sets it)
static var max_res := 1080
static var msaa := Viewport.MSAA_2X
const NEAR_ENOUGH := 9.0        # metres: further off, it isn't rendered
const SHEEN := Color(0.3, 0.33, 0.37)   # the glass while it isn't rendering (no frozen last reflection)

## (the settings: off, the glass just shows a dim reflection-less sheen and nothing renders a second view)
static var enabled := true
var arena: Node3D
var centre := Vector3.ZERO
var normal := Vector3.BACK      # out of the glass, into the room
var width := 0.8
var height := 1.8
var _vp: SubViewport
var _cam: Camera3D
var _glass: MeshInstance3D
var _gm: StandardMaterial3D
var _right := Vector3.RIGHT     # the glass's right as you face it

func setup(arena_: Node3D, centre_: Vector3, normal_: Vector3, w: float, h: float) -> void:
	arena = arena_
	centre = centre_
	normal = normal_.normalized()
	width = w
	height = h
	_right = Vector3.UP.cross(normal).normalized()
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(RES * w / h), RES)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.cull_mask = 0xFFFFF        # (everything, Jared's own layer too)
	_vp.add_child(_cam)
	_cam.current = true
	# the frame (dark wood) and the glass
	var basis := Basis(_right, Vector3.UP, normal)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(w + 0.1, h + 0.1, 0.05)
	frame.mesh = fm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color8(70, 40, 22)
	wood.roughness = 0.6
	frame.material_override = wood
	add_child(frame)
	frame.global_transform = Transform3D(basis, centre - normal * 0.03)
	_glass = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	_glass.mesh = qm
	_gm = StandardMaterial3D.new()
	_gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gm.albedo_color = SHEEN                    # (the reflection goes on while it renders)
	_gm.uv1_scale = Vector3(-1, 1, 1)           # (a reflection: left and right swapped)
	_gm.uv1_offset = Vector3(1, 0, 0)
	_glass.material_override = _gm
	add_child(_glass)
	_glass.global_transform = Transform3D(basis, centre + normal * 0.001)
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a vanity light on top of the frame (the owner, 23 Oct: "add a light so I can see him"): a brass bar, three frosted
	# bulbs, and a warm light out of it onto whoever stands in front (the ceiling light's behind you there: you were a
	# dark shape in it)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color8(176, 138, 70)
	brass.metallic = 0.8
	brass.roughness = 0.35
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w * 0.8, 0.035, 0.07)
	bar.mesh = bm
	bar.material_override = brass
	add_child(bar)
	bar.global_transform = Transform3D(basis, centre + Vector3.UP * (h * 0.5 + 0.08) + normal * 0.02)
	var bulb_m := StandardMaterial3D.new()
	bulb_m.albedo_color = Color(1.0, 0.95, 0.85)
	bulb_m.emission_enabled = true
	bulb_m.emission = Color(1.0, 0.86, 0.62)
	bulb_m.emission_energy_multiplier = 3.0
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 12
	sm.rings = 6
	for k in [-1, 0, 1]:
		var bulb := MeshInstance3D.new()
		bulb.mesh = sm
		bulb.material_override = bulb_m
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bulb)
		bulb.global_position = centre + Vector3.UP * (h * 0.5 + 0.08) + _right * (k * w * 0.3) + normal * 0.08
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.light_energy = 1.7
	lamp.spot_range = 4.0
	lamp.spot_angle = 50.0
	lamp.spot_attenuation = 0.8
	lamp.shadow_enabled = false
	add_child(lamp)
	# out of the glass and a little down, at a face and a body a metre or two in front
	var at := centre + Vector3.UP * (h * 0.5 + 0.06) + normal * 0.12
	lamp.global_position = at
	lamp.look_at(at + normal * 1.6 + Vector3.DOWN * 0.7, Vector3.UP)
	# a stand behind it
	var leg := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.06, h * 0.9, 0.06)
	leg.mesh = lm
	leg.material_override = wood
	add_child(leg)
	leg.global_transform = Transform3D(basis, Vector3(centre.x, h * 0.45, centre.z) - normal * 0.12)

func _process(_dt: float) -> void:
	var main: Camera3D = arena.cam
	var eye := main.global_position
	var off := (eye - centre).dot(normal)
	# (only from in the bedroom or its doorway: not through the walls, from the games room, the yard or the arena)
	var near: bool = off > 0.05 and eye.distance_to(centre) < NEAR_ENOUGH and VoxelBedroom.in_house(eye) and not arena.top_down and enabled
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
	if near != (_gm.albedo_texture != null):
		_gm.albedo_texture = _vp.get_texture() if near else null
		_gm.albedo_color = Color.WHITE if near else SHEEN
	if not near:
		return
	# the eye reflected in the glass's plane; the camera there looks out through the glass (its -z along the normal)
	var r_eye := eye - 2.0 * off * normal
	_cam.global_transform = Transform3D(Basis(-_right, Vector3.UP, -normal), r_eye)
	# the frustum cut to the glass: its near plane on the glass, offset to where the glass is from the eye's reflection
	var to := centre - r_eye
	var ox := to.dot(-_right)
	var oy := to.dot(Vector3.UP)
	_cam.set_frustum(height, Vector2(ox, oy), maxf(0.02, off), 60.0)
	# sharp: as many pixels as the glass takes up on the screen
	var screen_h := float(arena.get_viewport().get_visible_rect().size.y)
	var px := height / (2.0 * maxf(0.3, eye.distance_to(centre)) * tan(deg_to_rad(main.fov) * 0.5)) * screen_h
	var want := clampi(int(ceil(px / 64.0)) * 64, 256, max_res)
	if absi(want - _vp.size.y) >= 64:
		_vp.size = Vector2i(int(want * width / height), want)
	if _vp.msaa_3d != msaa:
		_vp.msaa_3d = msaa

