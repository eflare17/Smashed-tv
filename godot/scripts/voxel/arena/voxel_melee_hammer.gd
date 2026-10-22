class_name VoxelMeleeHammer
extends VoxelMelee
## The sledgehammer (the owner, 20 Oct: five melee weapons, each doing something different; and "can you make it so the
## sledge hammer can swing left and right"): slow, heavy, crushing. Left click goes by the mouse as you click. Moving it
## sideways swings the hammer that way: it's cocked back at the other side, then swept level across the front at chest
## height, head first, and follows through. The first body the head meets along the arc (and one standing right by it)
## takes a crater where it's struck (an arm in the way is crushed on into the ribs; a head loses a big chunk, which can
## kill), the cubes and whatever came off spray out the far side, and it's thrown sideways across the room, tumbling,
## bowling over whoever it lands on. Still (or moving up or down), it's the overhead smash: the hammer goes up over your
## head, hangs there a moment, comes down where you look and scoops a big round crater out of whatever it meets
## (VoxelBody.carve, a ball): a chest caved in, the top of a head gone (that kills), an arm or a leg knocked clean off
## where it lands; the one hit reels back and the cubes blow out of the crater. On the floor it just thuds, throwing the
## cubes lying there back up. Right click is a ground slam: the hammer comes down at your feet and a shockwave rings out
## across the floor; everyone it reaches is thrown up and away (the nearer the harder) and knocked down, lying cubes
## jump and lying pieces are tossed. Every blow freezes the game a blink as it lands and kicks the view; every swing
## whooshes, a body hit crunches, the floor thuds, the slam booms. Top-down the smash goes toward the mouse, a side
## swing sweeps round Jared (he turns into it; the mouse moving across the way he faces picks the side), and the slam
## rings out round him. Put away mid-move, the move is called off. The cores (where a blow lands, what it does) are
## static so the logic test can run them. Owned by the voxel session.

const REACH := 2.6              # metres from the eye a smash reaches
const CRATER_R := 0.17          # the crater's radius, metres
const SINK := 0.05              # its middle this far in past where the hammer meets the body
const HP_PER_CUBE := 0.04       # health a body cube the crater takes costs (carve's own; it scales it by the cube's size)
const SMASH_HURT := 10.0        # and the blow on top of that
const SHOVE := 3.0              # m/s the one smashed is shoved back
const SMASH_UP := 0.3           # seconds raising it over your head
const SMASH_HIT := 0.4          # when it lands
const SMASH_END := 0.8          # back at rest
const SMASH_CD := 0.85
const SLAM_UP := 0.26
const SLAM_HIT := 0.36
const SLAM_END := 0.9
const SLAM_CD := 2.0
const SLAM_R := 4.5             # metres the shockwave reaches
const RING_T := 0.35            # seconds it takes to get there
const SLAM_OUT := 3.0           # the throw: away * SLAM_OUT / (d + 0.5) + up * SLAM_LIFT (m/s)
const SLAM_LIFT := 3.5
const SLAM_HURT := 6.0
# the side swing
const SIDE_MIN := 40.0          # the mouse's recent motion (shooter.mouse_v) at least this long, and mostly across
const SIDE_REACH := 2.4         # metres from the eye (top-down: the chest) it reaches
const SIDE_ARC := 75.0          # degrees either side of where you look it sweeps (150 in all)
const SIDE_STEP := 5.0          # degrees between its rays
const SIDE_TILT := [0.0, -0.12, 0.12]   # each ray tried level in the sweep, then tilted down, up (radians)
const SIDE_R := 0.14            # the crater where it strikes, metres
const SIDE_R_HEAD := 0.17       # on a head
const SIDE_SINK := 0.06         # its middle this far in, on along the swing
const SIDE_SINK_HEAD := 0.11
const SIDE_R_RIBS := 0.11       # an arm in the way: crushed on into what's behind it, this big
const SIDE_HURT := 10.0
const SIDE_V := 6.5             # the throw (m/s): sideways the way it swung, on ahead a little, up
const SIDE_FWD := 1.0
const SIDE_UP := 2.5
const SIDE_SPIN := 6.0
const SIDE_NEXT := 0.6          # one standing this near where it struck takes it too
const SIDE_WIND := 0.25         # seconds cocking it back
const SIDE_SWEEP := 0.3         # across the front and through (across the 150 degrees in about 0.18 of them)
const SIDE_END := 0.75          # back at rest
const SIDE_CD := 0.8
# its view (one to the right; one to the left is the mirror image): degrees round from ahead toward the right the
# hammer points, and up it's raised; the hands go round a circle under your chin, well behind the head (it leads)
const SW_TH0 := -46.0           # cocked back at the left (the head at the edge of the view)
const SW_PH0 := 32.0
const SW_TH1 := 112.0           # followed through, round at the right
const SW_PH1 := 30.0
const SW_LOW := 12.0            # how far up it is passing the middle: level, at chest height
const SW_PIVOT := Vector3(0.02, -0.3, -0.2)
const SW_RADIUS := 0.36
const SW_LAG := 70.0            # degrees the hands trail the head
const TD_TH0 := -110.0          # top-down it's cocked right back behind him (there's no view to keep it in)
const TWIST := 0.45             # top-down: Jared turns into the swing this much of the way
const STEEL := Color(0.58, 0.6, 0.65)
const FACE := Color(0.26, 0.27, 0.3)
const WOOD := Color(0.5, 0.31, 0.15)
const WRAP := Color(0.16, 0.11, 0.08)
const LIMBS := ["arm_l", "arm_r", "forearm_l", "forearm_r", "hand_l", "hand_r"]

var _ham: Node3D                # the hammer in the view: the grip at its origin, the handle up +y, the striking face -z
var _trail: MeshInstance3D      # the smear behind the head as it comes down or sweeps across (in the view)
var _sweep: MeshInstance3D      # top-down: the smear round Jared of a side swing (world)
var _fx: MeshInstance3D         # shock rings (world)
var _hand: Node3D               # top-down: the hammer's pivot in Jared's hand (freed with it)
var _move := ""                 # "smash", "side", "slam" or "" (at rest)
var _t := -1.0                  # seconds into the move
var _hit_done := false
var _low := false               # the smash is coming down on the floor (the view takes it lower)
var _side := 1                  # the side swing's way: 1 to the right, -1 to the left
var _ray_a := 0.0               # its next ray, degrees along the arc (-SIDE_ARC .. SIDE_ARC)
var _trace_ms := 0.0
var _queue := []                # the one standing by the struck one, to take it next frame: [body, hit, push]
var _cd_left := 0.0             # the left click's cooldown (a smash's or a side swing's) and what it started at
var _cd_left_max := SMASH_CD
var _cd_slam := 0.0
var _clock := 0.0
var _rings := []                # [{c, n, t, dur, r, wall}]
var _wave := {}                 # the slam's shockwave going out: {c, t, done: {instance id: true}, n, ms}
# the view's key poses (camera space; see _pose)
var _rest: Transform3D
var _raise: Transform3D
var _hit: Transform3D
var _hit_low: Transform3D
var _slam_raise: Transform3D
var _slam_hit: Transform3D
var _side_low: Transform3D      # a side swing's way back: down out of sight at the right, before coming up to rest

