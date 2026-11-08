extends SceneTree
## The Dig Site's cave-ins self-test (stage 7; headless: -s test/voxel/digsite_cave_test.gd -- --nosave), on a ground of
## its own (no arena): a 1 m tunnel through the dirt holds; a 4 m room dug in the dirt creaks (a warning), then its
## roof falls into it as loose dirt, nothing made or lost; the same room down in the stone holds (stone spans 6 m);
## a room with a post left in the middle holds (the post halves its span); a room that's going, held up by a post put
## in before it falls, settles instead. Owned by the voxel session.

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DSCAVE ok   ", what)
	else:
		failed += 1
		print("DSCAVE FAIL ", what)

func _grid() -> DigSiteGrid:
	var g := DigSiteGrid.new()
	g.setup(512, 192, 512, 160)
	DsMats.apply(g)
	g.generate(31)
	g.set_cave_ticks(10)
	return g

# a room (or tunnel): x0..x0+sx, z0..z0+sz, its floor y0, sy tall (air), from the inside: no opening to the top
func _room(g: DigSiteGrid, x0: int, y0: int, z0: int, sx: int, sy: int, sz: int) -> void:
	for y in range(y0, y0 + sy):
		for z in range(z0, z0 + sz):
			for x in range(x0, x0 + sx):
				g.set_cell(x, y, z, 0)

func _settle(g: DigSiteGrid, ticks: int) -> Array:
	var ev := []
	for i in ticks:
		g.settle(1000000)
		for v in g.take_cave_events():
			ev.append(v)
	return ev

func _kinds(ev: Array) -> Array:
	var k := []
	for i in range(0, ev.size() - 4, 5):
		k.append(ev[i])
	return k

func _counts(g: DigSiteGrid) -> Array:
	var out := []
	for m in range(1, 16):
		out.append(g.count_mat(m))
	return out

func _initialize() -> void:
	var g := _grid()
	var top := g.column_top(200, 200)
	print("DSCAVE   ground top %d; 2.5 m down: %s, 9 m down: %s" % [top, DsMats.name_of(g.get_cell(200, top - 20, 200)), DsMats.name_of(g.get_cell(200, top - 72, 200))])
	# a tunnel 1 m wide, 1.5 m tall, 10 m long, its roof 1 m under the ground
	_room(g, 100, top - 20, 100, 8, 12, 80)
	var ev := _settle(g, 120)
	check(not _kinds(ev).has(2) and g.count_box(100, top - 20, 100, 107, top - 9, 179, -3) == 0, "a 1 m tunnel through the dirt holds (%s)" % str(_kinds(ev)))
	check(g.roof_span_at(104, top - 8, 140) == 8, "its roof spans its width (%d cells)" % g.roof_span_at(104, top - 8, 140))
	# a 4 m room in the dirt
	_room(g, 300, top - 20, 300, 32, 12, 32)
	var c0 := _counts(g)
	ev = _settle(g, 200)
	var k := _kinds(ev)
	var loose := g.count_box(300, 0, 300, 331, 191, 331, -3)
	check(k.has(1) and k.has(2) and k.find(1) < k.find(2), "a 4 m room in the dirt: it creaks, then falls in (%s)" % str(k))
	check(loose > 100, "its roof came down loose (%d blocks)" % loose)
	check(_counts(g) == c0, "not a block made or lost")
	# the same room in the stone (9 m down)
	_room(g, 100, top - 84, 300, 32, 12, 32)
	ev = _settle(g, 150)
	check(not _kinds(ev).has(2), "the same room down in the stone holds (%s)" % str(_kinds(ev)))
	# a dirt room with a post left in its middle (as a support would)
	var g2 := _grid()
	var t2 := g2.column_top(200, 200)
	_room(g2, 200, t2 - 20, 200, 28, 12, 28)
	for y in range(t2 - 20, t2 - 8):
		for z in range(213, 215):
			for x in range(213, 215):
				g2.set_cell(x, y, z, DsMats.WOOD)
	ev = _settle(g2, 150)
	check(not _kinds(ev).has(2), "a 3.5 m room with a post in the middle holds (%s)" % str(_kinds(ev)))
	# a room that's going, a post put in before it falls
	_room(g2, 100, t2 - 20, 300, 24, 12, 24)
	var k3 := []
	for i in 4:
		g2.settle(1000000)
		k3.append_array(_kinds(Array(g2.take_cave_events())))
	check(k3.has(1), "a 3 m room starts to go (%s)" % str(k3))
	for y in range(t2 - 20, t2 - 8):
		for z in range(311, 313):
			for x in range(111, 113):
				g2.set_cell(x, y, z, DsMats.WOOD)
	ev = _settle(g2, 100)
	check(_kinds(ev).has(3) and not _kinds(ev).has(2), "held up in time, it settles (%s)" % str(_kinds(ev)))
	print("DSCAVE done %d passed, %d failed" % [passed, failed])
	quit()
