class_name VoxelTouch
extends CanvasLayer
## Touch controls for the block game in a phone's browser (the owner, 24 Nov: "could the website one detect if you're on
## phone then use phone controls?"). On when the page is on a touch screen with no mouse (detect(): ?touch / --touch
## forces it, ?notouch never), or at the first real touch. Landscape first:
##   left half: a stick where the thumb lands (move; pushed to its edge: run)
##   right half: drag to look (top-down: the way you aim, as a second stick)
##   bottom right: FIRE (hold; a drag from it looks too), AIM (the right mouse button), E (use), R (reload), JUMP,
##     < > (the weapon before / after); a tap on a slot of the weapon bar takes that one out
##   top right: ... shows or hides PHONE, BAG, VIEW, HELP, SET, ONLINE
##   a menu open: taps are clicks (the first finger is the mouse), X closes it
##   driving Demolition's crane: the cluster goes and the crane's own buttons take its place (BOOM < >, CABLE ^ v,
##     OUT), the left stick drives the tracks and turns it; out of the cab they go back
## The game is fed through one shim: buttons send the same InputEventKey / InputEventMouseButton the keyboard and mouse
## would (Input.parse_input_event), the stick sets `move` (VoxelArena reads it in place of WASD), a look drag calls
## VoxelArena.look_by (what the mouse's motion calls). No pointer lock: grab() / grabbed() stand in for
## Input.mouse_mode, pointer() for the mouse's place (top-down aiming). Nothing made each frame. Owned by the
## voxel-web-touch session.

enum {B_FIRE, B_AIM, B_USE, B_RELOAD, B_PREV, B_NEXT, B_JUMP, B_MORE, B_PHONE, B_BAG, B_VIEW, B_HELP, B_SET, B_ONLINE,
	B_LANE_PREV, B_LANE_NEXT, B_CLOSE, B_TAKE_OFF, B_N1, B_N2, B_N3, B_N4,
	B_BOOM_L, B_BOOM_R, B_CABLE_UP, B_CABLE_DOWN, B_CRANE_OUT, B_COUNT}
enum {K_KEY, K_MOUSE, K_WHEEL, K_MORE}
enum {F_NONE, F_STICK, F_LOOK, F_BUTTON, F_SLOT, F_UI}
## each button: [label, kind, key or mouse button, half its size (x, y) at scale 1, round]
const DEFS := [
	["FIRE", K_MOUSE, MOUSE_BUTTON_LEFT, Vector2(70, 70), true],
	["AIM", K_MOUSE, MOUSE_BUTTON_RIGHT, Vector2(46, 46), true],
	["E", K_KEY, KEY_E, Vector2(46, 46), true],
	["R", K_KEY, KEY_R, Vector2(40, 40), true],
	["<", K_WHEEL, MOUSE_BUTTON_WHEEL_UP, Vector2(36, 36), true],
	[">", K_WHEEL, MOUSE_BUTTON_WHEEL_DOWN, Vector2(36, 36), true],
	["JUMP", K_KEY, KEY_SPACE, Vector2(46, 46), true],
	["...", K_MORE, 0, Vector2(38, 38), false],
	["PHONE", K_KEY, KEY_P, Vector2(59, 38), false],
	["BAG", K_KEY, KEY_TAB, Vector2(59, 38), false],
	["VIEW", K_KEY, KEY_V, Vector2(59, 38), false],
	["HELP", K_KEY, KEY_SLASH, Vector2(59, 38), false],
	["SET", K_KEY, KEY_F10, Vector2(59, 38), false],
	["ONLINE", K_KEY, KEY_O, Vector2(59, 38), false],
	["LANE <", K_KEY, KEY_BRACKETLEFT, Vector2(59, 38), false],
	["LANE >", K_KEY, KEY_BRACKETRIGHT, Vector2(59, 38), false],
	["X", K_KEY, KEY_ESCAPE, Vector2(46, 46), false],
	["TAKE OFF", K_KEY, KEY_R, Vector2(70, 38), false],
	["1", K_KEY, KEY_1, Vector2(44, 44), false],
	["2", K_KEY, KEY_2, Vector2(44, 44), false],
	["3", K_KEY, KEY_3, Vector2(44, 44), false],
	["4", K_KEY, KEY_4, Vector2(44, 44), false],
	["BOOM <", K_KEY, KEY_LEFT, Vector2(58, 42), false],
	["BOOM >", K_KEY, KEY_RIGHT, Vector2(58, 42), false],
	["CABLE ^", K_KEY, KEY_UP, Vector2(54, 42), false],
	["CABLE v", K_KEY, KEY_DOWN, Vector2(54, 42), false],
	["OUT", K_KEY, KEY_E, Vector2(48, 48), true],
]
const CLUSTER := [B_FIRE, B_AIM, B_USE, B_RELOAD, B_PREV, B_NEXT, B_JUMP]
## Driving Demolition's crane: the boom round, the cable in and out, and out of the cab. The left stick drives it (its
## W A S D are the tracks and the turn) and a drag on the right still looks about, so these are what's left. Two rows
## in the bottom right corner where the weapons' cluster was, filled right to left under the right thumb; a phone held
## upright that hasn't the width for a row shrinks them to fit it rather than push one off the screen.
const CRANE_ROWS := [[B_CABLE_DOWN, B_BOOM_R, B_BOOM_L], [B_CABLE_UP, B_CRANE_OUT]]
const CRANE_Y := [-58.0, -152.0]        # each row, above the weapon bar, at scale 1
## (where each of the cluster is from the screen's bottom right corner, above the weapon bar, at scale 1)
const CLUSTER_AT := [Vector2(-118, -130), Vector2(-262, -55), Vector2(-380, -55), Vector2(-262, -160), Vector2(-265, -255),
	Vector2(-180, -255), Vector2(-70, -280)]
