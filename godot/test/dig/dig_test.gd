extends Node
## Digging (level 3, smooth caves) and ploughing, tested inside the real game (scenes/main.tscn, which installs
## Dig after the farm).
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
	await _t_volume()
	await _t_collision()
	await _t_body()
	await _t_tools_and_digging()
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
	player.look_y = 0.0
	var b = dig._bodies.get(player.get_instance_id())
	if b:
		b.prev = Vector2(x, y)
		b.feet = dig.grid.vol.floor_below(x, y, D.ZMAX - 1.0) if dig.grid.vol.touched_near(x, y) else 0.0
		b.vz = 0.0
		b.climb = -INF

func walk(action: String, n: int) -> void:
	Input.action_press(action)
	await frames(n)
	Input.action_release(action)
	await frames(4)

# ---------------------------------------------------------------- the ground's meshes and the World's floor

func _t_ground() -> void:
	var w: Node3D = main.world
	var g := w.get_node_or_null("DigGround")
	ok(g != null, "the ground is in the World")
	var gm: MeshInstance3D = g.get_node_or_null("DigGrass")
	ok(gm != null and gm.mesh != null, "the flat yard is one mesh")
	ok(gm.material_override is ShaderMaterial and String(gm.material_override.shader.code).contains("dig_cut"), "drawn with the terrain shader (the cutaway)")
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
	var gr := dig.grid
	ok(gr.diggable_at(1100, 1300), "the lawn east of the trampoline is diggable")
	ok(not gr.diggable_at(300, 1250), "the vegetable patch isn't")
	for s in GameData.data.YARD_SOLIDS:
		var c := Vector2(float(s.cx), float(s.cy)) if s.has("r") else Vector2((float(s.x0) + float(s.x1)) / 2.0, (float(s.y0) + float(s.y1)) / 2.0)
		if gr.diggable_at(c.x, c.y):
			ok(false, "solid %s isn't diggable" % s.m)
	ok(not gr.diggable_at(400, 300) and not gr.diggable_at(700, 700), "the house and the deck aren't")
	ok(not gr.diggable_at(425, 1700), "a margin by the shed")

# ---------------------------------------------------------------- the earth

func _t_volume() -> void:
	var v := dig.grid.vol
	ok(v.chunks.is_empty() and is_equal_approx(v.surface_height(1100, 1300), 0.0), "untouched: flat at 0, nothing stored")
	ok(v.solid(1100, 1300, -100) and not v.solid(1100, 1300, 10), "earth below, air above")
	var out := v.carve(Vector3(1100, 1300, -60), Vector3(1100, 1300, 20), 20.0)
	dig.grid.mark_dug(1100, 1300, 24.0)
	ok(out.size() > 20, "a carve digs samples out (%d)" % out.size())
	ok(not v.solid(1100, 1300, -40), "the hole is air")
	var sh := v.surface_height(1100, 1300)
	ok(sh < -70.0 and sh > -85.0, "the hole's floor is about 80 down (%.1f)" % sh)
	ok(absf(v.surface_height(1160, 1300)) < 0.5, "the lawn beside it is still level")
	ok(not v.chunks.is_empty(), "the dug chunks are stored (%d)" % v.chunks.size())
	var before := v.chunks.size()
	v.carve(Vector3(1070, 700, -40), Vector3(1070, 700, 10), 20.0)
	ok(v.chunks.size() == before and v.solid(1070, 700, -20), "nothing digs under the garage")
	v.carve(Vector3(1100, 1300, -400), Vector3(1100, 1300, -300), 40.0)
	ok(v.solid(1100, 1300, D.ZMIN + 2.0), "bedrock stays")
	# the smooth mesh
	dig.ground.flush()
	var key := DigVolume.chunk_key(int((1100 - D.X0) / D.CELL), int((1300 - D.Y0) / D.CELL), int((-40 - D.ZMIN) / D.CELL))
	var mi: MeshInstance3D = dig.ground.get_node_or_null("Cave_%d_%d_%d" % [key.x, key.y, key.z])
	ok(mi != null and mi.mesh != null and mi.mesh.get_faces().size() > 30, "the hole is drawn smooth (%d triangles)" % (mi.mesh.get_faces().size() / 3 if mi and mi.mesh else 0))

