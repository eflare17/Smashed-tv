extends SceneTree
## Screenshots of the online menu (not headless: under a display): open, with a copied code in the box; hosting,
## the room code big. -- --out=dir. Owned by the voxel session.

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
	var m: VoxelNetMenu = arena.net_menu
	if step == 0 and t > 1.5:
		arena.frozen = true
		DisplayServer.clipboard_set("yo join me, code K7QD")
		m.open()
		step = 1
	elif step == 1 and t > 2.5:
		_shot("online_menu")
		step = 2
	elif step == 2 and t > 3.0:
		m.close()
		m.host("K7QD")
		step = 3
	elif step == 3 and t > 4.5:
		_shot("online_hosting")
		step = 4
	elif step == 4 and t > 5.0:
		arena.net.leave()
		return true
	return false
