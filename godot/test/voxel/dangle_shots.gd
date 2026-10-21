extends SceneTree
## Screenshots of Stage 8 (not headless: under a display): a grunt whose elbow's bone has been shot out, the forearm
## swinging from its strip of skin; another's knee, the shin hanging. -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var a: VoxelBody
var b: VoxelBody

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

func _body(at: Vector3, yaw: float) -> VoxelBody:
	var g := VoxelBody.new()
	arena.add_child(g)
	g.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
	g.position = at
	g.yaw = yaw
	g.hp = 1e9
	arena.bodies.append(g)
	return g

func _tunnel(g: VoxelBody, nm: String, r: float, below: int) -> void:
	for k in 3:
		var p: Dictionary = g.parts[nm]
		var s: Vector3i = p.grid.size
		var cells: PackedInt32Array = p.grid.cells
		var aim := g._joint_in(p, int(p.bone)) + Vector3(0, -below - k, 0)
		var best := -1
		var bd := INF
		for i in cells.size():
			if cells[i] == VoxelBody.BONE_V:
				var d := Vector3(i % s.x, (i / s.x) % s.y, i / (s.x * s.y)).distance_to(aim)
				if d < bd:
					bd = d
					best = i
		var w := g._cell_world(nm, best)
		g.carve(w + Vector3(0, 0, 0.3), w - Vector3(0, 0, 0.3), r)
		if g.loose.has(nm):
			return

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if step == 0:
		arena.frozen = true
		for x in arena.bodies:
			x.queue_free()
		arena.bodies.clear()
		a = _body(Vector3(-0.5, 0, -2.0), 0.0)
		b = _body(Vector3(0.9, 0, -2.6), 0.4)
		_tunnel(a, "forearm_l", 0.03, 2)
		_tunnel(b, "shin_r", 0.025, 3)
		for g in [a, b]:
			for nm in g._dangle:
				g._dangle[nm].strain = -99.0          # (kept on for the pictures)
		arena.player.global_position = Vector3(0.2, 0, -0.3)
		arena.player.reset_physics_interpolation()
		arena.look_yaw = 0.0
		arena.look_pitch = -0.25
		step = 1
	elif step == 1 and t > 2.5:
		a.knock = Vector3(3.0, 0, 0)
		b.knock = Vector3(-2.5, 0, 0)
		step = 2
	elif step == 2 and t > 2.72:
		_shot("dangle_swing")
		step = 3
	elif step == 3 and t > 5.0:
		_shot("dangle_hanging")
		step = 4
	elif step == 4 and t > 5.5:
		return true
	return false
