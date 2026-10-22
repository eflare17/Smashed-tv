class_name VoxelNetMenu
extends CanvasLayer
## The online menu, as in the main game (NetMenu, the HTML game's net panel; the owner, 22 Oct: "make it easier to
## join, I like the set up in the last game"): an ONLINE (O) button in the corner opens PLAY ONLINE: HOST A GAME (a
## room code, copied for you to paste to your mate), the code box with JOIN (it fills itself in from a code you've
## copied, or the last room you joined; letters on screen too), LEAVE GAME, CLOSE, the status line. While the host
## waits, the room code shows big on screen. A room code someone else has gets a new one by itself. Same house / no
## internet: HOST DIRECT (it shows your address; your mate types that in the code box). Everything is a real button
## (mouse, or keys: Tab / arrows / Enter, Esc closes). F7 (host) and F8 (open it) still work. Owned by the voxel
## session.

const PINK := Color("#f7a8ff")
const GOLD := Color("#f6d17a")
const GOOD := Color("#7fd89a")
const BAD := Color("#ff7a7a")
const ABC := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"      # (the codes' letters: no I, O, 0 or 1 to mix up)
const CFG := "user://voxel_online.cfg"

var arena: Node3D
var net: VoxelNet
var _btn: Button
var _panel: PanelContainer
var _status: Label
var _room: Label
var _code_big: Label
var _code_in: LineEdit
var _host_b: Button
var _direct_b: Button
var _join_b: Button
var _copy_b: Button
var _leave_b: Button
var _keys: GridContainer
var _note: Label
var _wait: Label
var _open := false
var _retries := 0
var _last := ""                 # the last room joined (offered next time)
var _refresh_t := 0.0

func setup(arena_: Node3D) -> void:
	arena = arena_
	net = arena.net
	layer = 30
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		_last = String(cf.get_value("online", "last", ""))
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_btn = Button.new()
	_btn.text = "ONLINE (O)"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 14)
	_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_btn.offset_left = -12
	_btn.offset_right = -12
	_btn.offset_top = 10
	_btn.offset_bottom = 42
	_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_btn.pressed.connect(toggle)
	_btn.button_down.connect(func(): arena._ignore[MOUSE_BUTTON_LEFT] = true)     # (top-down: the click on it doesn't fire too)
	root.add_child(_btn)

	_wait = Label.new()
	_wait.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.offset_left = -320
	_wait.offset_right = 320
	_wait.offset_top = -270
	_wait.offset_bottom = -150
	_wait.add_theme_font_size_override("font_size", 34)
	_wait.add_theme_color_override("font_color", GOLD)
	_outline(_wait, 6)
	_wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait.visible = false
	root.add_child(_wait)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.1, 0.94)
	sb.border_color = PINK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(460, 0)
	_panel.visible = false
	root.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	var title := Label.new()
	title.text = "PLAY ONLINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", PINK)
	v.add_child(title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(420, 0)
	_status.add_theme_font_size_override("font_size", 15)
	v.add_child(_status)
	_room = Label.new()
	_room.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room.add_theme_font_size_override("font_size", 15)
	_room.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	v.add_child(_room)
	_code_big = Label.new()
	_code_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_big.add_theme_font_size_override("font_size", 44)
	_code_big.add_theme_color_override("font_color", GOLD)
	v.add_child(_code_big)
	_copy_b = _button(v, "COPY THE CODE", _on_copy)

	_host_b = _button(v, "HOST A GAME", _on_host)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_code_in = LineEdit.new()
	_code_in.placeholder_text = "room code"
	_code_in.max_length = 40
	_code_in.custom_minimum_size = Vector2(200, 44)
	_code_in.add_theme_font_size_override("font_size", 22)
	_code_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_in.text_changed.connect(_on_code_typed)
	_code_in.text_submitted.connect(func(_t): _on_join())
	row.add_child(_code_in)
	_join_b = _button(row, "JOIN", _on_join)
	_join_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var paste := _button(row, "PASTE", _on_paste)
	paste.add_theme_font_size_override("font_size", 14)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 13)
	_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	v.add_child(_note)

	_keys = GridContainer.new()
	_keys.columns = 11
	_keys.add_theme_constant_override("h_separation", 4)
	_keys.add_theme_constant_override("v_separation", 4)
	v.add_child(_keys)
	for ch in ABC:
		var c: String = ch
		var b := _button(_keys, c, func(): _type(c))
		b.custom_minimum_size = Vector2(34, 34)
		b.add_theme_font_size_override("font_size", 16)
	var del := _button(_keys, "<", func(): _code_in.text = _code_in.text.left(-1))
	del.custom_minimum_size = Vector2(34, 34)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row2)
	_leave_b = _button(row2, "LEAVE GAME", _on_leave)
	_button(row2, "CLOSE", close)
	_direct_b = _button(v, "SAME HOUSE? HOST DIRECT (no internet needed)", _on_direct)
	_direct_b.add_theme_font_size_override("font_size", 13)
	_direct_b.custom_minimum_size = Vector2(0, 32)
	var help := Label.new()
	help.text = "Host, and the code's copied: paste it to your mate. They copy it, open this and press Join.\nThe host's PC runs the game; you both play. F7 hosts, O opens this."
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	v.add_child(help)
	net.changed.connect(_refresh)
	_refresh()

