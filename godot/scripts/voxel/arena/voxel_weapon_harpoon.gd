class_name VoxelWeaponHarpoon
extends VoxelMelee
## The harpoon gun (the owner, 20 Oct: six new weapons, each doing something different; this one is "GET OVER HERE"). A
## pneumatic speargun held at the shoulder: a teak stock and pistol grip, a long dark barrel with a rail on top and an
## orange muzzle, a barbed steel harpoon lying in the rail with its point out past the muzzle, and a reel of steel line
## on its side (a red crank knob on it) that spins as the line pays out and as it's wound back in. Either button fires
## the harpoon: it flies at 45 m/s where you look (a little gravity; top-down from Jared's chest at the body under the
## mouse, so a head, the legs or one lying on the floor can be picked, else level toward it), traced every frame into
## the bodies and the world, trailing its line from the muzzle (sagging a little as it pays out, taut and straight while
## it pulls). Left click drags them to you: the harpoon sticks in the first body it hits, where it hits (a small hole
## punched, a few cubes out), riding on that part, and the reel winds them in at 7 m/s (feet dragging, a light one
## lifted a little off them; a brute slower) till they're 1.4 m in front of you. There the barbs tear out and they're
## left staggering for a second, right where you can hit them. Corpses and lying pieces are dragged in too. In a wall or
## the floor it sticks a moment, quivering, then reels back. Click again while it's out to let go. Right click yanks a
## limb off: the harpoon goes in the same way, the line snaps taut for a quarter of a second and jerks the body toward
## you, then the arm, forearm, hand, thigh, shin, foot or head it's in comes off whole with everything below it
## (VoxelBody.sever; the head kills), cubes spraying from the torn joint, and comes flying at you on the line till it
## drops at your feet. In the torso it tears a chunk out instead and the body stumbles toward you. Right click while one
## is being dragged in yanks off whatever the harpoon is in. The harpoon can fire again 0.8 s after it's back on the
## rail. If the body is freed mid-pull the harpoon just comes back; if the part it's in is cut off by something else, it
## stays in that piece and pulls it in. Owned by the voxel session.

const SPEED := 45.0             # m/s the harpoon flies
const GRAV := 2.0               # m/s/s pulling it down (first person; top-down it flies level)
const RANGE := 32.0             # metres of line on the reel (it runs out: the harpoon comes back)
const HOLE_R := 0.04            # the hole it punches going in: this wide ...
const HOLE_D := 0.06            # ... and this deep (metres)
const SINK := 0.14              # metres of the point buried in what it hits
const HURT := 8.0
const DRAG_V := 7.0             # m/s the reel drags a body in
const DRAG_TO := 1.4            # metres (level) in front of you it's let go
const DRAG_MAX := 5.0           # seconds of dragging at most (held back by something)
const HEFT := {"brute": 0.6, "swarmer": 1.2}                     # drag speed by kind
const LIFT := {"swarmer": 0.16, "grunt": 0.06, "batter": 0.05}   # metres a light one is lifted off its feet
const LET_GO := 1.0             # seconds they stagger once let go
const WORLD_T := 0.35           # seconds stuck in a wall or the floor before it reels back
const REEL_V := 34.0            # m/s it's reeled back empty
const COOLDOWN := 0.8           # seconds after it's back on the rail till it can fire again
const LOAD_T := 0.2             # back: the harpoon slides into the rail ...
const PUMP_T := 0.32            # ... then the air's pumped up again (the gun tilts)
const TUG_T := 0.25             # the right click's tug before the tear
const TUG_JERK := 0.3           # metres the tug jerks the body toward you
const YANK_V := 9.0             # m/s what's torn off flies at you on the line
const CATCH := 1.1              # metres (level) from you the line lets go of it
const CHUNK_R := 0.1            # the torso: a ball this big torn out
const CLOSE := 1.15             # metres (level) the tug and the stumble after the tear stop short of you
const STUMP_R := 0.05           # the torn joint's ragged edge (the spray)
const SHAFT := 0.6
const TAIL := 0.7               # the harpoon's own space: the point at the origin, the line's shackle this far back (+z)
const LIMBS := ["arm", "forearm", "hand", "thigh", "shin", "foot", "head"]
# the view (camera space: x right, y up, -z forward): the grip, and a point far ahead the barrel aims at
const REST_GRIP := Vector3(0.21, -0.2, -0.12)
const REST_AT := Vector3(0.08, -0.1, -4.0)
# the gun's own space (the grip at the origin, the barrel along +z, top +y, +x its left)
const RAIL := Vector3(0, 0.049, 0.86)       # the loaded harpoon's point
const GUIDE := Vector3(0, 0.058, 0.745)     # the line guide on the muzzle (the line comes out here)
const REEL_AT := Vector3(0.064, -0.03, 0.34)    # the reel's middle, on the left side (toward the middle of the view)
const TEAK := Color(0.5, 0.3, 0.16)
const TUBE := Color(0.17, 0.21, 0.28)
const BLACK := Color(0.06, 0.06, 0.07)
const STEEL := Color(0.8, 0.82, 0.86)
const WIRE := Color(0.34, 0.34, 0.36)
const KNOB := Color(0.75, 0.12, 0.08)
const MUZZLE := Color(0.9, 0.45, 0.08)
const CABLE := Color(0.4, 0.38, 0.35)       # the line in the world (first person) ...
const CABLE_TD := Color(0.62, 0.6, 0.55)    # ... and top-down, over the dark floor

var _gun: Node3D                # first person: the speargun (posed under view)
var _parts := {}                # its moving bits: {reel, harpoon (the loaded one), guide}
var _hand: Node3D               # top-down: the gun in Jared's hands (the arena frees it on a switch)
var _hand_parts := {}
var _proj: Node3D               # the harpoon out of the gun (top level, in the world): its point at the origin
var _proj_m: Node3D
var _cable: MeshInstance3D      # the line from the muzzle to the harpoon (top level, redrawn every frame)
var _cable_mat: StandardMaterial3D
var _mode := "ready"            # "ready" (on the rail), "fly", "body" (in one), "world" (in a wall or the floor),
                                # "piece" (in a piece flying at you), "reel" (coming back empty)
var _yank := false              # fired with the right click: a body it goes into is tugged and torn
var _st := {}                   # the flight (launch_state / fly)
var _vis := Vector3.ZERO        # first person: how far off its real path it's drawn (from the muzzle, closing fast)
var _p := Vector3.ZERO          # the harpoon's point (world) ...
var _dir := Vector3.FORWARD     # ... and the way it points
var _t := 0.0                   # seconds in this mode
var _body: VoxelBody            # the body it's in ...
var _part := ""                 # ... the part, and the point and its direction in that part's bone space
var _local := Vector3.ZERO
var _ldir := Vector3.FORWARD
var _rb: RigidBody3D            # the piece it's in
var _tug := -1.0                # seconds into a tug (-1: none)
var _tug_k := 0.0
var _dragging := false          # the reel winding a body in this frame
var _dragged := 0.0             # metres this one has been dragged
var _cd := 0.0
var _kick := 0.0                # the view's kick: 1 just fired, falling back
var _load := 9.0                # seconds since the harpoon came back onto the rail
var _pull := 0.0                # 0 .. 1: the reel straining (the view leans in and shakes)
var _reel_ang := 0.0
var _reel_v := 0.0              # radians a second the reel turns (+ winding in, - paying out)
var _taut := 0.0                # 0 slack (the line sags) .. 1 taut
var _twang := 0.0               # the line quivering after it snapped taut
var _clock := 0.0
var _ms := 0.0                  # the dearest frame of this shot (traces, carves), ms

