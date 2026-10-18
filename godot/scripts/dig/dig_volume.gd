class_name DigVolume
extends RefCounted
## The earth under the yard as a 3D density field (PLAN.md "Later: digging", level 3: smooth caves). Samples
## every D.CELL units across, down and deep, from D.ZMIN (bedrock) up to D.ZMAX; f > 0 is earth, f <= 0 is air.
## Untouched, f = -z (the ground's top at z = 0). Only chunks that were dug or filled are stored (sparse), as
## int8 (a quarter unit a step, held to +-31 units); the rest is worked out from that formula. DigMesher draws
## the stored chunks as smooth surfaces (marching tetrahedra); DigGround draws the untouched top as flat ground.
##
## Positions are the HTML game's: x across, y down the screen, z up (units).

const D := preload("res://scripts/dig/dig_data.gd")
const CS := 8                           # samples per chunk side (small: a dig redraws little)
const FMAX := 31.0                      # densities are held to +-FMAX units
const Q := 4.0                          # int8 steps a unit

signal changed

## Vector3i(chunk) -> Chunk (its CS^3 int8 samples)
var chunks: Dictionary = {}

## One stored chunk. (A packed array kept in a Dictionary is copied when written to, so each chunk is an object
## that writes its own array.)
class Chunk extends RefCounted:
	var d := PackedByteArray()
	func put(i: int, v: int) -> void:
		d.encode_s8(i, v)
## Chunks whose look changed since the last redraw.
var dirty: Dictionary = {}
var version := 0
## Columns (vertex indices) that may change: DigGrid.vmask (1 diggable), (D.NX + 1) x (D.NY + 1).
var vmask := PackedByteArray()

static var NZ := int((D.ZMAX - D.ZMIN) / D.CELL) + 1

## ---------------------------------------------------------------- samples

static func default_f(k: int) -> float:
	return clampf(-(D.ZMIN + k * D.CELL), -FMAX, FMAX)

static func chunk_key(i: int, j: int, k: int) -> Vector3i:
	return Vector3i(floori(float(i) / CS), floori(float(j) / CS), floori(float(k) / CS))

## The density at sample (i, j, k).
func sample(i: int, j: int, k: int) -> float:
	var key := Vector3i(i >> 3, j >> 3, k >> 3) if i >= 0 and j >= 0 and k >= 0 else chunk_key(i, j, k)
	var c = chunks.get(key)
	if c == null:
		return default_f(k)
	return c.d.decode_s8(((k & 7) * CS + (j & 7)) * CS + (i & 7)) / Q

func _set_sample(i: int, j: int, k: int, f: float) -> void:
	var key := Vector3i(i >> 3, j >> 3, k >> 3)
	var c = chunks.get(key)
	if c == null:
		c = _new_chunk(key)
		chunks[key] = c
	c.put(((k & 7) * CS + (j & 7)) * CS + (i & 7), clampi(int(roundf(f * Q)), -127, 127))

static func _new_chunk(key: Vector3i) -> Chunk:
	var b := PackedByteArray()
	b.resize(CS * CS * CS)
	for kk in CS:
		var v := clampi(int(roundf(default_f(key.z * CS + kk) * Q)), -127, 127)
		var base := kk * CS * CS
		for n in CS * CS:
			b.encode_s8(base + n, v)
	var c := Chunk.new()
	c.d = b
	return c

## Sample coordinates (floats) of an HTML position.
static func to_s(x: float, y: float, z: float) -> Vector3:
	return Vector3((x - D.X0) / D.CELL, (y - D.Y0) / D.CELL, (z - D.ZMIN) / D.CELL)

## The density at (x, y, z), between the samples.
func f_at(x: float, y: float, z: float) -> float:
	var s := to_s(x, y, z)
	var i := floori(s.x)
	var j := floori(s.y)
	var k := floori(s.z)
	var tx := s.x - i
	var ty := s.y - j
	var tz := s.z - k
	var c00 := lerpf(sample(i, j, k), sample(i + 1, j, k), tx)
	var c10 := lerpf(sample(i, j + 1, k), sample(i + 1, j + 1, k), tx)
	var c01 := lerpf(sample(i, j, k + 1), sample(i + 1, j, k + 1), tx)
	var c11 := lerpf(sample(i, j + 1, k + 1), sample(i + 1, j + 1, k + 1), tx)
	return lerpf(lerpf(c00, c10, ty), lerpf(c01, c11, ty), tz)

func solid(x: float, y: float, z: float) -> bool:
	return f_at(x, y, z) > 0.0

