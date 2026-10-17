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
## the look actions (arrow keys 2.4 rad/s, a pad's right stick 2.8) turn and look up and down (1.6 rad/s),
## release_mouse (Esc) lets the pointer go and a click takes it back; while it's let go, resting the mouse near the
## left or right edge of the window keeps turning (the HTML game's b310). 66 degrees of view across, like the HTML
## first person.
##
## Every control is an input action (project.godot): toggle_view (V, View), zoom (Z, d-pad up), release_mouse
## (Esc), look_left/right/up/down (arrows, right stick). The rig moves in _process (it's drawn, not simulated),
## following where the target is drawn (Player.visual_pos: physics interpolation), so it never judders.

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
## The HTML game's zoom steps: 0 = 1x, 1 = 1.5x (ZOOM_IN), 2 = 2x (ZOOM_LOBBY). 1x to start (CAM.lvl 0), and the
## player's choice (Z) is remembered in user://smashed.cfg like the HTML game's localStorage 'smashed-zoom'.
const ZOOMS := [1.0, 1.5, 2.0]
const CFG := "user://smashed.cfg"
var zoom_level: int = 0
static var _zoom_loaded := false
static var _zoom_saved := 0
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
## Where the top-down view centres instead of following the target (HTML ground units), or null to follow. The
## HTML game's 1x view in the lobby shows the whole lounge, or the whole bedroom, rather than following (camFollow);
## main sets this for that. With it set the view frames the room: the HTML screen's 860 x 520 (over the zoom)
## round that point fits the screen exactly from its north edge to its south (the pitched camera sees more ground
## above the middle than below, so this isn't simply centring on it), and across at its near edge.
var fixed_aim = null
## The ground the fixed_aim view frames, HTML units (the HTML game's screen at 1x).
const FRAME_W := 860.0
## The ground the top-down view keeps inside, HTML units (x0, y0, w, h); empty: no limit.
var bounds: Rect2 = Rect2()
## Lets the mouse capture happen (false for tests or menus over the game).
var capture_mouse: bool = true

const PORTRAIT_REF := 1.5        # the narrowest shape that keeps its height; narrower windows show the same across
const VIEW_H := 520.0            # the HTML game's screen height (ARENA.h): what 1x shows north to south
const MOUSE_X := 0.0045
const MOUSE_Y := 0.0035
const LOOK_MAX := 0.6

var _cam: Camera3D
var _aim: Vector2 = Vector2.ZERO      # where the top-down view centres, HTML ground units
var _aim_h: float = 0.0
var _z: float = 2.0                   # the zoom now (eases to the wanted one)
var _snap: bool = true
var _dist: float = -1.0               # how far back the top-down camera is (eases like the aim), metres

func _ready() -> void:
	process_priority = 100            # after the player has moved this frame
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved every drawn frame, not by physics
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.near = 0.05
	_cam.far = 400.0
	add_child(_cam)
	_cam.current = true
	if not _zoom_loaded:
		_zoom_loaded = true
		var cf := ConfigFile.new()
		if cf.load(CFG) == OK:
			_zoom_saved = clampi(int(cf.get_value("view", "zoom", 0)), 0, 2)
	zoom_level = _zoom_saved
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

## Z: the next step, remembered (over a restart's reload and the next visit).
func next_zoom() -> void:
	set_zoom(zoom_level + 1)
	_zoom_saved = zoom_level
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("view", "zoom", zoom_level)
	cf.save(CFG)

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
	if on and capture_mouse and not touch_active:      # (on a touch screen a finger looks round instead)
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
	if event.is_action_pressed("zoom") and not event.is_echo():
		if Fight.me and Fight.me.modal_open():
			return                             # (a panel or the mirror has the d-pad)
		next_zoom()                            # Z, or d-pad up like the HTML game's pad
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("release_mouse") and mode == Mode.FIRST_PERSON:
		_capture(false)                        # (the browser lets it go by itself; the desktop needs telling)
		return
	if mode != Mode.FIRST_PERSON or target == null:
		return
	if event is InputEventMouseButton and event.pressed and not mouse_captured() and capture_mouse and not touch_active:
		_capture(true)                         # a click takes it back
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if mode == Mode.FIRST_PERSON and target and target.controls_enabled:
		var dt := minf(delta, 0.1)
		# the look actions: the arrow keys turn 2.4 rad/s, a pad's right stick 2.8 (b314); both look up and down 1.6
		var lx := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
		var ly := Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
		var turn := 2.8 if Player.pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y).length() > 0.01 else 2.4
		target.look_ang += lx * turn * dt
		target.look_y = clampf(target.look_y + ly * 1.6 * dt, -LOOK_MAX, LOOK_MAX)
		# b310: with the pointer let go, resting it near the left or right edge keeps turning (up to 2.4 rad/s)
		target.look_ang += edge_turn() * 2.4 * dt
		target.look_ang = wrapf(target.look_ang, -PI, PI)
	_update(delta)

