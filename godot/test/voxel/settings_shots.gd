extends SceneTree
## Screenshots of the settings (not headless: under a display): the screen open; the benchmark running; its results;
## the arena on Low and on Ultra side by side. -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _process(dt: float) -> bool:
	t += dt
	var m: VoxelSettingsMenu = arena.settings_menu
	if step == 0 and t > 1.5:
		arena.frozen = true
		m.open()
		step = 1
	elif step == 1 and t > 2.5:
		_shot("settings_menu")
		step = 2
	elif step == 2 and t > 3.0:
		m.close()
		m.bench_warm = 0.5
		m.bench_measure = 1.5
		m.target_ms = 4.0
		m.bench_start()
		step = 3
	elif step == 3 and t > 4.8:
		_shot("settings_benchmark")
		step = 4
	elif step == 4 and m._bench.is_empty():
		step = 5
		t = 100.0
	elif step == 5 and t > 101.0:
		_shot("settings_results")
		step = 6
	elif step == 6 and t > 101.5:
		m.close()
		m.s.set_preset("low")
		m.s.apply(arena)
		arena.spawn(6)
		t = 200.0
		step = 7
	elif step == 7 and t > 203.0:
		_shot("preset_low")
		step = 8
	elif step == 8 and t > 203.5:
		m.s.set_preset("ultra")
		m.s.apply(arena)
		arena.spawn(6)
		t = 300.0
		step = 9
	elif step == 9 and t > 303.0:
		_shot("preset_ultra")
		step = 10
	elif step == 10 and t > 303.5:
		m.s.set_preset("extreme")
		m.s.apply(arena)
		arena.spawn(6)
		t = 400.0
		step = 11
	elif step == 11 and t > 403.0:
		_shot("preset_extreme")
		step = 12
	elif step == 12 and t > 403.5:
		return true
	return false
