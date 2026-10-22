class_name VoxelInventoryUI
extends Control
## The inventory screen (the owner, 21 Oct, Stage 2): Tab (or I) opens your backpack, E at a chest or a cabinet opens
## it above your backpack. Slots show each stack as a little cube in the item's colour with how many. Mouse like
## Minecraft's: left click picks a stack up / puts it down (or swaps), right click picks up half / puts down one,
## shift+click sends a stack straight across (backpack <-> the chest), a click outside the panels drops what's in your
## hand on the floor in front of you (right click: one), as cubes the vacuum can pick up again. Moves in and out of a
## chest go through VoxelStorages (co-op: through the host). Owned by the voxel session.

const SLOT := 54.0
const GAP := 6.0
const PAD := 16.0
const HEAD := 30.0
const BACK_COLS := 8
const C_PANEL := Color(0.09, 0.1, 0.13, 0.94)
const C_EDGE := Color(0.35, 0.38, 0.48)
const C_SLOT := Color(0.16, 0.17, 0.22)
const C_HOVER := Color(0.3, 0.32, 0.42)
const C_TEXT := Color(0.92, 0.93, 0.96)

var arena: Node
var inv: VoxelInventory
var storage: VoxelStorage = null
var cursor := {}                # the stack in your hand
var _panels := []               # [{title, inv, cols, rect: Rect2, store: bool}]
var _mouse := Vector2.ZERO
var _font: Font

func setup(arena_: Node, inv_: VoxelInventory) -> void:
	arena = arena_
	inv = inv_
	_font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	inv.changed.connect(queue_redraw)

func is_open() -> bool:
	return visible

## Shows the backpack, with a storage above it (null: the backpack alone).
func open(st: VoxelStorage = null) -> void:
	if storage and storage != st:
		_unhook()
	storage = st
	if storage:
		storage.inv.changed.connect(queue_redraw)
	visible = true
	_layout()
	queue_redraw()

func close() -> void:
	if not cursor.is_empty():
		var left := inv.add(cursor.id, int(cursor.n))     # (what's in your hand goes back in the backpack ...)
		if left > 0 and storage and not storage.locked:
			var back: Dictionary = arena.stash.add(storage, {"id": cursor.id, "n": left})    # (... or the chest open ...)
			left = int(back.get("n", 0)) if not back.is_empty() else 0
		if left > 0:
			arena.keep_or_drop({"id": cursor.id, "n": left})  # (... or the floor, cubes; anything else waits for room)
		cursor = {}
	_unhook()
	storage = null
	visible = false

func _unhook() -> void:
	if storage and storage.inv.changed.is_connected(queue_redraw):
		storage.inv.changed.disconnect(queue_redraw)

func _layout() -> void:
	_panels.clear()
	var vs := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var list := []
	if storage:
		list.append({"title": storage.title, "inv": storage.inv, "cols": storage.cols(), "store": true})
	list.append({"title": "Backpack", "inv": inv, "cols": BACK_COLS, "store": false})
	var h := 0.0
	for p in list:
		var cols: int = p.cols
		var rows := ceili(float((p.inv as VoxelInventory).size()) / cols)
		var w := PAD * 2.0 + cols * SLOT + (cols - 1) * GAP
		var ph := HEAD + PAD + rows * SLOT + (rows - 1) * GAP
		p.rect = Rect2(0, 0, w, ph)
		h += ph + 14.0
	var y := (vs.y - h) * 0.5 - 20.0
	for p in list:
		p.rect.position = Vector2((vs.x - p.rect.size.x) * 0.5, y)
		y += p.rect.size.y + 14.0
		_panels.append(p)

func _slot_rect(p: Dictionary, i: int) -> Rect2:
	var c := i % int(p.cols)
	var r := i / int(p.cols)
	return Rect2(p.rect.position + Vector2(PAD + c * (SLOT + GAP), HEAD + r * (SLOT + GAP)), Vector2(SLOT, SLOT))

## [panel index, slot] under a point on screen ([-1, -1]: none; [k, -1]: on panel k but not a slot).
func slot_at(pos: Vector2) -> Array:
	for k in _panels.size():
		var p: Dictionary = _panels[k]
		if not (p.rect as Rect2).has_point(pos):
			continue
		for i in (p.inv as VoxelInventory).size():
			if _slot_rect(p, i).has_point(pos):
				return [k, i]
		return [k, -1]
	return [-1, -1]

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_layout()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_mouse = e.position
		queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_mouse = e.position
		var at := slot_at(e.position)
		click(at[0], at[1], e.button_index, e.shift_pressed)
		accept_event()

## A click on slot i of panel k (k = -1: outside every panel: drop what's in the hand).
func click(k: int, i: int, button: int, shift := false) -> void:
	var right := button == MOUSE_BUTTON_RIGHT
	if k < 0:
		if not cursor.is_empty() and not VoxelItems.is_cubes(cursor.id):
			arena.say("Can't drop a %s: put it in a slot" % VoxelItems.name_of(cursor.id).to_lower(), 2.0)
			return
		if not cursor.is_empty():
			var n := 1 if right else int(cursor.n)
			arena.drop_stack({"id": cursor.id, "n": n})
			cursor.n = int(cursor.n) - n
			if int(cursor.n) <= 0:
				cursor = {}
		queue_redraw()
		return
	if i < 0:
		return
	var p: Dictionary = _panels[k]
	var store: bool = p.store
	var pinv: VoxelInventory = p.inv
	var s := pinv.at(i)
	if shift and not right:
		if s.is_empty():
			return
		if store:
			# the chest's stack into the backpack (a guest's comes from the host a moment later)
			var got: Dictionary = arena.stash.take(storage, i, -1, "inv")
			if not got.is_empty():
				var left := inv.add(got.id, int(got.n))
				if left > 0:
					arena.stash.put(storage, i, {"id": got.id, "n": left})
		elif storage:
			var st := inv.take_at(i)
			var back: Dictionary = arena.stash.add(storage, st)
			if not back.is_empty():
				inv.put_at(i, back)
		_tick("item_put")
		return
	if cursor.is_empty():
		if s.is_empty():
			return
		var n2 := ceili(int(s.n) / 2.0) if right else -1
		cursor = arena.stash.take(storage, i, n2, "cursor") if store else pinv.take_at(i, n2)
		_tick("item_pick")
	elif right:
		if not s.is_empty() and String(s.id) != String(cursor.id):
			return
		var one := {"id": cursor.id, "n": 1}
		var back2: Dictionary = arena.stash.put(storage, i, one) if store else pinv.put_at(i, one)
		if back2.is_empty():
			cursor.n = int(cursor.n) - 1
			if int(cursor.n) <= 0:
				cursor = {}
		_tick("item_put")
	else:
		cursor = arena.stash.put(storage, i, cursor) if store else pinv.put_at(i, cursor)
		_tick("item_put")
	queue_redraw()