const SECOND := [B_PHONE, B_BAG, B_VIEW, B_HELP, B_SET, B_ONLINE, B_LANE_PREV, B_LANE_NEXT]
const BAR_H := 130.0            # the weapon bar's strip along the bottom (the cluster sits above it)
const STICK_R := 92.0           # the stick's reach (at scale 1)
const DEAD := 0.14              # of its reach: nothing
const RUN_AT := 0.94            # pushed this far: running (Shift)
const KEY_AT := 0.4             # past this an axis is its key as well (W A S D: the rides, getting out of bed)
const LOOK_K := 1.5             # a look drag's pixels, as the mouse's (a swipe across half the screen: about 170 degrees)
const LOOK_CAP := 90.0          # the most one drag event turns (pixels): a new finger, a dropped frame never jerk the view
const AIM_REACH := 240.0        # top-down: how far from Jared the aim point sits (pixels)
const SLOT_SLIP := 26.0         # a touch on the weapon bar that moves this far isn't a tap: it's the stick, or a look
const UI_SLIP := 22.0           # a menu's tap that moves this far (a scroll) doesn't click when let go
const FINGERS := 10

static var active := false      # touch mode on (there's a layer)
static var allowed := true      # (?notouch: never, not even at a touch)
static var forced := false      # (?touch)
static var _aim_px := Vector2.ZERO
static var _aim_on := false

var arena: VoxelArena
var move := Vector2.ZERO        # the stick: x right, y back (as WASD's), length 0..1
var stick_on := false           # a thumb's on it
var more := true                # the second row shown
var k := 1.0                    # the buttons' scale (a phone held upright: bigger, the screen's stretch is smaller)
var _pad: Control
var _base: Control
var _knob: Control
var _font: Font
var _at := PackedVector2Array()         # each button's middle
var _half := PackedVector2Array()       # half its size
var _show := PackedByteArray()          # 1: there now
var _held := PackedInt32Array()         # the finger on it (-1: none)
var _role := PackedInt32Array()         # each finger's: F_*
var _fbtn := PackedInt32Array()         # the button (or the bar's slot) it's on
var _from := PackedVector2Array()       # where it came down
var _slip := PackedFloat32Array()       # how far it's strayed from there at most
var _stick_from := Vector2.ZERO
var _keys := [false, false, false, false, false]    # W A S D Shift down by the stick
var _ui := false
var _prompt := ""               # the game's "E  ..." line as last drawn
var _use_cap := ""              # what E does now ("" nothing)
var _size := Vector2.ZERO
var _xf := Transform2D.IDENTITY # the screen's stretch: this layer's pixels -> the window's (what Input.parse_input_event takes)
var _aim_dir := Vector2(0, -1)
var _sb := StyleBoxFlat.new()
var _sb_down := StyleBoxFlat.new()
var _ui_finger := -1
var _nums := 0
var _lanes := false
var _lock := false
var _top := false
var _crane := false             # in Demolition's crane: the crane's buttons in the cluster's place

