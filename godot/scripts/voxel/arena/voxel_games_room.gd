class_name VoxelGamesRoom
extends Node3D
## The retro games room (the owner, 21 Oct, Stage 7: "couch + TV area with all the consoles on the wall; pick a system
## and it pops up on the table; physically pull game cases off a shelf, open them and play; built-in emulator for Mega
## Drive games, Smash TV etc."), west of the bedroom through its own door in the arena's south wall.
##
## A big rear-projection TV against the back wall (VoxelRetroTV plays the games on it), a coffee table in front of it,
## a couch facing it (two seats: player 1 left, player 2 right), the consoles on shelves on the west wall (Mega Drive,
## Super Nintendo, Master System, Game Gear), a bookcase of game cases on the east wall, a retro carpet, posters, a lamp.
## E at a console on the wall: it comes down onto the table (the one there goes back up). E at a case: it comes off the
## shelf into your hands and opens (the cartridge inside). E at the console on the table with a case in your hands: in
## it goes and the TV comes on (the right console comes down by itself if it's another one's game). E on the couch: sit
## down, and your keys or pad are the controller; E or Esc gets you up. E at the console while it plays: eject (where
## you were is saved; next time it carries on). No games come with it but our own test cartridge: E at the ADD GAMES
## plaque picks game files from your PC (or a .zip of one), or drop them in the games folder (next to the game's exe,
## or the game's data folder). A safe room like the bedroom.
##
## Co-op: the room and its console are the host's. Their TV's picture goes to the guest fifteen times a second (a small
## JPEG, unreliable); a guest on the couch is player 2 (their buttons go to the host's console); the guest can't put
## games in (they're the host's files). Network message "R" (the console on the table, what's on, player 2's
## buttons), and a binary 84 for the pictures. Owned by the voxel session.

const X0 := -14.2
const X1 := -5.2                # (the bedroom's west wall is this one's east wall)
const Z0 := 22.5
const Z1 := 30.2
const H := 2.7
const DOOR_X0 := -10.45         # the doorway in the arena's south wall
const DOOR_X1 := -9.0
const DOOR_H := 2.1
const WALL := 0.25
const TV_X := -9.7
const TV_SCREEN := Vector3(-9.7, 1.0, 29.30)       # the picture's middle (just in front of the set's face)
const TABLE := Vector3(-9.7, 0.42, 28.15)          # the coffee table's top middle
const COUCH_Z := 26.35
const SEAT_X := {1: -10.25, 2: -9.15}
const SHELF_X := -14.05                            # the console shelves (west wall)
const SHELF_Z := {"md": 24.0, "snes": 25.4, "sms": 26.8, "gg": 28.2}
const SHELF_Y := 1.25
const CASE_X := -5.52                              # the bookcase (east wall): its front face ...
const CASE_Z0 := 24.0                              # ... from here ...
const CASE_LEN := 4.6                              # ... along z
const CASE_ROWS := 5
const PER_ROW := 60
const BUILTIN := "res://assets/voxel/retro/test_cart.md"
const GAMES := "user://games"

var arena: Node3D
var tv: VoxelRetroTV
var ceiling: Node3D
var library := []               # [{path, name, sys}]
var table_sys := "md"           # the console on the table
var held := -1                  # the case in this player's hands (library index), -1 none
var inserted := -1              # the cartridge in the console (library index), -1 none
var seated := 0                 # the seat this player's on (0: standing)
var _consoles := {}             # sys -> its model
var _cases := []                # per library entry: its case node (on the shelf)
var _case_root: Node3D
var _held_node: Node3D
var _held_k := 0.0
var _moving := {}               # sys -> [from, to, t] (a console flying to or from the table)
var _add_plaque: Node3D
var _mats := {}
const TV_HZ := 15.0             # (co-op) the host's TV pictures a second to the guest
var _tv_t := 0.0
var _pad_sent := -1
var _remote_name := ""          # (a guest) what's on the host's TV
var _was_role := ""

static func in_room(p: Vector3) -> bool:
	return p.z > 21.6 and p.x > X0 - 0.3 and p.x < X1 + 0.05 and p.z < Z1 + 0.3

## Where the games folder is (next to the exe in a build, the game's data folder otherwise): every place looked in.
static func game_dirs() -> Array:
	var out := [ProjectSettings.globalize_path(GAMES)]
	if not OS.has_feature("editor"):
		out.append(OS.get_executable_path().get_base_dir().path_join("games"))
	return out

func setup(arena_: Node3D) -> void:
	arena = arena_
	_shell()
	_furniture()
	tv = VoxelRetroTV.new()
	add_child(tv)
	tv.position = TV_SCREEN
	tv.setup(arena, Vector2(1.44, 1.08))
	for s in SHELF_Z:
		_consoles[s] = _console_model(s)
		_consoles[s].scale = Vector3.ONE * 1.4
		add_child(_consoles[s])
		_consoles[s].position = _wall_spot(s)
		_consoles[s].rotation.y = PI * 0.5
	_consoles[table_sys].position = TABLE + Vector3(0, 0, 0.05)
	_consoles[table_sys].rotation.y = 0.0
	scan()

# ---------------------------------------------------------------- the games

