class_name LobbyTableCards
extends Node
## Blackjack at the lounge table with Gothica dealing (specs/table.md section 7, Smashed.html 5234-5424: bjValue,
## bjDraw, bjAction, stepBJ, drawTableCards, drawBJPanel). Owned by the Lobby life session; part of LobbyTable.
##
## Rules: Gothica deals, draws to 16 and stands on 17 (a soft 17 is 17); every seated player plays against her for
## BJ_BET = 10 coins; blackjack pays 3:2 (25 back for 10). She walks round the table to stand behind it
## (goth_life.claim("cards", (165, 270), 2.4)) while the game is on, and goes back to wandering when it's over.
##
## The state is a Dictionary like the HTML game's w.bj ({} for none): ph "idle" | "play" | "dealer" | "done",
## deck, d (her cards), seats {chair: {c, st, bet, res}}, turn (the chair to play, 0 none), t (the dealer's timer),
## shown (her hole card is up), say, sayN. A card is 0..51: rank c % 13 (0 ace .. 12 king), suit c / 13
## (spade, heart, diamond, club); -1 is face down.
##
## The panel (top right, like the HTML game's), a CARDS button and the keys B (deal), H (hit), T (stand), pad X, Y, B.

const BET := 10
const SUITS := ["spade", "heart", "diamond", "club"]
const GREEN := Color(14 / 255.0, 40 / 255.0, 26 / 255.0, 0.9)

signal settled(chair: int, result: String, net: int)

var table: LobbyTable
var bj: Dictionary = {}
## The deck outlives a hand (bjDraw rebuilds it when it runs out).
var deck: Array = []
var say_n: int = 0
var rng := RandomNumberGenerator.new()

var _panel: PanelContainer
var _cards_btn: Button
var _sig: String = ""
var _pics: Array = []
var _pic_sig: String = ""
var _seen_cards: int = 0
var _tex_cache: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	_build_ui()

# ------------------------------------------------------------------ the rules

## bjValue (5240): aces 11 (down to 1 while over 21), faces 10, hidden cards skipped.
static func value(cs: Array) -> int:
	var v := 0
	var aces := 0
	for c in cs:
		if c < 0:
			continue
		var r: int = c % 13
		if r == 0:
			aces += 1
			v += 11
		else:
			v += mini(r + 1, 10)
	while v > 21 and aces > 0:
		v -= 10
		aces -= 1
	return v

static func rank_text(c: int) -> String:
	var r: int = c % 13
	return ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][r]

static func is_red(c: int) -> bool:
	return c >= 13 and c < 39

