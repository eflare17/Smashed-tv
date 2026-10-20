class_name VoxelMeleeSpear
extends VoxelMelee
## The spear (the owner, 20 Oct: five melee weapons, each doing something different): it pierces in a line, and it
## can be thrown. A long wooden shaft with a steel leaf tip bound on with red cord, held under the arm, point up ahead.
## Left click is a thrust: the spear draws back and jabs straight out where you look, and the tip's line (from just
## past your eye to 3.2 m out) bores a thin tunnel through every body on it (VoxelBody.carve, a long thin capsule), so
## two or three in a row are skewered at once. Each takes a little damage, a stagger and a small shove along the line,
## and the cubes blow out of the far side. Through the brain it kills; through a limb's joint (elbow, knee, wrist,
## ankle, shoulder, hip, the neck) the limb comes off there (a thin disc cut across it, VoxelBody.slice). Right click
## throws it: it flies at 28 m/s, nose along its path, boring through up to three bodies (a little slower after each;
## after the third it's spent and drops), and sticks in the first wall, pillar or bit of floor it meets, at the angle it
## came in, with a twang. While it's out your hands are empty: left click does nothing and the weapon bar shows it
## spent. Right click again (or walking up to it) calls it back: it flies to your hand in a third of a second, boring
## through anyone in the way. Top-down the thrust and the throw go level from Jared's chest toward the mouse, and the
## thrown spear is a thing in the world you can see. With an enemy right up close the spear in your hands slides back
## through the grip, so its point stays out of him till you jab. Owned by the voxel session.

const SHAFT := 1.6              # metres of wooden shaft
const BUTT_Z := 0.3             # the spear's own space: the grip near the butt (this far back, +z) ...
const TIP_Z := -1.7             # ... and the point this far forward (-z), its top +y
const THRUST_FROM := 0.3        # the thrust's line: from this far past the eye ...
const THRUST_TO := 3.2          # ... to this far
const THRUST_R := 0.045         # the tunnel's radius, metres
const THRUST_HURT := 8.0
const HP_PER_CUBE := 0.05       # health a body (torso) cube the tunnel takes costs (carve's own)
const BACK_T := 0.06            # the thrust: drawn back by here ...
const OUT_T := 0.1              # ... out by here (the tunnel bored as the tip gets there) ...
const HOLD_T := 0.13            # ... held out till here ...
const THRUST_T := 0.22          # ... and back at rest
const THRUST_CD := 0.4
const JOINT_R := 0.07           # a line this close to a limb's joint takes the limb off there (grunt metres)
const BRAIN_SHARE := 0.03       # a tunnel taking this share of the brain kills
const THROW_SPEED := 28.0
const THROW_G := 3.0            # m/s/s pulling it down (mild; top-down none: it flies level)
const THROW_R := 0.05
const THROW_HURT := 12.0
const PIERCE := 3               # bodies it bores through before it's spent (it drops)
const PIERCE_SLOW := 0.85       # its speed kept through each
const THROUGH := 0.9            # metres past where it goes in that a body is bored (one carve a body)
const SINK := 0.14              # how deep the tip goes into a wall or the floor
const COCK_T := 0.1             # the throw: drawn back over the shoulder this long, then let go
const RECALL_T := 0.35          # seconds it takes to fly back to your hand
const RECALL_HURT := 8.0
const PICKUP_R := 1.2           # walk this close to it stuck somewhere and it comes back
const MAX_FLIGHT := 4.0         # seconds in the air with nothing hit before it comes back by itself
const CATCH_T := 0.16
const SLIDE_MAX := 1.1          # metres the spear in your hands slides back through the grip, an enemy close
const SHOULDER := Vector3(0.3, -0.44, 0.12)     # the sleeve's top, camera space
const WOOD := Color(0.56, 0.4, 0.24)
const STEEL := Color(0.8, 0.82, 0.86)
const DARK := Color(0.3, 0.31, 0.34)
const CORD := Color(0.62, 0.1, 0.08)
const LEATHER := Color(0.24, 0.14, 0.08)
## The joints a line through takes the limb off at: part (no _l / _r) -> [how far past the joint along the limb the
## disc cut goes, its radius] (grunt metres, scaled by height). Measured on a grunt: the shoulder and the hip need the
## disc a little down the limb, or the side kept is the wrong one / the thigh too thick for it. A disc that doesn't
## take the limb off (a brute's thigh, a swarmer's head) goes again, as wide as the part's grid.
const JOINTS := {"head": [0.0, 0.13], "arm": [0.06, 0.15], "forearm": [0.0, 0.13], "hand": [0.0, 0.13],
	"thigh": [0.05, 0.16], "shin": [0.0, 0.13], "foot": [0.0, 0.13]}

var _spear: Node3D              # the spear in the view (under view): its grip at the origin, the tip toward -z
var _shaft: Node3D              # its boxes (under _spear, the glove's not), slid back through the grip by _slide
var _slide := 0.0               # at rest: how far back (metres), to keep the point out of the nearest body
var _slide_drawn := 0.0         # a thrust's: drawn back
var _arm: MeshInstance3D        # the sleeve from the shoulder to the glove (under view)
var _proj: Node3D               # the spear out of the hand (top level, in the world): its origin at the tip
var _proj_m: Node3D             # its boxes (stouter top-down, to be seen from up there)
var _fx: MeshInstance3D         # streaks: behind a thrown spear, along a top-down thrust (world)
var _hand: Node3D               # top-down: the spear in Jared's hand (hidden while it's out)
var _mode := "hand"             # "hand", "fly" (thrown), "stuck" (in a wall or the floor), "back" (called back)
var _out_now := false           # the weapon out (not put away)
var _t := -1.0                  # seconds into a thrust (-1: none)
var _struck := false
var _cock := -1.0               # seconds into a throw's wind-up (-1: none)
var _catch := 0.0               # seconds left of the catch's jolt
var _cd := 0.0
var _clock := 0.0
var _fly := {}                  # the flight (launch_state / fly)
var _vis := Vector3.ZERO        # thrown: how far off its real path it's drawn (from the hand, closing fast)
var _stuck_t := 0.0
var _stuck_b := Basis()
var _back := {}                 # called back: {from, basis, t, p, hit, pierced, limit, spent}
var _streaks := []              # [{a, b, t, dur}]
var _path := []                 # the flying spear's last few tip positions (its streak)
# the view's key poses (camera space: x right, y up, -z forward)
var _rest: Transform3D
var _drawn: Transform3D
var _out: Transform3D
var _cocked: Transform3D

