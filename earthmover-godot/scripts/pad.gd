class_name Pad
extends RefCounted
## A patch of ground to be brought to one height, inside a ring of pegs: a garden patch filled level by hand, a dam floor dug out,
## or a pad the scout ute pegged out. The ground inside is tinted to show what's still to do (red to take off, blue to fill, green
## done), and how much of it is within `tol_up` above or `tol_down` below `level` is what earns its stars.

var title := "PAD"
var outline := PackedVector2Array()    # the pegs, in order round it
var level := 0.0                        # m
## A road's: the height wanted follows the ground as it began, this many m under it, rather than being one `level`. -1: off.
var drop := -1.0
## A road's ends are open: no string across them.
var open_ends := false
var tol_up := 0.03
var tol_down := 0.03
## The cells that count: inside the outline, less `margin` m in from it (a dam's sloping sides aren't its floor).
var cells := PackedInt32Array()
## The cells to tint: everything inside the outline.
var shown := PackedInt32Array()

func _init(points: PackedVector2Array, at_level: float, up: float, down: float, margin := 0.0) -> void:
	outline = points
	level = at_level
	tol_up = up
	tol_down = down
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var a := DirtSim.cell_of(lo)
	var b := DirtSim.cell_of(hi)
	for j in range(maxi(a.y, 1), mini(b.y + 1, DirtSim.CELLS - 1)):
		for i in range(maxi(a.x, 1), mini(b.x + 1, DirtSim.CELLS - 1)):
			var p := Vector2(i, j) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M
			if not Geometry2D.is_point_in_polygon(p, outline):
				continue
			var n := j * DirtSim.CELLS + i
			shown.append(n)
			if margin <= 0.0 or _edge_gap(p) >= margin:
				cells.append(n)

## How far in from the nearest side of the outline.
func _edge_gap(p: Vector2) -> float:
	var least := INF
	for k in outline.size():
		var q := Geometry2D.get_closest_point_to_segment(p, outline[k], outline[(k + 1) % outline.size()])
		least = minf(least, p.distance_to(q))
	return least

func inside(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, outline)

func middle() -> Vector2:
	var c := Vector2.ZERO
	for p in outline:
		c += p
	return c / maxi(outline.size(), 1)

## The height wanted at a spot, in m.
func level_at(sim: DirtSim, p: Vector2) -> float:
	return sim.start_at(p) - drop if drop >= 0.0 else level

## The height wanted on a cell, in mm.
func want_mm(sim: DirtSim, n: int) -> int:
	if drop >= 0.0:
		if sim.start_ground.size() != sim.bed.size():
			sim.mark_start_ground()
		return sim.start_ground[n] - int(drop * 1000.0)
	return int(level * 1000.0)

## How much of it is at the height wanted, 0 to 1.
func score(sim: DirtSim) -> float:
	if cells.is_empty():
		return 0.0
	var up := int(tol_up * 1000.0)
	var down := int(tol_down * 1000.0)
	var good := 0
	for n in cells:
		var want := want_mm(sim, n)
		var h := sim.bed[n] + sim.soil[n]
		if h <= want + up and h >= want - down:
			good += 1
	return float(good) / cells.size()

## How much soil it still wants, in m3: what's to be dug out, and what's to be filled in.
func still_to_do(sim: DirtSim) -> Vector2:
	var cut := 0
	var fill := 0
	for n in shown:
		var want := want_mm(sim, n)
		var h := sim.bed[n] + sim.soil[n]
		if h > want:
			cut += h - want
		else:
			fill += want - h
	return Vector2(DirtSim.to_m3(cut), DirtSim.to_m3(fill))

## A road: a strip `half` m either side of the line through `points`, pegged down both sides and open at the ends. Only the cells at
## least `margin` m in from the pegs count, as the edges are hard to get to the inch.
static func along(points: PackedVector2Array, half: float, margin: float, up: float, down: float) -> Pad:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k in points.size():
		var dir := (points[mini(k + 1, points.size() - 1)] - points[maxi(k - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x)
		left.append(points[k] + side * half)
		right.append(points[k] - side * half)
	right.reverse()
	left.append_array(right)
	var p := Pad.new(left, 0.0, up, down)
	p.open_ends = true
	if margin <= 0.0:
		return p
	# Discs along the line, every half metre: a cell within one is far enough in.
	var keep := half - margin
	var near := {}
	var r := int(ceil(keep / DirtSim.CELL_M)) + 1
	for k in points.size() - 1:
		var a := points[k]
		var b := points[k + 1]
		var steps := maxi(int(ceil(a.distance_to(b) / 0.5)), 1)
		for s in steps + 1:
			var c := a.lerp(b, float(s) / steps)
			var at := DirtSim.cell_of(c)
			for j in range(at.y - r, at.y + r + 1):
				for i in range(at.x - r, at.x + r + 1):
					if (Vector2(i, j) * DirtSim.CELL_M - Vector2.ONE * DirtSim.HALF_M).distance_to(c) <= keep:
						near[j * DirtSim.CELLS + i] = true
	var kept := PackedInt32Array()
	for n in p.cells:
		if near.has(n):
			kept.append(n)
	p.cells = kept
	return p

## A ring of `count` points round a middle: an ellipse, for a round patch.
static func ring(c: Vector2, r: Vector2, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in count:
		var a := TAU * k / count
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return out

## A rectangle's four corners, in order round it.
static func box(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
