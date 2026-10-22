extends CanvasLayer
## Smash arcade HUD: wave / score / lives along the top, a centre banner (WAVE n, GAME OVER), a crosshair in first
## person, and the debug overlay (bottom left). It lives in the scene's own viewport, so inside a SubViewport it
## draws on the cabinet screen. Nothing here takes mouse input.

var wave_label: Label
var score_label: Label
var lives_label: Label
var banner: Label
var crosshair: Label
var debug_label: Label

var _banner_t := 0.0

func _init() -> void:
	name = "Hud"
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	wave_label = _label(root, 28, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	score_label = _label(root, 28, Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER)
	lives_label = _label(root, 28, Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT)
	banner = _label(root, 64, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
	crosshair = _label(root, 32, Control.PRESET_CENTER, HORIZONTAL_ALIGNMENT_CENTER)
	crosshair.text = "+"
	crosshair.visible = false
	debug_label = _label(root, 16, Control.PRESET_BOTTOM_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	debug_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	banner.visible = false

func _label(parent: Control, size: int, preset: Control.LayoutPreset, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.outline_size = maxi(4, size / 5)
	ls.outline_color = Color.BLACK
	l.label_settings = ls
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
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
		Control.PRESET_CENTER:
			l.grow_horizontal = Control.GROW_DIRECTION_BOTH
			l.grow_vertical = Control.GROW_DIRECTION_BOTH
		Control.PRESET_BOTTOM_LEFT:
			l.grow_vertical = Control.GROW_DIRECTION_BEGIN
			l.offset_left = 14
			l.offset_top = -8
			l.offset_bottom = -8
	return l

func set_stats(wave: int, score: int, lives: int) -> void:
	wave_label.text = "WAVE %d" % wave
	score_label.text = "SCORE %07d" % score
	lives_label.text = "LIVES %d" % lives

## Shows `text` in the middle for `secs` seconds (0 = until hide_banner()).
func show_banner(text: String, secs: float) -> void:
	banner.text = text
	banner.visible = true
	_banner_t = secs

func hide_banner() -> void:
	banner.visible = false
	_banner_t = 0.0

func tick(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			banner.visible = false
