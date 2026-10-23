class_name JaredBuild
extends RefCounted
## Juicy Jared sculpted (VoxelSculpt), from his sprites' front, three-quarter, side and back views: a big tanned head
## on a thick neck, a heavy jaw and brow, a bulbous nose, a big dark drooping moustache, short thick hair parted on
## his left, blue wrap-around shades. Model voxels (x his left, y up, z forward; the jared rig's pivots: head at
## (0, 110, 1)). Built so far: head, hair_classic, glasses (the rest from the model's files). Owned by the voxel
## session.

const SKIN := [Color8(109, 55, 55), Color8(176, 86, 73), Color8(206, 103, 79), Color8(233, 121, 84), Color8(244, 134, 90),
	Color8(252, 166, 111), Color8(253, 182, 128)]
const HAIR := [Color8(32, 18, 26), Color8(50, 28, 36), Color8(74, 40, 48), Color8(92, 56, 58), Color8(122, 80, 74)]
const FRAME := [Color8(20, 20, 30), Color8(42, 39, 53), Color8(70, 70, 86)]
const LENS := [Color8(4, 70, 150), Color8(10, 125, 205), Color8(4, 184, 243), Color8(120, 225, 255)]

static func part(name: String) -> Dictionary:
	match name:
		"head":
			return VoxelSculpt.fill(Vector3i(-16, 100, -13), Vector3i(19, 148, 26), _head_sdf, _head_paint)
		"hair_classic":
			return VoxelSculpt.fill(Vector3i(-17, 116, -16), Vector3i(20, 151, 22), _hair_sdf, _hair_paint)
		"glasses":
			return VoxelSculpt.fill(Vector3i(-17, 121, -5), Vector3i(19, 131, 25), _glasses_sdf, _glasses_paint)
	return {}

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
	var c := VoxelSculpt.ramp(SKIN.slice(2), 0.55 + 0.45 * clampf(VoxelSculpt.lit(n, ao * 0.5, 0.65), 0.0, 1.0))
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
	var outer := VoxelSculpt.smin(VoxelSculpt.ellipsoid(p, Vector3(0.5, 131.5, 2.8), Vector3(13.6, 14.8, 14.6)),
		VoxelSculpt.ellipsoid(p, Vector3(0.0, 139.0, 7.5), Vector3(10.0, 5.0, 8.0)), 3.0)    # a little fuller over the front
	var d := maxf(outer, _hairline(p) - p.y)
	d = maxf(d, -_skin_sdf(p))                        # (on the head, not in it)
	# the parting: a groove on his left, from the front back over the top
	if p.y > 137.0 and p.z > -6.0:
		d = maxf(d, -(absf(p.x - 6.0) - 0.45))
	return d

static func _hair_paint(p: Vector3, n: Vector3, ao: float) -> Color:
	var t := VoxelSculpt.lit(n, ao, 0.5)
	# combed: lines running front to back on top (away from the parting at the sides)
	var comb := VoxelSculpt.hash3(p.x * 1.0 + (p.y - 130.0) * 0.35, 0.0, 0.0)
	var clump := VoxelSculpt.noise3(Vector3(p.x * 1.6, p.y * 0.8, p.z * 0.35), 2.5)
	var c := VoxelSculpt.ramp(HAIR, 0.1 + 0.55 * t + 0.15 * comb + 0.3 * (clump - 0.5))
	if absf(p.x - 6.0) < 1.8 and p.y > 136.0:
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
