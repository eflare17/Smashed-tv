extends SceneTree
## Big close-ups of a creature's head with the jaw shut, half open and wide open (needs a window). From the dino
## folder: godot --path . --script res://tests/shot_head.gd -- --out=<folder> --stage=<0..3> (your forms) or --hunter

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "shots"
	var stage := 1
	var hunter := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--stage="):
			stage = int(a.substr(8))
		elif a == "--hunter":
			hunter = true
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
	var d: Dino
	if hunter:
		d = main.spawn_hunter(240.0)
		d.state = 99
		d.scale = Vector2.ONE
	else:
		d = Player.new()
		d.game = main
		main.area.add_child(d)
		(d as Player).set_stage(stage)
		d.position = Vector2(240.0 - stage * 40.0, main.GROUND_Y)
		main.player.position = Vector2(60.0, main.GROUND_Y)
	d.set_facing(1.0)
	var name := "hunter" if hunter else "form%d" % stage
	var row: Array = []
	for open in [0.0, 0.45, 0.9]:
		for f in 3:
			await process_frame
		d.jaw.rotation = open * d.jaw_k
		d.head.rotation = 0.0
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		# centred on the middle of the head picture, sized to fit it (and its open jaw)
		var hs := absf(d.head.get_global_transform_with_canvas().get_scale().x)
		var c := d.head.get_global_transform_with_canvas() * (d.head.offset + Vector2(d.head.w, d.head.h) * 0.5) + Vector2(0, d.head.h * hs * 0.3)
		var cw := clampi(int(d.head.w * hs * 2.2), 80, 240)
		var chh := cw * 3 / 4
		var r := Rect2i(Vector2i(clampi(int(c.x) - cw / 2, 0, 480 - cw), clampi(int(c.y) - chh / 2, 0, 270 - chh)), Vector2i(cw, chh))
		var z := img.get_region(r)
		z.resize(480, 360, Image.INTERPOLATE_NEAREST)
		row.append(z)
	var sheet := Image.create(480 * 3 + 16, 360, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for k in 3:
		sheet.blit_rect(row[k], Rect2i(0, 0, 480, 360), Vector2i(k * 488, 0))
	sheet.save_png("%s/%s_jaw.png" % [out, name])
	print("saved %s" % name)
	quit()