## How hard the mouse at the window's edge turns the first-person view (-1..1; 0 unless the pointer is let go
## and inside the window, in the outer 12% either side).
var mouse_in_window: bool = true
var touch_active: bool = false          # the touch layer is in use: the "mouse" is a finger, no edge turning
func edge_turn() -> float:
	if mouse_captured() or not mouse_in_window or touch_active or not capture_mouse or not target.controls_enabled:
		return 0.0
	var vp := get_viewport()
	var w := vp.get_visible_rect().size.x
	if w < 1.0:
		return 0.0
	var mp := vp.get_mouse_position()
	if mp.y < 0.0 or mp.y > vp.get_visible_rect().size.y:
		return 0.0
	var mx := mp.x / w
	if mx < 0.0 or mx > 1.0:
		return 0.0
	if mx < 0.12:
		return -(0.12 - mx) / 0.12
	if mx > 0.88:
		return (mx - 0.88) / 0.12
	return 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		mouse_in_window = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER:
		mouse_in_window = true

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
	var v := target.visual_pos()                          # where he's drawn this frame (interpolated)
	var pos := GameData.world_to_3d(v.x, v.y, v.z + eye)
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
	var pitch := deg_to_rad(clampf(pitch_deg, 10.0, 89.9))
	var half_f := deg_to_rad(top_fov) / 2.0
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(1.0, vp.y)
	# where he's drawn this frame (physics interpolation), and how far up the view rises with him
	var tx := _aim.x
	var ty := _aim.y
	var th := 0.0
	if target:
		var v := target.visual_pos()
		th = maxf(0.0, v.z) * (air_follow_tramp if target.on_tramp else air_follow)
		tx = v.x
		ty = v.y - 20.0                                    # camFollow: me.y - 20, him a little below the middle
	# far enough back that the screen's height covers VIEW_H / zoom of ground north to south (HTML units)
	# A tall screen (a phone upright) would otherwise see a thin strip across: the camera backs off so it shows
	# about what a PORTRAIT_REF-shaped window does across (more north to south instead).
	var span := VIEW_H / _z * maxf(1.0, PORTRAIT_REF / maxf(0.1, aspect))
	var dist := span * sin(pitch) / (2.0 * tan(half_f))
	if fixed_aim is Vector2:
		var f := _frame(fixed_aim, pitch, half_f, aspect)
		tx = f.x
		ty = f.y
		dist = f.z
	elif bounds.size.x > 0.0 and bounds.size.y > 0.0:
		# camView: kept inside the bounds (centred on them when they're smaller than the view)
		var hh := span / 2.0
		var hw := hh * aspect * sin(pitch)                  # across, the screen's width at the aim's depth
		tx = bounds.get_center().x if bounds.size.x <= hw * 2.0 else clampf(tx, bounds.position.x + hw, bounds.end.x - hw)
		ty = bounds.get_center().y if bounds.size.y <= hh * 2.0 else clampf(ty, bounds.position.y + hh, bounds.end.y - hh)
	if _snap or _dist < 0.0:
		_aim = Vector2(tx, ty)
		_aim_h = th
		_dist = dist
	else:
		var k := 1.0 - exp(-dt * 8.0)                        # (frame-rate independent: smooth at 30 fps too)
		_aim += (Vector2(tx, ty) - _aim) * k
		_aim_h += (th - _aim_h) * k
		_dist += (dist - _dist) * k
	var aim3 := GameData.world_to_3d(_aim.x, _aim.y, _aim_h)
	var back := Vector3(0.0, sin(pitch), cos(pitch))         # from the aim back up to the camera (it looks north)
	_cam.global_transform = Transform3D(Basis.looking_at(-back, Vector3.UP), aim3 + back * _dist * GameData.UNIT)

## The room framing (fixed_aim): FRAME_W x VIEW_H over the zoom, round c, fitting the screen's top and bottom edges
## (rays through them meet the ground at the room's north and south lines) and its width at the near (bottom)
## edge; pulled back if the width needs it, keeping it centred. Returns (aim x, aim y, distance back) in HTML
## units: the aim is where the middle of the screen meets the ground.
func _frame(c: Vector2, pitch: float, half_f: float, aspect: float) -> Vector3:
	var y0 := c.y - VIEW_H / _z / 2.0
	var y1 := c.y + VIEW_H / _z / 2.0
	var half_w := FRAME_W / _z / 2.0
	var a := pitch - half_f                                   # the top edge's ray, below the horizon
	var b := pitch + half_f                                   # the bottom edge's
	var cot_a := cos(a) / maxf(0.0001, sin(a))
	var cot_b := cos(b) / maxf(0.0001, sin(b))
	var h := (y1 - y0) / maxf(0.0001, cot_a - cot_b)          # the camera's height over the ground
	var near_half := h / maxf(0.0001, sin(b)) * cos(half_f) * tan(half_f) * aspect
	# an upright phone can't show the whole width without big empty bands above and below: in a run it shows
	# part of it (down to about half) and slides across with him
	var need := half_w
	if in_run:
		need = half_w * clampf(aspect * 1.25, 0.5, 1.0)
	if near_half < need:
		h *= need / maxf(0.0001, near_half)
		near_half = need
	var x := c.x
	if near_half < half_w and target:
		var slack := half_w - near_half
		x = clampf(target.visual_pos().x, c.x - slack, c.x + slack)
	var cam_y := (y0 + y1) / 2.0 + h * (cot_a + cot_b) / 2.0  # where the camera stands, on the ground
	var d := h / sin(pitch)
	return Vector3(x, cam_y - d * cos(pitch), d)