## Touch mode for this game? opts: the game's options (--touch, the page's ?touch / ?notouch). On the web: a touch screen
## with no mouse or trackpad (a coarse pointer).
static func detect(opts: Dictionary) -> bool:
	allowed = not opts.has("notouch")
	forced = opts.has("touch") and allowed
	active = forced
	_aim_on = false
	if allowed and not active and OS.has_feature("web"):
		var r = JavaScriptBridge.eval("((navigator.maxTouchPoints>0 && matchMedia('(pointer:coarse)').matches)?1:0)", true)
		active = r != null and str(r).to_float() == 1.0     # (a number: what comes back for a JS true isn't always a bool)
	print("VoxelTouch: ", "on" if active else "off", " (forced)" if forced else "")
	return active

## The mouse grabbed (first person, playing)? Touch mode: always (there's no pointer to lock; the menus say when they're up).
static func grabbed() -> bool:
	return active or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

## Input.mouse_mode = captured / visible; touch mode: nothing (no pointer lock asked of a phone's browser).
static func grab(on: bool) -> void:
	if not active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

## Where the pointer is on screen (top-down aiming): the mouse, or in touch mode the aim point the right thumb set.
static func pointer(vp: Viewport) -> Vector2:
	return _aim_px if (active and _aim_on) else vp.get_mouse_position()

func setup(a: VoxelArena) -> void:
	arena = a
	layer = 40                      # (over the menus, layer 31: X stays on top)
	active = true
	Input.emulate_mouse_from_touch = false      # (a thumb on the stick isn't a click: this layer says what each touch is)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_font = ThemeDB.fallback_font
	_at.resize(B_COUNT)
	_half.resize(B_COUNT)
	_show.resize(B_COUNT)
	_held.resize(B_COUNT)
	_held.fill(-1)
	_role.resize(FINGERS)
	_fbtn.resize(FINGERS)
	_from.resize(FINGERS)
	_slip.resize(FINGERS)
	for sb in [_sb, _sb_down]:
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.55)
	_sb.bg_color = Color(0.03, 0.04, 0.07, 0.5)
	_sb_down.bg_color = Color(1, 1, 1, 0.4)
	_pad = Control.new()
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	_base = Control.new()
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.draw.connect(_draw_base)
	add_child(_base)
	_knob = Control.new()
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob.draw.connect(_draw_knob)
	add_child(_knob)
	# the keyboard's line along the bottom and the mouse's small buttons: not on a phone (this layer has their buttons)
	arena.help.visible = false
	for m in [arena.settings_menu, arena.guide, arena.net_menu]:
		if m and m.get("_btn"):
			m._btn.visible = false
	if arena.settings_menu:
		arena.settings_menu.touch_layout()
	if arena.net_menu and arena.net_menu.has_method("touch_layout"):
		arena.net_menu.touch_layout()
	_layout()
	# (turned on at a touch: that touch was a mouse's click a moment ago, the engine's own stand-in; it's let go)
	_mouse_btn(MOUSE_BUTTON_LEFT, false, Vector2(-200, -200))

func _exit_tree() -> void:
	_let_go_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if arena:
			_let_go_all()               # (the tab left mid-press: nothing stays held)

# ---------------------------------------------------------------- where everything is

