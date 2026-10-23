class_name GothBuild
extends RefCounted
## Gothica sculpted (VoxelSculpt), measured off her sprites' front, side and back views: pale, a slim body, big
## wavy black hair with purple lights falling past her shoulders to the middle of her back, dark eye make-up and
## lips, a studded choker, a black scoop-necked top (VoxelModel.BUST: the shapes VoxelJiggle moves), a wide dark
## waistband, a two-tiered ruffled charcoal skirt to above her knees, bare legs, chunky laced platform boots to her
## knees. Model voxels on the goth rig (x her left, y up, z forward). Arms and legs built on her left, mirrored.
## Owned by the voxel session.

const SKIN := [Color8(120, 80, 74), Color8(180, 122, 108), Color8(215, 155, 135), Color8(236, 178, 152), Color8(248, 196, 168),
	Color8(254, 212, 184)]
const HAIR := [Color8(5, 3, 10), Color8(14, 11, 34), Color8(25, 23, 41), Color8(33, 28, 51), Color8(48, 39, 70), Color8(70, 58, 104)]
const HAIR_LIT := Color8(98, 80, 140)
const TOP := [Color8(5, 3, 10), Color8(14, 11, 34), Color8(25, 23, 41), Color8(40, 36, 56), Color8(62, 58, 82)]
const SKIRT := [Color8(19, 17, 26), Color8(25, 23, 41), Color8(43, 39, 53), Color8(56, 52, 72), Color8(78, 72, 96)]
const BOOT := [Color8(5, 3, 10), Color8(25, 23, 41), Color8(43, 39, 53), Color8(56, 52, 72), Color8(82, 78, 104)]
## Her bust's shapes (as VoxelModel.BUST, for this body; VoxelJiggle would need these if this model goes in).
const BUST := {"x": 5.0, "y": 92.5, "z": 6.4, "rx": 5.2, "ry_up": 5.0, "ry_down": 5.0, "rz": 5.6, "slope": 0.3}
const LIPS := [Color8(14, 11, 34), Color8(52, 40, 66), Color8(96, 87, 100)]

static func part(name: String) -> Dictionary:
	match name:
		"head":
			return VoxelSculpt.fill(Vector3i(-11, 99, -12), Vector3i(12, 137, 15), _head_sdf, _head_paint)
		"hair":
			return VoxelSculpt.fill(Vector3i(-23, 80, -22), Vector3i(24, 149, 15), _hair_sdf, _hair_paint,
				func(p: Vector3) -> float: return _skin_sdf(p))
		"torso":
			return VoxelSculpt.fill(Vector3i(-20, 77, -11), Vector3i(21, 109, 16), _torso_sdf, _torso_paint,
				func(p: Vector3) -> float: return minf(_arm_sdf(Vector3(absf(p.x), p.y, p.z)), _skirt_sdf(p)))
		"skirt":
			return VoxelSculpt.fill(Vector3i(-21, 49, -17), Vector3i(22, 83, 18), _skirt_sdf, _skirt_paint)
	for limb in LIMBS:
		if name == limb + "_l":
			return _limb(limb, false)
		if name == limb + "_r":
			return _limb(limb, true)
	return {}

const LIMBS := {
	"arm": [Vector3i(11, 84, -7), Vector3i(24, 107, 5)],
	"forearm": [Vector3i(14, 72, -5), Vector3i(24, 88, 4)],
	"hand": [Vector3i(15, 66, -4), Vector3i(24, 77, 4)],
	"thigh": [Vector3i(-1, 29, -7), Vector3i(12, 57, 7)],
	"shin": [Vector3i(-1, 11, -7), Vector3i(12, 35, 8)],
	"foot": [Vector3i(-2, 0, -9), Vector3i(13, 14, 15)],
}

static func _near(limb: String) -> Callable:
	match limb:
		"arm":
			return func(p: Vector3) -> float: return minf(_torso_body(p), _forearm_sdf(p))
		"thigh":
			return func(p: Vector3) -> float: return minf(_skirt_sdf(p), _shin_sdf(p))
		"shin":
			return func(p: Vector3) -> float: return minf(_thigh_sdf(p), _foot_sdf(p))
	return Callable()

