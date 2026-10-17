class_name FarmUI
extends CanvasLayer
## The farm's on-screen bits: a status strip (cash, seeds, buds, the can, fertiliser, the buff, the day and time),
## a line or two about what's in front of you under the E prompt (farmHint, in both views), a toast for raids,
## buffs and dropped seeds, the BAG button, and the farm panel.
##
## The panel opens at the crate (shop), the garage door (sell), a FOR SALE sign or the tractor shed (land and
## upgrades), the breeding table (breed), or anywhere with Tab / I / the pad's Y / the BAG button (your bag: pick
## the seed and the fertiliser E uses, smoke a bud). It's all buttons: click or tap them, or move between them
## with the arrows, the d-pad or the stick and press Enter / Space / A; Esc, B, Tab or the X closes it. While it's
## open the player stands still and the mouse is free.

const D := preload("res://scripts/farm/farm_data.gd")
const PINK := Color("#f7a8ff")
const GREEN := Color("#bff08a")
const PALE := Color("#dfe8d2")
const GOLD := Color("#f6d17a")
const BLUE := Color("#8fd3ff")

var farm: Farm
var world: FarmWorld
var player: Node
var rig: Node

var _root: Control
var _status: HBoxContainer          # one Label per item, so nothing can draw over a neighbour
var _status_key := ""
var _hint: Label
var _toast: Label
var _toast_t := 0.0
var _bag_btn: Button
var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _tabs: HBoxContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _msg: Label
var _context := ""
var _pid := 0
var _was_capture := true
var _rebuild_pending := false
var _icons := {}
var _can3d: Sprite3D                 # the watering can in his hand (top-down)
var _can_fp: TextureRect             # and down at the bottom of the screen (first person)

func _ready() -> void:
	layer = 11
	_ensure_actions()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_status = HBoxContainer.new()
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.position = Vector2(12, 46)
	_status.add_theme_constant_override("separation", 16)
	_root.add_child(_status)

	_hint = _label(_root, "", 15, PALE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)

	_toast = _label(_root, "", 20, GOLD)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = 84
	_toast.visible = false

	_bag_btn = Button.new()
	_bag_btn.text = "BAG"
	_bag_btn.icon = _icon("bud")
	_bag_btn.expand_icon = false
	_bag_btn.focus_mode = Control.FOCUS_NONE
	_bag_btn.add_theme_font_size_override("font_size", 16)
	_bag_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_bag_btn.offset_left = 12
	_bag_btn.offset_right = 120
	_bag_btn.offset_top = -92
	_bag_btn.offset_bottom = -40
	_bag_btn.pressed.connect(func(): toggle("bag"))
	_root.add_child(_bag_btn)

	_can_fp = TextureRect.new()
	_can_fp.texture = _icon("can")
	_can_fp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_can_fp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_can_fp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_can_fp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_can_fp.rotation = -0.12
	_can_fp.visible = false
	_root.add_child(_can_fp)

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.35)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	_root.add_child(_dim)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(20 / 255.0, 16 / 255.0, 24 / 255.0, 0.94)
	sb.border_color = Color("#7fbf5a")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.visible = false
	_root.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	_title = _label(top, "", 22, GREEN)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x := _button(top, "X", func(): close())
	x.custom_minimum_size = Vector2(52, 44)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	vb.add_child(_tabs)
	_msg = _label(vb, "", 16, GOLD)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_scroll.add_child(_body)

func setup(f: Farm, w: FarmWorld, p: Node, r: Node) -> void:
	farm = f
	world = w
	player = p
	rig = r
	farm.panel_wanted.connect(func(ctx, pid): open(ctx, pid))
	farm.changed.connect(func(): if _panel.visible: _rebuild_pending = true)
	farm.raid_resolved.connect(_on_raid)
	farm.raid_started.connect(func(r2): toast("RAIDERS ARE AFTER %d PLANTS!" % r2.targets.size(), Color("#ff7a6a")))
	farm.seed_dropped.connect(func(s): toast("A RAIDER DROPPED A %s SEED!" % D.STRAINS[s].name.to_upper(), GREEN))
	farm.buff_changed.connect(func(b): toast(("%s: %s (%d wave%s)" % [b.name.to_upper(), D.STRAINS[b.strain].effect, b.waves, "" if b.waves == 1 else "s"]) if not b.is_empty() else "THE BUFF HAS WORN OFF", PINK))
	farm.sound.connect(play)
	if world:
		farm.floater.connect(world_floater)
		_can3d = Sprite3D.new()
		_can3d.texture = _icon("can")
		_can3d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_can3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_can3d.pixel_size = 0.9 * 0.025
		_can3d.visible = false
		world.add_child(_can3d)

