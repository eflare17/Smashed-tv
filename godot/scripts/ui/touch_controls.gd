class_name TouchControls
extends Control
## Phone and tablet controls (Player and cameras task), as PLAN.md's "Decided with the owner" asks: top-down twin
## sticks (left moves, right aims) with ROLL and the E button; first person a left thumb stick to walk and a drag
## on the right half to look. VIEW and ZOOM buttons switch the view and zoom. There's a slot for milestone 2's FIRE
## button (fire_enabled), which presses the "fire" action like the others.
##
## Everything drives the existing input actions, so the game doesn't know a finger from a key: the left stick
## presses move_left/right/up/down with its strength (Input.action_press), the buttons send InputEventActions
## (roll, toggle_view, zoom, fire) through Input.parse_input_event, so a tap shorter than a frame still counts. The
## right stick top-down sets Player.aim_override; a first-person drag turns Player.look_ang and look_y.
## The round E button is the HUD's own (it takes its touches; this leaves them to it).
##
## Hidden until a touch is seen; a key press hides it again (a laptop with a touch screen). While it's active the
## player doesn't face the (finger-emulated) mouse and first person doesn't try to capture the pointer.
## Sizes scale with the screen's shorter side (a phone in landscape about 1, a tablet more).

## The Hud this lives in (it gives the player, the rig and the E button).
var hud: Hud
## Shown and in use (a touch has been seen).
var active: bool = false
## Show the FIRE button (milestone 2 turns it on and listens to the "fire" action).
var fire_enabled: bool = false

const PINK := Color("#f7a8ff")
const DARK := Color(20 / 255.0, 12 / 255.0, 28 / 255.0, 0.55)

# finger index -> {role, origin, pos}
var _fingers: Dictionary = {}
var _move := Vector2.ZERO
var _aim := Vector2.ZERO

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _scale() -> float:
	var vp := get_viewport_rect().size
	return clampf(minf(vp.x, vp.y) / 720.0, 0.75, 1.8)

func _stick_r() -> float:
	return 74.0 * _scale()

## The buttons: name -> [centre, radius, label, action]. (Laid out round the HUD's E button, bottom right.)
func buttons() -> Dictionary:
	var vp := get_viewport_rect().size
	var k := _scale()
	var r := 36.0 * k
	var fp := _fp()
	var out := {}
	out["roll"] = [Vector2(vp.x - 196.0 * k, vp.y - 92.0 * k), r, "HIGHER" if _on_tramp() else "ROLL", "roll"]
	if fire_enabled:
		out["fire"] = [Vector2(vp.x - 86.0 * k, vp.y - 72.0 * k), r * 1.15, "FIRE", "fire"]
	out["view"] = [Vector2(vp.x - 60.0 * k, 96.0 * k), r * 0.8, "VIEW", "toggle_view"]
	if not fp:
		out["zoom"] = [Vector2(vp.x - 140.0 * k, 96.0 * k), r * 0.8, "ZOOM", "zoom"]
	return out

func _player() -> Player:
	return hud.player if hud else null

func _rig() -> CameraRig:
	return hud.rig if hud else null

func _fp() -> bool:
	var r := _rig()
	return r != null and r.mode == CameraRig.Mode.FIRST_PERSON

func _on_tramp() -> bool:
	var p := _player()
	return p != null and p.on_tramp

