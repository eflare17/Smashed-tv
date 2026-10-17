class_name FightInstall
extends RefCounted
## Milestone 2's one entry point: main.gd calls FightInstall.install(self) at the end of _ready().
## Adds the input actions the fighting needs (in code, so project.godot stays as it is) and the Fight node.

static func install(main: Node) -> void:
	add_actions()
	var f := Fight.new()
	f.setup(main)
	main.add_child(f)

## fire, weapon_1..6, weapon_prev / weapon_next, start_run, restart, add_player (keyboard, mouse and pad).
static func add_actions() -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	_add("fire", [mb, rt])
	for i in 6:
		_add("weapon_%d" % (i + 1), [_key(KEY_1 + i)])
	_add("weapon_prev", [_pad(JOY_BUTTON_LEFT_SHOULDER), _pad(JOY_BUTTON_DPAD_LEFT), _key(KEY_Q)])
	_add("weapon_next", [_pad(JOY_BUTTON_Y), _pad(JOY_BUTTON_DPAD_RIGHT)])
	_add("start_run", [_key(KEY_ENTER), _key(KEY_KP_ENTER), _pad(JOY_BUTTON_START)])
	_add("restart", [_key(KEY_R)])
	_add("add_player", [_key(KEY_P)])

static func _add(name: String, events: Array) -> void:
	if InputMap.has_action(name):
		return
	InputMap.add_action(name, 0.2)
	for e in events:
		InputMap.action_add_event(name, e)

static func _key(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e

static func _pad(b: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e
