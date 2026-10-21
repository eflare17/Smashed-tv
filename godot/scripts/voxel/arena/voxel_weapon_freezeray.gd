class_name VoxelWeaponFreezeray
extends VoxelMelee
## The freeze ray (the owner, 20 Oct: six new weapons, each doing something different): freeze them solid, then shatter
## them. A white and pale-blue sci-fi gun held at the hip: a glowing cyan tank on top, a coil round the barrel, a dish
## of frosty fins at the front. Hold left for the freeze beam: a flickering cyan-white beam from the dish to whatever
## you point at, a double helix of beads twisting round it, frost drifting off it and puffing where it lands, a cold
## light there, the tank glowing hard and the coil spinning. The body it's on frosts over (slower and slower, frost
## clinging round the spot) and after about three quarters of a second of steady beam (a bigger one longer, by its
## height) it freezes solid: an ice statue that stands still for 8 s and then thaws; the beam on one already frozen
## keeps it frozen. On the floor or a wall it leaves frost lying. The beam runs on a charge, 6 s of it, that fills back
## up once you let go (a glowing strip down the gun's side and the weapon bar show it); run it dry and it vents and must
## fill a quarter back before it fires again. Right click fires an ice shard (one every 0.55 s; held, again and again; a
## new one grows in the dish meanwhile): a long pale-blue crystal flying at 40 m/s with a faint trail. Into a frozen
## body it SHATTERS it: the whole statue bursts into ice cubes along the shard's line and out, with a big kick and a
## hit-stop, and the shard flies on through for the next. Into one not frozen it knocks a small hole, chills it a third
## of the way to frozen and shoves it, and sticks in a moment before it melts. Into the world it breaks into ice bits
## with a tink. Any other weapon's blow shatters a frozen body too (VoxelBody does that). Top-down the beam and the
## shards go level from Jared's chest toward the mouse. The core (what the beam or a shard hits, a beam's chill, a
## shard's strike, the charge) is static so the logic test can run it. Owned by the voxel session.

const RANGE := 16.0             # metres the beam reaches
const FREEZE_S := 0.75          # seconds of steady beam that freeze a grunt solid (taller ones longer, by height squared)
const BEAM_V := 90.0            # m/s the beam shoots out to what it hits (frost only once it gets there)
const ENERGY := 6.0             # seconds of beam a full charge
const RECHARGE := 2.0           # seconds of beam charged back a second ...
const RECHARGE_WAIT := 0.4      # ... from this long after you let go
const RESTART := 0.25           # run dry: the share of a full charge it must fill back before it fires again
const SHARD_CD := 0.55          # seconds between shards
const SHARD_V := 40.0           # m/s
const SHARD_G := 1.5            # m/s/s pulling it down (first person; top-down it flies level)
const SHARD_LIFE := 1.6         # seconds in the air before it's gone
const SHARD_R := 0.045          # the hole a shard knocks in a body not frozen, metres ...
const SHARD_DEPTH := 0.07       # ... this deep
const SHARD_CHILL := 0.3        # frost a shard puts on (four freeze a grunt)
const SHARD_SHOVE := 0.4        # m/s it shoves one back (on top of the hit's own)
const SHARD_SLOW := 0.85        # its speed kept through a statue it shatters
const SHATTER_POWER := 5.5      # how hard a shattered statue's cubes fly
const STICK_T := 1.1            # seconds stuck in a body before it melts ...
const MELT_T := 0.7             # ... over this long
const MAX_SHARDS := 8
const MAX_P := 1400             # frost particles at once
const HELIX := 240              # beads in the beam's twisting double helix (both strands)
const TD := 1.8                 # top-down: shards, beam and frost this much bigger (seen from up high)
const EMIT := Vector3(0, 0.034, 0.37)       # the dish's middle, weapon space (where the beam and shards leave)
const VENT := Vector3(-0.04, 0.05, 0.13)    # the vents (the gun's right side)
# the view's poses, camera space (x right, y up, -z forward): the grip at the hip, turned in a little toward the middle
const REST := Vector3(0.25, -0.3, -0.42)
const REST_ROT := Vector3(0.05, 0.08, 0.0)
const FIRE_AT := Vector3(0.21, -0.27, -0.47)
const FIRE_ROT := Vector3(0.08, 0.11, -0.06)
const WHITE := Color(0.8, 0.84, 0.88)
const PALE := Color(0.48, 0.7, 0.92)
const DARK := Color(0.15, 0.17, 0.21)
const CYAN := Color(0.3, 0.88, 1.0)
const FROST := Color(0.8, 0.92, 1.0)
const ICE_COL := Color(0.72, 0.88, 1.0)

var _gun: Node3D                # first person: the gun (its grip at the origin), posed under view
var _gun_m: Node3D              # ... its boxes, turned to face -z
var _coils: Array = []          # the coil's rings (spin while firing), the view's
var _crystal: Node3D            # the next shard growing in the dish (view)
var _mflare: MeshInstance3D     # the glow in the dish while the beam is on (view)
var _gauge: Node3D              # the charge left, a glowing strip down the gun's side (view)
var _hand: Node3D               # top-down: the gun in Jared's hand (the arena frees it on a switch)
var _hand_emit: Node3D          # ... its dish
var _hand_coils: Array = []
var _m_tank: StandardMaterial3D
var _m_coil: StandardMaterial3D
var _m_fin: StandardMaterial3D
var _m_shard: StandardMaterial3D
var _core: MeshInstance3D       # the beam (world): a thin bright box ...
var _glow: MeshInstance3D       # ... in a wider see-through one
var _flare: MeshInstance3D      # the glare where it lands
var _helix: MultiMeshInstance3D # beads twisting round it
var _hit_light: OmniLight3D
var _muz_light: OmniLight3D
var _out := false               # the weapon out (not put away)
var _held_l := false
var _beam_on := false
var _beam_k := 0.0              # the beam's strength shown, 0..1 (eases in and out)
var _beam_len := 0.0            # metres the beam reaches now (shooting out to what it hits)
var _beam_t := 0.0
var _twist := 0.0
var _energy := ENERGY
var _idle := 0.0                # seconds since the beam was last on
var _locked := false            # run dry: no beam till it's a quarter back
var _vent := 0.0                # 1 just ran dry, venting, fading
var _fire_k := 0.0              # the view going from the hip to firing, 0..1
var _frosted := 0.0             # the dish's fins frosting over while it fires, 0..1
var _cd := 0.0                  # seconds till the next shard
var _kick := 0.0                # a shard's kick, 1 .. 0
var _kick_s := 0.0              # ... smoothed (a quick rise, an eased fall)
var _clock := 0.0
var _snd_hum := false
var _snd_crackle := false
var _froze_n := 0
var _trace_us := 0              # the beam's traces this press (for last)
var _trace_n := 0
var _shards: Array = []         # [{node, model, trail, mode: "" / "fly" / "stuck" / "melt", st, vis, t, body, part, bone, local, drip}]
# frost particles: one MultiMesh, little white and pale-blue cubes
var _parts: MultiMeshInstance3D
var _pp := PackedVector3Array()
var _pv := PackedVector3Array()
var _pl := PackedFloat32Array()  # life left
var _ps := PackedFloat32Array()  # life it started with
var _pz := PackedFloat32Array()  # size, metres
var _pg := PackedFloat32Array()  # gravity
var _pd := PackedFloat32Array()  # drag
var _pc := PackedColorArray()
var _pr: Array[Basis] = []
var _pn := 0
var _fx_us := 0                 # the frost particles' time this press (for last)
var _fx_frames := 0

