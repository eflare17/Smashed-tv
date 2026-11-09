extends SceneTree
## The Dig Site's dirt self-test (stage 4; headless: -s test/voxel/digsite_dirt_test.gd -- --nosave), on a small grid of
## its own (no arena): the ground as made stays put; a heap of loose dirt dropped in one spot spreads to a pile at
## about 34 degrees, moving a little every tick (the loose layer, in mm: the owner, 9 Nov, "its still so jumpy"), not a
## block at a time; a shallow pit's firm walls stand, a deep one's give way (past their height) and fill it in part; a
## slide's work keeps to its time budget; and through all of it not a millimetre of anything is made or lost. Owned by
## the voxel session.

const W := 128
const H := 96
const D := 128
const SURF := 64
const MM := 125

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

# each material in mm (its blocks' 125 each and its loose layer)
func _counts(g: DigSiteGrid) -> Array:
	var out := []
	for m in 16:
		out.append(g.mat_mm(m))
	return out

# a tick as the game runs it: the loose layer every tick (60 a second), the cells every third (20 a second)
func _tick(g: DigSiteGrid, n: int, budget := 1000000) -> int:
	var moved := g.layer_step(budget)
	if n % 3 == 0:
		moved += g.settle(budget)
	return moved

# ticks till nothing's awake (or most): -> [ticks, moved]
func _settle(g: DigSiteGrid, most: int) -> Array:
	var ticks := 0
	var moves := 0
	while ticks < most and (g.awake_count() > 0 or g.layer_awake() > 0):
		moves += _tick(g, ticks)
		ticks += 1
	return [ticks, moves]

# the surface over the ground as made, in cells, at column (x, z)
func _over(g: DigSiteGrid, x: int, z: int) -> float:
	return g.height_at(x + 0.5, z + 0.5) - (g.start_top(x, z) + 1)

