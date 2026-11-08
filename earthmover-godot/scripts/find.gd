class_name Find
extends RefCounted
## Something buried for the Buried find job, a surprise each time: an old car, a dinosaur's bones, or gold. It's a few solid
## shapes laid under the ground somewhere inside the pegs. The ground can't be dug through it (DirtSim.hard holds the dirt's floor
## at its top), a bucket that meets it stops, and the job's scored on how much of its top has been uncovered, less a little for
## each hard knock.

const KINDS := ["car", "bones", "gold"]
const NAMES := {"car": "AN OLD CAR", "bones": "DINOSAUR BONES", "gold": "GOLD"}
const TITLES := {"car": "OLD CAR", "bones": "DINOSAUR BONES", "gold": "GOLD"}
const COVER := 0.12       # m of dirt still lying on it that counts as uncovered: the last of it would come off with a brush
const SINK := 0.04        # m the dirt's floor stands below its top, so it's drawn over the dirt, not in it
const KNOCK_COST := 0.03  # off the score for each knock
const SEEN := 0.06        # uncovered this much, and it's plain what it is
const DEEP := {"car": 1.0, "bones": 0.8, "gold": 0.8}   # m of ground over its top to start with

var kind := "car"
var at := Vector2.ZERO    # its middle, on the ground
var angle := 0.0          # which way it lies, radians about straight up
var base := 0.0           # m: the y of its underside
## Its shapes, in its own space: x along it, y up from its underside. Each is [middle Vector3, size Vector3, colour hex, shape,
## turn about y]. "box", "wheel" (a cylinder across z) or "lump" (a rough rock, round in x and z).
var parts: Array = []
var radius := 1.0         # m: it all lies within this of `at`
var height := 0.0         # m from its underside to its top
var seen := false         # free play's: uncovered enough to see what it is, and counted
var cells := PackedInt32Array()   # the cells it lies under
var tops := PackedInt32Array()    # mm: its top over each of those
var knocks := 0
var _index := {}          # cell -> where it is in `cells`

## One of them, picked by `seed`, laid somewhere inside `patch` where the ground's `ground_y`. `only` picks which, for checks.
static func make(seed: int, patch: Rect2, ground_y: float, only := "") -> Find:
	var f := Find.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	f.kind = only if only != "" else KINDS[rng.randi() % KINDS.size()]
	match f.kind:
		"car":
			f._car()
		"bones":
			f._bones()
		_:
			f._gold(rng)
	for p: Array in f.parts:
		var c: Vector3 = p[0]
		var s: Vector3 = p[1]
		f.height = maxf(f.height, c.y + s.y * 0.5)
		f.radius = maxf(f.radius, Vector2(absf(c.x) + s.x * 0.5, absf(c.z) + s.z * 0.5).length())
	f.angle = rng.randf() * TAU
	var room := patch.grow(-(f.radius + 1.0))
	f.at = Vector2(rng.randf_range(room.position.x, room.end.x), rng.randf_range(room.position.y, room.end.y)) if room.has_area() else patch.get_center()
	f.base = ground_y - DEEP[f.kind] - f.height
	return f

## Sets it under the ground where it is now, its top as deep as usual under the lowest ground over it: free play's ground isn't
## flat, and none of it may show till it's dug down to.
func sink_under(sim: DirtSim) -> void:
	var low := INF
	var x := -radius
	while x <= radius:
		var z := -radius
		while z <= radius:
			if x * x + z * z <= radius * radius:
				low = minf(low, sim.height_at(at + Vector2(x, z)))
			z += 0.5
		x += 0.5
	base = low - DEEP[kind] - height

## Puts it in the ground: the dirt over it can be dug down to its top and no further.
func lay(sim: DirtSim) -> void:
	cells.clear()
	tops.clear()
	_index.clear()
	var a := DirtSim.cell_of(at - Vector2.ONE * radius)
	var b := DirtSim.cell_of(at + Vector2.ONE * radius)
	for j in range(maxi(a.y, 1), mini(b.y + 1, DirtSim.CELLS - 1)):
		for i in range(maxi(a.x, 1), mini(b.x + 1, DirtSim.CELLS - 1)):
			var p := Vector2(i, j) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M
			var top := top_at(p)
			if is_nan(top):
				continue
			var n := j * DirtSim.CELLS + i
			_index[n] = cells.size()
			cells.append(n)
			tops.append(int(top * 1000.0))
	# Where it steps down inside itself (a car's cabin to its bonnet), the dirt's floor takes the lower step a cell early. The ground's
	# drawn as a slope from one cell to the next, so this puts that slope inside the taller part, out of sight, not over the lower one.
	for k in cells.size():
		var n := cells[k]
		var low := tops[k]
		for m: int in [n - 1, n + 1, n - DirtSim.CELLS, n + DirtSim.CELLS]:
			if _index.has(m):
				low = mini(low, tops[_index[m]])
		sim.hard[n] = low - int(SINK * 1000.0)

