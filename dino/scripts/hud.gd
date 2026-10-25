class_name Hud
extends CanvasLayer
## The screen overlay: health and XP bars with your level (top left), the area and run (top right), the controls
## hint, a red flash when you're bitten, a banner for a new area, the level-up choice (three cards: click one, or
## press 1 / 2 / 3), and the end-of-run screen with the bones shop (Bones) and the leaderboard (Leaderboard).
## Every Control is made once here; main.gd sets what they show.

signal picked(index: int)
## The death screen's shop: a card clicked, and the next run button.
signal bought(index: int)
signal next_run
## The leaderboard (from the death screen): open it, a tab (Leaderboard.PERIODS), NEW NAME, BACK.
signal board_open
signal board_tab(period: String)
signal new_name
signal board_back

const W := 480.0
const H := 270.0
const GOLD := Color(1.0, 0.85, 0.35)
## Shop cards: the seven upgrades and the Raptor.
const SHOP_SIZE := 8

var stats: Label
var area_label: Label
var hint: Label
var banner: Label

var _hp_fill: ColorRect
var _xp_fill: ColorRect
var _danger_fill: ColorRect
var _level: Label
var _flash: ColorRect
var _flash_a := 0.0
var _banner_t := 0.0
var _choice: Control
var _cards: Array[Button] = []
var _over: Control
var _over_text: Label
var _over_hint: Label
var _shop: Array[Button] = []
var _shop_lines: Array = []
var _pips: Array[Control] = []
var _shop_items: Array = []
var _next: Button
var _shop_box: Control
var _board_btn: Button
var _board: Control
var _tabs: Array[Button] = []
## Each row's [rank, name, kg] labels.
var _rows: Array = []
var _board_status: Label
var _board_name: Label

func _init() -> void:
	layer = 10
	_level = _label(8, Vector2(6, 3))
	_level.label_settings.font_color = GOLD
	_hp_fill = _bar(Vector2(36, 5), Color(0.85, 0.12, 0.1))
	_xp_fill = _bar(Vector2(36, 11), Color(0.35, 0.75, 1.0))
	_danger_fill = _bar(Vector2(36, 17), Color(1.0, 0.5, 0.1))
	var dl := _label(8, Vector2(100, 13))
	dl.text = "DANGER"
	dl.modulate = Color(1, 0.7, 0.5)
	stats = _label(8, Vector2(6, 22))
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

func _card_button(parent: Control, rect: Rect2) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
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
	# a finger's tap comes through touch_tap; the mouse click the phone also makes from it must not buy twice
	b.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.device == InputEvent.DEVICE_ID_EMULATION:
			b.accept_event())
	parent.add_child(b)
	return b