## bjDraw (5246): the top card (a fresh shuffled double deck when it is empty).
func draw() -> int:
	if deck.is_empty():
		for i in 104:
			deck.append(i % 52)
		for i in range(deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = deck[i]
			deck[i] = deck[j]
			deck[j] = t
	return deck.pop_back()

func active() -> bool:
	return not bj.is_empty()

func phase() -> String:
	return String(bj.get("ph", ""))

func _goth() -> GothLife:
	return table.ll.things.get("goth_life", null)

func _say(text: String) -> void:
	bj["say"] = text
	bj["sayN"] = int(bj.get("sayN", 0)) + 1
	say_n = bj["sayN"]
	var g := _goth()
	if g:
		g.say(text, 2.6)

func _float(p: Node, text: String, col: Color) -> void:
	var o := LobbyLife.hpos(p)
	table.ll.ui.float_text(o.x, o.y, 70.0, text, col, 1.1, 18)

func _goth_busy() -> bool:
	var g := _goth()
	return g != null and g.is_busy()

func _fresh(keep_deck: bool) -> Dictionary:
	return {"ph": "idle", "deck": [], "d": [], "seats": {}, "turn": 0, "t": 0.0, "shown": false, "say": "",
		"sayN": say_n}

func _start_dealing() -> void:
	var g := _goth()
	if g:
		g.claim("cards", Vector2(LobbyTable.TX, LobbyTable.TY - 30.0), 2.4, Vector2(0, 1))

func _end() -> void:
	bj = {}
	var g := _goth()
	if g:
		g.unclaim("cards")

## bjAction (5254): p (seated) does call | stop | deal | hit | stand.
func act(p: Node, a: String) -> void:
	if not table.sitters.has(p):
		return
	var ch: int = table.chair_of(p)
	var ph := phase()
	if a == "call" or (a == "deal" and bj.is_empty()):
		if not bj.is_empty():
			return
		if _goth_busy():
			_float(p, "Gothica's busy!", Color("#f7a8ff"))
			return
		bj = _fresh(true)
		_start_dealing()
		_say("Cards? Sure, I'll deal." if rng.randf() < 0.5 else "Ooh, blackjack? Coming!")
		return
	if bj.is_empty():
		return
	match a:
		"stop":
			if ph == "idle" or ph == "done":
				_end()
		"deal":
			if ph == "play" or ph == "dealer":
				return
			if _goth_busy():
				_float(p, "Gothica's busy!", Color("#f7a8ff"))
				return
			_deal()
		"hit":
			if ph != "play" or int(bj.turn) != ch:
				return
			var seat: Dictionary = bj.seats.get(ch, {})
			if seat.is_empty() or seat.st != "play":
				return
			seat.c.append(draw())
			var v := value(seat.c)
			if v > 21:
				seat.st = "bust"
			elif v == 21:
				seat.st = "stand"
			if seat.st != "play":
				_advance()
		"stand":
			if ph != "play" or int(bj.turn) != ch:
				return
			var seat2: Dictionary = bj.seats.get(ch, {})
			if seat2.is_empty() or seat2.st != "play":
				return
			seat2.st = "stand"
			_advance()

## A new hand (the "deal" of bjAction): the bets, two rounds of cards.
func _deal() -> void:
	var keep_n := int(bj.get("sayN", say_n))
	say_n = keep_n
	bj = _fresh(true)
	bj["sayN"] = keep_n
	var ll := table.ll
	for ch in [1, 2]:
		var p := table.sitter_at(ch)
		if p == null:
			continue
		if ll.cash(p) < BET:
			_float(p, "need 10 coins", Color("#e0473f"))
			continue
		ll.add_cash(p, -BET)
		bj.seats[ch] = {"pid": ch, "p": p, "c": [], "st": "play", "bet": BET, "res": ""}
	if bj.seats.is_empty():
		_end()
		return
	for r in 2:
		for ch in [1, 2]:
			if bj.seats.has(ch):
				bj.seats[ch].c.append(draw())
		bj.d.append(draw())
	for ch in bj.seats:
		if value(bj.seats[ch].c) == 21:
			bj.seats[ch].st = "bj"
	bj.ph = "play"
	bj.turn = 0
	for ch in [1, 2]:
		if bj.seats.has(ch) and bj.seats[ch].st == "play":
			bj.turn = ch
			break
	_say("Cards, boys." if bj.seats.size() == 2 else "Cards up, big guy.")
	if int(bj.turn) == 0:
		bj.ph = "dealer"
		bj.t = 0.9

## bjAdvance: the next seat that is still to play, else her turn.
func _advance() -> void:
	for ch in [1, 2]:
		if bj.seats.has(ch) and bj.seats[ch].st == "play":
			bj.turn = ch
			return
	bj.turn = 0
	bj.ph = "dealer"
	bj.t = 0.7

## stepBJ (5291), every frame.
func _process(dt: float) -> void:
	if not bj.is_empty():
		_step(minf(dt, 0.1))
	_update_ui()

func _step(dt: float) -> void:
	var ph := phase()
	for ch in bj.seats.keys():
		var seat: Dictionary = bj.seats[ch]
		if table.sitter_at(ch) == seat.p:
			continue
		if ph == "play" or ph == "dealer":
			if seat.st == "play" or seat.st == "stand" or seat.st == "bj":
				seat.st = "left"
				seat.res = "LEFT"
				if int(bj.turn) == ch:
					_advance()
		else:
			bj.seats.erase(ch)
	ph = phase()
	if ph != "dealer" and table.sitters.is_empty():
		_end()
		return
	if ph != "dealer":
		return
	bj.t -= dt
	if bj.t > 0.0:
		return
	if not bj.shown:
		bj.shown = true
		bj.t = 0.8
		return
	var any_stand := false
	for ch in bj.seats:
		if bj.seats[ch].st == "stand":
			any_stand = true
	if any_stand and value(bj.d) < 17:
		bj.d.append(draw())
		bj.t = 0.8
		return
	_settle()

func _settle() -> void:
	var ll := table.ll
	var dv := value(bj.d)
	var dbj: bool = dv == 21 and bj.d.size() == 2
	var won := false
	var lost := false
	var any_bj := false
	for ch in bj.seats:
		var seat: Dictionary = bj.seats[ch]
		var v := value(seat.c)
		var pay := 0
		var res := ""
		if seat.st == "left":
			res = "LEFT"
		elif seat.st == "bust":
			res = "BUST"
		elif seat.st == "bj":
			if dbj:
				res = "PUSH"
				pay = BET
			else:
				res = "BLACKJACK"
				pay = int(round(BET * 2.5))
		elif dbj:
			res = "LOSE"
		elif dv > 21 or v > dv:
			res = "WIN"
			pay = BET * 2
		elif v == dv:
			res = "PUSH"
			pay = BET
		else:
			res = "LOSE"
		seat.res = res
		var net: int = pay - int(seat.bet)
		if res == "BLACKJACK":
			any_bj = true
		if net > 0:
			won = true
		elif net < 0:
			lost = true
		if pay > 0:
			ll.add_cash(seat.p, pay)
		var col := Color("#6fd3a0") if net > 0 else (Color("#e0473f") if net < 0 else Color("#f6d17a"))
		_float(seat.p, res + (" +%d" % net if net > 0 else (" %d" % net if net < 0 else "")), col)
		ll.sfx.play("win" if net > 0 else ("lose" if net < 0 else "click"))
		settled.emit(ch, res, net)
	if any_bj:
		_say("Blackjack?! Lucky.")
	elif dv > 21:
		_say("Ugh, I bust.")
	elif dbj:
		_say("Blackjack. House wins~")
	elif won and not lost:
		_say("Fine, you win.")
	elif lost and not won:
		_say("House wins~")
	else:
		_say("Some you win...")
	bj.ph = "done"
	bj.turn = 0

func on_sit(_p: Node, _chair: int) -> void:
	pass

func on_stand(_p: Node, _chair: int) -> void:
	pass

## What the players see: her hole card face down until it is shown.
func view_dealer() -> Array:
	var out: Array = []
	for i in bj.d.size():
		out.append(-1 if (i == 1 and not bj.shown) else bj.d[i])
	return out

# ------------------------------------------------------------------ the panel, buttons and cards on the table

func _build_ui() -> void:
	var ll := table.ll
	if ll == null or ll.ui == null:
		return
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = GREEN
	sb.border_color = LobbyUI.PINK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -66
	_panel.offset_top = 52
	_panel.custom_minimum_size = Vector2(330, 0)
	_panel.visible = false
	ll.ui.root.add_child(_panel)
	_cards_btn = Button.new()
	_cards_btn.text = "CARDS\n(B)"
	_cards_btn.custom_minimum_size = Vector2(88, 88)
	_cards_btn.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(14 / 255.0, 40 / 255.0, 26 / 255.0, 0.8 if st == "normal" else 0.95)
		s.border_color = Color("#6fd3a0")
		s.set_border_width_all(2)
		s.set_corner_radius_all(44)
		_cards_btn.add_theme_stylebox_override(st, s)
	_cards_btn.add_theme_color_override("font_color", Color("#6fd3a0"))
	_cards_btn.add_theme_font_size_override("font_size", 15)
	_cards_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_cards_btn.offset_left = -246
	_cards_btn.offset_right = -158
	_cards_btn.offset_top = -234
	_cards_btn.offset_bottom = -146
	_cards_btn.pressed.connect(func(): if table.ll.player: act(table.ll.player, "call"))
	_cards_btn.visible = false
	ll.ui.root.add_child(_cards_btn)

func _update_ui() -> void:
	var ll := table.ll
	if _panel == null or ll == null or ll.player == null:
		return
	var p := ll.player
	var seated := table.sitters.has(p)
	var tripping: bool = table.trip != null and table.trip.active
	_cards_btn.visible = seated and bj.is_empty() and not tripping
	_panel.visible = seated and not bj.is_empty() and not tripping
	_update_cards_on_table()
	if not _panel.visible:
		_sig = ""
		return
	var view := {"bj": bj.duplicate(true), "coins": ll.cash(p), "me": table.chair_of(p), "dv": view_dealer()}
	for ch in view.bj.get("seats", {}):
		view.bj.seats[ch].erase("p")
	view.bj.erase("deck")
	var sig := var_to_str(view)
	if sig == _sig:
		return
	_sig = sig
	# a card flick when more cards are showing than before
	var n := 0
	for c in view.dv:
		n += 1
	for ch in bj.seats:
		n += bj.seats[ch].c.size()
	if n > _seen_cards:
		ll.sfx.play("card")
	_seen_cards = n
	_rebuild(p, view)

func _rebuild(p: Node, view: Dictionary) -> void:
	for c in _panel.get_children():
		_panel.remove_child(c)
		c.queue_free()
	var me: int = view.me
	var ph := phase()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	var l1 := _lbl("BLACKJACK", 15, LobbyUI.PINK)
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l1)
	head.add_child(_lbl("coins %d" % view.coins, 14, LobbyUI.GOLD))
	box.add_child(head)
	if ph == "idle":
		var a := _lbl("Gothica deals. Beat her to 21 without going over.", 13, Color("#dfe6ea"))
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var b := _lbl("Dealer stands on 17 · blackjack pays 3:2", 13, Color("#dfe6ea"))
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(a)
		box.add_child(b)
	else:
		var shown: bool = bj.shown
		var dv: int = value(bj.d) if shown else value(view.dv)
		box.add_child(_row("GOTHICA", dv, view.dv, "drawing..." if ph == "dealer" else "", ph == "dealer"))
		for ch in [1, 2]:
			if not bj.seats.has(ch):
				continue
			var seat: Dictionary = bj.seats[ch]
			var note: String = seat.res
			if note == "":
				if seat.st == "bust":
					note = "BUST"
				elif seat.st == "bj":
					note = "BLACKJACK!"
				elif seat.st == "play" and int(bj.turn) == ch:
					note = "your go" if ch == me else "their go"
				elif seat.st == "stand":
					note = "stands"
			var who := "YOU" if ch == me else "P%d" % ch
			box.add_child(_row(who, value(seat.c), seat.c, note, int(bj.turn) == ch))
		if not bj.seats.has(me) and ph != "done":
			var sit := _lbl("sitting this hand out", 12, Color("#bfc8d0"))
			sit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(sit)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	var my_turn: bool = ph == "play" and int(bj.turn) == me and bj.seats.has(me) and bj.seats[me].st == "play"
	if my_turn:
		btns.add_child(LobbyTable._btn("HIT (H)", Color("#2f7d4a"), 130, func(): act(table.ll.player, "hit")))
		btns.add_child(LobbyTable._btn("STAND (T)", Color("#3a2150"), 130, func(): act(table.ll.player, "stand")))
	elif ph == "idle" or ph == "done":
		var txt := "DEAL AGAIN (B) · 10 coins" if ph == "done" else "DEAL (B) · 10 coins"
		btns.add_child(LobbyTable._btn(txt, Color("#3a2150"), 202, func(): act(table.ll.player, "deal")))
		btns.add_child(LobbyTable._btn("DONE", Color("#3a2150"), 88, func(): act(table.ll.player, "stop")))
	box.add_child(btns)

