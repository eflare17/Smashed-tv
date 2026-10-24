extends SceneTree
## Lets the bot play whole runs headless and prints how each went (how long, level, area, kills, what killed it).
## From the dino folder: godot --headless --path . --script res://tests/stats_run.gd -- --runs=3

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var runs := 3
	var leaves := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--leaves="):
			leaves = float(a.substr(9))
		if a.begins_with("--runs="):
			runs = int(a.substr(7))
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.demo = true
	main.bot_leaves_at = leaves
	await process_frame
	for r in runs:
		main.start_run()
		var t := 0.0
		var dt := 1.0 / 60.0
		var levels_at: Array = []
		var areas_at: Array = []
		var hp_low := 100.0
		var last_level := 1
		var last_area := 1
		var hits := 0
		var hp_prev: float = main.player.hp
		while main.state != main.OVER and t < 600.0:
			await process_frame
			t += dt
			if main.level != last_level:
				last_level = main.level
				levels_at.append("L%d@%ds" % [main.level, int(t)])
			if main.area_n != last_area:
				last_area = main.area_n
				areas_at.append("A%d@%ds" % [main.area_n, int(t)])
			if main.player.hp < hp_prev:
				hits += 1
			hp_prev = main.player.hp
			hp_low = minf(hp_low, main.player.hp)
		print("run %d (seed %d): %ds, level %d, area %d, kills %d, eaten %d, size %.1f, hit %d times, %s" % [
			r + 1, main.run_seed, int(t), main.level, main.area_n, main.kills, main.eaten, main.player.size, hits,
			"died" if main.state == main.OVER else "still alive"])
		print("   ", " ".join(levels_at), " | ", " ".join(areas_at))
	quit()
