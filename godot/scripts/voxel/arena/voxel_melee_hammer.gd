class_name VoxelMeleeHammer
extends VoxelMelee
## The sledgehammer (the owner, 20 Oct: five melee weapons, each doing something different): slow, heavy, crushing.
## Left click is an overhead smash: the hammer goes up over your head, hangs there a moment, comes down where you
## look and scoops a big round crater out of whatever it meets (VoxelBody.carve, a ball): a chest caved in, the top of
## a head gone (that kills), an arm or a leg knocked clean off where it lands; the one hit reels back and the cubes
## blow out of the crater. On the floor it just thumps, throwing the cubes lying there back up. Right click is a
## ground slam: the hammer comes down at your feet and a shockwave rings out across the floor; everyone it reaches is
## thrown up and away (the nearer the harder) and knocked down, lying cubes jump and lying pieces are tossed. Both
## freeze the game a blink as they land and kick the view. Top-down the smash goes toward the mouse and the slam rings
## out round Jared. Put away mid-move, the move is called off. Owned by the voxel session.

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
const STEEL := Color(0.58, 0.6, 0.65)
const FACE := Color(0.26, 0.27, 0.3)
const WOOD := Color(0.5, 0.31, 0.15)
const WRAP := Color(0.16, 0.11, 0.08)

var _ham: Node3D                # the hammer in the view: the grip at its origin, the handle up +y, the striking face -z
var _trail: MeshInstance3D      # the smear behind the head as it comes down (in the view)
var _fx: MeshInstance3D         # shock rings (world)
var _move := ""                 # "smash", "slam" or "" (at rest)
var _t := -1.0                  # seconds into the move
var _hit_done := false
var _low := false               # the smash is coming down on the floor (the view takes it lower)
var _cd_smash := 0.0
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

func _build() -> void:
	_ham = Node3D.new()
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
	view.add_child(_trail)
	_fx = MeshInstance3D.new()
	_fx.mesh = ImmediateMesh.new()
	_fx.material_override = _glow_mat()
	_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.top_level = true
	add_child(_fx)
	# at rest low across the body, the head on the left; raised up over the right shoulder; landed ahead (on a body
	# where you look, or lower on the floor); the slam's raise right over the head and its landing at your feet
	_rest = _pose(Vector3(0.28, -0.4, -0.44), Vector3(-0.88, 0.15, -0.45), Vector3(0.2, 0.95, 0.1))
	_raise = _pose(Vector3(0.15, 0.1, -0.42), Vector3(-0.1, 0.7, 0.7), Vector3(0.0, 0.7, -0.7))
	_hit = _pose(Vector3(0.2, -0.4, 0.2), Vector3(-0.2, 0.25, -0.75), Vector3(0.0, -1.0, 0.2))
	_hit_low = _pose(Vector3(0.18, -0.5, 0.22), Vector3(-0.18, 0.15, -0.77), Vector3(0.0, -1.0, 0.1))
	_slam_raise = _pose(Vector3(0.08, 0.14, -0.4), Vector3(-0.05, 0.75, 0.65), Vector3(0.0, 0.65, -0.75))
	_slam_hit = _pose(Vector3(0.15, -0.45, 0.26), Vector3(-0.15, 0.12, -0.78), Vector3(0.0, -1.0, 0.1))
	_pose_view()

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

func busy() -> bool:
	return _t >= 0.0

func cooling() -> float:
	return maxf(clampf(_cd_smash / SMASH_CD, 0.0, 1.0), clampf(_cd_slam / SLAM_CD, 0.0, 1.0))

func press(button: int) -> void:
	if _t >= 0.0:
		return
	if button == MOUSE_BUTTON_LEFT and _cd_smash <= 0.0:
		_start("smash")
		_cd_smash = SMASH_CD
	elif button == MOUSE_BUTTON_RIGHT and _cd_slam <= 0.0:
		_start("slam")
		_cd_slam = SLAM_CD

func _start(m: String) -> void:
	_move = m
	_t = 0.0
	_hit_done = false
	_low = false

# put away mid-move: called off (a blow not landed yet never lands, so it can't land with a gun out); the cooldown
# stays, and a shockwave already going out goes on
func on_deselect() -> void:
	_t = -1.0
	_move = ""

