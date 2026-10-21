class_name VoxelWeaponFlamethrower
extends VoxelMelee
## The flamethrower (the owner, 20 Oct: six new weapons, each doing something different): fire that spreads. A squat
## red fuel tank slung under a black nozzle pipe in a perforated steel shroud, held at the hip, a little blue-white
## pilot flame flickering at the tip and a gauge on the tank showing the fuel. Hold left and it sprays a roaring stream
## of fire: blobs of burning fuel thrown about 6 m, drooping a little, the flames billowing wider and redder the further
## they get and splashing over whatever they meet. About ten times a second a small cone of rays follows the stream
## (VoxelBody.trace on the bodies near it, a world ray for walls, pillars and the floor), and every body it reaches,
## alive, dead or a lying piece, is set alight where it lands (VoxelBody.ignite). The body does the rest by itself:
## the fire spreads over it, chars the cubes black and burns them to ash, and the living panic and run about flailing.
## More fire on one already burning just adds more. A frozen one is thawed instead (the ice steams off, a few seconds
## of its freeze melted each second), then it burns. The tank holds 8 s of spray and refills at a third of that rate
## once you stop; the weapon bar shows the fuel. Run it dry and it coughs out a few weak puffs and stops. Right click
## lobs a fire bomb (every 2.5 s, 15% of the tank): a blob of burning fuel in an arc toward where you aim, trailing
## flames. It bursts on the floor (or on the first body it hits, setting it alight, then drops at its feet) into a
## patch of fire 1.8 m across that burns about 6 s, crackling, catching the feet and shins of everyone standing or
## lying in it, then dies down to a scorch mark. Four patches burn at most (the oldest goes out). Top-down it's in
## Jared's right hand at the hip and sprays toward the mouse, the stream coming down on the floor at the end of its
## reach (so what lies there burns too). The core (the stream's line, what it reaches, what it sets alight or thaws,
## the patch's catching, the lob, the fuel) is static so the logic test can run it. Owned by the voxel session.

const REACH := 6.0              # metres the stream reaches
const STREAM_V := 11.0          # m/s the burning fuel leaves the nozzle
const DROOP := 2.6              # m/s/s it droops
const AIM_AT := 4.5             # metres out along the look the stream crosses the crosshair (aimed up a little for the droop)
const TD_DIP := 0.68            # top-down: metres below the nozzle it crosses AIM_AT out (it's on the floor by REACH)
const SPREAD := 0.04            # radians the fuel strays from the stream's line at most
const DROPS := 45.0             # blobs of fuel a second, each lighting flames along its way
const MAX_DROPS := 120
const FLAMES := 55.0            # flames a second each blob lights along its way (the splash where it lands is kept thin:
                                # seen close up, piled-up flames glare white)
const ARC_N := 3                # straight pieces the stream's drooping line is traced in
const TICK := 0.1               # seconds between the stream's hit tests at most ...
const BUDGET := 0.08            # ... and fewer if they cost more than this share of the time
const RAYS := 5                 # rays in its cone: the middle and a ring round it
const CONE := 0.07              # radians out from the middle the ring is
const SLACK := 0.7              # metres off the stream's line a body is still traced (the cone spreads, arms reach)
const IGNITE_R := 0.085         # metres round where the stream lands that catch
const SPOTS := 2                # spots a hit test sets alight on one body at most ...
const MAX_BODIES := 4           # ... and bodies
const THAW := 8.0               # seconds of a frozen body's freeze the fire melts a second
const FUEL_S := 8.0             # seconds of spray in a full tank
const REFILL_DELAY := 0.6       # seconds after it stops before the tank refills ...
const REFILL := 1.0 / 3.0       # ... at this share of the rate it empties
const MIN_FUEL := 0.04          # less than this and it won't light
const SPUTTER := [0.0, 0.17, 0.31, 0.52, 0.7]   # run dry: when its last weak puffs come (seconds)
const RAISE_T := 0.12           # seconds the gun takes to come up spraying ...
const LOWER_T := 0.28           # ... and to go back to the hip
# the fire bomb
const BOMB_CD := 2.5
const BOMB_FUEL := 0.15
const BOMB_G := 12.0            # m/s/s pulling the blob down
const BOMB_RANGE := 16.0        # metres (level) it's lobbed at most
const BOMB_IGNITE_R := 0.13     # metres round where it hits a body that catch
const LOB_T := 0.5              # the gun's kick as it lobs, seconds
const PATCH_R := 0.9            # the patch of fire it leaves: metres from its middle to its edge ...
const PATCH_T := 6.0            # ... seconds it burns ...
const PATCH_FADE := 1.5         # ... the last of them dying down
const PATCH_TICK := 0.2         # seconds between its catching whoever's in it
const PATCH_IGNITE_R := 0.08
const PATCH_BODIES := 3         # bodies one catch sets alight at most
const PATCH_FLAMES := 110.0     # flames a second over it, blazing
const MAX_PATCHES := 4
const SCORCH_T := 4.0           # seconds the scorch mark stays after the fire's out
const TILE := 0.12              # metres: the floor tiles the patch is drawn in
const MAX_PUFFS := 240          # smoke and steam
# poses in camera space (x right, y up, -z forward): where the grip is and a point the nozzle aims at
const REST_GRIP := Vector3(0.25, -0.22, -0.38)    # (the tank shows above the weapon bar)
const REST_AT := Vector3(0.03, -0.1, -4.0)
const FIRE_GRIP := Vector3(0.23, -0.205, -0.42)
const FIRE_AT := Vector3(0.0, -0.04, -AIM_AT)
const ROLL := 0.12              # radians it's turned over about the nozzle (its gauge side toward you)
const HAND_SCALE := 0.9         # top-down: Jared's is this big
const NEEDLE := 1.1             # radians the gauge's needle swings either side of half full

const SMOKE := Color(0.1, 0.09, 0.085, 0.42)
const STEAM := Color(0.9, 0.94, 0.98, 0.45)
const CHARRED := Color(0.07, 0.06, 0.055)

var _gun: Node3D                # first person: the flamethrower (the grip at its origin, the nozzle along +z), under view
var _vm := {}                   # its moving parts (see _model)
var _hand: Node3D               # top-down: the one in Jared's hand (the arena frees it on a switch)
var _hm := {}
var _light: OmniLight3D         # the stream's flicker (in the world)
var _tile_mat: StandardMaterial3D
var _out := false               # taken out (not put away)
var _firing := false            # spraying
var _fire_k := 0.0              # 0 at the hip .. 1 up spraying
var _fuel := 1.0
var _idle := 9.0                # seconds since it last sprayed (the refill waits a moment)
var _sputter := -1.0            # seconds into coughing out (-1: not)
var _sp_i := 0                  # the next of SPUTTER's puffs
var _tick := 0.0                # seconds to the next hit test
var _tick_dt := TICK            # seconds the last one waited
var _end_d := REACH             # metres along the stream to where it hits something (the fuel splashes there)
var _jolt := 0.0                # the gun bucking (lit, let go, coughing), 1 .. 0
var _heat := 0.0                # the nozzle glowing hot, 0 .. 1
var _steam_t := 0.0             # seconds left of the steam's hiss
var _bomb_cd := 0.0
var _lob_t := -1.0              # seconds into the gun's lob kick (-1: none)
var _t := 0.0
var _frames := 0                # frames sprayed this move (the cost per frame) ...
var _secs := 0.0                # ... and seconds
var _sl := {}                   # what the spray did (last, while it's the latest move) ...
var _bl := {}                   # ... and the latest fire bomb (its blob and patch keep counting into it)
var _globs := []                # fire bombs in the air: {node, light, p, v, t, off: "" or what it ran off ("body", "wall")}
var _patches := []              # patches of fire: {node, mm, light, at, t, tick, acc, smoke, key, phase, rad, out}
var _patch_n := 0
# blobs of burning fuel in the stream: where, how fast, how far they've come, how far past the stream's end they get
var _dp := PackedVector3Array()
var _dv := PackedVector3Array()
var _ds := PackedFloat32Array()
var _dj := PackedFloat32Array()
var _dn := 0
var _drop_acc := 0.0
# smoke and steam: little grey and white cubes rising and spreading (one draw call)
var _puffs: MultiMeshInstance3D
var _pp := PackedVector3Array()
var _pv := PackedVector3Array()
var _pl := PackedFloat32Array()
var _ps := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _pc := PackedColorArray()
var _pn := 0

