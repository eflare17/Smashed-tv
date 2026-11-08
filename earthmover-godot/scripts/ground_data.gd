class_name GroundData
extends RefCounted
## The look test's made-up dirt grid: a pit, a dumped pile and a scraped dozer run, as the real simulation's grid would
## hold them (a height and a set of material amounts at each corner). Nothing moves yet. These numbers only set the scene.

static var N := 256             # cells a side: DirtSim.set_world() changes these three for the big site
const CELL := 0.25              # metres
static var HALF := 32.0         # metres from the middle to the edge
static var SIDE := 257          # corners a side

const PIT := Vector2(-9.5, -4.0)
const PIT_R := Vector2(11.0, 8.0)
const PIT_DEEP := 3.4
const PIT_SLOPE := 6.6          # metres the wall takes to come down: no steeper than loose soil holds, about 34 degrees
const PILE := Vector2(12.0, 7.5)
const PILE_R := 6.2
const PILE_HIGH := 3.9
const RUN_A := Vector2(-6.0, -4.0)      # the scraped run, from down in the pit to the pile
const RUN_B := Vector2(8.0, 4.5)
const RUN_W := 2.9              # half the width

var heights := PackedFloat32Array()
var loose_depth := PackedFloat32Array()
var data := PackedByteArray()   # RGBA per corner: loose soil, rock, packed soil, shading in hollows

static func at(i: int, j: int) -> int:
	return j * SIDE + i

