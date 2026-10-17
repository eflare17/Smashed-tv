class_name CameraRig
extends Node3D
## CONTRACT. The two views. Owned by the Player and cameras task.
##
## Top-down: like the HTML game's view (camFollow/camView/camApply in Smashed.html), following the target,
## looking north and steeply down (pitch, about 65 degrees) so the floor art reads like the flat HTML view
## while the upright character pictures still stand. Z cycles the zoom like the HTML game's setZoom:
## 1x shows the whole 520-unit height of the lounge, 1.5x (ZOOM_IN) and 2x (ZOOM_LOBBY, about half of
## the 860x520 lounge, the default in the lobby). If bounds is set (HTML units) the view stays inside it the
## way camView keeps the HTML view inside the arena (and centres on it when it's smaller than the view).
##
## First person (V): the HTML game's plain first person: eyes at SHROOM_EYE plus the target's dz, mouse look
## with the pointer captured (0.0045 rad a pixel across, 0.0035 up and down, held to +-0.6 like SHROOM.lookY),
## the arrow keys (or a pad's right stick) turn (2.4 rad/s) and look up and down (1.6 rad/s), Esc lets the pointer go and a click takes
## it back. 66 degrees of view across, like the HTML first person.

enum Mode { TOP_DOWN, FIRST_PERSON }
signal mode_changed(mode: int)
var mode: int = Mode.TOP_DOWN
var target: Player:
	set(v):
		target = v
		if v:
			v.rig = self
			snap()

## --- Not contract ---
signal zoom_changed(level: int)
## The HTML game's zoom steps: 0 = 1x, 1 = 1.5x (ZOOM_IN), 2 = 2x (ZOOM_LOBBY). Lobby default 2x.
const ZOOMS := [1.0, 1.5, 2.0]
var zoom_level: int = 2
## In a run (the arena) the 2x step is 1.5x, like zoomWanted().
var in_run: bool = false
## How steeply the top-down camera looks down, in degrees (90 = straight down).
@export var pitch_deg: float = 65.0
## The top-down camera's vertical field of view, degrees (narrow: little perspective, like the flat HTML view).
@export var top_fov: float = 30.0
## First person field of view across, degrees (the HTML game's 66).
@export var fp_fov: float = 66.0
## How much of his height off the ground the top-down view rises with (on the trampoline, and otherwise). The HTML
## game's flat view lifts by 0.3 of it on the trampoline; in 3D the camera is close enough that a bounce 8 m up
## would come right up to it and leave the screen, so the view rises with most of the height instead: he still
## goes up the screen and the yard drops away under him.
@export var air_follow_tramp: float = 0.75
@export var air_follow: float = 0.6
## The ground the top-down view keeps inside, HTML units (x0, y0, w, h); empty: no limit.
var bounds: Rect2 = Rect2()
## Lets the mouse capture happen (false for tests or menus over the game).
var capture_mouse: bool = true

const VIEW_H := 520.0            # the HTML game's screen height (ARENA.h): what 1x shows north to south
const MOUSE_X := 0.0045
const MOUSE_Y := 0.0035
const LOOK_MAX := 0.6

var _cam: Camera3D
var _aim: Vector2 = Vector2.ZERO      # where the top-down view centres, HTML ground units
var _aim_h: float = 0.0
var _z: float = 2.0                   # the zoom now (eases to the wanted one)
var _snap: bool = true

func _ready() -> void:
	process_priority = 100            # after the player has moved this frame
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.near = 0.05
	_cam.far = 400.0
	add_child(_cam)
	_cam.current = true
	_z = zoom_wanted()
	_apply_mode()
	snap()

func camera() -> Camera3D:
	return _cam

## --- Not contract ---

func set_mode(m: int) -> void:
	if m == mode:
		return
	mode = m
	_apply_mode()
	if mode == Mode.FIRST_PERSON and target:
		var f := target.facing
		target.look_ang = atan2(f.y, f.x) if f.length() > 0.001 else -PI / 2.0
		target.look_y = 0.0
	_capture(mode == Mode.FIRST_PERSON)
	snap()
	mode_changed.emit(mode)

func toggle_mode() -> void:
	set_mode(Mode.TOP_DOWN if mode == Mode.FIRST_PERSON else Mode.FIRST_PERSON)

func set_zoom(level: int) -> void:
	zoom_level = posmod(level, 3)
	zoom_changed.emit(zoom_level)

func next_zoom() -> void:
	set_zoom(zoom_level + 1)

## The zoom the view eases to (zoomWanted).
func zoom_wanted() -> float:
	if zoom_level == 2 and in_run:
		return ZOOMS[1]
	return ZOOMS[zoom_level]

func zoom_text() -> String:
	return "Zoom: " + ["1x", "1.5x", "2x"][zoom_level] + " (Z)"

## Jump straight to where the view wants to be (no easing), e.g. after a teleport.
func snap() -> void:
	_snap = true
	if is_inside_tree() and _cam:
		_update(0.0)

