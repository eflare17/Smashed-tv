class_name PadSetup
extends CanvasLayer
## The controller setup: some pads (a Steam Controller in a browser, some Android pads) come through with their
## sticks on other axes than a standard pad's, so the left stick looks round and the right one walks. This asks
## for four pushes (left stick up, left stick right, right stick up, right stick right), learns which axis and
## which way each is, and from then on the move_* / look_* actions and Player.pad_stick read the right ones.
## Saved in user://smashed.cfg [pad]. Open it by holding Back / View for 2 s, or F7. The first time a pad is
## used it says so once.

const CFG := "user://smashed.cfg"
const HOLD := 2.0

## logical axis (JOY_AXIS_LEFT_X..RIGHT_Y) -> [physical axis, sign]
static var axis_map := {0: [0, 1.0], 1: [1, 1.0], 2: [2, 1.0], 3: [3, 1.0]}

const STEPS := [
	["Push the LEFT stick UP and hold it", JOY_AXIS_LEFT_Y, -1.0],
	["Push the LEFT stick RIGHT and hold it", JOY_AXIS_LEFT_X, 1.0],
	["Push the RIGHT stick UP and hold it", JOY_AXIS_RIGHT_Y, -1.0],
	["Push the RIGHT stick RIGHT and hold it", JOY_AXIS_RIGHT_X, 1.0],
]

var _panel: PanelContainer
var _label: Label
var _hint: Label
var _step := -1                 # -1: closed
var _found := {}                # logical axis -> [physical, sign]
var _held_t := 0.0
var _hold_back := 0.0
var _hint_t := 0.0
var _hinted := false
var _rest := true               # the sticks have been let go since the last step
## Tests only: pretend a pad is plugged in with these axis values (axis -> value).
var test_axes = null

static func install(main: Node) -> PadSetup:
	var p := PadSetup.new()
	p.name = "PadSetup"
	main.add_child(p)
	return p

## The physical axis and sign a logical one reads from.
static func phys(ax: int) -> Array:
	return axis_map.get(ax, [ax, 1.0])

static func read(dev: int, ax: int) -> float:
	var m: Array = phys(ax)
	return Input.get_joy_axis(dev, int(m[0])) * float(m[1])

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputMap.has_action("pad_setup"):
		InputMap.add_action("pad_setup")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_F7
		InputMap.action_add_event("pad_setup", k)
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		var m = cf.get_value("pad", "map", null)
		if m is Dictionary and m.size() == 4:
			for k in m:
				axis_map[int(k)] = [int(m[k][0]), float(m[k][1])]
		_hinted = bool(cf.get_value("pad", "hinted", false))
	_apply()
	_build()

func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(22)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	var title := Label.new()
	title.text = "CONTROLLER SETUP"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(520, 0)
	v.add_child(_label)
	var sub := Label.new()
	sub.text = "B or Esc: cancel"
	sub.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_panel.add_child(v)
	_panel.visible = false
	add_child(_panel)
	_hint = Label.new()
	_hint.text = "Controller: sticks the wrong way round? Hold BACK / VIEW (or F7) to set it up"
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.offset_top = 96
	_hint.visible = false
	add_child(_hint)

func is_open() -> bool:
	return _step >= 0

func open() -> void:
	_freeze(true)
	_step = 0
	_found = {}
	_held_t = 0.0
	_rest = false
	_panel.visible = true
	_hint.visible = false
	_show()

func close() -> void:
	if _step >= 0:
		_freeze(false)
	_step = -1
	_panel.visible = false

## Holds the player still while it asks (the pushes would walk him round).
var _was_enabled := true
func _freeze(on: bool) -> void:
	var p = get_parent().get("player")
	if p == null:
		return
	if on:
		_was_enabled = p.controls_enabled
		p.controls_enabled = false
	else:
		p.controls_enabled = _was_enabled

func _show() -> void:
	if _step >= 0 and _step < STEPS.size():
		_label.text = "%d / 4\n%s" % [_step + 1, STEPS[_step][0]]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pad_setup") and not event.is_echo():
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
		return
	if is_open():
		if (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE) \
				or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
			close()
		get_viewport().set_input_as_handled()       # nothing else moves while it asks

func _axis(d: int, a: int) -> float:
	if test_axes is Dictionary:
		return float(test_axes.get(a, 0.0))
	return Input.get_joy_axis(d, a)

func _process(dt: float) -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty() and not test_axes is Dictionary:
		_hold_back = 0.0
		return
	var d: int = pads[0] if not pads.is_empty() else 0
	# hold Back / View for 2 s (a tap still switches the view)
	if not is_open() and Input.is_joy_button_pressed(d, JOY_BUTTON_BACK):
		_hold_back += dt
		if _hold_back >= HOLD:
			_hold_back = -999.0
			var rig = get_parent().get("rig")
			if rig and rig.has_method("toggle_mode"):
				rig.toggle_mode()                  # (the press switched the view: put it back)
			open()
	elif not Input.is_joy_button_pressed(d, JOY_BUTTON_BACK):
		_hold_back = 0.0
	# the first time a pad moves, say how to fix it once
	if not _hinted and not is_open():
		var any := false
		for a in 4:
			if absf(_axis(d, a)) > 0.5:
				any = true
		if any:
			_hinted = true
			_hint.visible = true
			_hint_t = 7.0
			_save()
	if _hint_t > 0.0:
		_hint_t -= dt
		if _hint_t <= 0.0:
			_hint.visible = false
	if not is_open():
		return
	# which axis is pushed furthest (axes 0..7, triggers aside: they rest at -1 on some pads, so only changes count)
	var best := -1
	var best_v := 0.0
	for a in 8:
		if a == JOY_AXIS_TRIGGER_LEFT or a == JOY_AXIS_TRIGGER_RIGHT:
			continue
		var val := _axis(d, a)
		if absf(val) > absf(best_v):
			best = a
			best_v = val
	if not _rest:
		if absf(best_v) < 0.3:
			_rest = true
		return
	var taken := false
	for k in _found:
		if int(_found[k][0]) == best:
			taken = true
	if best < 0 or absf(best_v) < 0.7 or taken:
		_held_t = 0.0
		return
	_held_t += dt
	if _held_t < 0.35:
		return
	var st: Array = STEPS[_step]
	# the asked-for direction is st[2]: if the axis reads the other way, it's flipped
	_found[int(st[1])] = [best, 1.0 if signf(best_v) == signf(float(st[2])) else -1.0]
	_held_t = 0.0
	_rest = false
	_step += 1
	if _step >= STEPS.size():
		axis_map = _found.duplicate()
		_apply()
		_save()
		_label.text = "Done! Your sticks are set."
		await get_tree().create_timer(1.2).timeout
		close()
	else:
		_show()

## Points the move_* / look_* actions' stick events at the learned axes.
func _apply() -> void:
	var acts := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0],
		"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
		"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0]}
	for act in acts:
		if not InputMap.has_action(act):
			continue
		for e in InputMap.action_get_events(act):
			if e is InputEventJoypadMotion:
				InputMap.action_erase_event(act, e)
		var m: Array = phys(int(acts[act][0]))
		var jm := InputEventJoypadMotion.new()
		jm.device = -1
		jm.axis = int(m[0]) as JoyAxis
		jm.axis_value = float(acts[act][1]) * float(m[1])
		InputMap.action_add_event(act, jm)

func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("pad", "map", axis_map)
	cf.set_value("pad", "hinted", _hinted)
	cf.save(CFG)
