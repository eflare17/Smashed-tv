class_name DigGrid
extends RefCounted
## The yard's ground's top as data: what each 8-unit cell's surface is (grass, ploughed rows, dug-over dirt), how
## long it's been untended, and which cells can be dug or ploughed at all; the rules for ploughing, planting
## spots and growing back. The earth itself (holes, tunnels, caves) is the DigVolume in vol. No nodes, so the
## headless tests drive it directly; DigGround draws it, Dig runs the tools, saving and the network.
##
## Layout: cells of D.CELL units from (D.X0, D.Y0), D.NX x D.NY of them.

const D := preload("res://scripts/dig/dig_data.gd")

## Something changed: the flat chunks to redraw are in dirty.
signal changed

var vol := DigVolume.new()
var soil := PackedByteArray()          # per cell: D.GRASS, ROWS_X, ROWS_Y, DIRT
var age := PackedFloat32Array()        # per cell: game hours untended (ploughed soil and dirt grow back)
var mask := PackedByteArray()          # per cell: 1 diggable (grass in the yard, clear of everything solid)
var vmask := PackedByteArray()         # per vertex: 1 if every cell round it is diggable
## Flat chunk index -> true: chunks whose look changed since the last redraw.
var dirty: Dictionary = {}
## Bumped on every change (the network sends only changed grounds).
var version := 0
var stats := {"digs": 0, "spuds": 0, "coins": 0, "bones": 0, "stashes": 0, "gems": 0, "fossils": 0, "ploughed": 0}
var rng := RandomNumberGenerator.new()

const VW := D.NX + 1
const VH := D.NY + 1

func _init() -> void:
	rng.randomize()
	soil.resize(D.NX * D.NY)
	age.resize(D.NX * D.NY)
	set_mask(PackedByteArray())
	vol.changed.connect(func(): version += 1)

## The diggable cells (1 per cell; empty: none). Vertices are diggable when all the cells round them are.
func set_mask(m: PackedByteArray) -> void:
	mask = m.duplicate() if m.size() == D.NX * D.NY else PackedByteArray()
	if mask.is_empty():
		mask.resize(D.NX * D.NY)
	vmask.resize(VW * VH)
	for vy in VH:
		for vx in VW:
			var ok := 1
			for c in [[vx - 1, vy - 1], [vx, vy - 1], [vx - 1, vy], [vx, vy]]:
				if c[0] < 0 or c[1] < 0 or c[0] >= D.NX or c[1] >= D.NY or mask[c[1] * D.NX + c[0]] == 0:
					ok = 0
					break
			vmask[vy * VW + vx] = ok
	vol.vmask = vmask

## ---------------------------------------------------------------- reading

## Cell (cx, cy) holding the point (x, y), or (-1, -1) outside.
static func cell_of(x: float, y: float) -> Vector2i:
	var cx := int(floor((x - D.X0) / D.CELL))
	var cy := int(floor((y - D.Y0) / D.CELL))
	if cx < 0 or cy < 0 or cx >= D.NX or cy >= D.NY:
		return Vector2i(-1, -1)
	return Vector2i(cx, cy)

static func in_region(x: float, y: float) -> bool:
	return x >= D.X0 and y >= D.Y0 and x <= D.X0 + D.NX * D.CELL and y <= D.Y0 + D.NY * D.CELL

## The ground's top at (x, y), units up (0 untouched; down in a hole).
func height_at(x: float, y: float) -> float:
	if not in_region(x, y) or not vol.touched_near(x, y):
		return 0.0
	return vol.surface_height(x, y)

## How deep the ground's top is at (x, y) (positive in a hole).
func depth_at(x: float, y: float) -> float:
	return -height_at(x, y)

