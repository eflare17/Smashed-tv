extends SceneTree
## Stage 2, the backpack and the chests (headless): the inventory's stacking, the vacuum's cubes going into the
## backpack (a corpse sucked up: every cube counted as its item), E at a chest opening the screen with the lid going
## up, moving stacks with the screen's clicks (pick up, put down, half, one, shift across) with nothing made or lost,
## the screen shut by walking off, saving and loading, a stack dropped on the floor and vacuumed back, the backpack
## full, enemies kept out of the chests. With --host=CODE / --join=CODE (two copies, the host first) it checks co-op
## instead: the guest's stacks go into the host's chest and back through the host, the host's moves show in the
## guest's chest, the corpse a guest vacuums is theirs, and cubes one vacuums go in the other's game too. Prints
## "INV ok/FAIL ..." lines and "INV done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var role := ""
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
	print("INV %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host"):
			role = "host"
		elif a.begins_with("--join"):
			role = "guest"
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if role == "":
		return _solo()
	return _coop()

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	arena._unhandled_input(e)

func _st(id: String) -> VoxelStorage:
	return arena.stash.by_id[id]

# the player standing in front of a storage, looking at it
func _stand_at(st: VoxelStorage) -> void:
	arena.player.global_position = st.front() + Vector3(0, 0, 0.9)
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = 0.0
	arena.look_pitch = -0.7
	arena._camera(0.0)

func _all(id: String) -> int:
	var n: int = arena.inv.count(id)
	for st in arena.stash.list:
		n += st.inv.count(id)
	if not arena.inv_ui.cursor.is_empty() and arena.inv_ui.cursor.id == id:
		n += int(arena.inv_ui.cursor.n)
	return n

func _lying_near(p: Vector3, r: float) -> int:
	var d: VoxelDebris = arena.debris
	var n := 0
	for i in d._ln:
		if d._lp[i].distance_to(p) < r:
			n += 1
	return n

func _corpse_at(p: Vector3) -> VoxelBody:
	var b := VoxelBody.new()
	arena.add_child(b)
	b.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
	b.position = p
	b.died.connect(arena._on_died)
	arena.bodies.append(b)
	b.sever("head")
	return b

# the vacuum out, looking at p, its click held (the real vacuum's brush, beam and cubes going in)
func _vacuum_at(p: Vector3) -> void:
	var vi: int = arena.loadout.index_of("vacuum")
	arena._switch(func(): arena.loadout.select(vi))
	arena.loadout.switch_t = 0.0
	arena.vacuum.brush_r = VoxelVacuum.R_MAX
	_look_at(p)
	arena.hold_suck = true

func _look_at(p: Vector3) -> void:
	var to: Vector3 = p - (arena.player.global_position + Vector3(0, 1.65, 0))
	arena.look_yaw = atan2(-to.x, -to.z)
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _clear() -> void:
	for b in arena.bodies:
		b.queue_free()
	arena.bodies.clear()