func _build() -> void:
	_gun = Node3D.new()
	_gun.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(_gun)
	_vm = _model(_gun, false)
	_gun.transform = _aim_xf(REST_GRIP, REST_AT, ROLL)
	_light = OmniLight3D.new()
	_light.top_level = true
	_light.light_color = Color(1.0, 0.55, 0.22)
	_light.omni_range = 7.0
	_light.light_energy = 0.0
	add_child(_light)
	_tile_mat = StandardMaterial3D.new()
	_tile_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tile_mat.vertex_color_use_as_albedo = true
	_puffs = MultiMeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = pm
	_puffs.multimesh = MultiMesh.new()
	_puffs.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_puffs.multimesh.use_colors = true
	_puffs.multimesh.mesh = bm
	_puffs.multimesh.instance_count = MAX_PUFFS
	_puffs.multimesh.visible_instance_count = 0
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puffs.top_level = true
	add_child(_puffs)
	_pp.resize(MAX_PUFFS)
	_pv.resize(MAX_PUFFS)
	_pl.resize(MAX_PUFFS)
	_ps.resize(MAX_PUFFS)
	_pz.resize(MAX_PUFFS)
	_pc.resize(MAX_PUFFS)
	_dp.resize(MAX_DROPS)
	_dv.resize(MAX_DROPS)
	_ds.resize(MAX_DROPS)
	_dj.resize(MAX_DROPS)

# the flamethrower, weapon space (the grip at the origin, the nozzle along +z, its top +y; +x is its left), metres.
# Returns its moving parts: {tip: a Node3D at the nozzle's mouth, pilot: the pilot flame's boxes, needle: the fuel
# gauge's needle (turned about x), hot: the nozzle's material (it glows when hot)}. light: brighter, for top-down
# (seen small from up high on a dark floor).
func _model(root: Node3D, light: bool) -> Dictionary:
	var red := mat(Color(0.9, 0.17, 0.1) if light else Color(0.68, 0.08, 0.05), 0.3, 0.42)
	var red_dk := mat(Color(0.62, 0.09, 0.06) if light else Color(0.4, 0.04, 0.03), 0.3, 0.5)
	var black := mat(Color(0.22, 0.22, 0.24) if light else Color(0.06, 0.06, 0.07), 0.3, 0.6)
	var body := mat(Color(0.42, 0.43, 0.46) if light else Color(0.3, 0.31, 0.34), 0.5, 0.45)
	var steel := mat(Color(0.8, 0.81, 0.84), 0.85, 0.3)
	var dark := mat(Color(0.3, 0.3, 0.33), 0.7, 0.4)
	var brass := mat(Color(0.82, 0.62, 0.24), 0.8, 0.35)
	var white := mat(Color(0.92, 0.92, 0.88), 0.0, 0.6)
	var yellow := mat(Color(0.95, 0.75, 0.1), 0.0, 0.6)
	var hot := mat(Color(0.1, 0.1, 0.1), 0.6, 0.4)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.32, 0.06)
	hot.emission_energy_multiplier = 0.0
	# the pistol grip, the trigger and its guard
	box(root, Vector3(0.032, 0.105, 0.042), Vector3(0, -0.045, -0.008), black, Vector3(0.25, 0, 0))
	box(root, Vector3(0.008, 0.008, 0.055), Vector3(0, -0.04, 0.045), black)
	box(root, Vector3(0.008, 0.026, 0.008), Vector3(0, -0.02, 0.032), steel)
	# the body along the top, a cap at the back
	box(root, Vector3(0.05, 0.055, 0.27), Vector3(0, 0.03, 0.125), body)
	box(root, Vector3(0.054, 0.058, 0.02), Vector3(0, 0.03, -0.015), black)
	# the fuel tank slung under it: squat, its edges rounded off, bands round it, end caps, a filler cap, a hazard
	# stripe and the gauge on the side
	var tc := Vector3(0, -0.055, 0.175)
	box(root, Vector3(0.1, 0.095, 0.2), tc, red)
	box(root, Vector3(0.084, 0.112, 0.19), tc, red)
	box(root, Vector3(0.116, 0.078, 0.19), tc, red)
	for z: float in [0.072, 0.278]:
		box(root, Vector3(0.07, 0.068, 0.012), Vector3(0, tc.y, z), red_dk)
	for z: float in [0.11, 0.24]:
		box(root, Vector3(0.12, 0.116, 0.014), Vector3(0, tc.y, z), black)
	box(root, Vector3(0.014, 0.024, 0.026), Vector3(0.061, -0.03, 0.262), brass)
	box(root, Vector3(0.004, 0.011, 0.1), Vector3(0.0595, -0.088, 0.175), yellow)
	box(root, Vector3(0.006, 0.046, 0.046), Vector3(0.0595, -0.048, 0.175), black)
	box(root, Vector3(0.004, 0.037, 0.037), Vector3(0.062, -0.048, 0.175), white)
	var needle := Node3D.new()
	needle.position = Vector3(0.0645, -0.048, 0.175)
	root.add_child(needle)
	box(needle, Vector3(0.002, 0.017, 0.003), Vector3(0, 0.007, 0), red)
	# the fuel line from the tank up into the pipe
	box(root, Vector3(0.016, 0.016, 0.04), Vector3(0, -0.03, 0.3), black)
	box(root, Vector3(0.016, 0.06, 0.016), Vector3(0, 0.0, 0.316), black)
	# the nozzle pipe, the steel heat shroud round it (slotted, rings at its ends), the fore grip under it
	box(root, Vector3(0.026, 0.026, 0.36), Vector3(0, 0.045, 0.43), black)
	box(root, Vector3(0.048, 0.048, 0.22), Vector3(0, 0.045, 0.41), steel)
	for z: float in [0.3, 0.52]:
		box(root, Vector3(0.054, 0.054, 0.012), Vector3(0, 0.045, z), dark)
	for i in 5:
		var z := 0.33 + 0.04 * i
		box(root, Vector3(0.012, 0.003, 0.018), Vector3(0, 0.0695, z), black)
		box(root, Vector3(0.003, 0.012, 0.018), Vector3(0.0245, 0.045, z), black)
	box(root, Vector3(0.026, 0.075, 0.03), Vector3(0, -0.017, 0.41), black)
	# the mouth (it glows when hot), the pilot light's little pipe under it and its flame
	box(root, Vector3(0.036, 0.036, 0.032), Vector3(0, 0.045, 0.62), hot)
	box(root, Vector3(0.022, 0.022, 0.004), Vector3(0, 0.045, 0.6365), black)
	box(root, Vector3(0.008, 0.008, 0.05), Vector3(0, 0.019, 0.605), dark)
	var pilot := []
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.4, 0.62, 1.0, 0.9)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var core := glow.duplicate() as StandardMaterial3D
	core.albedo_color = Color(0.9, 0.95, 1.0, 1.0)
	pilot.append(box(root, Vector3(0.013, 0.016, 0.018), Vector3(0, 0.021, 0.638), glow))
	pilot.append(box(root, Vector3(0.006, 0.008, 0.009), Vector3(0, 0.02, 0.636), core))
	var tip := Node3D.new()
	tip.position = Vector3(0, 0.045, 0.64)
	root.add_child(tip)
	return {"tip": tip, "pilot": pilot, "needle": needle, "hot": hot}

# a pose: the grip at grip, the nozzle aimed at at (both camera space), turned roll radians about it
static func _aim_xf(grip: Vector3, at: Vector3, roll: float = 0.0) -> Transform3D:
	var z := (at - grip).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var bs := Basis(x, z.cross(x), z)
	if roll != 0.0:
		bs = Basis(z, roll) * bs
	return Transform3D(bs, grip)

func hand_mesh() -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_hand = Node3D.new()            # shaken while it sprays (the arena sets root's own transform)
	root.add_child(_hand)
	var inner := Node3D.new()
	inner.scale = Vector3.ONE * HAND_SCALE
	_hand.add_child(inner)
	_hm = _model(inner, true)
	return root