func diggable_cell(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < D.NX and cy < D.NY and mask[cy * D.NX + cx] == 1

func diggable_at(x: float, y: float) -> bool:
	var c := cell_of(x, y)
	return c.x >= 0 and mask[c.y * D.NX + c.x] == 1

func soil_at(x: float, y: float) -> int:
	var c := cell_of(x, y)
	return soil[c.y * D.NX + c.x] if c.x >= 0 else D.GRASS

## Is the cell's ground level (not in a hole or a mound)?
func cell_level(cx: int, cy: int) -> bool:
	if not vol.top_stored(cx, cy):
		return true
	var x := D.X0 + (cx + 0.5) * D.CELL
	var y := D.Y0 + (cy + 0.5) * D.CELL
	return absf(vol.surface_height(x, y)) < 2.0 and vol.f_at(x, y, -10.0) > 0.0

## How many cells are ploughed (rows) or dug over.
func counts() -> Dictionary:
	var rows := 0
	var dirt := 0
	for s in soil:
		if s == D.ROWS_X or s == D.ROWS_Y:
			rows += 1
		elif s == D.DIRT:
			dirt += 1
	return {"rows": rows, "dirt": dirt, "chunks": vol.chunks.size()}

## Dug: the cells round (x, y) within r at the ground's top become dug-over dirt (they grow back, and can be
## planted once level again).
func mark_dug(x: float, y: float, r: float) -> void:
	var c := cell_of(x, y)
	if c.x < 0:
		return
	var n := int(ceil(r / D.CELL))
	for cy in range(c.y - n, c.y + n + 1):
		for cx in range(c.x - n, c.x + n + 1):
			if diggable_cell(cx, cy) and Vector2(D.X0 + (cx + 0.5) * D.CELL - x, D.Y0 + (cy + 0.5) * D.CELL - y).length() <= r:
				_set_soil(cx, cy, D.DIRT)
	_changed()

## ---------------------------------------------------------------- the hoe

## The hoe at (x, y), pulled along dir: grass and dirt within PLOUGH_R become furrows running along dir.
## Returns the cells ploughed now (indices), for the network.
func plough(x: float, y: float, dir: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var kind := D.ROWS_X if absf(dir.x) >= absf(dir.y) else D.ROWS_Y
	var c := cell_of(x, y)
	if c.x < 0:
		return out
	var r := int(ceil(D.PLOUGH_R / D.CELL))
	for cy in range(c.y - r, c.y + r + 1):
		for cx in range(c.x - r, c.x + r + 1):
			if not diggable_cell(cx, cy):
				continue
			if Vector2(D.X0 + (cx + 0.5) * D.CELL - x, D.Y0 + (cy + 0.5) * D.CELL - y).length() > D.PLOUGH_R:
				continue
			if plough_cell(cx, cy, kind):
				out.append(cy * D.NX + cx)
	if not out.is_empty():
		_changed()
	return out

## One cell to furrows (kind ROWS_X or ROWS_Y): only level ground; already-ploughed rows keep their way.
func plough_cell(cx: int, cy: int, kind: int) -> bool:
	if not diggable_cell(cx, cy) or not cell_level(cx, cy):
		return false
	var i := cy * D.NX + cx
	var s := soil[i]
	if s == D.ROWS_X or s == D.ROWS_Y:
		if age[i] > 0.0:
			age[i] = 0.0                    # hoed again: fresh
			_touch_cell(cx, cy)
			return true
		return false
	_set_soil(cx, cy, kind)
	stats.ploughed += 1
	return true

## Paints soil kind s (D.GRASS, ROWS_X, ROWS_Y, DIRT) on the diggable cells within r of (x, y) (a push
## tiller, a ride-on, a test). Returns how many cells changed.
func set_soil(x: float, y: float, r: float, s: int) -> int:
	var c := cell_of(x, y)
	if c.x < 0:
		return 0
	var n := int(ceil(r / D.CELL))
	var count := 0
	for cy in range(c.y - n, c.y + n + 1):
		for cx in range(c.x - n, c.x + n + 1):
			if not diggable_cell(cx, cy):
				continue
			if Vector2(D.X0 + (cx + 0.5) * D.CELL - x, D.Y0 + (cy + 0.5) * D.CELL - y).length() > r:
				continue
			var i := cy * D.NX + cx
			if soil[i] != s:
				_set_soil(cx, cy, s)
				count += 1
	if count > 0:
		_changed()
	return count

## ---------------------------------------------------------------- planting

## The planting spot nearest (x, y) (on the SPOT grid), if the soil round it is ploughed or dug over and level;
## else null.
func plant_spot(x: float, y: float):
	var p := Vector2(D.X0 + (floor((x - D.X0) / D.SPOT) + 0.5) * D.SPOT, D.Y0 + (floor((y - D.Y0) / D.SPOT) + 0.5) * D.SPOT)
	var c := cell_of(p.x, p.y)
	if c.x < 0:
		return null
	var r := int(ceil(D.SPOT_NEED / D.CELL))
	for cy in range(c.y - r, c.y + r):
		for cx in range(c.x - r, c.x + r):
			if cx < 0 or cy < 0 or cx >= D.NX or cy >= D.NY:
				return null
			if soil[cy * D.NX + cx] == D.GRASS:
				return null
	if not cell_level(c.x, c.y):
		return null
	return p

## ---------------------------------------------------------------- growing back

## Game hours pass: untended soil ages; weedy after WEEDY_HOURS, grass again after REGROW_HOURS. tended: points
## (Vector2, HTML units) with a crop, which keep the soil within TEND_R fresh. Holes stay as they are.
func grow_back(hours: float, tended: Array = []) -> void:
	if hours <= 0.0:
		return
	var keep := {}
	var r := int(ceil(D.TEND_R / D.CELL))
	for t in tended:
		var c := cell_of(t.x, t.y)
		if c.x < 0:
			continue
		for cy in range(c.y - r, c.y + r + 1):
			for cx in range(c.x - r, c.x + r + 1):
				if cx >= 0 and cy >= 0 and cx < D.NX and cy < D.NY:
					keep[cy * D.NX + cx] = true
	var any := false
	for i in soil.size():
		var s := soil[i]
		if s == D.GRASS:
			continue
		var cx := i % D.NX
		var cy := i / D.NX
		if keep.has(i):
			if age[i] != 0.0:
				var was_weedy := age[i] >= D.WEEDY_HOURS
				age[i] = 0.0
				if was_weedy:
					_touch_cell(cx, cy)
					any = true
			continue
		if not cell_level(cx, cy):
			continue                         # (a hole's ground stays dirt)
		var a0 := age[i]
		var a1 := a0 + hours
		age[i] = a1
		if a1 >= D.REGROW_HOURS:
			soil[i] = D.GRASS
			age[i] = 0.0
			_touch_cell(cx, cy)
			any = true
		elif a0 < D.WEEDY_HOURS and a1 >= D.WEEDY_HOURS:
			_touch_cell(cx, cy)
			any = true
	if any:
		_changed()

func weedy(i: int) -> bool:
	return age[i] >= D.WEEDY_HOURS

## ---------------------------------------------------------------- bookkeeping

func _set_soil(cx: int, cy: int, s: int) -> void:
	var i := cy * D.NX + cx
	if soil[i] != s or age[i] != 0.0:
		soil[i] = s
		age[i] = 0.0
		_touch_cell(cx, cy)

static func chunk_of_cell(cx: int, cy: int) -> int:
	return (cy / D.CHUNK) * chunks_x() + cx / D.CHUNK

static func chunks_x() -> int:
	return int(ceil(float(D.NX) / D.CHUNK))

static func chunks_y() -> int:
	return int(ceil(float(D.NY) / D.CHUNK))

func _touch_cell(cx: int, cy: int) -> void:
	dirty[chunk_of_cell(cx, cy)] = true

func _changed() -> void:
	version += 1
	changed.emit()

func touch_all() -> void:
	for i in chunks_x() * chunks_y():
		dirty[i] = true

## ---------------------------------------------------------------- saving and sending

## The whole ground, compact: the soil bytes, ages in whole hours (0-255), deflated, and the earth's stored chunks.
## Used for the save (base64 in JSON) and the network (as is).
func pack() -> Dictionary:
	var ag := PackedByteArray()
	ag.resize(age.size())
	for i in age.size():
		ag[i] = clampi(int(roundf(age[i])), 0, 255)
	return {"v": 2, "nx": D.NX, "ny": D.NY, "ver": version,
		"s": _z(soil), "a": _z(ag), "vol": vol.pack(), "st": stats.duplicate()}

## Loads pack()'s output. Only what differs is touched (and redrawn). Returns false if it doesn't fit.
func unpack(p: Dictionary) -> bool:
	if int(p.get("v", 0)) != 2 or int(p.get("nx", 0)) != D.NX or int(p.get("ny", 0)) != D.NY:
		return false
	var sb := _unz(p.get("s"), soil.size())
	var ag := _unz(p.get("a"), age.size())
	if sb.is_empty() or ag.is_empty():
		return false
	for i in soil.size():
		var s := sb[i] if sb[i] <= D.DIRT else D.GRASS
		var a := float(ag[i])
		if s != soil[i] or (a >= D.WEEDY_HOURS) != (age[i] >= D.WEEDY_HOURS):
			_touch_cell(i % D.NX, i / D.NX)
		soil[i] = s
		age[i] = a
	vol.unpack(p.get("vol", {}))
	var st: Dictionary = p.get("st", {})
	for k in stats:
		stats[k] = int(st.get(k, stats[k]))
	version = maxi(version + 1, int(p.get("ver", 0)))
	changed.emit()
	return true

## Back to untouched grass.
func clear() -> void:
	soil.fill(0)
	age.fill(0.0)
	vol.clear()
	for k in stats:
		stats[k] = 0
	touch_all()
	_changed()

static func _z(b: PackedByteArray) -> PackedByteArray:
	return b.compress(FileAccess.COMPRESSION_DEFLATE)

static func _unz(b, n: int) -> PackedByteArray:
	if b is String:
		b = Marshalls.base64_to_raw(b)
	if not (b is PackedByteArray) or b.is_empty():
		return PackedByteArray()
	var out: PackedByteArray = b.decompress(n, FileAccess.COMPRESSION_DEFLATE)
	return out if out.size() == n else PackedByteArray()

## pack() made JSON-safe (byte arrays as base64), for the save file.
func to_json_dict() -> Dictionary:
	var p := pack()
	for k in ["s", "a"]:
		p[k] = Marshalls.raw_to_base64(p[k])
	var vp: Dictionary = p.vol
	var cs := {}
	for key in vp.cs:
		cs[key] = Marshalls.raw_to_base64(vp.cs[key])
	p.vol = {"v": vp.v, "cs": cs, "ver": vp.ver, "pl": Array(vp.pl)}
	return p
