class_name ArcadeOverlay
extends CanvasLayer
## A cabinet's game filling your screen (Smashed.html, drawArcade): the room dimmed, the cabinet round the
## 480 x 320 screen in its colours, its title on the lit marquee, SCORE and HI on the screen, scanlines, PUSH TO
## START / GAME OVER / PUSH TO PLAY AGAIN, the controls under it, and the round X at its top right. You stand
## still while you play. E, Esc, the pad's B or the X walks away. The whole cabinet is blown up to fill the
## window (with room either side for the on-screen buttons on a touch screen).
##
## Each game gets its own controls per device (decided with the owner): the keyboard and mouse, a pad
## (left stick or d-pad, A; Sand Miner: right stick aims, RT digs, LT / RB launches, X ammo, Y upgrade), and
## touch (Snake: swipe; Bricks: drag the paddle, tap to launch; Sand Miner: on-screen walk, jump, launch,
## ammo and upgrade buttons, and your finger on the screen is the shovel).

signal opened(game_id: String)
signal closed

const STAGE := Vector2(560, 432)
const SCR := Rect2(40, 70, 480, 320)
const CLOSE_R := 15.0

var arcade: Arcade
var cab: Dictionary = {}
var game_id: String = ""
var game: ArcadeGame
## The last thing used: "keys" (keyboard or mouse), "pad" or "touch". Picks the hint and the on-screen buttons.
var device: String = "keys"

var _root: Control
var _stage: _Stage
var _screen: _Screen
var _buttons: _TouchButtons
var _t_open := 0.0
var _now := 0.0
# the pointer on the screen (480 x 320 units)
var _ptr = null
var _ptr_in := false
var _ptr_down := false
var _ptr_alt := false
var _ptr_touch := false
var _ptr_touch_id := -1
var _drag_from := Vector2.ZERO
var _drag := Vector2.ZERO
var _swipe := Vector2.ZERO          # a swipe seen since the last frame (a quick flick can start and end within one)
var _paddle = null                   # Bricks: where the mouse or a finger puts the paddle
var _pressed: Dictionary = {}
var _btn_touch: Dictionary = {}      # touch index -> button id

func _ready() -> void:
	layer = 40
	visible = false
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.draw.connect(func(): _root.draw_rect(Rect2(Vector2.ZERO, _root.size), Color(8 / 255.0, 10 / 255.0, 14 / 255.0, 0.8)))
	add_child(_root)
	_stage = _Stage.new()
	_stage.ov = self
	_stage.size = STAGE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stage)
	_screen = _Screen.new()
	_screen.ov = self
	_screen.position = SCR.position
	_screen.size = SCR.size
	_screen.clip_contents = true
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_screen)
	_buttons = _TouchButtons.new()
	_buttons.ov = self
	_buttons.set_anchors_preset(Control.PRESET_FULL_RECT)
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_buttons)

func is_open() -> bool:
	return game != null

## Play this cabinet's game (arcadeOpenCab). game_name defaults to the cabinet's own.
func open(c: Dictionary, game_name: String = "") -> void:
	cab = c
	game_id = game_name if game_name != "" else String(c.get("game", "snake"))
	game = Arcade.make_game(game_id)
	if game == null:
		return
	game.sfx = arcade.sfx if arcade else null
	_t_open = _now
	_reset_pointer()
	_pressed.clear()
	_btn_touch.clear()
	visible = true
	if arcade:
		arcade.hold_player(true)
	if game.sfx:
		game.sfx.tone(0.12, 440, 880, 0.08, "square")
	_layout()
	opened.emit(game_id)

## Walk away (closeArcade): the score is kept if it's the best.
func close() -> void:
	if game == null:
		return
	_save_hi()
	game = null
	visible = false
	if arcade and not arcade.md.is_open():
		arcade.hold_player(false)
	closed.emit()

func _save_hi() -> void:
	if arcade and game and game.score > 0:
		arcade.save_hi(game_id, game.score)

func hi_score() -> int:
	var h := int(arcade.hi.get(game_id, 0)) if arcade else 0
	return maxi(h, game.score if game else 0)

func _reset_pointer() -> void:
	_ptr = null
	_ptr_in = false
	_ptr_down = false
	_ptr_alt = false
	_ptr_touch = false
	_ptr_touch_id = -1
	_drag = Vector2.ZERO
	_paddle = null

