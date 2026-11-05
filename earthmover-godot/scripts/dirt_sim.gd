class_name DirtSim
extends RefCounted
## The dirt, and nothing but the dirt: no nodes, no drawing, so the tests drive it alone and it can move to C++ later.
##
## A grid of cells, each a column of firm ground (bed) with loose soil on top, in whole millimetres. Soil only ever moves
## as whole numbers from one place to another, so none can be lost to rounding. It's somewhere in the ground, in the store
## (what the player has taken and not put back), or in the air (falling chunks). total() adds it all up.
##
## Only the parts of the grid where something moved are worked on: a chunk goes to sleep once nothing in it moves. Work
## over the time budget waits for the next tick, so a big slide goes slower rather than stalling the game.

const CELLS := 257              # cells a side
const CELL_M := 0.25
const HALF_M := 32.0
const CHUNK := 16               # cells a chunk side
const CHUNKS := 17              # chunks a side
const MM := 1000.0
const TRACK_RIDE := 0.55         # how much of the loose soil under a track holds it up
const HEAP_MM := 1600           # how high a blade heaps soil above its cutting edge: a load piled a bit over the blade's top
const DRAG_MOUTH := 300         # mm a back-dragged bucket can shift off a cell at once
const DRAG_HEAP := 320          # mm it heaps what it's carrying, above what it leaves behind
const SIDE_LOWER_MM := 900      # the ridge left past each end of the blade stands this much lower than the heap in front
const SPILL_AHEAD: Array[float] = [0.4, 0.6, 0.9, 1.3, 1.8, 2.4, 3.0]   # m ahead of the blade it lays soil, nearest first
const SPILL_SIDE: Array[float] = [0.15, 0.4, 0.7]                       # m past the blade's end it then rolls off, close in
const TRACK_SINK := 200        # mm, the deepest a track goes into it: deep soil holds a machine up, it doesn't swallow it
const RIM := 6                  # cells round the edge that soil never reaches, so it stops at the site fence

## How much higher a cell may stand than its neighbour, in mm over one cell's 250 mm.
const SOIL_LIMIT := 168         # about 34 degrees: loose soil slides beyond this
const BED_LIMIT := 433          # about 60 degrees: a firm wall gives way beyond this, turning loose as it does
const SOIL_LIMIT_CORNER := 238  # the same angles over a corner neighbour, 1.41 cells away
const DUST_LIMIT := 250         # about 45 degrees: cracker dust is coarse and stands steeper than soil
const DUST_LIMIT_CORNER := 354
const BED_LIMIT_CORNER := 612
const CUT_WALL_MM := 1700        # how high a firm wall beside a clean cut stands before it gives way
const BED_FLOOR := -7000        # nothing digs below this, 7 m down
const TOP := 9000               # soil stops piling up here, 9 m up (the drawn ground's limit)

## Falling chunks: a set number, as in Kev's game, but any over the limit land at once rather than vanish.
const AIR_MAX := 300
const GRAVITY := 9.8

var bed := PackedInt32Array()
var soil := PackedInt32Array()
var rock := PackedByteArray()   # 1: this cell's bed is rock, which never gives way
var store := 0                  # mm of soil on one cell's area, held by the player
var in_air := 0
var held := 0                   # mm of soil on one cell's area, in a machine's bucket

## Things that can catch falling soil, such as a truck's tray: each has catch_soil(pos, amt) -> bool. What's caught moves to `held`.
var catchers: Array = []
## 1: this cell was cut clean by a trencher, so the firm walls beside it stand far steeper than they otherwise would.
var clean_cut := PackedByteArray()
## How much of each cell's loose soil is cracker dust, in mm: never more than the soil there. It moves in step with the soil.
var dust := PackedInt32Array()
## The dust in the soil the last take() got. What moved it hands this on to put(), so dust stays dust.
var last_dust := 0
var air_dust := PackedInt32Array()

## How high the ground stood to begin with, in mm. CUT measures its depth from this, so going over a strip twice doesn't go deeper.
var start_ground := PackedInt32Array()

var air_pos := PackedVector3Array()
var air_vel := PackedVector3Array()
var air_amt := PackedInt32Array()

var _awake := PackedByteArray()
var _queue := PackedInt32Array()
var _queue_at := 0
var _flip := false
var _flip_set := false
var _tick := 0
## Chunk number -> true: chunks changed since the last time the drawing asked.
var dirty: Dictionary = {}
var moved_last_tick := 0
var loose_total_cached := 0
var chunks_left := 0

