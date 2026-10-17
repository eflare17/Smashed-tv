class_name LobbyUI
extends CanvasLayer
## Lobby life's overlay, over the game in both views: speech bubbles over people (following them on screen),
## floating words (+20 KG, $5...), the money line, menus with big buttons (mouse, touch, and a pad: the first
## button has focus, the d-pad moves, A picks, B leaves), and full-screen layers the trips draw on.
## Owned by the Lobby life session.

var ll: LobbyLife
var root: Control
## Full-screen layers under the menus (trips, the mirror) can go here.
var fx_root: Control

var _bubbles: Array = []        # {node, text, t, dur, head, ctl}
var _floaters: Array = []       # {pos (Vector3), text, col, t, dur, ctl}
var _money: Label
var _money_shown: int = -999999
var _money_t: float = 0.0
var _menu: PanelContainer
var _menu_box: VBoxContainer
var _menu_title: Label
var _menu_cancel: Callable
var _info: Label

const PINK := Color("#f7a8ff")
const GOLD := Color("#f6d17a")

func _ready() -> void:
	layer = 11
	fx_root = Control.new()
	fx_root.name = "Fx"
	fx_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_root)
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_money = _label("", 18, GOLD)
	_money.position = Vector2(14, 44)
	root.add_child(_money)
	_info = _label("", 20, Color.WHITE)
	_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.offset_left = -420
	_info.offset_right = 420
	_info.offset_top = 70
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_info)

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l

# ------------------------------------------------------------------ speech bubbles

## Say text over node (a person) for dur seconds; head is how high over its feet the bubble's tail points (units).
func say(node: Node3D, text: String, dur: float = 2.6, head: float = 92.0) -> void:
	for b in _bubbles:
		if b.node == node:
			b.text = text
			b.t = 0.0
			b.dur = dur
			b.ctl.text = text
			b.ctl.queue_redraw()
			return
	var c := _Bubble.new()
	c.text = text
	root.add_child(c)
	_bubbles.append({"node": node, "text": text, "t": 0.0, "dur": dur, "head": head, "ctl": c})

## What node is saying now ("" for nothing).
func saying(node: Node3D) -> String:
	for b in _bubbles:
		if b.node == node:
			return b.text
	return ""

func hush(node: Node3D) -> void:
	for b in _bubbles.duplicate():
		if b.node == node:
			b.ctl.queue_free()
			_bubbles.erase(b)

# ------------------------------------------------------------------ floating words

## Words rising from a spot (HTML units) and fading, like the HTML game's floaters.
func float_text(x: float, y: float, z: float, text: String, col: Color = GOLD, dur: float = 1.2, size: int = 18) -> void:
	var l := _label(text, size, col)
	root.add_child(l)
	_floaters.append({"pos": GameData.world_to_3d(x, y, z), "t": 0.0, "dur": dur, "ctl": l})

## A line across the top of the screen (the result of a hand, the slot's prize...); "" clears it.
func info(text: String, dur: float = 2.5) -> void:
	_info.text = text
	_info.set_meta("t", dur)

# ------------------------------------------------------------------ menus

## A menu of big buttons: options is [[label, Callable], ...]; cancel runs on B / Esc / Backspace / the X.
func menu(title: String, options: Array, cancel: Callable = Callable()) -> void:
	close_menu()
	_menu = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(20 / 255.0, 12 / 255.0, 28 / 255.0, 0.88)
	sb.border_color = PINK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	_menu.add_theme_stylebox_override("panel", sb)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu.offset_bottom = -120
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 8)
	_menu.add_child(_menu_box)
	_menu_title = _label(title, 20, PINK)
	_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_box.add_child(_menu_title)
	var first: Button = null
	for o in options:
		var b := Button.new()
		b.text = String(o[0])
		b.custom_minimum_size = Vector2(300, 46)
		b.add_theme_font_size_override("font_size", 18)
		var cb: Callable = o[1]
		b.pressed.connect(func(): cb.call())
		_menu_box.add_child(b)
		if first == null:
			first = b
	root.add_child(_menu)
	_menu_cancel = cancel
	if first:
		first.grab_focus.call_deferred()

func menu_open() -> bool:
	return _menu != null and is_instance_valid(_menu)

func close_menu() -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null
	_menu_cancel = Callable()