func _lbl(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _row(label: String, total: int, cs: Array, note: String, lit: bool) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(66, 0)
	v.add_theme_constant_override("separation", 0)
	v.add_child(_lbl(label, 12, Color.WHITE if lit else Color("#bfc8d0")))
	v.add_child(_lbl(str(total), 17, Color("#ff6a6a") if total > 21 else Color.WHITE))
	h.add_child(v)
	var cb := HBoxContainer.new()
	cb.add_theme_constant_override("separation", 4)
	for c in cs:
		var cv := _CardView.new()
		cv.c = c
		cv.custom_minimum_size = Vector2(26, 36)
		cb.add_child(cv)
	h.add_child(cb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var col := Color("#f6d17a")
	if note.contains("WIN") or note.contains("BLACKJACK"):
		col = Color("#6fd3a0")
	elif note.contains("LOSE") or note.contains("BUST") or note.contains("LEFT"):
		col = Color("#ff6a6a")
	h.add_child(_lbl(note, 13, col))
	return h

## drawTableCards (5359): the cards lying on the table, six by eight, as little pictures standing on the table
## picture's line like the bong.
func _update_cards_on_table() -> void:
	var sig := ""
	if not bj.is_empty():
		sig = var_to_str([view_dealer(), bj.seats.keys().map(func(k): return bj.seats[k].c)])
	if sig == _pic_sig:
		return
	_pic_sig = sig
	for pc in _pics:
		if is_instance_valid(pc):
			pc.queue_free()
	_pics.clear()
	if bj.is_empty():
		return
	var x := LobbyTable.TX
	var y := LobbyTable.TY
	var i := 0
	for c in view_dealer():
		_card_pic(c, x - 8.0 + i * 4.0, y - 16.0, i)
		i += 1
	for ch in [1, 2]:
		if not bj.seats.has(ch):
			continue
		var j := 0
		for c in bj.seats[ch].c:
			_card_pic(c, (x - 24.0 if ch == 1 else x + 8.0) + j * 3.0, y - 6.0, j + 5 * ch)
			j += 1

func _card_pic(c: int, left: float, top: float, order: int) -> void:
	var pic := LobbyPic.make(_card_tex(c), 0.5, 0.0)
	table.add_child(pic)
	pic.global_position = GameData.world_to_3d(left + 3.0, LobbyTable.FEET_Y + 0.5 + order * 0.02, 0.0)
	pic.lift = LobbyTable.FEET_Y - (top + 8.0)
	_pics.append(pic)

## A card 6x8 (12x16 art pixels): a back, or a face with its colour's dot (drawCard's W < 14 form).
func _card_tex(c: int) -> Texture2D:
	var k := -1 if c < 0 else (1 if is_red(c) else 0)
	if _tex_cache.has(k):
		return _tex_cache[k]
	var im := Image.create(12, 16, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	var base := Color("#5a2a6e") if k < 0 else Color("#fbf8f0")
	var edge := Color("#1c1a22")
	for yy in 16:
		for xx in 12:
			var corner := (xx == 0 or xx == 11) and (yy == 0 or yy == 15)
			if corner:
				continue
			var border := xx == 0 or xx == 11 or yy == 0 or yy == 15
			im.set_pixel(xx, yy, (edge if k >= 0 else Color("#3c1a4a")) if border else base)
	if k < 0:
		for yy in range(2, 14):
			for xx in range(2, 10):
				if xx == 2 or xx == 9 or yy == 2 or yy == 13:
					im.set_pixel(xx, yy, Color("#f7a8ff"))
	else:
		var dot := Color("#d8283a") if k == 1 else edge
		for yy in range(7, 9):
			for xx in range(5, 7):
				im.set_pixel(xx, yy, dot)
		for yy in range(3, 5):
			for xx in range(3, 5):
				im.set_pixel(xx, yy, dot)
	var t := ImageTexture.create_from_image(im)
	_tex_cache[k] = t
	return t

## drawCard (5338) for the panel: back, or rank and suit.
class _CardView extends Control:
	var c: int = -1

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0.35)
		sh.set_corner_radius_all(int(w / 7.0))
		draw_style_box(sh, Rect2(1, 2, w, h))
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(int(w / 7.0))
		if c < 0:
			sb.bg_color = Color("#5a2a6e")
			draw_style_box(sb, Rect2(0, 0, w, h))
			var inner := StyleBoxFlat.new()
			inner.bg_color = Color(0, 0, 0, 0)
			inner.border_color = Color("#f7a8ff")
			inner.set_border_width_all(1)
			inner.set_corner_radius_all(int(w / 10.0))
			draw_style_box(inner, Rect2(w * 0.14, w * 0.14, w * 0.72, h - w * 0.28))
			return
		sb.bg_color = Color("#fbf8f0")
		sb.border_color = Color("#1c1a22")
		sb.set_border_width_all(1)
		draw_style_box(sb, Rect2(0, 0, w, h))
		var col := Color("#d8283a") if LobbyTableCards.is_red(c) else Color("#1c1a22")
		var f := get_theme_default_font()
		var fs := int(round(w * 0.42))
		var txt := LobbyTableCards.rank_text(c)
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((w - tw) / 2.0, h * 0.3 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		_suit(int(c / 13), Vector2(w / 2.0, h * 0.7), w * 0.25, col)

	func _suit(s: int, ctr: Vector2, r: float, col: Color) -> void:
		match s:
			1:      # heart
				draw_circle(ctr + Vector2(-r * 0.5, -r * 0.3), r * 0.55, col)
				draw_circle(ctr + Vector2(r * 0.5, -r * 0.3), r * 0.55, col)
				draw_colored_polygon(PackedVector2Array([ctr + Vector2(-r * 1.02, -r * 0.1), ctr + Vector2(r * 1.02, -r * 0.1), ctr + Vector2(0, r)]), col)
			2:      # diamond
				draw_colored_polygon(PackedVector2Array([ctr + Vector2(0, -r), ctr + Vector2(r * 0.75, 0), ctr + Vector2(0, r), ctr + Vector2(-r * 0.75, 0)]), col)
			0:      # spade
				draw_circle(ctr + Vector2(-r * 0.5, r * 0.15), r * 0.55, col)
				draw_circle(ctr + Vector2(r * 0.5, r * 0.15), r * 0.55, col)
				draw_colored_polygon(PackedVector2Array([ctr + Vector2(-r * 1.02, r * 0.05), ctr + Vector2(r * 1.02, r * 0.05), ctr + Vector2(0, -r)]), col)
				draw_colored_polygon(PackedVector2Array([ctr + Vector2(-r * 0.2, r * 0.3), ctr + Vector2(r * 0.2, r * 0.3), ctr + Vector2(r * 0.4, r), ctr + Vector2(-r * 0.4, r)]), col)
			_:      # club
				draw_circle(ctr + Vector2(0, -r * 0.5), r * 0.5, col)
				draw_circle(ctr + Vector2(-r * 0.55, r * 0.3), r * 0.5, col)
				draw_circle(ctr + Vector2(r * 0.55, r * 0.3), r * 0.5, col)
				draw_colored_polygon(PackedVector2Array([ctr + Vector2(-r * 0.2, 0), ctr + Vector2(r * 0.2, 0), ctr + Vector2(r * 0.4, r), ctr + Vector2(-r * 0.4, r)]), col)
