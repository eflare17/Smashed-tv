extends SceneTree
## Stage 7, the games room (headless): in through its door in the arena's south wall, a safe room; the library (our
## test cartridge, game files of each system, a .zip of one, tidy names, anything else left out); a console off the wall
## onto the table; a case off the shelf into your hands and back; a Mega Drive game put in with the Super Nintendo on
## the table (the Mega Drive comes down), the TV on, the emulator running at its own frame rate, the picture on the
## screen, its sound playing; on the couch the keys are the controller (B turns the test cartridge red); up again;
## ejected (where you were saved) and put back in. With --host / --join (two copies, the host first): the host's TV
## picture on the guest's TV, the guest on the couch as player 2 (their buttons at the host's console), the guest
## can't put games in. Prints "GAMES ok/FAIL ..." and "GAMES done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var role := ""
var v0 := {}
const FAKE := ["Super_Smash_TV_(USA,_Europe).md", "Rally (Europe) [!].sfc", "Tennis.sms", "Pocket.gg", "notes.txt"]

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("GAMES %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--host"):
			role = "host"
		elif a.begins_with("--join"):
			role = "guest"
	if role == "":
		var dir := ProjectSettings.globalize_path("user://games")
		DirAccess.make_dir_recursive_absolute(dir)
		for f in FAKE:
			DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets/voxel/retro/test_cart.md"), dir.path_join(f))
		var z := ZIPPacker.new()
		z.open(dir.path_join("Zipped Game.zip"))
		z.start_file("Zipped Game (USA).md")
		z.write_file(FileAccess.get_file_as_bytes("res://assets/voxel/retro/test_cart.md"))
		z.close_file()
		z.close()
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _cleanup() -> void:
	var dir := ProjectSettings.globalize_path("user://games")
	for f in FAKE + ["Zipped Game.zip", ".unzipped/Zipped Game.md"]:
		DirAccess.remove_absolute(dir.path_join(f))

# a key pressed (E: straight to the game, once) or held down / let go (the console's buttons: Input's state)
func _key(k: Key, down := true) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	if k == KEY_E:
		arena._unhandled_input(e)
	else:
		Input.parse_input_event(e)

func _look(from: Vector3, at: Vector3) -> void:
	arena.player.global_position = from
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	var to := at - (from + Vector3(0, 1.65, 0))
	arena.look_yaw = atan2(-to.x, -to.z)
	arena.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())

func _near() -> String:
	arena._camera(0.0)
	arena._storage_step(0.0)
	return arena._near_game

func _g() -> VoxelGamesRoom:
	return arena.games

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	if role == "":
		return _solo()
	return _coop()

