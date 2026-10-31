extends SceneTree
## The Carousel sabotaged (VoxelCarouselHack): E at the control box holds the gadget up; its signals (shuffled) speed
## the ride up, slow it, stop it dead and turn its lights off and on; with it stopped, E held by an empty horse loosens
## its bolt; sped up and stopped dead, that horse is thrown over crooked on its pole, and a rider flies into a window
## of Luna Palace, caught on its sill by a foot, hanging upside down, the view going with them. Home and back, all as
## it was.
## Pictures (under a display, Forward+: -- --out=dir). Prints PASS or FAIL. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var hack: VoxelCarouselHack
var t := 0.0
var step := 0
var out := ""
var fails := []
var horse := -1

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _put(p: Vector3, look_at: Vector3) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = atan2(-(look_at.x - p.x), -(look_at.z - p.z))
	arena.look_pitch = -0.15

func _signal(act: String) -> void:
	hack.send(hack.keys.find(act))

func _horse_at(k: int) -> Vector3:
	for h in hack.spin.horses:
		if int(h[1]) == k:
			return hack.spin.global_transform * (h[2] as Transform3D).origin
	return Vector3.ZERO

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
			_check(hack != null and hack.box != null, "the control box is by the Carousel")
			var b := hack.box.global_position
			_put(b + hack.box.global_transform.basis.z * 1.2 + Vector3(0, 0.05, 0), hack.carousel.global_position)
			step = 1
			t = 0.0
		1:
			if t < 0.4:
				return false
			_key(KEY_E, true)
			_key(KEY_E, false)
			step = 2
			t = 0.0
		2:
			if t < 0.2:
				return false
			_check(hack._open, "E at the box holds the gadget up")
			_check(hack.seen.count(true) == 0, "no signal known yet")
			_shot("1_gadget")
			_signal("faster")
			_signal("faster")
			_check(hack.level == 3, "faster, twice: speed 3")
			step = 3
			t = 0.0
		3:
			if t < 4.0:
				return false
			_check(hack.w > 1.5, "it's turning faster (%.2f rad/s)" % hack.w)
			_shot("2_fast")
			_signal("lights")
			var bulbs := hack.carousel.find_child("Bulbs", true, false) as Node3D
			_check(bulbs != null and not bulbs.visible, "its lights off")
			_signal("lights")
			_check(bulbs.visible, "and on again")
			_signal("brake")
			step = 4
			t = 0.0
		4:
			if t < 0.4:
				return false
			_check(hack.w == 0.0, "the brake stops it dead")
			_signal("slower")
			_check(hack.seen.count(true) == 4, "all four signals worked out: %s" % str(hack.keys))
			# to a horse nobody's on, E held
			horse = hack._empty[0]
			var at := _horse_at(horse)
			var c := hack.carousel.global_position
			var from_mid := Vector3(at.x - c.x, 0, at.z - c.z).normalized()
			_put(Vector3(at.x, 0.7, at.z) + from_mid * 1.0, at)
			_key(KEY_E, true)
			_key(KEY_E, false)          # (that closes the gadget)
			step = 5
			t = 0.0
		5:
			if t < 0.5:
				return false
			_check(not hack._open, "E again puts the gadget away")
			_key(KEY_E, true)
			step = 6
			t = 0.0
		6:
			if t < VoxelCarouselHack.LOOSEN + 0.5:
				return false
			_key(KEY_E, false)
			_check(hack.loose == horse, "holding E by it loosens its bolt (loose: %d, horse %d)" % [hack.loose, horse])
			# sped right up and stopped dead
			for k in 4:
				_signal("faster")
			step = 7
			t = 0.0
		7:
			if t < 7.0:
				return false
			_check(hack.w > 3.0, "flat out (%.2f rad/s)" % hack.w)
			_shot("3_flat_out")
			_signal("brake")
			step = 8
			t = 0.0
		8:
			if t < 0.6:
				return false
			_check(hack.w == 0.0 and hack.thrown > 0.0, "stopped dead: the loose horse thrown over on its pole")
			_check(hack.tumbles.size() == 1, "and a rider thrown off")
			_shot("4_thrown")
			step = 9
			t = 0.0
		9:
			var tb: VoxelCarouselTumble = hack.tumbles[0] if not hack.tumbles.is_empty() else null
			if tb == null or (tb.stage != "hang" and t < 15.0) or (tb.stage == "hang" and tb._t < 1.5):
				return false
			_check(tb.hang_at != Vector3.INF, "thrown at a window of Luna Palace")
			# caught on the sill by a foot, upside down
			_check(tb.stage == "hang", "caught on the sill (%s)" % tb.stage)
			_check(hack._cam != null and hack._cam.current, "the view's gone with them")
			var c := hack.carousel.global_position
			_check(Vector2(tb.at.x - c.x, tb.at.z - c.z).length() > 25.0, "all the way over at Luna Palace (%.1f m from the ride)" % Vector2(tb.at.x - c.x, tb.at.z - c.z).length())
			var xf := tb._mm.get_instance_transform(0) if tb._mm.buffer.size() == 0 else Transform3D(Basis(Vector3(tb._mm.buffer[0], tb._mm.buffer[4], tb._mm.buffer[8]), Vector3(tb._mm.buffer[1], tb._mm.buffer[5], tb._mm.buffer[9]), Vector3(tb._mm.buffer[2], tb._mm.buffer[6], tb._mm.buffer[10])), Vector3(tb._mm.buffer[3], tb._mm.buffer[7], tb._mm.buffer[11]))
			_check(xf.basis.y.normalized().y < -0.9, "upside down (up's %.2f)" % xf.basis.y.normalized().y)
			_check(xf.origin.distance_to(tb.hang_at) < 0.3 and absf(tb.hang_at.y - 4.87) < 0.2, "feet on the sill, 4.9 m up (%.2f m)" % tb.hang_at.y)
			_shot("5_hanging")
			step = 11
			t = 0.0
		11:
			if t < 5.5:
				return false
			_check(hack._cam == null or not hack._cam.current, "then the view's back to you")
			_check(hack.tumbles[0].stage == "hang", "still hanging there")
			sk.home()
			sk.go()
			_check(hack.loose == -1 and hack.level == 1 and hack.thrown == 0.0 and hack.seen.count(true) == 0 and hack.tumbles.is_empty(), "home and back: all as it was")
			print("PASS" if fails.is_empty() else "FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
			return true
	return false