func _build() -> void:
	# (the view hangs off the camera, which is interpolated; posed every frame here, the hammer mustn't be)
	_ham = Node3D.new()
	_ham.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(_ham)
	var steel := mat(STEEL, 0.45, 0.4)
	var face := mat(FACE, 0.4, 0.55)
	var wood := mat(WOOD, 0.0, 0.85)
	var grip := mat(WRAP, 0.0, 0.95)
	# the handle (0.9 m, the grip a little up from its end), the head across it, its two striking faces darker
	box(_ham, Vector3(0.034, 0.9, 0.034), Vector3(0, 0.31, 0), wood)
	box(_ham, Vector3(0.042, 0.22, 0.042), Vector3(0, 0.02, 0), grip)
	box(_ham, Vector3(0.05, 0.03, 0.05), Vector3(0, -0.135, 0), grip)
	box(_ham, Vector3(0.14, 0.14, 0.25), Vector3(0, 0.82, 0), steel)
	box(_ham, Vector3(0.148, 0.148, 0.05), Vector3(0, 0.82, 0), face)
	for s in [-1.0, 1.0]:
		box(_ham, Vector3(0.124, 0.124, 0.016), Vector3(0, 0.82, 0.13 * s), face)
		box(_ham, Vector3(0.152, 0.152, 0.02), Vector3(0, 0.82, 0.095 * s), steel)
	# two gloved hands on it
	var glove := mat(Color(0.12, 0.11, 0.11), 0.0, 0.9)
	box(_ham, Vector3(0.07, 0.065, 0.08), Vector3(0, 0.0, 0), glove)
	box(_ham, Vector3(0.07, 0.065, 0.08), Vector3(0, 0.3, 0), glove)
	_trail = MeshInstance3D.new()
	_trail.mesh = ImmediateMesh.new()
	_trail.material_override = _glow_mat()
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(_trail)
	_fx = _world_mesh()
	_sweep = _world_mesh()
	_init_poses()
	_pose_view()

func _world_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = _glow_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mi)
	return mi

# at rest low across the body, the head on the left; raised up over the right shoulder; landed ahead (on a body where
# you look, or lower on the floor); the slam's raise right over the head and its landing at your feet; a side swing
# to the right's way back, hanging down out of sight at the right
func _init_poses() -> void:
	_rest = _pose(Vector3(0.28, -0.4, -0.44), Vector3(-0.88, 0.15, -0.45), Vector3(0.2, 0.95, 0.1))
	_raise = _pose(Vector3(0.15, 0.1, -0.42), Vector3(-0.1, 0.7, 0.7), Vector3(0.0, 0.7, -0.7))
	_hit = _pose(Vector3(0.2, -0.4, 0.2), Vector3(-0.2, 0.25, -0.75), Vector3(0.0, -1.0, 0.2))
	_hit_low = _pose(Vector3(0.18, -0.5, 0.22), Vector3(-0.18, 0.15, -0.77), Vector3(0.0, -1.0, 0.1))
	_slam_raise = _pose(Vector3(0.08, 0.14, -0.4), Vector3(-0.05, 0.75, 0.65), Vector3(0.0, 0.65, -0.75))
	_slam_hit = _pose(Vector3(0.15, -0.45, 0.26), Vector3(-0.15, 0.12, -0.78), Vector3(0.0, -1.0, 0.1))
	_side_low = _pose(Vector3(0.26, -0.56, -0.34), Vector3(0.5, -0.55, -0.67), Vector3(1.0, 0.0, 0.0))

static func _glow_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	return m

# the hammer in the view: the grip at g, the handle along d, the striking face toward f (camera space)
static func _pose(g: Vector3, d: Vector3, f: Vector3) -> Transform3D:
	var y := d.normalized()
	var z := -(f - y * f.dot(y)).normalized()
	return Transform3D(Basis(y.cross(z).normalized(), y, z), g)

# a pose mirrored left for right (a swing to the left is a swing to the right's mirror image)
static func _mirror(x: Transform3D, side: int) -> Transform3D:
	if side > 0:
		return x
	return Transform3D(Basis.FLIP_X * x.basis * Basis.FLIP_X, Vector3(-x.origin.x, x.origin.y, x.origin.z))

func busy() -> bool:
	return _t >= 0.0

func cooling() -> float:
	return maxf(clampf(_cd_left / _cd_left_max, 0.0, 1.0), clampf(_cd_slam / SLAM_CD, 0.0, 1.0))

func press(button: int) -> void:
	if _t >= 0.0:
		return
	if button == MOUSE_BUTTON_LEFT and _cd_left <= 0.0:
		var mv: Vector2 = shooter.mouse_v
		var sw := pick_swing(mv, top_down(), look(), frame().x)
		if sw != 0:
			_side = sw
			_start("side")
			_cd_left = SIDE_CD
		else:
			_start("smash")
			_cd_left = SMASH_CD
		_cd_left_max = _cd_left
	elif button == MOUSE_BUTTON_RIGHT and _cd_slam <= 0.0:
		_start("slam")
		_cd_slam = SLAM_CD

func _start(m: String) -> void:
	_move = m
	_t = 0.0
	_hit_done = false
	_low = false
	_ray_a = -SIDE_ARC
	_trace_ms = 0.0

# put away mid-move: called off (a blow not landed yet never lands, so it can't land with a gun out); the cooldown
# stays, and a shockwave already going out goes on
func on_deselect() -> void:
	_t = -1.0
	_move = ""
	_queue.clear()

# top-down: the head lies across the end of the handle (seen from above it's a T), its faces darker; under a pivot a
# side swing turns
func hand_mesh() -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # (posed every frame in a side swing)
	_hand = Node3D.new()
	root.add_child(_hand)
	var steel := mat(STEEL, 0.3, 0.45)
	var face := mat(FACE, 0.3, 0.55)
	box(_hand, Vector3(0.034, 0.034, 0.9), Vector3(0, 0, 0.33), mat(WOOD))
	box(_hand, Vector3(0.042, 0.042, 0.22), Vector3(0, 0, 0.04), mat(WRAP))
	box(_hand, Vector3(0.25, 0.14, 0.14), Vector3(0, 0, 0.82), steel)
	for s in [-1.0, 1.0]:
		box(_hand, Vector3(0.016, 0.124, 0.124), Vector3(0.13 * s, 0, 0.82), face)
	return root

func hand_pose() -> String:
	return "shotgun"

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	for p in [[Rect2(0.3, 2.2, 7.0, 0.6), Color(0.66, 0.42, 0.22)], [Rect2(0.3, 2.05, 1.8, 0.9), Color(0.32, 0.22, 0.15)],
			[Rect2(7.0, 0.5, 2.5, 4.0), Color(0.8, 0.82, 0.86)], [Rect2(7.0, 0.5, 2.5, 0.55), Color(0.45, 0.47, 0.52)],
			[Rect2(7.0, 3.95, 2.5, 0.55), Color(0.45, 0.47, 0.52)]]:
		var c: Color = p[1]
		var rr: Rect2 = p[0]
		ci.draw_rect(Rect2(r.position + rr.position * u, rr.size * u), Color(c.r, c.g, c.b, col.a))

# ---------------------------------------------------------------- every frame

func step(dt: float) -> void:
	_clock += dt
	_cd_left = maxf(0.0, _cd_left - dt)
	_cd_slam = maxf(0.0, _cd_slam - dt)
	if not _queue.is_empty():
		var q: Array = _queue.pop_front()
		if is_instance_valid(q[0]):
			_side_land(q[0], q[1], q[2], false)
	if _t >= 0.0:
		_t += dt
		if _move == "side":
			_side_step(dt)
		else:
			_drop_step(dt)
		if _t >= _end_t():
			_t = -1.0
			_move = ""
	_wave_step(dt)
	for i in range(_rings.size() - 1, -1, -1):
		_rings[i].t += dt
		if float(_rings[i].t) >= float(_rings[i].dur):
			_rings.remove_at(i)
	_pose_view()
	_pose_hand()
	_draw_trail()
	_draw_sweep()
	_draw_rings()

func _end_t() -> float:
	match _move:
		"smash":
			return SMASH_END
		"side":
			return SIDE_END
	return SLAM_END

# the smash and the slam: up, a whoosh as it comes down, the blow as it lands
func _drop_step(dt: float) -> void:
	var smash := _move == "smash"
	var up_t := SMASH_UP if smash else SLAM_UP
	var hit_t := SMASH_HIT if smash else SLAM_HIT
	if top_down() and _t < up_t:
		shooter.avatar.attack = 0.5          # arms up while it's raised; they come down with it
	if _t >= up_t and _t - dt < up_t:
		sfx("swoosh_heavy", Vector3.INF, 0.0, 0.9 if smash else 0.8)
		if smash and not _hit_done:
			_low = _target().is_empty()    # coming down: on a body, or lower on the floor
	if not _hit_done and _t >= hit_t:
		_hit_done = true
		if smash:
			_smash_now()
		else:
			_slam_now()

