class_name VoxelWeaponLaser
extends VoxelMelee
## The laser cutter (the owner, 20 Oct: six new weapons, each doing something different). A slim dark industrial
## cutting tool held at the hip: a red lens on the emitter out in front, cooling fins behind it, and a heat strip down
## each side that glows from dull red to bright orange as it heats. Hold left and a thin bright red beam runs from the lens
## to the first thing it meets, with a white-hot spot, orange sparks and wisps of smoke there. Where the beam goes into
## a body it cuts right through along its line: the beam's line inside the body (from where it goes in to where it
## comes out, 0.7 m at most: VoxelBody.carve with a 2 cm capsule) is cut out, so dragging the mouse sweeps the line
## across them like a sheet and cuts a clean plane: arms, legs, heads and whole bodies come apart where you drag it
## (carve takes off whatever the cut leaves hanging; through the neck the head comes off). Every frame's beam counts:
## fifteen times a second the lines since the last time are lined up, filled in where a fast drag left them far apart
## and thinned where they're close, and cut one a frame on a budget, so the cut has no holes. Held still in a body the
## hole is bored wider, round and round (the beam stays in its own hole). The cut is
## cauterised: only a few bits fly, glowing orange-hot. Five seconds of beam overheats it: it shuts off and vents
## steam for two seconds; it cools when it isn't firing (the weapon bar shows the heat; R vents it early). Hold right
## to overcharge: a rising whine for 0.6 s, the lens growing brighter, the tool trembling; then a fat beam fires for
## as long as you hold it (1.5 s at most) and goes through every body in line to the wall, boring a fat tunnel through
## each, with a big kick, scorch sparks on the wall and a lot of heat. Let go before it's charged and it fizzles out.
## Top-down it's in Jared's hands and the beam goes level from his chest toward the mouse. The core (which body the
## beam meets first, the cut lines between two frames' beams, a cut, the fat tunnel, the heat) is static so the logic
## test can run it. Owned by the voxel session.

const RANGE := 60.0             # metres the beam reaches at most (the arena is 44 across)
const CUT_R := 0.022            # the cut line's radius, metres
const CUT_DEPTH := 0.7          # metres past where the beam goes in that it cuts (or less: to where it comes out)
const CUT_PRE := 0.04           # ... and before it (the surface is never quite where the trace said)
const CUT_POST := 0.03          # ... and past where it comes out
const CUT_TICK := 1.0 / 15.0    # seconds between cuts: the beam's lines since the last one lined up to be cut ...
const CUT_SHARE := 0.25         # ... one a frame at most, spaced so cutting takes about this share of the time ...
const SHARE_MAX := 0.6          # ... more with lines waiting (a fast drag: one body crossed is 40-60), up to this
const MAX_PENDING := 96         # lines waiting at most for each body in them (more: an even spread, the newest kept)
const SPACING := 0.035          # metres apart neighbouring cut lines may be at either end (2.2 cm lines: no gaps)
const FILL_MAX := 4             # lines filled in between two frames' beams at most
const NECK_D := 0.05            # a cut line this near the head's joint is through the middle of the neck
const HP_PER_CUBE := 0.1        # health each body cube cut out costs (carve's own)
const BITS_EVERY := 3           # one flying bit for every this many cubes cut (it's cauterised) ...
const HOT_BITS := 3             # ... and this many a cut at most
const HEAT_HURT := 10.0         # health a second the beam burns off whoever it's in
const DWELL_GROW := 0.03        # held still in a body: metres a second the hole is bored wider ...
const DWELL_MAX := 0.035        # ... up to this round the beam
const TRACE_MAX := 16           # bodies traced a frame at most to find the first one the beam meets (a miss is cheap: a
                                # crowd beside the beam mustn't hide the one in it)
const HEAT_BEAM := 0.2          # heat a second the beam adds (five seconds overheats it)
const HEAT_CHARGE := 0.12
const HEAT_BLAST := 0.45
const COOL := 0.3               # heat a second lost resting ...
const COOL_WAIT := 0.4          # ... once it has rested this long
const VENT_T := 2.0             # overheated: seconds it vents steam, shut off,
const VENT_TO := 0.45           # ... and the heat left after
const VENT_R_T := 1.0           # R: seconds a vent by hand takes (down to cold)
const CHARGE_T := 0.6           # seconds the overcharge takes to fill
const BLAST_MAX := 1.5          # seconds the fat beam lasts at most
const BLAST_R := 0.09           # the fat tunnel's radius, metres
const BLAST_HALF := 0.75        # metres either side of where the fat beam passes a standing body's middle it bores
const BLAST_TICK := 0.1         # seconds between fat tunnels ...
const BLAST_SHARE := 0.4        # ... or more: one a frame at most, spaced so boring takes about this share of the time
const BLAST_HP := 0.08
const BLAST_BODIES := 6         # bodies one fat tunnel goes through at most
const BLAST_BITS := 50
const BLAST_BITS_HOT := 0.45    # the share of them glowing hot (the rest blown out as they were)
const MAX_PUFFS := 320          # smoke and steam puffs at once
# poses in camera space (x right, y up, -z forward): where the grip is (high enough that the power cell and the heat
# strip show above the weapon bar)
const REST := Vector3(0.23, -0.225, -0.42)
const FIRE_AT := Vector3(0.21, -0.205, -0.45)
const CHARGE_AT := Vector3(0.17, -0.185, -0.4)
const VENT_AT := Vector3(0.26, -0.255, -0.37)
const AIM_D := 6.0              # at rest it points at the crosshair this far out
const ROLL := 0.18              # radians it's canted over (its inner side and top toward you)
const VIEW_SCALE := 0.9
const STICK_R := 0.05           # metres from where the beam last met a body that it still counts as in it (in its own cut)
# the tool, weapon space (the grip at the origin, the emitter along +z, its top +y)
const LENS := Vector3(0, 0.03, 0.384)
const FINS := Vector3(0, 0.07, 0.14)

const RED := Color(1.0, 0.16, 0.08)
const HOT := [Color(1.0, 0.92, 0.55), Color(1.0, 0.6, 0.12), Color(1.0, 0.42, 0.06), Color(0.95, 0.25, 0.04)]
const STRIP_COLD := Color(0.24, 0.06, 0.03)
const STRIP_HOT := Color(1.0, 0.48, 0.07)

var _tool: Node3D               # first person: the tool (posed under view; the model inside it faces -z)
var _view_parts := {}           # its lens, strip, glow ... (see _model)
var _hand_parts := {}           # top-down: the same in Jared's hands (the arena frees it on a switch)
var _hand: Node3D
var _beam: Node3D               # the beam in the world: the core, its halo, a wider glow, the hot spot
var _core: MeshInstance3D       # (soft-edged tubes: _beam_mat)
var _halo: MeshInstance3D
var _outer: MeshInstance3D
var _spot: MeshInstance3D
var _m_core: ShaderMaterial
var _m_halo: ShaderMaterial
var _m_outer: ShaderMaterial
var _stick_b: VoxelBody         # the body the beam last met, and where (it may be in its own cut now)
var _stick_at := Vector3.ZERO
var _m_glow: StandardMaterial3D
var _spot_light: OmniLight3D
var _lens_light: OmniLight3D
var _puffs: MultiMeshInstance3D # smoke off the cut, steam off the fins
var _pp := PackedVector3Array()
var _pv := PackedVector3Array()
var _pl := PackedFloat32Array()  # life left, life it started with, size from, size to
var _ps := PackedFloat32Array()
var _pa := PackedFloat32Array()
var _pb := PackedFloat32Array()
var _pc := PackedColorArray()
var _pn := 0
var _firing := false            # left held (the beam wanted)
var _on := false                # the beam on now
var _charging := false
var _charge := 0.0              # seconds charged
var _blast_t := -1.0            # seconds into the fat beam (-1: none)
var _btick := 0.0
var _queue := []                # fat beam: [body, a, z, dir] still to bore, one a frame at most ...
var _bwait := 0.0               # ... seconds till the next may be
var _blasted := {}              # bodies the fat beam has been in (a hit-stop the first time)
var _heat := 0.0                # 0 cold .. 1 overheated
var _vent_t := 0.0              # seconds of venting left
var _vent_total := 1.0
var _vent_from := 1.0
var _vent_to := 0.0
var _rest_t := 0.0              # seconds since it last fired or charged
var _tick := 0.0                # seconds to the next cut
var _samples := []              # every frame's beam since the last cut: {from, dir, body, d, x} (lines_between)
var _prev := {}                 # the last one cut from
var _kept := {}                 # body id -> the last line kept to cut into it
var _carry := []                # lines held back at the last cut (the next frames' may do instead)
var _pending := []              # lines waiting to be cut: [body, a, z]
var _cut_wait := 0.0            # seconds till the next may be cut
var _dwell := 0.0               # seconds held still in a body
var _hit_b: VoxelBody           # the body the beam is in now (or null)
var _end := Vector3.ZERO        # where the beam ends (world) ...
var _end_n := Vector3.UP        # ... and the surface's normal there
var _in_body := 0.0             # seconds the beam still counts as in a body (the sizzle)
var _smoke_t := 0.0
var _kickback := 0.0            # the fat beam's recoil, 1 to 0
var _k_fire := 0.0              # eased poses, 0..1: firing, charging, venting
var _k_charge := 0.0
var _k_vent := 0.0
var _t := 0.0
var _stop_ms := 0
var _move_t := 0.0
var _trace_n := 0
var _trace_ms := 0.0

