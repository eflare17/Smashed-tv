extends SceneTree
## A short film of the pixel mine, played by a little autopilot (under a display with --write-movie): through the
## roller door, Jared's Mole drilling down nose-first, tunnelling along through ore veins (nuggets flying to the ship),
## the launcher (clay shots sticking to the wall, dirt piling), the propeller back up, the cargo squirted into the ORE
## box, boosters bought; then cuts: up a shaft on the boosters, the hose sucking up a pool, water sprayed on lava
## turning it to stone, sand pouring in when it's undermined, a mushroom cave (tripping), the cop bunker's alarm, the
## rival crew, and the rock worm. Owned by the voxel session.

var arena: Node
var m: VoxelMine
var g: MineGround
var t := 0.0
var plan: Array = []
var cur: Dictionary = {}
var cur_t := 0.0
const SX := 30.5

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _ready_plan() -> void:
	plan = [
		{"do": "door", "secs": 2.5},
		{"do": "enter", "secs": 1.6},
		{"do": "to_x", "x": SX, "secs": 6.0},
		{"do": "down", "depth": 8.6, "secs": 10.0},
		{"do": "to_x", "x": SX + 7.0, "secs": 7.0},
		{"do": "shoot", "ammo": "clay", "aim": Vector2(3.0, 0.4), "n": 4, "secs": 1.6},
		{"do": "shoot", "ammo": "dirt", "aim": Vector2(-2.5, 1.2), "n": 3, "secs": 1.6},
		{"do": "up", "x": SX, "depth": 0.0, "secs": 12.0},
		{"do": "to_x", "x": MineOreBox.X + 0.6, "secs": 9.0},
		{"do": "unload", "secs": 3.2},
		{"do": "to_x", "x": MineGround.building_x("mechanic"), "secs": 5.0},
		{"do": "menu", "at": "mechanic", "secs": 1.5},
		{"do": "upgrade", "secs": 2.0},
		{"do": "cut", "to": "boost", "secs": 4.0},
		{"do": "cut", "to": "water", "secs": 4.5},
		{"do": "cut", "to": "lava", "secs": 5.5},
		{"do": "cut", "to": "sand", "secs": 5.0},
		{"do": "cut", "to": "cave", "secs": 5.0},
		{"do": "cut", "to": "bunker", "secs": 6.0},
		{"do": "cut", "to": "rivals", "secs": 5.0},
		{"do": "cut", "to": "worm", "secs": 6.0},
		{"do": "quit", "secs": 1.0},
	]

## The ground along the way made sure: soft, with ore veins on the route and a way back up
func _route() -> void:
	g.set_box(Vector2(SX + 3.0, -5.0), Vector2(5.0, 5.0), MineTiles.CLAY)
	g.set_box(Vector2(SX + 3.0, -1.0), Vector2(5.0, 1.0), MineTiles.DIRT)
	for o in [[2.0, MineTiles.COAL], [3.3, MineTiles.COPPER], [4.5, MineTiles.COPPER], [5.6, MineTiles.SILVER], [6.4, MineTiles.GOLD]]:
		g.set_box(Vector2(SX + float(o[0]), -9.0), Vector2(0.3, 0.32), int(o[1]))
	g.set_box(Vector2(SX + 3.0, -9.6), Vector2(5.0, 0.2), MineTiles.STONE)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if plan.is_empty() and cur.is_empty():
		m = arena.mine
		arena.frozen = true
		arena.godmode = true
		arena.waves.queue.clear()
		arena.cash = 180
		arena.player.global_position = Vector3(MineHatch.AT.x - 0.3, 0.05, MineHatch.AT.z + 2.6)
		arena.top_down = false
		arena.look_yaw = 0.1
		arena.look_pitch = 0.1
		_ready_plan()
	if cur.is_empty():
		cur = plan.pop_front()
		cur_t = 0.0
		_start(cur)
	cur_t += dt
	_run(cur, dt)
	if cur_t >= float(cur.secs) or _done(cur):
		cur = {}
	return false

