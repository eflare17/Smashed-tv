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
## Something full-screen has the player (the farm panel, the mirror, the wardrobe, a menu): the sticks and buttons
## step aside (not drawn, their touches left to the panel). Ask the callable each frame (the Fight sets it).
var suspend_check: Callable
var suspended: bool = false

const PINK := Color("#f7a8ff")
const DARK := Color(20 / 255.0, 12 / 255.0, 28 / 255.0, 0.55)

# finger index -> {role, origin, pos}
var _fingers: Dictionary = {}
var _move := Vector2.ZERO
var _aim := Vector2.ZERO
var _aim_smooth := Vector2.ZERO      # the aim the player gets: _aim eased, so a thumb's tremor doesn't spin him
var _look_pending := Vector2.ZERO    # first person drag not yet turned into looking (eased in over a few frames)

## A thumb is imprecise: the left stick has a real dead zone and a gentle curve (small pushes walk slowly, a full
## push still runs), the aim stick a smaller dead zone, the drag-to-look a lower turn rate than a mouse.
const MOVE_DEAD := 0.22
const AIM_DEAD := 0.18
const MOVE_CURVE := 1.5
const LOOK_X := 0.0042
const LOOK_Y := 0.0034

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
	visible = on and not suspended
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
			if suspended:
				return
			if _touch_down(event.index, event.position):
				get_viewport().set_input_as_handled()
		elif _fingers.has(event.index):
			_touch_up(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		_touch_drag(event.index, event.position, event.relative)
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
	if Fight.me and Fight.me.hud and Fight.me.hud.on_ui(pos):
		return false                                    # the weapon bar, the mode picker: their own touches
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
		"look":
			# `rel` is in the game's own units (the same on any phone: the stretch already accounts for the
			# screen's density), taken in over the next frames by _process
			# (a single jump this big is the browser losing track of a finger, not a swipe: it would whip the
			# view round, so it's capped)
			_look_pending += rel.limit_length(60.0)
	queue_redraw()

func _touch_up(i: int) -> void:
	var f: Dictionary = _fingers[i]
	_fingers.erase(i)
	match f.role:
		"move":
			_set_move(Vector2.ZERO)
		"aim":
			_aim = Vector2.ZERO
			_aim_smooth = Vector2.ZERO
			var p := _player()
			if p:
				p.aim_override = Vector2.ZERO
		"look":
			_look_pending = Vector2.ZERO
		"btn":
			_send(f.action, false)
	queue_redraw()

func _release_all() -> void:
	for i in _fingers.keys():
		_touch_up(i)

## A stick push with the dead zone taken off (so it starts from 0 at the edge of it) and the curve put on.
static func shape(v: Vector2, dead: float, curve: float) -> Vector2:
	var l := v.length()
	if l <= dead:
		return Vector2.ZERO
	var m := pow(minf(1.0, (l - dead) / (1.0 - dead)), curve)
	return v / l * m

# The left stick as the move actions, with their strengths.
func _set_move(v: Vector2) -> void:
	_move = v
	v = shape(v, MOVE_DEAD, MOVE_CURVE)
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

func _process(dt: float) -> void:
	var sus := suspend_check.is_valid() and bool(suspend_check.call())
	if sus != suspended:
		suspended = sus
		if sus:
			_release_all()
		visible = active and not sus
	if not active or suspended:
		return
	dt = minf(dt, 0.1)
	var p := _player()
	# the aim stick, eased (about 60 ms) and shaped
	if _fingers.values().any(func(f): return f.role == "aim"):
		_aim_smooth = _aim_smooth.lerp(shape(_aim, AIM_DEAD, 1.0), 1.0 - exp(-dt * 25.0))
		if p:
			p.aim_override = _aim_smooth
	# the drag to look: a share of what's pending turns him each frame
	if _look_pending != Vector2.ZERO:
		var take := _look_pending * (1.0 - exp(-dt * 30.0))
		_look_pending -= take
		# (in a run the fight drives him and his own controls are off, but the look is still his)
		var in_run: bool = Fight.me != null and Fight.me.sim != null and Fight.me.sim.started and not Fight.me.sim.over
		if p and (p.controls_enabled or in_run) and _fp():
			p.look_ang = wrapf(p.look_ang + take.x * LOOK_X, -PI, PI)
			p.look_y = clampf(p.look_y + take.y * LOOK_Y, -CameraRig.LOOK_MAX, CameraRig.LOOK_MAX)
		if _look_pending.length() < 0.05:
			_look_pending = Vector2.ZERO
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
		if vp.x > vp.y and fire_enabled:
			# landscape: clear of the weapon bar along the bottom (its top is the HTML canvas's y 440)
			c2.y = minf(c2.y, vp.y - 80.0 * minf(vp.y / 520.0, vp.x / 372.0) - R - 12.0)
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
