extends SceneTree
## Screenshots of killing the chickens (not headless: under a display, e.g. xvfb-run): a hen out in the yard hit with
## the sword (feathers flying, running), the carcasses lying with their feathers round them, looking at one ("E  pick up
## the chicken carcass"), the backpack with it in, and from above. -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var out := "user://"
var _ids := []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _ch() -> VoxelChickens:
	return arena.yard.chickens

func _view(p: Vector3, at: Vector3) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	var to := at - (p + Vector3(0, 1.65, 0))
	arena.look_yaw = atan2(-to.x, -to.z)
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	var ch := _ch()
	match step:
		0:
			arena.frozen = true
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			arena.inv.from_data([])
			ch._fresh()
			ch.gate = true
			ch.hens.clear()
			# out in the yard: the one to hit, two more about, a chick; one left in the run
			for s in [[Vector2(15.0, 30.0), 0, 1.0], [Vector2(16.6, 31.4), 1, 1.0], [Vector2(14.2, 32.0), 2, 1.0], [Vector2(15.9, 32.6), 0, 0.3], [Vector2(24.5, 28.0), 1, 1.0]]:
				var h: Dictionary = ch._hatch(s[0], s[2], s[1])
				h.st = "peck"
				h.t = 999.0
				h.y = ch._ground_y(h.x, h.z)
				_ids.append(int(h.id))
			var si: int = arena.loadout.index_of("sword")
			arena._switch(func(): arena.loadout.select(si))
			arena.loadout.switch_t = 0.0
			_view(Vector3(13.6, 0, 29.6), Vector3(15.2, 0.25, 30.4))
			mark = t
			step = 1
		1:
			if t - mark > 1.0:
				ch.strike(_ids[0], 1, arena.player.global_position)
				arena.melee["sword"].press(MOUSE_BUTTON_LEFT)
				mark = t
				step = 2
		2:
			if t - mark > 0.16:
				_shot("chickens_kill_hit")
				mark = t
				step = 3
		3:
			if t - mark > 0.5:
				# killed: the hen, the brown one, the chick
				for i in 4:
					var h = ch._hen_by(_ids[i])
					if h != null and i != 2:
						h.hit_ms = 0
						ch.strike(_ids[i], VoxelChickens.HP, Vector3(float(h.x) - 1.0, 0, float(h.z)))
				mark = t
				step = 4
		4:
			if t - mark > 0.6:
				# laid out to be seen: the carcasses close together, the black hen still alive beside them
				var spots := [Vector2(15.0, 30.6), Vector2(15.75, 30.3), Vector2(15.35, 31.15)]
				var k := 0
				for c in ch.carcasses:
					c.x = spots[k].x
					c.z = spots[k].y
					c.y = ch._ground_y(c.x, c.z)
					c.yaw = [0.4, 2.3, -1.1][k]
					k += 1
				var bl = ch._hen_by(_ids[2])
				if bl != null:
					bl.x = 16.5
					bl.z = 31.6
					bl.st = "peck"
					bl.t = 999.0
					bl.path = []
				mark = t
				step = 5
		5:
			if t - mark > 4.0:
				_view(Vector3(14.0, 0, 29.2), Vector3(15.4, 0.0, 30.7))
				mark = t
				step = 6
		6:
			if t - mark > 0.6:
				_shot("chickens_kill_carcass")
				# looking right at one: E picks it up
				var c: Dictionary = ch.carcasses[0]
				_view(Vector3(float(c.x) - 1.0, 0, float(c.z) - 0.3), Vector3(float(c.x), 0.05, float(c.z)))
				mark = t
				step = 7
		7:
			if t - mark > 0.6:
				_shot("chickens_kill_pickup")
				mark = t
				step = 8
		8:
			if t - mark > 0.3:
				var e := InputEventKey.new()
				e.physical_keycode = KEY_E
				e.pressed = true
				arena._unhandled_input(e)
				mark = t
				step = 9
		9:
			if t - mark > 0.4:
				_shot("chickens_kill_picked")
				mark = t
				step = 10
		10:
			if t - mark > 0.3:
				arena.open_inventory(null)
				mark = t
				step = 11
		11:
			if t - mark > 0.6:
				_shot("chickens_kill_backpack")
				mark = t
				step = 12
		12:
			if t - mark > 0.3:
				arena.close_inventory()
				arena.top_down = true
				_view(Vector3(14.6, 0, 30.2), Vector3(15.4, 0, 31.0))
				mark = t
				step = 13
		13:
			if t - mark > 1.0:
				_shot("chickens_kill_topdown")
				mark = t
				step = 14
		14:
			return t - mark > 0.5
	return false