## Dug ground takes more room loose than it did firm, so a trench's dirt more than fills it again. The trencher's
## dirt swells by this much, and what it's made is counted here.
const SWELL_PCT := 35
## Raking leftover soil into a trench leaves this much on the cells it comes from.
const RAKE_KEEP_MM := 20
var swelled := 0

func _init() -> void:
	bed.resize(CELLS * CELLS)
	soil.resize(CELLS * CELLS)
	rock.resize(CELLS * CELLS)
	clean_cut.resize(CELLS * CELLS)
	dust.resize(CELLS * CELLS)
	_awake.resize(CHUNKS * CHUNKS)

## Everything there is, wherever it is, less what digging has made by loosening firm ground: so this never changes.
func total() -> int:
	var t := store + in_air + held - swelled
	for n in bed.size():
		t += bed[n] + soil[n]
	return t

## All the dust on the ground and in the air. Machines keep count of what they're carrying.
func dust_total() -> int:
	var t := 0
	for n in dust.size():
		t += dust[n]
	for d in air_dust:
		t += d
	return t

## Tips a heap of cracker dust here, as steep as loose soil stands. Returns how much it really put down, in mm on one cell's area.
func add_dust_pile(c: Vector2, m3: float) -> int:
	var r := pow(m3 / 0.628, 1.0 / 3.0)
	var high := r * 0.6 * MM
	var at := cell_of(c)
	var reach := int(ceil(r / CELL_M))
	var put_down := 0
	for j in range(at.y - reach, at.y + reach + 1):
		for i in range(at.x - reach, at.x + reach + 1):
			var d := Vector2(i - at.x, j - at.y).length() * CELL_M / r
			if d >= 1.0:
				continue
			var mm := int(high * (1.0 - d))
			put(i, j, mm, mm)
			put_down += mm
	return put_down

func loose_total() -> int:
	var t := 0
	for n in soil.size():
		t += soil[n]
	return t

static func to_m3(mm: int) -> float:
	return mm / MM * CELL_M * CELL_M

static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(round((p.x + HALF_M) / CELL_M)), int(round((p.y + HALF_M) / CELL_M)))

func height_mm(i: int, j: int) -> int:
	var n := clampi(j, 0, CELLS - 1) * CELLS + clampi(i, 0, CELLS - 1)
	return bed[n] + soil[n]

## The ground's height in metres, smooth between cells.
func height_at(p: Vector2) -> float:
	var gx := clampf((p.x + HALF_M) / CELL_M, 0.0, CELLS - 1.001)
	var gy := clampf((p.y + HALF_M) / CELL_M, 0.0, CELLS - 1.001)
	var i := int(gx)
	var j := int(gy)
	var fx := gx - i
	var fy := gy - j
	var n := j * CELLS + i
	var a := lerpf(bed[n] + soil[n], bed[n + 1] + soil[n + 1], fx)
	var b := lerpf(bed[n + CELLS] + soil[n + CELLS], bed[n + CELLS + 1] + soil[n + CELLS + 1], fx)
	return lerpf(a, b, fy) / MM

## The firm ground's height in metres, under any loose soil, smooth between cells.
## Takes the ground as it stands now as where it began, all over or only within a circle (the Dirt mode tools remake the land).
func mark_start_ground(c := Vector2.ZERO, radius := -1.0) -> void:
	if start_ground.size() != bed.size():
		start_ground.resize(bed.size())
		for n in bed.size():
			start_ground[n] = bed[n] + soil[n]
		return
	if radius < 0.0:
		for n in bed.size():
			start_ground[n] = bed[n] + soil[n]
		return
	var at := cell_of(c)
	var r := int(ceil(radius / CELL_M))
	for j in range(maxi(at.y - r, 0), mini(at.y + r + 1, CELLS)):
		for i in range(maxi(at.x - r, 0), mini(at.x + r + 1, CELLS)):
			var n := j * CELLS + i
			start_ground[n] = bed[n] + soil[n]

