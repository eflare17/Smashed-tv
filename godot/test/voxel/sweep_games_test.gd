extends SceneTree
## The bug sweep's games room fixes, each checked (headless). The library: our hidden copy of the test cartridge listed
## once; two systems' games of one name both on the shelf (a .zip of one still the same game); a .zip that can't be
## read leaves nothing behind, an empty cache is taken out again, a replaced .zip's new game is the one that loads;
## E at the plaque with no file picker looks in the folder again; more than the bookcase holds left off (no two cases
## in one spot). Playing: a case in your hands goes back when you leave the room (or look down from above); the linked
## host's couch line says player 1; a game left running with nobody in the room ejects itself (saved); the TV's glow
## stays off after it's switched off; the glow is the picture's average, not its middle; a guest's left stick is the
## d-pad (with a pad connected). Prints "SWG ok/FAIL ..." and "SWG done N passed, M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var v0 := {}
var dir := ""
var made := []                  # (the files this test put in the games folder: taken away after)

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("SWG %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	dir = ProjectSettings.globalize_path("user://games")
	DirAccess.make_dir_recursive_absolute(dir)
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _g() -> VoxelGamesRoom:
	return arena.games

func _cart() -> PackedByteArray:
	return FileAccess.get_file_as_bytes("res://assets/voxel/retro/test_cart.md")

func _put(fn: String, data: PackedByteArray) -> String:
	var p := dir.path_join(fn)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(data)
	f = null
	made.append(p)
	return p

func _zip(fn: String, inner: String, data: PackedByteArray) -> String:
	var p := dir.path_join(fn)
	var z := ZIPPacker.new()
	z.open(p)
	z.start_file(inner)
	z.write_file(data)
	z.close_file()
	z.close()
	made.append(p)
	return p

func _clear() -> void:
	for p in made:
		DirAccess.remove_absolute(p)
	made.clear()
	for f in DirAccess.get_files_at(dir.path_join(".unzipped")):
		if f.begins_with("SWG"):
			DirAccess.remove_absolute(dir.path_join(".unzipped").path_join(f))

func _names() -> Array:
	var out := []
	for e in _g().library:
		out.append("%s/%s" % [e.name, e.sys])
	return out

func _in_room() -> void:
	arena.player.global_position = Vector3(-9.7, 0, 27.0)
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()

func _out_of_room() -> void:
	arena.player.global_position = Vector3(-9.7, 0, 15.0)
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()

func _state_path() -> String:
	var tv: VoxelRetroTV = _g().tv
	var was: Dictionary = tv.game
	tv.game = _g().library[0]
	var st := tv._state_file()
	tv.game = was
	return st

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	var g := _g()
	match step:
		0:
			arena.frozen = true
			for b in arena.bodies:
				b.queue_free()
			arena.bodies.clear()
			_library()
			_pad_on()
			mark = t
			step = 1
		1:
			if t - mark > 0.1:
				_pad_check()
				# (playing) a case taken in the room, then out of the door
				_in_room()
				g.take(0)
				v0.took = g.held == 0
				_out_of_room()
				mark = t
				step = 2
		2:
			if t - mark > 0.1:
				check(v0.took and g.held == -1 and (g._cases[0] as Node3D).visible and g._held_node == null, "a case in your hands goes back on the shelf when you leave the room (#70)")
				_in_room()
				g.take(0)
				arena.top_down = true
				mark = t
				step = 3
		3:
			if t - mark > 0.1:
				check(g.held == -1 and (g._cases[0] as Node3D).visible, "... and when you look down from above (#70)")
				arena.top_down = false
				_in_room()
				g.take(0)
				g.insert(0)
				check(g.tv.playing(), "the test cartridge on")
				# the linked host's couch line
				var net = arena.net
				var r0: String = net.role
				var l0: bool = net.linked
				net.role = "host"
				net.linked = true
				var l2 := g.line("couch:2")
				var l1 := g.line("couch:1")
				net.role = r0
				net.linked = l0
				g.sit(2)
				var port: int = g.tv.player_port
				g.get_up()
				check(not l2.ends_with("(player 2)") and l2.contains("player 1") and l1 == l2 and port == 0, "the linked host on the right-hand seat is told player 1, and is player 1 (\"%s\", port %d) (#68)" % [l2, port])
				mark = t
				step = 4
		4:
			if t - mark > 0.6:
				var tv: VoxelRetroTV = g.tv
				v0.had_frame = tv.last_frame != null
				g.eject()
				check(v0.had_frame and tv.last_frame == null, "switched off: the last picture let go (#65)")
				mark = t
				step = 5
		5:
			if t - mark > 0.6:
				check(g.tv._glow.light_energy == 0.0, "the TV's glow stays off after it's switched off (%.2f) (#65)" % g.tv._glow.light_energy)
				_glow_check()
				# a game left running with nobody in the room
				_in_room()
				g.take(0)
				g.insert(0)
				DirAccess.remove_absolute(_state_path())
				mark = t
				step = 6
		6:
			if t - mark > 0.2:
				check(g.tv.playing() and g._away_t == 0.0, "in the room: the game keeps running")
				_out_of_room()
				mark = t
				step = 7
		7:
			if t - mark > 0.3:
				check(g.tv.playing() and g._away_t > 0.0 and g._away_t < 1.0, "just out of the room: still running (%.2f s away)" % g._away_t)
				g._away_t = VoxelGamesRoom.AWAY - 0.05
				mark = t
				step = 8
		8:
			if t - mark > 0.3:
				check(not g.tv.playing() and g.inserted == -1 and (g._cases[0] as Node3D).visible and FileAccess.file_exists(_state_path()), "left running a minute with nobody in the room: ejected, where you were saved (#71)")
				DirAccess.remove_absolute(_state_path())
				_clear()
				g.scan()
				DirAccess.remove_absolute(ProjectSettings.globalize_path("user://swg_test.json"))
				step = 99
		99:
			print("SWG done %d passed, %d failed" % [passed, failed])
			return true
	return false

# the library's fixes (#66, #119, #121, #64, #122)
func _library() -> void:
	var g := _g()
	_clear()
	var cart := _cart()
	_put("SWG Same (USA).md", cart)
	_put("SWG Same (USA).sfc", cart)
	_zip("SWG Same (USA).zip", "SWG Same (USA).md", cart)
	# a .zip packed a way that can't be read here (its method made LZMA)
	var bad := _zip("SWG Bad.zip", "SWG Bad.md", cart)
	var by := FileAccess.get_file_as_bytes(bad)
	by[8] = 14
	for i in by.size() - 4:
		if by[i] == 0x50 and by[i + 1] == 0x4b and by[i + 2] == 1 and by[i + 3] == 2:
			by[i + 10] = 14
	var fb := FileAccess.open(bad, FileAccess.WRITE)
	fb.store_buffer(by)
	fb = null
	_zip("SWG Swap.zip", "SWG Swap.md", cart)
	g.scan()
	var names := _names()
	var builtins := 0
	var dotted := false
	for e in g.library:
		if String(e.path).get_file() == ".builtin_test_cart.md":
			builtins += 1
		if String(e.name).begins_with("."):
			dotted = true
	check(builtins == 1 and not dotted and names[0] == "Smashed Test Cart/md", "our hidden copy of the test cartridge listed once, no dotted names (%s) (#66)" % ", ".join(names))
	check(names.has("SWG Same/md") and names.has("SWG Same/snes") and names.count("SWG Same/md") == 1, "two systems' games of one name both on the shelf, its .zip still the same game (#119)")
	var bad_cache := dir.path_join(".unzipped/SWG Bad.md")
	check(not names.has("SWG Bad/md") and not FileAccess.file_exists(bad_cache), "a .zip that can't be read: not on the shelf, no empty game left in the cache (#121)")
	var swap := dir.path_join(".unzipped/SWG Swap.md")
	check(FileAccess.get_file_as_bytes(swap).size() == cart.size(), "a .zip's game taken out into the cache")
	# an empty cache (an earlier failed take-out) is taken out again
	var fe := FileAccess.open(swap, FileAccess.WRITE)
	fe = null
	g.scan()
	check(FileAccess.get_file_as_bytes(swap).size() == cart.size() and _names().has("SWG Swap/md"), "an empty cached game is taken out again (#121)")
	# the .zip replaced by another game of the same name: the new one's what loads
	var other := PackedByteArray()
	other.resize(4096)
	other.fill(0x55)
	_zip("SWG Swap.zip", "SWG Swap.md", other)
	var rc := OS.execute("touch", ["-d", "2001-01-01 00:00", swap])
	if rc == 0:
		g.scan()
		check(FileAccess.get_file_as_bytes(swap) == other, "a replaced .zip (newer than its cache): its new game taken out (#121)")
	else:
		print("SWG skip the replaced .zip (no touch here)")
	_clear()
	# E at the plaque with no file picker: what's been dropped in the folder since comes onto the shelf
	g.scan()
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		_put("SWG Dropped In.md", cart)
		arena._say_text = ""
		g.add_games()
		check(_names().has("SWG Dropped In/md") and arena._say_text.contains("1 game added"), "no file picker: E at the plaque again looks in the folder (\"%s\") (#64)" % arena._say_text)
		_clear()
	else:
		print("SWG skip the no-file-picker plaque (this display has one)")
	# more than the bookcase holds: left off, no two cases in one spot (the game in the console kept, though past it)
	_put("SWG Zed.md", cart)
	g.scan()
	var zed := dir.path_join("SWG Zed.md")
	g.take(g._index_of(zed))
	g.insert(g._index_of(zed))
	var many := VoxelGamesRoom.CASE_ROWS * VoxelGamesRoom.PER_ROW + 5
	for i in many:
		_put("SWG Many %03d.md" % i, cart)
	g.scan()
	var spots := {}
	for cn in g._cases:
		if (cn as Node3D).visible:
			var p: Vector3 = (cn as Node3D).position
			spots["%d,%d,%d" % [roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000)]] = true
	var cap := VoxelGamesRoom.CASE_ROWS * VoxelGamesRoom.PER_ROW
	check(g.library.size() == cap + 1 and g._cases.size() == cap + 1 and spots.size() == cap and g._left_out == many + 2 - cap - 1, "%d games: %d on the shelf, each its own spot (%d), %d left off (#122)" % [many + 2, g.library.size(), spots.size(), g._left_out])
	check(g.inserted >= 0 and String(g.library[g.inserted].path) == zed and g.tv.playing(), "... the game in the console kept, though past a full shelf (%d)" % g.inserted)
	g.eject()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VoxelRetroTV.SAVES).path_join(zed.get_file().md5_text() + ".state"))
	_clear()
	g.scan()
	check(g.library.size() == 1 and g._left_out == 0, "all taken away again: our test cartridge alone")