## The buttons' scale: about the same size under a thumb however the page is stretched (a phone on its side: 1).
func _scale_for(vs: Vector2) -> float:
	var win := Vector2(get_window().size) if is_inside_tree() else Vector2.ZERO
	if win.y < 8.0 or vs.y < 8.0 or DisplayServer.get_name() == "headless":
		return 1.0
	var css := win.y / maxf(1.0, DisplayServer.screen_get_scale()) / vs.y      # the page's pixels a pixel of ours
	return clampf(0.54 / maxf(css, 0.05), 0.75, 1.7)

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	_size = vs
	_xf = get_viewport().get_final_transform() if is_inside_tree() else Transform2D.IDENTITY
	k = _scale_for(vs)
	for b in B_COUNT:
		_half[b] = (DEFS[b][3] as Vector2) * k
		_show[b] = 0
	var ui := _ui
	var corner := Vector2(vs.x, vs.y - BAR_H)
	for j in CLUSTER.size():
		var b: int = CLUSTER[j]
		_at[b] = corner + (CLUSTER_AT[j] as Vector2) * k
		_show[b] = 0 if (ui or _crane) else 1
	# in the crane's cab: the weapons' cluster is gone (no weapon works from in there) and the crane's own is up
	var ck := k
	for row in CRANE_ROWS:
		var need := 34.0
		for b2: int in row:
			need += (DEFS[b2][3] as Vector2).x * 2.0 + 10.0
		ck = minf(ck, vs.x / maxf(need, 1.0))
	for r in CRANE_ROWS.size():
		var cx := vs.x - 14.0 * ck
		var cy: float = corner.y + CRANE_Y[r] * ck
		for b3: int in CRANE_ROWS[r]:
			_half[b3] = (DEFS[b3][3] as Vector2) * ck
			_at[b3] = Vector2(cx - _half[b3].x, clampf(cy, _half[b3].y + 6.0, vs.y - _half[b3].y - 6.0))
			_show[b3] = 1 if (_crane and not ui) else 0
			cx -= _half[b3].x * 2.0 + 10.0 * ck
	# top right: X (a menu up), or ... and its row (wrapped where it runs out of room: a phone held upright)
	var m := 16.0 * k
	_at[B_CLOSE] = Vector2(vs.x - m - _half[B_CLOSE].x, m + _half[B_CLOSE].y)
	if ui and arena.phone.is_open() and vs.x > VoxelPhone.W + 80.0 + _half[B_CLOSE].x * 2.0 + m * 2.0:
		_at[B_CLOSE].x = vs.x - VoxelPhone.W - 40.0 - m - _half[B_CLOSE].x      # (the phone's in that corner: beside it)
	_show[B_CLOSE] = 1 if ui else 0
	_at[B_TAKE_OFF] = Vector2(vs.x - m - _half[B_TAKE_OFF].x, _at[B_CLOSE].y + _half[B_CLOSE].y + m + _half[B_TAKE_OFF].y)
	_show[B_TAKE_OFF] = 1 if (ui and _lock) else 0
	_at[B_MORE] = Vector2(vs.x - m - _half[B_MORE].x, m + _half[B_MORE].y)
	_show[B_MORE] = 0 if ui else 1
	var x := _at[B_MORE].x - _half[B_MORE].x - 8.0 * k
	var y := _at[B_MORE].y
	var left_most := vs.x * 0.42 if vs.x > vs.y else m
	for b in SECOND:
		var on: bool = more and not ui and (_lanes or (b != B_LANE_PREV and b != B_LANE_NEXT))
		if not on:
			continue
		if x - _half[b].x * 2.0 < left_most:
			x = vs.x - m
			y += _half[b].y * 2.0 + 8.0 * k
		_at[b] = Vector2(x - _half[b].x, y)
		_show[b] = 1
		x -= _half[b].x * 2.0 + 8.0 * k
	# a numbered list on screen (the Carousel's gadget): its numbers, in a row over the weapon bar
	for n in 4:
		var b2: int = B_N1 + n
		_at[b2] = Vector2(vs.x * 0.5 + (n - 1.5) * 104.0 * k, vs.y - BAR_H - 60.0 * k)
		_show[b2] = 1 if (not ui and n < _nums) else 0
	_rest_stick()
	_pad.queue_redraw()
	_base.queue_redraw()
	_knob.queue_redraw()

func _rest_stick() -> void:
	# (nobody on it: where a left thumb would find it, faint)
	_stick_from = Vector2(190.0 * k, _size.y - BAR_H - 150.0 * k)
	_base.position = _stick_from
	_knob.position = _stick_from
	_base.modulate.a = 0.35
	_knob.modulate.a = 0.35
	_base.visible = not _ui
	_knob.visible = not _ui