## The menu's buttons (tests press them).
func menu_buttons() -> Array:
	var out: Array = []
	if menu_open():
		for c in _menu_box.get_children():
			if c is Button:
				out.append(c)
	return out

func _unhandled_input(event: InputEvent) -> void:
	if not menu_open():
		return
	var back := event.is_action_pressed("lobby_back") or event.is_action_pressed("ui_cancel")
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		back = true
	if back:
		var c := _menu_cancel
		close_menu()
		if c.is_valid():
			c.call()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ every frame

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	for b in _bubbles.duplicate():
		b.t += delta
		var n = b.node
		if b.t >= b.dur or not is_instance_valid(n) or not n.is_inside_tree():
			b.ctl.queue_free()
			_bubbles.erase(b)
			continue
		var p: Vector3 = n.global_position + Vector3(0, b.head * GameData.UNIT, 0)
		var show: bool = cam != null and not cam.is_position_behind(p) and n.is_visible_in_tree()
		b.ctl.visible = show
		if show:
			b.ctl.tip = cam.unproject_position(p)
			b.ctl.alpha = clampf((b.dur - b.t) / 0.3, 0.0, 1.0)
			b.ctl.queue_redraw()
	for f in _floaters.duplicate():
		f.t += delta
		if f.t >= f.dur:
			f.ctl.queue_free()
			_floaters.erase(f)
			continue
		var p: Vector3 = f.pos + Vector3(0, f.t * 40.0 * GameData.UNIT, 0)
		var show2: bool = cam != null and not cam.is_position_behind(p)
		f.ctl.visible = show2
		if show2:
			var sp := cam.unproject_position(p)
			f.ctl.position = sp - f.ctl.size / 2.0
			f.ctl.modulate.a = clampf((f.dur - f.t) / 0.4, 0.0, 1.0)
	if _info.has_meta("t"):
		var t: float = _info.get_meta("t") - delta
		_info.set_meta("t", t)
		if t <= 0.0:
			_info.text = ""
			_info.remove_meta("t")
	# the money: shown for a while when it changes (and in the lobby with a menu up)
	if ll and ll.player:
		var c := ll.cash(ll.player)
		if c != _money_shown:
			_money_shown = c
			_money_t = 4.0
		_money_t -= delta
		_money.text = "$%d" % c
		_money.visible = _money_t > 0.0 or menu_open()

## A speech bubble: a white rounded box with dark words and a tail down to the speaker, like the HTML game's.
class _Bubble extends Control:
	var text: String = ""
	var tip: Vector2 = Vector2.ZERO
	var alpha: float = 1.0
	const FS := 15

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := get_theme_default_font()
		var lines := _wrap(f, text, 220.0)
		var w := 0.0
		for l in lines:
			w = maxf(w, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x)
		var lh := f.get_height(FS)
		var bw := w + 18.0
		var bh := lh * lines.size() + 10.0
		var x := tip.x - bw / 2.0
		var y := tip.y - 12.0 - bh
		var vp := get_viewport_rect().size
		x = clampf(x, 4.0, vp.x - bw - 4.0)
		y = clampf(y, 4.0, vp.y - bh - 4.0)
		var bg := Color(1, 1, 1, 0.95 * alpha)
		var edge := Color(0.1, 0.05, 0.12, alpha)
		var r := Rect2(x, y, bw, bh)
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = edge
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(9)
		draw_style_box(sb, r)
		var tx := clampf(tip.x, x + 12.0, x + bw - 12.0)
		var tri := PackedVector2Array([Vector2(tx - 7, y + bh - 1), Vector2(tx + 7, y + bh - 1), Vector2(tip.x, tip.y - 2)])
		draw_colored_polygon(tri, bg)
		draw_line(tri[0], tri[2], edge, 2.0, true)
		draw_line(tri[1], tri[2], edge, 2.0, true)
		for i in lines.size():
			var lw := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
			draw_string(f, Vector2(x + (bw - lw) / 2.0, y + 5.0 + f.get_ascent(FS) + i * lh), lines[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0.12, 0.06, 0.14, alpha))

	static func _wrap(f: Font, s: String, maxw: float) -> PackedStringArray:
		var out := PackedStringArray()
		var cur := ""
		for word in s.split(" "):
			var t := word if cur == "" else cur + " " + word
			if cur != "" and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x > maxw:
				out.append(cur)
				cur = word
			else:
				cur = t
		if cur != "":
			out.append(cur)
		return out
