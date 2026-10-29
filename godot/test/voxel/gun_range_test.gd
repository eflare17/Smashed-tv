extends SceneTree
## The gun range (VoxelGunRange): 4 on the phone takes you there (the pistol's lane, the pistol out, its dummies down
## the lane); knock them all down and the lane's DONE (and set up again); ] the next lane (the shotgun out); the phone
## home. Pictures of every lane (under a display, Forward+: -- --out=dir). Prints PASS or FAIL. Owned by the St Kilda
## session.

var arena: VoxelArena
var r: VoxelGunRange
var t := 0.0
var step := 0
var out := ""
var fails := []
var pic := 0
var snapped := false

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
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

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 or arena.phone._going:
		return false
	match step:
		0:
			arena.waves.queue.clear()
			arena.godmode = true
			r = arena.gun_range
			_key(KEY_P)
			step = 1
			t = 1.5
		1:
			_shot("range_phone")
			_key(KEY_4)
			step = 2
			t = 0.0
		2:
			if t > 1.5:
				_check(r.active, "4 on the phone: at the gun range")
				_check(arena.loadout.id() == "pistol", "the pistol's lane: the pistol out (%s)" % arena.loadout.id())
				_check(r._bodies.size() == 3, "three dummies down the lane (%d)" % r._bodies.size())
				_shot("range_pistol")
				step = 3
				t = 0.0
		3:
			# knocked down, a few shots a frame from just above their heads
			var left: Array = r._bodies.filter(func(b): return b.alive)
			if not left.is_empty() and t < 8.0:
				for b in left:
					var aim: Vector3 = b.global_position + Vector3(0, b.height * 0.85, 0)
					arena.fire(aim + Vector3(0.05, 1.2, 0), Vector3(-0.05, -1.2, 0).normalized(), 1, 0.0, 4.0)
				return false
			if t > 9.0:
				_check(r.done.has(r.lane), "all down: the lane's DONE")
				_shot("range_done")
				_key(KEY_BRACKETRIGHT)
				step = 4
				t = 0.0
		4:
			if t > 1.5:
				_check(r.lane == 6 and arena.loadout.id() == "shotgun", "]: the shotgun's lane, the shotgun out (%s)" % arena.loadout.id())
				# every lane's picture
				r.to_lane(pic)
				step = 5
				t = 0.0
		5:
			if not snapped:
				snapped = true
				_shot("range_lane_%02d" % (pic + 1))
			elif t > 2.4:
				snapped = false
				pic += 1
				if pic < VoxelGunRange.STOPS.size():
					r.to_lane(pic)
					t = 0.0
				else:
					step = 6
		6:
			r.home()
			_check(not r.active and not arena.bodies.any(func(b): return b.has_meta("range")), "home: the range's dummies gone")
			step = 99
		99:
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false
