extends SceneTree
## A short film of the dig mode, played by a little autopilot (under a display with --write-movie): through the roller
## door, drive off and drill down, tunnel along for ore, fly back up, sell at the trader, a better drill at the
## mechanic, then a few cuts to the deep: a mushroom cave (tripping), the cop bunker's alarm and its drones, the rival
## crew, and the rock worm. Owned by the voxel session.

var arena: Node
var m: VoxelMine
var g: MineGround
var t := 0.0
var plan: Array = []
var cur: Dictionary = {}
var cur_t := 0.0
var shaft_x := 30

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _ready_plan() -> void:
	plan = [
		{"do": "door", "secs": 2.5},
		{"do": "enter", "secs": 1.6},
		{"do": "to_x", "x": shaft_x + 0.5, "secs": 6.0},
		{"do": "down", "rows": 10, "secs": 10.0},
		{"do": "to_x", "x": shaft_x + 7.5, "secs": 7.0},
		{"do": "down", "rows": 3, "secs": 5.0},
		{"do": "to_x", "x": shaft_x - 3.5, "secs": 8.0},
		{"do": "to_x", "x": shaft_x + 7.5, "secs": 4.0},
		{"do": "up", "x": shaft_x + 7.5, "row": 9, "secs": 4.0},
		{"do": "to_x", "x": shaft_x + 0.5, "secs": 4.0},
		{"do": "up", "x": shaft_x + 0.5, "secs": 9.0},
		{"do": "to_x", "x": MineGround.building_x("trader"), "secs": 6.0},
		{"do": "menu", "at": "trader", "secs": 1.8},
		{"do": "sell", "secs": 1.5},
		{"do": "to_x", "x": MineGround.building_x("mechanic"), "secs": 4.0},
		{"do": "menu", "at": "mechanic", "secs": 1.5},
		{"do": "upgrade", "secs": 2.0},
		{"do": "cut", "to": "cave", "secs": 5.0},
		{"do": "cut", "to": "bunker", "secs": 6.0},
		{"do": "cut", "to": "rivals", "secs": 5.0},
		{"do": "cut", "to": "worm", "secs": 6.0},
		{"do": "quit", "secs": 1.0},
	]

## The ground along the way made sure: soft enough for the first drill, a few ores on the route.
func _route() -> void:
	for r in range(0, 14):
		for x in range(shaft_x - 5, shaft_x + 9):
			var tt := g.at(x, r)
			if not MineTiles.solid(tt) or int(MineTiles.info(tt).need) > 0 or MineTiles.hardness(tt, g.base_at(x, r)) < 0.0 or tt == MineTiles.GAS:
				if tt != MineTiles.AIR or r < 12:
					g.set_tile(x, r, MineTiles.CLAY if r > 5 else MineTiles.DIRT)
	for o in [[shaft_x + 2, 9, MineTiles.COAL], [shaft_x + 3, 9, MineTiles.COAL], [shaft_x + 5, 9, MineTiles.COPPER], [shaft_x + 6, 9, MineTiles.COPPER],
			[shaft_x + 7, 10, MineTiles.SILVER], [shaft_x + 7, 11, MineTiles.SILVER], [shaft_x, 12, MineTiles.GOLD], [shaft_x - 2, 12, MineTiles.COPPER], [shaft_x - 3, 12, MineTiles.GOLD]]:
		g.set_tile(o[0], o[1], o[2])
	# a floor under the route
	for x in range(shaft_x - 5, shaft_x + 9):
		if not MineTiles.solid(g.at(x, 13)):
			g.set_tile(x, 13, MineTiles.STONE)

func sit(x: int, r: int) -> void:
	g.set_tile(x, r, MineTiles.AIR)
	if not MineTiles.solid(g.at(x, r + 1)):
		g.set_tile(x, r + 1, MineTiles.STONE)
	m.ship.place(Vector2(x + 0.5, -r - 1.0 + MineShip.HALF + 0.002))
	m._cam_at = Vector3(clampf(x + 0.5, 10.5, MineGround.W - 10.5), -r - 0.5 + 0.6, 12.0)

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