## How high the ground began here, in m.
func start_at(p: Vector2) -> float:
	if start_ground.size() != bed.size():
		mark_start_ground()
	var gx := clampf((p.x + HALF_M) / CELL_M, 0.0, CELLS - 1.001)
	var gy := clampf((p.y + HALF_M) / CELL_M, 0.0, CELLS - 1.001)
	var i := int(gx)
	var j := int(gy)
	var n := j * CELLS + i
	var a := lerpf(start_ground[n], start_ground[n + 1], gx - i)
	var b := lerpf(start_ground[n + CELLS], start_ground[n + CELLS + 1], gx - i)
	return lerpf(a, b, gy - j) / MM

func firm_at(p: Vector2) -> float:
	var gx := clampf((p.x + HALF_M) / CELL_M, 0.0, CELLS - 1.001)
	var gy := clampf((p.y + HALF_M) / CELL_M, 0.0, CELLS - 1.001)
	var i := int(gx)
	var j := int(gy)
	var n := j * CELLS + i
	var a := lerpf(bed[n], bed[n + 1], gx - i)
	var b := lerpf(bed[n + CELLS], bed[n + CELLS + 1], gx - i)
	return lerpf(a, b, gy - j) / MM

## How high a track rides here: it sinks some way into loose soil, which is what lets a blade bite into a pile.
func track_height_at(p: Vector2) -> float:
	var gx := clampf((p.x + HALF_M) / CELL_M, 0.0, CELLS - 1.001)
	var gy := clampf((p.y + HALF_M) / CELL_M, 0.0, CELLS - 1.001)
	var i := int(gx)
	var j := int(gy)
	var fx := gx - i
	var fy := gy - j
	var n := j * CELLS + i
	var a := lerpf(_track_mm(n), _track_mm(n + 1), fx)
	var b := lerpf(_track_mm(n + CELLS), _track_mm(n + CELLS + 1), fx)
	return lerpf(a, b, fy) / MM

func _track_mm(n: int) -> float:
	return bed[n] + soil[n] - minf(soil[n] * (1.0 - TRACK_RIDE), TRACK_SINK)

## ---------------------------------------------------------------- waking chunks

func wake_chunk(ci: int, cj: int) -> void:
	if ci < 0 or cj < 0 or ci >= CHUNKS or cj >= CHUNKS:
		return
	var c := cj * CHUNKS + ci
	dirty[c] = true
	if _awake[c] == 0:
		_awake[c] = 1
		_queue.append(c)

## Wakes the cell's chunk, and the chunks beside it if it's near their edge.
func wake(i: int, j: int) -> void:
	var ci := i >> 4
	var cj := j >> 4
	wake_chunk(ci, cj)
	var fx := i & 15
	var fy := j & 15
	if fx < 2:
		wake_chunk(ci - 1, cj)
	elif fx > 13:
		wake_chunk(ci + 1, cj)
	if fy < 2:
		wake_chunk(ci, cj - 1)
	elif fy > 13:
		wake_chunk(ci, cj + 1)

func awake_count() -> int:
	return _queue.size() - _queue_at

## ---------------------------------------------------------------- the player's hands and the machine

## Takes up to `amt` mm off a cell, loose first, then firm ground unless it's rock. Returns what it got.
func take(i: int, j: int, amt: int) -> int:
	if i < 0 or j < 0 or i >= CELLS or j >= CELLS or amt <= 0:
		return 0
	var n := j * CELLS + i
	var got := mini(soil[n], amt)
	last_dust = 0
	if got > 0 and dust[n] > 0:
		last_dust = dust[n] * got / soil[n]
		dust[n] -= last_dust
	soil[n] -= got
	if got < amt and rock[n] == 0:
		var from_bed := mini(amt - got, maxi(bed[n] - BED_FLOOR, 0))
		bed[n] -= from_bed
		got += from_bed
	if got > 0:
		wake(i, j)
	return got

## What a bucket does to a cell: takes up to `amt` mm, loose soil freely but firm ground only `firm_rate` at a time, into the
## machine's hold. Returns [mm taken in all, mm of it from firm ground, mm of it that was cracker dust].
func bite(i: int, j: int, amt: int, firm_rate: int) -> Array:
	if i < 1 or j < 1 or i >= CELLS - 1 or j >= CELLS - 1 or amt <= 0:
		return [0, 0, 0]
	var n := j * CELLS + i
	var got := mini(soil[n], amt)
	var bit_dust := 0
	if got > 0 and dust[n] > 0:
		bit_dust = dust[n] * got / soil[n]
		dust[n] -= bit_dust
	soil[n] -= got
	var firm := 0
	if got < amt and rock[n] == 0:
		firm = mini(mini(amt - got, firm_rate), maxi(bed[n] - BED_FLOOR, 0))
		bed[n] -= firm
		got += firm
	if got > 0:
		held += got
		wake(i, j)
	return [got, firm, bit_dust]