static func _ensure_actions() -> void:
	# the panel by pad: A presses, B backs out, the d-pad moves (added if the ui actions lack them)
	var pad := {"ui_accept": [JOY_BUTTON_A], "ui_cancel": [JOY_BUTTON_B], "ui_up": [JOY_BUTTON_DPAD_UP],
		"ui_down": [JOY_BUTTON_DPAD_DOWN], "ui_left": [JOY_BUTTON_DPAD_LEFT], "ui_right": [JOY_BUTTON_DPAD_RIGHT]}
	for a in pad:
		if not InputMap.has_action(a):
			continue
		for b in pad[a]:
			var have := false
			for e in InputMap.action_get_events(a):
				if e is InputEventJoypadButton and e.button_index == b:
					have = true
			if not have:
				var j := InputEventJoypadButton.new()
				j.button_index = b
				InputMap.action_add_event(a, j)
	if not InputMap.has_action("farm_bag"):
		InputMap.add_action("farm_bag")
		for k in [KEY_TAB, KEY_I]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event("farm_bag", e)
		var j := InputEventJoypadButton.new()
		j.button_index = JOY_BUTTON_Y
		InputMap.action_add_event("farm_bag", j)

func _label(parent: Control, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l

func _button(parent: Control, text: String, cb: Callable, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 48)      # big enough for a thumb
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("focus", _focus_box())
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

static var _fbox: StyleBoxFlat
static func _focus_box() -> StyleBoxFlat:
	if _fbox == null:
		_fbox = StyleBoxFlat.new()
		_fbox.draw_center = false
		_fbox.border_color = Color("#f7a8ff")
		_fbox.set_border_width_all(3)
		_fbox.set_corner_radius_all(6)
		_fbox.set_expand_margin_all(2)
	return _fbox

func _icon(n: String) -> Texture2D:
	if not _icons.has(n):
		_icons[n] = load("res://assets/farm/%s.png" % n)
	return _icons[n]

## A farm sound (assets/farm/snd_<name>.wav).
var _players: Array = []
func play(n: String) -> void:
	var st = load("res://assets/farm/snd_%s.wav" % n)
	if st == null:
		return
	var pl: AudioStreamPlayer = null
	for a in _players:
		if not a.playing:
			pl = a
			break
	if pl == null:
		if _players.size() >= 6:
			return
		pl = AudioStreamPlayer.new()
		pl.volume_db = -6.0
		add_child(pl)
		_players.append(pl)
	pl.stream = st
	pl.play()

## ---------------------------------------------------------------- the panel

func is_open() -> bool:
	return _panel.visible

func toggle(ctx: String) -> void:
	if _panel.visible:
		close()
	else:
		open(ctx, Farm.pid_of(player))

func open(ctx: String, pid: int = 0) -> void:
	_context = ctx
	_pid = pid
	_msg.text = ""
	if not _panel.visible:
		_panel.visible = true
		_dim.visible = true
		if player:
			player.set("controls_enabled", false)
			if player.has_method("halt"):
				player.halt()
		if rig:
			_was_capture = bool(rig.get("capture_mouse"))
			rig.set("capture_mouse", false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild(true)

func close() -> void:
	if not _panel.visible:
		return
	_panel.visible = false
	_dim.visible = false
	if player:
		player.set("controls_enabled", true)
	if rig:
		rig.set("capture_mouse", _was_capture)
		if rig.get("mode") == 1 and _was_capture and not _touch_only():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("farm_bag") and not event.is_echo():
		toggle("bag")
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# Tab is also the GUI's "next button": with the panel open it closes it instead
	if _panel.visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		close()
		get_viewport().set_input_as_handled()
	elif _panel.visible and event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
		close()
		get_viewport().set_input_as_handled()

func _say(t: String) -> void:
	_msg.text = t

func _rebuild(grab: bool) -> void:
	_rebuild_pending = false
	var focus_i := -1
	var fo := get_viewport().gui_get_focus_owner()
	var buttons := _all_buttons()
	if fo:
		focus_i = buttons.find(fo)
	for c in _tabs.get_children():
		c.queue_free()
		_tabs.remove_child(c)
	for c in _body.get_children():
		c.queue_free()
		_body.remove_child(c)
	var names := {"bag": "YOUR BAG", "shop": "SEEDS & FERTILISER", "sell": "SELL BUDS", "land": "LAND & UPGRADES", "breed": "BREEDING TABLE"}
	_title.text = names.get(_context, "FARM") + "      $%d" % farm.cash()
	for ctx in (["bag"] if _context == "bag" else ["bag", _context]):
		var t := _button(_tabs, names[ctx].split(" ")[0] if ctx != "bag" else "BAG", func(): open(ctx, _pid))
		t.toggle_mode = true
		t.set_pressed_no_signal(ctx == _context)
		t.custom_minimum_size = Vector2(110, 40)
	match _context:
		"bag": _build_bag()
		"shop": _build_shop()
		"sell": _build_sell()
		"land": _build_land()
		"breed": _build_breed()
	_layout()
	buttons = _all_buttons()
	if grab or focus_i < 0:
		for b in buttons:
			if b.get_parent() != _tabs and not b.disabled and b.text != "X":
				b.grab_focus.call_deferred()
				break
	elif focus_i >= 0 and focus_i < buttons.size():
		buttons[focus_i].grab_focus.call_deferred()

func _all_buttons() -> Array:
	var out := []
	_collect(_panel, out)
	return out

func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		_collect(c, out)

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := minf(640.0, vp.x - 24.0)
	var h := minf(560.0, vp.y - 24.0)
	_panel.size = Vector2(w, h)
	_panel.position = (vp - _panel.size) / 2.0
	_panel.custom_minimum_size = Vector2(w, h)

## A row: an icon, a line of words, and buttons ([text, callable, enabled]).
func _row(icon: String, text: String, col: Color, buttons: Array = []) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_body.add_child(h)
	if icon != "":
		var t := TextureRect.new()
		t.texture = _icon(icon)
		t.custom_minimum_size = Vector2(32, 32)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(t)
	var l := _label(h, text, 16, col)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for b in buttons:
		_button(h, b[0], b[1], b[2] if b.size() > 2 else true)
	return h

func _heading(t: String) -> void:
	var l := _label(_body, t, 15, Color(0.75, 0.8, 0.7))
	l.add_theme_constant_override("outline_size", 2)

func _build_bag() -> void:
	var st := farm.state
	var v := st.inv_of(_pid)
	if not st.buff.is_empty():
		_row("joint", "BUFF: %s, %d wave%s left%s" % [st.buff.name, st.buff.waves, "" if st.buff.waves == 1 else "s", " (potent)" if st.buff.potent else ""], PINK)
	_heading("SEEDS  (the one E plants is marked)")
	var any := false
	for s in D.STRAINS.size():
		var n := int(v.seeds[s]) + int(v.frosty[s])
		if n <= 0:
			continue
		any = true
		var picked: bool = st.seed_pick(_pid) == s
		_row("seed", "%s%s x%d%s" % ["> " if picked else "", D.STRAINS[s].name, n, (" (%d frosty)" % v.frosty[s]) if int(v.frosty[s]) > 0 else ""],
			D.TIER_COLOURS[D.STRAINS[s].tier], [["PLANT THIS", func(): farm.pick_seed(_pid, s), not picked]])
	if not any:
		_row("", "no seeds: the crate against the shed sells them", PALE)
	_heading("BUDS  (smoke one for its buff before a wave)")
	any = false
	for s in D.STRAINS.size():
		var n := st.bud_count(_pid, s)
		if n <= 0:
			continue
		any = true
		_row("bud", "%s x%d  ($%d)  %s" % [D.STRAINS[s].name, n, st.bud_value(_pid, farm.price_mults, s), D.STRAINS[s].effect],
			D.TIER_COLOURS[D.STRAINS[s].tier], [["SMOKE", func(): _smoke(s)]])
	if not any:
		_row("", "no buds yet: grow some", PALE)
	_heading("FERTILISER  (E uses the marked one on a plant)")
	any = false
	for f in [1, 2, 3]:
		if int(v.ferts[f]) <= 0:
			continue
		any = true
		var picked: bool = st.fert_pick(_pid) == f
		_row(D.FERTS[f].icon, "%s%s x%d" % ["> " if picked else "", D.FERTS[f].name, v.ferts[f]], PALE, [["USE THIS", func(): farm.pick_fert(_pid, f), not picked]])
	if not any:
		_row("", "none: the crate sells it", PALE)
	_heading("WATERING CAN")
	_row("can", ("%d of %d waterings left" % [v.can, D.CAN_SIZE]) if int(v.can) > 0 else "not carrying it (fill it at the water tank)", BLUE)
	_row("", "harvests %d   sold $%d   smoked %d   raided %d" % [st.stats.harvests, st.stats.sold, st.stats.smoked, st.stats.raided], Color(0.7, 0.7, 0.7))

func _smoke(s: int) -> void:
	var b := farm.smoke(_pid, s)
	if not b.is_empty():
		_say("You smoke the %s. %s" % [D.STRAINS[s].name, D.STRAINS[s].effect])

func _build_shop() -> void:
	_heading("SEEDS")
	for s in D.STRAINS.size():
		var st: Dictionary = D.STRAINS[s]
		var txt := "%s  (%s, %s)  sells $%d, grows %d h / %d waves" % [st.name, st.type, D.TIER_NAMES[st.tier], st.price, int(st.hours), st.waves]
		if int(st.seed) > 0:
			_row("seed", txt, D.TIER_COLOURS[st.tier], [["$%d" % st.seed, func(): _say(farm.buy_seed(_pid, s, 1)), farm.cash() >= int(st.seed)],
				["5 $%d" % (int(st.seed) * 5), func(): _say(farm.buy_seed(_pid, s, 5)), farm.cash() >= int(st.seed) * 5]])
		else:
			_row("seed", txt + "  (bred or dropped by raiders)", D.TIER_COLOURS[st.tier].darkened(0.3))
	_heading("FERTILISER  (one bag a plant a harvest)")
	for f in [1, 2, 3]:
		var ft: Dictionary = D.FERTS[f]
		var what := "%d%% faster" % int(ft.speed * 100.0)
		if int(ft.buds) > 0:
			what += ", +%d bud" % ft.buds
		if int(ft.potency) > 0:
			what += ", +%d potency" % ft.potency
		_row(ft.icon, "%s: %s" % [ft.name, what], PALE, [["$%d" % ft.price, func(): _say(farm.buy_fert(_pid, f, 1)), farm.cash() >= int(ft.price)],
			["5 $%d" % (int(ft.price) * 5), func(): _say(farm.buy_fert(_pid, f, 5)), farm.cash() >= int(ft.price) * 5]])

func _build_sell() -> void:
	var st := farm.state
	var total := st.bud_value(_pid, farm.price_mults)
	_row("coin", "Everything: %d buds" % st.bud_count(_pid), GOLD, [["SELL ALL $%d" % total, func(): _sell(-1), total > 0]])
	for s in D.STRAINS.size():
		var n := st.bud_count(_pid, s)
		if n <= 0:
			continue
		var m := float(farm.price_mults.get(s, 1.0))
		var note := "" if is_equal_approx(m, 1.0) else ("  (market x%.2f)" % m)
		_row("bud", "%s x%d%s" % [D.STRAINS[s].name, n, note], D.TIER_COLOURS[D.STRAINS[s].tier], [["SELL $%d" % st.bud_value(_pid, farm.price_mults, s), func(): _sell(s)]])
	_row("", "Keep a bud or two to smoke: each strain's buff helps in a wave.", PALE)

func _sell(s: int) -> void:
	var v := farm.sell(_pid, s)
	if v > 0:
		_say("+$%d" % v)
		world_floater("+$%d" % v, GOLD, Farm.html_xy(player))

func _build_land() -> void:
	var st := farm.state
	_heading("LAND")
	for k in ["neighbour", "paddock"]:
		var nm: String = "The neighbour's block (24 plots, a grow house)" if k == "neighbour" else "The paddock (12 rows of %d; needs the tractor)" % D.P_ROW_PLANTS
		if st.land[k]:
			_row("", nm + ": yours", GREEN)
		else:
			var ok: bool = k == "neighbour" or st.land.neighbour
			_row("", nm + ("" if ok else " (buy the neighbour's first)"), PALE, [["BUY $%d" % D.LAND_PRICES[k], func(): _say(farm.buy_land(k)), ok and farm.cash() >= int(D.LAND_PRICES[k])]])
	_heading("UPGRADES")
	for k in D.UPGRADES:
		var u: Dictionary = D.UPGRADES[k]
		if st.upgrades[k]:
			_row("", "%s: %s (yours)" % [u.name, u.what], GREEN)
		else:
			var ok: bool = u.needs == "" or st.land[u.needs]
			_row("", "%s: %s%s" % [u.name, u.what, "" if ok else " (needs the %s)" % ("neighbour's block" if u.needs == "neighbour" else "paddock")], PALE,
				[["BUY $%d" % u.price, func(): _say(farm.buy_upgrade(k)), ok and farm.cash() >= int(u.price)]])

func _build_breed() -> void:
	var st := farm.state
	var v := st.inv_of(_pid)
	if not st.breeding.is_empty():
		var b: Dictionary = st.breeding
		_row("seed", "On the table: a %s seed%s. %s" % [D.STRAINS[b.s].name, " (frosty!)" if b.frosty else "", "Ready: E at the table takes it." if not b.waiting else "Ready after the next wave, or in %.1f h." % b.hours], GREEN,
			[["TAKE IT", func(): _take_bred(), not b.waiting]])
		return
	_heading("CROSS TWO SEEDS (two of a tier make one of the next; %d%% lucky)" % int(D.BREED_LUCKY * 100))
	for r in D.RECIPES:
		var a: int = r[0]
		var b: int = r[1]
		var have := func(s: int, n: int) -> bool: return int(v.seeds[s]) + int(v.frosty[s]) >= n
		var ok: bool = have.call(a, 2) if a == b else (have.call(a, 1) and have.call(b, 1))
		_row("seed", "%s + %s  =  %s" % [D.STRAINS[a].short, D.STRAINS[b].short, D.STRAINS[r[2]].name], D.TIER_COLOURS[D.STRAINS[r[2]].tier],
			[["CROSS", func(): _breed(a, b), ok]])

func _breed(a: int, b: int) -> void:
	var s := farm.breed(_pid, a, b)
	_say(("Crossing... a %s seed after the next wave." % D.STRAINS[s].name) if s >= 0 else "You need those two seeds.")

func _take_bred() -> void:
	var s := farm.state.breed_collect(_pid)
	if s >= 0:
		_say("+1 %s seed" % D.STRAINS[s].name)

## ---------------------------------------------------------------- the status strip, the hint, toasts, floaters

func toast(t: String, col: Color = GOLD) -> void:
	_toast.text = t
	_toast.add_theme_color_override("font_color", col)
	_toast.visible = true
	_toast_t = 4.0

func _on_raid(info: Dictionary) -> void:
	if info.lost.is_empty():
		toast("THE CROP HELD AGAINST THE RAIDERS", GREEN)
	else:
		toast("RAIDERS TOOK: " + ", ".join(info.lost), Color("#ff7a6a"))

## A word rising over the farm (the HTML game's floaters).
func world_floater(text: String, col: Color, at: Vector2) -> void:
	var parent: Node = world if world else self
	if not (parent is Node3D):
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
	l.position = GameData.world_to_3d(at.x, at.y, 90)
	parent.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.2, 1.4)
	tw.tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)

