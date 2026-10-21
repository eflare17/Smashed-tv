extends SceneTree
## Screenshots of Stage 2 (not headless: run under a display, e.g. xvfb-run): the chests and cabinet against the wall,
## a chest open with the inventory screen over it, the cabinet open, the backpack alone with a stack in the hand and a
## tooltip. -- --out=dir (default user://). Owned by the voxel session.

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

func _place(p: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = p
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	match step:
		0:
			arena.frozen = true
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			arena.inv.from_data([["meat", 4210], ["bone", 820], ["brain", 133], ["blocks", 2604], ["charred", 77], [], ["meat", 9999]])
			arena.stash.by_id["chest_a"].inv.from_data([["bone", 9999], [], ["brain", 512], ["meat", 300]])
			_place(Vector3(0, 0, -15.5), 0.0, -0.18)
			mark = t
			step = 1
		1:
			if t - mark > 0.6:
				_shot("inv_wall")
				_place(arena.stash.by_id["chest_a"].front() + Vector3(0, 0, 1.0), 0.0, -0.4)
				mark = t
				step = 2
		2:
			if t - mark > 0.3 and step == 2:
				arena._storage_step(0.0)
				arena.open_inventory(arena.stash.by_id["chest_a"])
				step = 3
				mark = t
		3:
			if t - mark > 0.8:
				arena.inv_ui._mouse = arena.inv_ui._slot_rect(arena.inv_ui._panels[0], 2).get_center()
				arena.inv_ui.queue_redraw()
				_shot("inv_chest_open")
				mark = t
				step = 30
		30:
			if t - mark > 0.3:
				arena.close_inventory()
				_place(arena.stash.by_id["cabinet_a"].front() + Vector3(0.6, 0, 1.6), 0.25, -0.15)
				mark = t
				step = 4
		4:
			if t - mark > 0.3 and step == 4:
				arena.stash.by_id["cabinet_a"].open_here = true
				step = 5
				mark = t
		5:
			if t - mark > 0.8 and step == 5:
				_shot("inv_cabinet_open")
				mark = t
				step = 50
		50:
			if t - mark > 0.3:
				arena.stash.by_id["cabinet_a"].open_here = false
				arena.open_inventory(null)
				arena.inv_ui._layout()
				arena.inv_ui.click(0, 1, MOUSE_BUTTON_RIGHT)
				arena.inv_ui._mouse = arena.inv_ui._slot_rect(arena.inv_ui._panels[0], 9).get_center() + Vector2(8, 6)
				arena.inv_ui.queue_redraw()
				mark = t
				step = 6
		6:
			if t - mark > 0.3:
				_shot("inv_backpack")
				mark = t
				step = 7
		7:
			if t - mark > 0.5:
				return true
	return false
