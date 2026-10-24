class_name VoxelHelp
extends CanvasLayer
## WHAT CAN I DO? (the owner, 25 Oct: "help page"): a HELP (?) button under SETTINGS (or the ? key) opens a page of
## cards, one an activity in the game: where it is, its keys, what it's for, and a tick once you've tried it (ticked
## by the game as you do each the first time; kept with the backpack's save). The first time you try one a small
## "Tried: ..." shows; the button says how many you've tried. Owned by the voxel session.

const PINK := Color("#f7a8ff")
const GOLD := Color("#f6d17a")
const GOOD := Color("#7fd89a")
const DIM := Color(1, 1, 1, 0.55)

## [id, title, where, keys, what it's for]
const CARDS := [
	["fight", "Fight", "The arena (where you start)",
		"Mouse aim, left fire   1-5 weapon groups (again: next)   R reload   F quick sword   V top-down",
		"Enemies come in waves, with a boss every fifth. Kills pay cash. Cut them up: every cube comes off."],
	["bench", "Weapon bench", "Back yard, left of the door",
		"E at the bench",
		"Spend kill cash on damage, clips, reload speed and more for your weapons."],
	["chests", "Backpack and chests", "Everywhere (Tab), chests in the house",
		"Tab backpack   E at a chest   (E at the vacuum cubes: suck them up)",
		"Keep what you find. Chests can have a 4-digit padlock."],
	["bed", "The bedroom", "The house, the bedroom door",
		"E at a bed (skips to morning)   E at the wardrobe",
		"Sleep to start a new game day: the crops, chickens and prices move on."],
	["dig", "Digging", "The back yard",
		"6 tools: the shovel, left dig, right fill",
		"Dig for worms, coins and stashes. A better shovel breaks harder ground."],
	["farm", "Farming", "The back yard, the SEEDS crate",
		"E at the crate (seeds)   6 hoe   E plant   6 watering can (E at the tank fills it)",
		"Grow weed (7 strains, Bush Kush too), water it, harvest the buds, sell at the BUYER."],
	["chickens", "Chickens", "Through the gate, back yard right",
		"E feed, collect eggs, open the gate   H eat",
		"Eggs hatch into more hens; poo is fertiliser. Out in the yard they can be killed for meat."],
	["barbecue", "Barbecue", "Back yard, by the far fence",
		"E with a chicken carcass: on the grill   E again: take it off",
		"Cook carcasses into roast chickens ($25, or +45 health). Leave them too long and they burn."],
	["shredder", "Shredder", "Back yard, the far fence",
		"E with meat, bones or a carcass",
		"Grind gore into blood and bone: the best fertiliser."],
	["games", "Games room", "The purple GAMES ROOM door",
		"E at the couch, a console or a game case",
		"Real retro consoles on the TV. In co-op your mate is player 2."],
	["slot", "Slot machine", "The arena's north wall",
		"E pulls the lever",
		"Old school: watch the reels spin."],
	["gothica", "Gothica", "The bedroom and games room",
		"E: she follows you round the house (E again: she stays)",
		"Your companion. Settings > Jiggle sets how much she bounces."],
	["mine", "The mine", "The MINE roller door in the yard wall",
		"E at the door   A/D drive and drill   S down   W fly   E at buildings   G help your mate",
		"Dig for ore, squirt it into the ORE box for cash, upgrade the Mole, go deeper. In co-op you dig together."],
	["coop", "Co-op", "Anywhere",
		"O: PLAY ONLINE (host a game, or join with your mate's code)",
		"Play with a mate over the internet: the fights, the farm, the chickens and the mine, together."],
]

var arena: Node3D
var done := {}                  # id -> true: tried
var _btn: Button
var _panel: PanelContainer
var _grid: GridContainer
var _count: Label
var _open := false
var _toast: Label
var _toast_t := 0.0