func _start(c: Dictionary) -> void:
	match String(c.do):
		"enter":
			m.enter()
			m.tips_done = {"cops": true, "rivals": true, "worm": true, "mush": true, "sewer": true, "deep": true, "gas": true, "lava": true, "hard": true}
			g = m.ground
			_route()
		"down":
			c["goal"] = MineGround.tile_of(m.ship.p).y + int(c.rows)
		"menu":
			m._near = String(c.at)
			m.use()
		"sell":
			m.sell_all()
		"upgrade":
			arena.cash = maxi(arena.cash, 300)
			m.buy_upgrade("drill")
		"cut":
			m.auto = {}
			m.hud.close_menu()
			match String(c.to):
				"cave":
					var cv: Array = g.features.caves[1]
					var cx := int(cv[0]) - int(cv[2]) - 2
					var cr := int(cv[1])
					while g.at(cx + 3, cr + 1) == MineTiles.AIR:
						cr += 1
					for x in range(cx, cx + 3):
						g.set_tile(x, cr, MineTiles.AIR)
						if not MineTiles.solid(g.at(x, cr + 1)):
							g.set_tile(x, cr + 1, MineTiles.STONE)
					sit(cx, cr)
					m.trip = 0.45
					m.cave_t = 12.0
					m.auto = {"x": 1.0}
				"bunker":
					m.trip = 0.0
					var b: Array = g.features.bunker
					for x in range(int(b[0]) - 7, int(b[0])):
						g.set_tile(x, int(b[3]) - 1, MineTiles.AIR)
					sit(int(b[0]) - 1, int(b[3]) - 1)
					m.ship.face = 1
					m.auto = {"x": 1.0}
					c["flee"] = true
				"rivals":
					m.critters.stand_down()
					var cells: Array = g.features.rival
					var cc: Vector2i = cells[cells.size() / 2]
					sit(cc.x, cc.y + (1 if g.at(cc.x, cc.y + 1) == MineTiles.AIR else 0))
					m.critters.on_enter()
					for i in m.critters.pods.size():
						var pd: Dictionary = m.critters.pods[i]
						var pc: Vector2i = cells[(cells.size() / 2 + 4 + i * 2) % cells.size()]
						pd.p = MineGround.centre(pc.x, pc.y)
				"worm":
					var w: Array = g.features.worm
					m.hull = 9999.0
					sit(int(w[0]) + 6, int(w[1]) + 1)
		"quit":
			quit()

func _done(c: Dictionary) -> bool:
	match String(c.do):
		"to_x":
			return absf(m.ship.p.x - float(c.x)) < 0.12 and not m.ship.drilling
		"down":
			return MineGround.tile_of(m.ship.p).y >= int(c.goal) and not m.ship.drilling
		"up":
			if c.has("row"):
				return m.ship.p.y > -float(c.row) - 0.35       # (up past the tunnel's floor: the next step drives onto it)
			return m.ship.p.y > 0.42 and m.ship.grounded and m.ship.p.y < 1.0
	return false

func _run(c: Dictionary, dt: float) -> void:
	match String(c.do):
		"to_x":
			m.auto = {"x": clampf((float(c.x) - m.ship.p.x) * 3.0, -1.0, 1.0)}
		"down":
			m.auto = {"down": MineGround.tile_of(m.ship.p).y < int(c.goal)}
		"up":
			var dx := float(c.x) - m.ship.p.x
			var under := absf(dx) < 0.25
			m.auto = {"x": clampf(dx * 3.0, -1.0, 1.0), "up": under or m.ship.p.y > -0.5}
			if m.ship.p.y > 0.6:
				m.auto = {"x": 0.0, "up": false}
		"cut":
			if c.has("flee") and cur_t > 2.2:
				m.auto = {"x": -1.0}
		_:
			if String(c.do) != "cut":
				m.auto = {}
