extends SceneTree
## Screenshots of Gothica (under a display, Forward+: -- --out=dir): goth_front (standing, face on), goth_three
## (three-quarters), goth_side (side on), goth_room (in the bedroom by the mirror). Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var cam: Camera3D
var g: VoxelGothica

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

func _look(from: Vector3, at: Vector3, fov := 40.0) -> void:
	if cam == null:
		cam = Camera3D.new()
		arena.add_child(cam)
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.fov = fov
	arena._hud_layer.visible = false
	cam.current = true
	cam.global_position = from
	cam.look_at(at)

func _place(at: Vector3, yaw: float) -> void:
	g.path.clear()
	g.following = false
	g.idle_t = 1e9
	g.body.global_position = at
	g.face = yaw
	g.body.yaw = yaw

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	match step:
		0:
			g = arena.gothica
			for x in OS.get_cmdline_user_args():
				if x.begins_with("--preset="):
					arena.settings_menu.s.set_preset(x.trim_prefix("--preset="))
					arena.settings_menu.s.apply(arena)
				if x.begins_with("--jiggle="):
					VoxelJiggle.level = int(x.trim_prefix("--jiggle="))
			print("preset ", arena.settings_menu.s.which_preset(), " taa ", arena.get_viewport().use_taa, " scale ", arena.get_viewport().scaling_3d_scale)
			arena.frozen = true
			arena.waves.queue.clear()
			for x in arena.bodies:
				x.queue_free()
			arena.bodies.clear()
			arena.player.global_position = Vector3(6, 0, 14)
			_place(Vector3(0, 0, 8), PI)
			_look(Vector3(0, 1.3, 5.9), Vector3(0, 1.05, 8))
			t = 10.0
			step = 1
		1:
			if t > 13.0:
				_shot("goth_front")
				step = 2
		2:
			if t > 13.3:
				_look(Vector3(1.3, 1.2, 6.5), Vector3(0, 1.12, 8))
				step = 3
		3:
			if t > 13.5:
				_shot("goth_three")
				step = 4
		4:
			if t > 13.8:
				_look(Vector3(-2.1, 1.2, 8.15), Vector3(0, 1.12, 8.05))
				step = 5
		5:
			if t > 14.0:
				_shot("goth_side")
				step = 6
		6:
			if t > 14.3:
				_place(Vector3(-1.1, 0, 28.6), PI)
				_look(Vector3(-0.2, 1.6, 26.2), Vector3(-1.1, 1.0, 28.6), 55.0)
				step = 7
		7:
			if t > 16.5:
				_shot("goth_room")
				step = 8
		8:
			return true
	return false
