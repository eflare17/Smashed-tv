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
			return _big(Vector3i(-17, 110, -17), Vector3i(20, 151, 22), _hair_sdf, _hair_paint)
		"glasses":
			return _big(Vector3i(-17, 120, -5), Vector3i(19, 132, 25), _glasses_sdf, _glasses_paint)
		"torso":
			return VoxelSculpt.fill(Vector3i(-36, 64, -25), Vector3i(37, 121, 23), _torso_sdf, _torso_paint,
				func(p: Vector3) -> float: return _arm_sdf(Vector3(absf(p.x - 0.5) + 0.5, p.y, p.z)))
		"pelvis":
			return VoxelSculpt.fill(Vector3i(-27, 46, -21), Vector3i(28, 73, 21), _pelvis_sdf, _pelvis_paint)
	for limb in LIMBS:
		if name == limb + "_l":
			return _limb(limb, false)
		if name == limb + "_r":
			return _limb(limb, true)
	return {}

## His head as in his pictures (measured off his front sprite): squat and wide, his chin at the top of his shoulders
## (no neck showing). The head's shapes are designed at one size and fitted to that: HX wider, HY shorter, HZ, the
## design's chin (DESIGN_CHIN) put at CHIN.
const HX := 1.12
const HY := 0.84
const HZ := 1.05
const DESIGN_CHIN := 107.3
const CHIN := 117.5

static func _to_model(q: Vector3) -> Vector3:
	return Vector3(0.5 + (q.x - 0.5) * HX, CHIN + (q.y - DESIGN_CHIN) * HY, 1.0 + (q.z - 1.0) * HZ)

static func _to_design(p: Vector3) -> Vector3:
	return Vector3(0.5 + (p.x - 0.5) / HX, DESIGN_CHIN + (p.y - CHIN) / HY, 1.0 + (p.z - 1.0) / HZ)

static func _big(lo: Vector3i, hi: Vector3i, sdf: Callable, paint: Callable) -> Dictionary:
	var a := _to_model(Vector3(lo))
	var b := _to_model(Vector3(hi))
	return VoxelSculpt.fill(Vector3i(floori(a.x), floori(a.y), floori(a.z)), Vector3i(ceili(b.x), ceili(b.y), ceili(b.z)),
		func(p: Vector3) -> float: return float(sdf.call(_to_design(p))) * HY,
		func(p: Vector3, n: Vector3, ao: float) -> Color: return paint.call(_to_design(p), n, ao))

## His left side's limbs: [lo, hi] (model voxels); the right's are these mirrored.
const LIMBS := {
	"arm": [Vector3i(14, 76, -17), Vector3i(44, 120, 14)],
	"forearm": [Vector3i(22, 60, -12), Vector3i(45, 86, 10)],
	"hand": [Vector3i(26, 48, -8), Vector3i(43, 66, 11)],
	"thigh": [Vector3i(1, 26, -16), Vector3i(33, 61, 16)],
	"shin": [Vector3i(6, 9, -12), Vector3i(31, 34, 12)],
	"foot": [Vector3i(8, 0, -10), Vector3i(31, 16, 21)],
}

## The parts a limb meets (for its shading: VoxelSculpt.fill's ctx), on his left.
static func _near(limb: String) -> Callable:
	match limb:
		"arm":
			return func(p: Vector3) -> float: return minf(_torso_body(p), _forearm_sdf(p))
		"forearm":
			return func(p: Vector3) -> float: return minf(_arm_sdf(p), _hand_sdf(p))
		"thigh":
			return func(p: Vector3) -> float: return minf(_pelvis_sdf(p), _shin_sdf(p))
		"shin":
			return func(p: Vector3) -> float: return minf(_thigh_sdf(p), _foot_sdf(p))
	return Callable()