static func _limb(limb: String, right: bool) -> Dictionary:
	var lo: Vector3i = LIMBS[limb][0]
	var hi: Vector3i = LIMBS[limb][1]
	var sdf := Callable(GothBuild, "_" + limb + "_sdf")
	var paint := Callable(GothBuild, "_" + limb + "_paint")
	var near := _near(limb)
	if not right:
		return VoxelSculpt.fill(lo, hi, sdf, paint, near)
	var m := func(p: Vector3) -> Vector3: return Vector3(-p.x, p.y, p.z)
	return VoxelSculpt.fill(Vector3i(-hi.x, lo.y, lo.z), Vector3i(-lo.x, hi.y, hi.z),
		func(p: Vector3) -> float: return sdf.call(m.call(p)),
		func(p: Vector3, n: Vector3, ao: float) -> Color: return paint.call(m.call(p), Vector3(-n.x, n.y, n.z), ao),
		(func(p: Vector3) -> float: return near.call(m.call(p))) if near.is_valid() else Callable())

static func _skin(p: Vector3, n: Vector3, ao: float) -> Color:
	var c := VoxelSculpt.ramp(SKIN, 0.22 + 0.55 * clampf(VoxelSculpt.lit(n, ao * 0.9, 0.6), 0.0, 1.0))
	var v := 0.98 + 0.04 * VoxelSculpt.noise3(p, 3.0)
	return Color(c.r * v, c.g * v, c.b * v)

# ---------------------------------------------------------------- the head (pivot 1, 106, 1)
# Her face is her own: the front of the head painted straight from her front picture (FACE_PIC), a pixel a cube, so
# her eyes, liner, brows and lips are the artist's. The head's shape is sculpted to fit it (its eyes at the picture's
# eyes, y 123.5; her lips at y 113; her chin at y 110.5), with only her nose standing out.

const FACE_PIC := "res://assets/CHARS/goth/sprites/front_a.png"
const FACE_COL := 31                # the picture's column at model x 0.5 (the middle of her face)
const FACE_ROWS := [26, 50]         # the picture's rows her face is in (forehead .. chin)
static var _face: Image
static var _face_span := {}         # row -> [first, last] column of her face (skin to skin) in the picture

static func _face_img() -> Image:
	if _face == null:
		var tex: Texture2D = load(FACE_PIC)
		_face = tex.get_image()
		if _face.is_compressed():
			_face.decompress()
		for row in range(int(FACE_ROWS[0]), int(FACE_ROWS[1]) + 1):
			var first := -1
			var last := -1
			for col in range(FACE_COL - 12, FACE_COL + 12):
				var c := _face.get_pixel(col, row)
				if c.a > 0.5 and c.r > 0.6 and c.g > 0.42:
					if first < 0:
						first = col
					last = col
			if first >= 0:
				_face_span[row] = [first, last]
	return _face

# her face's colour at a front cube (null: not her face)
static func _face_at(p: Vector3):
	var img := _face_img()
	var row := floori(160.0 - p.y)
	var col := floori(p.x - 0.5) + FACE_COL
	if not _face_span.has(row):
		return null
	var sp: Array = _face_span[row]
	if col < int(sp[0]) or col > int(sp[1]):
		return null
	var c := img.get_pixel(col, row)
	return c if c.a > 0.5 else null

static func _skin_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.ellipsoid(p, Vector3(0.5, 124.0, 0.5), Vector3(9.6, 11.0, 10.3))          # the skull
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 119.0, 2.6), Vector3(8.8, 5.6, 8.0)), 4.0)    # cheekbones: wide
	d = VoxelSculpt.smin(d, VoxelSculpt.cone_capsule(p, Vector3(0.5, 117.5, 3.0), Vector3(0.5, 111.6, 6.4), 6.8, 2.0), 3.5)   # her jaw narrowing to a pointed chin
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5, 101.0, 0.0), Vector3(0.5, 111.0, 0.5), 4.2), 2.0)   # the neck: slim
	d = VoxelSculpt.smin(d, VoxelSculpt.cone_capsule(p, Vector3(0.5, 121.5, 10.4), Vector3(0.5, 117.6, 11.6), 0.9, 1.3), 0.8)   # the nose
	return d

static func _head_sdf(p: Vector3) -> float:
	var d := _skin_sdf(p)
	if p.y > 105.0 and p.y < 108.6:
		d -= 0.8                                      # (the choker round her neck)
	return d

