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
	var mk := mate_mark()
	draw_rect(Rect2(10, 8, 330, 198 + (22 if not mk.is_empty() else 0) + (20 if m.team else 0)), Color(0, 0, 0, 0.35))
	_arc()
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
	y += 18
	var am := "Q launcher:  "
	for a in VoxelMine.AMMO_ORDER:
		am += ("[%s %d]  " if a == m.ammo_sel else "%s %d  ") % [String(VoxelMine.AMMO_NAME[a]).split(" ")[0], int(m.ammo[a])]
	_text(Vector2(x, y), am, 13, Color8(255, 220, 140))
	y += 20
	if not mk.is_empty():
		# (co-op) your mate: how deep, how far, in trouble
		var warn := ""
		if m.net.other_stranded:
			warn = "  OUT OF FUEL!"
		elif m.net.other_hull < 0.25:
			warn = "  HULL LOW!"
		elif m.net.other_fuel < 0.15:
			warn = "  fuel low"
		var blink := warn != "" and fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.3
		_text(Vector2(x, y + 4), "MATE  %d m down, %d m away%s" % [int(mk.depth), int(mk.dist), warn], 15, Color8(255, 90, 80) if blink else mk.col)
		y += 22
		if m.team:
			_text(Vector2(x, y + 2), "TEAM BONUS  +50% digging", 15, Color8(120, 255, 140))
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
	if not mk.is_empty():
		_mate(mk)
	# the middle line, the prompt, the tip
	if _say_t > 0.0:
		_text(Vector2(0, size.y * 0.3), _say, 26, Color(1, 1, 0.85, clampf(_say_t * 2.0, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if _prompt != "" and not _menu.visible:
		_text(Vector2(0, size.y * 0.76), _prompt, 22, Color8(255, 220, 120), HORIZONTAL_ALIGNMENT_CENTER, size.x)     # (below the Moles)
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
		# (rising from under the middle line, clear of the panel's numbers)
		var k: float = p.t / 1.8
		_text(Vector2(0, size.y * 0.3 + 46 - k * 50.0), p.text, 24, Color(p.col.r, p.col.g, p.col.b, 1.0 - k * k), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_text(Vector2(14, size.y - 14), "A/D drive (push into rock to drill)   S drill down   W/Space fly   E use   right click / F launch   Q ammo   R suck water   G help your mate   1 dynamite  2 repair  3 teleport   F10 settings", 13, Color(0.8, 0.8, 0.85))

## (co-op) Where your mate's Mole is, for the marker: {} when it's not down here with you; else at (on the screen),
## on (on screen), dir (from the screen's middle), dist (metres), depth, col (theirs: the guest's blue, the host's yellow)
func mate_mark() -> Dictionary:
	var m = mine
	if m.net == null or not m.net.mate_here() or m.cam == null or not m._built:
		return {}
	var op: Vector2 = m.net.other.p
	var at: Vector2 = m.cam.unproject_position(Vector3(op.x, op.y, MineShip.Z))
	var mid := size * 0.5
	var inset := Rect2(Vector2(50, 50), size - Vector2(100, 100))
	return {"at": at, "on": inset.has_point(at) and not m.cam.is_position_behind(Vector3(op.x, op.y, MineShip.Z)),
		"dir": (at - mid).normalized() if at.distance_to(mid) > 1.0 else Vector2.DOWN, "dist": op.distance_to(m.ship.p),
		"depth": maxf(0.0, -op.y - MineShip.HALF), "col": Color8(120, 190, 255) if m.net.role() == "host" else Color8(255, 215, 80)}

## The marker: over your mate's Mole when it's on screen (MATE, its fuel and hull), else an arrow at the screen's edge
## pointing to it, how far
func _mate(mk: Dictionary) -> void:
	var col: Color = mk.col
	var m = mine
	var trouble: bool = m.net.other_stranded or m.net.other_hull < 0.25
	if trouble and fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.3:
		col = Color8(255, 90, 80)
	if mk.on:
		if m.team:
			# (the team bonus on: a dotted green line between the two Moles)
			var me: Vector2 = m.cam.unproject_position(Vector3(m.ship.p.x, m.ship.p.y, MineShip.Z))
			var n := int(me.distance_to(mk.at) / 14.0)
			var ph := fmod(Time.get_ticks_msec() / 400.0, 1.0)
			for i in n:
				var q := me.lerp(mk.at, (float(i) + ph) / maxf(1.0, float(n)))
				draw_circle(q, 2.5, Color8(120, 255, 140, 170))
		var top: Vector2 = mk.at + Vector2(0, -58)
		_text(top + Vector2(-60, 0), "OUT OF FUEL" if m.net.other_stranded else "MATE", 14, col, HORIZONTAL_ALIGNMENT_CENTER, 120)
		for i in 2:
			var k: float = m.net.other_fuel if i == 0 else m.net.other_hull
			var bc := Color8(240, 150, 30) if i == 0 else Color8(80, 200, 90).lerp(Color8(230, 50, 40), 1.0 - k)
			var r := Rect2(top + Vector2(-22, 6 + i * 6), Vector2(44, 4))
			draw_rect(r, Color(0, 0, 0, 0.6))
			draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(k, 0.0, 1.0), r.size.y)), bc)
		return
	# off screen: the arrow on the edge, on the line from the middle to them
	var mid := size * 0.5
	var d: Vector2 = mk.dir
	var half := mid - Vector2(46, 46)
	var t := minf(half.x / maxf(0.001, absf(d.x)), half.y / maxf(0.001, absf(d.y)))
	var p := mid + d * t
	var side := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([p + d * 18.0, p - d * 8.0 + side * 12.0, p - d * 8.0 - side * 12.0])
	draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
	var pts2 := PackedVector2Array([p + d * 15.0, p - d * 6.0 + side * 9.0, p - d * 6.0 - side * 9.0])
	draw_colored_polygon(pts2, col)
	var label := "MATE %d m" % int(mk.dist) + ("  OUT OF FUEL" if m.net.other_stranded else "")
	var lp := p - d * 34.0 + Vector2(-70, 6)
	_text(lp, label, 15, col, HORIZONTAL_ALIGNMENT_CENTER, 140)

## The launcher's arc, from the ship toward the mouse (while right is held, or always faintly)
func _arc() -> void:
	var m = mine
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not m.aiming or m.cam == null or not held:
		return
	var sv: Array = m.shot_start()
	var p: Vector2 = sv[0]
	var v: Vector2 = sv[1]
	var last := Vector2.INF
	for k in 26:
		for j in 3:
			v.y -= 12.0 * 0.02
			p += v * 0.02
		if m.ground.solid_at(p):
			break
		var sp: Vector2 = m.cam.unproject_position(Vector3(p.x, p.y, 0.0))
		if last != Vector2.INF and k % 2 == 0:
			draw_line(last, sp, Color(1, 1, 1, 0.8 if held else 0.25), 2.0)
		last = sp
	var tip: Vector2 = m.cam.unproject_position(Vector3(p.x, p.y, 0.0))
	draw_circle(tip, 5.0 if held else 3.0, Color(1, 0.85, 0.4, 0.9 if held else 0.35))

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
