extends SceneTree
## The dig mode's self-test (headless: --fixed-fps 60 -s test/voxel/mine_test.gd -- --nosave): the roller door in the
## yard, going down, the ground (its zones, ores deeper and richer, its caves and hazards), drilling down and sideways,
## ore into the hold (and lost when it's full), the fuel running down, selling at the trader, the mechanic's upgrades,
## a boulder too hard for the drill, a gas pocket going off, lava flowing, the mushroom trip, the cop bunker's alarm and
## its drones busting you, the rival crew ramming, the sewer rats, the worm (killed: its hoard), dynamite, the tow when
## the fuel's gone, saving and loading the mine, and coming back up. Owned by the voxel session.

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

## An open tile at (x, r) with solid floor under it and the ship sat in it (facing d).
func sit(x: int, r: int, floor_t := MineTiles.STONE) -> void:
	g.set_tile(x, r, MineTiles.AIR)
	if not MineTiles.solid(g.at(x, r + 1)):
		g.set_tile(x, r + 1, floor_t)
	m.ship.place(Vector2(x + 0.5, -r - 1.0 + MineShip.HALF + 0.002))
	m.ship.grounded = true

func count(t_: int, r0: int, r1: int) -> int:
	var n := 0
	for r in range(r0, r1):
		for x in MineGround.W:
			if g.at(x, r) == t_:
				n += 1
	return n

