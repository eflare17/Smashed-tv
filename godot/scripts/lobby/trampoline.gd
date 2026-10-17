class_name Trampoline
extends Interactable
## The backyard trampoline (the HTML game's b326/b327, Smashed.html: TRAMP, trampNear, trampOn, trampOff,
## trampStep, trampHigh, trampLeap, airStep). Owned by the Trampoline and Gothica task.
##
## Round, its mat TRAMP.mat up inside a padded ring, a net TRAMP.net high round it on poles, at TRAMP.cx/cy with
## radius TRAMP.r (game_data.json; the node puts itself there in _ready unless place_from_data is off). Built in
## 3D: six legs, the steel frame with its springs, the blue pad and the mat on top, eight poles, a see-through
## net and the rope round its top; a cylinder to bump into (body, layer 1, inset like the World's solids).
## The World draws one too unless its include_trampoline is false: set that off when this one is in the scene.
##
## E: "CLIMB ON" next to it (within TRAMP.r + 40 of its middle), "CLIMB OFF" on it, "JUMP OFF" up high (more
## than TRAMP.net over the mat). On it (player.on_tramp) he walks about the mat as usual (the Player's own step)
## while this bounces him every physics frame: gravity TRAMP.g; landing throws him back up at keep (0.82) of the
## speed he hit with but never under vbase, or, if the roll action was pressed or held since the last landing,
## at that speed plus boost, up to vmax. His height is player.dz = mat + tz (HTML units) and his
## global_position.y follows it. The net keeps him within TRAMP.r - 22 of the middle; above the net (tz > net + 2)
## and moving outward faster than 30 a second he goes over it (trampLeap): no steering, 190 a second outward,
## falling under TRAMP.g till he lands on the grass (player.frozen meanwhile; this moves him).
## No sound yet.

## Put the node at TRAMP.cx, cy from game_data.json (off: wherever the scene put it).
@export var place_from_data: bool = true
## Make the collision cylinder (off if something else gives the trampoline one).
@export var build_body: bool = true

## The HTML game's TRAMP (overwritten from game_data.json).
var tr: Dictionary = {"cx": 707.0, "cy": 1340.0, "r": 122.0, "mat": 32.0, "net": 64.0, "g": 520.0,
	"vbase": 175.0, "vmax": 560.0, "boost": 110.0, "keep": 0.82}
## The cylinder to bump into (riders and fliers get a collision exception with it).
var body: StaticBody3D

## Who's on it: player -> {tz (over the mat), tv (up speed), tjump (roll pressed since the last landing)}.
var riders: Dictionary = {}
## Who's sailing off it: player -> {vx, vy (ground speed), tv (up speed)}.
var fliers: Dictionary = {}

## Fired as each rider lands on the mat (tests and, later, the boing): the speed he hit with, the new one up.
signal bounced(player: Node, hit: float, up: float)
## Fired when a flier lands on the grass.
signal landed(player: Node)

const U := 0.025                     # GameData.UNIT
const NET_IN := 22.0                 # trampStep: the net holds you TRAMP.r - 22 from the middle
const LEAP_SPEED := 190.0            # trampLeap
const LEAP_UP := 110.0
const R_DEFAULT := 14.0              # T.radius
## The HTML game steps its world at a fixed 1/120 s (FIXED_DT); the bounce does too, so its heights match.
const FIXED_DT := 1.0 / 120.0

func _ready() -> void:
	var d = GameData.data.get("TRAMP", {})
	if d is Dictionary:
		for k in d:
			tr[k] = float(d[k])
	if place_from_data:
		global_position = GameData.world_to_3d(tr.cx, tr.cy, 0.0)
	reach = tr.r + 40.0
	process_priority = 50             # after the Player's _process (0): the net check sees where he moved to
	process_physics_priority = 50
	_build()

# ------------------------------------------------------------------ E

func label_for(p: Node) -> String:
	if not (p is Node3D):
		return ""
	if riders.has(p):
		return "JUMP OFF" if is_high(p) else "CLIMB OFF"
	if is_near(p):
		return "CLIMB ON"
	return ""