func hand_pose() -> String:
	return "shotgun"                # at the hip, both hands on it

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var dim := Color(col.r * 0.35, col.g * 0.35, col.b * 0.38, col.a)
	var red := Color(0.85, 0.16, 0.1, col.a)
	var fire := Color(1.0, 0.62, 0.18, col.a)
	for b in [[Rect2(0.5, 2.3, 0.7, 1.7), dim], [Rect2(0.2, 1.3, 3.9, 0.9), dim], [Rect2(1.4, 2.25, 2.6, 1.7), red],
			[Rect2(4.0, 1.55, 3.4, 0.45), col], [Rect2(4.4, 1.3, 2.4, 0.95), col], [Rect2(5.4, 2.2, 0.35, 0.9), dim],
			[Rect2(7.4, 1.4, 0.4, 0.75), dim], [Rect2(7.9, 1.25, 0.9, 1.05), fire], [Rect2(8.8, 1.45, 0.8, 0.65), fire]]:
		var rr: Rect2 = b[0]
		ci.draw_rect(Rect2(r.position + rr.position * u, rr.size * u), b[1])

# ---------------------------------------------------------------- the buttons

func cooling() -> float:
	# the tank's emptiness (the bar's edge fills as it refills), or the fire bomb's wait, whichever's more
	return maxf(1.0 - _fuel, clampf(_bomb_cd / BOMB_CD, 0.0, 1.0))

func bar_text() -> String:
	return "%d%%" % roundi(_fuel * 100.0)

func press(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		if _fuel < MIN_FUEL:
			_cough(3)                   # a dry cough or two
			return
		_firing = true
		_sputter = -1.0
		_tick = 0.05                    # the first hit test as the fire gets out there
		_tick_dt = TICK
		_end_d = REACH
		_jolt = 1.0
		_frames = 0
		_secs = 0.0
		sfx("flamethrower_start")
		if not top_down():
			shooter.kick = maxf(float(shooter.kick), 0.4)
		_sl = {"move": "spray", "secs": 0.0, "ticks": 0, "hits": 0, "bodies": 0, "caught": 0, "thawed": 0, "end_d": REACH,
			"fuel": 0.0, "ran_dry": false, "tick_ms": 0.0, "max_tick_ms": 0.0, "frame_ms": 0.0, "max_frame_ms": 0.0,
			"flames": 0, "drops": 0}
		last = _sl
	elif button == MOUSE_BUTTON_RIGHT:
		bomb()

func release(button: int) -> void:
	if button != MOUSE_BUTTON_LEFT or not _firing:
		return
	# let go: the last of it puffs out of the nozzle
	_firing = false
	sfx_stop("roar")
	sfx("flamethrower_stop")
	_jolt = 0.45
	var s := _stream()
	var o: Vector3 = s[0]
	var d: Vector3 = s[1]
	arena.flames.emit(o + d * 0.08, 8, d * 1.8, 3.0, 0.25)
	_puff(o + d * 0.15, d * 0.4 + Vector3.UP * 0.6, SMOKE, 0.07, 1.0)

func on_select() -> void:
	_out = true

func on_deselect() -> void:
	_out = false
	_firing = false
	_sputter = -1.0
	_lob_t = -1.0
	_fire_k = 0.0
	sfx_stop("roar")
	sfx_stop("steam")

## Right click: a fire bomb lobbed toward where you aim (every BOMB_CD, BOMB_FUEL of the tank).
func bomb() -> void:
	if _bomb_cd > 0.0:
		return
	if _fuel < BOMB_FUEL:
		_bomb_cd = 0.4
		_cough(3)
		return
	var s := _stream()
	var o: Vector3 = s[0]
	var to := _bomb_target()
	var flat := Vector2(to.x - o.x, to.z - o.z).length()
	var secs := clampf(0.25 + flat * 0.065, 0.3, 1.3)
	var v := lob(o, to, BOMB_G, secs)
	_fuel -= BOMB_FUEL
	_idle = 0.0
	_bomb_cd = BOMB_CD
	_lob_t = 0.0
	_globs.append(_glob(o, v))
	sfx("flamethrower_lob")
	arena.flames.emit(o, 10, v.normalized() * 2.0, 4.0, 0.3)
	_puff(o, v.normalized() * 0.5 + Vector3.UP * 0.5, SMOKE, 0.08, 1.0)
	if top_down():
		shooter.avatar.recoil = 1.0
	else:
		shooter.kick = maxf(float(shooter.kick), 0.8)
	_bl = {"move": "bomb", "flight": snappedf(secs, 0.01), "to": to.snapped(Vector3.ONE * 0.01), "hit_body": false, "landed": "",
		"caught": 0, "patch_ignites": 0, "patch_caught": 0, "patch_ms": 0.0, "fuel": snappedf(_fuel, 0.01)}
	last = _bl

# where a fire bomb is lobbed to: the first body along where you aim (its upright middle), else the wall or floor
# there; no further than BOMB_RANGE (the floor that far out if it's aimed further or at the sky). Top-down: along the
# mouse's line from the camera.
func _bomb_target() -> Vector3:
	var from := eye()
	var dir := look()
	if top_down():
		var mr: Array = shooter.mouse_ray()
		if not mr.is_empty():
			from = mr[0]
			dir = mr[1]
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0)
	q.exclude = shooter.exclude()
	var wh := get_world_3d().direct_space_state.intersect_ray(q)
	var to: Vector3 = wh.position if not wh.is_empty() else from + dir * 60.0
	var best := from.distance_to(to)
	var sky := wh.is_empty()
	for b in arena.bodies:
		var p: Vector3 = b.global_position
		var up: float = b.height * 0.9 if (b.alive and not b.floored()) else 0.35
		var cp := Geometry3D.get_closest_points_between_segments(from, from + dir * best, p, p + Vector3.UP * up)
		if cp[0].distance_to(cp[1]) < 0.3 and from.distance_to(cp[0]) < best:
			best = from.distance_to(cp[0])
			to = cp[1]
			sky = false
	var pp: Vector3 = shooter.player.global_position
	var flat := Vector3(to.x - pp.x, 0.0, to.z - pp.z)
	if sky or flat.length() > BOMB_RANGE:
		to = pp + flat.normalized() * BOMB_RANGE      # (aimed at the sky: as far as it goes, onto the floor)
	return to

# a sputter: the weak puffs of SPUTTER from the i-th on, and the sound
func _cough(i: int) -> void:
	_sputter = float(SPUTTER[i])
	_sp_i = i
	sfx("flamethrower_empty", Vector3.INF, 3.0 if i == 0 else -2.0)

# ---------------------------------------------------------------- every frame

