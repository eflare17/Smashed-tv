extends SceneTree
## Screenshots of the barbecue (not headless: under a display, e.g. xvfb-run): it in the back yard, three chickens on
## the grill (just on, half done, roasted) with the burners going and smoke rising, close up, looking at it ("E  take
## off"), one left on till it's burnt, from above. -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
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

func _view(p: Vector3, at: Vector3) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	var to := at - (p + Vector3(0, 1.65, 0))
	arena.look_yaw = atan2(-to.x, -to.z)
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	var bb: VoxelBarbecue = arena.yard.barbecue
	var at := VoxelBarbecue.AT
	match step:
		0:
			arena.frozen = true
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			arena.inv.from_data([["chicken_carcass", 2]])
			bb.grill = [2.0, VoxelBarbecue.COOK_T * 0.55, VoxelBarbecue.COOK_T + 6.0]
			_view(at + Vector3(-2.2, 0, -3.4), at + Vector3(0, 0.8, 0))
			mark = t
			step = 1
		1:
			if t - mark > 2.5:
				_shot("barbecue_yard")
				_view(at + Vector3(-0.35, 0, -1.25), at + Vector3(0, VoxelBarbecue.GRILL_Y, 0))
				mark = t
				step = 2
		2:
			if t - mark > 0.8:
				_shot("barbecue_cooking")
				mark = t
				step = 3
		3:
			if t - mark > 0.3:
				bb.grill = [-1.0, -1.0, VoxelBarbecue.BURN_T + 2.0]
				bb.grill[0] = VoxelBarbecue.COOK_T + 2.0
				mark = t
				step = 4
		4:
			if t - mark > 1.5:
				_shot("barbecue_take_off")
				mark = t
				step = 5
		5:
			if t - mark > 0.3:
				var e := InputEventKey.new()
				e.physical_keycode = KEY_E
				e.pressed = true
				arena._unhandled_input(e)
				mark = t
				step = 6
		6:
			if t - mark > 0.5:
				_shot("barbecue_taken")
				mark = t
				step = 7
		7:
			if t - mark > 0.3:
				bb.grill = [VoxelBarbecue.BURN_T + 5.0, -1.0, -1.0]
				_view(at + Vector3(0.3, 0, -1.1), at + Vector3(-0.2, VoxelBarbecue.GRILL_Y, 0))
				mark = t
				step = 8
		8:
			if t - mark > 2.0:
				_shot("barbecue_burnt")
				mark = t
				step = 11
		11:
			if t - mark > 0.3:
				bb.grill = [5.0, 20.0, 31.0]
				arena.top_down = true
				_view(at + Vector3(0, 0, -1.2), at)
				mark = t
				step = 9
		9:
			if t - mark > 1.5:
				_shot("barbecue_topdown")
				mark = t
				step = 10
		10:
			return t - mark > 0.5
	return false
