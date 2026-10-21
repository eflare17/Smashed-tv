class_name VoxelWeaponGravity
extends VoxelMelee
## The gravity gun (the owner, 20 Oct: six new weapons, each doing something different): pick things up, throw them,
## black holes. A blocky Half-Life gravity gun held at the hip: an orange back end, a dark grey body, a square mouth
## with three claw prongs round a glowing orange core that pulses (brighter, with an orange light, while it holds
## something; the prongs open wide then).
## Left click with nothing held grabs what's under the aim within 14 m: a piece lying or flying about (VoxelPieces), a
## dead body, a lying fragment (made a piece first), or a live enemy, lifted off his feet with his arms and legs
## flailing. It flies to a point 1.8 m out in front, a little below the middle of the view (a body a little further
## out), and hovers there, bobbing and turning slowly as you look about, a crackling orange-white beam from the prongs
## to it. A piece is pulled there by its velocity (a damped spring, low gravity); a body is moved there (carried off
## its feet, staggered, so the arena doesn't walk it). Nothing there: a dry click and a puff from the prongs.
## Left click again launches it where you look: a piece at 24 m/s, spinning, and the first body it meets at speed is
## knocked flying, hurt and dented; a body at 22 m/s (VoxelBody.launch), bowling over whoever it flies into, hurt when
## it comes down (a frozen one flies as a statue and shatters as it lands). The core punches, the view kicks, a whump.
## Right click while holding drops it gently.
## Right click with nothing held fires a black hole (one at a time, every 7 s): a little dark ball flies out at 9 m/s
## and after 0.7 s, or on hitting anything, stops and opens for 4.5 s (at least 0.8 m up): a black sphere with a
## purple-white rim (its glow seen even through the bodies circling it), a spinning disc of glowing cubes round it and a
## deep purple light. While it's open the flying cubes spiral into it and are crushed and the lying ones lift off
## (VoxelDebris.well); bodies within 6 m, alive or dead, are dragged in and lifted off the floor, spinning, faster the
## nearer; pieces are pulled in and swallowed; and the bodies near the middle are crushed, the living first, one at a
## time: up to eight times a second a ball of it, where it's nearest the middle, is crushed out (VoxelBody.carve), limbs
## and the head first (they come off and are swallowed, the head chewed through the brain), then the trunk; its cubes
## and whatever comes off go into the hole; one with nothing left is gone. The crushes are spaced so they take a tenth
## of the time at most (one a frame; each costs 2-10 ms, the head's and the trunk's the most). The view wobbles near it.
## Then it collapses to nothing and bursts: everything still near is flung outward and up.
## Top-down it's in Jared's hands: it grabs what's under the mouse, holds it in front of him, and throws and fires
## level toward the mouse. The core (what's under the aim, holding and throwing a body, a piece's hit, the black
## hole's flight, pull, crush and burst) is static so the logic test can run it. Owned by the voxel session.

const REACH := 14.0             # metres it grabs from
const PICK_R := 0.6             # a piece whose middle is this near the aim's line can be grabbed ...
const BODY_PICK_R := 0.35       # ... a body whose middle is (when the line slips between its cubes)
const HOLD_D := 1.8             # metres out a thing is held ...
const HOLD_DOWN := 0.2          # ... this far below the middle of the view ...
const HOLD_BODY := 0.45         # ... a body further out by this share of its height (not all you see)
const SPRING := 70.0            # a held body: pulled to the hold point (1/s/s) ...
const DAMP := 15.0              # ... damped (1/s) ...
const MAX_PULL := 18.0          # ... at most this fast, m/s
const PIECE_K := 9.0            # a held piece: velocity toward the hold point, per metre off it ...
const PIECE_EASE := 10.0        # ... eased into (1/s)
const PIECE_GRAV := 0.12        # the gravity a held piece still feels
const BOB := 0.035              # metres a held thing bobs
const CARRY_UP := 0.4           # a carried body's air speed up (the arena never lands it; its position is ours)
const LAUNCH_V := 24.0          # a piece launched, m/s
const BODY_V := 22.0            # a body launched: look * this + up * BODY_UP, turning over at BODY_SPIN
const BODY_UP := 1.5
const BODY_SPIN := 8.0
const RAM_T := 1.5              # seconds a launched piece can still hit a body ...
const RAM_R := 0.6              # ... level metres from his middle ...
const RAM_V := 6.0              # ... going at least this fast
const RAM_HURT := 12.0
const RAM_DENT := 0.07          # the dent it knocks in, metres
const THROWN_HURT := 10.0       # a thrown body hurt as it comes down
const HOLE_V := 9.0             # the black hole: flies at this ...
const HOLE_FLY := 0.7           # ... for this long at most ...
const HOLE_OPEN := 4.5          # ... then open this long
const HOLE_CD := 7.0            # seconds from one to the next
const HOLE_Y := 0.8             # it opens at least this high
const HOLE_PAST := 2.0          # it slips past bodies this near where it was fired (it doesn't open in your face)
const HOLE_BALL := 0.32         # the black sphere's radius
const HOLE_R := 6.0             # bodies and pieces within this are dragged in ...
const PULL_V := 1.2             # ... at this far out ...
const PULL_NEAR := 7.0          # ... to this near the middle, m/s
const SWIRL := 1.6              # m/s round it far out (a spiral in) ...
const SWIRL_NEAR := 2.6         # ... and circling it
const ORBIT := 0.75             # a body's middle circles it this far out (closing in as it's eaten: the ball stays in sight)
const EAT_R := 0.7              # pieces this near are swallowed
const CRUSH_R := 1.3            # a body whose middle is this near is crushed ...
const CRUSH_T := 0.125          # ... a ball every this many seconds ...
const CRUSH_GAP := 0.05         # ... any two at least this far apart (20 a second at most, one a frame) ...
const CRUSH_BUDGET := 0.1       # ... and further if they cost more than this share of the time (a trunk's ~5 ms)
const CRUSH_BALL := 0.09        # ... this big ...
const CRUSH_HP := 0.08          # ... each body cube costing this health (carve's own) ...
const CRUSH_HURT := 6.0         # ... and this off
const LIMB_REACH := 1.2         # a limb or the head this near is crushed before the trunk ...
const LIMB_IN := 0.12           # ... from this far out along it from its joint (clear of the trunk)
const TRUNK := ["torso", "pelvis", "chest", "hips"]
const WELL_R := 4.5             # flying cubes this near spiral in (VoxelDebris.well_r)
const COLLAPSE_T := 0.36        # seconds the collapse takes (the sound's suck), then the burst
const FLING_V := 7.0            # the burst: bodies thrown out at up to this, m/s
const BURST_T := 0.4            # the burst's flash
const SPARKS := 400             # glowing bits at once (puffs, the launch's blast, the hole's streaks and burst)
const ORANGE := Color(1.0, 0.5, 0.1)
const PURPLE := Color(0.55, 0.22, 1.0)
const DARK := Color(0.17, 0.17, 0.19)
const MOUTH_Z := -0.215         # the gun's own space: the square mouth's middle (z) ...
const MOUTH_Y := 0.04           # ... and height
const REST := Vector3(0.21, -0.25, -0.5)        # where the grip is held, camera space (at the hip, right; above the weapon bar)
const AIM_AT := Vector3(0.0, -0.1, -7.0)        # ... the mouth pointing here
const VIEW_SCALE := 0.85        # the gun's size in the view
const TD_LOOK := 1.35           # top-down the black hole and the beam are drawn bigger (seen from 14 m up)
## The disc's rings of glowing cubes: [inner radius, outer, cubes, cube size, colour in, colour out, radians a second]
## (at the hole's full size).
const RINGS := [[0.36, 0.44, 44, 0.022, Color(1.0, 0.95, 1.0), Color(0.86, 0.7, 1.0), 9.0],
	[0.45, 0.66, 70, 0.03, Color(0.86, 0.66, 1.0), Color(0.62, 0.32, 1.0), 5.2],
	[0.66, 0.92, 80, 0.035, Color(0.62, 0.3, 1.0), Color(0.46, 0.14, 0.92), 3.3],
	[0.92, 1.26, 84, 0.04, Color(0.42, 0.1, 0.82), Color(0.95, 0.35, 0.55), 2.1]]

var _gun: Node3D                # first person: the gun under view (the grip at its origin, the mouth toward -z)
var _parts := {}                # its prongs, core, white-hot middle and mouth (see _model)
var _hand: Node3D               # top-down: the gun in Jared's hands (the arena frees it on a switch)
var _hand_parts := {}
var _core_m: StandardMaterial3D # the core's glow (both models)
var _light: OmniLight3D         # the core's light (world)
var _beam: MeshInstance3D       # the crackling beam to what's held (world)
var _glow_m: StandardMaterial3D # glowing cubes: sparks, the disc
var _sp: MultiMeshInstance3D    # sparks
var _spp := PackedVector3Array()
var _spv := PackedVector3Array()
var _spl := PackedFloat32Array()        # seconds left
var _spl0 := PackedFloat32Array()       # seconds it had
var _spc := PackedColorArray()
var _sps := PackedFloat32Array()        # size, metres
var _spw := PackedByteArray()           # 1: drawn into the black hole
var _spn := 0
var _hole: Node3D               # the black hole (world): the ball, its rim, the disc
var _disc: Node3D
var _rings: Array[Node3D] = []
var _hole_light: OmniLight3D
var _flash: MeshInstance3D      # the burst: a sphere of light swelling and fading
var _flash_m: StandardMaterial3D
var _clock := 0.0
# holding
var _held_b: VoxelBody          # a body held ...
var _held_rb: RigidBody3D       # ... or a piece
var _hold_pos := Vector3.ZERO   # the held body's position as we set it (the arena's nudges don't count)
var _hold_v := Vector3.ZERO     # its middle's velocity
var _held_t := 0.0              # seconds it's been held
var _hold_k := 0.0              # 0 empty .. 1 holding (eased: the prongs, the core, the view)
var _thrown := []               # [{rb or b, t, spent}]: launched, still able to hit
# the look of the gun
var _prong_k := 0.0             # 0 shut .. 1 wide open (more on a launch)
var _punch := 0.0               # the core's punch, 1 just launched
var _purple := 0.0              # the core gone purple (a black hole just fired)
var _recoil_t := 0.0            # the view's kick: where it's heading ...
var _recoil := 0.0              # ... and where it is (eased)
# the black hole
var _hs := ""                   # "", "fly", "open", "collapse"
var _hst := {}                  # its flight (hole_fly)
var _hp := Vector3.INF          # where it is
var _ht := 0.0                  # seconds open / collapsing
var _hole_cd := 0.0
var _hstat := {}                # what the black hole has done (last, till something else replaces it)
var _hframes := 0               # frames it's been open, and what they cost (ms)
var _hms := 0.0
var _burst_t := 0.0             # seconds since the burst (its flash)
var _pull_pos := {}             # body instance id -> its position as we set it
var _crush_next := {}           # body instance id -> seconds till it's crushed again
var _crush_gap := 0.0
var _pulled_rb := {}            # rigid pieces we took gravity off (instance id -> rb)
var _well_was := []             # the debris well's settings before (put back after) ...
var _well_d: Node3D             # ... on this VoxelDebris
var _eaten0 := 0                # its cubes eaten count last frame
var _stream_t := 0.0

