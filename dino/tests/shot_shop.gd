extends SceneTree
## Photographs the death screen's bones shop (needs a window), with some bones and a few ranks bought.
## From the dino folder: godot --path . --script res://tests/shot_shop.gd -- --out=<folder>

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
	for f in 20:
		await process_frame
	main.set("_hunt_t", 99999.0)
	main.bones.bones = 15
	main.bones.ranks = [2, 0, 1, 0, 0, 5, 0] as Array[int]
	main.kills = 14
	main.eaten = 6
	main.level = 8
	main.area_n = 2
	main.evolves = 1
	main.call("_game_over")
	for f in 70:
		await process_frame
	await _shot(out, "shop")
	quit()
