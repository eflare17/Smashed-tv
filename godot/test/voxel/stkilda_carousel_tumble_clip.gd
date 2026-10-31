extends SceneTree
## A clip (with --write-movie): the Carousel flat out and stopped dead with the gadget; a rider goes flying off all the
## way into Luna Palace's wall (the game's view following them), lies there a moment, gets up dizzy (stars round
## their head) and walks off (VoxelCarouselTumble).
## Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var hack: VoxelCarouselHack
var label: Label
var cam: Camera3D
var t := 0.0
var step := 0
var look := Vector3.ZERO
var eye := Vector3.ZERO

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)
	var cl := CanvasLayer.new()
	cl.layer = 100
	root.add_child(cl)
	label = Label.new()
	label.position = Vector2(80, 70)
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	cl.add_child(label)

func _film(from: Vector3, at: Vector3, dt: float, k := 3.0) -> void:
	eye = eye.lerp(from, minf(1.0, dt * k)) if eye != Vector3.ZERO else from
	look = look.lerp(at, minf(1.0, dt * k)) if look != Vector3.ZERO else at
	cam.global_position = eye
	cam.look_at(look, Vector3.UP)
	cam.current = true

# where the thrown one is now: the ragdoll's body, or them
func _them() -> Vector3:
	var tb: VoxelCarouselTumble = hack.tumbles[0]
	if tb._rag != null and is_instance_valid(tb._rag):
		var b := tb._rag._parts.get("body") as RigidBody3D
		if b:
			return b.global_position
	return tb.at + Vector3(0, 0.9, 0)

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0 and step == 0:
		return false
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			sk = arena.stkilda
			sk.go()
			hack = sk.hack
			cam = Camera3D.new()
			cam.fov = 60.0
			arena.add_child(cam)
			var b := hack.box.global_position
			arena.player.global_position = b + hack.box.global_transform.basis.z * 30.0     # (out of the way)
			for k in 4:
				hack.send(hack.keys.find("faster"))
			step = 1
			t = 0.0
		1:
			label.text = "The Carousel, flat out..."
			var c := hack.carousel.global_position
			var side := (hack.box.global_position - c)
			side.y = 0
			side = side.normalized()
			_film(c + side * 13.0 + side.cross(Vector3.UP) * 5.0 + Vector3(0, 3.0, 0), c + Vector3(0, 1.2, 0), dt)
			if t > 7.0:
				hack.send(hack.keys.find("brake"))
				step = 2
				t = 0.0
		2:
			if hack.tumbles.is_empty():
				quit()
				return true
			label.text = "...stopped dead"
			# (the game's own view goes with them: VoxelCarouselHack's FollowCam)
			var tb: VoxelCarouselTumble = hack.tumbles[0]
			if tb.stage == "up":
				label.text = "Up again..."
			elif tb.stage == "dizzy":
				label.text = "...dizzy..."
			elif tb.stage == "walk":
				label.text = "...and off they go"
			if (tb.stage == "walk" and tb._t > 5.0) or t > 25.0:
				quit()
				return true
	return false
