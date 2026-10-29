extends SceneTree
## "Kill 1, 2 come" (VoxelParkGame): 3 on the phone starts it in Luna Park; three come in; each one killed brings two
## more (one more about than before); going down ends it (kills, time, best kept) and clears them; the phone home.
## Pictures (under a display, Forward+: -- --out=dir). Prints PASS or FAIL. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var g: VoxelParkGame
var t := 0.0
var step := 0
var out := ""
var fails := []
var before := 0
var victim: VoxelBody
var had_best := false            # (the real game's best was there before: left as it is; otherwise the test's removed)

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	had_best = FileAccess.file_exists(VoxelParkGame.BEST_FILE)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _park() -> Array:
	return arena.bodies.filter(func(b): return b.alive and b.has_meta("park"))

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 or (arena.phone and arena.phone._going):
		return false
	match step:
		0:
			arena.waves.queue.clear()
			sk = arena.stkilda
			_key(KEY_P)
			step = 1
			t = 1.5
		1:
			_shot("kill12_phone")
			_key(KEY_3)
			step = 2
			t = 0.0
		2:
			g = sk.game
			_check(sk.active and g.running, "3 on the phone: the game on, in St Kilda")
			step = 3
			t = 0.0
		3:
			if _park().size() >= 3 or t > 10.0:
				_check(_park().size() == 3, "three come in (%d)" % _park().size())
				sk.stand("0,-40,0")
				step = 4
				t = 0.0
		4:
			if t > 4.0:
				_shot("kill12_coming")
				before = _park().size()
				victim = _park()[0]
				step = 5
				t = 0.0
		5:
			# shot in the head from just above it (no wall in the way), a few a frame, till it drops
			if victim.alive and t < 4.0:
				for k in 4:
					var aim := victim.global_position + Vector3(0, victim.height * 0.85, 0)
					var from := aim + Vector3(0.05, 1.2, 0.0)
					arena.fire(from, (aim - from).normalized(), 1, 0.0, 4.0)
				return false
			if t > 6.0:
				print("shot down: ", not victim.alive)
				_check(g.kills == 1, "a kill counted (%d)" % g.kills)
				_check(_park().size() == before + 1, "kill 1, 2 come: %d about now (was %d)" % [_park().size(), before])
				_shot("kill12_hud")
				arena.godmode = false
				arena.hurt_player(9999.0)
				step = 6
				t = 0.0
		6:
			if t > 0.5:
				_check(g.over and not g.running, "down: game over")
				_check(_park().is_empty(), "its enemies gone")
				_check(g.best_kills >= 1, "best kept (%d)" % g.best_kills)
				_shot("kill12_over")
				step = 7
				t = 0.0
		7:
			if arena.down_t <= 0.0 or t > 20.0:
				sk.home()
				_check(not sk.active and not g.running, "home")
				step = 99
		99:
			if not had_best:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(VoxelParkGame.BEST_FILE))
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false
