extends SceneTree
## Photographs the cast side by side, a pterodactyl diving and a charger charging (needs a window). From the dino
## folder: godot --path . --script res://tests/shot_creatures.gd -- --out=<folder>

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
	pl.position = Vector2(60, main.GROUND_Y)
	var cast: Array = [main.spawn_prey(110.0, Prey.RUNNER), main.spawn_hunter(160.0), main.spawn_prey(240.0),
			main._spawn_herd_kind(Area.HERD_CHARGER, 350.0)]
	var fl: Flyer = main.spawn_flyer(200.0)
	for f in 4:
		await process_frame
	for c in cast:
		c.state = 99
		c.vel = Vector2.ZERO
		c.set_facing(1.0)
	fl.state = 99
	fl.position = Vector2(440, 90)
	fl.set_facing(-1.0)
	for f in 3:
		await process_frame
	await _shot(out, "cast")
	# the pterodactyl dives
	for c in cast:
		c.queue_free()
		main.creatures.erase(c)
	fl.state = Flyer.CIRCLE
	fl.set("_t", 0.2)
	for f in 400:
		await process_frame
		if fl.state == Flyer.DIVE and fl.position.distance_to(pl.position) < 70.0:
			break
	await _shot(out, "flyer_dive")
	fl.queue_free()
	main.creatures.erase(fl)
	# a charger, angry, charging
	var ch: Charger = main._spawn_herd_kind(Area.HERD_CHARGER, 260.0)
	await process_frame
	ch.hurt(pl.global_position)
	for f in 400:
		await process_frame
		if ch.state == Charger.CHARGE:
			break
	for f in 6:
		await process_frame
	await _shot(out, "charger_charge")
	# the danger bar after a while in the area
	main.area_t = 80.0
	for f in 3:
		await process_frame
	await _shot(out, "danger")
	quit()