## With a site given it's a plain block for a job: flat there, a painted driveway, a sealed road, and none of the pit and pile.
## With `paddock`, it's the big site: open rolling ground with no pit or pile, and flat where `site` is given.
## With `mine`, it's the mine: see _mine().
func _init(site := Rect2(), paint := Rect2(), road := Rect2(), paddock := false, mine := false) -> void:
	var lumps := FastNoiseLite.new()
	lumps.seed = 7
	lumps.frequency = 0.035
	lumps.fractal_octaves = 3
	var rag := FastNoiseLite.new()
	rag.seed = 21
	rag.frequency = 0.18
	rag.fractal_octaves = 2
	heights.resize(SIDE * SIDE)
	loose_depth.resize(SIDE * SIDE)
	data.resize(SIDE * SIDE * 4)
	var loose := PackedFloat32Array()
	var rock := PackedFloat32Array()
	var packed := PackedFloat32Array()
	loose.resize(SIDE * SIDE)
	rock.resize(SIDE * SIDE)
	packed.resize(SIDE * SIDE)
	var run := RUN_B - RUN_A
	var run_dir := run.normalized()
	var run_side := Vector2(-run_dir.y, run_dir.x)
	for j in SIDE:
		for i in SIDE:
			var p := Vector2(-HALF + i * CELL, -HALF + j * CELL)
			var edge: float = maxf(abs(p.x), abs(p.y))
			var fade := 1.0 - smoothstep(HALF - 8.0, HALF - 1.0, edge)
			var h := lumps.get_noise_2dv(p) * 1.5 * fade
			var ragged := rag.get_noise_2dv(p)
			if mine:
				var n_m := at(i, j)
				var got := _mine(p, lumps, ragged, fade)
				heights[n_m] = got[0]
				loose_depth[n_m] = got[1]
				loose[n_m] = got[2]
				packed[n_m] = got[3]
				continue
			if paddock:
				# Long low rises, a paddock's worth, flat where the job is.
				var hp := (lumps.get_noise_2dv(p * 0.55) * 2.6 + 0.45 * sin(p.x * 0.07 + 0.6) * cos(p.y * 0.05)) * fade
				if site.has_area():
					var off_p := Vector2(maxf(maxf(site.position.x - p.x, p.x - site.end.x), 0.0), maxf(maxf(site.position.y - p.y, p.y - site.end.y), 0.0)).length()
					hp *= smoothstep(2.0, 14.0, off_p)
				heights[at(i, j)] = hp
				continue
			if site.has_area():
				var off := Vector2(maxf(maxf(site.position.x - p.x, p.x - site.end.x), 0.0), maxf(maxf(site.position.y - p.y, p.y - site.end.y), 0.0)).length()
				var at_n := at(i, j)
				heights[at_n] = h * smoothstep(2.0, 12.0, off)
				packed[at_n] = 1.0 if paint.has_point(p) else 0.0
				rock[at_n] = 1.0 if road.has_point(p + Vector2(0.0, ragged * 0.3)) else 0.0
				continue
			var soil := 0.0
			var stone := 0.0
			var pack := 0.0
			var lay := 0.0      # how much of this height is loose soil on top

			# The pit: distance in from an ellipse's edge, ragged, walls at the angle soil holds.
			var q := (p - PIT) / PIT_R
			var into := (1.0 - q.length()) * minf(PIT_R.x, PIT_R.y)
			var painted := into + ragged * 1.1
			if painted > -0.7:
				soil = maxf(soil, smoothstep(-0.7, -0.1, painted))
			var cut := into + ragged * 0.15
			if cut > 0.0:
				var k: float = clampf(cut / PIT_SLOPE, 0.0, 1.0)
				k = k * k * (3.0 - 2.0 * k) * 0.45 + k * 0.55
				h = lerpf(h, h * 0.25, k) - PIT_DEEP * k
				stone = smoothstep(0.72, 0.9, k + ragged * 0.25)

			# The scraped run: lowered a little, packed, with a rut under each track. It starts down in the pit, so it
			# comes up out of it as a ramp.
			var along := (p - RUN_A).dot(run_dir)
			var across := (p - RUN_A).dot(run_side)
			var inside: float = clampf(1.0 - abs(across) / RUN_W, 0.0, 1.0) * smoothstep(-2.0, 0.5, along) * (1.0 - smoothstep(run.length() - 1.0, run.length() + 1.2, along))
			if inside > 0.0:
				var ramp := smoothstep(0.0, 5.0, along)
				h -= 0.16 * smoothstep(0.0, 0.25, inside) * ramp
				var track: float = minf(abs(abs(across) - 1.15), 1.0)
				h -= 0.16 * (1.0 - smoothstep(0.1, 0.45, track)) * smoothstep(0.05, 0.3, inside) * ramp
				var worn := smoothstep(0.0, 0.14, inside)
				# Soil and packed ground share a cell: together they say how bare it is, between them which it looks like.
				pack = maxf(pack, worn)
				soil *= 1.0 - worn
				stone *= 1.0 - worn

			# The dumped pile, on top of everything, burying the grass where it lands.
			var from_pile := p.distance_to(PILE) + ragged * 0.5
			if from_pile < PILE_R + 0.8:
				soil = maxf(soil, smoothstep(PILE_R + 0.8, PILE_R, from_pile))
				pack *= 1.0 - soil
				if from_pile < PILE_R:
					var c := 1.0 - from_pile / PILE_R
					var dumped := PILE_HIGH * minf(c * 1.12, 0.62 + c * 0.42)
					h += dumped
					lay += dumped

			# A little windrow of soil left on the run.
			var ahead := (p - windrow_spot()).dot(run_dir)
			var beside := (p - windrow_spot()).dot(run_side)
			var windrow: float = (1.0 - smoothstep(0.0, 2.3, abs(beside))) * (1.0 - smoothstep(0.0, 0.85, abs(ahead - 3.7)))
			if windrow > 0.0:
				h += 0.7 * windrow
				lay += 0.7 * windrow
				soil = maxf(soil, smoothstep(0.02, 0.2, windrow))
				pack *= 1.0 - soil
			# Spilled trails off the sides of the blade.
			var spill: float = (1.0 - smoothstep(0.0, 0.7, abs(abs(across) - RUN_W - 0.1))) * smoothstep(-2.0, 0.5, along) * (1.0 - smoothstep(run.length() - 2.0, run.length(), along))
			if spill > 0.0:
				h += 0.2 * spill
				lay += 0.2 * spill
				soil = maxf(soil, smoothstep(0.02, 0.3, spill + ragged * 0.2))

			var n := at(i, j)
			heights[n] = h
			loose_depth[n] = lay
			loose[n] = soil
			rock[n] = stone
			packed[n] = pack

	_soften(2)
	_shade_hollows(loose, rock, packed)

## Takes the sharp edges off the made-up shapes, as settled soil would have.
func _soften(passes: int) -> void:
	for _pass in passes:
		var was := heights.duplicate()
		var was_lay := loose_depth.duplicate()
		for j in range(1, N):
			for i in range(1, N):
				var n := at(i, j)
				heights[n] = (was[n] * 4.0 + was[n - 1] + was[n + 1] + was[n - SIDE] + was[n + SIDE]) / 8.0
				loose_depth[n] = (was_lay[n] * 4.0 + was_lay[n - 1] + was_lay[n + 1] + was_lay[n - SIDE] + was_lay[n + SIDE]) / 8.0

## Hands this made-up ground to the simulation: firm ground, loose soil on top, and rock where the look says rock.
func fill_sim(sim: DirtSim) -> void:
	for n in heights.size():
		var loose_mm := int(round(loose_depth[n] * 1000.0))
		sim.soil[n] = loose_mm
		sim.bed[n] = int(round(heights[n] * 1000.0)) - loose_mm
		sim.rock[n] = 1 if data[n * 4 + 1] > 128 else 0
	sim.mark_start_ground()

