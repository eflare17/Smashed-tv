extends SceneTree
## The Carousel's brake in ORDINARY play (no invasion): wound right up and stopped dead, every rider on it goes flying
## and comes down on the ground clear of the ride; stopped from above half speed a few are knocked off and the rest ride
## on; stopped from slow, nobody comes off. Each one leaves the batch it's drawn in at the moment its own tumbling body
## appears, so none is ever drawn in two places. And the control box says how near it is to throwing them off, and what
## the brake just did, so the brake is never a button that does nothing with nothing said.
## (The owner, 24 Nov: "when I speed up the merry go round and stop it the person doesn't go flying now." He wasn't in
## the invasion; luna_invasion_test guards that side of it, and this is the side that was wrong.)
## Pictures (under a display, Forward+: -- --out=dir). Prints PASS or FAIL. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var hack: VoxelCarouselHack
var t := 0.0
var step := 0
var out := ""
var fails := []
var riders := 0                 # the scenery riders on it
var flung: Array = []           # the tumbles made by the brake under test

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

func _signal(act: String) -> void:
	hack.send(hack.keys.find(act))

## Wound up to speed `lv` (the signals are shuffled: send "faster" as often as it takes).
func _wind_to(lv: int) -> void:
	while hack.level < lv:
		_signal("faster")

# at the control box, the gadget up, the ride at its own speed: where every part of this starts
func _at_the_box() -> void:
	var b := hack.box.global_position
	arena.player.global_position = b + hack.box.global_transform.basis.z * 1.2 + Vector3(0, 0.05, 0)
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = atan2(-(hack.carousel.global_position.x - b.x), -(hack.carousel.global_position.z - b.z))
	arena.look_pitch = -0.1
	hack._show(true)

# how many riders are still sat on the ride, and how many are still drawn there (the batch as the eye sees it)
func _on_ride() -> int:
	var n := 0
	for s in hack.spin.riders.seats:
		if ((s as Array)[2] as Transform3D).basis.get_scale().x >= 0.01:
			n += 1
	return n

func _drawn() -> int:
	var buf: PackedFloat32Array = hack.spin.riders._buf
	var n := 0
	for i in hack.spin.riders.seats.size():
		if buf.size() < (i + 1) * 20:
			continue
		if Vector3(buf[i * 20], buf[i * 20 + 4], buf[i * 20 + 8]).length() >= 0.01:
			n += 1
	return n

# of `flung`, how many are in the air with their body still up about the ride (just thrown, not yet down)
func _airborne() -> int:
	var n := 0
	var mid := hack.spin.global_position
	for tb in flung:
		var c := tb as VoxelCarouselTumble
		if c.hang_at != Vector3.INF:
			continue                        # (the one thrown right over at Luna Palace: stkilda_carousel_hack_test)
		var r = c._rag
		if r == null or not is_instance_valid(r):
			continue
		var b := r._parts.get("body") as RigidBody3D
		if b != null and b.global_position.y > 1.0 and Vector2(b.global_position.x - mid.x, b.global_position.z - mid.z).length() < VoxelCarousel.EDGE + 5.0:
			n += 1
	return n

