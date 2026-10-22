extends RefCounted
## Smash arcade input. The actions are added to the InputMap at runtime (only if missing), so project.godot stays
## untouched. All are prefixed "arcade_smash_" so they can't clash with the main game or the other cabinets.
##   move   WASD / left stick / d-pad
##   aim    arrow keys / right stick (twin-stick: pushing it also fires)
##   fire   left mouse button (aims at the cursor) / RT / RB
##   view   C / pad Y            top-down <-> first person
##   start  Enter / pad Start    restart after game over
##   debug  F2 +50 grunts, F3 debug overlay, F4 god mode

const MOVE_UP := "arcade_smash_move_up"
const MOVE_DOWN := "arcade_smash_move_down"
const MOVE_LEFT := "arcade_smash_move_left"
const MOVE_RIGHT := "arcade_smash_move_right"
const AIM_UP := "arcade_smash_aim_up"
const AIM_DOWN := "arcade_smash_aim_down"
const AIM_LEFT := "arcade_smash_aim_left"
const AIM_RIGHT := "arcade_smash_aim_right"
const FIRE := "arcade_smash_fire"
const VIEW := "arcade_smash_view"
const START := "arcade_smash_start"
const DEBUG_SPAWN := "arcade_smash_debug_spawn"
const DEBUG_OVERLAY := "arcade_smash_debug_overlay"
const DEBUG_GOD := "arcade_smash_debug_god"

static func ensure_actions() -> void:
	_add(MOVE_UP, [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1), _button(JOY_BUTTON_DPAD_UP)])
	_add(MOVE_DOWN, [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1), _button(JOY_BUTTON_DPAD_DOWN)])
	_add(MOVE_LEFT, [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1), _button(JOY_BUTTON_DPAD_LEFT)])
	_add(MOVE_RIGHT, [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1), _button(JOY_BUTTON_DPAD_RIGHT)])
	_add(AIM_UP, [_key(KEY_UP), _axis(JOY_AXIS_RIGHT_Y, -1)])
	_add(AIM_DOWN, [_key(KEY_DOWN), _axis(JOY_AXIS_RIGHT_Y, 1)])
	_add(AIM_LEFT, [_key(KEY_LEFT), _axis(JOY_AXIS_RIGHT_X, -1)])
	_add(AIM_RIGHT, [_key(KEY_RIGHT), _axis(JOY_AXIS_RIGHT_X, 1)])
	_add(FIRE, [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_add(VIEW, [_key(KEY_C), _button(JOY_BUTTON_Y)])
	_add(START, [_key(KEY_ENTER), _key(KEY_KP_ENTER), _button(JOY_BUTTON_START)])
	_add(DEBUG_SPAWN, [_key(KEY_F2)])
	_add(DEBUG_OVERLAY, [_key(KEY_F3)])
	_add(DEBUG_GOD, [_key(KEY_F4)])

static func _add(action: String, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.25)
	for e: InputEvent in events:
		InputMap.action_add_event(action, e)

static func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e

static func _axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	return e

static func _button(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e

static func _mouse(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e