static func _head_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var x := p.x - 0.5
	if p.y > 105.0 and p.y < 108.6:
		# the choker: black, a row of silver studs across the front
		if p.z > 1.5 and absf(p.y - 106.8) < 0.6 and fmod(absf(x) + 0.5, 2.2) < 0.9:
			return Color8(196, 196, 210)
		return VoxelSculpt.ramp(TOP, 0.1 + 0.5 * VoxelSculpt.lit(n, ao, 0.5))
	var skin := _skin(p, n, ao)
	if n.z > 0.12 and p.z > 3.0:
		var f = _face_at(p)
		if f != null:
			# her picture's features (eyes, liner, brows, lips: its dark colours) as drawn, fading round the sides of
			# her head; its skin tones only a touch (the head's own shading does that, smooth, not in blotches)
			var k := smoothstep(0.05, 0.35, n.z)
			var fc: Color = f
			var skin_tone := fc.r > 0.5 and fc.r > fc.b + 0.12
			return skin.lerp(fc, k * (0.2 if skin_tone else 1.0))
	return skin

# ---------------------------------------------------------------- her hair: locks, wavy, to below her shoulder blades
# Not one mass: thick locks, each its own wavy tube from her crown down (from a middle parting over the top, round
# the sides behind her face, down her back), with a lighter purple sheen along the top of each wave and dark between.

static var _locks: Array = []        # [[points: PackedVector3Array, r0, r1, shade]]

static func _make_locks() -> void:
	if not _locks.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	# round her head: from beside her face (a = 0.42 pi) to the middle of her back (a = pi), both sides
	for layer in 2:
		_ring(rng, layer)
	_top_locks(rng)

# a ring of locks round her head (layer 0 the outer, thinner and lit; layer 1 under it, set between them, darker:
# the gaps between the outer locks show the dark ones under them)
static func _ring(rng: RandomNumberGenerator, layer: int) -> void:
	for side in [-1.0, 1.0]:
		var n := 10 if layer == 0 else 9
		for i in n:
			var f := (float(i) + (0.5 if layer == 1 else 0.0)) / float(n - 1)
			var a := lerpf(0.42 * PI, PI, minf(f, 1.0)) + rng.randf_range(-0.04, 0.04)
			var dir := Vector3(side * sin(a), 0.0, cos(a))
			var root := Vector3(0.5, 139.5, -1.0) + Vector3(side * sin(a) * 4.0, 0.0, cos(a) * 4.0)
			var bottom := lerpf(97.0, 84.0, float(i) / float(n - 1)) + rng.randf_range(-2.0, 2.0)
			var pts := PackedVector3Array()
			var steps := 9
			var phase := rng.randf() * TAU
			for k in steps + 1:
				var t := float(k) / steps
				var y := lerpf(139.5, bottom, t)
				# out over the crown, then falling: furthest out at her ears, in a little toward the ends
				var out := lerpf(4.0, 14.2, smoothstep(0.0, 0.3, t)) + 2.6 * sin(t * PI) - 0.6 * t - 2.4 * layer   # (full: out past her shoulders)
				var wave := 1.3 * sin(t * 7.5 + phase) * smoothstep(0.25, 0.5, t)
				var q := Vector3(0.5, y, -1.0) + dir * (out + wave)
				q += Vector3(dir.z, 0, -dir.x) * 0.9 * sin(t * 5.0 + phase) * smoothstep(0.3, 0.6, t)   # (and side to side)
				pts.append(q)
			if layer == 0:
				_locks.append([pts, rng.randf_range(3.0, 3.4), rng.randf_range(2.0, 2.4), rng.randf_range(-0.08, 0.14), phase])
			else:
				_locks.append([pts, 3.4, 2.4, -0.28, phase])