func _place(at: Vector2, cam_up := 0.6) -> void:
	m.ship.place(at)
	m._cam_at = Vector3(clampf(at.x, 9.0, MineGround.W - 9.0), at.y + cam_up, 10.0)

func _start(c: Dictionary) -> void:
	match String(c.do):
		"enter":
			m.enter()
			m.tips_done = {"cops": true, "rivals": true, "worm": true, "mush": true, "sewer": true, "deep": true, "gas": true, "lava": true, "hard": true, "welcome": true, "water": true, "first_ore": true, "sold": true, "cargo_full": true}
			g = m.ground
			_route()
		"menu":
			m._near = String(c.at)
			m.use()
		"unload":
			m._buildings_near()
			m.use()
		"upgrade":
			arena.cash = maxi(arena.cash, 3000)
			m.buy_upgrade("lift")
			m.buy_upgrade("lift")
		"shoot":
			m.auto = {}
			m.ammo_sel = String(c.ammo)
			m.ammo[m.ammo_sel] = maxi(int(m.ammo[m.ammo_sel]), 100)
			c["left"] = int(c.n)
		"cut":
			m.auto = {}
			m.hud.close_menu()
			m.trip = 0.0
			m.hull = 9999.0
			m.fuel = m.tank_max()
			match String(c.to):
				"sand":
					# a room under a lens of sand: drill up into... no, dig out under it and watch it pour
					var at := Vector2(18.0, -20.0)
					g.set_box(at + Vector2(0, 1.5), Vector2(3.0, 1.0), MineTiles.SAND)
					g.set_box(at + Vector2(0, 0.1), Vector2(3.0, 0.5), MineTiles.CLAY)
					g.set_box(at + Vector2(0, -0.8), Vector2(3.5, 0.4), MineTiles.AIR)
					g.set_box(at + Vector2(0, -1.3), Vector2(3.5, 0.12), MineTiles.STONE)
					_place(at + Vector2(-3.0, -0.8), 0.6)
					c["t_open"] = 0.6
				"boost":
					# a shaft from 14 m down to the top, the boosters on: up it
					m.hud.close_menu()
					g.set_box(Vector2(40.0, -7.0), Vector2(1.6, 7.6), MineTiles.STONE)
					g.set_box(Vector2(40.0, -6.6), Vector2(0.55, 7.2), MineTiles.AIR)
					_place(Vector2(40.0, -13.8 + MineShip.HALF + 0.02), 0.6)
					m.auto = {"up": true}
				"water":
					# a pool in a room behind the ship: the hose sucks it up
					var at := Vector2(30.0, -20.0 + MineShip.HALF + 0.01)
					g.set_box(at + Vector2(-1.4, 0.2), Vector2(3.0, 1.4), MineTiles.STONE)
					g.set_box(at, Vector2(0.5, 0.46), MineTiles.AIR)
					g.set_box(at + Vector2(-2.2, 0.0), Vector2(1.7, 0.5), MineTiles.AIR)
					g.set_box(at + Vector2(-2.2, -0.15), Vector2(1.6, 0.32), MineTiles.WATER)
					_place(at, 0.6)
					m.ship.face = 1
					m.ammo["water"] = 0
					m.auto = {"suck": true}
				"lava":
					# lava down past a ledge, in a stone room: sprayed with water, it crusts over to stone
					var at2 := Vector2(36.0, -30.0 + MineShip.HALF + 0.01)
					g.set_box(at2 + Vector2(2.0, -0.6), Vector2(3.0, 1.6), MineTiles.STONE)
					g.set_box(at2, Vector2(0.5, 0.46), MineTiles.AIR)
					g.set_box(at2 + Vector2(2.3, -0.55), Vector2(1.75, 1.05), MineTiles.AIR)
					g.set_box(at2 + Vector2(2.5, -1.35), Vector2(1.4, 0.25), MineTiles.LAVA)
					_place(at2, 0.2)
					m._cam_at.x = clampf(at2.x + 1.5, 9.0, MineGround.W - 9.0)
					m.ship.face = 1
					m.ammo_sel = "water"
					m.ammo["water"] = 500
					c["spray"] = at2 + Vector2(2.5, -1.2)
				"cave":
					var cv: Array = g.features.caves[1]
					var f := g._floor_spot(float(cv[0]), float(cv[1]) - float(cv[3]), float(cv[1]) + float(cv[3]) + 1.0)
					if f == Vector2.INF:
						f = Vector2(float(cv[0]), -float(cv[1]))
					_place(f + Vector2(-2.0, MineShip.HALF + 0.05), 0.9)
					m.trip = 0.5
					m.cave_t = 15.0
					m.auto = {"x": 1.0}
				"bunker":
					var b: Array = g.features.bunker
					g.set_box(Vector2(float(b[0]) - 3.0, -float(b[3]) + 1.5), Vector2(3.0, 0.5), MineTiles.AIR)
					g.set_box(Vector2(float(b[0]) - 3.0, -float(b[3]) + 0.9), Vector2(3.0, 0.12), MineTiles.STONE)
					_place(Vector2(float(b[0]) - 2.0, -float(b[3]) + 1.0 + MineShip.HALF + 0.02), 0.6)
					m.ship.face = 1
					m.auto = {"x": 1.0}
					c["flee"] = true
				"rivals":
					m.critters.stand_down()
					var spots: Array = g.features.rival
					var sp: Vector2 = spots[spots.size() / 3]
					_place(sp + Vector2(0, -0.6), 0.5)
					m.critters.on_enter()
					for i in m.critters.pods.size():
						m.critters.pods[i].p = spots[(spots.size() / 3 + 6 + i * 3) % spots.size()]
				"worm":
					var w: Array = g.features.worm
					var f2 := g._floor_spot(float(w[0]) + 5.0, float(w[1]) - 2.0, float(w[1]) + 5.0)
					_place((f2 if f2 != Vector2.INF else Vector2(float(w[0]) + 5.0, -float(w[1]))) + Vector2(0, MineShip.HALF + 0.05), 0.6)
		"quit":
			quit()