# ---------------------------------------------------------------- collision

func _t_collision() -> void:
	dig.ground.flush()
	await frames(2)
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var hit_hole = _ray(space, 1100, 1300)
	var hit_flat = _ray(space, 1300, 1150)
	ok(hit_hole != null and hit_hole < -70.0, "a ray down lands in the hole (%.1f)" % (hit_hole if hit_hole != null else 999.0))
	ok(hit_flat != null and absf(hit_flat) < 0.5, "and on the level lawn at 0 (%.2f)" % (hit_flat if hit_flat != null else 999.0))
	var hit_house = _ray(space, 400, 300)
	ok(hit_house != null and absf(hit_house) < 0.3, "the house floor is still solid")
	var hit_far = _ray(space, 3000, 3000)
	ok(hit_far != null and absf(hit_far) < 0.3, "and the ground past the region (the slabs)")

func _ray(space: PhysicsDirectSpaceState3D, x: float, y: float):
	var q := PhysicsRayQueryParameters3D.create(GameData.world_to_3d(x, y, 400), GameData.world_to_3d(x, y, -400))
	q.collision_mask = 1
	var r := space.intersect_ray(q)
	if r.is_empty():
		return null
	return r.position.y / U

# ---------------------------------------------------------------- moving in the earth

func _t_body() -> void:
	var v := dig.grid.vol
	# a deep shaft: he falls to the bottom
	v.carve(Vector3(1350, 1250, -200), Vector3(1350, 1250, 20), 22.0)
	dig.ground.flush()
	player.place(1350, 1250)
	player.halt()
	await frames(90)
	var feet := dig.feet_of(player)
	ok(feet < -200.0, "he falls down a shaft to its floor (%.0f)" % feet)
	ok(absf(player.global_position.y / U - feet) < 1.0, "and stands there")
	# its walls hold him (too high to climb)
	await walk("move_right", 40)
	var hp := player.html_pos()
	ok(absf(hp.x - 1350) < 20.0, "the shaft's walls hold him (x %.0f)" % hp.x)
	# a tunnel along the bottom: he walks along it
	v.carve(Vector3(1350, 1250, feet + 30), Vector3(1470, 1250, feet + 30), 36.0)
	dig.ground.flush()
	await walk("move_right", 60)
	hp = player.html_pos()
	ok(hp.x > 1420.0, "along a tunnel (x %.0f)" % hp.x)
	ok(absf(dig.feet_of(player) - feet) < 12.0, "on its floor (%.0f)" % dig.feet_of(player))
	# a pit chest-deep: he climbs out of it
	v.carve(Vector3(1500, 1300, -30), Vector3(1500, 1360, -30), 26.0)
	dig.ground.flush()
	put(1500, 1340, Vector2(0, -1))
	await frames(20)
	var f0 := dig.feet_of(player)
	ok(f0 < -30.0, "in a pit (%.0f)" % f0)
	await walk("move_up", 90)
	ok(dig.feet_of(player) > -3.0 and player.html_pos().y < 1270.0, "he climbs out of it (feet %.0f, y %.0f)" % [dig.feet_of(player), player.html_pos().y])
	# untouched lawn: as before
	put(1300, 1150, Vector2(1, 0))
	await frames(4)
	ok(absf(player.global_position.y) < 0.001, "on the lawn he's at 0")

# ---------------------------------------------------------------- tools from the shed, digging with E