## A trencher's chain at one cell: cuts down to `floor_mm`, at most `rate` mm in a tick, and throws what it cuts to `to`. It stays on
## the ground, moved whole from one place to another. Returns mm cut, and leaves the cell marked as a clean cut.
func trench(at: Vector2i, floor_mm: int, rate: int, to: Vector2i) -> int:
	if at.x < 1 or at.y < 1 or at.x >= CELLS - 1 or at.y >= CELLS - 1:
		return 0
	var n := at.y * CELLS + at.x
	var want := mini(bed[n] + soil[n] - floor_mm, rate)
	if want <= 0:
		return 0
	var firm_was := bed[n]
	var got := take(at.x, at.y, want)
	clean_cut[n] = 1
	var extra := (firm_was - bed[n]) * SWELL_PCT / 100
	swelled += extra
	put(to.x, to.y, got + extra, last_dust)
	return got

## Fills a low trench cell back up to the ground it was cut from with spare loose soil from round about, nearest first: soil
## standing above its own first ground, within `reach` cells. Only loose soil moves, so firm ground is never dug. It's what a bucket
## spreading over a backfilled trench does, raking the leftover in. Returns mm moved.
func rake_into(i: int, j: int, reach: int) -> int:
	if start_ground.size() != bed.size():
		return 0
	var n := j * CELLS + i
	var need := start_ground[n] - (bed[n] + soil[n])
	if need <= 0:
		return 0
	var moved := 0
	for r in range(1, reach + 1):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var x := i + di
				var y := j + dj
				if x < RIM or y < RIM or x >= CELLS - RIM or y >= CELLS - RIM:
					continue
				var k := y * CELLS + x
				var spare := mini(soil[k], bed[k] + soil[k] - start_ground[k] - RAKE_KEEP_MM)
				if spare <= 0:
					continue
				var got := take(x, y, mini(spare, need - moved))
				put(i, j, got, last_dust)
				moved += got
				if moved >= need:
					return moved
	return moved

## Puts soil on a cell. It always all goes on: nothing can be refused without losing it.
func put(i: int, j: int, amt: int, dust_amt := 0) -> void:
	if amt <= 0:
		return
	var at_i := clampi(i, RIM, CELLS - 1 - RIM)
	var at_j := clampi(j, RIM, CELLS - 1 - RIM)
	soil[at_j * CELLS + at_i] += amt
	dust[at_j * CELLS + at_i] += dust_amt
	wake(at_i, at_j)

## Digs a round patch into the store, deepest in the middle. Returns how much it took.
func scoop(c: Vector2, radius: float, rate: int) -> int:
	var at := cell_of(c)
	var r := int(ceil(radius / CELL_M))
	var taken := 0
	for j in range(at.y - r, at.y + r + 1):
		for i in range(at.x - r, at.x + r + 1):
			var d := Vector2(i - at.x, j - at.y).length() * CELL_M / radius
			if d < 1.0:
				taken += take(i, j, int(rate * (1.0 - d * d)))
	store += taken
	return taken

## Drops soil from the store as falling chunks over a round patch.
func pour(c: Vector2, radius: float, chunks: int, each: int, from_high: float, rng: RandomNumberGenerator) -> void:
	for _k in chunks:
		var amt := mini(each, store)
		if amt <= 0:
			return
		store -= amt
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := Vector2(c.x + cos(a) * r, c.y + sin(a) * r)
		launch(Vector3(p.x, height_at(p) + from_high * rng.randf_range(0.8, 1.2), p.y), Vector3(rng.randf_range(-0.4, 0.4), -1.0, rng.randf_range(-0.4, 0.4)), amt)

## A chunk carrying `amt` mm into the air. Over the limit, it lands where it is.
func launch(pos: Vector3, vel: Vector3, amt: int, dust_amt := 0) -> void:
	if air_amt.size() >= AIR_MAX:
		var at := cell_of(Vector2(pos.x, pos.z))
		put(at.x, at.y, amt, dust_amt)
		return
	in_air += amt
	air_pos.append(pos)
	air_vel.append(vel)
	air_amt.append(amt)
	air_dust.append(dust_amt)

