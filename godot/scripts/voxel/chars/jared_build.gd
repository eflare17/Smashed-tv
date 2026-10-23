class_name JaredBuild
extends RefCounted
## Juicy Jared sculpted (VoxelSculpt), from his sprites' front, three-quarter, side and back views: a big tanned head
## on a thick neck, a heavy jaw and brow, a bulbous nose, a big dark drooping moustache, short thick hair parted on
## his left, blue wrap-around shades. Model voxels (x his left, y up, z forward; the jared rig's pivots: head at
## (0, 110, 1)). Built: head, hair_classic, glasses; the body: a big barrel chest and belly in his green singlet
## (JUICY JARED on the front, the back mottled green and blue, a deep scoop neck, thick straps, big armholes), huge
## arms (deltoids, biceps, triceps, forearms, fists), grey shorts to mid-thigh with rolled cuffs, thick legs, chunky
## black boots up the shin. Arms and legs are built on his left and mirrored. Owned by the voxel session.

const SKIN := [Color8(109, 55, 55), Color8(176, 86, 73), Color8(206, 103, 79), Color8(233, 121, 84), Color8(244, 134, 90),
	Color8(252, 166, 111), Color8(253, 182, 128)]
const HAIR := [Color8(32, 18, 26), Color8(50, 28, 36), Color8(74, 40, 48), Color8(92, 56, 58), Color8(122, 80, 74)]
const FRAME := [Color8(20, 20, 30), Color8(42, 39, 53), Color8(70, 70, 86)]
const LENS := [Color8(4, 70, 150), Color8(10, 125, 205), Color8(4, 184, 243), Color8(120, 225, 255)]

static func part(name: String) -> Dictionary:
	match name:
		"head":
			return _big(Vector3i(-16, 100, -13), Vector3i(19, 148, 26), _head_sdf, _head_paint)
		"hair_classic":
			return _big(Vector3i(-17, 116, -16), Vector3i(20, 151, 22), _hair_sdf, _hair_paint)
		"glasses":
			return _big(Vector3i(-17, 121, -5), Vector3i(19, 131, 25), _glasses_sdf, _glasses_paint)
		"torso":
			return VoxelSculpt.fill(Vector3i(-31, 58, -19), Vector3i(32, 112, 23), _torso_sdf, _torso_paint)
		"pelvis":
			return VoxelSculpt.fill(Vector3i(-25, 44, -18), Vector3i(26, 67, 19), _pelvis_sdf, _pelvis_paint)
	for limb in LIMBS:
		if name == limb + "_l":
			return _limb(limb, false)
		if name == limb + "_r":
			return _limb(limb, true)
	return {}

## His head is drawn bigger than life (as in his pictures): the head's shapes scaled up by HEAD about the neck.
const HEAD := 1.12
const NECK := Vector3(0.5, 106.0, 1.0)

static func _big(lo: Vector3i, hi: Vector3i, sdf: Callable, paint: Callable) -> Dictionary:
	var a := NECK + (Vector3(lo) - NECK) * HEAD
	var b := NECK + (Vector3(hi) - NECK) * HEAD
	var m := func(p: Vector3) -> Vector3: return NECK + (p - NECK) / HEAD
	return VoxelSculpt.fill(Vector3i(floori(a.x), floori(a.y), floori(a.z)), Vector3i(ceili(b.x), ceili(b.y), ceili(b.z)),
		func(p: Vector3) -> float: return float(sdf.call(m.call(p))) * HEAD,
		func(p: Vector3, n: Vector3, ao: float) -> Color: return paint.call(m.call(p), n, ao))

## His left side's limbs: [lo, hi] (model voxels); the right's are these mirrored.
const LIMBS := {
	"arm": [Vector3i(17, 76, -14), Vector3i(42, 115, 13)],
	"forearm": [Vector3i(23, 60, -11), Vector3i(42, 84, 9)],
	"hand": [Vector3i(27, 48, -8), Vector3i(42, 66, 8)],
	"thigh": [Vector3i(2, 26, -14), Vector3i(32, 55, 15)],
	"shin": [Vector3i(7, 8, -13), Vector3i(29, 31, 10)],
	"foot": [Vector3i(9, 0, -11), Vector3i(30, 15, 19)],
}

