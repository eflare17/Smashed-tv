class_name LobbyShirtEditor
extends Control
## The shirt editor (Smashed.html: SHED, shirtEditorGeo @1801, drawShirtEditor @1829, shirtEditorDown/Move): a panel
## showing the back or front of Jared's singlet with your picture on it; drag the picture to move it, drag a corner
## to stretch it, and PICK PICTURE / FIT / FILL / TURN AROUND / LOOK / DONE / CANCEL. It only ever goes on the shirt
## (LobbyLook masks it). Owned by the Lobby life session.
##
## Port decisions: Godot controls (mouse, touch and the pad's focus all work on the buttons), and the preview is the
## real baked frame, cropped round the shirt, so what you see is what is printed.

signal closed

var back: bool = false
var place: Rect2 = Rect2(0, 0, 1, 1)
var smooth: bool = true

var _panel: Panel
var _view: Control
var _preview: Image
var _tex: ImageTexture
var _box: Rect2i
var _src: Rect2          # the square of the frame the view shows
var _k: float = 1.0
var _drag: String = ""
var _off: Vector2 = Vector2.ZERO
var _title: Label
var _turn_btn: Button
var _look_btn: Button
var _frames: Dictionary = {}

const VIEW := 250.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(8 / 255.0, 10 / 255.0, 14 / 255.0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(20 / 255.0, 12 / 255.0, 28 / 255.0, 0.96)
	sb.border_color = Color("#f7a8ff")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(430, 330)
	_panel.size = Vector2(430, 330)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -215
	_panel.offset_right = 215
	_panel.offset_top = -165
	_panel.offset_bottom = 165
	add_child(_panel)
	_title = Label.new()
	_title.position = Vector2(16, 8)
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", Color("#f7a8ff"))
	_panel.add_child(_title)
	var foot := Label.new()
	foot.text = "drag to move · drag a corner to stretch · it only goes on the shirt"
	foot.position = Vector2(16, 304)
	foot.add_theme_font_size_override("font_size", 11)
	foot.add_theme_color_override("font_color", Color("#8b93a4"))
	_panel.add_child(foot)
	_view = Control.new()
	_view.position = Vector2(16, 40)
	_view.size = Vector2(VIEW, VIEW)
	_view.custom_minimum_size = Vector2(VIEW, VIEW)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_view_input)
	_panel.add_child(_view)
	var x := 286.0
	_btn("PICK PICTURE", Vector2(x, 38), Color("#3a2150"), _on_pick)
	_btn("FIT", Vector2(x, 70), Color("#3a2150"), func(): _fit("fit"))
	_btn("FILL", Vector2(x, 102), Color("#3a2150"), func(): _fit("fill"))
	_turn_btn = _btn("TURN AROUND", Vector2(x, 134), Color("#3a2150"), _on_turn)
	_look_btn = _btn("LOOK: PHOTO", Vector2(x, 166), Color("#3a2150"), _on_look)
	_btn("DONE", Vector2(x, 250), Color("#1f5a36"), _on_done)
	_btn("CANCEL", Vector2(x, 284), Color("#5a1f28"), _on_cancel)

func _btn(text: String, pos: Vector2, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(128, 28)
	b.add_theme_font_size_override("font_size", 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color("#f7a8ff")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = col.lightened(0.2)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("focus", hv)
	b.pressed.connect(cb)
	_panel.add_child(b)
	return b

func is_open() -> bool:
	return visible

## openShirtEditor: starts on the front with the saved place.
func open() -> void:
	if LobbyLook.art_front == null:
		return
	back = false
	smooth = LobbyLook.smooth
	_load_side()
	visible = true
	_refresh()
	for c in _panel.get_children():
		if c is Button:
			c.grab_focus.call_deferred()
			break

func _load_side() -> void:
	var a := _art()
	if back:
		place = LobbyLook.place_back if LobbyLook.art_back != null else LobbyLook.fit_place(a, Vector2(_box_of(true).size), "fill")
	else:
		place = LobbyLook.place_front
	_title.text = "BACK OF HIS SHIRT" if back else "FRONT OF HIS SHIRT"
	_turn_btn.text = "SHOW FRONT" if back else "TURN AROUND"
	_look_btn.text = "LOOK: PHOTO" if smooth else "LOOK: PIXEL"

func _art() -> Image:
	return (LobbyLook.art_back if (back and LobbyLook.art_back != null) else LobbyLook.art_front)

func _frame(b: bool) -> Image:
	var k := "back" if b else "front"
	if not _frames.has(k):
		var t := GameData.tex("assets/CHARS/juicy/sprites/%s_run_0.png" % k)
		var im := t.get_image()
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
		_frames[k] = im
	return _frames[k]

func _box_of(b: bool) -> Rect2i:
	return LobbyLook.shirt_box(_frame(b))

func _refresh() -> void:
	var im := _frame(back)
	_box = LobbyLook.shirt_box(im)
	if _box.size.x <= 0:
		return
	var a := _art()
	var pv := LobbyLook.preview(im, back, place, a, smooth)
	var mx := maxi(_box.size.x, _box.size.y)
	var pad := int(round(mx * 0.28))
	var s := mx + 2 * pad
	var cx := _box.position.x + _box.size.x / 2.0
	var cy := _box.position.y + _box.size.y / 2.0
	_src = Rect2(cx - s / 2.0, cy - s / 2.0, s, s)
	var out := Image.create(s, s, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.067, 0.078, 0.106, 1.0))
	var sx := int(round(_src.position.x))
	var sy := int(round(_src.position.y))
	out.blend_rect(pv, Rect2i(sx, sy, s, s) if sx >= 0 and sy >= 0 else Rect2i(0, 0, pv.get_width(), pv.get_height()), Vector2i.ZERO if (sx >= 0 and sy >= 0) else Vector2i(-sx, -sy))
	_tex = ImageTexture.create_from_image(out)
	_k = VIEW / float(s)
	_view.queue_redraw()

# the picture's rectangle on the view, pixels
func _pic_rect() -> Rect2:
	var bx := float(_box.position.x)
	var by := float(_box.position.y)
	var bw := float(_box.size.x)
	var bh := float(_box.size.y)
	return Rect2((bx + place.position.x * bw - _src.position.x) * _k, (by + place.position.y * bh - _src.position.y) * _k,
		maxf(1.0, place.size.x * bw) * _k, maxf(1.0, place.size.y * bh) * _k)

func _draw_view() -> void:
	_view.draw_rect(Rect2(0, 0, VIEW, VIEW), Color("#11141b"))
	if _tex:
		_view.draw_texture_rect(_tex, Rect2(0, 0, VIEW, VIEW), false)
	if _box.size.x <= 0:
		return
	var br := Rect2((_box.position.x - _src.position.x) * _k, (_box.position.y - _src.position.y) * _k, _box.size.x * _k, _box.size.y * _k)
	_dashed(br, Color(0.435, 0.827, 0.627, 0.35))
	var pr := _pic_rect()
	_dashed(pr, Color(0.965, 0.82, 0.48, 0.55))
	for c in _corners(pr):
		_view.draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), Color("#1c1a22"))
		_view.draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), Color("#f6d17a"))