func _outline(l: Label, w: int) -> void:
	l.add_theme_constant_override("outline_size", w)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))

func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

## A room code in some text (a pasted message), or "" (an address counts too, for a direct game).
static func code_in(t: String) -> String:
	var s := t.strip_edges()
	# (an address, as a whole word: four numbers with dots, an IPv6 one (bare, or "[v6]:port"), or a name with a dot or
	# a port; not just any '.' or ':', as in "Code: K7QD", "meet at 10:30" or a message ending in a full stop)
	var v4 := RegEx.create_from_string("^\\d{1,3}(\\.\\d{1,3}){3}(:\\d+)?$")
	var v6 := RegEx.create_from_string("^\\[[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*\\](:\\d+)?$")
	var host := RegEx.create_from_string("^[A-Za-z][A-Za-z0-9-]*((\\.[A-Za-z0-9-]+)*\\.[A-Za-z][A-Za-z0-9-]+(:\\d+)?|(\\.[A-Za-z0-9-]+)*:\\d+)$")
	for m in RegEx.create_from_string("\\S+").search_all(s):
		var a := m.get_string().lstrip("(\"'").rstrip(".,!?;)\"'")
		# (a bare IPv6 one: Godot passes "10:30" too, so a "::" or all eight groups)
		var bare6 := a.count(":") > 1 and a.is_valid_ip_address() and (a.contains("::") or a.count(":") == 7)
		if v4.search(a) or v6.search(a) or host.search(a) or bare6:
			return a
	# (four numbers with dots inside a word, as in "ip:192.168.1.20")
	var addr := RegEx.create_from_string("\\b\\d{1,3}(\\.\\d{1,3}){3}(:\\d+)?\\b").search(s)
	if addr:
		return addr.get_string()
	# (in a message like "join me, code K7QD": the last word made only of the codes' letters)
	s = s.to_upper()
	var rx := RegEx.create_from_string("\\b[A-HJ-NP-Z2-9]{4,8}\\b")
	var found := rx.search_all(s)
	return found[-1].get_string() if not found.is_empty() else ""

static func new_code() -> String:
	var c := ""
	for i in 4:
		c += ABC[randi() % ABC.length()]
	return c

func _type(c: String) -> void:
	if _code_in.text.length() < 8:
		_code_in.text += c
	_code_in.caret_column = _code_in.text.length()

func _on_code_typed(t: String) -> void:
	if t.contains("."):
		return                      # (an address)
	var up := t.to_upper()
	if up != t:
		var cc := _code_in.caret_column
		_code_in.text = up
		_code_in.caret_column = cc

## HOST A GAME: a new room code over the internet, copied to the clipboard.
func host(code := "") -> void:
	_retries = 0
	var c := code if code != "" else new_code()
	net.host(c, "rtc", String(arena._opts.get("server", "")), arena._opts.has("local"))
	_copy(c)
	_refresh()

func _on_host() -> void:
	host()

func _on_direct() -> void:
	net.host("DIRECT", "enet")
	var ip := my_address()
	_copy(ip)
	_note.text = "your address is copied: your mate pastes it in the code box and presses Join"
	_refresh()

func _on_join() -> void:
	join(_code_in.text)

## JOIN: a room code (over the internet) or an address (a direct game).
func join(t: String) -> void:
	var c := code_in(t)
	if c == "":
		_note.text = "type the room code your mate gave you (4 letters)"
		return
	var direct := c.contains(".") or c.contains(":")
	net.join(c, "enet" if direct else "rtc", String(arena._opts.get("server", "")), arena._opts.has("local"))
	_last = c
	var cf := ConfigFile.new()
	cf.set_value("online", "last", c)
	cf.save(CFG)
	_code_in.release_focus()
	_refresh()

