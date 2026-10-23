extends SceneTree
## Photographs bites at the moment the jaws snap (needs a window, not --headless). From the dino folder:
##   godot --path . --script res://tests/shot_bite.gd -- --out=<folder>
## Saves bite_<zone>.png close-ups (3x) with a magenta dot on the spot that was aimed at.

const DinoArt := preload("res://scripts/dino_art.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var pl: Player = main.player
	var p: Prey = main.prey[0]
	var dot := Node2D.new()
	dot.z_index = 100
	main.add_child(dot)
	var aim_at := [Vector2.ZERO]
	dot.draw.connect(func(): dot.draw_rect(Rect2(aim_at[0].floor(), Vector2.ONE), Color.MAGENTA))
	for z in [DinoArt.HEAD, DinoArt.NECK, DinoArt.BODY, DinoArt.TAIL, DinoArt.LEGS]:
		p.position = Vector2(300.0, main.GROUND_Y)
		p.vel = Vector2.ZERO
		p.state = Prey.GRAZE
		p.set_facing(-1.0)
		pl.position = Vector2(255.0, main.GROUND_Y)
		pl.vel = Vector2.ZERO
		pl.cool = 0.0
		pl.bite_t = -1.0
		for f in 20:
			await process_frame
		var pts: Array = []
		for part in p.parts:
			for i in part.w * part.h:
				if part.alive[i] == 1 and part.zone[i] == z:
					pts.append(part.to_world(Vector2(i % part.w + 0.5, i / part.w + 0.5)))
		# a spot in range (the aim marker would be red), the middle one of those
		var ok: Array = pts.filter(func(q): return pl.predict_bite(q).distance_to(q) < 1.0)
		var aim: Vector2 = ok[ok.size() / 2] if not ok.is_empty() else pts[pts.size() / 2]
		print("   %d of %d %s pixels in range; predicted miss %.1f" % [ok.size(), pts.size(), DinoArt.ZONE_NAMES[z], pl.predict_bite(aim).distance_to(aim)])
		aim_at[0] = aim
		dot.queue_redraw()
		main.demo = true
		# press bite through the bot's slot: a one-frame override
		main.set("_bot_point", aim)
		pl.step(1.0 / 60.0, 0.0, false, true, aim)
		main.demo = false
		while pl.bite_t >= 0.0 and pl.bite_t < pl.WIND + 0.01:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var c := pl.get_global_transform_with_canvas().origin + Vector2(40, -20)
		var r := Rect2i(Vector2i(clampi(int(c.x) - 60, 0, 360), clampi(int(c.y) - 34, 0, 202)), Vector2i(120, 68))
		var zoom := img.get_region(r)
		zoom.resize(480, 272, Image.INTERPOLATE_NEAREST)
		zoom.save_png("%s/bite_%s.png" % [out, DinoArt.ZONE_NAMES[z].to_lower()])
		print("%s: prey moved %.1f px during the wind-up; teeth landed %.1f px from the spot on its body (neck to spot %.1f, reach %.1f)" % [DinoArt.ZONE_NAMES[z], pl.snap_info[0].distance_to(aim), pl.snap_info[1].distance_to(pl.snap_info[0]), pl.neck().distance_to(pl.snap_info[0]), pl.reach * pl.size])
	quit()
