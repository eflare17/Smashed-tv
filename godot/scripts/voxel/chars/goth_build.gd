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
			return VoxelSculpt.fill(Vector3i(-11, 100, -12), Vector3i(12, 140, 15), _head_sdf, _head_paint)
		"hair":
			return VoxelSculpt.fill(Vector3i(-19, 80, -19), Vector3i(20, 147, 15), _hair_sdf, _hair_paint,
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
		"forearm":
			return func(p: Vector3) -> float: return minf(_arm_sdf(p), _hand_sdf(p))
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

static func _skin_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.ellipsoid(p, Vector3(0.5, 124.5, 0.5), Vector3(9.8, 11.0, 10.3))          # the skull
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 118.8, 3.5), Vector3(8.6, 6.0, 7.4)), 3.0)    # cheeks, jaw
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 113.4, 6.5), Vector3(3.6, 2.6, 3.4)), 2.0)    # the chin: small
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5, 102.0, 0.0), Vector3(0.5, 112.0, 0.5), 4.2), 2.0)   # the neck: slim
	d = VoxelSculpt.smin(d, VoxelSculpt.cone_capsule(p, Vector3(0.5, 123.2, 10.4), Vector3(0.5, 118.8, 12.0), 0.9, 1.3), 0.8)   # the nose
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(-1.6, 116.0, 10.2), Vector3(2.6, 116.0, 10.2), 0.9), 0.8)   # lips
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(-1.2, 114.9, 10.0), Vector3(2.2, 114.9, 10.0), 1.0), 0.8)
	for sx in [-1.0, 1.0]:
		d = VoxelSculpt.smax(d, -VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 4.6, 124.6, 11.2), Vector3(3.0, 1.9, 1.6)), 0.8)   # eye sockets: a little in
	return d

static func _head_sdf(p: Vector3) -> float:
	var d := _skin_sdf(p)
	if p.y > 106.0 and p.y < 109.6:
		d -= 0.8                                      # (the choker round her neck)
	return d

static func _head_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var x := p.x - 0.5
	if p.y > 106.0 and p.y < 109.6:
		# the choker: black, a row of silver studs across the front
		if p.z > 1.5 and absf(p.y - 107.8) < 0.6 and fmod(absf(x) + 0.5, 2.2) < 0.9:
			return Color8(196, 196, 210)
		return VoxelSculpt.ramp(TOP, 0.1 + 0.5 * VoxelSculpt.lit(n, ao, 0.5))
	var front := n.z > 0.2 and p.z > 7.0
	if front:
		for sx: float in [-1.0, 1.0]:
			var ex: float = x - sx * 4.6
			var ey := p.y - 124.6
			var u := clampf(absf(ex) / 3.3, 0.0, 1.0)
			var e := Vector2(ex / 3.3, ey / (1.9 * (1.0 - 0.45 * u * u))).length()      # (almond: narrowing to its corners)
			# her eyes: a light grey-blue iris, a dark pupil, heavy dark liner, smoky shadow above, a flick out
			if e < 0.62:
				return Color8(20, 16, 30) if Vector2(ex, ey).length() < 0.9 else Color8(150, 162, 192)
			if e < 1.05:
				return Color8(8, 5, 14)
			if ey > 0.0 and ey < 2.8 and absf(ex) < 3.7 + ey * 0.3:
				return Color8(52, 44, 64).lerp(SKIN[2], clampf(ey / 2.6, 0.0, 1.0) * 0.6)
			if ey > -0.6 and ey < 1.4 and sx * ex > 2.9 and sx * ex < 5.0 and ey > (sx * ex - 2.9) * 0.5 - 0.6:
				return Color8(8, 5, 14)                 # (the wing)
			# brows: thin, arched, dark
			var by := 129.2 + 0.6 * (1.0 - absf(ex) / 3.8)
			if absf(p.y - by) < 0.55 and absf(ex) < 3.8:
				return Color8(14, 11, 26)
		# lips: closed, dark plum, the line between darker, a light catch on the lower one
		var lx := absf(x - 0.5)
		if p.y > 114.0 and p.y < 116.6 and lx < 2.4 - absf(p.y - 115.4) * 0.5 and p.z > 9.0:
			if absf(p.y - 115.4) < 0.25:
				return Color8(30, 20, 40)
			if p.y < 114.9 and lx < 1.0:
				return Color8(120, 96, 128)
			return Color8(66, 44, 78) if p.y > 115.4 else Color8(86, 62, 98)
	return _skin(p, n, ao)

# ---------------------------------------------------------------- her hair: big, wavy, to the middle of her back