func _process(delta: float) -> void:
	if farm == null:
		return
	# (not while a button's held down: a click or A lands on the button it started on)
	if _rebuild_pending and _panel.visible and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_action_pressed("ui_accept"):
		_rebuild(false)
	if _panel.visible:
		_layout()
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		_toast.visible = _toast_t > 0.0
	_update_status()
	_update_hint()
	_update_can()
	var held := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_bag_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if held else Control.MOUSE_FILTER_STOP

## The farm's part of the game's one HUD line (FightHud draws it after the cash): only what you have.
func status_parts() -> Array:
	var st := farm.state
	var pid := Farm.pid_of(player)
	var v := st.inv_of(pid)
	var parts: Array = []
	if st.seed_count(pid) > 0:
		parts.append(["seeds %d" % st.seed_count(pid), "#d9ecb8"])
	if st.bud_count(pid) > 0:
		parts.append(["buds %d" % st.bud_count(pid), "#a8e480"])
	if int(v.can) > 0:
		parts.append(["can %d" % v.can, "#8fd3ff"])
	if st.fert_count(pid) > 0:
		parts.append(["bags %d" % st.fert_count(pid), "#e0c890"])
	if not st.buff.is_empty():
		parts.append(["%s %dw" % [D.STRAINS[st.buff.strain].short, st.buff.waves], "#f7a8ff"])
	return parts