## Is anything stored (dug or filled) round (x, y)? (Untouched ground is flat at 0.)
func touched_near(x: float, y: float) -> bool:
	var s := to_s(x, y, 0.0)
	for oj in [-1, 1]:
		for oi in [-1, 1]:
			var i := floori(s.x + oi * 0.6)
			var j := floori(s.y + oj * 0.6)
			for kc in range(0, int(ceil(float(NZ) / CS))):
				if chunks.has(Vector3i(i >> 3, j >> 3, kc)):
					return true
	return false

## The top of the earth under (x, y) at or below z_from: where it goes from earth to air going up. Returns
## D.ZMIN if there's nothing (it can't happen: bedrock). If z_from is inside earth, the top of that earth above
## is looked for up to a step (step_up) first.
func floor_below(x: float, y: float, z_from: float) -> float:
	var s := to_s(x, y, z_from)
	var i := floori(s.x)
	var j := floori(s.y)
	var tx := s.x - i
	var ty := s.y - j
	var k := clampi(floori(s.z), 0, NZ - 2)
	var f_hi := lerpf(_col(i, j, tx, ty, k), _col(i, j, tx, ty, k + 1), clampf(s.z - k, 0.0, 1.0))
	if f_hi > 0.0:
		return z_from                        # (inside earth: the caller looks up for a step)
	var z_hi := z_from
	while k >= 0:
		var f_lo := _col(i, j, tx, ty, k)
		var z_lo := D.ZMIN + k * D.CELL
		if f_lo > 0.0:
			return z_lo + f_lo / (f_lo - f_hi) * (z_hi - z_lo)
		f_hi = f_lo
		z_hi = z_lo
		k -= 1
	return D.ZMIN

func _col(i: int, j: int, tx: float, ty: float, k: int) -> float:
	return lerpf(lerpf(sample(i, j, k), sample(i + 1, j, k), tx), lerpf(sample(i, j + 1, k), sample(i + 1, j + 1, k), tx), ty)

## The ground's top at (x, y) seen from above.
func surface_height(x: float, y: float) -> float:
	return floor_below(x, y, D.ZMAX - 1.0)

## The first earth along a ray (HTML units), or null.
func raycast(from: Vector3, dir: Vector3, max_d: float):
	var d := dir.normalized()
	var t := 0.0
	var prev := f_at(from.x, from.y, from.z)
	if prev > 0.0:
		return from
	while t < max_d:
		t += 2.0
		var p := from + d * t
		var f := f_at(p.x, p.y, p.z)
		if f > 0.0:
			var a := t - 2.0 * f / (f - prev)
			return from + d * a
		prev = f
	return null

## ---------------------------------------------------------------- changing it