func _build() -> void:
	_core_m = mat(ORANGE, 0.0, 0.3, 3.0)
	_glow_m = StandardMaterial3D.new()
	_glow_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_m.vertex_color_use_as_albedo = true
	_gun = Node3D.new()
	view.add_child(_gun)
	var inner := Node3D.new()
	inner.scale = Vector3.ONE * VIEW_SCALE
	_gun.add_child(inner)
	_parts = _model(inner, false)
	var glove := mat(Color(0.12, 0.11, 0.11), 0.0, 0.9)
	box(inner, Vector3(0.05, 0.075, 0.075), Vector3(0, -0.06, 0.005), glove, Vector3(0.25, 0, 0))
	box(inner, Vector3(0.022, 0.03, 0.05), Vector3(-0.032, -0.03, -0.02), glove)       # the thumb
	box(inner, Vector3(0.07, 0.05, 0.08), Vector3(-0.02, -0.035, -0.12), glove)        # the other hand under it
	_gun.transform = _aim(REST, AIM_AT)
	_light = OmniLight3D.new()
	_light.light_color = ORANGE
	_light.omni_range = 2.6
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.top_level = true
	add_child(_light)
	_beam = MeshInstance3D.new()
	_beam.mesh = ImmediateMesh.new()
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.vertex_color_use_as_albedo = true
	_beam.material_override = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	add_child(_beam)
	# sparks: one draw call
	_sp = MultiMeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	cube.material = _glow_m
	_sp.multimesh = MultiMesh.new()
	_sp.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_sp.multimesh.use_colors = true
	_sp.multimesh.mesh = cube
	_sp.multimesh.instance_count = SPARKS
	_sp.multimesh.visible_instance_count = 0
	_sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sp.top_level = true
	add_child(_sp)
	_spp.resize(SPARKS)
	_spv.resize(SPARKS)
	_spc.resize(SPARKS)
	_spl.resize(SPARKS)
	_spl0.resize(SPARKS)
	_sps.resize(SPARKS)
	_spw.resize(SPARKS)
	_build_hole(cube)