## The library looked through again: our test cartridge, then every game file (or .zip of one) in the games folders.
func scan() -> void:
	library.clear()
	var dir := ProjectSettings.globalize_path(GAMES)
	DirAccess.make_dir_recursive_absolute(dir.path_join(".unzipped"))
	var builtin := dir.path_join(".builtin_test_cart.md")
	if not FileAccess.file_exists(builtin):
		var b := FileAccess.get_file_as_bytes(BUILTIN)
		var f := FileAccess.open(builtin, FileAccess.WRITE)
		if f:
			f.store_buffer(b)
	library.append({"path": builtin, "name": "Smashed Test Cart", "sys": "md"})
	var seen := {}
	for d in game_dirs():
		var da := DirAccess.open(d)
		if da == null:
			continue
		var files := da.get_files()
		files.sort()
		for fn in files:
			var p := String(d).path_join(fn)
			var ext := fn.get_extension().to_lower()
			if ext == "zip":
				p = _unzip(p, dir.path_join(".unzipped"))
				if p == "":
					continue
			var sys := VoxelRetroTV.system_of(p)
			if sys == "" or seen.has(fn.get_basename().to_lower()):
				continue
			seen[fn.get_basename().to_lower()] = true
			library.append({"path": p, "name": pretty(fn.get_basename()), "sys": sys})
	_build_cases()

# the first game file in a .zip, taken out (once) into the cache; "" if there isn't one
static func _unzip(zip_path: String, cache: String) -> String:
	var z := ZIPReader.new()
	if z.open(zip_path) != OK:
		return ""
	for f in z.get_files():
		if VoxelRetroTV.system_of(f) != "":
			var out := cache.path_join(zip_path.get_file().get_basename() + "." + f.get_extension().to_lower())
			if not FileAccess.file_exists(out):
				var fa := FileAccess.open(out, FileAccess.WRITE)
				if fa:
					fa.store_buffer(z.read_file(f))
			z.close()
			return out
	z.close()
	return ""

## A game file's name tidied for its case: "Super_Smash_TV_(USA,_Europe)" -> "Super Smash TV".
static func pretty(n: String) -> String:
	var s := n.replace("_", " ")
	var rx := RegEx.create_from_string("\\s*[\\(\\[][^\\)\\]]*[\\)\\]]")
	s = rx.sub(s, "", true).strip_edges()
	return s if s != "" else n

## E at the ADD GAMES plaque: game files picked from this PC, copied into the games folder.
func add_games() -> void:
	var dir := ProjectSettings.globalize_path(GAMES)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		if arena.inv_ui.is_open():
			arena.close_inventory()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		DisplayServer.file_dialog_show("Add games", OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILES,
			PackedStringArray(["*.md, *.bin, *.gen, *.smd, *.sfc, *.smc, *.sms, *.gg, *.zip ; Games"]), _on_files)
	else:
		OS.shell_open(dir)
		arena.say("Put your game files in %s, then E here again" % dir, 4.0)

func _on_files(status: bool, paths: PackedStringArray, _filter: int) -> void:
	if not arena.top_down:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not status or paths.is_empty():
		return
	var n := 0
	for p in paths:
		var to := ProjectSettings.globalize_path(GAMES).path_join(p.get_file())
		if DirAccess.copy_absolute(p, to) == OK:
			n += 1
	scan()
	arena.say("%d game%s added: on the shelf" % [n, "" if n == 1 else "s"], 3.0)

# ---------------------------------------------------------------- what a player does

## What the look lands on: [tag, distance] ("console:<sys>", "table", "case:<i>", "couch:<seat>", "add", "tv"), or
## ["", INF].
func pick(eye: Vector3, dir: Vector3, reach := 2.6) -> Array:
	var boxes := {}
	for s in _consoles:
		var c: Node3D = _consoles[s]
		if s == table_sys:
			boxes["table"] = AABB(TABLE + Vector3(-0.5, -0.05, -0.3), Vector3(1.0, 0.25, 0.6))
		else:
			boxes["console:" + s] = AABB(c.position + Vector3(-0.25, -0.05, -0.25), Vector3(0.5, 0.25, 0.5))
	for i in _cases.size():
		var cn: Node3D = _cases[i]
		if cn.visible or i == held:      # (the gap a case in your hands came out of: it goes back there)
			boxes["case:%d" % i] = AABB(cn.position + Vector3(-0.07, -0.095, -0.021), Vector3(0.14, 0.19, 0.042))
	for seat in SEAT_X:
		boxes["couch:%d" % seat] = AABB(Vector3(float(SEAT_X[seat]) - 0.5, 0.0, COUCH_Z - 0.45), Vector3(1.0, 0.95, 0.9))
	boxes["add"] = AABB(_add_plaque.position + Vector3(-0.08, -0.2, -0.3), Vector3(0.16, 0.4, 0.6))
	boxes["tv"] = AABB(TV_SCREEN + Vector3(-0.9, -0.85, -0.05), Vector3(1.8, 1.7, 0.9))
	var best := ""
	var bd := INF
	for k in boxes:
		var hit = (boxes[k] as AABB).intersects_ray(eye, dir)
		if hit != null:
			var d := (hit as Vector3).distance_to(eye)
			if d <= reach and d < bd:
				bd = d
				best = k
	return [best, bd]