func _t_tools_and_digging() -> void:
	var rp := Dig.rack_pos("shovel")
	put(rp.x + 22, rp.y, Vector2(-1, 0))
	await frames(3)
	ok(player.focus_label == "TAKE SHOVEL", "at the shed: TAKE SHOVEL (%s)" % player.focus_label)
	player.use()
	ok(dig.tool_of(player) == "shovel", "he has the shovel")
	await frames(2)
	ok(player.get_node_or_null("DigTool") != null, "the shovel's in his hand")
	# standing still: the block under his feet; hits until it breaks
	dig.inv.res = [0, 0, 0, 0, 0]
	put(1250, 1350, Vector2(1, 0))
	await frames(3)
	ok(player.focus_label == "DIG DIRT", "on the lawn E says DIG DIRT (%s)" % player.focus_label)
	var tg := dig.block_target(player)
	ok(tg.b == DigVolume.block_of(Vector3(1250, 1350, -10)), "standing still he aims at the block under him")
	var b: Vector3i = tg.b
	var d0: int = dig.grid.stats.digs
	player.use()
	ok(dig.damage_of(b) > 0.0 and dig.damage_of(b) < 1.0 and dig.grid.stats.digs == d0, "a hit cracks it (%.2f) but it holds" % dig.damage_of(b))
	player.use()
	ok(dig.grid.stats.digs == d0 + 1, "dirt breaks in two shovel hits")
	ok(not dig.grid.vol.block_solid(b), "the block's gone")
	await frames(80)
	ok(int(dig.inv.res[D.DIRT_M]) >= 1, "it dropped dirt into his backpack (%d)" % dig.inv.res[D.DIRT_M])
	ok(dig.feet_of(player) < -20.0, "he drops into the hole (%.0f)" % dig.feet_of(player))
	# held, it keeps hitting: down a shaft
	var f0 := dig.feet_of(player)
	Input.action_press("interact")
	await frames(240)                        # (two seconds: 120 physics ticks a second)
	Input.action_release("interact")
	ok(dig.feet_of(player) < f0 - 50.0, "held, he digs on down (%.0f)" % dig.feet_of(player))
	ok(absf(player.html_pos().x - 1250) < 6.0, "straight down")
	# the materials: clay, then stone; harder; the pickaxe is better on stone
	var vol := dig.grid.vol
	ok(DigVolume.natural_material(Vector3i(0, 0, -1)) == D.DIRT_M, "near the top: dirt")
	var clay := 0
	var stone := 0
	var ore := 0
	for i in 60:
		var m1 := DigVolume.natural_material(Vector3i(i, 7, -5))
		var m2 := DigVolume.natural_material(Vector3i(i, 7, -9))
		clay += 1 if m1 == D.CLAY_M else 0
		stone += 1 if m2 == D.STONE_M else 0
		ore += 1 if m2 == D.IRON_M or m2 == D.COAL_M else 0
	ok(clay > 45 and stone > 40 and ore > 0, "deeper: clay, then stone with coal and iron in it (%d, %d, %d)" % [clay, stone, ore])
	ok(dig.tool_damage(player, D.STONE_M) < 0.5, "the shovel is poor on stone")
	dig.set_tool(player, "pickaxe")
	ok(dig.tool_damage(player, D.STONE_M) > 1.5, "the pickaxe is good on it")
	dig.set_tool(player, "shovel")
	# walking: the block ahead
	put(1500, 1350, Vector2(1, 0))
	player.moving = true
	tg = dig.block_target(player)
	ok(tg.b != null and DigVolume.block_centre(tg.b).x > 1500.0, "walking he aims ahead")
	# first person: where he looks
	main.rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	await frames(3)
	player.look_ang = 0.0
	player.look_y = 0.35
	tg = dig.block_target(player)
	ok(tg.b != null and DigVolume.block_centre(tg.b).x > 1510.0 and DigVolume.block_centre(tg.b).z < 0.0, "first person: the block he looks at (%s)" % str(tg.get("b")))
	player.look_y = 0.0
	main.rig.set_mode(CameraRig.Mode.TOP_DOWN)
	await frames(2)
	# placing: Q puts a block from the backpack where he aims (not into anyone)
	dig.inv.res = [3, 0, 0, 0, 0]
	put(1240, 1150, Vector2(1, 0))
	await frames(3)
	tg = dig.block_target(player)
	ok(tg.get("place") != null, "there's somewhere to place a block (%s)" % str(tg.get("place")))
	var pb = tg.place
	ok(dig.place_now(player), "Q places it")
	ok(vol.block_solid(pb) and int(dig.inv.res[D.DIRT_M]) == 2, "a dirt block stands there, one used")
	ok(vol.material(pb) == D.DIRT_M, "made of dirt")
	ok(not dig._block_has_player(pb), "not inside him")
	await walk("move_right", 40)
	ok(player.html_pos().x < DigVolume.block_centre(pb).x - 10.0 or dig.feet_of(player) > 20.0, "it's solid: a wall, or he climbs onto it (x %.0f, feet %.0f)" % [player.html_pos().x, dig.feet_of(player)])
	dig.inv.res = [0, 0, 0, 0, 0]
	ok(not dig.can_place(player), "nothing to place with an empty backpack")
	# the pickaxe: bought at the rack; the workbench upgrades
	var w := get_node_or_null("/root/Wallet")
	dig.inv.pickaxe = false
	var pp := Dig.rack_pos("pickaxe")
	put(pp.x + 22, pp.y, Vector2(-1, 0))
	await frames(3)
	ok(player.focus_label.begins_with("BUY PICKAXE"), "the rack sells a pickaxe (%s)" % player.focus_label)
	var cash0: int = w.get_cash()
	player.use()
	ok(dig.inv.pickaxe and w.get_cash() == cash0 - D.PICKAXE_PRICE, "bought")
	await frames(2)
	player.use()
	ok(dig.tool_of(player) == "pickaxe", "and taken")
	dig.inv.res = [0, 0, 0, 0, 4]
	var dmg0 := dig.tool_damage(player, D.STONE_M)
	put(D.BENCH.x + 22, D.BENCH.y, Vector2(-1, 0))
	await frames(3)
	ok(player.focus_label.begins_with("UPGRADE PICKAXE"), "the workbench offers an upgrade (%s)" % player.focus_label)
	player.use()
	ok(int(dig.inv.tiers.pickaxe) == 1 and dig.tool_damage(player, D.STONE_M) > dmg0 * 1.5 and int(dig.inv.res[D.IRON_M]) == 0, "an iron pickaxe: harder hits, the iron used")
	player.use()
	ok(int(dig.inv.tiers.pickaxe) == 1, "steel needs more than he has")
	dig.set_tool(player, "shovel")
	# not by the tank
	put(1380 - 140 - D.REACH, 1680, Vector2(1, 0))
	await frames(3)
	ok(not player.focus_label.begins_with("DIG"), "no digging by the tank (%s)" % player.focus_label)
	# the cutaway: top-down and underground, the earth over him isn't drawn
	put(1350, 1250, Vector2(1, 0))
	await frames(40)
	dig._update_cut()
	ok(dig.cut_on, "underground top-down: the earth over him is cut away")
	put(1300, 1150, Vector2(1, 0))
	await frames(3)
	dig._update_cut()
	ok(not dig.cut_on, "back on top: nothing cut")

