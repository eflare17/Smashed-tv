extends SceneTree
## The pixel mine's self-test (headless: --fixed-fps 60 -s test/voxel/mine_test.gd -- --nosave [--seed=N]): the roller
## door, going down, the ground (its zones, ores deeper and richer, its caves and hazards), drilling down and
## sideways cell by cell, ore into nuggets into the hold (and lost when it's full), dirt into the launcher's hopper,
## the fuel, selling, the upgrades, a boulder needing a better drill, gas going off, lava running out, sand falling and
## water pooling, a lone bit of lava settling, the mushroom trip, the bunker's alarm and being busted, the rival crew,
## the rats, the worm (killed: its hoard), dynamite, the launcher (clay sticks where it lands), saving and loading,
## the tow when the fuel's gone, where you left the ship underground, coming back up. Owned by the voxel session.

var arena: Node
var m: VoxelMine
var g: MineGround
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v := {}

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--seed="):
			seed(int(x.trim_prefix("--seed=")))
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("MINE ok   ", what)
	else:
		failed += 1
		print("MINE FAIL ", what)

## The ship sat on a floor at x, depth: a ship-sized hole dug there (and room ahead), a stone floor under it
func sit(x: float, depth: float) -> Vector2:
	var at := Vector2(x, -depth + MineShip.HALF + 0.01)
	g.set_box(at, Vector2(0.5, 0.46), MineTiles.AIR)
	g.set_box(at + Vector2(0, -0.6), Vector2(0.55, 0.12), MineTiles.STONE)
	m.ship.place(at)
	m.ship.grounded = true
	return at

## Cells of a material in a band of depths (metres)
func band(mat: int, d0: float, d1: float) -> int:
	var y0 := int(MineGround.dy(d0))
	var y1 := int(MineGround.dy(d1))
	return g.sim.count_rect(0, y0, MineGround.CW, y1 - y0, mat)

## The material most of a row of cells at a depth is (ignoring what's dug)
func zone_at(depth: float) -> int:
	var best := 0
	var bn := 0
	var y := int(MineGround.dy(depth))
	for mt in [MineTiles.DIRT, MineTiles.CLAY, MineTiles.STONE, MineTiles.RED, MineTiles.BASALT, MineTiles.CRYSTAL]:
		var n := g.sim.count_rect(MineGround.C, y, MineGround.CW - 2 * MineGround.C, 2, mt)
		if n > bn:
			bn = n
			best = mt
	return best

## A spot on a mushroom cave's floor (its own back wall, open, with ground under it)
func mush_floor(c: Array) -> Vector2:
	for dx in range(0, int(float(c[2]) * 8.0)):
		for sgn in [1, -1]:
			var x: float = float(c[0]) + sgn * dx / 8.0
			for dd in range(0, int((float(c[3]) * 2 + 1) * 8.0)):
				var p := Vector2(x, -(float(c[1]) - float(c[3]) + dd / 8.0))
				if g.bg_at(p) == MineTiles.BG_MUSH and g.mat_at(p) == MineTiles.AIR and g.solid_at(p + Vector2(0, -0.125)) \
						and g.count(p + Vector2(0, 0.45), Vector2(0.4, 0.4), -1) == 0:
					return MineGround.world(MineGround.cell(p)) + Vector2(0, -0.0625)
	return Vector2(float(c[0]), -float(c[1]))

