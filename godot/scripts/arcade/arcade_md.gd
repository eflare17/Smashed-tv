class_name ArcadeMd
extends CanvasLayer
## The Bricks cabinet's menu: it's a Mega Drive (and Super Nintendo) too (Smashed.html, "MEGA DRIVE", b303 to
## b306). Your own library of game files kept in this browser on this device (nothing is uploaded), a console
## picker (All, Mega Drive, Super Nintendo, and Master System / Game Gear once you have one), Add games (files or
## a .zip of them from this device), Add a folder (desktop browsers), Play Bricks (the cabinet's own game), Play
## Snake (Spud Snake lives here now: the HTML game's Snake cabinet became Sand Miner), and Close. Each game in
## the list has its picture (taken a few seconds into its first play), its size and a remove button.
##
## Picking a game plays it in EmulatorJS over the whole game (web build: MdBridgeJs, through JavaScriptBridge).
## Off the web (the editor, a desktop build) the library can't be reached, so it says so; Bricks and Snake work.
##
## Usable with the mouse, a finger or a pad (focus moves with the d-pad or stick, A picks, B closes) or the keys
## (arrows, Enter, Esc).
##
## Player 2 (milestone 4): see "the friend" below. Google Drive (later): see drive_connect().

signal opened
signal closed

## The owner's Google OAuth client ID for the Drive games folder (PLAN.md, milestone 5). Empty: not set up yet.
const DRIVE_CLIENT_ID := ""
const SYS_SHOW := ["md", "snes", "sms", "gg"]
const SYS := {"md": {"label": "Mega Drive", "tag": "MD", "extra": false}, "snes": {"label": "Super Nintendo", "tag": "SNES", "extra": false},
	"sms": {"label": "Master System", "tag": "SMS", "extra": true}, "gg": {"label": "Game Gear", "tag": "GG", "extra": true}}
const EMPTY := {"md": "Mega Drive games end in .md, .bin, .gen or .smd.", "snes": "Super Nintendo games end in .sfc or .smc.",
	"sms": "Master System games end in .sms.", "gg": "Game Gear games end in .gg."}
const RED := Color("#e0473f")

var arcade: Arcade
var cab: Dictionary = {}
var games: Array = []                 # [{id, file, name, sys, size, pic}]
var pick: String = "all"
## A game of ours is running in the emulator (over the game), or we're watching the friend's.
var emu_mode: String = ""
var playing_name: String = ""

var _open := false
var _web := false
var _js_cb: JavaScriptObject
var _md: JavaScriptObject
var _pics: Dictionary = {}            # data URL -> texture
var _playing_pic: Texture2D

var _panel: Control
var _title: Label
var _note: Label
var _bar: HFlowContainer
var _sys_row: HFlowContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _btn_add: Button
var _btn_folder: Button
var _btn_bricks: Button
var _btn_snake: Button
var _btn_drive: Button
var _btn_close: Button
var _confirm: ConfirmationDialog
var _del_id := -1
var _ask: PanelContainer
var _ask_text: Label

func _ready() -> void:
	layer = 41
	_web = OS.has_feature("web")
	_build_ui()
	_panel.visible = false
	if _web:
		JavaScriptBridge.eval(MdBridgeJs.JS, true)
		_md = JavaScriptBridge.get_interface("SmashedMD")
		if _md:
			_js_cb = JavaScriptBridge.create_callback(_on_js)
			_md.setListener(_js_cb)

func is_open() -> bool:
	return _open

## Open the menu for this cabinet (mdOpen).
func open(c: Dictionary) -> void:
	cab = c
	_open = true
	_panel.visible = true
	note("")
	if arcade:
		arcade.hold_player(true)
	if _md:
		_md.list()
	else:
		note("The Mega Drive and Super Nintendo games play in the web version (they run in the browser's EmulatorJS). Bricks and Snake work here.")
		_draw_list()
	_btn_bricks.grab_focus.call_deferred()
	opened.emit()

## Shut it, and the emulator if a game's running (mdClose).
func close() -> void:
	if not _open and emu_mode == "":
		return
	if _md and emu_mode != "":
		_md.stop()
	emu_mode = ""
	_open = false
	_panel.visible = false
	if arcade and not arcade.overlay.is_open():
		arcade.hold_player(false)
	closed.emit()

