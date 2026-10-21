extends SceneTree
## Stage 3, the bedroom (headless): walking through the door into it (it opens as you come), a safe room (an enemy
## doesn't go for you in here), the two beds' chests (yours, the spare / your mate's) with their padlocks hanging open,
## locking one with the code the wheels show (spun to hide it after), a wrong code not opening it and the right one
## springing it and opening the chest, a locked chest giving nothing, taking the padlock off and hanging it on another
## chest, the padlocks saved, lying in bed (health back faster, WASD gets you up), the wardrobe, the mirror only
## rendering near it, cubes dropped in the bedroom staying in it. With --host=CODE / --join=CODE (two copies, the
## host first): the chests named for each player, the guest's lock kept by the host (its code never sent to the
## guest), the host dialling it open, the guest lying in bed seen by the host, the enemies not going for the guest in
## the bedroom. Prints "BED ok/FAIL ..." and "BED done N passed, M failed". Owned by the voxel session.

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
	print("BED %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host"):
			role = "host"
		elif a.begins_with("--join"):
			role = "guest"
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _key(k: Key, down := true) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	arena._unhandled_input(e)

func _hold(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _st(id: String) -> VoxelStorage:
	return arena.stash.by_id[id]

func _place(p: Vector3, yaw: float, pitch: float) -> void:
	arena.player.global_position = p
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = yaw
	arena.look_pitch = pitch

# the wheels turned one click at a time (each tried) from where they are to code
func _dial(code: String) -> void:
	var lv: VoxelLockView = arena.lock_view
	for i in 4:
		var want := int(code[i])
		var guard := 0
		while lv.model.dials[i] != want and guard < 12:
			lv.turn(i, 1)
			guard += 1

func _clear() -> void:
	for b in arena.bodies:
		b.queue_free()
	arena.bodies.clear()

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if role == "":
		return _solo()
	return _coop()

func _solo() -> bool:
	var house: VoxelBedroom = arena.house
	match step:
		0:
			_clear()
			arena.frozen = true
			for st in arena.stash.list:
				st.inv.from_data([])
				st.set_lock(st.belongs > 0, false)      # (as new: an earlier run's save may have changed them)
			arena.inv.from_data([])
			check(house != null and house.is_inside_tree(), "the bedroom is there")
			var c1 := _st("bed_chest_1")
			var c2 := _st("bed_chest_2")
			check(c1.title == "Your chest" and c2.title == "Spare chest", "the beds' chests: yours and the spare (%s, %s)" % [c1.title, c2.title])
			check(c1.has_lock and not c1.locked and c2.has_lock and not c2.locked, "each with a padlock hanging open")
			check(c1.global_position.distance_to(VoxelBedroom.chest_spot(1)) < 0.01 and c1.global_position.z > VoxelBedroom.Z0 + VoxelBedroom.BED_L, "at the foot of its bed")
			# walk in through the door
			_place(Vector3(-2.17, 0, 19.5), PI, 0.0)
			_hold(KEY_W, true)
			mark = t
			step = 1
		1:
			if arena.player.global_position.z > 24.0 or t - mark > 6.0:
				_hold(KEY_W, false)
				check(arena.player.global_position.z > 24.0, "walked through the door into the bedroom (z %.1f)" % arena.player.global_position.z)
				check(house._door_k > 0.5, "the door opened as I came")
				# an enemy at the wall doesn't come for me in here
				arena.frozen = false
				var b := VoxelBody.new()
				arena.add_child(b)
				b.setup("grunt", arena._cube_m("grunt"), 1, arena._mat)
				b.position = Vector3(-2.2, 0, 19.0)
				b.speed = 1.5
				arena.bodies.append(b)
				v0.hp = arena.player_hp
				v0.b = b
				_place(Vector3(-2.17, 0, 23.2), PI, 0.0)
				mark = t
				step = 2
		2:
			if t - mark > 4.0:
				var b: VoxelBody = v0.b
				check(arena.net.targets().is_empty() and arena.player_hp == v0.hp and b.position.z < 21.5, "a safe room: the enemy doesn't come in or hurt me (%d health, it's at z %.1f)" % [arena.player_hp, b.position.z])
				_clear()
				arena.frozen = true
				_place(_st("bed_chest_1").front() + Vector3(0, 0, 0.9), 0.0, -0.7)
				mark = t
				step = 3
		3:
			if t - mark > 0.15:
				var c1 := _st("bed_chest_1")
				arena._camera(0.0)
				arena._storage_step(0.0)
				check(arena._near_st == c1 and arena._use_label.text.contains("L  padlock"), "at my chest: \"%s\"" % arena._use_label.text)
				_key(KEY_L)
				check(arena.lock_view.is_open() and arena.lock_view.storage == c1 and arena.lock_view.model != null, "L: its padlock up close")
				_dial("1234")
				arena.lock_view.shackle()
				check(c1.locked and c1.combo == "1234", "the shackle clicked shut: locked with the wheels' code (1234)")
				check(arena.lock_view.model.code() != "1234", "the wheels spun to hide it (now %s)" % arena.lock_view.model.code())
				check(arena.stash.take(c1, 0, -1, "cursor").is_empty() and not arena.stash.put(c1, 0, {"id": "meat", "n": 1}).is_empty(), "a locked chest: nothing in or out")
				_key(KEY_E)
				check(not arena.lock_view.is_open(), "E: done with it")
				arena._storage_step(0.0)
				check(arena._use_label.text.contains("unlock"), "\"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.lock_view.is_open() and arena.lock_then_chest and not arena.inv_ui.is_open(), "E at the locked chest: the padlock to dial, not the chest")
				_dial("9999")
				check(c1.locked, "a wrong code doesn't open it")
				_dial("1234")
				check(not c1.locked, "the right code springs it open")
				mark = t
				step = 4
		4:
			if t - mark > 1.0:
				var c1 := _st("bed_chest_1")
				check(arena.inv_ui.is_open() and arena.inv_ui.storage == c1, "then the chest opens")
				arena.close_inventory()
				# the padlock off, onto a chest in the arena
				_key(KEY_L)
				arena.lock_view.take_off()
				check(not c1.has_lock and arena.inv.count("padlock") == 1 and not arena.lock_view.is_open(), "R: the padlock off, into the backpack")
				arena.inv_ui.cursor = {"id": "padlock", "n": 1}
				arena.inv.remove("padlock", 1)
				arena.inv_ui.visible = true
				arena.inv_ui._layout()
				arena.inv_ui.click(-1, -1, MOUSE_BUTTON_LEFT)
				check(arena.inv_ui.cursor.get("id", "") == "padlock", "a padlock can't be dropped as cubes")
				arena.inv_ui.close()
				check(arena.inv.count("padlock") == 1, "(back in the backpack)")
				_place(_st("chest_a").front() + Vector3(0, 0, 0.9), 0.0, -0.7)
				mark = t
				step = 5
		5:
			if t - mark > 0.15:
				arena._camera(0.0)
				arena._storage_step(0.0)
				check(arena._use_label.text.contains("hang a padlock"), "at a chest without one: \"%s\"" % arena._use_label.text)
				_key(KEY_L)
				var ca := _st("chest_a")
				check(ca.has_lock and not ca.locked and arena.inv.count("padlock") == 0, "L hangs it on")
				# saved
				ca.combo = "5555"
				arena.stash._lock_set(ca, true, true)
				arena.stash.save()
				ca.set_lock(false, false)
				arena.stash.load_save()
				check(ca.has_lock and ca.locked and ca.combo == "5555" and not _st("bed_chest_1").has_lock, "the padlocks saved and loaded (locked, its code)")
				ca.set_lock(false, false)
				# lying in bed
				_place(Vector3(VoxelBedroom.BED_X[1] - 1.2, 0, 23.6), -PI * 0.5, -0.4)
				mark = t
				step = 6
		6:
			if t - mark > 0.15 and step == 6:
				arena._camera(0.0)
				arena._storage_step(0.0)
				check(arena._near_bed == 1 and arena._use_label.text.contains("lie down"), "at my bed: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(arena.lying == 1, "E: lying in it")
				arena.godmode = false
				arena.hurt_player(40.0)
				v0.hp = arena.player_hp
				mark = t
				step = 7
		7:
			if t - mark > 2.0:
				check(arena.player_hp >= v0.hp + 20.0, "health back fast in bed (%d -> %d in 2 s)" % [v0.hp, arena.player_hp])
				check(arena.player.global_position.distance_to(arena.house.lie_spot(1)) < 0.05, "on the mattress")
				_key(KEY_W)
				check(arena.lying == 0 and arena.player.global_position.distance_to(arena.house.up_spot(1)) < 0.1, "W: up, beside the bed")
				# the wardrobe
				_place(Vector3(VoxelBedroom.WARD_X, 0, VoxelBedroom.Z1 - 1.6), 0.0, -0.1)
				arena.look_yaw = PI
				mark = t
				step = 8
		8:
			if t - mark > 0.15 and step == 8:
				arena._camera(0.0)
				arena._storage_step(0.0)
				check(arena._near_ward, "at the wardrobe: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(house.ward_open, "E opens it")
				# the mirror renders only near it
				house.mirror._process(0.0)
				check(house.mirror._vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "the mirror renders near it")
				_place(Vector3(0, 0, 0), 0.0, 0.0)
				mark = t
				step = 9
		9:
			if t - mark > 0.15 and step == 9:
				arena._camera(0.0)
				house.mirror._process(0.0)
				check(house.mirror._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "and not from the arena")
				# cubes dropped in the bedroom stay there
				arena.drop_cubes(Vector3(-2.5, 1.2, 26.0), Vector3(0, 0, 1), "bone", 80, 77)
				mark = t
				step = 10
		10:
			if t - mark > 3.0:
				var d: VoxelDebris = arena.debris
				var n_in := 0
				for i in d._ln:
					if VoxelBedroom.in_house(d._lp[i]) and d._lp[i].z > VoxelBedroom.Z0:
						n_in += 1
				check(n_in == 80, "cubes dropped in the bedroom lie there (%d of 80)" % n_in)
				step = 99
		99:
			print("BED done %d passed, %d failed" % [passed, failed])
			return true
	return false

# ---------------------------------------------------------------- co-op

func _coop() -> bool:
	var n = arena.net
	if step > 0 and step < 99 and not n.linked and not (role == "host" and step == 6):
		check(false, "co-op: the link went before the end (step %d)" % step)
		step = 99
	elif step == 0 and (not n.linked or (role == "guest" and not n._got_world)):
		if Time.get_ticks_msec() > 60000:
			print("BED FAIL never linked (%s)" % n.status_text)
			print("BED done %d passed, %d failed" % [passed, failed + 1])
			return true
		return false
	if role == "host":
		match step:
			0:
				_clear()
				arena.frozen = true
				_place(Vector3(-8, 0, 0), 0.0, 0.0)
				mark = t
				step = 1
			1:
				if t - mark > 0.2:
					check(_st("bed_chest_1").title == "Your chest" and _st("bed_chest_2").title == "Mate's chest", "co-op, host: my chest and my mate's (%s, %s)" % [_st("bed_chest_1").title, _st("bed_chest_2").title])
				if _st("bed_chest_2").locked:
					var c2 := _st("bed_chest_2")
					check(c2.combo == "2468", "co-op: the guest locked their chest; the host keeps its code (%s)" % c2.combo)
					check(arena.stash.take(c2, 0, -1, "cursor").is_empty(), "co-op: the host can't take from it")
					_place(c2.front() + Vector3(0, 0, 0.9), 0.0, -0.7)
					mark = t
					step = 2
				elif t - mark > 30.0:
					check(false, "co-op: the guest's lock never came")
					step = 99
			2:
				if t - mark > 0.2:
					arena.open_lock(_st("bed_chest_2"), false)
					_dial("1111")
					check(_st("bed_chest_2").locked, "co-op: the host dialling a wrong code: still locked")
					_dial("2468")
					check(not _st("bed_chest_2").locked, "co-op: the host dials the right one: open")
					arena.close_lock()
					_place(Vector3(-8, 0, 0), 0.0, 0.0)          # (back out in the arena: a target)
					mark = t
					step = 3
			3:
				if n.other_lying == 2:
					check(true, "co-op: the guest lying in their bed, seen by the host")
					mark = t
					step = 4
				elif t - mark > 30.0:
					check(false, "co-op: the guest never lay down")
					step = 4
			4:
				# the guest standing in the bedroom: the enemies only go for the host
				if t - mark > 1.0 and VoxelBedroom.in_house(n._o_body.global_position) and n.other_lying == 0:
					var tg: Array = n.targets()
					check(tg.size() == 1, "co-op: the guest in the bedroom isn't a target (%d targets)" % tg.size())
					step = 6
					mark = t
				elif t - mark > 30.0:
					check(false, "co-op: the guest never stood in the bedroom")
					step = 6
			6:
				if not n.linked or t - mark > 120.0:
					step = 99
			99:
				print("BED done %d passed, %d failed" % [passed, failed])
				return true
	else:
		match step:
			0:
				check(_st("bed_chest_2").title == "Your chest" and _st("bed_chest_1").title == "Mate's chest", "co-op, guest: my chest is bed 2's")
				_place(_st("bed_chest_2").front() + Vector3(0, 0, 0.9), 0.0, -0.7)
				mark = t
				step = 1
			1:
				if t - mark > 0.2:
					var c2 := _st("bed_chest_2")
					arena._camera(0.0)
					arena._storage_step(0.0)
					_key(KEY_L)
					check(arena.lock_view.storage == c2, "co-op: the guest at their chest's padlock")
					_dial("2468")
					arena.lock_view.shackle()
					arena.close_lock()
					check(c2.locked and c2.combo == "", "co-op: locked (shown at once; the guest's game doesn't know the code)")
					mark = t
					step = 2
			2:
				if not _st("bed_chest_2").locked:
					check(true, "co-op: the host dialled it open, the guest sees it open")
					_place(Vector3(VoxelBedroom.BED_X[2] - 1.2, 0, 23.6), -PI * 0.5, -0.4)
					mark = t
					step = 3
				elif t - mark > 30.0:
					check(false, "co-op: never seen opened")
					step = 99
			3:
				if t - mark > 0.2 and step == 3:
					arena._camera(0.0)
					arena._storage_step(0.0)
					_key(KEY_E)
					check(arena.lying == 2, "co-op: the guest lies down in bed 2")
					mark = t
					step = 4
			4:
				if t - mark > 3.0:
					_key(KEY_W)
					_place(Vector3(0, 0, 27.0), 0.0, 0.0)
					mark = t
					step = 5
			5:
				if t - mark > 4.0:
					step = 99
			99:
				print("BED done %d passed, %d failed" % [passed, failed])
				return true
	return false