func act(p: Node) -> void:
	if not (p is Node3D):
		return
	if riders.has(p):
		if is_high(p):
			# the way he's heading (or facing), like p.moving ? p.ix : p.fx
			var dir := Vector2.ZERO
			var steer = p.get("steer")
			var facing = p.get("facing")
			if _flag(p, "moving") and steer is Vector2:
				dir = steer
			elif facing is Vector2:
				dir = facing
			if dir.length() < 0.001:
				dir = _out_dir(p)
			leap(p, dir)
		else:
			climb_off(p)
	elif is_near(p):
		climb_on(p)

## trampNear: close enough to climb on (and not on it, flying off it or busy).
func is_near(p: Node) -> bool:
	if not (p is Node3D) or riders.has(p) or fliers.has(p):
		return false
	if _flag(p, "frozen") or _flag(p, "on_tramp") or float(_get_or(p, "dz", 0.0)) > 0.5:
		return false
	return ground_distance(p) < tr.r + 40.0

## trampHigh: more than the net's height over the mat.
func is_high(p: Node) -> bool:
	return float(_get_or(p, "dz", 0.0)) - tr.mat > tr.net

## How high over the mat he is (0 when not on it).
func height_over_mat(p: Node) -> float:
	return float(riders[p].tz) if riders.has(p) else 0.0

## trampOn: up over the edge onto the mat near where he stood.
func climb_on(p: Node3D) -> void:
	var o := _html(p)
	var a := atan2(o.y - tr.cy, o.x - tr.cx)
	var d: float = tr.r - 36.0
	riders[p] = {"tz": 0.0, "tv": 150.0, "tjump": false, "acc": 0.0}
	fliers.erase(p)
	_halt(p)
	_set_if(p, "on_tramp", true)
	_set_if(p, "dz", tr.mat)
	_exceptions(p, true)
	p.global_position = GameData.world_to_3d(tr.cx + cos(a) * d, tr.cy + sin(a) * d, tr.mat)

## trampOff: over the side he's nearest, back onto the grass.
func climb_off(p: Node3D) -> void:
	var o := _html(p)
	var a := atan2(o.y - tr.cy, o.x - tr.cx)
	var d: float = tr.r + 24.0
	riders.erase(p)
	_halt(p)
	_set_if(p, "on_tramp", false)
	_set_if(p, "dz", 0.0)
	p.global_position = GameData.world_to_3d(tr.cx + cos(a) * d, tr.cy + sin(a) * d, 0.0)
	_exceptions(p, false)

## trampLeap: off it through the air, the way (ux, uy) points (HTML ground axes).
func leap(p: Node3D, dir: Vector2) -> void:
	var l := dir.length()
	if l < 0.0001:
		dir = Vector2(0, 1)
		l = 1.0
	var tv: float = float(riders[p].tv) if riders.has(p) else 0.0
	riders.erase(p)
	fliers[p] = {"vx": dir.x / l * LEAP_SPEED, "vy": dir.y / l * LEAP_SPEED, "tv": maxf(tv, LEAP_UP), "acc": 0.0}
	_halt(p)
	_set_if(p, "on_tramp", false)
	_set_if(p, "frozen", true)               # mid-air: no steering (this moves him)
	_set_if(p, "moving", false)
	if "facing" in p:
		p.facing = dir / l

## Take him off without ceremony (he's gone, or something else is taking him somewhere).
func release(p: Node) -> void:
	var was_flying := fliers.has(p)
	riders.erase(p)
	fliers.erase(p)
	if is_instance_valid(p):
		_set_if(p, "on_tramp", false)
		_set_if(p, "dz", 0.0)
		if was_flying:
			_set_if(p, "frozen", false)
		_exceptions(p, false)

# ------------------------------------------------------------------ the bounce

func _input(event: InputEvent) -> void:
	# a tap of the roll button between two frames still counts for the next landing
	if riders.is_empty() or not event.is_action_pressed("roll"):
		return
	for p in riders:
		if is_instance_valid(p) and _controls(p):
			riders[p].tjump = true

func _physics_process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	for p in riders.keys():
		if not is_instance_valid(p) or not p.is_inside_tree():
			riders.erase(p)
			continue
		if "on_tramp" in p and not _flag(p, "on_tramp"):   # someone else took him off
			release(p)
			continue
		_bounce(p, dt)
	for p in fliers.keys():
		if not is_instance_valid(p) or not p.is_inside_tree():
			fliers.erase(p)
			continue
		_air(p, dt)

