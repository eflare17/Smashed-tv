class_name Hud
extends CanvasLayer
## The on-screen bits for the player and cameras (Player and cameras task): the build label, what E does
## ("E: sit", under the crosshair in first person like the HTML game, above the bottom of the screen
## top-down), the round E button at the bottom right like the HTML game's carry button (click or tap it),
## which view and zoom, a crosshair in first person (and "click to look around with the mouse" when the
## pointer isn't held), and a small character picker (buttons, or keys 1, 2, 3).
##
## Give it the player and the rig (player, rig), or it finds the first node in group "player" and the first
## CameraRig in the scene.

## The playable characters and their names (the HTML game's charNames for the new art).
const CHARACTERS := [["juicy", "Juicy Jared"], ["tyson2", "Tornado Tyson"], ["goth", "Gothica"]]
const KEY_HELP := "WASD move   Shift roll   E use   V view   Z zoom   1 2 3 character"
const PAD_HELP := "left stick move   right stick aim / look   B roll   A use   View: first person   d-pad up zoom"
## Once the weapon bar has the number keys (number_keys_pick false).
const KEY_HELP_FIGHT := "WASD move   Shift roll   E use   V view   Z zoom   1-6 weapon   Enter start   Tab controls"
const PAD_HELP_FIGHT := "left stick move   right stick aim   RT fire   B roll   A use   d-pad left / right weapon   Menu start   d-pad down controls"
const PINK := Color("#f7a8ff")
const GOLD := Color("#f6d17a")

var player: Player
var rig: CameraRig
## The build label's text.
var build_text: String = "Godot M1"
## The pick_char_1..3 actions (keys 1, 2, 3) pick the character. The weapon bar (milestone 2) wants the number keys
## (weapon_1..6 are bound to 1-6 too): whoever installs it sets this false, and the picker's buttons stay.
var number_keys_pick: bool = true
## The phone and tablet controls (TouchControls), made in _ready; they show once a touch is seen.
var touch: TouchControls

var _build: Label
var _view: Label
var _prompt: Label
var _hint: Label
var _help: Label
var _cross: Control
var _ebtn: _EButton
var _picker: HBoxContainer
var _pick_btns: Array[Button] = []
var _sound_btn: Button
## Sound on or off (the HTML game's #muteBtn "Sound: on"): the Master bus muted, remembered in user://smashed.cfg.
static var sound_on := true
static var _sound_loaded := false

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build = _label(root, build_text, 14, Color(1, 1, 1, 0.75))
	_build.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_build.offset_left = 12
	_build.offset_right = 212
	_build.offset_top = -28
	_build.offset_bottom = -8

	_view = _label(root, "", 14, Color(1, 1, 1, 0.9))
	_view.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_view.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_view.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_view.offset_left = -360
	_view.offset_right = -12
	_view.offset_top = 10

	_help = _label(root, KEY_HELP, 12, Color(1, 1, 1, 0.55))
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.offset_top = -26
	_help.offset_bottom = -8

	_prompt = _label(root, "", 21, PINK)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.custom_minimum_size = Vector2(600, 0)
	_prompt.offset_left = -300
	_prompt.offset_right = 300

	_hint = _label(root, "click to look around with the mouse", 18, GOLD)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.offset_top = -50
	_hint.offset_bottom = -26

	_cross = _Crosshair.new()
	_cross.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_cross)

	_ebtn = _EButton.new()
	_ebtn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_ebtn.offset_left = -86 - 48
	_ebtn.offset_right = -86 + 48
	_ebtn.offset_top = -190 - 48
	_ebtn.offset_bottom = -190 + 48
	_ebtn.pressed.connect(func(): if player: player.use())
	root.add_child(_ebtn)

	_picker = HBoxContainer.new()
	_picker.position = Vector2(12, 10)
	_picker.add_theme_constant_override("separation", 6)
	root.add_child(_picker)
	for i in CHARACTERS.size():
		var b := Button.new()
		b.text = _pick_text(i)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 13)
		var id: String = CHARACTERS[i][0]
		b.pressed.connect(func(): pick(id))
		_picker.add_child(b)
		_pick_btns.append(b)

	_sound_btn = Button.new()
	_sound_btn.focus_mode = Control.FOCUS_NONE
	_sound_btn.add_theme_font_size_override("font_size", 13)
	_sound_btn.pressed.connect(func(): set_sound(not sound_on))
	_picker.add_child(_sound_btn)
	if not InputMap.has_action("mute"):
		InputMap.add_action("mute")
		var mk := InputEventKey.new()
		mk.physical_keycode = KEY_F9
		InputMap.action_add_event("mute", mk)
	if not _sound_loaded:
		_sound_loaded = true
		var cf := ConfigFile.new()
		if cf.load("user://smashed.cfg") == OK:
			sound_on = bool(cf.get_value("sound", "on", true))
	set_sound(sound_on, false)

	touch = TouchControls.new()
	touch.name = "Touch"
	touch.hud = self
	root.add_child(touch)
	root.move_child(touch, 0)               # under the other bits: the E button and the picker take their own touches

