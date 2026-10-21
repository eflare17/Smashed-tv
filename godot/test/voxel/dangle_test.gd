extends SceneTree
## Stage 8, bones hold the body together (headless): every kind whole holds every limb; a tunnel through the elbow
## (the bone out, flesh either side) and the forearm hangs (still on, by its strip), the hand with it; it swings when
## the body's shoved; it strains and tears off by itself (a piece, its meat on its bone); a thinner strip tears sooner;
## a shot on a hanging limb finishes it; a knee shot through and the leg hangs (a limp); a gouge in the flesh that misses
## the bone holds; fire (the bone doesn't burn) never loosens a limb. Prints "DANGLE ok/FAIL ..." and "DANGLE done N
## passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v0 := {}

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("DANGLE %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _body(key: String, at: Vector3) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup(key, arena._cube_m(key), 1, arena._mat)
	b.position = at
	arena.bodies.append(b)
	b.hp = 1e9
	return b

func _joint(b: VoxelBody, nm: String) -> Vector3:
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(int(b.parts[nm].bone)).origin

# a tunnel through a limb front to back, through its bone just below its joint: the bone taken out, flesh left either
# side (below: how far down, in cubes)
func _tunnel(b: VoxelBody, nm: String, r: float, below := 2) -> void:
	for k in 3:
		var p: Dictionary = b.parts[nm]
		var s: Vector3i = p.grid.size
		var cells: PackedInt32Array = p.grid.cells
		var aim := b._joint_in(p, int(p.bone)) + Vector3(0, -below - k, 0)
		var best := -1
		var bd := INF
		for i in cells.size():
			if cells[i] == VoxelBody.BONE_V:
				var d := Vector3(i % s.x, (i / s.x) % s.y, i / (s.x * s.y)).distance_to(aim)
				if d < bd:
					bd = d
					best = i
		if best < 0:
			return
		var w := b._cell_world(nm, best)
		b.carve(w + Vector3(0, 0, 0.3), w - Vector3(0, 0, 0.3), r)
		if b.loose.has(nm) or p.gone:
			return

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	match step:
		0:
			arena.frozen = true
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			var all_held := true
			for k in ["grunt", "batter", "brute", "swarmer"]:
				var w := _body(k, Vector3(-6, 0, -6))
				w._update_loose()
				all_held = all_held and w.loose.is_empty()
				arena.bodies.erase(w)
				w.queue_free()
			check(all_held, "every kind, whole: every limb held by its bones")
			# A: a tunnel through the left elbow
			var a := _body("grunt", Vector3(0, 0, -3))
			_tunnel(a, "forearm_l", 0.03)
			check(a.loose.has("forearm_l") and a.loose.has("hand_l") and not a.parts.forearm_l.gone and a.strip_cubes("forearm_l") > 0, "the elbow's bone shot out: the forearm hangs by its skin (a strip of %d cubes), the hand with it" % a.strip_cubes("forearm_l"))
			check(a._dangle.has("forearm_l") and not a._dangle.has("hand_l"), "one swing for the chain (from the elbow)")
			v0.a = a
			v0.tip0 = (a._dangle.forearm_l.tip as Vector3)
			a.knock = Vector3(2.5, 0, 0)          # shoved
			# B: a thinner strip (a wider tunnel), C: shot again on the hanging forearm
			var bb := _body("grunt", Vector3(2.5, 0, -3))
			_tunnel(bb, "forearm_l", 0.05)
			v0.b = bb
			var c := _body("grunt", Vector3(-2.5, 0, -3))
			_tunnel(c, "forearm_l", 0.03)
			v0.c = c
			v0.pieces0 = arena.pieces.count()
			mark = t
			step = 1
		1:
			var a: VoxelBody = v0.a
			if not v0.has("swung") and t - mark > 0.3:
				v0.swung = (a._dangle.forearm_l.tip as Vector3).distance_to(v0.tip0) if a._dangle.has("forearm_l") else 0.0
				check(float(v0.swung) > 0.01, "shoved, it swings (the hand end moved %.3f m)" % float(v0.swung))
				# the shot on C's hanging forearm
				var c: VoxelBody = v0.c
				var fp: Dictionary = c.parts.forearm_l
				var ki := VoxelBody._nearest_filled_cell(fp.grid.cells, fp.grid.size, c._joint_in(fp, int(fp.bone)) + Vector3(0, -6, 0))
				var cw := c._cell_world("forearm_l", ki)
				c.carve(cw + Vector3(0, 0, 0.1), cw - Vector3(0, 0, 0.1), 0.02)
				v0.c_t = t
			if v0.has("c_t") and not v0.has("c_done"):
				var c2: VoxelBody = v0.c
				if c2.parts.forearm_l.gone:
					v0.c_done = true
					check(t - float(v0.c_t) < 0.5, "a shot on the hanging forearm finishes it (off in %.2f s)" % (t - float(v0.c_t)))
			var bb: VoxelBody = v0.b
			if bb.parts.forearm_l.gone and not v0.has("b_t"):
				v0.b_t = t - mark
			if a.parts.forearm_l.gone and not v0.has("a_t"):
				v0.a_t = t - mark
				check(a._dangle.is_empty() and a.loose.is_empty(), "strained through, it tears off by itself (%.1f s)" % float(v0.a_t))
				check(arena.pieces.count() > int(v0.pieces0), "it comes off as a piece")
				var pc: Dictionary = arena.pieces._pieces[-1]
				var counts := {}
				VoxelPieces.cubes_of(pc, 1, counts)
				var flesh := 0
				var bone := 0
				for v in counts:
					var k := int(v) - 1
					var id := VoxelItems.of_colour(Color8((k >> 16) & 255, (k >> 8) & 255, k & 255))
					if id == "meat":
						flesh += int(counts[v])
					elif id == "bone":
						bone += int(counts[v])
				check(flesh > 100 and bone > 5, "its meat still on its bone (%d meat, %d bone)" % [flesh, bone])
			if v0.has("a_t") and v0.has("b_t"):
				check(float(v0.b_t) < float(v0.a_t), "a thinner strip tears sooner (%.1f s against %.1f s)" % [float(v0.b_t), float(v0.a_t)])
				step = 2
			elif t - mark > 40.0:
				check(false, "never tore (A %s, B %s)" % [str(v0.get("a_t")), str(v0.get("b_t"))])
				step = 2
		2:
			# a knee shot through: the leg hangs, a limp
			var d := _body("grunt", Vector3(5, 0, -6))
			_tunnel(d, "shin_r", 0.025, 3)
			check(d.loose.has("shin_r") and d.legs_lost() == 1 and is_equal_approx(d.move_factor(), 0.45), "the knee's bone shot out: the shin hangs, the leg's no use (a limp)")
			# a gouge in the forearm's flesh that misses the bone: held
			var e := _body("grunt", Vector3(-5, 0, -6))
			var fj := _joint(e, "forearm_l") + Vector3(0, -0.08, 0)
			e.carve(fj + Vector3(0.3, 0, 0.06), fj + Vector3(-0.3, 0, 0.06), 0.015)
			check(e.loose.is_empty(), "a gouge in the flesh that misses the bone: still held")
			# fire held on the elbow (the bone doesn't burn): held
			var f := _body("grunt", Vector3(-7, 0, -3))
			v0.f = f
			mark = t
			step = 3
		3:
			var f: VoxelBody = v0.f
			var j := _joint(f, "forearm_l")
			if int(t * 10) != int((t - 1.0 / 60.0) * 10):
				var h := f.trace(j + Vector3(0, 0, 1.0), Vector3(0, 0, -1), 2.0)
				if not h.is_empty():
					f.ignite(h.point, 0.085)
			if t - mark > 8.0:
				check(f.loose.is_empty(), "the flamethrower held on the elbow for 8 s: it burns to the bone and the arm holds")
				step = 99
		99:
			print("DANGLE done %d passed, %d failed" % [passed, failed])
			return true
	return false