func note(text: String) -> void:
	_note.text = text
	_note.visible = text != ""

# ---------------------------------------------------------------- the menu

func _build_ui() -> void:
	_panel = Panel.new()
	_panel.name = "Menu"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(10 / 255.0, 10 / 255.0, 14 / 255.0, 0.97)
	_panel.add_theme_stylebox_override("panel", bg)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 0)
	_panel.add_child(v)
	# the top bar
	var top := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color("#15171e")
	tsb.border_color = Color("#2a2f3b")
	tsb.border_width_bottom = 1
	tsb.content_margin_left = 10
	tsb.content_margin_right = 10
	tsb.content_margin_top = 8
	tsb.content_margin_bottom = 8
	top.add_theme_stylebox_override("panel", tsb)
	v.add_child(top)
	var th := HBoxContainer.new()
	top.add_child(th)
	_title = Label.new()
	_title.text = "MEGA DRIVE · SNES"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override("font_color", RED)
	_title.add_theme_font_size_override("font_size", 18)
	th.add_child(_title)
	_btn_close = _button("Close", close)
	th.add_child(_btn_close)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override("font_color", Color("#8b93a4"))
	_note.add_theme_font_size_override("font_size", 13)
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color("#1b1e27")
	nsb.content_margin_left = 10
	nsb.content_margin_right = 10
	nsb.content_margin_top = 6
	nsb.content_margin_bottom = 6
	_note.add_theme_stylebox_override("normal", nsb)
	v.add_child(_note)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	v.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	_bar = HFlowContainer.new()
	_bar.add_theme_constant_override("h_separation", 8)
	_bar.add_theme_constant_override("v_separation", 8)
	body.add_child(_bar)
	_btn_add = _button("+ Add games", func(): _pick_files(false), true)
	_btn_folder = _button("+ Add a folder", func(): _pick_files(true))
	_btn_bricks = _button("Play Bricks", func(): _play_builtin("bricks"))
	_btn_snake = _button("Play Snake", func(): _play_builtin("snake"))
	_btn_drive = _button("Connect Google Drive", drive_connect)
	for b in [_btn_add, _btn_folder, _btn_bricks, _btn_snake, _btn_drive]:
		_bar.add_child(b)
	_btn_folder.visible = false
	_btn_drive.tooltip_text = "A games folder shared with your friend (coming: needs the owner's Google sign-in set up)"
	var hint := Label.new()
	hint.text = "Your games stay on this device. They're never uploaded."
	hint.add_theme_color_override("font_color", Color("#8b93a4"))
	hint.add_theme_font_size_override("font_size", 13)
	body.add_child(hint)
	_sys_row = HFlowContainer.new()
	_sys_row.add_theme_constant_override("h_separation", 6)
	_sys_row.add_theme_constant_override("v_separation", 6)
	body.add_child(_sys_row)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Remove game"
	_confirm.confirmed.connect(func(): if _md and _del_id >= 0: _md.del(_del_id))
	_panel.add_child(_confirm)
	# the friend's offer: "<who> is playing <game> on the Mega Drive. Join as player 2 / No thanks" (mdAsk)
	_ask = PanelContainer.new()
	var asb := StyleBoxFlat.new()
	asb.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	asb.border_color = RED
	asb.set_border_width_all(2)
	asb.set_corner_radius_all(8)
	asb.content_margin_left = 12
	asb.content_margin_right = 12
	asb.content_margin_top = 8
	asb.content_margin_bottom = 8
	_ask.add_theme_stylebox_override("panel", asb)
	_ask.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ask.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ask.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ask.offset_bottom = -14
	_ask.visible = false
	add_child(_ask)
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", 10)
	_ask.add_child(ah)
	_ask_text = Label.new()
	ah.add_child(_ask_text)
	ah.add_child(_button("Join as player 2", join, true))
	ah.add_child(_button("No thanks", _no_thanks))

func _no_thanks() -> void:
	if offer:
		_dismissed = String(offer.name)
	_ask.visible = false