# of `flung` (bar the one at Luna Palace): how many have come to rest, and how many of those lie clear of the ride
func _settled() -> Array:
	var done := 0
	var clear := 0
	var mid := hack.spin.global_position
	for tb in flung:
		var c := tb as VoxelCarouselTumble
		if c.hang_at != Vector3.INF:
			continue
		if c.stage in ["down", "up", "dizzy", "walk", "done"]:
			done += 1
			if Vector2(c.at.x - mid.x, c.at.z - mid.z).length() > VoxelCarousel.EDGE:
				clear += 1
	return [done, clear]

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
			_check(hack != null and hack.spin != null and hack.spin.riders != null, "the Carousel, hacked, with riders on it")
			_check(sk.invasion == null or not sk.invasion.running, "no invasion on: this is ordinary play")
			riders = hack.spin.riders.seats.size()
			_check(riders >= 4, "%d riders on its horses" % riders)
			_at_the_box()
			_wind_to(SPEEDS_TOP)
			step = 1
			t = 0.0
		1:
			# ---------------- wound right up and stopped dead: the lot of them go
			if t < 8.0:
				return false
			_check(hack.w > VoxelCarouselHack.THROW_FROM, "wound right up, flat out (%.2f rad/s)" % hack.w)
			_check(hack.speed_word().contains("FLAT OUT"), "the box says the brake throws every rider off: %s" % hack.speed_word())
			_shot("1_flat_out")
			_signal("brake")
			flung = hack.tumbles.duplicate()
			_check(flung.size() == riders, "the brake: all %d of %d thrown off" % [flung.size(), riders])
			_check(hack.flung == riders, "the box counts them: %s" % hack._note)
			_check(_on_ride() == 0, "nobody left riding it (%d on their seats)" % _on_ride())
			_check(_drawn() == 0, "and not one still drawn on it: each left the batch the moment its body appeared")
			step = 2
			t = 0.0
		2:
			if t < 0.25:
				return false
			_check(_airborne() >= riders - 2, "%d of them in the air over the ride" % _airborne())
			_shot("2_in_the_air")
			step = 3
			t = 0.0
		3:
			if t < 1.1:
				return false
			_shot("3_coming_down")
			step = 4
			t = 0.0
		4:
			var s := _settled()
			if int(s[0]) < riders - 1 and t < 14.0:
				return false
			_check(int(s[0]) == riders - 1, "they came down and lay there (%d of %d; the other's away at Luna Palace)" % [s[0], riders - 1])
			_check(int(s[1]) == int(s[0]), "every one of them on the ground clear of the ride (%d of %d)" % [s[1], s[0]])
			_shot("4_on_the_ground")
			step = 40
			t = 0.0
		40:
			if t < 0.3:                 # (let the shot be taken before anything moves: _shot waits for the frame)
				return false
			sk.home()
			sk.go()
			_check(hack.tumbles.is_empty() and hack.flung == 0 and _on_ride() == riders, "home and back: all %d riding it again" % _on_ride())
			_at_the_box()
			_wind_to(SPEEDS_TOP - 1)
			step = 5
			t = 0.0
		5:
			# ---------------- stopped from above half speed: a few knocked off, the rest ride on
			if t < 5.0:
				return false
			_check(hack.w >= VoxelCarouselHack.KNOCK_FROM and hack.w <= VoxelCarouselHack.THROW_FROM, "wound to half speed (%.2f rad/s)" % hack.w)
			_check(hack.speed_word().contains("KNOCKS A FEW OFF"), "the box says the brake knocks a few off: %s" % hack.speed_word())
			_signal("brake")
			flung = hack.tumbles.duplicate()
			var few := flung.size()
			_check(few > 0 and few < riders, "the brake: %d of %d knocked off" % [few, riders])
			_check(_on_ride() == riders - few and _drawn() == riders - few, "the other %d still riding it, and still drawn on it" % _on_ride())
			_check(hack._note.contains("KNOCKED OFF"), "the box says what the brake did: %s" % hack._note)
			_shot("5_knocked_off")
			step = 6
			t = 0.0
		6:
			var s := _settled()
			if int(s[0]) < flung.size() and t < 12.0:
				return false
			_check(int(s[0]) == flung.size(), "those few came off and lay there (%d of %d)" % [s[0], flung.size()])
			sk.home()
			sk.go()
			_at_the_box()
			_wind_to(SPEEDS_TOP - 2)
			step = 7
			t = 0.0
		7:
			# ---------------- stopped from slow: nobody comes off, and the box says so
			if t < 4.0:
				return false
			_check(hack.w > 0.5 and hack.w < VoxelCarouselHack.KNOCK_FROM, "wound to a slow turn (%.2f rad/s, under %.2f)" % [hack.w, VoxelCarouselHack.KNOCK_FROM])
			_check(hack.speed_word().contains("TOO SLOW"), "the box says it's too slow to throw anyone off: %s" % hack.speed_word())
			_signal("brake")
			_check(hack.tumbles.is_empty() and hack.flung == 0, "the brake: nobody comes off (%d)" % hack.tumbles.size())
			_check(_on_ride() == riders and _drawn() == riders, "all %d still riding it" % _on_ride())
			_check(hack._note.contains("TOO SLOW"), "and the box says why, not nothing: %s" % hack._note)
			_shot("6_too_slow")
			print("PASS" if fails.is_empty() else "FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
			return true
	return false

const SPEEDS_TOP := 4           # (VoxelCarouselHack.SPEEDS' top notch)