func _label(parent: Control, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	# an outline, never a font shadow: with a shadow the Compatibility renderer draws text a letter at a time (one
	# draw call each: the help line alone was 88), with only an outline a label is about two
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l

## Sound on or off (F9, or the Sound button).
func set_sound(on: bool, save: bool = true) -> void:
	sound_on = on
	AudioServer.set_bus_mute(0, not on)
	if _sound_btn:
		_sound_btn.text = "Sound: on" if on else "Sound: off"
	if save:
		var cf := ConfigFile.new()
		cf.load("user://smashed.cfg")
		cf.set_value("sound", "on", on)
		cf.save("user://smashed.cfg")

func _pick_text(i: int) -> String:
	return ("%d  %s" % [i + 1, CHARACTERS[i][1]]) if number_keys_pick else String(CHARACTERS[i][1])

## Make the player this character ("juicy", "tyson2", "goth").
func pick(id: String) -> void:
	# (not while lobby life holds him: lying in bed, lifting, at the mirror its picture of him stays as it was)
	var ll := LobbyLife.current
	if player and ll and (ll.busy.has(player) or ll.pose_of(player) != null):
		return
	if player:
		player.char_id = id

## The last thing used was a controller: the prompts say A, not E (the HTML game's actKey).
var pad_last: bool = false

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		pad_last = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		pad_last = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch:
		pad_last = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute") and not event.is_echo():
		set_sound(not sound_on)
		get_viewport().set_input_as_handled()
		return
	if not number_keys_pick or event.is_echo():
		return
	for i in CHARACTERS.size():
		if event.is_action_pressed("pick_char_%d" % (i + 1)):
			pick(CHARACTERS[i][0])
			get_viewport().set_input_as_handled()
			return

## Is screen point p (pixels) on the round E button while it shows? (The touch layer leaves those touches to it.)
func e_button_hit(p: Vector2) -> bool:
	if _ebtn == null or not _ebtn.is_visible_in_tree():
		return false
	var r := _ebtn.get_global_rect()
	return p.distance_to(r.get_center()) <= minf(r.size.x, r.size.y) / 2.0 + 6.0

func _find() -> void:
	if player == null or not is_instance_valid(player):
		var ps := get_tree().get_nodes_in_group("player")
		player = ps[0] if ps.size() > 0 else null
	if rig == null or not is_instance_valid(rig):
		if player and player.rig is CameraRig:
			rig = player.rig
		else:
			rig = _find_rig(get_tree().root)

func _find_rig(n: Node) -> CameraRig:
	if n is CameraRig:
		return n
	for c in n.get_children():
		var r := _find_rig(c)
		if r:
			return r
	return null

func _process(_delta: float) -> void:
	_find()
	_build.text = build_text
	var fp := rig != null and rig.mode == CameraRig.Mode.FIRST_PERSON
	var keys := not pad_last and not (touch and touch.active)
	var view := "First person" if fp else "Top-down"
	if keys:
		view += " (V)"
	elif pad_last:
		view += " (View)"
	if rig and not fp:
		var zt := rig.zoom_text()
		if not keys:
			zt = zt.replace(" (Z)", "")
		view += "    " + zt
	_view.text = view
	_cross.visible = fp
	_hint.visible = fp and rig != null and not rig.mouse_captured() and not _touch_only() and not (touch and touch.active)
	var label := player.focus_label if player else ""
	var txt := (("A: " if pad_last else "E: ") + label.to_lower()) if label != "" else ""
	if number_keys_pick:
		_help.text = PAD_HELP if pad_last else KEY_HELP
	else:
		_help.text = PAD_HELP_FIGHT if pad_last else KEY_HELP_FIGHT
	for i in _pick_btns.size():
		var pt := _pick_text(i)
		if _pick_btns[i].text != pt:
			_pick_btns[i].text = pt
	_help.visible = touch == null or not touch.active
	_prompt.text = txt
	# first person only, under the crosshair (the HTML game's spot); top-down the round E button says it
	_prompt.visible = txt != "" and fp
	# under the crosshair in first person (the HTML game's spot); top-down, above the help line
	var vp := get_viewport().get_visible_rect().size
	if fp:
		_prompt.offset_top = 30
		_prompt.offset_bottom = 60
	else:
		_prompt.offset_top = vp.y / 2.0 - 78
		_prompt.offset_bottom = vp.y / 2.0 - 48
	_ebtn.label = label
	_ebtn.visible = label != ""
	# with the pointer held (first person) a click is the game's, never a button's: the pointer's position is
	# stale then, wherever it was let go
	var held := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_ebtn.mouse_filter = Control.MOUSE_FILTER_IGNORE if held else Control.MOUSE_FILTER_STOP
	for b in _pick_btns + [_sound_btn]:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE if held else Control.MOUSE_FILTER_STOP
	for i in _pick_btns.size():
		_pick_btns[i].set_pressed_no_signal(player != null and player.char_id == CHARACTERS[i][0])

func _touch_only() -> bool:
	return DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")

## The HTML game's carry button: a dark round button, pink ring and pink capitals.
class _EButton extends Control:
	signal pressed
	var label: String = "":
		set(v):
			if v != label:
				label = v
				queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var r := minf(size.x, size.y) / 2.0
		var c := size / 2.0
		draw_circle(c, r, Color(20 / 255.0, 12 / 255.0, 28 / 255.0, 0.72))
		draw_arc(c, r - 1.5, 0, TAU, 64, PINK, 3.0, true)
		var f := get_theme_default_font()
		var fs := 17
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > r * 1.8:
			fs = int(fs * r * 1.8 / w)
			w = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var asc := f.get_ascent(fs)
		var desc := f.get_descent(fs)
		draw_string(f, c + Vector2(-w / 2.0, (asc - desc) / 2.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PINK)

	func _gui_input(event: InputEvent) -> void:
		var hit := false
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hit = true
		elif event is InputEventScreenTouch and event.pressed and not _touch_is_mouse():
			hit = true                         # (a touch also arrives as a click when touch emulates the mouse)
		if hit and (event.position - size / 2.0).length() <= minf(size.x, size.y) / 2.0:
			pressed.emit()
			accept_event()

	static func _touch_is_mouse() -> bool:
		return bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true))

## The HTML game's first-person crosshair: four short white strokes round the middle.
class _Crosshair extends Control:
	func _draw() -> void:
		var col := Color(1, 1, 1, 0.8)
		var a := 3.0
		var b := 10.0
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(d * a, d * b, col, 2.0, true)