static func _top_locks(rng: RandomNumberGenerator) -> void:
	# over the top: from the parting down either side to her temples, framing her forehead
	for side in [-1.0, 1.0]:
		for i in 4:
			var z0 := lerpf(7.0, -6.0, float(i) / 3.0)
			var pts2 := PackedVector3Array()
			for k in 7:
				var t2 := float(k) / 6.0
				var ang := t2 * 1.45                      # (round the skull from the parting to the side)
				var r := 9.6 + 0.6 * sin(t2 * PI)
				pts2.append(Vector3(0.5 + side * (0.6 + r * sin(ang)), 130.5 + r * cos(ang), z0 - 0.5 * t2 * (z0 - 2.0)))
			_locks.append([pts2, 2.7, 2.4, rng.randf_range(-0.06, 0.12), rng.randf() * TAU])
	# the two locks falling in front of her shoulders
	for side in [-1.0, 1.0]:
		var pts3 := PackedVector3Array()
		for k in 8:
			var t3 := float(k) / 7.0
			pts3.append(Vector3(0.5 + side * (10.8 + 3.2 * t3 + 0.9 * sin(t3 * 6.0)), lerpf(128.0, 96.0, t3), 1.8 + 2.2 * t3))
		_locks.append([pts3, 2.8, 1.9, 0.1, 1.0])

# distance to the nearest lock (and which)
static func _lock_d(p: Vector3) -> Vector3:
	_make_locks()
	var best := INF
	var which := -1
	var at := 0.0
	for li in _locks.size():
		var L: Array = _locks[li]
		var pts: PackedVector3Array = L[0]
		var m := pts.size() - 1
		for k in m:
			var a := pts[k]
			var b := pts[k + 1]
			# (a quick skip when it's far off)
			if absf(p.y - (a.y + b.y) * 0.5) > absf(a.y - b.y) * 0.5 + 6.0:
				continue
			var r := lerpf(float(L[1]), float(L[2]), (float(k) + 0.5) / m)
			var d := VoxelSculpt.capsule(p, a, b, r)
			if d < best:
				best = d
				which = li
				at = (float(k) + 0.5) / m
	return Vector3(best, which, at)

static func _hair_sdf(p: Vector3) -> float:
	var d := _lock_d(p).x
	# a base over her skull under the locks (no gaps through to her scalp)
	d = minf(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 131.5, -1.5), Vector3(10.4, 10.2, 10.6)))
	# her face clear: an arch over her forehead from the parting, nothing in front of her cheeks from the side
	var ax := absf(p.x - 0.5)
	var face_top := 134.0 - 6.5 * (ax / 8.8) * (ax / 8.8)
	if p.y < face_top and ax < 8.8:
		d = maxf(d, p.z - 3.5)                        # (in front of z 3.5 within her face's width: clear)
	var zlim := lerpf(3.5, 13.0, smoothstep(127.0, 135.0, p.y))
	if ax < 13.5:
		d = VoxelSculpt.smax(d, p.z - zlim, 1.0)
	d = maxf(d, -(_skin_sdf(p) - 0.3))
	d = maxf(d, 82.0 - p.y)
	return d

static func _hair_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var ld := _lock_d(p)
	var shade := -0.3
	var crest := 0.0
	if ld.y >= 0 and ld.x < 1.0:
		var L: Array = _locks[int(ld.y)]
		shade = float(L[3])
		# where along its waves (the crest of each wave catches the light)
		crest = sin(ld.z * 7.5 + float(L[4]))
	var t := VoxelSculpt.lit(n, ao * 1.4, 0.42)
	var strands := VoxelSculpt.noise3(Vector3(p.x * 2.4, p.y * 0.25, p.z * 2.4), 1.2)
	var c := VoxelSculpt.ramp(HAIR, clampf(0.05 + 0.55 * t + shade + 0.18 * (strands - 0.5) + 0.12 * crest, 0.0, 1.0))
	# the sheen: purple bands across each lock at its wave crests, on the lit side
	# (streaks running down each lock on its lit side, longest over the crests of its waves)
	var streak := VoxelSculpt.noise3(Vector3(p.x * 3.0, p.y * 0.18, p.z * 3.0), 1.0)
	if shade > -0.2 and t > 0.45 and streak > 0.62 - 0.12 * crest:
		c = c.lerp(HAIR_LIT, 0.55 * smoothstep(0.45, 0.75, t))
	if ld.x > -0.6 and ao > 0.3:
		c = c.darkened(0.4)                           # (between locks)
	return c

# ---------------------------------------------------------------- the torso (chest bone, pivot 0, 80, 0)

