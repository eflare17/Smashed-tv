class_name VoxelWeaponBar
extends Control
## The weapon bar (the owner, 20 Oct): a slot for each weapon along the bottom of the screen, its number, a little
## drawing of it and its name; the one out is lit and stands taller, a slot's bottom edge fills while its weapon
## cools down, the vacuum's shows how many cubes it has taken. Above the bar, what the two mouse buttons do with the one
## out. Drawn, no textures. Owned by the voxel session.

const SLOT_W := 104.0
const SLOT_H := 64.0
const GAP := 8.0
const LIFT := 8.0               # the one out stands this much taller
const HINT_H := 24.0

var loadout: VoxelLoadout
var arena: Node
var _font: Font

func setup(loadout_: VoxelLoadout, arena_: Node) -> void:
	loadout = loadout_
	arena = arena_
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := loadout.slots.size()
	var w := n * SLOT_W + (n - 1) * GAP
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -w / 2.0
	offset_right = w / 2.0
	offset_bottom = -36.0
	offset_top = offset_bottom - (SLOT_H + LIFT + HINT_H)

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if loadout == null:
		return
	var n := loadout.slots.size()
	var cur: Dictionary = loadout.slot()
	var hint := "Left: %s     Right: %s" % [cur.left, cur.right]
	_text(Vector2(0, 16), hint, 15, Color(1, 1, 1, 0.92), size.x, HORIZONTAL_ALIGNMENT_CENTER)
	for i in n:
		var s: Dictionary = loadout.slots[i]
		var sel := i == loadout.current
		var h := SLOT_H + (LIFT if sel else 0.0)
		var r := Rect2(i * (SLOT_W + GAP), size.y - h, SLOT_W, h)
		var k := 1.0 - loadout.switch_frac() if sel else 0.0
		draw_rect(r, Color(0.05, 0.06, 0.08, 0.72 if sel else 0.5))
		var edge := Color(0.45, 1.0, 0.6).lerp(Color(1, 1, 1), 0.3 * (1.0 - k)) if sel else Color(1, 1, 1, 0.25)
		draw_rect(r, edge, false, 3.0 if sel else 1.0)
		_text(r.position + Vector2(7, 17), str(i + 1), 15, Color(1, 0.9, 0.4) if sel else Color(1, 1, 1, 0.6), 20.0, HORIZONTAL_ALIGNMENT_LEFT)
		_icon(String(s.id), Rect2(r.position + Vector2(26, 6), Vector2(r.size.x - 34, r.size.y - 30)), Color(1, 1, 1, 0.95 if sel else 0.55))
		var label := String(s.name)
		if s.id == "vacuum" and arena:
			var got: Dictionary = arena.debris.got
			label += "  %d" % (int(got.blocks) + int(got.meat) + int(got.bone) + int(got.brain))
		_text(Vector2(r.position.x, r.end.y - 8), label, 13, Color(1, 1, 1, 0.95 if sel else 0.6), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		# cooling down: the bottom edge fills back up
		var c: float = arena.slot_cooling(String(s.id)) if arena else 0.0
		if c > 0.0:
			draw_rect(Rect2(r.position.x + 3, r.end.y - 4, (r.size.x - 6) * (1.0 - c), 2), Color(1.0, 0.7, 0.3, 0.9))

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
		"blaster":
			_box(o, u, Rect2(2, 1.2, 5.5, 1.6), col)
			_box(o, u, Rect2(7.5, 1.6, 1.8, 0.8), col)
			_box(o, u, Rect2(2.6, 2.8, 1.3, 1.8), dim)
			_box(o, u, Rect2(4.0, 1.5, 1.0, 0.5), Color(0.4, 0.9, 1.0, col.a))
		"shotgun":
			_box(o, u, Rect2(0.2, 2.0, 2.4, 1.4), dim)
			_box(o, u, Rect2(2.6, 1.7, 2.4, 1.2), col)
			_box(o, u, Rect2(5.0, 1.75, 4.8, 0.55), col)
			_box(o, u, Rect2(5.0, 2.35, 4.4, 0.45), dim)
		"sword":
			_box(o, u, Rect2(0.4, 2.15, 1.6, 0.7), Color(0.55, 0.32, 0.18, col.a))
			_box(o, u, Rect2(2.0, 1.2, 0.5, 2.6), Color(0.9, 0.75, 0.3, col.a))
			_box(o, u, Rect2(2.5, 2.0, 6.6, 1.0), col)
			_box(o, u, Rect2(9.1, 2.2, 0.6, 0.6), col)
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
