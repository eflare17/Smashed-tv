extends SceneTree
## A clip (with --write-movie) of an invasion round at Luna Park, about 48 seconds, starring Maddie (SkPeople.maddie,
## walked by SkWalker, as the ibis clip does) with your own player and the HUD hidden. The beats, in order:
##   1. she walks up to the INVASION button by Mr Moon's mouth and sets it going -- siren, lamp
##   2. two ibises have a go at her on the way in, and get the bat
##   3. she walks to the Carousel's control box, which the invasion now leaves her room to use (VoxelParkInvasion.GRACE)
##   4. the gadget up, the ride wound right up to flat out, its riders holding on
##   5. the brake: every rider thrown off, and the one heading at Luna Palace sails across the park, hits above the
##      window, slides down, hangs by a foot, drops head first into the wheelie bin -- and the lid comes down on him
## It prints "ACTION_AT <seconds>" when the filming starts, so the loading can be cut off the front.
##
##   godot --path . --resolution 1280x720 --write-movie invasion.avi --fixed-fps 30 -s test/voxel/stkilda_invasion_clip.gd
## With --stills=<dir> it takes a picture at each beat instead, for checking the framing without a whole render.
## Owned by the St Kilda session.

func _initialize() -> void:
	var arena: VoxelArena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)
	var film := Film.new()
	film.arena = arena
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--stills="):
			film.stills = x.trim_prefix("--stills=")
	root.add_child(film)