func _build() -> void:
	_m_tank = mat(CYAN, 0.0, 0.3, 1.2)
	_m_coil = mat(CYAN.lightened(0.2), 0.3, 0.3, 1.5)
	_m_fin = mat(FROST, 0.2, 0.3)
	_m_shard = mat(ICE_COL, 0.1, 0.12, 0.7)
	_gun = Node3D.new()
	_gun.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # posed every frame
	view.add_child(_gun)
	_gun_m = Node3D.new()
	_gun_m.rotation = Vector3(0, PI, 0)           # weapon space's +z (the barrel) toward the camera's -z
	_gun.add_child(_gun_m)
	var mp := _model(_gun_m, false)
	_coils = mp.coils
	_crystal = mp.crystal
	_gauge = mp.gauge
	_mflare = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3.ONE
	_mflare.mesh = fm
	_mflare.material_override = _add_mat(Color(0.6, 0.95, 1.0), 1.0)
	_mflare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mflare.position = EMIT + Vector3(0, 0, 0.012)
	_mflare.visible = false
	_gun_m.add_child(_mflare)
	_gun.position = REST
	_gun.rotation = REST_ROT
	# the beam, its glare and lights: in the world
	_core = _world_box(_add_mat(Color(0.85, 1.0, 1.0), 1.0))
	_glow = _world_box(_add_mat(Color(0.25, 0.7, 1.0), 0.45))
	_flare = _world_box(_add_mat(Color(0.6, 0.9, 1.0), 0.8))
	_helix = MultiMeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3.ONE
	hm.material = _add_mat(Color(0.65, 0.95, 1.0), 0.9)
	_helix.multimesh = MultiMesh.new()
	_helix.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_helix.multimesh.mesh = hm
	_helix.multimesh.instance_count = HELIX
	_helix.multimesh.visible_instance_count = 0
	_helix.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_helix.top_level = true
	add_child(_helix)
	_hit_light = _light(Color(0.5, 0.82, 1.0), 3.0)
	_muz_light = _light(Color(0.45, 0.85, 1.0), 1.4)
	for i in MAX_SHARDS:
		var node := Node3D.new()
		node.top_level = true
		node.visible = false
		add_child(node)
		var model := Node3D.new()
		node.add_child(model)
		crystal_model(model, _m_shard)
		var trail := _world_box(_add_mat(Color(0.45, 0.75, 1.0), 0.3))
		_shards.append({"node": node, "model": model, "trail": trail, "mode": ""})
	# frost: one draw call
	_parts = MultiMeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3.ONE
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.vertex_color_use_as_albedo = true
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.material = pmat
	_parts.multimesh = MultiMesh.new()
	_parts.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_parts.multimesh.use_colors = true
	_parts.multimesh.mesh = pm
	_parts.multimesh.instance_count = MAX_P
	_parts.multimesh.visible_instance_count = 0
	_parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parts.top_level = true
	add_child(_parts)
	_pp.resize(MAX_P)
	_pv.resize(MAX_P)
	_pl.resize(MAX_P)
	_ps.resize(MAX_P)
	_pz.resize(MAX_P)
	_pg.resize(MAX_P)
	_pd.resize(MAX_P)
	_pc.resize(MAX_P)
	_pr.resize(MAX_P)

# the gun's boxes under root, weapon space (the grip at the origin, the barrel toward +z, its top +y), metres; light:
# a little brighter, for top-down. Returns {coils, crystal, gauge}.
func _model(root: Node3D, light: bool) -> Dictionary:
	var white := mat(WHITE.lightened(0.1) if light else WHITE, 0.1, 0.55)
	var pale := mat(PALE.lightened(0.12) if light else PALE, 0.2, 0.35)
	var dark := mat(DARK.lightened(0.2) if light else DARK, 0.4, 0.5)
	# the grip, trigger and guard
	box(root, Vector3(0.034, 0.1, 0.045), Vector3(0, -0.048, -0.008), dark, Vector3(0.28, 0, 0))
	box(root, Vector3(0.01, 0.026, 0.012), Vector3(0, -0.014, 0.034), dark, Vector3(-0.3, 0, 0))
	box(root, Vector3(0.014, 0.008, 0.07), Vector3(0, -0.04, 0.035), pale)
	# the body: white, a pale stripe down each side, a cap at the back, vents on the side
	box(root, Vector3(0.076, 0.072, 0.25), Vector3(0, 0.034, 0.075), white)
	box(root, Vector3(0.08, 0.02, 0.21), Vector3(0, 0.018, 0.08), pale)
	box(root, Vector3(0.07, 0.066, 0.03), Vector3(0, 0.034, -0.06), pale)
	for i in 3:
		box(root, Vector3(0.082, 0.006, 0.05), Vector3(0, 0.044 + 0.012 * i, 0.13), dark)
	# the tank on top, glowing, held by white bands, its feed into the barrel
	box(root, Vector3(0.048, 0.048, 0.16), Vector3(0, 0.1, 0.06), _m_tank)
	for z in [-0.005, 0.06, 0.125]:
		box(root, Vector3(0.058, 0.058, 0.014), Vector3(0, 0.1, z), white)
	box(root, Vector3(0.05, 0.05, 0.012), Vector3(0, 0.1, -0.024), pale)
	box(root, Vector3(0.026, 0.026, 0.004), Vector3(0, 0.1, -0.031), _m_coil)
	box(root, Vector3(0.05, 0.05, 0.012), Vector3(0, 0.1, 0.144), pale)
	# the charge left: a glowing strip down the left side, shorter as it runs down (its back end fixed)
	box(root, Vector3(0.004, 0.016, 0.19), Vector3(0.039, 0.052, 0.075), dark)
	var gauge := Node3D.new()
	gauge.position = Vector3(0.041, 0.052, -0.017)
	root.add_child(gauge)
	box(gauge, Vector3(0.004, 0.009, 0.18), Vector3(0, 0, 0.09), _m_coil)
	box(root, Vector3(0.014, 0.034, 0.014), Vector3(0, 0.075, 0.155), dark)
	# the barrel, the coil round it (rings that spin), a foregrip under it
	box(root, Vector3(0.042, 0.042, 0.17), Vector3(0, 0.034, 0.27), pale)
	var coils := []
	for i in 4:
		var c := Node3D.new()
		c.position = Vector3(0, 0.034, 0.215 + 0.03 * i)
		c.rotation.z = PI / 4.0 * float(i % 2)
		root.add_child(c)
		box(c, Vector3(0.056, 0.056, 0.012), Vector3.ZERO, _m_coil)
		coils.append(c)
	box(root, Vector3(0.028, 0.055, 0.034), Vector3(0, -0.018, 0.22), pale)
	# the dish: a frosty plate, four fins flaring out in an X, the emitter in the middle, the next shard growing there
	var dish := Node3D.new()
	dish.position = Vector3(0, 0.034, 0.35)
	root.add_child(dish)
	box(dish, Vector3(0.07, 0.07, 0.014), Vector3.ZERO, _m_fin, Vector3(0, 0, PI / 4.0))
	for i in 4:
		var piv := Node3D.new()
		piv.rotation.z = PI / 2.0 * i + PI / 4.0
		dish.add_child(piv)
		box(piv, Vector3(0.01, 0.05, 0.055), Vector3(0, 0.05, 0.012), _m_fin, Vector3(0.5, 0, 0))
	box(dish, Vector3(0.03, 0.03, 0.01), Vector3(0, 0, 0.009), _m_coil)
	var crystal := Node3D.new()
	crystal.position = Vector3(0, 0, 0.012)
	crystal.rotation = Vector3(0, PI, 0)             # its point toward +z, out of the dish
	dish.add_child(crystal)
	box(crystal, Vector3(0.014, 0.014, 0.05), Vector3(0, 0, -0.025), _m_shard, Vector3(0, 0, PI / 4.0))
	box(crystal, Vector3(0.007, 0.007, 0.02), Vector3(0, 0, -0.058), _m_shard, Vector3(0, 0, PI / 4.0))
	return {"coils": coils, "crystal": crystal, "gauge": gauge}

