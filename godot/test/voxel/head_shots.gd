extends SceneTree
## Head shots of a sculpted character (under a display, Forward+: -- --out=dir [--model=jared_new] [--y=1.62]): the
## head close (or with --dist=4 --y=1 the whole body) from the front, three-quarters, the side, three-quarters behind, the back (head_0..4). Owned by the
## voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var cam: Camera3D
var b: VoxelBody
var model := "jared_new"
var hy := 1.62
var yaws := [0.0, -PI * 0.25, -PI * 0.5, -PI * 0.75, PI]
var base := 0.0
var dist := 1.25

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
		if x.begins_with("--model="):
			model = x.trim_prefix("--model=")
		if x.begins_with("--y="):
			hy = float(x.trim_prefix("--y="))
		if x.begins_with("--dist="):
			dist = float(x.trim_prefix("--dist="))
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
	if step == 0:
		arena.settings_menu.s.set_preset("high")
		arena.settings_menu.s.apply(arena)
		if "--no-ssao" in OS.get_cmdline_user_args():
			arena.world_env.ssao_enabled = false
		arena.frozen = true
		arena.waves.queue.clear()
		for x in arena.bodies:
			x.queue_free()
		arena.bodies.clear()
		arena.player.global_position = Vector3(10, 0, 14)
		arena.gothica.visible = false
		arena.gothica.set_process(false)
		arena._hud_layer.visible = false
		var t0 := Time.get_ticks_msec()
		b = VoxelBody.new()
		arena.add_child(b)
		b.setup(model, 0.0125, 1, arena._mat)
		print("BUILT ", model, " in ", Time.get_ticks_msec() - t0, " ms")
		b.position = Vector3(0, 0, 8)
		cam = Camera3D.new()
		arena.add_child(cam)
		cam.current = true
		cam.fov = 30.0
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		# lit from the front (the sun behind the camera), as he's mostly seen
		var bz: Vector3 = arena.sun.global_transform.basis.z
		var fw := Vector3(bz.x, 0, bz.z).normalized()
		base = atan2(fw.x, fw.z)
		cam.global_position = Vector3(0, hy + 0.05 * dist / 1.25, 8) + fw * dist
		cam.look_at(Vector3(0, hy, 8))
		step = 1
		t = 10.0
		return false
	var k := (step - 1) / 2
	if k >= yaws.size():
		return true
	if step % 2 == 1:
		b.yaw = base + float(yaws[k])
		b.animate(0.016, false)
		t = 10.0
		step += 1
	elif t > 10.3:
		_shot("head_%d" % k)
		step += 1
	return false