## Off when the game's one HUD line shows the cash and the farm's items (the fight's HUD sets it).
var show_status := true

func _update_status() -> void:
	_status.visible = show_status
	if not show_status:
		return
	var st := farm.state
	var pid := Farm.pid_of(player)
	var v := st.inv_of(pid)
	var parts: Array = [["$%d" % farm.cash(), "#f6d17a"]]
	parts.append(["seeds %d" % st.seed_count(pid), "#d9ecb8"])
	parts.append(["buds %d" % st.bud_count(pid), "#a8e480"])
	if int(v.can) > 0:
		parts.append(["can %d" % v.can, "#8fd3ff"])
	if st.fert_count(pid) > 0:
		parts.append(["bags %d" % st.fert_count(pid), "#e0c890"])
	if not st.buff.is_empty():
		parts.append(["%s %dw" % [D.STRAINS[st.buff.strain].short, st.buff.waves], "#f7a8ff"])
	var c := farm.clock
	if c and is_instance_valid(c):
		var h := float(c.get("hour"))
		var hh := int(h) % 12
		parts.append(["day %d  %d:%02d %s" % [int(c.get("day")), 12 if hh == 0 else hh, int(fmod(h, 1.0) * 60.0), "am" if h < 12.0 else "pm"], "#ffffff"])
	var key := str(parts)
	if key == _status_key:
		return
	_status_key = key
	for ch in _status.get_children():
		_status.remove_child(ch)
		ch.queue_free()
	for p in parts:
		var l := _label(_status, p[0], 15, Color(p[1]))
		l.custom_minimum_size.x = l.get_minimum_size().x