static func _limb(limb: String, right: bool) -> Dictionary:
	var lo: Vector3i = LIMBS[limb][0]
	var hi: Vector3i = LIMBS[limb][1]
	var sdf := Callable(JaredBuild, "_" + limb + "_sdf")
	var paint := Callable(JaredBuild, "_" + limb + "_paint")
	if not right:
		return VoxelSculpt.fill(lo, hi, sdf, paint)
	var m := func(p: Vector3) -> Vector3: return Vector3(-p.x, p.y, p.z)
	return VoxelSculpt.fill(Vector3i(-hi.x, lo.y, lo.z), Vector3i(-lo.x, hi.y, hi.z),
		func(p: Vector3) -> float: return sdf.call(m.call(p)),
		func(p: Vector3, n: Vector3, ao: float) -> Color: return paint.call(m.call(p), Vector3(-n.x, n.y, n.z), ao))

# ---------------------------------------------------------------- the head

static func _skin_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.ellipsoid(p, Vector3(0.5, 131.0, 3.0), Vector3(12.5, 14.0, 13.5))           # the skull
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 120.0, 6.5), Vector3(12.3, 11.0, 12.5)), 4.0)   # the jaw: wide
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 111.8, 12.5), Vector3(7.8, 4.6, 6.4)), 2.5)     # the chin: jutting
	d = VoxelSculpt.smin(d, VoxelSculpt.round_box(p, Vector3(0.5, 113.5, 6.0), Vector3(11.0, 4.0, 9.0), 3.5), 3.0)   # the jaw's line: square
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5, 102.0, 0.5), Vector3(0.5, 116.0, 2.0), 8.6), 3.0)  # the neck: thick
	for sx in [-1.0, 1.0]:
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 7.5, 118.0, 11.5), Vector3(5.0, 6.0, 6.0)), 3.0)   # cheeks
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 12.4, 122.0, 2.5), Vector3(1.9, 4.4, 3.0)), 1.0)   # ears
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(-8.5, 128.6, 14.5), Vector3(9.5, 128.6, 14.5), 2.4), 2.5)    # the brow: heavy
	d = VoxelSculpt.smin(d, VoxelSculpt.cone_capsule(p, Vector3(0.5, 127.5, 17.0), Vector3(0.5, 120.8, 23.0), 1.7, 2.3), 1.2)   # the nose: it stands out
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 120.0, 22.2), Vector3(3.0, 2.3, 2.6)), 1.0)     # its end: a big one
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(-3.5, 113.6, 16.6), Vector3(4.5, 113.6, 16.6), 1.5), 1.2)   # the lower lip
	# (the nostrils: a little in under the nose's end)
	for sx2 in [-1.0, 1.0]:
		d = VoxelSculpt.smax(d, -VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx2 * 1.5, 118.3, 23.0), Vector3(0.9, 0.7, 1.2)), 0.4)
	return d

static func _tash_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.capsule(p, Vector3(0.5, 117.4, 20.6), Vector3(-6.0, 116.0, 18.0), 2.3)
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5, 117.4, 20.6), Vector3(7.0, 116.0, 18.0), 2.3), 1.2)
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(-6.0, 116.0, 18.0), Vector3(-7.8, 113.4, 16.6), 1.6), 1.0)   # the ends down
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(7.0, 116.0, 18.0), Vector3(8.8, 113.4, 16.6), 1.6), 1.0)
	return d

static func _head_sdf(p: Vector3) -> float:
	return minf(_skin_sdf(p), _tash_sdf(p))

static func _head_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var t := VoxelSculpt.lit(n, ao)
	if _tash_sdf(p) <= 0.6:
		# the moustache: strands running down and out, lighter at its top
		var strand := VoxelSculpt.hash3(p.x * 0.9 + p.y * 0.4, p.z * 0.5, 0.0)
		return VoxelSculpt.ramp(HAIR, 0.1 + 0.5 * t + 0.25 * strand)
	var x := p.x - 0.5
	# eyebrows above the shades: thick and dark
	if p.y > 129.8 and p.y < 131.4 and absf(x) > 1.8 and absf(x) < 10.5 and n.z > 0.25:
		return VoxelSculpt.ramp(HAIR, 0.2 + 0.45 * t + 0.15 * VoxelSculpt.hash3(p.x, p.y * 2.0, 0.0))
	# the mouth's line under the moustache, the lip a shade redder
	if p.y > 114.4 and p.y < 115.3 and absf(x) < 5.0 and p.z > 14.0:
		return SKIN[0]
	var c := VoxelSculpt.ramp(SKIN, 0.38 + 0.56 * clampf(VoxelSculpt.lit(n, ao * 0.5, 0.65), 0.0, 1.0))
	if absf(p.y - 113.6) < 1.6 and absf(x) < 5.0 and p.z > 15.0:
		c = c.lerp(Color8(196, 92, 78), 0.45)
	# a touch of variation (skin isn't flat paint)
	var v := 0.97 + 0.06 * VoxelSculpt.noise3(p, 3.0)
	return Color(c.r * v, c.g * v, c.b * v)