# ---------------------------------------------------------------- the smash

## The body a smash from along dir meets first within reach: [body, hit] (hit: VoxelBody.trace's), or [].
static func aim_at(bodies: Array, from: Vector3, dir: Vector3, reach: float = REACH) -> Array:
	var best := []
	var best_d := reach
	for bv in bodies:
		if not is_instance_valid(bv):
			continue
		var b: VoxelBody = bv
		var h := b.trace(from, dir, best_d)
		if not h.is_empty() and float(h.dist) <= best_d:
			best_d = h.dist
			best = [b, h]
	return best

## A smash landing on b at point (world), the hammer going along dir: a ball of cubes scooped out round it (and what
## that leaves hanging comes off), the blow's health on top, a big shove back. Returns carve's result plus centre
## and carve_ms.
static func smash_body(b: VoxelBody, point: Vector3, dir: Vector3) -> Dictionary:
	var c := point + dir.normalized() * SINK
	var t0 := Time.get_ticks_usec()
	# a cube's health goes with its volume, so the crater costs the same at any cube size (F2, a brute's)
	var res := b.carve(c, c, CRATER_R, HP_PER_CUBE, 2)
	res["carve_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	res["centre"] = c
	if b.alive and b.hurt(SMASH_HURT):
		res.killed = true
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.05 else Vector3(0, 0, -1)
	if b.alive:
		var part := String(res.parts[0]) if not (res.parts as Array).is_empty() else "torso"
		b.hit_react(flat, 60, part)
		b.stagger = maxf(b.stagger, 0.55)
		b.flinch = 1.0
	b.knock = flat * SHOVE * (0.55 if b.heavy() else 1.0)     # the dead slide back too
	return res

# what's in front to smash: [body, hit] or [] (top-down a lower ray too, for anything short or lying)
func _target() -> Array:
	var from := eye()
	var dir := look()
	var hit := aim_at(arena.bodies, from, dir, REACH)
	if hit.is_empty() and top_down():
		hit = aim_at(arena.bodies, from, (dir + Vector3.DOWN * 0.5).normalized(), REACH)
	if not hit.is_empty():
		hit.append(dir)
	return hit

# where a smash that meets nobody lands: where you look meets the floor if that's in reach, else just ahead
func _floor_point(from: Vector3, dir: Vector3) -> Vector3:
	if not top_down() and dir.y < -0.05:
		var t := -from.y / dir.y
		if t <= REACH + 0.6:
			return Vector3(from.x + dir.x * t, 0.0, from.z + dir.z * t)
	var f := Vector3(dir.x, 0, dir.z)
	f = f.normalized() if f.length() > 0.01 else Vector3(0, 0, -1)
	return Vector3(from.x, 0.0, from.z) + f * 1.3

func _smash_now() -> void:
	var t0 := Time.get_ticks_usec()
	var tg := _target()
	if tg.is_empty():
		# the floor: a thud, the lying cubes round it jump
		var fp := _floor_point(eye(), look())
		var popped: int = arena.debris.pop(fp, 1.1, 3.2, 500)
		sfx("hammer_thud", fp, 3.0)
		_ring(fp + Vector3(0, 0.03, 0), Vector3.UP, 1.2, 0.25, true)
		shooter.kick = maxf(float(shooter.kick), 1.3)
		hit_stop(0.06, 0.05)
		last = {"move": "smash", "hit": "floor", "popped": popped, "ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)}
		return
	var b: VoxelBody = tg[0]
	var h: Dictionary = tg[1]
	var dir: Vector3 = tg[2]
	var hp0 := b.hp
	var res := smash_body(b, h.point, dir)
	var c: Vector3 = res.centre
	sfx("shatter" if bool(res.get("shattered", false)) else "hammer_hit", h.point, 3.0)
	# the cubes blow out of the crater (back toward you and up, as well as round it)
	var bits: Array = res.bits
	arena.knocked += bits.size()
	for bit in bits:
		var out: Vector3 = (bit.pos as Vector3) - c
		var d := (out.normalized() - dir * 0.55 + Vector3.UP * 0.35).normalized()
		arena.debris.burst([bit], d, randf_range(2.4, 4.2))
	# what it knocked off flies out from the crater, on along the blow
	if not (res.pieces as Array).is_empty():
		var pc := Vector3.ZERO
		var n := 0
		for e in res.pieces:
			pc += (e.xform as Transform3D) * (e.box_at as Vector3)
			n += 1
		var away := (pc / float(n) - c).normalized()
		fling(b, res, away * randf_range(2.8, 4.0) + dir * 2.0 + Vector3.UP * randf_range(1.5, 2.8),
			Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 9.0)
	_ring(h.point, -dir, 0.5, 0.16, false)
	shooter.kick = 2.0
	hit_stop(0.09, 0.03)
	last = {"move": "smash", "hit": String(h.part), "cut": res.cut, "parts": res.parts, "pieces": (res.pieces as Array).size(),
		"killed": res.killed, "head_off": res.head_off, "hp": snappedf(hp0, 1.0), "hp_now": snappedf(b.hp, 1.0),
		"carve_ms": res.carve_ms, "ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)}

# ---------------------------------------------------------------- the side swing

## Which left click the mouse's recent motion mv (screen pixels, x right, y down) makes: 1 a swing to the right, -1
## one to the left, 0 the overhead smash (still, or moving mostly up or down). Top-down the motion is taken on the
## floor (the screen's right is +x, its down +z) against the way Jared faces (fwd) and his right: across it, a swing
## that way.
static func pick_swing(mv: Vector2, td: bool, fwd: Vector3, right: Vector3) -> int:
	if mv.length() < SIDE_MIN:
		return 0
	var across := mv.x
	var along := mv.y
	if td:
		across = mv.x * right.x + mv.y * right.z
		along = mv.x * fwd.x + mv.y * fwd.z
	if absf(across) <= absf(along):
		return 0
	return 1 if across > 0.0 else -1

## The first body a side swing from `from` meets (fwd: where you look; right: your right; side 1 swinging to the
## right, -1 to the left), trying its rays from a0 to a1 degrees along the arc (-SIDE_ARC at its start .. SIDE_ARC at
## its end) in the swing's order, each level in the sweep and then tilted down and up; at each the nearest body it
## meets. Returns [body, hit, angle] (hit: VoxelBody.trace's plus dir, the ray, and travel, the way the head is going
## there) or [].
static func side_hit(list: Array, from: Vector3, fwd: Vector3, right: Vector3, side: int, a0: float = -SIDE_ARC,
		a1: float = SIDE_ARC, reach: float = SIDE_REACH) -> Array:
	var f := fwd.normalized()
	var s := (right - f * right.dot(f)).normalized()
	var u := s.cross(f).normalized()
	# only the bodies in reach, each with the stretch of the arc it lies across
	var near := []
	for bv in list:
		if not is_instance_valid(bv):
			continue
		var b: VoxelBody = bv
		if b.skeleton == null:
			continue
		var to := b.global_position + Vector3(0, b.height * 0.5, 0) - from
		var d := Vector2(to.x, to.z).length()
		if d > reach + 0.6:
			continue
		var at := rad_to_deg(atan2(to.dot(s), to.dot(f))) * side
		var half := rad_to_deg(atan2(0.6, maxf(d, 0.3))) + SIDE_STEP
		near.append([b, at - half, at + half, _bounds(b)])
	if near.is_empty():
		return []
	var a := a0
	while a <= a1 + 0.001:
		var ar := deg_to_rad(a * side)
		var along := f * cos(ar) + s * sin(ar)
		for tv in SIDE_TILT:
			var tilt: float = tv
			var dir := (along * cos(tilt) + u * sin(tilt)).normalized()
			var best := []
			var best_d := reach
			for e in near:
				if a < float(e[1]) or a > float(e[2]):
					continue
				var box: AABB = e[3]
				if not box.has_point(from) and box.intersects_segment(from, from + dir * best_d) == null:
					continue          # (passing over one lying on the floor, say)
				var b: VoxelBody = e[0]
				var h := b.trace(from, dir, best_d)
				if not h.is_empty() and float(h.dist) <= best_d:
					best_d = h.dist
					best = [b, h]
			if not best.is_empty():
				var h2: Dictionary = best[1]
				h2["dir"] = dir
				h2["travel"] = ((s * cos(ar) - f * sin(ar)) * side).normalized()
				best.append(a)
				return best
		a += SIDE_STEP
	return []

# a box round what's left of b (its joints, padded out to the cubes past them), to pass by the rays that miss it
static func _bounds(b: VoxelBody) -> AABB:
	var box := AABB(b.global_position, Vector3.ZERO)
	var sk := b.skeleton.global_transform
	for n in b.parts:
		var p: Dictionary = b.parts[n]
		if not bool(p.gone):
			box = box.expand(sk * b.skeleton.get_bone_global_pose(int(p.bone)).origin)
	return box.grow(0.25 * b.height)

## Who stands by the struck one (first) to take the swing too: the nearest other body the head, going on along travel
## from point, meets within SIDE_NEXT of it, or one met aiming from `from` at its middle there. [body, hit] or [].
static func next_to(list: Array, first: VoxelBody, point: Vector3, travel: Vector3, from: Vector3) -> Array:
	var best := []
	var best_d := SIDE_NEXT
	for bv in list:
		if not is_instance_valid(bv) or bv == first:
			continue
		var b: VoxelBody = bv
		if Vector2(b.global_position.x - point.x, b.global_position.z - point.z).length() > SIDE_NEXT + 1.0:
			continue          # (its middle: its arms reach out most of a metre)
		var h := b.trace(point - travel * 0.1, travel, SIDE_NEXT + 0.1)
		if h.is_empty():
			var mid := Vector3(b.global_position.x, point.y, b.global_position.z)
			h = b.trace(from, (mid - from).normalized(), SIDE_REACH + 0.6)
		if h.is_empty():
			continue
		var d := (h.point as Vector3).distance_to(point)
		if d <= best_d:
			best_d = d
			h["dir"] = travel
			h["travel"] = travel
			best = [b, h]
	return best

## The throw a side swing gives: sideways the way it swung (side 1: to your right), on ahead a little, up (m/s).
static func side_push(right: Vector3, side: int) -> Vector3:
	var s := Vector3(right.x, 0.0, right.z).normalized()
	return s * side * SIDE_V + Vector3.UP.cross(s) * SIDE_FWD + Vector3.UP * SIDE_UP

## A side swing landing on b at hit (side_hit's): a crater where it strikes, sunk on along the swing (on a head a
## bigger, deeper one); an arm in the way crushed on into his side (a second, smaller crater behind it); the blow's
## health; b thrown at push, tumbling. Frozen, it shatters instead (every cube in bits). Returns carve's result
## (both craters') plus centre and carve_ms.
static func side_blow(b: VoxelBody, hit: Dictionary, push: Vector3) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var p: Vector3 = hit.point
	var travel: Vector3 = hit.travel
	var head := String(hit.part) == "head"
	var c := p + (travel * 0.7 + (hit.dir as Vector3) * 0.3).normalized() * (SIDE_SINK_HEAD if head else SIDE_SINK)
	var res := b.carve(c, c, SIDE_R_HEAD if head else SIDE_R, HP_PER_CUBE, 2)
	res["centre"] = c
	if bool(res.get("shattered", false)):
		res["carve_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
		return res
	if LIMBS.has(String(hit.part)):
		# on in toward his middle, past what's left of the arm, to his side
		var into := Vector3(b.global_position.x - p.x, 0.0, b.global_position.z - p.z).normalized()
		var h2 := b.trace(p, into, 0.6)
		var at := p
		for i in 8:
			if h2.is_empty() or not LIMBS.has(String(h2.part)):
				break
			at = (h2.point as Vector3) + into * 0.06
			h2 = b.trace(at, into, 0.6 - at.distance_to(p))
		if not h2.is_empty() and not LIMBS.has(String(h2.part)):
			var c2: Vector3 = (h2.point as Vector3) + into * SIDE_SINK
			var r2 := b.carve(c2, c2, SIDE_R_RIBS, HP_PER_CUBE, 2)
			(res.bits as Array).append_array(r2.bits)
			(res.pieces as Array).append_array(r2.pieces)
			for n in r2.parts:
				if not (res.parts as Array).has(n):
					(res.parts as Array).append(n)
			res.cut = int(res.cut) + int(r2.cut)
			res.killed = bool(res.killed) or bool(r2.killed)
			res.head_off = bool(res.head_off) or bool(r2.head_off)
	res["carve_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	if b.alive and b.hurt(SIDE_HURT):
		res.killed = true
	b.launch(push * (0.6 if b.heavy() else 1.0), SIDE_SPIN)
	return res

# the head sweeping across: each frame the rays it has passed since the last, till one meets a body or the arc's done
func _side_step(dt: float) -> void:
	if top_down():
		shooter.avatar.attack = 0.5          # arms out with it the whole swing
	if _t >= SIDE_WIND and _t - dt < SIDE_WIND:
		sfx("swoosh_heavy", Vector3.INF, 1.5, 1.05)
	if _hit_done or _t < SIDE_WIND:
		return
	var to := minf(_side_angles(_t, TD_TH0 if top_down() else SW_TH0).x, SIDE_ARC)
	if to < _ray_a:
		return
	var n := floori((to - _ray_a) / SIDE_STEP) + 1
	var a1 := _ray_a + (n - 1) * SIDE_STEP
	var t0 := Time.get_ticks_usec()
	var tg := side_hit(arena.bodies, eye(), look(), frame().x, _side, _ray_a, a1)
	_trace_ms += (Time.get_ticks_usec() - t0) / 1000.0
	_ray_a = a1 + SIDE_STEP
	if not tg.is_empty():
		_hit_done = true
		_side_land(tg[0], tg[1], side_push(frame().x, _side), true)
	elif _ray_a > SIDE_ARC:
		_hit_done = true
		last = {"move": "side", "side": "right" if _side > 0 else "left", "hit": "", "trace_ms": snappedf(_trace_ms, 0.01)}

# one body takes a side swing (first: the one the head met; else the one by it, a frame later)
func _side_land(b: VoxelBody, h: Dictionary, push: Vector3, first: bool) -> void:
	var t0 := Time.get_ticks_usec()
	var hp0 := b.hp
	var res := side_blow(b, h, push)
	var p: Vector3 = h.point
	var shattered := bool(res.get("shattered", false))
	sfx("shatter" if shattered else "hammer_hit", p, 3.0 if first else 0.0)
	# the cubes out the far side, the way it swung; anything knocked off flies on with it
	var s := Vector3(push.x, 0.0, push.z).normalized()
	spray(res, (s * 0.85 + Vector3.UP * 0.35).normalized(), 4.5 if shattered else 3.6)
	fling(b, res, push * 1.15 + Vector3.UP * 0.8, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 9.0)
	_ring(p, -(h.dir as Vector3), 0.55, 0.16, false)
	if first:
		var nb := next_to(arena.bodies, b, p, h.travel, eye())
		if not nb.is_empty():
			_queue.append([nb[0], nb[1], push * 0.85])
		shooter.kick = 1.8
		hit_stop(0.08, 0.04)
		last = {"move": "side", "side": "right" if _side > 0 else "left", "hit": String(h.part), "cut": res.cut,
			"parts": res.parts, "pieces": (res.pieces as Array).size(), "killed": res.killed, "head_off": res.head_off,
			"hp": snappedf(hp0, 1.0), "hp_now": snappedf(b.hp, 1.0), "v": snappedf(push.length(), 0.1),
			"second": "", "trace_ms": snappedf(_trace_ms, 0.01), "carve_ms": res.carve_ms,
			"ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)}
	elif last.get("move", "") == "side":
		last["second"] = String(h.part)
		last["second_cut"] = res.cut

## Where a side swing's head is t seconds in (one to the right; a left one's is the mirror image): Vector2(degrees
## round from ahead toward the right, degrees up). Cocked back at the left (th0) till SIDE_WIND, then slow to start,
## flat out across the middle (the 150 degrees of the arc in about 0.18 s), slowing into the follow-through at the
## right.
static func _side_angles(t: float, th0: float = SW_TH0) -> Vector2:
	if t < SIDE_WIND:
		return Vector2(th0, SW_PH0)
	var u := clampf((t - SIDE_WIND) / SIDE_SWEEP, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - pow(u, 1.4), 2.6)
	var ph := lerpf(SW_PH0, SW_PH1, e) - (lerpf(SW_PH0, SW_PH1, 0.5) - SW_LOW) * sin(minf(e * 1.15, 1.0) * PI)
	return Vector2(lerpf(th0, SW_TH1, e), ph)

# the side swing's view at th, ph (one to the right): the hands on their circle behind the head (on screen the
# handle runs back from the head to them, low on the side it came from), the striking face the way it's going
static func _side_pose(th: float, ph: float) -> Transform3D:
	var a := deg_to_rad(th)
	var e := deg_to_rad(ph)
	var ag := deg_to_rad(clampf(th - SW_LAG, -85.0, 85.0))
	var g := SW_PIVOT + Vector3(SW_RADIUS * sin(ag), 0.0, -SW_RADIUS * cos(ag))
	return _pose(g, Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e)), Vector3(cos(a), 0.0, sin(a)))

# ---------------------------------------------------------------- the ground slam

## A ground slam at centre (world, on the floor) reaching b: thrown up and away, the nearer the harder, tumbling
## backward, and hurt. Returns the throw (m/s), ZERO if b is out of reach.
static func slam_body(b: VoxelBody, centre: Vector3, radius: float = SLAM_R) -> Vector3:
	var off := Vector3(b.global_position.x - centre.x, 0, b.global_position.z - centre.z)
	var d := off.length()
	if d > radius:
		return Vector3.ZERO
	var away := off / d if d > 0.01 else Vector3(0, 0, -1)
	var near := 1.0 - d / radius
	var v := (away * SLAM_OUT / (d + 0.5) + Vector3.UP * SLAM_LIFT * (0.8 + 0.3 * near)) * (0.6 if b.heavy() else 1.0)
	b.launch(v, 3.0 + 4.0 * near)
	b.hurt(SLAM_HURT)
	return v

func _slam_now() -> void:
	var t0 := Time.get_ticks_usec()
	var pp: Vector3 = shooter.player.global_position
	var c := Vector3(pp.x, 0.0, pp.z)
	sfx("slam", Vector3.INF, 2.0)
	var popped: int = arena.debris.pop(c, SLAM_R, 4.5, 2000)
	# lying pieces tossed up and out
	var pushed := 0
	for pc in arena.pieces.list():
		var rv: Variant = pc.rb
		if not is_instance_valid(rv):
			continue
		var rb: RigidBody3D = rv
		var off := rb.global_position - c
		off.y = 0.0
		var d := off.length()
		if d > SLAM_R:
			continue
		var away := off / d if d > 0.01 else Vector3(0, 0, -1)
		rb.sleeping = false
		rb.linear_velocity += away * SLAM_OUT * 1.3 / (d + 0.5) + Vector3.UP * SLAM_LIFT * (1.2 - 0.4 * d / SLAM_R)
		rb.angular_velocity += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 7.0
		pushed += 1
	_wave = {"c": c, "t": 0.0, "done": {}, "n": 0, "ms": 0.0}
	_ring(c + Vector3(0, 0.03, 0), Vector3.UP, SLAM_R, RING_T, true)
	_ring(c + Vector3(0, 0.03, 0), Vector3.UP, SLAM_R * 0.6, RING_T * 1.4, false)
	shooter.kick = 2.0
	hit_stop(0.1, 0.04)
	last = {"move": "slam", "launched": 0, "popped": popped, "pieces_pushed": pushed,
		"ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1), "wave_ms": 0.0}
	_wave_step(0.0)

# the shockwave going out: everyone it has reached is thrown (once)
func _wave_step(dt: float) -> void:
	if _wave.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	_wave.t += dt
	var k := clampf(float(_wave.t) / RING_T, 0.0, 1.0)
	var r := SLAM_R * (1.0 - pow(1.0 - k, 2.2)) + 0.3
	var c: Vector3 = _wave.c
	var done: Dictionary = _wave.done
	for b in arena.bodies:
		if not is_instance_valid(b):
			continue
		var id: int = b.get_instance_id()
		if done.has(id):
			continue
		var d := Vector2(b.global_position.x - c.x, b.global_position.z - c.z).length()
		if d <= minf(r, SLAM_R):
			done[id] = true
			slam_body(b, c)
			_wave.n += 1
	_wave.ms += (Time.get_ticks_usec() - t0) / 1000.0
	if last.get("move", "") == "slam":
		last["launched"] = _wave.n
		last["wave_ms"] = snappedf(float(_wave.ms), 0.01)
	if k >= 1.0:
		_wave = {}

# ---------------------------------------------------------------- the look

# the view's pose at t into the move: rest (breathing a little); a smash rises (easing into the top, where it hangs),
# drops (faster and faster), lands with a little bounce and goes back; the slam the same, straight down at your feet;
# a side swing see _side_view
func _view_xform(t: float) -> Transform3D:
	var rest := _rest
	rest.origin += Vector3(0.0, sin(_clock * 1.9) * 0.006, 0.0)
	if _move == "":
		return rest
	if _move == "side":
		return _side_view(t, rest)
	var smash := _move == "smash"
	var up_t := SMASH_UP if smash else SLAM_UP
	var hit_t := SMASH_HIT if smash else SLAM_HIT
	var end_t := SMASH_END if smash else SLAM_END
	var top := _raise if smash else _slam_raise
	var land := (_hit_low if _low else _hit) if smash else _slam_hit
	if t < up_t:
		var k := 1.0 - pow(1.0 - t / up_t, 2.5)
		return rest.interpolate_with(top, k)
	if t < hit_t:
		# down, the hands swept out in front (straight from top to land they'd pass right by your eyes)
		var k2 := (t - up_t) / (hit_t - up_t)
		var down := top.interpolate_with(land, k2 * k2)
		down.origin += Vector3(0.0, 0.0, -0.3) * sin(k2 * k2 * PI)
		return down
	var settle := 0.12 if smash else 0.2
	if t < hit_t + settle:
		var x := land
		x.origin += Vector3(0.0, 0.03, 0.015) * sin((t - hit_t) / settle * PI)
		return x
	var k3 := clampf((t - hit_t - settle) / (end_t - hit_t - settle), 0.0, 1.0)
	return land.interpolate_with(rest, k3 * k3 * (3.0 - 2.0 * k3))

# a side swing: from rest cocked back at the far side (easing into it, where it hangs a moment), swept across head
# first and through, then down out of sight at the side it went to and back up to rest
func _side_view(t: float, rest: Transform3D) -> Transform3D:
	if t < SIDE_WIND:
		var k := 1.0 - pow(1.0 - t / SIDE_WIND, 2.5)
		return rest.interpolate_with(_mirror(_side_pose(SW_TH0, SW_PH0), _side), k)
	var done_t := SIDE_WIND + SIDE_SWEEP
	if t < done_t:
		var a := _side_angles(t)
		return _mirror(_side_pose(a.x, a.y), _side)
	var k2 := clampf((t - done_t) / (SIDE_END - done_t), 0.0, 1.0)
	var low := _mirror(_side_low, _side)
	if k2 < 0.5:
		return _mirror(_side_pose(SW_TH1, SW_PH1), _side).interpolate_with(low, smoothstep(0.0, 1.0, k2 * 2.0))
	return low.interpolate_with(rest, smoothstep(0.0, 1.0, k2 * 2.0 - 1.0))

func _pose_view() -> void:
	_ham.transform = _view_xform(_t)

# top-down, a side swing: Jared turned into it and the hammer swept level round him at the hand (back to how he holds
# it before and after)
func _pose_hand() -> void:
	if _hand == null or not is_instance_valid(_hand) or not _hand.is_inside_tree():
		return
	if _move != "side" or not top_down():
		_hand.transform = Transform3D.IDENTITY
		return
	var w := 1.0
	if _t < SIDE_WIND:
		w = 1.0 - pow(1.0 - _t / SIDE_WIND, 2.5)
	elif _t > SIDE_WIND + SIDE_SWEEP:
		w = 1.0 - smoothstep(SIDE_WIND + SIDE_SWEEP, SIDE_END, _t)
	var th := _side_angles(_t, TD_TH0).x * _side
	var root := _hand.get_parent() as Node3D
	var att := root.get_parent() as BoneAttachment3D
	var sk: Skeleton3D = shooter.avatar.skeleton
	if att == null or sk == null:
		return
	# the whole of him turns (his hips are the root: the arena poses them each frame, so this is for this frame)
	var hb := maxi(0, int(shooter.avatar.model.bone("hips")))
	var twist := Quaternion(Vector3.UP, -deg_to_rad(th) * TWIST * w)
	sk.set_bone_pose_rotation(hb, twist * sk.get_bone_pose_rotation(hb))
	sk.set_bone_pose_position(hb, twist * sk.get_bone_pose_position(hb))
	# the hammer level out from the fist along th, the face the way it's going (the hand's own space: its +z)
	var fr := frame()
	var a := deg_to_rad(th)
	var d := (-fr.z * cos(a) + fr.x * sin(a) + Vector3.UP * 0.1).normalized()
	var go := (fr.x * cos(a) + fr.z * sin(a)) * _side
	var x := (go - d * go.dot(d)).normalized()
	var root_g := sk.global_transform * sk.get_bone_global_pose(att.bone_idx) * root.transform
	var want := Transform3D(Basis(x, d.cross(x), d), root_g.origin)
	_hand.transform = Transform3D.IDENTITY.interpolate_with(root_g.affine_inverse() * want, w)

# the smear behind the head as it comes down (a band as wide as the head), or as it sweeps across (along the end of
# the handle, brightest at the head)
func _draw_trail() -> void:
	var im: ImmediateMesh = _trail.mesh
	im.clear_surfaces()
	if _move == "" or top_down():
		return
	var side := _move == "side"
	var a_t := SIDE_WIND if side else (SMASH_UP if _move == "smash" else SLAM_UP)
	var b_t := SIDE_WIND + SIDE_SWEEP * 0.75 if side else (SMASH_HIT if _move == "smash" else SLAM_HIT)
	if _t < a_t or _t > b_t + 0.08:
		return
	var t1 := minf(_t, b_t)
	var t0 := maxf(a_t, t1 - (0.07 if side else 0.075))
	if t1 - t0 < 0.004:
		return
	var fade := 1.0 - clampf((_t - b_t) / 0.08, 0.0, 1.0)
	var steps := 12
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in steps + 1:
		var a := float(i) / steps
		var x := _view_xform(lerpf(t0, t1, a))
		var c := Color(0.85, 0.88, 0.95, (0.42 if side else 0.35) * a * a * fade)
		im.surface_set_color(Color(c.r, c.g, c.b, c.a * (0.1 if side else 1.0)))
		im.surface_add_vertex(x * (Vector3(0, 0.45, 0) if side else Vector3(-0.09, 0.82, 0)))
		im.surface_set_color(c)
		im.surface_add_vertex(x * (Vector3(0, 0.92, 0) if side else Vector3(0.09, 0.82, 0)))
	im.surface_end()

# top-down: the side swing's smear, level round Jared at the hammer's height, from the hand out to past the head
func _draw_sweep() -> void:
	var im: ImmediateMesh = _sweep.mesh
	im.clear_surfaces()
	if _move != "side" or not top_down() or _t < SIDE_WIND:
		return
	var end_t := SIDE_WIND + SIDE_SWEEP * 0.75
	if _t > end_t + 0.1:
		return
	var fade := 1.0 - clampf((_t - end_t) / 0.1, 0.0, 1.0)
	var now := _side_angles(minf(_t, end_t), TD_TH0).x
	var from := maxf(TD_TH0, now - 100.0)
	if now - from < 1.0:
		return
	var c := eye() + Vector3.DOWN * 0.1
	var fr := frame()
	var steps := 14
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in steps + 1:
		var k := float(i) / steps
		var a := deg_to_rad(lerpf(from, now, k) * _side)
		var dl := -fr.z * cos(a) + fr.x * sin(a)
		var col := Color(0.9, 0.92, 1.0, 0.65 * k * k * fade)
		im.surface_set_color(Color(col.r, col.g, col.b, col.a * 0.15))
		im.surface_add_vertex(c + dl * 0.45)
		im.surface_set_color(col)
		im.surface_add_vertex(c + dl * 1.55)
	im.surface_end()

# a shock ring at c facing n, out to r metres over dur seconds; wall: a low band standing up round its edge too
func _ring(c: Vector3, n: Vector3, r: float, dur: float, wall: bool) -> void:
	_rings.append({"c": c, "n": n.normalized(), "t": 0.0, "dur": dur, "r": r, "wall": wall})

func _draw_rings() -> void:
	var im: ImmediateMesh = _fx.mesh
	im.clear_surfaces()
	if _rings.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 56
	for rg in _rings:
		var k := clampf(float(rg.t) / float(rg.dur), 0.0, 1.0)
		var rmax: float = rg.r
		var r := rmax * (1.0 - pow(1.0 - k, 2.2))
		var w := rmax * lerpf(0.12, 0.04, k)
		var a := pow(1.0 - k, 1.3)
		var c: Vector3 = rg.c
		var n: Vector3 = rg.n
		var u := n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD).normalized()
		var v := n.cross(u)
		var h := lerpf(0.5, 0.06, k) * minf(1.0, rmax / 3.0)
		var hot := Color(1.0, 0.86, 0.6, 0.85 * a)
		var cold := Color(1.0, 0.8, 0.5, 0.0)
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var e0 := u * cos(a0) + v * sin(a0)
			var e1 := u * cos(a1) + v * sin(a1)
			var o0 := c + e0 * r
			var o1 := c + e1 * r
			var i0 := c + e0 * maxf(0.0, r - w)
			var i1 := c + e1 * maxf(0.0, r - w)
			# the flat band: bright at its leading edge, fading in
			_tri(im, o0, hot, o1, hot, i1, cold)
			_tri(im, o0, hot, i1, cold, i0, cold)
			if bool(rg.wall):
				var top0 := o0 + n * h
				var top1 := o1 + n * h
				_tri(im, o0, hot, o1, hot, top1, cold)
				_tri(im, o0, hot, top1, cold, top0, cold)
	im.surface_end()

static func _tri(im: ImmediateMesh, p0: Vector3, c0: Color, p1: Vector3, c1: Color, p2: Vector3, c2: Color) -> void:
	im.surface_set_color(c0)
	im.surface_add_vertex(p0)
	im.surface_set_color(c1)
	im.surface_add_vertex(p1)
	im.surface_set_color(c2)
	im.surface_add_vertex(p2)

# ---------------------------------------------------------------- checks

static func _grunt(host: Node, m: Material, at: Vector3 = Vector3.ZERO, chunk: int = 1) -> VoxelBody:
	var b := VoxelBody.new()
	host.add_child(b)
	b.setup("grunt", 0.023 * chunk, chunk, m)
	b.position = at
	b.animate(0.0, false)
	return b

static func _joint(b: VoxelBody, bone: String) -> Vector3:
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(b.model.bone(bone)).origin

## The smash, the side swings and the slam on grunts standing at the origin facing +z (the logic test).
static func checks(host: Node) -> Array:
	var out := []
	var was_immortal := VoxelBody.immortal
	VoxelBody.immortal = false
	var m := StandardMaterial3D.new()
	# where you look from 1.4 m off finds his chest; from 3.6 m it's out of reach
	var b := _grunt(host, m)
	var from := Vector3(0, 1.65, 1.4)
	var dir := (Vector3(0, 1.0, 0) - from).normalized()
	var tg := aim_at([b], from, dir)
	out.append([tg.size() == 2 and tg[0] == b, "hammer aim: from 1.4 m a smash finds the grunt where you look"])
	var from2 := Vector3(0, 1.65, 3.6)
	out.append([aim_at([b], from2, (Vector3(0, 1.0, 0) - from2).normalized()).is_empty(), "hammer aim: 3.6 m off is out of reach (the floor)"])
	if tg.size() == 2:
		var h: Dictionary = tg[1]
		var hp0 := b.hp
		var t0 := Time.get_ticks_usec()
		var r := smash_body(b, h.point, dir)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		out.append([int(r.cut) > 300 and (r.bits as Array).size() > 100, "smash on the chest: a big crater (%d cubes, %.1f ms)" % [int(r.cut), ms]])
		out.append([b.alive and b.hp <= hp0 - SMASH_HURT - 5.0 and b.hp > 30.0, "smash on the chest: health %.0f -> %.0f, still up" % [hp0, b.hp]])
		out.append([b.knock.length() >= 2.0 and b.knock.z < 0.0 and b.stagger > 0.3, "smash on the chest: shoved back (%.1f m/s), reeling" % b.knock.length()])
		# a second one finishes him
		var h2 := b.trace(from, dir, REACH)
		if not h2.is_empty():
			smash_body(b, h2.point, dir)
		out.append([not b.alive, "a second smash on the chest kills (hp %.0f)" % b.hp])
	b.queue_free()
	# at 2 sprite pixels a cube (F2) an eighth of the cubes go, but the chest smash costs about the same
	var bc := _grunt(host, m, Vector3.ZERO, 2)
	var tgc := aim_at([bc], from, dir)
	if tgc.size() == 2:
		var hc: Dictionary = tgc[1]
		smash_body(bc, hc.point, dir)
	out.append([bc.alive and bc.hp > 30.0 and bc.hp < 65.0, "smash on the chest at 2 sprite pixels a cube: health 100 -> %.0f, as at 1" % bc.hp])
	bc.queue_free()
	# from above on the top of the head: the brain goes, he's dead
	var b2 := _grunt(host, m)
	var from3 := Vector3(0, 2.5, 0.45)
	var dir3 := (Vector3(0, 1.72, 0) - from3).normalized()
	var tg2 := aim_at([b2], from3, dir3)
	if tg2.size() == 2:
		var h3: Dictionary = tg2[1]
		var r3 := smash_body(b2, h3.point, dir3)
		out.append([not b2.alive and String(h3.part) == "head", "smash on top of the head kills (%s, brain %d of %d gone, %d cubes)" % [h3.part, b2.brain_lost, b2.brain_start, int(r3.cut)]])
	else:
		out.append([false, "smash on top of the head: missed it"])
	b2.queue_free()
	# at the elbow: the forearm and hand come off; at the knee: the leg below
	var b3 := _grunt(host, m)
	var r4 := smash_body(b3, _joint(b3, "forearm_r") + Vector3(0, 0, 0.05), Vector3(0, 0, -1))
	out.append([bool(b3.parts.hand_r.gone) and not (r4.pieces as Array).is_empty() and not bool(b3.parts.arm_r.gone), "smash at the elbow knocks the forearm off, the upper arm stays (%d pieces)" % (r4.pieces as Array).size()])
	var r5 := smash_body(b3, _joint(b3, "shin_l") + Vector3(0, 0, 0.05), Vector3(0, 0, -1))
	out.append([b3.legs_lost() >= 1 and bool(b3.parts.foot_l.gone) and not (r5.pieces as Array).is_empty(), "smash at the knee takes the leg off below (legs lost %d)" % b3.legs_lost()])
	b3.queue_free()
	out.append_array(_side_checks(host, m))
	# the slam: one 1 m off, one 3 m off, one 6 m off
	var bn := _grunt(host, m, Vector3(0, 0, -1.0))
	var bm := _grunt(host, m, Vector3(3.0, 0, 0))
	var bf := _grunt(host, m, Vector3(0, 0, 6.0))
	var vn := slam_body(bn, Vector3.ZERO)
	var vmid := slam_body(bm, Vector3.ZERO)
	var vf := slam_body(bf, Vector3.ZERO)
	out.append([bn.airborne and bm.airborne and not bf.airborne and vf == Vector3.ZERO, "ground slam: the ones within %.1f m are thrown up, not one 6 m off" % SLAM_R])
	out.append([vn.z < -1.0 and vmid.x > 0.3 and vn.y > 2.5 and Vector2(vn.x, vn.z).length() > Vector2(vmid.x, vmid.z).length() * 2.0,
		"ground slam: away from the hammer, the nearer the harder (%.1f vs %.1f m/s out)" % [Vector2(vn.x, vn.z).length(), Vector2(vmid.x, vmid.z).length()]])
	out.append([is_equal_approx(bn.hp, 100.0 - SLAM_HURT) and bf.hp == 100.0, "ground slam: hurts the ones it reaches (hp %.0f)" % bn.hp])
	for i in 75:
		bn.react_step(1.0 / 60.0)
	out.append([not bn.airborne and bn.down_t > 0.0 and bn.position.z < -1.8, "ground slam: lands further out, lying there (%.2f m)" % bn.position.z])
	bn.queue_free()
	bm.queue_free()
	bf.queue_free()
	VoxelBody.immortal = was_immortal
	return out

# the side swings: which click the mouse makes, where the head lands, what it does, the view
static func _side_checks(host: Node, m: Material) -> Array:
	var out := []
	var fwd := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	var ok := pick_swing(Vector2(300, 40), false, fwd, right) == 1 and pick_swing(Vector2(-300, -60), false, fwd, right) == -1
	ok = ok and pick_swing(Vector2(40, 300), false, fwd, right) == 0 and pick_swing(Vector2(20, 10), false, fwd, right) == 0
	out.append([ok, "side swing: the mouse moving right swings right, left swings left; up/down or still is the smash"])
	# top-down by the floor: facing down the screen (+z) a move to the right is across toward his left; facing +x a
	# move down the screen (+z) is toward his right
	var td := pick_swing(Vector2(300, 0), true, Vector3(0, 0, 1), Vector3(-1, 0, 0)) == -1
	td = td and pick_swing(Vector2(0, 300), true, Vector3(1, 0, 0), Vector3(0, 0, 1)) == 1
	td = td and pick_swing(Vector2(0, 300), true, Vector3(0, 0, 1), Vector3(-1, 0, 0)) == 0
	out.append([td, "side swing top-down: the side follows the mouse across the way Jared faces"])
	# swung at the chest from 1.4 m, looking at it: struck on the side it comes from
	var from := Vector3(0, 1.65, 1.4)
	var look_d := (Vector3(0, 1.0, 0) - from).normalized()
	var rgt := look_d.cross(Vector3.UP).normalized()
	var b := _grunt(host, m)
	var t0 := Time.get_ticks_usec()
	var hr := side_hit([b], from, look_d, rgt, 1)
	var ms_trace := (Time.get_ticks_usec() - t0) / 1000.0
	var hl := side_hit([b], from, look_d, rgt, -1)
	out.append([hr.size() == 3 and hl.size() == 3, "side swing: a swing either way at 1.4 m meets him (%s, %s; the whole arc's rays %.1f ms)" % [
		(hr[1] as Dictionary).part if hr.size() == 3 else "nothing", (hl[1] as Dictionary).part if hl.size() == 3 else "nothing", ms_trace]])
	if hr.size() == 3 and hl.size() == 3:
		var pr: Vector3 = (hr[1] as Dictionary).point
		var pl: Vector3 = (hl[1] as Dictionary).point
		out.append([pr.x < -0.1 and pl.x > 0.1 and float(hr[2]) < -5.0 and float(hl[2]) < -5.0,
			"side swing: struck on the side it comes from (to the right at x %.2f, to the left at %.2f)" % [pr.x, pl.x]])
		var h: Dictionary = hr[1]
		var hp0 := b.hp
		var t1 := Time.get_ticks_usec()
		var r := side_blow(b, h, side_push(rgt, 1))
		var ms := (Time.get_ticks_usec() - t1) / 1000.0
		out.append([int(r.cut) > 150 and (r.bits as Array).size() > 50 and b.hp <= hp0 - SIDE_HURT,
			"side swing to the right on the %s: a crater (%d cubes, parts %s, %d pieces, %.1f ms), health %.0f -> %.0f" % [
			h.part, int(r.cut), str(r.parts), (r.pieces as Array).size(), ms, hp0, b.hp]])
		out.append([b.airborne and b.air_v.x > 5.0 and b.air_v.y > 2.0 and absf(b.air_v.z) < 2.0,
			"side swing to the right: thrown sideways to the right, up (%s m/s)" % str(b.air_v.snapped(Vector3.ONE * 0.1))])
		for i in 90:
			b.react_step(1.0 / 60.0)
		out.append([not b.airborne and b.position.x > 2.5, "side swing: he lands %.1f m off to the side" % b.position.x])
		b.queue_free()
		var b2 := _grunt(host, m)
		var hl2 := side_hit([b2], from, look_d, rgt, -1)
		if hl2.size() == 3:
			side_blow(b2, hl2[1], side_push(rgt, -1))
		out.append([b2.airborne and b2.air_v.x < -5.0, "side swing to the left: thrown to the left (%.1f m/s)" % b2.air_v.x])
		b2.queue_free()
	else:
		b.queue_free()
	# at head height: a big chunk of the head goes
	var b3 := _grunt(host, m)
	var look_h := (Vector3(0, 1.62, 0) - from).normalized()
	var hh := side_hit([b3], from, look_h, look_h.cross(Vector3.UP).normalized(), 1)
	if hh.size() == 3 and String((hh[1] as Dictionary).part) == "head":
		var r3 := side_blow(b3, hh[1], side_push(rgt, 1))
		out.append([b3.brain_lost > 0 and int(r3.cut) > 300, "side swing to the head: a big chunk of it (%d cubes, brain %d of %d, %s)" % [
			int(r3.cut), b3.brain_lost, b3.brain_start, "dead" if not b3.alive else "alive"]])
	else:
		out.append([false, "side swing at head height meets the head (%s)" % ((hh[1] as Dictionary).part if hh.size() == 3 else "nothing")])
	b3.queue_free()
	# on the arm from the side: it comes off, crushed on into his ribs
	var b4 := _grunt(host, m)
	var ja := _joint(b4, "forearm_r")
	var r4 := side_blow(b4, {"point": ja + Vector3(-0.03, 0, 0), "part": "forearm_r", "dir": Vector3(0, -0.3, -1).normalized(),
		"travel": Vector3(1, 0, 0)}, side_push(rgt, 1))
	out.append([bool(b4.parts.hand_r.gone) and not (r4.pieces as Array).is_empty() and (r4.parts as Array).has("torso"),
		"side swing on the arm: it comes off (%d pieces) and the ribs behind it cave in (parts %s)" % [(r4.pieces as Array).size(), str(r4.parts)]])
	b4.queue_free()
	# one standing right by him takes it too; one 2 m off doesn't; out of reach and behind you, nothing
	var b5 := _grunt(host, m)
	var b6 := _grunt(host, m, Vector3(0.5, 0, -0.2))
	var b7 := _grunt(host, m, Vector3(2.5, 0, 0))
	var h5 := side_hit([b5, b6, b7], from, look_d, rgt, 1)
	var nb: Array = next_to([b5, b6, b7], b5, (h5[1] as Dictionary).point, (h5[1] as Dictionary).travel, from) if h5.size() == 3 else []
	out.append([h5.size() == 3 and h5[0] == b5 and nb.size() == 2 and nb[0] == b6, "side swing: the first body along the arc, and the one right by him, take it (not one 2.5 m off)"])
	var far := side_hit([b5], Vector3(0, 1.65, 3.4), (Vector3(0, 1.0, 0) - Vector3(0, 1.65, 3.4)).normalized(), rgt, 1)
	var behind := side_hit([b5], Vector3(0, 1.65, -1.4), Vector3(0, -0.3, -1).normalized(), Vector3(1, 0, 0), 1)
	out.append([far.is_empty() and behind.is_empty(), "side swing: 3.4 m off is out of reach, behind you is missed"])
	b5.queue_free()
	b6.queue_free()
	b7.queue_free()
	# one crawling at your feet (no legs) is swept over, and cheaply: the rays that miss his box aren't traced
	var b9 := _grunt(host, m, Vector3(0, 0, 0.4))
	b9._blow("thigh_l")
	b9._blow("thigh_r")
	b9.animate(0.0, false)
	var t9 := Time.get_ticks_usec()
	var low := side_hit([b9], from, Vector3(0, 0, -1), Vector3(1, 0, 0), 1)
	out.append([low.is_empty(), "side swing: passes over one crawling at your feet (the whole arc %.2f ms)" % ((Time.get_ticks_usec() - t9) / 1000.0)])
	b9.queue_free()
	# frozen solid, he shatters
	var b8 := _grunt(host, m)
	b8.chill(2.0)
	var h8 := side_hit([b8], from, look_d, rgt, 1)
	if h8.size() == 3 and b8.frozen():
		var r8 := side_blow(b8, h8[1], side_push(rgt, 1))
		out.append([bool(r8.get("shattered", false)) and not b8.alive and (r8.bits as Array).size() > 500, "side swing on a frozen one shatters him (%d cubes fly)" % (r8.bits as Array).size()])
	else:
		out.append([false, "side swing on a frozen one: not frozen or missed"])
	b8.queue_free()
	# the view, first person: cocked back at the far side with the head in sight, swept across the middle low head
	# first (on screen the head ahead of the hands), the hammer always clear of your eye
	var w := VoxelMeleeHammer.new()
	w._init_poses()
	w._move = "side"
	var clear := 9.0
	var shown := true
	var crossed := true
	var leads := true
	for sd in [1, -1]:
		w._side = sd
		var wind := w._view_xform(SIDE_WIND) * Vector3(0, 0.82, 0)
		shown = shown and wind.z < -0.2 and wind.x * sd < 0.0 and absf(wind.x / wind.z) < 1.4 and absf(wind.y / wind.z) < 0.8
		var mid := false
		var t := 0.0
		while t <= SIDE_END:
			var x := w._view_xform(t)
			clear = minf(clear, Geometry3D.get_closest_point_to_segment(Vector3.ZERO, x * Vector3(0, -0.15, 0), x * Vector3(0, 0.9, 0)).length())
			var hd := x * Vector3(0, 0.82, 0)
			if t > SIDE_WIND and hd.z < -0.5 and absf(hd.x / hd.z) < 0.15 and hd.y / -hd.z < 0.0 and hd.y / -hd.z > -0.4:
				mid = true
			var hand := x * Vector3(0, 0.3, 0)
			if t > SIDE_WIND and t < SIDE_WIND + SIDE_SWEEP * 0.5 and hd.z < -0.3 and absf(hd.x / hd.z) < 1.3:
				leads = leads and (hd.x / -hd.z - hand.x / -hand.z) * sd > 0.05
			t += 0.005
		crossed = crossed and mid
	w.free()
	out.append([shown, "side swing view: cocked back at the far side, the head in sight"])
	out.append([crossed, "side swing view: the head sweeps across the middle, a little low (chest height)"])
	out.append([leads, "side swing view: the head leads across, the handle trailing back to the hands"])
	out.append([clear > 0.12, "side swing view: the hammer passes %.2f m clear of your eye" % clear])
	return out