func _initialize() -> void:
	var g := _grid()
	var before := _counts(g)
	var total0: int = g.ground_mm()
	g.wake_all()
	g.layer_wake_all()
	var r := _settle(g, 400)
	check(int(r[1]) < 50 * MM, "the ground as made stays put (%d mm moved over %d ticks)" % [r[1], r[0]])

	# a heap of loose dirt dropped in the middle, a column at a time as from a bucket, ticking as it lands
	var cx := W / 2
	var cz := D / 2
	var heap := 1800
	var put := 0
	var ticks := 0
	while put < heap and ticks < 2000:
		put += g.drop_column(cx, cz, DsMats.DIRT, mini(24, heap - put))
		_tick(g, ticks)
		ticks += 1
	check(put == heap, "%d blocks dropped in one spot (%d ticks)" % [put, ticks])
	# as it slumps: how far any column's surface moves in a tick (a ring of them round the heap's foot and flank)
	var probe := []
	for k in range(4, 22, 3):
		for a in 8:
			probe.append(Vector2i(cx + roundi(k * cos(a * PI / 4.0)), cz + roundi(k * sin(a * PI / 4.0))))
	var was := []
	for p: Vector2i in probe:
		was.append(g.height_at(p.x + 0.5, p.y + 0.5))
	var worst_step := 0.0
	var moving_ticks := 0
	var t0 := Time.get_ticks_msec()
	var n := 0
	while n < 6000 and (g.awake_count() > 0 or g.layer_awake() > 0):
		_tick(g, ticks + n)
		n += 1
		var any := false
		for i in probe.size():
			var p: Vector2i = probe[i]
			var hh := g.height_at(p.x + 0.5, p.y + 0.5)
			var dh := absf(hh - float(was[i]))
			worst_step = maxf(worst_step, dh)
			any = any or dh > 0.0
			was[i] = hh
		if any:
			moving_ticks += 1
	print("DSDIRT   the heap settled in %d ticks (%.1f s at 60 a second, %d ms)" % [n, n / 60.0, Time.get_ticks_msec() - t0])
	check(g.awake_count() == 0 and g.layer_awake() == 0, "it comes to rest (nothing left awake)")
	check(worst_step < 0.5 and moving_ticks > 20, "it slides a little at a time: the most a surface moved in a tick was %.0f mm (a block's 125), over %d ticks" % [worst_step * MM, moving_ticks])
	var after := _counts(g)
	check(int(after[DsMats.DIRT]) == int(before[DsMats.DIRT]) + heap * MM, "not a millimetre of dirt made or lost (%d, %d)" % [after[DsMats.DIRT], int(before[DsMats.DIRT]) + heap * MM])
	var same := true
	for m in range(1, 16):
		if m != DsMats.DIRT and after[m] != before[m]:
			same = false
	check(same and g.ground_mm() == total0 + heap * MM, "nor of anything else")
	# its shape: how high in the middle, how far out it reaches (a quarter of a block over the ground as made)
	var high := _over(g, cx, cz)
	var reach := 0
	for k in range(1, 60):
		if _over(g, cx + k, cz) < 0.25 and _over(g, cx, cz - k) < 0.25:
			reach = k
			break
	var deg := rad_to_deg(atan(high / maxf(1.0, float(reach))))
	print("DSDIRT   the pile: %.1f blocks high, %d out: %.0f degrees" % [high, reach, deg])
	check(deg > 25.0 and deg < 42.0, "a pile at about 34 degrees (%.0f)" % deg)
	check(g.loose_mm() == heap * MM, "all of it still loose (%d mm)" % g.loose_mm())

	# pits: 1 m deep stands, 3 m deep gives way
	var g2 := _grid()
	var px := 36
	var pz := 36
	_pit(g2, px, pz, 12, 8)
	r = _settle(g2, 400)
	check(int(r[1]) == 0, "a 1 m pit's firm walls stand (%d moved)" % r[1])
	var qx := 92
	var qz := 92
	var t2 := g2.column_top(qx, qz)
	_pit(g2, qx, qz, 24, 24)
	var dug2: int = g2.ground_mm()
	var hard0 := _counts(g2)
	var in0 := _over_box(g2, qx, qz, 12)
	var t3 := Time.get_ticks_usec()
	var first := g2.settle(2000)
	var first_ms := (Time.get_ticks_usec() - t3) / 1000.0
	var t4 := Time.get_ticks_usec()
	var first_l := g2.layer_step(2000)
	var first_l_ms := (Time.get_ticks_usec() - t4) / 1000.0
	r = _settle(g2, 5000)
	var loose: int = g2.loose_mm()
	var in1 := _over_box(g2, qx, qz, 12)
	print("DSDIRT   the 3 m pit (ground at %d): %d mm moved over %d ticks, %d mm gave way, %d mm fell in" % [t2, r[1], r[0], loose, in1 - in0])
	check(loose > 50 * MM and in1 - in0 > 50 * MM, "a 3 m pit's walls give way and fill it in part (%d mm loose, %d in it)" % [loose, in1 - in0])
	var hard1 := _counts(g2)
	var rock_same := true
	for m in range(DsMats.STONE, 16):
		if hard0[m] != hard1[m]:
			rock_same = false
	check(g2.ground_mm() == dug2 and rock_same, "not a millimetre made or lost there either (%d, %d)" % [g2.ground_mm(), dug2])
	check(first_ms < 6.0 and first_l_ms < 6.0, "a slide's work keeps to its budget (cells %.1f ms, layer %.1f ms for 2 ms asked; %d, %d moved)" % [first_ms, first_l_ms, first, first_l])
	print("DSDIRT done %d passed, %d failed" % [passed, failed])
	quit()

# a square pit, side cells across, depth cells deep, from the ground's top there down (straight sides)
func _pit(g: DigSiteGrid, x0: int, z0: int, side: int, depth: int) -> void:
	var top := g.column_top(x0, z0)
	for y in range(top - depth + 1, top + 8):
		for z in range(z0 - side / 2, z0 + side / 2):
			for x in range(x0 - side / 2, x0 + side / 2):
				g.set_cell(x, y, z, 0)

# what stands in a box of columns round (x0, z0), in mm (its blocks and the loose layer on them)
func _over_box(g: DigSiteGrid, x0: int, z0: int, half: int) -> int:
	var n := 0
	for z in range(z0 - half, z0 + half):
		for x in range(x0 - half, x0 + half):
			n += g.count_box(x, 0, z, x, H, z, -1) * MM + (g.get_layer(x, z) & 255)
	return n