## The button under a point (-1: none). A little bigger than drawn: a thumb's not a mouse.
func button_at(p: Vector2) -> int:
	var pad := 8.0 * k
	for b in B_COUNT:
		if _show[b] == 0:
			continue
		var d := p - _at[b]
		var h := _half[b]
		if DEFS[b][4]:
			if d.length_squared() <= (h.x + pad) * (h.x + pad):
				return b
		elif absf(d.x) <= h.x + pad * 0.5 and absf(d.y) <= h.y + pad * 0.5:
			return b
	return -1

## A button's middle on screen (the tests; where to tap).
func button_pos(b: int) -> Vector2:
	return _at[b]

func button_shown(b: int) -> bool:
	return _show[b] == 1

# ---------------------------------------------------------------- the touches

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.index < 0 or t.index >= FINGERS:
			return
		if t.pressed:
			_down(t.index, t.position)
		else:
			_up(t.index, t.position)
		if _role[t.index] != F_UI and not _ui:
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index < 0 or d.index >= FINGERS:
			return
		_drag(d.index, d.position, d.relative)
		if _role[d.index] != F_UI and not _ui:
			get_viewport().set_input_as_handled()

func _down(i: int, p: Vector2) -> void:
	if _role[i] != F_NONE:
		_up(i, p)                   # (a finger the browser never said was lifted)
	_from[i] = p
	_slip[i] = 0.0
	var b := button_at(p)
	if b >= 0:
		_role[i] = F_BUTTON
		_fbtn[i] = b
		_press(b, i)
		return
	if _ui:
		if _ui_finger < 0:          # a menu: the first finger is the mouse
			_ui_finger = i
			_role[i] = F_UI
			_mouse_move(p, Vector2.ZERO, false)
			_mouse_btn(MOUSE_BUTTON_LEFT, true, p)
		return
	var s := _slot_at(p)
	if s >= 0:
		_role[i] = F_SLOT
		_fbtn[i] = s
	elif p.x < _size.x * 0.5 and not stick_on:
		_stick_start(i, p)
	else:
		_role[i] = F_LOOK

func _up(i: int, p: Vector2) -> void:
	match _role[i]:
		F_BUTTON:
			_release(_fbtn[i])
		F_STICK:
			_stick_end()
		F_SLOT:
			var s := _fbtn[i]
			if s != arena.loadout.current:
				arena._switch(func(): arena.loadout.select(s))
		F_UI:
			_ui_finger = -1
			# (a scroll's drag let go over a button isn't a click on it: the mouse comes up off the screen)
			_mouse_btn(MOUSE_BUTTON_LEFT, false, p if _slip[i] < UI_SLIP * k else Vector2(-200, -200))
	_role[i] = F_NONE

func _drag(i: int, p: Vector2, rel: Vector2) -> void:
	_slip[i] = maxf(_slip[i], p.distance_to(_from[i]))
	match _role[i]:
		F_STICK:
			_stick_to(p)
		F_LOOK:
			_look(i, p, rel)
		F_BUTTON:
			if _fbtn[i] == B_FIRE or _fbtn[i] == B_AIM:
				_look(i, p, rel)    # (aim while you fire: a drag that began on FIRE turns the view as well)
		F_SLOT:
			if _slip[i] > SLOT_SLIP * k:
				if _from[i].x < _size.x * 0.5 and not stick_on:
					_stick_start(i, _from[i])
					_stick_to(p)
				else:
					_role[i] = F_LOOK
		F_UI:
			_mouse_move(p, rel, true)

func _look(i: int, p: Vector2, rel: Vector2) -> void:
	if _ui:
		return
	if arena.top_down:
		var d := p - _from[i]       # top-down: the drag is a second stick, Jared aims the way it's pushed
		if d.length_squared() > 144.0:
			_aim_dir = d.normalized()
		return
	rel.x = clampf(rel.x, -LOOK_CAP, LOOK_CAP)
	rel.y = clampf(rel.y, -LOOK_CAP, LOOK_CAP)
	arena.look_by(rel * LOOK_K)

func _stick_start(i: int, p: Vector2) -> void:
	var r := STICK_R * k
	_role[i] = F_STICK
	stick_on = true
	_stick_from = Vector2(clampf(p.x, r * 0.7, _size.x - r * 0.7), clampf(p.y, r * 0.7, _size.y - r * 0.7))
	_base.position = _stick_from
	_knob.position = _stick_from
	_base.modulate.a = 1.0
	_knob.modulate.a = 1.0
	move = Vector2.ZERO

