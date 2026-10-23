extends SceneTree
## A short film of the pixel mine, played by a little autopilot (under a display with --write-movie): through the
## roller door, drill down, tunnel along through ore veins (nuggets flying to the ship), the launcher (clay shots
## sticking to the wall, dirt piling), fly back up, sell, a better drill; then cuts to the deep: sand pouring in when
## it's undermined, lava running into a tunnel, a mushroom cave (tripping), the cop bunker's alarm, the rival crew, and
## the rock worm. Owned by the voxel session.

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
		{"do": "up", "x": SX, "depth": 0.0, "secs": 10.0},
		{"do": "to_x", "x": MineGround.building_x("trader"), "secs": 6.0},
		{"do": "menu", "at": "trader", "secs": 1.8},
		{"do": "sell", "secs": 1.5},
		{"do": "to_x", "x": MineGround.building_x("mechanic"), "secs": 4.0},
		{"do": "menu", "at": "mechanic", "secs": 1.5},
		{"do": "upgrade", "secs": 2.0},
		{"do": "cut", "to": "sand", "secs": 5.0},
		{"do": "cut", "to": "lava", "secs": 5.0},
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
			m.tips_done = {"cops": true, "rivals": true, "worm": true, "mush": true, "sewer": true, "deep": true, "gas": true, "lava": true, "hard": true, "welcome": true}
			g = m.ground
			_route()
		"menu":
			m._near = String(c.at)
			m.use()
		"sell":
			m.sell_all()
		"upgrade":
			arena.cash = maxi(arena.cash, 300)
			m.buy_upgrade("drill")
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
				"lava":
					var lp: Vector2 = g.features.lava[0]
					for cand in g.features.lava:
						if g.count(cand, Vector2(1.0, 1.0), MineTiles.LAVA) > 30:
							lp = cand
							break
					g.set_box(lp + Vector2(4.0, 0), Vector2(3.2, 0.5), MineTiles.AIR)
					g.set_box(lp + Vector2(4.0, -0.62), Vector2(3.3, 0.12), MineTiles.STONE)
					_place(lp + Vector2(6.6, -0.08), 0.8)
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
			return m.ship.p.y > 0.42 and m.ship.grounded and m.ship.p.y < 1.0
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
		_:
			m.auto = {}