func _step_air(dt: float) -> void:
	var k := air_amt.size() - 1
	while k >= 0:
		var v := air_vel[k]
		v.y -= GRAVITY * dt
		var p := air_pos[k] + v * dt
		air_vel[k] = v
		air_pos[k] = p
		var caught := false
		for c: Object in catchers:
			if c.catch_soil(p, air_amt[k], air_dust[k]):
				caught = true
				break
		if caught:
			in_air -= air_amt[k]
			held += air_amt[k]
			var end := air_amt.size() - 1
			air_pos[k] = air_pos[end]
			air_vel[k] = air_vel[end]
			air_amt[k] = air_amt[end]
			air_dust[k] = air_dust[end]
			air_pos.resize(end)
			air_vel.resize(end)
			air_amt.resize(end)
			air_dust.resize(end)
		elif p.y <= height_at(Vector2(p.x, p.z)):
			var at := cell_of(Vector2(p.x, p.z))
			var amt := air_amt[k]
			in_air -= amt
			put(at.x, at.y, amt, air_dust[k])
			# Off the list by moving the last one into its place.
			var last := air_amt.size() - 1
			air_pos[k] = air_pos[last]
			air_vel[k] = air_vel[last]
			air_amt[k] = air_amt[last]
			air_dust[k] = air_dust[last]
			air_pos.resize(last)
			air_vel.resize(last)
			air_amt.resize(last)
			air_dust.resize(last)
		k -= 1

## A blade from a to b, its cutting edge `edge_mm` high, moving soil on past it along `forward`. It scrapes whatever stands
## above the edge and drops it just ahead. Firm ground comes away slowly, and rock doesn't. Returns what it did:
## [mm moved, mm cut from firm ground, whether rock stopped it].
## `rows` over 2 sweep further back as well, for loose soil only: what slid off the heap onto ground already cut.
func blade(a: Vector2, b: Vector2, forward: Vector2, edge_mm: int, bed_rate: int, share := 1.0, rows := 2) -> Array:
	var moved := 0
	var cut := 0
	var hit_rock := false
	var steps := int(a.distance_to(b) / (CELL_M * 0.5)) + 1
	var width := a.distance_to(b)
	var across := (b - a) / maxf(width, 0.001)
	for row in rows:
		var back := forward * (-0.22 * row)
		# The back row catches what slides under the blade, so it clears harder: soil can't leak past a moving blade.
		var row_share := share if row == 0 else minf(share * 5.0, 1.0)
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps) + back
			var at := cell_of(p)
			if at.x < 1 or at.y < 1 or at.x >= CELLS - 1 or at.y >= CELLS - 1:
				continue
			var n := at.y * CELLS + at.x
			var high := bed[n] + soil[n] - edge_mm
			if high <= 0:
				continue
			var got := mini(soil[n], ceili(high * row_share))
			var got_dust := 0
			if got > 0 and dust[n] > 0:
				got_dust = dust[n] * got / soil[n]
				dust[n] -= got_dust
			soil[n] -= got
			var left := ceili(high * row_share) - got
			# Rock is felt when firm ground itself stands above the edge, not just soil lying on it.
			if rock[n] != 0 and bed[n] > edge_mm:
				hit_rock = true
			if left > 0 and rock[n] == 0 and row < 2:
				var firm := mini(mini(left, ceili(bed_rate * row_share)), maxi(bed[n] - BED_FLOOR, 0))
				bed[n] -= firm
				got += firm
				cut += firm
			if got > 0:
				wake(at.x, at.y)
				var along := float(s) / steps
				var out := across * (1.0 if along >= 0.5 else -1.0)
				var to_end := width * (0.5 - absf(along - 0.5))
				_spill(p, forward, out, to_end, got, edge_mm + HEAP_MM, got_dust)
				moved += got
	return [moved, cut, hit_rock]