func _stick_to(p: Vector2) -> void:
	var r := STICK_R * k
	var v := (p - _stick_from) / r
	var l := v.length()
	if l > 1.0:
		v /= l
		l = 1.0
	_knob.position = _stick_from + v * r
	move = Vector2.ZERO if l < DEAD else v * ((l - DEAD) / (1.0 - DEAD) / l)
	_stick_keys(v.y < -KEY_AT, v.x < -KEY_AT, v.y > KEY_AT, v.x > KEY_AT, l >= RUN_AT)

func _stick_end() -> void:
	stick_on = false
	move = Vector2.ZERO
	_stick_keys(false, false, false, false, false)
	_rest_stick()

func _stick_keys(w: bool, a: bool, s: bool, d: bool, run: bool) -> void:
	_stick_key(0, KEY_W, w)
	_stick_key(1, KEY_A, a)
	_stick_key(2, KEY_S, s)
	_stick_key(3, KEY_D, d)
	_stick_key(4, KEY_SHIFT, run)

func _stick_key(j: int, key: Key, on: bool) -> void:
	if _keys[j] != on:
		_keys[j] = on
		_key(key, on)

func _press(b: int, finger: int) -> void:
	if _held[b] >= 0:
		return
	_held[b] = finger
	match int(DEFS[b][1]):
		K_KEY:
			_key(DEFS[b][2], true)
		K_MOUSE:
			_mouse_btn(DEFS[b][2], true, _size * 0.5)
		K_WHEEL:
			_mouse_btn(DEFS[b][2], true, _size * 0.5)
			_mouse_btn(DEFS[b][2], false, _size * 0.5)
		K_MORE:
			more = not more
			_layout()
	_pad.queue_redraw()

func _release(b: int) -> void:
	if _held[b] < 0:
		return
	_held[b] = -1
	match int(DEFS[b][1]):
		K_KEY:
			_key(DEFS[b][2], false)
		K_MOUSE:
			_mouse_btn(DEFS[b][2], false, _size * 0.5)
	_pad.queue_redraw()

## Everything held let go (a menu's come up, the tab's left).
func _let_go_all() -> void:
	for b in B_COUNT:
		_release(b)
	if stick_on:
		_stick_end()
	if _ui_finger >= 0:
		_mouse_btn(MOUSE_BUTTON_LEFT, false, Vector2(-200, -200))
		_ui_finger = -1
	_role.fill(F_NONE)

# ---------------------------------------------------------------- the shim: what the keyboard and mouse would send