# ---------------------------------------------------------------- layout

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var side := 0.0
	if device == "touch" and game and not game.touch_buttons().is_empty():
		side = _buttons.side_width(vp)
	var k := minf((vp.x - 2.0 * side) / STAGE.x, vp.y / STAGE.y)
	k = maxf(0.2, k)
	_stage.scale = Vector2(k, k)
	_stage.position = ((vp - STAGE * k) / 2.0).floor()

func stage_to_view(p: Vector2) -> Vector2:
	return _stage.position + p * _stage.scale

func _view_to_screen(p: Vector2) -> Vector2:
	return (p - _stage.position) / _stage.scale - SCR.position

func _close_center() -> Vector2:
	return Vector2(SCR.end.x + 6, SCR.position.y - 44)

func _hits_close(view_pos: Vector2) -> bool:
	var c := stage_to_view(_close_center())
	return view_pos.distance_to(c) < (CLOSE_R + 8.0) * _stage.scale.x

# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventKey:
			device = "keys"
		elif event is InputEventJoypadButton or absf(event.axis_value) > 0.5:
			device = "pad"
		if event.is_action_pressed("arcade_close", false, true):
			close()
		elif event.is_action_pressed("arcade_ammo", false, true):
			_pressed["q"] = true
		elif event.is_action_pressed("arcade_upgrade", false, true):
			_pressed["u"] = true
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		_touch(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_touch_drag(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			get_viewport().set_input_as_handled()
			return                                     # a finger, already seen as a touch
		device = "keys"
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _hits_close(event.position):
			close()
			get_viewport().set_input_as_handled()
			return
		_mouse_at(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			_ptr_down = event.pressed
			if event.pressed:
				_pressed["tap"] = true
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_ptr_alt = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if device == "touch" and event.relative.length() < 0.01:
			return
		device = "keys"
		_mouse_at(event.position)
		if _ptr_in:
			_paddle = _ptr.x
		get_viewport().set_input_as_handled()

func _mouse_at(view_pos: Vector2) -> void:
	_ptr_touch = false
	_ptr = _view_to_screen(view_pos)
	_ptr_in = Rect2(Vector2.ZERO, SCR.size).has_point(_ptr)

func _touch(e: InputEventScreenTouch) -> void:
	device = "touch"
	if e.pressed:
		_layout()
		var b := _buttons.hit(e.position)
		if b != "":
			_btn_touch[e.index] = b
			_pressed[b] = true
			return
		if _hits_close(e.position):
			close()
			return
		if _ptr_touch_id < 0:
			_ptr_touch_id = e.index
			_ptr_touch = true
			_ptr = _view_to_screen(e.position)
			_ptr_in = Rect2(Vector2.ZERO, SCR.size).has_point(_ptr)
			_ptr_down = true
			_drag_from = e.position
			_drag = Vector2.ZERO
			_paddle = _ptr.x
			_pressed["tap"] = true
	else:
		_btn_touch.erase(e.index)
		if e.index == _ptr_touch_id:
			_ptr_touch_id = -1
			_ptr_down = false
			_drag = Vector2.ZERO
			_paddle = null

## (tests) how many finger drags and touches have come in
var touch_events := 0

func _touch_drag(e: InputEventScreenDrag) -> void:
	device = "touch"
	touch_events += 1
	if e.index != _ptr_touch_id:
		return
	_ptr = _view_to_screen(e.position)
	_ptr_in = Rect2(Vector2.ZERO, SCR.size).has_point(_ptr)
	_paddle = _ptr.x
	# drag from where the finger lands to steer (30 pixels is all the way), and the start follows a long drag
	# so a swipe the other way turns straight back
	var lim := 30.0 * maxf(1.0, _stage.scale.x)
	var d := e.position - _drag_from
	if d.length() > lim:
		_drag_from = e.position - d.normalized() * lim
		d = e.position - _drag_from
	_drag = Vector2(clampf(d.x / lim, -1, 1), clampf(d.y / lim, -1, 1))
	if _drag.length() > 0.3:
		_swipe = _drag

## The stick for this frame (arcadeStick, plus the pointer and the game's buttons).
func read_stick() -> Dictionary:
	# the arcade's input actions (Arcade.add_actions): keys, the d-pad and the left stick
	var x := Input.get_action_strength("arcade_right") - Input.get_action_strength("arcade_left")
	var y := Input.get_action_strength("arcade_down") - Input.get_action_strength("arcade_up")
	var keyed := absf(x) > 0.01 or absf(y) > 0.01
	var miner := game_id == "miner"
	if not miner and _drag.length() > 0.3:
		x = _drag.x
		y = _drag.y
	elif not miner and _swipe.length() > 0.3:
		x = _swipe.x
		y = _swipe.y
	_swipe = Vector2.ZERO
	var held: Dictionary = {}
	for i in _btn_touch:
		held[_btn_touch[i]] = true
	if held.has("left"): x -= 1.0
	if held.has("right"): x += 1.0
	var fire := Input.is_action_pressed("arcade_fire") or (_ptr_down and not miner)
	if Input.is_action_pressed("arcade_fire"):
		held["jump"] = true                            # Space / A: Sand Miner jumps (W / Space in the HTML game)
	if Input.is_action_pressed("arcade_dig"):
		held["dig"] = true
	if Input.is_action_pressed("arcade_launch"):
		held["launch"] = true
	if held.has("jump_btn"):
		held["jump"] = true
	var aim := Vector2.ZERO                            # the right stick, analogue (Sand Miner aims the shovel)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var rs := Vector2(Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X), Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_Y))
		if rs.length() > 0.25:
			aim = rs
	if keyed and _ptr_touch_id < 0:
		_paddle = null                                 # the keys or a stick took the paddle back
	var st := {"x": clampf(x, -1, 1), "y": clampf(y, -1, 1), "fire": fire or _pressed.has("tap") or held.has("fire_btn"),
		"ptr": _ptr, "ptr_in": _ptr_in, "ptr_down": _ptr_down, "ptr_alt": _ptr_alt, "touch": _ptr_touch,
		"pressed": _pressed.duplicate(), "held": held, "aim": aim, "paddle": _paddle}
	st["go"] = st.fire or Vector2(st.x, st.y).length() > 0.5 or held.has("jump") or held.has("launch") or held.has("dig")
	return st

# ---------------------------------------------------------------- running it

func _process(delta: float) -> void:
	_now += delta
	if game == null:
		return
	_layout()
	var dt := minf(0.05, delta)
	var st := read_stick()
	if _now - _t_open < 0.3:
		st.go = false                                  # the press that opened it doesn't start it
		st.fire = false
	if game.over:
		game.wait -= dt
		if game.wait <= 0.0 and st.go:
			_save_hi()
			var sf := game.sfx
			game = Arcade.make_game(game_id)
			game.sfx = sf
			game.live = true
	else:
		if not game.live and st.go:
			game.live = true
		game.step(dt, st)
		if game.over:
			_save_hi()
	_pressed.clear()
	_root.queue_redraw()
	_stage.queue_redraw()
	_screen.queue_redraw()
	_buttons.queue_redraw()

## Run the game for a while with a scripted stick (tests).
func test_step(dt: float, st: Dictionary) -> void:
	if game == null:
		return
	for k in ["x", "y", "fire", "go"]:
		if not st.has(k):
			st[k] = 0.0 if k in ["x", "y"] else false
	if game.over:
		game.wait -= dt
		if game.wait <= 0.0 and st.go:
			_save_hi()
			game = Arcade.make_game(game_id)
			game.live = true
	else:
		if not game.live and st.go:
			game.live = true
		game.step(dt, st)
		if game.over:
			_save_hi()

# ---------------------------------------------------------------- drawing

static func _mid(ci: CanvasItem, text: String, y: float, size: int, col: Color) -> void:
	var f := ArcadeGame.font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := SCR.size.x / 2.0 - w / 2.0
	ci.draw_string(f, Vector2(x + 2, y + 2 + size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7))
	ci.draw_string(f, Vector2(x, y + size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

## The cabinet round the screen, the title, the hint and the X.
class _Stage extends Control:
	var ov: ArcadeOverlay
	func _draw() -> void:
		if ov.game == null:
			return
		var s := SCR
		var body := Color(String(ov.cab.get("body", "#4f1d44")))
		var trim := Color(String(ov.cab.get("trim", "#ff8ad8")))
		var box := Rect2(s.position.x - 22, s.position.y - 62, s.size.x + 44, s.size.y + 94)
		var sb := StyleBoxFlat.new()
		sb.bg_color = body
		sb.border_color = trim
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		draw_style_box(sb, box)
		draw_rect(Rect2(s.position.x - 8, s.position.y - 54, s.size.x + 16, 40), Color("#0c0c12"))
		var f := ArcadeGame.font()
		var title := ov.game.title()
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(f, Vector2(s.position.x + s.size.x / 2 - tw / 2, s.position.y - 33 + 8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, trim)
		draw_rect(Rect2(s.position.x - 6, s.position.y - 6, s.size.x + 12, s.size.y + 12), Color("#050507"))
		var back := "B to walk away" if ov.device == "pad" else ("X to walk away" if ov.device == "touch" else "E or Esc to walk away")
		var hint := ov.game.hint(ov.device) + "  ·  " + back
		var hw := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(s.position.x + s.size.x / 2 - hw / 2, s.end.y + 22), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#cfd4de"))
		var c := ov._close_center()
		draw_circle(c, CLOSE_R, Color(20 / 255.0, 12 / 255.0, 28 / 255.0, 0.9))
		draw_arc(c, CLOSE_R, 0, TAU, 32, trim, 2.0, true)
		ArcadeGame.cross(self, c, 5.0, trim, 2.0)

## The screen: the game, scanlines, the score and the messages.
class _Screen extends Control:
	var ov: ArcadeOverlay
	func _draw() -> void:
		var g := ov.game
		if g == null:
			return
		var s := Rect2(Vector2.ZERO, SCR.size)
		g.draw(self, s)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var y := 0.0
		while y < s.size.y:
			draw_rect(Rect2(0, y, s.size.x, 1), Color(0, 0, 0, 0.18))
			y += 3.0
		var f := ArcadeGame.font()
		var trim := Color(String(ov.cab.get("trim", "#ff8ad8")))
		draw_string(f, Vector2(8, 19), "SCORE " + str(g.score), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		var hi := "HI " + str(ov.hi_score())
		var hw := f.get_string_size(hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f, Vector2(s.size.x - 8 - hw, 19), hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, trim)
		if g.over:
			ArcadeOverlay._mid(self, "YOU WIN!" if g.won else "GAME OVER", s.size.y / 2 - 12, 30, Color("#7dff9a") if g.won else Color("#e0473f"))
			if g.wait <= 0.0:
				ArcadeOverlay._mid(self, "PUSH TO PLAY AGAIN", s.size.y / 2 + 22, 14, Color.WHITE)
		elif not g.live and int(floor(ov._now / 0.45)) % 2 == 1:
			ArcadeOverlay._mid(self, "PUSH TO START", s.size.y / 2 + 40, 16, Color.WHITE)

## A game's on-screen buttons on a touch screen, down the sides of the window.
class _TouchButtons extends Control:
	var ov: ArcadeOverlay
	func _rad(vp: Vector2) -> float:
		return clampf(minf(vp.x, vp.y) * 0.085, 30.0, 64.0)
	func side_width(vp: Vector2) -> float:
		var cols := 1
		for b in ov.game.touch_buttons():
			cols = maxi(cols, int(b[4]) + 1)
		return cols * _rad(vp) * 2.3 + 12.0
	## [id, label, centre, radius] for each button now.
	func layout() -> Array:
		var out: Array = []
		if ov.game == null or ov.device != "touch":
			return out
		var vp := get_viewport_rect().size
		var r := _rad(vp)
		for b in ov.game.touch_buttons():
			var row: int = b[3]
			var col: int = b[4]
			var cx := 12.0 + r * 1.15 + col * r * 2.3
			if b[2] == "right":
				cx = vp.x - cx
			var cy := vp.y - 16.0 - r * 1.15 - row * r * 2.3
			out.append([b[0], b[1], Vector2(cx, cy), r])
		return out
	func hit(p: Vector2) -> String:
		for b in layout():
			if p.distance_to(b[2]) <= b[3] * 1.1:
				return b[0]
		return ""
	func _draw() -> void:
		var held: Dictionary = {}
		for i in ov._btn_touch:
			held[ov._btn_touch[i]] = true
		var f := ArcadeGame.font()
		var trim := Color(String(ov.cab.get("trim", "#ff8ad8")))
		for b in layout():
			var c: Vector2 = b[2]
			var r: float = b[3]
			draw_circle(c, r, Color(0.08, 0.05, 0.11, 0.55) if not held.has(b[0]) else Color(trim, 0.5))
			draw_arc(c, r - 1.5, 0, TAU, 48, trim, 3.0, true)
			if b[1] == "<" or b[1] == ">":
				var d := -1.0 if b[1] == "<" else 1.0
				var a := r * 0.38
				draw_colored_polygon(PackedVector2Array([c + Vector2(d * a, 0), c + Vector2(-d * a * 0.7, -a), c + Vector2(-d * a * 0.7, a)]), Color.WHITE)
				continue
			var fs := int(r * 0.36)
			var w := f.get_string_size(b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, c + Vector2(-w / 2, fs * 0.35), b[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