func _build() -> void:
	_tool = Node3D.new()
	_tool.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF    # (posed every frame, under the camera)
	view.add_child(_tool)
	var inner := Node3D.new()
	inner.rotation = Vector3(0, PI, 0)          # the model's emitter (+z) down the view (-z)
	inner.scale = Vector3.ONE * VIEW_SCALE
	_tool.add_child(inner)
	_m_glow = _fx_mat(Color(1.0, 0.35, 0.25, 0.8))
	_view_parts = _model(inner, false)
	_tool.transform = _aim_xf(REST, Vector3(0, 0, -AIM_D))
	# the beam: a thin glowing core, a soft halo round it, a wider glow (the fat beam), a white-hot spot where it ends
	_beam = Node3D.new()
	_beam.top_level = true
	add_child(_beam)
	_m_core = _beam_mat()
	_m_halo = _beam_mat()
	_m_outer = _beam_mat()
	_core = _tube(_beam, _m_core)
	_halo = _tube(_beam, _m_halo)
	_outer = _tube(_beam, _m_outer)
	_spot = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	_spot.mesh = sm
	_spot.material_override = _fx_mat(Color(1.0, 0.85, 0.6, 0.95))
	_spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(_spot)
	_beam.visible = false
	_spot_light = OmniLight3D.new()
	_spot_light.light_color = Color(1.0, 0.35, 0.15)
	_spot_light.omni_range = 1.6
	_spot_light.visible = false
	_spot_light.top_level = true
	add_child(_spot_light)
	_lens_light = OmniLight3D.new()
	_lens_light.light_color = Color(1.0, 0.2, 0.1)
	_lens_light.omni_range = 1.2
	_lens_light.visible = false
	_lens_light.top_level = true
	add_child(_lens_light)
	# smoke and steam: one draw call
	_puffs = MultiMeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3.ONE
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.material = pmat
	_puffs.multimesh = MultiMesh.new()
	_puffs.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_puffs.multimesh.use_colors = true
	_puffs.multimesh.mesh = pm
	_puffs.multimesh.instance_count = MAX_PUFFS
	_puffs.multimesh.visible_instance_count = 0
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puffs.top_level = true
	add_child(_puffs)
	_pp.resize(MAX_PUFFS)
	_pv.resize(MAX_PUFFS)
	_pl.resize(MAX_PUFFS)
	_ps.resize(MAX_PUFFS)
	_pa.resize(MAX_PUFFS)
	_pb.resize(MAX_PUFFS)
	_pc.resize(MAX_PUFFS)

# a glowing see-through material (added on): the hot spot, the lens's charge glow
static func _fx_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m