func _button(text: String, fn: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 14)
	var n := StyleBoxFlat.new()
	n.bg_color = Color("#3a1d1c") if primary else Color("#232833")
	n.border_color = RED if primary else Color("#333a49")
	n.set_border_width_all(1)
	n.set_corner_radius_all(6)
	n.content_margin_left = 12
	n.content_margin_right = 12
	n.content_margin_top = 7
	n.content_margin_bottom = 7
	var h := n.duplicate()
	h.bg_color = Color("#2c313f") if not primary else Color("#4a2422")
	var f := n.duplicate()
	f.border_color = Color("#f6d17a")
	f.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", f)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.pressed.connect(fn)
	return b

func _count(k: String) -> int:
	var n := 0
	for g in games:
		if k == "all" or g.sys == k:
			n += 1
	return n

func _draw_sys() -> void:
	for c in _sys_row.get_children():
		c.queue_free()
	var tiles := ["all"]
	for k in SYS_SHOW:
		if not SYS[k].extra or _count(k) > 0 or pick == k:
			tiles.append(k)
	for k in tiles:
		var n := _count(k)
		var b := _button(("All" if k == "all" else String(SYS[k].label)) + "   " + str(n), func(): set_pick(k), k == pick)
		if n == 0 and k != pick:
			b.modulate = Color(1, 1, 1, 0.55)
		_sys_row.add_child(b)

func set_pick(k: String) -> void:
	pick = k
	if _md:
		_md.setPick(k)
	else:
		_draw_list()