func _set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	visible = on
	var p := _player()
	if p:
		p.face_mouse = not on
		if not on:
			p.aim_override = Vector2.ZERO
	var r := _rig()
	if r:
		r.touch_active = on                   # (no pointer capture, no edge turning: a finger looks round)
	if not on:
		_release_all()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_set_active(false)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_set_active(true)
			if _touch_down(event.index, event.position):
				get_viewport().set_input_as_handled()
		elif _fingers.has(event.index):
			_touch_up(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		_touch_drag(event.index, event.position, event.screen_relative)
		get_viewport().set_input_as_handled()

# A finger down: a button, the left stick, or the right side (aim top-down, look in first person). False: not ours.
func _touch_down(i: int, pos: Vector2) -> bool:
	if hud and hud.e_button_hit(pos):
		return false                                    # the HUD's E button takes it
	var vp := get_viewport_rect().size
	var bs := buttons()
	for n in bs:
		var b: Array = bs[n]
		if pos.distance_to(b[0]) <= b[1] + 8.0:
			_fingers[i] = {"role": "btn", "name": n, "action": b[3], "origin": pos, "pos": pos}
			_send(b[3], true)
			queue_redraw()
			return true
	if pos.y < vp.y * 0.22 and pos.x < vp.x * 0.5:
		return false                                    # the character picker up there
	var role := "move" if pos.x < vp.x * 0.45 else ("look" if _fp() else "aim")
	for f in _fingers.values():
		if f.role == role:
			return false                                # one finger per stick
	_fingers[i] = {"role": role, "origin": pos, "pos": pos}
	queue_redraw()
	return true

func _touch_drag(i: int, pos: Vector2, rel: Vector2) -> void:
	var f: Dictionary = _fingers[i]
	f.pos = pos
	match f.role:
		"move", "aim":
			var v: Vector2 = (pos - f.origin) / _stick_r()
			if v.length() > 1.0:
				# the stick's base follows a thumb that runs past it
				f.origin = pos - v.normalized() * _stick_r()
				v = v.normalized()
			if f.role == "move":
				_set_move(v)
			else:
				_aim = v
				var p := _player()
				if p:
					p.aim_override = v
		"look":
			var p := _player()
			if p and p.controls_enabled:
				var k := 720.0 / maxf(1.0, get_viewport_rect().size.y)   # the same turn for a swipe across any screen
				p.look_ang = wrapf(p.look_ang + rel.x * 0.0075 * k, -PI, PI)
				p.look_y = clampf(p.look_y + rel.y * 0.006 * k, -CameraRig.LOOK_MAX, CameraRig.LOOK_MAX)
	queue_redraw()

func _touch_up(i: int) -> void:
	var f: Dictionary = _fingers[i]
	_fingers.erase(i)
	match f.role:
		"move":
			_set_move(Vector2.ZERO)
		"aim":
			_aim = Vector2.ZERO
			var p := _player()
			if p:
				p.aim_override = Vector2.ZERO
		"btn":
			_send(f.action, false)
	queue_redraw()

func _release_all() -> void:
	for i in _fingers.keys():
		_touch_up(i)

# The left stick as the move actions, with their strengths (dead zone 0.15).
func _set_move(v: Vector2) -> void:
	_move = v
	if v.length() < 0.15:
		v = Vector2.ZERO
	for a in [["move_right", v.x], ["move_left", -v.x], ["move_down", v.y], ["move_up", -v.y]]:
		if a[1] > 0.0:
			Input.action_press(a[0], minf(1.0, a[1]))
		else:
			Input.action_release(a[0])

func _send(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(e)

func _process(_dt: float) -> void:
	if active:
		queue_redraw()

func _draw() -> void:
	if not active:
		return
	var k := _scale()
	var R := _stick_r()
	var font := get_theme_default_font()
	# the sticks: where a thumb is, else a faint hint of where to put one
	var vp := get_viewport_rect().size
	var shown := {}
	for f in _fingers.values():
		if f.role == "move" or f.role == "aim":
			shown[f.role] = true
			draw_circle(f.origin, R, Color(0, 0, 0, 0.22))
			draw_arc(f.origin, R, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0 * k, true)
			var kn: Vector2 = f.origin + (f.pos - f.origin).limit_length(R)
			draw_circle(kn, R * 0.42, Color(1, 1, 1, 0.35))
	if not shown.has("move"):
		var c := Vector2(150.0 * k, vp.y - 150.0 * k)
		draw_arc(c, R, 0, TAU, 48, Color(1, 1, 1, 0.18), 2.0 * k, true)
		_text(font, c, "MOVE", int(13 * k), Color(1, 1, 1, 0.35))
	if not shown.has("aim") and not _fp():
		var c2 := Vector2(vp.x * 0.62, vp.y - 150.0 * k)
		draw_arc(c2, R, 0, TAU, 48, Color(1, 1, 1, 0.12), 2.0 * k, true)
		_text(font, c2, "AIM", int(13 * k), Color(1, 1, 1, 0.3))
	if _fp() and not _fingers.values().any(func(f): return f.role == "look"):
		_text(font, Vector2(vp.x * 0.7, vp.y * 0.5 + 60.0 * k), "drag to look", int(14 * k), Color(1, 1, 1, 0.35))
	# the buttons: the HTML game's round dark buttons with a pink ring
	var held := {}
	for f in _fingers.values():
		if f.role == "btn":
			held[f.name] = true
	var bs := buttons()
	for n in bs:
		var b: Array = bs[n]
		draw_circle(b[0], b[1], Color(0.45, 0.25, 0.5, 0.8) if held.has(n) else DARK)
		draw_arc(b[0], b[1] - 1.5, 0, TAU, 48, PINK, 2.5 * k, true)
		_text(font, b[0], b[2], int(14 * k), PINK)

func _text(font: Font, c: Vector2, s: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w / 2.0, (font.get_ascent(fs) - font.get_descent(fs)) / 2.0), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
