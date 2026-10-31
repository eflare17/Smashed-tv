# (Copied from stkilda-godot scripts/town/crowd.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkCrowd
extends Node3D
## SkPeople about the place, so it doesn't feel empty: walking round Luna Park between the rides (keeping out from under
## the moving ones and off anything solid), standing in little queues by the rides, walking up and down the
## footpaths of Acland St, Fitzroy St and The Esplanade, and riding in the Scenic Railway's cars. They're simple blocky
## townsfolk (legs, a body, arms, a head with hair, in the chunky style of the rest), one shape for everyone, each
## in their own colours (shirt, pants, hair, skin: picked in the shader from what each one carries), their legs and
## arms swinging as they walk (the shader too): so the whole crowd is one batch, cheap enough for phones. They're not
## solid, and nobody minds you. Random, but the same crowd every time.

const PARK_WALKERS := 50
const QUEUE := 3                          # people standing by each ride
const STREETS := ["Acland Street", "Fitzroy Street", "The Esplanade"]
const STREET_EVERY := 28.0               # m of footpath per person
const SWINGS := {"Carousel": 8.5, "Spider": 10.0, "PowerSurge": 9.0, "ArabianMerry": 7.0, "PharaohsCurse": 11.0,
	"Supernova": 9.5, "ConeyDrop": 4.5, "MoonBalloons": 4.5}

var town: SkTownBuilder
var _mm: MultiMesh
var _people: Array = []                  # each: {at: Vector3, to: Vector3, speed, wait, mode, path, s, dir, yaw, i}
var _wall := PackedVector2Array()
var _swings: Array = []                  # [centre (x, z), radius]
var _rng := RandomNumberGenerator.new()
var _space: PhysicsDirectSpaceState3D
var _probe: PhysicsShapeQueryParameters3D
## Set up (the park's wall read, the space to ask about open spots): the ibises wait for it.
var ready_ := false

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial

func setup(t: SkTownBuilder) -> void:
	town = t

func _ready() -> void:
	_rng.seed = 2026
	await get_tree().physics_frame
	await get_tree().physics_frame
	_space = get_world_3d().direct_space_state
	_probe = PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.6
	_probe.shape = cap
	_probe.collision_mask = SkData.LAYER_WORLD
	var main := get_parent()
	for nm in SWINGS:
		var ride := main.get_node_or_null(nm) as Node3D
		if ride:
			_swings.append([Vector2(ride.global_position.x, ride.global_position.z), float(SWINGS[nm])])
	var park = JSON.parse_string(FileAccess.get_file_as_string("res://data/stkilda/luna.json"))
	if park != null:
		for e in park.elements:
			if e.type == "way" and int(e.id) == SkLunaPark.WALL_WAY:
				for g in e.geometry:
					_wall.append(town.project(g.lat, g.lon))
	var list := []
	# wandering round the park
	if _wall.size() > 3:
		for k in PARK_WALKERS:
			var at := _open_spot_anywhere()
			if at != Vector3.INF:
				list.append({"mode": "park", "at": at, "to": at, "speed": _rng.randf_range(1.0, 1.5), "wait": _rng.randf() * 3.0})
	# little queues by the rides
	var spots: Dictionary = main.get_meta("luna_spots", {})
	for name in spots:
		var s: Array = spots[name]
		var at: Vector3 = s[0]
		var look: Vector3 = s[1] if s.size() > 1 and s[1] is Vector3 else at + Vector3(0, 0, -1)
		var d := look - at
		d.y = 0.0
		if d.length() < 0.1:
			continue
		d = d.normalized()
		var side := Vector3(-d.z, 0, d.x)
		for k in QUEUE:
			var p := at + side * 2.2 - d * (k * 0.9)
			if _open(p):
				list.append({"mode": "stand", "at": p, "yaw": atan2(-d.x, -d.z) + _rng.randf_range(-0.3, 0.3)})
	# up and down the footpaths
	for r in town.data.roads:
		if not (r.n in STREETS):
			continue
		for side in [-1.0, 1.0]:
			var path := SkTownBuilder._offset(SkTownBuilder._pts(r.p), side * (float(r.w) / 2.0 + SkTownBuilder.PATH_W / 2.0))
			var len := 0.0
			for i in path.size() - 1:
				len += path[i].distance_to(path[i + 1])
			for k in int(len / STREET_EVERY):
				list.append({"mode": "street", "path": path, "len": len, "s": _rng.randf() * len, "dir": 1.0 if _rng.randf() < 0.5 else -1.0,
					"speed": _rng.randf_range(1.0, 1.5), "off": _rng.randf_range(-0.8, 0.8)})
	_people = list
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = person_mesh()
	_mm.instance_count = list.size()
	for i in list.size():
		var p: Dictionary = list[i]
		p.i = i
		p.shirt = _rng.randi() % 8
		# custom: walking (0.5 or not) plus the shirt (sixteenths), the step's phase, pants and hair (indexes into the shader's lists), skin
		_mm.set_instance_custom_data(i, Color(float(p.shirt) / 16.0, _rng.randf() * TAU, float(_rng.randi() % 6) / 8.0 + float(_rng.randi() % 5) / 64.0, _rng.randf()))
		if not p.has("yaw"):
			p.yaw = _rng.randf() * TAU
		p.h = _rng.randf_range(0.92, 1.08)
		if p.mode == "street":
			p.at = Vector3.ZERO
			_walk_street(p, 0.0)
		_place(p)
	_buf = _mm.buffer
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "People"
	mmi.multimesh = _mm
	mmi.material_override = material()
	add_child(mmi)
	_riders(main)
	ready_ = true

