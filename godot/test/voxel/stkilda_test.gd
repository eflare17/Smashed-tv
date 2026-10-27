extends SceneTree
## St Kilda (scripts/voxel/stkilda): P gets the phone out, Travel to St Kilda puts you on Luna Park's forecourt
## facing Mr Moon (the arena waiting: its enemies stood still, the weapons away), you can walk in through his mouth,
## and Travel home puts you back where you were. Pictures along the way (under a display, Forward+:
## -- --out=dir). Prints PASS or FAIL. Owned by the St Kilda session.

var arena: VoxelArena
var t := 0.0
var step := 0
var out := ""
var busy := false
var fails := []
var home_at := Vector3(3.0, 0.05, 8.0)
var walk_from := Vector3.ZERO

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	if out == "":
		return
	busy = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)
	busy = false

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 or busy or arena.phone._going:
		return false
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			arena.player.global_position = home_at
			arena.look_yaw = 0.3
			_key(KEY_P, true)
			_key(KEY_P, false)
			step = 1
		1:
			_check(arena.phone.is_open(), "P gets the phone out")
			_shot("stkilda_phone_home")
			step = 2
		2:
			_key(KEY_2, true)
			_key(KEY_2, false)
			step = 3
		3:
			_check(arena.stkilda.active, "2 on the phone: off to St Kilda")
			_check(arena.frozen, "the arena's enemies stood still")
			_check(arena.player.global_position.z < -2000.0, "you're in St Kilda (%s)" % arena.player.global_position)
			_shot("stkilda_arrive")
			walk_from = arena.player.global_position
			step = 4
			t = 2.0
		4:
			_key(KEY_W, true)                  # walk at Mr Moon for 6 s (27 m: through his mouth)
			if t > 8.0:
				_key(KEY_W, false)
				var face := arena.stkilda.global_transform * SkLunaPark.xf(arena.stkilda.town)
				var past := (face.affine_inverse() * arena.player.global_position).z
				_check(past < -3.0, "walked in through Mr Moon's mouth (%.1f m past his face)" % -past)
				arena.look_yaw += 0.6
				step = 5
		5:
			_shot("stkilda_inside")
			step = 6
		6:
			arena.stkilda.stand("0,-75,0")
			step = 7
			t = 2.0
		7:
			if t > 2.5:
				_shot("stkilda_deep")
				arena.stkilda.stand("0,3,0")
				arena.look_pitch = 0.25
				_key(KEY_V, true)
				_key(KEY_V, false)
				step = 8
				t = 2.0
		8:
			if t > 3.0:
				_shot("stkilda_topdown")
				_key(KEY_V, true)
				_key(KEY_V, false)
				arena.stkilda.stand("0,0,0")
				arena.look_pitch = 0.0
				_key(KEY_P, true)
				_key(KEY_P, false)
				step = 9
				t = 2.0
		9:
			if t > 2.5:
				_shot("stkilda_phone_there")
				_key(KEY_1, true)
				_key(KEY_1, false)
				step = 10
		10:
			_check(not arena.stkilda.active, "1 on the phone: home")
			_check(not arena.frozen, "the arena going again")
			_check(arena.player.global_position.distance_to(home_at) < 0.3, "back where you were (%s)" % arena.player.global_position)
			_check(arena.sun.visible and not arena.stkilda.sun.is_visible_in_tree(), "the arena's sun back")
			_shot("stkilda_home")
			step = 11
		11:
			print("PASS" if fails.is_empty() else "FAIL: %s" % ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
			return true
	return false