func line(tag: String) -> String:
	if _is_guest():
		if tag.begins_with("couch:"):
			return "E  sit down: you're player 2"
		if tag == "tv":
			return ("On your mate's TV: %s" % _remote_name) if _remote_name != "" else "Your mate's TV is off"
		return "Your mate's games room: they put the games in (sit on the couch to play as player 2)"
	if tag.begins_with("console:"):
		var s := tag.trim_prefix("console:")
		return "E  put the %s on the table" % VoxelRetroTV.SYSTEMS[s].name
	if tag == "table":
		var sn: String = VoxelRetroTV.SYSTEMS[table_sys].name
		if held >= 0:
			var g: Dictionary = library[held]
			return "E  put %s in and switch on" % g.name + ("" if g.sys == table_sys else " (the %s comes down)" % VoxelRetroTV.SYSTEMS[g.sys].name)
		if inserted >= 0:
			return "%s: %s     E  eject it" % [sn, library[inserted].name]
		return "%s: take a game off the shelf (E at a case)" % sn
	if tag.begins_with("case:"):
		var i := int(tag.trim_prefix("case:"))
		if held >= 0:
			return "E  put %s back" % library[held].name
		var g2: Dictionary = library[i]
		return "E  take %s  (%s)" % [g2.name, VoxelRetroTV.SYSTEMS[g2.sys].name]
	if tag.begins_with("couch:"):
		return ("E  sit down and play" + (" (player 2)" if tag == "couch:2" and arena.net.linked else "")) if tv.playing() else "E  sit down"
	if tag == "add":
		return "E  add games: Mega Drive (.md .bin .gen), Super Nintendo (.sfc .smc), Master System (.sms), Game Gear (.gg), or a .zip"
	if tag == "tv":
		return ("On the TV: %s" % tv.game.name) if tv.playing() else ("" if VoxelRetroTV.available() else "The TV: the console plugin isn't there")
	return ""

func use(tag: String) -> void:
	if _is_guest() and not tag.begins_with("couch:"):
		arena.say("Your mate's games room: they put the games in. Sit on the couch to play as player 2", 2.5)
		return
	if tag.begins_with("console:"):
		bring(tag.trim_prefix("console:"))
	elif tag == "table":
		if held >= 0:
			insert(held)
		elif inserted >= 0:
			eject()
	elif tag.begins_with("case:"):
		if held >= 0:
			put_back()
		else:
			take(int(tag.trim_prefix("case:")))
	elif tag.begins_with("couch:"):
		sit(int(tag.trim_prefix("couch:")))
	elif tag == "add":
		add_games()

## The console for sys down onto the table (the one there back up on its shelf).
func bring(sys: String) -> void:
	if sys == table_sys:
		return
	if inserted >= 0:
		eject()
	_fly(table_sys, _wall_spot(table_sys), PI * 0.5)
	table_sys = sys
	_fly(sys, TABLE + Vector3(0, 0, 0.05), 0.0)
	arena.sound.play("chest_open", TABLE, -8.0, 1.4)
	send_all()

func _wall_spot(s: String) -> Vector3:
	return Vector3(SHELF_X + 0.2, SHELF_Y + 0.03, float(SHELF_Z[s]))

func _fly(sys: String, to: Vector3, yaw: float) -> void:
	var c: Node3D = _consoles[sys]
	_moving[sys] = [c.position, to, 0.0, c.rotation.y, yaw]

## A case off the shelf into this player's hands, opening.
func take(i: int) -> void:
	if i < 0 or i >= library.size():
		return
	held = i
	(_cases[i] as Node3D).visible = false
	_held_node = _case_model(library[i], true)
	arena.cam.add_child(_held_node)
	_held_node.position = Vector3(0.02, -0.14, -0.5)
	_held_node.rotation = Vector3(0.25, PI, 0)
	_held_node.scale = Vector3.ONE * 1.3
	_held_k = 0.0
	arena.sound.play("item_pick", Vector3.INF, -6.0, 0.8)

func put_back() -> void:
	if held < 0:
		return
	(_cases[held] as Node3D).visible = true
	held = -1
	_drop_held()
	arena.sound.play("item_pick", Vector3.INF, -8.0, 0.7)

func _drop_held() -> void:
	if _held_node:
		_held_node.queue_free()
	_held_node = null

## The cartridge in the case in your hands into the console (the right one comes down) and the TV on.
func insert(i: int) -> void:
	var g: Dictionary = library[i]
	if g.sys != table_sys:
		bring(g.sys)
	if inserted >= 0:
		eject()
	held = -1
	_drop_held()
	inserted = i
	var why := tv.play(g)
	if why != "":
		arena.say("It won't start: " + why, 3.0)
		(_cases[i] as Node3D).visible = true
		inserted = -1
		return
	arena.sound.play("chest_close", TABLE, -6.0, 1.6)
	arena.say("%s on the TV: sit on the couch to play (E)" % g.name, 3.0)
	_show_cart()
	send_all()

func eject() -> void:
	if inserted < 0:
		return
	tv.stop()
	(_cases[inserted] as Node3D).visible = true
	inserted = -1
	_show_cart()
	arena.sound.play("chest_open", TABLE, -6.0, 1.6)
	send_all()