func step(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_t += dt
	_bomb_cd = maxf(0.0, _bomb_cd - dt)
	_jolt = maxf(0.0, _jolt - dt * 6.0)
	_heat = clampf(_heat + dt * (0.7 if _firing else -0.3), 0.0, 1.0)
	_fire_k = move_toward(_fire_k, 1.0 if _firing else 0.0, dt / (RAISE_T if _firing else LOWER_T))
	if _lob_t >= 0.0:
		_lob_t += dt
		if _lob_t >= LOB_T:
			_lob_t = -1.0
	if _firing:
		_fuel = refuel(_fuel, dt, true, 0.0)
		_idle = 0.0
		if _fuel <= 0.0:
			_run_dry()
	else:
		_idle += dt
		_fuel = refuel(_fuel, dt, false, _idle)
	var s := _stream() if (_firing or _sputter >= 0.0) else []
	if _firing:
		_spray(dt, s)
	if _sputter >= 0.0:
		_sputter_step(dt, s)
	if not _firing:
		_light.light_energy = move_toward(_light.light_energy, 0.0, dt * 20.0)
	_light.visible = _light.light_energy > 0.0
	_steam_t -= dt
	if _steam_t > 0.0 and _out:
		sfx_loop("steam", "flamethrower_steam_loop", -6.0)
	elif _steam_t > -dt:
		sfx_stop("steam")
	_drops_step(dt, s)
	_globs_step(dt)
	_patches_step(dt)
	_puffs_step(dt)
	_look()
	if _firing:
		_frames += 1
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		_sl.frame_ms = snappedf((float(_sl.frame_ms) * (_frames - 1) + ms) / _frames, 0.01)
		_sl.max_frame_ms = snappedf(maxf(float(_sl.max_frame_ms), ms), 0.01)
		_sl.flames = maxi(int(_sl.flames), int(arena.flames.count()))
		_sl.drops = maxi(int(_sl.drops), _dn)
		_sl.fuel = snappedf(_fuel, 0.01)

# where the stream starts and which way it goes: [the nozzle's mouth (world), its direction (unit)]. First person from
# the view's nozzle through the crosshair AIM_AT out; top-down from the nozzle in Jared's hand toward the mouse, dipping
# so it comes down on the floor at the end of its reach. A nozzle poked into a wall (it sticks out a metre) starts at
# the wall's face instead, so nothing goes through.
func _stream() -> Array:
	var f := look()
	var o: Vector3 = (_vm.tip as Node3D).global_position
	if top_down():
		o = shooter.player.global_position + Vector3(0, 0.95, 0) + f * 0.7
		if is_instance_valid(_hand) and _hand.is_visible_in_tree():
			o = (_hm.tip as Node3D).global_position
	var q := PhysicsRayQueryParameters3D.create(eye(), o)
	q.exclude = shooter.exclude()
	var wh := get_world_3d().direct_space_state.intersect_ray(q)
	if not wh.is_empty():
		o = (wh.position as Vector3) + (eye() - o).normalized() * 0.05
	if top_down():
		return [o, aim_dir(o, o + Vector3.DOWN * TD_DIP, f)]
	return [o, aim_dir(o, eye(), f)]

# spraying: fuel out, the roar, the light, the gun shaking, a hit test every so often
func _spray(dt: float, s: Array) -> void:
	var o: Vector3 = s[0]
	var d: Vector3 = s[1]
	sfx_loop("roar", "flamethrower_loop", -1.0 + 1.2 * sin(_t * 3.1), 1.0 + 0.03 * sin(_t * 1.7))
	_light.global_position = o + d * minf(1.4, _end_d * 0.5) + Vector3.UP * 0.15
	_light.light_energy = _fire_k * randf_range(0.9, 1.6)
	if top_down():
		shooter.avatar.recoil = maxf(float(shooter.avatar.recoil), randf_range(0.1, 0.3))
	else:
		shooter.kick = maxf(float(shooter.kick), randf_range(0.04, 0.12))
	_secs += dt
	_sl.secs = snappedf(_secs, 0.01)
	_tick -= dt
	if _tick <= 0.0:
		_hit_test(o, d)

# the stream run dry: it stops and coughs out
func _run_dry() -> void:
	_fuel = 0.0
	_firing = false              # (held on, it stays out till the next press)
	sfx_stop("roar")
	_cough(0)
	_sl.ran_dry = true

func _sputter_step(dt: float, s: Array) -> void:
	_sputter += dt
	var o: Vector3 = s[0]
	var d: Vector3 = s[1]
	while _sp_i < SPUTTER.size() and _sputter >= float(SPUTTER[_sp_i]):
		# a weak puff: a little fire that doesn't get far, a gout of smoke, the gun bucking
		var k := 1.0 - 0.17 * _sp_i
		arena.flames.emit(o + d * 0.05, int(5 + 7 * k), d * (1.2 + 2.6 * k), 2.6 + 1.5 * k, 0.18 + 0.12 * k)
		_puff(o + d * 0.1, d * 0.6 + Vector3.UP * 0.5, SMOKE, 0.06 + 0.03 * k, 1.1)
		_jolt = maxf(_jolt, 0.5 * k)
		if not top_down():
			shooter.kick = maxf(float(shooter.kick), 0.25 * k)
		_sp_i += 1
	if _sp_i >= SPUTTER.size():
		_sputter = -1.0

# one hit test: a cone of rays down the drooping stream; each body the rays reach is set alight (or thawed) where the
# nearest of them lands, and the stream's end set where the middle one stops
func _hit_test(o: Vector3, d: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	var space := get_world_3d().direct_space_state
	var lines := []                 # per ray: [its points, how far it gets before a wall or the floor]
	for dir in cone(d, RAYS, CONE, randf() * TAU):
		var pts := arc(o, dir, REACH, ARC_N)
		lines.append([pts, _wall_d(space, pts)])
	var cands := []
	for b in bodies_near(o, REACH + 1.0):
		if near_line(b, lines[0][0], SLACK):
			cands.append(b)
	var hits := {}                  # body -> [its hits, nearest first]
	var end_d: float = lines[0][1]
	for i in lines.size():
		var upto: float = lines[i][1]
		var best := {}
		var best_b: VoxelBody = null
		for b in cands:
			var h := hit_along(b, lines[i][0], upto)
			if not h.is_empty():
				upto = float(h.dist)
				best = h
				best_b = b
		if best_b == null:
			continue
		if not hits.has(best_b):
			hits[best_b] = []
		(hits[best_b] as Array).append(best)
		if i == 0:
			end_d = upto
	_end_d = end_d
	var order := hits.keys()
	order.sort_custom(func(x, y): return float(hits[x][0].dist) < float(hits[y][0].dist))
	var thawed := false
	for bi in mini(order.size(), MAX_BODIES):
		var b: VoxelBody = order[bi]
		var hs: Array = hits[b]
		hs.sort_custom(func(x, y): return float(x.dist) < float(y.dist))
		for j in mini(hs.size(), SPOTS):
			var h: Dictionary = hs[j]
			var p: Vector3 = h.point
			var r := scorch(b, p, IGNITE_R, THAW * _tick_dt / mini(hs.size(), SPOTS))
			_sl.caught = int(_sl.caught) + int(r.caught)
			_sl.hits = int(_sl.hits) + 1
			if bool(r.thawed):
				thawed = true
				_puff(p, (h.normal as Vector3) * 0.5 + Vector3.UP * 0.8, STEAM, 0.08, 0.9)
			else:
				arena.flames.emit(p, 3, (h.normal as Vector3) * 1.2 + Vector3.UP * 0.8, 5.0, 0.45)
		_sl.bodies = int(_sl.bodies) + 1
	if thawed:
		_sl.thawed = int(_sl.thawed) + 1
		_steam_t = 0.3
	_sl.ticks = int(_sl.ticks) + 1
	_sl.end_d = snappedf(_end_d, 0.01)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_sl.tick_ms = snappedf((float(_sl.tick_ms) * (int(_sl.ticks) - 1) + ms) / int(_sl.ticks), 0.01)
	_sl.max_tick_ms = snappedf(maxf(float(_sl.max_tick_ms), ms), 0.01)
	_tick_dt = maxf(TICK, ms / 1000.0 / BUDGET)
	_tick = _tick_dt

# how far along the stream's line pts it gets before a wall, a pillar or the floor
func _wall_d(space: PhysicsDirectSpaceState3D, pts: PackedVector3Array) -> float:
	var ex: Array[RID] = shooter.exclude()
	var gone := 0.0
	for i in pts.size() - 1:
		var q := PhysicsRayQueryParameters3D.create(pts[i], pts[i + 1])
		q.exclude = ex
		var wh := space.intersect_ray(q)
		if not wh.is_empty():
			return gone + pts[i].distance_to(wh.position)
		gone += pts[i].distance_to(pts[i + 1])
	return gone

# the burning fuel in the stream: new blobs out of the nozzle while it sprays; each flies (drooping), lighting flames
# along its way that are small and white-hot near the nozzle and big and red further out, till it reaches the
# stream's end (or the floor) and splashes
func _drops_step(dt: float, s: Array) -> void:
	if _firing:
		var o: Vector3 = s[0]
		var d: Vector3 = s[1]
		var side := d.cross(Vector3.UP)
		side = (side if side.length() > 0.01 else d.cross(Vector3.RIGHT)).normalized()
		var upv := side.cross(d).normalized()
		_drop_acc += DROPS * dt
		while _drop_acc >= 1.0 and _dn < MAX_DROPS:
			_drop_acc -= 1.0
			var a := randf() * TAU
			var dir := (d + (side * cos(a) + upv * sin(a)) * randf() * SPREAD).normalized()
			var v := dir * STREAM_V * randf_range(0.93, 1.05)
			var lead := randf() * dt            # spread through the frame, not bunched at its start
			_dp[_dn] = o + v * lead
			_dv[_dn] = v
			_ds[_dn] = v.length() * lead
			_dj[_dn] = randf_range(-0.1, 0.35)
			_dn += 1
		_drop_acc = minf(_drop_acc, 1.0)
	if _dn == 0:
		return
	var big := 1.45 if top_down() else 1.0
	var fl: VoxelFlames = arena.flames
	var i := 0
	while i < _dn:
		var p0 := _dp[i]
		var v := _dv[i]
		v.y -= DROOP * dt
		var p1 := p0 + v * dt
		var s1 := _ds[i] + v.length() * dt
		var k := clampf(s1 / REACH, 0.0, 1.0)
		if s1 >= minf(REACH, _end_d + _dj[i]) or p1.y < 0.03:
			# splashed: the fire spreads out over what it hit and up it (a little more the sooner it hit: it hadn't
			# burnt on the way), now and then smoke
			var vn := v.normalized()
			for j in 1 + int(1.5 * (1.0 - k) + randf()):
				var out := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
				out = (out - vn * out.dot(vn)).normalized() * randf_range(1.2, 3.0)
				fl.emit(p1, 1, out - vn * 0.4 + Vector3.UP * randf_range(0.4, 1.6), randf_range(4.5, 7.0) * big, 0.5)
			if randf() < 0.1:
				_puff(p1 + Vector3.UP * 0.15, Vector3(randf_range(-0.3, 0.3), randf_range(0.6, 1.1), randf_range(-0.3, 0.3)), SMOKE, 0.1, 1.4)
			_dn -= 1
			_dp[i] = _dp[_dn]
			_dv[i] = _dv[_dn]
			_ds[i] = _ds[_dn]
			_dj[i] = _dj[_dn]
			continue
		var w := 0.35 + 1.7 * k
		for j in int(FLAMES * dt + randf()):
			fl.emit(p0.lerp(p1, randf()), 1, v * 0.3 + Vector3(randf_range(-w, w), randf_range(-w, w) * 0.6, randf_range(-w, w)),
				(2.2 + 6.0 * k) * big, 0.14 + 0.32 * k)
		_dp[i] = p1
		_dv[i] = v
		_ds[i] = s1
		i += 1

# ---------------------------------------------------------------- the fire bomb

# a blob of burning fuel in the air (its own node in the world): a hot core in a glowing skin, a light
func _glob(o: Vector3, v: Vector3) -> Dictionary:
	var node := Node3D.new()
	node.top_level = true
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(node)
	node.global_position = o
	var skin := StandardMaterial3D.new()
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.albedo_color = Color(1.0, 0.45, 0.08, 0.75)
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var core := skin.duplicate() as StandardMaterial3D
	core.albedo_color = Color(1.0, 0.9, 0.55, 1.0)
	box(node, Vector3(0.15, 0.13, 0.15), Vector3.ZERO, skin)
	box(node, Vector3(0.08, 0.08, 0.08), Vector3.ZERO, core, Vector3(0.6, 0.4, 0.2))
	var lt := OmniLight3D.new()
	lt.light_color = Color(1.0, 0.55, 0.2)
	lt.omni_range = 3.5
	lt.light_energy = 1.6
	node.add_child(lt)
	return {"node": node, "light": lt, "p": o, "v": v, "t": 0.0, "off": ""}

# the blobs in the air: falling, trailing flames; one that hits a body sets it alight there and drops at its feet, one
# that hits a wall runs down it, and on the floor each bursts into a patch of fire
func _globs_step(dt: float) -> void:
	if _globs.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = shooter.exclude()
	var big := 1.4 if top_down() else 1.0
	for g in _globs.duplicate():
		var node: Node3D = g.node
		var p0: Vector3 = g.p
		var v: Vector3 = g.v
		v.y -= BOMB_G * dt
		var p1 := p0 + v * dt
		g.t = float(g.t) + dt
		var land := Vector3.INF
		var seg := p1 - p0
		if String(g.off) == "" and seg.length() > 0.0001:
			for b in bodies_near(p1, 1.6):
				var h: Dictionary = b.trace(p0, seg.normalized(), seg.length() + 0.06)
				if h.is_empty():
					continue
				var hp: Vector3 = h.point
				var r := scorch(b, hp, BOMB_IGNITE_R, THAW * 0.6)
				_burst(hp, h.normal, 0.45)
				sfx("flamethrower_splash", hp, -2.0, 1.15)
				if not top_down() and eye().distance_to(hp) < 4.0:
					hit_stop(0.035, 0.3)
				_note("caught", int(r.caught))
				_bl.hit_body = true
				g.off = "body"
				p1 = hp + (h.normal as Vector3) * 0.1
				v = Vector3(v.x * 0.08, minf(v.y, 0.0) * 0.3, v.z * 0.08)
				break
		var q := PhysicsRayQueryParameters3D.create(p0, p1)
		q.exclude = ex
		var wh := space.intersect_ray(q)
		if not wh.is_empty():
			var n: Vector3 = wh.normal
			if n.y > 0.6:
				land = wh.position
			else:
				# a wall or a pillar: it splashes and runs down it
				p1 = (wh.position as Vector3) + n * 0.1
				v = Vector3(0, minf(v.y, 0.0), 0)
				g.off = "wall"
		if p1.y <= 0.02:
			land = Vector3(p1.x, 0.0, p1.z)
		if land != Vector3.INF or float(g.t) > 5.0:
			if land != Vector3.INF:
				_land(land, String(g.off))
			node.queue_free()
			_globs.erase(g)
			continue
		g.p = p1
		g.v = v
		node.global_position = p1
		node.rotation += Vector3(7.0, 5.0, 3.0) * dt
		(g.light as OmniLight3D).light_energy = randf_range(1.2, 2.0)
		arena.flames.emit(p1, 3, -v * 0.08 + Vector3.UP * 0.3, 4.5 * big, 0.35)
		if randf() < dt * 6.0:
			_puff(p1, Vector3.UP * 0.5, SMOKE, 0.07, 0.9)

# a blob lands (off: what it ran down first, "" none): a burst of fire, a new patch (the oldest of MAX_PATCHES goes
# out), the cubes lying there thrown up
func _land(at: Vector3, off: String) -> void:
	var burning := _patches.filter(func(pt): return float(pt.t) < PATCH_T)
	if burning.size() >= MAX_PATCHES:
		burning[0].t = maxf(float(burning[0].t), PATCH_T - 0.35)
	_patches.append(_patch(at))
	_burst(at + Vector3.UP * 0.05, Vector3.UP, 1.0)
	sfx("flamethrower_splash", at)
	arena.debris.pop(at, PATCH_R, 1.8, 300)
	if not top_down() and eye().distance_to(at) < 5.0:
		shooter.kick = maxf(float(shooter.kick), 0.45)
	_bl.landed = {"": "floor", "body": "at its feet", "wall": "at the wall's foot"}[off]
	_bl.patch_at = at.snapped(Vector3.ONE * 0.01)

# fire thrown out from where a blob burst (n: the face it hit; k: how much): spread out over the face and up, only a
# little straight off it (a burst on someone's chest doesn't throw fire in your face)
func _burst(p: Vector3, n: Vector3, k: float) -> void:
	var big := 1.3 if top_down() else 1.0
	for i in int(20 * k):
		var out := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		out = (out - n * out.dot(n)).normalized() * randf_range(0.6, 2.2) + n * randf_range(0.2, 0.7) + Vector3.UP * randf_range(0.4, 1.6)
		arena.flames.emit(p, 1, out, randf_range(4.5, 8.0) * big, randf_range(0.35, 0.65))
	for i in int(4 * k):
		_puff(p + Vector3.UP * 0.3, Vector3(randf_range(-0.4, 0.4), randf_range(0.8, 1.4), randf_range(-0.4, 0.4)), SMOKE, 0.08, 1.6)

# a patch of fire on the floor (its own node in the world): floor tiles glowing like embers (one draw call), a light
func _patch(at: Vector3) -> Dictionary:
	var node := Node3D.new()
	node.top_level = true
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(node)
	node.global_position = at
	var cells := []
	var n := ceili(PATCH_R / TILE) + 1
	for gx in range(-n, n + 1):
		for gz in range(-n, n + 1):
			var c := Vector2(gx, gz) * TILE
			var rr := c.length()
			if rr <= PATCH_R - TILE * 0.5 or (rr <= PATCH_R + TILE * 0.5 and randf() < 0.45):
				cells.append(c)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(TILE * 0.94, 0.008, TILE * 0.94)
	bm.material = _tile_mat
	mm.mesh = bm
	mm.instance_count = cells.size()
	var phase := PackedFloat32Array()
	var rad := PackedFloat32Array()
	for i in cells.size():
		var c: Vector2 = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(c.x, 0.004 + 0.002 * randf(), c.y)))
		phase.append(randf() * TAU)
		rad.append(minf(1.0, c.length() / PATCH_R))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mmi)
	var lt := OmniLight3D.new()
	lt.light_color = Color(1.0, 0.5, 0.18)
	lt.omni_range = 4.5
	lt.position = Vector3(0, 0.7, 0)
	node.add_child(lt)
	_patch_n += 1
	return {"node": node, "mm": mm, "light": lt, "at": at, "t": 0.0, "tick": 0.05, "acc": 0.0, "smoke": 0.0,
		"key": "%dpatch%d" % [get_instance_id(), _patch_n], "phase": phase, "rad": rad, "out": false}

