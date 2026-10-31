extends SceneTree
## A clip (with --write-movie): the Carousel sabotaged (VoxelCarouselHack). The gadget held up to the control box,
## its signals tried one by one (faster, the lights, the brake: found out as you go); the ride stopped, a horse's bolt
## loosened (E held); then flat out, the loose horse rattling, and stopped dead: thrown over on its pole. Owned by the
## St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var hack: VoxelCarouselHack
var label: Label
var cam: Camera3D
var t := 0.0
var step := 0
var horse := -1
var tries: Array = []
var next := 0.0

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

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _tap(k: Key) -> void:
	_key(k, true)
	_key(k, false)

func _put(p: Vector3, at: Vector3, pitch := -0.1) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = atan2(-(at.x - p.x), -(at.z - p.z))
	arena.look_pitch = pitch

func _horse_at(k: int) -> Vector3:
	for h in hack.spin.horses:
		if int(h[1]) == k:
			return hack.spin.global_transform * (h[2] as Transform3D).origin
	return Vector3.ZERO

func _film(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	cam.current = true

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
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			cam = Camera3D.new()
			cam.fov = 60.0
			arena.add_child(cam)
			arena._switch(func(): arena.loadout.select(arena.loadout.index_of("pick")))
			var b := hack.box.global_position
			var c := hack.carousel.global_position
			_put(b + hack.box.global_transform.basis.z * 1.3 + hack.box.global_transform.basis.x * 0.6 + Vector3(0, 0.05, 0), c.lerp(b, 0.3), -0.05)
			# the order they're tried in: as the buttons come, till the brake's found last
			for k in 4:
				if hack.keys[k] != "brake":
					tries.append(k)
			tries.append(hack.keys.find("brake"))
			step = 1
			t = 0.0
		1:
			label.text = "The Carousel's control box"
			if t > 1.5:
				_tap(KEY_E)
				step = 2
				t = 0.0
				next = 1.0
		2:
			label.text = "Try each signal: what does it do?"
			if t >= next and not tries.is_empty():
				var k: int = tries.pop_front()
				_tap(KEY_1 + k)
				if hack.keys[k] == "faster":
					_tap(KEY_1 + k)
				next += 3.2
			if tries.is_empty() and t > next - 1.2:
				step = 3
				t = 0.0
		3:
			label.text = "Stopped: now for a bolt"
			if t > 1.0:
				_tap(KEY_E)
				horse = hack._empty[0]
				var at := _horse_at(horse)
				var c := hack.carousel.global_position
				var out := Vector3(at.x - c.x, 0, at.z - c.z).normalized()
				_put(Vector3(at.x, 0.72, at.z) + out * 1.0 + out.cross(Vector3.UP) * 0.4, at + Vector3(0, 0.6, 0), -0.25)
				step = 4
				t = 0.0
		4:
			label.text = "Hold E: loosen a horse's bolt"
			if t > 0.6 and step == 4 and not hack._e_down and hack.loose < 0:
				_key(KEY_E, true)
			if hack.loose >= 0:
				_key(KEY_E, false)
				if t > VoxelCarouselHack.LOOSEN + 1.6:
					var b := hack.box.global_position
					_put(b + hack.box.global_transform.basis.z * 1.3 + Vector3(0, 0.05, 0), hack.carousel.global_position, -0.05)
					_tap(KEY_E)
					step = 5
					t = 0.0
		5:
			label.text = "Flat out..."
			if t > 0.3 and t < 0.5:
				for k in 4:
					_tap(KEY_1 + hack.keys.find("faster"))
			# beside the ride, the loose horse coming round
			var c := hack.carousel.global_position
			var b := hack.box.global_position
			var side := (b - c)
			side.y = 0
			side = side.normalized()
			_film(c + side * 11.0 + side.cross(Vector3.UP) * 4.0 + Vector3(0, 2.6, 0), c + Vector3(0, 1.2, 0))
			if t > 7.5:
				# brake when the loose horse is on our side
				var at := _horse_at(hack.loose)
				if (at - c).normalized().dot(side) > 0.6 or t > 11.0:
					hack.send(hack.keys.find("brake"))
					step = 6
					t = 0.0
		6:
			label.text = "...and stopped dead"
			if t > 2.0:
				var at := _horse_at(hack.loose)
				var c := hack.carousel.global_position
				var out := Vector3(at.x - c.x, 0, at.z - c.z).normalized()
				_film(at + out * 2.6 + out.cross(Vector3.UP) * 1.2 + Vector3(0, 1.6, 0), at + Vector3(0, 0.7, 0))
				label.text = "The loose horse, thrown over on its pole"
			if t > 5.5:
				quit()
				return true
	return false