func next(s: int) -> void:
	step = s
	mark = t
	if m and step >= 4 and step != 15:
		m.fuel = m.tank_max()         # (each check on its own: not towed for running dry mid-test)
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
				check(g.tiles.size() == MineGround.W * MineGround.D, "the ground: %d x %d tiles" % [MineGround.W, MineGround.D])
				var zones := [g.base_at(20, 10), g.base_at(20, 35), g.base_at(20, 68), g.base_at(20, 104), g.base_at(20, 138)]
				check(zones[1] == MineTiles.STONE and zones[2] == MineTiles.RED and zones[3] == MineTiles.BASALT and zones[4] == MineTiles.CRYSTAL and zones[0] in [MineTiles.DIRT, MineTiles.CLAY],
					"the depth zones: %s" % [zones])
				var coal := count(MineTiles.COAL, 0, 50)
				var dia_top := count(MineTiles.DIAMOND, 0, 95)
				var dia := count(MineTiles.DIAMOND, 95, MineGround.D)
				var gold := count(MineTiles.GOLD, 50, MineGround.D)
				check(coal > 30 and dia > 5 and dia_top == 0 and gold > 10, "ores: coal near the top %d, gold deeper %d, diamonds only deep %d (none shallow: %d)" % [coal, gold, dia, dia_top])
				var f := g.features
				check(f.caves.size() == 5 and f.has("cathedral") and f.has("worm"), "five mushroom caves, the cathedral, the worm's cavern")
				check(f.sewer.size() == 2 and f.has("bunker") and f.rival.size() > 30, "the trial hazards: sewers %d, bunker %s, rival tunnels %d tiles" % [f.sewer.size(), f.get("bunker"), f.rival.size()])
				check(count(MineTiles.SHROOM, 90, 130) >= 20, "the giant mushroom (%d tiles)" % count(MineTiles.SHROOM, 90, 130))
				check(m.ship.p.y > 0.0 and MineGround.building_at(m.ship.p.x) == "lift", "the ship starts at the lift")
				# drill down from the surface past the buildings
				var x := 31
				for r in 6:
					if not MineTiles.solid(g.at(x, r)) or MineTiles.hardness(g.at(x, r), g.base_at(x, r)) < 0.0 or int(MineTiles.info(g.at(x, r)).need) > 0:
						g.set_tile(x, r, MineTiles.DIRT)
				m.ship.place(Vector2(x + 0.5, MineShip.HALF + 0.002))
				v.fuel = m.fuel
				m.auto = {"down": true}
				next(3)
		3:
			if e > 3.0:
				m.auto = {}
				var depth := -m.ship.p.y
				check(depth > 3.0, "drilled down: %.1f m deep" % depth)
				check(g.at(31, 0) == MineTiles.AIR and g.at(31, 1) == MineTiles.AIR, "the shaft's dug out")
				check(m.fuel < float(v.fuel) - 0.3, "fuel used: %.2f -> %.2f L" % [v.fuel, m.fuel])
				# sideways into gold
				sit(20, 30)
				g.set_tile(21, 30, MineTiles.GOLD)
				m.cargo = {}
				m.auto = {"x": 1.0}
				next(4)
		4:
			if e > 2.5:
				m.auto = {}
				check(int(m.cargo.get("gold", 0)) == 1, "drilled sideways into gold: in the hold %s" % [m.cargo])
				# a full hold: the next one's lost
				m.cargo = {"coal": m.cargo_cap()}
				sit(20, 32)
				g.set_tile(21, 32, MineTiles.SILVER)
				m.auto = {"x": 1.0}
				next(5)
		5:
			if e > 2.5:
				m.auto = {}
				check(not m.cargo.has("silver") and g.at(21, 32) == MineTiles.AIR, "hold full: the silver's lost (%s)" % [m.cargo])
				# the trader
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
				# the mechanic
				arena.cash = 20000
				m.buy_upgrade("drill")
				m.buy_upgrade("tank")
				m.buy_upgrade("cargo")
				check(m.upg.drill == 1 and is_equal_approx(m.ship.drill_power, 1.6) and m.tank_max() == 20.0 and m.cargo_cap() == 14, "upgrades: drill %d (%.1fx), tank %.0f L, cargo %d" % [m.upg.drill, m.ship.drill_power, m.tank_max(), m.cargo_cap()])
				m.hud.close_menu()
				# a boulder too hard for it
				sit(20, 60)
				g.set_tile(21, 60, MineTiles.HARD2)
				m.auto = {"x": 1.0}
				next(6)
		6:
			if e > 1.5:
				m.auto = {}
				check(g.at(21, 60) == MineTiles.HARD2 and not m.ship.drilling, "a Mk III boulder won't drill with Mk II")
				m.buy_upgrade("drill")
				m.hud.close_menu()
				m.auto = {"x": 1.0}
				next(7)
		7:
			if e > 3.0:
				m.auto = {}
				check(g.at(21, 60) == MineTiles.AIR, "with Mk III it does")
				# a gas pocket
				m.hull = m.hull_max()
				sit(20, 66)
				g.set_tile(21, 66, MineTiles.GAS)
				for r in range(64, 69):
					for x in range(22, 25):
						if not MineTiles.solid(g.at(x, r)):
							g.set_tile(x, r, MineTiles.STONE)
				v.hull = m.hull
				m.auto = {"x": 1.0}
				next(8)
		8:
			if e > 2.5:
				m.auto = {}
				check(m.hull < float(v.hull) - 3.0, "the gas went off: hull %.0f -> %.0f" % [v.hull, m.hull])
				check(g.at(22, 66) == MineTiles.AIR and g.at(22, 65) == MineTiles.AIR, "and blew the rock open round it")
				# lava: a lava tile with rock to its right; dig a tunnel off it with a floor under it
				var lx := -1
				var lr := -1
				for i in g.tiles.size():
					var x := i % MineGround.W
					var r := i / MineGround.W
					if g.tiles[i] == MineTiles.LAVA and x < MineGround.W - 7 and MineTiles.solid(g.at(x + 1, r)) and g.at(x + 1, r) != MineTiles.LAVA:
						lx = x + 1
						lr = r
						break
				v.lava_x = lx
				v.lava_r = lr
				for k in 4:
					g.set_tile(lx + k, lr, MineTiles.AIR)
					if not MineTiles.solid(g.at(lx + k, lr + 1)) or g.at(lx + k, lr + 1) == MineTiles.LAVA:
						g.set_tile(lx + k, lr + 1, MineTiles.STONE)
				m.ship.place(Vector2(10.5, MineShip.HALF + 0.002))
				next(9)
		9:
			var now := 0
			for k in 4:
				if g.at(int(v.lava_x) + k, int(v.lava_r)) == MineTiles.LAVA:
					now += 1
			v.lava_max = maxi(int(v.get("lava_max", 0)), now)
			if e > 3.0:
				var moved: int = v.lava_max
				var row := ""
				for k in range(-2, 6):
					row += "%d,%d " % [g.at(int(v.lava_x) + k, int(v.lava_r)), g.at(int(v.lava_x) + k, int(v.lava_r) + 1)]
				check(moved > 0, "lava flowed out into the dug tiles (%d) at %d,%d: %s; hull %.1f; %s" % [moved, v.lava_x, v.lava_r, row, m.hull, m.hud._say])
				# the mushroom trip: an open tile in the first cave with floor under it
				var c: Array = g.features.caves[0]
				var cx := int(c[0])
				var cr := int(c[1])
				for r in range(int(c[1]) - 4, int(c[1]) + 5):
					for x in range(int(c[0]) - 6, int(c[0]) + 7):
						if g.at(x, r) == MineTiles.AIR and g.bg_at(x, r) == MineTiles.BG_MUSH and MineTiles.solid(g.at(x, r + 1)):
							cx = x
							cr = r
				sit(cx, cr)
				m.trip = 0.0
				next(10)
		10:
			if e > 4.0:
				var stt := MineGround.tile_of(m.ship.p)
				check(m.trip > 0.25 and m.ship.grav_k < 0.95, "tripping in the mushroom cave: %.2f, gravity x%.2f (ship at %s, %s, bg %d, cave %s; %s)" % [m.trip, m.ship.grav_k, m.ship.p, stt, g.bg_at(stt.x, stt.y), g.features.caves[0], m.hud._say + " / " + m.last_hurt])
				m.trip = 0.0
				# the cop bunker
				var b: Array = g.features.bunker
				m.cargo = {"gold": 2}
				arena.cash = 1000
				sit(int(b[0]) + 3, int(b[3]) - 1)
				next(11)
		11:
			if e > 0.5 and not v.has("alarm"):
				v.alarm = true
				check(m.critters.alarm and m.critters.drones.size() == 3, "into the bunker: the alarm and %d drones" % m.critters.drones.size())
			if e > 12.0 or (v.has("alarm") and not m.critters.alarm):
				check(not m.critters.alarm and m.cargo.is_empty() and arena.cash < 1000 and m.ship.p.y > 0.0, "busted: cargo gone, $1000 -> $%d, towed up" % arena.cash)
				# the rival crew
				m.hull = m.hull_max()
				v.hull = m.hull
				var pd: Dictionary = m.critters.pods[0] if not m.critters.pods.is_empty() else {}
				check(not pd.is_empty(), "the rival crew's pods: %d" % m.critters.pods.size())
				if not pd.is_empty():
					# a stretch of the main tunnel: the ship at one end, the pod four along
					for cc in g.features.rival:
						var ok := true
						for k in 5:
							if g.at(cc.x + k, cc.y) != MineTiles.AIR or not MineTiles.solid(g.at(cc.x + k, cc.y + 1)):
								ok = false
						if ok:
							sit(cc.x, cc.y)
							pd.p = MineGround.centre(cc.x + 4, cc.y)
							pd.chase = false
							break
				next(12)
		12:
			if e > 6.0:
				var pinfo := ""
				for pd2 in m.critters.pods:
					pinfo += "%s chase %s cool %.1f field %d; " % [pd2.p, pd2.chase, pd2.cool, int(m.critters._field.get(MineGround.tile_of(pd2.p), -1))]
				check(m.hull < float(v.hull), "rammed by the rival crew: hull %.0f -> %.0f (ship %s; %s)" % [v.hull, m.hull, m.ship.p, pinfo])
				# the sewer rats
				m.hull = m.hull_max()
				v.hull = m.hull
				var sw: Array = g.features.sewer[0]
				m.critters.on_enter()
				check(m.critters.rats.size() > 0, "rats in the sewers: %d" % m.critters.rats.size())
				if not m.critters.rats.is_empty():
					var rp: Vector2 = m.critters.rats[0].p
					var rt := MineGround.tile_of(rp)
					m.ship.place(Vector2(rp.x, -rt.y - 1.0 + MineShip.HALF + 0.002))
				next(13)
		13:
			if e > 3.0:
				check(m.hull < float(v.hull) or m.critters.rats.size() < MineCritters.RAT_MAX, "the rats chewed the hull (%.1f -> %.1f) or got squashed" % [v.hull, m.hull])
				# the worm
				m.hull = 9999.0
				var w: Array = g.features.worm
				sit(int(w[0]) + 4, int(w[1]))
				next(14)
		14:
			if e > 1.5 and not v.has("worm"):
				v.worm = true
				check(m.worm.awake, "the worm wakes when you come down")
				v.hoard = count(MineTiles.HOARD, 100, MineGround.D)
				m.worm.hurt(MineWorm.HP_MAX + 1.0)
			if e > 6.0:
				check(not m.worm.alive and m.worm_dead, "the worm's dead")
				check(count(MineTiles.HOARD, 100, MineGround.D) > int(v.hoard), "its hoard spilled out: %d diamonds" % count(MineTiles.HOARD, 100, MineGround.D))
				# dynamite
				m.hull = m.hull_max()
				m.items.dynamite = 2
				sit(20, 80)
				for r in range(78, 83):
					for x in range(18, 23):
						if g.at(x, r) != MineTiles.AIR:
							g.set_tile(x, r, MineTiles.STONE)
				g.set_tile(21, 80, MineTiles.COPPER)
				m.cargo = {}
				m.use_item("dynamite")
				check(m.items.dynamite == 1 and g.at(21, 80) == MineTiles.AIR and g.at(19, 80) == MineTiles.AIR and m.cargo.get("copper", 0) == 1, "dynamite: the rock round you gone, the copper scooped up")
				# saving and loading
				var d: Dictionary = m.save_data()
				var dug := count(MineTiles.AIR, 0, MineGround.D)
				var s = JSON.parse_string(JSON.stringify(d))
				m.upg.drill = 0
				g.set_tile(30, 30, MineTiles.AIR)
				m.load_data(s)
				check(m.upg.drill == 2 and count(MineTiles.AIR, 0, MineGround.D) == dug and m.worm_dead and m.cargo.get("copper", 0) == 1, "saved and loaded: upgrades, the dug ground (%d open), the worm, the cargo" % dug)
				# out of fuel deep down: towed
				g = m.ground
				m.cargo = {"gold": 1}
				sit(20, 40)
				m.fuel = 0.0
				next(15)
		15:
			if e > 0.5:
				check(m.cargo.is_empty() and m.ship.p.y > 0.0 and m.fuel > 0.0, "out of fuel: towed up, cargo lost")
				# out of fuel up top, away from the pumps: not stuck there for ever
				m.ship.place(Vector2(14.0, MineShip.HALF + 0.002))
				m.fuel = 0.0
				next(17)
		17:
			if e > 0.5:
				check(m.fuel > 0.0, "out of fuel up top: towed too (not stuck with no way to move)")
				# a lone bit of lava on a flat floor settles (doesn't slosh about for ever)
				for x in range(18, 27):
					g.set_tile(x, 50, MineTiles.AIR)
					g.set_tile(x, 51, MineTiles.STONE)
					g.set_tile(x, 49, MineTiles.STONE)
				g.set_tile(17, 50, MineTiles.STONE)
				g.set_tile(27, 50, MineTiles.STONE)
				g.set_tile(22, 50, MineTiles.LAVA)
				next(18)
		18:
			if g.at(22, 50) != MineTiles.LAVA:
				v.lava_moved = true
			if e > 3.0:
				check(not v.has("lava_moved"), "a lone bit of lava stays put")
				# quit down there: back down there next time
				sit(20, 60)
				var d2: Dictionary = m.save_data()
				check(d2.has("ship") and absf(float(d2.ship[1]) - m.ship.p.y) < 0.01, "where the ship was left underground is saved")
				m.leave()
				next(16)
		16:
			if e > 1.5:
				check(not m.active and not arena.get_viewport().disable_3d, "back up in the yard")
				check(arena.player.global_position.distance_to(Vector3(MineHatch.AT.x, 0.05, MineHatch.AT.z + 1.0)) < 0.5, "stood at the roller door")
				print("MINE done: %d passed, %d failed" % [passed, failed])
				quit(1 if failed > 0 else 0)
				return true
	return false
