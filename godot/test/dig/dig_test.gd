extends Node
## Digging and ploughing, tested inside the real game (scenes/main.tscn, which installs Dig after the farm).
## Run: godot --headless --path <copy> --fixed-fps 60 res://test/dig/dig_test.tscn
## Prints "PASS ..." / "FAIL ..." and "DIG TESTS: n passed, m failed" (exit code 1 if anything failed).

const D := preload("res://scripts/dig/dig_data.gd")
const U := 0.025

var main: Node
var dig: Dig
var player: Player
var passed := 0
var failed := 0

func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	_go.call_deferred()

func ok(c: bool, what: String) -> void:
	if c:
		passed += 1
		print("PASS ", what)
	else:
		failed += 1
		print("FAIL ", what)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _go() -> void:
	await frames(3)
	dig = main.get_node_or_null("Dig")
	player = main.player
	ok(dig != null and Dig.instance == dig, "installed: main/Dig")
	if dig == null:
		_done()
		return
	main.rig.capture_mouse = false
	dig.grid.clear()
	dig.ground.flush()
	await _t_ground()
	await _t_grid()
	await _t_collision()
	await _t_tools_and_player_dig()
	await _t_finds()
	await _t_fill()
	await _t_plough_plant_regrow()
	await _t_save_load()
	await _t_net()
	await _t_speed()
	_done()

