extends SceneTree
## Screenshots of stumps (not headless: under a display): a grunt standing with its left forearm torn off at the elbow
## (stump_arm), its right shin off at the knee (stump_leg), one with its head off (stump_neck), and the pieces lying on
## the floor (stump_pieces: the forearm; stump_head_piece: the head, from its neck end). -- --out=dir. Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var out := "user://"
var g: VoxelBody
var cam: Camera3D

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)

func _body(at: Vector3, yaw: float) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
	b.position = at
	b.yaw = yaw
	b.hp = 1e9
	arena.bodies.append(b)
	return b

func _joint(b: VoxelBody, nm: String) -> Vector3:
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(b.parts[nm].bone)).origin

func _look(from: Vector3, at: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 55.0
		arena.add_child(cam)
		arena._hud_layer.visible = false
		arena.net_menu.visible = false
		arena.settings_menu.visible = false
	cam.current = true
	cam.global_position = from
	cam.look_at(at)
	arena.player.global_position = Vector3(0, 0, 6)

# a part torn off at its joint, as a strained-through limb is (the piece flung to the side)
func _off(b: VoxelBody, nm: String, fling: Vector3) -> void:
	var r: Dictionary = b.sever(nm)
	if not (r.pieces as Array).is_empty():
		arena.pieces.spawn(b, r.pieces, fling, Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))

func _process(dt: float) -> bool:
	t += dt
	if t < 1.5:
		return false
	match step:
		0:
			arena.frozen = true
			VoxelBody.immortal = true
			for x in arena.bodies:
				x.queue_free()
			arena.bodies.clear()
			g = _body(Vector3(0, 0, -2.0), 0.0)
			_off(g, "forearm_l", Vector3(1.5, 1.0, 1.0))
			_off(g, "shin_r", Vector3(-2.5, 1.0, -2.5))
			var el := _joint(g, "forearm_l")
			_look(el + Vector3(0.45, -0.25, 0.55), el + Vector3(0, -0.02, 0))
			t = 10.0
			step = 1
		1:
			if t > 11.0:
				_shot("stump_arm")
				step = 2
		2:
			if t > 11.3:
				var kn := _joint(g, "shin_r")
				_look(kn + Vector3(-0.3, -0.25, 0.6), kn + Vector3(0, -0.03, 0))
				step = 3
		3:
			if t > 11.8:
				_shot("stump_leg")
				step = 4
		4:
			if t > 12.1:
				var b2 := _body(Vector3(2.5, 0, -2.0), 0.0)
				_off(b2, "head", Vector3(0.5, 2.0, 1.0))
				var nk := _joint(b2, "head")
				_look(nk + Vector3(0.35, 0.4, 0.5), nk)
				step = 5
				t = 20.0
		5:
			if t > 21.0:
				_shot("stump_neck")
				step = 6
		6:
			if t > 21.3:
				# the torn-off forearm, lying where it fell, from its torn end
				var best: VoxelBody = null
				for b3 in arena.bodies:
					if b3.fragment and b3.parts.has("forearm_l") and not b3.parts.forearm_l.gone:
						best = b3
				if best:
					var e := _joint(best, "forearm_l")
					var away := (e - best.global_position)
					away.y = 0.0
					_look(e + away.normalized() * 0.35 + Vector3(0, 0.35, 0) + Vector3(0.1, 0, 0.1), e)
				step = 7
		7:
			if t > 21.8:
				_shot("stump_pieces")
				step = 8
		8:
			if t > 22.1:
				# the head, lying where it fell, from its neck end
				var hb: VoxelBody = null
				for b4 in arena.bodies:
					if b4.fragment and b4.parts.has("head") and not b4.parts.head.gone:
						hb = b4
				if hb:
					var nk2 := _joint(hb, "head")
					var mid2: Vector3 = hb.skeleton.global_transform * hb.skeleton.get_bone_global_pose(int(hb.parts.head.bone)) * (Vector3(0, 0.12, 0))
					var away2 := (nk2 - mid2).normalized()
					_look(nk2 + away2 * 0.4 + Vector3(0, 0.25, 0), nk2)
				step = 9
		9:
			if t > 22.6:
				_shot("stump_head_piece")
				step = 10
		10:
			if t > 22.9:
				return true
	return false