func _process(_delta: float) -> void:
	# after the Player has moved him this frame: the net (trampStep's first half)
	for p in riders.keys():
		if is_instance_valid(p) and riders.has(p):
			_net(p)

# trampStep: the net, then the bounce.
func _net(p: Node3D) -> void:
	var o := _html(p)
	var dx: float = o.x - tr.cx
	var dy: float = o.y - tr.cy
	var d := sqrt(dx * dx + dy * dy)
	if d < 0.0001:
		d = 1.0
	var mx: float = tr.r - NET_IN
	if d <= mx:
		return
	var vel: Vector2 = _get_or(p, "vel", Vector2.ZERO)
	var r = riders[p]
	if float(r.tz) > tr.net + 2.0 and (vel.x * dx + vel.y * dy) / d > 30.0:
		leap(p, Vector2(dx, dy))          # above it and still going: over you go
		return
	var y := p.global_position.y
	p.global_position = GameData.world_to_3d(tr.cx + dx / d * mx, tr.cy + dy / d * mx, 0.0)
	p.global_position.y = y
	var vn := (vel.x * dx + vel.y * dy) / d
	if vn > 0.0 and "vel" in p:
		p.vel = vel - Vector2(dx, dy) / d * vn

func _bounce(p: Node3D, dt: float) -> void:
	var r: Dictionary = riders[p]
	if _controls(p) and Input.is_action_pressed("roll"):
		r.tjump = true                   # the roll button is a bigger bounce
	r.acc += dt
	while r.acc >= FIXED_DT - 1e-9:
		r.acc -= FIXED_DT
		r.tv -= tr.g * FIXED_DT
		r.tz += r.tv * FIXED_DT
		if r.tz <= 0.0:                  # down on the mat: it throws you back up
			var hit: float = -r.tv
			r.tz = 0.0
			r.tv = minf(tr.vmax, hit + tr.boost) if r.tjump else maxf(tr.vbase, hit * tr.keep)
			r.tjump = false
			bounced.emit(p, hit, r.tv)
	var dz: float = tr.mat + r.tz
	_set_if(p, "dz", dz)
	p.global_position.y = dz * U

# airStep: sailing off it till he lands.
func _air(p: Node3D, dt: float) -> void:
	var f: Dictionary = fliers[p]
	var dz: float = float(_get_or(p, "dz", 0.0))
	if p is CharacterBody3D:
		var cb := p as CharacterBody3D
		# (move_and_slide moves by the physics step, which is dt unless the frame was very long)
		cb.velocity = Vector3(f.vx, 0.0, f.vy) * U * (dt / maxf(get_physics_process_delta_time(), 0.0001))
		cb.global_position.y = dz * U
		cb.move_and_slide()
		cb.velocity = Vector3.ZERO
	else:
		var o := _html(p)
		p.global_position = GameData.world_to_3d(o.x + f.vx * dt, o.y + f.vy * dt, dz)
	_set_if(p, "vel", Vector2.ZERO)
	f.acc += dt
	while f.acc >= FIXED_DT - 1e-9 and dz > 0.0:
		f.acc -= FIXED_DT
		f.tv -= tr.g * FIXED_DT
		dz += f.tv * FIXED_DT
	if dz <= 0.0:
		dz = 0.0
		fliers.erase(p)
		_push_out(p)                       # (not landed inside it)
		_set_if(p, "dz", 0.0)
		_set_if(p, "frozen", false)
		p.global_position.y = 0.0
		_exceptions(p, false)
		landed.emit(p)
		return
	_set_if(p, "dz", dz)
	p.global_position.y = dz * U

# Landed: not inside anything (airStep: pushOutOfSolid(p, T.radius * 0.5, b) for each of YARD_SOLIDS, the
# trampoline among them).
func _push_out(p: Node3D) -> void:
	var o := _html(p)
	var pos := Vector2(o.x, o.y)
	var r := _radius() * 0.5
	var solids = GameData.data.get("YARD_SOLIDS", [])
	if not (solids is Array) or solids.is_empty():
		solids = [{"cx": tr.cx, "cy": tr.cy, "r": tr.r}]
	for s in solids:
		if s is Dictionary:
			pos = push_out_of_solid(pos, r, s)
	p.global_position = GameData.world_to_3d(pos.x, pos.y, 0.0)