func _process(dt: float) -> void:
	if _mm == null:
		return
	var bumper := _bumper()
	for p in _people:
		if p.has("rag"):
			continue                          # (flying about as a ragdoll)
		if p.has("fall"):
			_falling(p, dt)
			continue
		if not bumper.is_empty() and _bumped(p, bumper):
			continue
		match p.mode:
			"park":
				_walk_park(p, dt)
			"street":
				_walk_street(p, dt)
		_place(p)
	if _dirty:
		_mm.buffer = _buf
		_dirty = false

# ---------------------------------------------------------------- bumping into them (the owner: they fall over)

const FALL_T := 0.45                     # s to topple
const DOWN_T := 3.5                      # s lying there
const UP_T := 0.9                        # s getting back up

## Who might knock someone over just now: the car you're driving (moving), or you on foot (walking). Empty if neither.
func _bumper() -> Dictionary:
	var main := get_parent()
	if main.ride_train != null or main.fly.active:
		return {}
	if main.driving:
		var car: SkCar = main.car
		if absf(car.speed) < 1.0:
			return {}
		return {"car": true, "xf": car.global_transform, "v": car.velocity, "speed": absf(car.speed)}
	var w: SkWalker = main.walker
	var v := Vector3(w.velocity.x, 0, w.velocity.z)
	if v.length() < 0.6:
		return {}
	return {"car": false, "at": w.global_position, "v": v, "speed": v.length()}

## Whether `p` has just been knocked: if so they start to fall, pushed the way the knock went.
func _bumped(p: Dictionary, b: Dictionary) -> bool:
	var push := Vector3.ZERO
	var slide := 0.3
	if b.car:
		var local: Vector3 = (b.xf as Transform3D).affine_inverse() * (p.at as Vector3)
		if absf(local.x) > 1.4 or absf(local.z) > 3.1 or local.y > 2.0:
			return false
		push = (b.v as Vector3).normalized() + (b.xf as Transform3D).basis.x * signf(local.x) * 0.5
		slide = clampf(float(b.speed) * 0.3, 0.8, 5.0)
	else:
		var d: Vector3 = (p.at as Vector3) - (b.at as Vector3)
		d.y = 0.0
		if d.length() > 0.65:
			return false
		push = (b.v as Vector3).normalized() * 0.7 + d.normalized() * 0.3
	push.y = 0.0
	if push.length() < 0.01:
		push = Vector3.FORWARD
	_walking(p, false)
	if not b.car:
		var w: SkWalker = get_parent().walker
		w.shove()                        # (your arms out: a proper shove)
	# knocked flying: a ragdoll in their place till they've landed (a few at a time; past that they just topple)
	if _ragdolls < MAX_RAGDOLLS:
		var c := _custom(p.i)
		var look := [p.shirt, int(floor(c.b * 8.0)), int(floor(fposmod(c.b * 8.0, 1.0) * 8.0 + 0.01)), c.a]
		var r := SkRagdoll.new()
		r.name = "SkRagdoll"
		add_child(r)
		var speed: float = b.speed
		if b.car:
			r.setup(_xf(p), look, push.normalized() * speed * 0.9, 2.5 + speed * 0.25, 5.0 + speed * 0.3)
		else:
			r.setup(_xf(p), look, push.normalized() * 4.6, 2.4, 7.5)
		r.done.connect(_landed.bind(p))
		_ragdolls += 1
		p.rag = true
		_put(p.i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), p.at))
		return true
	p.fall = 0.0
	p.push = push.normalized()
	p.slide = slide
	return true

