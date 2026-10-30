extends SceneTree
## St Kilda's rubble knocking about (VoxelBreakables): a row of blasts along a building's foot and the wall above comes
## away in slabs that tip over and smash into bricks; walking through the pile (W held, as you would) kicks bricks
## along; a blast on the pile throws its bricks up again; and bricks thrown at a wall still standing bounce off it, none
## ending up inside. -- --out=dir for pictures (under a display, Forward+). Prints PASS or FAIL. Owned by the St Kilda
## session.

var arena: VoxelArena
var sk: VoxelStKilda
var b: VoxelBreakables.Building
var t := 0.0
var step := 0
var out := ""
var fails := []
var c := 0
var n := Vector2.ZERO
var most_slabs := 0
var shot_at := -1.0
var pile := Vector3.ZERO
var l0 := 0
var wall: VoxelBreakables.Building

func _initialize() -> void:
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--out="):
			out = x.trim_prefix("--out=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _shot(name: String) -> void:
	if out == "":
		return
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
			for bb in sk.breaks.list:
				if not bb.over and (b == null or bb.alive.size() > b.alive.size()):
					b = bb
			c = b.cols.size() / 2
			n = b.cols[c].n
			sk._put(b.block_at(c, 0) + Vector3(n.x, 0, n.y) * 18.0, atan2(n.x, n.y), 0.15)
			step = 1
			t = 0.0
		1:
			if t > 1.0:
				for k in range(-4, 5):
					sk.breaks.blast(b.block_at((c + k * 2 + b.cols.size()) % b.cols.size(), 0) + Vector3(n.x, 0, n.y) * 0.3, 1.6)
				step = 2
				t = 0.0
		2:
			most_slabs = maxi(most_slabs, sk.breaks.slabs_count())
			if shot_at < 0.0 and sk.breaks.slabs_count() > 0 and t > 0.35:
				shot_at = t
				_shot("rubble_1_tipping")
			if t > 5.0 and ((sk.breaks.falling_count() == 0 and sk.breaks.bricks_flying() < 20) or t > 15.0):
				_check(sk.breaks.bricks_flying() < 20, "it all settles (%d still flying)" % sk.breaks.bricks_flying())
				_check(most_slabs > 0, "the wall above came away in slabs (%d at once)" % most_slabs)
				_check(sk.breaks.bricks_lying() > 500, "smashed into bricks, lying in a pile (%d)" % sk.breaks.bricks_lying())
				_shot("rubble_2_pile")
				# a brick lying at the foot of where the wall was: you, 4 m back from it, walking at it
				var foot := b.block_at(c, 0) + Vector3(n.x, 0, n.y) * 1.2
				var best := INF
				for i in sk.breaks._lp.size():
					var d := sk.breaks._lp[i].distance_to(foot)
					if d < best:
						best = d
						pile = sk.breaks._lp[i]
				sk._put(Vector3(pile.x, 0.05, pile.z) + Vector3(n.x, 0, n.y) * 4.0, atan2(n.x, n.y), -0.3)
				_key(KEY_W, true)
				step = 3
				t = 0.0
		3:
			if t > 2.0:
				_key(KEY_W, false)
				_check(sk.breaks.kicked > 0, "walking through the pile kicks bricks along (%d)" % sk.breaks.kicked)
				_shot("rubble_3_kicked")
				var thrown0 := sk.breaks.thrown
				sk.breaks.blast(pile + Vector3.UP * 0.3, 1.6)
				_check(sk.breaks.thrown - thrown0 > 20, "a blast on the pile throws its bricks up again (%d)" % (sk.breaks.thrown - thrown0))
				step = 4
				t = 0.0
		4:
			if t > 0.25 and t < 0.4:
				_shot("rubble_4_thrown")
				t = 0.5
			if t > 3.0:
				# bricks thrown hard at a wall still standing (another building's): they bounce off it
				for bb in sk.breaks.list:
					if bb != b and not bb.over and bb.whole and bb.alive.size() > 40:
						wall = bb
						break
				var wc := wall.cols.size() / 3
				var wn: Vector2 = wall.cols[wc].n
				var at := wall.block_at(wc, 1) + Vector3(wn.x, 0, wn.y) * 3.0
				l0 = sk.breaks.bricks_lying()
				sk.breaks.bricks(Transform3D(Basis.IDENTITY.scaled(Vector3(0.6, 0.6, 0.3)), at), Color.ORANGE, PackedColorArray(),
						-Vector3(wn.x, 0, wn.y) * 9.0, 0.3)
				step = 5
				t = 0.0
		5:
			if t > 3.0:
				var inside := 0
				var landed := 0
				for i in range(l0, sk.breaks.bricks_lying()):
					var p := sk.breaks._lp[i]
					landed += 1
					if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), wall.ring):
						inside += 1
				_check(landed > 3, "the bricks thrown at the wall landed (%d)" % landed)
				_check(inside == 0, "none went through the wall (%d inside)" % inside)
				sk.home()
				_check(sk.breaks.bricks_lying() == 0, "home: cleared for next time")
				step = 99
		99:
			print("PASS" if fails.is_empty() else "FAIL: " + ", ".join(fails))
			quit(0 if fails.is_empty() else 1)
	return false
