extends SceneTree
## St Kilda's Scenic Railway (VoxelStKilda): E on the yellow ring gets you in the front seat, W speeds it up, V the
## view from behind, E gets off early back on the ring, and a whole ride ends back on the ring too. Pictures along
## the way (under a display, Forward+: -- --out=dir). Prints PASS or FAIL. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var t := 0.0
var step := 0
var out := ""
var busy := false
var fails := []

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

func _key(k: Key, down := true) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	if down:
		_key(k, false)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _ring() -> Vector3:
	return sk.global_transform * (sk.railway().get_meta("board") as Vector3)

func _go(to: int) -> void:
	step = to
	t = 2.0

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 or busy:
		return false
	match step:
		0:
			arena.godmode = true
			sk = arena.stkilda
			sk.go()
			var r := _ring()
			var into: Vector3 = sk.railway().get_meta("board_into")
			sk._put(r + Vector3(into.x, 0.05, into.z) * 3.0, atan2(into.x, into.z), -0.35)   # (by the ring, looking at it and the station)
			_go(1)
		1:
			if t > 2.5:
				_check(sk.near_ride, "on the ring: E rides it")
				_shot("ride_ring")
				_key(KEY_E)
				_go(2)
		2:
			_check(sk.riding(), "E: in the front seat")
			_go(3)
		3:
			Input.parse_input_event(_held(KEY_W, true))
			if t > 4.0:
				Input.parse_input_event(_held(KEY_W, false))
				_check(SkScenicRailway.speed > 1.5, "W speeds it up (×%.1f)" % SkScenicRailway.speed)
				_go(4)
		4:
			# on to the big drop: the train's top speed spot (the steepest way down)
			if sk.ride_train.here() > sk.ride_train.lift_end + 5.0 or t > 40.0:
				_shot("ride_front_seat")
				_key(KEY_V)
				_go(5)
		5:
			if t > 3.5:
				_check(sk.ride_train.chase_cam.current, "V: the view from behind")
				_shot("ride_from_behind")
				_key(KEY_V)
				_go(6)
		6:
			if t > 2.5:
				_key(KEY_E)
				_go(7)
		7:
			_check(not sk.riding(), "E: off early")
			_check(arena.player.global_position.distance_to(_ring()) < 1.0, "stood back on the ring")
			_check(arena.cam.current, "the arena's view back")
			_key(KEY_E)
			_go(8)
		8:
			_check(sk.riding(), "on again")
			sk.ride_train.s = sk.ride_train.s + sk.ride_train.total - 6.0      # (nearly round both laps)
			_go(9)
		9:
			if not sk.riding() or t > 12.0:
				_check(not sk.riding(), "a whole ride ends back at the station")
				_check(arena.player.global_position.distance_to(_ring()) < 1.0, "stood on the ring after it")
				_shot("ride_after")
				_key(KEY_E)
				_go(10)
		10:
			_check(sk.riding(), "on again (for the phone)")
			sk.home()
			_check(not sk.riding() and not sk.active, "the phone home takes you off it first")
			_check(arena.cam.current, "the arena's view, home")
			print("PASS" if fails.is_empty() else "FAIL: %s" % ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
			return true
	return false

func _held(k: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	return e