static func _limb(limb: String, right: bool) -> Dictionary:
	var lo: Vector3i = LIMBS[limb][0]
	var hi: Vector3i = LIMBS[limb][1]
	var sdf := Callable(JaredBuild, "_" + limb + "_sdf")
	var paint := Callable(JaredBuild, "_" + limb + "_paint")
	var near := _near(limb)
	if not right:
		return VoxelSculpt.fill(lo, hi, sdf, paint, near)
	var m := func(p: Vector3) -> Vector3: return Vector3(-p.x, p.y, p.z)
	return VoxelSculpt.fill(Vector3i(-hi.x, lo.y, lo.z), Vector3i(-lo.x, hi.y, hi.z),
		func(p: Vector3) -> float: return sdf.call(m.call(p)),
		func(p: Vector3, n: Vector3, ao: float) -> Color: return paint.call(m.call(p), Vector3(-n.x, n.y, n.z), ao),
		(func(p: Vector3) -> float: return near.call(m.call(p))) if near.is_valid() else Callable())

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
	d = VoxelSculpt.smin(d, VoxelSculpt.cone_capsule(p, Vector3(0.5, 127.5, 16.5), Vector3(0.5, 121.0, 19.6), 1.7, 2.3), 1.2)   # the nose
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 120.2, 19.4), Vector3(3.0, 2.3, 2.0)), 1.0)     # its end: broad, not long
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(-3.5, 113.6, 16.6), Vector3(4.5, 113.6, 16.6), 1.5), 1.2)   # the lower lip
	# (the nostrils: a little in under the nose's end)
	for sx2 in [-1.0, 1.0]:
		d = VoxelSculpt.smax(d, -VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx2 * 1.5, 118.5, 20.4), Vector3(0.9, 0.7, 1.2)), 0.4)
	return d

static func _tash_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.capsule(p, Vector3(0.5, 117.4, 18.8), Vector3(-6.0, 116.0, 17.0), 2.3)
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5, 117.4, 18.8), Vector3(7.0, 116.0, 17.0), 2.3), 1.2)
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(-6.0, 116.0, 17.0), Vector3(-7.8, 113.4, 15.8), 1.6), 1.0)   # the ends down
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(7.0, 116.0, 17.0), Vector3(8.8, 113.4, 15.8), 1.6), 1.0)
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
	# (no eyebrows: in his pictures the shades sit right under his brow, forehead above)
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
	# over the forehead: a slight dip in the middle, up at the temples (as in his front sprite); sideburns down in front
	# of the ears; down to the nape at the back
	var front := 134.0 + 2.4 * smoothstep(1.5, 7.5, x) - 1.2 * smoothstep(9.5, 12.5, x)
	var side := 127.0 if x < 10.0 else lerpf(127.0, 119.5, clampf((x - 10.0) / 2.5, 0.0, 1.0))
	var back := 112.5                                # (longer at the back: down to his nape)
	if p.z > 9.0:
		return front
	if p.z > 3.5:
		return lerpf(side, front, (p.z - 3.5) / 5.5)
	if p.z > -2.5:
		return lerpf(back, side, (p.z + 2.5) / 6.0) if x > 9.0 else lerpf(back, 128.0, (p.z + 2.5) / 6.0)
	return back

static func _hair_sdf(p: Vector3) -> float:
	var skin := _skin_sdf(p)
	# swept back: short and close at the sides and nape, thick on top, fullest over the front where it lifts off his
	# forehead and is combed back; the top rounded off (not a dome, not a flat cap)
	var top_k := smoothstep(131.0, 140.0, p.y)
	var front_k := smoothstep(-8.0, 10.0, p.z)
	var thick := 0.9 + top_k * (2.3 + 0.9 * front_k) + 0.6 * smoothstep(2.0, -8.0, p.z) * (1.0 - top_k)   # (a little fuller down the back)
	var hl := _hairline(p)
	thick *= 0.3 + 0.7 * smoothstep(hl - 0.5, hl + 4.0, p.y)     # (thin at its edge: no brim over his forehead)
	var d := skin - thick
	d = VoxelSculpt.smax(d, p.y - (146.0 + 0.6 * front_k), 3.5)     # (rounded off on top, a touch higher at the front)
	d = maxf(d, _hairline(p) - p.y)
	d = maxf(d, -skin)                               # (on the head, not in it)
	return d

const HAIR_LIT := Color8(116, 72, 68)

static func _hair_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var t := VoxelSculpt.lit(n, ao, 0.5)
	# locks combed back from the forehead (running front to back over the top, down and back at the sides): each lock
	# lighter along its middle, darker in the gaps between
	var along_top := Vector3(p.x * 1.5, p.y * 0.35, p.z * 0.2)
	var along_side := Vector3(p.x * 0.2, p.y * 1.2 + p.z * 0.5, p.z * 0.2)
	var lock := VoxelSculpt.noise3(along_top if p.y > 134.0 else along_side, 1.6)
	var c := VoxelSculpt.ramp(HAIR, 0.08 + 0.55 * t + 0.4 * (lock - 0.5))
	# the shine: a band of lighter strands across the top front, where the light catches the sweep
	if p.y > 139.0 and p.z > 0.0 and n.y > 0.35 and lock > 0.55:
		c = c.lerp(HAIR_LIT, 0.55 * smoothstep(0.55, 0.8, lock))
	return c

