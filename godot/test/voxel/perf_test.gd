extends Node
## What the block characters cost on the CPU: the first build of Jared's meshes (full and half detail), and the
## game's frame (process + physics time) with the characters as pictures and as blocks, him walking.
##   godot --headless --fixed-fps 60 --path godot res://test/voxel/perf_test.tscn
## (The GPU side, triangles: printed from the meshes; draw calls: one a character.)

func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	var md := VoxelModel.get_model("jared")
	var m0 := md.build_mesh("perf0", "classic", 0, VoxelWeapons.attachments(md, "spud", 0))
	var t1 := Time.get_ticks_usec()
	var m1 := md.build_mesh("perf1", "classic", 1, VoxelWeapons.attachments(md, "spud", 1))
	var t2 := Time.get_ticks_usec()
	print("PERF build: full %.0f ms, half %.0f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	print("PERF triangles: full %d, half %d" % [m0.surface_get_array_index_len(0) / 3, m1.surface_get_array_index_len(0) / 3])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var sw := VoxelSwitch.install(main)
	for mode in ["pixel", "blocks", "pixel", "blocks"]:
		sw.set_mode(mode, false)
		for i in 20:
			await get_tree().process_frame
		Input.action_press("move_right")
		var pt := 0.0
		var ph := 0.0
		var n := 240
		for i in n:
			if i == 120:
				Input.action_release("move_right")
				Input.action_press("move_left")
			await get_tree().process_frame
			pt += Performance.get_monitor(Performance.TIME_PROCESS)
			ph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		Input.action_release("move_left")
		var t3 := Time.get_ticks_usec()
		for k in 10:
			sw._scan()
		var scan := (Time.get_ticks_usec() - t3) / 10000.0
		var t4 := Time.get_ticks_usec()
		var vc := (main.player as Player).sprite.get_node_or_null("Blocks") as VoxelChar
		if vc:
			for k in 100:
				vc._process(0.016)
		var vct := (Time.get_ticks_usec() - t4) / 100000.0
		print("PERF scan %.2f ms, one VoxelChar frame %.3f ms" % [scan, vct])
		print("PERF %s: process %.2f ms, physics %.2f ms a frame" % [mode, pt / n * 1000.0, ph / n * 1000.0])
	get_tree().quit()
