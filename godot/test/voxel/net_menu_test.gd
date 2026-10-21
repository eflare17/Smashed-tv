extends SceneTree
## The online menu (headless): O opens it (the mouse free, walking off while you type), Esc closes it; a room code
## picked out of a pasted message; HOST A GAME hosts a new 4-letter room (shown big, the button says so), LEAVE goes
## back to playing alone; the last room joined offered next time. With --host / --join (two copies, the host first),
## done the way a player does it, with the menu's buttons: the host presses HOST DIRECT, the guest types the address
## in the code box and presses JOIN, and they're playing together. Prints "MENU ok/FAIL ..." and "MENU done N passed,
## M failed". Owned by the voxel session.

var arena: Node
var t := 0.0
var step := 0
var mark := 0.0
var passed := 0
var failed := 0
var role := ""
var room := ""                  # --room=CODE: the internet way (HOST A GAME with that code / JOIN with it)

var _once := {}
func check(ok: bool, what: String) -> void:
	if _once.has(what):
		return
	_once[what] = true
	if ok:
		passed += 1
	else:
		failed += 1
	print("MENU %s %s" % ["ok" if ok else "FAIL", what])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--as-host":
			role = "host"
		elif a == "--as-guest":
			role = "guest"
		elif a.begins_with("--room="):
			room = a.trim_prefix("--room=")
	arena = load("res://scripts/voxel/arena/voxel_arena.tscn").instantiate()
	root.add_child(arena)

func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	arena.net_menu._unhandled_input(e)
	arena._unhandled_input(e)

func _process(dt: float) -> bool:
	t += dt
	if t < 1.0:
		return false
	var m: VoxelNetMenu = arena.net_menu
	var n: VoxelNet = arena.net
	if role == "":
		match step:
			0:
				arena.frozen = true
				check(m._btn.visible and m._btn.text == "ONLINE (O)", "an ONLINE (O) button on screen")
				_key(KEY_O)
				check(m.is_open() and m._panel.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "O opens PLAY ONLINE, the mouse free")
				Input.parse_input_event(_press(KEY_W, true))
				mark = t
				v_pos = arena.player.global_position
				step = 1
			1:
				if t - mark > 0.5:
					Input.parse_input_event(_press(KEY_W, false))
					check(arena.player.global_position.distance_to(v_pos) < 0.05, "typing in it doesn't walk you about")
					check(VoxelNetMenu.code_in("join me, the code's k7qd!") == "K7QD" and VoxelNetMenu.code_in("  PXR2 ") == "PXR2" and VoxelNetMenu.code_in("192.168.1.20") == "192.168.1.20" and VoxelNetMenu.code_in("hello") == "", "a room code picked out of a pasted message (or an address)")
					m.host()
					check(n.role == "host" and n.code.length() == 4 and m._code_big.text == n.code and m._host_b.text == "HOST A NEW ROOM" and m._leave_b.visible, "HOST A GAME: room %s, shown big" % n.code)
					m._on_leave()
					check(n.role == "" and not m._leave_b.visible, "LEAVE GAME: alone again")
					m.join("ZZ9Q")
					check(n.role == "guest" and n.code == "ZZ9Q", "JOIN with a code")
					m._on_leave()
					_key(KEY_ESCAPE)
					check(not m.is_open(), "Esc closes it")
					m._code_in.text = ""
					DisplayServer.clipboard_set("")
					m.open()
					check(m._code_in.text == "ZZ9Q", "next time, the last room joined is in the box (\"%s\")" % m._code_in.text)
					m.close()
					DirAccess.remove_absolute(ProjectSettings.globalize_path(VoxelNetMenu.CFG))
					step = 99
			99:
				print("MENU done %d passed, %d failed" % [passed, failed])
				return true
		return false
	match step:
		0:
			arena.frozen = true
			if role == "host" and room != "":
				m.open()
				m.host(room)
				check(n.role == "host" and m._code_big.text == room, "host: HOST A GAME, room %s" % room)
			elif role == "host":
				m.open()
				m._direct_b.pressed.emit()
				check(n.role == "host" and m._code_big.text == VoxelNetMenu.my_address(), "host: HOST DIRECT, your address shown (%s)" % m._code_big.text)
			else:
				m.open()
				m._code_in.text = room if room != "" else "127.0.0.1"
				m._join_b.pressed.emit()
				check(n.role == "guest", "guest: the address typed, JOIN pressed")
			mark = t
			step = 1
		1:
			if n.linked and (role == "host" or n._got_world):
				check(true, "%s: playing together (%s)" % [role, n.status_text])
				check(m._btn.text.begins_with("ONLINE: "), "the button says so: \"%s\"" % m._btn.text)
				mark = t
				step = 2
			elif Time.get_ticks_msec() > 60000:
				check(false, "never linked (%s)" % n.status_text)
				step = 99
		2:
			if (role == "guest" and t - mark > 3.0) or (role == "host" and (not n.linked or t - mark > 60.0)):
				step = 99
		99:
			print("MENU done %d passed, %d failed" % [passed, failed])
			return true
	return false

var v_pos := Vector3.ZERO

func _press(k: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	return e
