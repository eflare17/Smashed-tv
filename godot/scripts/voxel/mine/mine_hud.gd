class_name MineHud
extends Control
## The dig mode's screen (the owner, 23 Oct): fuel, hull, cargo, depth and cash up in the corner, the supplies you've
## got, a line in the middle for what's happening, cash popping up when you sell, the tips on the first dives, the
## worm's health when it's after you, and the buildings' menus up top (click a line, or press its number). Owned by
## the voxel session.

var mine                        # VoxelMine
var _font: Font
var _say := ""
var _say_t := 0.0
var _tip := ""
var _tip_t := 0.0
var _pops: Array = []           # {text, col, t}
var _prompt := ""
var _menu: PanelContainer
var _menu_box: VBoxContainer
var _menu_title: Label
var _menu_rows: Array = []      # [Button, Callable]
var _confirm := ""
var flash := 0.0                # the hull taking a hit: the bar flashes

func setup(mine_) -> void:
	mine = mine_
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_menu = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	sb.border_color = Color8(240, 186, 40)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_menu.add_theme_stylebox_override("panel", sb)
	_menu.visible = false
	add_child(_menu)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 6)
	_menu.add_child(_menu_box)
	_menu_title = Label.new()
	_menu_title.add_theme_font_size_override("font_size", 26)
	_menu_title.add_theme_color_override("font_color", Color8(240, 186, 40))
	_menu_box.add_child(_menu_title)

func _process(dt: float) -> void:
	_say_t -= dt
	_tip_t -= dt
	flash = maxf(0.0, flash - dt * 2.0)
	for p in _pops:
		p.t += dt
	_pops = _pops.filter(func(p): return p.t < 1.8)
	if _menu.visible:
		_menu.position = (size - _menu.size) * 0.5
	queue_redraw()

func say(text: String, secs: float) -> void:
	_say = text
	_say_t = secs

func tip(text: String) -> void:
	_tip = text
	_tip_t = 9.0

func tip_showing() -> bool:
	return _tip_t > 0.0

func pop(text: String, col: Color) -> void:
	_pops.append({"text": text, "col": col, "t": 0.0})

func prompt(text: String) -> void:
	_prompt = text

# ---------------------------------------------------------------- menus

func menu_open() -> bool:
	return _menu.visible

## A menu: rows of [text, enabled, Callable or null (just a line)]
func open_menu(title: String, rows: Array) -> void:
	_menu_title.text = title
	for r in _menu_rows:
		(r[0] as Control).queue_free()
	_menu_rows.clear()
	var n := 0
	for row in rows:
		var cb = row[2]
		if cb == null:
			var l := Label.new()
			l.text = String(row[0])
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85) if row[1] else Color(0.55, 0.55, 0.6))
			_menu_box.add_child(l)
			_menu_rows.append([l, null])
			continue
		n += 1
		var b := Button.new()
		b.text = "%d   %s" % [n, row[0]] if n <= 9 else String(row[0])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size = Vector2(520, 34)
		b.disabled = not bool(row[1])
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): (cb as Callable).call())
		_menu_box.add_child(b)
		_menu_rows.append([b, cb])
	var close := Label.new()
	close.text = "E or Esc: close"
	close.add_theme_font_size_override("font_size", 13)
	close.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_menu_box.add_child(close)
	_menu_rows.append([close, null])
	_menu.visible = true
	_menu.reset_size()

func close_menu() -> void:
	_menu.visible = false
	_confirm = ""

## A number key in a menu: that row's button.
func menu_key(k: int) -> void:
	var n := 0
	for r in _menu_rows:
		if r[1] == null:
			continue
		n += 1
		if n == k:
			var b: Button = r[0]
			if not b.disabled:
				(r[1] as Callable).call()
			return

## Asked twice before something big (a fresh claim): true the second time.
func confirm(what: String) -> bool:
	if _confirm == what:
		_confirm = ""
		return true
	_confirm = what
	say("Sure? Do it again to confirm", 2.5)
	return false

# ---------------------------------------------------------------- drawing

