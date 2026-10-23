extends SceneTree
## A turntable clip for the movie maker (under a display: godot --write-movie out.avi --fixed-fps 30
## -s res://test/voxel/turntable_clip.gd -- --nosave): Jared and Gothica side by side turning all the way round
## (8 s), then each face close, turning (5 s each). Owned by the voxel session.

var arena: Node
var t := 0.0
var cam: Camera3D
var j: VoxelBody
var g: VoxelBody
var jig: VoxelJiggle
var started := false

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	if not started:
		started = true
		arena.settings_menu.s.set_preset("high")
		arena.settings_menu.s.apply(arena)
		arena.frozen = true
		arena.waves.queue.clear()
		for x in arena.bodies:
			x.queue_free()
		arena.bodies.clear()
		arena.player.global_position = Vector3(10, 0, 14)
		arena.gothica.visible = false
		arena.gothica.set_process(false)
		arena._hud_layer.visible = false
		j = VoxelBody.new()
		arena.add_child(j)
		j.setup("jared_hd", 0.0125, 1, arena._mat)
		VoxelJiggle.dress(j)
		g = VoxelBody.new()
		arena.add_child(g)
		g.setup("gothica", 0.0125, 1, arena._mat)
		jig = VoxelJiggle.new()
		jig.setup(g)
		j.position = Vector3(-0.6, 0, 8)
		g.position = Vector3(0.6, 0, 8)
		cam = Camera3D.new()
		arena.add_child(cam)
		cam.current = true
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		t = 0.0
		return false
	var yaw := PI + t * TAU / 8.0
	if t < 8.0:
		cam.fov = 40.0
		cam.global_position = Vector3(0, 1.25, 4.9)
		cam.look_at(Vector3(0, 1.0, 8))
		for b in [j, g]:
			b.yaw = yaw
	elif t < 13.0:
		var k := (t - 8.0) / 5.0
		j.yaw = PI + k * TAU
		cam.fov = 32.0
		cam.global_position = Vector3(-0.6, 1.66, 7.0)
		cam.look_at(Vector3(-0.6, 1.6, 8))
	elif t < 18.0:
		var k2 := (t - 13.0) / 5.0
		g.yaw = PI + k2 * TAU
		cam.fov = 32.0
		cam.global_position = Vector3(0.6, 1.5, 7.05)
		cam.look_at(Vector3(0.6, 1.45, 8))
	else:
		return true
	for b in [j, g]:
		b.animate(dt, false)
	jig.step(dt)
	return false
