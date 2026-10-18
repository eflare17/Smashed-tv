class_name DigGrid
extends RefCounted
## The yard's ground as data (PLAN.md "Later: digging", level 2): a depth grid over the yard and what each cell's
## surface is (grass, ploughed rows, dug-over dirt), with the rules for digging, filling, ploughing, regrowing
## and finds. No nodes, so the headless tests drive it directly; DigGround draws it and gives it collision, Dig
## runs the tools, saving and the network. A later voxel level 3 can seed itself from depth (see depth_at).
##
## Layout: cells of D.CELL units from (D.X0, D.Y0), D.NX x D.NY of them; depths on their corners (vertices,
## (NX + 1) x (NY + 1)), in HTML units, positive down (a hole), negative up (a dirt pile). Kept on the half unit
## (D.QUANT) so a save or a snapshot (int8) gives back exactly the same ground.

const D := preload("res://scripts/dig/dig_data.gd")

## Something changed: the chunks to redraw are in dirty.
signal changed

var depth := PackedFloat32Array()      # per vertex
var soil := PackedByteArray()          # per cell: D.GRASS, ROWS_X, ROWS_Y, DIRT
var age := PackedFloat32Array()        # per cell: game hours untended (ploughed soil and dirt grow back)
var searched := PackedByteArray()      # per cell: 1 once a hole there reached the bottom (each spot finds once)
var mask := PackedByteArray()          # per cell: 1 diggable (grass in the yard, clear of everything solid)
var vmask := PackedByteArray()         # per vertex: 1 if every cell round it is diggable
## Chunk index -> true: chunks whose look changed since the last redraw.
var dirty: Dictionary = {}
## Chunk index -> true: chunks whose corner depths changed (the heightmap's to update).
var hdirty: Dictionary = {}
## Bumped on every change (the network sends only changed grids).
var version := 0
var stats := {"holes": 0, "spuds": 0, "coins": 0, "bones": 0, "stashes": 0, "ploughed": 0}
var rng := RandomNumberGenerator.new()

const VW := D.NX + 1
const VH := D.NY + 1

func _init() -> void:
	rng.randomize()
	depth.resize(VW * VH)
	soil.resize(D.NX * D.NY)
	age.resize(D.NX * D.NY)
	searched.resize(D.NX * D.NY)
	set_mask(PackedByteArray())

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

func vdepth(vx: int, vy: int) -> float:
	return depth[vy * VW + vx]

## How deep the ground is at (x, y), units (positive down; negative on a pile), between the corners.
func depth_at(x: float, y: float) -> float:
	if not in_region(x, y):
		return 0.0
	var fx := clampf((x - D.X0) / D.CELL, 0.0, D.NX - 0.0001)
	var fy := clampf((y - D.Y0) / D.CELL, 0.0, D.NY - 0.0001)
	var cx := int(fx)
	var cy := int(fy)
	var tx := fx - cx
	var ty := fy - cy
	var a := depth[cy * VW + cx]
	var b := depth[cy * VW + cx + 1]
	var c := depth[(cy + 1) * VW + cx]
	var d := depth[(cy + 1) * VW + cx + 1]
	# the two triangles the mesh and the heightmap use (split corner a to d)
	if tx >= ty:
		return a + (b - a) * tx + (d - b) * ty
	return a + (d - c) * tx + (c - a) * ty

## The ground's height at (x, y), units up (the negative of depth_at).
func height_at(x: float, y: float) -> float:
	return -depth_at(x, y)