const MAX_RAGDOLLS := 8
var _ragdolls := 0

func _xf(p: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, p.yaw).scaled(Vector3.ONE * p.h), p.at)

## A ragdoll's landed: back as one of the crowd, lying where it came down (head the way it points), about to get up.
func _landed(at: Vector3, head_dir: Vector3, p: Dictionary) -> void:
	_ragdolls -= 1
	p.erase("rag")
	p.at = at - head_dir * 1.1                        # (their feet: the ragdoll says where their middle is)
	p.push = head_dir
	p.yaw = atan2(head_dir.x, head_dir.z)            # (feet towards where they came from)
	p.fall = FALL_T + DOWN_T - 0.6
	p.slide = 0.0

## Falling over, lying there, getting back up, then on their way again.
func _falling(p: Dictionary, dt: float) -> void:
	p.fall += dt
	var t: float = p.fall
	var tip := 0.0
	if t < FALL_T:
		var k := t / FALL_T
		tip = k * k
		p.at += (p.push as Vector3) * float(p.slide) * dt / FALL_T * (1.0 - k)
	elif t < FALL_T + DOWN_T:
		tip = 1.0
	elif t < FALL_T + DOWN_T + UP_T:
		tip = 1.0 - smoothstep(0.0, 1.0, (t - FALL_T - DOWN_T) / UP_T)
	else:
		p.erase("fall")
		if p.mode == "park":
			p.to = p.at
			p.wait = 0.5
		elif p.mode == "street":
			_street_from(p)
		_place(p)
		return
	var axis: Vector3 = Vector3.UP.cross(p.push).normalized()
	var basis := Basis(axis, tip * PI * 0.5) * Basis(Vector3.UP, p.yaw)
	_put(p.i, Transform3D(basis.scaled(Vector3.ONE * p.h), (p.at as Vector3) + Vector3(0, 0.13 * tip, 0)))

## Back on the footpath after a fall: carry on from the nearest point along it.
func _street_from(p: Dictionary) -> void:
	var path: PackedVector2Array = p.path
	var q := Vector2((p.at as Vector3).x, (p.at as Vector3).z)
	var best := INF
	var s := 0.0
	var walked := 0.0
	for i in path.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(q, path[i], path[i + 1])
		if c.distance_to(q) < best:
			best = c.distance_to(q)
			s = walked + path[i].distance_to(c)
		walked += path[i].distance_to(path[i + 1])
	p.s = s

func _walk_park(p: Dictionary, dt: float) -> void:
	if p.wait > 0.0:
		p.wait -= dt
		_walking(p, false)
		if p.wait <= 0.0:
			p.to = _next_spot(p.at)
		return
	var to: Vector3 = p.to - p.at
	to.y = 0.0
	if to.length() < 0.4:
		p.wait = _rng.randf_range(0.5, 4.0)            # (a look round before going on)
		return
	var step: Vector3 = to.normalized() * p.speed * dt
	p.at += step if step.length() < to.length() else to
	p.yaw = lerp_angle(p.yaw, atan2(-to.x, -to.z), minf(1.0, dt * 6.0))
	_walking(p, true)

