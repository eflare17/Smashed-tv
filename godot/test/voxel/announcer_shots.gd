extends SceneTree
## Screenshots of the kill announcer (under a display, Forward+: -- --out=dir): a MONSTER KILL with a KILLING SPREE
## under it, and a HEADSHOT. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var busy := false

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	busy = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)
	busy = false

func _kill(at: Vector3) -> void:
	var b: VoxelBody = arena.spawn_kind("grunt", at)
	b.hurt(9999.0)

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 or busy:
		return false
	match step:
		0:
			arena.waves.queue.clear()
			arena.godmode = true
			arena.player.global_position = Vector3(0, 0.05, 8)
			arena.look_yaw = 0.0
			arena.look_pitch = -0.2
			for i in 6:
				_kill(Vector3(-3 + i * 1.2, 0, 2))
			step = 1
		1:
			if t > 2.25:
				_shot("announcer_monster")
				step = 2
		2:
			if t > 6.0:
				var b: VoxelBody = arena.spawn_kind("grunt", Vector3(0, 0, 3))
				b.head_gone = true
				b.hurt(9999.0)
				step = 3
		3:
			if t > 6.25:
				_shot("announcer_headshot")
				step = 4
		4:
			if t > 6.6:
				quit()
				return true
	return false
