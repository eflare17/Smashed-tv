extends SceneTree
## St Kilda's buildings you can smash (VoxelBreakables): in St Kilda, stood 10 m out from a building's wall, shots
## knock its blocks out (it swaps from as-drawn to blocks), a row of blasts along its foot brings the wall above down
## (falling, then smashed into cubes on the ground), and the trip home builds it again. Pictures along the way (under
## a display, Forward+: -- --out=dir); -- --video=dir also saves every frame of the collapse. Prints PASS or FAIL.
## Owned by the St Kilda session.

var arena: VoxelArena
var sk: VoxelStKilda
var b: VoxelBreakables.Building
var t := 0.0
var step := 0
var out := ""
var video := ""
var fails := []
var wall_c := 0                  # the column in the middle of the wall we face
var face_n := Vector2.ZERO
var start_standing := 0
var frame := 0

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
		if x.begins_with("--video="):
			video = x.trim_prefix("--video=")
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

## The building with the longest straight wall (at least 12 m, and 6 m tall), and the middle of that wall.
func _pick() -> void:
	var best := 0.0
	for bb in sk.breaks.list:
		if bb.h < 6.0:
			continue
		var run := 0
		for c in bb.cols.size():
			var same: bool = c > 0 and (bb.cols[c].dir as Vector2).is_equal_approx(bb.cols[c - 1].dir)
			run = run + 1 if same else 1
			if run * float(bb.cols[c].w) > best:
				# (and open ground in front: nothing within 10 m)
				var cc: Dictionary = bb.cols[c - run / 2]
				var at: Vector3 = bb.block_at(c - run / 2, 0)
				var n: Vector2 = cc.n
				var q := PhysicsRayQueryParameters3D.create(at + Vector3(n.x, 0, n.y) * 0.6 + Vector3.UP * 1.5, at + Vector3(n.x, 0, n.y) * 11.0 + Vector3.UP * 1.5)
				if sk.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					best = run * float(bb.cols[c].w)
					b = bb
					wall_c = c - run / 2
					face_n = n
	print("building ", b.data.get("id", ""), " ", b.data.get("n", ""), ": wall ", snappedf(best, 0.1), " m, ", b.rows, " rows, ", b.alive.size(), " blocks")

func _stand(back: float) -> void:
	var at := b.block_at(wall_c, 0)
	var to := at + Vector3(face_n.x, 0, face_n.y) * back
	sk._put(Vector3(to.x, 0.05, to.z), atan2(face_n.x, face_n.y), 0.05)

func _process(dt: float) -> bool:
	t += dt
	if t < 2.0:
		return false
	match step:
		0:
			arena.godmode = true
			arena.waves.queue.clear()
			sk = arena.stkilda
			sk.go()
			_pick()
			_check(b != null, "a building to smash")
			if b == null:
				step = 99
				return false
			start_standing = b.standing
			_stand(14.0)
			step = 1
			t = 0.0
		1:
			if t > 1.0:
				_shot("smash_before")
				step = 2
				t = 0.0
		2:
			# five spots on the wall, chest high, a little apart, three shots each: a bite of bricks out at each
			for k in 5:
				var at := b.block_at(wall_c + k - 2, 1)
				var from := at + Vector3(face_n.x, 0, face_n.y) * 9.0
				for s in 3:
					arena.fire(from, (at - from).normalized(), 1, 0.0, 2.2)
			_check(not b.whole, "hit: in blocks now")
			_check(b.chipped >= 15 and b.chipped < 150, "fifteen shots, just the bricks they hit out (%d)" % b.chipped)
			_check(b.standing == start_standing, "no whole block gone")
			step = 3
			t = 0.0
		3:
			if t > 0.6:
				_shot("smash_shots")
				step = 4
				t = 0.0
		4:
			# a row of blasts along the wall's foot, 7 m of it: the wall above has nothing under it
			for k in range(-3, 4):
				sk.breaks.blast(b.block_at(wall_c + k * 2, 0) + Vector3(face_n.x, 0, face_n.y) * 0.3, 1.6)
			_check(sk.breaks._fall.size() > 10, "the wall above comes down (%d falling)" % sk.breaks._fall.size())
			_stand(16.0)
			step = 5
			t = 0.0
			frame = 0
		5:
			if video != "":
				_vid()
			if t > 0.35 and t < 0.45:
				_shot("smash_falling")
			if t > 3.5:
				_check(sk.breaks._fall.is_empty(), "all down and smashed")
				_check(sk.breaks.bricks_lying() > 300, "bricks piled on the ground (%d)" % sk.breaks.bricks_lying())
				_shot("smash_after")
				step = 6
				t = 0.0
		6:
			if t > 0.5:
				sk.home()
				_check(b.whole and b.standing == start_standing, "home: built again for next time")
				step = 99
		99:
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false

func _vid() -> void:
	frame += 1
	var img := root.get_texture().get_image()
	img.save_jpg("%s/f%04d.jpg" % [video, frame], 0.9)
