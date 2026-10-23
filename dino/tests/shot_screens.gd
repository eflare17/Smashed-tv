extends SceneTree
## Photographs the screens (needs a window): the level-up choice, a hunter winding up, the other areas' looks, and
## the end of a run. From the dino folder: godot --path . --script res://tests/shot_screens.gd -- --out=<folder>

func _initialize() -> void:
	_run.call_deferred()

func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])

func _run() -> void:
	var out := "shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	for f in 10:
		await process_frame
	var pl: Player = main.player
	main.set("_hunt_t", 99999.0)

	# a hunter winding up next to you
	pl.position = Vector2(200, main.GROUND_Y)
	var h: Hunter = main.spawn_hunter(240.0)
	for f in 200:
		await process_frame
		if h.state == Hunter.WINDUP and h.get("_t") < 0.25:
			break
	await _shot(out, "hunter_windup")

	main.add_xp(main.xp_needed(), pl.global_position)
	for f in 3:
		await process_frame
	await _shot(out, "level_up")
	main._pick(0)

	for n in [2, 3, 4]:
		main.enter_area(n)
		main.set("_hunt_t", 99999.0)
		pl.position = Vector2(260, main.GROUND_Y)
		for f in 5:
			await process_frame
		await _shot(out, "area_%d" % n)

	pl.hp = 1.0
	pl.invuln = 0.0
	main.hunter_bit(main.spawn_hunter(pl.position.x + 30.0))
	for f in 20:
		await process_frame
	await _shot(out, "game_over")
	quit()