func _done(c: Dictionary) -> bool:
	match String(c.do):
		"to_x":
			return absf(m.ship.p.x - float(c.x)) < 0.12 and not m.ship.drilling
		"down":
			return -m.ship.p.y - MineShip.HALF >= float(c.depth) - 0.05 and not m.ship.drilling
		"up":
			return m.ship.p.y > 0.55
		"shoot":
			return int(c.left) <= 0 and m._shots.is_empty() and cur_t > 0.8
	return false

func _run(c: Dictionary, dt: float) -> void:
	match String(c.do):
		"to_x":
			m.auto = {"x": clampf((float(c.x) - m.ship.p.x) * 3.0, -1.0, 1.0)}
		"down":
			m.auto = {"down": -m.ship.p.y - MineShip.HALF < float(c.depth) - 0.05}
		"up":
			var dx := float(c.x) - m.ship.p.x
			m.auto = {"x": clampf(dx * 3.0, -1.0, 1.0), "up": absf(dx) < 0.25 or m.ship.p.y > -0.5}
			if m.ship.p.y > 0.6:
				m.auto = {"x": 0.0, "up": false}
		"shoot":
			m.aim = m.ship.p + (c.aim as Vector2)
			if int(c.left) > 0 and m._launch_t <= 0.0:
				m.shoot()
				c.left = int(c.left) - 1
		"cut":
			if String(c.to) == "sand" and cur_t > 0.6 and not c.has("opened"):
				# the clay under the sand drilled out: it pours
				c["opened"] = true
				m.auto = {"x": 1.0}
			if c.has("flee") and cur_t > 2.2:
				m.auto = {"x": -1.0}
			if c.has("spray") and cur_t > 0.6:
				m.aim = c.spray
				if m._launch_t <= 0.0:
					m.shoot()
		_:
			m.auto = {}