func _dashed(r: Rect2, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		_view.draw_dashed_line(pts[i], pts[i + 1], col, 1.5, 4.0)

func _corners(r: Rect2) -> Array:
	return [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]

func _view_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_down(e.position)
		else:
			_drag = ""
	elif e is InputEventMouseMotion and _drag != "":
		_move(e.position)

func _to_place(p: Vector2) -> Vector2:
	var f := Vector2(_src.position.x + p.x / _k, _src.position.y + p.y / _k)
	return Vector2((f.x - _box.position.x) / _box.size.x, (f.y - _box.position.y) / _box.size.y)

func _down(p: Vector2) -> void:
	var pr := _pic_rect()
	var names := ["nw", "ne", "sw", "se"]
	var cs := _corners(pr)
	for i in 4:
		if p.distance_to(cs[i]) <= 16.0:
			_drag = names[i]
			return
	if pr.has_point(p):
		_drag = "move"
		_off = _to_place(p) - place.position

func _move(p: Vector2) -> void:
	var q := _to_place(p)
	const MIN := 0.08
	var r := place
	match _drag:
		"move":
			place.position = q - _off
		"nw":
			var rr := place.end
			place = Rect2(minf(q.x, rr.x - MIN), minf(q.y, rr.y - MIN), 0, 0)
			place.size = Vector2(rr.x - place.position.x, rr.y - place.position.y)
		"ne":
			var ll_ := Vector2(place.position.x, place.end.y)
			var top := minf(q.y, ll_.y - MIN)
			place = Rect2(ll_.x, top, maxf(MIN, q.x - ll_.x), ll_.y - top)
		"sw":
			var ur := Vector2(place.end.x, place.position.y)
			var left := minf(q.x, ur.x - MIN)
			place = Rect2(left, ur.y, ur.x - left, maxf(MIN, q.y - ur.y))
		"se":
			place.size = Vector2(maxf(MIN, q.x - place.position.x), maxf(MIN, q.y - place.position.y))
	if place != r:
		_refresh()

func _fit(mode: String) -> void:
	place = LobbyLook.fit_place(_art(), Vector2(_box.size), mode)
	_refresh()

func _save_side() -> void:
	if back and LobbyLook.art_back != null:
		LobbyLook.place_back = place
	elif not back:
		LobbyLook.place_front = place

func _on_turn() -> void:
	_save_side()
	back = not back
	_load_side()
	_refresh()

func _on_look() -> void:
	smooth = not smooth
	LobbyLook.smooth = smooth
	LobbyLook.rev += 1
	_look_btn.text = "LOOK: PHOTO" if smooth else "LOOK: PIXEL"
	_refresh()

func _on_pick() -> void:
	LobbyLook.pick_picture(self, func(im: Image) -> void: take_picture(im))

## loadShirtArt's end: the picture is the front's (or the back's if that's the side showing), fitted.
func take_picture(im: Image) -> void:
	LobbyLook.set_art(im, back)
	if not visible:
		back = false
		smooth = LobbyLook.smooth
		visible = true
	place = LobbyLook.fit_place(_art(), Vector2(_box_of(back).size), "fill" if back else "fit")
	_title.text = "BACK OF HIS SHIRT" if back else "FRONT OF HIS SHIRT"
	_turn_btn.text = "SHOW FRONT" if back else "TURN AROUND"
	_save_side()
	_refresh()

func _on_done() -> void:
	_save_side()
	LobbyLook.smooth = smooth
	LobbyLook.rev += 1
	LobbyLook.save()
	visible = false
	closed.emit()

func _on_cancel() -> void:
	visible = false
	closed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if visible and e.is_action_pressed("lobby_back"):
		_on_cancel()
		get_viewport().set_input_as_handled()