func setup(arena_: Node3D) -> void:
	arena = arena_
	layer = 31
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_btn = Button.new()
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 14)
	_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_btn.offset_left = -12
	_btn.offset_right = -12
	_btn.offset_top = 86
	_btn.offset_bottom = 118
	_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_btn.pressed.connect(toggle)
	_btn.button_down.connect(func(): arena._ignore[MOUSE_BUTTON_LEFT] = true)
	root.add_child(_btn)
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 150
	_toast.offset_bottom = 180
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", GOOD)
	_toast.add_theme_constant_override("outline_size", 5)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.visible = false
	root.add_child(_toast)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.1, 0.96)
	sb.border_color = PINK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 60
	_panel.offset_right = -60
	_panel.offset_top = 40
	_panel.offset_bottom = -40
	_panel.visible = false
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := Label.new()
	title.text = "WHAT CAN I DO?"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", PINK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 16)
	_count.add_theme_color_override("font_color", GOLD)
	top.add_child(_count)
	var close_b := Button.new()
	close_b.text = "  CLOSE (Esc)  "
	close_b.add_theme_font_size_override("font_size", 14)
	close_b.pressed.connect(close)
	top.add_child(close_b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	var foot := Label.new()
	foot.text = "Tip: Esc lets go of the mouse; V switches to top-down; F10 settings; O plays online."
	foot.add_theme_font_size_override("font_size", 13)
	foot.add_theme_color_override("font_color", DIM)
	v.add_child(foot)
	_refresh()

func _card(c: Array) -> Control:
	var tried := done.has(String(c[0]))
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.1, 0.18, 0.95) if not tried else Color(0.08, 0.16, 0.1, 0.95)
	sb.border_color = GOOD if tried else Color(1, 1, 1, 0.15)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := Label.new()
	t.text = String(c[1])
	t.add_theme_font_size_override("font_size", 19)
	t.add_theme_color_override("font_color", GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var tick := Label.new()
	tick.text = "✔ tried" if tried else "not tried yet"
	tick.add_theme_font_size_override("font_size", 14)
	tick.add_theme_color_override("font_color", GOOD if tried else DIM)
	h.add_child(tick)
	for k in 3:
		var l := Label.new()
		l.text = [String(c[2]), String(c[3]), String(c[4])][k]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		l.add_theme_font_size_override("font_size", 13 if k < 2 else 14)
		l.add_theme_color_override("font_color", [Color(0.75, 0.85, 1.0), Color(1, 0.9, 0.7), Color(1, 1, 1, 0.9)][k])
		v.add_child(l)
	return p

func _refresh() -> void:
	var n := 0
	for c in CARDS:
		if done.has(String(c[0])):
			n += 1
	_btn.text = "HELP (?)  %d/%d" % [n, CARDS.size()]
	if _count:
		_count.text = "You've tried %d of %d    " % [n, CARDS.size()]
	if _grid and _open:
		for ch in _grid.get_children():
			ch.queue_free()
		for c in CARDS:
			_grid.add_child(_card(c))

## The game: the player's just tried something (an id in CARDS): ticked (and said) the first time
func tried(id: String) -> void:
	if done.has(id):
		return
	var title := ""
	for c in CARDS:
		if String(c[0]) == id:
			title = String(c[1])
	if title == "":
		return
	done[id] = true
	_toast.text = "Tried: %s   (%d/%d, HELP has the rest)" % [title, done.size(), CARDS.size()]
	_toast.visible = true
	_toast_t = 3.0
	_refresh()
	if arena.stash:
		arena.stash._dirty = true

func is_open() -> bool:
	return _open

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func open() -> void:
	if _open:
		return
	if arena.settings_menu and arena.settings_menu.is_open():
		arena.settings_menu.close()
	if arena.net_menu and arena.net_menu.is_open():
		arena.net_menu.close()
	_open = true
	_panel.visible = true
	arena._let_go()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func close() -> void:
	if not _open:
		return
	_open = false
	_panel.visible = false
	if not arena.top_down and not arena._opts.has("auto") and not arena.inv_ui.is_open() and not arena.lock_view.is_open() \
			and not (arena.mine and arena.mine.active):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(dt: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= dt
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		_toast.visible = _toast_t > 0.0

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if e.physical_keycode == KEY_ESCAPE and _open:
		close()
		get_viewport().set_input_as_handled()
	elif e.physical_keycode == KEY_SLASH and not (arena.games and arena.games.seated > 0):
		toggle()
		get_viewport().set_input_as_handled()

func to_data() -> Array:
	return done.keys()

func from_data(d) -> void:
	done = {}
	if typeof(d) == TYPE_ARRAY:
		for id in d:
			done[String(id)] = true
	_refresh()