func _build() -> void:
	_gun = Node3D.new()
	view.add_child(_gun)
	_parts = gun_model(_gun, false)
	_gun.transform = _aim_xf(REST_GRIP, REST_AT)
	_proj = Node3D.new()
	_proj.top_level = true
	add_child(_proj)
	_proj_m = Node3D.new()
	_proj.add_child(_proj_m)
	harpoon_model(_proj_m, 1.0, true)
	_proj.visible = false
	_cable = MeshInstance3D.new()
	_cable.mesh = ImmediateMesh.new()
	_cable_mat = StandardMaterial3D.new()
	_cable_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cable_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cable_mat.albedo_color = CABLE
	_cable.material_override = _cable_mat
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cable.top_level = true
	add_child(_cable)

## The speargun's boxes under root (the grip at the origin, the barrel along +z, its top +y, +x its left), metres;
## light: brighter, for top-down (seen small from up high on a dark floor). Returns its moving bits: {reel (turns
## about x), harpoon (the loaded one, its point at RAIL), guide (where the line comes out)}.
static func gun_model(root: Node3D, light: bool) -> Dictionary:
	var teak := VoxelMelee.mat(TEAK.lightened(0.2) if light else TEAK, 0.0, 0.6)
	var tube := VoxelMelee.mat(TUBE.lightened(0.3) if light else TUBE, 0.3, 0.5)
	var black := VoxelMelee.mat(BLACK.lightened(0.15) if light else BLACK, 0.0, 0.7)
	var steel := VoxelMelee.mat(STEEL, 0.85, 0.25)
	var wire := VoxelMelee.mat(WIRE.lightened(0.3) if light else WIRE, 0.7, 0.4)
	var knob := VoxelMelee.mat(KNOB, 0.0, 0.5)
	var orange := VoxelMelee.mat(MUZZLE, 0.0, 0.5)
	# the pistol grip (raked back), the trigger and its guard
	VoxelMelee.box(root, Vector3(0.032, 0.11, 0.045), Vector3(0, -0.06, -0.01), black, Vector3(0.3, 0, 0))
	VoxelMelee.box(root, Vector3(0.008, 0.026, 0.012), Vector3(0, -0.024, 0.036), steel, Vector3(0.25, 0, 0))
	VoxelMelee.box(root, Vector3(0.01, 0.008, 0.07), Vector3(0, -0.05, 0.04), black)
	VoxelMelee.box(root, Vector3(0.01, 0.045, 0.008), Vector3(0, -0.03, 0.074), black)
	# the handle's housing, the teak stock back to the shoulder, its butt pad
	VoxelMelee.box(root, Vector3(0.046, 0.05, 0.17), Vector3(0, 0.006, 0.03), black)
	VoxelMelee.box(root, Vector3(0.04, 0.048, 0.2), Vector3(0, -0.004, -0.15), teak)
	VoxelMelee.box(root, Vector3(0.046, 0.075, 0.026), Vector3(0, -0.016, -0.262), black)
	# the barrel, the rail along its top, two clamps, the muzzle and the line guide on it
	VoxelMelee.box(root, Vector3(0.044, 0.044, 0.6), Vector3(0, 0.012, 0.4), tube)
	VoxelMelee.box(root, Vector3(0.016, 0.01, 0.66), Vector3(0, 0.039, 0.42), black)
	for z in [0.28, 0.52]:
		VoxelMelee.box(root, Vector3(0.052, 0.052, 0.014), Vector3(0, 0.012, z), black)
	VoxelMelee.box(root, Vector3(0.062, 0.062, 0.05), Vector3(0, 0.014, 0.715), orange)
	VoxelMelee.box(root, Vector3(0.022, 0.016, 0.018), Vector3(0, 0.052, 0.735), steel)
	var guide := Node3D.new()
	guide.position = GUIDE
	root.add_child(guide)
	# the reel on the left side: a bracket off the barrel, the drum of wound line, the rim, spokes and a crank
	VoxelMelee.box(root, Vector3(0.034, 0.03, 0.03), Vector3(0.038, -0.016, REEL_AT.z), black)
	var reel := Node3D.new()
	reel.position = REEL_AT
	root.add_child(reel)
	VoxelMelee.box(reel, Vector3(0.014, 0.05, 0.05), Vector3.ZERO, wire)
	VoxelMelee.box(reel, Vector3(0.014, 0.05, 0.05), Vector3.ZERO, wire, Vector3(PI / 4.0, 0, 0))
	for i in 8:
		var a := TAU * i / 8.0
		VoxelMelee.box(reel, Vector3(0.018, 0.012, 0.04), Vector3(0, cos(a), sin(a)) * 0.048, steel, Vector3(a, 0, 0))
	VoxelMelee.box(reel, Vector3(0.024, 0.016, 0.016), Vector3(0.004, 0, 0), steel)
	VoxelMelee.box(reel, Vector3(0.004, 0.09, 0.008), Vector3(0.009, 0, 0), black)
	VoxelMelee.box(reel, Vector3(0.004, 0.008, 0.09), Vector3(0.009, 0, 0), black)
	VoxelMelee.box(reel, Vector3(0.006, 0.008, 0.036), Vector3(0.014, 0, 0.024), steel)
	VoxelMelee.box(reel, Vector3(0.018, 0.016, 0.016), Vector3(0.024, 0, 0.042), knob)
	# the line from the drum up along the barrel to the guide
	_rod(root, REEL_AT + Vector3(0, 0.026, 0), GUIDE, 0.003, wire)
	# the harpoon in the rail, its point out past the muzzle
	var hp := Node3D.new()
	hp.position = RAIL
	root.add_child(hp)
	var hm := Node3D.new()
	hm.rotation = Vector3(0, PI, 0)
	hp.add_child(hm)
	harpoon_model(hm, 1.0, false)
	return {"reel": reel, "harpoon": hp, "guide": guide}

## The harpoon's boxes under root (its point at the origin, the shaft back along +z, metres); thick: this many times
## stouter (top-down); shadows: cast them (in the world).
static func harpoon_model(root: Node3D, thick: float, shadows: bool) -> void:
	var steel := VoxelMelee.mat(STEEL, 0.85, 0.25)
	var dark := VoxelMelee.mat(Color(0.3, 0.31, 0.34), 0.6, 0.45)
	var w := Vector3(thick, thick, 1.0)
	var bx := [
		[Vector3(0.006, 0.006, 0.022), Vector3(0, 0, 0.011), steel, Vector3.ZERO],       # the point, widening back
		[Vector3(0.012, 0.012, 0.026), Vector3(0, 0, 0.034), steel, Vector3.ZERO],
		[Vector3(0.018, 0.018, 0.03), Vector3(0, 0, 0.062), steel, Vector3.ZERO],
		[Vector3(0.014, 0.014, 0.014), Vector3(0, 0, 0.084), dark, Vector3.ZERO],        # the collar
		[Vector3(0.009, 0.009, SHAFT), Vector3(0, 0, 0.09 + SHAFT * 0.5), steel, Vector3.ZERO],
		[Vector3(0.014, 0.014, 0.022), Vector3(0, 0, TAIL - 0.011), dark, Vector3.ZERO],  # the line's shackle
	]
	# the barbs: four blades swept back from behind the head
	for s in [-1.0, 1.0]:
		bx.append([Vector3(0.004, 0.003, 0.055), Vector3(s * 0.021 * thick, 0, 0.1), steel, Vector3(0, s * 0.45, 0)])
		bx.append([Vector3(0.003, 0.004, 0.045), Vector3(0, s * 0.018 * thick, 0.095), steel, Vector3(-s * 0.45, 0, 0)])
	for e in bx:
		var mi := VoxelMelee.box(root, (e[0] as Vector3) * w, e[1], e[2], e[3])
		if shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# a thin box from a to b under parent