func _solo() -> bool:
	var inv: VoxelInventory = arena.inv
	match step:
		0:
			arena.frozen = true
			_clear()
			for st in arena.stash.list:
				st.inv.from_data([])
			# stacking
			var x := VoxelInventory.new(4)
			var left := x.add("meat", 15000)
			check(left == 0 and x.at(0).n == 9999 and x.at(1).n == 5001 and x.count("meat") == 15000, "stacks of 9999: 15000 meat in two slots")
			check(x.add("bone", 9999 * 3) == 9999 and x.room_for("meat") == 4998, "a full inventory says what didn't fit (9999 bone left over, room for 4998 meat)")
			var half := x.take_at(1, 250)
			check(half.n == 250 and x.at(1).n == 4751, "take part of a stack")
			var sw := x.put_at(0, {"id": "bone", "n": 5})
			check(sw.id == "meat" and sw.n == 9999 and x.at(0).id == "bone", "putting a different item down swaps")
			var y := VoxelInventory.new(4)
			y.from_data(x.to_data())
			check(y.to_data() == x.to_data(), "saved and loaded the same")
			check(x.remove("bone", 20004) == 20003 and x.count("bone") == 0, "remove takes what's there")
			# the vacuum's cubes are items
			inv.from_data([])
			arena.debris.take(VoxelBody.FLESH[0], 10)
			arena.debris.take(VoxelBody.BONE, 3)
			arena.debris.take(VoxelBody.CHAR, 2)
			arena.debris.take(Color8(10, 200, 30), 4)
			check(inv.count("meat") == 10 and inv.count("bone") == 3 and inv.count("charred") == 2 and inv.count("blocks") == 4, "vacuumed cubes go in the backpack as meat, bone, charred bits, rubble")
			inv.from_data([])
			arena.player.global_position = Vector3(0, 0, 6.5)
			arena.player.reset_physics_interpolation()
			var b := _corpse_at(Vector3(0, 0, 4.5))
			v0.cubes = b.cubes_left()
			_vacuum_at(Vector3(0, 0.3, 4.5))
			mark = t
			step = 1
		1:
			if t - mark > 3.0:
				arena.hold_suck = false
				check(inv.total() >= v0.cubes - 2 and inv.total() <= v0.cubes and inv.count("meat") > 0, "a corpse vacuumed: every cube in the backpack (%d of %d)" % [inv.total(), v0.cubes])
				_stand_at(_st("chest_a"))
				mark = t
				step = 10
		10:
			if t - mark > 0.1:
				# open a chest with E
				var st := _st("chest_a")
				arena._camera(0.0)
				arena._storage_step(0.0)
				check(arena._near_st == st and arena._use_label.text.contains("Chest"), "at a chest: \"E  open Chest\"")
				_key(KEY_E)
				check(arena.inv_ui.is_open() and arena.inv_ui.storage == st and st.open_here, "E opens it, above the backpack")
				mark = t
				step = 2
		2:
			if t - mark > 0.4:
				var st := _st("chest_a")
				check(st._k > 0.9, "the lid swings up")
				var ui: VoxelInventoryUI = arena.inv_ui
				ui._layout()
				var meat0 := _all("meat")
				var tot0 := _all("bone") + meat0 + _all("blocks") + _all("brain") + _all("charred")
				# backpack is panel 1, the chest panel 0
				var mi := -1
				for i in inv.size():
					if not inv.is_empty_at(i) and inv.at(i).id == "meat":
						mi = i
						break
				var n_meat: int = inv.at(mi).n
				ui.click(1, mi, MOUSE_BUTTON_LEFT)
				check(ui.cursor.get("id", "") == "meat" and inv.is_empty_at(mi), "left click picks the stack up")
				ui.click(0, 3, MOUSE_BUTTON_LEFT)
				check(ui.cursor.is_empty() and st.inv.at(3).get("n", 0) == n_meat, "left click puts it in the chest")
				ui.click(0, 3, MOUSE_BUTTON_RIGHT)
				check(int(ui.cursor.get("n", 0)) == ceili(n_meat / 2.0), "right click picks up half")
				ui.click(0, 5, MOUSE_BUTTON_RIGHT)
				ui.click(0, 5, MOUSE_BUTTON_RIGHT)
				check(st.inv.at(5).get("n", 0) == 2, "right click puts down one at a time")
				ui.click(1, 0, MOUSE_BUTTON_LEFT)
				var bi := -1
				for i in inv.size():
					if not inv.is_empty_at(i) and inv.at(i).id != "meat":
						bi = i
						break
				var moving: Dictionary = inv.at(bi).duplicate()
				ui.click(1, bi, MOUSE_BUTTON_LEFT, true)
				check(inv.count(moving.id) == 0 and st.inv.count(moving.id) == int(moving.n), "shift+click sends a stack across (%d %s)" % [moving.n, moving.id])
				ui.click(0, 3, MOUSE_BUTTON_LEFT, true)
				check(st.inv.at(3).is_empty(), "and back")
				var tot1 := _all("bone") + _all("meat") + _all("blocks") + _all("brain") + _all("charred")
				check(tot1 == tot0, "nothing made or lost moving them about (%d, %d)" % [tot0, tot1])
				# saved and loaded
				arena.stash.save()
				var saved: Array = st.inv.to_data()
				var bag: Array = inv.to_data()
				st.inv.from_data([])
				inv.from_data([])
				arena.stash.load_save()
				check(st.inv.to_data() == saved and inv.to_data() == bag and inv.total() > 0, "saved: the chest and the backpack come back as they were")
				# walking off shuts it
				arena.player.global_position += Vector3(0, 0, 4)
				arena._storage_step(0.0)
				check(not ui.is_open() and not st.open_here, "walking off shuts the screen")
				mark = t
				step = 3
		3:
			if t - mark > 0.5:
				var st := _st("chest_a")
				check(st._k == 0.0, "the lid shuts")
				arena.player.global_position = Vector3(5, 0, 5)
				arena.player.reset_physics_interpolation()
				arena.look_yaw = 0.0
				arena.look_pitch = 0.0
				mark = t
				step = 30
		30:
			if t - mark > 0.1:
				# drop a stack and vacuum it back
				arena._camera(0.0)
				inv.from_data([])
				inv.add("bone", 60)
				_key(KEY_TAB)
				check(arena.inv_ui.is_open() and arena.inv_ui.storage == null, "Tab opens the backpack alone")
				arena.inv_ui._layout()
				arena.inv_ui.click(0, 0, MOUSE_BUTTON_LEFT)
				arena.inv_ui.click(-1, -1, MOUSE_BUTTON_LEFT)
				check(inv.count("bone") == 0 and arena.inv_ui.cursor.is_empty(), "clicking outside drops it")
				_key(KEY_TAB)
				check(not arena.inv_ui.is_open(), "Tab again shuts it")
				mark = t
				step = 4
		4:
			if t - mark > 3.0 and step == 4:
				var spot := Vector3(5, 0, 3.6)
				var n := _lying_near(spot, 3.0)
				check(n == 60, "dropped: 60 bone cubes lying on the floor (%d)" % n)
				_vacuum_at(spot)
				mark = t
				step = 5
		5:
			# (swept about the spot: they're spread over a couple of metres)
			var spot2 := Vector3(5, 0, 3.6) + Vector3(sin((t - mark) * 3.0), 0, cos((t - mark) * 3.0)) * 0.9
			_look_at(spot2)
			if t - mark > 4.0:
				arena.hold_suck = false
				var still := _lying_near(Vector3(5, 0, 3.6), 6.0)
				check(inv.count("bone") >= 55 and inv.count("bone") + still == 60, "vacuumed back: %d bone (%d still lying)" % [inv.count("bone"), still])
				# full
				inv.from_data([])
				for i in inv.size():
					inv.add("meat", 9999)
				check(arena.backpack_full(), "backpack full")
				var lost0: int = arena.lost
				arena.debris.take(VoxelBody.BONE, 5)
				check(arena.lost == lost0 + 5 and arena._say_text.contains("full"), "full: what the vacuum takes is lost, and it says so")
				# enemies walk round the chests
				var c := _st("cabinet_a").global_position
				var out: Vector3 = VoxelArena.out_of_pillars(c + Vector3(0.1, 0, 0.05), 0.35)
				check(Vector2(out.x - c.x, out.z - c.z).length() > 0.4, "enemies kept out of the chests")
				inv.from_data([])
				step = 9
		9:
			print("INV done %d passed, %d failed" % [passed, failed])
			return true
	return false