## How far a corner sits below its surroundings, at two sizes (a rut, a hole), goes in the data texture as shading. A real
## simulation would redo this only for the chunks that changed.
func _shade_hollows(loose: PackedFloat32Array, rock: PackedFloat32Array, packed: PackedFloat32Array) -> void:
	const RINGS := [[3, 0.45], [8, 1.2], [18, 2.4]]
	for j in SIDE:
		for i in SIDE:
			var n := at(i, j)
			var dark := 0.0
			for ring in RINGS:
				var r: int = ring[0]
				var total := 0.0
				for s in [[r, 0], [-r, 0], [0, r], [0, -r]]:
					total += heights[at(clampi(i + s[0], 0, N), clampi(j + s[1], 0, N))]
				var d := r * 7 / 10
				for s in [[d, d], [-d, d], [d, -d], [-d, -d]]:
					total += heights[at(clampi(i + s[0], 0, N), clampi(j + s[1], 0, N))]
				dark = maxf(dark, (total / 8.0 - heights[n]) / float(ring[1]))
			var ao: float = 1.0 - clampf(dark, 0.0, 1.0) * 0.62
			var b := n * 4
			data[b] = int(clampf(loose[n], 0.0, 1.0) * 255.0)
			data[b + 1] = int(clampf(rock[n], 0.0, 1.0) * 255.0)
			data[b + 2] = int(clampf(packed[n], 0.0, 1.0) * 255.0)
			data[b + 3] = int(ao * 255.0)

func height_at(p: Vector2) -> float:
	var g := (p + Vector2(HALF, HALF)) / CELL
	var i := clampi(int(floor(g.x)), 0, N - 1)
	var j := clampi(int(floor(g.y)), 0, N - 1)
	var fx: float = clampf(g.x - i, 0.0, 1.0)
	var fy: float = clampf(g.y - j, 0.0, 1.0)
	var a: float = lerp(heights[at(i, j)], heights[at(i + 1, j)], fx)
	var b: float = lerp(heights[at(i, j + 1)], heights[at(i + 1, j + 1)], fx)
	return lerp(a, b, fy)

static func windrow_spot() -> Vector2:
	return RUN_A.lerp(RUN_B, 0.55)

## On open ground with a good run at the pile, so the first push of the stick gets it moving.
static func dozer_spot() -> Vector2:
	return Vector2(14.0, -14.0)

## The excavator starts between the pile and the pit, so it can dig the one and swing round to fill the other.
static func digger_spot() -> Vector2:
	return Vector2(2.0, 7.0)

## The truck parks where the excavator can reach its tray with a swing to the right.
static func truck_spot() -> Vector2:
	return Vector2(0.5, 14.5)

static func bobcat_spot() -> Vector2:
	return Vector2(8.5, -1.5)

## The wheelbarrow, by the cracker dust, out of the dozer's way.
static func barrow_spot() -> Vector2:
	return Vector2(18.0, -9.5)

## The scout ute, parked on the open side of the pit.
static func ute_spot() -> Vector2:
	return Vector2(-18.0, 17.0)

## The Dingo starts on open firm ground, for trenching.
static func dingo_spot() -> Vector2:
	return Vector2(21.0, -7.0)

static func dozer_dir() -> Vector2:
	return (PILE - dozer_spot()).normalized()

func height_texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_RF, heights.to_byte_array()))

func data_texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_RGBA8, data))

## ---------------------------------------------------------------- the mine
## A stepped pit with a ramp cut down its south side, a haul road from the parking area past the top of the ramp to the dump,
## windrows along the road and along the ramp's open edge, and a bund round the lot. Each cut is a level with faces rising from
## it at the batter, and the ground is whichever is lowest, so the ramp runs down onto the first bench and then into the floor.
const MINE_BENCH := Rect2(-10.0, -12.0, 44.0, 38.0)     # the first bench's level ground: x -10 to 34, z -12 to 26
const MINE_FLOOR := Rect2(-2.0, -4.0, 28.0, 22.0)        # the pit floor: x -2 to 26, z -4 to 18
const MINE_STEP := 2.5          # m each bench goes down
const MINE_BATTER := 1.5        # m up for each m across, on a cut face
const MINE_RAMP_Z := -10.0      # the ramp's middle: it runs along the pit's south side, coming down eastward
const MINE_RAMP_HALF := 5.5
const MINE_RAMP := [Vector2(-25.0, 0.0), Vector2(-10.0, -2.5), Vector2(-4.0, -2.5), Vector2(10.0, -5.0), Vector2(16.0, -5.0)]   # x and level
const MINE_ROAD := Rect2(-39.0, -30.0, 14.0, 55.0)      # the haul road, x -39 to -25
const MINE_PARK := Rect2(-41.0, -41.0, 26.0, 14.0)
const MINE_DUMP := Rect2(-41.0, 22.0, 22.0, 19.0)
const MINE_WINDROWS := [[Vector2(-40.3, -26.0), Vector2(-40.3, 21.0)], [Vector2(-23.7, -1.5), Vector2(-23.7, 21.0)], [Vector2(-23.7, -27.0), Vector2(-23.7, -17.5)], [Vector2(-4.0, -6.0), Vector2(6.0, -6.0)]]
const MINE_WINDROW_HIGH := 1.0
const MINE_WINDROW_HALF := 1.6
const MINE_BUND_IN := 3.4       # m in from the edge, all round
const MINE_BUND_HIGH := 2.2