## Lays what the blade took just ahead of it, up to `top_mm`. What's left over goes further ahead, then rolls off past the end
## of the blade as a windrow. This happens in the tick: slumping alone can't keep up, and soil would stack into a tower.
func _spill(p: Vector2, forward: Vector2, out: Vector2, to_end: float, amt: int, top_mm: int, dust_amt := 0) -> void:
	var left := amt
	var left_dust := dust_amt
	var lowest := -1
	var lowest_h := 0
	for k in SPILL_AHEAD.size() + SPILL_SIDE.size():
		var spot: Vector2
		if k < SPILL_AHEAD.size():
			spot = p + forward * SPILL_AHEAD[k]
		else:
			spot = p + forward * 0.25 + out * (to_end + SPILL_SIDE[k - SPILL_AHEAD.size()])
		var at := cell_of(spot)
		var i := clampi(at.x, RIM, CELLS - 1 - RIM)
		var j := clampi(at.y, RIM, CELLS - 1 - RIM)
		var n := j * CELLS + i
		var h := bed[n] + soil[n]
		var ahead := k < SPILL_AHEAD.size()
		if lowest < 0 or h < lowest_h:
			lowest = n
			lowest_h = h
		var room := top_mm - h if ahead else top_mm - SIDE_LOWER_MM - h
		if room <= 0:
			continue
		var given := mini(room, left)
		var given_dust := left_dust * given / left
		put(i, j, given, given_dust)
		left -= given
		left_dust -= given_dust
		if left == 0:
			return
	# Soil already stands higher than that all round, as in the heart of a big pile: the lowest place seen takes the rest.
	put(lowest % CELLS, lowest / CELLS, left, left_dust)

## A bucket back-dragged from a to b, moving along `toward`: it floats on the firm ground and leaves `leave_mm` of loose soil behind,
## carrying the rest along in front of it. So what's heaped gets laid out at an even depth, and thin spots fill as the heap passes
## over them. It never cuts firm ground. Returns mm moved.
## `lowest_mm` is as low as the edge can go, being on an arm on a machine standing on firm ground: it can't follow a slot down.
func drag(a: Vector2, b: Vector2, toward: Vector2, leave_mm: int, share: float, lowest_mm := BED_FLOOR) -> int:
	var moved := 0
	var steps := int(a.distance_to(b) / (CELL_M * 0.5)) + 1
	var width := a.distance_to(b)
	var across := (b - a) / maxf(width, 0.001)
	for row in 2:
		# The trailing row finishes the job, so nothing leaks past a moving bucket.
		var row_share := share if row == 0 else minf(share * 3.0, 1.0)
		# The edge is straight and rides on the highest firm ground across it, so it bridges a trench rather than dipping in
		# and dragging the backfill back out. What's below it is left, and fills as soil spills ahead.
		var edge := lowest_mm
		for s in steps + 1:
			var at := cell_of(a.lerp(b, float(s) / steps) - toward * (0.22 * row))
			if at.x >= 1 and at.y >= 1 and at.x < CELLS - 1 and at.y < CELLS - 1:
				edge = maxi(edge, bed[at.y * CELLS + at.x])
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps) - toward * (0.22 * row)
			var at := cell_of(p)
			if at.x < 1 or at.y < 1 or at.x >= CELLS - 1 or at.y >= CELLS - 1:
				continue
			var n := at.y * CELLS + at.x
			var over := mini(soil[n] - leave_mm, bed[n] + soil[n] - edge - leave_mm)
			if over <= 0:
				continue
			var got := mini(over, ceili(mini(over, DRAG_MOUTH) * row_share))
			var got_dust := dust[n] * got / soil[n] if dust[n] > 0 else 0
			dust[n] -= got_dust
			soil[n] -= got
			wake(at.x, at.y)
			var along := float(s) / steps
			var out := across * (1.0 if along >= 0.5 else -1.0)
			var to_end := width * (0.5 - absf(along - 0.5))
			_spill(p, toward, out, to_end, got, bed[n] + leave_mm + DRAG_HEAP, got_dust)
			moved += got
	return moved

## What's banked up against the blade: loose soil above the cutting edge in a strip ahead of it, in tonnes. Firm ground
## rising ahead doesn't count: it isn't being pushed yet.
func load_ahead(a: Vector2, b: Vector2, forward: Vector2, edge_mm: int) -> float:
	var over := 0
	for row in 5:
		var off := forward * (0.2 + row * 0.3)
		for s in 9:
			var p := a.lerp(b, s / 8.0) + off
			var at := cell_of(p)
			var n := clampi(at.y, 0, CELLS - 1) * CELLS + clampi(at.x, 0, CELLS - 1)
			var h := mini(bed[n] + soil[n] - edge_mm, soil[n])
			if h > 0:
				over += h
	# Each sample stands for a patch of 0.3 m by an eighth of the blade.
	var patch := 0.3 * a.distance_to(b) / 8.0
	return over / MM * patch * 1.5

## ---------------------------------------------------------------- slumping

