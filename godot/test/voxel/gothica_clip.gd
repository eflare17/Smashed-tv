extends SceneTree
## A clip of Gothica moving, for the movie maker (under a display: godot --write-movie out.avi --fixed-fps 30
## -s res://test/voxel/gothica_clip.gd -- --nosave): she hops, runs across, pulls up, turns about, runs at you and
## hops again, then walks off; the camera close on her the while. Owned by the voxel session.

var arena: Node
var t := 0.0
var cam: Camera3D
var g: VoxelGothica
var beats := []
var b := 0
var end := 20.0

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--secs="):
			end = float(x.trim_prefix("--secs="))

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if g == null:
		g = arena.gothica
		arena.frozen = true
		arena.waves.queue.clear()
		for x in arena.bodies:
			x.queue_free()
		arena.bodies.clear()
		arena._hud_layer.visible = false
		arena.player.global_position = Vector3(10, 0, 14)
		g.idle_t = 1e9
		g.path.clear()
		g.body.global_position = Vector3(0, 0, 4.0)
		g.face = PI
		g.body.yaw = PI
		cam = Camera3D.new()
		cam.fov = 42.0
		arena.add_child(cam)
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		cam.current = true
		t = 0.0
		# [when, what]
		beats = [[0.6, "hop"], [1.8, "run", Vector3(-4.5, 0, 4.0)], [3.6, "run", Vector3(4.5, 0, 4.0)], [6.4, "face", PI],
			[7.2, "hop"], [8.4, "run", Vector3(0, 0, 2.2)], [10.0, "face", PI * 0.5], [10.6, "face", -PI * 0.5],
			[11.2, "face", PI], [11.8, "hop"], [13.2, "walk", Vector3(-2.5, 0, 5.0)], [15.6, "walk", Vector3(1.5, 0, 3.0)]]
		return false
	while b < beats.size() and t >= float(beats[b][0]):
		var e: Array = beats[b]
		match String(e[1]):
			"hop":
				g.hop_t = 0.0
			"run", "walk":
				g.goal = e[2]
				g.goal_run = e[1] == "run"
			"face":
				g.face = float(e[2])
		b += 1
	# the camera: a little ahead of her, at chest height, following
	var p := g.body.global_position
	var want := Vector3(p.x * 0.7, 1.3, p.z - 2.1)
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-dt * 3.0)) if t > 0.1 else want
	cam.look_at(Vector3(p.x, 1.08, p.z))
	if "--log" in OS.get_cmdline_user_args():
		var l: Dictionary = g.jig.sides[0]
		var r: Dictionary = g.jig.sides[1]
		var R: Vector3 = VoxelJiggle.LEVELS[VoxelJiggle.level][5]
		var e := VoxelJiggle._ease(l.p, Vector3(R.y, R.x, R.z))
		print("J %.3f %.2f %.4f %.4f %.4f %.4f %.4f" % [t, g.speed, e.x, e.y, e.z, l.p.y / R.x, l.p.x / R.y])
	return t > end
