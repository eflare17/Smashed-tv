extends SceneTree
## A clip of the sculpted Jared for the movie maker (under a display: godot --write-movie out.avi --fixed-fps 30
## -s res://test/voxel/jared_clip.gd -- --nosave): turning round (7 s), his head close turning (5 s), then running
## across and back with the camera following (7 s). Owned by the voxel session.

var arena: Node
var t := 0.0
var cam: Camera3D
var j: VoxelBody
var started := false
var fw := Vector3.BACK
var base := 0.0

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
		j.setup("jared_new", 0.0125, 1, arena._mat)
		j.position = Vector3(0, 0, 8)
		var bz: Vector3 = arena.sun.global_transform.basis.z
		fw = Vector3(bz.x, 0, bz.z).normalized()
		base = atan2(fw.x, fw.z)
		cam = Camera3D.new()
		arena.add_child(cam)
		cam.current = true
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		t = 0.0
		return false
	var moving := false
	var side := fw.cross(Vector3.UP)
	if t < 7.0:
		j.yaw = base + t * TAU / 7.0
		cam.fov = 40.0
		cam.global_position = Vector3(0, 1.1, 8) + fw * 2.9
		cam.look_at(Vector3(0, 0.95, 8))
	elif t < 12.0:
		j.yaw = base + (t - 7.0) * TAU / 5.0
		cam.fov = 32.0
		cam.global_position = Vector3(0, 1.66, 8) + fw * 1.35
		cam.look_at(Vector3(0, 1.6, 8))
	elif t < 19.0:
		# running across, turning, running back
		var k := t - 12.0
		var dir := 1.0 if k < 3.5 else -1.0
		var along := (k if k < 3.5 else 7.0 - k) * 1.6 - 2.8
		j.position = Vector3(0, 0, 8) + side * along
		var mv := side * dir
		j.yaw = atan2(mv.x, mv.z)
		moving = true
		j.speed = 4.0
		j.odo += 4.0 * dt
		cam.fov = 40.0
		cam.global_position = Vector3(0, 1.15, 8) + fw * 3.2 + side * along * 0.8
		cam.look_at(j.position + Vector3(0, 0.95, 0))
	else:
		return true
	j.animate(dt, moving)
	return false
