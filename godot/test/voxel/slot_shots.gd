extends SceneTree
## Screenshots of the slot machine (under a display; Forward+ for the chrome): slot_front, slot_reels (the spider down on
## its thread), slot_spin (the lever down, the reels a blur, the spider caught on a drum), slot_flung (it bouncing
## about behind the glass), slot_win, slot_side (the dented, shot, bloodied left side), slot_lever. -- --out=dir.
## Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var out := "user://"
var cam: Camera3D
var m: VoxelSlotMachine
var v_dropped := false

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

func _look(from: Vector3, at: Vector3, fov := 50.0) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		arena.add_child(cam)
	arena._hud_layer.visible = false
	arena.net_menu.visible = false
	arena.settings_menu.visible = false
	arena.waves._layer.visible = false
	cam.fov = fov
	cam.current = true
	cam.global_position = m.global_position + from
	cam.look_at(m.global_position + at)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if m == null:
		m = arena.slot
		arena.frozen = true
		for b in arena.bodies:
			b.queue_free()
		arena.bodies.clear()
		arena.player.global_position = Vector3(0, 0, 0)
		mark = t
	var lt := t - mark
	match step:
		0:
			_look(Vector3(1.1, 1.45, 2.7), Vector3(0, 1.15, 0), 48.0)
			if lt > 1.0:
				_shot("slot_front")
				# the spider let down over the middle reel
				m._sp_state = "hide"
				m._sp_t = 0.0
				mark = t
				step = 1
		1:
			_look(Vector3(0.18, 1.62, 0.62), Vector3(0, 1.53, 0.2), 45.0)
			m._sp_t = maxf(m._sp_t, 1.0) if m._sp_state == "dangle" else m._sp_t
			if m._sp_state == "dangle" and lt > 1.5:
				_shot("slot_reels")
				mark = t
				step = 2
			elif lt > 8.0:
				_shot("slot_reels")
				mark = t
				step = 2
		2:
			# pulled: the spider on the drum
			m.pull()
			m._sp_shake = false
			mark = t
			step = 3
		3:
			_look(Vector3(0.12, 1.6, 0.55), Vector3(0.0, 1.53, 0.2), 45.0)
			if m.spinning and m._sp_state != "ride" and not v_dropped:
				v_dropped = true
				m._sp_reel = 1
				m._sp_drop()
				m._sp_t = 0.9
			if m._sp_state == "ride" and lt > 0.5 and m._sp.visible and cos(m._sp_a - m._reels[1].rotation.x) > 0.6:
				_shot("slot_spin")
				mark = t
				step = 4
			elif lt > 3.0:
				_shot("slot_spin")
				mark = t
				step = 4
		4:
			_look(Vector3(0.12, 1.6, 0.55), Vector3(0.0, 1.53, 0.2), 45.0)
			if m._sp_state == "flung" and m._sp_t < 1.0:
				_shot("slot_flung")
				mark = t
				step = 5
			elif lt > 4.0:
				_shot("slot_flung")
				mark = t
				step = 5
		5:
			if not m.spinning and m._lever_t < 0.0:
				m.pull()
				m._result = [3, 3, 3]
				m._sp_shake = false
				mark = t
				step = 6
		6:
			_look(Vector3(0.0, 1.5, 1.6), Vector3(0, 1.45, 0), 50.0)
			if not m.spinning and lt > 2.5:
				_shot("slot_win")
				mark = t
				step = 7
		7:
			_look(Vector3(-1.7, 1.35, 1.1), Vector3(-0.2, 1.15, 0.0), 45.0)
			if lt > 0.6:
				_shot("slot_side")
				m.pull()
				mark = t
				step = 8
		8:
			_look(Vector3(1.6, 1.5, 1.0), Vector3(0.3, 1.45, 0.0), 45.0)
			if lt > 0.2:
				_shot("slot_lever")
				mark = t
				step = 9
		9:
			return true
	return false