# ---------------------------------------------------------------- the shades: one wrap-around visor, blue

const LENS2 := [Color8(3, 40, 105), Color8(6, 90, 178), Color8(8, 145, 226), Color8(4, 184, 243), Color8(120, 228, 255)]
const SHADE_TOP := 129.9

static func _shade_bottom(x: float) -> float:
	var ax := absf(x)
	var b := 122.9 - 0.009 * ax * ax               # (lower toward the sides)
	if ax < 2.8:
		b = maxf(b, 125.9 - ax * 0.9)              # (the notch over his nose)
	return b

static func _glasses_sdf(p: Vector3) -> float:
	var x := p.x - 0.5
	var shell := absf(_skin_sdf(p) - 1.4) - 0.9        # a layer standing just off his face
	var d := maxf(shell, maxf(_shade_bottom(x) - p.y, p.y - SHADE_TOP))
	d = maxf(d, 1.0 - p.z)                            # (front and sides, round to the temples)
	for sx in [-1.0, 1.0]:
		d = minf(d, VoxelSculpt.capsule(p, Vector3(0.5 + sx * 13.8, 128.6, 3.5), Vector3(0.5 + sx * 13.5, 128.2, -3.0), 1.0))   # arms
	return d

static func _glasses_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var x := p.x - 0.5
	var t := VoxelSculpt.lit(n, ao, 0.5)
	var bottom := _shade_bottom(x)
	if p.y > SHADE_TOP - 1.2 or p.z < 3.0:
		return VoxelSculpt.ramp(FRAME, 0.15 + 0.6 * t)      # (the frame along the top, the arms)
	# the lens: deep blue at its lower edge and round the sides, bright cyan across its upper middle
	var k := clampf((p.y - bottom) / (SHADE_TOP - 1.2 - bottom), 0.0, 1.0)
	var side := clampf(absf(x) / 13.0, 0.0, 1.0)
	var c := VoxelSculpt.ramp(LENS2, clampf(0.2 + 0.62 * k - 0.35 * side * side + 0.08 * t, 0.0, 0.8))
	if p.y < bottom + 0.8:
		c = c.darkened(0.25)                          # (its lower rim)
	# one glint on each side, up and in
	if absf(absf(x) - 5.5) < 1.2 and p.y > SHADE_TOP - 3.4 and p.y < SHADE_TOP - 2.0 and n.z > 0.4:
		c = c.lerp(Color8(230, 250, 255), 0.75)
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
# (measured off his sprites: a barrel chest nearly as deep as his head is long, sticking out almost as far as his
# nose; big traps up to his chin; the singlet down to y 70)

static func _torso_body(p: Vector3) -> float:
	var d := VoxelSculpt.ellipsoid(p, Vector3(0.5, 81.0, 0.5), Vector3(21.0, 16.5, 19.0))           # the belly
	d = VoxelSculpt.smin(d, VoxelSculpt.round_box(p, Vector3(0.5, 73.5, 0.0), Vector3(19.5, 7.0, 16.0), 6.0), 4.0)   # down to the hem
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5, 100.0, 0.0), Vector3(22.5, 13.5, 18.0)), 5.0)     # the chest: deep
	d = VoxelSculpt.smin(d, VoxelSculpt.round_box(p, Vector3(0.5, 101.0, -8.0), Vector3(19.5, 10.0, 8.5), 6.5), 4.0)   # the back: broad, flat
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5, 110.0, -3.0), Vector3(0.5, 113.0, -3.0), 8.5), 3.0)   # round the neck
	# his pecs: one broad slab across his chest, flat-fronted with a shelf under it (two round ones read as a bust)
	d = VoxelSculpt.smin(d, VoxelSculpt.round_box(p, Vector3(0.5, 101.5, 12.0), Vector3(17.0, 5.5, 4.5), 4.0), 3.0)
	for sx in [-1.0, 1.0]:
		pass
		d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(0.5 + sx * 7.0, 111.0, -4.0), Vector3(0.5 + sx * 23.0, 109.0, -3.0), 7.0), 3.5)   # traps: to his chin
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 18.0, 91.0, -6.0), Vector3(6.5, 10.0, 8.0)), 3.0)   # lats
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 26.0, 108.5, -2.0), Vector3(8.5, 8.0, 10.0)), 4.0)   # the shoulder's top: the traps run into it
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 21.0, 98.0, -2.5), Vector3(5.5, 9.0, 9.5)), 3.5)   # the armpit: his side meets the arm
	d = VoxelSculpt.smax(d, 66.5 - p.y, 1.5)
	return d

