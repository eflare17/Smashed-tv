extends SceneTree
## Screenshots of Stage 3 (not headless: under a display, e.g. xvfb-run): the doorway from the arena, the room from
## the door, the beds and their chests, the padlock up close, the mirror, lying in bed, the room from above.
## -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var out := "user://"
const SHOTS := [
	# [name, player position, yaw, pitch, what to do first]
	["bed_doorway", Vector3(-2.2, 0, 17.5), PI, -0.05, ""],
	["bed_room", Vector3(-2.2, 0, 23.0), PI * 0.82, -0.25, ""],
	["bed_beds", Vector3(-0.4, 0, 28.6), PI * 0.08 + PI * 0.95 + PI, -0.3, ""],
	["bed_mirror", Vector3(-1.4, 0, 27.4), PI, -0.12, ""],
	["bed_padlock", Vector3(1.15, 0, 26.2), 0.0, -0.4, "lock"],
	["bed_lying", Vector3.ZERO, 0.0, 0.0, "lie"],
	["bed_topdown", Vector3(0.0, 0, 26.0), 0.0, 0.0, "top"],
]

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
	if t < 1.5:
		return false
	if step == 0:
		arena.frozen = true
		arena.inv.from_data([["meat", 120]])
		step = 1
		mark = t
		_setup_shot(0)
		return false
	var k := (step - 1) / 2
	if k >= SHOTS.size():
		return t - mark > 0.5
	if (step - 1) % 2 == 0:
		if t - mark > 0.9:
			_shot(SHOTS[k][0])
			mark = t
			step += 1
	else:
		if t - mark > 0.3:
			_undo(k)
			if k + 1 < SHOTS.size():
				_setup_shot(k + 1)
			mark = t
			step += 1
	return false

func _setup_shot(k: int) -> void:
	var s: Array = SHOTS[k]
	var what: String = s[4]
	if what == "lie":
		arena.lie_down(2)
		arena.look_pitch = 0.1
		return
	if what == "top":
		arena.top_down = true
	arena.player.global_position = s[1]
	arena.player.reset_physics_interpolation()
	arena.look_yaw = s[2]
	arena.look_pitch = s[3]
	if what == "lock":
		arena.open_lock(arena.stash.by_id["bed_chest_2"], false)
		arena.lock_view.model.set_code("4271")

func _undo(k: int) -> void:
	var what: String = SHOTS[k][4]
	if what == "lock":
		arena.close_lock()
	elif what == "lie":
		arena.get_up()
	elif what == "top":
		arena.top_down = false
