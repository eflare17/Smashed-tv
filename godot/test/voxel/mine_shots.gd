extends SceneTree
## Screenshots of the dig mode (under a display, Forward+: -- --out=dir): the roller door in the yard, the surface
## with its buildings, a shaft going down, ore in the stone, a mushroom cave (tripping), the cop bunker with its
## drones out, the rival tunnels, lava running out, the cathedral's giant mushroom, the worm, the trader's menu and a
## fully upgraded ship. Owned by the voxel session.

var arena: Node
var m: VoxelMine
var g: MineGround
var t := 0.0
var step := 0
var mark := 0.0
var out := "user://"
var only := ""
var _then := Callable()         # what to do once the shot's taken

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
		if x.begins_with("--only="):
			only = x.trim_prefix("--only=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

var busy := false

## A screenshot of the next frame drawn (nothing changes till it's taken: _process waits on busy).
func _shot(name: String) -> void:
	busy = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/mine_%s.png" % [out, name])
	print("SHOT ", name)
	busy = false

## The ship sat in an open tile at (x, r), the tiles round it dug a little so there's something to see.
func sit(x: int, r: int) -> void:
	g.set_tile(x, r, MineTiles.AIR)
	if not MineTiles.solid(g.at(x, r + 1)):
		g.set_tile(x, r + 1, MineTiles.STONE)
	m.ship.place(Vector2(x + 0.5, -r - 1.0 + MineShip.HALF + 0.002))
	m._cam_at = Vector3(clampf(x + 0.5, 10.5, MineGround.W - 10.5), -r - 0.5 + 0.6, 12.0)
	m.cam_hold = false

func tunnel(x0: int, x1: int, r: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		g.set_tile(x, r, MineTiles.AIR)

func shaft(x: int, r0: int, r1: int) -> void:
	for r in range(r0, r1 + 1):
		g.set_tile(x, r, MineTiles.AIR)

func next(s: int) -> void:
	step = s
	mark = t

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5 or busy:
		return false
	if _then.is_valid():
		var c := _then
		_then = Callable()
		c.call()
		return false
	var e := t - mark
	match step:
		0:
			m = arena.mine
			arena.frozen = true
			arena.godmode = true
			arena.waves.queue.clear()
			arena.cash = 2400
			arena.player.global_position = Vector3(MineHatch.AT.x - 0.4, 0.05, MineHatch.AT.z + 3.2)
			arena.top_down = false
			arena.look_yaw = 0.12
			arena.look_pitch = 0.08
			next(1)
		1:
			if e > 1.0:
				_shot("door")
				_then = func():
					next(2)
		2:
			if e > 0.3:
				m.enter()
				m.tips_done = {"welcome": true}
				next(3)
		3:
			if e > 1.5:
				g = m.ground
				m.ship.place(Vector2(13.5, MineShip.HALF + 0.002))
				m.ship.face = 1
				m._cam_at = Vector3(14.5, 2.4, 12.0)
				next(4)
		4:
			if e > 0.8:
				_shot("surface")
				_then = func():
					# a shaft down and a tunnel off it
					shaft(33, 0, 12)
					tunnel(33, 40, 12)
					shaft(40, 12, 16)
					sit(36, 12)
					m.ship.face = 1
					m.hud.close_menu()
					next(5)
		5:
			if e > 0.8:
				_shot("shaft")
				_then = func():
					# ore in the stone, the drill going
					var r := 34
					tunnel(18, 26, r)
					for k in 6:
						g.set_tile(27 + (k % 2), r - 1 + k / 2, [MineTiles.COPPER, MineTiles.SILVER, MineTiles.COAL][k % 3])
					sit(26, r)
					m.ship.face = 1
					m.auto = {"x": 1.0}
					next(6)
		6:
			if e > 0.5:
				_shot("ore")
				_then = func():
					m.auto = {}
					# a mushroom cave, tripping
					var c: Array = g.features.caves[1]
					var cx := int(c[0])
					var cr := int(c[1])
					while g.at(cx, cr + 1) == MineTiles.AIR:
						cr += 1
					sit(cx, cr)
					m.trip = 0.8
					m.cave_t = 30.0
					next(7)
		7:
			if e > 0.9:
				_shot("mushroom_cave")
				_then = func():
					m.trip = 0.0
					# the cop bunker, alarm going
					var b: Array = g.features.bunker
					tunnel(int(b[0]) - 6, int(b[0]), int(b[3]) - 1)
					sit(int(b[0]) - 4, int(b[3]) - 1)
					m.critters._raise_alarm()
					next(8)
		8:
			if e > 1.2:
				_shot("bunker")
				_then = func():
					m.critters.stand_down()
					m.critters.alarm_rest = 0.0
					# the rival tunnels
					var cells: Array = g.features.rival
					var cc: Vector2i = cells[cells.size() / 3]
					sit(cc.x, cc.y + (1 if g.at(cc.x, cc.y + 1) == MineTiles.AIR else 0))
					m.critters.on_enter()
					for i in m.critters.pods.size():
						var pd: Dictionary = m.critters.pods[i]
						var pc: Vector2i = cells[(cells.size() / 3 + 3 + i * 3) % cells.size()]
						pd.p = MineGround.centre(pc.x, pc.y)
					next(9)
		9:
			if e > 0.6:
				_shot("rivals")
				_then = func():
					m.critters._drop(m.critters.pods)
					# lava running out of a pocket
					var lp: Vector2i = g.features.lava[0]
					var lx := lp.x
					while g.at(lx, lp.y) == MineTiles.LAVA:
						lx += 1
					tunnel(lx, lx + 6, lp.y)
					shaft(lx + 6, lp.y - 3, lp.y)
					sit(lx + 6, lp.y - 3)
					g.set_tile(lx + 6, lp.y - 2, MineTiles.STONE)
					next(10)
		10:
			if e > 2.5:
				_shot("lava")
				_then = func():
					# the cathedral
					var cat: Array = g.features.cathedral
					var sx := int(cat[4]) - 5
					var fr := int(cat[5])
					sit(sx, fr)
					m.trip = 0.35
					m.cam_hold = true
					m.cam.position = Vector3(float(cat[4]) + 1.0, -fr + 3.5, 15.0)
					next(11)
		11:
			if e > 0.9:
				_shot("cathedral")
				_then = func():
					m.trip = 0.0
					m.cam_hold = false
					# the worm, awake
					var w: Array = g.features.worm
					sit(int(w[0]) + 5, int(w[1]) + 1)
					m.hull = 9999.0
					next(12)
		12:
			if e > 2.5:
				_shot("worm")
				_then = func():
					m.hull = m.hull_max()
					# the trader, a full hold
					m.ship.place(Vector2(MineGround.building_x("trader"), MineShip.HALF + 0.002))
					m.cargo = {"gold": 3, "silver": 4, "coal": 5, "opal": 1}
					next(13)
		13:
			if e > 0.5:
				m._near = "trader"
				m.use()
				next(14)
		14:
			if e > 0.6:
				_shot("trader")
				_then = func():
					m.hud.close_menu()
					m.upg = {"drill": 3, "tank": 3, "cargo": 3, "hull": 3, "lights": 3}
					m.ship.build(m.upg)
					m.ship.place(Vector2(MineGround.building_x("mechanic"), MineShip.HALF + 0.002))
					m.cam_hold = true
					m.cam.position = Vector3(MineGround.building_x("mechanic"), 1.0, 3.6)
					next(15)
		15:
			if e > 0.5:
				_shot("ship_maxed")
				_then = func():
					m.upg = {"drill": 0, "tank": 0, "cargo": 0, "hull": 0, "lights": 0}
					m.ship.build(m.upg)
					next(16)
		16:
			if e > 0.5:
				_shot("ship_basic")
				_then = func():
					next(17)
		17:
			if e > 0.5:
				quit()
				return true
	return false