## Sat on the couch (seat 1 or 2): the view on the TV, the keys and pad the controller.
func sit(seat: int) -> void:
	arena._let_go()
	seated = seat
	arena.player.global_position = Vector3(float(SEAT_X[seat]), 0.05, COUCH_Z)
	arena.player.velocity = Vector3.ZERO
	arena.player.reset_physics_interpolation()
	arena.look_yaw = PI
	arena.look_pitch = -0.05
	tv.player_port = -1 if _is_guest() else 0      # (a guest's buttons go to the host's console, player 2)
	arena.sound.play("chest_close", arena.player.global_position, -10.0, 0.6)

func get_up() -> void:
	if seated == 0:
		return
	var x := float(SEAT_X[seated])
	seated = 0
	tv.player_port = -1
	if _is_guest():
		_msg(["pad", 0])
		_pad_sent = 0
	arena.player.global_position = Vector3(x, 0.0, COUCH_Z - 0.85)
	arena.player.reset_physics_interpolation()

## The line at the bottom while sat down.
func seated_line() -> String:
	if _is_guest():
		return ("Player 2 on %s:  arrows/WASD  J K L  U I O  Enter start     E: get up" % _remote_name) if _remote_name != "" else "E  get up     (your mate puts a game in)"
	if not tv.playing():
		return "E  get up     (put a game in first: E at the console on the table)"
	return "%s:  arrows/WASD  J K L  U I O  Enter start     E: get up" % tv.game.name

# ---------------------------------------------------------------- each frame

func _is_guest() -> bool:
	return arena.net != null and arena.net.role == "guest" and arena.net.linked

func _is_host() -> bool:
	return arena.net != null and arena.net.role == "host" and arena.net.linked

func _msg(m: Array) -> void:
	if arena.net and arena.net.linked:
		arena.net.send_games(m)

## (the host's) the room's state to the guest: the console on the table, what's on.
func send_all() -> void:
	if _is_host():
		_msg(["state", table_sys, String(tv.game.get("name", "")), tv.playing()])

func on_net(m: Array) -> void:
	match String(m[0]):
		"state":
			if _is_guest():
				var sys := String(m[1])
				if SHELF_Z.has(sys) and sys != table_sys:
					_fly(table_sys, _wall_spot(table_sys), PI * 0.5)
					table_sys = sys
					_fly(sys, TABLE + Vector3(0, 0, 0.05), 0.0)
				_remote_name = String(m[2]) if bool(m[3]) else ""
				(_consoles[table_sys].get_node("Cart") as Node3D).visible = bool(m[3])
				if not bool(m[3]):
					tv.show_remote(null)
		"pad":
			if _is_host():
				tv.remote_buttons = int(m[1])

## (a guest) a picture of the host's TV.
func on_tv_frame(jpg: PackedByteArray) -> void:
	if not _is_guest() or _remote_name == "":
		return
	var img := Image.new()
	if img.load_jpg_from_buffer(jpg) == OK:
		tv.show_remote(img)

func _coop(dt: float) -> void:
	var role: String = arena.net.role if arena.net and arena.net.linked else ""
	if role != _was_role:
		if role == "guest":
			if held >= 0:
				put_back()
			eject()                        # (in the host's game: their console, not ours)
		elif _was_role == "guest":
			_remote_name = ""
			tv.show_remote(null)
		if role == "host":
			send_all()
		if role != "host":
			tv.remote_buttons = 0
		_was_role = role
	if role == "host" and tv.playing() and tv.last_frame:
		_tv_t += dt
		if _tv_t >= 1.0 / TV_HZ:
			_tv_t = 0.0
			var img: Image = tv.last_frame.duplicate()
			img.resize(192, 134, Image.INTERPOLATE_BILINEAR)
			arena.net.send_tv(img.save_jpg_to_buffer(0.6))
	elif role == "guest" and seated > 0:
		var bits := tv.my_buttons()
		if bits != _pad_sent:
			_pad_sent = bits
			_msg(["pad", bits])

var _rt := 0.0
# --retrotest: our test cartridge put in and played two seconds, what came out printed, then quit (the exported game's
# check that the console plugin and its cores load on this machine)
func _retrotest(dt: float) -> void:
	_rt += dt
	if _rt > 1.0 and inserted < 0 and _rt < 2.0:
		take(0)
		insert(0)
		print("RETROTEST plugin %s, playing %s (%s)" % [str(VoxelRetroTV.available()), str(tv.playing()), tv.core.get_core_name() if tv.core else "-"])
	if _rt > 4.0:
		var f: Image = tv.last_frame
		print("RETROTEST frames %d, picture %s, pixel %s" % [tv.frames_run, ("%dx%d" % [f.get_width(), f.get_height()]) if f else "none", str(f.get_pixel(10, 10)) if f else "-"])
		eject()
		get_tree().quit(0 if tv.frames_run > 60 and f != null else 1)

func _process(dt: float) -> void:
	if arena._opts.has("retrotest"):
		_retrotest(dt)
	_coop(dt)
	for s in _moving.keys():
		var m: Array = _moving[s]
		m[2] = minf(1.0, float(m[2]) + dt * 2.2)
		var k := ease(float(m[2]), -2.0)
		var c: Node3D = _consoles[s]
		c.position = (m[0] as Vector3).lerp(m[1], k) + Vector3(0, sin(k * PI) * 0.35, 0)
		c.rotation.y = lerp_angle(float(m[3]), float(m[4]), k)
		if float(m[2]) >= 1.0:
			_moving.erase(s)
	if _held_node:
		_held_k = minf(1.0, _held_k + dt * 2.5)
		var lid: Node3D = _held_node.get_node_or_null("Lid")
		if lid:
			lid.rotation.y = -ease(_held_k, -2.0) * 2.4
	ceiling.visible = not (arena.top_down and in_room(arena.player.global_position))

