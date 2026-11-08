extends SceneTree
## The Dig Site ground's self-test (stage 2; headless: --fixed-fps 60 -s test/voxel/digsite_ground_test.gd -- --nosave):
## the grid's size, the same ground from the same seed, the materials by depth and the ore pockets; going there builds
## the sections near you (drawn, and solid close by) and nothing far off; you stand on it; a dig takes blocks out and
## rebuilds only the sections it touched; a frame's building keeps to its budget. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("DSGROUND ok   ", what)
	else:
		failed += 1
		print("DSGROUND FAIL ", what)

func _done() -> bool:
	print("DSGROUND done %d passed, %d failed" % [passed, failed])
	return true

func _next(s: int) -> void:
	step = s
	mark = t

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if t > 90.0:
		check(false, "timed out at step %d" % step)
		return _done()
	var ds: DigSite = arena.digsite
	match step:
		0:
			_grid_checks()
			arena.phone.travel("digsite")
			_next(1)
		1:
			if ds.active and not arena.phone._going and t - mark > 1.0:
				_near_checks(ds.terrain)
				# stand on the ground in the middle of the site
				var tr: DsTerrain = ds.terrain
				v.top = tr.top_at(DigSite.AT.x, DigSite.AT.z)
				ds._put(Vector3(DigSite.AT.x, v.top + 1.0, DigSite.AT.z), 0.0, -0.3)
				_next(2)
		2:
			var tr: DsTerrain = ds.terrain
			tr.step(50.0)
			if t - mark > 2.5:
				var y: float = arena.player.global_position.y
				check(absf(y - v.top) < 0.35, "standing on the ground in the middle (feet %.2f, ground %.2f)" % [y, v.top])
				_dig_checks(tr)
				_next(3)
		3:
			if t - mark > 0.5:
				_budget_checks(ds.terrain)
				# stage 4: a scoop's worth dumped again and again in one spot (in the game: the dirt runs each frame)
				var tr: DsTerrain = ds.terrain
				v.solid = tr.grid.count_box(0, 0, 0, 512, 192, 512, -1)
				v.dump = DigSite.AT + Vector3(-4, 0, 8)
				v.moves = tr.settle_moves
				var put := 0
				for k in 20:
					put += tr.dump(v.dump, DsMats.DIRT, 20)
				v.put = put
				v.top0 = tr.top_at(v.dump.x, v.dump.z)
				_next(4)
		4:
			if t - mark > 4.0:
				var tr: DsTerrain = ds.terrain
				var top := tr.top_at(v.dump.x, v.dump.z)
				var side := tr.top_at(v.dump.x + 0.75, v.dump.z)
				check(tr.settle_moves > int(v.moves) and top < float(v.top0) - 0.5, "dumped dirt slumps in the game (%d moves; its top %.2f -> %.2f m)" % [tr.settle_moves - int(v.moves), v.top0, top])
				check(side > DigSite.AT.y - 0.5 and tr.grid.count_box(0, 0, 0, 512, 192, 512, -1) == int(v.solid) + int(v.put), "into a pile, nothing made or lost (%d dumped)" % v.put)
				return _done()
	return false

func _grid_checks() -> void:
	var ds: DigSite = arena.digsite
	if not ds.built:
		ds._build()
	var g: DigSiteGrid = ds.terrain.grid
	check(g.get_w() == 512 and g.get_h() == 192 and g.get_d() == 512, "the grid: 512 x 192 x 512 cells (64 m x 24 m x 64 m)")
	var t0 := Time.get_ticks_msec()
	var g2 := DigSiteGrid.new()
	g2.setup(512, 192, 512, 160)
	DsMats.apply(g2)
	g2.generate(DigSite.SEED)
	var gen_ms := Time.get_ticks_msec() - t0
	var same := true
	for m in [DsMats.TOPSOIL, DsMats.DIRT, DsMats.STONE, DsMats.COAL, DsMats.GEM]:
		same = same and g.count_mat(m) == g2.count_mat(m)
	check(same, "the same seed, the same ground (made in %d ms)" % gen_ms)
	var g3 := DigSiteGrid.new()
	g3.setup(512, 192, 512, 160)
	DsMats.apply(g3)
	g3.generate(DigSite.SEED + 1)
	check(g3.count_mat(DsMats.COAL) != g.count_mat(DsMats.COAL), "another seed, other ground")
	# down the middle: topsoil, then dirt (or clay/sand), stone, hard rock, bedrock
	var cx := 256
	var cz := 256
	var top := g.column_top(cx, cz)
	var at_depth := func(m_down: float) -> int: return g.get_cell(cx, top - int(m_down / 0.125), cz) & DsMats.MASK
	check(at_depth.call(0.0) == DsMats.TOPSOIL, "the top's topsoil (%s)" % DsMats.name_of(at_depth.call(0.0)))
	var shallow := [DsMats.DIRT, DsMats.CLAY, DsMats.SAND, DsMats.GRAVEL]
	check(shallow.has(at_depth.call(1.5)), "1.5 m down: dirt or clay or sand (%s)" % DsMats.name_of(at_depth.call(1.5)))
	var by_depth := {}
	for y in range(top, 0, -1):
		var m: int = g.get_cell(cx, y, cz) & DsMats.MASK
		if not by_depth.has(m):
			by_depth[m] = (top - y) * 0.125
	var names := []
	for m in by_depth:
		names.append("%s %.1fm" % [DsMats.name_of(m), by_depth[m]])
	print("DSGROUND   down the middle: ", ", ".join(names))
	check(by_depth.has(DsMats.STONE) or by_depth.has(DsMats.COAL), "stone further down")
	check(by_depth.has(DsMats.HARDROCK), "hard rock deeper")
	check(g.get_cell(cx, 1, cz) & DsMats.MASK == DsMats.BEDROCK, "bedrock at the bottom")
	var ores := []
	for m in [DsMats.COAL, DsMats.IRON, DsMats.GOLD, DsMats.GEM, DsMats.SAND, DsMats.GRAVEL, DsMats.CLAY]:
		ores.append("%s %d" % [DsMats.name_of(m), g.count_mat(m)])
	print("DSGROUND   pockets: ", ", ".join(ores))
	check(g.count_mat(DsMats.COAL) > 0 and g.count_mat(DsMats.IRON) > 0 and g.count_mat(DsMats.GOLD) > 0 and g.count_mat(DsMats.GEM) > 0, "ore pockets: coal, iron, gold, gems")
	check(g.count_mat(DsMats.EDGE) > 0 and g.get_cell(0, g.column_top(0, 256), 256) & DsMats.MASK == DsMats.EDGE and g.get_cell(511, 100, 300) & DsMats.MASK == DsMats.EDGE, "an edge ring round it (never digs)")

