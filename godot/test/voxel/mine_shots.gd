extends SceneTree
## Screenshots of the pixel mine (under a display, Forward+: -- --out=dir): the roller door in the yard, the surface
## with its buildings, a shaft going down, drilling into ore (chips flying, cracks spreading), a mushroom cave
## (tripping), the cop bunker with its drones out, the rival tunnels, lava running out, water and sand, the cathedral's
## giant mushroom, the worm, the trader's menu, the launcher's arc, and the ship basic and fully upgraded. Owned by the
## voxel session.

var arena: Node
var m: VoxelMine
var g: MineGround
var t := 0.0
var step := 0
var mark := 0.0
var out := "user://"
var busy := false
var _then := Callable()

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

## A screenshot of the next frame drawn (nothing changes till it's taken: _process waits on busy).
func _shot(name: String) -> void:
	busy = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/mine_%s.png" % [out, name])
	print("SHOT ", name)
	busy = false

## The ship sat on a floor at (x, depth): a ship-sized hole dug there, a floor under it
func sit(x: float, depth: float) -> void:
	var at := Vector2(x, -depth + MineShip.HALF + 0.01)
	g.set_box(at, Vector2(0.5, 0.45), MineTiles.AIR)
	if g.count(at + Vector2(0, -0.52), Vector2(0.45, 0.06), -1) < 6:
		g.set_box(at + Vector2(0, -0.6), Vector2(0.5, 0.12), MineTiles.STONE)
	m.ship.place(at)
	m._cam_at = Vector3(clampf(x, 10.5, MineGround.W - 10.5), at.y + 0.6, 12.0)
	m.cam_hold = false

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
				_then = func(): next(2)
		2:
			if e > 0.3:
				m.enter()
				m.tips_done = {"welcome": true}
				next(3)
		3:
			if e > 1.5:
				g = m.ground
				m.ship.place(Vector2(13.5, MineShip.HALF + 0.01))
				m._cam_at = Vector3(14.5, 2.4, 12.0)
				next(4)
		4:
			if e > 0.8:
				_shot("surface")
				_then = func():
					m.ship.place(Vector2(31.5, MineShip.HALF + 0.01))
					m.auto = {"down": true}
					next(5)
		5:
			if e > 2.5:
				m.auto = {"x": 1.0}
				next(6)
		6:
			if e > 1.6:
				_shot("shaft")
				_then = func():
					m.auto = {}
					# ore in the stone, the drill going
					sit(22.0, 34.0)
					for k in 5:
						g.set_box(Vector2(23.0 + k * 0.35, -33.6 + (k % 2) * 0.3), Vector2(0.18, 0.18), [MineTiles.COPPER, MineTiles.SILVER, MineTiles.GOLD][k % 3])
					m.auto = {"x": 1.0}
					next(7)
		7:
			if e > 0.45:
				_shot("drilling")
				_then = func(): next(8)
		8:
			if e > 0.6:
				_shot("drilling2")
				_then = func():
					m.auto = {}
					var c: Array = g.features.caves[1]
					var f := g._floor_spot(float(c[0]), float(c[1]) - float(c[3]), float(c[1]) + float(c[3]) + 1.0)
					m.ship.place(f + Vector2(0, MineShip.HALF + 0.02))
					m._cam_at = Vector3(clampf(f.x, 10.5, MineGround.W - 10.5), f.y + 1.0, 12.0)
					m.trip = 0.7
					m.cave_t = 30.0
					next(9)
		9:
			if e > 0.9:
				_shot("mushroom_cave")
				_then = func():
					m.trip = 0.0
					var b: Array = g.features.bunker
					g.set_box(Vector2(float(b[0]) - 2.5, -float(b[3]) + 1.5), Vector2(2.5, 0.5), MineTiles.AIR)
					sit(float(b[0]) - 1.0, float(b[3]) - 1.0)
					m.critters._raise_alarm()
					next(10)
		10:
			if e > 1.2:
				_shot("bunker")
				_then = func():
					m.critters.stand_down()
					m.critters.alarm_rest = 0.0
					var spots: Array = g.features.rival
					var sp: Vector2 = spots[spots.size() / 4]
					m.ship.place(sp + Vector2(0, -0.6))
					m._cam_at = Vector3(clampf(sp.x, 10.5, MineGround.W - 10.5), sp.y + 0.4, 12.0)
					m.critters.on_enter()
					for i in m.critters.pods.size():
						m.critters.pods[i].p = spots[(spots.size() / 4 + 6 + i * 4) % spots.size()]
					next(11)
		11:
			if e > 0.8:
				_shot("rivals")
				_then = func():
					m.critters._drop(m.critters.pods)
					var lp: Vector2 = g.features.lava[0]
					# a tunnel off the side of a lava pocket, the ship a little way along it
					g.set_box(lp + Vector2(4.0, 0), Vector2(3.0, 0.5), MineTiles.AIR)
					g.set_box(lp + Vector2(4.0, -0.62), Vector2(3.0, 0.12), MineTiles.STONE)
					m.ship.place(lp + Vector2(6.0, -0.08))
					m._cam_at = Vector3(clampf(lp.x + 3.0, 10.5, MineGround.W - 10.5), lp.y + 0.8, 12.0)
					m.hull = 9999.0
					next(12)
		12:
			if e > 2.5:
				_shot("lava")
				_then = func():
					m.hull = m.hull_max()
					var cat: Array = g.features.cathedral
					m.ship.place(Vector2(float(cat[0]) - 5.0, -float(cat[5]) + MineShip.HALF + 0.3))
					m.trip = 0.3
					m.cam_hold = true
					m.cam.position = Vector3(float(cat[0]), -float(cat[1]) + 1.0, 15.0)
					next(13)
		13:
			if e > 1.2:
				_shot("cathedral")
				_then = func():
					m.trip = 0.0
					m.cam_hold = false
					var w: Array = g.features.worm
					sit(float(w[0]) + 5.0, float(w[1]) + 1.0)
					m.hull = 9999.0
					next(14)
		14:
			if e > 2.5:
				_shot("worm")
				_then = func():
					m.hull = m.hull_max()
					m.ship.place(Vector2(MineGround.building_x("trader"), MineShip.HALF + 0.01))
					m.cargo = {"gold": 3, "silver": 4, "coal": 5, "opal": 1}
					next(15)
		15:
			if e > 0.5:
				m._near = "trader"
				m.use()
				next(16)
		16:
			if e > 0.6:
				_shot("trader")
				_then = func():
					m.hud.close_menu()
					m.upg = {"drill": 3, "tank": 3, "cargo": 3, "hull": 3, "lights": 3, "launcher": 3}
					m.ship.build(m.upg)
					m.ship.place(Vector2(MineGround.building_x("mechanic"), MineShip.HALF + 0.01))
					m.cam_hold = true
					m.cam.position = Vector3(MineGround.building_x("mechanic"), 1.0, 3.6)
					next(17)
		17:
			if e > 0.5:
				_shot("ship_maxed")
				_then = func():
					quit()
	return false