func _build_over() -> void:
	_over = Control.new()
	_over.size = Vector2(W, H)
	_over.visible = false
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_over)
	var dim := ColorRect.new()
	dim.color = Color(0.15, 0, 0, 0.7)
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
	title.position = Vector2(0, 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.add_child(title)
	_over_text = Label.new()
	_over_text.label_settings = LabelSettings.new()
	_over_text.label_settings.font_size = 8
	_over_text.label_settings.outline_size = 2
	_over_text.label_settings.outline_color = Color.BLACK
	_over_text.size = Vector2(W, 40)
	_over_text.position = Vector2(0, 44)
	_over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.add_child(_over_text)
	# the shop: two rows of four cards (the seven upgrades, then the Raptor), and the buttons for the leaderboard
	# and the next run (all hidden while the leaderboard is up)
	_shop_box = Control.new()
	_shop_box.size = Vector2(W, H)
	_shop_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.add_child(_shop_box)
	for i in SHOP_SIZE:
		var b := _card_button(_shop_box, Rect2(31 + (i % 4) * 106, 84 + (i / 4) * 58, 100, 52))
		b.pressed.connect(func(): bought.emit(i))
		# its lines: the name, what it does, the rank squares (drawn), the price
		var lines: Array[Label] = []
		for y in [4, 15, 38]:
			var l := Label.new()
			l.label_settings = LabelSettings.new()
			l.label_settings.font_size = 8
			l.position = Vector2(0, y)
			l.size = Vector2(b.size.x, 10)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(l)
			lines.append(l)
		var pips := Control.new()
		pips.size = b.size
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.draw.connect(_draw_pips.bind(pips, i))
		b.add_child(pips)
		_shop.append(b)
		_shop_lines.append(lines)
		_pips.append(pips)
	_next = _card_button(_shop_box, Rect2(W * 0.5 - 60, 204, 120, 24))
	_next.text = "NEXT RUN"
	_next.add_theme_color_override("font_color", GOLD)
	_next.pressed.connect(func(): next_run.emit())
	_board_btn = _card_button(_shop_box, Rect2(W * 0.5 - 124, 204, 120, 24))
	_board_btn.text = "LEADERBOARD"
	_board_btn.pressed.connect(func(): board_open.emit())
	_board_btn.visible = false
	_build_board()
	_over_hint = Label.new()
	_over_hint.label_settings = _over_text.label_settings
	_over_hint.size = Vector2(W, 12)
	_over_hint.position = Vector2(0, 236)
	_over_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over_hint.modulate = Color(1, 1, 1, 0.7)
	_over.add_child(_over_hint)

func _small_label(parent: Control, at: Vector2, w: float, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.label_settings = LabelSettings.new()
	l.label_settings.font_size = 8
	l.position = at
	l.size = Vector2(w, 10)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

## The leaderboard, over the shop: DAY / WEEK / MONTH tabs, the top 10 (and your spot) by kilograms of meat,
## your name with NEW NAME, and BACK.
func _build_board() -> void:
	_board = Control.new()
	_board.size = Vector2(W, H)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.visible = false
	_over.add_child(_board)
	var bg := _panel(_board, Rect2(70, 68, 340, 168), Color(0.08, 0.06, 0.05, 0.95))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _small_label(_board, Vector2(70, 72), 340, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "MOST MEAT EATEN"
	title.label_settings.font_color = GOLD
	for k in Leaderboard.PERIODS.size():
		var p: String = Leaderboard.PERIODS[k]
		var b := _card_button(_board, Rect2(W * 0.5 - 85 + k * 58, 85, 54, 15))
		b.text = ["TODAY", "THIS WEEK", "THIS MONTH"][k]
		b.pressed.connect(func(): board_tab.emit(p))
		_tabs.append(b)
	for k in 11:
		var y := 104.0 + k * 10.0
		_rows.append([_small_label(_board, Vector2(80, y), 24, HORIZONTAL_ALIGNMENT_RIGHT),
				_small_label(_board, Vector2(110, y), 200), _small_label(_board, Vector2(300, y), 100, HORIZONTAL_ALIGNMENT_RIGHT)])
	_board_status = _small_label(_board, Vector2(70, 150), 340, HORIZONTAL_ALIGNMENT_CENTER)
	_board_name = _small_label(_board, Vector2(80, 219), 180)
	_board_name.label_settings.font_color = GOLD
	var nn := _card_button(_board, Rect2(268, 216, 70, 15))
	nn.text = "NEW NAME"
	nn.pressed.connect(func(): new_name.emit())
	var back := _card_button(_board, Rect2(342, 216, 60, 15))
	back.text = "BACK"
	back.pressed.connect(func(): board_back.emit())

## Shows the leaderboard on `period`'s tab, loading (set_board_rows fills it in).
func show_board(you: String, period: String) -> void:
	_shop_box.visible = false
	_board.visible = true
	_board_name.text = "YOU: " + you
	for k in _tabs.size():
		var on: bool = Leaderboard.PERIODS[k] == period
		_tabs[k].add_theme_color_override("font_color", GOLD if on else Color(1, 1, 1, 0.6))
	set_board_rows([], "LOADING...")

func hide_board() -> void:
	_board.visible = false
	_shop_box.visible = true

func board_showing() -> bool:
	return _board.visible

## The board's rows, each [rank, name, kg, is it you] (yours in gold), or `status` instead ("" = the rows).
func set_board_rows(rows: Array, status := "") -> void:
	_board_status.text = status if status != "" else ("NO ONE HAS EATEN YET" if rows.is_empty() else "")
	for k in _rows.size():
		var labels: Array = _rows[k]
		var r: Array = rows[k] if k < rows.size() and status == "" else []
		labels[0].text = "" if r.is_empty() else "%d." % r[0]
		labels[1].text = "" if r.is_empty() else r[1]
		labels[2].text = "" if r.is_empty() else "%d KG" % roundi(r[2])
		for l: Label in labels:
			l.label_settings.font_color = GOLD if not r.is_empty() and r[3] else Color.WHITE

## The leaderboard button: shown only when the leaderboard is on (NEXT RUN moves over to make room).
func set_board_enabled(on: bool) -> void:
	_board_btn.visible = on
	_next.position.x = W * 0.5 + 4 if on else W * 0.5 - 60

## The death screen's button (shop card, NEXT RUN, leaderboard and its buttons) under a point, or null.
func over_button_at(at: Vector2) -> Button:
	for b: Button in _shop + [_next, _board_btn] + _tabs:
		if b.is_visible_in_tree() and b.get_global_rect().has_point(at):
			return b
	for b in _board.get_children():
		if b is Button and b.is_visible_in_tree() and b.get_global_rect().has_point(at):
			return b
	return null

## A card's ranks: MAX_RANK little squares, filled up to the rank (none on the Raptor card).
func _draw_pips(c: Control, i: int) -> void:
	var rank: int = _shop_items[i][2] if i < _shop_items.size() else -1
	if rank < 0:
		return
	var x0 := c.size.x * 0.5 - (Bones.MAX_RANK * 7 - 2) * 0.5
	for k in Bones.MAX_RANK:
		var r := Rect2(x0 + k * 7, 28, 5, 5)
		c.draw_rect(r, GOLD if k < rank else Color(0, 0, 0, 0.6))
		c.draw_rect(r, GOLD.darkened(0.3), false, 1.0)

## Fractions 0..1 for the bars. The danger bar pulses once it's past half.
func set_bars(hp: float, xp: float, level: int, danger: float) -> void:
	_hp_fill.size.x = 60.0 * clampf(hp, 0.0, 1.0)
	_xp_fill.size.x = 60.0 * clampf(xp, 0.0, 1.0)
	_danger_fill.size.x = 60.0 * clampf(danger, 0.0, 1.0)
	var hot := danger > 0.5 and int(Time.get_ticks_msec() / 200) % 2 == 0
	_danger_fill.color = Color(1.0, 0.15, 0.1) if hot else Color(1.0, 0.5, 0.1)
	_level.text = "LV %d" % level

func hurt() -> void:
	flash(Color(1, 0, 0), 0.45)

## A full-screen flash of `c` starting at alpha `a` (fades by itself).
func flash(c: Color, a: float) -> void:
	_flash.color = Color(c, 0.0)
	_flash_a = a

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

## Which card is under a point (screen space), or -1.
func card_at(at: Vector2) -> int:
	for i in _cards.size():
		if _cards[i].get_global_rect().has_point(at):
			return i
	return -1

func choosing() -> bool:
	return _choice.visible

## The death screen: `text` (the run and the bones it paid), `hint` under the button, and the shop (set_shop).
func show_over(text: String, hint_text: String, items: Array) -> void:
	_over_text.text = text
	_over_hint.text = hint_text
	set_shop(items)
	_over.visible = true
	banner.visible = false
	_banner_t = 0.0

func over_hint() -> String:
	return _over_hint.text

## The shop's cards, each [name, what it does, rank (-1: the Raptor), price (-1: nothing left to buy), affordable].
func set_shop(items: Array) -> void:
	_shop_items = items
	for i in SHOP_SIZE:
		var it: Array = items[i]
		var cost: String = "MAXED" if it[3] < 0 and it[2] >= 0 else ("OWNED" if it[3] < 0 else "%d BONES" % it[3])
		var lines: Array[Label] = _shop_lines[i]
		lines[0].text = it[0]
		lines[1].text = it[1]
		lines[2].text = cost
		# what you can afford is lit up; the rest is dimmed
		lines[0].label_settings.font_color = Color.WHITE if it[4] else Color(1, 1, 1, 0.5)
		lines[1].label_settings.font_color = Color(0.8, 0.8, 0.8) if it[4] else Color(1, 1, 1, 0.35)
		lines[2].label_settings.font_color = GOLD if it[4] else Color(1, 1, 1, 0.5)
		_pips[i].queue_redraw()

func hide_over() -> void:
	_over.visible = false
	hide_board()

func tick(delta: float) -> void:
	_flash_a = maxf(0.0, _flash_a - delta * 1.6)
	_flash.color.a = _flash_a
	if _banner_t > 0.0:
		_banner_t -= delta
		banner.visible = _banner_t > 0.0