# ---------------------------------------------------------------- finds

func _t_finds() -> void:
	ok(Dig.find_at(10, 20, 30) == Dig.find_at(10, 20, 30), "a find hangs on its place (both screens agree)")
	var counts := {}
	var total := [0, 0, 0]
	var found := [0, 0, 0]
	for k in [36, 25, 12]:
		var band := 0 if k == 36 else (1 if k == 25 else 2)
		for j in 100:
			for i in 100:
				total[band] += 1
				var f := Dig.find_at(i, j, k)
				if not f.is_empty():
					found[band] += 1
					counts[f.kind] = int(counts.get(f.kind, 0)) + 1
	for b in 3:
		var rate: float = float(found[b]) / float(total[b])
		ok(absf(rate - float(D.FIND_P[b])) < float(D.FIND_P[b]) * 0.35, "band %d: about %.2f%% of the earth hides something (%.2f%%)" % [b, D.FIND_P[b] * 100.0, rate * 100.0])
	ok(counts.has("spuds") and counts.has("gem") and counts.has("fossil") and counts.has("stash"), "spuds near the top, gems and fossils deep (%s)" % str(counts))
	# a find pops out and he picks it up
	var w := get_node_or_null("/root/Wallet")
	var c0: int = w.get_cash() if w else 0
	put(1300, 1150, Vector2(1, 0))
	await frames(2)
	for old in dig._pickups.duplicate():
		dig._pickups.erase(old)
		old.queue_free()
	dig._spawn_pickup({"kind": "coins", "n": 12}, Vector3(1320, 1150, -10))
	ok(dig._pickups.size() == 1, "a find pops out")
	await frames(100)
	if not dig._pickups.is_empty():
		var land: Vector3 = dig._pickups[0]._land
		put(land.x - 6, land.y, Vector2(1, 0))
		await frames(10)
	ok(dig._pickups.is_empty() and w.get_cash() == c0 + 12, "walking over it picks it up: coins into the Wallet")
	var fm := Farm.instance
	var seeds0: int = fm.state.seed_count(0)
	dig._award(player, "stash", 150, Vector2(1300, 1150))
	ok(w.get_cash() == c0 + 162 and fm.state.seed_count(0) == seeds0 + 1, "a stash: cash and a rare seed")
	dig._award(player, "gem", 70, Vector2(1300, 1150))
	ok(w.get_cash() == c0 + 232, "a gem: cash")
	var ff = Fight.me.fighter_of(player) if Fight.me else null
	if ff:
		var a0: int = ff.ammo
		ff.ammo = 0
		dig._award(player, "spuds", 3, Vector2(1300, 1150))
		ok(ff.ammo == 3 * int(Fight.me.sim.tv("spudPellets", 10)), "spuds load the spud gun (%d)" % ff.ammo)
		ff.ammo = a0

