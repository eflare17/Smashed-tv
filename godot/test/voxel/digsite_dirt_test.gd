extends SceneTree
## The Dig Site's dirt self-test (stage 4; headless: -s test/voxel/digsite_dirt_test.gd -- --nosave), on a small grid of
## its own (no arena): the ground as made stays put; a heap of loose dirt dropped in one spot spreads to a pile at
## about 34 degrees; a shallow pit's firm walls stand, a deep one's give way (past their height) and fill it in part;
## a slide's work keeps to its time budget; and through all of it not one block of anything is made or lost. Owned by
## the voxel session.

const W := 128
const H := 96
const D := 128
const SURF := 64

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DSDIRT ok   ", what)
	else:
		failed += 1
		print("DSDIRT FAIL ", what)

func _grid() -> DigSiteGrid:
	var g := DigSiteGrid.new()
	g.setup(W, H, D, SURF)
	DsMats.apply(g)
	g.generate(77)
	return g

func _counts(g: DigSiteGrid) -> Array:
	var out := []
	for m in 16:
		out.append(g.count_mat(m))
	return out

# settles till nothing's awake (or most ticks): -> [ticks, moves]
func _settle(g: DigSiteGrid, most: int) -> Array:
	var ticks := 0
	var moves := 0
	while ticks < most and g.awake_count() > 0:
		moves += g.settle(1000000)
		ticks += 1
	return [ticks, moves]

func _initialize() -> void:
	var g := _grid()
	var before := _counts(g)
	g.wake_all()
	var r := _settle(g, 400)
	check(int(r[1]) < 50, "the ground as made stays put (%d moves over %d ticks)" % [r[1], r[0]])

	# a heap of loose dirt dropped in the middle
	var cx := W / 2
	var cz := D / 2
	var base := g.column_top(cx, cz)
	var heap := 1800
	var put := 0
	while put < heap:
		put += g.drop_column(cx, cz, DsMats.DIRT, heap - put)
		g.settle(1000000)
	var dirt_before: int = before[DsMats.DIRT] + heap
	var t0 := Time.get_ticks_msec()
	r = _settle(g, 5000)
	print("DSDIRT   the heap settled in %d ticks (%d moves, %d ms)" % [r[0], r[1], Time.get_ticks_msec() - t0])
	check(g.awake_count() == 0, "it comes to rest (nothing left awake)")
	var after := _counts(g)
	check(after[DsMats.DIRT] == dirt_before, "not a block of dirt made or lost (%d, %d)" % [after[DsMats.DIRT], dirt_before])
	var same := true
	for m in range(1, 16):
		if m != DsMats.DIRT and after[m] != before[m]:
			same = false
	check(same, "nor of anything else")
	# its shape: how high in the middle, how far out it reaches (a cell or more of dirt over the ground as made)
	var top := g.column_top(cx, cz)
	var high := top - base
	var reach := 0
	for k in range(1, 60):
		var hx := g.column_top(cx + k, cz)
		var hz := g.column_top(cx, cz - k)
		if g.get_cell(cx + k, hx, cz) & DsMats.LOOSE == 0 and g.get_cell(cx, hz, cz - k) & DsMats.LOOSE == 0:
			reach = k
			break
	var slope := float(high) / maxf(1.0, float(reach))
	var deg := rad_to_deg(atan(slope))
	print("DSDIRT   the pile: %d cells high, %d out: %.0f degrees" % [high, reach, deg])
	check(deg > 25.0 and deg < 42.0, "a pile at about 34 degrees (%.0f)" % deg)
	check(g.count_box(0, 0, 0, W, H, D, -3) == heap, "all of it still loose (%d)" % g.count_box(0, 0, 0, W, H, D, -3))

	# pits: 1 m deep stands, 3 m deep gives way
	var g2 := _grid()
	var c0 := _counts(g2)
	var px := 36
	var pz := 36
	var t1 := g2.column_top(px, pz)
	_pit(g2, px, pz, 12, 8)
	var dug := _counts(g2)
	r = _settle(g2, 400)
	check(int(r[1]) == 0, "a 1 m pit's firm walls stand (%d moves)" % r[1])
	var qx := 92
	var qz := 92
	var t2 := g2.column_top(qx, qz)
	_pit(g2, qx, qz, 24, 24)
	var dug2 := _counts(g2)
	var in0 := g2.count_box(qx - 12, 0, qz - 12, qx + 11, H, qz + 11, -1)
	var t3 := Time.get_ticks_usec()
	var first := g2.settle(2000)
	var first_ms := (Time.get_ticks_usec() - t3) / 1000.0
	r = _settle(g2, 5000)
	var loose := g2.count_box(0, 0, 0, W, H, D, -3)
	var in1 := g2.count_box(qx - 12, 0, qz - 12, qx + 11, H, qz + 11, -1)
	print("DSDIRT   the 3 m pit (ground at %d): %d moves over %d ticks, %d blocks gave way, %d fell in" % [t2, r[1], r[0], loose, in1 - in0])
	check(loose > 50 and in1 - in0 > 50, "a 3 m pit's walls give way and fill it in part (%d blocks loose, %d in it)" % [loose, in1 - in0])
	var same2 := true
	for m in 16:
		if dug2[m] != _counts(g2)[m]:
			same2 = false
	check(same2, "not a block made or lost there either")
	check(first_ms < 6.0, "a slide's work keeps to its budget (%.1f ms for 2 ms asked, %d moved)" % [first_ms, first])
	var _u := [c0, dug, t1]
	print("DSDIRT done %d passed, %d failed" % [passed, failed])
	quit()

# a square pit, side cells across, depth cells deep, from the ground's top there down (straight sides)
func _pit(g: DigSiteGrid, x0: int, z0: int, side: int, depth: int) -> void:
	var top := g.column_top(x0, z0)
	for y in range(top - depth + 1, top + 8):
		for z in range(z0 - side / 2, z0 + side / 2):
			for x in range(x0 - side / 2, x0 + side / 2):
				g.set_cell(x, y, z, 0)
