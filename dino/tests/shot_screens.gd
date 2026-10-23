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

	# a quick bite at the snap, then a charged big bite mid-shake, on a prey standing still
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()
	main.obstacles.clear()
	var p: Prey = main.spawn_prey(300.0)
	p.set_facing(-1.0)
	pl.position = Vector2(255.0, main.GROUND_Y)
	pl.vel = Vector2.ZERO
	pl.cool = 0.0
	for f in 3:
		await process_frame
	# a state it has no behaviour for: it just stands there
	p.state = 99
	var neck_spot: Vector2 = p.rig.to_global(Vector2(25, -38))
	pl.step(1.0 / 60.0, 0.0, false, true, neck_spot)
	for f in 30:
		await process_frame
		if pl.bite_t >= pl.WIND[0]:
			break
	await _shot(out, "quick_bite")
	for f in 30:
		await process_frame
	pl.cool = 0.0
	pl.bite_t = -1.0
	p.state = 99
	p.vel = Vector2.ZERO
	p.position.x = 300.0
	pl.position.x = 250.0
	await process_frame
	main.demo = true
	main.set("_bot_point", p.rig.to_global(Vector2(0, -24)))
	main.set("_bot_charge", 1.0)
	pl.step(1.0 / 60.0, 0.0, false, false, main.get("_bot_point"), true)
	for f in 200:
		await process_frame
		if not pl.grab.is_empty() and pl.grab.t > 0.15:
			break
	await _shot(out, "big_bite_shake")
	main.demo = false
	for f in 60:
		await process_frame
	await _shot(out, "big_bite_after")

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
	main.creature_hit(main.spawn_hunter(pl.position.x + 30.0), Hunter.DAMAGE)
	for f in 20:
		await process_frame
	await _shot(out, "game_over")
	quit()
