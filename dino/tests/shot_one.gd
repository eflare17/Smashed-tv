extends SceneTree
## Close-ups of one kind of creature (needs a window), to check its art: standing next to you, walking, the zone
## map (F3's colours), after a few bites, and dead. From the dino folder:
##   godot --path . --script res://tests/shot_one.gd -- --out=<folder> --kind=<runner|grazer|charger|hunter|flyer>

const DinoArt := preload("res://scripts/dino_art.gd")

var _size := 40.0

func _initialize() -> void:
	_run.call_deferred()

func _shot(out: String, name: String, at: Vector2) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	# a 4x close-up around `at` (screen position)
	# a bigger window for a bigger creature, so it fits
	var cw := clampi(int(_size * 2.6), 120, 300)
	var chh := cw * 100 / 120
	var r := Rect2i(Vector2i(clampi(int(at.x) - cw / 2, 0, 480 - cw), clampi(int(at.y) - chh / 2, 0, 270 - chh)), Vector2i(cw, chh))
	var zoom := img.get_region(r)
	zoom.resize(480, 400, Image.INTERPOLATE_NEAREST)
	zoom.save_png("%s/%s.png" % [out, name])

func _run() -> void:
	var out := "shots"
	var kind := "runner"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--kind="):
			kind = a.substr(7)
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
	main.platforms.clear()
	var pl: Player = main.player
	pl.position = Vector2(200.0, main.GROUND_Y)
	var c: Prey
	match kind:
		"grazer":
			c = main.spawn_prey(250.0)
		"charger":
			c = main._spawn_herd_kind(Area.HERD_CHARGER, 260.0)
		"hunter":
			c = main.spawn_hunter(240.0)
		"flyer":
			c = main.spawn_flyer(240.0)
		_:
			c = main.spawn_prey(235.0, Prey.RUNNER)
	await process_frame
	c.state = 99
	c.vel = Vector2.ZERO
	c.set_facing(-1.0)
	# drawn at its own size for the close-ups (a hunter is shrunk to match yours)
	c.scale = Vector2.ONE
	if c is Flyer:
		c.position = Vector2(240.0, main.GROUND_Y - 40.0)
	for f in 4:
		await process_frame
	_size = maxf(c.height, c.half_w * 3.0)
	var at: Vector2 = c.get_global_transform_with_canvas().origin + Vector2(0, -c.height * 0.45)
	if c.head:
		# centre between the body and the head, so a long head stays in frame
		at = (at + c.head.get_global_transform_with_canvas().origin) * 0.5
		_size *= 1.2
	await _shot(out, "%s_1_stand" % kind, at)
	# the jaw hanging open (the hunter's wind-up, your bite)
	if c.jaw:
		c.state = 98
		c.jaw.rotation = 0.9
		await process_frame
		await _shot(out, "%s_1b_jaw" % kind, at)
		c.jaw.rotation = 0.0
		c.state = 99
	# walking: swing the legs a few frames in
	c.set_facing(1.0)
	for f in 7:
		c.animate(1.0 / 60.0, true, 12.0)
		if c is Flyer:
			(c as Flyer)._flap_wings(1.0 / 60.0, 9.0)
		await process_frame
	await _shot(out, "%s_2_walk" % kind, at)
	c.set_facing(-1.0)
	# drawn at its own size for the close-ups (a hunter is shrunk to match yours)
	c.scale = Vector2.ONE
	# the zones
	c.set_show_zones(true)
	await process_frame
	await _shot(out, "%s_3_zones" % kind, at)
	c.set_show_zones(false)
	# one bite, in the middle of the body
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for z in [DinoArt.BODY]:
		var pts: Array = []
		for part in c.parts:
			for i in part.w * part.h:
				if part.alive[i] == 1 and part.zone[i] == z:
					pts.append(part.to_world(Vector2(i % part.w + 0.5, i / part.w + 0.5)))
		if not pts.is_empty():
			main.player_bite(pl, pts[pts.size() / 2], pl.bite_radius)
	c.state = 99
	c.vel = Vector2.ZERO
	for f in 20:
		await process_frame
	await _shot(out, "%s_4_bitten" % kind, at)
	# dead
	if not c.dead:
		c.die()
	for f in 240:
		await process_frame
	await _shot(out, "%s_5_dead" % kind, at)
	print("%s: %d parts, height %.1f, half_w %.1f, art_k %.2f" % [kind, c.parts.size(), c.height, c.half_w, c.art_k])
	quit()