# a pad's left stick held left and down (the guest's buttons, sent to the host): only with a pad connected (none headless)
func _pad_on() -> void:
	for a in [[JOY_AXIS_LEFT_X, -1.0], [JOY_AXIS_LEFT_Y, 1.0]]:
		var e := InputEventJoypadMotion.new()
		e.device = 0 if Input.get_connected_joypads().is_empty() else Input.get_connected_joypads()[0]
		e.axis = a[0]
		e.axis_value = a[1]
		Input.parse_input_event(e)

func _pad_check() -> void:
	if Input.get_connected_joypads().is_empty():
		print("SWG skip a guest's left stick (#67): no pad connected here")
	else:
		var bits := _g().tv.my_buttons()
		var want := (1 << VoxelRetroTV.LEFT) | (1 << VoxelRetroTV.DOWN)
		check(bits & want == want and bits & ((1 << VoxelRetroTV.RIGHT) | (1 << VoxelRetroTV.UP)) == 0, "a guest's left stick is the d-pad (bits %d) (#67)" % bits)
	for a in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var e := InputEventJoypadMotion.new()
		e.device = 0 if Input.get_connected_joypads().is_empty() else Input.get_connected_joypads()[0]
		e.axis = a
		e.axis_value = 0.0
		Input.parse_input_event(e)