## Its top at a spot on the ground, in m, or NAN where it isn't.
func top_at(p: Vector2) -> float:
	# Basis(UP, a) turns a spot on the ground by -a, as a Vector2 sees it: so the world's taken back into its own space by -angle.
	var q := (p - at).rotated(-angle)
	var top := NAN
	for part: Array in parts:
		var c: Vector3 = part[0]
		var s: Vector3 = part[1]
		var r := (q - Vector2(c.x, c.z)).rotated(-float(part[4]))
		if absf(r.x) <= s.x * 0.5 and absf(r.y) <= s.z * 0.5:
			var y := base + c.y + s.y * 0.5
			top = y if is_nan(top) else maxf(top, y)
	return top

## How much of its top has the dirt off it, 0 to 1.
func uncovered(sim: DirtSim) -> float:
	if cells.is_empty():
		return 0.0
	var clear := 0
	var leave := int(COVER * 1000.0)
	for k in cells.size():
		var n := cells[k]
		if sim.bed[n] + sim.soil[n] <= tops[k] + leave:
			clear += 1
	return float(clear) / cells.size()

## What it's worth: how much is uncovered, less the knocks.
func score(sim: DirtSim) -> float:
	return maxf(uncovered(sim) - knocks * KNOCK_COST, 0.0)

## How far `p` is from it, in m: from the nearest bit of its top.
func distance(p: Vector3) -> float:
	var best := INF
	for k in cells.size():
		var n := cells[k]
		var c := Vector3((n % DirtSim.CELLS) * DirtSim.CELL_M - DirtSim.HALF_M, tops[k] * 0.001, (n / DirtSim.CELLS) * DirtSim.CELL_M - DirtSim.HALF_M)
		best = minf(best, c.distance_squared_to(p))
	return sqrt(best)

## Its look, in its own space: the node it's on goes at `at`, `base` and `angle`.
func mesh() -> ArrayMesh:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for part: Array in parts:
		var c: Vector3 = part[0]
		var s: Vector3 = part[1]
		var col := Props.c(part[2])
		match part[3]:
			"wheel":
				kit.cone(c - Vector3(0.0, 0.0, s.z * 0.5), c + Vector3(0.0, 0.0, s.z * 0.5), s.x * 0.5, s.x * 0.5, 10, col)
			"lump":
				# Fat in the middle and rounded off at the top, rough all over.
				var mid := c + Vector3(0.0, s.y * 0.05, 0.0)
				kit.cone(c - Vector3(0.0, s.y * 0.5, 0.0), mid, s.x * 0.4, s.x * 0.5, 7, col, 0.18, rng)
				kit.cone(mid, c + Vector3(0.0, s.y * 0.5, 0.0), s.x * 0.5, s.x * 0.26, 7, col, 0.18, rng)
			_:
				kit.box(c, s, col, Basis(Vector3.UP, -float(part[4])))
	return kit.mesh()

## Where it goes in the world.
func place() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -angle), Vector3(at.x, base, at.y))

func _part(c: Vector3, s: Vector3, hex: String, shape := "box", turn := 0.0) -> void:
	parts.append([c, s, hex, shape, turn])

## An old sedan gone to rust, lost in a flood and silted over: faded paint, a rusty roof and bonnet, flat tyres.
func _car() -> void:
	const PAINT := "#5d7a86"
	const RUST := "#6b3b25"
	const GLASS := "#2b3a42"
	_part(Vector3(0.0, 0.62, 0.0), Vector3(4.3, 0.55, 1.72), PAINT)
	_part(Vector3(1.6, 0.9, 0.25), Vector3(0.6, 0.02, 0.7), RUST)
	_part(Vector3(-1.85, 0.9, -0.3), Vector3(0.45, 0.02, 0.6), RUST)
	_part(Vector3(0.7, 0.6, 0.865), Vector3(1.2, 0.3, 0.03), RUST)
	_part(Vector3(-1.2, 0.55, -0.865), Vector3(0.9, 0.25, 0.03), RUST)
	_part(Vector3(-0.25, 1.12, 0.0), Vector3(2.1, 0.46, 1.56), PAINT)
	_part(Vector3(-0.5, 1.355, -0.2), Vector3(0.8, 0.02, 0.6), RUST)
	for side: float in [-1.0, 1.0]:
		_part(Vector3(-0.25, 1.13, side * 0.785), Vector3(1.85, 0.32, 0.03), GLASS)
		_part(Vector3(2.165, 0.7, side * 0.58), Vector3(0.05, 0.16, 0.24), "#d9d4b8")
		_part(Vector3(side * 2.18, 0.45, 0.0), Vector3(0.08, 0.16, 1.8), "#9a9fa3")
		for end: float in [-1.0, 1.0]:
			_part(Vector3(end * 1.35, 0.33, side * 0.78), Vector3(0.66, 0.66, 0.24), "#262626", "wheel")
	_part(Vector3(0.83, 1.12, 0.0), Vector3(0.04, 0.36, 1.4), GLASS)
	_part(Vector3(-1.33, 1.12, 0.0), Vector3(0.04, 0.36, 1.4), GLASS)

