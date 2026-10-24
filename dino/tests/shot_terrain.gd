extends SceneTree
## Photographs the terrain (needs a window): the player standing by each kind of raised ground and a shelf.
## From the dino folder: godot --path . --script res://tests/shot_terrain.gd -- --out=<folder> [--seed=<n>]

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
	var pl: Player = main.player
	var shown := {}
	var n := 0
	for slab: Rect2 in main.area.ground:
		var high := slab.size.y > 20.0
		var key := "plateau" if high else "rise"
		if shown.has(key):
			continue
		shown[key] = true
		pl.position = Vector2(slab.position.x - 40.0, main.GROUND_Y)
		pl.vel = Vector2.ZERO
		for f in 8:
			await process_frame
		n += 1
		await _shot(out, "terrain_%d_%s" % [n, key])
	for shelf: Rect2 in main.area.platforms:
		pl.position = Vector2(shelf.position.x - 30.0, main.GROUND_Y)
		pl.vel = Vector2.ZERO
		for f in 8:
			await process_frame
		n += 1
		await _shot(out, "terrain_%d_shelf" % n)
		break
	print("ground slabs %d, shelves %d, obstacles %d" % [main.area.ground.size(), main.area.platforms.size(), main.area.obstacles.size()])
	quit()
