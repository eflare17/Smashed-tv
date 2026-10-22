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

# Stage B: co-op and weapons
func _stage_b() -> void:
	var net: VoxelNet = arena.net
	# a settings change mid co-op doesn't start the fight over (the caps wait)
	var b1 := _body("grunt", Vector3(-4, 0, -8))
	var lie0 := VoxelDebris.max_lie
	net.linked = true
	var s := VoxelSettings.new()
	s.file = ""
	s.set_preset("ultra")
	s.v.chunk = arena.chunk
	s.apply(arena)
	net.linked = false
	check(is_instance_valid(b1) and not b1.is_queued_for_deletion() and VoxelDebris.max_lie == lie0,
		"a preset picked mid co-op: the cubes' caps wait, the shared fight isn't started over")
	# O while sitting at the console isn't the online menu
	arena.games.seated = 1
	var e := InputEventKey.new()
	e.physical_keycode = KEY_O
	e.pressed = true
	arena.net_menu._unhandled_input(e)
	var opened: bool = arena.net_menu.is_open()
	arena.games.seated = 0
	arena.net_menu.close()
	check(not opened, "O on the couch is the game's button, not the online menu")
	# a co-op guest never frees the host's lying piece
	var f := _body("grunt", Vector3(4, 0, -8))
	var xf := {}
	for nm in f.parts:
		xf[nm] = f.skeleton.global_transform * f.skeleton.get_bone_global_pose(int(f.parts[nm].bone))
	f.make_fragment({"forearm_l": {"cells": f.parts.forearm_l.grid.cells, "mesh": null}}, xf)
	arena.pieces.puppet = true
	arena.pieces.from_fragment(f)
	arena.pieces.puppet = false
	check(is_instance_valid(f) and not f.is_queued_for_deletion() and arena.bodies.has(f), "a co-op guest's grab doesn't free the host's lying piece")
	# a linked guest's own lunge isn't applied twice (the host's copy sends it back)
	net.linked = true
	net.role = "guest"
	arena._dash_t = 0.0
	arena.me.dash(Vector3(9, 0, 0), 0.3)
	var dashed: float = arena._dash_t
	net.linked = false
	net.role = ""
	check(dashed == 0.0, "a co-op guest's own chainsaw lunge waits for the host's (not applied twice)")
	# the dead can be carried out the back door to the yard; the living stay in the arena
	var yard_spot := Vector3((VoxelYard.X0 + VoxelYard.X1) * 0.5, 0.0, 30.0)
	var d := _body("grunt", yard_spot)
	d.alive = false
	VoxelWeaponGravity._clamp(d)
	var live := _body("grunt", yard_spot)
	VoxelWeaponGravity._clamp(live)
	check(d.position.distance_to(yard_spot) < 0.5 and absf(live.position.z) <= 21.0,
		"the gravity gun: a corpse can be in the yard (for the shredder), a live one stays in the arena")
	# the lying cubes go across to a guest who's just come
	for i in 40:
		arena.debris._lay(Vector3(2.0 + i * 0.03, 0.02, 2.0), Basis(), VoxelBody.FLESH[i % 4])
	var deb := VoxelDebris.new()
	arena.add_child(deb)
	deb.setup(arena._cube_m("grunt"))
	var out: Array = arena.debris.lying_out()
	deb.lying_in(out)
	var same: bool = deb._ln > 0 and deb._ln == arena.debris._ln and (deb._ln == 0 or (deb._lp[0].distance_to(arena.debris._lp[0]) < 0.001 and deb._lc[0].is_equal_approx(arena.debris._lc[0])))
	check(same, "the host's lying cubes laid the same on a guest who's just come (%d)" % deb._ln)
	deb.queue_free()

