class_name DsGauge
extends Control
## The level while you drive a Dig Site machine (the owner, 8 Nov: "a level type thing ... so you can see what angle it
## is"): two dials like a 4x4's inclinometer, the machine side on tipped by its nose up or down, and from behind
## tipped by its lean, each with its degrees. White while it's fine, amber as it nears what the machine will climb
## (DsMachine.max_climb), red past that; "TOO STEEP" when it's stopped for it. Top right, under the buttons.
## Owned by the voxel session.

const R := 46.0                 # a dial's radius (px)

var machine: DsMachine

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -250
	offset_right = -16
	offset_top = 150
	offset_bottom = 315

func _process(_dt: float) -> void:
	visible = machine != null
	if visible:
		queue_redraw()

func _col(a: float) -> Color:
	var k := absf(a) / maxf(0.01, machine.max_climb)
	if k >= 1.0:
		return Color("#ff4a3a")
	if k >= 0.7:
		return Color("#ffb42a")
	return Color("#f2f2f2")

func _draw() -> void:
	if machine == null:
		return
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	_dial(Vector2(size.x * 0.27, size.y * 0.5), machine.pitch, true, "NOSE", font)
	_dial(Vector2(size.x * 0.73, size.y * 0.5), machine.roll, false, "LEAN", font)
	if machine.blocked.begins_with("Too steep") or machine.blocked.begins_with("Too big"):
		var w := "TOO STEEP"
		draw_string_outline(font, Vector2(0, -6), w, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 6, Color.BLACK)
		draw_string(font, Vector2(0, -6), w, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color("#ff4a3a"))

# a dial: its face, level marks, the limit marked either side, the machine tipped by a (side on: nose to the right)
func _dial(c: Vector2, a: float, side: bool, word: String, font: Font) -> void:
	var col := _col(a)
	draw_circle(c, R, Color(0.08, 0.09, 0.1, 0.9))
	draw_arc(c, R, 0.0, TAU, 40, Color(0.6, 0.6, 0.6), 2.0)
	# the level line, and where the machine's limit is either way
	draw_line(c - Vector2(R - 6, 0), c + Vector2(R - 6, 0), Color(0.45, 0.45, 0.45), 1.0)
	for s in [-1.0, 1.0]:
		var lim: float = machine.max_climb * s
		var p := Vector2(cos(-lim), sin(-lim)) * (R - 3)
		draw_line(c + p * 0.82, c + p, Color("#ff4a3a"), 3.0)
		draw_line(c - p * 0.82, c - p, Color("#ff4a3a"), 3.0)
	# the machine, tipped: side on a body and two wheels, from behind a body on two tracks
	var t := Transform2D(-a if side else a, c)
	var body := PackedVector2Array()
	if side:
		body = PackedVector2Array([Vector2(-26, -2), Vector2(22, -2), Vector2(26, -12), Vector2(6, -12), Vector2(2, -26), Vector2(-18, -26), Vector2(-26, -12)])
	else:
		body = PackedVector2Array([Vector2(-18, -4), Vector2(18, -4), Vector2(14, -24), Vector2(-14, -24)])
	var pts := PackedVector2Array()
	for p in body:
		pts.append(t * p)
	draw_colored_polygon(pts, col)
	if side:
		for x in [-16.0, 16.0]:
			draw_circle(t * Vector2(x, 2), 7.0, Color(0.15, 0.15, 0.15))
	else:
		for x in [-14.0, 14.0]:
			var tr := PackedVector2Array([t * Vector2(x - 6, -4), t * Vector2(x + 6, -4), t * Vector2(x + 6, 6), t * Vector2(x - 6, 6)])
			draw_colored_polygon(tr, Color(0.15, 0.15, 0.15))
	# its degrees, and which dial it is
	var deg := "%+d°" % roundi(rad_to_deg(a))
	draw_string_outline(font, c + Vector2(-R, R + 18), deg, HORIZONTAL_ALIGNMENT_CENTER, R * 2.0, 20, 5, Color.BLACK)
	draw_string(font, c + Vector2(-R, R + 18), deg, HORIZONTAL_ALIGNMENT_CENTER, R * 2.0, 20, col)
	draw_string(font, c + Vector2(-R, -R - 5), word, HORIZONTAL_ALIGNMENT_CENTER, R * 2.0, 13, Color(0.8, 0.8, 0.8))