# ---------------------------------------------------------------- co-op

func _coop() -> bool:
	var n = arena.net
	if step > 0 and step < 9 and not n.linked and not (role == "host" and step == 4):
		check(false, "co-op: the link went before the end (step %d, %d lying at the drop)" % [step, _lying_near(Vector3(-5, 0, -6), 3.5)])
		step = 9
	elif step == 0 and (not n.linked or (role == "guest" and not n._got_world)):
		if Time.get_ticks_msec() > 60000:          # (real time: --fixed-fps runs faster than that)
			print("INV FAIL never linked (%s)" % n.status_text)
			print("INV done %d passed, %d failed" % [passed, failed + 1])
			return true
		return false
	var inv: VoxelInventory = arena.inv
	if role == "host":
		match step:
			0:
				arena.frozen = true
				_clear()
				inv.from_data([])
				for st in arena.stash.list:
					st.inv.from_data([])
				arena.player.global_position = Vector3(-8, 0, 3)
				mark = t
				step = 1
			1:
				# the guest's 100 meat arrive in chest_a; then 40 go back out
				if _st("chest_a").inv.count("meat") == 100:
					check(true, "co-op: the guest's stack is in the host's chest")
					step = 2
				elif t - mark > 25.0:
					check(false, "co-op: the guest's stack never came (%d)" % _st("chest_a").inv.count("meat"))
					step = 2
			2:
				if _st("chest_a").inv.count("meat") == 60:
					check(true, "co-op: the guest took 40 back out of the host's chest")
					# the host's own move, for the guest to see
					_st("chest_b").inv.add("bone", 30)
					# a corpse by the guest for their vacuum
					_corpse_at(Vector3(6, 0, 4.4))
					mark = t
					step = 3
				elif t - mark > 30.0:
					check(false, "co-op: the guest's take never happened (%d)" % _st("chest_a").inv.count("meat"))
					step = 3
			3:
				# cubes dropped here for the guest's vacuum
				if t - mark > 1.0 and not v0.has("dropped"):
					v0.dropped = true
					arena.drop_cubes(Vector3(-6, 1.0, -6), Vector3.RIGHT, "blocks", 200, 12345)
					arena.stash.dropped(Vector3(-6, 1.0, -6), Vector3.RIGHT, "blocks", 200, 12345)
				var now_l := _lying_near(Vector3(-5, 0, -6), 3.5)
				v0.lying = maxi(int(v0.get("lying", 0)), now_l)
				# (dropped here, landed, and gone: the guest's vacuum took them in its game, here too; it may take them as
				# they land, so not all 200 need be seen lying at once)
				if t - mark > 5.0 and int(v0.lying) > 0 and now_l < 10:
					check(true, "co-op: the guest's vacuum cleared the cubes in the host's game too (up to %d were lying)" % v0.lying)
					mark = t
					step = 4
				elif t - mark > 30.0:
					check(false, "co-op: the guest's vacuum never cleared them here (%d lying)" % _lying_near(Vector3(-5, 0, -6), 3.5))
					step = 4
			4:
				if not n.linked or t - mark > 120.0:     # (till the guest's done and gone)
					step = 9
			9:
				print("INV done %d passed, %d failed" % [passed, failed])
				return true
	else:
		match step:
			0:
				inv.from_data([])
				inv.add("meat", 100)
				_stand_at(_st("chest_a"))
				mark = t
				step = 20
			20:
				if t - mark < 0.15:
					return false
				var st := _st("chest_a")
				arena._camera(0.0)
				arena._storage_step(0.0)
				_key(KEY_E)
				check(arena.inv_ui.storage == st, "co-op: the guest opens the host's chest")
				arena.inv_ui._layout()
				arena.inv_ui.click(1, 0, MOUSE_BUTTON_LEFT)
				arena.inv_ui.click(0, 0, MOUSE_BUTTON_LEFT)
				check(arena.inv_ui.cursor.is_empty() and inv.count("meat") == 0, "co-op: put in (gone from the guest's hand at once)")
				mark = t
				step = 1
			1:
				if _st("chest_a").inv.count("meat") == 100:
					check(true, "co-op: the guest's copy of the chest shows it (from the host)")
					# take 40: right click takes half (50), put 10 back one at a time
					arena.inv_ui.click(0, 0, MOUSE_BUTTON_RIGHT)
					mark = t
					step = 2
				elif t - mark > 15.0:
					check(false, "co-op: the chest never showed the stack")
					step = 9
			2:
				if int(arena.inv_ui.cursor.get("n", 0)) == 50:
					check(true, "co-op: half came back into the guest's hand from the host")
					for i in 10:
						arena.inv_ui.click(0, 0, MOUSE_BUTTON_RIGHT)
					arena.inv_ui.click(1, 0, MOUSE_BUTTON_LEFT)
					mark = t
					step = 3
				elif t - mark > 15.0:
					check(false, "co-op: the take never came back (%s)" % str(arena.inv_ui.cursor))
					step = 9
			3:
				if inv.count("meat") == 40 and _st("chest_a").inv.count("meat") == 60:
					check(true, "co-op: 40 in the guest's backpack, 60 in the chest: nothing made or lost")
					_key(KEY_E)
					mark = t
					step = 4
				elif t - mark > 15.0:
					check(false, "co-op: after the moves: backpack %d, chest %d" % [inv.count("meat"), _st("chest_a").inv.count("meat")])
					step = 4
			4:
				if _st("chest_b").inv.count("bone") == 30:
					check(true, "co-op: the host's move shows in the guest's chest")
					step = 5
					mark = t
				elif t - mark > 20.0:
					check(false, "co-op: the host's move never showed")
					step = 5
					mark = t
			5:
				# the corpse the host made by us: vacuum it
				var corpse: VoxelBody = null
				for b in arena.bodies:
					if not b.alive and b.global_position.distance_to(Vector3(6, 0, 4.4)) < 1.0:
						corpse = b
				if corpse and not v0.has("vac"):
					v0.vac = inv.total()
					v0.cubes = corpse.cubes_left()
					arena.pieces.vacuum(corpse.global_position + Vector3(0, 0.6, 0), 1.5)
				if v0.has("vac") and inv.total() >= int(v0.vac) + int(v0.cubes) - 2:
					check(true, "co-op: the corpse the guest vacuumed is in the guest's backpack (%d cubes)" % [inv.total() - int(v0.vac)])
					mark = t
					step = 6
				elif t - mark > 25.0:
					check(false, "co-op: the guest's corpse never counted (%d, %s)" % [inv.total(), str(v0)])
					step = 6
					mark = t
			6:
				# the host's dropped rubble: lying here too; vacuum it
				var spot := Vector3(-4.5, 0, -6)
				if not v0.has("seen") and _lying_near(spot, 3.5) >= 190:
					v0.seen = _lying_near(spot, 3.5)
					v0.rubble = inv.count("blocks")
					arena.player.global_position = Vector3(-4.5, 0, -3.0)
					arena.player.reset_physics_interpolation()
					_vacuum_at(spot)
					mark = t
				if v0.has("seen"):
					# swept round the spot (they're spread over a few metres)
					_look_at(spot + Vector3(sin((t - mark) * 2.5) * 1.6, 0, cos((t - mark) * 2.5) * 1.4))
					if t - mark > 6.0:
						arena.hold_suck = false
						check(true, "co-op: the host's dropped stack lies in the guest's game too (%d)" % v0.seen)
						check(inv.count("blocks") - int(v0.rubble) >= 190, "co-op: and the guest vacuumed it up (%d)" % (inv.count("blocks") - int(v0.rubble)))
						mark = t
						step = 7
				elif t - mark > 25.0:
					check(false, "co-op: the host's dropped stack never showed here (%d)" % _lying_near(spot, 3.5))
					step = 7
					mark = t
			7:
				if t - mark > 4.0:
					step = 9
			9:
				print("INV done %d passed, %d failed" % [passed, failed])
				return true
	return false