# ---------------------------------------------------------------- building it

func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var key := "%s,%f,%f" % [c.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m

func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material, solid := false) -> Node3D:
	var n: Node3D = StaticBody3D.new() if solid else Node3D.new()
	n.position = at
	parent.add_child(n)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	n.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		n.add_child(cs)
	return n

func _label(parent: Node3D, text: String, at: Vector3, size := 32, col := Color.WHITE, yaw := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.003
	l.outline_size = 6
	l.modulate = col
	l.position = at
	l.rotation.y = yaw
	parent.add_child(l)
	return l

# the 90s arcade carpet: dark blue with neon squiggles, triangles and dots, tiled
static func _carpet() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color8(18, 16, 48))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1993
	var neon := [Color8(255, 60, 170), Color8(60, 230, 255), Color8(255, 230, 60), Color8(120, 255, 90), Color8(170, 90, 255)]
	for k in 26:
		var c: Color = neon[k % neon.size()]
		var x := rng.randi() % 64
		var y := rng.randi() % 64
		match k % 3:
			0:
				for i in 9:
					img.set_pixel((x + i) % 64, (y + int(round(sin(i * 0.9) * 2.0)) + 64) % 64, c)
			1:
				for i in 4:
					for j in i + 1:
						img.set_pixel((x + j) % 64, (y + i) % 64, c)
			2:
				img.set_pixel(x, y, c)
				img.set_pixel((x + 1) % 64, y, c)
				img.set_pixel(x, (y + 1) % 64, c)
				img.set_pixel((x + 1) % 64, (y + 1) % 64, c)
	return ImageTexture.create_from_image(img)

func _shell() -> void:
	var w := X1 - X0
	var d := Z1 - Z0
	var mid := Vector3((X0 + X1) * 0.5, 0, (Z0 + Z1) * 0.5)
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = _carpet()
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	fm.uv1_scale = Vector3(w / 1.6, d / 1.6, 1)
	fm.roughness = 1.0
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	floor_mi.mesh = pm
	floor_mi.material_override = fm
	floor_mi.position = mid + Vector3(0, 0.002, 0)
	add_child(floor_mi)
	_box(self, Vector3(w + WALL, 1.0, d + WALL), mid + Vector3(-WALL * 0.5, -0.5, WALL * 0.5), _mat(Color8(18, 16, 48)), true)
	# the walls: deep purple, a skirting; the west and back walls of its own (the bedroom's wall is the east one)
	var paper := _mat(Color8(64, 40, 92), 0.95)
	var skirt := _mat(Color8(30, 22, 40))
	_box(self, Vector3(WALL, H, d + WALL), Vector3(X0 - WALL * 0.5, H * 0.5, mid.z + WALL * 0.5), paper, true)
	_box(self, Vector3(w + WALL, H, WALL), Vector3(mid.x - WALL * 0.5, H * 0.5, Z1 + WALL * 0.5), paper, true)
	_box(self, Vector3(0.02, H, d), Vector3(X1 - 0.01, H * 0.5, mid.z), paper)          # (papered over the bedroom's)
	_box(self, Vector3(DOOR_X0 - X0, H, 0.02), Vector3((X0 + DOOR_X0) * 0.5, H * 0.5, Z0 + 0.01), paper)
	_box(self, Vector3(X1 - DOOR_X1, H, 0.02), Vector3((DOOR_X1 + X1) * 0.5, H * 0.5, Z0 + 0.01), paper)
	_box(self, Vector3(DOOR_X1 - DOOR_X0, H - DOOR_H, 0.02), Vector3((DOOR_X0 + DOOR_X1) * 0.5, (H + DOOR_H) * 0.5, Z0 + 0.01), paper)
	var frame := _mat(Color8(255, 60, 170), 0.4)
	frame.emission_enabled = true
	frame.emission = Color8(255, 40, 160)
	frame.emission_energy_multiplier = 0.8
	for x in [DOOR_X0 - 0.04, DOOR_X1 + 0.04]:
		_box(self, Vector3(0.08, DOOR_H, 1.08), Vector3(x, DOOR_H * 0.5, 22.0), frame)
	_box(self, Vector3(DOOR_X1 - DOOR_X0 + 0.16, 0.08, 1.08), Vector3((DOOR_X0 + DOOR_X1) * 0.5, DOOR_H + 0.04, 22.0), frame)
	_label(self, "GAMES ROOM", Vector3((DOOR_X0 + DOOR_X1) * 0.5, DOOR_H + 0.35, 21.45), 48, Color8(255, 120, 210), PI)
	for sk in [[Vector3(0.02, 0.12, d), Vector3(X0 + 0.01, 0.06, mid.z)], [Vector3(w, 0.12, 0.02), Vector3(mid.x, 0.06, Z1 - 0.01)]]:
		_box(self, sk[0], sk[1], skirt)
	# the ceiling (off from above, inside), a dim light; a lamp in the corner
	ceiling = Node3D.new()
	add_child(ceiling)
	_box(ceiling, Vector3(w + WALL, 0.12, d + WALL), Vector3(mid.x - WALL * 0.5, H + 0.06, mid.z + WALL * 0.5), _mat(Color8(40, 30, 56), 0.95))
	var l := OmniLight3D.new()
	l.position = Vector3(mid.x, H - 0.3, mid.z - 0.5)
	l.light_color = Color8(220, 190, 255)
	l.light_energy = 0.7
	l.omni_range = 7.0
	l.shadow_enabled = false
	add_child(l)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(X0 + 0.5, 1.5, Z1 - 0.5)
	lamp.light_color = Color8(255, 170, 90)
	lamp.light_energy = 0.8
	lamp.omni_range = 4.0
	add_child(lamp)
	_box(self, Vector3(0.04, 1.5, 0.04), Vector3(X0 + 0.5, 0.75, Z1 - 0.5), _mat(Color8(40, 40, 44), 0.4, 0.8))
	var shade := _mat(Color8(255, 200, 140))
	shade.emission_enabled = true
	shade.emission = Color8(255, 160, 80)
	shade.emission_energy_multiplier = 1.5
	_box(self, Vector3(0.36, 0.3, 0.36), Vector3(X0 + 0.5, 1.55, Z1 - 0.5), shade)
	# posters on the west wall's ends and the back wall's corner
	_poster(Vector3(X0 + 0.02, 1.6, 23.05), PI * 0.5, "SMASH TV", "BIG MONEY\nBIG PRIZES\nI LOVE IT!", Color8(230, 40, 40))
	_poster(Vector3(X0 + 0.02, 1.6, 29.45), PI * 0.5, "16-BIT", "BLAST\nPROCESSING", Color8(30, 120, 230))
	_poster(Vector3(X1 - 1.1, 1.6, Z1 - 0.02), PI, "HIGH SCORES", "1  JARED  999990\n2  SHANE  450210\n3  YOU     000000", Color8(30, 30, 30))

