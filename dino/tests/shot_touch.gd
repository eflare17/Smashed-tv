extends SceneTree
## Photographs the phone controls in use (needs a window): left thumb walking, a finger holding on a runner's
## neck, charging a big bite there. From the dino folder:
##   godot --path . --script res://tests/shot_touch.gd -- --out=<folder>

const DinoArt := preload("res://scripts/dino_art.gd")

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
	# left thumb down and a little right; a finger holding on the runner's neck (charging the big bite there)
	touch.handle(_ev(0, Vector2(60, 200), true))
	touch.handle(_ev(0, Vector2(70, 200), false, true))
	touch.handle(_ev(1, touch.get_canvas_transform() * _neck(r), true))
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

func _neck(c: Prey) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for p in c.parts:
		for i in p.w * p.h:
			if p.alive[i] == 1 and p.zone[i] == DinoArt.NECK:
				sum += p.to_world(Vector2(i % p.w + 0.5, i / p.w + 0.5))
				n += 1
	return sum / maxf(1.0, n)