func _walk_street(p: Dictionary, dt: float) -> void:
	p.s += p.dir * p.speed * dt
	if p.s < 0.0 or p.s > p.len:
		p.dir = -p.dir
		p.s = clampf(p.s, 0.0, p.len)
	var path: PackedVector2Array = p.path
	var left: float = p.s
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if left <= seg or i == path.size() - 2:
			var a := path[i]
			var b := path[i + 1]
			var d := (b - a).normalized()
			var q: Vector2 = a.lerp(b, clampf(left / maxf(seg, 0.01), 0.0, 1.0)) + Vector2(-d.y, d.x) * float(p.off)
			p.at = Vector3(q.x, 0, q.y)
			var go: Vector2 = d * float(p.dir)
			p.yaw = atan2(-go.x, -go.y)
			break
		left -= seg
	_walking(p, true)

func _walking(p: Dictionary, on: bool) -> void:
	var c := _custom(p.i)
	if (c.r >= 0.5) != on:
		c.r = (0.5 if on else 0.0) + float(p.shirt) / 16.0
		_set_custom(p.i, c)

func _place(p: Dictionary) -> void:
	_put(p.i, Transform3D(Basis(Vector3.UP, p.yaw).scaled(Vector3.ONE * p.h), p.at))

# Godot 4.4's compatibility renderer loses a batch's custom data (who's wearing what) when one copy's transform is set
# after it's first drawn (they all came out in red, arms up), so the crowd's whole batch is written in one go, once a
# frame: each copy 20 floats (its transform's three rows, its colour, its custom data).
var _buf := PackedFloat32Array()
var _dirty := false

func _put(i: int, xf: Transform3D) -> void:
	if _buf.is_empty():
		_mm.set_instance_transform(i, xf)
		return
	put(_buf, i, xf)
	_dirty = true

func _custom(i: int) -> Color:
	if _buf.is_empty():
		return _mm.get_instance_custom_data(i)
	return Color(_buf[i * 20 + 16], _buf[i * 20 + 17], _buf[i * 20 + 18], _buf[i * 20 + 19])

func _set_custom(i: int, c: Color) -> void:
	if _buf.is_empty():
		_mm.set_instance_custom_data(i, c)
		return
	for k in 4:
		_buf[i * 20 + 16 + k] = c[k]
	_dirty = true

## Write copy `i`'s transform into a batch's buffer (`stride` floats a copy: 20 with colours and custom data).
static func put(buf: PackedFloat32Array, i: int, xf: Transform3D, stride := 20) -> void:
	var o := i * stride
	for r in 3:
		buf[o + r * 4] = xf.basis.x[r]
		buf[o + r * 4 + 1] = xf.basis.y[r]
		buf[o + r * 4 + 2] = xf.basis.z[r]
		buf[o + r * 4 + 3] = xf.origin[r]

## Somewhere open to walk to, within 30 m, that you can walk straight to (or stay put).
func _next_spot(from: Vector3) -> Vector3:
	for k in 12:
		var p := from + Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(-30, 30))
		if not _open(p):
			continue
		var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0), SkData.LAYER_WORLD)
		if _space.intersect_ray(q).is_empty():
			return p
	return from

func _open_spot_anywhere() -> Vector3:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for v in _wall:
		lo = lo.min(v)
		hi = hi.max(v)
	for k in 40:
		var p := Vector3(_rng.randf_range(lo.x, hi.x), 0, _rng.randf_range(lo.y, hi.y))
		if _open(p):
			return p
	return Vector3.INF

