extends SceneTree
## Screenshots of the waves and the boss (Stage 12; under a display, -- --waves --out=dir): boss_wave (wave 5's
## banner, THE BUTCHER walking in, his bar), boss_slam (his fists up, close), boss_carved (shot up, an arm off).
## Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var boss: VoxelBody
var cam: Camera3D

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
	match step:
		0:
			arena.godmode = true
			arena.wave = 4
			arena.waves.queue.clear()
			for b in arena.bodies:
				b.hurt(1e6)
			step = 1
		1:
			for b in arena.bodies:
				if b.key == "boss":
					boss = b
			if boss:
				boss.position = Vector3(0, 0, -6)
				arena.player.global_position = Vector3(0, 0, 6)
				arena.look_yaw = 0.0
				arena.look_pitch = 0.08
				t = 10.0
				step = 2
		2:
			if t > 10.5:
				_shot("boss_wave")
				step = 3
		3:
			arena.frozen = true
			for b in arena.bodies:
				if b != boss:
					b.queue_free()
			arena.bodies = arena.bodies.filter(func(x): return x == boss)
			arena.waves.queue.clear()
			boss.position = Vector3(0, 0, 0)
			boss.yaw = 0.3
			boss.act = VoxelBody.ACT_SLAM_UP
			boss.act_p = 1.0
			cam = Camera3D.new()
			cam.fov = 60.0
			arena.add_child(cam)
			cam.current = true
			cam.global_position = Vector3(1.5, 1.6, 5.5)
			cam.look_at(Vector3(0, 2.4, 0))
			arena._hud_layer.visible = false
			t = 20.0
			step = 4
		4:
			if t > 21.0:
				_shot("boss_slam")
				step = 5
		5:
			boss.act = 0
			boss.yaw = 0.0
			boss.animate(0.016, false)
			VoxelBody.immortal = true
			var eye := Vector3(0, 2.0, 5.5)
			for i in 40:
				var aim := Vector3(randf_range(-1.2, 1.2), randf_range(0.5, 4.0), 0)
				arena.fire(eye, (aim - eye).normalized(), 1, 0.0, 2.6)
			boss.sever("arm_l")
			cam.global_position = Vector3(-1.2, 2.0, 5.0)
			cam.look_at(Vector3(0, 2.0, 0))
			t = 30.0
			step = 6
		6:
			if t > 31.5:
				_shot("boss_carved")
				step = 7
		7:
			return true
	return false