## How far a point is outside a rectangle, or 0 inside it.
static func _outside(p: Vector2, r: Rect2) -> float:
	return Vector2(maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0), maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)).length()

## The ramp's level at x along it.
static func mine_ramp_level(x: float) -> float:
	var pts: Array = MINE_RAMP
	if x <= pts[0].x:
		return 0.0
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		if x <= b.x:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return pts[pts.size() - 1].y

## The firm ground of the pit and ramp at a point: 0 outside them.
static func mine_cut(p: Vector2) -> float:
	var bench := -MINE_STEP + MINE_BATTER * _outside(p, MINE_BENCH)
	var floor_h := -2.0 * MINE_STEP + MINE_BATTER * _outside(p, MINE_FLOOR)
	var last: float = MINE_RAMP[MINE_RAMP.size() - 1].x
	var off := Vector2(maxf(p.x - last, 0.0), maxf(absf(p.y - MINE_RAMP_Z) - MINE_RAMP_HALF, 0.0)).length()
	var ramp := mine_ramp_level(minf(p.x, last)) + MINE_BATTER * off
	return minf(minf(0.0, bench), minf(floor_h, ramp))

## Whether a point's on the ramp's running surface.
static func on_mine_ramp(p: Vector2) -> bool:
	return p.x > MINE_RAMP[0].x - 1.0 and p.x < MINE_RAMP[MINE_RAMP.size() - 1].x + 1.0 and absf(p.y - MINE_RAMP_Z) < MINE_RAMP_HALF

## One corner of the mine: its height, how much of that is loose, and how it's painted (soil, packed).
func _mine(p: Vector2, lumps: FastNoiseLite, ragged: float, fade: float) -> Array:
	var cut := mine_cut(p)
	# Low red rises round about, flattened near anything that's been made.
	var near := minf(minf(_outside(p, MINE_BENCH) - 2.0, _outside(p, MINE_ROAD)), minf(_outside(p, MINE_PARK), _outside(p, MINE_DUMP)))
	near = minf(near, _outside(p, mine_ramp_rect()))
	var rise := (lumps.get_noise_2dv(p * 0.7) * 1.1 + 0.3 * sin(p.x * 0.09) * cos(p.y * 0.07)) * fade * smoothstep(3.0, 12.0, near)
	var edge: float = maxf(absf(p.x), absf(p.y))
	var bund := MINE_BUND_HIGH * (0.5 + 0.5 * cos(PI * clampf(absf(edge - (HALF - MINE_BUND_IN)) / 2.7, 0.0, 1.0)))
	var lay := 0.0
	for w: Array in MINE_WINDROWS:
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		var along := (b - a).normalized()
		var t := (p - a).dot(along)
		var across := absf((p - a).dot(Vector2(-along.y, along.x)))
		var ends := smoothstep(-1.5, 0.5, t) * (1.0 - smoothstep(a.distance_to(b) - 0.5, a.distance_to(b) + 1.5, t))
		var shape := 0.5 + 0.5 * cos(PI * clampf(across / MINE_WINDROW_HALF, 0.0, 1.0))
		lay = maxf(lay, MINE_WINDROW_HIGH * shape * ends)
	var h := cut + rise + bund + lay
	var soil := 0.0
	if cut < -0.05 + ragged * 0.04:
		soil = 1.0
	soil = maxf(soil, smoothstep(0.03, 0.2, lay + bund * 0.4 + ragged * 0.05))
	var pack := 0.0
	var worked := minf(minf(_outside(p, MINE_ROAD), _outside(p, MINE_PARK)), _outside(p, MINE_DUMP))
	if worked < 0.3 + ragged * 0.6 or on_mine_ramp(p + Vector2(0.0, ragged * 0.5)):
		pack = 1.0
	pack *= 1.0 - smoothstep(0.03, 0.2, lay)
	if pack > 0.0:
		soil *= 1.0 - pack
	return [h, lay, soil, pack]

## The ramp's running surface as a rectangle on the ground.
static func mine_ramp_rect() -> Rect2:
	var first: float = MINE_RAMP[0].x
	var last: float = MINE_RAMP[MINE_RAMP.size() - 1].x
	return Rect2(first, MINE_RAMP_Z - MINE_RAMP_HALF, last - first, MINE_RAMP_HALF * 2.0)