## The spot in front of the player (the nearest farm spot in reach, with or without something for E to do).
func _spot_here() -> FarmSpot:
	if world == null or player == null or not (player is Node3D):
		return null
	var foc = player.get("focus")
	if foc is FarmSpot:
		return foc
	if foc != null:
		return null                      # E is about something else: say nothing
	var best: FarmSpot = null
	var bd := INF
	for s in world.spots:
		var d: float = s.ground_distance(player)
		if d <= s.reach and d < bd:
			bd = d
			best = s
	return best

func _update_hint() -> void:
	var lines: Array = []
	if not _panel.visible:
		var s := _spot_here()
		if s:
			lines = farm.hint_lines(s, player)
	_hint.text = "\n".join(lines)
	_hint.visible = not lines.is_empty()
	if _hint.visible:
		var vp := get_viewport().get_visible_rect().size
		var fp: bool = rig != null and rig.get("mode") == 1
		_hint.size = Vector2(vp.x, 50)
		_hint.position = Vector2(0, vp.y / 2.0 + 64.0 if fp else vp.y - 136.0)   # under the crosshair's E, or over the prompt

## The watering can, while you're carrying it: in his hand top-down, at the bottom of the screen in first person.
func _update_can() -> void:
	var holding := player != null and int(farm.state.inv_of(Farm.pid_of(player)).can) > 0
	var fp: bool = rig != null and rig.get("mode") == 1
	if _can3d:
		_can3d.visible = holding and not fp
		if _can3d.visible and player is Node3D:
			var f: Vector2 = player.get("facing") if player.get("facing") != null else Vector2(0, 1)
			var side := -1.0 if f.x < 0.0 else 1.0
			_can3d.global_position = player.global_position + Vector3(side * 16.0, 44.0 + float(player.get("dz") if player.get("dz") != null else 0.0), 6.0) * 0.025
			_can3d.flip_h = side > 0.0
	_can_fp.visible = holding and fp and not _panel.visible
	if _can_fp.visible:
		var vp := get_viewport().get_visible_rect().size
		var k := vp.y / 340.0
		_can_fp.size = Vector2(64, 64) * k
		_can_fp.position = Vector2(vp.x * 0.5 - 20 * k, vp.y - 50 * k)

static func _touch_only() -> bool:
	return DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")
