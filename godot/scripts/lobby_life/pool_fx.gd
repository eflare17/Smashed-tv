class_name LobbyPoolFx
extends Node3D
## The pool's looks and small life, for LobbyPool (pool.gd): the water that wobbles and glints and carries rings
## (drawPoolWater), the white-water splashes (waterSplash / drawSplashes), the spark bursts (fx / burst), the three
## rubber ducks (stepDucks / drawDucks), and the drops that run off a swimmer who has climbed out (drawDrips).
## All numbers are the HTML game's (Smashed.html), in its units: arena pixels, x across, y down the screen, z up.
## Owned by the Lobby life session.
##
## The water is the World's own PoolWater mesh (the lounge picture on it); this swaps its material for one that
## redraws the picture in 2 px bands shifted sideways, adds a sheen, and draws the rings, the splash foam and a
## few ellipses (the swimmers', the ducks' waterlines) in the shader, in arena pixels. The flying drops, sparks and
## drips are billboard quads in one MultiMesh, the wet spots on the tiles flat quads in another.

const WATER_Z := -3.0                 # the water sits this far under the floor (WorldBuilder._pool depth)
const MAX_RIP := 32
const MAX_ELL := 8
const MAX_FOAM := 4
const BITS_CAP := 900
const SPOTS_CAP := 110

var pool: Node                        # the LobbyPool (for the height factor and the swimmers)
var water: MeshInstance3D
var mat: ShaderMaterial
var clock: float = 0.0

## Water rings: {x, y, t, life, grow, w} (t < 0 waits to start).
var ripples: Array = []
## White-water splashes: {x, y, size, t, drops: [{x, y, z, vx, vy, vz, r}]}.
var foams: Array = []
## Sparks: {x, y, z, vx, vy, t, life, col}.
var sparks: Array = []
## The ducks: {look, x, y, vx, vy, head, flip, ph, wob, pic: LobbyPic}.
var ducks: Array = []
## Who is swimming now, for the ducks: [{x, y, vx, vy}]; set by the pool each frame.
var swimmers: Array = []
## Ellipses to draw on the water this frame: key -> {x, y, rx, ry, col, lw, fill, frame}.
var ells: Dictionary = {}

# the drips
var _was: Dictionary = {}
var _wet: Dictionary = {}
var _ents: Dictionary = {}
var _drops: Array = []
var _runs: Array = []
var _dbits: Array = []
var _spots: Array = []

var _bits: MultiMeshInstance3D
var _spotmm: MultiMeshInstance3D
var _list: Array = []                 # this frame's billboard quads: [pos, size, colour]

const POOL := {"x0": 624.0, "y0": 90.0, "x1": 815.0, "y1": 239.0}
const DUCK_LOOKS := [["yellow", 0.25, 0.3, false], ["yellow", 0.72, 0.62, true], ["black", 0.45, 0.78, false]]
const DRIP_POINTS := [[0, -0.74], [-0.08, -0.84], [0.08, -0.84], [-0.23, -0.6], [0.23, -0.6],
	[-0.33, -0.56], [0.33, -0.56], [-0.16, -0.25], [0.16, -0.25], [0, -0.27]]
const DRIP_TIME := 3.0

func _ready() -> void:
	_make_water()
	_make_quads()
	_make_ducks()

## The pool picture on the pool water, with the wobble.
func _make_water() -> void:
	var w = null
	if pool and pool.get("ll") and pool.ll.world:
		w = pool.ll.world.get("pool_water")
	if not (w is MeshInstance3D):
		return
	water = w
	var tex: Texture2D = null
	var old = water.material_override
	if old is StandardMaterial3D:
		tex = old.albedo_texture
	if tex == null:
		return
	mat = ShaderMaterial.new()
	mat.shader = _water_shader()
	mat.set_shader_parameter("tex", tex)
	water.material_override = mat