# the patches: flames over each, the crackle, the light; catching whoever's in it; the tiles glowing and charring;
# out, a scorch mark a while, then gone
func _patches_step(dt: float) -> void:
	for pt in _patches.duplicate():
		pt.t = float(pt.t) + dt
		var t: float = pt.t
		var at: Vector3 = pt.at
		var node: Node3D = pt.node
		var k := blaze(t)
		if t < PATCH_T:
			pt.acc = float(pt.acc) + PATCH_FLAMES * k * dt
			while float(pt.acc) >= 1.0:
				pt.acc = float(pt.acc) - 1.0
				var a := randf() * TAU
				var rr := sqrt(randf()) * PATCH_R
				arena.flames.emit(at + Vector3(cos(a) * rr, 0.03, sin(a) * rr), 1,
					Vector3(randf_range(-0.15, 0.15), randf_range(0.3, 1.2), randf_range(-0.15, 0.15)),
					randf_range(3.5, 8.0) * (1.0 - 0.4 * rr / PATCH_R), randf_range(0.45, 0.85))
			pt.smoke = float(pt.smoke) + dt * 2.5 * k
			if float(pt.smoke) >= 1.0:
				pt.smoke = 0.0
				var a2 := randf() * TAU
				_puff(at + Vector3(cos(a2), 0, sin(a2)) * randf() * PATCH_R * 0.7 + Vector3.UP * 0.6, Vector3(randf_range(-0.2, 0.2), randf_range(0.7, 1.1), randf_range(-0.2, 0.2)), SMOKE, 0.1, 1.8)
			(pt.light as OmniLight3D).light_energy = minf(k, 1.0) * randf_range(1.3, 2.1) + 5.0 * maxf(0.0, 1.0 - t / 0.25)
			arena.sound.loop(String(pt.key), "flamethrower_patch_loop", node, linear_to_db(clampf(k, 0.05, 1.0)) - 2.0)
			pt.tick = float(pt.tick) - dt
			if float(pt.tick) <= 0.0:
				pt.tick = PATCH_TICK
				_catch(at)
				arena.hurt_players_near(at + Vector3.UP * 0.3, PATCH_R + 0.5, 3.0 * k)     # (standing in it burns you)
		elif not bool(pt.out):
			pt.out = true
			arena.sound.stop(String(pt.key))
			(pt.light as OmniLight3D).visible = false
		if Engine.get_process_frames() % 3 == 0 and t < PATCH_T + 0.5:
			_tiles(pt, k)
		var gone := t - PATCH_T - SCORCH_T
		if gone > 0.0:
			node.global_position = at + Vector3.DOWN * gone * 0.02    # sinks out of sight under the floor
		if gone > 1.0:
			node.queue_free()
			_patches.erase(pt)

