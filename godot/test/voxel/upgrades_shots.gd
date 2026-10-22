extends SceneTree
## A screenshot of the weapon bench (Stage 13; under a display): upgrades_bench (standing at it in the yard, a rack
## looked at, its line at the bottom). -- --out=dir. Owned by the voxel session.

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

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	match step:
		0:
			arena.cash = 75
			arena.set_upgrades({"damage": 1, "clip": 2, "fuel": 0})
			arena.player.global_position = VoxelUpgrades.AT + Vector3(-0.3, 0.05, 1.9)
			arena.look_yaw = 0.0
			arena.look_pitch = -0.32
			t = 10.0
			step = 1
		1:
			if t > 11.5:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/upgrades_bench.png" % out)
				print("SHOT upgrades_bench")
				step = 2
		2:
			return true
	return false
