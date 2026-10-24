extends SceneTree
## Photographs the kill moment (needs a window): the frame of the killing bite, the slow-motion beat with the
## camera punched in, and the KILL! landing. From the dino folder:
##   godot --path . --script res://tests/shot_kill.gd -- --out=<folder>

const DinoArt := preload("res://scripts/dino_art.gd")

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
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()
	main.obstacles.clear()
	var pl: Player = main.player
	pl.position = Vector2(250.0, main.GROUND_Y)
	var victim: Prey = main.spawn_prey(300.0, Prey.RUNNER)
	await process_frame
	victim.state = 99
	victim.set_facing(-1.0)
	for f in 3:
		await process_frame
	# chew it down to the last bite by hand, then let the real bite land the kill
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	while victim.mass_fraction() > Prey.DIE_MASS + 0.06:
		var pts: Array = []
		for part in victim.parts:
			for i in part.w * part.h:
				if part.alive[i] == 1 and part.zone[i] == DinoArt.BODY:
					pts.append(part.to_world(Vector2(i % part.w + 0.5, i / part.w + 0.5)))
		if pts.is_empty():
			break
		victim.bite(pts[rng.randi() % pts.size()], 4.0, rng)
	var spot := Vector2.ZERO
	for part in victim.parts:
		for i in part.w * part.h:
			if part.alive[i] == 1 and part.zone[i] == DinoArt.NECK:
				spot = part.to_world(Vector2(i % part.w + 0.5, i / part.w + 0.5))
	pl.step(1.0 / 60.0, 0.0, false, true, spot)
	for f in 40:
		await process_frame
		if victim.dead:
			break
	await _shot(out, "kill_1_bite")
	for f in 12:
		await process_frame
	await _shot(out, "kill_2_slowmo")
	for f in 600:
		if main.get("_pending").is_empty() and main.get("_slow_t") <= 0.0:
			break
		await process_frame
	await _shot(out, "kill_3_popup")
	var names: Array = []
	for pu in main.get("_popups"):
		names.append("%s@%s" % [pu[0], pu[1]])
	print("dead: %s, popups: %s, pending: %d, slow %.2f" % [victim.dead, names, main.get("_pending").size(), main.get("_slow_t")])
	quit()