# where his singlet covers him (else skin): a scoop at the front, thick straps over his traps, big armholes
static func _singlet_at(p: Vector3) -> float:
	var x := absf(p.x - 0.5)
	var top: float
	if x > 12.5:
		top = lerpf(119.0, 96.0, smoothstep(14.5, 22.5, x))     # (the strap curving down into the armhole)
	else:
		var k := (x / 12.5) * (x / 12.5)
		top = lerpf(99.0, 116.0, k) if p.z > -1.0 else lerpf(110.0, 117.0, k)
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
	for line in [["JUICY", 96], ["JARED", 81]]:
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
	var r := Vector2(x - 0.5, y - 86.5).length()
	return absf(r - 2.6) < 0.7 or (r < 1.2)

static func _torso_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var cover := _singlet_at(p)
	if cover <= 0.0:
		return _skin(p, n, ao)
	var t := VoxelSculpt.lit(n, ao, 0.55)
	# the trim: a darker band round the neck, the armholes and the straps' edges, and the hem
	var x := absf(p.x - 0.5)
	if cover < 1.3 or p.y < 68.0 or (p.y > 97.0 and absf(x - 12.5) < 0.9):
		return VoxelSculpt.ramp(SINGLET, 0.1 + 0.4 * t)
	if p.z > 6.0 and n.z > 0.35 and _print_at(p.x, p.y):
		return PRINT.lerp(Color8(160, 230, 140), 0.4 * (1.0 - t))
	var mottle := VoxelSculpt.noise3(p, 4.5)
	if p.z < -4.0:
		# the back: mottled green and blue
		var blue := VoxelSculpt.noise3(p + Vector3(31, 7, 3), 6.0)
		if blue > 0.55:
			return VoxelSculpt.ramp(SINGLET_BLUE, 0.15 + 0.7 * t + 0.2 * (mottle - 0.5))
		return VoxelSculpt.ramp(SINGLET, 0.15 + 0.7 * t + 0.35 * (mottle - 0.5))
	return VoxelSculpt.ramp(SINGLET, 0.3 + 0.65 * t + 0.25 * (mottle - 0.5))

# ---------------------------------------------------------------- the shorts (hips bone): short, from y 71 to 51

static func _pelvis_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.ellipsoid(p, Vector3(0.5, 61.0, 0.0), Vector3(24.0, 11.0, 17.5))
	d = VoxelSculpt.smin(d, VoxelSculpt.round_box(p, Vector3(0.5, 67.0, 0.0), Vector3(21.5, 4.5, 16.5), 4.5), 3.0)
	for sx in [-1.0, 1.0]:
		d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(0.5 + sx * 9.5, 57.5, -7.5), Vector3(10.0, 9.0, 9.5)), 3.0)   # his backside
	d = VoxelSculpt.smax(d, p.y - 71.5, 1.0)
	return d

static func _pelvis_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var c := _denim(p, n, ao)
	if p.y > 68.5:
		c = c.darkened(0.15)                          # (the waistband)
	if absf(p.x - 0.5) < 0.8 and p.z > 10.0 and p.y < 68.5 and p.y > 55.0:
		c = c.darkened(0.3)                           # (the fly's seam)
	if absf(p.x - 0.5) > 22.0 and p.y < 68.0:
		c = c.darkened(0.1)                           # (the side seams)
	return c

# ---------------------------------------------------------------- arms (his left; the right mirrored): huge

static func _arm_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(30.0, 106.0, -2.0), Vector3(32.5, 80.0, -2.0), 9.5, 7.5)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(29.5, 106.5, -1.5), Vector3(11.0, 11.0, 11.5)), 3.0)   # the deltoid
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(25.0, 109.0, -2.0), Vector3(6.0, 6.5, 8.5)), 3.0)   # onto the shoulder
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(31.5, 93.0, 2.5), Vector3(9.0, 11.5, 9.0)), 2.5)   # the biceps
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(32.5, 94.0, -6.0), Vector3(8.5, 12.0, 7.5)), 2.5)  # the triceps
	return d

static func _arm_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	return _skin(p, n, ao)