func _build() -> void:
	# at rest the grip is just below the view's corner and the point up and right of the middle (out of the way, and
	# over the shoulder of one standing close); a thrust levels it at what's in front (see thrust)
	_rest = _aim(Vector3(0.3, -0.38, -0.28), Vector3(0.5, 1.2, -3.0))
	_cocked = _aim(Vector3(0.36, 0.0, 0.1), Vector3(0.08, 0.55, -4.0))
	_aim_at(3.0)
	_spear = Node3D.new()
	view.add_child(_spear)
	_shaft = Node3D.new()
	_spear.add_child(_shaft)
	spear_model(_shaft, 1.0, false)
	var glove := mat(Color(0.13, 0.12, 0.12), 0.0, 0.9)
	box(_spear, Vector3(0.075, 0.07, 0.1), Vector3(0, -0.005, 0), glove)
	box(_spear, Vector3(0.02, 0.03, 0.06), Vector3(-0.045, 0.012, -0.01), glove)     # the thumb over the top
	_spear.transform = _rest
	_arm = box(view, Vector3(0.075, 0.075, 1.0), Vector3.ZERO, mat(Color(0.1, 0.11, 0.14), 0.0, 0.95))
	_proj = Node3D.new()
	_proj.top_level = true
	add_child(_proj)
	_proj_m = Node3D.new()
	_proj.add_child(_proj_m)
	_proj_m.position = Vector3(0, 0, -TIP_Z)
	spear_model(_proj_m, 1.5, true)
	_proj.visible = false
	_fx = MeshInstance3D.new()
	_fx.mesh = ImmediateMesh.new()
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.vertex_color_use_as_albedo = true
	_fx.material_override = fm
	_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.top_level = true
	add_child(_fx)

## The spear's boxes under parent: the grip at the origin, the tip toward -z, top +y, metres; thick makes the shaft
## stouter (the thrown one and Jared's, to be seen from up top); shadows: cast them (in the world).
static func spear_model(parent: Node3D, thick: float, shadows: bool) -> void:
	var wood := VoxelMelee.mat(WOOD, 0.0, 0.8)
	var steel := VoxelMelee.mat(STEEL, 0.85, 0.25)
	var dark := VoxelMelee.mat(DARK, 0.6, 0.45)
	var cord := VoxelMelee.mat(CORD, 0.0, 0.9)
	var leather := VoxelMelee.mat(LEATHER, 0.0, 0.9)
	var w := 0.034 * thick
	var lw := 1.0 + (thick - 1.0) * 0.6          # the leaf widens less than the shaft
	var bx := [
		[Vector3(w, w, SHAFT), Vector3(0, 0, BUTT_Z - SHAFT * 0.5), wood],
		[Vector3(w * 1.25, w * 1.25, 0.05), Vector3(0, 0, BUTT_Z), dark],           # the butt cap
		[Vector3(w * 1.2, w * 1.2, 0.22), Vector3(0, 0, 0.0), leather],             # the grip
		[Vector3(w * 1.3, w * 1.3, 0.1), Vector3(0, 0, -1.36), dark],               # the socket
		[Vector3(0.012 * thick, 0.07 * thick, 0.012 * thick), Vector3(0, -0.05 * thick, -1.22), cord],   # a tassel
		[Vector3(0.014 * lw, 0.024 * lw, 0.27), Vector3(0, 0, -1.55), steel],       # the leaf's midrib
	]
	for z in [-1.2, -1.24, -1.28]:                   # the binding
		bx.append([Vector3(w * 1.45, w * 1.45, 0.018), Vector3(0, 0, z), cord])
	# the leaf: flat, widest a third of the way up, to a point (at TIP_Z)
	for e in [[0.036, -1.425, 0.03], [0.062, -1.47, 0.06], [0.074, -1.53, 0.06], [0.06, -1.585, 0.05], [0.04, -1.6325, 0.045],
			[0.018, -1.6775, 0.045]]:
		bx.append([Vector3(float(e[0]) * lw, 0.012 * lw, float(e[2])), Vector3(0, 0, float(e[1])), steel])
	for e in bx:
		var mi := VoxelMelee.box(parent, e[0], e[1], e[2])
		if shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

static func _aim(at: Vector3, to: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(to - at, Vector3.UP), at)

# the thrust's two poses, the spear's line through the middle of the view d metres out: drawn back along it, then out
func _aim_at(d: float) -> void:
	_out = _aim(Vector3(0.16, -0.24, -0.62), Vector3(0, 0, -d))
	_drawn = Transform3D(_out.basis, _out.origin + _out.basis.z * 0.42 + Vector3(0.04, -0.06, 0.0))

func on_select() -> void:
	_out_now = true

func on_deselect() -> void:
	_out_now = false
	_cock = -1.0

func busy() -> bool:
	return _t >= 0.0 or _cock >= 0.0 or _catch > 0.0

## Thrown: spent (the weapon bar's slot full) till it's back in your hand.
func cooling() -> float:
	if _mode != "hand":
		return 1.0
	return clampf(_cd / THRUST_CD, 0.0, 1.0)