# a beam layer's material: glowing, added on, fading out to its edges (brightest where you look straight through it);
# col, energy (above 1 blooms) and soft (how quickly it fades to the edge) set per layer
static var _beam_shader: Shader
static func _beam_mat() -> ShaderMaterial:
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.2, 0.1, 0.5);
uniform float energy = 1.0;
uniform float soft = 1.0;
void fragment() {
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = col.rgb * energy;
	ALPHA = col.a * pow(f, soft);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _beam_shader
	return m

static func _set_layer(m: ShaderMaterial, col: Color, energy: float, soft: float) -> void:
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("soft", soft)

# an open tube one metre long and across, along its y (stretched from end to end by _stretch)
static func _tube(parent: Node3D, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 1.0
	cm.radial_segments = 10
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# the tool, weapon space (the grip at the origin, the emitter along +z, its top +y), metres; returns the parts that
# change: {lens_m, strip_m (its heat strips), glow (the charge glow at the lens), lens, fins (points)}. light: brighter,
# for top-down (seen small from up high on a dark floor).
func _model(root: Node3D, light: bool) -> Dictionary:
	var m_body := mat(Color(0.34, 0.35, 0.39) if light else Color(0.12, 0.125, 0.14), 0.55, 0.45)
	var m_dark := mat(Color(0.17, 0.17, 0.19) if light else Color(0.05, 0.05, 0.06), 0.3, 0.7)
	var m_fin := mat(Color(0.62, 0.64, 0.68) if light else Color(0.42, 0.44, 0.48), 0.85, 0.3)
	var m_haz := mat(Color(0.95, 0.72, 0.08), 0.0, 0.6)
	var m_lens := mat(RED, 0.0, 0.3, 2.5)
	var m_strip := mat(STRIP_COLD, 0.0, 0.5, 0.3)
	# the grip (raked back), the trigger and its guard
	box(root, Vector3(0.03, 0.095, 0.04), Vector3(0, -0.048, -0.012), m_dark, Vector3(-0.3, 0, 0))
	box(root, Vector3(0.008, 0.02, 0.012), Vector3(0, -0.012, 0.028), m_fin)
	box(root, Vector3(0.018, 0.006, 0.046), Vector3(0, -0.03, 0.028), m_dark)
	# the housing: slim, a rail along the top
	box(root, Vector3(0.048, 0.056, 0.26), Vector3(0, 0.03, 0.07), m_body)
	box(root, Vector3(0.016, 0.01, 0.17), Vector3(0, 0.063, 0.04), m_dark)
	# the power cell at the back, a hazard band round it, a little green ready light
	box(root, Vector3(0.054, 0.062, 0.065), Vector3(0, 0.03, -0.09), m_dark)
	box(root, Vector3(0.056, 0.064, 0.01), Vector3(0, 0.03, -0.066), m_haz)
	box(root, Vector3(0.01, 0.006, 0.01), Vector3(0.015, 0.064, -0.1), mat(Color(0.2, 1.0, 0.3), 0.0, 0.5, 2.0))
	# the front grip under it
	box(root, Vector3(0.024, 0.065, 0.028), Vector3(0, -0.03, 0.15), m_dark, Vector3(0.15, 0, 0))
	# the cooling fins round the front of the housing
	for i in 5:
		box(root, Vector3(0.074, 0.074, 0.006), Vector3(0, 0.03, 0.1 + 0.02 * i), m_fin)
	# the heat strips down both sides (and along the top, for top-down)
	for sx in [1.0, -1.0]:
		box(root, Vector3(0.004, 0.012, 0.14), Vector3(0.0255 * sx, 0.036, 0.02), m_strip)
	if light:
		box(root, Vector3(0.012, 0.004, 0.14), Vector3(0, 0.0705, 0.02), m_strip)
	# the emitter out in front: the barrel, the collar, a red glowing ring and the lens
	box(root, Vector3(0.03, 0.03, 0.16), Vector3(0, 0.03, 0.27), m_dark)
	box(root, Vector3(0.046, 0.046, 0.03), Vector3(0, 0.03, 0.355), m_fin)
	box(root, Vector3(0.05, 0.05, 0.008), Vector3(0, 0.03, 0.372), m_lens)
	var lens := box(root, Vector3(0.028, 0.028, 0.006), Vector3(0, 0.03, 0.378), m_lens)
	var glow := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.5
	gm.height = 1.0
	gm.radial_segments = 12
	gm.rings = 6
	glow.mesh = gm
	glow.material_override = _m_glow
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position = LENS + Vector3(0, 0, 0.015)
	glow.visible = false
	root.add_child(glow)
	var lens_pt := Node3D.new()
	lens_pt.position = LENS
	root.add_child(lens_pt)
	var fins_pt := Node3D.new()
	fins_pt.position = FINS
	root.add_child(fins_pt)
	return {"lens_m": m_lens, "strip_m": m_strip, "glow": glow, "lens_mi": lens, "lens": lens_pt, "fins": fins_pt}

# a pose: the grip at grip, pointing at at (both camera space)
static func _aim_xf(grip: Vector3, at: Vector3, roll: float = ROLL) -> Transform3D:
	var d := at - grip
	if d.length() < 0.05:
		d = Vector3.FORWARD
	return Transform3D(Basis.looking_at(d, Vector3.UP) * Basis(Vector3.BACK, roll), grip)

func hand_mesh() -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_hand = Node3D.new()            # shaken (the arena sets root's own transform)
	root.add_child(_hand)
	var inner := Node3D.new()
	inner.scale = Vector3.ONE * 1.3
	inner.position = Vector3(0, 0, -0.03)
	_hand.add_child(inner)
	_hand_parts = _model(inner, true)
	return root

func hand_pose() -> String:
	return "shotgun"                # at the hip, both hands on it

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var dim := Color(col.r * 0.4, col.g * 0.4, col.b * 0.45, col.a)
	var heat := Color(STRIP_COLD.lerp(STRIP_HOT, _heat), col.a)
	var rects := [[Rect2(0.6, 1.4, 6.6, 1.4), col], [Rect2(0.2, 1.2, 1.3, 1.8), dim], [Rect2(1.9, 2.8, 0.9, 1.7), dim],
		[Rect2(4.2, 2.8, 0.6, 1.1), dim], [Rect2(7.2, 1.8, 1.6, 0.6), dim], [Rect2(2.0, 1.9, 3.6, 0.35), heat],
		[Rect2(8.8, 1.75, 0.55, 0.7), Color(RED, col.a)]]
	for i in 5:
		rects.append([Rect2(5.6 + i * 0.36, 1.0, 0.16, 2.2), dim])
	for b in rects:
		var rr: Rect2 = b[0]
		ci.draw_rect(Rect2(r.position + rr.position * u, rr.size * u), b[1])

# ---------------------------------------------------------------- the buttons

func cooling() -> float:
	return _heat

func bar_text() -> String:
	return "%d%%" % roundi(_heat * 100.0)

## R: vents the heat now (a second, down to cold), if it's warm and not firing.
func reload_key() -> void:
	if _heat > 0.2 and _vent_t <= 0.0 and not _on and not _charging and _blast_t < 0.0:
		_vent(true)

func press(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		if _charging or _blast_t >= 0.0:
			return                      # the right button's going
		if _vent_t > 0.0:
			sfx("dry_fire")
			return
		_firing = true
		_begin("beam")
	elif button == MOUSE_BUTTON_RIGHT:
		if _firing or _blast_t >= 0.0:
			return
		if _vent_t > 0.0:
			sfx("dry_fire")
			return
		_charging = true
		_charge = 0.0
		_begin("overcharge")
		sfx("laser_charge", Vector3.INF, -2.0)

func release(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_firing = false
	elif button == MOUSE_BUTTON_RIGHT:
		if _charging:
			# let go before it filled: it fizzles out, nothing fired
			_charging = false
			last.fizzled = true
			sfx("laser_fizzle")
		elif _blast_t >= 0.0:
			_end_blast()

func on_select() -> void:
	_k_fire = 0.0
	_k_charge = 0.0

func on_deselect() -> void:
	_firing = false
	_charging = false
	if _blast_t >= 0.0:
		_end_blast()
	_set_on(false)
	for tag in ["beam", "sizzle", "blast"]:
		sfx_stop(tag)
	_beam.visible = false
	_spot_light.visible = false
	_lens_light.visible = false

# a new move: fresh numbers in last
func _begin(move: String) -> void:
	_move_t = 0.0
	_trace_n = 0
	_trace_ms = 0.0
	last = {"move": move, "lines": 0, "cut": 0, "parts": [], "pieces": 0, "killed": false, "head_off": false, "ms": 0.0,
		"max_ms": 0.0, "per_s": 0.0, "trace_ms": 0.0, "bodies": 0, "heat": 0, "overheated": false}

# ---------------------------------------------------------------- every frame

func step(dt: float) -> void:
	_t += dt
	_kickback = maxf(0.0, _kickback - dt * 5.0)
	_in_body = maxf(0.0, _in_body - dt)
	var busy_now := false
	if _vent_t > 0.0:
		_vent_t = maxf(0.0, _vent_t - dt)
		_heat = lerpf(_vent_to, _vent_from, _vent_t / _vent_total)
		if _visible_tool():
			_steam()
	if _charging:
		busy_now = true
		_charge += dt
		_heat = heat_step(_heat, dt, HEAT_CHARGE)
		if _charge >= CHARGE_T:
			_charging = false
			_start_blast()
	if _blast_t >= 0.0:
		busy_now = true
		_blast_t += dt
		_heat = heat_step(_heat, dt, HEAT_BLAST)
		if _blast_t >= BLAST_MAX:
			_end_blast()
	_set_on(_firing and _vent_t <= 0.0 and not _charging and _blast_t < 0.0)
	if _on:
		busy_now = true
		_heat = heat_step(_heat, dt, HEAT_BEAM)
	if _heat >= 1.0 and _vent_t <= 0.0:
		_vent(false)
	if busy_now:
		_rest_t = 0.0
		_move_t += dt
		if not last.is_empty():
			last.heat = roundi(_heat * 100.0)
	else:
		_rest_t += dt
		if _rest_t > COOL_WAIT and _vent_t <= 0.0:
			_heat = maxf(0.0, _heat - COOL * dt)
	if _on:
		_beam_frame(dt)
	elif _blast_t >= 0.0:
		_blast_frame(dt)
	_cut_wait -= dt
	if not _pending.is_empty() and _cut_wait <= 0.0:
		_cut_next()
		# (a long queue, a sweep across a group: a second one this frame if the first was cheap)
		if _pending.size() > 48 and _cut_wait <= dt * 0.5:
			_cut_next()
	_sounds()
	_draw(dt)
	_puffs_step(dt)
	_look(dt)

# the beam switched on (a zap, a fresh start: nothing cut back to an old beam) or off
func _set_on(on: bool) -> void:
	if on == _on:
		return
	_on = on
	if not on:
		# off: the frames since the last cut, and where it last was, are cut too
		if not _samples.is_empty():
			_cut_tick()
		_pending.append_array(_carry)
	_carry = []
	_samples.clear()
	_prev = {}
	_kept.clear()
	_dwell = 0.0
	_tick = 0.0
	_hit_b = null
	_stick_b = null
	if on:
		sfx("laser_start", Vector3.INF, -3.0)

func _visible_tool() -> bool:
	return view.visible or (is_instance_valid(_hand) and _hand.is_visible_in_tree())

# overheated (or R): shut off, steam out of the fins, the heat down to _vent_to over the vent
func _vent(by_hand: bool) -> void:
	_vent_t = VENT_R_T if by_hand else VENT_T
	_vent_total = _vent_t
	_vent_from = _heat
	_vent_to = 0.0 if by_hand else VENT_TO
	_charging = false
	if _blast_t >= 0.0:
		_end_blast()
	_set_on(false)
	sfx("laser_overheat", Vector3.INF, -6.0 if by_hand else -1.0)
	if not by_hand and not last.is_empty():
		last.overheated = true

# ---------------------------------------------------------------- the thin beam

# a frame of the beam: where it ends (the first body or the wall), noted for the next cut; it burns whoever it's in
func _beam_frame(dt: float) -> void:
	var from := eye()
	var dir := look()
	var wall := _wall(from, dir)
	var t0 := Time.get_ticks_usec()
	var h := first_hit(arena.bodies, from, dir, float(wall[0]))
	if not h.is_empty():
		_stick_b = h.body
		_stick_at = h.point
	elif is_instance_valid(_stick_b) and _stick_b.cubes_left() > 0:
		# no cube on the line: it may be in its own cut (a hole bored, a slit it's dragging along): still in that body
		var along := (_stick_at - from).dot(dir)
		if along > 0.0 and along < float(wall[0]) and (from + dir * along).distance_to(_stick_at) < STICK_R:
			h = {"body": _stick_b, "dist": along, "point": from + dir * along, "normal": -dir}
	_trace_ms += (Time.get_ticks_usec() - t0) / 1000.0
	_trace_n += 1
	last.trace_ms = snappedf(_trace_ms / _trace_n, 0.01)
	_hit_b = null
	var d := 0.0
	var x := 0.0
	if h.is_empty():
		_end = wall[1]
		_end_n = wall[2]
	else:
		_hit_b = h.body
		d = float(h.dist)
		x = exit_dist(_hit_b, from, dir, d)
		_end = h.point
		_end_n = h.normal
		_in_body = 0.15
		if _hit_b.alive:
			_hit_b.hurt(HEAT_HURT * dt)
	_samples.append({"from": from, "dir": dir, "body": _hit_b, "d": d, "x": x})
	_tick -= dt
	if _tick <= 0.0:
		_cut_tick()
	if not top_down():
		shooter.kick = maxf(float(shooter.kick), randf_range(0.0, 0.05) + (0.06 if is_instance_valid(_hit_b) else 0.0))

# the world along the beam: [distance, point, normal] (walls, pillars, the floor; RANGE if nothing)
func _wall(from: Vector3, dir: Vector3) -> Array:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE, 1, shooter.exclude())
	var wh := get_world_3d().direct_space_state.intersect_ray(q)
	if wh.is_empty():
		return [RANGE, from + dir * RANGE, -dir]
	return [from.distance_to(wh.position), wh.position, wh.normal]

# a cut: the lines since the last one (every frame's beam, filled in where they're far apart), thinned to the ones
# needed, lined up to be cut; held still in a body, one line round the hole instead (bored wider)
func _cut_tick() -> void:
	var lines := _carry
	_carry = []
	for s in _samples:
		lines.append_array(lines_between(_prev, s, FILL_MAX))
		_prev = s
	_samples.clear()
	var keep := thin_lines(lines, _kept, _carry)
	if keep.is_empty() and _pending.is_empty() and is_instance_valid(_hit_b) and _prev.get("body") == _hit_b:
		# held still: the line goes round the hole, a little wider each time
		_dwell += CUT_TICK
		var dir: Vector3 = _prev.dir
		var u := dir.cross(Vector3.UP)
		u = (u if u.length() > 0.01 else dir.cross(Vector3.RIGHT)).normalized()
		var v := u.cross(dir).normalized()
		var ang := _dwell * 9.0
		var off := (u * cos(ang) + v * sin(ang)) * minf(DWELL_MAX, DWELL_GROW * _dwell)
		var from: Vector3 = _prev.from
		keep.append([_hit_b, from + dir * (float(_prev.d) - CUT_PRE) + off, from + dir * (float(_prev.x) + CUT_POST) + off])
	elif not keep.is_empty():
		_dwell = 0.0
	_pending.append_array(keep)
	var in_q := {}
	for ln in _pending:
		in_q[ln[0]] = true
	var cap := MAX_PENDING * clampi(in_q.size(), 1, 4)       # (a sweep across a group: each body its own lines)
	if _pending.size() > cap:
		# falling behind (a very fast drag through a lot): an even spread of them, the newest kept
		var spread := []
		for i in cap:
			spread.append(_pending[int(round(float(i + 1) * _pending.size() / cap)) - 1])
		_pending = spread
	_tick = maxf(0.0, _tick + CUT_TICK)

# the oldest line waiting cut; the next waits so cutting takes CUT_SHARE of the time (more while many wait, so a
# fast drag comes apart soon after the beam has passed)
func _cut_next() -> void:
	var t0 := Time.get_ticks_usec()
	var ln: Array = _pending.pop_front()
	if is_instance_valid(ln[0]):
		_cut_one(ln[0], ln[1], ln[2])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_cut_wait = ms / 1000.0 / minf(SHARE_MAX, CUT_SHARE + 0.01 * _pending.size())
	last.per_s = snappedf(int(last.lines) / maxf(0.1, _move_t), 0.1)

func _cut_one(b: VoxelBody, a: Vector3, z: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	var res := cut_line(b, a, z)
	var res2 := neck_cut(b) if not res.get("shattered", false) and through_neck(b, a, z) else {}
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	last.lines = int(last.lines) + 1
	last.ms = snappedf((float(last.ms) * (int(last.lines) - 1) + ms) / int(last.lines), 0.01)
	last.max_ms = snappedf(maxf(float(last.max_ms), ms), 0.01)
	for rr in [res, res2]:
		if int(rr.get("cut", 0)) > 0 or not (rr.get("pieces", []) as Array).is_empty():
			_cut_fx(b, rr, (z - a).normalized(), false)

# what a cut did: hot bits (a few, or blown out of the far side by the fat beam), pieces off, the body held or shoved,
# a hit-stop when something comes off
func _cut_fx(b: VoxelBody, res: Dictionary, dir: Vector3, fat: bool) -> void:
	var pieces: Array = res.pieces
	last.cut = int(last.cut) + int(res.cut)
	for p in res.parts:
		if not (last.parts as Array).has(p):
			(last.parts as Array).append(p)
	last.pieces = int(last.pieces) + pieces.size()
	last.killed = bool(last.killed) or bool(res.killed)
	last.head_off = bool(last.head_off) or bool(res.head_off)
	if res.get("shattered", false):
		# frozen solid: it bursts into ice
		spray(res, dir, 3.0)
		sfx("shatter", b.global_position + Vector3.UP)
		return
	var hot := hot_bits(res.bits, BLAST_BITS if fat else HOT_BITS, BLAST_BITS_HOT if fat else 1.0)
	if fat:
		spray({"bits": hot}, (dir + Vector3.UP * 0.25).normalized(), 4.5)
	else:
		spray({"bits": hot}, (Vector3.UP - dir * 0.3).normalized(), 1.1)
	for i in mini(3 if fat else 2, hot.size()):
		arena.flames.emit(hot[i].pos, 1, Vector3.ZERO, 1.3, 0.35)
	if not pieces.is_empty():
		# cut clean through: the piece slides off (the fat beam throws it on along the beam)
		var pc: Dictionary = pieces[0]
		var at: Vector3 = (pc.xform as Transform3D) * (pc.box_at as Vector3)
		var away := at - b.global_position
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3(dir.x, 0.0, dir.z)       # (off the top: it slides off down the cut, away from you)
		away = away.normalized()
		var rs := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		if fat:
			fling(b, res, dir * randf_range(3.0, 4.5) + Vector3.UP * randf_range(1.0, 2.0) + away * 0.8, rs * 7.0)
			sfx("crunch", at, -4.0)
		else:
			fling(b, res, away * randf_range(0.4, 0.9) + Vector3.UP * randf_range(0.2, 0.6), rs * 2.0)
			sfx("slice", at, -6.0)
	if b.alive:
		if fat:
			b.hit_react(dir, mini(int(res.cut), 120), String(res.parts[0]) if not (res.parts as Array).is_empty() else "torso")
		else:
			b.stagger = maxf(b.stagger, 0.3)
			b.flinch = maxf(b.flinch, randf_range(0.2, 0.45))
			b.knock = Vector3.ZERO
		b.flinch_head = (res.parts as Array).has("head")
	var now := Time.get_ticks_msec()
	var big := bool(res.killed) or not pieces.is_empty()
	if fat and not _blasted.has(b.get_instance_id()):
		_blasted[b.get_instance_id()] = true
		last.bodies = int(last.bodies) + 1
		sfx("hit_flesh", b.global_position + Vector3.UP, -2.0)
		if now - _stop_ms > 200:
			_stop_ms = now
			hit_stop(0.07, 0.08)
	elif big and now - _stop_ms > 300:
		_stop_ms = now
		hit_stop(0.09 if bool(res.killed) else 0.05, 0.08 if bool(res.killed) else 0.2)
	if not top_down():
		shooter.kick = maxf(float(shooter.kick), 0.7 if big else 0.15)

# ---------------------------------------------------------------- the overcharge

func _start_blast() -> void:
	_blast_t = 0.0
	_btick = 0.0
	_bwait = 0.0
	_queue.clear()
	_blasted.clear()
	_kickback = 1.0
	last.fired = true
	sfx("laser_blast")
	shooter.kick = maxf(float(shooter.kick), 1.8)
	shooter.avatar.recoil = 1.0

func _end_blast() -> void:
	_blast_t = -1.0
	_queue.clear()
	sfx_stop("blast")
	sfx("laser_fizzle", Vector3.INF, -8.0, 0.6)

# a frame of the fat beam: to the wall through everything; a tunnel through each body in line every BLAST_TICK (one
# body bored a frame at most, on a budget: a crowd in line is bored less often)
func _blast_frame(dt: float) -> void:
	var from := eye()
	var dir := look()
	var wall := _wall(from, dir)
	_end = wall[1]
	_end_n = wall[2]
	_hit_b = null
	_btick -= dt
	if _btick <= 0.0 and _queue.is_empty():
		_btick = BLAST_TICK
		var cand := []
		for b in arena.bodies:
			var tb := in_line(b, from, dir, float(wall[0]), BLAST_R + 0.1)
			if tb >= 0.0:
				cand.append([tb, b])
		cand.sort_custom(func(x, y): return x[0] < y[0])
		for i in mini(BLAST_BODIES, cand.size()):
			var b: VoxelBody = cand[i][1]
			var span := blast_span(b, float(cand[i][0]), float(wall[0]))
			_queue.append([b, from + dir * span.x, from + dir * span.y, dir])
	_bwait -= dt
	if not _queue.is_empty() and _bwait <= 0.0:
		var q: Array = _queue.pop_front()
		if is_instance_valid(q[0]):
			var t0 := Time.get_ticks_usec()
			var res := blast_line(q[0], q[1], q[2])
			var res2 := neck_cut(q[0]) if not res.get("shattered", false) and through_neck(q[0], q[1], q[2]) else {}
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			last.lines = int(last.lines) + 1
			last.ms = snappedf((float(last.ms) * (int(last.lines) - 1) + ms) / int(last.lines), 0.01)
			last.max_ms = snappedf(maxf(float(last.max_ms), ms), 0.01)
			for rr in [res, res2]:
				if int(rr.get("cut", 0)) > 0 or not (rr.get("pieces", []) as Array).is_empty():
					_cut_fx(q[0], rr, q[3], true)
			_bwait = (Time.get_ticks_usec() - t0) / 1000000.0 / BLAST_SHARE
	# the scorch on the wall, the shake, the recoil
	arena.flames.emit(_end + _end_n * 0.02, 3, _end_n * 2.2, 1.6, 0.3)
	shooter.kick = maxf(float(shooter.kick), randf_range(0.3, 0.5) if top_down() else randf_range(0.5, 0.9))
	_kickback = maxf(_kickback, randf_range(0.25, 0.45))
	shooter.avatar.recoil = maxf(float(shooter.avatar.recoil), 0.6)

# ---------------------------------------------------------------- the look

func _sounds() -> void:
	if _on:
		var flesh := _in_body > 0.0
		sfx_loop("beam", "laser_loop", -3.0 if flesh else -5.0, 1.18 if flesh else 1.0)
	else:
		sfx_stop("beam")
	if _on and _in_body > 0.0:
		sfx_loop("sizzle", "laser_sizzle_loop", -5.0)
	else:
		sfx_stop("sizzle")
	if _blast_t >= 0.0:
		sfx_loop("blast", "laser_blast_loop", -1.0, 0.96 + 0.06 * sin(_t * 13.0))

# the beam from the lens to where it ends, the hot spot, the lights, sparks and smoke
func _draw(dt: float) -> void:
	var fat := _blast_t >= 0.0
	var lens := _lens_world()
	var charge_k := clampf(_charge / CHARGE_T, 0.0, 1.0) if _charging else (1.0 if fat else 0.0)
	_lens_light.global_position = lens
	_lens_light.light_energy = 3.5 * charge_k * charge_k + (0.5 if _on else 0.0) + (1.5 if fat else 0.0)
	_lens_light.visible = _lens_light.light_energy > 0.0       # (lights out of the scene when off: none to cluster)
	_lens_light.omni_range = 2.5 if top_down() else 1.2         # (top-down: a red glow on the floor round Jared)
	if not (_on or fat):
		_beam.visible = false
		_spot_light.visible = false
		return
	_beam.visible = true
	# 4 mm across (top-down, as thick as it needs to be to show from up there); the spot bigger the further off
	var cam_d: float = shooter.cam.global_position.distance_to(_end)
	var w := maxf(0.004, cam_d * 0.0035) if top_down() else 0.004
	var flick := randf_range(0.85, 1.15)
	var fwd := (_end - lens).normalized()
	if fat:
		# a white-hot core in a red glow, the glow widening out from the lens
		var wf := 2.0 if top_down() else 1.0             # (top-down: seen from 14 m up)
		_set_layer(_m_core, Color(1.0, 0.75, 0.7, 1.0), 5.0, 0.6)
		_set_layer(_m_halo, Color(1.0, 0.2, 0.08, 0.55), 1.6, 1.4)
		_set_layer(_m_outer, Color(1.0, 0.1, 0.04, 0.2), 1.2, 2.2)
		_stretch(_core, lens, _end, 0.05 * wf * flick)
		_stretch(_halo, lens + fwd * 0.12, _end, 0.2 * wf * flick)
		_stretch(_outer, lens + fwd * 0.3, _end, 0.38 * wf * randf_range(0.9, 1.1))
	else:
		_set_layer(_m_core, Color(1.0, 0.35, 0.25, 1.0), 4.0, 0.4)
		_set_layer(_m_halo, Color(1.0, 0.1, 0.05, 0.5), 1.5, 1.5)
		_stretch(_core, lens, _end, w)
		_stretch(_halo, lens, _end, w * 3.5 * flick)
	_outer.visible = fat
	var spot := maxf(0.05, cam_d * 0.012) * (2.6 if fat else 1.0)
	_spot.global_position = _end + _end_n * 0.004
	_spot.scale = Vector3.ONE * spot * randf_range(0.75, 1.2)
	_spot_light.global_position = _end + _end_n * 0.1
	_spot_light.light_energy = (4.0 if fat else 1.4) * flick
	_spot_light.visible = true
	if fat:
		return
	# sparks off the spot (more in a body), smoke drifting up off it
	var sv := _end_n * 1.4 + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * 0.7
	var in_b := is_instance_valid(_hit_b)
	arena.flames.emit(_end + _end_n * 0.01, 2 if in_b else 1, sv, 0.6, 0.15)
	_smoke_t -= dt
	if _smoke_t <= 0.0:
		_smoke_t = 0.05 if in_b else 0.14
		_puff(_end + _end_n * 0.02, _end_n * 0.15 + Vector3.UP * 0.35, randf_range(0.9, 1.5), 0.012, 0.05,
			Color(0.35, 0.33, 0.33, 0.3))

# a tube (_tube) stretched from a to b, w across
static func _stretch(mi: MeshInstance3D, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		mi.visible = false
		return
	mi.visible = true
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(x * w, y * l, x.cross(y) * w), (a + b) * 0.5)

func _lens_world() -> Vector3:
	if top_down():
		var hl: Variant = _hand_parts.get("lens")
		if is_instance_valid(hl) and (hl as Node3D).is_inside_tree():
			return (hl as Node3D).global_position
		return eye() + look() * 0.5
	return (_view_parts.lens as Node3D).global_position

# steam out of the fins, up and out to the sides (first person: wisps, drifting away from you; top-down: bigger,
# to show from up there)
func _steam() -> void:
	var fins: Variant = _hand_parts.get("fins") if top_down() else _view_parts.fins
	if not is_instance_valid(fins) or not (fins as Node3D).is_inside_tree():
		return
	var p := (fins as Node3D).global_position
	var fr := frame()
	var side := fr.x * randf_range(-1.0, 1.0)
	if top_down():
		_puff(p, Vector3.UP * randf_range(0.6, 1.1) + side * 0.5, randf_range(0.5, 0.9), 0.04, 0.25, Color(0.92, 0.94, 0.97, 0.5))
	else:
		_puff(p + side * 0.02, Vector3.UP * randf_range(0.25, 0.45) + side * 0.25 - fr.z * 0.2, randf_range(0.3, 0.55),
			0.004, 0.025, Color(0.92, 0.94, 0.97, 0.35))

func _puff(p: Vector3, v: Vector3, life: float, s0: float, s1: float, col: Color) -> void:
	var i := _pn
	if _pn >= MAX_PUFFS:
		i = randi() % MAX_PUFFS
	else:
		_pn += 1
	_pp[i] = p
	_pv[i] = v + Vector3(randf_range(-0.05, 0.05), 0.0, randf_range(-0.05, 0.05))
	_pl[i] = life
	_ps[i] = life
	_pa[i] = s0
	_pb[i] = s1
	_pc[i] = col

func _puffs_step(dt: float) -> void:
	var mm := _puffs.multimesh
	var i := 0
	while i < _pn:
		_pl[i] -= dt
		if _pl[i] <= 0.0:
			_pn -= 1
			_pp[i] = _pp[_pn]
			_pv[i] = _pv[_pn]
			_pl[i] = _pl[_pn]
			_ps[i] = _ps[_pn]
			_pa[i] = _pa[_pn]
			_pb[i] = _pb[_pn]
			_pc[i] = _pc[_pn]
			continue
		var k := 1.0 - _pl[i] / _ps[i]               # 0 just out .. 1 gone
		var v := _pv[i]
		v.y += 0.5 * dt
		v *= exp(-dt * 1.8)
		_pv[i] = v
		_pp[i] += v * dt
		var s := lerpf(_pa[i], _pb[i], sqrt(k))
		var col := _pc[i]
		col.a *= (1.0 - k) * minf(1.0, k * 8.0)
		mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(i * 0.7 + k, i * 1.3, k * 2.0)).scaled(Vector3.ONE * s), _pp[i]))
		mm.set_instance_color(i, col)
		i += 1
	mm.visible_instance_count = _pn

# the tool in the view (aimed at where the beam ends while it fires, raised to charge, tilted up to vent, kicking and
# trembling) and in Jared's hands; the lens, the charge glow and the heat strips
func _look(dt: float) -> void:
	var fat := _blast_t >= 0.0
	var charge_k := clampf(_charge / CHARGE_T, 0.0, 1.0) if _charging else (1.0 if fat else 0.0)
	var heat_col := STRIP_COLD.lerp(STRIP_HOT, _heat)
	var heat_e := 0.3 + 5.0 * _heat * _heat
	if _vent_t > 0.0:
		heat_e *= 0.55 + 0.45 * sin(_t * 22.0)
	var lens_e := 2.5 + (2.0 + randf() if _on else 0.0) + 14.0 * charge_k * charge_k + (4.0 if fat else 0.0)
	if _vent_t > 0.0:
		lens_e = 0.4
	var glow_s := (0.06 + 0.1 * charge_k * charge_k) * randf_range(0.85, 1.15) if charge_k > 0.0 else 0.0
	for parts in [_view_parts, _hand_parts]:
		if parts.is_empty() or not is_instance_valid(parts.get("glow")):
			continue
		var sm: StandardMaterial3D = parts.strip_m
		sm.albedo_color = heat_col
		sm.emission = heat_col
		sm.emission_energy_multiplier = heat_e
		var lm: StandardMaterial3D = parts.lens_m
		lm.emission_energy_multiplier = lens_e
		var g: MeshInstance3D = parts.glow
		g.visible = glow_s > 0.0
		g.scale = Vector3.ONE * maxf(glow_s * (2.5 if parts == _hand_parts else 1.0), 0.001)   # (top-down: seen small)
		(parts.lens_mi as MeshInstance3D).scale = Vector3.ONE * (1.0 + 0.5 * charge_k)
	var shake := 0.0007 + (0.0009 if _on else 0.0) + 0.006 * charge_k * charge_k * (0.0 if fat else 1.0) + (0.007 if fat else 0.0)
	if is_instance_valid(_hand) and _hand.is_visible_in_tree():
		_hand.position = Vector3(sin(_t * 91.0), sin(_t * 117.0 + 1.3), sin(_t * 71.0)) * shake * 0.8 + Vector3(0, 0, -0.04 * _kickback)
	_k_fire = move_toward(_k_fire, 1.0 if (_on or fat) else 0.0, dt * 7.0)
	_k_charge = move_toward(_k_charge, 1.0 if (_charging or fat) else 0.0, dt * 5.0)
	_k_vent = move_toward(_k_vent, 1.0 if _vent_t > 0.0 else 0.0, dt * 4.0)
	if top_down() or not view.visible:
		return
	var kf := _smooth(_k_fire)
	var kv := _smooth(_k_vent)
	var grip := REST.lerp(FIRE_AT, kf).lerp(CHARGE_AT, _smooth(_k_charge)).lerp(VENT_AT, kv)
	grip += Vector3(sin(_t * 1.3) * 0.003, sin(_t * 2.1) * 0.002, 0.0)      # breathing
	# where it points: the crosshair far off at rest, the beam's end while it fires (in the view's own space)
	var at := Vector3(0, 0, -AIM_D)
	if kf > 0.0:
		var e_local: Vector3 = shooter.cam.global_transform.affine_inverse() * _end - view.position
		if e_local.z < -0.6:
			at = at.lerp(e_local, kf)
	at = at.lerp(grip + Vector3(-0.35, 0.8, -0.55), kv)                   # turned up and in to vent
	var xf := _aim_xf(grip, at, ROLL + 0.55 * kv)
	# the fat beam's recoil: back and up
	xf.origin += xf.basis.z * 0.08 * _kickback
	xf.basis = xf.basis * Basis(Vector3.RIGHT, 0.18 * _kickback)
	xf.origin += Vector3(sin(_t * 93.0), sin(_t * 121.0 + 1.7), 0.6 * sin(_t * 67.0 + 0.5)) * shake
	xf.basis = xf.basis * Basis.from_euler(Vector3(sin(_t * 83.0), 0.7 * sin(_t * 101.0 + 0.3), sin(_t * 59.0 + 2.0)) * shake * 2.0)
	_tool.transform = xf

static func _smooth(k: float) -> float:
	var c := clampf(k, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

# ---------------------------------------------------------------- the core (static: the logic test runs it)

## Standing up (alive, on its feet or one): its middle is an upright line; else (dead, lying, crawling) anywhere within
## its height of its feet.
static func standing(b: VoxelBody) -> bool:
	return b.alive and not b.floored() and b.legs_lost() < 2 and not b.fragment

## How far along the ray from from (dir, unit; max_d long) it passes nearest b, if it comes within b's reach plus slack
## of it; -1 if it doesn't. Cheap: trace or carve only what passes.
static func in_line(b: VoxelBody, from: Vector3, dir: Vector3, max_d: float, slack: float) -> float:
	if not is_instance_valid(b) or b.cubes_left() <= 0:
		return -1.0
	var p := b.global_position
	var z := from + dir * max_d
	if standing(b):
		var pts := Geometry3D.get_closest_points_between_segments(from, z, p, p + Vector3.UP * b.height)
		if pts[0].distance_to(pts[1]) > b.radius + slack:
			return -1.0
		return from.distance_to(pts[0])
	var q := Geometry3D.get_closest_point_to_segment(p, from, z)
	if q.distance_to(p) > b.height + slack:
		return -1.0
	return from.distance_to(q)

## The first cube the beam meets on any of bodies, nearer than max_d (the wall): the trace's {dist, part, cell, point,
## normal} and body; {} if none. Bodies in line are traced nearest first (TRACE_MAX at most).
static func first_hit(bodies: Array, from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	var cand := []
	for b in bodies:
		var tb := in_line(b, from, dir, max_d, 0.3)
		if tb >= 0.0:
			cand.append([tb, b])
	cand.sort_custom(func(x, y): return x[0] < y[0])
	var best := {}
	var best_d := max_d
	var n := 0
	for c in cand:
		var b: VoxelBody = c[1]
		var reach := (b.radius if standing(b) else b.height) + 0.4
		if float(c[0]) - reach > best_d or n >= TRACE_MAX:
			break
		n += 1
		var h := b.trace(from, dir, best_d)
		if not h.is_empty() and float(h.dist) < best_d:
			best_d = h.dist
			best = h
			best.body = b
	return best

## The cut lines for the beam going from frame p to frame s ({from, dir, body (or null), d, x: how far along it the
## beam goes into the body and comes out}): lines in between (at most most) so that no two neighbours are more than
## SPACING apart, each cut into the body either frame met, then s's own line. [[body, a, z], ...] (world).
static func lines_between(p: Dictionary, s: Dictionary, most: int) -> Array:
	var out := []
	var sb: VoxelBody = s.body if is_instance_valid(s.get("body")) else null
	var pb: VoxelBody = p.body if not p.is_empty() and is_instance_valid(p.get("body")) else null
	var sf: Vector3 = s.from
	var sd: Vector3 = s.dir
	var own := []
	if sb != null:
		own = [sb, sf + sd * (float(s.d) - CUT_PRE), sf + sd * (float(s.x) + CUT_POST)]
	if pb != null or sb != null:
		var pf: Vector3 = p.get("from", sf)
		var pd: Vector3 = p.get("dir", sd)
		# where it goes in and comes out between the two: anywhere from the nearer to the further
		var d0: float = minf(p.d, s.d) if pb != null and sb != null else (p.d if pb != null else s.d)
		var x0: float = maxf(p.x, s.x) if pb != null and sb != null else (p.x if pb != null else s.x)
		var gap := line_gap([null, pf + pd * d0, pf + pd * x0], [null, sf + sd * d0, sf + sd * x0])
		var n := mini(most, ceili(gap / SPACING) - 1)
		for k in range(1, n + 1):
			var f := float(k) / float(n + 1)
			var dir := pd.slerp(sd, f).normalized()
			var from := pf.lerp(sf, f)
			for b in [pb, sb]:
				if b != null:
					out.append([b, from + dir * (d0 - CUT_PRE), from + dir * (x0 + CUT_POST)])
				if pb == sb:
					break
	if sb != null:
		out.append(own)
	return out

## How far along the beam (from from, dir) it comes out of b, going in at d: the last cube on it within CUT_DEPTH
## (traced back from there). A cut line ends there, so it's no longer than it need be (a long one costs more).
static func exit_dist(b: VoxelBody, from: Vector3, dir: Vector3, d: float) -> float:
	var h := b.trace(from + dir * (d + CUT_DEPTH), -dir, CUT_DEPTH)
	return d + CUT_DEPTH - float(h.dist) if not h.is_empty() else d + 0.05

## Of the cut lines ([body, a, z], in the order the beam went) the ones to cut: a line is cut when the next one into
## the same body would be more than SPACING from the last one cut (so the cut has no gaps and no line too many); the
## last into each body is held back in carry while it's still within SPACING (the next frames' may do instead).
## kept: body id -> the last line cut into each, updated.
static func thin_lines(lines: Array, kept: Dictionary, carry: Array) -> Array:
	var out := []
	for i in lines.size():
		var ln: Array = lines[i]
		if not is_instance_valid(ln[0]):
			continue
		var id := (ln[0] as Object).get_instance_id()
		if kept.has(id):
			var nxt := []
			for j in range(i + 1, lines.size()):
				if is_instance_valid(lines[j][0]) and lines[j][0] == ln[0]:
					nxt = lines[j]
					break
			if nxt.is_empty():
				if line_gap(kept[id], ln) <= SPACING:
					carry.append(ln)
					continue
			elif line_gap(kept[id], nxt) <= SPACING:
				continue
		kept[id] = ln
		out.append(ln)
	return out

## How far apart two cut lines ([body, a, z]) are: the furthest either end of q is off p's line.
static func line_gap(p: Array, q: Array) -> float:
	var pa: Vector3 = p[1]
	var u := ((p[2] as Vector3) - pa).normalized()
	return maxf(((q[1] as Vector3) - pa).cross(u).length(), ((q[2] as Vector3) - pa).cross(u).length())

## Whether the line a-z goes through the middle of b's neck (within NECK_D of the head's joint).
static func through_neck(b: VoxelBody, a: Vector3, z: Vector3) -> bool:
	if not b.parts.has("head") or bool(b.parts.head.gone):
		return false
	var jw := _joint(b, "head")
	return Geometry3D.get_closest_point_to_segment(jw, a, z).distance_to(jw) <= NECK_D

## Cut through the neck: the head off at its base, whole (a carve can't sever it there: the head's joint is at its
## bottom edge, so whatever is left of the neck either side of a cut line still counts as joined). A thin plane cut
## across the neck's own axis through the joint (VoxelBody.slice).
static func neck_cut(b: VoxelBody) -> Dictionary:
	var pose := b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(b.parts.head.bone))
	var up := pose.basis.y.normalized()
	var fwd := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	return b.slice(pose.origin, up, fwd, 0.3, -1.0, b.vm * 0.9)

## One cut: every cube within CUT_R of a-z (world) cut out of b, a body cube costing HP_PER_CUBE health; whatever that
## leaves hanging comes off (VoxelBody.carve; one flying bit for every BITS_EVERY cubes).
static func cut_line(b: VoxelBody, a: Vector3, z: Vector3) -> Dictionary:
	return b.carve(a, z, CUT_R, HP_PER_CUBE, BITS_EVERY)

## The stretch of the fat beam (distances along it) bored through b, which it passes nearest at tb: BLAST_HALF either
## side for one standing, its height for one lying; not past the wall (max_d).
static func blast_span(b: VoxelBody, tb: float, max_d: float) -> Vector2:
	var half := BLAST_HALF if standing(b) else b.height * 0.6 + 0.2
	return Vector2(maxf(0.2, tb - half), minf(max_d, tb + half))

## The fat tunnel: every cube within BLAST_R of a-z bored out of b (VoxelBody.carve).
static func blast_line(b: VoxelBody, a: Vector3, z: Vector3) -> Dictionary:
	return b.carve(a, z, BLAST_R, BLAST_HP, 2)

## The heat after dt seconds at rate a second (0..1).
static func heat_step(heat: float, dt: float, rate: float) -> float:
	return clampf(heat + rate * dt, 0.0, 1.0)

## A cut's flying bits, cauterised: at most n of them (spread through the list), frac of those glowing hot (orange,
## yellow, white; one in four charred). Returns them.
static func hot_bits(bits: Array, n: int, frac: float) -> Array:
	var out := []
	var m := mini(n, bits.size())
	for i in m:
		var bt: Dictionary = bits[int(float(i) * bits.size() / m)]
		if randf() < frac:
			bt.col = HOT[randi() % HOT.size()] if randf() < 0.75 else VoxelBody.CHAR
		out.append(bt)
	return out

# a grunt for the checks (stands at the origin facing +z)
static func _grunt(host: Node, m: Material, at: Vector3 = Vector3.ZERO) -> VoxelBody:
	var b := VoxelBody.new()
	host.add_child(b)
	b.setup("grunt", 0.023, 1, m)
	b.position = at
	b.animate(0.0, false)
	return b

# a sweep for the checks: the beam along dir, its start moved from f0 to f1 in steps frames (each traced; or, with an
# eye e, from e at a point moved from f0 to f1), the lines cut as the weapon cuts them (fill: lines filled in between
# two frames at most)
static func _sweep(b: VoxelBody, f0: Vector3, f1: Vector3, dir: Vector3, steps: int, fill: int, e := Vector3.INF) -> Dictionary:
	var out := {"lines": 0, "cut": 0, "pieces": [], "killed": false, "head_off": false, "ms": 0.0, "max_ms": 0.0}
	var prev := {}
	var kept := {}
	var carry := []
	for i in steps + 1:
		var from := f0.lerp(f1, float(i) / steps)
		if e != Vector3.INF:
			dir = (from - e).normalized()
			from = e
		var h := first_hit([b], from, dir, 10.0)
		var d: float = h.get("dist", 0.0)
		var s := {"from": from, "dir": dir, "body": b if not h.is_empty() else null, "d": d,
			"x": exit_dist(b, from, dir, d) if not h.is_empty() else 0.0}
		var lines := carry
		carry = []
		lines.append_array(lines_between(prev, s, fill))
		for ln in thin_lines(lines, kept, carry):
			_sweep_cut(b, ln, out)
		prev = s
	for ln in carry:
		_sweep_cut(b, ln, out)
	if int(out.lines) > 0:
		out.ms = float(out.ms) / int(out.lines)
	return out

static func _sweep_cut(b: VoxelBody, ln: Array, out: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var r := cut_line(b, ln[1], ln[2])
	var r2 := neck_cut(b) if through_neck(b, ln[1], ln[2]) else {}
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	out.lines += 1
	out.ms += ms
	out.max_ms = maxf(float(out.max_ms), ms)
	for rr in [r, r2]:
		if rr.is_empty():
			continue
		out.cut += int(rr.cut)
		for pc in rr.pieces:
			(out.pieces as Array).append(String(pc.part))
		out.killed = bool(out.killed) or bool(rr.killed)
		out.head_off = bool(out.head_off) or bool(rr.head_off)

# a joint of b in the world (a part's bone)
static func _joint(b: VoxelBody, part: String) -> Vector3:
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(b.parts[part].bone)).origin

static func checks(host: Node) -> Array:
	var out := []
	var was := VoxelBody.immortal
	VoxelBody.immortal = false
	var m := StandardMaterial3D.new()
	var back := Vector3.FORWARD
	# one beam into the chest from in front: a thin line cut right through, nothing off, few bits
	var b := _grunt(host, m)
	var from := Vector3(0, 1.0, 2.0)
	var h := first_hit([b], from, back, 10.0)
	out.append([not h.is_empty() and String(h.part) == "torso" and float(h.dist) > 1.5 and float(h.dist) < 2.0,
		"the beam meets his chest (%s at %.2f m)" % [h.get("part", "-"), float(h.get("dist", 0.0))]])
	var d: float = h.get("dist", 1.8)
	var x := exit_dist(b, from, back, d)
	out.append([x > d + 0.3 and x < d + 0.5, "it comes out of his back %.2f m on" % (x - d)])
	var t0 := Time.get_ticks_usec()
	var r := cut_line(b, from + back * (d - CUT_PRE), from + back * (x + CUT_POST))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var cut := int(r.cut)
	out.append([cut > 10 and cut < 300 and (r.pieces as Array).is_empty() and (r.parts as Array) == ["torso"] and b.alive,
		"one cut line through the chest: a thin hole right through (%d cubes, %.1f ms), nothing off" % [cut, ms]])
	out.append([(r.bits as Array).size() <= cut / 2 and hot_bits(r.bits, HOT_BITS, 1.0).size() <= HOT_BITS,
		"cauterised: few bits fly (%d of %d, %d shown)" % [(r.bits as Array).size(), cut, mini(HOT_BITS, (r.bits as Array).size())]])
	var hb := hot_bits([{"pos": Vector3.ZERO, "col": VoxelBody.FLESH[0]}, {"pos": Vector3.ZERO, "col": VoxelBody.BONE}], 4, 1.0)
	out.append([hb.size() == 2 and (HOT + [VoxelBody.CHAR]).has(hb[0].col) and (HOT + [VoxelBody.CHAR]).has(hb[1].col),
		"the bits glow orange-hot (or charred)"])
	var r2 := cut_line(b, from + back * (d - CUT_PRE), from + back * (x + CUT_POST))
	out.append([int(r2.cut) == 0, "the same line again cuts nothing new (%d)" % r2.cut])
	# the beam stops at the first body: one behind him isn't met
	var b_behind := _grunt(host, m, Vector3(0, 0, -1.2))
	var h2 := first_hit([b_behind, b], from + Vector3(0.08, 0.1, 0), back, 10.0)
	out.append([not h2.is_empty() and h2.body == b, "the beam stops at the first one in line"])
	out.append([in_line(b, from + Vector3(1.6, 0, 0), back, 10.0, 0.3) < 0.0 and in_line(b, from + Vector3(0, 2.0, 0), back, 10.0, 0.3) < 0.0,
		"a beam off to the side or over his head isn't near him"])
	b.queue_free()
	b_behind.queue_free()
	# a crowd standing just beside the beam doesn't hide the one in it further on
	var crowd := []
	for i in 5:
		crowd.append(_grunt(host, m, Vector3(0.76 if i % 2 == 0 else -0.76, 0, -1.0 - i * 1.2)))
	var b_far := _grunt(host, m, Vector3(0, 0, -7.0))
	var h3 := first_hit(crowd + [b_far], from + Vector3(0, 0.1, 0), back, 20.0)
	out.append([not h3.is_empty() and h3.body == b_far, "a crowd beside the beam doesn't hide the one in it"])
	for c in crowd + [b_far]:
		c.queue_free()
	# dragged across the right shin: the foot comes off
	var b2 := _grunt(host, m)
	var s1 := _sweep(b2, Vector3(-0.45, 0.27, 2.0), Vector3(-0.02, 0.27, 2.0), back, 22, FILL_MAX)
	out.append([(s1.pieces as Array).has("foot_r") and b2.parts.foot_r.gone and b2.legs_lost() >= 1,
		"dragged across the right shin: the foot comes off (%d lines, %d cubes, %.2f ms a line)" % [s1.lines, s1.cut, s1.ms]])
	# dragged across the neck: off with his head, dead
	var neck := _joint(b2, "head")
	var s2 := _sweep(b2, Vector3(-0.3, neck.y, 2.0), Vector3(0.3, neck.y, 2.0), back, 30, FILL_MAX)
	out.append([bool(s2.head_off) and b2.parts.head.gone and not b2.alive,
		"dragged across the neck: off with his head, dead (%d lines)" % s2.lines])
	b2.queue_free()
	# dragged down past the shoulder: the arm comes off whole there
	var b3 := _grunt(host, m)
	var sh := _joint(b3, "arm_l")
	var sx := sh.x + signf(sh.x) * 0.04
	var s3 := _sweep(b3, Vector3(sx, sh.y + 0.15, 2.0), Vector3(sx, sh.y - 0.37, 2.0), back, 26, FILL_MAX)
	out.append([(s3.pieces as Array).has("arm_l") and b3.parts.hand_l.gone and b3.parts.forearm_l.gone and not b3.parts.torso.gone,
		"dragged down past the shoulder: the arm off whole (%d lines, %d cubes)" % [s3.lines, s3.cut]])
	b3.queue_free()
	# dragged across the middle: cut in half, the top half (head, arms) off
	var b4 := _grunt(host, m)
	var s4 := _sweep(b4, Vector3(-0.6, 0.85, 2.0), Vector3(0.6, 0.85, 2.0), back, 40, FILL_MAX)
	out.append([(s4.pieces as Array).has("torso") and b4.parts.head.gone and b4.parts.arm_r.gone and not b4.parts.thigh_l.gone and not b4.alive,
		"dragged across the middle: cut in half (%d lines, %d cubes, %.2f ms a line, worst %.1f)" % [s4.lines, s4.cut, s4.ms, s4.max_ms]])
	out.append([float(s4.ms) < 8.0, "a cut line costs %.2f ms (worst %.1f)" % [s4.ms, s4.max_ms]])
	b4.queue_free()
	# the same from up at your eye (first person: the beam slopes down through him, so a line costs more)
	var b7 := _grunt(host, m)
	var s7 := _sweep(b7, Vector3(-0.6, 0.85, 0), Vector3(0.6, 0.85, 0), back, 40, FILL_MAX, Vector3(0.25, 1.65, 1.4))
	out.append([(s7.pieces as Array).has("torso") and not b7.alive and float(s7.ms) < 25.0,
		"dragged across his middle from your eye: cut in half (%d lines, %.1f ms a line, worst %.1f)" % [s7.lines, s7.ms, s7.max_ms]])
	b7.queue_free()
	# a fast drag (frames 15 cm apart): the lines filled in between still cut him in half; without them he holds
	var b5 := _grunt(host, m)
	var s5 := _sweep(b5, Vector3(-0.6, 0.85, 2.0), Vector3(0.6, 0.85, 2.0), back, 8, FILL_MAX)
	var b6 := _grunt(host, m)
	var s6 := _sweep(b6, Vector3(-0.6, 0.85, 2.0), Vector3(0.6, 0.85, 2.0), back, 8, 0)
	out.append([(s5.pieces as Array).has("torso") and not (s6.pieces as Array).has("torso"),
		"a fast drag: filled in, still cut in half (%d lines); not filled in, he holds together (%d lines)" % [s5.lines, s6.lines]])
	b5.queue_free()
	b6.queue_free()
	# the fat beam: a tunnel through two in a row
	var f1 := _grunt(host, m)
	var f2 := _grunt(host, m, Vector3(0.05, 0, -1.3))
	var bf := Vector3(0, 1.05, 2.5)
	var cuts := []
	var t1 := Time.get_ticks_usec()
	for fb in [f1, f2]:
		var tb := in_line(fb, bf, back, 10.0, BLAST_R + 0.1)
		if tb < 0.0:
			cuts.append(0)
			continue
		var sp := blast_span(fb, tb, 10.0)
		cuts.append(int(blast_line(fb, bf + back * sp.x, bf + back * sp.y).cut))
	var ms2 := (Time.get_ticks_usec() - t1) / 1000.0 / 2.0
	out.append([int(cuts[0]) > 300 and int(cuts[1]) > 300, "the fat beam bores through both in line (%d and %d cubes, %.1f ms each)" % [cuts[0], cuts[1], ms2]])
	f1.queue_free()
	f2.queue_free()
	# the heat: about five seconds of beam overheats it; it cools resting
	var heat := 0.0
	var secs := 0.0
	while heat < 1.0 and secs < 10.0:
		heat = heat_step(heat, 1.0 / 60.0, HEAT_BEAM)
		secs += 1.0 / 60.0
	out.append([secs > 4.8 and secs < 5.2, "%.2f s of beam overheats it" % secs])
	var blast_heat := heat_step(heat_step(0.0, CHARGE_T, HEAT_CHARGE), BLAST_MAX, HEAT_BLAST)
	out.append([blast_heat > 0.6 and blast_heat < 1.0, "a full overcharge heats it to %d%% (warm, it overheats)" % roundi(blast_heat * 100.0)])
	VoxelBody.immortal = was
	return out

func reset_state() -> void:
	_heat = 0.0
	_vent_t = 0.0