func _poster(at: Vector3, yaw: float, title: String, body: String, col: Color) -> void:
	var p := Node3D.new()
	p.position = at
	p.rotation.y = yaw
	add_child(p)
	_box(p, Vector3(0.7, 0.95, 0.02), Vector3.ZERO, _mat(col, 0.7))
	_box(p, Vector3(0.74, 0.99, 0.01), Vector3(0, 0, -0.006), _mat(Color8(20, 20, 20)))
	_label(p, title, Vector3(0, 0.3, 0.015), 44, Color8(255, 236, 120))
	_label(p, body, Vector3(0, -0.1, 0.015), 26, Color.WHITE)

func _furniture() -> void:
	var black := _mat(Color8(22, 22, 26), 0.5)
	var wood := _mat(Color8(96, 64, 40), 0.7)
	var fabric := _mat(Color8(150, 40, 60), 1.0)
	var cushion := _mat(Color8(170, 52, 72), 1.0)
	# the TV: a big rear-projection set, its cabinet, a speaker grille each side, the brand
	_box(self, Vector3(1.8, 1.75, 0.85), Vector3(TV_X, 0.875, Z1 - 0.45), black, true)
	_box(self, Vector3(1.56, 1.2, 0.02), Vector3(TV_X, TV_SCREEN.y, TV_SCREEN.z + 0.02), _mat(Color8(8, 8, 10), 0.3))
	for sx in [-1, 1]:
		_box(self, Vector3(0.1, 1.0, 0.02), Vector3(TV_X + sx * 0.83, TV_SCREEN.y, TV_SCREEN.z + 0.01), _mat(Color8(50, 50, 56), 0.9))
	_label(self, "PROJECTRON 50", Vector3(TV_X, 0.28, TV_SCREEN.z - 0.005), 28, Color8(200, 200, 210), PI)
	var led := _mat(Color8(255, 40, 40))
	led.emission_enabled = true
	led.emission = Color8(255, 30, 30)
	_box(self, Vector3(0.02, 0.02, 0.01), Vector3(TV_X + 0.7, 0.28, TV_SCREEN.z - 0.005), led)
	# the coffee table, two pads on it
	_box(self, Vector3(1.3, 0.05, 0.6), TABLE + Vector3(0, -0.025, 0), wood, true)
	for lx in [-0.6, 0.6]:
		for lz in [-0.25, 0.25]:
			_box(self, Vector3(0.05, 0.4, 0.05), Vector3(TABLE.x + lx, 0.2, TABLE.z + lz), wood, true)
	for k in 2:
		var pad := _box(self, Vector3(0.14, 0.03, 0.08), TABLE + Vector3(-0.42 + k * 0.84, 0.015, -0.18), black)
		pad.rotation.y = 0.3 - k * 0.6
		_box(pad, Vector3(0.02, 0.012, 0.02), Vector3(-0.04, 0.02, 0), _mat(Color8(80, 80, 90)))
		for b in 3:
			_box(pad, Vector3(0.012, 0.012, 0.012), Vector3(0.025 + b * 0.017, 0.02, 0.005 - b * 0.005), _mat([Color8(200, 40, 40), Color8(40, 160, 60), Color8(60, 80, 220)][b]))
	# the couch, facing the TV
	_box(self, Vector3(2.4, 0.42, 0.9), Vector3(TV_X, 0.21, COUCH_Z), fabric, true)
	_box(self, Vector3(2.4, 0.95, 0.25), Vector3(TV_X, 0.475, COUCH_Z - 0.45), fabric, true)
	for sx in [-1, 1]:
		_box(self, Vector3(0.22, 0.65, 0.9), Vector3(TV_X + sx * 1.2, 0.325, COUCH_Z), fabric, true)
	for seat in SEAT_X:
		_box(self, Vector3(1.0, 0.1, 0.72), Vector3(float(SEAT_X[seat]), 0.47, COUCH_Z + 0.05), cushion)
		_box(self, Vector3(1.0, 0.45, 0.14), Vector3(float(SEAT_X[seat]), 0.75, COUCH_Z - 0.28), cushion)
	# a rug under the table
	_box(self, Vector3(2.6, 0.01, 1.9), Vector3(TV_X, 0.006, 27.6), _mat(Color8(30, 120, 140), 1.0))
	# the console shelves on the west wall, each one's name
	for s in SHELF_Z:
		_box(self, Vector3(0.45, 0.04, 0.55), Vector3(SHELF_X + 0.22, SHELF_Y, float(SHELF_Z[s])), wood, true)
		_label(self, VoxelRetroTV.SYSTEMS[s].name.to_upper(), Vector3(SHELF_X + 0.02, SHELF_Y + 0.38, float(SHELF_Z[s])), 26, Color8(255, 236, 160), PI * 0.5)
	# the bookcase on the east wall
	var bc := Node3D.new()
	add_child(bc)
	for r in CASE_ROWS + 1:
		_box(bc, Vector3(0.32, 0.03, CASE_LEN), Vector3(CASE_X + 0.16, 0.1 + r * 0.36, CASE_Z0 + CASE_LEN * 0.5), wood, r == 0)
	for z in [CASE_Z0, CASE_Z0 + CASE_LEN]:
		_box(bc, Vector3(0.32, 0.1 + CASE_ROWS * 0.36 + 0.03, 0.03), Vector3(CASE_X + 0.16, (0.1 + CASE_ROWS * 0.36) * 0.5, z), wood, true)
	_box(bc, Vector3(0.02, 0.1 + CASE_ROWS * 0.36, CASE_LEN), Vector3(CASE_X + 0.31, (0.1 + CASE_ROWS * 0.36) * 0.5, CASE_Z0 + CASE_LEN * 0.5), wood)
	_case_root = Node3D.new()
	add_child(_case_root)
	# the ADD GAMES plaque on the bookcase's end
	_add_plaque = Node3D.new()
	_add_plaque.position = Vector3(CASE_X + 0.16, 1.3, CASE_Z0 - 0.03)
	add_child(_add_plaque)
	_box(_add_plaque, Vector3(0.3, 0.32, 0.02), Vector3.ZERO, _mat(Color8(240, 220, 120), 0.5, 0.3))
	_label(_add_plaque, "ADD\nGAMES\n(E)", Vector3(0, 0, -0.015), 30, Color8(40, 20, 10), PI)

