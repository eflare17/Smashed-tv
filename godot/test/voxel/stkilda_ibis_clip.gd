extends SceneTree
## A clip (with --write-movie): the St Kilda game's ibis video (stkilda-godot test/ibis_video.gd) made again here, the
## same beats, timings and camera, with the Carousel behind the action: Maddie (SkPeople.maddie, walked by SkWalker)
## comes up on an ibis (SkIbis) pecking in Luna Park; it squawks and chases her, she walks off with it on her heels,
## then stops, turns and swings the bat; it all slows right down and closes in on its neck as the bat lands, then
## speeds up and backs out as it bounces off like a ball, staggers up and runs off. Your player and the HUD are hidden.
## Bigger than the St Kilda video's, for the owner: right in front of the Carousel (its railing hidden), closer in on the
## neck, a cartoon X-ray flash as the bat lands (the skeleton's neck bending like rubber and springing back), a sharper
## crack, a harder jolt, more feathers and a longer freeze.
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
		SkWalker.hit_stop_len = FREEZE              # (the freeze as the bat lands: longer, slowed down as it is)
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
		# (the owner: closer still than the St Kilda video, 1.3 m off at 40 degrees)
		cam.global_position = _wide.lerp(_neck + _close_side * CLOSE + Vector3(0, 0.08, 0), k)
		cam.fov = lerpf(55.0, CLOSE_FOV, k)
		cam.look_at(look.lerp(_neck, k), Vector3.UP)
		# (a jolt as the bat lands: harder than the St Kilda video's, and the X-ray flash, feathers and crack with it)
		if w._bat_hit and not _shook:
			_shook = true
			_shake = 0.06
			_hit_fx(ib)
		if _shake > 0.0:
			_shake_t += rdt
			cam.global_position += cam.global_basis * Vector3(sin(_shake_t * 71.0), sin(_shake_t * 53.0 + 1.3), 0.0) * _shake
			_shake = maxf(0.0, _shake - rdt * 0.1)
		_xray_step(ib, rdt)

	const CLOSE := 0.75                     # (m off its neck, the close-up)
	const CLOSE_FOV := 34.0

	# ================================================================ the hit, bigger (the owner's picks)
	#
	# A cartoon X-ray flash as the bat lands: a white flash, then a few moments of the screen as an X-ray (dark blue,
	# what's solid glowing) with the ibis's cartoon skeleton showing through it, its neck bones bending like a rubber hose
	# with the bat and springing straight again (the ibis's own bend, BENT: nothing breaks). A sharper crack on top of the
	# whack, more feathers, and a longer freeze.

	const FLASH_T := 0.06                   # real s of white first
	const XRAY_T := 1.2                     # real s of X-ray, all told
	const FREEZE := 0.35                    # real s the hit-stop holds (the St Kilda video: 0.15)
	const MORE_FEATHERS := 6
	var _xray_t := -1.0
	var _xray_layer: CanvasLayer
	var _xray_rect: ColorRect
	var _white: ColorRect
	var _bones: MeshInstance3D
	var _body_mat: Material
	var _ghost: StandardMaterial3D

	func _hit_fx(ib: SkIbis) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		var at := ib.neck_point()
		var away := ib.global_position - walker.global_position
		away.y = 0.0
		SkFeather.burst(ib.get_parent(), at, away.normalized(), MORE_FEATHERS, ib.global_position.y, rng)
		var crack := AudioStreamPlayer.new()
		crack.stream = _crack()
		crack.volume_db = 3.0
		add_child(crack)
		crack.play()
		_xray_t = 0.0

	## The X-ray, on for its moment: the screen's colours turned to an X-ray's, the ibis's flesh a faint ghost and its bones
	## drawn over it.
	func _xray_step(ib: SkIbis, rdt: float) -> void:
		if _xray_t < 0.0:
			return
		if _xray_layer == null:
			_make_xray(ib)
		_xray_t += rdt
		var on := _xray_t < XRAY_T
		_white.visible = _xray_t < FLASH_T
		_xray_rect.visible = on and not _white.visible
		_bones.visible = on
		var body := ib.model.get_node("Skeleton/Body") as MeshInstance3D
		body.material_override = _ghost if on else _body_mat
		if not on:
			_xray_t = -1.0
			_xray_layer.visible = false

	func _make_xray(ib: SkIbis) -> void:
		_xray_layer = CanvasLayer.new()
		_xray_layer.layer = 100
		add_child(_xray_layer)
		_xray_rect = ColorRect.new()
		_xray_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		var sh := Shader.new()
		sh.code = """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float x = pow(1.0 - l, 3.0);
	float lines = 0.94 + 0.06 * sin(SCREEN_UV.y * 720.0);
	COLOR = vec4(mix(vec3(0.01, 0.03, 0.09), vec3(0.8, 0.93, 1.0), x) * lines, 1.0);
}
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		_xray_rect.material = m
		_xray_layer.add_child(_xray_rect)
		_white = ColorRect.new()
		_white.set_anchors_preset(Control.PRESET_FULL_RECT)
		_white.color = Color(1, 1, 1, 0.9)
		_xray_layer.add_child(_white)
		var body := ib.model.get_node("Skeleton/Body") as MeshInstance3D
		_body_mat = body.material_override
		_ghost = StandardMaterial3D.new()
		_ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost.albedo_color = Color(0.55, 0.55, 0.55)
		_bones = _skeleton(ib)

	## The ibis's cartoon skeleton (black: the X-ray turns it bright), skinned to its own bones so it bends as it does:
	## a skull and the long bill, the neck as a string of vertebrae, a spine and ribs in the body, and the legs. Worked
	## out from its model, slice by slice: where the flesh is, and which of its bones that flesh goes with.
	func _skeleton(ib: SkIbis) -> MeshInstance3D:
		var a := SkIbis._model_mesh().surface_get_arrays(0)
		var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var slices := {}                    # [part, slice] -> [sum of positions, count, bone -> weight, min, max]
		for i in pos.size():
			var g := pos[i]
			var p := Vector3(-g.z, -g.x, g.y) / SkIbis.S + Vector3(0, 0, SkIbis.FOOT)     # (back to the model's own units)
			if p.z < 7.2:
				continue
			var key := []
			if p.x > 24.0 and p.z > 80.0:
				key = ["bill", int(p.x / 5.0)]
			elif p.z > 110.0:
				key = ["skull", 0]
			elif p.z > 88.0 and p.x > -10.0:
				key = ["neck", int(p.z / 3.0)]
			elif p.z < 44.0:
				key = ["leg_l" if p.y > 0.0 else "leg_r", int(p.z / 4.0)]
			else:
				key = ["body", int(p.x / 7.0)]
			if not slices.has(key):
				slices[key] = [Vector3.ZERO, 0, {}, g, g]
			var s: Array = slices[key]
			s[0] = (s[0] as Vector3) + g
			s[1] = int(s[1]) + 1
			for j in 4:
				var b := bones[i * 4 + j]
				(s[2] as Dictionary)[b] = float((s[2] as Dictionary).get(b, 0.0)) + wts[i * 4 + j]
			s[3] = (s[3] as Vector3).min(g)
			s[4] = (s[4] as Vector3).max(g)
		# each part as a line through its slices' middles (smoothed), each point with its slice's bone weights
		var parts := {}
		for key in slices:
			if not parts.has(key[0]):
				parts[key[0]] = []
			(parts[key[0]] as Array).append(key)
		var lines := {}                     # part -> [points, weights, half sizes]
		for part in parts:
			var keys: Array = parts[part]
			keys.sort_custom(func(x: Array, y: Array) -> bool: return int(x[1]) < int(y[1]))
			var pts := []
			var ws := []
			var halves := []
			for key in keys:
				var s: Array = slices[key]
				pts.append((s[0] as Vector3) / float(s[1]))
				var w := {}
				var total := 0.0
				for b in (s[2] as Dictionary):
					total += float((s[2] as Dictionary)[b])
				for b in (s[2] as Dictionary):
					w[b] = float((s[2] as Dictionary)[b]) / maxf(0.0001, total)
				ws.append(w)
				halves.append(((s[4] as Vector3) - (s[3] as Vector3)) * 0.5)
			for it in 2:
				var smooth := pts.duplicate()
				for n in range(1, pts.size() - 1):
					smooth[n] = ((pts[n - 1] as Vector3) + (pts[n] as Vector3) * 2.0 + (pts[n + 1] as Vector3)) * 0.25
				pts = smooth
			lines[part] = [pts, ws, halves]
		var blobs := []                     # [centre, size, bone -> weight]
		var skull := lines.get("skull", [[Vector3.ZERO], [{}], [Vector3.ONE * 0.02]]) as Array
		var head: Vector3 = (skull[0] as Array)[0]
		blobs.append([head, ((skull[2] as Array)[0] as Vector3) * 0.5, (skull[1] as Array)[0]])
		for part in lines:
			var l: Array = lines[part]
			var pts: Array = l[0]
			var ws: Array = l[1]
			match part:
				"neck":                     # a string of vertebrae up into the skull
					pts = pts + [head]
					ws = ws + [(skull[1] as Array)[0]]
					_tube(blobs, pts, ws, 0.0045, 0.0095, 0.016)
				"bill":                     # from the skull out along it
					_tube(blobs, [head] + pts, [(skull[1] as Array)[0]] + ws, 0.0045, 0.0, 0.0)
				"leg_l", "leg_r":
					_tube(blobs, pts, ws, 0.005, 0.0085, 0.08)
				"body":                     # the spine along its top, ribs hooped round it
					var halves: Array = l[2]
					var spine := []
					for n in pts.size():
						spine.append((pts[n] as Vector3) + Vector3(0, (halves[n] as Vector3).y * 0.45, 0))
					_tube(blobs, spine, ws, 0.0055, 0.009, 0.02)
					for n in range(1, pts.size() - 1):
						if n % 2 == 0:
							continue
						var h: Vector3 = halves[n]
						var ring := []
						var rws := []
						for r in 25:
							var ang := TAU * r / 24.0
							ring.append((pts[n] as Vector3) + Vector3(cos(ang) * h.x * 0.65, sin(ang) * h.y * 0.6, 0))
							rws.append(ws[n])
						_tube(blobs, ring, rws, 0.0035, 0.0, 0.0)
		# each blob a little ball, skinned with the weights its slice of flesh had
		var ball := SphereMesh.new()
		ball.radial_segments = 8
		ball.rings = 4
		var ba := ball.get_mesh_arrays()
		var bv: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
		var bn: PackedVector3Array = ba[Mesh.ARRAY_NORMAL]
		var bi: PackedInt32Array = ba[Mesh.ARRAY_INDEX]
		var out_v := PackedVector3Array()
		var out_n := PackedVector3Array()
		var out_b := PackedInt32Array()
		var out_w := PackedFloat32Array()
		var out_i := PackedInt32Array()
		for blob in blobs:
			var w := blob[2] as Dictionary
			var order := w.keys()
			order.sort_custom(func(x: int, y: int) -> bool: return float(w[x]) > float(w[y]))
			var top := []
			var sum := 0.0
			for j in 4:
				var b := int(order[j]) if j < order.size() else 0
				var v := float(w[b]) if j < order.size() else 0.0
				top.append([b, v])
				sum += v
			var base := out_v.size()
			for k in bv.size():
				out_v.append((blob[0] as Vector3) + bv[k] * (blob[1] as Vector3) * 2.0)
				out_n.append(bn[k])
				for t in top:
					out_b.append(int(t[0]))
					out_w.append(float(t[1]) / maxf(0.0001, sum))
			for k in bi:
				out_i.append(base + k)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = out_v
		arr[Mesh.ARRAY_NORMAL] = out_n
		arr[Mesh.ARRAY_BONES] = out_b
		arr[Mesh.ARRAY_WEIGHTS] = out_w
		arr[Mesh.ARRAY_INDEX] = out_i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.name = "XrayBones"
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.BLACK
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.render_priority = 10
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ib.skel.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.skin = ib.skel.create_skin_from_rest_transforms()
		print("X-ray skeleton: %d bits of bone" % blobs.size())
		return mi

	## Bone along a line (pts, with each point's bone weights ws): balls of radius `r` packed close so they read as one
	## smooth bone, and every `every` m a bigger bead of radius `bead` (a vertebra, a joint), if any.
	static func _tube(blobs: Array, pts: Array, ws: Array, r: float, bead: float, every: float) -> void:
		var gone := 0.0
		var next_bead := every * 0.5
		for n in range(1, pts.size()):
			var a: Vector3 = pts[n - 1]
			var b: Vector3 = pts[n]
			var wa: Dictionary = ws[n - 1]
			var wb: Dictionary = ws[n]
			var steps := maxi(1, int(ceil(a.distance_to(b) / (r * 1.1))))
			for s in steps:
				var u := float(s) / steps
				var w := {}
				for k in wa:
					w[k] = float(wa[k]) * (1.0 - u)
				for k in wb:
					w[k] = float(w.get(k, 0.0)) + float(wb[k]) * u
				var at := a.lerp(b, u)
				blobs.append([at, Vector3.ONE * r, w])
				gone += a.distance_to(b) / steps
				if bead > 0.0 and gone >= next_bead:
					next_bead += every
					blobs.append([at, Vector3.ONE * bead, w])

	## A bat's crack: sharp and woody, over the thump of the whack.
	static func _crack() -> AudioStreamWAV:
		var rate := 22050
		var n := int(rate * 0.25)
		var bytes := PackedByteArray()
		bytes.resize(n * 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in n:
			var t := float(i) / rate
			var snap := rng.randf_range(-1.0, 1.0) * exp(-t * 70.0)
			var knock := sin(TAU * 1500.0 * t) * exp(-t * 35.0) + 0.6 * sin(TAU * 2350.0 * t) * exp(-t * 50.0)
			var thump := sin(TAU * 70.0 * t) * exp(-t * 14.0)
			var s := 0.55 * snap + 0.35 * knock + 0.5 * thump
			bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = rate
		w.data = bytes
		return w

	var _wide := Vector3.ZERO
	var _neck := Vector3.ZERO
	var _close_side := Vector3.RIGHT
	var _shook := false
	var _shake := 0.0
	var _shake_t := 0.0
