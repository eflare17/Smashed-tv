class_name DigUI
extends CanvasLayer
## What digging shows and plays: the held tool at the bottom of the screen in first person, a FILL button for
## touch (with the shovel, by a hole), words rising over the ground (finds, "NOTHING"), and the sounds (made here
## in code, like the HTML game's: a shovel's chunk, dirt going back, a find's ding, the hoe's scrape).

var dig: Dig
var _pic: _ToolPic
var _fill: _FillButton
var _players: Array = []
var _streams: Dictionary = {}

func _ready() -> void:
	layer = 8
	_pic = _ToolPic.new()
	_pic.ui = self
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_pic)
	_fill = _FillButton.new()
	_fill.ui = self
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fill)
	dig.floater.connect(world_floater)
	dig.sound.connect(play)

func _process(_dt: float) -> void:
	var p := dig._local() if dig else null
	var t := dig.tool_of(p) if p else ""
	var fp: bool = p != null and p.has_method("is_first_person") and p.is_first_person()
	_pic.tool = t if fp else ""
	_pic.swing = dig._swing
	_pic.queue_redraw()
	var touch = _touch()
	_fill.shown = touch != null and touch.active and t == "shovel" and dig.can_fill(p)
	_fill.queue_redraw()

func _touch():
	var hud = dig.main.get("hud") if dig and dig.main else null
	return hud.get("touch") if hud else null

## The touch FILL button: a tap fills (as Q / pad X do). Taken here first (this layer gets touches before the
## HUD's touch layer, which would start the aim stick there).
func _input(event: InputEvent) -> void:
	if not _fill.shown:
		return
	if event is InputEventScreenTouch and event.pressed and _fill.hit(event.position):
		var p := dig._local()
		if p and dig.can_fill(p):
			dig.fill_at(p, dig.target_of(p))
		get_viewport().set_input_as_handled()

## A word rising over the ground (like the farm's floaters).
func world_floater(text: String, col: Color, at: Vector2) -> void:
	var parent: Node = dig.world if dig and dig.world else null
	if parent == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.018
	l.modulate = col
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 5
	l.position = GameData.world_to_3d(at.x, at.y, 80)
	parent.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.2, 1.6)
	tw.tween_property(l, "modulate:a", 0.0, 1.6).set_delay(0.7)
	tw.chain().tween_callback(l.queue_free)

## ---------------------------------------------------------------- sounds

func play(n: String) -> void:
	if not _streams.has(n):
		_streams[n] = _make(n)
	var st: AudioStreamWAV = _streams[n]
	if st == null:
		return
	var pl: AudioStreamPlayer = null
	for a in _players:
		if not a.playing:
			pl = a
			break
	if pl == null:
		if _players.size() >= 4:
			return
		pl = AudioStreamPlayer.new()
		add_child(pl)
		_players.append(pl)
	pl.stream = st
	pl.volume_db = -10.0 if n == "plough" else -4.0
	pl.pitch_scale = randf_range(0.92, 1.08)
	pl.play()

## The sounds, 22 kHz mono: filtered noise with an envelope (dig, fill, plough, tool) or a two-note chime (find).
static func _make(n: String) -> AudioStreamWAV:
	var rate := 22050
	var dur := {"dig": 0.16, "fill": 0.22, "plough": 0.09, "tool": 0.1, "find": 0.42}.get(n, 0.1) as float
	var count := int(rate * dur)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(n)
	var lp := 0.0
	for i in count:
		var t := float(i) / rate
		var k := t / dur
		var v := 0.0
		match n:
			"dig":       # the blade going in: a thud and gritty noise
				lp += (rng.randf_range(-1, 1) - lp) * 0.35
				v = lp * exp(-k * 5.0) * 0.9 + sin(TAU * 90.0 * t) * exp(-k * 9.0) * 0.6
			"fill":      # dirt thrown back: softer, longer
				lp += (rng.randf_range(-1, 1) - lp) * 0.18
				v = lp * sin(PI * k) * 0.9
			"plough":    # the hoe scraping
				lp += (rng.randf_range(-1, 1) - lp) * 0.5
				v = lp * sin(PI * k) * 0.5
			"tool":      # a clink
				v = sin(TAU * 1320.0 * t) * exp(-k * 7.0) * 0.4 + sin(TAU * 2100.0 * t) * exp(-k * 9.0) * 0.2
			"find":      # a little chime
				var f := 880.0 if t < 0.12 else 1318.5
				v = sin(TAU * f * t) * exp(-fmod(t, 0.12 if t < 0.12 else 1.0) * 6.0) * 0.45
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s