func _on_paste() -> void:
	var c := code_in(DisplayServer.clipboard_get())
	if c == "":
		_note.text = "nothing to paste (copy the code your mate sent first)"
		return
	_code_in.text = c
	_note.text = "pasted: press Join"

func _on_copy() -> void:
	if net.code != "":
		_copy(my_address() if net.code == "DIRECT" else net.code)

func _copy(t: String) -> void:
	DisplayServer.clipboard_set(t)
	_note.text = "copied \"%s\": paste it to your mate (Ctrl+V)" % t

func _on_leave() -> void:
	net.leave()
	_refresh()

## This PC's address on the home network (for a direct game).
static func my_address() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and a.split(".").size() == 4 and int(a.split(".")[1]) >= 16 and int(a.split(".")[1]) <= 31):
			return a
	return "127.0.0.1"

func is_open() -> bool:
	return _open

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func open() -> void:
	if _open or (arena.settings_menu and arena.settings_menu.is_open()):
		return                      # (the settings screen, or its benchmark, has the mouse: no co-op started mid-run)
	if arena.games.seated > 0:
		arena.games.get_up()        # (on the couch the keys are the console's: up, so typing a code doesn't play the game)
	_open = true
	_panel.visible = true
	arena._let_go()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# the code box filled in for you: a code you've copied (your mate's message), else the last room you joined
	if net.role == "" and _code_in.text == "":
		var c := code_in(DisplayServer.clipboard_get())
		if c != "" and not c.contains("."):
			_code_in.text = c
			_note.text = "your copied code's in: press Join"
		elif _last != "":
			_code_in.text = _last
			_note.text = "the last room you joined: press Join (or host your own)"
		else:
			_note.text = ""
	_refresh()
	if net.role == "":
		(_join_b if _code_in.text != "" else _host_b).grab_focus()     # (in a game: nothing focused, Enter can't leave it)

func close() -> void:
	if not _open:
		return
	_open = false
	_panel.visible = false
	var fo := get_viewport().gui_get_focus_owner()
	if fo:
		fo.release_focus()
	if not arena.top_down and not arena._opts.has("auto") and not arena.inv_ui.is_open() and not arena.lock_view.is_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED     # (the backpack or a padlock still up underneath: the mouse stays theirs)

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if arena.settings_menu and arena.settings_menu.is_open():
		return                      # (the settings screen has the keys)
	if _open and e.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif e.physical_keycode == KEY_O and not (_open and _code_in.has_focus()) and not _keys_elsewhere():
		toggle()
		get_viewport().set_input_as_handled()

# the keys are a game's on the couch, or the backpack's or padlock's (O there is a button, not the menu)
func _keys_elsewhere() -> bool:
	if _open:
		return false
	return arena.games.seated > 0 or arena.inv_ui.is_open() or arena.lock_view.is_open()

func _process(dt: float) -> void:
	# a room code someone else is hosting: a new one, by itself (three goes)
	if net.role == "host" and not net.linked and net.code != "DIRECT" and net.status_text.contains("taken") and _retries < 3:
		_retries += 1
		var r := _retries
		host()
		_retries = r
	var show: bool = net.role == "host" and not net.linked and not _open
	_wait.visible = show
	if show:
		_wait.text = ("your address\n%s" % my_address()) if net.code == "DIRECT" else ("room code\n%s" % net.code)
	_refresh_t += dt
	if _refresh_t > 0.5:
		_refresh_t = 0.0
		_refresh()

func _refresh() -> void:
	if _status == null:
		return
	var kind: String = net.status_kind
	_status.text = net.status_text if net.role != "" else "Play with a mate over the internet: no port forwarding."
	_status.add_theme_color_override("font_color", GOOD if kind == "live" else (BAD if kind == "bad" else Color(1, 1, 1, 0.9)))
	var hosting := net.role == "host"
	var direct := net.code == "DIRECT"
	_room.text = ("you're hosting: your address" if direct else "you're hosting: room code") if hosting else ("joined" if net.role == "guest" else "")
	_room.visible = net.role != ""
	_code_big.text = (my_address() if direct else net.code) if net.role != "" else ""
	_code_big.visible = net.role != ""
	_copy_b.visible = hosting
	_leave_b.visible = net.role != ""
	_host_b.text = "HOST A NEW ROOM" if hosting else "HOST A GAME"
	if net.linked:
		_btn.text = "ONLINE: %s  %s (O)" % ["host" if hosting else "guest", "direct" if direct else net.code]
	elif hosting:
		_btn.text = "ONLINE: waiting (O)"
	elif net.role == "guest":
		_btn.text = "ONLINE: joining… (O)"
	else:
		_btn.text = "ONLINE (O)"
