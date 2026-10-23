class_name Hud
extends CanvasLayer
## The screen overlay: health and XP bars with your level (top left), the area and run (top right), the controls
## hint, a red flash when you're bitten, a banner for a new area, the level-up choice (three cards: click one, or
## press 1 / 2 / 3), and the end-of-run screen. Every Control is made once here; main.gd sets what they show.

signal picked(index: int)

const W := 480.0
const H := 270.0
const GOLD := Color(1.0, 0.85, 0.35)

var stats: Label
var area_label: Label
var hint: Label
var banner: Label

var _hp_fill: ColorRect
var _xp_fill: ColorRect
var _level: Label
var _flash: ColorRect
var _flash_a := 0.0
var _banner_t := 0.0
var _choice: Control
var _cards: Array[Button] = []
var _over: Control
var _over_text: Label

func _init() -> void:
	layer = 10
	_level = _label(8, Vector2(6, 3))
	_level.label_settings.font_color = GOLD
	_hp_fill = _bar(Vector2(36, 5), Color(0.85, 0.12, 0.1))
	_xp_fill = _bar(Vector2(36, 11), Color(0.35, 0.75, 1.0))
	stats = _label(8, Vector2(6, 16))
	area_label = _label(8, Vector2(W - 206, 3))
	area_label.size = Vector2(200, 10)
	area_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint = _label(8, Vector2(6, H - 14))
	hint.modulate = Color(1, 1, 1, 0.7)
	banner = _label(16, Vector2(0, 70))
	banner.size = Vector2(W, 20)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.label_settings.font_color = GOLD
	banner.visible = false
	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.size = Vector2(W, H)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_build_choice()
	_build_over()

func _label(size: int, at: Vector2) -> Label:
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.outline_size = 2 if size <= 8 else 4
	ls.outline_color = Color.BLACK
	var l := Label.new()
	l.label_settings = ls
	l.position = at
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _bar(at: Vector2, c: Color) -> ColorRect:
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.7)
	back.position = at - Vector2(1, 1)
	back.size = Vector2(62, 5)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var fill := ColorRect.new()
	fill.color = c
	fill.position = at
	fill.size = Vector2(60, 3)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)
	return fill

func _panel(parent: Control, rect: Rect2, c: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.border_color = Color(0, 0, 0)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	return p

func _build_choice() -> void:
	_choice = Control.new()
	_choice.size = Vector2(W, H)
	_choice.visible = false
	add_child(_choice)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(W, H)
	_choice.add_child(dim)
	var title := Label.new()
	title.label_settings = LabelSettings.new()
	title.label_settings.font_size = 16
	title.label_settings.font_color = GOLD
	title.label_settings.outline_size = 4
	title.label_settings.outline_color = Color.BLACK
	title.text = "LEVEL UP!  CHOOSE ONE"
	title.size = Vector2(W, 20)
	title.position = Vector2(0, 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice.add_child(title)
	for i in 3:
		var b := Button.new()
		b.position = Vector2(48 + i * 132, 90)
		b.size = Vector2(120, 80)
		b.add_theme_font_size_override("font_size", 8)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.1, 0.08, 0.95)
		sb.border_color = GOLD.darkened(0.3)
		sb.set_border_width_all(1)
		var hover := sb.duplicate() as StyleBoxFlat
		hover.border_color = GOLD
		hover.bg_color = Color(0.22, 0.17, 0.1, 0.95)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.add_theme_stylebox_override("focus", hover)
		b.pressed.connect(func(): picked.emit(i))
		_choice.add_child(b)
		_cards.append(b)

func _build_over() -> void:
	_over = Control.new()
	_over.size = Vector2(W, H)
	_over.visible = false
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_over)
	var dim := ColorRect.new()
	dim.color = Color(0.15, 0, 0, 0.6)
	dim.size = Vector2(W, H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.add_child(dim)
	var title := Label.new()
	title.label_settings = LabelSettings.new()
	title.label_settings.font_size = 24
	title.label_settings.font_color = Color(0.95, 0.2, 0.15)
	title.label_settings.outline_size = 5
	title.label_settings.outline_color = Color.BLACK
	title.text = "YOU WERE EATEN"
	title.size = Vector2(W, 30)
	title.position = Vector2(0, 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.add_child(title)
	_over_text = Label.new()
	_over_text.label_settings = LabelSettings.new()
	_over_text.label_settings.font_size = 8
	_over_text.label_settings.outline_size = 2
	_over_text.label_settings.outline_color = Color.BLACK
	_over_text.size = Vector2(W, 160)
	_over_text.position = Vector2(0, 96)
	_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.add_child(_over_text)

func set_bars(hp: float, xp: float, level: int) -> void:
	_hp_fill.size.x = 60.0 * clampf(hp, 0.0, 1.0)
	_xp_fill.size.x = 60.0 * clampf(xp, 0.0, 1.0)
	_level.text = "LV %d" % level

func hurt() -> void:
	_flash_a = 0.45

func show_banner(text: String, secs: float) -> void:
	banner.text = text
	banner.visible = true
	_banner_t = secs

## The three choices: each [name, what it does now -> after].
func show_choice(cards: Array) -> void:
	for i in 3:
		_cards[i].text = "%d\n\n%s\n\n%s" % [i + 1, cards[i][0], cards[i][1]]
	_choice.visible = true
	banner.visible = false
	_banner_t = 0.0

func hide_choice() -> void:
	_choice.visible = false

func choosing() -> bool:
	return _choice.visible

func show_over(text: String) -> void:
	_over_text.text = text
	_over.visible = true
	banner.visible = false
	_banner_t = 0.0

func hide_over() -> void:
	_over.visible = false

func tick(delta: float) -> void:
	_flash_a = maxf(0.0, _flash_a - delta * 1.6)
	_flash.color.a = _flash_a
	if _banner_t > 0.0:
		_banner_t -= delta
		banner.visible = _banner_t > 0.0