func _bar(at: Vector2, w: float, k: float, col: Color, label: String, value: String, blink := false) -> void:
	draw_rect(Rect2(at, Vector2(w, 20)), Color(0, 0, 0, 0.55))
	var c := col
	if blink and fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25:
		c = Color.WHITE
	draw_rect(Rect2(at + Vector2(2, 2), Vector2((w - 4) * clampf(k, 0.0, 1.0), 16)), c)
	draw_string(_font, at + Vector2(6, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.BLACK)
	draw_string(_font, at + Vector2(5, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	draw_string(_font, at + Vector2(w + 8, 15), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)

func _text(at: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	for o in [Vector2(2, 2), Vector2(-1, 1), Vector2(1, -1)]:
		draw_string(_font, at + o, s, align, w, sz, Color(0, 0, 0, 0.85))
	draw_string(_font, at, s, align, w, sz, col)

func _draw() -> void:
	if mine == null or not mine.active:
		return
	var m = mine
	var tank: float = m.tank_max()
	var hmax: float = m.hull_max()
	var cap: int = m.cargo_cap()
	var held: int = m.cargo_count()
	var x := 18.0
	var y := 16.0
	draw_rect(Rect2(10, 8, 330, 180), Color(0, 0, 0, 0.35))
	_bar(Vector2(x, y), 200, m.fuel / tank, Color8(240, 150, 30), "FUEL", "%.1f / %.0f L" % [m.fuel, tank], m.fuel < tank * 0.2)
	y += 26
	var hc := Color8(80, 200, 90).lerp(Color8(230, 50, 40), 1.0 - m.hull / hmax)
	_bar(Vector2(x, y), 200, m.hull / hmax, hc if flash <= 0.0 else Color.WHITE, "HULL", "%d / %d" % [int(ceil(m.hull)), int(hmax)], m.hull < hmax * 0.25)
	y += 26
	_bar(Vector2(x, y), 200, float(held) / cap, Color8(90, 150, 230) if held < cap else Color8(230, 60, 60), "CARGO", "%d / %d" % [held, cap], held >= cap)
	y += 46
	var depth := maxf(0.0, -m.ship.p.y - MineShip.HALF)
	_text(Vector2(x, y), "DEPTH  %d m" % int(depth), 20, Color.WHITE)
	_text(Vector2(x + 165, y), "$%d" % m.arena.cash, 22, Color8(120, 240, 120))
	y += 26
	var it := ""
	for id in MineShop.ITEM_ORDER:
		it += "%s %s x%d   " % [MineShop.ITEMS[id].key, MineShop.ITEMS[id].name, int(m.items.get(id, 0))]
	_text(Vector2(x, y), it, 13, Color(0.85, 0.85, 0.9))
	y += 20
	if m.trip > 0.05:
		_text(Vector2(x, y), "TRIPPING " + "~".repeat(int(m.trip * 10.0)), 15, Color.from_hsv(fmod(Time.get_ticks_msec() / 900.0, 1.0), 0.7, 1.0))
	if m.critters and m.critters.alarm:
		var on := fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25
		_text(Vector2(size.x - 280, 40), "WANTED  %ds" % int(MineCritters.DRONE_GIVE_UP - m.critters.alarm_t), 24, Color(0.3, 0.5, 1.0) if on else Color(1, 0.2, 0.2))
	# the worm's health
	if m.worm and m.worm.awake and m.worm.alive:
		var w := minf(500.0, size.x - 80.0)
		var at := Vector2((size.x - w) * 0.5, 22)
		draw_rect(Rect2(at, Vector2(w, 18)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(at + Vector2(2, 2), Vector2((w - 4) * m.worm.hp / MineWorm.HP_MAX, 14)), Color8(200, 40, 60))
		_text(at + Vector2(0, -4), "THE ROCK WORM", 16, Color8(255, 120, 120))
	# the middle line, the prompt, the tip
	if _say_t > 0.0:
		_text(Vector2(0, size.y * 0.3), _say, 26, Color(1, 1, 0.85, clampf(_say_t * 2.0, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if _prompt != "" and not _menu.visible:
		_text(Vector2(0, size.y * 0.62), _prompt, 22, Color8(255, 220, 120), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if _tip_t > 0.0:
		var tw := minf(560.0, size.x - 40.0)
		var lines := _wrap(_tip, tw - 24, 16)
		var th := 16.0 + lines.size() * 21.0
		var at2 := Vector2(size.x - tw - 14, size.y - th - 44)
		draw_rect(Rect2(at2, Vector2(tw, th)), Color(0.05, 0.08, 0.12, 0.85 * clampf(_tip_t, 0.0, 1.0)))
		draw_rect(Rect2(at2, Vector2(4, th)), Color8(240, 186, 40))
		for i in lines.size():
			_text(at2 + Vector2(14, 24 + i * 21), lines[i], 16, Color(1, 1, 1, clampf(_tip_t, 0.0, 1.0)))
	for p in _pops:
		var k: float = p.t / 1.8
		_text(Vector2(190, 120 - k * 60.0), p.text, 24, Color(p.col.r, p.col.g, p.col.b, 1.0 - k * k))
	_text(Vector2(14, size.y - 14), "A/D drive (push into rock to drill)   S drill down   W/Space fly   E use   1 dynamite  2 repair  3 teleport   F10 settings", 13, Color(0.8, 0.8, 0.85))

func _wrap(s: String, w: float, sz: int) -> Array:
	var out := []
	var line := ""
	for word in s.split(" "):
		var t := word if line == "" else line + " " + word
		if _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > w and line != "":
			out.append(line)
			line = word
		else:
			line = t
	if line != "":
		out.append(line)
	return out