func _make_quads() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm.instance_count = BITS_CAP
	mm.visible_instance_count = 0
	_bits = MultiMeshInstance3D.new()
	_bits.name = "Bits"
	_bits.multimesh = mm
	_bits.material_override = m
	_bits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bits.extra_cull_margin = 50.0
	add_child(_bits)
	var q2 := QuadMesh.new()
	q2.size = Vector2(1, 1)
	q2.orientation = PlaneMesh.FACE_Y
	var m2 := StandardMaterial3D.new()
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m2.vertex_color_use_as_albedo = true
	m2.albedo_texture = _dot_tex()
	m2.cull_mode = BaseMaterial3D.CULL_DISABLED
	m2.no_depth_test = false
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.use_colors = true
	mm2.mesh = q2
	mm2.instance_count = SPOTS_CAP
	mm2.visible_instance_count = 0
	_spotmm = MultiMeshInstance3D.new()
	_spotmm.name = "Spots"
	_spotmm.multimesh = mm2
	_spotmm.material_override = m2
	_spotmm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spotmm.extra_cull_margin = 50.0
	add_child(_spotmm)

static var _dot: Texture2D
static func _dot_tex() -> Texture2D:
	if _dot:
		return _dot
	var im := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			im.set_pixel(x, y, Color(1, 1, 1, 1.0 if d <= 1.0 else 0.0))
	_dot = ImageTexture.create_from_image(im)
	return _dot

# ------------------------------------------------------------------ the ducks

func _make_ducks() -> void:
	var b := duck_bounds()
	for i in DUCK_LOOKS.size():
		var l: Array = DUCK_LOOKS[i]
		var pic := LobbyPic.new()
		pic.name = "Duck%d" % i
		pic.texture = _duck_tex(l[0])
		pic.units_per_px = 1.0
		pic.foot_px = 4.0                     # the bottom four rows are under the water
		add_child(pic)
		ducks.append({"look": l[0], "x": b.position.x + b.size.x * float(l[1]), "y": b.position.y + b.size.y * float(l[2]),
			"vx": 0.0, "vy": 0.0, "head": randf() * TAU, "flip": l[3], "ph": randf() * 6.28, "wob": 0.0, "pic": pic})

## The duck picture with the water's blue washed over its bottom four rows (drawDucks' fillRect).
static func _duck_tex(look: String) -> Texture2D:
	var t := LobbyPic.art("pool/duck_%s.png" % look)
	if t == null:
		return null
	var im := t.get_image()
	if im == null or im.is_empty():
		return t
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var wl := im.get_height() - 4
	var wc := Color(40 / 255.0, 140 / 255.0, 210 / 255.0)
	for y in range(wl, im.get_height()):
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			if c.a > 0.5:
				im.set_pixel(x, y, c.lerp(wc, 0.55))
	return ImageTexture.create_from_image(im)

static func duck_bounds() -> Rect2:
	return Rect2(POOL.x0 + 16, POOL.y0 + 18, (POOL.x1 - 16) - (POOL.x0 + 16), (POOL.y1 - 10) - (POOL.y0 + 18))

## duckSplash: a splash at (x, y) shoves the ducks near it.
func shove_ducks(x: float, y: float, power: float) -> void:
	for d in ducks:
		var dx: float = d.x - x
		var dy: float = d.y - y
		var r := sqrt(dx * dx + dy * dy)
		if r > 70.0:
			continue
		var m := 60.0 * (1.0 - r / 70.0) * power
		var a := atan2(dy, dx) if r > 1.0 else randf() * TAU
		d.vx += cos(a) * m
		d.vy += sin(a) * m
		d.wob = 1.0