func _near_checks(tr: DsTerrain) -> void:
	var p: Vector3 = arena.player.global_position
	var near_mesh := 0
	var near_col := 0
	var far := 0
	for i in tr._sec:
		var s: Dictionary = tr._sec[i]
		var c := tr._sec_centre(i)
		var d := Vector2(c.x - p.x, c.z - p.z).length()
		if d > DsTerrain.R_COL + 4.0 and s.get("body") != null:
			far += 1
		if d < 12.0 and s.get("mi") != null:
			near_mesh += 1
		if d < 10.0 and s.get("body") != null:
			near_col += 1
	print("DSGROUND   sections: %d of %d held, %d built" % [tr._sec.size(), tr.grid.section_count(), tr.built_n])
	check(near_mesh > 0, "arriving: the ground near you drawn (%d sections)" % near_mesh)
	check(near_col > 0, "... and solid (%d sections)" % near_col)
	check(far == 0, "solid only near you (%d far sections solid)" % far)
	var t0 := Time.get_ticks_usec()
	tr.build_now()
	print("DSGROUND   the whole site built in %.0f ms (the screen's black arriving)" % ((Time.get_ticks_usec() - t0) / 1000.0))

func _dig_checks(tr: DsTerrain) -> void:
	tr.step(50.0)                       # (anything left over first)
	var at := Vector3(DigSite.AT.x + 3.0, tr.top_at(DigSite.AT.x + 3.0, DigSite.AT.z), DigSite.AT.z)
	var before: int = tr.grid.count_box(0, 0, 0, 512, 192, 512, -1)
	var r: Dictionary = tr.dig(at, 0.5, 2)
	var after: int = tr.grid.count_box(0, 0, 0, 512, 192, 512, -1)
	check(int(r.n) > 50 and before - after == int(r.n), "a dig took %d blocks out (%d solid before, %d after)" % [r.n, before, after])
	var b0 := tr.built_n
	var built := tr.step(50.0)
	check(built >= 1 and built <= 8, "only the sections it touched rebuilt (%d)" % built)
	check(tr.top_at(at.x, at.z) < at.y - 0.3, "a hole there (top %.2f, was %.2f)" % [tr.top_at(at.x, at.z), at.y])
	var r2: Dictionary = tr.dig(at + Vector3(0, -6.0, 0), 0.5, 2)
	check(int(r2.refused) > 2 or int(r2.n) == 0 or int(r2.n) < 260, "a shovel can't dig rock (deep: %d taken, hardest refused %d)" % [r2.n, r2.refused])
	var _unused := b0

func _budget_checks(tr: DsTerrain) -> void:
	tr.grid.mark_all_dirty()
	var worst := 0.0
	var frames := 0
	var total := 0
	while frames < 400:
		var t0 := Time.get_ticks_usec()
		var n := tr.step(DsTerrain.BUDGET_MS)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		frames += 1
		total += n
		if n == 0:
			break
	print("DSGROUND   rebuilding everything near: %d sections over %d frames, worst frame %.1f ms" % [total, frames, worst])
	check(frames > 1, "a big rebuild's spread over frames (%d)" % frames)
	check(worst < 16.0, "no frame over 16 ms building (worst %.1f ms)" % worst)
