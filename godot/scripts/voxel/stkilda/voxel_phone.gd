class_name VoxelPhone
extends Control
## The phone (the owner, 27 Oct: "a phone-style menu pops up and you fast travel"): P gets it out, bottom right.
## One app so far, Travel: Home (the arena), St Kilda (Luna Park, VoxelStKilda), a game there (Kill 1, 2 come:
## VoxelParkGame), or the gun range (VoxelGunRange). Pick one (a click, or its number) and
## the screen goes black a moment and you're there. P or Esc puts it away. Not while playing with a mate (yet).

const W := 270.0
const H := 600.0
const PLACES := [["home", "Home", "The arena"], ["stkilda", "St Kilda", "Luna Park"], ["kill12", "Kill 1, 2 come", "A game in Luna Park"],
	["range", "Gun range", "Try every weapon"]]

var arena: VoxelArena
var stkilda: VoxelStKilda
var _open := false
var _buttons := {}                  # place id -> its Button
var _note: Label
var _clock: Label
var _black: ColorRect
var _black_label: Label
var _going := false

func setup(a: VoxelArena, sk: VoxelStKilda) -> void:
	arena = a
	stkilda = sk
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := Panel.new()
	body.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	body.position = Vector2(-W - 40.0, -H - 70.0)
	body.size = Vector2(W, H)
	body.add_theme_stylebox_override("panel", _box(Color("#16161c"), 30, Color("#3a3a46"), 3))
	body.name = "Phone"
	add_child(body)
	var screen := Panel.new()
	screen.position = Vector2(12, 14)
	screen.size = Vector2(W - 24, H - 28)
	screen.add_theme_stylebox_override("panel", _box(Color("#22324f"), 22))
	body.add_child(screen)
	_clock = _label(screen, "", 14, Vector2(18, 10), Color(1, 1, 1, 0.85))
	var notch := Panel.new()
	notch.position = Vector2((W - 24) / 2.0 - 40.0, 8)
	notch.size = Vector2(80, 18)
	notch.add_theme_stylebox_override("panel", _box(Color("#16161c"), 9))
	screen.add_child(notch)
	_label(screen, "Travel", 30, Vector2(20, 46), Color.WHITE)
	_label(screen, "Where to?", 16, Vector2(22, 88), Color(0.8, 0.86, 1.0))
	var y := 124.0
	for i in PLACES.size():
		var p: Array = PLACES[i]
		var b := Button.new()
		b.position = Vector2(16, y)
		b.size = Vector2(W - 56, 78)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", _box(Color("#f2f2f6"), 16))
		b.add_theme_stylebox_override("hover", _box(Color("#ffffff"), 16, Color("#ffd54a"), 3))
		b.add_theme_stylebox_override("pressed", _box(Color("#ffe58a"), 16))
		b.add_theme_stylebox_override("disabled", _box(Color("#8792a8"), 16))
		b.pressed.connect(travel.bind(String(p[0])))
		screen.add_child(b)
		_label(b, "%d  %s" % [i + 1, p[1]], 24, Vector2(16, 8), Color("#1a1c2c"))
		var sub := _label(b, String(p[2]), 16, Vector2(42, 44), Color("#4a4f63"))
		sub.name = "Sub"
		_buttons[p[0]] = b
		y += 88.0
	_note = _label(screen, "", 14, Vector2(18, H - 28 - 80), Color(1.0, 0.85, 0.4))
	_note.size = Vector2(W - 60, 40)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_label(screen, "P or Esc: put it away", 13, Vector2(18, H - 28 - 30), Color(1, 1, 1, 0.6))
	body.visible = false
	# the trip: the screen goes black, then you're there
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	_black.visible = false
	add_child(_black)
	_black_label = Label.new()
	_black_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_black_label.offset_left = -300
	_black_label.offset_right = 300
	_black_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_black_label.add_theme_font_size_override("font_size", 26)
	_black.add_child(_black_label)

func is_open() -> bool:
	return _open or _going

func open() -> void:
	_open = true
	get_node("Phone").visible = true
	var here := "home"
	if stkilda.active:
		here = "kill12" if stkilda.game and stkilda.game.running else "stkilda"
	elif arena.gun_range.active:
		here = "range"
	var coop: bool = arena.net != null and arena.net.role != ""
	for id in _buttons:
		var b: Button = _buttons[id]
		b.disabled = id == here or coop
		var sub: Label = b.get_node("Sub")
		sub.text = "You're here" if id == here else String(PLACES.filter(func(pl: Array) -> bool: return pl[0] == id)[0][2])
		if id == "kill12" and stkilda.game and stkilda.game.over:
			sub.text = "Play again (best %d kills)" % stkilda.game.best_kills
	_note.text = "Travel's off while you're playing with a mate (for now)." if coop else ""
	var t := Time.get_time_dict_from_system()
	_clock.text = "%d:%02d" % [t.hour, t.minute]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	_open = false
	get_node("Phone").visible = false
	if not arena.top_down:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func can_open() -> bool:
	return not (arena.inv_ui.is_open() or arena.lock_view.is_open() or arena.lying > 0 or arena.games.seated > 0
			or arena.games.held >= 0 or arena.mine.active or arena.down_t > 0.0
			or (arena.net_menu and arena.net_menu.is_open()) or (arena.settings_menu and arena.settings_menu.is_open())
			or (arena.guide and arena.guide.is_open()))

func _unhandled_input(e: InputEvent) -> void:
	if _going or not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k := (e as InputEventKey).physical_keycode
	if _open:
		if k == KEY_P or k == KEY_ESCAPE:
			close()
		elif k >= KEY_1 and k < KEY_1 + PLACES.size():
			var id: String = PLACES[k - KEY_1][0]
			if not (_buttons[id] as Button).disabled:
				travel(id)
		get_viewport().set_input_as_handled()     # (the phone's out: the keys are its)
	elif k == KEY_P and can_open():
		open()
		get_viewport().set_input_as_handled()

## Go: black, there, back from black.
func travel(id: String) -> void:
	if _going:
		return
	_going = true
	close()
	_black_label.text = {"stkilda": "Off to St Kilda ...", "kill12": "Kill 1, 2 come: Luna Park ...", "range": "To the gun range ..."}.get(id, "Heading home ...")
	_black.visible = true
	var tw := create_tween()
	tw.tween_property(_black, "modulate:a", 1.0, 0.35)
	await tw.finished
	await get_tree().process_frame               # (the black drawn before the build stalls a frame)
	await get_tree().process_frame
	if id != "range":
		arena.gun_range.home()                 # (off the range first: back where you were in the arena)
	match id:
		"stkilda":
			if stkilda.active:
				stkilda.game.stop()
			stkilda.go()
		"kill12":
			stkilda.go()
			stkilda.game.start()
		"range":
			stkilda.home()
			arena.gun_range.go()
		_:
			stkilda.home()
	await get_tree().create_timer(0.25).timeout
	tw = create_tween()
	tw.tween_property(_black, "modulate:a", 0.0, 0.45)
	await tw.finished
	_black.visible = false
	_going = false

static func _box(c: Color, r: int, border := Color.TRANSPARENT, bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	return s

static func _label(parent: Control, text: String, size: int, at: Vector2, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