func _step_ducks(dt: float) -> void:
	var b := duck_bounds()
	for d in ducks:
		d.head += (randf() - 0.5) * dt * 1.6
		d.vx += cos(d.head) * 4.0 * dt
		d.vy += sin(d.head) * 4.0 * dt
		var damp := maxf(0.0, 1.0 - dt * 0.9)
		d.vx *= damp
		d.vy *= damp
		for s in swimmers:
			var dx: float = d.x - s.x
			var dy: float = d.y - s.y
			var r := sqrt(dx * dx + dy * dy)
			if r < 0.01:
				r = 0.01
			if r < 20.0:
				d.vx += dx / r * 90.0 * dt + float(s.vx) * 0.8 * dt
				d.vy += dy / r * 90.0 * dt + float(s.vy) * 0.8 * dt
				d.wob = maxf(d.wob, 0.6)
	for i in ducks.size():
		for j in range(i + 1, ducks.size()):
			var a: Dictionary = ducks[i]
			var c: Dictionary = ducks[j]
			var dx: float = c.x - a.x
			var dy: float = c.y - a.y
			var r := sqrt(dx * dx + dy * dy)
			if r < 0.01:
				r = 0.01
			if r < 17.0:
				var nx := dx / r
				var ny := dy / r
				var push := (17.0 - r) / 2.0
				a.x -= nx * push
				a.y -= ny * push
				c.x += nx * push
				c.y += ny * push
				var rel: float = (c.vx - a.vx) * nx + (c.vy - a.vy) * ny
				if rel < 0.0:
					a.vx += nx * rel
					a.vy += ny * rel
					c.vx -= nx * rel
					c.vy -= ny * rel
				a.wob = maxf(a.wob, 0.4)
				c.wob = maxf(c.wob, 0.4)
	for d in ducks:
		d.x += d.vx * dt
		d.y += d.vy * dt
		if d.x < b.position.x:
			d.x = b.position.x
			d.vx = absf(d.vx) * 0.6
			d.head = PI - d.head
		elif d.x > b.end.x:
			d.x = b.end.x
			d.vx = -absf(d.vx) * 0.6
			d.head = PI - d.head
		if d.y < b.position.y:
			d.y = b.position.y
			d.vy = absf(d.vy) * 0.6
			d.head = -d.head
		elif d.y > b.end.y:
			d.y = b.end.y
			d.vy = -absf(d.vy) * 0.6
			d.head = -d.head
		if d.vx > 1.5:
			d.flip = false
		elif d.vx < -1.5:
			d.flip = true
		d.ph += dt * 2.2
		d.wob = maxf(0.0, d.wob - dt * 1.2)
		if sqrt(d.vx * d.vx + d.vy * d.vy) > 18.0 and randf() < dt * 6.0:
			ripple(d.x, d.y + 1.0, 0.9, 22.0, 1.2)
		# drawn: bobbing at the waterline, a shadow and the ring round it
		var bob: float = sin(d.ph) * 0.7
		var pic: LobbyPic = d.pic
		pic.flip = d.flip
		pic.global_position = GameData.world_to_3d(round(d.x), round(d.y), WATER_Z + bob)
		ellipse("duck_sh%d" % ducks.find(d), d.x, d.y + 1.0, 10.0, 3.0, Color(10 / 255.0, 40 / 255.0, 70 / 255.0), 1.0, 0.28, true)
		ellipse("duck_wl%d" % ducks.find(d), d.x, d.y + bob + 0.5, 11.0, 2.6, Color(225 / 255.0, 247 / 255.0, 1.0), 1.0, 0.75)

# ------------------------------------------------------------------ rings, splashes, sparks

## A ring on the water (RIPPLES.push): life s, grows to grow px radius, line width w; delay waits before it starts.
func ripple(x: float, y: float, life: float, grow: float, w: float, delay: float = 0.0) -> void:
	ripples.append({"x": x, "y": y, "t": -delay, "life": life, "grow": grow, "w": w})
	if ripples.size() > 80:
		ripples.pop_front()

## An ellipse on the water this frame (call it every frame it should show). col is sRGB; a is the alpha.
func ellipse(key: String, x: float, y: float, rx: float, ry: float, col: Color, lw: float, a: float, fill: bool = false) -> void:
	ells[key] = {"x": x, "y": y, "rx": rx, "ry": ry, "col": Color(col.r, col.g, col.b, a), "lw": lw, "fill": fill,
		"frame": Engine.get_process_frames()}

## waterSplash(x, y, size): the white-water crown and plume, and three rings.
func foam(x: float, y: float, size: float) -> void:
	var drops: Array = []
	var ring := int(round(38.0 * size + 8.0))
	for i in ring:
		var a := float(i) / ring * TAU + randf() * 0.2
		var out := (40.0 + randf() * 60.0) * size
		drops.append({"x": cos(a) * 8.0 * size, "y": sin(a) * 4.0 * size, "z": 2.0, "vx": cos(a) * out, "vy": sin(a) * out * 0.5,
			"vz": (120.0 + randf() * 120.0) * sqrt(size), "r": 1.5 + randf() * 2.5 * size})
	var plume := int(round(28.0 * size))
	for i in plume:
		var a2 := randf() * TAU
		var out2 := randf() * 20.0 * size
		drops.append({"x": 0.0, "y": 0.0, "z": 4.0, "vx": cos(a2) * out2, "vy": sin(a2) * out2 * 0.5,
			"vz": (150.0 + randf() * 180.0) * size, "r": 2.0 + randf() * 3.0 * size})
	foams.append({"x": x, "y": y, "size": size, "t": 0.0, "drops": drops})
	for i in 3:
		ripple(x, y, 1.4, 40.0 + 45.0 * size, 1.2 + 1.5 * size, i * 0.15)

