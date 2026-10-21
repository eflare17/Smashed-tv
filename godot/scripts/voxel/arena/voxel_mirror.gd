class_name VoxelMirror
extends Node3D
## A full-length mirror that really reflects (the HTML game's bedroom mirror; the owner, 21 Oct: "as graphics heavy as
## possible"). A second camera stands where your eye's reflection is, behind the glass, looking out through it with a
## frustum cut to exactly the glass (an off-axis projection whose near plane is the glass itself, so nothing behind
## the mirror shows); what it sees is drawn on the glass, flipped. In first person you see yourself in it: Jared, who
## otherwise only shows from above, stands where you are on a layer only the mirror's camera sees. It only renders
## while you're near enough to see it. Owned by the voxel session.

const LAYER_SELF := 2           # render layer (bit index + 1) the player's own Jared is on in first person
const RES := 360                # the reflection's height in pixels (the width follows the glass)
const NEAR_ENOUGH := 9.0        # metres: further off, it isn't rendered

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
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_texture = _vp.get_texture()
	gm.uv1_scale = Vector3(-1, 1, 1)           # (a reflection: left and right swapped)
	gm.uv1_offset = Vector3(1, 0, 0)
	_glass.material_override = gm
	add_child(_glass)
	_glass.global_transform = Transform3D(basis, centre + normal * 0.001)
	_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var near: bool = off > 0.05 and eye.distance_to(centre) < NEAR_ENOUGH and not arena.top_down and enabled
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
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