# ---------------------------------------------------------------- filling

func _t_fill() -> void:
	# a hole filled back in with blocks: level again, dug-over dirt
	var v := dig.grid.vol
	var b := DigVolume.block_of(Vector3(1600, 1220, -16))
	var c := DigVolume.block_centre(b)
	dig.break_block(b, null)
	ok(v.surface_height(c.x, c.y) < -20.0, "a hole to fill")
	ok(v.fill_block(b, D.DIRT_M), "a block back in it")
	ok(absf(v.surface_height(c.x, c.y)) < 3.0, "level again (%.1f)" % v.surface_height(c.x, c.y))
	ok(dig.grid.soil_at(c.x, c.y) == D.DIRT, "dug-over dirt where it was")

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
	var walkd := player.html_pos().x - w0
	Input.action_release("move_right")
	dig.set_tool(player, "hoe")
	put(x0, y, Vector2(1, 0))
	await frames(2)
	var c0: int = dig.grid.counts().rows
	Input.action_press("move_right")
	var t0 := player.html_pos().x
	await frames(60)
	var speed := player.html_pos().x - t0
	Input.action_release("move_right")
	await frames(20)
	var rows: int = dig.grid.counts().rows
	ok(rows - c0 >= int(speed / D.CELL) * 2, "walking with the hoe ploughs (%d cells over %.0f units)" % [rows - c0, speed])
	ok(speed < walkd * 0.8, "and he's slower with it (%.0f, %.0f without)" % [speed, walkd])
	ok(dig.grid.soil_at(x0 + 60, y) == D.ROWS_X, "furrows running the way he walked")
	put(x0, y + 16, Vector2(1, 0))
	await walk("move_right", 60)
	var fm := Farm.instance
	fm.state.add_seed(0, 0, 4)
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
	fm.state.grow(1.0)
	ok(fm.state.plots[i].g > 0.0, "it grows like a bed's")
	# dug over and filled in: plantable too
	var v := dig.grid.vol
	v.carve(Vector3(1200, 1184, -20), Vector3(1200, 1184, 10), 22.0)
	dig.grid.mark_dug(1200, 1184, 40.0)
	for k in 12:
		for o in [Vector2(0, 0), Vector2(16, 8), Vector2(-14, 10), Vector2(10, -14), Vector2(-12, -12), Vector2(24, 0), Vector2(0, 24)]:
			var q: Vector2 = Vector2(1200, 1184) + o
			var h := v.surface_height(q.x, q.y)
			if h < -1.0:
				dig.fill(Vector3(q.x, q.y, h + 4.0), D.FILL_R)
	ok(dig.grid.plant_spot(1200, 1184) != null, "dug-over and filled-in ground can be planted")
	ok(dig.grid.plant_spot(1100, 1300) == null, "not down in a hole")
	# growing back
	var far := Vector2(x0 + 8, y)
	dig.grow_back(D.WEEDY_HOURS + 1.0)
	var ci := DigGrid.cell_of(far.x, far.y)
	ok(dig.grid.weedy(ci.y * D.NX + ci.x), "after %d game hours untended soil is weedy" % int(D.WEEDY_HOURS + 1))
	var cs := DigGrid.cell_of(spot.x, spot.y)
	ok(not dig.grid.weedy(cs.y * D.NX + cs.x), "the crop's soil is tended")
	dig.grow_back(D.REGROW_HOURS)
	ok(dig.grid.soil_at(far.x, far.y) == D.GRASS, "then grass again")
	ok(dig.grid.soil_at(spot.x, spot.y) != D.GRASS and fm.state.plots[i].on, "the crop's soil stays, crop and all")
	ok(dig.grid.soil_at(1100, 1300) == D.DIRT, "a hole's ground stays dirt")
	fm.state.plots[i].s = -1
	dig.grow_back(D.REGROW_HOURS + 1.0)
	ok(not fm.state.plots[i].on, "harvested and grown over: the field plot is freed")
	dig.ground.flush()