## Inside the park's wall, clear of the moving rides and of anything solid.
func _open(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	if _wall.size() > 3 and not Geometry2D.is_point_in_polygon(q, _wall):
		return false
	for s in _swings:
		if (s[0] as Vector2).distance_to(q) < float(s[1]):
			return false
	_probe.transform = Transform3D(Basis(), p + Vector3(0, 1.1, 0))
	return _space.intersect_shape(_probe, 1).is_empty()

## SkPeople sitting in the Scenic Railway's cars (not the front seat: that's yours), riding round with them.
func _riders(main: Node) -> void:
	var rail := main.get_node_or_null("SkScenicRailway")
	if rail == null:
		return
	for t in rail.get_children():
		if not (t is SkScenicRailway.Train):
			continue
		var first := true
		for car in t.get_children():
			if not (car is Node3D) or car is Camera3D:
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = person_mesh()
			var seats := []
			for row in range(2 if first else 0, 5):           # (the front car: not right behind you in the front seat)
				for x in [-0.4, 0.4]:
					if _rng.randf() < 0.55:
						seats.append(Vector3(x, -0.08, -1.35 + row * 0.62))
			mm.instance_count = seats.size()
			for k in seats.size():
				mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * 0.95), seats[k]))

				mm.set_instance_custom_data(k, Color(float(_rng.randi() % 8) / 16.0, 0.0, float(_rng.randi() % 6) / 8.0 + float(_rng.randi() % 5) / 64.0, _rng.randf()))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Riders"
			mmi.multimesh = mm
			mmi.material_override = material()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(car as Node3D).add_child(mmi)
			first = false

# ---------------------------------------------------------------- the shape and its material

## A townsperson, 1.8 m: each part's kind in its UV's x (0 skin, 1 shirt, 2 pants, 3 hair, 4 shoes), for the
## shader to colour. Facing -z, feet at y = 0.
static func person_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-0.1, 0.1]:
		_box(st, Vector3(x, 0.47, 0), Vector3(0.16, 0.78, 0.18), 2)        # legs
		_box(st, Vector3(x, 0.04, -0.03), Vector3(0.17, 0.08, 0.26), 4)    # shoes
	_box(st, Vector3(0, 1.15, 0), Vector3(0.42, 0.62, 0.24), 1)            # body
	for x in [-0.28, 0.28]:
		_box(st, Vector3(x, 1.33, 0), Vector3(0.13, 0.24, 0.15), 1)        # sleeves
		_box(st, Vector3(x, 1.0, 0), Vector3(0.11, 0.42, 0.12), 0)         # arms
	_box(st, Vector3(0, 1.5, 0), Vector3(0.12, 0.08, 0.12), 0)             # neck
	_box(st, Vector3(0, 1.64, 0), Vector3(0.26, 0.26, 0.26), 0)            # head
	_box(st, Vector3(0, 1.79, 0.02), Vector3(0.28, 0.06, 0.28), 3)         # hair
	_box(st, Vector3(0, 1.66, 0.13), Vector3(0.28, 0.24, 0.04), 3)
	_mesh = st.commit()
	return _mesh

static func _box(st: SurfaceTool, c: Vector3, s: Vector3, part: int) -> void:
	var h := s / 2.0
	var tag := Vector2(float(part) / 8.0, 0)
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n * h
		var uu := u * h
		var vv := v * h
		var corners := [o - uu - vv, o + uu - vv, o + uu + vv, o - uu + vv]
		for t in [[0, 1, 2], [0, 2, 3]]:
			var a: Vector3 = corners[t[0]]
			var b: Vector3 = corners[t[1]]
			var d: Vector3 = corners[t[2]]
			var order: Array = [a, b, d] if (b - a).cross(d - a).dot(n) < 0.0 else [a, d, b]
			for p in order:
				st.set_normal(n)
				st.set_color(Color.WHITE)
				st.set_uv(tag)
				st.add_vertex(p)

