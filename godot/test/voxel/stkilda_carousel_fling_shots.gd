extends SceneTree
## Pictures of the Carousel's riders flung off in ordinary play (VoxelCarouselHack._fling): the gadget at the control
## box saying it's flat out, the lot of them in the air over the ride, coming down, and lying about the path getting up
## again; and the gadget after a brake from too slow a turn, saying why nobody came off. (--out=dir.)
## Prints PASS or FAIL. Owned by the St Kilda session.

const OUT_R := 15.0             # m out from the ride's middle we watch from
const UP := 1.9                 # ... and how high (held there: _stand_back every frame, so nothing drops you)
const ROUND := 2.3              # how far round (rad)

var arena: VoxelArena
var sk: VoxelStKilda
var hack: VoxelCarouselHack
var t := 0.0
var step := 0
var out := ""
var fails := []

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)

func _shot(name: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/carousel_fling_%s.png" % [out, name])
	print("SHOT ", name)

func _signal(act: String) -> void:
	hack.send(hack.keys.find(act))

func _at_the_box() -> void:
	var b := hack.box.global_position
	var to := hack.carousel.global_position - b
	sk._put(b + hack.box.global_transform.basis.z * 1.2, atan2(-to.x, -to.z), -0.1)
	hack._show(true)

# back from the ride, watching it (the view's own, not the one that goes with the rider thrown at Luna Palace)
func _stand_back() -> void:
	var mid := hack.carousel.global_position
	var at := mid + Vector3(cos(ROUND), UP, sin(ROUND)) * Vector3(OUT_R, 1.0, OUT_R)
	var to := mid + Vector3(0, 3.8, 0) - (at + Vector3(0, 1.7, 0))
	sk._put(at, atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	if hack._cam and hack._cam.current:
		hack._cam.current = false
		arena.cam.current = true

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
			_check(hack != null and hack.spin.riders.seats.size() > 0, "the Carousel, hacked, with riders on it")
			_at_the_box()
			while hack.level < VoxelCarouselHack.SPEEDS.size() - 1:
				_signal("faster")
			step = 1
			t = 0.0
		1:
			if t < 8.0:
				return false
			_check(hack.w > VoxelCarouselHack.THROW_FROM, "wound right up (%.2f rad/s)" % hack.w)
			_shot("box_flat_out")
			step = 2
			t = 0.0
		2:
			if t < 0.4:
				return false
			_signal("brake")
			_check(hack.flung > 1, "the brake threw %d of them off" % hack.flung)
			_stand_back()
			step = 3
			t = 0.0
		3:
			_stand_back()
			if t < 0.28:
				return false
			_shot("in_the_air")
			step = 4
			t = 0.0
		4:
			_stand_back()
			if t < 0.32:
				return false
			_shot("coming_down")
			step = 5
			t = 0.0
		5:
			_stand_back()
			if t < 2.4:
				return false
			_shot("on_the_ground")
			step = 45
			t = 0.0
		45:
			_stand_back()
			if t < 5.0:
				return false
			_check(hack.tumbles.any(func(c): return (c as VoxelCarouselTumble).stage in ["dizzy", "walk"]), "they get up and walk it off")
			_shot("walking_off")
			step = 50
			t = 0.0
		50:
			_stand_back()
			if t < 0.3:                 # (let the shot be taken before anything moves: _shot waits for the frame)
				return false
			# and the box after a brake from too slow a turn: why nobody came off
			sk.home()
			sk.go()
			_at_the_box()
			while hack.level < 2:
				_signal("faster")
			step = 6
			t = 0.0
		6:
			if t < 4.0:
				return false
			_signal("brake")
			_check(hack.flung == 0, "braked from slow: nobody came off")
			step = 7
			t = 0.0
		7:
			if t < 0.3:
				return false
			_shot("box_too_slow")
			step = 8
			t = 0.0
		8:
			if t < 0.3:
				return false
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
			return true
	return false