## Is the pointer held by the game (first person mouse look)?
func mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _capture(on: bool) -> void:
	if on and capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _apply_mode() -> void:
	if _cam == null:
		return
	if mode == Mode.FIRST_PERSON:
		_cam.keep_aspect = Camera3D.KEEP_WIDTH
		_cam.fov = fp_fov
	else:
		_cam.keep_aspect = Camera3D.KEEP_HEIGHT
		_cam.fov = top_fov

# Mouse look comes first, before the GUI: with the pointer held its position stays where it was let go
# (the web build especially), so a HUD button under it would otherwise swallow every movement.
func _input(event: InputEvent) -> void:
	if mode == Mode.FIRST_PERSON and target and event is InputEventMouseMotion and mouse_captured():
		var rel: Vector2 = event.screen_relative
		target.look_ang = wrapf(target.look_ang + rel.x * MOUSE_X, -PI, PI)
		target.look_y = clampf(target.look_y + rel.y * MOUSE_Y, -LOOK_MAX, LOOK_MAX)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_view") and not event.is_echo():
		toggle_mode()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Z:
			next_zoom()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_ESCAPE and mode == Mode.FIRST_PERSON:
			_capture(false)                    # (the browser lets it go by itself; the desktop needs telling)
			return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_DPAD_UP:
		next_zoom()                            # d-pad up: zoom, like the HTML game's pad
		get_viewport().set_input_as_handled()
		return
	if mode != Mode.FIRST_PERSON or target == null:
		return
	if event is InputEventMouseButton and event.pressed and not mouse_captured():
		_capture(true)                         # a click takes it back
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if mode == Mode.FIRST_PERSON and target and target.controls_enabled:
		var dt := minf(delta, 0.05)
		if Input.is_physical_key_pressed(KEY_LEFT): target.look_ang -= 2.4 * dt
		if Input.is_physical_key_pressed(KEY_RIGHT): target.look_ang += 2.4 * dt
		if Input.is_physical_key_pressed(KEY_UP): target.look_y = maxf(-LOOK_MAX, target.look_y - 1.6 * dt)
		if Input.is_physical_key_pressed(KEY_DOWN): target.look_y = minf(LOOK_MAX, target.look_y + 1.6 * dt)
		var rs := Player.pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)   # the right stick looks round
		target.look_ang += rs.x * 2.8 * dt
		target.look_y = clampf(target.look_y + rs.y * 1.6 * dt, -LOOK_MAX, LOOK_MAX)
		target.look_ang = wrapf(target.look_ang, -PI, PI)
	_update(delta)

func _update(delta: float) -> void:
	if _cam == null:
		return
	if mode == Mode.FIRST_PERSON:
		_update_fp()
	else:
		_update_top(minf(delta, 0.1))
	_snap = false

func _update_fp() -> void:
	if target == null:
		return
	var eye := float(GameData.data.get("SHROOM_EYE", 62.0))
	var p := target.global_position
	var pos := Vector3(p.x, (target.dz + eye) * GameData.UNIT, p.z)
	var a := target.look_ang
	var ly := target.look_y
	var fwd := Vector3(cos(a) * cos(ly), -sin(ly), sin(a) * cos(ly))
	_cam.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)

func _update_top(dt: float) -> void:
	var want := zoom_wanted()
	if _snap:
		_z = want
	else:
		_z += (want - _z) * minf(1.0, dt * 10.0)
		if absf(want - _z) < 0.003:
			_z = want
	var tx := _aim.x
	var ty := _aim.y
	var th := 0.0
	if target:
		var hp := target.html_pos()
		tx = hp.x
		ty = hp.y - 20.0                                   # camFollow: me.y - 20, him a little below the middle
		th = target.dz * (air_follow_tramp if target.on_tramp else air_follow)  # and up with him off the ground
	if _snap:
		_aim = Vector2(tx, ty)
		_aim_h = th
	else:
		var k := minf(1.0, dt * 8.0)
		_aim += (Vector2(tx, ty) - _aim) * k
		_aim_h += (th - _aim_h) * k
	var pitch := deg_to_rad(clampf(pitch_deg, 10.0, 89.9))
	# far enough back that the screen's height covers VIEW_H / zoom of ground north to south
	var span := VIEW_H / _z * GameData.UNIT
	var d := span * sin(pitch) / (2.0 * tan(deg_to_rad(top_fov) / 2.0))
	var c := _aim
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		var vp := get_viewport().get_visible_rect().size
		var aspect := vp.x / maxf(1.0, vp.y)
		var hh := VIEW_H / _z / 2.0
		var hw := hh * aspect * sin(pitch)                  # across, the screen's width at the aim's depth
		c.x = bounds.get_center().x if bounds.size.x <= hw * 2.0 else clampf(c.x, bounds.position.x + hw, bounds.end.x - hw)
		c.y = bounds.get_center().y if bounds.size.y <= hh * 2.0 else clampf(c.y, bounds.position.y + hh, bounds.end.y - hh)
	var aim3 := GameData.world_to_3d(c.x, c.y, _aim_h)
	var back := Vector3(0.0, sin(pitch), cos(pitch))         # from the aim back up to the camera (it looks north)
	_cam.global_transform = Transform3D(Basis.looking_at(-back, Vector3.UP), aim3 + back * d)
