class_name VoxelLockView
extends Control
## Dialling a chest's padlock (the owner, 21 Oct, Stage 3): the padlock held up close in front of you (a real 3D one,
## lit by a little lamp of its own), the mouse free. Wheel over a number wheel (or click its top or bottom half) turns
## it a digit, with a click. A locked padlock springs open by itself when its wheels show the code; an open one is
## locked by clicking the shackle shut, the code being what the wheels show (they're spun to hide it straight after,
## the code shown a moment so you remember it). R takes an open padlock off the chest into your backpack. E, L or Esc:
## done. Every lock change goes through VoxelStorages (co-op: the host, which alone knows the codes). Owned by the
## voxel session.

const DIST := 0.15              # metres in front of the eye the padlock is held

var arena: Node
var storage: VoxelStorage
var model: VoxelPadlock
var _lamp: OmniLight3D
var _font: Font
var _note := ""
var _note_t := 0.0
var _hover := -2                # the wheel under the mouse (-1: the shackle, -2: nothing)

func setup(arena_: Node) -> void:
	arena = arena_
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func is_open() -> bool:
	return visible

func open(st: VoxelStorage) -> void:
	storage = st
	visible = true
	model = VoxelPadlock.new()
	arena.cam.add_child(model)
	model.position = Vector3(0, -0.004, -DIST)
	model.set_code(st.dial_code)
	model.open = not st.locked
	model._k = 0.99 if model.open else 0.0      # (just short of open: its first frame stands the shackle up and aside)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.95, 0.85)
	_lamp.light_energy = 0.6
	_lamp.omni_range = 0.6
	arena.cam.add_child(_lamp)
	_lamp.position = Vector3(0.08, 0.1, -0.05)
	_note = ""
	queue_redraw()

func close() -> void:
	if storage and model:
		storage.dial_code = model.code()       # (the wheels stay where you left them, on this chest, for you)
	if model:
		model.queue_free()
	if _lamp:
		_lamp.queue_free()
	model = null
	_lamp = null
	storage = null
	visible = false

## The chest's lock changed (here or from the host): the padlock in your hand follows.
func refresh() -> void:
	if not visible or storage == null:
		return
	if not storage.has_lock:
		arena.close_lock()
		return
	if model.open != (not storage.locked):
		model.open = not storage.locked
		arena.sound.play("lock_open" if model.open else "lock_shut", Vector3.INF, -3.0)
		if model.open and arena.lock_then_chest:
			_note = "Open!"
			_note_t = 1.5
	queue_redraw()

func _process(dt: float) -> void:
	if not visible:
		return
	_note_t = maxf(0.0, _note_t - dt)
	if _note_t <= 0.0:
		_note = ""

# the wheel (0-3), the shackle (-1) or nothing (-2) at a point on screen
func pick(at: Vector2) -> int:
	if model == null:
		return -2
	var cam: Camera3D = arena.cam
	for i in VoxelPadlock.DIALS:
		var c := cam.unproject_position(model.wheel_pos(i))
		var e := cam.unproject_position(model.wheel_pos(i) + cam.global_transform.basis.y * VoxelPadlock.DIAL_R)
		var r := c.distance_to(e) * 1.25
		var hw := r * VoxelPadlock.DIAL_W / VoxelPadlock.DIAL_R * 0.5
		if absf(at.x - c.x) <= hw and absf(at.y - c.y) <= r:
			return i
	var sc := cam.unproject_position(model.shackle_pos())
	var se := cam.unproject_position(model.shackle_pos() + cam.global_transform.basis.x * VoxelPadlock.W * 0.4)
	if at.distance_to(sc) <= sc.distance_to(se) * 1.2:
		return -1
	return -2

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := pick(e.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		var at := pick(e.position)
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and at >= 0:
			turn(at, 1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		elif e.button_index == MOUSE_BUTTON_LEFT and at >= 0:
			var cam: Camera3D = arena.cam
			var c := cam.unproject_position(model.wheel_pos(at))
			turn(at, 1 if e.position.y < c.y else -1)
		elif e.button_index == MOUSE_BUTTON_RIGHT and at >= 0:
			turn(at, -1)
		elif e.button_index == MOUSE_BUTTON_LEFT and at == -1:
			shackle()
		accept_event()

## Wheel i turned d digits; a locked padlock is tried at the new code.
func turn(i: int, d: int) -> void:
	model.spin(i, d)
	storage.dial_code = model.code()
	arena.sound.play("dial_click", Vector3.INF, -8.0, 1.0, 0.12)
	if storage.locked:
		arena.stash.try_code(storage, model.code())
	queue_redraw()

## The shackle clicked: an open padlock locked with the wheels' code (then spun to hide it); a shut one tugged.
func shackle() -> void:
	if storage.locked:
		arena.sound.play("lock_rattle", Vector3.INF, -4.0)
		_note = "Locked tight: the wheels don't show its code"
		_note_t = 1.5
		return
	var c := model.code()
	arena.stash.lock(storage, c)
	model.open = false
	model.scramble()
	storage.dial_code = model.code()
	arena.sound.play("lock_shut", Vector3.INF, -3.0)
	_note = "Locked. The code is %s %s %s %s — the wheels are spun to hide it." % [c[0], c[1], c[2], c[3]]
	_note_t = 4.0
	queue_redraw()

## R: an open padlock off the chest, into the backpack.
func take_off() -> void:
	if storage.locked:
		_note = "Open it first"
		_note_t = 1.5
		return
	arena.stash.lock_off(storage)

func _draw() -> void:
	if not visible or storage == null:
		return
	var title := "%s's padlock" % storage.title if not storage.title.begins_with("Your") else "Your padlock"
	var state := "LOCKED — turn the wheels to its code" if storage.locked else "open — click the shackle to lock it with the code the wheels show"
	var lines := [title + ":  " + state,
		"mouse wheel (or click the top / bottom of a wheel) to turn it     " + ("" if storage.locked else "R: take the padlock off     ") + "E, L or Esc: done"]
	var y := size.y - 190.0
	for l in lines:
		var w := _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string_outline(_font, Vector2((size.x - w) * 0.5, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color.BLACK)
		draw_string(_font, Vector2((size.x - w) * 0.5, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.92, 0.8))
		y += 28.0
	if _note != "":
		var w2 := _font.get_string_size(_note, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string_outline(_font, Vector2((size.x - w2) * 0.5, 90), _note, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 7, Color.BLACK)
		draw_string(_font, Vector2((size.x - w2) * 0.5, 90), _note, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.85, 0.4))
	# the wheel under the mouse: a faint ring round it
	var cam: Camera3D = arena.cam
	if _hover >= 0 and model:
		var c := cam.unproject_position(model.wheel_pos(_hover))
		var e := cam.unproject_position(model.wheel_pos(_hover) + cam.global_transform.basis.y * VoxelPadlock.DIAL_R)
		draw_arc(c, c.distance_to(e) * 1.4, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
	elif _hover == -1 and model:
		var sc := cam.unproject_position(model.shackle_pos())
		draw_arc(sc, 40, 0, TAU, 32, Color(1, 1, 1, 0.4), 2.0)
