class_name VoxelWeaponBar
extends Control
## The weapon bar (the owner, 20 Oct): the weapons along the bottom of the screen in their groups, as in Half-Life:
## each group under its key (1 melee, 2 guns, 3 special, 4 explosives, 5 the vacuum), a little drawing for each weapon
## in it; the one out is lit, a slot's bottom edge fills while its weapon cools down or reloads, a gun's slot shows its
## rounds, the vacuum's how many cubes it has taken. Above the bar: the name of the one out and what the two mouse
## buttons do with it. Drawn, no textures. Owned by the voxel session.

const SLOT_W := 62.0
const SLOT_H := 44.0
const PAD := 4.0                # between slots in a group
const GROUP_GAP := 14.0         # between groups
const HEAD_H := 16.0            # the group's key and name over it
const HINT_H := 24.0

var loadout: VoxelLoadout
var arena: Node
var _font: Font

func setup(loadout_: VoxelLoadout, arena_: Node) -> void:
	loadout = loadout_
	arena = arena_
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := 0.0
	for g in _groups():
		w += _group_w(g) + GROUP_GAP
	w -= GROUP_GAP
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -w / 2.0
	offset_right = w / 2.0
	offset_bottom = -36.0
	offset_top = offset_bottom - (SLOT_H + HEAD_H + HINT_H)

func _process(_dt: float) -> void:
	queue_redraw()

# the groups there are, in key order: [[group, [slot indices]], ...]
func _groups() -> Array:
	var by := {}
	for i in loadout.slots.size():
		var g := int(loadout.slots[i].group)
		if not by.has(g):
			by[g] = []
		by[g].append(i)
	var keys := by.keys()
	keys.sort()
	return keys.map(func(g): return [g, by[g]])

func _group_w(g: Array) -> float:
	var n: int = (g[1] as Array).size()
	return n * SLOT_W + (n - 1) * PAD

func _draw() -> void:
	if loadout == null:
		return
	var cur: Dictionary = loadout.slot()
	var hint := "%s      Left: %s      Right: %s" % [cur.name, cur.left, cur.right]
	_text(Vector2(0, 16), hint, 15, Color(1, 1, 1, 0.92), size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var x := 0.0
	var top := size.y - SLOT_H - HEAD_H
	for gr in _groups():
		var g: int = gr[0]
		var mine: Array = gr[1]
		var gw := _group_w(gr)
		var here := loadout.group() == g
		_text(Vector2(x, top + 12), "%d  %s" % [g, VoxelLoadout.GROUPS.get(g, "")], 12,
			Color(1, 0.9, 0.4) if here else Color(1, 1, 1, 0.55), gw, HORIZONTAL_ALIGNMENT_LEFT)
		for j in mine.size():
			var i: int = mine[j]
			var s: Dictionary = loadout.slots[i]
			var sel := i == loadout.current
			var r := Rect2(x + j * (SLOT_W + PAD), top + HEAD_H, SLOT_W, SLOT_H)
			var k := 1.0 - loadout.switch_frac() if sel else 0.0
			draw_rect(r, Color(0.05, 0.06, 0.08, 0.78 if sel else 0.5))
			var edge := Color(0.45, 1.0, 0.6).lerp(Color(1, 1, 1), 0.3 * (1.0 - k)) if sel else Color(1, 1, 1, 0.22)
			draw_rect(r, edge, false, 3.0 if sel else 1.0)
			_icon(String(s.id), Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 16)), Color(1, 1, 1, 0.95 if sel else 0.55))
			var label := ""
			if s.id == "vacuum" and arena:
				var got: Dictionary = arena.debris.got
				label = str(int(got.blocks) + int(got.meat) + int(got.bone) + int(got.brain))
			elif arena and arena.melee.has(s.id):
				label = arena.melee[s.id].bar_text()
			if label != "":
				_text(Vector2(r.position.x, r.end.y - 4), label, 11, Color(1, 1, 1, 0.9 if sel else 0.6), r.size.x - 4, HORIZONTAL_ALIGNMENT_RIGHT)
			# cooling down or reloading: the bottom edge fills back up
			var c: float = arena.slot_cooling(String(s.id)) if arena else 0.0
			if c > 0.0:
				draw_rect(Rect2(r.position.x + 3, r.end.y - 3, (r.size.x - 6) * (1.0 - c), 2), Color(1.0, 0.7, 0.3, 0.9))
		x += gw + GROUP_GAP

func _text(at: Vector2, t: String, fs: int, col: Color, w: float, align: HorizontalAlignment) -> void:
	draw_string_outline(_font, at, t, align, w, fs, 4, Color(0, 0, 0, 0.85))
	draw_string(_font, at, t, align, w, fs, col)

# a little drawing of each, in r (left to right: grip to tip)
func _icon(weapon: String, r: Rect2, col: Color) -> void:
	if arena and arena.melee.has(weapon):
		arena.melee[weapon].draw_icon(self, r, col)
		return
	var u := r.size / Vector2(10, 5)
	var o := r.position
	var dim := Color(col.r * 0.55, col.g * 0.55, col.b * 0.6, col.a)
	match weapon:
		"vacuum":
			_box(o, u, Rect2(1.0, 1.4, 5.0, 2.0), Color(0.45, 0.85, 0.6, col.a))
			_box(o, u, Rect2(6.0, 1.0, 1.2, 2.8), dim)
			_box(o, u, Rect2(7.2, 1.3, 0.5, 2.2), Color(0.5, 1.0, 0.7, col.a))
			_box(o, u, Rect2(2.0, 0.4, 2.5, 1.0), Color(0.45, 0.85, 0.6, col.a))
			_box(o, u, Rect2(2.4, 3.4, 1.0, 1.4), dim)
		_:
			_box(o, u, Rect2(1, 1.5, 8, 2), col)

func _box(o: Vector2, u: Vector2, r: Rect2, col: Color) -> void:
	draw_rect(Rect2(o + r.position * u, r.size * u), col)