## burst(w, x, y, n, colour, speed): sparks flying out along the ground.
func burst(x: float, y: float, n: int, col: Color, speed: float, z: float = 1.0) -> void:
	for i in n:
		var a := randf() * TAU
		var sp := speed * (0.3 + randf() * 0.7)
		var life := 0.25 + randf() * 0.35
		sparks.append({"x": x, "y": y, "z": z, "vx": cos(a) * sp, "vy": sin(a) * sp, "t": 0.0, "life": minf(0.6, life), "col": col})
	if sparks.size() > 260:
		sparks = sparks.slice(sparks.size() - 260)

## A swimmer's rings, called each frame he is in the water: three on entering, then now and again.
## key tells swimmers apart; entering is true on the first frame.
var _emit: Dictionary = {}
func swimmer_rings(key: String, x: float, y: float, speed: float, entering: bool, dt: float) -> void:
	if entering:
		for i in 3:
			ripple(x, y, 1.3, 70.0, 2.5, i * 0.18)
		_emit[key] = 0.4
		return
	var t: float = float(_emit.get(key, 0.4)) - dt
	if t <= 0.0:
		var moving := speed > 20.0
		ripple(x, y, 0.9 if moving else 1.6, 34.0 if moving else 26.0, 1.5)
		t = 0.22 if moving else 0.9
	_emit[key] = t

# ------------------------------------------------------------------ dripping

## Called every frame for each person who could be wet (a player, Gothica): picks up the end of a swim and drips.
## (drawDrips.) x, y: where he stands; fx, fy: which way he faces; swim: in the water; diving: on the tower or in
## the air; dt.
func drip_tick(key: String, x: float, y: float, fx: float, fy: float, swim: bool, diving: bool, dt: float) -> void:
	var e: Dictionary = _ents.get(key, {})
	e.x = x
	e.y = y
	e.fx = fx
	e.fy = fy
	_ents[key] = e
	var h := 14.0 * 4.6
	if _was.get(key, false) and not swim and not diving:
		_wet[key] = DRIP_TIME
		for i in 5:
			_spots.append({"x": x + (randf() - 0.5) * 14.0, "y": y + (randf() - 0.3) * 5.0, "r": 3.0 + randf() * 3.0, "t": 0.0, "life": 4.0})
	_was[key] = swim
	if swim or diving:
		_wet[key] = 0.0
		return
	var wet: float = float(_wet.get(key, 0.0))
	if wet <= 0.0:
		return
	_wet[key] = wet - dt
	var f := wet / DRIP_TIME
	if randf() < dt * 22.0 * f + dt * 2.0:
		var pt: Array = DRIP_POINTS[randi() % DRIP_POINTS.size()]
		_drops.append({"e": e, "ox": float(pt[0]) * h + (randf() - 0.5) * 2.0, "oy": float(pt[1]) * h, "t": 0.0,
			"hang": 0.25 + randf() * 0.35, "r": 2.2 + randf(), "live": false})
	if randf() < dt * 9.0 * f:
		_runs.append({"e": e, "ox": (randf() - 0.5) * 0.4, "oy": -(0.45 + randf() * 0.3) * h, "sp": 14.0 + randf() * 14.0,
			"t": 0.0, "life": 0.6 + randf() * 0.5})

func _drip_at(e: Dictionary, ox: float, oy: float) -> Vector2:
	var side := absf(float(e.fx)) > absf(float(e.fy))
	var sx := 0.0
	if side:
		sx = signf(float(e.fx)) * 3.0
	return Vector2(float(e.x) + (ox * 0.35 + sx if side else ox), float(e.y) + 0.0)

func is_wet(key: String) -> bool:
	return float(_wet.get(key, 0.0)) > 0.0

# ------------------------------------------------------------------ the step

func _process(delta: float) -> void:
	step(minf(delta, 0.1))