func diggable_cell(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < D.NX and cy < D.NY and mask[cy * D.NX + cx] == 1

func diggable_at(x: float, y: float) -> bool:
	var c := cell_of(x, y)
	return c.x >= 0 and mask[c.y * D.NX + c.x] == 1

func soil_at(x: float, y: float) -> int:
	var c := cell_of(x, y)
	return soil[c.y * D.NX + c.x] if c.x >= 0 else D.GRASS

## A cell is flat grass (drawn with the yard picture) when its soil is grass and its corners are all level.
func cell_flat(cx: int, cy: int) -> bool:
	if soil[cy * D.NX + cx] != D.GRASS:
		return false
	var i := cy * VW + cx
	return depth[i] == 0.0 and depth[i + 1] == 0.0 and depth[i + VW] == 0.0 and depth[i + VW + 1] == 0.0

## How many cells are ploughed (rows) or dug over, and how many vertices are off level.
func counts() -> Dictionary:
	var rows := 0
	var dirt := 0
	for s in soil:
		if s == D.ROWS_X or s == D.ROWS_Y:
			rows += 1
		elif s == D.DIRT:
			dirt += 1
	var off := 0
	for v in depth:
		if v != 0.0:
			off += 1
	return {"rows": rows, "dirt": dirt, "off": off}

## ---------------------------------------------------------------- the shovel

## What the shovel would do at (x, y): "DIG", "FILL" (the hole there is at the bottom), or "" (can't dig here).
func shovel_label(x: float, y: float) -> String:
	if not _hole_fits(x, y):
		return ""
	return "FILL" if depth_at(x, y) >= D.MAX_DEPTH - 0.01 else "DIG"

## Can a hole go here? Every vertex within R_OUT must be diggable (so holes are whole, with a margin from solids).
func _hole_fits(x: float, y: float) -> bool:
	if not diggable_at(x, y):
		return false
	var r := int(ceil(D.R_OUT / D.CELL))
	var c := cell_of(x, y)
	for vy in range(c.y - r, c.y + r + 2):
		for vx in range(c.x - r, c.x + r + 2):
			if vx < 0 or vy < 0 or vx >= VW or vy >= VH:
				return false
			var px := D.X0 + vx * D.CELL
			var py := D.Y0 + vy * D.CELL
			if Vector2(px - x, py - y).length() <= D.R_OUT and vmask[vy * VW + vx] == 0:
				return false
	return true

## One press of the shovel at (x, y): the hole goes STEP deeper (to MAX_DEPTH) and the pile beside it (on side,
## a unit vector from the hole: where the dirt is thrown) grows. Returns {ok, depth, bottom (just reached it),
## find (the find's kind or ""), n} ; the find is rolled when the hole first reaches the bottom at a spot not
## searched before (award false: the caller already knows, e.g. replaying a guest's dig on the host).
func dig(x: float, y: float, side: Vector2 = Vector2.RIGHT, award: bool = true) -> Dictionary:
	if not _hole_fits(x, y):
		return {"ok": false}
	var before := depth_at(x, y)
	if before >= D.MAX_DEPTH - 0.01:
		return {"ok": false, "depth": before}
	var level := minf(D.MAX_DEPTH, _q(before + D.STEP))
	_shape_hole(x, y, level, true)
	_grow_pile(x, y, side, D.PILE_PER_STEP)
	var out := {"ok": true, "depth": depth_at(x, y), "bottom": false, "find": "", "n": 0}
	if level >= D.MAX_DEPTH - 0.01:
		out.bottom = true
		var c := cell_of(x, y)
		var i := c.y * D.NX + c.x
		if searched[i] == 0:
			# this spot and the cells right round it are searched now
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if diggable_cell(c.x + ox, c.y + oy):
						searched[(c.y + oy) * D.NX + c.x + ox] = 1
			stats.holes += 1
			if award:
				var f := roll_find()
				out.find = f.kind
				out.n = f.n
				_count_find(f)
	_changed()
	return out

## One press filling the hole at (x, y) back in by STEP, taking dirt back from the nearest pile. Returns
## {ok, depth}. Filled to the top, it's dug-over dirt (grows back to grass).
func fill(x: float, y: float) -> Dictionary:
	if not _hole_fits(x, y):
		return {"ok": false}
	var before := depth_at(x, y)
	if before <= 0.01:
		return {"ok": false, "depth": before}
	var level := maxf(0.0, _q(before - D.STEP))
	_shape_hole(x, y, level, false)
	_take_pile(x, y, D.PILE_PER_STEP)
	_changed()
	return {"ok": true, "depth": depth_at(x, y)}

## The hole's shape at level: flat to R_IN, sloping to the rim at R_OUT. Deeper only (dig) or shallower only (fill).
func _shape_hole(x: float, y: float, level: float, deeper: bool) -> void:
	var r := int(ceil(D.R_OUT / D.CELL)) + 1
	var c := cell_of(x, y)
	for vy in range(maxi(0, c.y - r), mini(VH, c.y + r + 2)):
		for vx in range(maxi(0, c.x - r), mini(VW, c.x + r + 2)):
			var i := vy * VW + vx
			if vmask[i] == 0:
				continue
			var dist := Vector2(D.X0 + vx * D.CELL - x, D.Y0 + vy * D.CELL - y).length()
			if dist > D.R_OUT:
				continue
			var k := 1.0 if dist <= D.R_IN else 1.0 - (dist - D.R_IN) / (D.R_OUT - D.R_IN)
			var want := _q(level * k)
			var old := depth[i]
			var nv := maxf(old, want) if deeper else (minf(old, want) if old > 0.0 else old)
			if nv != old:
				depth[i] = nv
				_touch_vertex(vx, vy)
	# the hole's cells are dirt from now on (drawn as dug ground; filled in, it grows back)
	var rc := int(ceil(D.R_OUT / D.CELL))
	for cy in range(c.y - rc, c.y + rc + 1):
		for cx in range(c.x - rc, c.x + rc + 1):
			if diggable_cell(cx, cy) and Vector2(D.X0 + (cx + 0.5) * D.CELL - x, D.Y0 + (cy + 0.5) * D.CELL - y).length() <= D.R_OUT:
				_set_soil(cx, cy, D.DIRT)

## Where the pile for a hole at (x, y) goes: PILE_OFF on the side given (or the other side, or ahead, if that's
## no good), or null if nowhere fits.
func pile_spot(x: float, y: float, side: Vector2):
	var s := side.normalized() if side.length() > 0.001 else Vector2.RIGHT
	for d in [s, -s, Vector2(-s.y, s.x), Vector2(s.y, -s.x)]:
		var p: Vector2 = Vector2(x, y) + d * D.PILE_OFF
		if _pile_fits(p):
			return p
	return null

func _pile_fits(p: Vector2) -> bool:
	if not diggable_at(p.x, p.y):
		return false
	var c := cell_of(p.x, p.y)
	var r := int(ceil(D.PILE_R / D.CELL)) + 1
	for vy in range(c.y - r, c.y + r + 2):
		for vx in range(c.x - r, c.x + r + 2):
			if Vector2(D.X0 + vx * D.CELL - p.x, D.Y0 + vy * D.CELL - p.y).length() > D.PILE_R + 2.0:
				continue
			if vx < 0 or vy < 0 or vx >= VW or vy >= VH or vmask[vy * VW + vx] == 0:
				return false
			if depth[vy * VW + vx] > 0.0:
				return false               # (not into another hole)
	return true

func _grow_pile(x: float, y: float, side: Vector2, h: float) -> void:
	# an existing pile near the hole takes the dirt; else a new one on the side given
	var near = _nearest_pile(x, y, D.PILE_OFF + D.PILE_R)
	var p = near if near != null else pile_spot(x, y, side)
	if p == null:
		return
	_bump(p, -h, -D.PILE_MAX)

func _take_pile(x: float, y: float, h: float) -> void:
	var p = _nearest_pile(x, y, D.PILE_FIND)
	if p != null:
		_bump(p, h, 0.0)

## Raises (dh < 0: depth goes negative) or lowers a round mound at p, its top held to limit.
func _bump(p: Vector2, dh: float, limit: float) -> void:
	var c := cell_of(p.x, p.y)
	var r := int(ceil(D.PILE_R / D.CELL)) + 1
	for vy in range(maxi(0, c.y - r), mini(VH, c.y + r + 2)):
		for vx in range(maxi(0, c.x - r), mini(VW, c.x + r + 2)):
			var i := vy * VW + vx
			if vmask[i] == 0:
				continue
			var dist := Vector2(D.X0 + vx * D.CELL - p.x, D.Y0 + vy * D.CELL - p.y).length()
			if dist > D.PILE_R:
				continue
			var k := 0.5 + 0.5 * cos(PI * dist / D.PILE_R)      # a soft round mound
			var old := depth[i]
			var nv := old
			if dh < 0.0:
				if old > 0.0:
					continue
				nv = maxf(limit * k, old + dh * k)
			else:
				if old >= 0.0:
					continue
				nv = minf(0.0, old + dh * k)
			nv = _q(nv)
			if nv != old:
				depth[i] = nv
				_touch_vertex(vx, vy)
	var rc := int(ceil(D.PILE_R / D.CELL))
	for cy in range(c.y - rc, c.y + rc + 1):
		for cx in range(c.x - rc, c.x + rc + 1):
			if diggable_cell(cx, cy) and Vector2(D.X0 + (cx + 0.5) * D.CELL - p.x, D.Y0 + (cy + 0.5) * D.CELL - p.y).length() <= D.PILE_R * 0.8:
				_set_soil(cx, cy, D.DIRT)

## The top of the nearest pile within r of (x, y), or null: the nearest raised vertex, then the highest point of
## its mound.
func _nearest_pile(x: float, y: float, r: float):
	var c := cell_of(x, y)
	var n := int(ceil(r / D.CELL))
	var near = null
	var near_d := INF
	for vy in range(maxi(0, c.y - n), mini(VH, c.y + n + 2)):
		for vx in range(maxi(0, c.x - n), mini(VW, c.x + n + 2)):
			if depth[vy * VW + vx] >= -0.01:
				continue
			var dist := Vector2(D.X0 + vx * D.CELL - x, D.Y0 + vy * D.CELL - y).length()
			if dist <= r and dist < near_d:
				near = Vector2i(vx, vy)
				near_d = dist
	if near == null:
		return null
	var m := int(ceil(D.PILE_R / D.CELL))
	var top: Vector2i = near
	for vy in range(maxi(0, near.y - m), mini(VH, near.y + m + 1)):
		for vx in range(maxi(0, near.x - m), mini(VW, near.x + m + 1)):
			if depth[vy * VW + vx] < depth[top.y * VW + top.x]:
				top = Vector2i(vx, vy)
	return Vector2(D.X0 + top.x * D.CELL, D.Y0 + top.y * D.CELL)

## ---------------------------------------------------------------- finds

func roll_find(r: float = -1.0) -> Dictionary:
	if r < 0.0:
		r = rng.randf()
	var acc := 0.0
	for f in D.FINDS:
		acc += float(f.p)
		if r < acc:
			return {"kind": f.kind, "n": rng.randi_range(int(f.min), int(f.max))}
	return {"kind": "", "n": 0}

func _count_find(f: Dictionary) -> void:
	match String(f.kind):
		"spuds": stats.spuds += int(f.n)
		"coins": stats.coins += int(f.n)
		"bone": stats.bones += 1
		"stash": stats.stashes += 1

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
	if not diggable_cell(cx, cy):
		return false
	var i := cy * D.NX + cx
	var v := cy * VW + cx
	if depth[v] != 0.0 or depth[v + 1] != 0.0 or depth[v + VW] != 0.0 or depth[v + VW + 1] != 0.0:
		return false
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

## ---------------------------------------------------------------- planting on ploughed soil

## The planting spot nearest (x, y) (on the SPOT grid, in the middle of a furrow), if the soil round it is
## ploughed; else null.
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
			var s := soil[cy * D.NX + cx]
			if s != D.ROWS_X and s != D.ROWS_Y:
				return null
	return p

## ---------------------------------------------------------------- growing back

## Game hours pass: untended soil ages; weedy after WEEDY_HOURS, grass again after REGROW_HOURS. tended: points
## (Vector2, HTML units) with a crop, which keep the soil within TEND_R fresh. Holes and piles stay as they are.
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
		if _cell_off_level(cx, cy):
			continue                         # (a hole's or a pile's ground stays dirt)
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

func _cell_off_level(cx: int, cy: int) -> bool:
	var v := cy * VW + cx
	return depth[v] != 0.0 or depth[v + 1] != 0.0 or depth[v + VW] != 0.0 or depth[v + VW + 1] != 0.0

## ---------------------------------------------------------------- bookkeeping

static func _q(v: float) -> float:
	return roundf(v * D.QUANT) / D.QUANT

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

## A vertex changed: the chunks of the (up to four) cells round it.
func _touch_vertex(vx: int, vy: int) -> void:
	for c in [[vx - 1, vy - 1], [vx, vy - 1], [vx - 1, vy], [vx, vy]]:
		if c[0] >= 0 and c[1] >= 0 and c[0] < D.NX and c[1] < D.NY:
			var k := chunk_of_cell(c[0], c[1])
			dirty[k] = true
			hdirty[k] = true

func _changed() -> void:
	version += 1
	changed.emit()

func touch_all() -> void:
	for i in chunks_x() * chunks_y():
		dirty[i] = true
		hdirty[i] = true

## ---------------------------------------------------------------- saving and sending

## The whole ground, compact: int8 depths (half units), the soil bytes, ages in whole hours (0-255), the searched
## bits; each deflated. Used for the save (base64 in JSON) and the network (as is).
func pack() -> Dictionary:
	var dq := PackedByteArray()
	dq.resize(depth.size())
	for i in depth.size():
		dq.encode_s8(i, clampi(int(roundf(depth[i] * D.QUANT)), -127, 127))
	var ag := PackedByteArray()
	ag.resize(age.size())
	for i in age.size():
		ag[i] = clampi(int(roundf(age[i])), 0, 255)
	return {"v": 1, "nx": D.NX, "ny": D.NY, "ver": version,
		"d": _z(dq), "s": _z(soil), "a": _z(ag), "f": _z(searched), "st": stats.duplicate()}

## Loads pack()'s output. Only what differs is touched (and redrawn). Returns false if it doesn't fit.
func unpack(p: Dictionary) -> bool:
	if int(p.get("v", 0)) != 1 or int(p.get("nx", 0)) != D.NX or int(p.get("ny", 0)) != D.NY:
		return false
	var dq := _unz(p.get("d"), depth.size())
	var sb := _unz(p.get("s"), soil.size())
	var ag := _unz(p.get("a"), age.size())
	var fb := _unz(p.get("f"), searched.size())
	if dq.is_empty() or sb.is_empty() or ag.is_empty() or fb.is_empty():
		return false
	for i in depth.size():
		var v := dq.decode_s8(i) / D.QUANT
		if v != depth[i]:
			depth[i] = v
			_touch_vertex(i % VW, i / VW)
	for i in soil.size():
		var s := sb[i] if sb[i] <= D.DIRT else D.GRASS
		var a := float(ag[i])
		if s != soil[i] or (a >= D.WEEDY_HOURS) != (age[i] >= D.WEEDY_HOURS):
			_touch_cell(i % D.NX, i / D.NX)
		soil[i] = s
		age[i] = a
	searched = fb
	var st: Dictionary = p.get("st", {})
	for k in stats:
		stats[k] = int(st.get(k, stats[k]))
	version = maxi(version + 1, int(p.get("ver", 0)))
	changed.emit()
	return true

## Back to untouched grass.
func clear() -> void:
	depth.fill(0.0)
	soil.fill(0)
	age.fill(0.0)
	searched.fill(0)
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
	for k in ["d", "s", "a", "f"]:
		p[k] = Marshalls.raw_to_base64(p[k])
	return p
