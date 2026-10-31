extends SceneTree
## A clip (with --write-movie): the St Kilda game's ibis video (stkilda-godot test/ibis_video.gd) made again here, the
## same beats, timings and camera, with the Carousel behind the action: Maddie (SkPeople.maddie, walked by SkWalker)
## comes up on an ibis (SkIbis) pecking in Luna Park; it squawks and chases her, she walks off with it on her heels,
## then stops, turns and swings the bat; it all slows right down and closes in on its neck as the bat lands, then
## speeds up and backs out as it bounces off like a ball, staggers up and runs off. Your player and the HUD are hidden.
## It prints "ACTION_AT <seconds>" (when the filming starts) so the loading can be cut off.
##
##   godot --path . --resolution 1280x720 --write-movie ibis.avi --fixed-fps 30 -s test/voxel/stkilda_ibis_clip.gd
## Owned by the St Kilda session.

func _initialize() -> void:
	var arena: VoxelArena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)
	var film := Film.new()
	film.arena = arena
	root.add_child(film)

class Film extends Node:
	var arena: VoxelArena
	var sk: VoxelStKilda
	var walker: SkWalker
	var follow: SkFollowCam
	var maddie: Node3D
	var cam: Camera3D
	var _mid := Vector3.ZERO
	var _side := Vector3.ZERO

	func _ready() -> void:
		_run()

	func _run() -> void:
		await get_tree().create_timer(2.0).timeout
		arena.godmode = true
		arena.waves.queue.clear()
		sk = arena.stkilda
		sk.go()
		var crowd := sk.get_node("SkCrowd") as SkCrowd
		while not crowd.ready_:
			await get_tree().physics_frame
		await get_tree().create_timer(0.5).timeout
		sk.sun.shadow_enabled = true
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(n as CanvasLayer).visible = false
		# a clear straight stretch right by the Carousel, going round it, so from the camera's side (away from it) it's
		# behind them: she starts at `at`, the ibis pecks ahead along `dir`
		_no_fence(sk.hack.carousel)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var c := sk.hack.carousel.global_position
		var ground: float = (sk.arrive_spot()[0] as Vector3).y
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var at := Vector3.INF
		var dir := Vector3.ZERO
		var space := sk.get_world_3d().direct_space_state
		# (the park's lamp posts and the benches beside them: only the posts are solid, so found by their posts)
		var lamps := []
		for n in sk.find_children("*", "CollisionShape3D", true, false):
			var cs := n as CollisionShape3D
			if cs.shape is BoxShape3D and (cs.shape as BoxShape3D).size.is_equal_approx(Vector3(0.3, 3.0, 0.3)):
				var base := cs.position - Vector3(0, 1.5, 0)
				var xf := (cs.get_parent() as Node3D).global_transform
				lamps.append(xf * base)
				lamps.append(xf * (base + Vector3(0.9, 0, 0)))
		for k in 800:
			var a := rng.randf() * TAU
			var out := Vector3(sin(a), 0, cos(a))                 # (from the Carousel out)
			var d := out.cross(Vector3.UP).normalized()          # (round it: then the camera's side, d x up, is out)
			if d.cross(Vector3.UP).dot(out) < 0.0:
				d = -d
			# (the owner: right in front of it, so inside its fence, on the walk round between the ride and the fence)
			var mid := Vector3(c.x, ground, c.z) + out * rng.randf_range(IN_FROM, IN_TO)
			var p := mid - d * 2.0                               # (the action's middle is a couple of m on from her start)
			var clear := true
			for s in [-7.5, -5.0, -2.5, 0.0, 2.5, 5.0, 7.5]:
				if not crowd._open(mid + d * s):
					clear = false
			for off in [Vector3.ZERO, d.cross(Vector3.UP) * 0.4, -d.cross(Vector3.UP) * 0.4]:
				var q := PhysicsRayQueryParameters3D.create(mid - d * 7.5 + off + Vector3(0, 0.5, 0), mid + d * 7.5 + off + Vector3(0, 0.5, 0), SkData.LAYER_WORLD)
				if not space.intersect_ray(q).is_empty():
					clear = false
			# (and no bench or lamp post on the camera's side, out past the fence, where it swings along with them)
			for l in lamps:
				var rel: Vector3 = l - p
				var along_ := rel.dot(d)
				var back_ := rel.dot(out)
				if along_ > -3.0 and along_ < 8.0 and back_ > 1.0 and back_ < 9.0:
					clear = false
			if clear:
				at = p
				dir = d
				break
		print("SPOT ", at, " dir ", dir, " carousel ", c, " (%.1f m out)" % Vector2(at.x + dir.x * 2.0 - c.x, at.z + dir.z * 2.0 - c.z).length())
		if at == Vector3.INF:
			get_tree().quit(1)
			return
		# your player out of the way, behind the camera, and hidden
		arena.player.global_position = at + dir * 2.0 + dir.cross(Vector3.UP) * 25.0 + Vector3(0, 0.3, 0)
		arena.player.visible = false
		# Maddie, and the walker that walks her (it steers by the follow camera's yaw: that camera's never shown)
		walker = SkWalker.new()
		walker.name = "Walker"
		sk.add_child(walker)
		follow = SkFollowCam.new()
		follow.name = "FollowCam"
		sk.add_child(follow)
		follow.exclude(walker)
		follow.active = false
		walker.cam = follow
		maddie = SkPeople.maddie()
		sk.add_child(maddie)
		maddie.global_position = at + Vector3(0, 0.3, 0)
		walker.take(maddie)
		# the ibis, pecking away, minding its own business
		var ib := SkIbis.new(1)
		ib.crowd = crowd
		sk.add_child(ib)
		ib.player = null
		ib.global_position = at + dir * 9.0 + Vector3(0, 0.3, 0)
		ib.velocity = Vector3.ZERO
		ib.state = SkIbis.PECK
		ib._pecks = 99
		ib._t = 0.0
		ib.model.rotation.y = atan2(dir.x, dir.z) + 0.6
		walker.global_position = at + Vector3(0, 0.3, 0)
		walker.velocity = Vector3.ZERO
		walker.reset_physics_interpolation()
		maddie.rotation.y = atan2(-dir.x, -dir.z)
		follow.yaw = atan2(-dir.x, -dir.z)
		# the camera: side-on, keeping the two of them in shot
		_side = dir.cross(Vector3.UP).normalized()
		cam = Camera3D.new()
		cam.fov = 55.0
		cam.near = 0.1
		cam.far = 3000.0
		sk.add_child(cam)
		_mid = at + dir * 4.5
		_place_cam(walker, ib, 1.0)
		cam.current = true
		await get_tree().create_timer(0.8).timeout
		print("ACTION_AT %.3f" % (Engine.get_process_frames() / 30.0))
		# 1. she walks up towards it, pecking away
		await _walk(walker, ib, dir, 1.5)
		# 2. it sees her: up comes its head, a squawk, and it comes for her
		ib.player = walker
		ib.keep_off = 1.1                    # (it stops a step off her, so the close-up isn't behind her legs)
		ib._pecks = 0
		ib._t = 1.0
		Input.action_release("move_up")
		await _wait(walker, ib, 0.5)
		# 3. she walks off, it on her heels
		follow.yaw = atan2(dir.x, dir.z)
		await _walk(walker, ib, -dir, 3.2)
		Input.action_release("move_up")
		# 4. she stops and turns round to it, and as it comes in, the bat
		var turned := 0.0
		while true:
			var dt := get_process_delta_time()
			var to := ib.global_position - walker.global_position
			to.y = 0.0
			maddie.rotation.y = lerp_angle(maddie.rotation.y, atan2(-to.x, -to.z), minf(1.0, dt * 10.0))
			turned += dt
			_place_cam(walker, ib, dt)
			if to.length() < 2.1 and turned > 0.35:
				break
			if turned > 4.0:
				break
			await get_tree().process_frame
		SkWalker.hit_stop_len = 0.15                # (the freeze as the bat lands: longer, slowed down as it is)
		walker.swing()
		# 5. just as the bat starts down it all slows right down and the camera closes in on its neck
		while walker._bat_t >= 0.0 and walker._bat_t < 0.3 * SkWalker.BAT_TIME:
			_place_cam(walker, ib, get_process_delta_time())
			await get_tree().process_frame
		# (the close-up from side-on to the line between her and it, so neither's in the way of the other)
		var md := ib.global_position - walker.global_position
		md.y = 0.0
		md = md.normalized()
		_close_side = md.cross(Vector3.UP)
		if _close_side.dot(_side) < 0.0:
			_close_side = -_close_side
		_close_side = (_close_side + md * 0.25).normalized()
		Engine.time_scale = SLOW
		var flying := 0.0
		var waited := 0.0
		while flying < 0.07 and waited < 0.6:
			var dt := get_process_delta_time()
			waited += dt
			if ib.state == SkIbis.TUMBLE:
				flying += dt
			_close = move_toward(_close, 1.0, _real(dt) * 3.0)
			_place_cam(walker, ib, dt)
			await get_tree().process_frame
		print("HIT ", walker._bat_hit, " state ", ib.state)
		# up to speed again and back out, as it goes flying
		var s := 0.0
		while s < 1.2:
			var dt := get_process_delta_time()
			s += _real(dt)
			Engine.time_scale = lerpf(SLOW, 1.0, smoothstep(0.0, 1.2, s))
			_close = 1.0 - smoothstep(0.0, 1.0, s)
			_place_cam(walker, ib, dt)
			await get_tree().process_frame
		Engine.time_scale = 1.0
		_close = 0.0
		# 6. it bounces off, staggers up and runs off
		await _wait(walker, ib, 4.2)
		get_tree().quit()

	## The Carousel without its iron fence (the owner, for this video): its railing hidden and the fence's solid lengths
	## gone. (Only in the video: the game keeps it.)
	func _no_fence(carousel: Node3D) -> void:
		(carousel.get_node("Fence") as Node3D).visible = false
		for bar in carousel.get_children():
			var b := bar.get_child(0) if bar.get_child_count() > 0 else null
			if b is StaticBody3D:
				var cs := b.get_child(0) as CollisionShape3D
				if cs and cs.shape is BoxShape3D and is_equal_approx((cs.shape as BoxShape3D).size.y, 1.2):
					bar.queue_free()

	const SLOW := 0.1
	const IN_FROM := 9.6                    # (how far out from the Carousel's middle the action is: right in front of it)
	const IN_TO := 10.6
	var _close := 0.0                       # (0 the wide shot .. 1 right in on its neck)

	## A step's time as it went by for the viewer (the game's slowed down, the video isn't).
	func _real(dt: float) -> float:
		return dt / maxf(0.01, Engine.time_scale)

	func _walk(w: SkWalker, ib: SkIbis, d: Vector3, secs: float) -> void:
		follow.yaw = atan2(-d.x, -d.z)
		Input.action_press("move_up")
		await _wait(w, ib, secs)

	func _wait(w: SkWalker, ib: SkIbis, secs: float) -> void:
		var t := 0.0
		while t < secs:
			var dt := get_process_delta_time()
			t += dt
			_place_cam(w, ib, dt)
			await get_tree().process_frame

	## Side-on, back far enough to have both of them in, moving smoothly.
	func _place_cam(w: SkWalker, ib: SkIbis, dt: float) -> void:
		var a := w.global_position
		var b := ib.global_position
		if a.distance_to(b) > 12.0:
			b = a + (b - a).normalized() * 12.0
		var after := ib.state in [SkIbis.TUMBLE, SkIbis.DAZED, SkIbis.RUN_OFF]
		var want := a.lerp(b, 0.62 if after else 0.5)          # (once it's hit, more on the ibis)
		_mid = _mid.lerp(want, minf(1.0, dt * 3.0))
		var back := clampf(a.distance_to(b) * 0.55 + 2.6, 3.0, 8.0)
		var from := _mid + _side * back + Vector3(0, 1.0, 0)
		var look := _mid + Vector3(0, 0.55, 0)
		if cam.global_position == Vector3.ZERO:
			cam.global_position = from
		var rdt := _real(dt)
		_wide = _wide.lerp(from, minf(1.0, rdt * 3.0)) if _wide != Vector3.ZERO else from
		# (right in on its neck, from the side, the bat coming in)
		var neck := ib.neck_point()
		_neck = _neck.lerp(neck, minf(1.0, rdt * 8.0)) if _neck != Vector3.ZERO else neck
		var k := smoothstep(0.0, 1.0, _close)
		cam.global_position = _wide.lerp(_neck + _close_side * 1.3 + Vector3(0, 0.15, 0), k)
		cam.fov = lerpf(55.0, 40.0, k)
		cam.look_at(look.lerp(_neck, k), Vector3.UP)
		# (a jolt as the bat lands)
		if w._bat_hit and not _shook:
			_shook = true
			_shake = 0.035
		if _shake > 0.0:
			_shake_t += rdt
			cam.global_position += cam.global_basis * Vector3(sin(_shake_t * 71.0), sin(_shake_t * 53.0 + 1.3), 0.0) * _shake
			_shake = maxf(0.0, _shake - rdt * 0.08)

	var _wide := Vector3.ZERO
	var _neck := Vector3.ZERO
	var _close_side := Vector3.RIGHT
	var _shook := false
	var _shake := 0.0
	var _shake_t := 0.0
