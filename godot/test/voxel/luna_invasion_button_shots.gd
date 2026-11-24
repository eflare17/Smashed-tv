extends SceneTree
## Pictures of the invasion's start button and the Carousel's brake flinging its enemies (under a display):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot --resolution 1280x720 --fixed-fps 60 -s res://test/voxel/luna_invasion_button_shots.gd
## into integration/voxel_shots/luna_invasion_button.png (as you walk in through Mr Moon's mouth, by day),
## luna_invasion_button_close.png, luna_invasion_button_night.png and luna_invasion_fling.png (just after the brake,
## from a camera of the test's own). Owned by the St Kilda session.

const OUT := "res://integration/voxel_shots/luna_invasion_%s.png"

var arena: VoxelArena
var sk: VoxelStKilda
var f := 0
var step := 0
var busy := false
var cam: Camera3D

func _initialize() -> void:
	seed(20261124)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _save(name: String) -> void:
	busy = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT % name))
	print("SHOT ", name)
	busy = false

func _look(p: Vector3, at: Vector3) -> void:
	var to := at - (p + Vector3(0, 1.6, 0))
	sk._put(Vector3(p.x, 0.05, p.z), atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))

func _next() -> void:
	step += 1
	f = 0

func _process(_dt: float) -> bool:
	f += 1
	if busy:
		return false
	match step:
		0:
			if f < 60:
				return false
			arena.waves.queue.clear()
			arena.godmode = true
			sk = arena.stkilda
			sk.go()
			var face: Transform3D = sk.global_transform * SkLunaPark.xf(sk.town)
			_look(face * Vector3(-0.4, 0, -3.0), sk.button.global_position + Vector3(0, 1.5, 0) + face.basis * Vector3(-1.2, 0, 0))
			_next()
		1:
			if f == 40:
				_save("button")
				_next()
		2:
			if f == 1:
				_look(sk.button.global_transform * Vector3(0.3, 0, 2.3), sk.button.global_position + Vector3(0, 1.75, 0))
			if f == 30:
				_save("button_close")
				_next()
		3:
			if f == 1:
				sk.day_night.toggle()
				var face: Transform3D = sk.global_transform * SkLunaPark.xf(sk.town)
				_look(face * Vector3(-0.4, 0, -3.5), sk.button.global_position + Vector3(0, 1.5, 0) + face.basis * Vector3(-1.2, 0, 0))
				sk.button.press()
			if f == 200:
				_save("button_night")
				_next()
		4:
			if f == 1:
				sk.button.call_off()
				sk.day_night.toggle()
				sk.invasion.seed_ = 7
				sk.invasion.start()
				var mid := sk.hack.spin.global_position
				var home: Vector3 = sk.arrive_spot()[0]
				var d := Vector3(home.x - mid.x, 0, home.z - mid.z).normalized()
				_look(mid + d * 24.0, mid)
				cam = Camera3D.new()
				cam.fov = 60.0
				cam.near = 0.1
				cam.far = 1500.0
				cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
				root.add_child(cam)
				cam.global_position = mid + d * 17.0 + d.cross(Vector3.UP) * 6.0 + Vector3(0, 3.2, 0)
				cam.look_at(mid + Vector3(0, 3.0, 0), Vector3.UP)
				cam.current = true
				arena._use_label.text = ""
			if f == 160:
				sk.hack.level = 4
				sk.hack.w = 3.4
			if f == 200:
				sk.hack.send(sk.hack.keys.find("brake"))
				cam.current = true
			if f == 200 + int(get_meta("after", 34)):
				_save("fling")
				_next()
		5:
			if f == 5:
				quit(0)
	return false
