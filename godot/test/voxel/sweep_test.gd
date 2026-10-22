extends SceneTree
## The whole-game bug sweep's fixes, each checked (headless). Stage A, the bodies: a pistol hole through the elbow's
## bone makes the forearm hang; a hole in a hanging forearm finishes it; a hanging limb blown off by holes leaves no
## swing, skin or drip behind; a shatter clears them too; a lying piece never hangs (or tears and jumps up); freezing
## keeps the bone (nothing hangs, no tear while frozen, the tear waits for the thaw); a part off whole keeps cells of
## the right size; the grids sent whole carry the hits and the frost; a co-op guest's replays never decide a death;
## the swing and the strain come out the same at 30 and 240 frames a second. Prints "SWEEP ok/FAIL ..." and "SWEEP
## done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
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
	print("SWEEP %s %s" % ["ok" if ok else "FAIL", what])

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

# the bone cell of part nm nearest its joint, below by `below` cubes: its index
func _bone_cell(b: VoxelBody, nm: String, below: int) -> int:
	var p: Dictionary = b.parts[nm]
	var s: Vector3i = p.grid.size
	var aim := b._joint_in(p, int(p.bone)) + Vector3(0, -below, 0)
	var best := -1
	var bd := INF
	for i in (p.grid.cells as PackedInt32Array).size():
		if p.grid.cells[i] == VoxelBody.BONE_V:
			var d := Vector3(i % s.x, (i / s.x) % s.y, i / (s.x * s.y)).distance_to(aim)
			if d < bd:
				bd = d
				best = i
	return best

func _cell(b: VoxelBody, nm: String, i: int) -> Vector3i:
	var s: Vector3i = b.parts[nm].grid.size
	return Vector3i(i % s.x, (i / s.x) % s.y, i / (s.x * s.y))