static func _torso_body(p: Vector3) -> float:
	var d := VoxelSculpt.ellipsoid(p, Vector3(0.5, 95.0, 0.0), Vector3(12.3, 11.0, 8.5))            # the ribcage
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 84.5, 0.0), Vector3(10.2, 7.0, 7.2)), 3.0)   # the waist
	for sx in [-1.0, 1.0]:
		d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5 + sx * 4.0, 103.5, -1.0), Vector3(0.5 + sx * 13.5, 102.0, -1.0), 3.8), 2.5)   # shoulders
		var b: Dictionary = BUST
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * float(b.x), float(b.y), float(b.z)),
			Vector3(float(b.rx), float(b.ry_up), float(b.rz))), 3.5)                                # her bust: blended into her
	d = VoxelSculpt.smax(d, 78.5 - p.y, 1.0)
	return d


# where her top covers her: a scoop at the front, thin straps, the arms bare
static func _top_at(p: Vector3) -> float:
	var x := absf(p.x - 0.5)
	var top: float
	if x > 10.5:
		top = 98.0
	elif x > 7.0:
		top = 106.0
	elif p.z > 0.0:
		top = lerpf(97.0, 104.0, (x / 7.0) * (x / 7.0))
	else:
		top = lerpf(101.0, 105.0, (x / 7.0) * (x / 7.0))
	return top - p.y

static func _torso_sdf(p: Vector3) -> float:
	var d := _torso_body(p)
	if p.y < 85.5:
		return d - 0.9                                # (the waistband: thicker)
	return d - 0.5 if _top_at(p) > 0.0 else d

static func _torso_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var t := VoxelSculpt.lit(n, ao, 0.5)
	if p.y < 85.5:
		# the waistband: dark charcoal-purple, laced up the front
		var c := VoxelSculpt.ramp(SKIRT, 0.25 + 0.6 * t)
		if p.z > 4.0 and absf(p.x - 0.5) < 2.0 and absf(fmod(p.y + 100.0, 2.0) - 1.0) < 0.4 and absf(absf(p.x - 0.5) - (fmod(p.y + 100.0, 2.0))) < 0.8:
			c = Color8(96, 70, 120)
		if absf(p.y - 85.0) < 0.5 or absf(p.y - 79.2) < 0.5:
			c = c.darkened(0.35)                      # (its edges)
		return c
	var cover := _top_at(p)
	if cover <= 0.0:
		return _skin(p, n, ao)
	# the top: soft black cotton, its folds and the light on it from the shading
	var c2 := VoxelSculpt.ramp(TOP, 0.18 + 0.65 * t)
	if cover < 0.9:
		c2 = TOP[0]                                   # (its edge)
	return c2

# ---------------------------------------------------------------- the skirt (hips bone, pivot 0, 68, 0): two tiers, ruffled

static func _skirt_r(p: Vector3) -> Vector2:
	# its half-width and half-depth at a height: the upper tier from the waistband out, the lower tier stepping out
	# again and flaring to the hem
	var y := p.y
	if y > 66.0:
		var k := (79.5 - y) / 13.5
		return Vector2(lerpf(11.0, 15.0, k), lerpf(8.0, 11.5, k))
	var k2 := (66.0 - y) / 14.0
	return Vector2(lerpf(15.0, 18.2, k2), lerpf(11.6, 14.2, k2))

static func _skirt_sdf(p: Vector3) -> float:
	var r := _skirt_r(p)
	var q := Vector2(p.x - 0.5, p.z)
	var a := atan2(q.x, q.y)
	var ruffle := 0.7 * sin(a * 11.0) * smoothstep(79.0, 60.0, p.y)
	var d := (Vector2(q.x / r.x, q.y / r.y).length() - 1.0) * minf(r.x, r.y) - ruffle
	var hem := 52.0 + 0.8 * sin(a * 9.0 + 0.5)
	d = maxf(d, hem - p.y)
	d = maxf(d, p.y - 79.8)
	if absf(p.y - 66.0) < 1.0:
		d -= 0.6                                      # (the lower tier's top: a frill)
	return d

static func _skirt_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var t := VoxelSculpt.lit(n, ao, 0.5)
	var a := atan2(p.x - 0.5, p.z)
	var pleat := 0.18 * cos(a * 11.0)
	var c := VoxelSculpt.ramp(SKIRT, clampf(0.2 + 0.6 * t + pleat, 0.0, 1.0))
	if absf(p.y - 65.4) < 0.7:
		c = c.darkened(0.4)                           # (under the frill)
	if p.y < 53.5 + 0.8 * sin(a * 9.0 + 0.5):
		c = c.darkened(0.2)                           # (the hem)
	return c