func _done() -> void:
	print("DIG TESTS: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func put(x: float, y: float, face: Vector2) -> void:
	player.place(x, y)
	player.halt()
	player.facing = face
	player.look_ang = atan2(face.y, face.x)

# ---------------------------------------------------------------- the ground's meshes and the World's floor

func _t_ground() -> void:
	var w: Node3D = main.world
	var g := w.get_node_or_null("DigGround")
	ok(g != null, "the ground is in the World (lit with it)")
	var gm: MeshInstance3D = g.get_node_or_null("DigGrass")
	ok(gm != null and gm.mesh != null and gm.mesh.get_surface_count() == 1, "the grass is one mesh")
	var draws := 0
	for c in g.get_children():
		if c is MeshInstance3D and c.visible:
			draws += 1
	ok(draws <= 3, "the yard's ground is at most three draws (%d)" % draws)
	var wm: MeshInstance3D = w.get_node("WorldMesh")
	var hidden := false
	for i in wm.mesh.get_surface_count():
		var m := wm.get_surface_override_material(i)
		if m is ShaderMaterial and m.shader and m.shader.code.contains("discard"):
			hidden = true
	ok(hidden, "the World's flat yard floor is hidden")
	var grd: StaticBody3D = w.get_node("Ground")
	var plane := false
	for c in grd.get_children():
		if c is CollisionShape3D and c.shape is WorldBoundaryShape3D:
			plane = true
	ok(not plane, "the endless ground plane is gone (slabs round the region instead)")
	# the mask: open lawn yes; the shed, the garage, the tank, the trampoline, the crop beds, the house no
	var gr := dig.grid
	ok(gr.diggable_at(1100, 1300), "the lawn east of the trampoline is diggable")
	ok(gr.diggable_at(300, 1250) == false, "the vegetable patch isn't")
	for s in GameData.data.YARD_SOLIDS:
		var c := Vector2(float(s.cx), float(s.cy)) if s.has("r") else Vector2((float(s.x0) + float(s.x1)) / 2.0, (float(s.y0) + float(s.y1)) / 2.0)
		if gr.diggable_at(c.x, c.y):
			ok(false, "solid %s isn't diggable" % s.m)
	ok(gr.diggable_at(400, 300) == false and gr.diggable_at(700, 700) == false, "the house and the deck aren't")
	ok(gr.diggable_at(1100, 1100 - 0) and gr.diggable_at(1102, 1074) , "near the garage's front lawn")
	# a margin: right beside the shed's east wall (x 418) no
	ok(not gr.diggable_at(425, 1700), "a margin by the shed")

# ---------------------------------------------------------------- the depth grid

func _t_grid() -> void:
	var gr := dig.grid
	var x := 1100.0
	var y := 1300.0
	ok(gr.shovel_label(x, y) == "DIG", "the shovel says DIG on the lawn")
	var depths := []
	var bottom := false
	for i in 4:
		var r := gr.dig(x, y, Vector2.RIGHT, false)
		depths.append(r.get("depth", -1))
		bottom = r.get("bottom", false)
	ok(depths == [9.0, 18.0, 27.0, 36.0], "four presses: 9, 18, 27, 36 deep (%s)" % str(depths))
	ok(bottom, "the fourth reaches the bottom")
	ok(gr.shovel_label(x, y) == "FILL", "at the bottom the shovel says FILL")
	ok(not gr.dig(x, y).get("ok", true), "no deeper than waist-deep")
	ok(is_equal_approx(gr.depth_at(x + D.R_IN - 1, y), 36.0), "the hole's floor is flat to R_IN")
	ok(gr.depth_at(x + D.R_OUT + D.CELL, y) <= 0.0, "level ground past its rim")
	var pile := gr.depth_at(x + D.PILE_OFF, y)
	ok(pile < -10.0 and pile >= -D.PILE_MAX, "a pile beside it (%.1f up)" % -pile)
	ok(gr.soil_at(x, y) == D.DIRT, "the hole's cells are dirt")
	ok(gr.searched[DigGrid.cell_of(x, y).y * D.NX + DigGrid.cell_of(x, y).x] == 1, "the spot is searched")
	# a hole near the garage: never under it
	ok(gr.shovel_label(1100, 960) == "", "no hole under the garage")
	dig.ground.flush()

# ---------------------------------------------------------------- collision, and standing in the hole

func _t_collision() -> void:
	await frames(2)
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var hit_hole = _ray(space, 1100, 1300)
	var hit_flat = _ray(space, 1300, 1150)
	var hit_pile = _ray(space, 1100 + D.PILE_OFF, 1300)
	ok(hit_hole != null and absf(hit_hole + 36.0) < 0.6, "a ray down lands in the hole (%.2f)" % (hit_hole if hit_hole != null else 999.0))
	ok(hit_flat != null and absf(hit_flat) < 0.3, "and on the level lawn at 0 (%.2f)" % (hit_flat if hit_flat != null else 999.0))
	ok(hit_pile != null and hit_pile > 10.0, "and on top of the pile (%.2f)" % (hit_pile if hit_pile != null else -999.0))
	var hit_house = _ray(space, 400, 300)
	ok(hit_house != null and absf(hit_house) < 0.3, "the house floor is still solid")
	var hit_far = _ray(space, 3000, 3000)
	ok(hit_far != null and absf(hit_far) < 0.3, "and the ground past the region (the slabs)")
	# the player stands in it
	put(1100, 1300, Vector2(1, 0))
	await frames(6)
	ok(absf(player.global_position.y / U + 36.0) < 0.6, "standing in the hole he's 36 down (%.1f)" % (player.global_position.y / U))
	ok(player.html_pos().distance_to(Vector3(1100, 1300, player.html_pos().z)) < 2.0, "not shoved out by the walls")
	# walking out
	Input.action_press("move_right")
	await frames(60)
	Input.action_release("move_right")
	var hp := player.html_pos()
	ok(hp.x > 1180.0, "he walks out of it (x %.0f)" % hp.x)
	await frames(4)
	var want := dig.grid.height_at(hp.x, hp.y)
	ok(absf(player.global_position.y / U - want) < 0.6, "on the ground where he is (%.1f vs %.1f)" % [player.global_position.y / U, want])
	# first person: his eyes go down with him
	put(1100, 1300, Vector2(1, 0))
	main.rig.set_mode(CameraRig.Mode.FIRST_PERSON) if main.rig.has_method("set_mode") else null
	await frames(6)
	var cam := get_viewport().get_camera_3d()
	if cam:
		ok(cam.global_position.y / U < 40.0, "first person in the hole: eyes low (%.0f)" % (cam.global_position.y / U))
	if main.rig.has_method("set_mode"):
		main.rig.set_mode(CameraRig.Mode.TOP_DOWN)
	await frames(2)

func _ray(space: PhysicsDirectSpaceState3D, x: float, y: float):
	var q := PhysicsRayQueryParameters3D.create(GameData.world_to_3d(x, y, 400), GameData.world_to_3d(x, y, -400))
	q.collision_mask = 1
	var r := space.intersect_ray(q)
	if r.is_empty():
		return null
	return r.position.y / U

# ---------------------------------------------------------------- tools from the shed, digging with E

func _t_tools_and_player_dig() -> void:
	var rp := Dig.rack_pos("shovel")
	put(rp.x + 22, rp.y, Vector2(-1, 0))
	await frames(3)
	ok(player.focus_label == "TAKE SHOVEL", "at the shed: TAKE SHOVEL (%s)" % player.focus_label)
	player.use()
	ok(dig.tool_of(player) == "shovel", "he has the shovel")
	await frames(2)
	ok(player.focus_label == "PUT BACK SHOVEL", "then PUT BACK SHOVEL (%s)" % player.focus_label)
	ok(player.get_node_or_null("DigTool") != null, "the shovel's in his hand")
	# dig a fresh hole with E
	put(1300 - D.REACH, 1150, Vector2(1, 0))
	await frames(3)
	ok(player.focus_label == "DIG", "on the lawn E says DIG (%s)" % player.focus_label)
	for i in 4:
		player.use()
		await frames(2)
	ok(absf(dig.grid.depth_at(1300, 1150) - 36.0) < 0.01, "four E presses dig it waist-deep")
	ok(player.focus_label == "FILL", "then E says FILL")
	# not by the shed, not into the tank
	put(1380 - 120 - D.REACH, 1680, Vector2(1, 0))
	await frames(3)
	ok(player.focus_label != "DIG", "no digging by the tank (%s)" % player.focus_label)

# ---------------------------------------------------------------- finds

func _t_finds() -> void:
	var gr := dig.grid
	ok(gr.roll_find(0.1).kind == "spuds" and gr.roll_find(0.4).kind == "coins" and gr.roll_find(0.58).kind == "bone"
		and gr.roll_find(0.63).kind == "stash" and gr.roll_find(0.7).kind == "", "the find table: spuds, coins, bone, stash, nothing")
	var w := get_node_or_null("/root/Wallet")
	var c0: int = w.get_cash() if w else 0
	dig._award(player, "coins", 12, Vector2(1300, 1150))
	ok(w != null and w.get_cash() == c0 + 12, "coins go in the Wallet")
	var fm := Farm.instance
	var seeds0: int = fm.state.seed_count(0)
	dig._award(player, "stash", 150, Vector2(1300, 1150))
	ok(w.get_cash() == c0 + 162 and fm.state.seed_count(0) == seeds0 + 1, "a stash: cash and a rare seed")
	var ff = Fight.me.fighter_of(player) if Fight.me else null
	if ff:
		var a0: int = ff.ammo
		ff.ammo = 0
		dig._award(player, "spuds", 3, Vector2(1300, 1150))
		ok(ff.ammo == 3 * int(Fight.me.sim.tv("spudPellets", 10)), "spuds load the spud gun (%d)" % ff.ammo)
		ff.ammo = a0
	# over many holes, some finds and some nothing
	var n_find := 0
	var n_none := 0
	for i in 400:
		var f := gr.roll_find()
		if f.kind == "":
			n_none += 1
		else:
			n_find += 1
	ok(n_find > 200 and n_none > 100, "not every dig finds something (%d finds, %d nothing)" % [n_find, n_none])
	# each spot finds once
	var h0: int = gr.stats.holes
	var r := gr.dig(1300, 1150)
	ok(not r.get("ok", false) and gr.stats.holes == h0, "a dug spot doesn't find twice")

# ---------------------------------------------------------------- filling

func _t_fill() -> void:
	put(1300 - D.REACH, 1150, Vector2(1, 0))
	await frames(2)
	var pile0 := dig.grid.depth_at(1300, 1150 + D.PILE_OFF)
	var ev := InputEventAction.new()
	ev.action = "lobby_alt"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var ev2 := InputEventAction.new()
	ev2.action = "lobby_alt"
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await frames(1)
	ok(absf(dig.grid.depth_at(1300, 1150) - 27.0) < 0.01, "Q (lobby_alt) fills a step (%.1f)" % dig.grid.depth_at(1300, 1150))
	for i in 3:
		var r := dig.fill_at(player, Vector2(1300, 1150))
		print("fill ", r, " label ", player.focus_label)
		await frames(1)
	ok(dig.grid.depth_at(1300, 1150) == 0.0, "filled back to level (%.1f, he's at %s)" % [dig.grid.depth_at(1300, 1150), str(player.html_pos())])
	ok(dig.grid.depth_at(1300, 1150 + D.PILE_OFF) >= pile0, "the pile went back in")
	ok(dig.grid.soil_at(1300, 1150) == D.DIRT, "dug-over dirt where it was")
	await frames(2)
	ok(player.focus_label == "DIG", "and it can be dug again (%s)" % player.focus_label)

# ---------------------------------------------------------------- the hoe, planting, growing back

func _t_plough_plant_regrow() -> void:
	var x0 := 1060.0
	var y := 1460.0
	dig.set_tool(player, "")
	put(x0, y - 120, Vector2(1, 0))
	await frames(2)
	Input.action_press("move_right")
	var w0 := player.html_pos().x
	await frames(60)
	var walk := player.html_pos().x - w0
	Input.action_release("move_right")
	dig.set_tool(player, "hoe")
	put(x0, y, Vector2(1, 0))
	await frames(2)
	var c0: int = dig.grid.counts().rows
	Input.action_press("move_right")
	var t0 := player.html_pos().x
	await frames(60)
	var speed := (player.html_pos().x - t0)
	Input.action_release("move_right")
	await frames(20)
	var rows: int = dig.grid.counts().rows
	ok(rows - c0 >= int(speed / D.CELL) * 2, "walking with the hoe ploughs (%d cells over %.0f units)" % [rows - c0, speed])
	ok(speed < walk * 0.8, "and he's slower with it (%.0f, %.0f without)" % [speed, walk])
	ok(dig.grid.soil_at(x0 + 60, y) == D.ROWS_X, "furrows running the way he walked")
	# a second row below, so a spot has ploughed soil all round
	put(x0, y + 16, Vector2(1, 0))
	Input.action_press("move_right")
	await frames(60)
	Input.action_release("move_right")
	await frames(10)
	# plant
	var fm := Farm.instance
	fm.state.add_seed(0, 0, 3)
	fm.pick_seed(0, 0)
	dig.set_tool(player, "")
	var spot = null
	var sx := x0 + 40.0
	while sx < x0 + 200.0 and spot == null:
		spot = dig.grid.plant_spot(sx, y + 8)
		sx += 16.0
	ok(spot != null, "a planting spot on the ploughed rows")
	if spot == null:
		return
	put(spot.x - D.REACH, spot.y, Vector2(1, 0))
	await frames(3)
	ok(player.focus_label.begins_with("PLANT"), "on ploughed soil E says PLANT (%s)" % player.focus_label)
	player.use()
	await frames(3)
	var i: int = fm.state.field_near(spot.x, spot.y, 4.0)
	ok(i >= 0 and fm.state.plots[i].s == 0, "planted: a field plot with NL")
	var fw := main.get_node_or_null("FarmWorld")
	if fw and i >= 0:
		ok(fw.views[i].position.distance_to(GameData.world_to_3d(spot.x, spot.y, 0)) < 0.01, "its plant stands there")
	await frames(2)
	ok(not player.focus_label.begins_with("PLANT"), "then no PLANT there: the plot is the farm's (%s)" % player.focus_label)
	# the crop grows on the farm's clock
	fm.state.grow(1.0)
	ok(fm.state.plots[i].g > 0.0, "it grows like a bed's")
	# growing back: untended soil goes weedy, then grass; the crop's soil stays
	var far := Vector2(x0 + 8, y)
	dig.grow_back(D.WEEDY_HOURS + 1.0)
	var ci := DigGrid.cell_of(far.x, far.y)
	ok(dig.grid.weedy(ci.y * D.NX + ci.x), "after %d game hours untended soil is weedy" % int(D.WEEDY_HOURS + 1))
	var cs := DigGrid.cell_of(spot.x, spot.y)
	ok(not dig.grid.weedy(cs.y * D.NX + cs.x), "the crop's soil is tended")
	dig.grow_back(D.REGROW_HOURS)
	ok(dig.grid.soil_at(far.x, far.y) == D.GRASS, "then grass again")
	ok(dig.grid.soil_at(spot.x, spot.y) != D.GRASS and fm.state.plots[i].on, "the crop's soil stays, crop and all")
	# harvested, its soil grows back and the plot goes
	fm.state.plots[i].s = -1
	dig.grow_back(D.REGROW_HOURS + 1.0)
	ok(not fm.state.plots[i].on, "harvested and grown over: the field plot is freed")
	# on the clock: GameClock time moves the soil on too
	dig.grid.plough(1300, 1300, Vector2.RIGHT)
	var gc := get_node_or_null("/root/GameClock")
	if gc:
		await get_tree().create_timer(0.6).timeout
		gc.advance_hours(D.REGROW_HOURS + 2.0)
		await get_tree().create_timer(0.6).timeout
		ok(dig.grid.soil_at(1300, 1300) == D.GRASS, "the game clock grows it back")
	dig.ground.flush()

# ---------------------------------------------------------------- saving

func _t_save_load() -> void:
	var gr := dig.grid
	gr.dig(1150, 1700, Vector2.UP)
	gr.dig(1150, 1700, Vector2.UP)
	gr.plough(1500, 1300, Vector2.DOWN)
	var path := "user://dig_test_save.json"
	dig.save_path = path
	dig.persist = true
	dig.save()
	dig.persist = false
	var g2 := DigGrid.new()
	var f := FileAccess.open(path, FileAccess.READ)
	var dd = JSON.parse_string(f.get_as_text())
	f.close()
	ok(g2.unpack(dd), "the save loads")
	ok(g2.depth == gr.depth and g2.soil == gr.soil and g2.searched == gr.searched, "and it's the same ground")
	var sz := FileAccess.get_file_as_bytes(path).size()
	ok(sz < 20000, "the save is small (%d bytes)" % sz)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# the farm's field plots save with the farm
	var fm := Farm.instance
	var i := fm.state.field_plot(1400, 1400)
	fm.state.plant(i, 0, 0) if fm.state.seed_count(0) > 0 else null
	var fd := fm.state.to_dict()
	var st2 := FarmState.new()
	st2.from_dict(JSON.parse_string(JSON.stringify(fd)))
	ok(st2.plots[i].on and st2.plots[i].x == 1400.0 and st2.plots[i].s == fm.state.plots[i].s, "a field plot saves with the farm")
	fm.state.field_free(i)

# ---------------------------------------------------------------- online: ops and snapshots

func _t_net() -> void:
	var host := DigGrid.new()
	host.set_mask(dig.grid.mask)
	var guest := DigGrid.new()
	guest.set_mask(dig.grid.mask)
	# the guest digs; the host replays its op (no finds on the host)
	ok(guest.shovel_label(1250, 1350) == "DIG", "(a lawn spot)")
	guest.dig(1250, 1350, Vector2.RIGHT)
	var saved := dig.grid
	dig.grid = host
	dig.apply_op(["dig", 1250.0, 1350.0, 1.0, 0.0])
	dig.apply_op(["plough", PackedInt32Array([(170) * D.NX * 4 + 160 * 4 + D.ROWS_Y])])
	dig.grid = saved
	ok(host.depth == guest.depth and host.counts().off > 0, "the host replays a guest's dig")
	ok(host.diggable_cell(160, 170) and host.soil[170 * D.NX + 160] == D.ROWS_Y, "and its ploughing")
	ok(host.stats.coins == 0 and host.stats.spuds == 0, "without finds")
	# the host's snapshot puts the guest's ground right
	var p := host.pack()
	var bytes := var_to_bytes({"t": "dig", "k": "snap", "p": p}).compress(FileAccess.COMPRESSION_DEFLATE)
	ok(bytes.size() < 4000, "a snapshot is small (%d bytes)" % bytes.size())
	var g3 := DigGrid.new()
	g3.set_mask(dig.grid.mask)
	ok(g3.unpack(p) and g3.depth == host.depth and g3.soil == host.soil, "a snapshot loads on the guest")
	ok(g3.dirty.size() > 0 and g3.dirty.size() < 10, "redrawing only the chunks that changed (%d)" % g3.dirty.size())
	# the plough's API: painting soil
	var n := g3.set_soil(1300, 1300, 20, D.ROWS_Y)
	ok(n > 10 and g3.soil_at(1300, 1300) == D.ROWS_Y and g3.soil_at(1300, 1330) == D.GRASS, "set_soil paints a round patch (%d cells)" % n)

# ---------------------------------------------------------------- speed

func _t_speed() -> void:
	var t0 := Time.get_ticks_usec()
	for i in DigGrid.chunks_x() * DigGrid.chunks_y():
		dig.grid.dirty[i] = true
	dig.ground.flush()
	var all_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var n := DigGrid.chunks_x() * DigGrid.chunks_y()
	print("SPEED all %d chunks rebuilt in %.1f ms (%.2f ms a chunk)" % [n, all_ms, all_ms / n])
	t0 = Time.get_ticks_usec()
	var r := dig.grid.dig(1250, 1350, Vector2.RIGHT)
	dig.ground.flush()
	ok(r.get("ok", false), "(the timed dig dug)")
	var one_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("SPEED one dig, redrawn with collision: %.2f ms" % one_ms)
	ok(one_ms < 40.0, "a dig redraws fast natively (%.1f ms)" % one_ms)