func _key(key: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key        # (the game reads physical keys; no keycode: Tab isn't the menus' "next")
	e.pressed = down
	Input.parse_input_event(e)

func _mouse_btn(btn: MouseButton, down: bool, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	e.position = _xf * at
	e.global_position = e.position
	if down and btn == MOUSE_BUTTON_LEFT:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	elif down and btn == MOUSE_BUTTON_RIGHT:
		e.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(e)

func _mouse_move(at: Vector2, rel: Vector2, held: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _xf * at
	e.global_position = e.position
	e.relative = _xf.basis_xform(rel)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(e)

func _slot_at(p: Vector2) -> int:
	var bar: VoxelWeaponBar = arena.bar
	if bar == null or not bar.is_visible_in_tree():
		return -1
	return bar.slot_at(p - bar.global_position)

# ---------------------------------------------------------------- each frame

func _ui_open() -> bool:
	return arena.inv_ui.is_open() or arena.lock_view.is_open() or arena.phone.is_open() or arena.settings_menu.is_open() \
			or arena.guide.is_open() or (arena.net_menu != null and arena.net_menu.is_open())

func _process(_dt: float) -> void:
	var redo := false
	var ui := _ui_open()
	if ui != _ui:
		_let_go_all()
		_ui = ui
		redo = true
		if ui and arena.inv_ui.is_open():
			_fit_inventory()
	var lock: bool = arena.lock_view.is_open()
	var hack = arena.stkilda.hack if arena.stkilda else null
	var nums := 4 if (hack and hack._open) else 0
	var lanes: bool = arena.gun_range != null and arena.gun_range.active
	var crane: bool = arena.demolition != null and arena.demolition.driving()
	if lock != _lock or nums != _nums or lanes != _lanes or crane != _crane or get_viewport().get_visible_rect().size != _size:
		_lock = lock
		_nums = nums
		_lanes = lanes
		if crane != _crane:
			_let_go_all()               # (in or out of the cab: nothing stays held, no key left down)
			_crane = crane
		redo = true
	if redo:
		_layout()
	# what E does now: the game's own line ("E  ride the Scenic Railway"), under the button
	var line: String = arena._use_label.text
	if line != _prompt:
		_prompt = line
		_use_cap = _caption(line)
		_pad.queue_redraw()
	if arena.top_down != _top:
		_top = arena.top_down
		_pad.queue_redraw()
	_aim_on = arena.top_down
	if _aim_on:
		_aim_px = arena.cam.unproject_position(arena.player.global_position + Vector3(0, 1.2, 0)) + _aim_dir * AIM_REACH

static func _caption(line: String) -> String:
	var l := line.get_slice("\n", 0).strip_edges()
	if l.begins_with("Hold E"):
		return "hold: " + l.substr(6).strip_edges()
	if l.begins_with("E ") or l.begins_with("E,"):
		return l.substr(2).strip_edges()
	return ""

## The backpack's screen as big as fits (its slots are a mouse's size).
func _fit_inventory() -> void:
	var ui: VoxelInventoryUI = arena.inv_ui
	var h := 90.0
	var w := 100.0
	for p in ui._panels:
		h += (p.rect as Rect2).size.y + 14.0
		w = maxf(w, (p.rect as Rect2).size.x + 40.0)
	var s := clampf(minf(_size.y / h, (_size.x - 220.0 * k) / w), 1.0, 1.5)
	ui.pivot_offset = ui.size * 0.5
	ui.scale = Vector2(s, s)

# ---------------------------------------------------------------- drawing (only when something changes)

func _draw_pad() -> void:
	for b in B_COUNT:
		if _show[b] == 0:
			continue
		var c := _at[b]
		var h := _half[b]
		var down := _held[b] >= 0
		var label := String(DEFS[b][0])
		var kb := h.x / maxf((DEFS[b][3] as Vector2).x, 1.0)      # (this button's own scale: the crane's row shrinks to fit)
		var fs := int((26.0 if b == B_FIRE else 20.0) * kb)
		if DEFS[b][4]:
			var hot := b == B_USE and _use_cap != ""
			_pad.draw_circle(c, h.x, Color(1, 1, 1, 0.4) if down else (Color(0.9, 0.7, 0.1, 0.45) if hot else Color(0.03, 0.04, 0.07, 0.45)))
			_pad.draw_arc(c, h.x, 0.0, TAU, 40, Color(1, 0.85, 0.3, 0.95) if hot else Color(1, 1, 1, 0.6), 2.5 * k, true)
			if b == B_FIRE and arena.top_down:
				label = "FIRE"
		else:
			_pad.draw_style_box(_sb_down if down else _sb, Rect2(c - h, h * 2.0))
			if label.length() > 5:
				fs = int(17.0 * kb)
		_text(c, label, fs, Color.WHITE)
		if b == B_USE and _use_cap != "":
			_text(c + Vector2(0, -h.y - 14.0 * k), _use_cap, int(17.0 * k), Color(1, 0.9, 0.5))

func _text(mid: Vector2, t: String, fs: int, col: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(mid.x - w * 0.5, mid.y + fs * 0.36)
	if at.x + w > _size.x - 6.0:
		at.x = _size.x - 6.0 - w        # (a long line by the screen's edge: kept on it)
	_pad.draw_string_outline(_font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, int(4.0 * k)), Color(0, 0, 0, 0.8))
	_pad.draw_string(_font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw_base() -> void:
	var r := STICK_R * k
	_base.draw_circle(Vector2.ZERO, r, Color(0.03, 0.04, 0.07, 0.35))
	_base.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 2.5 * k, true)

func _draw_knob() -> void:
	_knob.draw_circle(Vector2.ZERO, STICK_R * k * 0.42, Color(1, 1, 1, 0.5))