## An ice shard's boxes under parent, its point at the origin toward -z (the way it flies), metres.
static func crystal_model(parent: Node3D, m: Material) -> void:
	var edge := VoxelMelee.mat(Color(0.95, 0.99, 1.0), 0.0, 0.1, 1.2)
	var q := Vector3(0, 0, PI / 4.0)
	VoxelMelee.box(parent, Vector3(0.022, 0.022, 0.15), Vector3(0, 0, 0.115), m, q)
	VoxelMelee.box(parent, Vector3(0.015, 0.015, 0.05), Vector3(0, 0, 0.03), m, q)
	VoxelMelee.box(parent, Vector3(0.007, 0.007, 0.025), Vector3(0, 0, 0.008), m, q)
	VoxelMelee.box(parent, Vector3(0.013, 0.013, 0.04), Vector3(0, 0, 0.205), m, q)
	VoxelMelee.box(parent, Vector3(0.011, 0.011, 0.06), Vector3(0.011, 0.006, 0.15), m, Vector3(0.0, 0.3, PI / 4.0))
	VoxelMelee.box(parent, Vector3(0.009, 0.009, 0.045), Vector3(-0.009, -0.008, 0.17), m, Vector3(0.0, -0.35, PI / 4.0))
	VoxelMelee.box(parent, Vector3(0.004, 0.004, 0.14), Vector3(0, 0.0145, 0.11), edge)