# ---------------------------------------------------------------- the hair: short, thick, parted on his left

static func _hairline(p: Vector3) -> float:
	var x := absf(p.x - 0.5)
	# over the forehead (front), at the temples and sideburns (sides, in front of the ears), down the back
	var front := 135.5 + 0.1 * x
	var side := 127.0 if x < 10.0 else lerpf(127.0, 119.5, clampf((x - 10.0) / 2.5, 0.0, 1.0))
	var back := 118.5
	if p.z > 9.0:
		return front
	if p.z > 3.5:
		return lerpf(side, front, (p.z - 3.5) / 5.5)
	if p.z > -2.5:
		return lerpf(back, side, (p.z + 2.5) / 6.0) if x > 9.0 else lerpf(back, 128.0, (p.z + 2.5) / 6.0)
	return back

static func _hair_sdf(p: Vector3) -> float:
	var skin := _skin_sdf(p)
	# a layer on his head: short at the back and sides, thicker on top (most at the front, swept across to his right),
	# the very top flattened off; never sticking out past his forehead
	var top_k := smoothstep(134.0, 141.5, p.y)
	var thick := 1.1 + top_k * (1.9 + 1.0 * smoothstep(-6.0, 12.0, p.z) + 0.8 * smoothstep(4.0, -8.0, p.x))
	var hl := _hairline(p)
	thick *= 0.3 + 0.7 * smoothstep(hl, hl + 3.5, p.y)          # (thin at its edge: grows out of the skin, no ledge)
	var d := skin - thick
	d = VoxelSculpt.smax(d, p.y - 145.6, 2.0)
	d = maxf(d, _hairline(p) - p.y)
	d = maxf(d, -skin)                               # (on the head, not in it)
	return d

static func _hair_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var t := VoxelSculpt.lit(n, ao, 0.5)
	# combed: across to his right on top (away from the parting), back along the sides
	var comb := VoxelSculpt.hash3(p.z * 1.0 + p.y * 0.3, 0.0, 0.0) if p.y > 136.5 else VoxelSculpt.hash3(p.y * 1.0 + p.x * 0.3, 7.0, 0.0)
	var clump := VoxelSculpt.noise3(Vector3(p.x * 0.4, p.y * 0.8, p.z * 1.4), 2.5) if p.y > 136.5 else VoxelSculpt.noise3(Vector3(p.x * 1.4, p.y * 0.8, p.z * 0.4), 2.5)
	var c := VoxelSculpt.ramp(HAIR, 0.1 + 0.55 * t + 0.15 * comb + 0.3 * (clump - 0.5))
	if absf(p.x - 6.0) < 1.6 and p.y > 136.0:
		c = c.darkened(0.25)                          # (the parting's shadow)
	return c

# ---------------------------------------------------------------- the shades: wrap-around, blue

static func _glasses_sdf(p: Vector3) -> float:
	var x := p.x - 0.5
	var bottom := 121.2 + 0.014 * x * x
	if absf(x) < 2.0:
		bottom = 124.6                                # (over the bridge of his nose)
	var shell := absf(_skin_sdf(p) - 1.5) - 0.85       # a layer just off his face
	var d := maxf(shell, maxf(bottom - p.y, p.y - 129.6))
	d = maxf(d, 1.5 - p.z)                            # (front and sides, round to the temples)
	for sx in [-1.0, 1.0]:
		d = minf(d, VoxelSculpt.capsule(p, Vector3(0.5 + sx * 13.6, 127.4, 4.5), Vector3(0.5 + sx * 13.4, 127.2, -3.0), 0.75))   # arms
	return d