func next(s: int) -> void:
	step = s
	mark = t
	if m and g:
		m.fuel = m.tank_max()         # (each check on its own: not towed for running dry, nor wrecked, mid-test)
		m.hull = maxf(m.hull, m.hull_max())

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	var e := t - mark
	match step:
		0:
			m = arena.mine
			arena.waves.queue.clear()
			arena.godmode = true
			arena.frozen = true
			arena.cash = 100
			check(m != null and m.hatch != null, "the roller door's in the yard")
			arena.player.global_position = Vector3(MineHatch.AT.x, 0.05, MineHatch.AT.z + 1.0)
			arena.top_down = false
			arena.look_yaw = 0.0
			arena.look_pitch = -0.15
			next(1)
		1:
			if e > 0.4:
				check(arena._near_hatch, "looking at it: the prompt (%s)" % arena._use_label.text)
				m.enter()
				next(2)
		2:
			if e > 1.2:
				g = m.ground
				check(m.active and m._going == 0, "down the mine")
				check(arena.get_viewport().disable_3d, "the arena's not drawn while you're down there")
				check(g.sim.get_w() == MineGround.CW and g.sim.get_h() == MineGround.CH, "the pixel world: %d x %d cells" % [MineGround.CW, MineGround.CH])
				var zones := [zone_at(10), zone_at(35), zone_at(68), zone_at(104), zone_at(138)]
				check(zones[0] in [MineTiles.DIRT, MineTiles.CLAY] and zones[1] == MineTiles.STONE and zones[2] == MineTiles.RED and zones[3] == MineTiles.BASALT and zones[4] == MineTiles.CRYSTAL,
					"the depth zones: %s" % [zones])
				var coal := band(MineTiles.COAL, 0, 50)
				var dia_top := band(MineTiles.DIAMOND, 0, 90)
				var dia := band(MineTiles.DIAMOND, 90, MineGround.D)
				var gold := band(MineTiles.GOLD, 45, MineGround.D)
				check(coal > 500 and gold > 300 and dia > 150 and dia_top == 0, "ores (cells): coal near the top %d, gold deeper %d, diamonds only deep %d (shallow: %d)" % [coal, gold, dia, dia_top])
				var f := g.features
				check(f.caves.size() == 5 and f.has("cathedral") and f.has("worm"), "five mushroom caves, the cathedral, the worm's cavern")
				check(f.sewer.size() == 2 and f.has("bunker") and f.rival.size() > 50, "the trial hazards: sewers %d, bunker %s, rival tunnels %d spots" % [f.sewer.size(), f.get("bunker"), f.rival.size()])
				check(band(MineTiles.SHROOM, 90, 130) > 300 and band(MineTiles.SAND, 0, 60) > 300 and band(MineTiles.WATER, 0, 80) > 200 and band(MineTiles.LAVA, 60, 150) > 100,
					"the giant mushroom (%d cells), sand %d, water %d, lava %d" % [band(MineTiles.SHROOM, 90, 130), band(MineTiles.SAND, 0, 60), band(MineTiles.WATER, 0, 80), band(MineTiles.LAVA, 60, 150)])
				check(m.ship.p.y > 0.0 and MineGround.building_at(m.ship.p.x) == "lift", "the ship starts at the lift")
				# drill down from the surface
				var x := 31.5
				g.set_box(Vector2(x, -3.0), Vector2(0.7, 3.0), MineTiles.DIRT)
				m.ship.place(Vector2(x, MineShip.HALF + 0.01))
				v.fuel = m.fuel
				m.ammo = {"dirt": 0, "clay": 0, "sand": 0}
				m.auto = {"down": true}
				next(3)
		3:
			if e > 3.0:
				m.auto = {}
				var depth := -m.ship.p.y
				check(depth > 3.0, "drilled down through dirt: %.1f m in 3 s" % depth)
				check(g.count(Vector2(31.5, -1.5), Vector2(0.3, 1.0), -6) > 50, "the shaft's dug out")
				check(int(m.ammo.dirt) > 100, "the dirt's in the launcher's hopper (%d)" % int(m.ammo.dirt))
				check(m.fuel < float(v.fuel) - 0.2, "fuel used: %.2f -> %.2f L" % [v.fuel, m.fuel])
				# sideways into gold
				var at := sit(20.0, 30.0)
				g.set_box(at + Vector2(0.95, 0), Vector2(0.45, 0.45), MineTiles.GOLD)
				m.cargo = {}
				v.x0 = at.x
				m.auto = {"x": 1.0}
				next(4)
		4:
			if e > 3.0:
				m.auto = {}
				check(int(m.cargo.get("gold", 0)) >= 2, "drilled sideways into a gold vein: nuggets into the hold %s" % [m.cargo])
				check(m.ship.p.x > float(v.x0) + 0.6, "and worked its way in (%.2f m)" % (m.ship.p.x - float(v.x0)))
				# a full hold: the next is lost
				m.cargo = {"coal": m.cargo_cap()}
				var at := sit(20.0, 32.0)
				g.set_box(at + Vector2(0.95, 0), Vector2(0.45, 0.45), MineTiles.SILVER)
				m.auto = {"x": 1.0}
				next(5)
		5:
			if e > 3.0:
				m.auto = {}
				check(not m.cargo.has("silver") and m.cargo_count() == m.cargo_cap(), "hold full: the silver's lost (%s)" % [m.cargo])
				m.cargo = {"gold": 3, "coal": 2}
				var want := MineShop.value(m.cargo, m.day)
				var c0: int = arena.cash
				m.sell_all()
				check(arena.cash == c0 + want and m.cargo.is_empty(), "sold at the trader: $%d -> $%d (+%d)" % [c0, arena.cash, want])
				var p0 := MineShop.price("gold", 100)
				var p1 := MineShop.price("gold", 101)
				var p2 := MineShop.price("gold", 102)
				check(p0 > 0 and (p0 != p1 or p1 != p2), "prices wobble day to day: gold $%d, $%d, $%d" % [p0, p1, p2])
				m.hud.close_menu()
				arena.cash = 30000
				m.buy_upgrade("drill")
				m.buy_upgrade("tank")
				m.buy_upgrade("cargo")
				m.buy_upgrade("launcher")
				check(m.upg.drill == 1 and is_equal_approx(m.ship.drill_power, 1.6) and m.tank_max() == 20.0 and m.cargo_cap() == 14 and m.launch_speed() == 13.0,
					"upgrades: drill %d (%.1fx), tank %.0f L, cargo %d, launcher %.0f m/s" % [m.upg.drill, m.ship.drill_power, m.tank_max(), m.cargo_cap(), m.launch_speed()])
				m.hud.close_menu()
				var at := sit(20.0, 60.0)
				g.set_box(at + Vector2(1.0, 0), Vector2(0.5, 0.55), MineTiles.HARD2)
				m.auto = {"x": 1.0}
				next(6)
		6:
			if e > 1.5:
				m.auto = {}
				check(g.count(m.ship.p + Vector2(0.9, 0), Vector2(0.3, 0.3), MineTiles.HARD2) > 20, "a Mk III boulder won't drill with Mk II")
				m.buy_upgrade("drill")
				m.hud.close_menu()
				m.auto = {"x": 1.0}
				v.x0 = m.ship.p.x
				next(7)
		7:
			if e > 4.0:
				m.auto = {}
				check(m.ship.p.x > float(v.x0) + 0.5, "with Mk III it does (%.2f m in)" % (m.ship.p.x - float(v.x0)))
				# a gas pocket
				var at := sit(20.0, 66.0)
				g.set_box(at + Vector2(3.0, 0), Vector2(2.5, 2.0), MineTiles.STONE)
				g.set_box(at + Vector2(0.95, 0), Vector2(0.4, 0.4), MineTiles.GAS)
				v.hull = m.hull
				m.auto = {"x": 1.0}
				next(8)
		8:
			if e > 2.5:
				m.auto = {}
				check(m.hull < float(v.hull) - 3.0, "the gas went off: hull %.0f -> %.0f" % [v.hull, m.hull])
				check(g.count(m.ship.p + Vector2(2.0, 0), Vector2(0.5, 0.5), -6) > 20, "and blew the rock open round it")
				# lava: a tunnel off a pocket's side
				# (the right edge of a pocket's lava, on its middle row)
				var lp: Vector2 = g.features.lava[0]
				var row := PackedInt32Array()
				var lc := MineGround.cell(lp)
				for cand in g.features.lava:
					lc = MineGround.cell(cand)
					row = g.sim.find(MineTiles.LAVA, lc.x - 40, lc.y, lc.x + 40, lc.y, 200)
					if row.size() >= 6:
						lp = cand
						break
				var rx := lc.x
				for k in range(0, row.size(), 2):
					rx = maxi(rx, row[k])
				var lx := MineGround.world(Vector2i(rx, lc.y)).x + 0.07
				v.lava_at = Vector2(lx + 1.5, lp.y)
				g.set_box(Vector2(lx + 1.5, lp.y), Vector2(1.5, 0.5), MineTiles.AIR)
				g.set_box(Vector2(lx + 1.5, lp.y - 0.62), Vector2(1.6, 0.12), MineTiles.STONE)
				m.ship.place(Vector2(10.5, MineShip.HALF + 0.01))
				next(9)
		9:
			v.lava_max = maxi(int(v.get("lava_max", 0)), g.count(v.lava_at, Vector2(1.5, 0.5), MineTiles.LAVA))
			if e > 3.0:
				check(int(v.lava_max) > 10, "lava ran out into the tunnel (%d cells)" % int(v.lava_max))
				# sand falls, water pools, a lone drop of lava settles: a sealed room, things put in its top
				var room := Vector2(25.0, -100.0)
				g.set_box(room, Vector2(3.4, 2.4), MineTiles.BASALT)
				g.set_box(room, Vector2(3.0, 2.0), MineTiles.AIR)
				g.set_box(room + Vector2(-2.0, 1.6), Vector2(0.5, 0.3), MineTiles.SAND)
				g.set_box(room + Vector2(1.5, 1.6), Vector2(0.5, 0.3), MineTiles.WATER)
				v.room = room
				next(10)
		10:
			if e > 4.0:
				var room: Vector2 = v.room
				var sand_low := g.count(room + Vector2(-2.0, -1.5), Vector2(1.0, 0.5), MineTiles.SAND)
				var sand_high := g.count(room + Vector2(-2.0, 1.6), Vector2(0.5, 0.3), MineTiles.SAND)
				var water_low := g.count(room + Vector2(0.5, -1.7), Vector2(2.5, 0.3), MineTiles.WATER)
				check(sand_low > 30 and sand_high < 5, "the sand fell and piled (%d at the bottom, %d left up top)" % [sand_low, sand_high])
				check(water_low > 30, "the water ran down and pooled (%d)" % water_low)
				# a few drops of lava on a flat floor: they settle, not slosh about for ever
				g.set_box(room, Vector2(3.0, 2.0), MineTiles.AIR)
				g.set_box(room + Vector2(0, -1.94), Vector2(0.12, 0.06), MineTiles.LAVA)
				next(11)
		11:
			if e > 2.0 and not v.has("lava_pos"):
				v.lava_pos = g.sim.find(MineTiles.LAVA, int((v.room.x - 3) * 8), int(MineGround.dy(-v.room.y + 2.2)) - 40, int((v.room.x + 3) * 8), int(MineGround.dy(-v.room.y + 2.2)), 50)
			if e > 3.5:
				var now: PackedInt32Array = g.sim.find(MineTiles.LAVA, int((v.room.x - 3) * 8), int(MineGround.dy(-v.room.y + 2.2)) - 40, int((v.room.x + 3) * 8), int(MineGround.dy(-v.room.y + 2.2)), 50)
				check(now.size() > 0 and now == v.lava_pos, "a little lava settles and stays put (%d cells)" % (now.size() / 2))
				# the mushroom trip
				var c: Array = g.features.caves[0]
				var fs := mush_floor(c)
				m.ship.place(fs + Vector2(0, MineShip.HALF + 0.02))
				m.trip = 0.0
				next(12)
		12:
			if e > 4.0:
				check(m.trip > 0.25 and m.ship.grav_k < 0.95, "tripping in the mushroom cave: %.2f, gravity x%.2f (bg %d)" % [m.trip, m.ship.grav_k, g.bg_at(m.ship.p)])
				m.trip = 0.0
				m.critters.stand_down()
				m.critters.alarm_rest = 0.0       # (an earlier check may have set it off)
				var b: Array = g.features.bunker
				m.cargo = {"gold": 2}
				arena.cash = 1000
				m.ship.place(Vector2(float(b[0]) + 3.0, -float(b[3]) + 1.0 + MineShip.HALF + 0.01))
				next(13)
		13:
			if e > 0.5 and not v.has("alarm"):
				v.alarm = true
				check(m.critters.alarm and m.critters.drones.size() == 3, "into the bunker: the alarm and %d drones" % m.critters.drones.size())
			if e > 14.0 or (v.has("alarm") and not m.critters.alarm):
				check(not m.critters.alarm and m.cargo.is_empty() and arena.cash < 1000 and m.ship.p.y > 0.0, "busted: cargo gone, $1000 -> $%d, towed up" % arena.cash)
				v.hull = m.hull
				var pd: Dictionary = m.critters.pods[0] if not m.critters.pods.is_empty() else {}
				check(not pd.is_empty(), "the rival crew's pods: %d" % m.critters.pods.size())
				if not pd.is_empty():
					var spots: Array = g.features.rival
					var sp: Vector2 = spots[10]
					var at := sit(sp.x, -sp.y + 0.6)
					g.set_box(at + Vector2(1.5, 0), Vector2(1.5, 0.5), MineTiles.AIR)
					pd.p = at + Vector2(2.2, 0)
					pd.chase = false
				next(14)
		14:
			if e > 6.0:
				check(m.hull < float(v.hull), "rammed by the rival crew: hull %.0f -> %.0f (%s)" % [v.hull, m.hull, m.last_hurt])
				m.hull = m.hull_max()
				v.hull = m.hull
				m.last_hurt = ""
				m.critters.on_enter()
				check(m.critters.rats.size() > 0, "rats in the sewers: %d" % m.critters.rats.size())
				if not m.critters.rats.is_empty():
					m.ship.place(m.critters.rats[0].p + Vector2(0, MineShip.HALF + 0.02))
				next(15)
		15:
			if e > 3.0:
				check(m.hull < float(v.hull) or m.last_hurt == "rats" or m.critters.rats.size() < MineCritters.RAT_MAX, "the rats chewed the hull (%.1f -> %.1f) or got squashed" % [v.hull, m.hull])
				m.hull = 9999.0
				var w: Array = g.features.worm
				var fs := g._floor_spot(float(w[0]) + 4.0, float(w[1]) - 2.0, float(w[1]) + 5.0)
				m.ship.place((fs if fs != Vector2.INF else Vector2(float(w[0]) + 4.0, -float(w[1]))) + Vector2(0, MineShip.HALF + 0.02))
				next(16)
		16:
			if e > 1.5 and not v.has("worm"):
				v.worm = true
				check(m.worm.awake, "the worm wakes when you come down")
				v.hoard = band(MineTiles.HOARD, 100, MineGround.D)
				m.worm.hurt(MineWorm.HP_MAX + 1.0)
			if e > 6.0:
				check(not m.worm.alive and m.worm_dead, "the worm's dead")
				check(band(MineTiles.HOARD, 100, MineGround.D) > int(v.hoard) + 50, "its hoard spilled out: %d diamond cells" % band(MineTiles.HOARD, 100, MineGround.D))
				# dynamite
				m.hull = m.hull_max()
				m.items.dynamite = 2
				var at := sit(20.0, 80.0)
				g.set_box(at, Vector2(2.5, 2.5), MineTiles.STONE)
				g.set_box(at, Vector2(0.5, 0.46), MineTiles.AIR)
				g.set_box(at + Vector2(1.0, 0), Vector2(0.4, 0.4), MineTiles.COPPER)
				m.cargo = {}
				m.use_item("dynamite")
				check(m.items.dynamite == 1 and g.count(at + Vector2(1.0, 0), Vector2(0.4, 0.4), -6) > 30 and m._nuggets.size() > 0, "dynamite: the rock round you gone, the copper flying out as nuggets (%d)" % m._nuggets.size())
				# the launcher: clay shot at a wall sticks to it
				var at2 := sit(20.0, 90.0)
				g.set_box(at2 + Vector2(2.5, 0.5), Vector2(2.0, 1.2), MineTiles.AIR)
				g.set_box(at2 + Vector2(5.0, 0.5), Vector2(0.5, 1.5), MineTiles.BASALT)
				v.clay = g.count(at2 + Vector2(4.2, 0.5), Vector2(0.6, 1.2), MineTiles.CLAY)
				m.ammo = {"dirt": 100, "clay": 100, "sand": 100}
				m.ammo_sel = "clay"
				m.aim = at2 + Vector2(5.0, 0.3)
				m._launch_t = 0.0
				m.shoot()
				check(int(m.ammo.clay) == 100 - VoxelMine.SHOT_CELLS and m._shots.size() == 1, "a clay shot fired (%d left)" % int(m.ammo.clay))
				v.at2 = at2
				next(17)
		17:
			if e > 1.5:
				var at2: Vector2 = v.at2
				var clay := g.count(at2 + Vector2(4.2, 0.5), Vector2(0.6, 1.2), MineTiles.CLAY)
				check(m._shots.is_empty() and clay > int(v.clay) + 8, "it stuck to the wall: %d clay cells" % (clay - int(v.clay)))
				# saving and loading
				var d: Dictionary = m.save_data()
				var region := Vector2(31.5, -1.5)
				var dug := g.count(region, Vector2(1.0, 1.4), -6)
				var s = JSON.parse_string(JSON.stringify(d))
				m.upg.drill = 0
				g.set_box(region, Vector2(1.0, 1.4), MineTiles.DIRT)
				m.load_data(s)
				g = m.ground
				check(m.upg.drill == 2 and g.count(region, Vector2(1.0, 1.4), -6) == dug and m.worm_dead and int(m.ammo.clay) == 100 - VoxelMine.SHOT_CELLS,
					"saved and loaded: upgrades, the dug ground (%d open), the worm, the launcher's hopper" % dug)
				m.cargo = {"gold": 1}
				sit(20.0, 40.0)
				next(18)
				m.fuel = 0.0
		18:
			if e > 0.5:
				check(m.cargo.is_empty() and m.ship.p.y > 0.0 and m.fuel > 0.0, "out of fuel: towed up, cargo lost")
				m.ship.place(Vector2(14.0, MineShip.HALF + 0.01))
				next(19)
				m.fuel = 0.0
		19:
			if e > 0.5:
				check(m.fuel > 0.0, "out of fuel up top: towed too (not stuck)")
				sit(20.0, 60.0)
				var d2: Dictionary = m.save_data()
				check(d2.has("ship") and absf(float(d2.ship[1]) - m.ship.p.y) < 0.01, "where the ship was left underground is saved")
				m.leave()
				next(20)
		20:
			if e > 1.5:
				check(not m.active and not arena.get_viewport().disable_3d, "back up in the yard")
				check(arena.player.global_position.distance_to(Vector3(MineHatch.AT.x, 0.05, MineHatch.AT.z + 1.0)) < 0.5, "stood at the roller door")
				print("MINE done: %d passed, %d failed" % [passed, failed])
				quit(1 if failed > 0 else 0)
				return true
	return false