static func _rod(parent: Node3D, a: Vector3, b: Vector3, thick: float, m: Material) -> MeshInstance3D:
	var mi := VoxelMelee.box(parent, Vector3(thick, thick, a.distance_to(b)), (a + b) * 0.5, m)
	mi.basis = Basis.looking_at(b - a, Vector3.UP)
	return mi

# a pose: the grip at grip, the barrel (+z) aimed at at (both camera space), its top up
static func _aim_xf(grip: Vector3, at: Vector3) -> Transform3D:
	var z := (at - grip).normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Transform3D(Basis(x, z.cross(x), z), grip)

## -z along d (the harpoon's point along its flight), up kept up.
static func dir_basis(d: Vector3) -> Basis:
	if d.length_squared() < 0.000001:
		return Basis()
	var n := d.normalized()
	return Basis.looking_at(n, Vector3.UP if absf(n.y) < 0.98 else Vector3.BACK)

func on_deselect() -> void:
	# put away: whatever it's in is let go and the line wound straight back in
	if _mode != "ready":
		_drop_body()
		_mode = "ready"
		_tug = -1.0
		_cd = COOLDOWN
		_load = 9.0
		_proj.visible = false
		(_cable.mesh as ImmediateMesh).clear_surfaces()
	sfx_stop("reel")

## Out: spent (the weapon bar's slot full) till it's back on the rail, then the cooldown.
func cooling() -> float:
	if _mode != "ready":
		return 1.0
	return clampf(_cd / COOLDOWN, 0.0, 1.0)

## Out: the metres of line paid out.
func bar_text() -> String:
	if _mode == "ready":
		return ""
	return "%dm" % roundi(_muzzle().distance_to(_p))

func press(button: int) -> void:
	if _mode == "ready":
		if _cd <= 0.0:
			fire(button == MOUSE_BUTTON_RIGHT)
		else:
			sfx("dry_fire", Vector3.INF, -8.0, 0.8)     # the air not pumped up yet
		return
	if _tug >= 0.0 or _mode == "reel":
		return
	if button == MOUSE_BUTTON_RIGHT and _mode == "body":
		_start_tug()            # one being dragged in: yank off whatever it's in
		return
	# the barbs pulled out of what it's in
	if _mode == "body" or _mode == "piece":
		sfx("harpoon_rip", _p, -12.0, 1.6)
	elif _mode == "world":
		sfx("harpoon_clank", _p, -10.0, 1.3)
	let_go()

## Fires the harpoon where you look (yank: the right click's, tearing off what it goes into).
func fire(yank_it: bool) -> void:
	var a: Array = arena._aim()
	var e: Vector3 = eye() if a.is_empty() else a[0]
	var f: Vector3 = look() if a.is_empty() else a[1]
	if top_down():
		# aimed at what's under the mouse (a head, the legs, one lying on the floor), not only level
		var c: Camera3D = arena.cam
		var mp := get_viewport().get_mouse_position()
		var at := pick(arena.bodies, c.project_ray_origin(mp), c.project_ray_normal(mp))
		if at != Vector3.INF and Vector2(at.x - e.x, at.z - e.z).length() > 0.6:
			f = (at - e).normalized()
	# its path is the aim's line; it's drawn leaving from where it lay in the rail, closing onto the path
	var mz := _rail_tip()
	var start := e + f * clampf((mz - e).dot(f), 0.2, 1.4)
	_vis = mz - start
	_vis -= f * _vis.dot(f)
	_mode = "fly"
	_t = 0.0
	_yank = yank_it
	_taut = 0.5
	_ms = 0.0
	_p = start
	_dir = f
	last = {"move": "yank" if yank_it else "drag", "hit": "", "flown_m": 0.0, "cut": 0, "dragged_m": 0.0, "severed": [],
		"pieces": 0, "killed": false, "ms": 0.0}
	_kick = 1.0
	arena._kick = maxf(float(arena._kick), 0.35)
	arena.avatar.recoil = 1.0
	sfx("harpoon_fire")
	# anyone between the aim's start and the muzzle is hit at once
	var t0 := Time.get_ticks_usec()
	var near := launch_state(e + f * 0.15, start - (e + f * 0.15), 0.0)
	var ex: Array[RID] = [arena.player.get_rid()]
	var h := fly(near, 1.0, arena.bodies, arena.get_world_3d().direct_space_state, ex)
	_st = launch_state(start, f * SPEED, 0.0 if top_down() else GRAV)
	_note_ms(t0)
	if not h.is_empty() and String(h.kind) != "end":
		_vis = Vector3.ZERO
		_hit(h)
	_place_proj()

## The point on the first body along the ray from o along d (static, for the checks): where it goes in, a little
## deeper; INF if none. Top-down, the camera's ray through the mouse picks what the harpoon is aimed at.
static func pick(bodies: Array, o: Vector3, d: Vector3) -> Vector3:
	var best := 60.0
	var at := Vector3.INF
	for b in bodies:
		if not is_instance_valid(b):
			continue
		var h: Dictionary = b.trace(o, d, best)
		if not h.is_empty() and float(h.dist) < best:
			best = float(h.dist)
			at = (h.point as Vector3) + d * 0.05
	return at

## Lets go of whatever the harpoon is in (or stops its flight): it's reeled back empty.
func let_go() -> void:
	_drop_body()
	if _proj.visible:
		# from where it's drawn (along the line, driven in deeper close up)
		_p = _proj.global_position
		_dir = -_proj.global_transform.basis.z
	_mode = "reel"
	_t = 0.0
	_tug = -1.0
	_body = null
	_rb = null
	_vis = Vector3.ZERO

# a body let go mid-pull: off the reel, back on its feet
func _drop_body() -> void:
	if _mode == "body" and is_instance_valid(_body) and not _body.airborne:
		_body.position.y = 0.0
		if _body.alive:
			_body.stagger = maxf(_body.stagger, 0.3)

func step(dt: float) -> void:
	_clock += dt
	_t += dt
	_cd = maxf(0.0, _cd - dt)
	_kick = maxf(0.0, _kick - dt * 5.0)
	_load += dt
	_twang = maxf(0.0, _twang - dt * 2.5)
	_dragging = false
	var straining := false
	match _mode:
		"fly":
			_fly_step(dt)
		"body":
			straining = _body_step(dt)
		"world":
			if _t >= WORLD_T:
				let_go()
		"piece":
			straining = _piece_step(dt)
		"reel":
			_reel_step(dt)
	_pull = move_toward(_pull, 1.0 if straining else 0.0, dt * 5.0)
	var taut_want: float = {"fly": 0.55, "world": 0.0, "reel": 0.65}.get(_mode, 1.0)
	_taut = move_toward(_taut, taut_want, dt * 3.0)
	_spin(dt)
	_place_proj()
	_pose_view()
	_pose_hand()
	_draw_cable()
	if _mode == "ready" or absf(_reel_v) < 2.0:
		sfx_stop("reel")
	else:
		sfx_loop("reel", "harpoon_reel_loop", -5.0 if _reel_v > 0.0 else -11.0, clampf(0.7 + absf(_reel_v) / 45.0, 0.7, 1.6))

# ---------------------------------------------------------------- in flight

## A harpoon's flight (static, for the checks): {p: the point (world), v: velocity, g: gravity, dist: metres flown, t}.
static func launch_state(p: Vector3, v: Vector3, g: float) -> Dictionary:
	return {"p": p, "v": v, "g": g, "dist": 0.0, "t": 0.0}