# pistol-sized holes (damage(), as arena.fire makes) through the forearm's bone just under the elbow, till it hangs
func _shoot_elbow(b: VoxelBody) -> void:
	for k in 6:
		var i := _bone_cell(b, "forearm_l", 2 + (k % 3))
		if i < 0:
			return
		b.parts.forearm_l.hits = 0                  # (no blow-off while the bone's being shot through)
		b.damage({"part": "forearm_l", "cell": _cell(b, "forearm_l", i)}, 1.6)
		if b.loose.has("forearm_l"):
			return

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	match step:
		0:
			arena.frozen = true
			for x in arena.bodies:
				x.queue_free()
			arena.bodies.clear()
			var a := _body("grunt", Vector3(-3, 0, -4))
			_shoot_elbow(a)
			check(a.loose.has("forearm_l") and a._dangle.has("forearm_l") and not a.parts.forearm_l.gone,
				"pistol holes through the elbow's bone (damage()): the forearm hangs")
			var fp: Dictionary = a.parts.forearm_l
			var ki := VoxelBody._nearest_filled_cell(fp.grid.cells, fp.grid.size, a._joint_in(fp, int(fp.bone)) + Vector3(0, -6, 0))
			a.parts.forearm_l.hits = 0
			a.damage({"part": "forearm_l", "cell": _cell(a, "forearm_l", ki)}, 1.2)
			check(a._dangle.has("forearm_l") and float(a._dangle.forearm_l.strain) >= 1.0 and a.tear_due() == "forearm_l", "a pistol hole in the hanging forearm finishes it (due to tear)")
			# blown off by holes while hanging: no swing, skin or drip left behind
			var b := _body("grunt", Vector3(0, 0, -4))
			_shoot_elbow(b)
			b.animate(1.0 / 60.0, false)                    # (its skin and drip made)
			b.parts.forearm_l.hits = 1                      # (the next hole takes it off)
			var fp2: Dictionary = b.parts.forearm_l
			var k2 := VoxelBody._nearest_filled_cell(fp2.grid.cells, fp2.grid.size, b._joint_in(fp2, int(fp2.bone)) + Vector3(0, -5, 0))
			b.damage({"part": "forearm_l", "cell": _cell(b, "forearm_l", k2)}, 1.2)
			b.animate(1.0 / 60.0, false)
			check(b.parts.forearm_l.gone and b._dangle.is_empty() and b.loose.is_empty() and b._dangle_fx.is_empty(),
				"a hanging forearm blown off by a hole: no swing, skin strip or drip left in the air")
			# shattered while a limb hangs
			var c := _body("grunt", Vector3(3, 0, -4))
			_shoot_elbow(c)
			c.animate(1.0 / 60.0, false)
			c.chill(1.0)
			var sh := c.shatter()
			check(not sh.is_empty() and c._dangle.is_empty() and c.loose.is_empty() and c._dangle_fx.is_empty() and c._seams.is_empty(),
				"shattered with a limb hanging: the swing, skin, drip and torn edges all gone")
			# a lying piece never hangs (and so never tears off and jumps up when cut)
			var f := _body("grunt", Vector3(-3, 0, 2))
			var xf := {}
			for nm in f.parts:
				xf[nm] = f.skeleton.global_transform * f.skeleton.get_bone_global_pose(int(f.parts[nm].bone))
			var grids := {}
			for nm in ["forearm_l", "hand_l"]:
				grids[nm] = {"cells": f.parts[nm].grid.cells, "mesh": null}
			f.make_fragment(grids, xf)
			for k in 3:
				var bi := _bone_cell(f, "forearm_l", 1 + k)
				if bi >= 0:
					f.damage({"part": "forearm_l", "cell": _cell(f, "forearm_l", bi)}, 1.6)
			var fp3: Dictionary = f.parts.forearm_l
			f.carve(f._cell_world("forearm_l", VoxelBody._nearest_filled_cell(fp3.grid.cells, fp3.grid.size, Vector3(6, 3, 6))) + Vector3(0, 0, 0.2),
				f._cell_world("forearm_l", VoxelBody._nearest_filled_cell(fp3.grid.cells, fp3.grid.size, Vector3(6, 3, 6))) - Vector3(0, 0, 0.2), 0.02)
			check(f.loose.is_empty() and f._dangle.is_empty() and f.tear_due() == "", "a lying forearm shot through the bone and cut: never hangs, never 'tears off'")
			# freezing keeps the bone: nothing goes loose, no tear while frozen, the tear waits for the thaw
			var g := _body("grunt", Vector3(0, 0, 2))
			_shoot_elbow(g)
			g._dangle.forearm_l.strain = 1.0
			g.chill(1.0)
			var bones_kept := 0
			for v in (g.parts.arm_r.grid.cells as PackedInt32Array):
				if v == VoxelBody.BONE_V:
					bones_kept += 1
			g._update_loose()
			check(g.frozen() and bones_kept > 0 and not g.loose.has("arm_r") and not g.loose.has("thigh_l"),
				"frozen: the bone keeps its colour, the whole limbs stay held (%d bone cubes in the right arm)" % bones_kept)
			check(g.tear_due() == "", "frozen: a tear that's due waits (no shatter)")
			g._thaw()
			check(not g.frozen() and g.tear_due() == "forearm_l", "thawed: the tear comes due again")
			# a part off whole keeps cells of its size; the grids sent whole carry the hits and the frost
			var h := _body("grunt", Vector3(3, 0, 2))
			var nk: Vector3 = h.skeleton.global_transform * h.skeleton.get_bone_global_pose(int(h.parts.head.bone)).origin
			h.slice(nk + Vector3(0, 0.0, 1.0), Vector3.UP, Vector3(0, 0, -1), 2.5, 0.3, 0.03)
			var hs: Vector3i = h.parts.head.grid.size
			check(h.parts.head.gone and (h.parts.head.grid.cells as PackedInt32Array).size() == hs.x * hs.y * hs.z,
				"a head off whole: its (empty) cells still the size of its grid (%d)" % (h.parts.head.grid.cells as PackedInt32Array).size())
			h.parts.arm_r.hits = 2
			h.chill(1.0)
			var out := h.grids_out()
			var h2 := _body("grunt", Vector3(5, 0, 2))
			h2.grids_in(out)
			check(int(h2.parts.arm_r.hits) == 2 and h2.frozen() and h2._orig.size() > 0 and h2.parts.head.gone and h2.loose.is_empty(),
				"sent whole: the hits, the frost and the colours under it come across; nothing goes loose")
			# the forearm hanging, then the upper arm's bone broken too: one swing from the shoulder, the strain carried
			# on, and a hit on the forearm finishes the lot
			var u := _body("grunt", Vector3(5, 0, 6))
			_shoot_elbow(u)
			u._dangle.forearm_l.strain = 0.6
			for k in 8:
				var ui := _bone_cell(u, "arm_l", 2 + (k % 3))
				if ui < 0 or u.loose.has("arm_l"):
					break
				u.parts.arm_l.hits = 0
				u.damage({"part": "arm_l", "cell": _cell(u, "arm_l", ui)}, 1.6)
			check(u.loose.has("arm_l") and u._dangle.has("arm_l") and not u._dangle.has("forearm_l") and float(u._dangle.arm_l.strain) >= 0.6,
				"the upper arm broken too: one swing from the shoulder, the forearm's strain carried on (%s)" % str(u._dangle.keys()))
			var up: Dictionary = u.parts.forearm_l
			var uk := VoxelBody._nearest_filled_cell(up.grid.cells, up.grid.size, u._joint_in(up, int(up.bone)) + Vector3(0, -5, 0))
			u.parts.forearm_l.hits = 0
			u.damage({"part": "forearm_l", "cell": _cell(u, "forearm_l", uk)}, 1.2)
			check(u._dangle.has("arm_l") and float(u._dangle.arm_l.strain) >= 1.0, "then a hole in the hanging forearm finishes the whole arm")
			# a co-op guest's replays never decide a death
			var m := _body("grunt", Vector3(-3, 0, 6))
			m.hp = 5.0
			VoxelBody.net_locked = true
			VoxelBody._net_replay = true
			var killed := m.hurt(50.0)
			VoxelBody._net_replay = false
			VoxelBody.net_locked = false
			check(not killed and m.alive, "a co-op guest's replayed hurt doesn't kill (the host's snapshot decides)")
			# the swing and the strain at 30 and 240 frames a second
			v0.slow = _body("grunt", Vector3(-1, 0, 6))
			v0.fast = _body("grunt", Vector3(1.5, 0, 6))
			for bb in [v0.slow, v0.fast]:
				_shoot_elbow(bb)
				bb._dangle.forearm_l.strain = 0.0
				bb.knock = Vector3.ZERO
				bb.odo = 0.0
			for k in 60:          # two seconds walking, at 30 a second
				v0.slow.odo += 1.2 / 30.0
				v0.slow.animate(1.0 / 30.0, true)
			for k in 480:         # the same at 240 a second
				v0.fast.odo += 1.2 / 240.0
				v0.fast.animate(1.0 / 240.0, true)
			var s1 := float(v0.slow._dangle.forearm_l.strain)
			var s2 := float(v0.fast._dangle.forearm_l.strain)
			check(s1 > 0.0 and s2 > 0.0 and maxf(s1, s2) / minf(s1, s2) < 1.6,
				"two seconds walking with a forearm hanging: the strain the same at 30 and 240 fps (%.3f, %.3f)" % [s1, s2])
			step = 99
		99:
			print("SWEEP done %d passed, %d failed" % [passed, failed])
			return true
	return false
