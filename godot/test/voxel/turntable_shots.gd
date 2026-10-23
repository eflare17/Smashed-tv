extends SceneTree
## Turntable of the block characters as the arena shows them (under a display, Forward+: -- --out=dir [--old]): Jared
## and Gothica side by side, front, three-quarters, side, back (turn_0..3), then their faces close, face on and side
## on (face_jared, face_jared_side, face_goth, face_goth_side). --old: Jared and Gothica as they were (the plain
## models, no VoxelReshape) for comparing. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var cam: Camera3D
var j: VoxelBody
var g: VoxelBody
var shots := []

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

func _pose(yaw: float) -> void:
	for b in [j, g]:
		b.yaw = yaw
		b.animate(0.016, false)

func _look(from: Vector3, at: Vector3, fov := 38.0) -> void:
	cam.fov = fov
	cam.global_position = from
	cam.look_at(at)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if step == 0:
		var old := "--old" in OS.get_cmdline_user_args()
		arena.settings_menu.s.set_preset("high")
		arena.settings_menu.s.apply(arena)
		arena.frozen = true
		arena.waves.queue.clear()
		for x in arena.bodies:
			x.queue_free()
		arena.bodies.clear()
		arena.player.global_position = Vector3(10, 0, 14)
		arena.gothica.visible = false
		arena.gothica.set_process(false)
		j = VoxelBody.new()
		arena.add_child(j)
		j.setup("jared" if old else "jared_hd", 0.0125, 1, arena._mat)
		g = VoxelBody.new()
		arena.add_child(g)
		g.setup("goth" if old else "gothica", 0.0125, 1, arena._mat)
		if not old:
			VoxelJiggle.dress(j)
			var jg := VoxelJiggle.new()
			jg.setup(g)
		j.position = Vector3(-0.6, 0, 8)
		g.position = Vector3(0.6, 0, 8)
		cam = Camera3D.new()
		arena.add_child(cam)
		cam.current = true
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		arena._hud_layer.visible = false
		# [yaw, camera from, camera at, fov, name]
		var jh := Vector3(-0.6, 1.6, 8)
		var gh := Vector3(0.6, 1.45, 8)
		shots = [[PI, Vector3(0, 1.2, 4.9), Vector3(0, 1.0, 8), 40.0, "turn_0"],
			[PI * 0.75, Vector3(0, 1.2, 4.9), Vector3(0, 1.0, 8), 40.0, "turn_1"],
			[PI * 0.5, Vector3(0, 1.2, 4.9), Vector3(0, 1.0, 8), 40.0, "turn_2"],
			[0.0, Vector3(0, 1.2, 4.9), Vector3(0, 1.0, 8), 40.0, "turn_3"],
			[PI, jh + Vector3(0, 0.05, -1.0), jh, 32.0, "face_jared"],
			[PI * 0.5, jh + Vector3(0, 0.05, -1.0), jh, 32.0, "face_jared_side"],
			[PI, gh + Vector3(0, 0.05, -0.95), gh, 32.0, "face_goth"],
			[PI * 0.5, gh + Vector3(0, 0.05, -0.95), gh, 32.0, "face_goth_side"]]
		step = 1
		t = 10.0
		return false
	var k := (step - 1) / 2
	if k >= shots.size():
		return true
	var s: Array = shots[k]
	if step % 2 == 1:
		_pose(float(s[0]))
		_look(s[1], s[2], float(s[3]))
		t = 10.0
		step += 1
	elif t > 10.4:
		_shot(String(s[4]))
		step += 1
	return false