func _draw_list() -> void:
	_draw_sys()
	for c in _list.get_children():
		c.queue_free()
	var list: Array = games.filter(func(g): return pick == "all" or g.sys == pick)
	if list.is_empty():
		var p := Label.new()
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.add_theme_color_override("font_color", Color("#8b93a4"))
		p.add_theme_font_size_override("font_size", 13)
		if pick == "all":
			p.text = "No games yet. Tap \"Add games\" and pick Mega Drive games (.md, .bin, .gen, .smd), Super Nintendo games (.sfc, .smc), or a .zip of them from this device."
		else:
			p.text = "No " + String(SYS[pick].label) + " games yet. " + String(EMPTY[pick]) + " Tap \"Add games\" to add some."
		_list.add_child(p)
		return
	for g in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(64, 45)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture = picture(String(g.pic))
		if pic.texture == null:
			var blank := ColorRect.new()                  # no picture yet: a dark tile in its place
			blank.color = Color("#111522")
			blank.custom_minimum_size = Vector2(64, 45)
			blank.tooltip_text = "Play it once and it gets a picture"
			row.add_child(blank)
		else:
			row.add_child(pic)
		var id: int = int(g.id)
		var b := _button(String(g.name), func(): play(id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.tooltip_text = String(g.file)
		row.add_child(b)
		var s := Label.new()
		s.text = (String(SYS.get(g.sys, SYS.md).tag) + "  " if pick == "all" else "") + _size(int(g.size))
		s.custom_minimum_size = Vector2(90, 0)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.add_theme_color_override("font_color", Color("#6b7385"))
		s.add_theme_font_size_override("font_size", 12)
		row.add_child(s)
		var d := _button("Remove", func(): _ask_delete(id, String(g.name)))
		d.tooltip_text = "Remove from library"
		row.add_child(d)
		_list.add_child(row)

static func _size(n: int) -> String:
	return ("%.1f MB" % (n / 1048576.0)) if n >= 1048576 else (str(maxi(1, roundi(n / 1024.0))) + " KB")

func _ask_delete(id: int, name_: String) -> void:
	_del_id = id
	_confirm.dialog_text = "Remove \"" + name_ + "\" from this device?"
	_confirm.popup_centered()

## A game's picture (a JPEG data URL from the library), as a texture.
func picture(data_url: String) -> Texture2D:
	if data_url == "":
		return null
	if _pics.has(data_url):
		return _pics[data_url]
	var comma := data_url.find(",")
	var t: Texture2D = null
	if comma > 0:
		var img := Image.new()
		var raw := Marshalls.base64_to_raw(data_url.substr(comma + 1))
		var err := img.load_jpg_from_buffer(raw) if data_url.contains("jpeg") else img.load_png_from_buffer(raw)
		if err == OK:
			t = ImageTexture.create_from_image(img)
	_pics[data_url] = t
	return t

## The picture of what's being played on the cabinet (yours, or the friend's they offered), or null (mdCabPic).
func cab_picture() -> Texture2D:
	if emu_mode == "play" and _playing_pic:
		return _playing_pic
	if offer and offer.has("pic"):
		return picture(String(offer.pic))
	return null

func _pick_files(folder: bool) -> void:
	if not _md:
		note("Adding games works in the web version.")
		return
	if _last_pointer_click:
		return                                     # the page opened the picker in the click itself (_send_pick_rects)
	_md.pick(folder)                               # the keys: Enter is a user action too, if the browser lets it

var _last_pointer_click := false
var _rects_sent := ""

## Tell the page where the Add buttons are, as fractions of the canvas (empty when the menu's shut).
func _send_pick_rects() -> void:
	if not _md:
		return
	var out: Array = []
	if _open and _panel.visible and not _confirm.visible:
		var vs := get_viewport().get_visible_rect().size
		for b in [[_btn_add, false], [_btn_folder, true]]:
			var btn: Button = b[0]
			if btn.is_visible_in_tree():
				var r := btn.get_global_rect()
				out.append({"x": r.position.x / vs.x, "y": r.position.y / vs.y, "w": r.size.x / vs.x, "h": r.size.y / vs.y, "folder": b[1]})
	var j := JSON.stringify(out)
	if j != _rects_sent:
		_rects_sent = j
		_md.setPickRects(j)

func _play_builtin(id: String) -> void:
	var c := cab
	close()
	if arcade:
		arcade.overlay.open(c, id)

## Play a game from the library in the emulator (mdPlay).
func play(id: int) -> void:
	if _md:
		_md.play(id)

func _on_js(args: Array) -> void:
	if args.is_empty():
		return
	var d = JSON.parse_string(String(args[0]))
	if not d is Dictionary:
		return
	match String(d.get("ev", "")):
		"list":
			games = d.get("games", [])
			pick = String(d.get("pick", pick))
			if _md:
				_btn_folder.visible = bool(_md.canFolder())
			_draw_list()
		"note":
			note(String(d.get("text", "")))
		"playing":
			emu_mode = "play"
			playing_name = String(d.get("name", ""))
			_playing_pic = null
			for g in games:
				if int(g.id) == int(d.get("id", -1)):
					_playing_pic = picture(String(g.pic))
		"pic":
			_playing_pic = picture(String(d.get("pic", "")))
			_offer_to_friend(true)
		"started":
			_offer_to_friend(true)
		"stopped":
			if friend_send.is_valid():
				friend_send.call({"t": "md", "on": 0})
		"library":
			emu_mode = ""
			note("")
			if _md:
				_md.list()
			_btn_bricks.grab_focus.call_deferred()
		"close":
			emu_mode = ""
			_open = false
			_panel.visible = false
			if arcade and not arcade.overlay.is_open():
				arcade.hold_player(false)
			closed.emit()
		"pad":
			if friend_send.is_valid():
				friend_send.call({"t": "mdpad", "b": int(d.get("bits", 0))})
		"watching":
			emu_mode = "watch"
		"watch_end":
			if bool(d.get("tell", false)) and friend_send.is_valid():
				friend_send.call({"t": "mdleave"})
			if emu_mode == "watch":
				emu_mode = ""
				if not _open and arcade and not arcade.overlay.is_open():
					arcade.hold_player(false)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_last_pointer_click = true
	elif event is InputEventKey or event is InputEventJoypadButton:
		_last_pointer_click = false
	if not _open or not _panel.visible:
		return
	if _confirm.visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		close()
		get_viewport().set_input_as_handled()
		return
	# the room's keys stay out of it while the menu's up (the menu's own arrows, Enter and Tab still work)
	if event is InputEventKey and not (event.is_action("ui_up") or event.is_action("ui_down") or event.is_action("ui_left")
			or event.is_action("ui_right") or event.is_action("ui_accept") or event.is_action("ui_focus_next") or event.is_action("ui_focus_prev")):
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- the friend (milestone 4 hooks)
#
# The game's connection (milestone 4, another session) wires these up:
#   arcade.md.friend_send = func(msg: Dictionary): <send msg to the other player>
#   arcade.md.friend_name = "Juicy Jared"            (what the friend's told: "<who> is playing ...")
#   on a message from the other player:  if arcade.md.on_friend_message(msg): return   (it was ours)
#   when the connection drops:           arcade.md.friend_gone()
# The messages are the HTML game's: {t:'md', on:1, name, who, sys, pic} (I'm playing this; on:0 stopped),
# {t:'mdjoin'} (the friend joins), {t:'mdleave'}, {t:'mdpad', b} (the friend's buttons, 12 bits).
# The picture and sound go as a WebRTC media call, which has to be made in the page's JavaScript: on mdjoin
# the host's page runs SmashedMD.streamTo(peer, friendPeerId) with its PeerJS peer; the friend's page passes
# the incoming call to SmashedMD.answerCall(call). If milestone 4 isn't PeerJS, SmashedMD.watch(mediaStream)
# shows any MediaStream and SmashedMD.offer() / the emulator canvas give the host's side to send.

var friend_send: Callable = Callable()
var friend_name: String = "Your friend"
## What the friend's offered to play (mdOnData's MD.offer): {name, who, sys, pic}, or null.
var offer = null
var _dismissed := ""
var _offer_at := 0.0

func _process(delta: float) -> void:
	_send_pick_rects()
	_offer_at += delta
	if _offer_at > 3.0 and emu_mode == "play":
		_offer_to_friend(false)                     # keep saying so, for a friend who connects after

func _offer_to_friend(force: bool) -> void:
	if not friend_send.is_valid() or not _md:
		return
	if not force and _offer_at < 3.0:
		return
	_offer_at = 0.0
	var o = JSON.parse_string(String(_md.offer()))
	if not o is Dictionary:
		return
	var msg := {"t": "md", "on": 1, "name": String(o.name), "who": friend_name, "sys": String(o.sys)}
	if String(o.get("pic", "")) != "":
		msg["pic"] = o.pic
	friend_send.call(msg)

## A message from the other player. True if it was the Mega Drive's.
func on_friend_message(d: Dictionary) -> bool:
	match String(d.get("t", "")):
		"md":
			if int(d.get("on", 0)):
				var o := {"name": String(d.get("name", "a game")).left(60), "who": String(d.get("who", "Your friend")).left(30),
					"sys": String(d.get("sys", "md")) if SYS.has(String(d.get("sys", ""))) else "md"}
				var fresh: bool = offer == null or offer.name != o.name
				var pic = d.get("pic")
				if pic is String and pic.begins_with("data:image/jpeg;base64,") and pic.length() < 60000:
					o["pic"] = pic
				elif not fresh and offer.has("pic"):
					o["pic"] = offer.pic
				offer = o
				if fresh and _dismissed != o.name and emu_mode == "":
					_ask_text.text = o.who + " is playing " + o.name + " on the " + String(SYS[o.sys].label) + "."
					_ask.visible = true
			else:
				offer = null
				_dismissed = ""
				_ask.visible = false
				if emu_mode == "watch" and _md:
					_md.stopWatching(false)
			return true
		"mdjoin":
			# the friend wants in: the page sends them the picture (SmashedMD.streamTo, wired by milestone 4)
			friend_joined.emit()
			return true
		"mdleave":
			if _md:
				_md.endStream()
			return true
		"mdpad":
			if _md:
				_md.applyPad(int(d.get("b", 0)) & 4095)
			return true
	return false

## The friend asked to join (the page should now call SmashedMD.streamTo with its PeerJS peer).
signal friend_joined

## Join the friend's game as player 2 (mdJoin).
func join() -> void:
	_ask.visible = false
	if offer == null or not friend_send.is_valid():
		return
	if _md:
		_md.join(String(offer.name), String(offer.sys))
	emu_mode = "watch"
	if arcade:
		arcade.hold_player(true)
	friend_send.call({"t": "mdjoin"})

## The connection dropped (mdConnGone).
func friend_gone() -> void:
	offer = null
	_ask.visible = false
	if _md:
		_md.endStream()
		if emu_mode == "watch":
			_md.stopWatching(false)

# ---------------------------------------------------------------- Google Drive (later)

## "Connect Google Drive": a games folder shared with your friend by Gmail (PLAN.md, milestone 5). Needs the
## owner's OAuth client ID (DRIVE_CLIENT_ID); the browser side is SmashedMD.driveConnect.
func drive_connect() -> void:
	if DRIVE_CLIENT_ID == "":
		note("Google Drive games folder: coming. It needs the owner's Google sign-in set up first (an OAuth client ID).")
		return
	if _md:
		_md.driveConnect(DRIVE_CLIENT_ID)