## pushOutOfSolid / pushOutOfBox: the point o pushed r clear of solid s (a box x0..y1, or round cx, cy, r).
static func push_out_of_solid(o: Vector2, r: float, s: Dictionary) -> Vector2:
	if s.has("r"):
		var dx: float = o.x - float(s.cx)
		var dy: float = o.y - float(s.cy)
		var d := sqrt(dx * dx + dy * dy)
		var m: float = float(s.r) + r
		if d >= m:
			return o
		if d < 0.001:
			return Vector2(float(s.cx), float(s.cy) + m)
		return Vector2(float(s.cx) + dx / d * m, float(s.cy) + dy / d * m)
	var x0: float = s.x0
	var y0: float = s.y0
	var x1: float = s.x1
	var y1: float = s.y1
	var cx := clampf(o.x, x0, x1)
	var cy := clampf(o.y, y0, y1)
	var ex := o.x - cx
	var ey := o.y - cy
	var dd := sqrt(ex * ex + ey * ey)
	if dd >= r:
		return o
	if dd > 0.001:
		return Vector2(cx + ex / dd * r, cy + ey / dd * r)
	var l := o.x - x0
	var rr := x1 - o.x
	var t := o.y - y0
	var bt := y1 - o.y
	var m2 := minf(minf(l, rr), minf(t, bt))
	if m2 == l:
		return Vector2(x0 - r, o.y)
	if m2 == rr:
		return Vector2(x1 + r, o.y)
	if m2 == t:
		return Vector2(o.x, y0 - r)
	return Vector2(o.x, y1 + r)

# ------------------------------------------------------------------ helpers

func _html(p: Node3D) -> Vector3:
	return GameData.from_3d(p.global_position)

func _out_dir(p: Node3D) -> Vector2:
	var o := _html(p)
	return Vector2(o.x - tr.cx, o.y - tr.cy)

static func _get_or(o: Object, k: String, def):
	var v = o.get(k)
	return def if v == null else v

# A true/false property of his, false if he hasn't got it.
static func _flag(o: Object, k: String) -> bool:
	var v = o.get(k)
	if v == null:
		return false
	return true if v else false

static func _set_if(o: Object, k: String, v) -> void:
	if k in o:
		o.set(k, v)

func _halt(p: Node) -> void:
	if p.has_method("halt"):
		p.halt()
	else:
		_set_if(p, "vel", Vector2.ZERO)
		if p is CharacterBody3D:
			(p as CharacterBody3D).velocity = Vector3.ZERO

func _controls(p: Node) -> bool:
	var c = p.get("controls_enabled")
	return c == null or (true if c else false)

func _radius() -> float:
	var t = GameData.data.get("T", {})
	return float(t.get("radius", R_DEFAULT)) if t is Dictionary else R_DEFAULT

# The trampoline's bodies (this one's, and the World's if it built one too): whoever's on it or flying off it
# passes through them (the net, not the cylinder, keeps him in).
func _bodies() -> Array:
	var out: Array = []
	if body:
		out.append(body)
	var w := get_tree().get_first_node_in_group("world_builder") if is_inside_tree() else null
	if w == null and is_inside_tree():
		for n in get_tree().root.find_children("*", "Node3D", true, false):
			var sc = n.get_script()
			if sc is Script and sc.get_global_name() == "WorldBuilder":
				w = n
				break
	if w:
		var tb = w.get("tramp_body")
		if tb is PhysicsBody3D and is_instance_valid(tb):
			out.append(tb)
	return out

func _exceptions(p: Node, on: bool) -> void:
	if not (p is PhysicsBody3D):
		return
	for b in _bodies():
		if on:
			(p as PhysicsBody3D).add_collision_exception_with(b)
		else:
			(p as PhysicsBody3D).remove_collision_exception_with(b)

# ------------------------------------------------------------------ the look (fpMaterial's 'tramp', the mat rows)

# A point round it: angle a, radius rr, height z (HTML units), in this node's space.
static func _pt(a: float, rr: float, z: float) -> Vector3:
	return Vector3(cos(a) * rr * U, z * U, sin(a) * rr * U)