# the patch's tiles: embers glowing and flickering while it burns (hotter in the middle), charring as it dies
func _tiles(pt: Dictionary, k: float) -> void:
	var mm: MultiMesh = pt.mm
	var phase: PackedFloat32Array = pt.phase
	var rad: PackedFloat32Array = pt.rad
	var kk := clampf(k, 0.0, 1.0)
	for i in mm.instance_count:
		var ph := phase[i]
		var heat := kk * (0.55 + 0.45 * sin(_t * (4.0 + ph) + ph * 5.0)) * (1.0 - 0.5 * rad[i])
		var col := CHARRED.lerp(Color(0.6, 0.1, 0.02), clampf(heat * 2.0, 0.0, 1.0))
		col = col.lerp(Color(1.15, 0.42, 0.06), clampf(heat * 2.0 - 1.0, 0.0, 1.0))
		mm.set_instance_color(i, col)

# a patch catching: whoever's standing or lying in it set alight low on the legs (the nearest few)
func _catch(at: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	var n := 0
	for b in bodies_near(at, PATCH_R + 0.6):
		if n >= PATCH_BODIES:
			break
		var p := legs_point(b, randi())
		if not in_patch(p, at):
			continue
		n += 1
		var r := scorch(b, p, PATCH_IGNITE_R, THAW * PATCH_TICK * 0.5)
		_note("patch_ignites", 1)
		_note("patch_caught", int(r.caught))
		if bool(r.thawed):
			_puff(p, Vector3.UP * 0.9, STEAM, 0.08, 0.9)
	if n > 0:
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var k := maxi(1, int(_bl.patch_ignites))
		_bl.patch_ms = snappedf((float(_bl.patch_ms) * (k - n) + ms) / k, 0.01)

# adds to one of the latest fire bomb's numbers (what it and its patch did)
func _note(key: String, add: int) -> void:
	_bl[key] = int(_bl.get(key, 0)) + add

# ---------------------------------------------------------------- smoke and steam

func _puff(p: Vector3, v: Vector3, col: Color, size: float, life: float) -> void:
	var i := _pn
	if _pn >= MAX_PUFFS:
		i = randi() % MAX_PUFFS
	else:
		_pn += 1
	_pp[i] = p
	_pv[i] = v
	var sp := life * randf_range(0.7, 1.3)
	_pl[i] = sp
	_ps[i] = sp
	_pz[i] = size * randf_range(0.7, 1.3)
	_pc[i] = col

func _puffs_step(dt: float) -> void:
	if _pn == 0 and _puffs.multimesh.visible_instance_count == 0:
		return
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
			_pz[i] = _pz[_pn]
			_pc[i] = _pc[_pn]
			continue
		var k := _pl[i] / _ps[i]                 # 1 just out .. 0 gone
		var v := _pv[i] * exp(-dt * 1.2) + Vector3.UP * 0.35 * dt
		_pv[i] = v
		_pp[i] += v * dt
		var c := _pc[i]
		c.a *= clampf(k * 1.6, 0.0, 1.0) * clampf((1.0 - k) * 8.0, 0.0, 1.0)
		var sz := _pz[i] * (1.0 + 1.3 * (1.0 - k))
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, i * 1.7).scaled(Vector3.ONE * sz), _pp[i]))
		mm.set_instance_color(i, c)
		i += 1
	mm.visible_instance_count = _pn

# ---------------------------------------------------------------- the look

func _look() -> void:
	_flicker(_vm)
	if is_instance_valid(_hand) and _hand.is_visible_in_tree():
		_flicker(_hm)
		var a := 0.004 * _fire_k + 0.01 * _jolt
		_hand.position = Vector3(sin(_t * 71.0), sin(_t * 93.0 + 1.3), sin(_t * 57.0)) * a
	if top_down() or not view.visible:
		return
	# at the hip, breathing; up spraying (aimed where the stream goes), shaking with it; the lob kicks the nozzle up
	var sway := Vector3(sin(_t * 1.1) * 0.004, sin(_t * 2.2) * 0.003, 0.0)
	var xf := _aim_xf(REST_GRIP + sway, REST_AT, ROLL)
	if _fire_k > 0.0:
		var k := _fire_k
		k = 1.0 - (1.0 - k) * (1.0 - k) if _firing else _smooth(k)
		xf = xf.interpolate_with(_aim_xf(FIRE_GRIP, FIRE_AT, ROLL * 0.5), k)
	if _lob_t >= 0.0:
		var lk := _lob_k(_lob_t)
		xf.basis = xf.basis * Basis(Vector3.RIGHT, -0.4 * lk)
		xf.origin += Vector3(0.0, 0.025, 0.06) * lk
	xf.basis = xf.basis * Basis(Vector3.RIGHT, -0.1 * _jolt)
	xf.origin += Vector3(0.0, 0.006, 0.035) * _jolt
	var amp := 0.0022 * _fire_k
	xf.origin += Vector3(sin(_t * 71.0), sin(_t * 93.0 + 1.7), 0.6 * sin(_t * 57.0 + 0.5)) * amp
	xf.basis = xf.basis * Basis.from_euler(Vector3(sin(_t * 83.0), 0.7 * sin(_t * 61.0 + 0.3), sin(_t * 47.0 + 2.0)) * amp * 2.0)
	_gun.transform = xf