# the cases on the bookcase's shelves, spines out, a row at a time
func _build_cases() -> void:
	for c in _cases:
		(c as Node).queue_free()
	_cases.clear()
	# (rows of up to PER_ROW, the eye-level shelf first, each row in the middle of its shelf)
	var order := [3, 2, 4, 1, 0]
	for i in library.size():
		var row: int = order[mini(i / PER_ROW, order.size() - 1)]
		var col := i % PER_ROW
		var in_row := mini(PER_ROW, library.size() - (i / PER_ROW) * PER_ROW)
		var cn := _case_model(library[i], false)
		_case_root.add_child(cn)
		cn.position = Vector3(CASE_X + 0.075, 0.1 + 0.015 + 0.095 + row * 0.36, CASE_Z0 + CASE_LEN * 0.5 + (col - (in_row - 1) * 0.5) * 0.042)
		cn.rotation.y = -PI * 0.5            # (the spine to the room)
		cn.visible = i != held and i != inserted
		_cases.append(cn)

## A game's case: on the shelf (spine out, its name down it), or open in your hands (the cartridge inside, the lid
## with its cover swinging open).
func _case_model(g: Dictionary, open: bool) -> Node3D:
	var root := Node3D.new()
	var sys := String(g.sys)
	var shell: Color = {"md": Color8(24, 24, 28), "snes": Color8(200, 200, 205), "sms": Color8(235, 235, 235), "gg": Color8(24, 24, 28)}[sys]
	var hue := float(hash(String(g.name)) % 360) / 360.0
	var art := Color.from_hsv(hue, 0.7, 0.85)
	var w := 0.135 if sys != "gg" else 0.11
	var h := 0.19 if sys != "gg" else 0.14
	var t := 0.03
	if not open:
		# thin along x here (the shelf turns it), the spine on its +z face: a band of the game's colour, its name
		_box(root, Vector3(t, h, w), Vector3.ZERO, _mat(shell, 0.4))
		_box(root, Vector3(t + 0.002, h * 0.86, 0.004), Vector3(0, 0, w * 0.5), _mat(art, 0.6))
		var lab := _label(root, String(g.name), Vector3(0.0, 0.0, w * 0.5 + 0.003), 16, Color.WHITE, 0.0)
		lab.rotation = Vector3(0, 0, -PI * 0.5)
		lab.pixel_size = 0.0011
		lab.outline_size = 3
		return root
	# open in your hands (it faces the camera: -z): the back with the cartridge in it, the lid swinging open
	_box(root, Vector3(w, h, 0.008), Vector3.ZERO, _mat(shell, 0.4))
	var cart: Color = {"md": Color8(30, 30, 34), "snes": Color8(150, 150, 156), "sms": Color8(30, 30, 34), "gg": Color8(30, 30, 34)}[sys]
	_box(root, Vector3(w * 0.72, h * 0.62, 0.016), Vector3(0, -h * 0.05, -0.012), _mat(cart, 0.5))
	_box(root, Vector3(w * 0.56, h * 0.3, 0.002), Vector3(0, 0.0, -0.021), _mat(art, 0.6))
	var cl := _label(root, String(g.name), Vector3(0, 0.0, -0.023), 18, Color.WHITE, PI)
	cl.pixel_size = 0.0009
	cl.width = 130.0
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.outline_size = 3
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(-w * 0.5, 0, -0.03)
	root.add_child(lid)
	_box(lid, Vector3(w, h, 0.006), Vector3(w * 0.5, 0, 0), _mat(art, 0.6))
	var tl := _label(lid, String(g.name), Vector3(w * 0.5, h * 0.15, -0.004), 20, Color.WHITE, PI)
	tl.pixel_size = 0.0009
	tl.width = 140.0
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.outline_size = 3
	var sl := _label(lid, String(VoxelRetroTV.SYSTEMS[sys].name).to_upper(), Vector3(w * 0.5, h * 0.4, -0.004), 14, Color8(255, 236, 160), PI)
	sl.pixel_size = 0.0008
	return root

