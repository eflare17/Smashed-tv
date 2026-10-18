class_name DigUI
extends CanvasLayer
## What digging shows and plays: the held tool at the bottom of the screen in first person, the backpack (the
## dug materials) and the health bar of the block being hit, a PLACE button for touch, words rising over the
## ground (finds), and the sounds (made here in code, like the HTML game's: a shovel's chunk, dirt going back, a
## find's ding, the hoe's scrape). On touch, holding the HUD's round button keeps digging (Dig.touch_hold).

const D := preload("res://scripts/dig/dig_data.gd")

var dig: Dig
var _pic: _ToolPic
var _fill: _FillButton
var _info: _Info
var _hold_index := -1
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
	_info = _Info.new()
	_info.ui = self
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_info)
	dig.floater.connect(world_floater)
	dig.sound.connect(play)

func _process(_dt: float) -> void:
	var p := dig._local() if dig else null
	var t := dig.tool_of(p) if p else ""
	var fp: bool = p != null and p.has_method("is_first_person") and p.is_first_person()
	var want := t if fp else ""
	if want != _pic.tool or dig._swing != _pic.swing:
		_pic.tool = want
		_pic.swing = dig._swing
		_pic.queue_redraw()
	var touch = _touch()
	var shown: bool = touch != null and touch.active and (t == "shovel" or t == "pickaxe") and dig.can_place(p)
	if shown != _fill.shown:
		_fill.shown = shown
		_fill.queue_redraw()
	_info.queue_redraw()

func _touch():
	var hud = dig.main.get("hud") if dig and dig.main else null
	return hud.get("touch") if hud else null

## The touch FILL button: a tap fills (as Q / pad X do). Taken here first (this layer gets touches before the
## HUD's touch layer, which would start the aim stick there).
func _input(event: InputEvent) -> void:
	# a finger held on the HUD's round button keeps digging (the button itself takes the first tap)
	if event is InputEventScreenTouch:
		var hud = dig.main.get("hud") if dig and dig.main else null
		if event.pressed and hud and hud.has_method("e_button_hit") and hud.e_button_hit(event.position):
			_hold_index = event.index
		elif not event.pressed and event.index == _hold_index:
			_hold_index = -1
		dig.touch_hold = _hold_index >= 0
	if not _fill.shown:
		return
	if event is InputEventScreenTouch and event.pressed and _fill.hit(event.position):
		var p := dig._local()
		if p and dig.can_place(p):
			dig.place_now(p)
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
		if tool == "pickaxe":
			var hw := 64.0 * k
			var a2 := tip + d * 4.0 * k
			var pts3 := PackedVector2Array([a2 + side * hw, a2 + side * hw * 0.2 - d * 8.0 * k, a2 - side * hw * 0.2 - d * 8.0 * k,
				a2 - side * hw, a2 - side * hw * 0.2 + d * 6.0 * k, a2 + side * hw * 0.2 + d * 6.0 * k])
			draw_colored_polygon(pts3, steel)
			draw_polyline(pts3 + PackedVector2Array([pts3[0]]), shade, 3.0 * k)
		elif tool == "shovel":
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

## The backpack (what he's dug: the material Q places marked) and the health bar of the block he's breaking.
class _Info extends Control:
	var ui: DigUI
	func _draw() -> void:
		var dig := ui.dig
		var p := dig._local()
		if p == null:
			return
		var t := dig.tool_of(p)
		var digging := t == "shovel" or t == "pickaxe"
		var font := get_theme_default_font()
		var k := clampf(minf(size.x, size.y) / 720.0, 0.7, 1.6)
		var fs := int(13 * k)
		# the backpack
		var total := 0
		for n in dig.inv.res:
			total += int(n)
		if digging or total > 0:
			var x := 12.0 * k
			var y := 128.0 * k
			var pick := dig.place_material()
			for m in dig.inv.res.size():
				var n2 := int(dig.inv.res[m])
				if n2 <= 0 and not digging:
					continue
				var txt := "%s %d" % [D.MATS[m].name, n2]
				var col := Color("#ffd36b") if m == pick else (Color("#e6e8ee") if n2 > 0 else Color(1, 1, 1, 0.4))
				draw_rect(Rect2(x, y - fs + 1, 9 * k, 9 * k), (D.MATS[m].tint as Color) * Color8(140, 100, 64))
				draw_string_outline(font, Vector2(x + 12 * k, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * k), Color(0, 0, 0, 0.7))
				draw_string(font, Vector2(x + 12 * k, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
				y += fs + 5.0 * k
			if digging:
				var tier := int(dig.inv.tiers.get(t, 0))
				var tt := "%s%s" % [D.TIER_NAMES[tier], t.to_upper()]
				draw_string_outline(font, Vector2(x, y + 2 * k), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * k), Color(0, 0, 0, 0.7))
				draw_string(font, Vector2(x, y + 2 * k), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#9fe07a"))
		# the block being broken: its health, by it on the screen
		var b = dig.target.get("b")
		var dmg := dig.damage_of(b)
		if b != null and dmg > 0.0:
			var cam := get_viewport().get_camera_3d()
			if cam == null:
				return
			var c := DigVolume.block_centre(b)
			var w3 := GameData.world_to_3d(c.x, c.y, c.z + D.BLOCK / 2.0)
			if cam.is_position_behind(w3):
				return
			var sp := cam.unproject_position(w3)
			var bw := 64.0 * k
			var r := Rect2(sp.x - bw / 2.0, sp.y - 18.0 * k, bw, 7.0 * k)
			draw_rect(r.grow(1.5), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(r.position, Vector2(r.size.x * (1.0 - dmg), r.size.y)), Color("#e8b04a"))
			var name: String = D.MATS[dig.target.get("mat", 0)].name
			draw_string_outline(font, Vector2(r.position.x, r.position.y - 4 * k), name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * k), int(3 * k), Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(r.position.x, r.position.y - 4 * k), name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * k), Color.WHITE)

## The touch PLACE button, above ROLL (bottom right).
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
		var w := font.get_string_size("PLACE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, c[0] + Vector2(-w / 2.0, fs * 0.35), "PLACE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6))
		draw_string(font, c[0] + Vector2(-w / 2.0, fs * 0.35), "PLACE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