static func _glasses_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var x := p.x - 0.5
	var bottom := 121.2 + 0.014 * x * x
	if absf(x) < 2.0:
		bottom = 124.6
	var t := VoxelSculpt.lit(n, ao, 0.5)
	var rim := p.y > 128.9 or p.y < bottom + 0.6 or absf(x) < 0.9 or p.z < 4.5
	if rim:
		return VoxelSculpt.ramp(FRAME, 0.2 + 0.7 * t)
	# the lens: darker at the top, a bright streak across
	var k := clampf((p.y - bottom) / (128.9 - bottom), 0.0, 1.0)
	var c := VoxelSculpt.ramp(LENS, 0.95 - 0.6 * k + 0.1 * t)
	var streak := absf(fmod(x * 0.55 + p.y * 1.0 + 200.0, 9.0) - 4.5)
	if streak < 0.8 and n.z > 0.3:
		c = c.lerp(Color8(220, 248, 255), 0.6)
	return c

# ---------------------------------------------------------------- the body: shared paints

const SINGLET := [Color8(3, 120, 70), Color8(3, 160, 92), Color8(5, 190, 82), Color8(37, 227, 83), Color8(97, 243, 93),
	Color8(150, 248, 140)]
const SINGLET_BLUE := [Color8(8, 70, 120), Color8(10, 110, 170), Color8(22, 164, 190), Color8(70, 200, 210)]
const PRINT := Color8(208, 251, 173)
const DENIM := [Color8(46, 58, 78), Color8(72, 88, 110), Color8(98, 124, 142), Color8(116, 151, 169), Color8(132, 169, 185),
	Color8(163, 212, 222)]
const BOOT := [Color8(16, 18, 30), Color8(26, 28, 42), Color8(42, 39, 53), Color8(55, 62, 80), Color8(80, 86, 100)]

static func _skin(p: Vector3, n: Vector3, ao: float) -> Color:
	var c := VoxelSculpt.ramp(SKIN, 0.26 + 0.6 * clampf(VoxelSculpt.lit(n, ao * 0.8, 0.6), 0.0, 1.0))
	var v := 0.97 + 0.06 * VoxelSculpt.noise3(p, 3.0)
	return Color(c.r * v, c.g * v, c.b * v)

static func _denim(p: Vector3, n: Vector3, ao: float) -> Color:
	var t := VoxelSculpt.lit(n, ao, 0.55)
	var weave := VoxelSculpt.hash3(p.x + p.y, p.y - p.z, p.z) * 0.12
	return VoxelSculpt.ramp(DENIM, 0.15 + 0.8 * t + weave - 0.06)

static func _boot(p: Vector3, n: Vector3, ao: float) -> Color:
	return VoxelSculpt.ramp(BOOT, 0.1 + 0.85 * VoxelSculpt.lit(n, ao, 0.45))

# ---------------------------------------------------------------- the torso (chest bone)

static func _torso_body(p: Vector3) -> float:
	var d := VoxelSculpt.ellipsoid(p, Vector3(0.5, 80.0, 2.0), Vector3(20.5, 17.5, 16.5))            # the belly
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 95.0, 0.0), Vector3(23.0, 12.5, 14.5)), 5.0)   # the chest
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 96.0, -6.0), Vector3(22.0, 11.5, 11.0)), 4.0)  # the back
	for sx in [-1.0, 1.0]:
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 9.5, 96.5, 9.0), Vector3(9.5, 6.5, 6.5)), 2.5)   # pecs
		d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5 + sx * 5.0, 104.0, -3.0), Vector3(0.5 + sx * 19.0, 102.5, -3.0), 5.5), 3.0)   # traps
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 17.0, 88.0, -5.0), Vector3(6.0, 10.0, 7.5)), 3.0)   # lats
	d = VoxelSculpt.smax(d, 60.5 - p.y, 1.5)
	return d

# where his singlet covers him (else skin): a deep scoop at the front, thick straps, big armholes
static func _singlet_at(p: Vector3) -> float:
	var x := absf(p.x - 0.5)
	var top: float
	if x > 17.0:
		top = 88.0
	elif x > 9.0:
		top = 109.0
	else:
		var k := (x / 9.0) * (x / 9.0)
		top = lerpf(91.0, 106.0, k) if p.z > -1.0 else lerpf(101.0, 107.0, k)
	return top - p.y                                   # (> 0: covered, by how far)

static func _torso_sdf(p: Vector3) -> float:
	var d := _torso_body(p)
	return d - 0.9 if _singlet_at(p) > 0.0 else d      # (the singlet a layer over him: its edge a step)