# the pilot flame flickering, the gauge's needle on the fuel, the nozzle's glow
func _flicker(m: Dictionary) -> void:
	if m.is_empty():
		return
	for mi in m.pilot:
		if is_instance_valid(mi):
			(mi as Node3D).scale = Vector3(randf_range(0.75, 1.2), randf_range(0.7, 1.45), randf_range(0.75, 1.25))
	(m.needle as Node3D).rotation = Vector3(lerpf(-NEEDLE, NEEDLE, _fuel), 0, 0)
	(m.hot as StandardMaterial3D).emission_energy_multiplier = 3.0 * _heat * _heat

# the lob's kick: up fast, back down slowly (0 .. 1 .. 0)
static func _lob_k(t: float) -> float:
	if t < 0.06:
		var k := t / 0.06
		return 1.0 - (1.0 - k) * (1.0 - k)
	return 1.0 - _smooth((t - 0.06) / (LOB_T - 0.06))

static func _smooth(k: float) -> float:
	var c := clampf(k, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

# ---------------------------------------------------------------- the core (static: the logic test runs it)

## The stream's direction from the nozzle o: through the point AIM_AT out along the look (from e along f, unit),
## aimed up a little so its droop brings it down there.
static func aim_dir(o: Vector3, e: Vector3, f: Vector3) -> Vector3:
	var to := e + f * AIM_AT - o
	var tt := to.length() / STREAM_V
	to.y += 0.5 * DROOP * tt * tt
	return to.normalized()

## The stream's drooping line from o along d (unit) out to reach metres, in n straight pieces: its n + 1 points.
static func arc(o: Vector3, d: Vector3, reach: float = REACH, n: int = ARC_N) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n + 1:
		var s := reach * i / n
		var tt := s / STREAM_V
		out.append(o + d * s + Vector3.DOWN * 0.5 * DROOP * tt * tt)
	return out

## n directions round d (unit): d itself, then n - 1 on a cone half radians out from it, the ring turned by spin.
static func cone(d: Vector3, n: int, half: float, spin: float) -> Array:
	var out := [d]
	var side := d.cross(Vector3.UP)
	side = (side if side.length() > 0.01 else d.cross(Vector3.RIGHT)).normalized()
	for i in n - 1:
		out.append(d.rotated(side.rotated(d, spin + TAU * i / (n - 1)), half).normalized())
	return out

## Whether b is near enough to the stream's line pts to be worth tracing: its upright middle (standing) or within its
## height of its feet (lying, dead, a piece) within slack metres of a piece of the line. Cheap; trace only what passes.
static func near_line(b: VoxelBody, pts: PackedVector3Array, slack: float) -> bool:
	if not is_instance_valid(b):
		return false
	var p := b.global_position
	var standing := b.alive and not b.floored() and b.legs_lost() < 2 and not b.fragment
	for i in pts.size() - 1:
		if standing:
			var cp := Geometry3D.get_closest_points_between_segments(pts[i], pts[i + 1], p, p + Vector3.UP * b.height)
			if cp[0].distance_to(cp[1]) <= b.radius + slack:
				return true
		elif Geometry3D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) <= b.height + slack:
			return true
	return false

## The first cube of b the stream's line pts reaches within upto metres along it: {} or VoxelBody.trace's hit, its
## dist measured along the whole line.
static func hit_along(b: VoxelBody, pts: PackedVector3Array, upto: float = INF) -> Dictionary:
	var gone := 0.0
	for i in pts.size() - 1:
		if gone >= upto:
			break
		var seg := pts[i + 1] - pts[i]
		var l := seg.length()
		var h := b.trace(pts[i], seg / l, minf(l, upto - gone))
		if not h.is_empty():
			h.dist = gone + float(h.dist)
			return h
		gone += l
	return {}

## Fire landing on b at at (world): set alight within r metres (VoxelBody.ignite: it spreads, chars and burns to ash
## by itself; on fire already, it just catches more). Frozen, it catches nothing: thaw seconds of its freeze melt
## instead (it thaws when they run out). {caught: cubes alight, thawed: it was ice}.
static func scorch(b: VoxelBody, at: Vector3, r: float, thaw: float) -> Dictionary:
	if b.frozen():
		b.frozen_t = maxf(0.001, b.frozen_t - thaw)     # (status_step thaws it as the last of it runs out)
		return {"caught": 0, "thawed": true}
	return {"caught": b.ignite(at, r), "thawed": false}

## A point low on b's legs for a fire on the floor to catch: the middle of a shin (pick chooses which leg), or a foot or
## a thigh if that's what's left, or the lowest part it has (a lying piece). INF: nothing left.
static func legs_point(b: VoxelBody, pick: int) -> Vector3:
	var have := func(n: String) -> bool: return b.parts.has(n) and not bool(b.parts[n].gone)
	for legs: Array in [["shin_l", "shin_r"], ["foot_l", "foot_r"], ["thigh_l", "thigh_r"]]:
		var got := legs.filter(have)
		if got.is_empty():
			continue
		var n: String = got[pick % got.size()]
		var p := joint(b, n)
		if n.begins_with("shin"):
			p = (p + joint(b, "foot" + n.substr(4))) * 0.5     # the knee to the ankle
		elif n.begins_with("thigh"):
			p = p.lerp(joint(b, "shin" + n.substr(5)), 0.8)    # just above the knee
		return p
	var low := Vector3.INF
	for n in b.parts:
		if have.call(n):
			var p2 := joint(b, n)
			if low == Vector3.INF or p2.y < low.y:
				low = p2
	return low

## Where part n's joint is in the world (its bone).
static func joint(b: VoxelBody, n: String) -> Vector3:
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(b.parts[n].bone)).origin

## Whether p (low on a body) is in the patch of fire at at (around it, at its height: not below a patch on a pillar).
static func in_patch(p: Vector3, at: Vector3) -> bool:
	var up := p.y - at.y
	return p != Vector3.INF and Vector2(p.x - at.x, p.z - at.z).length() <= PATCH_R + 0.1 and up > -0.3 and up < 0.7

## How hard a patch t seconds old burns: a whoomph at first, then steady, dying down over its last PATCH_FADE, 0 out.
static func blaze(t: float) -> float:
	if t >= PATCH_T:
		return 0.0
	return (1.0 + 0.5 * maxf(0.0, 1.0 - t / 0.4)) * clampf((PATCH_T - t) / PATCH_FADE, 0.0, 1.0)

## The velocity that lobs a blob from a to land on b in secs, g (m/s/s) pulling it down.
static func lob(a: Vector3, b: Vector3, g: float, secs: float) -> Vector3:
	var v := (b - a) / secs
	v.y += 0.5 * g * secs
	return v

## The tank after dt seconds: spraying empties it in FUEL_S; otherwise, once idle (seconds since it last sprayed) is
## past REFILL_DELAY, it fills at REFILL of that rate.
static func refuel(fuel: float, dt: float, spraying: bool, idle: float) -> float:
	if spraying:
		return maxf(0.0, fuel - dt / FUEL_S)
	if idle < REFILL_DELAY:
		return fuel
	return minf(1.0, fuel + dt / FUEL_S * REFILL)

# a grunt for the checks (stands at x facing +z)
static func _grunt(host: Node, m: Material, x: float = 0.0) -> VoxelBody:
	var b := VoxelBody.new()
	host.add_child(b)
	b.setup("grunt", 0.023, 1, m)
	b.position = Vector3(x, 0, 0)
	b.animate(0.0, false)
	return b

