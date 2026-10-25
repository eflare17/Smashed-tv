extends SceneTree
## Photographs the phone controls in use (needs a window): left thumb walking, the lock on a runner's neck, the
## right thumb charging a big bite. From the dino folder:
##   godot --path . --script res://tests/shot_touch.gd -- --out=<folder>

func _initialize() -> void:
	_run.call_deferred()

func _ev(index: int, at: Vector2, pressed: bool, drag := false) -> InputEvent:
	if drag:
		var d := InputEventScreenDrag.new()
		d.index = index
		d.position = at
		return d
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = at
	t.pressed = pressed
	return t

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
	var touch: Touch = main.touch
	touch.active = true
	var pl: Player = main.player
	pl.position = Vector2(150.0, main.GROUND_Y)
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()
	var r: Prey = main.spawn_prey(190.0, Prey.RUNNER)
	await process_frame
	r.state = 99
	# pick the neck: one flick up
	touch.handle(_ev(1, Vector2(400, 200), true))
	touch.handle(_ev(1, Vector2(400, 180), false, true))
	touch.handle(_ev(1, Vector2(400, 180), false))
	for f in 10:
		await process_frame
	# left thumb down and a little right; right thumb holding
	touch.handle(_ev(0, Vector2(90, 200), true))
	touch.handle(_ev(0, Vector2(100, 200), false, true))
	touch.handle(_ev(1, Vector2(410, 210), true))
	for f in 400:
		await process_frame
		r.state = 99
		r.vel = Vector2.ZERO
		if pl.charging and pl.charge > 0.6:
			break
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/touch_controls.png" % out)
	print("saved")
	quit()