## A big meat-eater's skeleton, lying flat as it fell: skull, neck and back, ribs, hips, legs splayed out, and a long tail.
func _bones() -> void:
	const BONE := "#e6dbc0"
	const OLD := "#cdbf9c"
	_part(Vector3(3.95, 0.3, 0.0), Vector3(1.15, 0.5, 0.62), BONE)
	_part(Vector3(4.65, 0.24, 0.0), Vector3(0.55, 0.36, 0.45), BONE)
	_part(Vector3(4.1, 0.1, 0.4), Vector3(1.3, 0.16, 0.18), OLD, "box", 0.15)
	_part(Vector3(3.8, 0.56, 0.17), Vector3(0.22, 0.02, 0.18), "#6b5b45")
	var x := 3.3
	while x > 2.5:
		_part(Vector3(x, 0.22, 0.0), Vector3(0.26, 0.3, 0.28), BONE)
		x -= 0.35
	x = 2.4
	while x > -0.7:
		_part(Vector3(x, 0.2, 0.0), Vector3(0.3, 0.36, 0.34), BONE)
		x -= 0.4
	_part(Vector3(-0.55, 0.26, 0.0), Vector3(0.9, 0.42, 0.95), OLD)
	x = -1.1
	var k := 0
	while x > -4.7:
		var thin := lerpf(0.3, 0.12, (-1.1 - x) / 3.6)
		_part(Vector3(x, thin * 0.6, 0.35 * sin(k * 0.55)), Vector3(thin, thin, thin), BONE)
		x -= 0.38
		k += 1
	x = 0.1
	while x < 2.2:
		for side: float in [-1.0, 1.0]:
			_part(Vector3(x - 0.12, 0.1, side * 0.62), Vector3(0.1, 0.12, 1.0), BONE, "box", side * 0.25)
		x += 0.4
	for side: float in [-1.0, 1.0]:
		_part(Vector3(-0.4, 0.14, side * 1.05), Vector3(0.26, 0.24, 1.1), OLD, "box", side * 0.4)
		_part(Vector3(-0.15, 0.12, side * 1.95), Vector3(0.2, 0.2, 1.0), BONE, "box", -side * 0.3)
		_part(Vector3(0.2, 0.08, side * 2.5), Vector3(0.55, 0.14, 0.35), OLD)
		_part(Vector3(2.2, 0.1, side * 0.95), Vector3(0.12, 0.12, 0.6), BONE, "box", side * 0.5)
		_part(Vector3(2.4, 0.07, side * 1.25), Vector3(0.2, 0.1, 0.18), OLD)

## Gold: one great nugget in a lump of quartz, and a few small ones scattered round it.
func _gold(rng: RandomNumberGenerator) -> void:
	const GOLD := "#f1c232"
	const DEEP_GOLD := "#d4a017"
	const QUARTZ := "#ece9e0"
	_part(Vector3(0.0, 0.32, 0.0), Vector3(1.4, 0.64, 1.1), GOLD, "lump")
	_part(Vector3(0.35, 0.45, 0.2), Vector3(0.8, 0.5, 0.7), DEEP_GOLD, "lump")
	_part(Vector3(-0.4, 0.3, -0.25), Vector3(0.75, 0.55, 0.6), GOLD, "lump")
	_part(Vector3(-1.2, 0.25, 0.6), Vector3(0.9, 0.5, 0.75), QUARTZ, "lump")
	_part(Vector3(1.1, 0.2, -0.8), Vector3(0.7, 0.4, 0.65), QUARTZ, "lump")
	for i in 5:
		var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / 5.0
		var d := rng.randf_range(1.6, 2.6)
		var s := rng.randf_range(0.35, 0.55)
		_part(Vector3(cos(a) * d, s * 0.5, sin(a) * d), Vector3(s, s, s), GOLD if i % 2 == 0 else DEEP_GOLD, "lump")