func step(dt: float) -> void:
	clock += dt
	_list.clear()
	var k := _k()
	# rings
	for r in ripples.duplicate():
		r.t += dt
		if r.t >= r.life:
			ripples.erase(r)
	# the ambient ones (with probability dt*0.9, if there are fewer than 40)
	if randf() < dt * 0.9 and ripples.size() < 40:
		ripple(POOL.x0 + 10.0 + randf() * (POOL.x1 - POOL.x0 - 20.0), POOL.y0 + 10.0 + randf() * (POOL.y1 - POOL.y0 - 20.0), 1.8, 18.0, 1.0)
	_step_ducks(dt)
	# splashes
	for s in foams.duplicate():
		s.t += dt
		var alive := 0
		for d in s.drops:
			if d.z <= 0.0:
				continue
			d.x += d.vx * dt
			d.y += d.vy * dt
			d.vz -= 700.0 * dt
			d.z += d.vz * dt
			d.vx *= 0.99
			if d.z <= 0.0:
				d.z = 0.0
				if randf() < 0.3:
					ripple(s.x + d.x, s.y + d.y, 0.6, 10.0, 1.0)
				continue
			alive += 1
			var p := GameData.world_to_3d(s.x + d.x, s.y + d.y, WATER_Z + d.z * k)
			var rim := ceilf(d.r) + 2.0
			_list.append([p, rim, Color("#7cc8f0", 0.95)])
			_list.append([p + Vector3(0, 0.002, 0), ceilf(d.r), Color("#ffffff" if d.r > 3.0 else "#eefaff", 0.95)])
		if alive == 0 and s.t >= 1.4:
			foams.erase(s)
	# sparks
	for s in sparks.duplicate():
		s.t += dt
		if s.t >= s.life:
			sparks.erase(s)
			continue
		var dr := pow(0.9, dt * 60.0)
		s.vx *= dr
		s.vy *= dr
		s.x += s.vx * dt
		s.y += s.vy * dt
		var c: Color = s.col
		_list.append([GameData.world_to_3d(s.x, s.y, s.z), 3.0, Color(c.r, c.g, c.b, 1.0 - s.t / s.life)])
	# the ellipses (kept only while they are being refreshed)
	var now_f := Engine.get_process_frames()
	for key in ells.keys():
		if int(ells[key].frame) < now_f - 2:
			ells.erase(key)
	_step_drips(dt, k)
	_flush_bits()
	_update_water()

## The factor the pool uses to draw heights from above (see LobbyPool.vis_k).
func _k() -> float:
	return float(pool.vis_k()) if pool else 1.0

func _step_drips(dt: float, k: float) -> void:
	var out_spots: Array = []
	# wet spots on the tiles, drying off
	for s in _spots.duplicate():
		s.t += dt
		if s.t >= s.life:
			_spots.erase(s)
	for q in _runs.duplicate():
		q.t += dt
		if q.t >= q.life:
			_runs.erase(q)
			continue
		var a := _drip_at(q.e, q.ox * 64.4, q.oy)
		var fade: float = 1.0 - q.t / q.life
		var ln := minf(7.0, q.sp * q.t)
		# oy is the height on him (negative: up the screen); it slides down by sp*t
		var hz: float = (-float(q.oy) - q.sp * q.t) * k
		_list.append([GameData.world_to_3d(a.x, float(q.e.y), maxf(0.0, hz)), 1.0, Color("#cfefff", 0.35 * fade)])
		_list.append([GameData.world_to_3d(a.x, float(q.e.y) + 0.1, maxf(0.0, hz - ln * 0.5)), 1.5, Color.WHITE * Color(1, 1, 1, 0.9 * fade)])
	for d in _drops.duplicate():
		d.t += dt
		if d.t < d.hang:
			var a2 := _drip_at(d.e, d.ox, d.oy)
			var kk: float = d.t / d.hang
			var r: float = 0.6 + d.r * kk
			_list.append([GameData.world_to_3d(a2.x, float(d.e.y), (-float(d.oy) - kk * 2.0) * k), maxf(1.0, ceilf(r)), Color("#2f79ad", 0.95)])
			_list.append([GameData.world_to_3d(a2.x, float(d.e.y) + 0.1, (-float(d.oy) - kk * 2.0) * k), 1.0, Color("#bfe9ff", 0.95)])
			continue
		if not d.live:
			var a3 := _drip_at(d.e, d.ox, d.oy)
			d.live = true
			d.x = a3.x
			d.y = float(d.e.y)
			d.z = -float(d.oy) - 2.0
			d.vz = 0.0
		d.vz -= 420.0 * dt
		var z0: float = d.z
		d.z += d.vz * dt
		if d.z <= 0.0:
			_drops.erase(d)
			if _spots.size() < 70:
				_spots.append({"x": d.x, "y": d.y + randf() * 3.0, "r": 1.5 + randf() * 1.3, "t": 0.0, "life": 1.8})
			for sd in [-1.0, 1.0]:
				_dbits.append({"x": d.x, "y": d.y, "z": 0.0, "vx": sd * (18.0 + randf() * 18.0), "vy": (randf() - 0.5) * 12.0,
					"vz": 30.0 + randf() * 20.0, "t": 0.0})
			continue
		_list.append([GameData.world_to_3d(d.x, d.y, d.z * k), 3.0, Color("#2f79ad", 0.95)])
		_list.append([GameData.world_to_3d(d.x, d.y + 0.1, d.z * k), 1.0, Color("#e8f8ff", 0.95)])
		var tail := minf(5.0, z0 - d.z + 1.0)
		_list.append([GameData.world_to_3d(d.x, d.y, (d.z + tail * 0.5 + 1.0) * k), 1.0, Color("#bfe9ff", 0.35)])
	for b in _dbits.duplicate():
		b.t += dt
		if b.t > 0.18:
			_dbits.erase(b)
			continue
		b.vz -= 500.0 * dt
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.z = maxf(0.0, b.z + b.vz * dt)
		_list.append([GameData.world_to_3d(b.x, b.y, b.z * k), 1.0, Color("#bfe9ff", 0.8)])
	# the wet spots on the tiles
	var mm := _spotmm.multimesh
	var n := mini(_spots.size(), SPOTS_CAP)
	for i in n:
		var s: Dictionary = _spots[i]
		var xf := Transform3D(Basis.from_scale(Vector3(s.r * 2.0 * GameData.UNIT, 1.0, s.r * 2.0 * 0.45 * GameData.UNIT)),
			GameData.world_to_3d(s.x, s.y, 0.06))
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, Color("#3a78a8", 0.35 * (1.0 - s.t / s.life)))
	mm.visible_instance_count = n
	out_spots.clear()