## A stack the host gave (co-op guest): into the hand if it's free (or the same thing), else the backpack.
func receive_to_cursor(stack: Dictionary) -> Dictionary:
	if not visible:
		return stack
	if cursor.is_empty():
		cursor = stack.duplicate()
		queue_redraw()
		return {}
	if String(cursor.id) == String(stack.id):
		var room := VoxelItems.stack_max(cursor.id) - int(cursor.n)
		var k := mini(room, int(stack.n))
		cursor.n = int(cursor.n) + k
		queue_redraw()
		return {} if k == int(stack.n) else {"id": stack.id, "n": int(stack.n) - k}
	return stack

func _tick(name: String) -> void:
	if arena.sound:
		arena.sound.play(name, Vector3.INF, -6.0)

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not visible:
		return
	if _panels.is_empty():
		_layout()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	var hover := slot_at(_mouse)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	for k in _panels.size():
		var p: Dictionary = _panels[k]
		draw_style_box(sb, p.rect)
		var pinv: VoxelInventory = p.inv
		var head := String(p.title)
		if not p.store:
			head += "    %d / %d slots used" % [pinv.size() - _free(pinv), pinv.size()]
		draw_string(_font, p.rect.position + Vector2(PAD, 22), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, C_TEXT)
		for i in pinv.size():
			var r := _slot_rect(p, i)
			draw_rect(r, C_HOVER if (hover[0] == k and hover[1] == i) else C_SLOT)
			var s := pinv.at(i)
			if not s.is_empty():
				_draw_stack(r, s)
	if not cursor.is_empty():
		_draw_stack(Rect2(_mouse - Vector2(SLOT, SLOT) * 0.45, Vector2(SLOT, SLOT) * 0.9), cursor)
	elif hover[0] >= 0 and hover[1] >= 0:
		var s2 := (_panels[hover[0]].inv as VoxelInventory).at(hover[1])
		if not s2.is_empty():
			_tooltip(s2)
	var hint := "left: pick up / put down     right: half / one     shift+click: move across     click outside: drop     Tab, E or Esc: close"
	var last: Dictionary = _panels[_panels.size() - 1]
	var hp: Vector2 = last.rect.position + Vector2(0, last.rect.size.y + 26)
	draw_string(_font, Vector2(size.x * 0.5 - _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x * 0.5, hp.y), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.82, 0.88))

func _free(pinv: VoxelInventory) -> int:
	var n := 0
	for i in pinv.size():
		if pinv.is_empty_at(i):
			n += 1
	return n

# a stack: a little cube in the item's colour (three shaded faces), the count bottom right
func _draw_stack(r: Rect2, s: Dictionary) -> void:
	var c := VoxelItems.colour(s.id)
	var m := r.get_center() + Vector2(0, -2)
	var w := r.size.x * 0.3
	var hgt := w * 0.58
	var top := PackedVector2Array([m + Vector2(0, -hgt * 1.6), m + Vector2(w, -hgt), m + Vector2(0, -hgt * 0.4), m + Vector2(-w, -hgt)])
	var left := PackedVector2Array([m + Vector2(-w, -hgt), m + Vector2(0, -hgt * 0.4), m + Vector2(0, hgt * 1.0), m + Vector2(-w, hgt * 0.4)])
	var right := PackedVector2Array([m + Vector2(0, -hgt * 0.4), m + Vector2(w, -hgt), m + Vector2(w, hgt * 0.4), m + Vector2(0, hgt * 1.0)])
	draw_colored_polygon(top, c.lightened(0.25))
	draw_colored_polygon(left, c)
	draw_colored_polygon(right, c.darkened(0.3))
	var t := str(int(s.n))
	var tp := r.position + Vector2(r.size.x - 4 - _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, r.size.y - 5)
	draw_string_outline(_font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
	draw_string(_font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT)

func _tooltip(s: Dictionary) -> void:
	var l1 := "%s  x%d" % [VoxelItems.name_of(s.id), int(s.n)]
	var l2 := VoxelItems.desc(s.id)
	var w := maxf(_font.get_string_size(l1, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, _font.get_string_size(l2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x) + 20
	var r := Rect2(_mouse + Vector2(16, 14), Vector2(w, 50))
	if r.end.x > size.x:
		r.position.x = _mouse.x - w - 10
	draw_rect(r, Color(0.04, 0.04, 0.06, 0.95))
	draw_rect(r, C_EDGE, false, 1.0)
	draw_string(_font, r.position + Vector2(10, 20), l1, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_TEXT)
	draw_string(_font, r.position + Vector2(10, 40), l2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.77, 0.82))