# ---------------------------------------------------------------- saving

func _t_save_load() -> void:
	var gr := dig.grid
	var path := "user://dig_test_save.json"
	dig.save_path = path
	dig.persist = true
	dig.save()
	dig.persist = false
	var g2 := DigGrid.new()
	g2.set_mask(gr.mask)
	var f := FileAccess.open(path, FileAccess.READ)
	var dd = JSON.parse_string(f.get_as_text())
	f.close()
	ok(g2.unpack(dd), "the save loads")
	var same := g2.soil == gr.soil and g2.vol.chunks.size() == gr.vol.chunks.size()
	for key in gr.vol.chunks:
		if not g2.vol.chunks.has(key) or g2.vol.chunks[key].d != gr.vol.chunks[key].d:
			same = false
	ok(same, "and it's the same ground (%d chunks)" % gr.vol.chunks.size())
	var sz := FileAccess.get_file_as_bytes(path).size()
	ok(sz < 200000, "the save is small enough (%d bytes)" % sz)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var fm := Farm.instance
	var i := fm.state.field_plot(1400, 1400)
	var fd := fm.state.to_dict()
	var st2 := FarmState.new()
	st2.from_dict(JSON.parse_string(JSON.stringify(fd)))
	ok(st2.plots[i].on and st2.plots[i].x == 1400.0, "a field plot saves with the farm")
	fm.state.field_free(i)

# ---------------------------------------------------------------- online: ops and snapshots