func _flush_bits() -> void:
	var mm := _bits.multimesh
	var n := mini(_list.size(), BITS_CAP)
	for i in n:
		var it: Array = _list[i]
		var sz: float = float(it[1]) * GameData.UNIT
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sz, sz, sz)), it[0]))
		mm.set_instance_color(i, it[2])
	mm.visible_instance_count = n

# ------------------------------------------------------------------ the water shader

func _update_water() -> void:
	if mat == null:
		return
	mat.set_shader_parameter("t", clock)
	var ra := PackedVector4Array()
	ra.resize(MAX_RIP)
	var n := 0
	var i := ripples.size() - 1
	while i >= 0 and n < MAX_RIP:
		var r: Dictionary = ripples[i]
		i -= 1
		if r.t < 0.0:
			continue
		var kk: float = r.t / r.life
		var rx: float = 5.0 + r.grow * kk
		var al := 0.55 * (1.0 - kk)
		var lw4 := floorf(clampf(r.w, 0.25, 6.0) * 4.0)
		ra[n] = Vector4(r.x, r.y, rx, lw4 + clampf(al, 0.0, 0.99))
		n += 1
	mat.set_shader_parameter("rip_a", ra)
	mat.set_shader_parameter("rip_n", n)
	var ea := PackedVector4Array()
	var eb := PackedVector4Array()
	var ec := PackedVector4Array()
	ea.resize(MAX_ELL)
	eb.resize(MAX_ELL)
	ec.resize(MAX_ELL)
	var m := 0
	for key in ells:
		if m >= MAX_ELL:
			break
		var e: Dictionary = ells[key]
		var c: Color = (e.col as Color)
		var lc := c.srgb_to_linear()
		ea[m] = Vector4(e.x, e.y, e.rx, e.ry)
		eb[m] = Vector4(lc.r, lc.g, lc.b, c.a)
		ec[m] = Vector4(e.lw, 1.0 if e.fill else 0.0, 0, 0)
		m += 1
	mat.set_shader_parameter("ell_a", ea)
	mat.set_shader_parameter("ell_b", eb)
	mat.set_shader_parameter("ell_c", ec)
	mat.set_shader_parameter("ell_n", m)
	var fa := PackedVector4Array()
	var fb := PackedVector4Array()
	fa.resize(MAX_FOAM)
	fb.resize(MAX_FOAM)
	var f := 0
	for s in foams:
		if f >= MAX_FOAM:
			break
		var fk := minf(1.0, s.t / 1.4)
		if fk >= 1.0:
			continue
		var fr: float = (16.0 + 36.0 * sqrt(fk)) * s.size + 6.0
		fa[f] = Vector4(s.x, s.y, fr, 0.85 * (1.0 - fk))
		fb[f] = Vector4(s.t, 0, 0, 0)
		f += 1
	mat.set_shader_parameter("foam_a", fa)
	mat.set_shader_parameter("foam_b", fb)
	mat.set_shader_parameter("foam_n", f)