# Stage C: the backpack, saving, keys while down, loose cubes, the games shelf, plants
func _stage_c() -> void:
	# a full backpack: gold waits (not thrown as rubble), goes in when there's room
	var inv: VoxelInventory = arena.inv
	var saved := inv.to_data()
	for i in inv.slots.size():
		inv.slots[i] = {"id": "blocks", "n": VoxelItems.stack_max("blocks")}
	var lay0: int = arena.debris._ln + arena.debris._n
	arena.receive({"id": "gold", "n": 3}, "inv")
	var thrown: int = arena.debris._ln + arena.debris._n - lay0
	check(inv.count("gold") == 0 and arena.waiting.size() == 1 and int(arena.waiting[0].n) == 3 and thrown == 0,
		"a full backpack: 3 gold wait (not thrown on the floor to come back as rubble)")
	inv.take_at(0, -1)
	check(inv.count("gold") == 3 and arena.waiting.is_empty(), "room made: the waiting gold goes in the backpack")
	inv.from_data(saved)
	# kill cash marks the save to be written
	arena.stash._dirty = false
	var kb := _body("grunt", Vector3(0, 0, -10))
	arena._on_died(kb)
	check(arena.stash._dirty, "kill cash: the save's marked to be written (it was lost on quitting)")
	# F2 tells the settings, so a later change doesn't put the cube size back
	var c0: int = arena.chunk
	var e := InputEventKey.new()
	e.physical_keycode = KEY_F2
	e.keycode = KEY_F2
	e.pressed = true
	arena._unhandled_input(e)
	var kept: bool = int(arena.settings_menu.s.v.chunk) == arena.chunk and arena.chunk != c0
	arena.settings_menu.s.apply(arena)
	kept = kept and arena.chunk != c0
	arena._unhandled_input(e)            # (back as it was)
	check(kept, "F2's cube size is kept by the settings (applying them doesn't put it back)")
	# down: no quick sword slash
	arena.down_t = 2.0
	var ready0: bool = arena.sword.ready_to_swing()
	arena._sword_key(false)
	var still: bool = arena.sword.ready_to_swing()
	arena.down_t = 0.0
	check(ready0 and still, "down: F / C / a side button don't swing the sword")
	# a flying cube pushed out by the cap lands on the floor
	var f0 := VoxelDebris.max_fly
	VoxelDebris.max_fly = 4
	var deb := VoxelDebris.new()
	arena.add_child(deb)
	deb.setup(arena._cube_m("grunt"))
	VoxelDebris.max_fly = f0
	var bits := []
	for i in 8:
		bits.append({"pos": Vector3(i * 0.1, 2.0, 0), "col": VoxelBody.FLESH[0]})
	deb.burst(bits, Vector3.UP, 0.1)
	var floating := 0
	for i in deb._ln:
		if deb._lp[i].y > 0.2:
			floating += 1
	check(deb._ln > 0 and floating == 0, "the flying cap full: the cubes pushed out land on the floor (%d laid, %d in the air)" % [deb._ln, floating])
	deb.queue_free()
	# a plant's height worked out once
	VoxelPlant._tops.clear()
	var h1 := VoxelPlant._top(0, 0, 0)
	var h2 := VoxelPlant._top(0, 0, 0)
	check(VoxelPlant._tops.size() == 1 and is_equal_approx(h1, h2), "a plant's height is worked out once, not every frame")
	# the games shelf looked through again: the case in your hands is still the same game
	var gr: Node = arena.games
	var dir := ProjectSettings.globalize_path(VoxelGamesRoom.GAMES)
	var b_path := dir.path_join("zz_sweep_b.md")
	var a_path := dir.path_join("aa_sweep_a.md")
	var fb := FileAccess.open(b_path, FileAccess.WRITE)
	fb.store_buffer(FileAccess.get_file_as_bytes(VoxelGamesRoom.BUILTIN))
	fb = null
	gr.scan()
	gr.held = gr._index_of(b_path)
	var fa := FileAccess.open(a_path, FileAccess.WRITE)
	fa.store_buffer(FileAccess.get_file_as_bytes(VoxelGamesRoom.BUILTIN))
	fa = null
	gr.scan()
	var same_game: bool = gr.held >= 0 and String(gr.library[gr.held].path) == b_path
	gr.held = -1
	DirAccess.remove_absolute(a_path)
	DirAccess.remove_absolute(b_path)
	gr.scan()
	check(same_game, "a game added to the shelf: the case in your hands is still the same game")

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
			step = 10
		10:
			_stage_b()
			_stage_c()
			step = 99
		99:
			print("SWEEP done %d passed, %d failed" % [passed, failed])
			return true
	return false