## One step of the harpoon in flight (static, for the checks): it moves dt along its path and stops at the first thing
## the step reaches: a body (traced into its cubes), the world (space: the physics space, or null for just the floor)
## or the floor. Returns {} (still flying), {kind: "body", body, hit (VoxelBody.trace's), dir}, {kind: "world", point,
## normal, dir} or {kind: "end", dir} (the line ran out).
static func fly(st: Dictionary, dt: float, bodies: Array, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> Dictionary:
	var p0: Vector3 = st.p
	var v: Vector3 = st.v
	var p1 := p0 + v * dt
	var sl := p0.distance_to(p1)
	if sl < 0.00001:
		return {}
	var dir := (p1 - p0) / sl
	var best := sl
	var out := {}
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(p0, p1, 1)
		q.exclude = exclude
		var wh := space.intersect_ray(q)
		if not wh.is_empty():
			best = p0.distance_to(wh.position)
			out = {"kind": "world", "point": wh.position, "normal": wh.normal, "dir": dir}
	if p1.y < 0.0:
		var fd := sl * p0.y / maxf(p0.y - p1.y, 0.000001) if p0.y > 0.0 else 0.0
		if fd < best:
			best = fd
			out = {"kind": "world", "point": p0 + dir * fd, "normal": Vector3.UP, "dir": dir}
	for b in bodies:
		if not is_instance_valid(b) or not _near(b, p0, p0 + dir * best):
			continue
		var h: Dictionary = b.trace(p0, dir, best)
		if not h.is_empty() and float(h.dist) <= best:
			best = float(h.dist)
			out = {"kind": "body", "body": b, "hit": h, "dir": dir}
	st.p = p0 + dir * best
	st.dist = float(st.dist) + best
	v.y -= float(st.g) * dt
	st.v = v
	st.t = float(st.t) + dt
	if out.is_empty() and float(st.dist) >= RANGE:
		out = {"kind": "end", "dir": dir}
	return out

# whether the segment a-c comes near enough body b to trace (cheap; the trace is the real test)
static func _near(b: VoxelBody, a: Vector3, c: Vector3) -> bool:
	var p := b.global_position
	var a2 := Vector2(a.x - p.x, a.z - p.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var tt := clampf(-a2.dot(ac) / maxf(ac.length_squared(), 0.000001), 0.0, 1.0)
	if (a2 + ac * tt).length() > maxf(b.height, b.radius) + 0.4:
		return false
	return minf(a.y, c.y) <= p.y + b.height + 0.3 and maxf(a.y, c.y) >= p.y - 0.6

func _fly_step(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var ex: Array[RID] = [arena.player.get_rid()]
	var h := fly(_st, dt, arena.bodies, arena.get_world_3d().direct_space_state, ex)
	_note_ms(t0)
	_p = _st.p
	_dir = (_st.v as Vector3).normalized()
	_vis *= exp(-dt * 12.0)
	last.flown_m = snappedf(float(_st.dist), 0.1)
	if not h.is_empty():
		_hit(h)

func _hit(h: Dictionary) -> void:
	match String(h.kind):
		"body":
			_hit_body(h.body, h.hit, h.dir)
		"world":
			_hit_world(h.point, h.dir)
		_:
			let_go()            # the line ran out

## The harpoon going into body b at trace hit h, flying along dir (static, for the checks): a small hole punched
## where it goes in (clear of the hips), a little hurt. Returns {res (carve's), part, tip (world: the point, buried),
## local, ldir (the point and its direction in the part's bone space), stuck: false if the part it hit is gone or the
## body shattered (frozen)}.
static func stick(b: VoxelBody, h: Dictionary, dir: Vector3) -> Dictionary:
	var at: Vector3 = h.point
	var part := String(h.part)
	var a := at - dir * 0.01
	var c := at + dir * HOLE_D
	var sh := _off_hips(b, a, c, HOLE_R)
	var res := b.carve(a + sh, c + sh, HOLE_R, 0.05, 2)
	var tip := at + dir * SINK
	var out := {"res": res, "part": part, "tip": tip, "local": Vector3.ZERO, "ldir": Vector3.FORWARD, "stuck": false}
	if bool(res.get("shattered", false)) or not b.parts.has(part) or bool(b.parts[part].gone):
		return out
	if b.alive and b.hurt(HURT):
		res.killed = true
	var xf := bone_xf(b, part)
	out.local = xf.affine_inverse() * tip
	out.ldir = (xf.basis.inverse() * dir).normalized()
	out.stuck = true
	return out

## A part's bone, world (what the harpoon in it rides on).
static func bone_xf(b: VoxelBody, part: String) -> Transform3D:
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(b.parts[part].bone))

## Where the harpoon in a part is now (static, for the checks): [point, direction] (world), or [] if the body's been
## freed or the part is gone (cut off by something).
static func ride(b, part: String, local: Vector3, ldir: Vector3) -> Array:
	if not is_instance_valid(b) or not b.parts.has(part) or bool(b.parts[part].gone):
		return []
	var xf := bone_xf(b, part)
	return [xf * local, (xf.basis * ldir).normalized()]

## A part's joint (where it hangs from its parent), world.
static func joint(b: VoxelBody, part: String) -> Vector3:
	return bone_xf(b, part).origin

# the shift that keeps a carve round a-c (radius r) clear of the hips: a carve through the root joint would take all
# above it off (a carve keeps the side toward a joint's parent, and the root has none)
static func _off_hips(b: VoxelBody, a: Vector3, c: Vector3, r: float) -> Vector3:
	var hips := b.skeleton.global_transform * b.skeleton.get_bone_global_pose(0).origin
	var gap := r + b.vm * 1.5
	var ac := c - a
	var tt := clampf((hips - a).dot(ac) / maxf(ac.length_squared(), 0.000001), 0.0, 1.0)
	var off := a + ac * tt - hips
	var d := off.length()
	if d >= gap:
		return Vector3.ZERO
	return (off / d if d > 0.001 else Vector3.UP) * (gap - d)

func _hit_body(b: VoxelBody, h: Dictionary, dir: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	var s := stick(b, h, dir)
	_note_ms(t0)
	var res: Dictionary = s.res
	last.hit = String(h.part)
	last.cut = int(res.cut)
	last.killed = bool(last.killed) or bool(res.killed)
	_vis = Vector3.ZERO
	_p = s.tip
	_dir = dir
	sfx("harpoon_hit", h.point)
	hit_stop(0.05, 0.08)
	arena._kick = maxf(float(arena._kick), 0.45)
	if bool(res.get("shattered", false)):
		spray(res, dir, 3.0)    # frozen: the statue bursts
		sfx("shatter", h.point)
		let_go()
		return
	spray(res, -dir, 1.4)       # the cubes out of the hole, back toward you
	var rb := _fling_res(b, res, dir * 1.5 + Vector3.UP, 5.0)
	if not bool(s.stuck):
		# the hole took what it hit off (a hand): it's in that piece
		if rb:
			_into(rb)
		else:
			let_go()
		return
	_mode = "body"
	_t = 0.0
	_body = b
	_part = s.part
	_local = s.local
	_ldir = s.ldir
	_dragged = 0.0
	_taut = 1.0
	_twang = 1.0
	if b.alive:
		b.hit_react(dir, 12, _part)
		b.knock = Vector3.ZERO      # (the flinch, not the shove: it's about to be pulled the other way)
	if _yank:
		_start_tug()

func _hit_world(at: Vector3, dir: Vector3) -> void:
	_mode = "world"
	_t = 0.0
	_vis = Vector3.ZERO
	_p = at + dir * 0.08
	_dir = dir
	last.hit = "world"
	sfx("harpoon_clank", at)
	arena.debris.pop(at, 0.5, 2.0, 40)
	arena._kick = maxf(float(arena._kick), 0.2)

# a carve's pieces flung off at vel, spinning about spin radians a second (the rigid body, or null)
func _fling_res(b: VoxelBody, res: Dictionary, vel: Vector3, spin: float) -> RigidBody3D:
	if (res.pieces as Array).is_empty():
		return null
	last.pieces = int(last.pieces) + (res.pieces as Array).size()
	return arena.pieces.spawn(b, res.pieces, vel, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spin)

# ---------------------------------------------------------------- in a body: dragged in, or tugged and torn

## One step of a body dragged toward to (world: your feet) at speed m/s (static, for the checks): moved level and
## held there (no walking, no shove), facing you, a light one lifted a little off its feet. Returns true once it's
## within stop of to (back on its feet there).
static func drag(b: VoxelBody, to: Vector3, speed: float, stop: float, dt: float) -> bool:
	var d := Vector3(to.x - b.position.x, 0.0, to.z - b.position.z)
	var dl := d.length()
	b.stagger = maxf(b.stagger, 0.2)
	b.knock = Vector3.ZERO
	var mv := clampf(dl - stop, 0.0, speed * dt)
	if mv > 0.0:
		b.position += d / dl * mv
	var lift := 0.0
	if b.alive and not b.fragment:
		lift = float(LIFT.get(b.key, 0.0)) * clampf((dl - mv - stop) / 0.8, 0.0, 1.0)
		if dl > 0.01:
			b.yaw = lerp_angle(b.yaw, atan2(d.x, d.z), 1.0 - exp(-dt * 10.0))
		b.flinch = maxf(b.flinch, 0.75)     # leaning back against the line, arms flung up
	b.position.y = lift
	return dl - mv <= stop + 0.001

# in a body: dragged in (or tugged); true while the reel strains
func _body_step(dt: float) -> bool:
	if not is_instance_valid(_body):
		_lost_part()            # freed (a lying piece knocked flying is a piece again: it may be in that)
		return false
	if _body.airborne:
		let_go()                # knocked flying out of it
		return false
	var r := ride(_body, _part, _local, _ldir)
	if r.is_empty():
		_lost_part()
		return false
	_p = r[0]
	_dir = r[1]
	if _tug >= 0.0:
		return _tug_step(dt)
	var before := _body.position
	var to: Vector3 = arena.player.global_position
	if not _body.alive and not _body.fragment and _body.parts.has("torso") and not bool(_body.parts.torso.gone):
		# a corpse lies out from its feet: its middle is what's brought up in front of you, so it never ends up under you
		var mid := joint(_body, "torso")
		to -= Vector3(mid.x - _body.position.x, 0.0, mid.z - _body.position.z)
	var done := drag(_body, to, DRAG_V * float(HEFT.get(_body.key, 1.0)), DRAG_TO, dt)
	_dragged += Vector2(_body.position.x - before.x, _body.position.z - before.z).length()
	last.dragged_m = snappedf(_dragged, 0.1)
	_dragging = _dragged > 0.0 and not done
	r = ride(_body, _part, _local, _ldir)
	_p = r[0]
	_dir = r[1]
	if done or _t > DRAG_MAX:
		_arrived()
		return false
	return true

# dragged all the way: the barbs tear out (a few cubes) and it's left staggering in front of you
func _arrived() -> void:
	var b := _body
	var to: Vector3 = arena.player.global_position + Vector3(0, 1.1, 0) - _p
	if b.alive:
		b.stagger = maxf(b.stagger, LET_GO)
		b.flinch = 1.0
	var t0 := Time.get_ticks_usec()
	var res := b.carve(_p, _p, 0.03, 0.05, 1)
	_note_ms(t0)
	last.cut = int(last.cut) + int(res.cut)
	last.killed = bool(last.killed) or bool(res.killed)
	spray(res, to.normalized(), 1.8)
	_fling_res(b, res, to.normalized() * 2.0, 4.0)
	sfx("shatter" if bool(res.get("shattered", false)) else "harpoon_rip", _p, -8.0, 1.3)
	arena._kick = maxf(float(arena._kick), 0.3)
	let_go()

func _start_tug() -> void:
	_tug = 0.0
	_tug_k = 0.0
	_taut = 1.0
	_twang = 1.0
	last.move = "yank"
	sfx("harpoon_taut")
	if top_down():
		arena.avatar.attack = 0.45      # Jared hauls back on it

# the tug: the line taut, the body jerked toward you; then the tear
func _tug_step(dt: float) -> bool:
	_tug += dt
	var b := _body
	var k := _ease(_tug / TUG_T)
	var to: Vector3 = arena.player.global_position - b.position
	to.y = 0.0
	if to.length() > CLOSE:
		b.position += to.normalized() * minf(TUG_JERK * (k - _tug_k), to.length() - CLOSE)
	_tug_k = k
	b.stagger = maxf(b.stagger, 0.2)
	b.knock = Vector3.ZERO
	if b.alive:
		b.flinch = maxf(b.flinch, 0.9)
	var r := ride(b, _part, _local, _ldir)
	_p = r[0]
	_dir = r[1]
	if _tug >= TUG_T:
		_tear()
		return false
	return true

## The right click's tear (static, for the checks): a limb or the head the harpoon is in comes off whole, everything
## hanging from it too (VoxelBody.sever; the head kills), and a ragged ball is carved out of the stump for the spray;
## in the torso (or anything else) a ball CHUNK_R is torn out round at instead (clear of the hips). Returns sever's /
## carve's result (bits: the cubes to spray) with "joint" (world: where it tore) and "severed".
static func yank(b: VoxelBody, part: String, at: Vector3) -> Dictionary:
	var base := part.trim_suffix("_l").trim_suffix("_r")
	if LIMBS.has(base) and b.parts.has(part) and not bool(b.parts[part].gone):
		var j := joint(b, part)
		var bi := int(b.parts[part].bone)
		var pj := j + Vector3.DOWN
		if b.model.bone_parent[bi] >= 0:
			pj = b.skeleton.global_transform * b.skeleton.get_bone_global_pose(b.model.bone_parent[bi]).origin
		var res := b.sever(part)
		res["joint"] = j
		res["severed"] = not bool(res.get("shattered", false)) and not (res.parts as Array).is_empty()
		if bool(res.severed):
			# the stump's ragged edge: where the body begins from the joint toward the one above it (a shoulder or a
			# hip joint sits out in the limb, off the body)
			var at_j := j
			var hs := b.trace(j, (pj - j).normalized(), 0.4)
			if not hs.is_empty():
				at_j = (hs.point as Vector3) + (pj - j).normalized() * STUMP_R * 0.8
			var sh := _off_hips(b, at_j, at_j, STUMP_R)
			var stump := b.carve(at_j + sh, at_j + sh, STUMP_R, 0.03, 1)
			(res.bits as Array).append_array(stump.bits)
			(res.pieces as Array).append_array(stump.pieces)
			res.cut = int(res.cut) + int(stump.cut)
			res.killed = bool(res.killed) or bool(stump.killed)
			res.joint = at_j
		return res
	var sh2 := _off_hips(b, at, at, CHUNK_R)
	var res2 := b.carve(at + sh2, at + sh2, CHUNK_R, 0.06, 1)
	res2["joint"] = at + sh2
	res2["severed"] = false
	return res2

func _tear() -> void:
	_tug = -1.0
	var b := _body
	var me: Vector3 = arena.player.global_position + Vector3(0, 1.1, 0)
	var to_me := (me - _p).normalized()
	var flat := Vector3(to_me.x, 0.0, to_me.z).normalized()
	var t0 := Time.get_ticks_usec()
	var res := yank(b, _part, _p)
	_note_ms(t0)
	last.cut = int(last.cut) + int(res.cut)
	last.killed = bool(last.killed) or bool(res.killed)
	if bool(res.severed):
		last.severed = (res.parts as Array).duplicate()
	sfx("harpoon_rip", res.joint)
	hit_stop(0.09, 0.05)
	arena._kick = maxf(float(arena._kick), 1.0)
	_kick = 1.2
	if bool(res.get("shattered", false)):
		spray(res, to_me, 3.0)
		sfx("shatter", _p)
		let_go()
		return
	spray(res, to_me, 2.6)
	if b.alive:
		b.flinch = 1.0
		b.stagger = maxf(b.stagger, 0.7)
		# stumbling after it (a knock slides knock / 6 metres), not into you
		var room := Vector2(me.x - b.position.x, me.z - b.position.z).length() - CLOSE
		b.knock = flat * 6.0 * clampf(room, 0.0, 0.2 if bool(res.severed) else 0.4)
	var rb := _fling_res(b, res, to_me * YANK_V + Vector3.UP * 2.0, 8.0)
	if bool(res.severed) and rb:
		_into(rb)               # it comes at you on the line
	else:
		let_go()

# ---------------------------------------------------------------- in a piece, in a wall, coming back

# the harpoon now in rigid piece rb (where it is now)
func _into(rb: RigidBody3D) -> void:
	_mode = "piece"
	_t = 0.0
	_rb = rb
	_body = null
	var inv := rb.global_transform.affine_inverse()
	_local = inv * _p
	_ldir = (inv.basis * _dir).normalized()
	_taut = 1.0

# the part it was in is gone (cut off by something else) or the body freed: it's in a piece that just came off with
# that part, if there is one near (pulled in on the line), or it comes back
func _lost_part() -> void:
	var list: Array = arena.pieces.list()
	for i in range(list.size() - 1, -1, -1):
		var pc: Dictionary = list[i]
		if float(pc.t) > 0.5:
			break
		var rb = pc.rb
		if not is_instance_valid(rb) or (rb as RigidBody3D).global_position.distance_to(_p) > 1.5:
			continue
		for e in pc.cells:
			if String(e.part) == _part:
				_into(rb)
				return
	let_go()

# in a piece flying at you on the line: steered at you till it's close, then let go (it drops at your feet)
func _piece_step(dt: float) -> bool:
	if not is_instance_valid(_rb):
		let_go()
		return false
	var xf := _rb.global_transform
	_p = xf * _local
	_dir = (xf.basis * _ldir).normalized()
	var to: Vector3 = arena.player.global_position + Vector3(0, 1.1, 0) - _rb.global_position
	if Vector2(to.x, to.z).length() < CATCH or _t > 1.4:
		_rb.linear_velocity *= 0.3
		let_go()
		return false
	_rb.linear_velocity = _rb.linear_velocity.lerp(to.normalized() * YANK_V, 1.0 - exp(-dt * 6.0))
	return true

# coming back empty, the point trailing: wound in till its tail is at the muzzle, then onto the rail
func _reel_step(dt: float) -> void:
	var mz := _muzzle()
	var away := _p - mz
	var d := away.length()
	if d > 0.001:
		_dir = _dir.slerp(away / d, 1.0 - exp(-dt * 12.0)).normalized()
	var mv := minf(REEL_V * dt, maxf(0.0, d - TAIL))
	if d > 0.001:
		_p -= away / d * mv
	if d - mv <= TAIL + 0.1:
		_mode = "ready"
		_load = 0.0
		_cd = COOLDOWN
		_proj.visible = false
		sfx("harpoon_load")

# ---------------------------------------------------------------- the look

static func _ease(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)

# where the line comes out of the gun (world): the view's muzzle, or top-down the one in Jared's hands
func _muzzle() -> Vector3:
	if top_down():
		var g = _hand_parts.get("guide")
		if is_instance_valid(g) and (g as Node3D).is_inside_tree():
			return (g as Node3D).global_position
		return eye() + look() * 0.6
	return (_parts.guide as Node3D).global_position

# where the loaded harpoon's point is (world): in the view's rail, or the one in Jared's hands
func _rail_tip() -> Vector3:
	var bits: Dictionary = _hand_parts if top_down() else _parts
	var g = bits.get("harpoon")
	if is_instance_valid(g) and (g as Node3D).is_inside_tree():
		return (g as Node3D).global_transform * Vector3.ZERO
	return _muzzle()

# the reel: paying out fast as it flies, winding in while it drags or comes back, cranked hard on a tug
func _spin(dt: float) -> void:
	var want := 0.0
	match _mode:
		"fly":
			want = -40.0
		"body":
			want = 14.0 if _tug >= 0.0 else (30.0 if _dragging else 0.0)
		"piece", "reel":
			want = 30.0
	_reel_v = lerpf(_reel_v, want, 1.0 - exp(-dt * 10.0))
	_reel_ang = wrapf(_reel_ang + _reel_v * dt, -PI, PI)

func _place_proj() -> void:
	_proj.visible = _mode != "ready"
	if not _proj.visible:
		return
	var d := _dir
	var p := _p + _vis
	if _mode == "body" or _mode == "piece":
		# pulled by its line it swings round to point along it; close in it's drawn driven deeper (through them), so
		# its tail stays out in front of the muzzle
		var mz := _muzzle()
		if p.distance_to(mz) > 0.01:
			d = d.slerp((p - mz).normalized(), _taut).normalized()
		p += d * maxf(0.0, TAIL + 0.08 - (p - mz).dot(d))
	var bs := dir_basis(d)
	if _mode == "world":
		bs = bs * Basis(Vector3.RIGHT, 0.12 * sin(_t * 40.0) * exp(-_t * 6.0))     # quivering
	_proj.global_transform = Transform3D(bs, p)
	_proj_m.scale = Vector3(2.8, 2.8, 1.0) if top_down() else Vector3.ONE

# the gun in the view: kicked back and up on a shot, hauled back on a tug, leaning in and shaking while the reel
# strains; back on the rail the harpoon slides in, then the gun tilts as the air's pumped up
func _pose_view() -> void:
	var base := _aim_xf(REST_GRIP, REST_AT)
	var tg := _ease(_tug / TUG_T) if _tug >= 0.0 else 0.0
	var pump := sin(clampf((_load - LOAD_T) / PUMP_T, 0.0, 1.0) * PI)
	var shake := Vector3(sin(_clock * 63.0), sin(_clock * 49.0 + 1.3), 0.0) * 0.004 * (_pull + tg)
	var o := base.origin + Vector3(0.0, 0.012 * _kick + 0.02 * tg - 0.01 * pump, 0.07 * _kick + 0.1 * tg - 0.035 * _pull) + shake
	o.y += sin(_clock * 1.7) * 0.004
	var bs := base.basis * Basis(Vector3.RIGHT, -(0.13 * _kick + 0.22 * tg) + 0.03 * _pull) * Basis(Vector3.BACK, 0.35 * pump)
	_gun.transform = Transform3D(bs, o)
	_pose_bits(_parts)

# the loaded harpoon (hidden while it's out, sliding in when it's back) and the reel's turn
func _pose_bits(bits: Dictionary) -> void:
	var hp: Node3D = bits.harpoon
	hp.visible = _mode == "ready"
	hp.position = RAIL + Vector3(0, 0, 0.3 * (1.0 - _ease(_load / LOAD_T)))
	(bits.reel as Node3D).rotation.x = _reel_ang

func _pose_hand() -> void:
	if not is_instance_valid(_hand):
		return
	(_hand.get_child(0) as Node3D).position = Vector3(0, 0, -0.08 * _kick)
	_pose_bits(_hand_parts)

# the line: from the muzzle to the harpoon's tail, sagging as it pays out or lies slack, straight when taut, quivering
# a moment after it snaps taut; a thin ribbon facing the camera, a couple of pixels wide however far it goes
func _draw_cable() -> void:
	var im: ImmediateMesh = _cable.mesh
	im.clear_surfaces()
	if _mode == "ready":
		return
	var a := _muzzle()
	var b := _proj.global_transform * Vector3(0, 0, TAIL)
	var ln := a.distance_to(b)
	if ln < 0.02:
		return
	var td := top_down()
	_cable_mat.albedo_color = CABLE_TD if td else CABLE
	var k := 0.0035 if td else 0.0022
	var sag := (1.0 - _taut) * clampf(ln * 0.05, 0.0, 0.8)
	var across := (b - a).cross(Vector3.UP)
	across = across.normalized() if across.length() > 0.001 else Vector3.RIGHT
	var wob := _twang * minf(0.05, ln * 0.02) * sin(_clock * 75.0)
	var cp: Vector3 = arena.cam.global_position
	var n := 20
	var pts := PackedVector3Array()
	for i in n + 1:
		var s := float(i) / n
		pts.append(a.lerp(b, s) + Vector3.DOWN * sag * 4.0 * s * (1.0 - s) + across * wob * sin(s * PI * 3.0))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var s0 := (p1 - p0).cross(cp - p0).normalized() * (0.002 + cp.distance_to(p0) * k)
		var s1 := (p1 - p0).cross(cp - p1).normalized() * (0.002 + cp.distance_to(p1) * k)
		for v in [p0 - s0, p0 + s0, p1 + s1, p0 - s0, p1 + s1, p1 - s1]:
			im.surface_add_vertex(v)
	im.surface_end()

func _note_ms(t0: int) -> void:
	_ms = maxf(_ms, (Time.get_ticks_usec() - t0) / 1000.0)
	last.ms = snappedf(_ms, 0.01)

func hand_mesh() -> Node3D:
	var root := Node3D.new()
	var m := Node3D.new()
	root.add_child(m)
	m.scale = Vector3.ONE * 1.35
	_hand_parts = gun_model(m, true)
	_hand = root
	_pose_bits(_hand_parts)
	return root

func hand_pose() -> String:
	return "shotgun"

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var dim := Color(col.r * 0.55, col.g * 0.55, col.b * 0.6, col.a)
	var spear := Color(col.r, col.g, col.b, col.a * (1.0 if _mode == "ready" else 0.3))
	for e in [[Rect2(0.1, 2.3, 2.1, 0.9), dim], [Rect2(1.9, 2.7, 0.6, 1.5), dim], [Rect2(2.0, 2.0, 5.9, 0.9), col],
			[Rect2(7.8, 1.85, 0.6, 1.2), dim], [Rect2(2.6, 1.55, 6.6, 0.35), spear], [Rect2(9.1, 1.35, 0.7, 0.75), spear]]:
		ci.draw_rect(Rect2(r.position + (e[0] as Rect2).position * u, (e[0] as Rect2).size * u), e[1])
	ci.draw_arc(r.position + Vector2(3.6, 3.5) * u, 0.75 * u.y, 0.0, TAU, 14, col, maxf(1.0, 0.3 * u.y))

# ---------------------------------------------------------------- checks

static func _grunt(host: Node, at: Vector3, key: String = "grunt") -> VoxelBody:
	var b := VoxelBody.new()
	host.add_child(b)
	# the arena's own size for the kind (a grunt: 0.023 m cubes)
	var cube := float(VoxelArena.HEIGHT[key]) / float(VoxelModel.get_model(key).rig.get("ref_rows", 80))
	b.setup(key, cube, 1, StandardMaterial3D.new())
	b.position = at
	b.animate(0.0, false)
	return b

# flies st till it hits something (at most n frames): [what it hit, frames, the dearest frame's ms]
static func _fly_till(st: Dictionary, bodies: Array, n: int) -> Array:
	var none: Array[RID] = []
	var max_ms := 0.0
	for i in n:
		var t0 := Time.get_ticks_usec()
		var h := fly(st, 1.0 / 60.0, bodies, null, none)
		max_ms = maxf(max_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		if not h.is_empty():
			return [h, i + 1, max_ms]
	return [{}, n, max_ms]

## A grunt at the origin facing +z (chest at about y 1.0, head 1.43-1.8): fired at from 6 m it hits the chest and
## sticks (a small hole), the point riding on the part as the body moves; dragged in from 6 m (and a corpse); the
## nearer of two in a row is the one hit; yanking a forearm, an arm, a thigh, a shin, a hand, the head off; a chest
## chunk; a frozen one shattering; the floor; the line running out; a corpse picked top-down; the part cut off and the
## body freed.
static func checks(host: Node) -> Array:
	var out := []
	var imm := VoxelBody.immortal
	VoxelBody.immortal = false
	var made := []
	# fired at the chest from 6 m: it flies there and hits the torso
	var b := _grunt(host, Vector3.ZERO)
	made.append(b)
	var fl := _fly_till(launch_state(Vector3(0, 1.05, 6.0), Vector3(0, 0, -SPEED), GRAV), [b], 60)
	var h: Dictionary = fl[0]
	var ok: bool = String(h.get("kind", "")) == "body" and h.body == b and String(h.hit.part) == "torso"
	out.append([ok and int(fl[1]) >= 7 and int(fl[1]) <= 9,
		"fired from 6 m it flies there in %d frames and hits the chest (%.2f ms a frame at most)" % [int(fl[1]), float(fl[2])]])
	if not ok:
		for x in made:
			(x as Node).queue_free()
		VoxelBody.immortal = imm
		return out
	# it sticks: a small hole, a little hurt; the point rides on the part
	var t0 := Time.get_ticks_usec()
	var s := stick(b, h.hit, h.dir)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var res: Dictionary = s.res
	out.append([bool(s.stuck) and int(res.cut) > 5 and int(res.cut) < 150 and b.alive and b.hp < 100.0 and (res.pieces as Array).is_empty(),
		"it sticks in the chest: a small hole (%d cubes, %.1f ms), a little hurt (hp %.0f)" % [int(res.cut), ms, b.hp]])
	var r0 := ride(b, s.part, s.local, s.ldir)
	b.position += Vector3(1.0, 0.0, -2.0)
	var r1 := ride(b, s.part, s.local, s.ldir)
	out.append([r0.size() == 2 and r1.size() == 2 and (r0[0] as Vector3).distance_to(s.tip) < 0.01
		and ((r1[0] as Vector3) - (r0[0] as Vector3) - Vector3(1.0, 0.0, -2.0)).length() < 0.01, "the point rides on the part as the body moves"])
	b.position = Vector3.ZERO
	# dragged in from 6 m to 1.4 m in front at 7 m/s, lifted a little on the way, let go on its feet
	var feet := Vector3(0, 0, 6.0)
	var steps := 0
	var lifted := 0.0
	var done := false
	while steps < 300 and not done:
		done = drag(b, feet, DRAG_V, DRAG_TO, 1.0 / 60.0)
		lifted = maxf(lifted, b.position.y)
		steps += 1
	var dl := Vector2(feet.x - b.position.x, feet.z - b.position.z).length()
	out.append([done and absf(dl - DRAG_TO) < 0.02 and absf(steps / 60.0 - (6.0 - DRAG_TO) / DRAG_V) < 0.05,
		"dragged in at %.0f m/s from 6 m, let go %.2f m in front after %.2f s" % [DRAG_V, dl, steps / 60.0]])
	out.append([lifted > 0.02 and b.position.y == 0.0 and b.stagger > 0.0 and b.knock == Vector3.ZERO,
		"held as it's dragged (no walking, no shove), lifted off its feet a little (%.2f m), back on them at the end" % lifted])
	var r2 := ride(b, s.part, s.local, s.ldir)
	out.append([r2.size() == 2 and (r2[0] as Vector3).z > 4.0, "the harpoon came along in it (point at z %.2f)" % ((r2[0] as Vector3).z if r2.size() == 2 else 0.0)])
	# a corpse is dragged in too, along the floor
	var bd := _grunt(host, Vector3(4, 0, 0))
	made.append(bd)
	bd.hurt(500.0)
	steps = 0
	done = false
	while steps < 300 and not done:
		done = drag(bd, Vector3(4, 0, 8), DRAG_V, DRAG_TO, 1.0 / 60.0)
		steps += 1
	out.append([not bd.alive and done and bd.position.y == 0.0 and absf(bd.position.z - (8.0 - DRAG_TO)) < 0.02,
		"a corpse is dragged in along the floor (%.2f s)" % (steps / 60.0)])
	# two in a row: the nearer is the one hit
	var n1 := _grunt(host, Vector3(12, 0, 0))
	var n2 := _grunt(host, Vector3(12, 0, -1.5))
	made.append_array([n1, n2])
	fl = _fly_till(launch_state(Vector3(12, 1.05, 6.0), Vector3(0, 0, -SPEED), GRAV), [n2, n1], 60)
	h = fl[0]
	out.append([String(h.get("kind", "")) == "body" and h.body == n1, "two in a row: it sticks in the nearer"])
	# yanked off whole at the joint: a limb and all below it, the cubes spraying from the stump; still alive
	for lc in [["forearm_l", ["forearm_l", "hand_l"]], ["arm_r", ["arm_r", "forearm_r", "hand_r"]],
			["thigh_l", ["thigh_l", "shin_l", "foot_l"]], ["shin_r", ["shin_r", "foot_r"]], ["hand_r", ["hand_r"]]]:
		var bl := _grunt(host, Vector3(16, 0, 0))
		made.append(bl)
		var part: String = lc[0]
		var want: Array = lc[1]
		t0 = Time.get_ticks_usec()
		var ry := yank(bl, part, joint(bl, part))
		ms = (Time.get_ticks_usec() - t0) / 1000.0
		var got: Array = ry.parts
		var same := got.size() == want.size() and want.all(func(x): return got.has(x))
		var legs := 1 if part.begins_with("thigh") or part.begins_with("shin") else 0
		out.append([bool(ry.severed) and same and bl.alive and not bool(bl.parts.torso.gone) and not bool(bl.parts.head.gone)
			and bl.legs_lost() == legs and (ry.pieces as Array).size() >= want.size() and (ry.bits as Array).size() > 3,
			"yanking the %s takes off %s whole, cubes spray from the joint (%d), alive (%.1f ms)" % [part, ", ".join(got), (ry.bits as Array).size(), ms]])
	# the head: off, dead
	var bh := _grunt(host, Vector3(20, 0, 0))
	made.append(bh)
	var rh := yank(bh, "head", joint(bh, "head"))
	out.append([bool(rh.severed) and bool(rh.head_off) and bool(rh.killed) and not bh.alive and (rh.parts as Array) == ["head"],
		"yanking the head off kills (%s)" % ", ".join(rh.parts)])
	# the chest: a chunk torn out, nothing else off
	var bt := _grunt(host, Vector3(24, 0, 0))
	made.append(bt)
	var ht := bt.trace(Vector3(24, 1.05, 3.0), Vector3(0, 0, -1), 5.0)
	t0 = Time.get_ticks_usec()
	var rt := yank(bt, String(ht.get("part", "torso")), (ht.get("point", Vector3(24, 1.05, 0.1)) as Vector3) + Vector3(0, 0, -SINK))
	ms = (Time.get_ticks_usec() - t0) / 1000.0
	out.append([not bool(rt.severed) and int(rt.cut) > 150 and bt.alive and not bool(bt.parts.torso.gone) and not bool(bt.parts.head.gone)
		and bt.legs_lost() == 0 and (rt.bits as Array).size() > 100, "in the chest it tears a chunk out (%d cubes, %.1f ms), nothing else off" % [int(rt.cut), ms]])
	# frozen: it shatters as the harpoon goes in
	var bf := _grunt(host, Vector3(28, 0, 0))
	made.append(bf)
	bf.chill(1.0)
	var hf := bf.trace(Vector3(28, 1.05, 3.0), Vector3(0, 0, -1), 5.0)
	var sf := stick(bf, hf, Vector3(0, 0, -1)) if not hf.is_empty() else {"res": {}, "stuck": true}
	out.append([bool((sf.res as Dictionary).get("shattered", false)) and not bool(sf.stuck) and bf.cubes_left() == 0 and not bf.alive,
		"a frozen one shatters as it goes in (%d cubes)" % ((sf.res as Dictionary).get("bits", []) as Array).size()])
	# the floor: it stops there
	fl = _fly_till(launch_state(Vector3(32, 1.5, 0), Vector3(0, -0.3, -1).normalized() * SPEED, GRAV), [], 120)
	h = fl[0]
	out.append([String(h.get("kind", "")) == "world" and absf((h.point as Vector3).y) < 0.001 and (h.normal as Vector3) == Vector3.UP,
		"fired at the floor it stops in it (%s)" % str((h.get("point", Vector3.INF) as Vector3).snapped(Vector3.ONE * 0.01))])
	# the line runs out
	var sr := launch_state(Vector3(36, 1.5, 0), Vector3(0, 0, -SPEED), 0.0)
	fl = _fly_till(sr, [], 120)
	h = fl[0]
	out.append([String(h.get("kind", "")) == "end" and absf(float(sr.dist) - RANGE) < SPEED / 60.0 + 0.01,
		"the line runs out at %.1f m" % float(sr.dist)])
	# top-down: a corpse lying on the floor, picked by a ray from the camera up behind, the harpoon flown down into it
	# from Jared's chest
	var bc := _grunt(host, Vector3(44, 0, 0))
	made.append(bc)
	bc.hurt(500.0)
	bc.dead_t = 1.0
	bc.animate(0.0, false)
	var tc := joint(bc, "torso")
	var chest := Vector3(44, 1.2, 4.0)
	var cam_at := chest + Vector3(0, 12.0, 6.0)
	var pk := pick([bc], cam_at, (tc - cam_at).normalized())
	var hit_c := false
	if pk != Vector3.INF:
		fl = _fly_till(launch_state(chest, (pk - chest).normalized() * SPEED, 0.0), [bc], 60)
		h = fl[0]
		hit_c = String(h.get("kind", "")) == "body" and h.body == bc
	out.append([pk != Vector3.INF and pk.y < 0.5 and hit_c, "top-down: a corpse lying under the mouse is picked (y %.2f) and harpooned" % pk.y])
	# the part it's in cut off, or the body freed: it lets go
	var bx := _grunt(host, Vector3(40, 0, 0))
	var before := ride(bx, "forearm_l", Vector3.ZERO, Vector3.FORWARD)
	bx.sever("forearm_l")
	var cut_off := ride(bx, "forearm_l", Vector3.ZERO, Vector3.FORWARD)
	bx.free()
	var freed := ride(bx, "torso", Vector3.ZERO, Vector3.FORWARD)
	out.append([before.size() == 2 and cut_off.is_empty() and freed.is_empty(), "the part it's in cut off, or the body freed: it lets go"])
	for x in made:
		(x as Node).queue_free()
	VoxelBody.immortal = imm
	return out