static func _letter_rows() -> Dictionary:
	return {"J": ["0011", "0001", "0001", "0001", "1001", "0110"], "U": ["1001", "1001", "1001", "1001", "1001", "0110"],
		"I": ["111", "010", "010", "010", "010", "111"], "C": ["0111", "1000", "1000", "1000", "1000", "0111"],
		"Y": ["10001", "01010", "00100", "00100", "00100", "00100"], "A": ["0110", "1001", "1001", "1111", "1001", "1001"],
		"R": ["1110", "1001", "1001", "1110", "1010", "1001"], "E": ["1111", "1000", "1110", "1000", "1000", "1111"],
		"D": ["1110", "1001", "1001", "1001", "1001", "1110"]}

# whether a front cube at x, y is in the print ("JUICY" over a round logo over "JARED")
static func _print_at(x: float, y: float) -> bool:
	var rows := _letter_rows()
	for line in [["JUICY", 89], ["JARED", 74]]:
		var word: String = line[0]
		var top: int = line[1]
		var w := 0
		for ch in word:
			w += (rows[ch][0] as String).length() + 1
		w -= 1
		var cx := -floori(w / 2.0)
		var ix := floori(x - 0.5) - cx
		var iy := top - floori(y)
		if iy < 0 or iy >= 6 or ix < 0 or ix >= w:
			continue
		for ch in word:
			var cw := (rows[ch][0] as String).length()
			if ix < cw:
				return (rows[ch][iy] as String)[ix] == "1"
			ix -= cw + 1
			if ix < 0:
				return false
	var r := Vector2(x - 0.5, y - 80.0).length()
	return absf(r - 2.6) < 0.7 or (r < 1.2)

static func _torso_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var cover := _singlet_at(p)
	if cover <= 0.0:
		return _skin(p, n, ao)
	var t := VoxelSculpt.lit(n, ao, 0.55)
	# the trim: a darker band round the neck, the armholes and the straps' edges
	var x := absf(p.x - 0.5)
	if cover < 1.3 or (p.y > 88.0 and (absf(x - 9.0) < 0.9 or absf(x - 17.0) < 0.9)):
		return VoxelSculpt.ramp(SINGLET, 0.1 + 0.4 * t)
	if p.z > 4.0 and n.z > 0.35 and _print_at(p.x, p.y):
		return PRINT.lerp(Color8(160, 230, 140), 0.4 * (1.0 - t))
	var mottle := VoxelSculpt.noise3(p, 4.5)
	if p.z < -2.0:
		# the back: mottled green and blue
		var blue := VoxelSculpt.noise3(p + Vector3(31, 7, 3), 6.0)
		if blue > 0.55:
			return VoxelSculpt.ramp(SINGLET_BLUE, 0.15 + 0.7 * t + 0.2 * (mottle - 0.5))
		return VoxelSculpt.ramp(SINGLET, 0.15 + 0.7 * t + 0.35 * (mottle - 0.5))
	return VoxelSculpt.ramp(SINGLET, 0.3 + 0.65 * t + 0.25 * (mottle - 0.5))

# ---------------------------------------------------------------- the shorts (hips bone)

static func _pelvis_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.ellipsoid(p, Vector3(0.5, 57.0, 0.5), Vector3(21.5, 10.0, 15.5))
	d = VoxelSculpt.smin(d, VoxelSculpt.round_box(p, Vector3(0.5, 61.0, 0.5), Vector3(19.5, 4.0, 14.0), 4.0), 3.0)
	for sx in [-1.0, 1.0]:
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 9.0, 52.0, -6.0), Vector3(9.5, 8.0, 8.5)), 3.0)   # his backside
	d = VoxelSculpt.smax(d, p.y - 65.5, 1.0)
	return d

static func _pelvis_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var c := _denim(p, n, ao)
	if p.y > 62.5:
		c = c.darkened(0.15)                          # (the waistband)
	if absf(p.x - 0.5) < 0.8 and p.z > 8.0 and p.y < 62.5 and p.y > 52.0:
		c = c.darkened(0.3)                           # (the fly's seam)
	if absf(p.x - 0.5) > 19.0 and p.y < 62.0:
		c = c.darkened(0.1)                           # (the side seams)
	return c

# ---------------------------------------------------------------- arms (his left; the right mirrored)

static func _arm_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(29.5, 106.0, -2.0), Vector3(32.5, 80.0, -2.0), 8.0, 6.3)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(28.5, 104.0, -1.5), Vector3(9.5, 8.0, 9.5)), 3.0)   # the deltoid
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(31.0, 92.0, 2.0), Vector3(7.8, 10.5, 7.5)), 2.5)   # the biceps
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(32.0, 94.0, -5.5), Vector3(7.5, 11.5, 6.5)), 2.5)  # the triceps
	return d