# How lit a side facing (nx, ny) on the ground is (the sun's to the north), like the World's round solids.
static func _lit(nx: float, ny: float) -> float:
	return 0.7 + 0.3 * maxf(0.0, -ny * 0.9 + nx * 0.25)

static func _rep(u: float, n: float) -> float:
	return fposmod(u, n)

func _unshaded(tex: Texture2D, alpha: int, filter: int = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	if tex:
		m.albedo_texture = tex
		m.texture_filter = filter
	if alpha == 1:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	elif alpha == 2:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _mesh_node(n: String, st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

# An open cylinder band from z0 to z1 at radius rr: u runs round it (u_per_unit texture repeats a unit of
# circumference), v from 1 at z0 to 0 at z1 (times v_rep).
func _band(st: SurfaceTool, rr: float, z0: float, z1: float, u_per_unit: float, v_rep: float, lit: bool, segs: int = 96) -> void:
	var circ := TAU * rr
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var am := (a0 + a1) * 0.5
		var k := _lit(cos(am), sin(am)) if lit else 1.0
		var c := Color(k, k, k)
		var u0 := circ * i / segs * u_per_unit
		var u1 := circ * (i + 1) / segs * u_per_unit
		var p00 := _pt(a0, rr, z0)
		var p10 := _pt(a1, rr, z0)
		var p11 := _pt(a1, rr, z1)
		var p01 := _pt(a0, rr, z1)
		for q in [[p00, Vector2(u0, v_rep)], [p10, Vector2(u1, v_rep)], [p11, Vector2(u1, 0)],
				[p00, Vector2(u0, v_rep)], [p11, Vector2(u1, 0)], [p01, Vector2(u0, 0)]]:
			st.set_color(c)
			st.set_uv(q[1])
			st.add_vertex(q[0])

# An upright square post w wide at angle a, radius rr, from z0 to z1.
func _post(st: SurfaceTool, a: float, rr: float, w: float, z0: float, z1: float, col: Color) -> void:
	var cx := cos(a) * rr
	var cy := sin(a) * rr
	var h := w * 0.5
	var corners := [Vector2(cx - h, cy - h), Vector2(cx + h, cy - h), Vector2(cx + h, cy + h), Vector2(cx - h, cy + h)]
	var normals := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	for i in 4:
		var p0: Vector2 = corners[i]
		var p1: Vector2 = corners[(i + 1) % 4]
		var n: Vector2 = normals[i]
		var k := _lit(n.x, n.y)
		var c := Color(col.r * k, col.g * k, col.b * k)
		var v := [Vector3(p0.x * U, z0 * U, p0.y * U), Vector3(p1.x * U, z0 * U, p1.y * U),
			Vector3(p1.x * U, z1 * U, p1.y * U), Vector3(p0.x * U, z1 * U, p0.y * U)]
		for j in [0, 1, 2, 0, 2, 3]:
			st.set_color(c)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v[j])
	# its top
	var t := [Vector3(corners[0].x * U, z1 * U, corners[0].y * U), Vector3(corners[1].x * U, z1 * U, corners[1].y * U),
		Vector3(corners[2].x * U, z1 * U, corners[2].y * U), Vector3(corners[3].x * U, z1 * U, corners[3].y * U)]
	for j in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(t[j])

func _build() -> void:
	var R: float = tr.r
	var MAT: float = tr.mat
	var H: float = tr.mat + tr.net
	var circ := TAU * R

	# the mat, its springs and the padded ring over them, seen from above (the HTML game's mat rows)
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var wx := (x + 0.5) / n * 2.0 * R - R
			var wy := (y + 0.5) / n * 2.0 * R - R
			var rr := sqrt(wx * wx + wy * wy)
			var c := Color(0, 0, 0, 0)
			if rr < R - 18.0:
				var kk := 1.4 if (_rep(wx + wy, 14.0) < 1.0 or _rep(wx - wy, 14.0) < 1.0) else 1.0
				c = Color8(int(24 * kk), int(24 * kk), int(28 * kk))
			elif rr < R - 15.0:
				c = Color8(120, 124, 130)
			elif rr < R:
				var seam := 0.8 if _rep((atan2(wy, wx) + PI) * R, 26.0) < 1.2 else 1.0
				c = Color8(int(46 * seam), int(88 * seam), int(178 * seam))
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var top_tex := ImageTexture.create_from_image(img)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := [Vector3(-R * U, MAT * U, -R * U), Vector3(R * U, MAT * U, -R * U), Vector3(R * U, MAT * U, R * U), Vector3(-R * U, MAT * U, R * U)]
	var quv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for j in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color.WHITE)
		st.set_uv(quv[j])
		st.add_vertex(q[j])
	_mesh_node("Mat", st, _unshaded(top_tex, 1))

	# its side: the steel frame and its springs (22..26), the blue pad (26..mat), a texel a quarter unit
	var side := Image.create(12, int(4 * (MAT - 22.0)), false, Image.FORMAT_RGBA8)
	for y in side.get_height():
		var z := MAT - (y + 0.5) / 4.0
		for x in 12:
			var u := (x + 0.5) / 4.0
			var c: Color
			if z < 26.0:
				var k := 0.78 if _rep(u, 3.0) < 1.0 else 1.0
				c = Color8(int(132 * k), int(136 * k), int(142 * k))
			elif z > MAT - 1.2:
				c = Color8(80, 120, 208)
			else:
				c = Color8(44, 84, 172)
			side.set_pixel(x, y, c)
	side.generate_mipmaps()
	var side_mat := _unshaded(ImageTexture.create_from_image(side), 0)
	side_mat.texture_repeat = true
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band(st, R, 22.0, MAT, 1.0 / 3.0, 1.0, true)
	_mesh_node("Frame", st, side_mat)

	# legs (six round it, 5 wide, up to the frame), poles (eight, 3 wide, up to the net's top) and the rope
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		_post(st, TAU * (i + 0.5) / 6.0, R - 2.5, 5.0, 0.0, 22.0, Color8(50, 52, 56))
	for i in 8:
		_post(st, TAU * i / 8.0, R + 0.5, 3.0, 22.0, H, Color8(58, 60, 66))
	_mesh_node("Posts", st, _unshaded(null, 0))
	var rope := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	rope.set_pixel(0, 0, Color8(58, 60, 66))
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band(st, R + 0.2, H - 2.5, H, 0.0, 1.0, true)
	_mesh_node("Rope", st, _unshaded(ImageTexture.create_from_image(rope), 0))

	# the net: dark, see-through, its strands every 4 units (one tile of 4 x 4 units, 8 texels a unit)
	var net := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var on := (x + 0.5) / 8.0 < 0.7 or (y + 0.5) / 8.0 < 0.7
			net.set_pixel(x, y, Color8(12, 12, 16, int(255 * (0.42 if on else 0.1))))
	net.generate_mipmaps()
	var net_mat := _unshaded(ImageTexture.create_from_image(net), 2, BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	net_mat.texture_repeat = true
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band(st, R, MAT, H - 2.5, 0.25, (H - 2.5 - MAT) / 4.0, false, 128)
	_mesh_node("Net", st, net_mat)

	# its shadow on the grass (the HTML game's floor darkens to 0.55 under it)
	var sh := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x + 0.5 - 32, y + 0.5 - 32).length() / 32.0
			sh.set_pixel(x, y, Color(0, 0, 0, 0.4 * clampf((1.0 - d) * 6.0, 0.0, 1.0)))
	sh.generate_mipmaps()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := 0.35
	q = [Vector3(-R * U, z0 * U, -R * U), Vector3(R * U, z0 * U, -R * U), Vector3(R * U, z0 * U, R * U), Vector3(-R * U, z0 * U, R * U)]
	for j in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color.WHITE)
		st.set_uv(quv[j])
		st.add_vertex(q[j])
	var shm := _unshaded(ImageTexture.create_from_image(sh), 2, BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	shm.render_priority = -1
	_mesh_node("Shadow", st, shm)

	if build_body:
		body = StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(1.0, R - _radius() * 0.5) * U      # he stops half his radius into it, like the HTML game
		cyl.height = H * U
		cs.shape = cyl
		cs.position = Vector3(0, H * 0.5 * U, 0)
		body.add_child(cs)
		add_child(body)
