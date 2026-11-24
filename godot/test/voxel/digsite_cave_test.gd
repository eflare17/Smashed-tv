extends SceneTree
## The Dig Site's cave-ins self-test (stage 7; headless: -s test/voxel/digsite_cave_test.gd -- --nosave), on a ground of
## its own (no arena): a 1 m tunnel through the dirt holds; a 4 m room dug in the dirt creaks (a warning), then its
## roof falls into it as loose dirt, nothing made or lost; the same room down in the stone holds (stone spans 6 m);
## a room with a post left in the middle holds (the post halves its span); a room that's going, held up by a post put
## in before it falls, settles instead. And (dirt physics, stage 7) with the lumps: the middle of a roof that falls
## comes down as clods (DsCaves.lumps, 200 blocks an event at most), which land in the room and are put back there in
## whole blocks, nothing made or lost. Owned by the voxel session.

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
	_lumps()
	print("DSCAVE done %d passed, %d failed" % [passed, failed])
	quit()

# the 4 m room again on a ground of its own, its fall's middle as lumps (as DsCaves.poll does it in the site)
func _lumps() -> void:
	var g := _grid()
	var top := g.column_top(200, 200)
	var d := DsDirt.new()
	d.setup(g)
	d.cap_us = 0
	_room(g, 300, top - 20, 300, 32, 12, 32)
	var total: int = g.ground_mm()
	var over := 0               # (the ground's top over the room and round it, before)
	for z in range(290, 342):
		for x in range(290, 342):
			over += int(g.height_at(x + 0.5, z + 0.5) * 1000.0)
	var falls := 0
	var most := 0
	var went := 0
	var awake_most := 0
	var drift := 0
	var steps := 0
	var roofed := 0
	for i in 200:
		g.settle(1000000)
		var ev := g.take_cave_events()
		for j in range(0, ev.size() - 4, 5):
			if ev[j] == 2:
				falls += 1
				var n0 := d.n
				var n := DsCaves.lumps(g, d, ev[j + 1], ev[j + 2], ev[j + 3])
				most = maxi(most, n)
				went += n
				for q in range(n0, d.n):
					if d._roofed(q):
						roofed += 1
		# (the dirt ticks 10 times a second in the site: six clod steps to each)
		for s in 6:
			if d.n > 0:
				d.step(1.0 / 60.0)
				steps += 1
			awake_most = maxi(awake_most, d.n)
		drift = maxi(drift, absi(int(g.ground_mm()) + d.mass_mm() + d.owed_mm() - total))
	var made := d.settled_n + d.n + d.direct_n
	check(falls > 0 and went > 0 and most <= 200, "a 4 m room's roof falls: %d blocks of it come down as lumps (%d falls, %d at the most a fall: 200 at most)" % [went, falls, most])
	check(made > 0 and roofed == made, "%d clods, every one let go under the roof (%d awake at the most)" % [made, awake_most])
	check(drift == 0, "not a mm made or lost at any tick (%d)" % drift)
	# (a clod that lands where the whole roof's come down by then, the sky over it, is laid on the ground as any other)
	check(d.n == 0 and d.settled_n == made and d.buried_n * 10 >= d.settled_n * 9, "they all come to rest in the room: %d of %d put back in blocks under what's left of the roof, the rest where it's open to the sky by then (%d still awake after %d steps)" % [d.buried_n, d.settled_n, d.n, steps])
	var owed := d.owed_mm()
	d.land_all()
	var over2 := 0
	for z in range(290, 342):
		for x in range(290, 342):
			over2 += int(g.height_at(x + 0.5, z + 0.5) * 1000.0)
	check(int(g.ground_mm()) == total and d.mass_mm() + d.owed_mm() == 0, "after land_all it's all ground again (%d mm were owed)" % owed)
	print("DSCAVE   the ground's top over the room: %d before, %d after (cells x 1000, summed)" % [over, over2])