static func checks(host: Node) -> Array:
	var out := []
	var was := VoxelBody.immortal
	VoxelBody.immortal = false
	var m := StandardMaterial3D.new()
	# the stream from a nozzle at the hip 3 m in front, aimed at his chest: its drooping line reaches the chest
	var b := _grunt(host, m)
	var o := Vector3(0.2, 1.05, 3.0)
	var pts := arc(o, aim_dir(o, o, (Vector3(0, 1.0, 0) - o).normalized()))
	var t0 := Time.get_ticks_usec()
	var h := hit_along(b, pts)
	var tr_ms := (Time.get_ticks_usec() - t0) / 1000.0
	out.append([not h.is_empty() and String(h.get("part", "")) == "torso" and float(h.get("dist", 0.0)) > 2.6 and float(h.get("dist", 0.0)) < 3.1,
		"the stream from 3 m reaches his chest (%s at %.2f m, %.2f ms)" % [h.get("part", "-"), float(h.get("dist", 0.0)), tr_ms]])
	out.append([near_line(b, pts, SLACK) and not near_line(b, arc(o + Vector3(3, 0, 0), Vector3.FORWARD), SLACK),
		"the stream past him is near him, one 3 m off to the side isn't"])
	# set alight where it lands: cubes catch, he burns and panics
	t0 = Time.get_ticks_usec()
	var r := scorch(b, h.get("point", Vector3(0, 1, 0.15)), IGNITE_R, THAW * TICK)
	var ig_ms := (Time.get_ticks_usec() - t0) / 1000.0
	out.append([int(r.caught) > 10 and b.burning() and b.panic_t > 0.0 and not bool(r.thawed),
		"set alight where it lands: %d cubes catch (%.2f ms), he burns and panics" % [r.caught, ig_ms]])
	# more fire on him, burning already, catches more (before it spreads: a body burns BURN_MAX cubes at most)
	var hh := hit_along(b, arc(Vector3(0, 1.62, 2.0), Vector3.FORWARD))
	var r2 := scorch(b, hh.get("point", Vector3(0, 1.62, 0.1)), IGNITE_R, 0.0)
	out.append([b.burning() and int(r2.caught) > 0, "on fire already, a new spot (his face) catches more (%d)" % r2.caught])
	# it spreads by itself: in 3 s it has hurt him and burnt cubes to ash
	var hp0 := b.hp
	var left0 := b.cubes_left()
	var flames := 0
	for i in 26:
		var st: Dictionary = b.status_step(0.125)
		flames += (st.flames as Array).size()
	out.append([b.hp < hp0 - 15.0 and b.cubes_left() < left0 and flames > 20,
		"it spreads by itself: %.0f health and %d cubes burnt away in 3 s" % [hp0 - b.hp, left0 - b.cubes_left()]])
	b.queue_free()
	# out of reach: 8 m off, it doesn't get there; the line droops, the cone's ring is CONE out
	var b2 := _grunt(host, m)
	var far := arc(Vector3(0, 1.0, 8.0), Vector3.FORWARD)
	var a0 := arc(Vector3.ZERO, Vector3.FORWARD, REACH)
	var dirs := cone(Vector3.FORWARD, RAYS, CONE, 0.3)
	var ring := dirs.size() == RAYS
	for i in range(1, dirs.size()):
		ring = ring and absf(Vector3.FORWARD.angle_to(dirs[i]) - CONE) < 0.001
	out.append([hit_along(b2, far).is_empty() and -a0[a0.size() - 1].y > 0.25 and -a0[a0.size() - 1].y < 0.6 and ring,
		"8 m off the stream doesn't reach him; it droops %.2f m by 6 m; %d rays in its cone" % [-a0[a0.size() - 1].y, dirs.size()]])
	# top-down, from the hip: waist high close in, on the floor by the end of its reach
	var hip := Vector3(0, 1.05, 0)
	var td := arc(hip, aim_dir(hip, hip + Vector3.DOWN * TD_DIP, Vector3.FORWARD))
	var mid := arc(hip, aim_dir(hip, hip + Vector3.DOWN * TD_DIP, Vector3.FORWARD), 1.5, 1)
	out.append([td[td.size() - 1].y < 0.15 and td[td.size() - 1].y > -0.3 and mid[1].y > 0.6,
		"top-down the stream is %.2f m up 1.5 m out and %.2f m by its end (on the floor)" % [mid[1].y, td[td.size() - 1].y]])
	# frozen: nothing catches, the ice melts instead; kept on him a moment he thaws, then burns
	b2.chill(1.0)
	var hf := hit_along(b2, pts)
	var pf: Vector3 = hf.get("point", Vector3(0, 1, 0.15))
	var rf := scorch(b2, pf, IGNITE_R, THAW * TICK)
	out.append([b2.frozen() and bool(rf.thawed) and int(rf.caught) == 0 and not b2.burning() and b2.frozen_t < VoxelBody.FREEZE_T,
		"frozen: nothing catches, the ice melts instead (%.1f s of it left)" % b2.frozen_t])
	var ticks := 1
	while b2.frozen() and ticks < 100:
		scorch(b2, pf, IGNITE_R, THAW * TICK)
		b2.status_step(TICK)
		ticks += 1
	var rt := scorch(b2, pf, IGNITE_R, THAW * TICK)
	out.append([not b2.frozen() and ticks * TICK < 2.0 and int(rt.caught) > 0 and b2.burning(),
		"%.1f s of fire thaws him, then he burns (%d cubes)" % [ticks * TICK, rt.caught]])
	b2.queue_free()
	# the patch: it catches him low on the legs (both shins in turn), whoever's in it and nobody outside it
	var b3 := _grunt(host, m)
	var l0 := legs_point(b3, 0)
	var l1 := legs_point(b3, 1)
	var low := l0.y > 0.1 and l0.y < 0.45 and l1.y > 0.1 and l1.y < 0.45 and Vector2(l0.x, l0.z).length() < 0.3 and l0.distance_to(l1) > 0.08
	t0 = Time.get_ticks_usec()
	var rp := scorch(b3, l0, PATCH_IGNITE_R, 0.0)
	var pa_ms := (Time.get_ticks_usec() - t0) / 1000.0
	out.append([low and int(rp.caught) > 0 and in_patch(l0, Vector3(0.6, 0, 0.3)) and not in_patch(l0, Vector3(2.0, 0, 0))
		and not in_patch(l0, Vector3(0.6, 3.5, 0.3)),
		"a patch of fire catches his shins (at %.2f m, %d cubes, %.2f ms), not from 2 m off or up on a pillar" % [l0.y, rp.caught, pa_ms]])
	b3.queue_free()
	# it blazes up, burns, dies down, goes out
	out.append([blaze(0.0) > 1.2 and absf(blaze(2.0) - 1.0) < 0.001 and blaze(PATCH_T - 0.5) < 0.5 and blaze(PATCH_T) == 0.0,
		"a patch blazes up, burns %.0f s, dies down" % PATCH_T])
	# the lob lands where it was aimed
	var from := Vector3(0.2, 1.3, 6.0)
	var to := Vector3(1.5, 0.0, -3.0)
	var v := lob(from, to, BOMB_G, 0.9)
	var p := from
	for i in 54:
		v.y -= BOMB_G / 60.0
		p += v / 60.0
	out.append([p.distance_to(to) < 0.2, "a fire bomb lobbed 9 m lands where it was aimed (%.2f m off)" % p.distance_to(to)])
	# the fuel: 8 s of spray empties the tank; after a moment it refills at a third of that rate
	var f := 1.0
	for i in 480:
		f = refuel(f, 1.0 / 60.0, true, 0.0)
	var f2 := refuel(0.0, 1.0, false, REFILL_DELAY * 0.5)
	var f3 := 0.0
	for i in 24:
		f3 = refuel(f3, 1.0, false, REFILL_DELAY + i)
	out.append([f < 0.001 and f2 == 0.0 and f3 > 0.99, "8 s of spray empties the tank, it refills in %.0f s" % (FUEL_S / REFILL)])
	# the cost: five burning, the stream through them all
	var bs := []
	for i in 5:
		var bb := _grunt(host, m, -2.0 + i)
		var hb := hit_along(bb, arc(Vector3(-2.0 + i, 1.0, 2.0), Vector3.FORWARD))
		bb.ignite(hb.get("point", Vector3(-2.0 + i, 1.0, 0.15)), IGNITE_R)
		bs.append(bb)
	var step_ms := 0.0
	for k in 8:
		t0 = Time.get_ticks_usec()
		for bb in bs:
			bb.status_step(0.125)
		step_ms = maxf(step_ms, (Time.get_ticks_usec() - t0) / 1000.0)
	t0 = Time.get_ticks_usec()
	var traced := 0
	for dir in cone((Vector3(0, 1.0, 0) - Vector3(-2.5, 1.0, 1.0)).normalized(), RAYS, CONE, 0.0):
		var line := arc(Vector3(-2.5, 1.0, 1.0), dir, REACH)
		for bb in bs:
			if near_line(bb, line, SLACK):
				traced += 1
				hit_along(bb, line)
	var cone_ms := (Time.get_ticks_usec() - t0) / 1000.0
	out.append([step_ms < 40.0 and cone_ms < 40.0, "five burning: %.1f ms a fire step (every %.3f s); a hit test's cone through them %.1f ms (%d traced)" % [step_ms, VoxelBody.BURN_TICK, cone_ms, traced]])
	for bb in bs:
		bb.queue_free()
	VoxelBody.immortal = was
	return out