## One tick: falling chunks, then slumping in the awake chunks until the time budget's gone.
func step(dt: float, budget_usec := 4000) -> void:
	_step_air(dt)
	var t0 := Time.get_ticks_usec()
	moved_last_tick = 0
	_tick += 1
	_flip = _tick % 2 == 0
	_flip_set = (_tick >> 1) % 2 == 0
	var end := _queue.size()
	var i := _queue_at
	while i < end:
		var c := _queue[i]
		i += 1
		_awake[c] = 0
		if _slump_chunk(c % CHUNKS, c / CHUNKS, _flip_set) or _slump_chunk(c % CHUNKS, c / CHUNKS, not _flip_set):
			wake_chunk(c % CHUNKS, c / CHUNKS)
		if Time.get_ticks_usec() - t0 > budget_usec:
			break
	_queue_at = i
	# Trim what's done off the front now and then.
	if _queue_at > 256:
		_queue = _queue.slice(_queue_at)
		_queue_at = 0
	chunks_left = _queue.size() - _queue_at

## One pass over a chunk, sliding soil to its straight neighbours (diagonals false) or its corner neighbours (true), a tick
## of each in turn so piles come out round rather than diamond-shaped. Corner neighbours are further away, so they may
## stand that much higher. Returns whether anything moved.
func _slump_chunk(ci: int, cj: int, diagonals: bool) -> bool:
	var i0 := ci * CHUNK
	var j0 := cj * CHUNK
	var i1 := mini(i0 + CHUNK, CELLS)
	var j1 := mini(j0 + CHUNK, CELLS)
	var moved := false
	var last := CELLS - 1
	var soil_limit := SOIL_LIMIT_CORNER if diagonals else SOIL_LIMIT
	var dust_limit := DUST_LIMIT_CORNER if diagonals else DUST_LIMIT
	var bed_limit := BED_LIMIT_CORNER if diagonals else BED_LIMIT
	var off_a := CELLS + 1 if diagonals else 1
	var off_b := CELLS - 1 if diagonals else CELLS
	# Sweep a different way each tick, or soil would lean one way.
	var ja := j0 if _flip else j1 - 1
	var jb := j1 if _flip else j0 - 1
	var ia := i1 - 1 if _flip else i0
	var ib := i0 - 1 if _flip else i1
	var js := 1 if _flip else -1
	var is_ := -1 if _flip else 1
	for j in range(ja, jb, js):
		for i in range(ia, ib, is_):
			if i == 0 or j == 0 or i == last or j == last:
				continue
			var n := j * CELLS + i
			var s := soil[n]
			var h := bed[n] + s
			var acted := false
			var ds := -1            # looked up only if something moves: most cells are at rest, and this runs for every one
			for side in 4:
				var m: int
				match side:
					0: m = n - off_a
					1: m = n + off_a
					2: m = n - off_b
					_: m = n + off_b
				var d := h - bed[m] - soil[m]
				if d <= soil_limit:
					continue
				if s > 0:
					var to_i := m % CELLS
					var to_j := m / CELLS
					if to_i < RIM or to_j < RIM or to_i > last - RIM or to_j > last - RIM:
						continue
					if ds < 0:
						ds = dust[n]
					var limit := dust_limit if ds * 2 > s else soil_limit
					if d <= limit:
						continue
					var mv := mini((d - limit + 3) / 4, s)
					if ds > 0:
						var mv_dust := ds * mv / s
						ds -= mv_dust
						dust[m] += mv_dust
					s -= mv
					h -= mv
					soil[m] += mv
					acted = true
					moved_last_tick += mv
					var mi := m % CELLS
					var mj := m / CELLS
					if (mi >> 4) != ci or (mj >> 4) != cj:
						wake(mi, mj)
				elif d > bed_limit and rock[n] == 0 and bed[n] > BED_FLOOR and not (clean_cut[m] != 0 and d <= CUT_WALL_MM):
					# A firm wall too steep to stand: a slice of it comes loose.
					var slice := mini((d - bed_limit) / 2 + 1, bed[n] - BED_FLOOR)
					bed[n] -= slice
					s += slice
					acted = true
			soil[n] = s
			if ds >= 0:
				dust[n] = ds
			if acted:
				moved = true
				# Lowering a cell can unsettle the chunk next door, so it has to look again.
				wake(i, j)
	if moved:
		dirty[cj * CHUNKS + ci] = true
	return moved