class Film extends Node:
	var arena: VoxelArena
	var sk: VoxelStKilda
	var inv: VoxelParkInvasion
	var hack: VoxelCarouselHack
	var walker: SkWalker
	var follow: SkFollowCam
	var maddie: Node3D
	var crowd: SkCrowd
	var cam: Camera3D                 # the clip's own camera, all the way through (SkFollowCam is never shown: it only
	                                  # tells the walker which way "forward" is, and with no target it sits at the world
	                                  # origin, which is the bedroom, 3 km from the park)
	var on_her := true                # the camera is keeping her in shot (off for the ride beats, placed by hand)
	var tight := false                # close in behind her shoulder, looking past her at `aim` (the button)
	var aim := Vector3.ZERO
	var stills := ""
	var shot_n := 0

	func _ready() -> void:
		_run()

	# ---------------------------------------------------------------- the little helpers

	func _shot(name: String) -> void:
		if stills == "":
			return
		shot_n += 1
		get_tree().root.get_texture().get_image().save_png("%s/clip_%d_%s.png" % [stills, shot_n, name])
		print("SHOT ", name)

	func _wait(secs: float) -> void:
		var t := 0.0
		while t < secs:
			var dt := get_process_delta_time()
			t += dt
			_place(dt)
			await get_tree().process_frame

	## Over her shoulder and a little to the side, easing along so it doesn't snap about.
	func _place(dt: float) -> void:
		if not on_her or walker == null:
			return
		var her := walker.global_position + Vector3(0, 1.2, 0)
		var back := Vector3(sin(follow.yaw), 0, cos(follow.yaw))        # (the way she's walking)
		var want := her + back * 5.4 + back.cross(Vector3.UP) * 2.0 + Vector3(0, 2.6, 0)
		if tight:
			# right in behind her: the park's entrance is a thicket of signs, booths and coaster legs with no collision
			# on any of it, so anything further back ends up inside something. Close in, she fills the shot and the
			# clutter is just the park behind her.
			want = her + back * 2.6 + back.cross(Vector3.UP) * 1.35 + Vector3(0, 0.95, 0)   # (off her shoulder enough
			                                                                                # that she isn't over the sign)
			cam.global_position = cam.global_position.lerp(want, clampf(dt * 4.0, 0.0, 1.0)) if cam.global_position.distance_to(want) < 40.0 else want
			cam.look_at(aim if aim != Vector3.ZERO else her, Vector3.UP)
			return
		want = _clear(her, want)
		var k := clampf(dt * 3.5, 0.0, 1.0)
		cam.global_position = cam.global_position.lerp(want, k) if cam.global_position.distance_to(want) < 40.0 else want
		cam.look_at(her, Vector3.UP)

	## `want` pulled in to this side of anything between it and `from`, so the camera never ends up inside the park's
	## scenery looking at the back of a sign (what the first cut of this clip did at Mr Moon's mouth).
	func _clear(from: Vector3, want: Vector3) -> Vector3:
		var space := sk.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(from, want, SkData.LAYER_WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return want
		var d := from.distance_to(hit.position)
		return from + (want - from).normalized() * maxf(1.2, d - 0.45)

	## Walk her `secs` seconds along `d` (the walker goes where the follow cam looks).
	func _walk(d: Vector3, secs: float) -> void:
		follow.yaw = atan2(-d.x, -d.z)
		Input.action_press("move_up")
		await _wait(secs)
		Input.action_release("move_up")

	## Walk her at `to` until she is within `near` m of it (or `most` seconds go by).
	func _walk_to(to: Vector3, near: float, most: float) -> void:
		var t := 0.0
		Input.action_press("move_up")
		while t < most:
			var d := to - walker.global_position
			d.y = 0.0
			if d.length() < near:
				break
			follow.yaw = atan2(-d.x, -d.z)
			var dt := get_process_delta_time()
			t += dt
			_place(dt)
			await get_tree().process_frame
		Input.action_release("move_up")

	## My own camera, at `at`, looking at `to`.
	func _look(at: Vector3, to: Vector3) -> void:
		cam.global_position = at
		cam.look_at(to, Vector3.UP)

	## An ibis pecking at `at`, which then comes for her.
	func _ibis(at: Vector3, facing: Vector3) -> SkIbis:
		var ib := SkIbis.new(1)
		ib.crowd = crowd
		sk.add_child(ib)
		ib.player = null
		ib.global_position = at + Vector3(0, 0.3, 0)
		ib.velocity = Vector3.ZERO
		ib.state = SkIbis.PECK
		ib._pecks = 99
		ib._t = 0.0
		ib.model.rotation.y = atan2(facing.x, facing.z) + 0.6
		return ib

	## It notices her and comes in; she turns, waits for it and swings.
	func _whack(ib: SkIbis) -> void:
		ib.player = walker
		ib.keep_off = 1.1
		ib._pecks = 0
		ib._t = 1.0
		var turned := 0.0
		while turned < 4.0:
			var dt := get_process_delta_time()
			var to := ib.global_position - walker.global_position
			to.y = 0.0
			maddie.rotation.y = lerp_angle(maddie.rotation.y, atan2(-to.x, -to.z), minf(1.0, dt * 10.0))
			turned += dt
			_place(dt)
			if to.length() < 2.1 and turned > 0.35:
				break
			await get_tree().process_frame
		walker.swing()
		await _wait(0.9)

	# ---------------------------------------------------------------- the clip

	func _run() -> void:
		await get_tree().create_timer(2.0).timeout
		arena.godmode = true
		arena.waves.queue.clear()
		sk = arena.stkilda
		sk.go()
		crowd = sk.get_node("SkCrowd") as SkCrowd
		while not crowd.ready_:
			await get_tree().physics_frame
		await get_tree().create_timer(0.5).timeout
		sk.sun.shadow_enabled = true
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(n as CanvasLayer).visible = false
		inv = sk.invasion
		hack = sk.hack
		await get_tree().physics_frame

		# her, the camera that follows her, and a camera of my own for the ride
		walker = SkWalker.new()
		walker.name = "Walker"
		sk.add_child(walker)
		follow = SkFollowCam.new()
		follow.name = "FollowCam"
		sk.add_child(follow)
		follow.exclude(walker)
		walker.cam = follow
		maddie = SkPeople.maddie()
		sk.add_child(maddie)
		walker.take(maddie)
		cam = Camera3D.new()
		cam.name = "ClipCam"
		cam.fov = 62.0
		sk.add_child(cam)

		var btn = sk.button
		var bat := btn.button_at() as Vector3
		var into := (hack.carousel.global_position - bat)
		into.y = 0.0
		into = into.normalized()
		# She starts on the PARK side of the button, a few steps off it, facing back at it. Walking in from outside
		# took her through Mr Moon's mouth and left her jammed against the entrance wall, because the button sits hard
		# against it and none of the entrance scenery has collision to stop her. `into` points at the Carousel, i.e.
		# into the open park, so everything on this side is clear ground.
		var start := bat + into * 3.2
		walker.global_position = Vector3(start.x, 0.3, start.z)
		walker.velocity = Vector3.ZERO
		walker.reset_physics_interpolation()
		maddie.rotation.y = atan2(-into.x, -into.z)        # (facing back at the button)
		follow.yaw = atan2(into.x, into.z)
		follow.active = false          # (never shown: see the note on `cam`)
		cam.current = true
		arena.player.visible = false
		on_her = true
		_place(1.0)
		await get_tree().physics_frame
		print("ACTION_AT %.2f" % (Time.get_ticks_msec() / 1000.0))

		# 1. up to the button, and on it goes. Hand-placed, from inside the park looking back at the button with Mr
		# Moon's face behind her: the entrance's signs and panels are scenery with no collision at all (the same reason
		# you can walk through the Carousel), so _clear's ray goes straight through them and an over-the-shoulder
		# camera ends up behind a sign looking at the back of it.
		on_her = true
		tight = true
		aim = bat + Vector3(0, 1.2, 0)
		_place(1.0)
		await _walk_to(bat, 2.0, 4.0)      # (a couple of steps to it, not a march through the entrance)
		_shot("at_the_button")
		await _wait(0.4)
		inv.start()
		btn.presses += 1
		await _wait(2.2)
		_shot("invasion_on")

		# 2. two ibises on the way in, out on the open grass where the wider over-the-shoulder works
		on_her = true
		tight = false
		aim = Vector3.ZERO
		var ib1 := _ibis(walker.global_position + into * 9.0 + into.cross(Vector3.UP) * 1.5, -into)
		await _walk(into, 2.6)             # (turning away from the button and off into the park)
		await _whack(ib1)
		_shot("ibis_one")
		var ib2 := _ibis(walker.global_position + into * 6.0 - into.cross(Vector3.UP) * 2.0, -into)
		await _wait(0.5)
		await _whack(ib2)
		_shot("ibis_two")
		await _wait(0.8)

		# 3. on to the Carousel's control box (the player goes with her: the gadget is his to hold up)
		var box: Vector3 = hack.box.global_position
		await _walk_to(box, 2.0, 12.0)
		sk._put(box + (box - hack.carousel.global_position).normalized() * 1.2, 0.0, 0.0)
		arena.player.visible = false
		await _wait(0.6)
		_shot("at_the_box")

		# 4. the gadget up and the ride wound right up
		on_her = false
		var mid: Vector3 = hack.spin.global_position
		var side := (walker.global_position - mid)
		side.y = 0.0
		side = side.normalized()
		_look(mid + side * 11.0 + Vector3(0, 3.4, 0), mid + Vector3(0, 2.2, 0))
		hack._show(true)
		for k in 4:
			hack.send(hack.keys.find("faster"))
			await _wait(0.5)
		var spun := 0.0
		while hack.w < 3.35 and spun < 14.0:
			spun += get_process_delta_time()
			await get_tree().process_frame
		_shot("flat_out")
		await _wait(1.0)

		# 5. the brake: they all go, and one goes all the way over
		hack.send(hack.keys.find("brake"))
		await _wait(0.5)
		_shot("the_brake")
		var tb: VoxelCarouselTumble = hack.tumbles[hack.tumbles.size() - 1] if not hack.tumbles.is_empty() else null
		# across the park with him, from the side, then round to the window as he comes in
		# square on to the arc, far enough back to hold the whole of it, on whichever side of the park is open --
		# the first cut watched from 9 m beside him and spent the shot looking at Luna Palace's wall
		var line := (tb.hang_at - mid) if tb != null else Vector3.FORWARD
		line.y = 0.0
		var half := mid + line * 0.5
		var out := line.normalized().cross(Vector3.UP)
		var space := sk.get_world_3d().direct_space_state
		for way in [1.0, -1.0]:
			var sgn := float(way)
			var try_at := half + out * sgn * 17.0 + Vector3(0, 7.0, 0)
			var q := PhysicsRayQueryParameters3D.create(half + Vector3(0, 3.0, 0), try_at, SkData.LAYER_WORLD)
			if space.intersect_ray(q).is_empty():
				out = out * sgn
				break
		var watched := 0.0
		while tb != null and is_instance_valid(tb) and watched < 3.2 and tb.stage == "flying":
			var dt := get_process_delta_time()
			watched += dt
			_look(half + out * 17.0 + Vector3(0, 7.0, 0), tb.mid_now)
			await get_tree().process_frame
		_shot("across_the_park")
		# the window: in close for the slide and the hang
		if tb != null and is_instance_valid(tb):
			var sill: Vector3 = tb.hang_at
			var outw: Vector3 = tb.hang_out
			_look(sill + outw * 5.0 + outw.cross(Vector3.UP) * 2.2 + Vector3(0, 0.6, 0), sill + Vector3(0, -0.3, 0))
			await _wait(2.0)
			_shot("hanging")
			await _wait(3.4)
			# down into the bin, and the lid
			var bin: Node3D = hack.bin
			if bin:
				var bo := bin.global_transform.basis.z.normalized()
				_look(bin.global_position + bo * 2.6 + bin.global_transform.basis.x.normalized() * 1.5 + Vector3(0, 1.6, 0),
					bin.global_position + Vector3(0, 0.9, 0))
			await _wait(3.5)
			_shot("in_the_bin")
			await _wait(2.0)
			_shot("the_lid")
		await _wait(1.0)
		print("CLIP: done")
		get_tree().quit(0)