static func _forearm_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(32.5, 80.0, -2.0), Vector3(34.5, 64.5, -1.5), 8.0, 5.6)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(33.5, 75.0, -0.5), Vector3(8.0, 7.5, 8.0)), 2.5)   # the forearm's bulk
	return d

static func _forearm_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	return _skin(p, n, ao)

static func _hand_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.round_box(p, Vector3(34.5, 57.0, 0.5), Vector3(5.0, 5.5, 5.5), 2.6)    # a big fist
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(34.5, 64.0, -1.5), Vector3(34.5, 60.0, -0.5), 5.0), 2.0)   # the wrist
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(30.0, 59.5, 4.0), Vector3(30.5, 55.5, 5.8), 2.0), 1.0)   # the thumb
	return d

static func _hand_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var c := _skin(p, n, ao)
	if p.z > 4.5 and p.y < 57.0 and fmod(p.y + 100.0, 2.6) < 0.6:
		c = c.darkened(0.18)                          # (between the fingers)
	return c

# ---------------------------------------------------------------- legs (his left; the right mirrored)
# (thick thighs, the shorts hugging them to y 51; boots right up to his knees)

const SHORTS_HEM := 51.0

static func _thigh_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(16.0, 53.0, 0.0), Vector3(17.5, 30.0, 0.0), 13.5, 9.5)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(18.0, 41.0, 4.0), Vector3(12.0, 12.0, 9.0)), 3.0)   # the quads
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(12.0, 41.0, 0.0), Vector3(7.0, 9.5, 8.0)), 2.5)    # inside of the thigh
	if p.y > SHORTS_HEM + 2.4:
		d -= 1.2                                      # (the shorts' leg, hugging)
	elif p.y > SHORTS_HEM:
		d -= 2.2                                      # (the rolled cuff)
	return d

static func _thigh_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	if p.y > SHORTS_HEM:
		var c := _denim(p, n, ao)
		if p.y < SHORTS_HEM + 2.4:
			c = c.lightened(0.12) if p.y > SHORTS_HEM + 1.2 else c.darkened(0.08)    # (the cuff's fold)
		return c
	return _skin(p, n, ao)

const BOOT_TOP := 27.0

static func _shin_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.cone_capsule(p, Vector3(17.5, 29.0, 0.0), Vector3(18.5, 12.0, -0.5), 8.0, 6.6)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(18.0, 30.0, 3.0), Vector3(5.5, 3.5, 4.5)), 1.5)   # the knee
	if p.y < BOOT_TOP:
		d -= 2.2 if p.y > BOOT_TOP - 2.5 else 1.4     # (the boot up to his knee, its top rolled)
	return d

static func _shin_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	if p.y < BOOT_TOP:
		var c := _boot(p, n, ao)
		if p.z > 4.0 and absf(p.x - 18.5) < 2.5 and fmod(p.y + 100.0, 2.2) < 0.8 and p.y < BOOT_TOP - 2.5:
			c = c.lightened(0.25)                     # (the laces)
		return c
	return _skin(p, n, ao)

static func _foot_sdf(p: Vector3) -> float:
	var d := VoxelSculpt.round_box(p, Vector3(19.0, 6.5, 3.0), Vector3(8.5, 5.5, 10.0), 3.2)
	d = VoxelSculpt.smin(d, VoxelSculpt.ellipsoid(p, Vector3(19.0, 5.5, 11.5), Vector3(8.6, 5.5, 7.0)), 2.5)   # the toe cap
	d = VoxelSculpt.smin(d, VoxelSculpt.capsule(p, Vector3(18.8, 8.0, -1.0), Vector3(18.6, 15.0, -0.8), 8.0), 2.5)   # the ankle
	d = minf(d, VoxelSculpt.round_box(p, Vector3(19.0, 1.3, 3.5), Vector3(9.4, 1.3, 11.8), 1.0))       # the sole: wider
	return maxf(d, -p.y)

static func _foot_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	if p.y < 2.6:
		return VoxelSculpt.ramp(BOOT, 0.05 + 0.3 * VoxelSculpt.lit(n, ao, 0.4))    # (the sole)
	var c := _boot(p, n, ao)
	if p.z > 5.0 and p.z < 11.0 and absf(p.x - 19.0) < 2.5 and p.y > 7.0 and fmod(p.z + 100.0, 2.2) < 0.8:
		c = c.lightened(0.25)                         # (the laces)
	return c