func _show_cart() -> void:
	var c: Node3D = _consoles[table_sys]
	var slot: Node3D = c.get_node_or_null("Cart")
	if slot:
		slot.visible = inserted >= 0

## A console (boxes): the Mega Drive black with its round top, the Super Nintendo grey with purple buttons, the
## Master System black and red, the Game Gear a handheld. A cartridge shows in its slot when there's one in.
func _console_model(s: String) -> Node3D:
	var root := Node3D.new()
	var black := _mat(Color8(26, 26, 30), 0.45)
	var red := _mat(Color8(200, 30, 30), 0.5)
	match s:
		"md":
			_box(root, Vector3(0.28, 0.06, 0.22), Vector3(0, 0.03, 0), black)
			var disc := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.08
			cm.bottom_radius = 0.085
			cm.height = 0.015
			disc.mesh = cm
			disc.material_override = _mat(Color8(44, 44, 50), 0.3)
			disc.position = Vector3(0.03, 0.065, 0.02)
			root.add_child(disc)
			_box(root, Vector3(0.12, 0.012, 0.02), Vector3(0.03, 0.075, -0.04), _mat(Color8(10, 10, 12)))
			_box(root, Vector3(0.05, 0.01, 0.02), Vector3(-0.09, 0.065, 0.06), red)
			var cart := _box(root, Vector3(0.11, 0.07, 0.018), Vector3(0.03, 0.105, -0.04), _mat(Color8(30, 30, 34), 0.5))
			cart.name = "Cart"
		"snes":
			_box(root, Vector3(0.24, 0.07, 0.2), Vector3(0, 0.035, 0), _mat(Color8(196, 196, 202), 0.5))
			_box(root, Vector3(0.12, 0.02, 0.08), Vector3(0, 0.08, 0.0), _mat(Color8(170, 170, 178), 0.5))
			for bx in [-0.07, 0.07]:
				_box(root, Vector3(0.03, 0.015, 0.02), Vector3(bx, 0.078, 0.06), _mat(Color8(120, 100, 170), 0.5))
			var cart2 := _box(root, Vector3(0.1, 0.07, 0.02), Vector3(0, 0.12, 0.0), _mat(Color8(150, 150, 156), 0.5))
			cart2.name = "Cart"
		"sms":
			_box(root, Vector3(0.36, 0.07, 0.17), Vector3(0, 0.035, 0), black)
			_box(root, Vector3(0.36, 0.01, 0.02), Vector3(0, 0.07, 0.075), red)
			_box(root, Vector3(0.14, 0.01, 0.06), Vector3(0.05, 0.072, -0.02), _mat(Color8(60, 60, 66), 0.4))
			var cart3 := _box(root, Vector3(0.12, 0.06, 0.016), Vector3(0.05, 0.1, -0.02), _mat(Color8(30, 30, 34), 0.5))
			cart3.name = "Cart"
		"gg":
			_box(root, Vector3(0.21, 0.035, 0.11), Vector3(0, 0.018, 0), black)
			_box(root, Vector3(0.08, 0.005, 0.065), Vector3(0, 0.037, 0), _mat(Color8(20, 40, 30), 0.2))
			_box(root, Vector3(0.025, 0.006, 0.025), Vector3(-0.075, 0.037, 0), _mat(Color8(60, 60, 66)))
			for k in 2:
				_box(root, Vector3(0.015, 0.006, 0.015), Vector3(0.065 + k * 0.02, 0.037, 0.008 - k * 0.016), _mat(Color8(60, 60, 140)))
			var cart4 := _box(root, Vector3(0.07, 0.01, 0.05), Vector3(0, 0.04, 0.07), _mat(Color8(30, 30, 34), 0.5))
			cart4.name = "Cart"
	var cn: Node3D = root.get_node("Cart")
	cn.visible = false
	return root