# the black hole: a black ball, a rim of light round it (brightest at its edge), the disc's rings of glowing cubes, a
# purple light; and the burst's flash
func _build_hole(cube: BoxMesh) -> void:
	_hole = Node3D.new()
	_hole.top_level = true
	add_child(_hole)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = HOLE_BALL
	sm.height = HOLE_BALL * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	ball.mesh = sm
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color(0, 0, 0)
	ball.material_override = black
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hole.add_child(ball)
	var rim := MeshInstance3D.new()
	var rm := SphereMesh.new()
	rm.radius = HOLE_BALL * 1.32
	rm.height = HOLE_BALL * 2.64
	rm.radial_segments = 24
	rm.rings = 12
	rim.mesh = rm
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;
uniform vec4 rim : source_color = vec4(0.72, 0.42, 1.0, 1.0);
uniform float energy = 2.2;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(f, 2.2);
	ALBEDO = (rim.rgb * edge + vec3(1.0) * pow(f, 7.0) * 0.8) * energy;
	ALPHA = clamp(edge * 1.4, 0.0, 1.0);
}
"""
	var rmat := ShaderMaterial.new()
	rmat.shader = sh
	rim.material_override = rmat
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hole.add_child(rim)
	# the rim again, fainter, seen through whatever is in front of it (the bodies circling it hide the ball)
	var halo := MeshInstance3D.new()
	halo.mesh = rm
	var hsh := Shader.new()
	hsh.code = sh.code.replace("depth_draw_never", "depth_draw_never, depth_test_disabled")
	var hmat := ShaderMaterial.new()
	hmat.shader = hsh
	hmat.set_shader_parameter("energy", 0.9)
	halo.material_override = hmat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hole.add_child(halo)
	_disc = Node3D.new()
	_hole.add_child(_disc)
	for rg in RINGS:
		var ring := Node3D.new()
		_disc.add_child(ring)
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = cube
		var n: int = rg[2]
		mm.instance_count = n
		for i in n:
			var k := randf()
			var r := lerpf(float(rg[0]), float(rg[1]), k)
			var a := TAU * (float(i) + randf() * 0.6) / float(n)
			var s := float(rg[3]) * randf_range(0.6, 1.3)
			var bs := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)).scaled(Vector3.ONE * s)
			mm.set_instance_transform(i, Transform3D(bs, Vector3(cos(a) * r, randf_range(-1.0, 1.0) * 0.025 * r, sin(a) * r)))
			var c := (rg[4] as Color).lerp(rg[5] as Color, k)
			mm.set_instance_color(i, Color(c.r, c.g, c.b, randf_range(0.55, 1.0)))
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.add_child(mmi)
		_rings.append(ring)
	_hole.visible = false
	_hole_light = OmniLight3D.new()
	_hole_light.light_color = Color(0.5, 0.16, 1.0)
	_hole_light.omni_range = 7.0
	_hole_light.light_energy = 0.0
	_hole_light.shadow_enabled = false
	_hole_light.top_level = true
	add_child(_hole_light)
	_flash = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 1.0
	fm.height = 2.0
	fm.radial_segments = 20
	fm.rings = 10
	_flash.mesh = fm
	_flash_m = StandardMaterial3D.new()
	_flash_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash.material_override = _flash_m
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.top_level = true
	_flash.visible = false
	add_child(_flash)

# the gun's boxes under root (the grip at the origin, the mouth toward -z, its top +y, metres); light: brighter, for
# top-down. Returns {prongs: [[pivot, its basis shut]], core, hot, mouth (a node in the middle of the prongs)}.
func _model(root: Node3D, light: bool) -> Dictionary:
	var orange := mat(ORANGE.lightened(0.1) if light else ORANGE.darkened(0.08), 0.1, 0.5)
	var orange_dk := mat(ORANGE.darkened(0.4), 0.1, 0.6)
	var dark := mat(DARK.lightened(0.25) if light else DARK, 0.55, 0.45)
	var black := mat(Color(0.22, 0.22, 0.24) if light else Color(0.07, 0.07, 0.08), 0.3, 0.6)
	var steel := mat(Color(0.56, 0.57, 0.6), 0.85, 0.3)
	var hot := mat(Color(1.0, 0.95, 0.8), 0.0, 0.3, 6.0)
	# the grip (raked back) and the trigger guard
	box(root, Vector3(0.036, 0.1, 0.045), Vector3(0, -0.06, 0.01), black, Vector3(0.25, 0, 0))
	box(root, Vector3(0.012, 0.012, 0.06), Vector3(0, -0.045, -0.04), black)
	# the orange back end over the grip, a black band round it, a hump on top
	box(root, Vector3(0.12, 0.11, 0.17), Vector3(0, 0.045, 0.06), orange)
	box(root, Vector3(0.124, 0.114, 0.022), Vector3(0, 0.045, 0.03), black)
	box(root, Vector3(0.07, 0.016, 0.12), Vector3(0, 0.105, 0.07), orange_dk)
	box(root, Vector3(0.1, 0.08, 0.02), Vector3(0, 0.045, 0.15), black)                 # the back plate
	# the dark body ahead of it: steel ribs, orange side panels with vents
	box(root, Vector3(0.14, 0.12, 0.17), Vector3(0, MOUTH_Y, -0.105), dark)
	for z in [-0.06, -0.1, -0.14]:
		box(root, Vector3(0.146, 0.018, 0.016), Vector3(0, 0.0, z), steel)
	for s in [-1.0, 1.0]:
		box(root, Vector3(0.012, 0.06, 0.12), Vector3(0.074 * s, 0.055, -0.1), orange)
		for i in 3:
			box(root, Vector3(0.014, 0.008, 0.09), Vector3(0.077 * s, 0.04 + 0.018 * i, -0.1), black)
	# the square mouth round the core, open at the top (the core seen over it from behind)
	for e in [[Vector3(0.17, 0.03, 0.05), Vector3(0, MOUTH_Y - 0.07, MOUTH_Z)],
			[Vector3(0.03, 0.12, 0.05), Vector3(0.07, MOUTH_Y - 0.005, MOUTH_Z)], [Vector3(0.03, 0.12, 0.05), Vector3(-0.07, MOUTH_Y - 0.005, MOUTH_Z)]]:
		box(root, e[0], e[1], dark)
	# the core: a glowing block standing up out of the mouth (over the body's top, seen from behind), the mouth lined
	# with glow
	var core := box(root, Vector3(0.085, 0.085, 0.085), Vector3(0, MOUTH_Y + 0.035, MOUTH_Z - 0.05), _core_m)
	var hot_mi := box(root, Vector3(0.04, 0.04, 0.09), Vector3(0, MOUTH_Y + 0.035, MOUTH_Z - 0.05), hot)
	for e in [[Vector3(0.11, 0.008, 0.04), Vector3(0, MOUTH_Y - 0.051, MOUTH_Z - 0.01)],
			[Vector3(0.008, 0.1, 0.04), Vector3(0.051, MOUTH_Y, MOUTH_Z - 0.01)], [Vector3(0.008, 0.1, 0.04), Vector3(-0.051, MOUTH_Y, MOUTH_Z - 0.01)]]:
		box(root, e[0], e[1], _core_m)
	# three claws on the mouth's rim (upper right and left on its posts, one under it), each turning out about its root
	var prongs := []
	for deg in [30.0, 150.0, 270.0]:
		var a := deg_to_rad(deg)
		var radial := Vector3(cos(a), sin(a), 0)
		var tangent := Vector3(-sin(a), cos(a), 0)
		var piv := Node3D.new()
		root.add_child(piv)
		# its own space: x along the rim, y out from the middle, +z forward (out of the mouth)
		var bs := Basis(tangent, radial, tangent.cross(radial))
		piv.transform = Transform3D(bs, Vector3(0, MOUTH_Y, MOUTH_Z - 0.02) + radial * 0.072)
		box(piv, Vector3(0.03, 0.026, 0.05), Vector3(0, 0.004, 0.0), dark)               # its root
		box(piv, Vector3(0.022, 0.022, 0.16), Vector3(0, 0.0, 0.095), steel)
		box(piv, Vector3(0.026, 0.012, 0.13), Vector3(0, 0.014, 0.085), orange_dk)      # its back
		box(piv, Vector3(0.02, 0.02, 0.06), Vector3(0, -0.018, 0.19), steel, Vector3(0.6, 0, 0))     # the tip, hooked in
		prongs.append([piv, bs])
	var mouth := Node3D.new()
	mouth.position = Vector3(0, MOUTH_Y, MOUTH_Z - 0.17)
	root.add_child(mouth)
	return {"prongs": prongs, "core": core, "hot": hot_mi, "mouth": mouth}

static func _aim(at: Vector3, to: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(to - at, Vector3.UP), at)

func hand_mesh() -> Node3D:
	var root := Node3D.new()
	_hand = Node3D.new()
	root.add_child(_hand)
	var inner := Node3D.new()
	inner.rotation = Vector3(0, PI, 0)              # its mouth toward +z, out of the hands
	inner.scale = Vector3.ONE * 1.4                 # stout enough to see from up there
	inner.position = Vector3(0, 0.02, 0.05)
	_hand.add_child(inner)
	_hand_parts = _model(inner, true)
	return root

func hand_pose() -> String:
	return "shotgun"                # at the hip, both hands on it

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var org := Color(ORANGE.r, ORANGE.g, ORANGE.b, col.a)
	var dim := Color(col.r * 0.45, col.g * 0.45, col.b * 0.5, col.a)
	var glow := Color(1.0, 0.85, 0.5, col.a) if _holding() else Color(ORANGE.r, ORANGE.g * 0.8, 0.1, col.a)
	for e in [[Rect2(0.7, 2.9, 0.8, 1.8), dim], [Rect2(0.2, 1.2, 2.6, 1.9), org], [Rect2(2.8, 1.0, 3.1, 2.3), col],
			[Rect2(3.2, 1.6, 2.3, 0.35), dim], [Rect2(5.9, 0.7, 0.7, 2.9), col], [Rect2(6.6, 1.7, 0.8, 0.9), glow],
			[Rect2(6.6, 0.45, 2.5, 0.45), col], [Rect2(6.6, 3.2, 2.5, 0.45), col], [Rect2(8.9, 0.45, 0.5, 1.0), col],
			[Rect2(8.9, 2.65, 0.5, 1.0), col]]:
		var rr: Rect2 = e[0]
		ci.draw_rect(Rect2(r.position + rr.position * u, rr.size * u), e[1])

# ---------------------------------------------------------------- the buttons

## Put away: what's held is let go (gently); a black hole goes on by itself.
func on_deselect() -> void:
	if _holding():
		drop()
	sfx_stop("hold")

func cooling() -> float:
	return clampf(_hole_cd / HOLE_CD, 0.0, 1.0)

func bar_text() -> String:
	if _holding():
		return "held"
	if _hs != "":
		return "hole"
	return ""

func press(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		if _holding():
			launch()
		else:
			grab()
	elif button == MOUSE_BUTTON_RIGHT:
		if _holding():
			drop()
		else:
			fire_hole()

func _holding() -> bool:
	return (_held_b != null and is_instance_valid(_held_b)) or (_held_rb != null and is_instance_valid(_held_rb))

## Left click, holding nothing: what's under the aim flies to the hold point and stays there.
func grab() -> void:
	var h := _pick_now()
	if h.is_empty():
		_miss()
		return
	var what := String(h.kind)
	var dist := float(h.dist)
	if what == "piece":
		_held_rb = h.rb
	else:
		var b: VoxelBody = h.body
		if b.fragment:
			# a lying fragment: made a piece again (it was one), and that's what's held
			_held_rb = _unfragment(b)
			what = "fragment"
			if _held_rb == null:
				_miss()
				return
		else:
			what = "body" if b.alive else "dead"
			_held_b = b
			carry(b)
			_hold_pos = b.position
			_hold_v = Vector3.ZERO
			_pull_pos.erase(b.get_instance_id())
	_held_t = 0.0
	if _held_rb != null:
		_held_rb.gravity_scale = PIECE_GRAV
		_held_rb.sleeping = false
		_pulled_rb.erase(_held_rb.get_instance_id())
	# caught again after a throw: it can't hit anyone on its way here, nor be hurt landing after a drop
	var got: Object = _held_b if _held_b != null else _held_rb
	_thrown = _thrown.filter(func(e): return e.get("b", e.get("rb")) != got)
	sfx("gravity_grab")
	_recoil_t = 0.3
	_punch = maxf(_punch, 0.4)
	shooter.kick = maxf(float(shooter.kick), 0.3)
	var m := _mouth_world()
	for i in 10:
		_spark(m, (_held_mid() - m).normalized() * randf_range(3.0, 7.0) + _rand_v(1.5), ORANGE.lerp(Color.WHITE, randf()), 0.25, 0.012)
	last = {"move": "grab", "what": what, "dist_m": snappedf(dist, 0.1), "launched": false}

## Left click, holding something: it's thrown where you look.
func launch() -> void:
	var f := look()
	var m := _mouth_world()
	if _held_b != null and is_instance_valid(_held_b):
		var b := _held_b
		_held_b = null
		throw_body(b, f)
		_thrown.append({"b": b, "t": 0.0})
		last["v"] = snappedf(b.air_v.length(), 0.1)
	elif _held_rb != null and is_instance_valid(_held_rb):
		var rb := _held_rb
		_held_rb = null
		rb.gravity_scale = 1.0
		rb.linear_velocity = f * LAUNCH_V + Vector3.UP * 0.6
		rb.angular_velocity = _rand_v(6.0)
		_thrown.append({"rb": rb, "t": 0.0, "spent": false})
		last["v"] = LAUNCH_V
	last["move"] = "launch"
	last["held_s"] = snappedf(_held_t, 0.01)
	last["launched"] = true
	last["rams"] = 0
	sfx_stop("hold")
	sfx("gravity_launch", Vector3.INF, 2.0)
	_punch = 1.0
	_prong_k = 1.5
	_recoil_t = 1.0
	shooter.kick = maxf(float(shooter.kick), 0.9)
	shooter.avatar.recoil = 1.0
	if top_down():
		shooter.avatar.attack = 0.4
	hit_stop(0.03, 0.25)
	for i in 30:
		_spark(m, f * randf_range(4.0, 12.0) + _rand_v(3.0), ORANGE.lerp(Color(1, 1, 0.8), randf()), randf_range(0.2, 0.4), randf_range(0.01, 0.022))

## Right click, holding something: let go of it gently.
func drop() -> void:
	if _held_b != null and is_instance_valid(_held_b):
		var b := _held_b
		_held_b = null
		var v := Vector3(_hold_v.x, minf(_hold_v.y, 0.0), _hold_v.z) * 0.3
		if b.frozen():
			b.air_v = v
			b.tumble_v = 0.5
		else:
			b.launch(v, 0.5)
	elif _held_rb != null and is_instance_valid(_held_rb):
		_held_rb.gravity_scale = 1.0
		_held_rb.linear_velocity *= 0.3
	_held_b = null
	_held_rb = null
	sfx_stop("hold")
	sfx("gravity_drop")
	_recoil_t = -0.15
	last["move"] = "drop"

# nothing under the aim: a dry click and a puff from the prongs
func _miss() -> void:
	sfx("gravity_miss")
	_prong_k = 0.6
	_recoil_t = 0.12
	var m := _mouth_world()
	var f := look()
	for i in 8:
		_spark(m, f * randf_range(0.5, 1.5) + _rand_v(0.8), Color(1.0, 0.6, 0.25), 0.3, 0.01)
	last = {"move": "miss"}

## Right click, holding nothing: a black hole (one at a time, HOLE_CD apart).
func fire_hole() -> void:
	if _hs != "" or _hole_cd > 0.0:
		sfx("gravity_miss", Vector3.INF, -4.0)
		return
	_hole_cd = HOLE_CD
	var e := eye()
	var f := look()
	var start := e + f * 0.6
	if not top_down():
		# out of the mouth, toward the crosshair's point where it would open (6.3 m out, or nearer if it's in the way)
		var reach := HOLE_V * HOLE_FLY
		var q := PhysicsRayQueryParameters3D.create(e, e + f * reach, 1)
		var ex: Array[RID] = shooter.exclude()
		q.exclude = ex
		var wh: Dictionary = arena.get_world_3d().direct_space_state.intersect_ray(q)
		if not wh.is_empty():
			reach = e.distance_to(wh.position)
		var to := e + f * reach
		start = _mouth_world()
		f = (to - start).normalized()
	_hst = {"p": start, "v": f * HOLE_V, "t": 0.0, "from": start}
	_hs = "fly"
	_hp = start
	_hole.visible = true
	_hole.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.35), start)
	_disc.scale = Vector3.ONE * 0.001
	sfx("gravity_launch", Vector3.INF, -3.0, 0.6)
	_purple = 1.0
	_punch = 0.8
	_recoil_t = 0.7
	shooter.kick = maxf(float(shooter.kick), 0.6)
	shooter.avatar.recoil = 1.0
	_hstat = {"move": "hole", "state": "fly", "pulled": 0, "crushes": 0, "cut": 0, "pieces_eaten": 0, "cubes_eaten": 0,
		"killed": 0, "gone": 0, "flung": 0, "crush_ms": 0.0, "crush_max_ms": 0.0, "frame_max_ms": 0.0, "frame_avg_ms": 0.0}
	_hframes = 0
	_hms = 0.0
	last = _hstat

# ---------------------------------------------------------------- what's under the aim

# the grab's pick: first person along the eye's line; top-down along the mouse's line from the camera (things within
# REACH of Jared)
func _pick_now() -> Dictionary:
	var from := eye()
	var dir := look()
	if top_down():
		var mr: Array = shooter.mouse_ray()
		if not mr.is_empty():
			from = mr[0]
			dir = mr[1]
	var reach := REACH if not top_down() else 40.0
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 1)
	var ex: Array[RID] = shooter.exclude()
	q.exclude = ex
	var wh: Dictionary = arena.get_world_3d().direct_space_state.intersect_ray(q)
	if not wh.is_empty():
		reach = minf(reach, from.distance_to(wh.position) + 0.4)
	var h := pick(arena.bodies, arena.pieces.list(), from, dir, reach)
	if not h.is_empty() and top_down():
		var at: Vector3 = (h.rb as Node3D).global_position if h.kind == "piece" else middle(h.body)
		var pp: Vector3 = shooter.player.global_position
		var lvl := Vector2(at.x - pp.x, at.z - pp.z).length()
		if lvl > REACH:
			return {}
		h.dist = lvl
	return h

## What's under the aim (static, for the checks): the nearest thing along the line from `from` along dir (unit)
## within reach: a piece (pieces: VoxelPieces.list()'s [{rb}]) whose middle is within PICK_R of the line, or a body
## the line goes into (VoxelBody.trace; failing that, one whose middle is within BODY_PICK_R of it). Returns {} or
## {kind: "piece" / "body", rb / body, dist: metres along the line}.
static func pick(bodies: Array, pieces: Array, from: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for pc in pieces:
		var rb = pc.rb
		if not is_instance_valid(rb) or not (rb as Node3D).visible:
			continue
		var p: Vector3 = (rb as Node3D).global_position
		var along := (p - from).dot(dir)
		if along < 0.0 or along > best_d or (from + dir * along).distance_to(p) > PICK_R:
			continue
		best_d = along
		best = {"kind": "piece", "rb": rb, "dist": along}
	for bb in bodies:
		if not is_instance_valid(bb):
			continue
		var b: VoxelBody = bb
		var d := INF
		var h := b.trace(from, dir, best_d)
		if not h.is_empty():
			d = float(h.dist)
		else:
			var m := middle(b)
			var along := (m - from).dot(dir)
			if along > 0.0 and (from + dir * along).distance_to(m) <= BODY_PICK_R:
				d = along
		if d < best_d:
			best_d = d
			best = {"kind": "body", "body": b, "dist": d}
	return best

## A body's middle, world: carried or flying (turning over about its middle), lying (toppled back from its feet), or
## standing.
static func middle(b: VoxelBody) -> Vector3:
	if b.airborne or (b.alive and b.down_t <= 0.0 and b.up_t <= 0.0):
		return b.global_position + Vector3(0, b.height * 0.5, 0)
	return b.global_position + Basis(Vector3.UP, b.yaw) * Vector3(0, 0.12, -b.height * 0.5)

# a lying fragment made a piece again (VoxelPieces.from_fragment), nudged up toward you; null if nothing came of it
func _unfragment(b: VoxelBody) -> RigidBody3D:
	var lst: Array = arena.pieces.list()
	var before: Object = lst.back().rb if not lst.is_empty() else null
	b.air_v = (eye() - b.global_position).normalized() * 2.0 + Vector3.UP * 2.0
	b.tumble_v = 2.0
	arena.pieces.from_fragment(b)
	lst = arena.pieces.list()
	if lst.is_empty() or lst.back().rb == before:
		return null
	return lst.back().rb

# ---------------------------------------------------------------- holding and throwing (static, for the checks)

## Picks body b up (static, for the checks): carried from now on (see _keep); one lying is turned so its middle stays
## where it was (it turns upright as it's held).
static func carry(b: VoxelBody) -> void:
	if not b.airborne:
		if b.alive and b.down_t <= 0.0 and b.up_t <= 0.0:
			b.tumble = 0.0
		else:
			b.position += Basis(Vector3.UP, b.yaw) * Vector3(0, 0.12 - b.height * 0.5, -b.height * 0.5)
			b.tumble = PI / 2.0
	_keep(b)

# carried: in the air (turning over about its middle), going nowhere by itself (we set its position), not walking,
# not shoved, not swinging; a little air speed up, so the arena never lands it
static func _keep(b: VoxelBody) -> void:
	b.airborne = true
	b.air_v = Vector3(0, CARRY_UP, 0)
	b.tumble_v = 0.0
	b.knock = Vector3.ZERO
	b.stagger = maxf(b.stagger, 0.2)
	b.down_t = 0.0
	b.up_t = 0.0
	b.attack = 0.0

# a carried body kept off the floor (its lowest point, as far as it's turned over) and inside the walls
static func _clamp(b: VoxelBody) -> void:
	var p := b.position
	p.y = maxf(p.y, b.height * 0.5 * (absf(cos(b.tumble)) - 1.0) + 0.03)
	p.x = clampf(p.x, -21.0, 21.0)
	p.z = clampf(p.z, -21.0, 21.0)
	b.position = p

## One frame of a held body (static, for the checks): its middle pulled toward `to` by a damped spring (at most
## MAX_PULL m/s), turned slowly upright, carried. vel: its middle's velocity; returns it, updated.
static func hold_body(b: VoxelBody, to: Vector3, vel: Vector3, dt: float) -> Vector3:
	vel += ((to - middle(b)) * SPRING - vel * DAMP) * dt
	vel = vel.limit_length(MAX_PULL)
	b.position += vel * dt
	b.tumble = lerp_angle(b.tumble, 0.18, 1.0 - exp(-dt * 4.0))
	_clamp(b)
	_keep(b)
	return vel

## Throws body b along dir (static, for the checks): VoxelBody.launch at dir * BODY_V + up * BODY_UP, turning over;
## one frozen solid flies as a statue (a launch would shatter it at once).
static func throw_body(b: VoxelBody, dir: Vector3) -> void:
	var v := dir * BODY_V + Vector3.UP * BODY_UP
	b.position.y = maxf(b.position.y, 0.02)
	if b.frozen():
		b.airborne = true
		b.air_v = v
		b.tumble_v = BODY_SPIN * 0.5
		b.knock = Vector3.ZERO
	else:
		b.launch(v, BODY_SPIN)

## A launched piece hitting body b at `at` going at vel (static, for the checks): a dent knocked in where it hit
## (carve, RAM_DENT), RAM_HURT off, and he's knocked flying along it. Returns the dent's carve result with "at".
static func piece_hit(b: VoxelBody, at: Vector3, vel: Vector3) -> Dictionary:
	var u := vel.normalized()
	var h := b.trace(at - u * 0.8, u, 1.6)
	var q: Vector3 = h.point if not h.is_empty() else at
	var res := b.carve(q, q + u * 0.04, RAM_DENT, 0.08, 2)
	res["at"] = q
	if bool(res.get("shattered", false)):
		return res
	if b.alive and b.hurt(RAM_HURT):
		res.killed = true
	b.launch(Vector3(vel.x, 0.0, vel.z) * 0.45 + Vector3.UP * 3.0, 6.0)
	return res

# ---------------------------------------------------------------- the black hole (static, for the checks)

## The black hole's flight (static, for the checks): st = {p, v, t, from}; one step of dt: it moves on, and stops at
## the first wall or pillar (space; null: just the floor), the floor, a body (once it's HOLE_PAST from where it was
## fired: it slips past nearer ones), or when it's flown HOLE_FLY seconds. True once it's stopped: st.p is then where
## it opens (clear of the wall, in front of the body, at least HOLE_Y up).
static func hole_fly(st: Dictionary, dt: float, bodies: Array, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> bool:
	var p0: Vector3 = st.p
	var v: Vector3 = st.v
	var sl := v.length() * dt
	var dir := v.normalized()
	var best := sl
	var stop := false
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(p0, p0 + dir * (sl + HOLE_BALL), 1)
		q.exclude = exclude
		var wh := space.intersect_ray(q)
		if not wh.is_empty():
			best = maxf(0.0, p0.distance_to(wh.position) - HOLE_BALL)
			stop = true
	if dir.y < -0.0001 and p0.y + dir.y * best < HOLE_BALL:
		best = maxf(0.0, (p0.y - HOLE_BALL) / -dir.y)
		stop = true
	if not st.has("from"):
		st["from"] = p0
	var from: Vector3 = st.from
	for bb in bodies:
		if not is_instance_valid(bb) or p0.distance_to(from) + sl < HOLE_PAST:
			continue
		var h: Dictionary = (bb as VoxelBody).trace(p0, dir, best + HOLE_BALL)
		if not h.is_empty():
			best = maxf(0.0, float(h.dist) - HOLE_BALL)
			stop = true
	st.t = float(st.t) + dt
	var p1 := p0 + dir * best
	if float(st.t) >= HOLE_FLY:
		stop = true
	if stop:
		p1.y = maxf(p1.y, HOLE_Y)
	st.p = p1
	return stop

## One frame of the pull on body b (static, for the checks): its middle dragged toward c, faster the nearer (PULL_V at
## HOLE_R up to PULL_NEAR at the middle), swirling round it, turning over and spinning, carried off its feet, till it
## circles c ORBIT out (less as it's eaten). Returns how far its middle was from c.
static func pull_body(b: VoxelBody, c: Vector3, dt: float) -> float:
	if not b.airborne:
		carry(b)
	var to := c - middle(b)
	var d := to.length()
	if d > 0.001:
		var k := clampf(1.0 - d / HOLE_R, 0.0, 1.0)
		var u := to / d
		var start := 0
		for n in b.parts:
			start += int(b.parts[n].start)
		var orbit := ORBIT * clampf(float(b.cubes_left()) / float(maxi(1, start)), 0.3, 1.0)
		var gap := d - orbit
		var radial := minf(lerpf(PULL_V, PULL_NEAR, k * k) * dt, gap) if gap > 0.0 else maxf(-0.6 * dt, gap)
		var tang := u.cross(Vector3.UP)
		tang = tang.normalized() * lerpf(SWIRL * minf(1.0, d), SWIRL_NEAR, k * k) if tang.length() > 0.01 else Vector3.ZERO
		b.position += u * radial + tang * dt
		b.tumble += dt * (1.5 + 9.0 * k)
		b.yaw += dt * (1.0 + 5.0 * k)
	_clamp(b)
	_keep(b)
	return d

## One crush (static, for the checks): a ball CRUSH_BALL wide crushed out of body b where it's nearest c, CRUSH_HURT
## off. Limbs and the head go first, the nearest first: the ball at the first cube left on its line out from LIMB_IN
## past its joint (clear of the trunk), so a limb is cut through and comes off, and the head is chewed up through the
## brain; then the trunk, at the first cube on the line from c to its middle (or another way, once that's hollowed
## out). Returns carve's result with "at" and "part" ({} if there's nothing left of it).
static func crush(b: VoxelBody, c: Vector3) -> Dictionary:
	var lines := []                 # [how far its line starts from c, part, start, direction, length]
	var trunk := ""
	for n in b.parts:
		var p: Dictionary = b.parts[n]
		if bool(p.gone) or int(p.left) <= 0:
			continue
		if TRUNK.has(n):
			trunk = n
			continue
		if int(p.left) * 8 < int(p.start):
			continue                # a stub
		var j := joint(b, n)
		var ax := (part_middle(b, n) - j) * 2.0
		var al := ax.length()
		if al < 0.001:
			continue
		var u := ax / al
		var a0 := j + u * minf(LIMB_IN, al * 0.75)
		lines.append([a0.distance_to(c), n, a0, u, al - (a0 - j).length() + b.vm])
	lines.sort_custom(func(x, y): return x[0] < y[0])
	var best := ""
	var q := Vector3.INF
	for i in mini(8, lines.size()):             # (a stub's line is empty: the next one)
		var ln: Array = lines[i]
		if float(ln[0]) > LIMB_REACH:
			break
		var h := b.trace(ln[2], ln[3], ln[4])
		if not h.is_empty():
			best = ln[1]
			q = (h.point as Vector3) + (ln[3] as Vector3) * CRUSH_BALL * 0.4
			break
	if best == "":
		if trunk == "":
			return {}
		best = trunk
		var bm := part_middle(b, trunk)
		q = bm
		var ways := [(bm - c).normalized()] if bm.distance_to(c) > 0.001 else []
		for i in 3:
			ways.append(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized())
		for u in ways:
			var h := b.trace(c, u, 2.0)
			if not h.is_empty():
				q = (h.point as Vector3) + (u as Vector3) * CRUSH_BALL * 0.5
				break
	var res := b.carve(q, q, CRUSH_BALL, CRUSH_HP, 2)
	res["at"] = q
	res["part"] = best
	if not bool(res.get("shattered", false)) and b.alive and b.hurt(CRUSH_HURT):
		res.killed = true
	return res

## A part's joint (where it hangs from its parent), world.
static func joint(b: VoxelBody, n: String) -> Vector3:
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(b.parts[n].bone)).origin

## The middle of a part's grid, world.
static func part_middle(b: VoxelBody, n: String) -> Vector3:
	var p: Dictionary = b.parts[n]
	var bi: int = p.bone
	var bind := Transform3D(Basis.IDENTITY, -b.model.bone_pivot[bi] * b.model.voxel_m)
	var m := b.skeleton.global_transform * b.skeleton.get_bone_global_pose(bi) * bind
	return m * ((Vector3(p.origin) + Vector3(p.grid.size) * 0.5) * b.vm)

## The burst (static, for the checks): body b thrown out from c, level, and up (harder the nearer).
static func fling_out(b: VoxelBody, c: Vector3) -> void:
	var away := middle(b) - c
	away.y = 0.0
	var d := away.length()
	var u := away / d if d > 0.05 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var k := clampf(1.0 - d / HOLE_R, 0.25, 1.0)
	b.position.y = maxf(b.position.y, 0.02)
	b.launch(u * FLING_V * k + Vector3.UP * (2.5 + 3.5 * k), 7.0)

# ---------------------------------------------------------------- every frame

func step(dt: float) -> void:
	_clock += dt
	_hole_cd = maxf(0.0, _hole_cd - dt)
	_punch = maxf(0.0, _punch - dt * 4.0)
	_purple = maxf(0.0, _purple - dt * 1.5)
	_recoil_t *= exp(-dt * 8.0)
	_recoil = lerpf(_recoil, _recoil_t, 1.0 - exp(-dt * 35.0))
	if _held_b != null and is_instance_valid(_held_b) and _held_b.cubes_left() == 0:
		_held_b = null                  # (shattered or burnt away in its grip: nothing left to hold)
	var holding := _holding()
	if not holding:
		_held_b = null              # (freed under it: the vacuum, the oldest corpses going)
		_held_rb = null
		sfx_stop("hold")
	_hold_k = move_toward(_hold_k, 1.0 if holding else 0.0, dt * 5.0)
	_prong_k = lerpf(_prong_k, 1.0 if holding else 0.0, 1.0 - exp(-dt * 10.0))
	if holding:
		_held_t += dt
		_hold_step(dt)
		sfx_loop("hold", "gravity_hold_loop", -9.0 + 2.0 * sin(_clock * 3.0), 1.0 + 0.03 * sin(_clock * 1.7))
	_thrown_step(dt)
	_hole_step(dt)
	_sparks_step(dt)
	_pose_view()
	_pose_hand()
	_draw_beam()

# the hold point: in front of the view, a little below its middle (top-down: in front of Jared's chest), bobbing
func _hold_point(extra: float) -> Vector3:
	var p := eye() + look() * (HOLD_D + extra) + Vector3.UP * BOB * sin(_clock * 2.4)
	if not top_down():
		p -= frame().y * HOLD_DOWN
	return p

func _held_mid() -> Vector3:
	if _held_b != null and is_instance_valid(_held_b):
		return middle(_held_b)
	if _held_rb != null and is_instance_valid(_held_rb):
		return _held_rb.global_position
	return _mouth_world() + look()

func _hold_step(dt: float) -> void:
	if _held_b != null and is_instance_valid(_held_b):
		var b := _held_b
		b.position = _hold_pos
		_hold_v = hold_body(b, _hold_point(b.height * HOLD_BODY), _hold_v, dt)
		_hold_pos = b.position
		# it turns to face you, swaying slowly round as you look about
		var pp: Vector3 = eye()
		b.yaw = lerp_angle(b.yaw, atan2(pp.x - b.position.x, pp.z - b.position.z) + 0.45 * sin(_clock * 0.6), 1.0 - exp(-dt * 2.5))
		_pose_carried(b)
	elif _held_rb != null and is_instance_valid(_held_rb):
		var rb := _held_rb
		var want := ((_hold_point(0.0) - rb.global_position) * PIECE_K).limit_length(MAX_PULL)
		rb.linear_velocity = rb.linear_velocity.lerp(want, 1.0 - exp(-dt * PIECE_EASE))
		rb.angular_velocity = rb.angular_velocity.lerp(Vector3(0.25 * sin(_clock * 0.9), 0.7, 0.2), 1.0 - exp(-dt * 3.0))
		rb.gravity_scale = PIECE_GRAV
		rb.sleeping = false
		for pc in arena.pieces.list():
			if pc.rb == rb:
				# hovering isn't lying still, nor rocking on the floor (held low): it isn't made a body again
				pc.still = 0.0
				pc.t = minf(float(pc.t), 1.0)

# a carried body's limbs (after the arena posed it): a live one flails, arms and legs going; a dead one hangs limp;
# a frozen one stays a statue
func _pose_carried(b: VoxelBody) -> void:
	if b.frozen() or b.fragment:
		return
	var t := _clock + float(b.get_instance_id() % 13) * 0.7
	var rot := {}
	if b.alive:
		rot = {"arm_r": Vector3(-2.1 + 0.9 * sin(t * 11.0), 0.0, -0.5 - 0.35 * sin(t * 7.0)),
			"arm_l": Vector3(-2.1 + 0.9 * sin(t * 11.0 + 2.2), 0.0, 0.5 + 0.35 * sin(t * 7.6)),
			"forearm_r": Vector3(-0.8 - 0.6 * sin(t * 13.0), 0.0, 0.0),
			"forearm_l": Vector3(-0.8 - 0.6 * sin(t * 12.0 + 1.0), 0.0, 0.0),
			"thigh_l": Vector3(-0.5 + 0.7 * sin(t * 9.0), 0.0, 0.15),
			"thigh_r": Vector3(-0.5 + 0.7 * sin(t * 9.0 + PI), 0.0, -0.15),
			"shin_l": Vector3(0.6 + 0.5 * sin(t * 9.0 + 1.2), 0.0, 0.0),
			"shin_r": Vector3(0.6 + 0.5 * sin(t * 9.0 + PI + 1.2), 0.0, 0.0),
			"head": Vector3(-0.3 + 0.25 * sin(t * 5.0), 0.4 * sin(t * 6.5), 0.0)}
	else:
		rot = {"arm_r": Vector3(0.15 * sin(t * 2.0), 0.0, -0.12), "arm_l": Vector3(0.15 * sin(t * 2.0 + 1.0), 0.0, 0.12),
			"forearm_r": Vector3(-0.2, 0.0, 0.0), "forearm_l": Vector3(-0.2, 0.0, 0.0),
			"thigh_l": Vector3(0.1 * sin(t * 1.7), 0.0, 0.05), "thigh_r": Vector3(0.1 * sin(t * 1.7 + 1.5), 0.0, -0.05),
			"shin_l": Vector3(0.25, 0.0, 0.0), "shin_r": Vector3(0.25, 0.0, 0.0), "head": Vector3(0.55, 0.0, 0.15)}
	for n in rot:
		var bi := b.model.bone(n)
		if bi >= 0:
			b.skeleton.set_bone_pose_rotation(bi, Quaternion.from_euler(rot[n]))

# launched things still flying: a piece hits the first body it meets at speed; a body is hurt as it comes down (a
# frozen one shatters)
func _thrown_step(dt: float) -> void:
	for i in range(_thrown.size() - 1, -1, -1):
		var e: Dictionary = _thrown[i]
		e.t = float(e.t) + dt
		if e.has("rb"):
			var rb = e.rb
			if not is_instance_valid(rb) or bool(e.spent) or float(e.t) > RAM_T:
				_thrown.remove_at(i)
				continue
			var v: Vector3 = (rb as RigidBody3D).linear_velocity
			if v.length() < RAM_V:
				continue
			var p: Vector3 = (rb as Node3D).global_position
			for bb in arena.bodies:
				if not is_instance_valid(bb) or bb.fragment:
					continue
				var b: VoxelBody = bb
				var off := Vector2(p.x - b.global_position.x, p.z - b.global_position.z).length()
				if off > RAM_R or p.y < b.global_position.y - 0.2 or p.y > b.global_position.y + b.height + 0.2:
					continue
				_ram(b, rb, p, v)
				e.spent = true
				break
		else:
			var b = e.b
			if not is_instance_valid(b) or float(e.t) > 3.0:
				_thrown.remove_at(i)
				continue
			if (b as VoxelBody).airborne or float(e.t) < 0.05:
				continue
			_thrown.remove_at(i)
			var vb: VoxelBody = b
			if vb.frozen():
				var res := vb.shatter()
				spray(res, Vector3.UP, 3.0)
				sfx("shatter", vb.global_position)
			elif vb.alive:
				vb.hurt(THROWN_HURT)
				sfx("thwack", vb.global_position, -2.0, 0.8)

# a launched piece hit body b: dented, hurt, knocked flying; the piece slowed
func _ram(b: VoxelBody, rb: RigidBody3D, p: Vector3, v: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	var res := piece_hit(b, p, v)
	var u := v.normalized()
	spray(res, u, 3.0)
	if is_instance_valid(b):
		fling(b, res, u * 4.0 + Vector3.UP * 2.0, _rand_v(6.0))
	rb.linear_velocity = v * 0.35
	if bool(res.get("shattered", false)):
		sfx("shatter", res.at)
	sfx("crunch", res.at, 0.0)
	sfx("thwack", res.at, 2.0)
	hit_stop(0.05, 0.08)
	shooter.kick = maxf(float(shooter.kick), 0.5)
	last["rams"] = int(last.get("rams", 0)) + 1
	last["ram_cut"] = int(res.cut)
	last["ram_killed"] = bool(res.killed)
	last["ram_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)

# ---------------------------------------------------------------- the black hole

func _hole_step(dt: float) -> void:
	match _hs:
		"fly":
			var ex: Array[RID] = shooter.exclude()
			var p0: Vector3 = _hst.p
			if hole_fly(_hst, dt, arena.bodies, arena.get_world_3d().direct_space_state, ex):
				_open()
			else:
				_hole.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.35 * (TD_LOOK if top_down() else 1.0)), _hst.p)
				_spark(p0, _rand_v(0.4), PURPLE.lerp(Color.WHITE, randf() * 0.5), 0.3, 0.02)
		"open", "collapse":
			_ht += dt
			_well_on()
			var t0 := Time.get_ticks_usec()
			_pull_step(dt, _hs == "open")
			var fms := (Time.get_ticks_usec() - t0) / 1000.0
			_hstat.frame_max_ms = maxf(float(_hstat.frame_max_ms), snappedf(fms, 0.01))
			_hframes += 1
			_hms += fms
			_hstat.frame_avg_ms = snappedf(_hms / _hframes, 0.01)
			_hstat.cubes_eaten = int(_hstat.cubes_eaten) + int(arena.debris.eaten) - _eaten0
			_eaten0 = arena.debris.eaten
			if _hs == "open" and _ht >= HOLE_OPEN:
				_collapse()
			elif _hs == "collapse" and _ht >= COLLAPSE_T:
				_burst()
	_hole_look(dt)

func _open() -> void:
	_hs = "open"
	_hp = _hst.p
	_ht = 0.0
	_crush_next.clear()
	_crush_gap = 0.0
	_well_d = null
	_well_on()
	sfx("gravity_hole_open", _hp, 3.0)
	shooter.kick = maxf(float(shooter.kick), 0.4)
	_hstat.state = "open"
	_hstat["at"] = _hp.snapped(Vector3.ONE * 0.01)

func _collapse() -> void:
	_hs = "collapse"
	_ht = 0.0
	arena.sound.stop(_hole_key())
	sfx("gravity_hole_close", _hp, 4.0)
	_hstat.state = "collapse"

# everything near is flung out, the well let go, a flash
func _burst() -> void:
	var c := _hp
	_hs = ""
	_reset_well()
	_burst_t = 0.0
	_hole.visible = false
	_flash.visible = true
	var flung := 0
	for bb in arena.bodies:
		if not is_instance_valid(bb) or bb == _held_b:
			continue
		var b: VoxelBody = bb
		var near := middle(b).distance_to(c) <= HOLE_R
		if near:
			if b.fragment:
				b.launch((b.global_position - c).normalized() * 5.0 + Vector3.UP * 3.0, 4.0)
			else:
				fling_out(b, c)
			flung += 1
		elif _pull_pos.has(b.get_instance_id()):
			b.air_v = Vector3.ZERO          # dragged and let go out there: it just falls
	for pc in arena.pieces.list():
		var rb = pc.rb
		if not is_instance_valid(rb) or rb == _held_rb:
			continue
		var away: Vector3 = (rb as Node3D).global_position - c
		if away.length() <= HOLE_R:
			(rb as RigidBody3D).linear_velocity = away.normalized() * 8.0 + Vector3.UP * 4.0
			(rb as RigidBody3D).angular_velocity = _rand_v(8.0)
	_release_pieces()
	_pull_pos.clear()
	_crush_next.clear()
	arena.debris.pop(Vector3(c.x, 0.0, c.z), 3.5, 5.0, 500)
	for i in 120:
		var u := _rand_v(1.0).normalized()
		_spark(c + u * 0.2, u * randf_range(5.0, 14.0), PURPLE.lerp(Color.WHITE, randf() * 0.8), randf_range(0.3, 0.6), randf_range(0.02, 0.05))
	var near_k := clampf(1.0 - eye().distance_to(c) / 12.0, 0.0, 1.0)
	shooter.kick = maxf(float(shooter.kick), 0.6 + 1.2 * near_k)
	hit_stop(0.05, 0.12)
	_hstat.state = "burst"
	_hstat.flung = flung

# the debris well set at the hole (again on new debris: F2 makes it afresh), its settings kept to put back
func _well_on() -> void:
	var d = arena.debris
	if d == _well_d:
		return
	_well_d = d
	_well_was = [d.well_r, d.well_pull, d.well_eat]
	d.well = _hp
	d.well_r = WELL_R
	_eaten0 = d.eaten

# the well let go, its settings as they were
func _reset_well() -> void:
	_well_d = null
	if arena == null or not is_instance_valid(arena) or not is_instance_valid(arena.debris):
		return
	var d = arena.debris
	d.well = Vector3.INF
	if _well_was.size() == 3:
		d.well_r = _well_was[0]
		d.well_pull = _well_was[1]
		d.well_eat = _well_was[2]
	_well_was = []

# pieces we took gravity off get it back
func _release_pieces() -> void:
	for id in _pulled_rb:
		var rb = _pulled_rb[id]
		if is_instance_valid(rb) and rb != _held_rb:
			(rb as RigidBody3D).gravity_scale = 1.0
	_pulled_rb.clear()

func _hole_key() -> String:
	return str(get_instance_id()) + "hole"

# open: bodies dragged in and crushed, pieces pulled in and swallowed; collapsing, the same, harder, no crushing
func _pull_step(dt: float, crushing: bool) -> void:
	var c := _hp
	var grow := clampf(_ht / 0.3, 0.0, 1.0) if _hs == "open" else 1.6
	var pulled := 0
	var due: VoxelBody = null       # the one crushed now: of those due, the living first (one at a time, dead in a few
	var due_k := INF                # crushes), the nearest first; then the dead
	var frags := 0
	_crush_gap -= dt
	for bb in arena.bodies:
		if not is_instance_valid(bb) or bb == _held_b:
			continue
		var b: VoxelBody = bb
		var id := b.get_instance_id()
		if middle(b).distance_to(c) > HOLE_R:
			if _pull_pos.has(id):
				_pull_pos.erase(id)
				b.air_v = Vector3.ZERO      # out of its reach: it falls
			continue
		if b.fragment:
			# a lying fragment: knocked up toward it, so the arena makes it a piece again (and it's pulled in as one)
			if frags < 3:
				frags += 1
				b.launch((c - b.global_position).normalized() * 3.0 + Vector3.UP * 2.5, 3.0)
			continue
		if _pull_pos.has(id):
			b.position = _pull_pos[id]
		var d := pull_body(b, c, dt * grow)
		_pull_pos[id] = b.position
		pulled += 1
		if b.alive:
			_pose_carried(b)
		if crushing and d <= CRUSH_R:
			var nt: float = float(_crush_next.get(id, 0.0)) - dt
			_crush_next[id] = nt
			var k := d + (0.0 if b.alive else HOLE_R * 2.0)
			if nt <= 0.0 and k < due_k:
				due = b
				due_k = k
	_hstat.pulled = maxi(int(_hstat.pulled), pulled)
	if due != null and _crush_gap <= 0.0:
		_crush_next[due.get_instance_id()] = CRUSH_T
		var t0 := Time.get_ticks_usec()
		_crush_one(due)
		_crush_gap = maxf(CRUSH_GAP, (Time.get_ticks_usec() - t0) / 1000000.0 / CRUSH_BUDGET)
	# pieces: pulled in (no gravity near it), swallowed at the middle (one a frame)
	var ate := false
	for pc in arena.pieces.list():
		var rb = pc.rb
		if not is_instance_valid(rb) or rb == _held_rb or not (rb as Node3D).visible:
			continue
		var r: RigidBody3D = rb
		var to := c - r.global_position
		var d := to.length()
		if d > HOLE_R:
			if _pulled_rb.has(r.get_instance_id()):
				r.gravity_scale = 1.0
				_pulled_rb.erase(r.get_instance_id())
			continue
		if d <= EAT_R and not ate and crushing and r.visible:
			# swallowed: a few of its cubes burst into the well; the piece hidden and dropped under the floor, where
			# VoxelPieces frees it as fallen out of the arena (it isn't freed under its list's feet)
			ate = true
			spray({"bits": VoxelPieces.cubes_of(pc, 50)}, Vector3.UP, 0.4)
			r.visible = false
			r.freeze = true
			r.global_position = Vector3(r.global_position.x, -10.0, r.global_position.z)
			_pulled_rb.erase(r.get_instance_id())
			_hstat.pieces_eaten = int(_hstat.pieces_eaten) + 1
			continue
		var k := clampf(1.0 - d / HOLE_R, 0.0, 1.0)
		var u := to / maxf(d, 0.001)
		var tang := u.cross(Vector3.UP)
		tang = tang.normalized() * SWIRL * 1.5 if tang.length() > 0.01 else Vector3.ZERO
		var want := u * lerpf(PULL_V * 1.5, PULL_NEAR * 1.4, k * k) * grow + tang
		r.linear_velocity = r.linear_velocity.lerp(want, 1.0 - exp(-dt * 4.0))
		r.angular_velocity = r.angular_velocity.lerp(Vector3(3.0, 5.0, 2.0) * k, 1.0 - exp(-dt * 2.0))
		r.gravity_scale = 0.0
		r.sleeping = false
		_pulled_rb[r.get_instance_id()] = r
		pc.still = 0.0

# one body crushed (crush): its cubes and whatever came off into the hole; one with nothing left is gone
func _crush_one(b: VoxelBody) -> void:
	var t0 := Time.get_ticks_usec()
	var res := crush(b, _hp)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if not res.is_empty():
		var at: Vector3 = res.at
		var u := (_hp - at).normalized() if at.distance_to(_hp) > 0.01 else Vector3.UP
		spray(res, u, 1.6)
		if is_instance_valid(b):
			fling(b, res, u * 2.5, _rand_v(5.0))
		_hstat.crushes = int(_hstat.crushes) + 1
		_hstat.cut = int(_hstat.cut) + int(res.cut)
		if bool(res.killed):
			_hstat.killed = int(_hstat.killed) + 1
		_hstat.crush_ms = snappedf(float(_hstat.crush_ms) + ms, 0.1)
		_hstat.crush_max_ms = maxf(float(_hstat.crush_max_ms), snappedf(ms, 0.01))
		if bool(res.get("shattered", false)):
			sfx("shatter", _hp)
		elif int(res.cut) > 0:
			sfx("crunch", _hp, -9.0, randf_range(0.7, 1.0))
	if is_instance_valid(b) and (res.is_empty() or b.cubes_left() == 0) and not VoxelBody.net_locked:   # (a guest's: the host's goes)
		if res.is_empty():
			spray({"bits": b.cubes(60)}, Vector3.UP, 0.4)       # (only stubs left, nothing to bite: swallowed whole)
		arena.bodies.erase(b)
		_pull_pos.erase(b.get_instance_id())
		b.queue_free()
		_hstat.gone = int(_hstat.gone) + 1

# the ball (growing as it opens, shrinking away as it collapses), its disc turning, the light, the drone, streaks
# drawn in, the view wobbling near it; the burst's flash
func _hole_look(dt: float) -> void:
	if _hs == "open" or _hs == "collapse":
		var s := 1.0
		var ds := 1.0
		var spin := 1.0
		if _hs == "open":
			var k := clampf(_ht / 0.35, 0.0, 1.0)
			s = lerpf(0.35, 1.0, 1.0 + 2.7 * pow(k - 1.0, 3) + 1.7 * pow(k - 1.0, 2))      # out, past, back
			ds = clampf(_ht / 0.6, 0.0, 1.0)
			ds = 1.0 - pow(1.0 - ds, 3)
		else:
			var kc := clampf(_ht / COLLAPSE_T, 0.0, 1.0)
			s = pow(1.0 - kc, 2)
			ds = 1.0 - kc * kc
			spin = 1.0 + 4.0 * kc
		var wob := (1.0 + 0.04 * sin(_clock * 17.0)) * (TD_LOOK if top_down() else 1.0)
		_hole.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * maxf(s * wob, 0.001)), _hp)
		_disc.scale = Vector3.ONE * maxf(ds, 0.001)
		_disc.rotation = Vector3(0.38 + 0.08 * sin(_clock * 0.5), _clock * 0.25, 0.22)
		for i in _rings.size():
			_rings[i].rotation.y -= float(RINGS[i][6]) * spin * dt
		_hole_light.global_position = _hp
		_hole_light.light_energy = (2.6 + 0.9 * sin(_clock * 5.0)) * maxf(s, 0.3) + (4.0 * _ht / COLLAPSE_T if _hs == "collapse" else 0.0)
		if _hs == "open":
			arena.sound.loop(_hole_key(), "gravity_hole_loop", _hole, 2.0 + 2.0 * sin(_clock * 1.3), 1.0)
			# streaks drawn in from all round
			_stream_t += dt * 70.0
			while _stream_t >= 1.0:
				_stream_t -= 1.0
				var u := _rand_v(1.0).normalized()
				var p := _hp + u * randf_range(2.0, 4.0)
				_spark(p, u.cross(Vector3.UP).normalized() * randf_range(1.5, 3.0), PURPLE.lerp(Color(1, 0.8, 1), randf() * 0.6), 1.6, randf_range(0.015, 0.03), true)
		# the view wobbles near it
		var near_k := clampf(1.0 - eye().distance_to(_hp) / 9.0, 0.0, 1.0) * s
		if near_k > 0.0:
			shooter.kick = maxf(float(shooter.kick), near_k * (0.25 + 0.2 * sin(_clock * 23.0)))
			if not top_down():
				shooter.cam.rotation.z += near_k * 0.025 * sin(_clock * 6.3)
	elif _hs == "fly":
		_hole_light.global_position = _hst.p
		_hole_light.light_energy = 1.2
	else:
		_hole_light.light_energy = 0.0
	# the burst's flash: a sphere of light swelling and fading, the light flaring
	if _flash.visible:
		_burst_t += dt
		var kb := clampf(_burst_t / BURST_T, 0.0, 1.0)
		_flash.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.2 + 3.6 * (1.0 - pow(1.0 - kb, 3)))), _hp)
		var c := Color(0.85, 0.65, 1.0).lerp(PURPLE, kb)
		_flash_m.albedo_color = Color(c.r, c.g, c.b, 0.85 * (1.0 - kb))
		_hole_light.global_position = _hp
		_hole_light.light_energy = 14.0 * (1.0 - kb)
		if kb >= 1.0:
			_flash.visible = false
			_hole_light.light_energy = 0.0
			_hp = Vector3.INF

# ---------------------------------------------------------------- sparks

func _rand_v(s: float) -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s

func _spark(p: Vector3, v: Vector3, col: Color, life: float, size: float, pulled: bool = false) -> void:
	var i := _spn
	if _spn >= SPARKS:
		i = randi() % SPARKS
	else:
		_spn += 1
	_spp[i] = p
	_spv[i] = v
	_spl[i] = life
	_spl0[i] = life
	_spc[i] = col
	_sps[i] = size
	_spw[i] = 1 if pulled else 0

func _sparks_step(dt: float) -> void:
	var mm := _sp.multimesh
	var hole_on := _hs == "open" or _hs == "collapse"
	var i := 0
	while i < _spn:
		_spl[i] -= dt
		var p := _spp[i]
		var v := _spv[i]
		var to := _hp - p if hole_on else Vector3.ZERO
		if _spl[i] <= 0.0 or (hole_on and _spw[i] == 1 and to.length() < HOLE_BALL * 0.9):
			_spn -= 1
			_spp[i] = _spp[_spn]
			_spv[i] = _spv[_spn]
			_spl[i] = _spl[_spn]
			_spl0[i] = _spl0[_spn]
			_spc[i] = _spc[_spn]
			_sps[i] = _sps[_spn]
			_spw[i] = _spw[_spn]
			continue
		if _spw[i] == 1 and hole_on:
			var d := maxf(to.length(), 0.3)
			v += to / d * (26.0 / d) * dt
			v *= exp(-dt * 0.6)
		else:
			v *= exp(-dt * 3.5)
			v.y -= 1.5 * dt
		p += v * dt
		_spp[i] = p
		_spv[i] = v
		var k := _spl[i] / _spl0[i]
		var s := _sps[i] * (0.35 + 0.65 * k)
		var stretch := 1.0 + minf(v.length() * 0.12, 3.0)
		var bs := Basis.looking_at(v, Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.RIGHT) if v.length() > 0.05 else Basis.IDENTITY
		mm.set_instance_transform(i, Transform3D(bs.scaled(Vector3(s, s, s * stretch)), p))
		var c := _spc[i]
		mm.set_instance_color(i, Color(c.r, c.g, c.b, minf(1.0, k * 1.5)))
		i += 1
	mm.visible_instance_count = _spn

# ---------------------------------------------------------------- the look of the gun

# where the beam and the puffs come from: the middle of the prongs (top-down: of Jared's gun)
func _mouth_world() -> Vector3:
	if top_down():
		var hm = _hand_parts.get("mouth")
		if hm != null and is_instance_valid(hm) and (hm as Node3D).is_inside_tree():
			return (hm as Node3D).global_position
		return eye() + look() * 0.7
	return (_parts.mouth as Node3D).global_position

# the core pulsing (faster and brighter holding, punching on a launch, purple after a black hole), the prongs
# opening, the light
func _pose_parts(pp: Dictionary) -> void:
	var pulse := 0.5 + 0.5 * sin(_clock * lerpf(5.0, 13.0, _hold_k))
	var core: MeshInstance3D = pp.core
	core.scale = Vector3.ONE * (1.0 + (0.08 + 0.18 * _hold_k) * pulse + 0.8 * _punch)
	(pp.hot as MeshInstance3D).scale = Vector3.ONE * (0.7 + 0.5 * _hold_k * pulse + 0.9 * _punch)
	var ang := lerpf(-0.06, 0.62, _prong_k) + 0.02 * sin(_clock * 31.0) * _hold_k
	for pr in pp.prongs:
		(pr[0] as Node3D).basis = (pr[1] as Basis) * Basis(Vector3.RIGHT, -ang)

func _pose_view() -> void:
	var pulse := 0.5 + 0.5 * sin(_clock * lerpf(5.0, 13.0, _hold_k))
	var col := ORANGE.lerp(PURPLE, _purple)
	_core_m.albedo_color = col
	_core_m.emission = col
	_core_m.emission_energy_multiplier = (2.0 + 4.0 * _hold_k) * (0.7 + 0.3 * pulse) + 14.0 * _punch
	_light.light_color = col
	_light.light_energy = (0.25 + 1.4 * _hold_k) * (0.75 + 0.25 * pulse) + 3.0 * _punch
	# (only while it's out: in the view, or in Jared's hands top-down)
	_light.visible = view.visible or (_hand != null and is_instance_valid(_hand) and _hand.is_visible_in_tree())
	_light.global_position = _mouth_world()
	_light.omni_range = 3.2 if top_down() else 2.6
	if top_down():
		return
	_pose_parts(_parts)
	var x := _aim(REST, AIM_AT)
	var o := x.origin + Vector3(sin(_clock * 1.4) * 0.003, sin(_clock * 2.8) * 0.004, 0.0)
	o += Vector3(-0.012, 0.03, 0.02) * _hold_k                       # holding: up a little, drawn in, straining
	if _hold_k > 0.01:
		o += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.0012 * _hold_k
	o += Vector3(0.0, 0.025, 0.11) * _recoil
	_gun.transform = Transform3D(x.basis * Basis(Vector3.RIGHT, 0.3 * _recoil + 0.06 * _hold_k), o)

# top-down: Jared's gun, its prongs and core as in the view, jolting back on a launch
func _pose_hand() -> void:
	if _hand == null or not is_instance_valid(_hand) or _hand_parts.is_empty():
		return
	_pose_parts(_hand_parts)
	_hand.position = Vector3(0, 0, -0.1 * _recoil)

# the beam: crackling strands from the prongs to what's held, jumping about every frame, ribbons facing the camera
func _draw_beam() -> void:
	var im: ImmediateMesh = _beam.mesh
	im.clear_surfaces()
	if not _holding():
		return
	var a := _mouth_world()
	var b := _held_mid()
	var ab := b - a
	var l := ab.length()
	if l < 0.05:
		return
	var cp: Vector3 = shooter.cam.global_position
	var u := ab.cross(cp - a).normalized()
	var w := ab.cross(u).normalized()
	var verts := []
	for strand in [[0.018, Color(1.0, 0.55, 0.15, 0.5), 0.07], [0.007, Color(1.0, 0.95, 0.8, 0.9), 0.05], [0.005, Color(1.0, 0.75, 0.4, 0.6), 0.11]]:
		var n := 12
		var pts := []
		for i in n + 1:
			var k := float(i) / n
			var amp := float(strand[2]) * sin(k * PI) * minf(1.0, l / 1.5)
			pts.append(a + ab * k + (u * randf_range(-1, 1) + w * randf_range(-1, 1)) * amp)
		var hw: float = float(strand[0]) * (TD_LOOK * 1.8 if top_down() else 1.0)
		var sc: Color = strand[1]
		var flick := randf_range(0.6, 1.0)
		for i in n:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var side := (p1 - p0).cross(cp - (p0 + p1) * 0.5)
			if side.length_squared() < 0.0000001:
				continue
			side = side.normalized() * hw
			var c := Color(sc.r, sc.g, sc.b, sc.a * flick)
			verts.append_array([p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side, c])
	if verts.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(0, verts.size(), 7):
		im.surface_set_color(verts[j + 6])
		for v in 6:
			im.surface_add_vertex(verts[j + v])
	im.surface_end()

func _exit_tree() -> void:
	_reset_well()
	super._exit_tree()

# ---------------------------------------------------------------- checks

static func _grunt(host: Node, at: Vector3) -> VoxelBody:
	var b := VoxelBody.new()
	host.add_child(b)
	b.setup("grunt", 0.023, 1, StandardMaterial3D.new())
	b.position = at
	b.animate(0.0, false)
	return b

## A grunt at the origin facing +z (chest at about y 1.0, head 1.43-1.8): the aim picks him, misses beside him, takes
## a piece in front of him first, not one out of reach; held, he flies to the hold point and hangs there off his feet,
## carried; thrown, he flies; a launched piece dents him, hurts him and knocks him flying; the black hole stops in
## front of a body, opens up off the floor, stops after its flight; the pull drags a body in faster the nearer; the
## crush takes cubes where he's nearest and kills in the end; six crushed in a round (the cost); the burst throws
## them out and up.
static func checks(host: Node) -> Array:
	var out := []
	var imm := VoxelBody.immortal
	VoxelBody.immortal = false
	var made := []
	var none: Array[RID] = []
	var down := Vector3(0, 0, -1)
	# the pick
	var b := _grunt(host, Vector3.ZERO)
	made.append(b)
	var h := pick([b], [], Vector3(0, 1.0, 5.0), down, REACH)
	out.append([not h.is_empty() and h.kind == "body" and h.body == b and float(h.dist) > 4.4 and float(h.dist) < 5.0,
		"the aim at a grunt's chest picks him (%.2f m)" % float(h.get("dist", -1.0))])
	h = pick([b], [], Vector3(1.2, 1.0, 5.0), down, REACH)
	out.append([h.is_empty(), "a metre beside him picks nothing"])
	var piece := Node3D.new()
	host.add_child(piece)
	made.append(piece)
	piece.position = Vector3(0.35, 1.2, 2.5)
	h = pick([b], [{"rb": piece}], Vector3(0, 1.0, 5.0), down, REACH)
	out.append([not h.is_empty() and h.kind == "piece" and h.rb == piece, "a piece in front of him (0.4 m off the line) is taken first"])
	h = pick([b], [{"rb": piece}], Vector3(0, 1.0, 20.0), down, REACH)
	out.append([h.is_empty(), "both further than %.0f m: nothing" % REACH])
	# held: to the hold point, off his feet, carried
	var to := Vector3(0.0, 1.5, 2.2)
	var vel := Vector3.ZERO
	carry(b)
	var max_v := 0.0
	for i in 60:
		vel = hold_body(b, to, vel, 1.0 / 60.0)
		max_v = maxf(max_v, vel.length())
	var off := middle(b).distance_to(to)
	out.append([off < 0.08 and b.position.y > 0.3 and b.airborne and b.stagger > 0.0 and b.knock == Vector3.ZERO,
		"held, he's at the hold point in a second (%.2f m off), off his feet (%.2f m up), not walking" % [off, b.position.y]])
	out.append([max_v <= MAX_PULL + 0.01, "no faster than %.0f m/s on the way (%.1f)" % [MAX_PULL, max_v]])
	throw_body(b, down)
	out.append([b.airborne and b.air_v.dot(down) > BODY_V * 0.95 and b.air_v.y > 1.0 and b.tumble_v == BODY_SPIN,
		"thrown, he flies off along the aim at %.0f m/s, up a little, turning over" % b.air_v.length()])
	# a frozen one thrown flies whole, a statue (it shatters as it comes down)
	var bz := _grunt(host, Vector3(-3, 0, 0))
	made.append(bz)
	bz.chill(1.0)
	throw_body(bz, down)
	out.append([bz.frozen() and bz.airborne and bz.cubes_left() > 1000 and bz.air_v.z < -BODY_V * 0.9,
		"a frozen one thrown flies whole, a statue (%d cubes)" % bz.cubes_left()])
	# a lying corpse picked up: its middle stays put
	var bl := _grunt(host, Vector3(3, 0, 0))
	made.append(bl)
	bl.hurt(200.0)
	var m0 := middle(bl)
	carry(bl)
	out.append([middle(bl).distance_to(m0) < 0.02 and is_equal_approx(bl.tumble, PI / 2.0),
		"a corpse picked up off the floor stays where it lay (%.3f m)" % middle(bl).distance_to(m0)])
	# a launched piece hits a body
	var br := _grunt(host, Vector3(6, 0, 0))
	made.append(br)
	var res := piece_hit(br, Vector3(6, 1.1, 0.4), Vector3(0, 0, -LAUNCH_V))
	out.append([int(res.cut) > 20 and br.hp <= 100.0 - RAM_HURT and br.airborne and br.air_v.z < -5.0,
		"a launched piece dents him (%d cubes), hurts him (hp %.0f) and knocks him flying" % [int(res.cut), br.hp]])
	# the black hole's flight: into a body, at the floor, into the open
	var bh := _grunt(host, Vector3(9, 0, 0))
	made.append(bh)
	var st := {"p": Vector3(9, 1.1, 4.0), "v": down * HOLE_V, "t": 0.0}
	var stopped := false
	for i in 60:
		if hole_fly(st, 1.0 / 60.0, [bh], null, none):
			stopped = true
			break
	var hz: float = (st.p as Vector3).z
	out.append([stopped and float(st.t) < HOLE_FLY and hz > 0.1 and hz < 0.8, "fired at a body it stops just in front of him (z %.2f, %.2f s)" % [hz, float(st.t)]])
	st = {"p": Vector3(9, 1.1, 1.2), "v": down * HOLE_V, "t": 0.0}
	for i in 60:
		if hole_fly(st, 1.0 / 60.0, [bh], null, none):
			break
	out.append([(st.p as Vector3).z < -4.0, "fired at one %.1f m off it slips past him and opens beyond (z %.1f)" % [1.2, (st.p as Vector3).z]])
	st = {"p": Vector3(14, 1.2, 4.0), "v": Vector3(0, -0.6, -1).normalized() * HOLE_V, "t": 0.0}
	for i in 60:
		if hole_fly(st, 1.0 / 60.0, [], null, none):
			break
	out.append([is_equal_approx((st.p as Vector3).y, HOLE_Y) and float(st.t) < HOLE_FLY, "fired at the floor it stops there and opens %.1f m up" % HOLE_Y])
	st = {"p": Vector3(18, 1.5, 4.0), "v": down * HOLE_V, "t": 0.0}
	for i in 120:
		if hole_fly(st, 1.0 / 60.0, [], null, none):
			break
	var flown: float = (st.p as Vector3).distance_to(Vector3(18, 1.5, 4.0))
	out.append([absf(float(st.t) - HOLE_FLY) < 0.02 and absf(flown - HOLE_V * HOLE_FLY) < 0.2,
		"into the open it stops after %.1f s (%.1f m)" % [HOLE_FLY, flown]])
	# the pull: faster the nearer, off the floor
	var bp := _grunt(host, Vector3(-10, 0, 0))
	made.append(bp)
	var c := Vector3(-10, 1.2, -5.0)
	var d0 := pull_body(bp, c, 1.0 / 60.0)
	for i in 14:
		pull_body(bp, c, 1.0 / 60.0)
	var far_v := (d0 - middle(bp).distance_to(c)) * 4.0
	var t_in := 0.25
	var near_v := 0.0
	for i in 600:
		var dd := pull_body(bp, c, 1.0 / 60.0)
		t_in += 1.0 / 60.0
		if dd < 1.6:
			var d1 := pull_body(bp, c, 1.0 / 60.0)
			near_v = (dd - d1) * 60.0
			break
	out.append([far_v > 0.8 and near_v > far_v * 2.0 and bp.airborne and bp.stagger > 0.0,
		"the black hole drags a body in from 5 m, faster the nearer (%.1f m/s, then %.1f), in %.1f s" % [far_v, near_v, t_in]])
	var dmin := INF
	var dmax := 0.0
	for i in 120:
		var dd := pull_body(bp, c, 1.0 / 60.0)
		if i >= 60:
			dmin = minf(dmin, dd)
			dmax = maxf(dmax, dd)
	out.append([dmin > ORBIT - 0.12 and dmax < ORBIT + 0.12, "then he circles it %.2f-%.2f m out (the ball stays in sight)" % [dmin, dmax]])
	# the crush, then crushed till he dies
	var bc := _grunt(host, Vector3(-14, 0, 0))
	made.append(bc)
	var cc := Vector3(-14, 1.0, 0.2)
	var t0 := Time.get_ticks_usec()
	res = crush(bc, cc)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var at: Vector3 = res.get("at", Vector3.INF)
	out.append([int(res.cut) > 20 and not (res.pieces as Array).is_empty() and String(res.part) != "torso" and at.distance_to(cc) < LIMB_REACH,
		"a crush takes the limb nearest the middle off first (%s: %d cubes, %d pieces, %.1f ms)" % [String(res.part), int(res.cut), (res.pieces as Array).size(), ms]])
	var n := 1
	var off_parts := []
	for pc in res.pieces:
		off_parts.append(String(pc.part))
	var trunk_ms := 0.0
	var limb_ms := ms
	while bc.cubes_left() > 0 and n < 80:
		var tc := Time.get_ticks_usec()
		res = crush(bc, cc)
		var cms := (Time.get_ticks_usec() - tc) / 1000.0
		if res.is_empty():
			break
		if String(res.part) == "torso":
			trunk_ms = maxf(trunk_ms, cms)
		else:
			limb_ms = maxf(limb_ms, cms)
		for pc in res.pieces:
			if not off_parts.has(String(pc.part)):
				off_parts.append(String(pc.part))
		n += 1
		if not bc.alive:
			break
	out.append([not bc.alive and off_parts.size() >= 2 and n < 40,
		"crushed again and again: limbs off (%s), the head chewed, dead in %d crushes (a limb or the head %.1f ms at most, the trunk %.1f)" % [", ".join(off_parts), n, limb_ms, trunk_ms]])
	# six bodies in it: a crush each (the cost of a round)
	var six := []
	for i in 6:
		var a := TAU * i / 6.0
		six.append(_grunt(host, Vector3(-18 + cos(a) * 0.5, 0, 8.0 + sin(a) * 0.5)))
	made.append_array(six)
	var c6 := Vector3(-18, 1.0, 8.0)
	var worst := 0.0
	t0 = Time.get_ticks_usec()
	var cut6 := 0
	for x in six:
		var t1 := Time.get_ticks_usec()
		cut6 += int(crush(x, c6).get("cut", 0))
		worst = maxf(worst, (Time.get_ticks_usec() - t1) / 1000.0)
	ms = (Time.get_ticks_usec() - t0) / 1000.0
	out.append([cut6 > 200 and worst < 25.0, "six bodies crushed once each: %.1f ms in all, %.1f ms the worst (%d cubes)" % [ms, worst, cut6]])
	# the burst
	var bf := _grunt(host, Vector3(12, 0, 8))
	made.append(bf)
	fling_out(bf, Vector3(10.5, 1.2, 8))
	out.append([bf.airborne and bf.air_v.x > 2.0 and bf.air_v.y > 2.5, "the burst throws a body out and up (%s)" % str(bf.air_v.snapped(Vector3.ONE * 0.1))])
	for x in made:
		(x as Node).queue_free()
	VoxelBody.immortal = imm
	return out