func press(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		thrust()
	elif button == MOUSE_BUTTON_RIGHT:
		if _mode == "hand":
			throw()
		elif _mode == "fly" or _mode == "stuck":
			recall()

## A jab straight out where you look (the tunnel is bored as the tip gets there).
func thrust() -> void:
	if _mode != "hand" or _t >= 0.0 or _cock >= 0.0 or _cd > 0.0:
		return
	_t = 0.0
	_struck = false
	_cd = THRUST_CD
	sfx("spear_thrust")
	_slide_drawn = _slide
	if top_down():
		arena.avatar.attack = 0.5
	else:
		# the view's spear is levelled at the first body on the line (or 3 m out)
		var e := eye()
		var f := look()
		var d := 3.0
		for b in arena.bodies:
			if is_instance_valid(b) and on_line(b, e + f * THRUST_FROM, e + f * THRUST_TO):
				var h: Dictionary = b.trace(e, f, d)
				if not h.is_empty():
					d = float(h.dist)
		_aim_at(clampf(d, 1.0, 3.0))
		# one close: drawn back, the shaft slides back through the grip so the point starts out of him
		_slide_drawn = clampf(-(_drawn * Vector3(0, 0, TIP_Z)).z - (d - 0.1), 0.0, SLIDE_MAX)

## Winds up over the shoulder and lets the spear fly where you look (top-down: level toward the mouse).
func throw() -> void:
	if _mode != "hand" or _t >= 0.0 or _cock >= 0.0 or _cd > 0.0:
		return
	_cock = 0.0
	sfx("spear_throw")
	if top_down():
		arena.avatar.attack = 0.5

## Calls the thrown spear back: it flies to your hand over RECALL_T, boring through anyone in the way.
func recall() -> void:
	if _mode != "fly" and _mode != "stuck":
		return
	_mode = "back"
	_back = {"from": _proj.global_position, "basis": _proj.global_transform.basis.orthonormalized(), "t": 0.0,
		"p": _proj.global_position, "hit": {}, "pierced": 0, "limit": 6, "spent": false}
	_vis = Vector3.ZERO
	_path.clear()
	last = {"move": "recall", "from_m": snappedf(_back.from.distance_to(eye()), 0.1), "bodies": 0, "cut": 0, "parts": [],
		"severed": [], "pieces": 0, "killed": 0, "ms": 0.0}

func hand_mesh() -> Node3D:
	var root := Node3D.new()
	var m := Node3D.new()
	root.add_child(m)
	var s := Node3D.new()
	m.add_child(s)
	s.rotation = Vector3(0, PI, 0)                  # its tip toward +z, out of the fist
	spear_model(s, 1.5, true)
	_hand = root
	root.visible = _mode == "hand"
	return root

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var a := col.a * (1.0 if _mode == "hand" else 0.35)
	for e in [[Rect2(0.2, 2.25, 7.1, 0.5), Color(0.78, 0.58, 0.36)], [Rect2(0.1, 2.15, 0.4, 0.7), Color(0.55, 0.56, 0.6)],
			[Rect2(2.2, 2.15, 1.1, 0.7), Color(0.45, 0.3, 0.2)], [Rect2(6.3, 2.1, 0.7, 0.8), Color(0.9, 0.25, 0.2)],
			[Rect2(7.0, 2.15, 0.5, 0.7), Color(0.6, 0.62, 0.66)], [Rect2(7.5, 1.8, 0.9, 1.4), Color(1, 1, 1)],
			[Rect2(8.4, 1.95, 0.7, 1.1), Color(1, 1, 1)], [Rect2(9.1, 2.25, 0.6, 0.5), Color(1, 1, 1)]]:
		var c: Color = e[1]
		ci.draw_rect(Rect2(r.position + (e[0] as Rect2).position * u, (e[0] as Rect2).size * u), Color(c.r, c.g, c.b, a))

func step(dt: float) -> void:
	_clock += dt
	_cd = maxf(0.0, _cd - dt)
	_catch = maxf(0.0, _catch - dt)
	if _t >= 0.0:
		_t += dt
		if not _struck and _t >= OUT_T - 0.015:
			_struck = true
			_strike()
		if _t >= THRUST_T:
			_t = -1.0
	if _cock >= 0.0:
		_cock += dt
		if _cock >= COCK_T:
			_cock = -1.0
			_let_go()
	match _mode:
		"fly":
			_fly_step(dt)
		"stuck":
			_stuck_step(dt)
		"back":
			_back_step(dt)
	for i in range(_streaks.size() - 1, -1, -1):
		_streaks[i].t = float(_streaks[i].t) + dt
		if float(_streaks[i].t) >= float(_streaks[i].dur):
			_streaks.remove_at(i)
	_pose_view(dt)
	_pose_hand()
	_draw_fx()

# ---------------------------------------------------------------- the thrust

func _strike() -> void:
	var t0 := Time.get_ticks_usec()
	var e := eye()
	var f := look()
	var a := e + f * THRUST_FROM
	var c := e + f * THRUST_TO
	var hits := skewer(arena.bodies, a, c, THRUST_R, THRUST_HURT)
	var info := {"move": "thrust", "bodies": 0, "cut": 0, "parts": [], "severed": [], "pieces": 0, "killed": 0}
	for h in hits:
		_land(h[0], h[1], f, 5.0, 0.8)
		_tally(info, h[1])
	info["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	last = info
	if top_down():
		_streaks.append({"a": e + f * 0.5, "b": c, "t": 0.0, "dur": 0.12})
	if not hits.is_empty():
		hit_stop(0.04 + 0.02 * mini(hits.size(), 3) + (0.03 if int(info.killed) > 0 else 0.0), 0.06)
		arena._kick = maxf(float(arena._kick), 0.5 + 0.25 * hits.size())

## The thrust (static, for the checks): the line a-c bored through every body on it (run_through each), nearest
## first. Returns [[body, result], ...] for the ones it went into.
static func skewer(bodies: Array, a: Vector3, c: Vector3, r: float, hurt_amt: float) -> Array:
	var near := []
	var f := (c - a).normalized()
	for b in bodies:
		if not is_instance_valid(b) or not on_line(b, a, c):
			continue
		near.append([(b.global_position - a).dot(f), b])
	near.sort_custom(func(x, y): return x[0] < y[0])
	var out := []
	for e in near:
		var b: VoxelBody = e[1]
		var res := run_through(b, a, c, r, hurt_amt)
		if int(res.cut) > 0 or not (res.pieces as Array).is_empty():
			out.append([b, res])
	return out

## The spear's line a-c through body b (static, for the checks): every cube within r of it is cut out (carve); a line
## through a limb's joint takes the limb off there (a thin disc cut across the limb, slice); a tunnel through the
## brain kills; hurt_amt off its health if it went in at all. Returns carve's result with the disc cuts added and
## "severed": the parts something came off (at a joint, or the tunnel cutting a limb through).
static func run_through(b: VoxelBody, a: Vector3, c: Vector3, r: float, hurt_amt: float) -> Dictionary:
	var brain0 := b.brain_lost
	var hp0 := b.hp
	var k := b.height / 1.85
	# every cut kept clear of the hips (the root joint): a cut through a joint keeps the side toward its parent, the
	# root's is "below", and nothing of the body is below the hips, so the whole top half would come off
	var hips: Vector3 = b.skeleton.global_transform * b.skeleton.get_bone_global_pose(0).origin
	var gap := b.vm * 2.5
	var shift := _clear(hips, a, c, r + b.vm * 1.5)
	a += shift
	c += shift
	# the joints first (a disc across a limb only severs it whole; after the tunnel it can find a way round)
	var discs := []
	for n in b.parts.keys():
		var base := String(n).trim_suffix("_l").trim_suffix("_r")
		if not JOINTS.has(base) or bool(b.parts[n].gone):
			continue
		var j := joint(b, n)
		if seg_dist(j, a, c) > JOINT_R * k:
			continue
		var ax := (part_middle(b, n) - j).normalized()
		var cfg: Array = JOINTS[base]
		var off := float(cfg[0]) * k
		if off > 0.0:
			off = maxf(off, b.vm * 2.3)     # still clear of the joint itself with big cubes (F2)
		var at := j + ax * off
		var hd := (hips - at).dot(ax)
		if absf(hd) < gap:
			at += ax * (hd + gap)           # (a hip's disc) moved down the limb, the hips out of its plane
		b.hp = INF                          # a disc's own blade damage (a slash's third) isn't the spear's
		var cut := b.slice(at, ax, ax, float(cfg[1]) * k, -1.0, b.vm * 0.9)
		discs.append(cut)
		if not _came_off(b, n, cut):
			# a thick limb (a brute's thigh) or a wide head: again, right across it
			discs.append(b.slice(at, ax, ax, _girth(b, n, at, ax) + b.vm, -1.0, b.vm * 0.9))
	b.hp = hp0
	var res := b.carve(a, c, r, HP_PER_CUBE, 2)
	for cut in discs:
		(res.bits as Array).append_array(cut.bits)
		res.cut = int(res.cut) + int(cut.cut)
		for pn in cut.parts:
			if not (res.parts as Array).has(pn):
				(res.parts as Array).append(pn)
		(res.pieces as Array).append_array(cut.pieces)
		res.killed = bool(res.killed) or bool(cut.killed)
		res.head_off = bool(res.head_off) or bool(cut.head_off)
	res["severed"] = []
	if int(res.cut) == 0 and (res.pieces as Array).is_empty():
		return res
	# what came off (at a joint, or the tunnel itself cutting a limb through)
	for pc in res.pieces:
		if not (res.severed as Array).has(String(pc.part)):
			(res.severed as Array).append(String(pc.part))
	# through the brain: dead, however little of it the tunnel took
	if b.alive and b.brain_start > 0 and float(b.brain_lost - brain0) >= float(b.brain_start) * BRAIN_SHARE:
		if b.hurt(b.hp + 1.0):
			res.killed = true
	if b.alive and b.hurt(hurt_amt):
		res.killed = true
	return res

## Whether the segment a-c comes near enough body b to be worth boring (cheap; the carve or trace is the real test).
static func on_line(b: VoxelBody, a: Vector3, c: Vector3) -> bool:
	var p := b.global_position
	var reach := b.height + 0.3 if (not b.alive or b.floored()) else maxf(0.8, b.height * 0.45)
	var a2 := Vector2(a.x - p.x, a.z - p.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var tt := clampf(-a2.dot(ac) / maxf(ac.length_squared(), 0.000001), 0.0, 1.0)
	if (a2 + ac * tt).length() > reach:
		return false
	return minf(a.y, c.y) <= p.y + b.height + 0.3 and maxf(a.y, c.y) >= p.y - 0.6

## A part's joint (where it hangs from its parent), world.
static func joint(b: VoxelBody, n: String) -> Vector3:
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(b.parts[n].bone)).origin

## The middle of a part's grid, world (with the joint: which way the limb runs).
static func part_middle(b: VoxelBody, n: String) -> Vector3:
	var p: Dictionary = b.parts[n]
	return _part_xform(b, n) * ((Vector3(p.origin) + Vector3(p.grid.size) * 0.5) * b.vm)

# a part's grid space (metres from its mesh origin) to the world
static func _part_xform(b: VoxelBody, n: String) -> Transform3D:
	var bi: int = b.parts[n].bone
	var bind := Transform3D(Basis.IDENTITY, -b.model.bone_pivot[bi] * b.model.voxel_m)
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(bi) * bind

# how far the corners of part n's grid reach out from the line through p along ax (a disc this wide goes right across)
static func _girth(b: VoxelBody, n: String, p: Vector3, ax: Vector3) -> float:
	var pt: Dictionary = b.parts[n]
	var m := _part_xform(b, n)
	var s := Vector3(pt.grid.size)
	var out := 0.0
	for i in 8:
		var d: Vector3 = m * ((Vector3(pt.origin) + s * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)) * b.vm) - p
		out = maxf(out, (d - ax * d.dot(ax)).length())
	return out

# whether a disc took part n off (gone, or a real share of it a piece)
static func _came_off(b: VoxelBody, n: String, cut: Dictionary) -> bool:
	if bool(b.parts[n].gone):
		return true
	for pc in cut.pieces:
		if String(pc.part) == n and int(pc.count) * 3 > int(b.parts[n].start):
			return true
	return false

# the shift that puts the line through a and c at least gap from p (none if the segment already is)
static func _clear(p: Vector3, a: Vector3, c: Vector3, gap: float) -> Vector3:
	if seg_dist(p, a, c) >= gap:
		return Vector3.ZERO
	var u := (c - a).normalized()
	var off := (a - p) - u * (a - p).dot(u)
	var side := off
	if side.length() < 0.001:
		side = u.cross(Vector3.UP) if absf(u.y) < 0.9 else u.cross(Vector3.RIGHT)
	return side.normalized() * gap - off

static func seg_dist(p: Vector3, a: Vector3, c: Vector3) -> float:
	var ac := c - a
	var tt := clampf((p - a).dot(ac) / maxf(ac.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ac * tt)

# ---------------------------------------------------------------- the throw

## A thrown spear's flight (static, for the checks): {p: the tip (world), v: velocity, g: gravity, dir: the way it
## points, hit: {body id: true}, pierced, limit, spent, stuck: "" / "floor" / "wall", t: seconds up, dist: metres}.
static func launch_state(p: Vector3, v: Vector3, g: float) -> Dictionary:
	return {"p": p, "v": v, "g": g, "dir": v.normalized(), "hit": {}, "pierced": 0, "limit": PIERCE, "spent": false,
		"stuck": "", "t": 0.0, "dist": 0.0}

## One step of a thrown spear (static, for the checks): it moves dt along its path, bores into each body the step
## reaches (bore: up to PIERCE, slower after each; after the last it's spent and drops) and sticks in the world
## (space: the physics space, or null for just the floor) or the floor, the tip SINK in. Returns bore's events.
static func fly(st: Dictionary, dt: float, bodies: Array, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> Array:
	var p0: Vector3 = st.p
	var v: Vector3 = st.v
	var p1 := p0 + v * dt
	var stuck := ""
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(p0, p1, 1)
		q.exclude = exclude
		var wh := space.intersect_ray(q)
		if not wh.is_empty():
			p1 = wh.position
			stuck = "floor" if (wh.normal as Vector3).y > 0.7 else "wall"
	if p1.y <= 0.0:
		p1 = p0.lerp(p1, p0.y / maxf(p0.y - p1.y, 0.000001)) if p0.y > 0.0 else Vector3(p1.x, 0.0, p1.z)
		stuck = "floor"
	var dir := (p1 - p0).normalized() if p1.distance_to(p0) > 0.0001 else v.normalized()
	var ev := bore(st, p0, p1, bodies, THROW_R, THROW_HURT, THROUGH)
	st.v = v
	_slow(st, ev.size())
	v = st.v
	v.y -= float(st.g) * dt
	st.v = v
	st.t = float(st.t) + dt
	st.dist = float(st.dist) + p0.distance_to(p1)
	st.dir = dir
	if stuck != "":
		st.stuck = stuck
		st.p = p1 + dir * SINK
	else:
		st.p = p1
	return ev

# a flight slowed by boring through n more bodies (spent: it tumbles on a little and drops)
static func _slow(st: Dictionary, n: int) -> void:
	if n == 0:
		return
	st.v = (st.v as Vector3) * pow(PIERCE_SLOW, n) * (0.35 if bool(st.spent) else 1.0)
	if bool(st.spent):
		st.g = 9.8

## The bodies the segment p0-p1 goes into, nearest first, each bored through once (from where it goes in, depth
## metres on along the segment) and marked in st.hit; st.pierced counts them, and at st.limit st.spent stops it.
## Returns [[body, result, where it went in], ...].
static func bore(st: Dictionary, p0: Vector3, p1: Vector3, bodies: Array, r: float, hurt_amt: float, depth: float) -> Array:
	var out := []
	var sl := p0.distance_to(p1)
	if sl < 0.0001 or bool(st.spent):
		return out
	var dir := (p1 - p0) / sl
	var hits := []
	var seen: Dictionary = st.hit
	for b in bodies:
		if not is_instance_valid(b) or seen.has(b.get_instance_id()) or not on_line(b, p0, p1):
			continue
		var h: Dictionary = b.trace(p0, dir, sl)
		if not h.is_empty():
			hits.append([float(h.dist), b, h.point])
	hits.sort_custom(func(x, y): return x[0] < y[0])
	for e in hits:
		var b: VoxelBody = e[1]
		var at: Vector3 = e[2]
		seen[b.get_instance_id()] = true
		out.append([b, run_through(b, at - dir * 0.03, at + dir * depth, r, hurt_amt), at])
		st.pierced = int(st.pierced) + 1
		if int(st.pierced) >= int(st.limit):
			st.spent = true
			break
	return out

func _let_go() -> void:
	var e := eye()
	var f := look()
	var p0 := e + f * THRUST_FROM
	var start := p0
	var vis := Vector3.ZERO
	if not top_down():
		# its path is the eye's line; it's drawn leaving from the hand, closing onto the path
		var x: Transform3D = view.global_transform * _cocked
		var tip := x * Vector3(0, 0, TIP_Z)
		start = e + f * clampf((tip - e).dot(f), THRUST_FROM, 1.4)
		vis = tip - start
		vis -= f * vis.dot(f)
	_fly = launch_state(start, f * THROW_SPEED, 0.0 if top_down() else THROW_G)
	_mode = "fly"
	_vis = vis
	_path.clear()
	last = {"move": "throw", "bodies": 0, "pierced": 0, "cut": 0, "parts": [], "severed": [], "pieces": 0, "killed": 0,
		"stuck": "", "flown_m": 0.0, "ms": 0.0, "max_ms": 0.0}
	_proj_m.scale = Vector3.ONE if top_down() else Vector3(0.67, 0.67, 1.0)     # first person: as thin as in hand
	_proj.global_transform = Transform3D(dir_basis(f), start + vis)
	_proj.visible = _seen()
	arena._kick = maxf(float(arena._kick), 0.3)
	# what's between the eye and the hand's reach is bored at once
	var t0 := Time.get_ticks_usec()
	var ev := bore(_fly, p0, start, arena.bodies, THROW_R, THROW_HURT, THROUGH)
	if not ev.is_empty():
		_slow(_fly, ev.size())
		_bored(ev, f, Time.get_ticks_usec() - t0)

# the thrown spear shown (first person: once its butt is out in front, not running past your ear as it leaves)
func _seen() -> bool:
	if top_down() or _mode != "fly":
		return true
	return (_proj.global_transform * Vector3(0, 0, BUTT_Z - TIP_Z) - eye()).dot(look()) > 0.4

# a thrown or called-back spear went into bodies (events from bore; us: what it cost)
func _bored(ev: Array, dir: Vector3, us: int) -> void:
	for e in ev:
		_land(e[0], e[1], dir, 6.0, 1.4)
		_tally(last, e[1])
	var ms := snappedf(us / 1000.0, 0.1)
	last.ms = snappedf(float(last.ms) + ms, 0.1)
	last["max_ms"] = maxf(float(last.get("max_ms", 0.0)), ms)
	if last.has("pierced") and not _fly.is_empty():
		last.pierced = int(_fly.pierced)
	var killed := false
	for e in ev:
		killed = killed or bool(e[1].killed)
	hit_stop(0.035 + (0.03 if killed else 0.0), 0.1)
	arena._kick = maxf(float(arena._kick), 0.45)

func _fly_step(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var ex: Array[RID] = [arena.player.get_rid()]
	var ev := fly(_fly, dt, arena.bodies, arena.get_world_3d().direct_space_state, ex)
	if not ev.is_empty():
		_bored(ev, _fly.dir, Time.get_ticks_usec() - t0)
	_vis *= exp(-dt * 14.0)
	if String(_fly.stuck) != "":
		_stick()
	elif float(_fly.t) > MAX_FLIGHT or (_fly.p as Vector3).length() > 120.0:
		recall()
	else:
		_proj.global_transform = Transform3D(dir_basis(_fly.v), (_fly.p as Vector3) + _vis)
	_proj.visible = _seen()
	_trail_point(_proj.global_position)

func _stick() -> void:
	_mode = "stuck"
	_stuck_t = 0.0
	_vis = Vector3.ZERO
	_stuck_b = dir_basis(_fly.dir)
	_proj.global_transform = Transform3D(_stuck_b, _fly.p)
	last.stuck = _fly.stuck
	last.flown_m = snappedf(float(_fly.dist), 0.1)
	sfx("spear_stick", _fly.p)
	# the cubes lying where it went in jump
	arena.debris.pop(_fly.p, 0.6, 2.5, 80)

# stuck in: a twang (the shaft quivering about the tip), and it comes back if you walk up to it
func _stuck_step(dt: float) -> void:
	_stuck_t += dt
	var ang := 0.1 * sin(_stuck_t * 42.0) * exp(-_stuck_t * 5.0)
	_proj.global_transform = Transform3D(_stuck_b * Basis(Vector3.RIGHT, ang), _fly.p)
	var mid: Vector3 = (_fly.p as Vector3) + _stuck_b.z * 0.8
	var pp: Vector3 = arena.player.global_position
	if _stuck_t > 0.3 and Vector2(mid.x - pp.x, mid.z - pp.z).length() < PICKUP_R and absf(mid.y - pp.y - 0.9) < 1.6:
		recall()

func _back_step(dt: float) -> void:
	_back.t = float(_back.t) + dt
	var k := clampf(float(_back.t) / RECALL_T, 0.0, 1.0)
	var to := _hand_xform()
	var from: Vector3 = _back.from
	# faster and faster (pulled in), a little arc up on the way
	var p := from.lerp(to.origin, k * k) + Vector3.UP * sin(k * PI) * minf(0.5, from.distance_to(to.origin) * 0.06)
	var t0 := Time.get_ticks_usec()
	var ev := bore(_back, _back.p, p, arena.bodies, THROW_R, RECALL_HURT, THROUGH)
	if not ev.is_empty():
		_bored(ev, (p - (_back.p as Vector3)).normalized(), Time.get_ticks_usec() - t0)
	_back.p = p
	var b0: Basis = _back.basis
	var bs := b0.slerp(to.basis, k * k * (3.0 - 2.0 * k))
	_proj.global_transform = Transform3D(bs, p)
	_trail_point(p)
	if k >= 1.0:
		_caught()

# where the spear's tip is when it's in your hand (and which way it points), world
func _hand_xform() -> Transform3D:
	if top_down():
		var f := look()
		var av: VoxelBody = arena.avatar
		var hb := av.model.bone("hand_r")
		var grip: Vector3 = arena.player.global_position + Vector3(0, 1.1, 0)
		if hb >= 0:
			grip = av.skeleton.global_transform * av.skeleton.get_bone_global_pose(hb).origin
		return Transform3D(dir_basis(f), grip - f * TIP_Z)
	var x: Transform3D = view.global_transform * _rest
	return Transform3D(x.basis.orthonormalized(), x * Vector3(0, 0, TIP_Z + _slide))

func _caught() -> void:
	_mode = "hand"
	_proj.visible = false
	_path.clear()
	_cd = 0.1
	if _out_now:
		_catch = CATCH_T
		arena._kick = maxf(float(arena._kick), 0.35)

## -z along d (the spear's nose along its flight), up kept up.
static func dir_basis(d: Vector3) -> Basis:
	if d.length_squared() < 0.000001:
		return Basis()
	var n := d.normalized()
	return Basis.looking_at(n, Vector3.UP if absf(n.y) < 0.98 else Vector3.BACK)

# ---------------------------------------------------------------- what a hit shows

# one bored body: most of the tunnel's cubes blow out of the far side, a few back out of the near; what came off is
# flung on along the line; a stagger and a small shove along it
func _land(b: VoxelBody, res: Dictionary, dir: Vector3, power: float, shove: float) -> void:
	var bits: Array = res.bits
	if not bits.is_empty():
		var mid := 0.0
		for bt in bits:
			mid += (bt.pos as Vector3).dot(dir)
		mid /= bits.size()
		var far := []
		var near := []
		for i in bits.size():
			var bt: Dictionary = bits[i]
			if (bt.pos as Vector3).dot(dir) >= mid - 0.02:
				far.append(bt)
			elif i % 3 == 0:
				near.append(bt)
		spray({"bits": far}, dir, power)
		spray({"bits": near}, -dir, power * 0.3)
	if not is_instance_valid(b):
		return
	fling(b, res, dir * randf_range(1.5, 3.0) + Vector3.UP * randf_range(1.0, 2.2),
		Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)))
	if b.alive and not (res.parts as Array).is_empty():
		b.hit_react(dir, mini(bits.size(), 40), String(res.parts[0]))
		var flat := Vector3(dir.x, 0, dir.z)
		if flat.length() > 0.01:
			b.knock += flat.normalized() * shove

# adds one body's result to a 'last' dict
static func _tally(info: Dictionary, res: Dictionary) -> void:
	info.bodies = int(info.get("bodies", 0)) + 1
	info.cut = int(info.cut) + int(res.cut)
	for p in res.parts:
		if not (info.parts as Array).has(p):
			(info.parts as Array).append(p)
	(info.severed as Array).append_array(res.get("severed", []))
	info.pieces = int(info.pieces) + (res.pieces as Array).size()
	if bool(res.killed):
		info.killed = int(info.killed) + 1

# ---------------------------------------------------------------- the look

static func _ease(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)

# the spear in the view: at rest under the arm; a thrust draws back, jabs out fast (the shaft sliding out through the
# grip to its full reach), holds, comes back; a throw draws it up over the shoulder; a catch knocks it into the hand
func _pose_view(dt: float) -> void:
	if not top_down():
		_slide = move_toward(_slide, _rest_slide(), dt * 5.0)
	var held := _mode == "hand"
	_spear.visible = held
	_arm.visible = held
	if not held:
		return
	var x := _rest
	var s := _slide
	if _t >= 0.0:
		if _t < BACK_T:
			var kb := _ease(_t / BACK_T)
			x = _rest.interpolate_with(_drawn, kb)
			s = lerpf(_slide, _slide_drawn, kb)
		elif _t < OUT_T:
			var k := 1.0 - pow(1.0 - (_t - BACK_T) / (OUT_T - BACK_T), 3.0)
			x = _drawn.interpolate_with(_out, k)
			s = lerpf(_slide_drawn, 0.0, k)
		elif _t < HOLD_T:
			x = _out
			s = 0.0
		else:
			var kr := _ease((_t - HOLD_T) / (THRUST_T - HOLD_T))
			x = _out.interpolate_with(_rest, kr)
			s = lerpf(0.0, _slide, kr)
	elif _cock >= 0.0:
		x = _rest.interpolate_with(_cocked, _ease(_cock / COCK_T))
	elif _catch > 0.0:
		var kc := sin((1.0 - _catch / CATCH_T) * PI)
		x = Transform3D(x.basis * Basis(Vector3.RIGHT, 0.12 * kc), x.origin + Vector3(0.015, 0.03, 0.12) * kc)
	x.origin.y += sin(_clock * 1.7) * 0.004
	_spear.transform = x
	_shaft.position = Vector3(0, 0, s)
	# the sleeve: from the shoulder (low, behind the eye, on the right) to the glove
	var d := x.origin - SHOULDER
	var bs := Basis.looking_at(d, Vector3.UP)
	_arm.transform = Transform3D(Basis(bs.x, bs.y, bs.z * d.length()), (SHOULDER + x.origin) * 0.5)

# first person: how far the spear at rest slides back through the grip to keep its point (1.7 m out) out of the
# nearest body ahead (they come right up to you)
func _rest_slide() -> float:
	var e := eye()
	var x: Transform3D = view.global_transform * _rest
	var tip := x * Vector3(0, 0, TIP_Z)
	var along := -x.basis.z.normalized()
	var u := Vector3(along.x, 0, along.z)
	var per := u.length()                       # level metres the point comes back a metre slid
	if per < 0.2:
		return 0.0
	u /= per
	var out := 0.0
	for b in arena.bodies:
		if not is_instance_valid(b) or not b.alive or b.floored():
			continue
		var p: Vector3 = b.global_position
		if tip.y > p.y + b.height + 0.05 or (p - e).dot(u) < 0.0:
			continue                            # the point over his head, or he's behind
		var rr: float = 0.45 * b.height / 1.85  # him, seen from above: a round this wide (his arms)
		var d := Vector3(p.x - tip.x, 0, p.z - tip.z)
		var bf := d.dot(u)
		var lat := (d - u * bf).length()
		if lat < rr:
			# his front this far ahead of the point (less than nothing: the point's in him)
			var front := bf - sqrt(rr * rr - lat * lat)
			out = maxf(out, (0.05 - front) / per)
	return clampf(out, 0.0, SLIDE_MAX)

# top-down: Jared's spear hidden while it's out, slid forward through the fist on a thrust
func _pose_hand() -> void:
	if not is_instance_valid(_hand):
		return
	_hand.visible = _mode == "hand"
	var jab := 0.0
	if _t >= 0.0:
		if _t < BACK_T:
			jab = -0.12 * _ease(_t / BACK_T)
		elif _t < OUT_T:
			jab = lerpf(-0.12, 0.55, 1.0 - pow(1.0 - (_t - BACK_T) / (OUT_T - BACK_T), 3.0))
		elif _t < HOLD_T:
			jab = 0.55
		else:
			jab = lerpf(0.55, 0.0, _ease((_t - HOLD_T) / (THRUST_T - HOLD_T)))
	(_hand.get_child(0) as Node3D).position = Vector3(0, 0, jab)

func _trail_point(p: Vector3) -> void:
	_path.append(p)
	if _path.size() > 6:
		_path.remove_at(0)

# the streaks: thin ribbons facing the camera, bright at the head, fading back
func _draw_fx() -> void:
	var im: ImmediateMesh = _fx.mesh
	im.clear_surfaces()
	var segs := []          # [a, b, alpha at a, alpha at b, half width]
	for s in _streaks:
		var k := 1.0 - float(s.t) / float(s.dur)
		segs.append([s.a, s.b, 0.05 * k, 0.6 * k, 0.03])
	if _mode == "fly" or _mode == "back":
		var n := _path.size()
		for i in range(1, n):
			segs.append([_path[i - 1], _path[i], 0.35 * float(i - 1) / n, 0.35 * float(i) / n, 0.022])
	var verts := []
	var cp: Vector3 = arena.cam.global_position
	for s in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var side := (b - a).cross(cp - (a + b) * 0.5)
		if side.length_squared() < 0.0000001:
			continue
		side = side.normalized() * float(s[4])
		var ca := Color(1.0, 0.95, 0.85, float(s[2]))
		var cb := Color(1.0, 0.95, 0.85, float(s[3]))
		verts.append_array([[a - side, ca], [a + side, ca], [b + side, cb], [a - side, ca], [b + side, cb], [b - side, cb]])
	if verts.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		im.surface_set_color(v[1])
		im.surface_add_vertex(v[0])
	im.surface_end()

# ---------------------------------------------------------------- checks

# the thrust's own 2.9 m line at height y, x across, coming from the front (+z)
static func _line(y: float, x: float) -> Array:
	return [Vector3(x, y, 1.6), Vector3(x, y, 1.6 - (THRUST_TO - THRUST_FROM))]

static func _grunt(host: Node, at: Vector3, key: String = "grunt") -> VoxelBody:
	var b := VoxelBody.new()
	host.add_child(b)
	# the arena's own size for the kind (a grunt: 0.023 m cubes)
	var cube := float(VoxelArena.HEIGHT[key]) / float(VoxelModel.get_model(key).rig.get("ref_rows", 80))
	b.setup(key, cube, 1, StandardMaterial3D.new())
	b.position = at
	b.animate(0.0, false)
	return b

## A grunt at the origin facing +z (chest at about y 1.0, head 1.43-1.8): thrusts from the front (the thrust's own
## 2.9 m line) through the chest, two in a row, the head, the hips, an elbow, a knee, a shoulder, a hip, the neck (and
## a brute's hip, a swarmer's neck), a miss; throws through two and into the floor, through four (three bored, then
## spent); a call back through one.
static func checks(host: Node) -> Array:
	var out := []
	var imm := VoxelBody.immortal
	VoxelBody.immortal = false
	var made := []
	var none: Array[RID] = []
	# the chest
	var b := _grunt(host, Vector3.ZERO)
	made.append(b)
	var ln: Array = _line(1.0, 0.0)
	var t0 := Time.get_ticks_usec()
	var hits := skewer([b], ln[0], ln[1], THRUST_R, THRUST_HURT)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var res: Dictionary = hits[0][1] if hits.size() == 1 else {"cut": 0, "parts": [], "bits": [], "pieces": []}
	out.append([int(res.cut) > 60 and (res.parts as Array).has("torso"),
		"a thrust through the chest bores a tunnel (%d cubes, %.1f ms)" % [int(res.cut), ms]])
	var h := b.trace(ln[0], Vector3(0, 0, -1), 2.9)
	out.append([h.is_empty() or String(h.part) != "torso", "the tunnel goes clean through: a ray down it misses the chest (%s)" % str(h.get("part", "-"))])
	out.append([b.alive and b.hp <= 100.0 - THRUST_HURT and b.hp > 50.0, "it hurts (hp %.0f) but one thrust through the body doesn't kill" % b.hp])
	out.append([(res.bits as Array).size() > 20 and (res.pieces as Array).is_empty(), "cubes to blow out of the far side (%d), nothing comes off" % (res.bits as Array).size()])
	# two in a row
	var b1 := _grunt(host, Vector3(3, 0, 0))
	var b2 := _grunt(host, Vector3(3, 0, -0.9))
	made.append_array([b1, b2])
	ln = _line(1.05, 3.0)
	hits = skewer([b2, b1], ln[0], ln[1], THRUST_R, THRUST_HURT)
	out.append([hits.size() == 2 and hits[0][0] == b1 and int(hits[1][1].cut) > 30,
		"one thrust skewers two in a row, the nearer first (%d bodies)" % hits.size()])
	# the head
	var bh := _grunt(host, Vector3(6, 0, 0))
	made.append(bh)
	ln = _line(1.6, 6.0)
	hits = skewer([bh], ln[0], ln[1], THRUST_R, THRUST_HURT)
	out.append([hits.size() == 1 and not bh.alive and bool(hits[0][1].killed), "through the head kills (brain %d of %d)" % [bh.brain_lost, bh.brain_start]])
	# through the hips (the root joint): a tunnel, not the top half off
	var bp := _grunt(host, Vector3(7.5, 0, 0))
	made.append(bp)
	var hp_at: Vector3 = bp.skeleton.global_transform * bp.skeleton.get_bone_global_pose(0).origin
	hits = skewer([bp], hp_at + Vector3(0, 0, 1.6), hp_at + Vector3(0, 0, -1.3), THRUST_R, THRUST_HURT)
	var rp: Dictionary = hits[0][1] if hits.size() == 1 else {"cut": 0, "pieces": [null]}
	out.append([int(rp.cut) > 30 and (rp.pieces as Array).is_empty() and bp.alive,
		"through the hips bores a tunnel and takes nothing off (%d pieces)" % (rp.pieces as Array).size()])
	# an elbow, a knee, a shoulder, a hip, the neck; a brute's hip (a thick thigh), a swarmer's neck (a wide head)
	for jc in [["forearm_l", "grunt"], ["shin_r", "grunt"], ["arm_r", "grunt"], ["thigh_l", "grunt"], ["head", "grunt"],
			["thigh_l", "brute"], ["head", "swarmer"]]:
		var jn: String = jc[0]
		var bj := _grunt(host, Vector3(9, 0, 0), jc[1])
		made.append(bj)
		var j := joint(bj, jn)
		hits = skewer([bj], j + Vector3(0, 0, 1.6), j + Vector3(0, 0, -1.3), THRUST_R, THRUST_HURT)
		var rj: Dictionary = hits[0][1] if hits.size() == 1 else {"severed": [], "pieces": []}
		var names := []
		for pc in rj.pieces:
			if not names.has(String(pc.part)):
				names.append(String(pc.part))
		var neck: bool = jn == "head"
		out.append([(rj.severed as Array).has(jn) and names.has(jn) and bj.alive != neck and (neck or bj.hp > 80.0),
			"through a %s's %s joint takes it off there (%s), %s (hp %.0f)" % [jc[1], jn, ", ".join(names),
			"dead" if neck else "alive", bj.hp]])
	# a miss
	var bm := _grunt(host, Vector3(12, 0, 0))
	made.append(bm)
	ln = _line(1.0, 13.3)
	hits = skewer([bm], ln[0], ln[1], THRUST_R, THRUST_HURT)
	out.append([hits.is_empty() and bm.hp == 100.0, "a thrust beside him does nothing"])
	# thrown through two (chest, then hips) and into the floor behind
	var t1 := _grunt(host, Vector3(15, 0, 0))
	var t2 := _grunt(host, Vector3(15, 0, -1.0))
	made.append_array([t1, t2])
	var st := launch_state(Vector3(15, 1.4, 2.5), Vector3(0, -0.18, -1).normalized() * THROW_SPEED, THROW_G)
	var cuts := []
	var max_ms := 0.0
	for i in 240:
		var tf := Time.get_ticks_usec()
		for e in fly(st, 1.0 / 60.0, [t1, t2], null, none):
			cuts.append(int(e[1].cut))
		max_ms = maxf(max_ms, (Time.get_ticks_usec() - tf) / 1000.0)
		if String(st.stuck) != "":
			break
	var sp := (st.v as Vector3).length()
	out.append([cuts.size() == 2 and cuts.min() > 30 and t1.hp < 100.0 and t2.hp < 100.0,
		"a thrown spear bores through both in its path (%s cubes, %.1f ms a frame at most)" % [str(cuts), max_ms]])
	out.append([String(st.stuck) == "floor" and (st.p as Vector3).y < 0.0 and (st.p as Vector3).y > -SINK - 0.01 and (st.dir as Vector3).y < -0.1,
		"and sticks in the floor behind, tip in, at its angle (%s)" % str((st.p as Vector3).snapped(Vector3.ONE * 0.01))])
	out.append([sp < THROW_SPEED * 0.8, "slower after each (%.1f m/s)" % sp])
	# through four in a row: three bored, then spent
	var four := []
	for i in 4:
		four.append(_grunt(host, Vector3(18, 0, -0.8 * i)))
	made.append_array(four)
	st = launch_state(Vector3(18, 1.0, 2.0), Vector3(0, 0, -THROW_SPEED), THROW_G)
	var n := 0
	for i in 240:
		n += fly(st, 1.0 / 60.0, four, null, none).size()
		if String(st.stuck) != "":
			break
	out.append([n == PIERCE and bool(st.spent) and (four[3] as VoxelBody).hp == 100.0 and String(st.stuck) == "floor",
		"it bores through %d and no more, then drops (%d bored, the fourth hp %.0f)" % [PIERCE, n, (four[3] as VoxelBody).hp]])
	# called back through one in the way
	var bb := _grunt(host, Vector3(21, 0, 0))
	made.append(bb)
	var bk := {"hit": {}, "pierced": 0, "limit": 6, "spent": false}
	var ev := bore(bk, Vector3(21, 1.1, -3.0), Vector3(21, 1.1, 3.0), [bb], THROW_R, RECALL_HURT, THROUGH)
	out.append([ev.size() == 1 and int(ev[0][1].cut) > 30, "called back, it bores through anyone in the way"])
	for x in made:
		(x as Node).queue_free()
	VoxelBody.immortal = imm
	return out