# an unshaded glowing material, added on top of what's behind (alpha: how strongly)
static func _add_mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _world_box(m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	add_child(mi)
	return mi

func _light(col: Color, r: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = r
	l.light_energy = 0.0
	l.top_level = true
	add_child(l)
	return l

func hand_mesh() -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var inner := Node3D.new()
	inner.scale = Vector3.ONE * 1.4
	inner.position = Vector3(0, 0, -0.02)
	root.add_child(inner)
	var mp := _model(inner, true)
	_hand_coils = mp.coils
	(mp.crystal as Node3D).visible = false
	(mp.gauge as Node3D).visible = false
	_hand_emit = Node3D.new()
	_hand_emit.position = EMIT
	inner.add_child(_hand_emit)
	_hand = root
	return root

func hand_pose() -> String:
	return "shotgun"                # at the hip, both hands on it

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var a := col.a
	var glow := 0.45 + 0.55 * _energy / ENERGY
	var white := Color(WHITE.r, WHITE.g, WHITE.b, a)
	var pale := Color(PALE.r, PALE.g, PALE.b, a)
	var dark := Color(0.3, 0.32, 0.38, a)
	var cyan := Color(CYAN.r * glow, CYAN.g * glow, CYAN.b * glow, a)
	for e in [[Rect2(1.5, 2.7, 1.1, 1.9), dark], [Rect2(0.5, 1.6, 5.0, 1.3), white], [Rect2(0.7, 2.25, 4.6, 0.35), pale],
			[Rect2(1.3, 0.75, 3.0, 0.8), cyan], [Rect2(1.2, 0.65, 0.3, 1.0), white], [Rect2(2.65, 0.65, 0.3, 1.0), white],
			[Rect2(4.1, 0.65, 0.3, 1.0), white], [Rect2(5.5, 1.85, 2.3, 0.8), pale], [Rect2(5.8, 1.6, 0.3, 1.3), cyan],
			[Rect2(6.5, 1.6, 0.3, 1.3), cyan], [Rect2(7.2, 1.6, 0.3, 1.3), cyan], [Rect2(7.8, 1.0, 0.45, 2.8), pale],
			[Rect2(8.25, 0.55, 0.9, 0.5), pale], [Rect2(8.25, 3.75, 0.9, 0.5), pale], [Rect2(8.25, 1.95, 0.45, 0.6), cyan]]:
		ci.draw_rect(Rect2(r.position + (e[0] as Rect2).position * u, (e[0] as Rect2).size * u), e[1])

# ---------------------------------------------------------------- the buttons

func on_select() -> void:
	_out = true

func on_deselect() -> void:
	_out = false
	_held_l = false
	if _beam_on:
		_stop_beam()

## Run dry: the bar's slot edge fills as it charges back up to a quarter; otherwise the shard's cooldown.
func cooling() -> float:
	if _locked:
		return clampf(1.0 - _energy / (ENERGY * RESTART), 0.0, 1.0)
	return clampf(_cd / SHARD_CD, 0.0, 1.0)

func bar_text() -> String:
	return "%d%%" % roundi(100.0 * _energy / ENERGY)

func press(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_held_l = true
		_trace_us = 0
		_trace_n = 0
		_froze_n = 0
		_fx_us = 0
		_fx_frames = 0
		_beam_t = 0.0
		last = {"move": "beam", "secs": 0.0, "energy": 0, "on": "", "frost": 0.0, "frozen": 0, "trace_ms": 0.0, "max_ms": 0.0, "fx_ms": 0.0}
		if _locked:
			sfx("dry_fire")
	elif button == MOUSE_BUTTON_RIGHT:
		fire_shard()

func hold(button: int, _dt: float) -> void:
	if button == MOUSE_BUTTON_RIGHT and _cd <= 0.0:
		fire_shard()

func release(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_held_l = false

# ---------------------------------------------------------------- the core (static, for the checks)

## The beam's charge after dt (static, for the checks): drained while firing, charging back RECHARGE_WAIT after.
static func charge(e: float, firing: bool, idle: float, dt: float) -> float:
	if firing:
		return maxf(0.0, e - dt)
	if idle >= RECHARGE_WAIT:
		return minf(ENERGY, e + RECHARGE * dt)
	return e

## What a ray from `from` along dir runs into first within max_d (static, for the checks): a body ({body, part, cell,
## point, normal, dist}: its trace), the world ({point, normal, dist}; space: the physics space, or null for just the
## floor) or nothing ({}).
static func beam_target(bodies: Array, from: Vector3, dir: Vector3, max_d: float, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> Dictionary:
	var best := {}
	var best_d := max_d
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_d, 1)
		q.exclude = exclude
		var wh := space.intersect_ray(q)
		if not wh.is_empty():
			var wp: Vector3 = wh.position
			best_d = from.distance_to(wp)
			best = {"point": wp, "normal": wh.normal, "dist": best_d}
	elif dir.y < -0.0001 and from.y > 0.0 and from.y / -dir.y < best_d:
		best_d = from.y / -dir.y
		best = {"point": from + dir * best_d, "normal": Vector3.UP, "dist": best_d}
	for b in bodies:
		if not is_instance_valid(b):
			continue
		var h: Dictionary = b.trace(from, dir, best_d)
		if h.is_empty():
			continue
		var d: float = h.dist
		if d < best_d:
			best_d = d
			best = h
			best["body"] = b
	return best

## Frost a second the beam puts on b (static, for the checks): a grunt frozen solid after FREEZE_S of it, a taller one
## longer (by height squared), the frost's own fading made up for.
static func chill_rate(b: VoxelBody) -> float:
	var k := clampf(b.height / 1.85, 0.6, 2.0)
	return 1.0 / (FREEZE_S * k * k) + VoxelBody.FROST_FADE

## dt seconds of beam on body b (static, for the checks): the frost builds up; on one frozen already it keeps it frozen.
## True if it froze solid now.
static func beam_tick(b: VoxelBody, dt: float) -> bool:
	if b.frozen():
		b.frozen_t = VoxelBody.FREEZE_T
		return false
	return b.chill(chill_rate(b) * dt)

## An ice shard into body b at `at` (world), flying along dir (static, for the checks). Frozen: it shatters
## (VoxelBody.shatter: every cube flies, dead). Not: a small hole (carve), then SHARD_CHILL of frost. Returns the
## shatter's or carve's result, with "froze": that frost froze it solid.
static func shard_strike(b: VoxelBody, at: Vector3, dir: Vector3) -> Dictionary:
	if b.frozen():
		var sh := b.shatter()
		sh["froze"] = false
		return sh
	var res := b.carve(at - dir * 0.015, at + dir * SHARD_DEPTH, SHARD_R, 0.08, 1)
	res["froze"] = b.chill(SHARD_CHILL)
	return res

## A shard's flight (static, for the checks): {p (world), v, g (gravity), t (seconds up), dist (metres flown), hit:
## {body id: true} (the statues it has gone through)}.
static func shard_state(p: Vector3, v: Vector3, g: float) -> Dictionary:
	return {"p": p, "v": v, "g": g, "t": 0.0, "dist": 0.0, "hit": {}}

## One step of a shard (static, for the checks): it moves dt along its path, or up to what it runs into on the way
## (beam_target's result, the bodies it has gone through passed over), which it returns ({} for nothing).
static func shard_fly(st: Dictionary, dt: float, bodies: Array, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> Dictionary:
	var p0: Vector3 = st.p
	var v: Vector3 = st.v
	var p1 := p0 + v * dt
	var seg := p0.distance_to(p1)
	var seen: Dictionary = st.hit
	var near := []
	for b in bodies:
		if is_instance_valid(b) and not seen.has(b.get_instance_id()):
			near.append(b)
	var h := beam_target(near, p0, (p1 - p0) / maxf(seg, 0.000001), seg, space, exclude)
	v.y -= float(st.g) * dt
	st.v = v
	st.t = float(st.t) + dt
	if h.is_empty():
		st.p = p1
		st.dist = float(st.dist) + seg
	else:
		st.p = h.point
		st.dist = float(st.dist) + float(h.dist)
	return h

## -z along d (a shard's point the way it flies), up kept up.
static func dir_basis(d: Vector3) -> Basis:
	if d.length_squared() < 0.000001:
		return Basis()
	var n := d.normalized()
	return Basis.looking_at(n, Vector3.UP if absf(n.y) < 0.98 else Vector3.BACK)

# ---------------------------------------------------------------- every frame

func step(dt: float) -> void:
	_clock += dt
	_cd = maxf(0.0, _cd - dt)
	_kick = maxf(0.0, _kick - dt * 4.5)
	_kick_s = lerpf(_kick_s, _kick, 1.0 - exp(-dt * 40.0))
	_vent = maxf(0.0, _vent - dt * 0.8)
	_beam_step(dt)
	for s in _shards:
		if String(s.mode) != "":
			_shard_step(s, dt)
	if _vent > 0.0 and randf() < _vent:
		var vp := _vent_world()
		var fr := frame()
		_emit(vp, fr.x * randf_range(-0.6, -0.2) + Vector3.UP * randf_range(0.2, 0.6), randf_range(0.012, 0.024), randf_range(0.4, 0.8), Color(0.92, 0.97, 1.0), -0.3, 2.0)
	_pose_view(dt)
	_pose_hand(dt)
	var t0 := Time.get_ticks_usec()
	_parts_step(dt)
	_fx_us += Time.get_ticks_usec() - t0
	_fx_frames += 1

func _beam_step(dt: float) -> void:
	var want := _out and _held_l and not _locked and _energy > 0.0
	if want and not _beam_on:
		_start_beam()
	elif not want and _beam_on:
		_stop_beam()
	if _beam_on:
		_idle = 0.0
		_beam_t += dt
		_energy = charge(_energy, true, 0.0, dt)
		if _energy <= 0.0:
			_locked = true
			_vent = 1.0
			_stop_beam()
			sfx("dry_fire")
	else:
		_idle += dt
		_energy = charge(_energy, false, _idle, dt)
		if _locked and _energy >= ENERGY * RESTART:
			_locked = false
	_beam_k = move_toward(_beam_k, 1.0 if _beam_on else 0.0, dt / (0.06 if _beam_on else 0.14))
	_fire_k = move_toward(_fire_k, 1.0 if _beam_on else 0.0, dt / 0.15)
	_frosted = clampf(_frosted + dt * (0.35 if _beam_on else -0.12), 0.0, 1.0)
	var on_body := false
	var a: Array = shooter.aim() if _beam_k > 0.0 else []
	if a.is_empty():
		_beam_hide()
	else:
		on_body = _beam_draw(a[0], a[1], dt)
	if _beam_on:
		sfx_loop("hum", "freezeray_loop", -5.0 + (1.5 if on_body else 0.0), 1.0 + 0.02 * sin(_clock * 3.1) + (0.05 if on_body else 0.0))
		_snd_hum = true
	elif _snd_hum:
		sfx_stop("hum")
		_snd_hum = false
	if on_body:
		sfx_loop("crackle", "freezeray_crackle_loop", -7.0)
		_snd_crackle = true
	elif _snd_crackle:
		sfx_stop("crackle")
		_snd_crackle = false
	if _beam_on and top_down():
		shooter.avatar.recoil = maxf(float(shooter.avatar.recoil), randf_range(0.1, 0.25))     # the gun buzzing in his hands
	if _held_l and _beam_last():
		last.secs = snappedf(_beam_t, 0.01)
		last.energy = roundi(100.0 * _energy / ENERGY)
		if _trace_n > 0:
			last.trace_ms = snappedf(_trace_us / 1000.0 / _trace_n, 0.01)
		last.fx_ms = snappedf(_fx_us / 1000.0 / maxi(1, _fx_frames), 0.01)

func _start_beam() -> void:
	_beam_on = true
	_beam_len = 0.0
	sfx("freezeray_start")

func _stop_beam() -> void:
	_beam_on = false
	sfx("freezeray_stop")

func _beam_hide() -> void:
	for n in [_core, _glow, _flare]:
		(n as Node3D).visible = false
	_helix.multimesh.visible_instance_count = 0
	_hit_light.light_energy = 0.0
	_muz_light.light_energy = 0.0
	_mflare.visible = false

# the beam this frame from the dish to what the aim (from, along dir) hits: traced, frost put on, drawn. True if it's on
# a body.
func _beam_draw(from: Vector3, dir: Vector3, dt: float) -> bool:
	var hit := {}
	var dist := _beam_len           # (let go: it fades where it was)
	if _beam_on:
		var t0 := Time.get_ticks_usec()
		var ex: Array[RID] = shooter.exclude()
		hit = beam_target(arena.bodies, from, dir, RANGE, arena.get_world_3d().direct_space_state, ex)
		var us := Time.get_ticks_usec() - t0
		_trace_us += us
		_trace_n += 1
		if _beam_last():
			last.max_ms = maxf(float(last.max_ms), snappedf(us / 1000.0, 0.01))
		dist = RANGE if hit.is_empty() else float(hit.dist)
		_beam_len = minf(_beam_len + BEAM_V * dt, dist)
	var reached := _beam_on and not hit.is_empty() and _beam_len >= dist - 0.001
	var end := from + dir * _beam_len
	var start := _emit_world(from, dir)
	var td := TD if top_down() else 1.0
	var k := _beam_k
	# the beam: a thin bright box in a wider see-through one, both twisting about the line, flickering
	_twist += dt * 7.0
	var ln := start.distance_to(end)
	if ln > 0.01:
		var z := (end - start) / ln
		var u := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
		var v := z.cross(u)
		var mid := (start + end) * 0.5
		var wc := (0.013 + 0.006 * randf()) * k * td
		var wg := (0.05 + 0.015 * sin(_clock * 41.0) + 0.012 * randf()) * k * td
		_core.global_transform = Transform3D(_twisted(u, v, z, _twist, wc, ln), mid)
		_glow.global_transform = Transform3D(_twisted(u, v, z, -_twist * 0.6, wg, ln), mid)
		_core.visible = true
		_glow.visible = true
		# two strands of beads winding round it, turning as they go
		var mm := _helix.multimesh
		var nb := mini(int(ln / (0.035 * td)), HELIX / 2)
		var hr := 0.022 * td * k
		var bead := Basis.IDENTITY * (0.009 * td * k)
		for j in 2:
			for i in nb:
				var sd := (float(i) + 0.5) / float(nb)
				var ha := sd * ln / (0.3 * td) * TAU - _twist * 1.6 + PI * j
				mm.set_instance_transform(j * nb + i, Transform3D(bead, start.lerp(end, sd) + (u * cos(ha) + v * sin(ha)) * hr))
		mm.visible_instance_count = nb * 2
		# frost drifting off it in a loose twist round the line, sinking a little (the cold air)
		var n := int(260.0 * k * dt * clampf(ln / 4.0, 0.4, 2.0) + randf())
		for i in n:
			var s := randf()
			var ang := _twist * 2.0 + s * ln * 9.0
			var off := (u * cos(ang) + v * sin(ang)) * randf_range(0.01, 0.035) * td
			_emit(start.lerp(end, s) + off, off.normalized() * randf_range(0.05, 0.25) + Vector3.DOWN * randf_range(0.05, 0.2),
				randf_range(0.007, 0.016) * td, randf_range(0.45, 0.9), _frost_col(), 0.0, 1.5)
	else:
		_core.visible = false
		_glow.visible = false
		_helix.multimesh.visible_instance_count = 0
	# the dish's glow, a light there
	_mflare.visible = not top_down() and k > 0.0
	_mflare.scale = Vector3.ONE * (0.03 + 0.02 * randf()) * k
	_mflare.rotation.z = randf() * TAU
	_muz_light.global_position = start
	_muz_light.light_energy = 0.9 * k * randf_range(0.8, 1.1)
	if not reached:
		_flare.visible = false
		_hit_light.light_energy = 0.0
		if _beam_on and hit.is_empty() and _beam_last():
			last.on = "nothing"
		return false
	# where it lands: a glare, a cold light, frost puffing out
	var nrm: Vector3 = hit.normal
	_flare.visible = true
	_flare.global_transform = Transform3D(Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU).scaled(Vector3.ONE * randf_range(0.05, 0.09) * td), end - dir * 0.01)
	_hit_light.global_position = end + nrm * 0.25
	_hit_light.light_energy = 2.2 * randf_range(0.8, 1.15)
	var puffs := int(110.0 * dt + randf())
	for i in puffs:
		_emit(end, (nrm * randf_range(0.3, 1.1) + _rand_dir() * 0.45) * td, randf_range(0.01, 0.024) * td, randf_range(0.3, 0.6), _frost_col(), 0.4, 4.0)
	if hit.has("body"):
		var b: VoxelBody = hit.body
		var froze := beam_tick(b, dt)
		# frost clinging round the spot, spreading wider and thicker the nearer frozen
		var fr: float = 1.0 if b.frozen() else b.frost
		var cling := int((30.0 + 110.0 * fr) * dt + randf())
		var cu := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
		var cv := dir.cross(cu)
		for i in cling:
			var ca := randf() * TAU
			var cr := sqrt(randf()) * (0.03 + 0.3 * fr * fr)
			_emit(end + (cu * cos(ca) + cv * sin(ca)) * cr - dir * randf_range(0.0, 0.05), _rand_dir() * 0.02, randf_range(0.01, 0.022) * td,
				randf_range(0.7, 1.4), Color(0.95, 0.98, 1.0), 0.0, 6.0)
		if froze:
			_froze(b)
		if _beam_last():
			last.on = "body"
			last.frost = snappedf(fr, 0.01)
		return true
	# the floor or a wall: frost lying there a while
	if randf() < 30.0 * dt:
		var tg := nrm.cross(Vector3.RIGHT if absf(nrm.x) < 0.9 else Vector3.UP).normalized()
		var bt := nrm.cross(tg)
		var at := end + nrm * 0.006 + (tg * randf_range(-1, 1) + bt * randf_range(-1, 1)) * 0.09 * td
		_emit(at, Vector3.ZERO, randf_range(0.016, 0.03) * td, randf_range(2.0, 3.0), Color(0.86, 0.94, 1.0), 0.0, 0.0)
	if _beam_last():
		last.on = "world"
	return false

func _beam_last() -> bool:
	return String(last.get("move", "")) == "beam"

static func _twisted(u: Vector3, v: Vector3, z: Vector3, ang: float, w: float, ln: float) -> Basis:
	var c := cos(ang)
	var s := sin(ang)
	return Basis((u * c + v * s) * w, (v * c - u * s) * w, z * ln)

# a body just frozen solid: the freeze sound, frost bursting off it all over
func _froze(b: VoxelBody) -> void:
	_froze_n += 1
	if _beam_last():
		last.frozen = _froze_n
	sfx("freeze", b.global_position + Vector3.UP)
	var td := TD if top_down() else 1.0
	for i in 110:
		var p := b.global_position + Vector3(randf_range(-0.3, 0.3), randf() * b.height, randf_range(-0.3, 0.3))
		var o := Vector3(p.x - b.global_position.x, 0.0, p.z - b.global_position.z)
		_emit(p, (o.normalized() * randf_range(0.3, 0.9) + Vector3.UP * randf_range(0.0, 0.5)) * td, randf_range(0.012, 0.028) * td,
			randf_range(0.5, 1.0), _frost_col(), 0.3, 2.5)
	shooter.kick = maxf(float(shooter.kick), 0.4)
	hit_stop(0.05, 0.25)

# where the beam and shards leave from: the dish (first person; top-down the dish in Jared's hand, or his chest)
func _emit_world(from: Vector3, dir: Vector3) -> Vector3:
	if top_down():
		if is_instance_valid(_hand_emit) and _hand_emit.is_inside_tree():
			return _hand_emit.global_position
		return from + dir * 0.45
	return _gun_m.global_transform * EMIT

func _vent_world() -> Vector3:
	if top_down():
		if is_instance_valid(_hand_emit) and _hand_emit.is_inside_tree():
			return _hand_emit.global_position
		return shooter.player.global_position + Vector3(0, 1.1, 0)
	return _gun_m.global_transform * VENT

# ---------------------------------------------------------------- the shards

## An ice shard where you look (top-down: level toward the mouse), if its cooldown is done.
func fire_shard() -> void:
	if _cd > 0.0 or not _out:
		return
	var a: Array = shooter.aim()
	if a.is_empty():
		return
	_cd = SHARD_CD
	var from: Vector3 = a[0]
	var f: Vector3 = a[1]
	var s := _free_shard()
	var start := from + f * 0.45
	var vis := Vector3.ZERO
	var td := top_down()
	if not td:
		# its path is the eye's line; it's drawn leaving the dish, closing onto the path
		var em := _gun_m.global_transform * EMIT
		start = from + f * clampf((em - from).dot(f), 0.3, 1.2)
		vis = em - start
		vis -= f * vis.dot(f)
	s.st = shard_state(start, f * SHARD_V, 0.0 if td else SHARD_G)
	s.mode = "fly"
	s.vis = vis
	s.t = 0.0
	(s.model as Node3D).scale = Vector3.ONE * (TD if td else 1.0)
	(s.node as Node3D).global_transform = Transform3D(dir_basis(f), start + vis)
	(s.node as Node3D).visible = true
	_kick = 1.0
	shooter.kick = maxf(float(shooter.kick), 0.45)
	shooter.avatar.recoil = 1.0
	sfx("freezeray_shard")
	if last.is_empty() or String(last.get("move", "")) != "shard":
		last = {"move": "shard", "shots": 0, "shattered": 0, "cubes": 0, "holes": 0, "cut": 0, "frost": 0.0, "froze": 0, "world": 0, "ms": 0.0, "max_ms": 0.0}
	last.shots = int(last.shots) + 1
	var em2 := _emit_world(from, f)
	for i in 12:
		_emit(em2, (f * randf_range(0.8, 2.5) + _rand_dir() * 0.5) * (TD if td else 1.0), randf_range(0.008, 0.016) * (TD if td else 1.0),
			randf_range(0.2, 0.4), _frost_col(), 0.0, 5.0)
	# what's between the eye and where it's drawn leaving is hit at once
	var pre := shard_state(from + f * 0.15, f * maxf(0.01, start.distance_to(from + f * 0.15)), 0.0)
	var ex: Array[RID] = shooter.exclude()
	var h := shard_fly(pre, 1.0, arena.bodies, arena.get_world_3d().direct_space_state, ex)
	if not h.is_empty():
		s.st.p = h.point
		_shard_hit(s, h)

# a shard not in use (or the oldest one stuck in someone, taken out)
func _free_shard() -> Dictionary:
	var oldest: Dictionary = _shards[0]
	var most := -1.0
	for s in _shards:
		if String(s.mode) == "":
			return s
		var age := float(s.t) + (STICK_T if String(s.mode) == "melt" else 0.0)
		if String(s.mode) != "fly" and age > most:
			most = age
			oldest = s
	_shard_off(oldest)
	return oldest

func _shard_off(s: Dictionary) -> void:
	s.mode = ""
	(s.node as Node3D).visible = false
	(s.trail as Node3D).visible = false

func _shard_step(s: Dictionary, dt: float) -> void:
	s.t = float(s.t) + dt
	var node: Node3D = s.node
	match String(s.mode):
		"fly":
			var st: Dictionary = s.st
			var p0: Vector3 = st.p
			var ex: Array[RID] = shooter.exclude()
			var h := shard_fly(st, dt, arena.bodies, arena.get_world_3d().direct_space_state, ex)
			if not h.is_empty() and not _shard_hit(s, h):
				return
			s.vis = (s.vis as Vector3) * exp(-dt * 16.0)
			var p: Vector3 = st.p
			if float(st.t) > SHARD_LIFE or absf(p.x) > 30.0 or absf(p.z) > 30.0:
				_shard_off(s)
				return
			var v: Vector3 = st.v
			node.global_transform = Transform3D(dir_basis(v), p + (s.vis as Vector3))
			# a faint trail behind it, frost shed along the way
			var td := TD if top_down() else 1.0
			var tl := minf(0.9 * td, float(st.dist) + 0.2)
			var dn := v.normalized()
			var u := dn.cross(Vector3.UP if absf(dn.y) < 0.95 else Vector3.RIGHT).normalized()
			var trail: MeshInstance3D = s.trail
			trail.global_transform = Transform3D(_twisted(u, dn.cross(u), dn, randf() * TAU, 0.012 * td, tl), node.global_position - dn * (0.18 * td + tl * 0.5))
			trail.visible = true
			for i in 2:
				_emit(p0.lerp(p, randf()) + _rand_dir() * 0.01, _rand_dir() * 0.08, randf_range(0.006, 0.012) * td, randf_range(0.2, 0.35), _frost_col(), 0.0, 3.0)
		"stuck", "melt":
			var b: VoxelBody = s.body if is_instance_valid(s.body) else null
			var part := String(s.part)
			if b == null or not b.parts.has(part) or bool(b.parts[part].gone):
				_shard_break(node.global_position, Vector3.UP, -node.global_transform.basis.z, 10)
				_shard_off(s)
				return
			var m := b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(s.bone))
			node.global_transform = m * (s.local as Transform3D)
			if String(s.mode) == "stuck":
				if float(s.t) >= STICK_T:
					s.mode = "melt"
					s.t = 0.0
				return
			# melting: thinner and shorter, dripping
			var k := 1.0 - float(s.t) / MELT_T
			if k <= 0.0:
				_shard_off(s)
				return
			var sc: float = TD if top_down() else 1.0
			(s.model as Node3D).scale = Vector3(k, k, 0.35 + 0.65 * k) * sc
			if randf() < dt * 14.0:
				_emit(node.global_transform * Vector3(0, -0.01, 0.12 * k * sc), Vector3(0, -0.2, 0), randf_range(0.007, 0.012) * sc, 0.8, Color(0.6, 0.8, 1.0), 9.8, 0.2)

# a flying shard ran into h: a body (shatters a frozen one and flies on; holes one not frozen and sticks) or the world
# (breaks). False if it's done flying.
func _shard_hit(s: Dictionary, h: Dictionary) -> bool:
	var st: Dictionary = s.st
	var dir: Vector3 = (st.v as Vector3).normalized()
	var at: Vector3 = h.point
	if not h.has("body"):
		_shard_break(at, h.normal, dir, 26)
		sfx("freezeray_tink", at)
		last.world = int(last.get("world", 0)) + 1
		_shard_off(s)
		return false
	var b: VoxelBody = h.body
	var t0 := Time.get_ticks_usec()
	var res := shard_strike(b, at, dir)
	var ms := snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	last.ms = snappedf(float(last.get("ms", 0.0)) + ms, 0.01)
	last.max_ms = maxf(float(last.get("max_ms", 0.0)), ms)
	if bool(res.get("shattered", false)):
		var bits: Array = res.bits
		if bits.is_empty():
			# (can't die: the ice only broke off) a chip of it, and the shard's done
			_shard_break(at, -dir, dir, 26)
			sfx("freezeray_tink", at)
			_shard_off(s)
			return false
		_shatter_burst(b, bits, dir)
		last.shattered = int(last.get("shattered", 0)) + 1
		last.cubes = int(last.get("cubes", 0)) + bits.size()
		var seen: Dictionary = st.hit
		seen[b.get_instance_id()] = true
		st.v = (st.v as Vector3) * SHARD_SLOW
		return true
	# not frozen: a small hole, the cubes out of it chilled pale, the shard stuck in
	var cut: Array = res.bits
	for bt in cut:
		bt.col = (bt.col as Color).lerp(VoxelBody.ICE, 0.25)
	spray({"bits": cut}, (-dir + Vector3.UP * 0.6).normalized(), 2.2)
	fling(b, res, dir * 2.0 + Vector3.UP * 1.5, Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)))
	if b.alive and not b.frozen():
		b.hit_react(dir, mini(cut.size(), 30), String(h.part))
		var flat := Vector3(dir.x, 0.0, dir.z).normalized()
		b.knock += flat * SHARD_SHOVE
	sfx("freezeray_tink", at)
	sfx("hit_flesh", at, -8.0)
	if bool(res.froze):
		_froze(b)
		last.froze = int(last.get("froze", 0)) + 1
	for i in 14:
		_emit(at, (-dir * randf_range(0.3, 1.0) + _rand_dir() * 0.5), randf_range(0.01, 0.02), randf_range(0.3, 0.6), _frost_col(), 0.5, 4.0)
	last.holes = int(last.get("holes", 0)) + 1
	last.cut = int(last.get("cut", 0)) + int(res.cut)
	last.frost = snappedf(1.0 if b.frozen() else b.frost, 0.01)
	shooter.kick = maxf(float(shooter.kick), 0.35)
	hit_stop(0.03, 0.15)
	var part := String(h.part)
	if not b.parts.has(part) or bool(b.parts[part].gone):
		_shard_break(at, -dir, dir, 12)
		_shard_off(s)
		return false
	var bone: int = b.parts[part].bone
	var m := b.skeleton.global_transform * b.skeleton.get_bone_global_pose(bone)
	s.body = b
	s.part = part
	s.bone = bone
	var tilt := dir.cross(_rand_dir()).normalized()          # in at a slant, not end on to you
	var sd := dir.rotated(tilt, randf_range(0.3, 0.5)) if tilt.length() > 0.5 else dir
	s.local = m.affine_inverse() * Transform3D(dir_basis(sd), at + sd * 0.05)
	s.mode = "stuck"
	s.t = 0.0
	(s.trail as Node3D).visible = false
	(s.node as Node3D).global_transform = m * (s.local as Transform3D)
	return false

# a statue shattered: its cubes burst out along the shard's line and away from its middle, a cloud of frost, the
# crash, a big kick and a hit-stop
func _shatter_burst(b: VoxelBody, bits: Array, dir: Vector3) -> void:
	var c := b.global_position + Vector3.UP * b.height * 0.5
	var bins := {}
	for bt in bits:
		var o: Vector3 = (bt.pos as Vector3) - c
		var k := (1 if o.x > 0.0 else 0) + (2 if o.y > 0.0 else 0) + (4 if o.z > 0.0 else 0)
		if not bins.has(k):
			bins[k] = []
		(bins[k] as Array).append(bt)
	for k in bins:
		var od := Vector3(1.0 if k & 1 else -1.0, 1.0 if k & 2 else -1.0, 1.0 if k & 4 else -1.0).normalized()
		spray({"bits": bins[k]}, (dir * 1.3 + od * 0.8).normalized(), SHATTER_POWER)
	var td := TD if top_down() else 1.0
	for i in 160:
		var p := b.global_position + Vector3(randf_range(-0.35, 0.35), randf() * b.height, randf_range(-0.35, 0.35))
		_emit(p, (dir * randf_range(0.5, 2.5) + _rand_dir() * 1.2) * td, randf_range(0.014, 0.034) * td, randf_range(0.5, 1.2), _frost_col(), 0.6, 2.2)
	sfx("shatter", c, 4.0)
	sfx("freezeray_tink", c, 2.0, 0.8)
	shooter.kick = maxf(float(shooter.kick), 1.5)
	hit_stop(0.11, 0.04)

# a shard broken: ice bits bouncing off, a puff of frost
func _shard_break(p: Vector3, n: Vector3, dir: Vector3, count: int) -> void:
	var td := TD if top_down() else 1.0
	var bounce := (dir - 2.0 * dir.dot(n) * n).normalized()
	for i in count:
		_emit(p + _rand_dir() * 0.02, (n * randf_range(0.4, 1.8) + bounce * randf_range(0.0, 1.5) + _rand_dir() * 0.9) * td,
			randf_range(0.012, 0.028) * td, randf_range(0.7, 1.3), ICE_COL.lerp(Color(1, 1, 1), randf() * 0.5), 9.8, 0.4)
	for i in count / 2:
		_emit(p, (n * randf_range(0.2, 0.7) + _rand_dir() * 0.4) * td, randf_range(0.014, 0.026) * td, randf_range(0.3, 0.6), Color(0.95, 0.98, 1.0), 0.0, 4.0)

# ---------------------------------------------------------------- the view, the hand

func _pose_view(dt: float) -> void:
	var e := _fire_k * _fire_k * (3.0 - 2.0 * _fire_k)
	var at := REST.lerp(FIRE_AT, e)
	var rot := REST_ROT.lerp(FIRE_ROT, e)
	# breathing at rest; buzzing in the hands while the beam is on
	at += Vector3(sin(_clock * 1.3) * 0.003, sin(_clock * 2.1) * 0.004, 0.0) * (1.0 - e)
	at += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.0016 * _beam_k
	rot.z += sin(_clock * 23.0) * 0.008 * _beam_k
	# a shard's kick: back and up; run dry: lowered and tipped, venting
	at += Vector3(0.0, 0.012, 0.07) * _kick_s
	rot.x += 0.3 * _kick_s
	at.y -= 0.035 * _vent
	rot.z -= 0.25 * _vent
	_gun.position = at
	_gun.rotation = rot
	# the tank glows, harder and pulsing while firing, dim when it's low; the coil spins; the fins frost over
	var low := 0.35 + 0.65 * _energy / ENERGY
	_m_tank.emission_energy_multiplier = (1.0 + 0.3 * sin(_clock * 2.4) + _beam_k * (2.6 + 1.4 * sin(_clock * 29.0) + randf() * 0.6)) * low
	_m_coil.emission_energy_multiplier = (1.2 + _beam_k * (3.0 + randf())) * low + 2.0 * _kick_s
	_m_fin.albedo_color = FROST.lerp(Color(1, 1, 1), _frosted)
	var spin := dt * (0.6 + 13.0 * _beam_k + 8.0 * _kick_s)
	for i in _coils.size():
		(_coils[i] as Node3D).rotation.z += spin * (1.0 if i % 2 == 0 else -1.0)
	var ch := maxf(0.01, _energy / ENERGY)
	_gauge.scale = Vector3(1.0, 1.0, ch)
	# the next shard growing in the dish
	var g := 1.0 - _cd / SHARD_CD
	_crystal.visible = g > 0.05
	_crystal.scale = Vector3.ONE * maxf(0.05, g * g * (3.0 - 2.0 * g))

func _pose_hand(dt: float) -> void:
	if not is_instance_valid(_hand):
		return
	var spin := dt * (0.6 + 13.0 * _beam_k)
	for i in _hand_coils.size():
		if is_instance_valid(_hand_coils[i]):
			(_hand_coils[i] as Node3D).rotation.z += spin * (1.0 if i % 2 == 0 else -1.0)

# ---------------------------------------------------------------- frost particles

func _emit(p: Vector3, v: Vector3, size: float, life: float, col: Color, g: float, drag: float) -> void:
	var i := _pn
	if _pn >= MAX_P:
		i = randi() % MAX_P
	else:
		_pn += 1
	_pp[i] = p
	_pv[i] = v
	_pl[i] = life
	_ps[i] = life
	_pz[i] = size
	_pg[i] = g
	_pd[i] = drag
	_pc[i] = col
	_pr[i] = Basis.from_euler(Vector3(randf(), randf(), randf()) * TAU)

func _frost_col() -> Color:
	return Color(1.0, 1.0, 1.0).lerp(Color(0.62, 0.84, 1.0), randf())

static func _rand_dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()

func _parts_step(dt: float) -> void:
	if _pn == 0:
		_parts.multimesh.visible_instance_count = 0
		return
	var mm := _parts.multimesh
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
			_pg[i] = _pg[_pn]
			_pd[i] = _pd[_pn]
			_pc[i] = _pc[_pn]
			_pr[i] = _pr[_pn]
			continue
		var v := _pv[i]
		v.y -= _pg[i] * dt
		if _pd[i] > 0.0:
			v *= 1.0 / (1.0 + _pd[i] * dt)
		var p := _pp[i] + v * dt
		var sz := _pz[i]
		if p.y < sz * 0.5 and _pg[i] > 0.0:
			p.y = sz * 0.5
			v = Vector3(v.x * 0.6, -v.y * 0.3, v.z * 0.6)
		_pp[i] = p
		_pv[i] = v
		var k := _pl[i] / _ps[i]                    # 1 new .. 0 gone
		var col := _pc[i]
		col.a = clampf(k * 2.5, 0.0, 0.9)
		mm.set_instance_transform(i, Transform3D(_pr[i] * (sz * (0.55 + 0.45 * k)), p))
		mm.set_instance_color(i, col)
		i += 1
	mm.visible_instance_count = _pn

# ---------------------------------------------------------------- checks

static func _grunt(host: Node, m: Material) -> VoxelBody:
	var b := VoxelBody.new()
	host.add_child(b)
	b.setup("grunt", 0.023, 1, m)
	b.animate(0.0, false)
	return b

static func checks(host: Node) -> Array:
	var out := []
	var was := VoxelBody.immortal
	VoxelBody.immortal = false
	var m := StandardMaterial3D.new()
	var none: Array[RID] = []
	var dt := 1.0 / 60.0
	# the beam from 3 m out at his chest finds him; over his head it finds nothing; aimed down short of him, the floor
	var b := _grunt(host, m)
	var from := Vector3(0, 1.0, 3.0)
	var t0 := Time.get_ticks_usec()
	var h := beam_target([b], from, Vector3.FORWARD, RANGE, null, none)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	out.append([h.get("body") == b and absf(float(h.get("dist", 0.0)) - 2.85) < 0.3,
		"the beam from 3 m finds his chest (%.2f m, %.2f ms)" % [float(h.get("dist", -1.0)), ms]])
	var over := beam_target([b], Vector3(0, 2.3, 3.0), Vector3.FORWARD, RANGE, null, none)
	var down := beam_target([b], Vector3(0, 2.3, 3.0), Vector3(0, -1, -0.3).normalized(), RANGE, null, none)
	out.append([over.is_empty() and not down.is_empty() and not down.has("body") and absf((down.point as Vector3).y) < 0.01,
		"over his head the beam finds nothing; aimed down short of him, the floor"])
	# a steady beam: frost builds (slower and slower), frozen solid after about FREEZE_S
	var t := 0.0
	var froze_at := -1.0
	var half_frost := 0.0
	var half_move := 1.0
	while t < 3.0:
		if beam_tick(b, dt):
			froze_at = t + dt
			break
		b.status_step(dt)
		t += dt
		if half_frost == 0.0 and t >= FREEZE_S * 0.5:
			half_frost = b.frost
			half_move = b.move_factor()
	out.append([half_frost > 0.35 and half_frost < 0.65 and half_move < 0.75,
		"half way there: frosting over (frost %.2f), slowed to %.2f" % [half_frost, half_move]])
	out.append([b.frozen() and absf(froze_at - FREEZE_S) < 0.05 and b.frozen_t == VoxelBody.FREEZE_T,
		"frozen solid after %.2f s of beam, for %.0f s" % [froze_at, b.frozen_t]])
	b.frozen_t = 2.0
	beam_tick(b, dt)
	out.append([b.frozen_t == VoxelBody.FREEZE_T, "the beam on one frozen keeps him frozen (%.1f s again)" % b.frozen_t])
	# a bigger one takes longer
	var big := VoxelBody.new()
	big.height = 2.2
	var big_s := 1.0 / (chill_rate(big) - VoxelBody.FROST_FADE)
	out.append([big_s > FREEZE_S * 1.3, "a brute takes %.2f s to freeze" % big_s])
	big.free()
	# a shard into the frozen one: he shatters, every cube flying, dead
	var cubes := b.cubes_left()
	var t1 := Time.get_ticks_usec()
	var r := shard_strike(b, h.point, Vector3.FORWARD)
	var ms1 := (Time.get_ticks_usec() - t1) / 1000.0
	out.append([bool(r.get("shattered", false)) and bool(r.killed) and not b.alive and b.cubes_left() == 0 and (r.bits as Array).size() > 1000,
		"a shard into the statue shatters it (%d cubes, %d flying, %.1f ms)" % [cubes, (r.bits as Array).size(), ms1]])
	b.queue_free()
	# a shard into one not frozen: a small hole, chilled, still alive; four of them freeze him
	var b2 := _grunt(host, m)
	var h2 := b2.trace(from, Vector3.FORWARD, 5.0)
	var t2 := Time.get_ticks_usec()
	var r2 := shard_strike(b2, h2.point, Vector3.FORWARD)
	var ms2 := (Time.get_ticks_usec() - t2) / 1000.0
	out.append([int(r2.cut) > 10 and int(r2.cut) < 250 and (r2.pieces as Array).is_empty() and absf(b2.frost - SHARD_CHILL) < 0.001 and not b2.frozen() and b2.alive,
		"a shard into him unfrozen: a small hole (%d cubes, %.1f ms), frost %.2f, alive" % [int(r2.cut), ms2, b2.frost]])
	var froze := false
	for y in [1.15, 0.9, 1.25]:
		var hy := b2.trace(Vector3(0.05, y, 3.0), Vector3.FORWARD, 5.0)
		if not hy.is_empty():
			froze = bool(shard_strike(b2, hy.point, Vector3.FORWARD).froze)
	out.append([froze and b2.frozen(), "four shards freeze him solid"])
	b2.queue_free()
	# the flight: from 3 m out at his chest it hits him in a few frames at 40 m/s; aimed down short of him, the floor
	var b3 := _grunt(host, m)
	var st := shard_state(Vector3(0, 1.1, 3.0), Vector3.FORWARD * SHARD_V, 0.0)
	var hit := {}
	var steps := 0
	while hit.is_empty() and steps < 30:
		hit = shard_fly(st, dt, [b3], null, none)
		steps += 1
	out.append([hit.get("body") == b3 and steps <= 5, "a shard hits him %d frames out (%.2f m flown)" % [steps, float(st.dist)]])
	var st2 := shard_state(Vector3(0, 1.1, 3.0), Vector3(0, -0.5, -1).normalized() * SHARD_V, 0.0)
	var hit2 := {}
	steps = 0
	while hit2.is_empty() and steps < 30:
		hit2 = shard_fly(st2, dt, [b3], null, none)
		steps += 1
	out.append([not hit2.is_empty() and not hit2.has("body") and absf((st2.p as Vector3).y) < 0.01, "a shard aimed at the floor in front of him hits the floor"])
	# one gone through (a shattered statue) is passed over
	var st3 := shard_state(Vector3(0, 1.1, 3.0), Vector3.FORWARD * SHARD_V, 0.0)
	(st3.hit as Dictionary)[b3.get_instance_id()] = true
	var passed := true
	for i in 10:
		if not shard_fly(st3, dt, [b3], null, none).is_empty():
			passed = false
	out.append([passed and (st3.p as Vector3).z < -2.0, "a shard flies on past one it went through"])
	b3.queue_free()
	# the charge: 6 s of beam empties it; let go, it fills back up in RECHARGE_WAIT + ENERGY / RECHARGE
	var e := ENERGY
	var frames := 0
	while e > 0.0 and frames < 1000:
		e = charge(e, true, 0.0, dt)
		frames += 1
	var idle := 0.0
	while e < ENERGY and idle < 20.0:
		idle += dt
		e = charge(e, false, idle, dt)
	out.append([absf(frames * dt - ENERGY) < 0.05 and absf(idle - (RECHARGE_WAIT + ENERGY / RECHARGE)) < 0.05,
		"a charge is %.1f s of beam, back full %.1f s after letting go" % [frames * dt, idle]])
	VoxelBody.immortal = was
	return out