static var _wshader: Shader
static func _water_shader() -> Shader:
	if _wshader:
		return _wshader
	_wshader = Shader.new()
	_wshader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform float t = 0.0;
uniform vec4 rip_a[32];
uniform int rip_n = 0;
uniform vec4 ell_a[8];
uniform vec4 ell_b[8];
uniform vec4 ell_c[8];
uniform int ell_n = 0;
uniform vec4 foam_a[4];
uniform vec4 foam_b[4];
uniform int foam_n = 0;

vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
// how much of a 'lw' px wide line round the ellipse (rx, ry) covers the point d from its middle
float ring(vec2 d, float rx, float ry, float lw) {
	vec2 q = d / vec2(rx, ry);
	float e = length(q);
	vec2 g = q / vec2(rx, ry);
	float gl = length(g) / max(e, 0.0001);
	float dist = abs(e - 1.0) / max(gl, 0.0001);
	return clamp(lw * 0.5 + 0.5 - dist, 0.0, 1.0);
}
float disc(vec2 d, float rx, float ry) {
	vec2 q = d / vec2(rx, ry);
	float e = length(q);
	vec2 g = q / vec2(rx, ry);
	float gl = length(g) / max(e, 0.0001);
	return clamp(0.5 + (1.0 - e) / max(gl, 0.0001), 0.0, 1.0);
}
void fragment() {
	vec2 A = vec2(18.0, 18.0) + UV * vec2(824.0, 484.0);
	float yq = floor((A.y - 99.0) / 2.0) * 2.0 + 99.0;
	float off = sin(yq * 0.16 + t * 2.1) * 1.4 + sin(yq * 0.05 - t * 1.3) * 0.8;
	vec2 uv = vec2(UV.x - off / 824.0, UV.y);
	vec3 col = texture(tex, uv).rgb;
	// the sheen
	vec2 p0 = vec2(633.0, 99.0);
	vec2 dd = vec2(806.0, 230.0) - p0;
	float g = dot(A - p0, dd) / dot(dd, dd);
	float s = fract(t * 0.08);
	col = mix(col, vec3(1.0), 0.07 * clamp(1.0 - abs(g - s) / 0.12, 0.0, 1.0));
	vec3 foamc = lin(vec3(1.0));
	for (int i = 0; i < foam_n; i++) {
		vec2 d = A - foam_a[i].xy;
		float fr = foam_a[i].z;
		float a = foam_a[i].w;
		float c = disc(d, fr, fr * 0.45) * a;
		col = mix(col, foamc, c);
		if (length(d / vec2(fr, fr * 0.45)) < 1.5) {
			for (int j = 0; j < 7; j++) {
				float an = float(j) * 0.9 + foam_b[i].x * 0.7;
				vec2 o = vec2(cos(an) * 0.8 * fr, sin(an) * 0.8 * fr * 0.45);
				float l = disc(d - o, 0.28 * fr, 0.13 * fr) * a;
				col = mix(col, lin(vec3(0.749, 0.914, 1.0)), l);
			}
		}
	}
	for (int i = 0; i < rip_n; i++) {
		vec4 r = rip_a[i];
		float lw4 = floor(r.w);
		float al = r.w - lw4;
		float c = ring(A - r.xy, r.z, r.z * 0.45, lw4 / 4.0) * al;
		col = mix(col, lin(vec3(0.902, 0.969, 1.0)), c);
	}
	for (int i = 0; i < ell_n; i++) {
		vec4 e = ell_a[i];
		float c = ell_c[i].y > 0.5 ? disc(A - e.xy, e.z, e.w) : ring(A - e.xy, e.z, e.w, ell_c[i].x);
		col = mix(col, ell_b[i].rgb, c * ell_b[i].a);
	}
	ALBEDO = col;
}
"""
	return _wshader
