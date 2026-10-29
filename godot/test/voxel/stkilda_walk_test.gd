extends SceneTree
## St Kilda's walking map (VoxelParkNav): four enemies stood on Luna Park's forecourt find their way in through Mr
## Moon's mouth and round the rides to you, stood at the back of the park; then (a wall of a building knocked through)
## the map's made again. Pictures (under a display, Forward+: -- --out=dir). Prints PASS or FAIL. Owned by the St
## Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var t := 0.0
var step := 0
var out := ""
var fails := []
var them: Array = []
var start_d := 0.0

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

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _far() -> float:
	var most := 0.0
	for b in them:
		if is_instance_valid(b) and b.alive:
			most = maxf(most, Vector2(b.position.x - arena.player.global_position.x, b.position.z - arena.player.global_position.z).length())
	return most

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0:
		return false
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			sk = arena.stkilda
			sk.go()
			sk.nav.bake()
			step = 1
			t = 0.0
		1:
			if sk.nav.ready_:
				print("walking map made in ", snappedf(t, 0.1), " s")
				var front: Vector3 = sk.arrive_spot()[0]
				for k in 4:
					them.append(sk.spawn(["grunt", "swarmer", "batter", "brute"][k], front + Vector3(k * 1.5 - 2.0, 0, 0)))
				sk.stand("0,-80,180")              # (at the back of the park, looking back at the way in)
				start_d = _far()
				print("they start ", snappedf(start_d, 0.1), " m away")
				step = 2
				t = 0.0
			elif t > 30.0:
				_check(false, "the walking map made")
				step = 99
		2:
			if t > 6.0 and t < 6.1:
				_shot("walk_coming")
			if _far() < 4.0 or t > 110.0:
				_check(_far() < 4.0, "all four found their way to you (furthest %.1f m, from %.1f m, in %.0f s)" % [_far(), start_d, t])
				_shot("walk_there")
				step = 3
				t = 0.0
		3:
			sk.home()
			_check(not arena.bodies.any(func(x): return x.has_meta("park")), "home: St Kilda's enemies gone")
			step = 99
		99:
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false
