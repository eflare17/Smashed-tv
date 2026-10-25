extends SceneTree
## Photographs every area look with a few creatures about, and in the swamp, the volcano and the desert a grazer
## standing in the water, the lava or the quicksand (needs a window). From the dino folder:
##   godot --path . --script res://tests/shot_maps.gd -- --out=<folder>

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
	for n in range(1, Area.NAMES.size() + 1):
		main.enter_area(n)
		main.set("_hunt_t", 99999.0)
		main.set("_herd_t", 99999.0)
		while main.state == main.CHOOSE:
			main._pick(1)
		for c in main.creatures.duplicate():
			c.queue_free()
		main.creatures.clear()
		var area: Area = main.area
		# looking at the first patch if it has them, else a stretch near the start
		var at: float = (area.hazards[0][0] + area.hazards[0][1]) * 0.5 if not area.hazards.is_empty() else 520.0
		var pl: Player = main.player
		pl.position = Vector2(at - 110.0, main.GROUND_Y)
		var cast: Array = [main.spawn_prey(at), main.spawn_prey(at + 90.0, Prey.RUNNER),
				main._spawn_herd_kind(Area.HERD_ANKYLO, at - 40.0)]
		for f in 3:
			await process_frame
		for c: Prey in cast:
			c.state = 99
			c.vel = Vector2.ZERO
			c.set_facing(-1.0)
		# let the quicksand pull the grazer in, and the lava have a go at its feet
		for f in 50:
			await process_frame
			cast[0].position.x = at
			cast[0].vel.x = 0.0
		await _shot(out, "map_%d_%s" % [n, area.look.to_lower().replace(" ", "_")])
	main.queue_free()
	quit()
