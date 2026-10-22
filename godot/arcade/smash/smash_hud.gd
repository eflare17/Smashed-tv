extends CanvasLayer
## Smash arcade HUD: room / wave, power-up timers, score and lives along the top, a centre banner, a crosshair in
## first person, the debug overlay, the red hurt flash and the black fade between rooms, the attract screens
## (title, high-score table, controls), the initials entry, and the TV host. Every Control is made once here; the
## scene root only sets text and visibility. It lives in the scene's own viewport (so on a cabinet it draws on
## the cabinet screen), and nothing in it takes mouse input.

const SmashHost := preload("smash_host.gd")

const HELP := "MOVE  WASD / left stick\nSHOOT  arrows, mouse / right stick, RT\nFIRST PERSON  C / Y\n\n" \
		+ "Grab the crates: SPREAD, ROCKETS, SHIELD, SPEED\nClear the room, then take the green door"

var room_label: Label
var power_label: Label
var score_label: Label
var lives_label: Label
var banner: Label
var crosshair: Label
var debug_label: Label
var host: SmashHost

var _flash: ColorRect
var _fade: ColorRect
var _title: Label
var _press: Label
var _help: Label
var _table: Control
var _rows: Array = []
var _name: Label

var _banner_t := 0.0
var _flash_a := 0.0

func _init() -> void:
	name = "SmashHud"
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	room_label = _label(root, 28, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	power_label = _label(root, 22, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	power_label.position.y += 38
	score_label = _label(root, 28, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER)
	lives_label = _label(root, 28, Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	banner = _label(root, 64, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
	banner.visible = false
	crosshair = _label(root, 32, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
	crosshair.text = "+"
	crosshair.visible = false
	debug_label = _label(root, 16, Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	debug_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	_title = _label(root, 120, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
	_title.text = "SMASH"
	_title.label_settings.font_color = Color(1.0, 0.85, 0.2)
	_title.label_settings.outline_size = 24
	_title.position.y -= 70
	_press = _label(root, 32, Control.PRESET_CENTER_BOTTOM, HORIZONTAL_ALIGNMENT_CENTER)
	_press.text = "PRESS FIRE OR ENTER TO PLAY"
	_press.offset_top = -120
	_press.offset_bottom = -120
	_help = _label(root, 30, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
	_help.text = HELP
	_name = _label(root, 44, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)

	# high-score table: heading + 10 rows of rank / name / score / room, built once
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	var head := _cell(box, "HIGH SCORES", 40, HORIZONTAL_ALIGNMENT_CENTER)
	head.label_settings.font_color = Color(1.0, 0.85, 0.2)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 36)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(grid)
	for i in 10:
		_rows.append([
			_cell(grid, "%d." % (i + 1), 24, HORIZONTAL_ALIGNMENT_RIGHT),
			_cell(grid, "", 24, HORIZONTAL_ALIGNMENT_LEFT),
			_cell(grid, "", 24, HORIZONTAL_ALIGNMENT_RIGHT),
			_cell(grid, "", 24, HORIZONTAL_ALIGNMENT_RIGHT),
		])
	_table = center

	host = SmashHost.new()
	root.add_child(host)
	_flash = _rect(root, Color(1, 0, 0, 0))
	_fade = _rect(root, Color(0, 0, 0, 0))
	hide_attract()
	hide_name()

func _rect(parent: Control, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	parent.add_child(r)
	return r

func _settings(size: int) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.outline_size = maxi(4, size / 5)
	ls.outline_color = Color.BLACK
	return ls

func _cell(parent: Control, text: String, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.label_settings = _settings(size)
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _label(parent: Control, size: int, preset: Control.LayoutPreset, align: HorizontalAlignment) -> Label:
	var l := _cell(parent, "", size, align)
	# zero-size labels pinned to an anchor, growing away from the screen edge as their text needs
	l.set_anchors_and_offsets_preset(preset)
	match preset:
		Control.PRESET_TOP_LEFT:
			l.position = Vector2(14, 8)
		Control.PRESET_CENTER_TOP:
			l.grow_horizontal = Control.GROW_DIRECTION_BOTH
			l.offset_top = 8
		Control.PRESET_TOP_RIGHT:
			l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			l.offset_left = -14
			l.offset_right = -14
			l.offset_top = 8
		Control.PRESET_CENTER, Control.PRESET_CENTER_BOTTOM:
			l.grow_horizontal = Control.GROW_DIRECTION_BOTH
			l.grow_vertical = Control.GROW_DIRECTION_BOTH
		Control.PRESET_BOTTOM_LEFT:
			l.grow_vertical = Control.GROW_DIRECTION_BEGIN
			l.offset_left = 14
			l.offset_top = -8
			l.offset_bottom = -8
	return l

func set_stats(room: int, wave: int, score: int, lives: int, demo: bool) -> void:
	room_label.text = "ROOM %d   WAVE %d" % [room, wave]
	score_label.text = "SCORE %07d" % score
	lives_label.text = "DEMO" if demo else "LIVES %d" % lives

## Shows `text` in the middle for `secs` seconds (0 = until hide_banner()).
func show_banner(text: String, secs: float) -> void:
	banner.text = text
	banner.visible = true
	_banner_t = secs

func hide_banner() -> void:
	banner.visible = false
	_banner_t = 0.0

## The red flash when you get hit (fades by itself).
func hurt() -> void:
	_flash_a = 0.55

## 0 = clear, 1 = black.
func set_fade(a: float) -> void:
	_fade.visible = a > 0.0
	_fade.color.a = a

## Attract screens: 0 title, 1 high scores, 2 controls. `blink` toggles the PRESS FIRE line.
func show_attract(screen: int, blink: bool) -> void:
	_title.visible = screen != 1
	_title.position.y = _title.get_parent_area_size().y * 0.5 - (150.0 if screen == 2 else 70.0) - _title.size.y * 0.5
	_table.visible = screen == 1
	_help.visible = screen == 2
	_help.position.y = _help.get_parent_area_size().y * 0.5 + 10.0
	_press.visible = blink

func hide_attract() -> void:
	_title.visible = false
	_table.visible = false
	_help.visible = false
	_press.visible = false

## Fills the table; row `highlight` (-1 none) shows in yellow.
func set_table(entries: Array, highlight: int) -> void:
	for i in _rows.size():
		var row: Array = _rows[i]
		var e: Array = entries[i] if i < entries.size() else ["---", 0, 0]
		row[1].text = e[0]
		row[2].text = str(e[1])
		row[3].text = "ROOM %d" % e[2]
		for l: Label in row:
			l.label_settings.font_color = Color(1.0, 0.85, 0.2) if i == highlight else Color.WHITE

func show_name(text: String) -> void:
	_name.text = text
	_name.visible = true

func hide_name() -> void:
	_name.visible = false

func tick(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			banner.visible = false
	if _flash_a > 0.0:
		_flash_a = maxf(0.0, _flash_a - delta * 1.4)
		_flash.color.a = _flash_a
	_flash.visible = _flash_a > 0.0
