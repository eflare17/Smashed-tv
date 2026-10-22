extends SceneTree
## Screenshots of the enemy variety (Stage 11; under a display, not headless): kinds_lineup (the charger, the thrower,
## the shield brute from the front), kinds_moves (the charger crouched to run, the thrower's arm back, the shield brute
## side-on), kinds_shield (his shield shot up). -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var cam: Camera3D
var sh: VoxelBody

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

func _body(key: String, at: Vector3, yaw: float) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup(key, arena._cube_m(key), 1, arena._mat)
	b.position = at
	b.yaw = yaw
	arena.bodies.append(b)
	return b

func _look(from: Vector3, at: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 50.0
		arena.add_child(cam)
		arena._hud_layer.visible = false
		arena.net_menu.visible = false
		arena.settings_menu.visible = false
	cam.current = true
	cam.global_position = from
	cam.look_at(at)
	arena.player.global_position = Vector3(0, 0, 12)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	match step:
		0:
			arena.frozen = true
			VoxelBody.immortal = true
			for x in arena.bodies:
				x.queue_free()
			arena.bodies.clear()
			_body("charger", Vector3(-1.6, 0, 0), 0.0)
			_body("thrower", Vector3(0, 0, 0), 0.0)
			sh = _body("shielder", Vector3(1.8, 0, 0), 0.0)
			_look(Vector3(0, 1.5, 5.2), Vector3(0, 1.0, 0))
			step = 1
			t = 10.0
		1:
			if t > 11.0:
				_shot("kinds_lineup")
				step = 2
		2:
			for x in arena.bodies:
				x.queue_free()
			arena.bodies.clear()
			var c := _body("charger", Vector3(-1.8, 0, 0), 0.6)
			c.act = VoxelBody.ACT_WINDUP
			c.act_p = 1.0
			var th := _body("thrower", Vector3(0, 0, 0), 0.3)
			th.act = VoxelBody.ACT_AIM
			th.act_p = 1.0
			sh = _body("shielder", Vector3(2.0, 0, 0), PI / 2.0)
			_look(Vector3(0.3, 1.6, 5.5), Vector3(0.2, 1.0, 0))
			step = 3
			t = 20.0
		3:
			if t > 21.0:
				_shot("kinds_moves")
				step = 4
		4:
			sh.yaw = 0.0
			sh.animate(0.016, false)
			var eye := Vector3(sh.position.x, 1.4, 6)
			for i in 12:
				var aim := sh.position + Vector3(randf_range(-0.5, 0.8), randf_range(0.6, 1.8), 0)
				arena.fire(eye, (aim - eye).normalized(), 1, 0.0, 1.9)
			_look(sh.position + Vector3(-0.8, 1.6, 3.2), sh.position + Vector3(0, 1.1, 0))
			step = 5
			t = 30.0
		5:
			if t > 31.5:
				_shot("kinds_shield")
				step = 6
		6:
			return true
	return false
