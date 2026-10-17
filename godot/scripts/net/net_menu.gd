class_name NetMenu
extends CanvasLayer
## The online menu (the HTML game's net panel: Host, the room code, Join with a code, Leave, the status line):
## an ONLINE button under the character picker (or O, or the pad's left stick click) opens it. Everything in it
## is a real button, so a mouse, a finger or a pad (d-pad / stick to move, A to press, B to close) all work; the
## code can be typed or picked from the on-screen letters. While the host waits, the room code shows big at the
## bottom of the screen, as in the HTML game.
## Owned by the Online task.

const PINK := Color("#f7a8ff")
const GOLD := Color("#f6d17a")
const GOOD := Color("#7fd89a")
const BAD := Color("#ff7a7a")

var net: Net

var _btn: Button
var _panel: PanelContainer
var _status: Label
var _code_big: Label
var _room: Label
var _code_in: LineEdit
var _host_b: Button
var _join_b: Button
var _leave_b: Button
var _close_b: Button
var _keys: GridContainer
var _wait: Label
var _was_controls := true
var _open := false

func _ready() -> void:
	layer = 30
	_add_action()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_btn = Button.new()
	_btn.text = "ONLINE (O)"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 13)
	_btn.position = Vector2(12, 44)
	_btn.pressed.connect(toggle)
	root.add_child(_btn)

	_wait = Label.new()
	_wait.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.offset_left = -300
	_wait.offset_right = 300
	_wait.offset_top = -150
	_wait.offset_bottom = -60
	_wait.add_theme_font_size_override("font_size", 34)
	_wait.add_theme_color_override("font_color", GOLD)
	_outline(_wait, 6)
	_wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_panel.custom_minimum_size = Vector2(440, 0)
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
	_status.custom_minimum_size = Vector2(400, 0)
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

	_host_b = _button(v, "HOST A GAME", _on_host)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_code_in = LineEdit.new()
	_code_in.placeholder_text = "room code"
	_code_in.max_length = 21
	_code_in.custom_minimum_size = Vector2(200, 44)
	_code_in.add_theme_font_size_override("font_size", 22)
	_code_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_in.text_changed.connect(_on_code_typed)
	_code_in.text_submitted.connect(func(_t): _on_join())
	row.add_child(_code_in)
	_join_b = _button(row, "JOIN", _on_join)
	_join_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_keys = GridContainer.new()
	_keys.columns = 11
	_keys.add_theme_constant_override("h_separation", 4)
	_keys.add_theme_constant_override("v_separation", 4)
	v.add_child(_keys)
	for ch in Net.ABC:
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
	_close_b = _button(row2, "CLOSE", close)
	var help := Label.new()
	help.text = "Host, then tell your friend the code. They press Join.\nThe host runs the game; you both play."
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	v.add_child(help)
	if net:
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

static func _add_action() -> void:
	if InputMap.has_action("net_menu"):
		return
	InputMap.add_action("net_menu")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_O
	InputMap.action_add_event("net_menu", k)
	var j := InputEventJoypadButton.new()
	j.button_index = JOY_BUTTON_LEFT_STICK
	InputMap.action_add_event("net_menu", j)

func _type(c: String) -> void:
	if _code_in.text.length() < 8:
		_code_in.text += c
	_code_in.caret_column = _code_in.text.length()

func _on_code_typed(t: String) -> void:
	var up := t.to_upper()
	if up != t:
		var cc := _code_in.caret_column
		_code_in.text = up
		_code_in.caret_column = cc

func _on_host() -> void:
	if net:
		net.host()

func _on_join() -> void:
	if net:
		net.join(_code_in.text)
	_code_in.release_focus()

func _on_leave() -> void:
	if net:
		net.leave()

func is_open() -> bool:
	return _open

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func open() -> void:
	if _open:
		return
	_open = true
	_panel.visible = true
	var p: Player = net.player if net else null
	if p and is_instance_valid(p):
		_was_controls = p.controls_enabled
		p.controls_enabled = false
		p.halt()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	(_leave_b if net and net.role != "local" else _host_b).grab_focus()

func close() -> void:
	if not _open:
		return
	_open = false
	_panel.visible = false
	var fo := get_viewport().gui_get_focus_owner()
	if fo:
		fo.release_focus()
	var p: Player = net.player if net else null
	if p and is_instance_valid(p):
		var fight := Fight.me
		p.controls_enabled = _was_controls if not (fight and fight.sim.started) else false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("net_menu") and not event.is_echo():
		if _open and _code_in.has_focus() and event is InputEventKey:
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("release_mouse")):
		close()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# a pad's B closes the menu (ui_cancel is Esc and the pad's B in Godot's defaults)
	if _open and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		close()
		get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	_refresh_wait()

func _refresh() -> void:
	if _status == null or net == null:
		return
	_status.text = net.status_text
	_status.add_theme_color_override("font_color", GOOD if net.status_kind == "live" else (BAD if net.status_kind == "bad" else Color(1, 1, 1, 0.9)))
	var hosting := net.role == "host"
	_room.text = ("you're hosting — room code" if hosting else ("joined room" if net.role == "client" else ""))
	_room.visible = net.role != "local"
	_code_big.text = net.code
	_code_big.visible = net.role != "local" and net.code != ""
	_leave_b.visible = net.role != "local"
	_host_b.text = "HOST A NEW ROOM" if hosting else "HOST A GAME"
	var label := "ONLINE (O)"
	if net.live:
		label = "ONLINE: %s  %s  %dms" % [net.code, "host" if hosting else "guest", net.ping_ms]
	elif net.role == "host":
		label = "ONLINE: room %s, waiting" % net.code
	elif net.role == "client":
		label = "ONLINE: joining %s" % net.code
	_btn.text = label

var _wait_t := 0.0
func _refresh_wait() -> void:
	if net == null:
		return
	var show := net.role == "host" and not net.live and net.code != "" and not _open
	_wait.visible = show
	if show:
		_wait.text = "room code\n" + net.code
	_wait_t += get_process_delta_time()
	if _wait_t > 0.5:
		_wait_t = 0.0
		_refresh()
