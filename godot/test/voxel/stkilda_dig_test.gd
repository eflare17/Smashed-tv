extends SceneTree
## The dirt along Luna Park's wall (VoxelParkDirt) and its bushes (VoxelParkBushes): you stand on the dirt; a trench
## dug down beside the wall and under it, you walk through it from one side of the wall to the other; a bush cut down,
## dragged and let go over the trench while you're down it hides you; standing in a growing bush hides you. Pictures
## (under a display, Forward+: -- --out=dir). Prints PASS or FAIL. Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var t := 0.0
var step := 0
var out := ""
var fails := []
var patch: VoxelParkDirt.Patch
var along := 8.0
var fwd := Vector3.ZERO          # across the wall, world (the patch's +z)
var walking := false            # (pushed along under the wall: a test can't hold W down)

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

# a point on the patch: m along the wall, m across it (+ the patch's +z), y up
func _at(a: float, across: float, y: float) -> Vector3:
	return patch.to_global(Vector3(a, y, across))

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _put(p: Vector3, yaw: float, pitch := 0.0) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

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
			sk.dirt.finish()
			_check(sk.dirt.patches.size() >= 10, "dirt along the wall: %d patches" % sk.dirt.patches.size())
			_check(sk.bushes.list.size() >= 20, "bushes in it: %d" % sk.bushes.list.size())
			var g := sk.find_child("Ground", true, false) as MeshInstance3D
			_check(g != null and int((g.material_override as ShaderMaterial).get_shader_parameter("dig_n")) > 0, "the town's ground cut over the strip")
			patch = sk.dirt.patches[0]
			var x := patch.global_transform.basis.z
			fwd = Vector3(x.x, 0, x.z).normalized()
			_put(_at(along, 2.2, 0.6), atan2(fwd.x, fwd.z))
			step = 1
			t = 0.0
		1:
			if t < 1.2:
				return false
			var y := arena.player.global_position.y
			_check(absf(y) < 0.15, "standing on the dirt (feet at %.2f m)" % y)
			_shot("1_on_dirt")
			# a trench across the wall: open down to 2.6 m either side, a tunnel under the wall itself
			var a := -3.2
			while a <= 3.2:
				var ys := [-2.2, -1.7, -1.2, -0.8] if absf(a) < 0.75 else [-2.2, -1.7, -1.2, -0.8, -0.3, 0.2]
				for yy in ys:
					for w in [-0.5, 0.0, 0.5]:
						patch.wdig(_at(along + w, a, yy), 0.62, VoxelTerrain.STONE)
				a += 0.25
			patch.finish()
			step = 2
			t = 0.0
		2:
			if t < 0.3:
				return false
			# down in the trench, on the far side from where we'll go, facing under the wall
			_put(_at(along, 2.6, -2.3), atan2(fwd.x, fwd.z))
			step = 3
			t = 0.0
		3:
			if t < 0.8:
				return false
			var y := arena.player.global_position.y
			_check(y < -1.9, "down in the trench (feet at %.2f m)" % y)
			_shot("2_in_trench")
			walking = true
			step = 4
			t = 0.0
		4:
			if t < 2.5:
				return false
			walking = false
			var l := patch.to_local(arena.player.global_position)
			_check(l.z < -1.2, "walked under the wall to the other side (%.2f m across, was 2.6)" % l.z)
			_shot("3_through")
			# a bush cut down
			var best := -1
			var bd := INF
			for i in sk.bushes.list.size():
				var d := (sk.bushes.list[i].at as Vector3).distance_to(_at(along, 0.0, 0.0))
				if d < bd:
					bd = d
					best = i
			var b: Dictionary = sk.bushes.list[best]
			var c: Vector3 = (b.at as Vector3) + Vector3(0, 0.55, 0)
			var from := c + Vector3(1.5, 0.4, 0)
			for k in 3:
				b.cool = 0.0
				sk.bushes.strike(from, (c - from).normalized(), 3.0)
			_check(b.state == "tip", "three blows cut a bush down")
			step = 5
			t = 0.0
			set_meta("bush", best)
		5:
			if t < 0.8:
				return false
			var i: int = get_meta("bush")
			var b: Dictionary = sk.bushes.list[i]
			_check(b.state == "lie", "it lies on its side")
			# take hold of it (E), walk it over to the trench, get down in it and let go: over you
			_put((b.at as Vector3) + Vector3(0, 0.1, 0) + fwd * 0.5, atan2(fwd.x, fwd.z))
			step = 6
			t = 0.0
		6:
			if t < 0.3:
				return false
			_key(KEY_E, true)
			_key(KEY_E, false)
			step = 7
			t = 0.0
		7:
			if t < 0.2:
				return false
			_check(sk.bushes.dragging >= 0, "E takes hold of it")
			_check(is_equal_approx(arena.speed_k, VoxelParkBushes.DRAG_SLOW), "slower dragging it")
			_put(_at(along, -2.6, -2.3), atan2(fwd.x, fwd.z))
			step = 8
			t = 0.0
		8:
			if t < 0.8:
				return false
			_key(KEY_E, true)
			_key(KEY_E, false)
			step = 9
			t = 0.0
		9:
			if t < 0.3:
				return false
			_check(sk.bushes.dragging < 0 and is_equal_approx(arena.speed_k, 1.0), "E lets go")
			_check(sk.bushes.covered(arena.player.global_position), "let go down the trench: pulled over the top of you")
			_check(sk.bushes.hidden(), "hidden down the hole under the bush")
			_shot("4_under_bush")
			# standing in a bush that's still growing
			for b in sk.bushes.list:
				if b.state == "grow":
					_put((b.at as Vector3) + Vector3(0, 0.1, 0), 0.0)
					break
			step = 10
			t = 0.0
		10:
			if t < 0.5:
				return false
			_check(sk.bushes.hidden(), "hidden standing in a growing bush")
			# home and back: all as it was
			sk.home()
			sk.go()
			sk.dirt.finish()
			var top := patch.surface_y(patch.to_local(_at(along, 0.0, 0.0)))
			_check(is_equal_approx(top, 0.0) and sk.bushes.list.all(func(b): return b.state == "grow"), "home and back: the trench filled in, the bushes grown back")
			print("PASS" if fails.is_empty() else "FAIL %s" % str(fails))
			quit(0 if fails.is_empty() else 1)
			return true
	return false

func _physics_process(_dt: float) -> bool:
	if walking:
		arena.player.velocity = Vector3(-fwd.x * 3.0, arena.player.velocity.y, -fwd.z * 3.0)
		arena.player.move_and_slide()
	return false