# ---------------------------------------------------------------- arms (her left; the right mirrored): slim

static func _arm_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(16.8, 100.5, -1.0), Vector3(17.8, 86.0, -1.0), 4.1, 3.3)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(15.8, 101.0, -1.0), Vector3(4.8, 4.6, 4.8)), 2.0)   # the shoulder: round
	return d

static func _arm_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	return _skin(p, n, ao)

static func _forearm_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(17.9, 85.5, -1.0), Vector3(19.2, 75.0, -0.8), 3.3, 2.4)
	return VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(18.3, 82.0, -0.6), Vector3(3.4, 3.8, 3.2)), 1.5)   # the forearm's curve

static func _forearm_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	return _skin(p, n, ao)

static func _hand_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.round_box(p, Vector3(19.7, 71.2, -0.5), Vector3(1.7, 2.6, 2.1), 1.2)
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(19.5, 75.0, -0.8), Vector3(19.6, 73.0, -0.6), 2.3), 1.0)   # the wrist
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(18.0, 72.5, 1.2), Vector3(18.2, 70.6, 2.0), 0.9), 0.6)   # the thumb
	return d

static func _hand_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var c := _skin(p, n, ao)
	if p.y < 69.6 and n.y < -0.3:
		c = c.lerp(Color8(30, 24, 40), 0.7)           # (dark nail polish at her fingertips)
	return c

# ---------------------------------------------------------------- legs (her left; the right mirrored)

const BOOT_TOP := 32.5

static func _thigh_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(5.5, 53.0, 0.0), Vector3(5.6, 32.0, 0.0), 6.6, 4.6)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(5.5, 32.0, 1.6), Vector3(3.2, 2.5, 3.0)), 1.0)   # the knee
	return d

static func _thigh_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	return _skin(p, n, ao)

static func _shin_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(5.6, 31.5, 0.0), Vector3(5.5, 14.0, -0.5), 4.5, 3.4)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(5.5, 24.0, -1.5), Vector3(4.2, 5.2, 4.0)), 1.5)   # the calf
	if p.y < BOOT_TOP:
		d -= 1.9 if p.y > BOOT_TOP - 2.2 else 1.3     # (the boot, its cuff at the top)
	return d

static func _boot(p: Vector3, n: Vector3, ao: float) -> Color:
	return VoxelSculpt.ramp(BOOT, 0.12 + 0.75 * VoxelSculpt.lit(n, ao, 0.45))

static func _shin_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	if p.y >= BOOT_TOP:
		return _skin(p, n, ao)
	var c := _boot(p, n, ao)
	if p.z > 2.5 and absf(p.x - 5.5) < 1.8 and fmod(p.y + 100.0, 2.0) < 0.7 and p.y < BOOT_TOP - 2.2:
		c = Color8(96, 87, 100)                       # (the laces)
	return c

static func _foot_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.round_box(p, Vector3(5.5, 9.0, 2.5), Vector3(5.0, 3.8, 7.5), 2.4)          # the boot's upper
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(5.5, 8.0, 8.5), Vector3(5.2, 3.6, 4.4)), 2.0)   # the toe
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(5.5, 10.0, -0.5), Vector3(5.5, 14.0, -0.5), 4.6), 2.0)   # the ankle
	d = minf(d, VoxelSculpt.round_box(p, Vector3(5.5, 2.6, 3.0), Vector3(6.0, 2.6, 9.0), 1.2))      # the platform: thick
	return maxf(d, -p.y)

static func _foot_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	if p.y < 5.2:
		var c := VoxelSculpt.ramp(BOOT, 0.2 + 0.55 * VoxelSculpt.lit(n, ao, 0.45))
		if absf(p.y - 2.6) < 0.5 or fmod(p.z + 100.0, 2.5) < 0.6 and p.y < 1.5:
			c = Color8(75, 74, 97)                    # (the ridges round the platform)
		return c
	var c2 := _boot(p, n, ao)
	if p.z > 4.0 and p.z < 9.0 and absf(p.x - 5.5) < 1.8 and p.y > 8.0 and fmod(p.z + 100.0, 2.0) < 0.7:
		c2 = Color8(96, 87, 100)                      # (the laces)
	return c2
