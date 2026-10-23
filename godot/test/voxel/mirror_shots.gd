extends SceneTree
## The bedroom mirror close up (under a display): mirror_old (its reflection held at 360 pixels, as it was) and
## mirror_sharp (as many as it covers on screen, Ultra). -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	arena._hud_layer.visible = false
	match step:
		0:
			arena.settings_menu.s.set_preset("ultra")
			arena.settings_menu.s.apply(arena)
			arena.frozen = true
			arena.player.global_position = Vector3(-1.1, 0, 28.75)
			arena.player.reset_physics_interpolation()
			arena.look_yaw = PI
			arena.look_pitch = -0.08
			VoxelMirror.max_res = 360
			t = 10.0
			step = 1
		1:
			if t > 11.5:
				_shot("mirror_old")
				arena.settings_menu.s.apply(arena)
				t = 20.0
				step = 2
		2:
			if t > 21.5:
				_shot("mirror_sharp")
				step = 3
		3:
			return true
	return false
