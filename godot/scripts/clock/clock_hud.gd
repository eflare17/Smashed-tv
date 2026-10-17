class_name ClockHud
extends CanvasLayer
## The small clock on the HUD (1.4): "Day 3  7:42 am" with a sun or a moon, at the top right under the view
## label, and the fade to black and back when you sleep ("Day 4"). Owned by the Lighting session.

const GOLD := Color("#f6d17a")
const MOON := Color("#bcd0ff")

var _label: Label
var _icon: _Icon
var _fade: ColorRect
var _banner: Label

func _ready() -> void:
	layer = 11
	var root := Control.new()
	root.name = "ClockRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", GOLD)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	_label.add_theme_constant_override("outline_size", 3)
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.offset_left = -260
	_label.offset_right = -12
	_label.offset_top = 32
	_label.offset_bottom = 54
	root.add_child(_label)

	_icon = _Icon.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_icon.custom_minimum_size = Vector2(16, 16)
	root.add_child(_icon)

	_fade = ColorRect.new()
	_fade.color = Color(0.01, 0.01, 0.03, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	root.add_child(_fade)

	_banner = Label.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.add_theme_color_override("font_color", GOLD)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.offset_left = -300
	_banner.offset_right = 300
	_banner.offset_top = -30
	_banner.offset_bottom = 30
	_banner.modulate.a = 0.0
	root.add_child(_banner)

func _process(_dt: float) -> void:
	var c := get_node_or_null("/root/GameClock")
	if c == null:
		_label.text = ""
		return
	_label.text = "Day %d   %s" % [c.day, c.time_text()]
	var night: bool = c.hour < 6.0 or c.hour >= 20.0
	_label.add_theme_color_override("font_color", MOON if night else GOLD)
	var f := _label.get_theme_font("font")
	var w := f.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if f else 120.0
	_icon.night = night
	var vw := get_viewport().get_visible_rect().size.x
	_icon.position = Vector2(vw - 12 - w - 22, 35)
	_icon.queue_redraw()

## Fade to black, call mid (the skip) when it's dark, show the banner, fade back. Returns when done.
func sleep_fade(mid: Callable, banner_text: Callable) -> void:
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.7)
	await tw.finished
	mid.call()
	_banner.text = banner_text.call()
	var tb := create_tween()
	tb.tween_property(_banner, "modulate:a", 1.0, 0.35)
	tb.tween_interval(0.9)
	await tb.finished
	var t2 := create_tween()
	t2.set_parallel(true)
	t2.tween_property(_fade, "color:a", 0.0, 1.0)
	t2.tween_property(_banner, "modulate:a", 0.0, 0.8)
	await t2.finished
	_fade.visible = false

## A little sun (rays) or moon (a crescent).
class _Icon extends Control:
	var night := false
	func _draw() -> void:
		var c := Vector2(8, 8)
		if night:
			draw_circle(c, 6.0, MOON)
			draw_circle(c + Vector2(3, -2), 5.0, Color(0.06, 0.08, 0.16))
		else:
			draw_circle(c, 4.0, GOLD)
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * 5.5, c + Vector2(cos(a), sin(a)) * 7.5, GOLD, 1.5, true)