func _column_ok(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i > D.NX or j > D.NY:
		return false
	return vmask.size() == (D.NX + 1) * (D.NY + 1) and vmask[j * (D.NX + 1) + i] == 1

## Digs out a capsule from a to b (HTML units) of radius r: f = min(f, distance - r). Returns the samples that
## went from earth to air (Vector3i), for finds. Bedrock (the lowest two samples) and columns that can't be dug
## (round solids, the house) stay.
func carve(a: Vector3, b: Vector3, r: float) -> Array:
	var out: Array = []
	var lo := to_s(minf(a.x, b.x) - r, minf(a.y, b.y) - r, minf(a.z, b.z) - r)
	var hi := to_s(maxf(a.x, b.x) + r, maxf(a.y, b.y) + r, maxf(a.z, b.z) + r)
	var any := false
	for k in range(maxi(2, floori(lo.z)), mini(NZ - 1, ceili(hi.z)) + 1):
		var z := D.ZMIN + k * D.CELL
		for j in range(floori(lo.y), ceili(hi.y) + 1):
			var y := D.Y0 + j * D.CELL
			for i in range(floori(lo.x), ceili(hi.x) + 1):
				if not _column_ok(i, j):
					continue
				var p := Vector3(D.X0 + i * D.CELL, y, z)
				var dist := _seg_dist(p, a, b)
				if dist > r + FMAX:
					continue
				var old := sample(i, j, k)
				var nf := minf(old, dist - r)
				if nf < old - 0.01:
					_set_sample(i, j, k, nf)
					_touch_sample(i, j, k)
					any = true
					if old > 0.0 and sample(i, j, k) <= 0.0:
						out.append(Vector3i(i, j, k))
	if any:
		_changed()
	return out

## Puts earth back: a ball at c of radius r (f = max(f, r - distance)), only up to z_top.
func fill(c: Vector3, r: float, z_top: float = 8.0) -> bool:
	var lo := to_s(c.x - r, c.y - r, c.z - r)
	var hi := to_s(c.x + r, c.y + r, minf(c.z + r, z_top))
	var any := false
	for k in range(maxi(2, floori(lo.z)), mini(NZ - 1, ceili(hi.z)) + 1):
		var z := D.ZMIN + k * D.CELL
		if z > z_top:
			continue
		for j in range(floori(lo.y), ceili(hi.y) + 1):
			for i in range(floori(lo.x), ceili(hi.x) + 1):
				if not _column_ok(i, j):
					continue
				var p := Vector3(D.X0 + i * D.CELL, D.Y0 + j * D.CELL, z)
				var dist := p.distance_to(c)
				if dist > r + FMAX:
					continue
				var old := sample(i, j, k)
				# (never more than the untouched ground there: filled holes come back level)
				var nf := minf(maxf(old, r - dist), maxf(old, default_f(k)))
				if nf > old + 0.01:
					_set_sample(i, j, k, nf)
					_touch_sample(i, j, k)
					any = true
	if any:
		_changed()
	return any

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## A sample changed: the chunks whose cells use it (its own and the ones before it on each axis) redraw; they're
## stored from now on (an untouched chunk next to a dug one must be drawn too, or the seam would show a gap).
func _touch_sample(i: int, j: int, k: int) -> void:
	for dk in [0, -1]:
		for dj in [0, -1]:
			for di in [0, -1]:
				var key := Vector3i((i + di) >> 3, (j + dj) >> 3, (k + dk) >> 3)
				if i + di < 0 or j + dj < 0 or k + dk < 0:
					continue
				if not chunks.has(key):
					chunks[key] = _new_chunk(key)
				dirty[key] = true

func _changed() -> void:
	version += 1
	changed.emit()

## Is the top layer of the chunk column holding cell (cx, cy) stored (then the smooth mesh draws the ground's top
## there, not the flat yard)?
func top_stored(cx: int, cy: int) -> bool:
	return chunks.has(Vector3i(cx >> 3, cy >> 3, top_layer()))

## (the layer of the cells the untouched ground's top crosses: those just under z = 0)
static func top_layer() -> int:
	return (int((0.0 - D.ZMIN) / D.CELL) - 1) >> 3

## ---------------------------------------------------------------- blocks

## Blocks put back (Vector3i -> material): what they're made of (the rest by where they are).
var placed: Dictionary = {}

## The block holding (x, y, z).
static func block_of(p: Vector3) -> Vector3i:
	return Vector3i(floori((p.x - D.X0) / D.BLOCK), floori((p.y - D.Y0) / D.BLOCK), floori(p.z / D.BLOCK))

static func block_centre(b: Vector3i) -> Vector3:
	return Vector3(D.X0 + (b.x + 0.5) * D.BLOCK, D.Y0 + (b.y + 0.5) * D.BLOCK, (b.z + 0.5) * D.BLOCK)

## What block b is made of: what was put there, else by depth (dirt, clay, stone) with coal and iron ore
## scattered in (fixed by where it is: the same on both screens).
func material(b: Vector3i) -> int:
	if placed.has(b):
		return int(placed[b])
	return natural_material(b)

static func natural_material(b: Vector3i) -> int:
	var depth := -(b.z + 0.5) * D.BLOCK
	var h := float(_bhash(b.x, b.y, b.z) % 10000) / 10000.0
	if depth >= D.STONE_Z:
		if h < D.IRON_IN_STONE:
			return D.IRON_M
		if h < D.IRON_IN_STONE + D.COAL_IN_STONE:
			return D.COAL_M
		return D.STONE_M
	if depth >= D.CLAY_Z:
		return D.COAL_M if h < D.COAL_IN_CLAY else D.CLAY_M
	return D.DIRT_M

static func _bhash(i: int, j: int, k: int) -> int:
	var h := (i * 92837111) ^ (j * 689287499) ^ (k * 283923481)
	h = (h ^ (h >> 15)) * 2246822519
	return (h ^ (h >> 13)) & 0x7fffffff

## Is there earth in block b (worth hitting)?
func block_solid(b: Vector3i) -> bool:
	var c := block_centre(b)
	if solid(c.x, c.y, c.z):
		return true
	for o in [Vector3(-8, -8, -8), Vector3(8, 8, 8), Vector3(8, -8, 0), Vector3(-8, 8, 0), Vector3(0, 0, 10)]:
		if solid(c.x + o.x, c.y + o.y, c.z + o.z):
			return true
	return false

## A rounded cube's distance (negative inside) from p: centre c, half size half, its edges rounded by round
## (a placed block's lump).
static func _box_sd(p: Vector3, c: Vector3, half: float = D.PLACE_HALF, round: float = D.PLACE_ROUND) -> float:
	var hh := half - round
	var q := (p - c).abs() - Vector3(hh, hh, hh)
	var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
	return outside + minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - round

## Breaks block b: a ball of earth out, a little bigger than its cell (see BREAK_HALF). Returns the samples that went from earth to air (for finds).
func carve_block(b: Vector3i) -> Array:
	var out: Array = []
	# (a little off the block's centre and size, fixed by the block: a row of them is a dug tunnel, not tiles)
	var h := _bhash(b.x, b.y, b.z)
	var c := block_centre(b) + Vector3(float(h & 7) - 3.5, float((h >> 3) & 7) - 3.5, float((h >> 6) & 3) - 1.5)
	var rr := D.BREAK_HALF + float((h >> 8) & 3) - 1.0
	var r := rr + 14.0
	var lo := to_s(c.x - r, c.y - r, c.z - r)
	var hi := to_s(c.x + r, c.y + r, c.z + r)
	var any := false
	for k in range(maxi(2, floori(lo.z)), mini(NZ - 1, ceili(hi.z)) + 1):
		var z := D.ZMIN + k * D.CELL
		for j in range(floori(lo.y), ceili(hi.y) + 1):
			for i in range(floori(lo.x), ceili(hi.x) + 1):
				if not _column_ok(i, j):
					continue
				var sd := Vector3(D.X0 + i * D.CELL, D.Y0 + j * D.CELL, z).distance_to(c) - rr
				if sd > 8.0:
					continue
				var old := sample(i, j, k)
				var nf := minf(old, sd)
				if nf < old - 0.01:
					_set_sample(i, j, k, nf)
					_touch_sample(i, j, k)
					any = true
					if old > 0.0 and sample(i, j, k) <= 0.0:
						out.append(Vector3i(i, j, k))
	if placed.has(b):
		placed.erase(b)
	if any:
		_changed()
	return out

## Puts a block of material m at b (a rounded lump about its cell). False if nothing changed.
func fill_block(b: Vector3i, m: int) -> bool:
	var c := block_centre(b)
	if c.z + D.BLOCK / 2.0 > D.ZMAX - D.CELL or c.z - D.BLOCK / 2.0 < D.ZMIN + 2.0 * D.CELL:
		return false
	var r := D.PLACE_HALF + 8.0
	var lo := to_s(c.x - r, c.y - r, c.z - r)
	var hi := to_s(c.x + r, c.y + r, c.z + r)
	var any := false
	for k in range(maxi(2, floori(lo.z)), mini(NZ - 1, ceili(hi.z)) + 1):
		var z := D.ZMIN + k * D.CELL
		for j in range(floori(lo.y), ceili(hi.y) + 1):
			for i in range(floori(lo.x), ceili(hi.x) + 1):
				if not _column_ok(i, j):
					continue
				var sd := _box_sd(Vector3(D.X0 + i * D.CELL, D.Y0 + j * D.CELL, z), c)
				if sd > 8.0:
					continue
				var old := sample(i, j, k)
				var nf := maxf(old, -sd)
				if nf > old + 0.01:
					_set_sample(i, j, k, nf)
					_touch_sample(i, j, k)
					any = true
	if any:
		if m != natural_material(b) or c.z > 0.0:
			placed[b] = m
		_changed()
	return any

## ---------------------------------------------------------------- saving and sending

func pack() -> Dictionary:
	var cs := {}
	for key in chunks:
		cs["%d,%d,%d" % [key.x, key.y, key.z]] = (chunks[key].d as PackedByteArray).compress(FileAccess.COMPRESSION_DEFLATE)
	var pl := PackedInt32Array()
	for b in placed:
		pl.append_array([b.x, b.y, b.z, int(placed[b])])
	return {"v": 4, "cs": cs, "ver": version, "pl": pl}

func unpack(p: Dictionary) -> bool:
	if int(p.get("v", 0)) != 4:
		return false
	var cs: Dictionary = p.get("cs", {})
	var seen := {}
	for ks in cs:
		var a := String(ks).split(",")
		if a.size() != 3:
			continue
		var key := Vector3i(int(a[0]), int(a[1]), int(a[2]))
		var b = cs[ks]
		if b is String:
			b = Marshalls.base64_to_raw(b)
		if not (b is PackedByteArray):
			continue
		var raw: PackedByteArray = b.decompress(CS * CS * CS, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() != CS * CS * CS:
			continue
		seen[key] = true
		if not chunks.has(key) or chunks[key].d != raw:
			var c := Chunk.new()
			c.d = raw
			chunks[key] = c
			dirty[key] = true
	for key in chunks.keys():
		if not seen.has(key):
			chunks.erase(key)
			dirty[key] = true
	placed.clear()
	var pl = p.get("pl", PackedInt32Array())
	if pl is Array or pl is PackedInt32Array:
		for n in range(0, pl.size() - 3, 4):
			placed[Vector3i(int(pl[n]), int(pl[n + 1]), int(pl[n + 2]))] = int(pl[n + 3])
	version = maxi(version + 1, int(p.get("ver", 0)))
	changed.emit()
	return true

func clear() -> void:
	for key in chunks:
		dirty[key] = true
	chunks.clear()
	placed.clear()
	_changed()
