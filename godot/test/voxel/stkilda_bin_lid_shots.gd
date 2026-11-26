extends SceneTree
## Pictures of the wheelie bin's lid under Luna Palace's window: hanging open as it waits, part way down, and lying
## shut (VoxelCarouselHack._make_bin, VoxelCarouselTumble._lid_step). The lid's motion is checked in
## stkilda_bin_lid_test.gd; this is for the look of it -- the hinge in the right place, the lid over the opening and
## not through the bin. Owned by the St Kilda session.
##   xvfb-run -a godot --path godot --fixed-fps 60 -s res://test/voxel/stkilda_bin_lid_shots.gd -- --out=<dir>

var arena: VoxelArena
var sk: VoxelStKilda
var hack: VoxelCarouselHack
var t := 0.0
var step := 0
var out := ""

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	if out == "":
		return
	# (no await here: awaiting inside _process turns it into a coroutine and the loop ends after the first shot.
	# Every step waits a few tenths of a second after it changes anything, so a frame has long since been drawn.)
	root.get_texture().get_image().save_png("%s/bin_lid_%s.png" % [out, name])
	print("SHOT ", name)

## The view just in front of the bin, looking at it side-on so the lid's angle reads
func _look_at_bin() -> void:
	var b: Vector3 = hack.bin.global_position
	var side := hack.bin.global_transform.basis.x.normalized()
	var at := b + side * 2.1 + Vector3(0, 1.5, 0)
	var to := b + Vector3(0, 1.0, 0) - at
	sk._put(at, atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))

func _process(dt: float) -> bool:
	t += dt
	match step:
		0:
			if t < 2.0:
				return false
			sk = arena.stkilda
			sk.go()
			step = 1
			t = 0.0
		1:
			if t < 3.0:
				return false
			hack = sk.hack
			hack._palace_wall()
			if hack.bin == null:
				hack._make_bin()          # (it makes its own once you're near: a second would sit inside the first)
			print("bin at ", hack.bin.global_position if hack.bin else "nothing")
			step = 2
			t = 0.0
		2:
			if t < 0.5:
				return false
			_look_at_bin()
			step = 3
			t = 0.0
		3:
			if t < 0.5:
				return false
			_shot("open")
			var lid: Node3D = hack.bin.get_node("Lid")
			lid.rotation.x = (VoxelCarouselHack.LID_OPEN + VoxelCarouselHack.LID_SHUT) * 0.5
			step = 4
			t = 0.0
		4:
			if t < 0.3:
				return false
			_shot("halfway")
			var lid: Node3D = hack.bin.get_node("Lid")
			lid.rotation.x = VoxelCarouselHack.LID_SHUT
			step = 5
			t = 0.0
		5:
			if t < 0.3:
				return false
			_shot("shut")
			print("BIN LID SHOTS: done")
			quit(0)
	return false