# the glow is the whole picture's colour, not the few pixels in its middle (#123)
func _glow_check() -> void:
	var tv: VoxelRetroTV = _g().tv
	var dark := Image.create(320, 224, false, Image.FORMAT_RGB8)
	dark.fill(Color.BLACK)
	dark.fill_rect(Rect2i(156, 108, 8, 8), Color.WHITE)
	tv.last_frame = dark
	tv._glow_t = 0.0
	tv._glow_light(0.01)
	var e_dark := tv._glow.light_energy
	var light := Image.create(320, 224, false, Image.FORMAT_RGB8)
	light.fill(Color.WHITE)
	light.fill_rect(Rect2i(156, 108, 8, 8), Color.BLACK)
	tv.last_frame = light
	tv._glow_t = 0.0
	tv._glow_light(0.01)
	var e_light := tv._glow.light_energy
	var halves := Image.create(320, 224, false, Image.FORMAT_RGB8)
	halves.fill(Color.RED)
	halves.fill_rect(Rect2i(160, 0, 160, 224), Color.BLUE)
	tv.last_frame = halves
	tv._glow_t = 0.0
	tv._glow_light(0.01)
	var c := tv._glow.light_color
	tv.last_frame = null
	tv._glow.light_energy = 0.0
	check(e_dark < 0.45 and e_light > 1.5 and absf(c.r - c.b) < 0.05 and c.r > c.g, "the glow is the picture's average colour, not its middle (dark %.2f, light %.2f, red|blue %s) (#123)" % [e_dark, e_light, str(c)])