## ---------------------------------------------------------------- the pictures

## The held tool in first person: its handle coming up from the bottom right, the blade out in front; a dig
## pushes it in.
class _ToolPic extends Control:
	var ui: DigUI
	var tool := ""
	var swing := 0.0
	func _draw() -> void:
		if tool == "":
			return
		var vp := size
		var k := clampf(minf(vp.x, vp.y) / 720.0, 0.6, 1.8)
		var push := sin(clampf(swing, 0.0, 1.0) * PI) * 40.0 * k
		var base := Vector2(vp.x * 0.78, vp.y + 10.0)
		var tip := Vector2(vp.x * 0.6, vp.y * 0.66 + push * 0.6) + Vector2(-push * 0.3, 0)
		var wood := Color8(150, 104, 58)
		var dark := Color8(96, 66, 36)
		draw_line(base, tip, dark, 16.0 * k)
		draw_line(base + Vector2(-3, 0) * k, tip + Vector2(-3, 0) * k, wood, 11.0 * k)
		var d := (tip - base).normalized()
		var side := Vector2(-d.y, d.x)
		var steel := Color8(158, 164, 174)
		var shade := Color8(104, 110, 120)
		if tool == "shovel":
			var w := 46.0 * k
			var l := 62.0 * k
			var pts := PackedVector2Array([tip + side * w * 0.5, tip - side * w * 0.5,
				tip - side * w * 0.45 + d * l, tip + d * (l + 14.0 * k), tip + side * w * 0.45 + d * l])
			draw_colored_polygon(pts, steel)
			draw_polyline(pts + PackedVector2Array([pts[0]]), shade, 3.0 * k)
		else:
			var w2 := 58.0 * k
			var a := tip + d * 6.0 * k
			var pts2 := PackedVector2Array([a + side * w2 * 0.5, a - side * w2 * 0.5,
				a - side * w2 * 0.5 + Vector2(0, 22.0 * k), a + side * w2 * 0.5 + Vector2(0, 22.0 * k)])
			draw_colored_polygon(pts2, steel)
			draw_polyline(pts2 + PackedVector2Array([pts2[0]]), shade, 3.0 * k)

## The touch FILL button, above ROLL (bottom right).
class _FillButton extends Control:
	var ui: DigUI
	var shown := false
	func _centre() -> Array:
		var vp := size
		var k := clampf(minf(vp.x, vp.y) / 720.0, 0.75, 1.8)
		return [Vector2(vp.x - 196.0 * k, vp.y - 182.0 * k), 34.0 * k, k]
	func hit(p: Vector2) -> bool:
		var c := _centre()
		return p.distance_to(c[0]) <= c[1] + 8.0
	func _draw() -> void:
		if not shown:
			return
		var c := _centre()
		draw_circle(c[0], c[1], Color(0.36, 0.25, 0.14, 0.55))
		draw_arc(c[0], c[1], 0.0, TAU, 40, Color(1, 1, 1, 0.6), 2.0 * c[2])
		var font := get_theme_default_font()
		var fs := int(15 * c[2])
		var w := font.get_string_size("FILL", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, c[0] + Vector2(-w / 2.0, fs * 0.35), "FILL", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6))
		draw_string(font, c[0] + Vector2(-w / 2.0, fs * 0.35), "FILL", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
