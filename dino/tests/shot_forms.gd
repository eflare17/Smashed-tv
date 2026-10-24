extends SceneTree
## Photographs the four forms side by side, then the evolve moment (needs a window). From the dino folder:
##   godot --path . --script res://tests/shot_forms.gd -- --out=<folder>

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
	for f in 5:
		await process_frame
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()
	main.obstacles.clear()
	var pl: Player = main.player
	# the four forms in a row: the player itself for the first, stand-ins (spare Players) for the others
	var xs := [36.0, 90.0, 160.0, 255.0]
	pl.position = Vector2(xs[0], main.GROUND_Y)
	var extras: Array = []
	for s in range(1, 4):
		var p := Player.new()
		p.game = main
		main.area.add_child(p)
		p.set_stage(s)
		p.position = Vector2(xs[s], main.GROUND_Y)
		extras.append(p)
	for f in 4:
		await process_frame
	await _shot(out, "forms")
	for p in extras:
		p.queue_free()
	# the evolve moment
	pl.position = Vector2(200.0, main.GROUND_Y)
	main.eaten = pl.meals_to_evolve()
	main._evolve()
	for f in 3:
		await process_frame
	await _shot(out, "evolve_flash")
	for f in 600:
		await process_frame
		if main.get("_pending").is_empty() and main.get("_slow_t") <= 0.0:
			break
	for f in 10:
		await process_frame
	await _shot(out, "evolve_after")
	print("now a %s, size %.2f" % [pl.stage_name(), pl.size])
	quit()
