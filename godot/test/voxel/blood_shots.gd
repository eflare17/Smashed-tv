extends SceneTree
## Screenshots of Ultra Gore (under a display, Forward+: -- --out=dir [--gore=n]): blood_stump0-5 (an arm torn off, the
## stumps spurting, a frame every 0.12 s through a heartbeat), blood_pools (a minute's shooting later: the pools on the floor, some drying), blood_wall (shot
## through against the north wall: the spatter on it), blood_screen (first person, a grunt shot right in your face:
## blood on your view). Prints the blood's stats. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var cam: Camera3D
var g: VoxelBody
var step2 := 0

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name, " ", arena.blood.stats, " pools ", arena.blood.pool_count(), " wounds ", arena.blood.wounds.size())

func _body(at: Vector3, yaw: float) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
	b.position = at
	b.yaw = yaw
	b.hp = 1e9
	arena.bodies.append(b)
	return b

func _look(from: Vector3, at: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 55.0
		arena.add_child(cam)
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	arena._hud_layer.visible = false
	cam.current = true
	cam.global_position = from
	cam.look_at(at)

func _clear() -> void:
	for x in arena.bodies:
		x.queue_free()
	arena.bodies.clear()

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	match step:
		0:
			for x in OS.get_cmdline_user_args():
				if x.begins_with("--gore="):
					VoxelBlood.level = int(x.trim_prefix("--gore="))
			arena.frozen = true
			arena.godmode = true
			VoxelBody.immortal = true
			arena.waves.queue.clear()
			_clear()
			arena.player.global_position = Vector3(0, 0, 8)
			g = _body(Vector3(0, 0, -2.0), 0.4)
			var r: Dictionary = g.sever("forearm_l")
			arena.pieces.spawn(g, r.pieces, Vector3(1.5, 1.0, 1.0), Vector3(1, 2, 0))
			var r2: Dictionary = g.sever("head")
			arena.pieces.spawn(g, r2.pieces, Vector3(-1.0, 2.5, 0.5), Vector3(2, 0, 1))
			_look(Vector3(1.6, 1.5, 0.6), Vector3(0, 1.0, -2.0))
			t = 10.0
			step = 1
		1:
			if t > 11.1 + 0.12 * (step2 + 1):
				_shot("blood_stump%d" % step2)
				step2 += 1
				if step2 == 6:
					step = 2
		2:
			# a row of grunts shot to bits, then a while for it to pool and part dry
			for i in 4:
				var b := _body(Vector3(-3.0 + i * 2.0, 0, -6.0), 0.0)
				var eye := Vector3(b.position.x, 1.3, -1.0)
				for k in 10:
					var aim := b.position + Vector3(randf_range(-0.3, 0.3), randf_range(0.5, 1.6), 0)
					arena.fire(eye, (aim - eye).normalized(), 1, 0.0, 2.6)
				var rr: Dictionary = b.sever(["arm_r", "shin_l", "head", "forearm_r"][i])
				arena.pieces.spawn(b, rr.pieces, Vector3(randf_range(-2, 2), 1.5, randf_range(-2, 2)), Vector3(1, 1, 1))
			t = 20.0
			step = 3
		3:
			if t > 28.0:
				_look(Vector3(1.0, 2.2, -1.5), Vector3(-0.5, 0.0, -5.5))
				step = 4
		4:
			if t > 28.3:
				_shot("blood_pools")
				step = 5
		5:
			# shot through against the north wall
			var w := _body(Vector3(-6.0, 0, -20.4), 0.0)
			var eye := Vector3(-6.0, 1.3, -15.0)
			for k in 14:
				var aim := w.position + Vector3(randf_range(-0.25, 0.25), randf_range(0.7, 1.6), 0)
				arena.fire(eye, (aim - eye).normalized(), 1, 0.0, 2.6)
			t = 40.0
			step = 6
		6:
			if t > 42.0:
				w_hide()
				_look(Vector3(-5.0, 1.4, -18.8), Vector3(-6.0, 1.1, -21.5))
				step = 7
		7:
			if t > 42.3:
				_shot("blood_wall")
				step = 8
		8:
			# first person: a grunt right in your face, shot
			cam.current = false
			arena.cam.current = true
			arena._hud_layer.visible = true
			arena.player.global_position = Vector3(6.0, 0, 4.0)
			arena.look_yaw = 0.0
			arena.look_pitch = 0.0
			var f := _body(Vector3(6.0, 0, 2.9), PI)
			t = 50.0
			step = 9
		9:
			if t > 50.3:
				var eye: Vector3 = arena.cam.global_position
				for k in 3:
					arena.fire(eye, (Vector3(6.0, 1.45, 2.9) - eye).normalized(), 1, 0.0, 2.6)
				step = 10
		10:
			if t > 50.9:
				_shot("blood_screen")
				step = 11
		11:
			return true
	return false

# the wall grunt out of the way, to see the wall
func w_hide() -> void:
	for b in arena.bodies:
		if b.position.z < -19.0:
			b.visible = false
