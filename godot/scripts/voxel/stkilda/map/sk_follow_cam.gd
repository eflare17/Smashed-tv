# (Copied from stkilda-godot scripts/camera/follow_cam.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkFollowCam
extends Node3D
## The third-person camera for walking: it follows the walker from behind and a little above, the mouse swings
## it round (click to grab the mouse, Esc lets go; or hold the right button), the wheel zooms in and out, and a
## spring arm pulls it in front of walls so you never lose sight of who you're walking.

const LOOK := 0.0025
var target: Node3D
var yaw := 0.0
var pitch := -0.3
var dist := 4.2
## How high above the target to look at (a person: their head; a car: over its roof).
var height := 1.55
## Driving: swing round behind the target by itself whenever you haven't looked round for a moment.
var chase := false
var _idle := 9.0
var _yaw_was := 0.0
var _pitch_was := 0.0
const FOV := 62.0
const PORTRAIT_FOV := 82.0
var active := true:
	set(v):
		active = v
		if _cam:
			_cam.current = v
		if not v and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

var _arm: SpringArm3D
var _cam: Camera3D
var _focus := Vector3.ZERO

func _ready() -> void:
	top_level = true
	_arm = SpringArm3D.new()
	_arm.collision_mask = SkData.LAYER_WORLD
	var sph := SphereShape3D.new()
	sph.radius = 0.2
	_arm.shape = sph
	_arm.margin = 0.1
	add_child(_arm)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.near = 0.05
	_cam.far = 1200.0
	_arm.add_child(_cam)
	_cam.current = active

func camera() -> Camera3D:
	return _cam

## Look from behind whoever we're following (yaw: the way they face).
func behind(face_yaw: float) -> void:
	yaw = face_yaw
	if target:
		_focus = target.global_position + Vector3(0, height, 0)

func exclude(body: CollisionObject3D) -> void:
	_arm.add_excluded_object(body.get_rid())

func _unhandled_input(event: InputEvent) -> void:
	# a phone turns each touch into a pretend mouse as well: the touch controls already look round, so skip those
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if not active:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP:
				dist = maxf(dist - 0.4, 1.6)
			MOUSE_BUTTON_WHEEL_DOWN:
				dist = minf(dist + 0.4, 10.0)
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			yaw -= event.relative.x * LOOK
			pitch = clampf(pitch - event.relative.y * LOOK, -1.3, 0.5)

var _kick := 0.0
var _kick_t := 0.0

## Jolt the camera (a bat landing a hit): `amount` m of shake, gone in a fraction of a second.
func kick(amount: float) -> void:
	_kick = amount
	_kick_t = 0.0

func _process(dt: float) -> void:
	if target == null:
		return
	var want := target.global_position + Vector3(0, height, 0)
	# anything that swung the camera (the mouse, a drag on a phone) holds off the chase for a bit
	if not is_equal_approx(yaw, _yaw_was) or not is_equal_approx(pitch, _pitch_was):
		_idle = 0.0
	_idle += dt
	if chase and _idle > 1.2:
		var k := 1.0 - exp(-dt * 2.5)
		yaw = lerp_angle(yaw, target.global_rotation.y, k)
		pitch = lerpf(pitch, -0.2, k)
	_yaw_was = yaw
	_pitch_was = pitch
	_focus = _focus.lerp(want, 1.0 - exp(-dt * 14.0))
	global_position = _focus
	# a jolt (kick): a quick shake, dying away in real time (even with the game slowed for a hit)
	if _kick > 0.0:
		var real := dt / maxf(0.01, Engine.time_scale)
		_kick_t += real
		global_position += Vector3(sin(_kick_t * 71.0), sin(_kick_t * 53.0 + 1.3), 0.0) * _kick
		_kick = maxf(0.0, _kick - real * 0.25)
	rotation = Vector3(pitch, yaw, 0)
	# held upright (a phone in portrait) the screen is tall and narrow: see more of the height and stand further
	# back, or you only see a thin slice of the world
	var vp := get_viewport().get_visible_rect().size
	var tall := vp.y > vp.x
	_cam.fov = PORTRAIT_FOV if tall else FOV
	_arm.spring_length = dist * (1.35 if tall else 1.0)