static func _hair_sdf(p: Vector3) -> float:
	# parted in the middle; volume over the crown; lengths falling behind her face and down her back to below her
	# shoulder blades; a lock each side framing her face and falling over her shoulders in front
	var d := VoxelSculpt.ellipsoid(p, Vector3(0.5, 132.5, -1.5), Vector3(12.4, 11.8, 12.6))       # the crown
	for sx in [-1.0, 1.0]:
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 11.8, 117.5, -4.0), Vector3(6.2, 17.0, 8.0)), 4.0)   # behind her face
		d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5 + sx * 10.2, 129.0, 2.0), Vector3(0.5 + sx * 12.0, 110.0, 1.5), 2.8), 2.5)   # framing her face
		d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5 + sx * 11.8, 110.0, 3.5), Vector3(0.5 + sx * 13.5, 98.0, 4.5), 3.0), 2.5)   # over her shoulders
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 110.0, -8.5), Vector3(15.0, 27.0, 8.0)), 5.0)    # down her back
	# waves: the surface rising and falling in bands down the lengths
	var low := smoothstep(132.0, 112.0, p.y)
	d += low * (0.8 * sin(p.y * 0.55 + absf(p.x) * 0.3) + 0.4 * sin(p.x * 0.8 + p.z * 0.6))
	# her face clear (the hair parts round it, a little lower over her forehead at the sides), outside her head
	# (an arch: high at the parting, sweeping down either side of her forehead to her temples)
	var ax := absf(p.x - 0.5)
	var face_top := 133.0 - 7.5 * (ax / 8.5) * (ax / 8.5)
	if p.y < face_top and ax < 8.4 + 0.08 * (face_top - p.y) * 0.0:
		d = maxf(d, -VoxelSculpt.round_box(p, Vector3(0.5, 118.0, 13.0), Vector3(8.4, 14.0, 8.0), 1.5))
	# nothing in front of her face from the side: below her hairline the hair stays behind her cheeks
	var zlim := lerpf(2.5, 12.0, smoothstep(127.0, 136.0, p.y))
	d = VoxelSculpt.smax(d, p.z - zlim, 1.5)
	d = maxf(d, -(_skin_sdf(p) - 0.2))
	d = maxf(d, 82.0 - p.y)
	return d

static func _hair_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var t := VoxelSculpt.lit(n, ao, 0.45)
	# strands running down (and back from a parting in the middle on top), purple lights on the waves
	var strands := VoxelSculpt.noise3(Vector3(p.x * 1.6, p.y * 0.25, p.z * 1.6), 1.6) if p.y < 136.0 \
		else VoxelSculpt.noise3(Vector3(p.x * 0.4, p.y * 1.2, p.z * 1.6), 1.6)
	var c := VoxelSculpt.ramp(HAIR, 0.08 + 0.55 * t + 0.35 * (strands - 0.5))
	var wave := sin(p.y * 0.55 + p.x * 0.3)
	if wave > 0.55 and n.y > -0.2 and strands > 0.45:
		c = c.lerp(HAIR_LIT, 0.45 * smoothstep(0.55, 1.0, wave) * t)
	if absf(p.x - 0.5) < 0.8 and p.y > 138.0 and p.z > -2.0:
		c = HAIR[0]                                   # (the parting)
	return c

# ---------------------------------------------------------------- the torso (chest bone, pivot 0, 80, 0)

static func _torso_body(p: Vector3) -> float:
	var d := VoxelSculpt.ellipsoid(p, Vector3(0.5, 95.0, 0.0), Vector3(12.3, 11.0, 8.5))            # the ribcage
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 84.5, 0.0), Vector3(10.2, 7.0, 7.2)), 3.0)   # the waist
	for sx in [-1.0, 1.0]:
		d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5 + sx * 4.0, 103.5, -1.0), Vector3(0.5 + sx * 13.5, 102.0, -1.0), 3.8), 2.5)   # shoulders
		var b: Dictionary = BUST
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * float(b.x), float(b.y), float(b.z)),
			Vector3(float(b.rx), float(b.ry_up), float(b.rz))), 2.0)                                # her bust
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
	# the top: black, a soft sheen where the light catches it (on her bust most)
	var c2 := VoxelSculpt.ramp(TOP, 0.12 + 0.55 * t)
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
	var d := VoxelSculpt.cone_capsule(p, Vector3(17.3, 100.5, -1.0), Vector3(18.4, 86.0, -1.0), 3.5, 2.9)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(16.4, 101.0, -1.0), Vector3(4.4, 4.4, 4.4)), 2.0)   # the shoulder: round
	return d

static func _arm_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	return _skin(p, n, ao)

static func _forearm_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(18.4, 85.5, -1.0), Vector3(19.5, 75.0, -0.8), 2.9, 2.2)
	return VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(18.7, 82.0, -0.6), Vector3(3.0, 3.6, 2.9)), 1.5)   # the forearm's curve

static func _forearm_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	return _skin(p, n, ao)

static func _hand_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.round_box(p, Vector3(19.7, 71.2, -0.5), Vector3(1.7, 2.6, 2.1), 1.2)
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(19.5, 75.0, -0.8), Vector3(19.6, 73.0, -0.6), 2.3), 1.0)   # the wrist
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(18.0, 72.5, 1.2), Vector3(18.2, 70.6, 2.0), 0.9), 0.6)   # the thumb
	return d

static func _hand_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var c := _skin(p, n, ao)
	if p.y < 70.2:
		c = c.lerp(Color8(30, 24, 40), 0.7)           # (dark nail polish at her fingertips)
	return c

# ---------------------------------------------------------------- legs (her left; the right mirrored)

const BOOT_TOP := 32.5

static func _thigh_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(5.5, 53.0, 0.0), Vector3(5.5, 32.0, 0.0), 5.6, 4.3)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(5.5, 32.0, 1.6), Vector3(3.2, 2.5, 3.0)), 1.0)   # the knee
	return d

static func _thigh_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	return _skin(p, n, ao)

static func _shin_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(5.5, 31.5, 0.0), Vector3(5.5, 14.0, -0.5), 4.1, 3.2)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(5.5, 24.0, -1.5), Vector3(3.8, 5.0, 3.6)), 1.5)   # the calf
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
