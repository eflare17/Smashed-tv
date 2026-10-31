extends SceneTree
## A clip (with --write-movie): just the Carousel's big moment, no how-to: the ride going round flat out, stopped dead
## (VoxelCarouselHack's brake), a rider flung off all the way to Luna Palace, smacking into the wall above a window,
## sliding down it, caught by a foot on the sill, hanging there, then dropping head first into the wheelie bin below
## (VoxelCarouselTumble), the game's own view following them. Your player and the HUD are hidden.
##
##   godot --path . --resolution 1280x720 --write-movie bin.avi --fixed-fps 30 -s test/voxel/stkilda_carousel_bin_clip.gd
## It prints "ACTION_AT <seconds>" (when the filming starts) so the loading can be cut off. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var hack: VoxelCarouselHack
var cam: Camera3D
var t := 0.0
var step := 0
var around := 0.0

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

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
			# you, out of the way and out of sight; a bolt already loose, and the ride sped up flat out
			var b := hack.box.global_position
			arena.player.global_position = b + hack.box.global_transform.basis.z * 30.0
			arena.player.visible = false
			hack.loose = hack._empty[0]
			for k in 4:
				hack.send(hack.keys.find("faster"))
			step = 1
			t = 0.0
		1:
			for n in root.find_children("*", "CanvasLayer", true, false):
				(n as CanvasLayer).visible = false
			_film(dt)
			if t > 2.0:
				print("ACTION_AT %.3f" % (Engine.get_process_frames() / 30.0))
				step = 2
				t = 0.0
		2:
			# the ride flat out, the camera drifting slowly round it
			_film(dt)
			if t > 6.0 and hack.w > 3.2:
				hack.send(hack.keys.find("brake"))
				step = 3
				t = 0.0
		3:
			# stopped dead: the game's view goes with the one thrown off, all the way into the bin
			if not hack._cam or not hack._cam.current:
				_film(dt)
			var tb: VoxelCarouselTumble = hack.tumbles[0] if not hack.tumbles.is_empty() else null
			# (once the view's at the castle, the crowd's gone: one of them stood right in front of it, by the bin)
			if tb != null and tb.stage not in ["flying"]:
				(sk.get_node("SkCrowd/People") as Node3D).visible = false
			if (tb != null and tb.stage == "binned" and tb._t > 2.6) or t > 30.0:
				print("ENDED ", tb.stage if tb else "-", " at %.1f s" % t)
				quit()
				return true
	return false

## Side-on to the Carousel from the control box's side, a bit up, drifting round it.
func _film(dt: float) -> void:
	around += dt * 0.06
	var c := hack.carousel.global_position
	var side := hack.box.global_position - c
	side.y = 0.0
	side = side.normalized().rotated(Vector3.UP, -0.5 + around)
	cam.global_position = c + side * 14.0 + Vector3(0, 3.2, 0)
	cam.look_at(c + Vector3(0, 1.6, 0), Vector3.UP)
	cam.current = true