# top-down: the head lies across the end of the handle (seen from above it's a T), its faces darker
func hand_mesh() -> Node3D:
	var root := Node3D.new()
	var steel := mat(STEEL, 0.3, 0.45)
	var face := mat(FACE, 0.3, 0.55)
	box(root, Vector3(0.034, 0.034, 0.9), Vector3(0, 0, 0.33), mat(WOOD))
	box(root, Vector3(0.042, 0.042, 0.22), Vector3(0, 0, 0.04), mat(WRAP))
	box(root, Vector3(0.25, 0.14, 0.14), Vector3(0, 0, 0.82), steel)
	for s in [-1.0, 1.0]:
		box(root, Vector3(0.016, 0.124, 0.124), Vector3(0.13 * s, 0, 0.82), face)
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
	_cd_smash = maxf(0.0, _cd_smash - dt)
	_cd_slam = maxf(0.0, _cd_slam - dt)
	if _t >= 0.0:
		_t += dt
		var up_t := SMASH_UP if _move == "smash" else SLAM_UP
		var hit_t := SMASH_HIT if _move == "smash" else SLAM_HIT
		var end_t := SMASH_END if _move == "smash" else SLAM_END
		if top_down() and _t < up_t:
			arena.avatar.attack = 0.5          # arms up while it's raised; they come down with it
		if _move == "smash" and not _hit_done and _t >= up_t and _t - dt < up_t:
			_low = _target().is_empty()        # coming down: on a body, or lower on the floor
		if not _hit_done and _t >= hit_t:
			_hit_done = true
			if _move == "smash":
				_smash_now()
			else:
				_slam_now()
		if _t >= end_t:
			_t = -1.0
			_move = ""
	_wave_step(dt)
	for i in range(_rings.size() - 1, -1, -1):
		_rings[i].t += dt
		if float(_rings[i].t) >= float(_rings[i].dur):
			_rings.remove_at(i)
	_pose_view()
	_draw_trail()
	_draw_rings()

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
	b.knock = flat * SHOVE * (0.55 if b.key == "brute" else 1.0)     # the dead slide back too
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
		# the floor: a thump, the lying cubes round it jump
		var fp := _floor_point(eye(), look())
		var popped: int = arena.debris.pop(fp, 1.1, 3.2, 500)
		_ring(fp + Vector3(0, 0.03, 0), Vector3.UP, 1.2, 0.25, true)
		arena._kick = maxf(float(arena._kick), 1.3)
		hit_stop(0.06, 0.05)
		last = {"move": "smash", "hit": "floor", "popped": popped, "ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)}
		return
	var b: VoxelBody = tg[0]
	var h: Dictionary = tg[1]
	var dir: Vector3 = tg[2]
	var hp0 := b.hp
	var res := smash_body(b, h.point, dir)
	var c: Vector3 = res.centre
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
	arena._kick = 2.0
	hit_stop(0.09, 0.03)
	last = {"move": "smash", "hit": String(h.part), "cut": res.cut, "parts": res.parts, "pieces": (res.pieces as Array).size(),
		"killed": res.killed, "head_off": res.head_off, "hp": snappedf(hp0, 1.0), "hp_now": snappedf(b.hp, 1.0),
		"carve_ms": res.carve_ms, "ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)}

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
	var v := (away * SLAM_OUT / (d + 0.5) + Vector3.UP * SLAM_LIFT * (0.8 + 0.3 * near)) * (0.6 if b.key == "brute" else 1.0)
	b.launch(v, 3.0 + 4.0 * near)
	b.hurt(SLAM_HURT)
	return v

func _slam_now() -> void:
	var t0 := Time.get_ticks_usec()
	var pp: Vector3 = arena.player.global_position
	var c := Vector3(pp.x, 0.0, pp.z)
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
	arena._kick = 2.0
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
# drops (faster and faster), lands with a little bounce and goes back; the slam the same, straight down at your feet
func _view_xform(t: float) -> Transform3D:
	var rest := _rest
	rest.origin += Vector3(0.0, sin(_clock * 1.9) * 0.006, 0.0)
	if _move == "":
		return rest
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

func _pose_view() -> void:
	_ham.transform = _view_xform(_t)

# the smear behind the head as it comes down
func _draw_trail() -> void:
	var im: ImmediateMesh = _trail.mesh
	im.clear_surfaces()
	if _move == "":
		return
	var up_t := SMASH_UP if _move == "smash" else SLAM_UP
	var hit_t := SMASH_HIT if _move == "smash" else SLAM_HIT
	if _t < up_t or _t > hit_t + 0.08:
		return
	var t1 := minf(_t, hit_t)
	var t0 := maxf(up_t, t1 - 0.075)
	if t1 - t0 < 0.004:
		return
	var fade := 1.0 - clampf((_t - hit_t) / 0.08, 0.0, 1.0)
	var steps := 10
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in steps + 1:
		var a := float(i) / steps
		var x := _view_xform(lerpf(t0, t1, a))
		var c := Color(0.85, 0.88, 0.95, 0.35 * a * a * fade)
		# a band as wide as the head, along where it has been
		im.surface_set_color(c)
		im.surface_add_vertex(x * Vector3(-0.09, 0.82, 0))
		im.surface_set_color(c)
		im.surface_add_vertex(x * Vector3(0.09, 0.82, 0))
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

## The smash and the slam on grunts standing at the origin facing +z (the logic test).
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