func _t_net() -> void:
	var host := DigGrid.new()
	host.set_mask(dig.grid.mask)
	var saved := dig.grid
	dig.grid = host
	dig.apply_op(["carve", 1250.0, 1350.0, -60.0, 1250.0, 1350.0, 10.0, 18.0])
	dig.apply_op(["carve", 1250.0, 1350.0, -60.0, 1250.0, 1350.0, 10.0, 18.0])    # (twice: the same)
	dig.apply_op(["plough", PackedInt32Array([170 * D.NX * 4 + 160 * 4 + D.ROWS_Y])])
	var guest := DigGrid.new()
	guest.set_mask(saved.mask)
	dig.grid = guest
	dig.apply_op(["carve", 1250.0, 1350.0, -60.0, 1250.0, 1350.0, 10.0, 18.0])
	dig.grid = saved
	var same := true
	for key in host.vol.chunks:
		if not guest.vol.chunks.has(key) or guest.vol.chunks[key].d != host.vol.chunks[key].d:
			same = false
	ok(same and not host.vol.chunks.is_empty(), "an op digs the same on both games (and twice is once)")
	ok(host.diggable_cell(160, 170) and host.soil[170 * D.NX + 160] == D.ROWS_Y, "ploughing goes over too")
	# blocks broken and placed: the same on both
	dig.grid = host
	dig.apply_op(["break", 39, 30, -1])
	dig.apply_op(["place", 39, 31, 0, D.STONE_M])
	dig.grid = guest
	dig.apply_op(["break", 39, 30, -1])
	dig.apply_op(["place", 39, 31, 0, D.STONE_M])
	dig.grid = saved
	ok(not host.vol.block_solid(Vector3i(39, 30, -1)) and host.vol.block_solid(Vector3i(39, 31, 0)) and host.vol.material(Vector3i(39, 31, 0)) == D.STONE_M,
		"a broken block and a placed stone one go over")
	ok(guest.vol.placed == host.vol.placed, "both games know what the placed block is")
	ok(host.stats.coins == 0 and host.stats.spuds == 0, "without finds")
	var p := host.pack()
	var bytes := var_to_bytes({"t": "dig", "k": "snap", "p": p}).compress(FileAccess.COMPRESSION_DEFLATE)
	ok(bytes.size() < 20000, "a snapshot is small (%d bytes)" % bytes.size())
	var g3 := DigGrid.new()
	g3.set_mask(saved.mask)
	ok(g3.unpack(p) and g3.vol.chunks.size() == host.vol.chunks.size() and g3.soil == host.soil, "a snapshot loads on the guest")

# ---------------------------------------------------------------- speed

func _t_speed() -> void:
	var v := dig.grid.vol
	var keys := v.chunks.keys()
	var t0 := Time.get_ticks_usec()
	for key in keys:
		dig.ground._build_cave(key)
	var all_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("SPEED %d dug chunks drawn in %.1f ms (%.2f ms a chunk)" % [keys.size(), all_ms, all_ms / maxf(1.0, keys.size())])
	dig.ground.flush()
	v.dirty.clear()
	t0 = Time.get_ticks_usec()
	dig.carve(Vector3(1450, 1500, -30), Vector3(1450, 1500, 50), D.DIG_R)
	var carve_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var n := v.dirty.size()
	t0 = Time.get_ticks_usec()
	for key in v.dirty.keys():
		dig.ground._build_cave(key)
	var each := (Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, n)
	v.dirty.clear()
	print("SPEED one dig: %.2f ms to dig, then %d chunks to redraw at %.2f ms each (one a frame)" % [carve_ms, n, each])
	ok(carve_ms < 10.0 and each < 15.0, "a dig is fast enough natively (%.1f ms, %.1f ms a chunk)" % [carve_ms, each])
	t0 = Time.get_ticks_usec()
	for i in 120:
		dig._move_body(player, 1.0 / 120.0, true)
	print("SPEED a second of his steps on the earth: %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
