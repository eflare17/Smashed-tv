extends SceneTree
## A clip (with --write-movie): the Carousel sabotaged (VoxelCarouselHack), played through step by step as you would:
## arriving, the gadget held up to the control box, its signals tried one by one (found out as you go), the ride
## stopped and a horse's bolt loosened (E held), then flat out and stopped dead: a rider thrown at Luna Palace, caught
## by a foot on a window sill and left hanging upside down, the game's view following them, and back to you. Owned by the St Kilda session.

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
			# the order they're tried in: as the buttons come, till the brake's found last
			for k in 4:
				if hack.keys[k] != "brake":
					tries.append(k)
			tries.append(hack.keys.find("brake"))
			step = 10
			t = 0.0
		10:
			# where you arrive: Luna Park's forecourt, Mr Moon's face ahead
			label.text = "1. P phone, Travel to St Kilda"
			if t > 3.0:
				var b := hack.box.global_position
				var c := hack.carousel.global_position
				_put(b + hack.box.global_transform.basis.z * 1.3 + hack.box.global_transform.basis.x * 0.6 + Vector3(0, 0.05, 0), c.lerp(b, 0.3), -0.05)
				step = 1
				t = 0.0
		1:
			label.text = "2. In through Mr Moon's mouth to the\n    Carousel's control box (grey cabinet)"
			if t > 3.0:
				_tap(KEY_E)
				step = 2
				t = 0.0
				next = 1.0
		2:
			label.text = "3. E: the gadget\n4. Keys 1-4: try each signal, see what it does"
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
			label.text = "Stopped (brake). Now a bolt (optional):\nE puts the gadget away"
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
			label.text = "Hold E by an empty horse: its bolt's loose"
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
			# back at the box (E: the gadget again), faster up to SPEED 4, waiting for it to get there
			label.text = "5. E at the box again, FASTER till SPEED 4,\n    wait for full speed..."
			if t > 0.6 and t < 0.8:
				for k in 4:
					_tap(KEY_1 + hack.keys.find("faster"))
			if t > 8.0:
				_tap(KEY_1 + hack.keys.find("brake"))
				step = 6
				t = 0.0
		6:
			# the game's own view goes after the one thrown off (VoxelCarouselHack's FollowCam), and comes back
			label.text = "6. BRAKE: stopped dead"
			# swinging the view round him with the mouse as he flies (and a little nearer with the wheel)
			if hack._cam and hack._cam.current and t < 1.6:
				var mm := InputEventMouseMotion.new()
				mm.relative = Vector2(-0.35 if t < 0.8 else 0.35, -0.08 if t < 0.8 else 0.08)
				Input.parse_input_event(mm)
				if t > 0.6 and not has_meta("wheel"):
					set_meta("wheel", true)
					var wb := InputEventMouseButton.new()
					wb.button_index = MOUSE_BUTTON_WHEEL_UP
					wb.pressed = true
					Input.parse_input_event(wb)
			var tb: VoxelCarouselTumble = hack.tumbles[0] if not hack.tumbles.is_empty() else null
			if tb != null:
				match tb.stage:
					"flying":
						label.text = "6. BRAKE: stopped dead... into the castle"
					"splat":
						label.text = "...splat, above the window..."
					"slide":
						label.text = "...sliding down..."
					"hang":
						label.text = "...caught by a foot on a window sill"
					"fall":
						label.text = "...his foot slips..."
					"binned":
						label.text = "...into the bin!"
					"down", "up":
						label.text = "Up again..."
					"dizzy", "walk":
						label.text = "...dizzy, and off they go"
			if arena.cam.current and t > 3.0:
				label.text = "Back to you (he's in the bin)"
				arena.look_pitch = -0.1
				if not has_meta("back"):
					set_meta("back", t)
				if t - float(get_meta("back")) > 3.0:
					quit()
					return true
			if t > 30.0:
				quit()
				return true
	return false