static func _arm_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	return _skin(p, n, ao)

static func _forearm_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(32.5, 80.0, -2.0), Vector3(34.5, 64.5, -1.5), 6.6, 4.4)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(33.5, 74.5, -0.5), Vector3(6.5, 6.5, 6.5)), 2.5)   # the forearm's bulk
	return d

static func _forearm_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	return _skin(p, n, ao)

static func _hand_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.round_box(p, Vector3(34.5, 57.5, 0.0), Vector3(3.8, 4.5, 4.6), 2.3)    # a fist
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(34.5, 63.5, -1.5), Vector3(34.5, 60.0, -0.5), 4.0), 2.0)   # the wrist
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(31.5, 59.5, 3.0), Vector3(31.8, 56.0, 4.6), 1.6), 1.0)   # the thumb
	return d

static func _hand_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var c := _skin(p, n, ao)
	if p.z > 3.5 and p.y < 57.0 and fmod(p.y + 100.0, 2.4) < 0.6:
		c = c.darkened(0.18)                          # (between the fingers)
	return c

# ---------------------------------------------------------------- legs (his left; the right mirrored)

const SHORTS_HEM := 41.5

static func _thigh_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(16.0, 51.0, 0.0), Vector3(17.5, 30.0, 0.0), 12.0, 8.8)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(17.5, 39.0, 3.5), Vector3(10.5, 11.0, 8.0)), 3.0)   # the quads
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(12.5, 37.0, 0.0), Vector3(6.0, 8.0, 7.0)), 2.5)    # inside of the thigh
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(18.0, 31.0, 3.5), Vector3(5.0, 3.5, 4.0)), 1.5)   # the knee
	if p.y > SHORTS_HEM + 2.4:
		d -= 1.3                                      # (the shorts' leg, loose)
	elif p.y > SHORTS_HEM:
		d -= 2.3                                      # (the rolled cuff)
	return d

static func _thigh_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	if p.y > SHORTS_HEM:
		var c := _denim(p, n, ao)
		if p.y < SHORTS_HEM + 2.4:
			c = c.lightened(0.12) if p.y > SHORTS_HEM + 1.2 else c.darkened(0.08)    # (the cuff's fold)
		return c
	return _skin(p, n, ao)

const BOOT_TOP := 20.0

static func _shin_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(17.5, 28.5, 0.0), Vector3(18.5, 13.0, -0.5), 8.4, 5.8)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(17.8, 23.0, -3.0), Vector3(7.6, 7.5, 6.5)), 2.5)   # the calf
	if p.y < BOOT_TOP:
		d -= 1.8 if p.y > BOOT_TOP - 2.0 else 1.3     # (the boot's shaft, its top rolled)
	return d

static func _shin_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	if p.y < BOOT_TOP:
		var c := _boot(p, n, ao)
		if p.z > 3.0 and absf(p.x - 18.5) < 2.5 and fmod(p.y + 100.0, 2.0) < 0.8:
			c = c.lightened(0.25)                     # (the laces)
		return c
	return _skin(p, n, ao)

static func _foot_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.round_box(p, Vector3(19.0, 6.0, 2.5), Vector3(7.2, 5.0, 9.5), 3.0)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(19.0, 5.0, 10.5), Vector3(7.4, 5.0, 6.5)), 2.5)   # the toe cap
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(18.8, 8.0, -1.0), Vector3(18.6, 14.0, -0.8), 6.6), 2.5)   # the ankle
	d = minf(d, VoxelSculpt.round_box(p, Vector3(19.0, 1.2, 3.0), Vector3(8.0, 1.2, 11.0), 1.0))       # the sole: wider
	return maxf(d, -p.y)

static func _foot_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	if p.y < 2.4:
		return VoxelSculpt.ramp(BOOT, 0.05 + 0.3 * VoxelSculpt.lit(n, ao, 0.4))    # (the sole)
	var c := _boot(p, n, ao)
	if p.z > 4.0 and p.z < 10.0 and absf(p.x - 19.0) < 2.5 and p.y > 6.0 and fmod(p.z + 100.0, 2.0) < 0.8:
		c = c.lightened(0.25)                         # (the laces)
	return c