func _solo() -> bool:
	var g := _g()
	match step:
		0:
			arena.frozen = true
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			check(VoxelRetroTV.available(), "the console plugin (RetroCore) is there")
			check(VoxelArena.safe(Vector3(-9.7, 0, 26)) and not VoxelArena.safe(Vector3(-9.7, 0, 15)), "the games room is safe from the enemies")
			# walk in through its door
			arena.player.global_position = Vector3((VoxelGamesRoom.DOOR_X0 + VoxelGamesRoom.DOOR_X1) * 0.5, 0, 19.5)
			arena.player.reset_physics_interpolation()
			arena.look_yaw = PI
			arena.look_pitch = 0.0
			Input.parse_input_event(_ev(KEY_W, true))
			mark = t
			step = 1
		1:
			if arena.player.global_position.z > 23.5 or t - mark > 5.0:
				Input.parse_input_event(_ev(KEY_W, false))
				check(arena.player.global_position.z > 23.5, "in through the games room's door (z %.1f)" % arena.player.global_position.z)
				# the library
				var names := []
				for e in g.library:
					names.append("%s/%s" % [e.name, e.sys])
				check(g.library.size() == 6 and names[0] == "Smashed Test Cart/md", "the library: our test cartridge and 5 games (%s)" % ", ".join(names))
				check(names.has("Super Smash TV/md") and names.has("Rally/snes") and names.has("Tennis/sms") and names.has("Pocket/gg") and names.has("Zipped Game/md"), "each system by its file, names tidied, a .zip opened, a .txt left out")
				check(g._cases.size() == 6, "a case on the shelf for each")
				# the Super Nintendo onto the table
				_look(Vector3(-12.6, 0, float(VoxelGamesRoom.SHELF_Z.snes)), g._wall_spot("snes"))
				mark = t
				step = 2
		2:
			if t - mark > 0.2:
				var n := _near()
				check(n == "console:snes" and arena._use_label.text.contains("Super Nintendo on the table"), "at the Super Nintendo on the wall: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				mark = t
				step = 3
		3:
			if t - mark > 1.0:
				check(g.table_sys == "snes" and g._consoles.snes.position.distance_to(VoxelGamesRoom.TABLE + Vector3(0, 0, 0.05)) < 0.01 and g._consoles.md.position.distance_to(g._wall_spot("md")) < 0.01, "E: it comes down onto the table, the Mega Drive back up on the wall")
				# a case off the shelf
				var cn: Node3D = g._cases[0]
				_look(Vector3(-6.6, 0, cn.position.z), cn.position)
				mark = t
				step = 4
		4:
			if t - mark > 0.2:
				var n := _near()
				check(n == "case:0" and arena._use_label.text.contains("take Smashed Test Cart"), "at a case on the shelf: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(g.held == 0 and not (g._cases[0] as Node3D).visible and g._held_node != null, "E: it's in your hands (open, the cartridge in it)")
				_near()
				check(arena._use_label.text.contains("put Smashed Test Cart back"), "with it: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(g.held == -1 and (g._cases[0] as Node3D).visible, "E again: back on the shelf")
				_key(KEY_E)
				_look(Vector3(-9.7, 0, 27.0), VoxelGamesRoom.TABLE)
				mark = t
				step = 5
		5:
			if t - mark > 0.2:
				var n := _near()
				check(n == "table" and arena._use_label.text.contains("put Smashed Test Cart in") and arena._use_label.text.contains("Mega Drive comes down"), "at the table with it: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(g.table_sys == "md" and g.tv.playing() and g.inserted == 0, "E: the Mega Drive comes down, the cartridge goes in, the TV's on (%s)" % g.tv.core.get_core_name())
				v0.f0 = g.tv.frames_run
				v0.t0 = t
				mark = t
				step = 6
		6:
			if t - mark > 2.0:
				var tv: VoxelRetroTV = g.tv
				var fps := (tv.frames_run - int(v0.f0)) / (t - float(v0.t0))
				check(absf(fps - tv.core.get_fps()) < 3.0, "the emulator at the Mega Drive's own rate (%.1f frames a second, %.2f)" % [fps, tv.core.get_fps()])
				check(tv.last_frame != null and tv.last_frame.get_width() == 320 and tv.last_frame.get_height() == 224 and float(tv._mat.get_shader_parameter("on")) == 1.0, "its picture on the TV's screen (320 x 224)")
				check(tv._audio.playing and tv._playback != null, "its sound out of the TV")
				var blue := 0
				for x in range(0, 320, 4):
					var c := tv.last_frame.get_pixel(x, 10)
					if c.b > 0.8 and c.r < 0.2:
						blue += 1
				check(blue > 10 and blue < 70, "the test cartridge's checkerboard (%d of 80 blue along a line)" % blue)
				_look(Vector3(-10.25, 0, 25.6), Vector3(-10.25, 0.5, VoxelGamesRoom.COUCH_Z))
				mark = t
				step = 7
		7:
			if t - mark > 0.2:
				var n := _near()
				check(n == "couch:1" and arena._use_label.text.contains("sit down and play"), "at the couch: \"%s\"" % arena._use_label.text)
				_key(KEY_E)
				check(g.seated == 1 and g.tv.player_port == 0, "E: sat down, the controller in your hands")
				_key(KEY_K, true)
				v0.pos = arena.player.global_position
				mark = t
				step = 8
		8:
			if t - mark > 0.5:
				var img: Image = g.tv.last_frame
				var red := 0
				for x in range(0, 320, 4):
					var c := img.get_pixel(x, 10)
					if c.r > 0.8 and c.b < 0.2 and c.g < 0.2:
						red += 1
				check(red > 10, "K (the B button): the test cartridge's squares go red (%d of 80 along a line)" % red)
				check(arena.player.global_position.distance_to(v0.pos) < 0.05, "the keys play the game, not walk you off the couch")
				_key(KEY_K, false)
				_key(KEY_E)
				check(g.seated == 0 and g.tv.player_port == -1, "E: up off the couch")
				g.eject()
				var st := g.tv._state_file()
				check(not g.tv.playing() and g.inserted == -1 and (g._cases[0] as Node3D).visible, "ejected: the TV off, the case back on the shelf")
				g.tv.game = g.library[0]
				var st_path := g.tv._state_file()
				g.tv.game = {}
				check(FileAccess.file_exists(st_path), "where you were saved (%s)" % st_path.get_file())
				g.take(0)
				g.insert(0)
				check(g.tv.playing(), "put back in, it carries on")
				g.eject()
				_cleanup()
				DirAccess.remove_absolute(st_path)
				step = 99
		99:
			print("GAMES done %d passed, %d failed" % [passed, failed])
			return true
	return false

func _ev(k: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	return e

func _coop() -> bool:
	var n = arena.net
	var g := _g()
	if step > 0 and step < 99 and not n.linked and not (role == "host" and step == 9):
		check(false, "co-op: the link went before the end (step %d)" % step)
		step = 99
	elif step == 0 and (not n.linked or (role == "guest" and not n._got_world)):
		if Time.get_ticks_msec() > 60000:
			print("GAMES FAIL never linked (%s)" % n.status_text)
			print("GAMES done %d passed, %d failed" % [passed, failed + 1])
			return true
		return false
	if role == "host":
		match step:
			0:
				arena.frozen = true
				g.take(0)
				g.insert(0)
				check(g.tv.playing(), "co-op: the host's test cartridge on")
				mark = t
				step = 1
			1:
				if g.tv.remote_buttons & (1 << VoxelRetroTV.B):
					check(true, "co-op: the guest's B button at the host's console (player 2)")
					mark = t
					step = 9
				elif t - mark > 40.0:
					check(false, "co-op: the guest's buttons never came")
					step = 9
					mark = t
			9:
				if not n.linked or t - mark > 60.0:
					g.eject()
					step = 99
			99:
				print("GAMES done %d passed, %d failed" % [passed, failed])
				return true
	else:
		match step:
			0:
				if g._remote_name != "" and g.tv.last_frame != null:
					check(g._remote_name == "Smashed Test Cart" and float(g.tv._mat.get_shader_parameter("on")) == 1.0, "co-op: the host's TV picture on the guest's TV (%d x %d)" % [g.tv.last_frame.get_width(), g.tv.last_frame.get_height()])
					check(not g.tv.playing(), "co-op: the guest's own console isn't running")
					var before := g.held
					g.use("case:0")
					check(g.held == before and arena._say_text.contains("mate's games room"), "co-op: the guest can't put games in")
					g.sit(2)
					_key(KEY_K, true)
					mark = t
					step = 1
				elif t - mark > 30.0 and t > 30.0:
					check(false, "co-op: the host's TV never showed (%s)" % g._remote_name)
					step = 1
			1:
				if t - mark > 3.0:
					_key(KEY_K, false)
					g.get_up()
					step = 99
			99:
				print("GAMES done %d passed, %d failed" % [passed, failed])
				return true
	return false