static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_back;
varying vec3 tint;
uniform float legs = 0.0;             // (riders) 0: legs hanging down; 1: straight out in front, sat down
uniform float hold = 0.0;             // (riders) arms out in front, holding on
uniform float cheer = 0.0;            // (riders) how many of them have their arms up in the air, waving (0..1)
const vec3 PANTS[6] = vec3[6](vec3(0.11, 0.14, 0.24), vec3(0.06, 0.06, 0.07), vec3(0.45, 0.4, 0.3), vec3(0.3, 0.33, 0.38), vec3(0.24, 0.3, 0.45), vec3(0.55, 0.52, 0.48));
const vec3 HAIR[5] = vec3[5](vec3(0.06, 0.04, 0.03), vec3(0.22, 0.12, 0.06), vec3(0.65, 0.5, 0.25), vec3(0.45, 0.18, 0.06), vec3(0.6, 0.6, 0.58));
const vec3 SHIRTS[8] = vec3[8](vec3(0.78, 0.19, 0.17), vec3(0.18, 0.37, 0.7), vec3(0.95, 0.94, 0.92), vec3(0.11, 0.12, 0.13), vec3(0.88, 0.69, 0.16), vec3(0.25, 0.54, 0.29), vec3(0.88, 0.48, 0.66), vec3(0.42, 0.31, 0.64));
const vec3 SKIN_LIGHT = vec3(0.78, 0.55, 0.42);
const vec3 SKIN_DARK = vec3(0.32, 0.2, 0.13);
void vertex() {
	float part = floor(UV.x * 8.0 + 0.5);
	vec4 c = INSTANCE_CUSTOM;
	float walk = step(0.5, c.r);
	int shirt = int(floor((c.r - walk * 0.5) * 16.0 + 0.01));
	float s = sin(TIME * 6.5 + c.g) * 0.5 * walk;
	// the legs swing from the hips, the arms (the other way) from the shoulders, and the body bobs (riders: sat or
	// astride, holding on, some with their arms right up, waving)
	float up = step(fract(c.g * 7.13), cheer - 0.001);
	if (part == 2.0 || part == 4.0) {
		float a = (VERTEX.x < 0.0 ? s : -s) - legs * 1.5;
		float y = VERTEX.y - 0.88;
		float z = VERTEX.z;
		VERTEX.z = z * cos(a) - y * sin(a);
		VERTEX.y = 0.88 + z * sin(a) + y * cos(a);
	} else if (abs(VERTEX.x) > 0.22 && VERTEX.y < 1.46) {
		float a = (VERTEX.x < 0.0 ? -s : s) * 0.8 - hold * 1.2;
		a = mix(a, -2.85 - sin(TIME * 5.0 + c.g * 3.0) * 0.2, up);
		float y = VERTEX.y - 1.42;
		float z = VERTEX.z;
		VERTEX.z = z * cos(a) - y * sin(a);
		VERTEX.y = 1.42 + z * sin(a) + y * cos(a);
		if (up > 0.5) {
			// (out in a V)
			float b = VERTEX.x < 0.0 ? 0.35 : -0.35;
			float sx = VERTEX.x < 0.0 ? -0.28 : 0.28;
			float dx = VERTEX.x - sx;
			float dy = VERTEX.y - 1.42;
			VERTEX.x = sx + dx * cos(b) - dy * sin(b);
			VERTEX.y = 1.42 + dx * sin(b) + dy * cos(b);
		}
	}
	VERTEX.y += abs(cos(TIME * 6.5 + c.g)) * 0.03 * walk;
	int pants = int(floor(c.b * 8.0));
	int hair = int(floor(fract(c.b * 8.0) * 8.0 + 0.01));
	vec3 skin = mix(SKIN_LIGHT, SKIN_DARK, c.a * c.a);
	tint = skin;
	if (part == 1.0) { tint = SHIRTS[clamp(shirt, 0, 7)]; }
	if (part == 2.0) { tint = PANTS[clamp(pants, 0, 5)]; }
	if (part == 3.0) { tint = HAIR[clamp(hair, 0, 4)]; }
	if (part == 4.0) { tint = vec3(0.05, 0.05, 0.06); }
}
void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.85;
}
"""
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat

## Somewhere open in the park within `r` m of `from` that's straight there (or not, if not `straight`), or `from`: for
## the ibises (with their own dice, so the crowd stays the same every time).
func next_spot_near(from: Vector3, r: float, rng: RandomNumberGenerator, straight := true) -> Vector3:
	for k in 12:
		var p := from + Vector3(rng.randf_range(-r, r), 0, rng.randf_range(-r, r))
		if not _open(p):
			continue
		if not straight:
			return p
		var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.5, 0), p + Vector3(0, 0.5, 0), SkData.LAYER_WORLD)
		if _space.intersect_ray(q).is_empty():
			return p
	return from
