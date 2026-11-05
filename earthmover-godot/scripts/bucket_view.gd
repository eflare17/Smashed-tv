class_name BucketView
extends Control
## A small live picture of the machine from the side: the arm, the bucket at its true angle, and the real ground under it.
## It's there because from the driver's view the machine itself often hides the bucket.

const SKY := Color(0.12, 0.14, 0.18, 0.88)
const DIRT := Color("#7d4329")
const BODY := Color("#d8a400")
const ARM := Color("#ffd23f")
const STEEL := Color("#e8e8e8")
const SOIL := Color("#6b4423")
const DUST := Color("#c9c6bb")
const TIPPING := Color("#ff9a4a")
const GOOD := Color("#a8f07a")
const LEVEL_LINE := Color(1.0, 1.0, 1.0, 0.45)
const INK := Color.BLACK
const NEAR_TRUCK := 16.0        # m: further off than this it isn't what's being lined up with

var machine: Machine
var truck: Truck                # to line up with, when there's one on site

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if machine == null:
		return
	var v: Dictionary = machine.side_view()
	if v.is_empty():
		return
	var high: float = v["high"]
	var left: float = v["left"]
	var span: float = high - float(v["low"])
	# The words get their own strip along the top, so a raised bucket is never hidden behind them.
	var strip := size.y * 0.14
	var scale_m: float = (size.y - strip) / span
	# The picture rides up or down so the bucket never leaves it.
	var stays: Vector2 = v["pin"]
	var room: float = float(v["reach"]) * 1.2
	high = maxf(high, stays.y + room)
	high = minf(high, stays.y - room + span)
	var to_px := func(p: Vector2) -> Vector2:
		return Vector2((p.x - left) * scale_m, strip + (high - p.y) * scale_m)
	var line := maxf(size.y * 0.012, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), SKY)

	# The real ground along the way the arm points, heaps and holes included.
	var steps := 28
	var last := Vector2.ZERO
	for k in steps + 1:
		var x: float = left + (size.x / scale_m) * k / steps
		var p: Vector2 = to_px.call(Vector2(x, machine.side_ground(x)))
		if k > 0:
			var base := maxf(size.y, maxf(p.y, last.y)) + 1.0
			draw_colored_polygon(PackedVector2Array([last, p, Vector2(p.x, base), Vector2(last.x, base)]), DIRT)
			draw_line(last, p, INK, line)
		last = p

	var lining := _truck_word(v)
	if truck != null and v.has("pour"):
		_draw_truck(to_px, lining, line)

	for r: Rect2 in v["body"]:
		var box := Rect2(to_px.call(Vector2(r.position.x, r.end.y)), r.size * scale_m)
		draw_rect(box, BODY)
		draw_rect(box, INK, false, line * 0.7)
	var joints: Array = v["joints"]
	for k in joints.size() - 1:
		var a: Vector2 = to_px.call(joints[k])
		var b: Vector2 = to_px.call(joints[k + 1])
		draw_line(a, b, INK, line * 3.0)
		draw_line(a, b, ARM, line * 1.6)

	# A level line from the pin, to read the bucket's angle against.
	var pin: Vector2 = v["pin"]
	var reach: float = v["reach"]
	var pin_px: Vector2 = to_px.call(pin)
	var level_long: float = v.get("level_long", reach * 1.5)
	draw_dashed_line(pin_px, pin_px + Vector2(level_long * scale_m, 0.0), LEVEL_LINE, maxf(line * 0.5, 1.0), line * 2.0)

	var turn: float = v["turn"]
	var outline := PackedVector2Array()
	for s: Vector2 in v["shape"]:
		outline.append(to_px.call(pin + s.rotated(turn)))
	var pours: bool = v["pours"]
	draw_colored_polygon(outline, TIPPING if pours else ARM)
	var f: float = v["fill"]
	if f > 0.02:
		var from: Vector2 = v["fill_from"]
		var grown := minf(0.35 + 0.75 * f, 1.0)
		var soil := PackedVector2Array()
		for s: Vector2 in v["shape"]:
			soil.append(to_px.call(pin + (from + (s - from) * grown).rotated(turn)))
		draw_colored_polygon(soil, DUST if v["dust"] else SOIL)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, INK, line)
	# The cutting edge, so which way it faces can't be missed.
	var edge: Vector2 = to_px.call(pin + Vector2(reach, 0.0).rotated(turn))
	draw_circle(edge, line * 2.2, INK)
	draw_circle(edge, line * 1.4, STEEL)

	draw_rect(Rect2(0.0, 0.0, size.x, strip), Color(0.05, 0.05, 0.05))
	var font := ThemeDB.fallback_font
	var font_size := int(strip * 0.68)
	var down: float = v["down"]
	var word := "ON GROUND"
	var colour := Color("#ffd23f")
	var near: float = v.get("near", 0.03)
	if down > near:
		word = "IN DIRT %.2f m" % down
		colour = TIPPING
	elif down < -near:
		word = "UP %.2f m" % -down
		colour = GOOD
	var gap := size.y * 0.02
	var base_y := strip * 0.76
	_say(font, Vector2(gap, base_y), word, font_size, colour)
	var angle: float = v["angle"]
	var said := "%d°" % roundi(angle)
	if pours:
		said += " POURS"
	var wide := font.get_string_size(said, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_say(font, Vector2(size.x - wide - gap, base_y), said, font_size, TIPPING if pours else Color.WHITE)
	if not lining.is_empty():
		_say(font, Vector2(gap, size.y - gap * 1.5), lining["word"], font_size, lining["colour"])

## What the driver needs to do to get the load over the tray: empty if there's no truck about.
func _truck_word(v: Dictionary) -> Dictionary:
	if truck == null or not v.has("pour"):
		return {}
	if truck.spot.distance_to(machine.spot) > NEAR_TRUCK:
		return {}
	var pour: Vector2 = v["pour"]
	var at := machine.side_world(pour)
	var corners: PackedVector3Array = truck.side_shapes()["floor"]
	if truck.over_tray(at):
		if at.y < truck.tray_rim() + 0.1:
			return {"word": "OVER THE TRUCK: RAISE", "colour": Color("#ffd23f"), "crosses": true}
		return {"word": "OVER THE TRUCK: DUMP" if v["has_load"] else "OVER THE TRUCK", "colour": GOOD, "crosses": true, "over": true}
	# Where the line of the arm runs across the tray, if it does.
	var from := INF
	var to := -INF
	var nearest := INF
	for k in corners.size():
		var a := machine.side_point(corners[k])
		var b := machine.side_point(corners[(k + 1) % corners.size()])
		if absf(a.z) < absf(nearest):
			nearest = a.z
		if signf(a.z) != signf(b.z):
			var along := lerpf(a.x, b.x, a.z / (a.z - b.z))
			from = minf(from, along)
			to = maxf(to, along)
	if from > to:
		return {"word": "%s %s %.1f m" % [v["turn_word"], "RIGHT" if nearest > 0.0 else "LEFT", absf(nearest)], "colour": Color.WHITE, "crosses": false}
	if pour.x < from:
		return {"word": "%s %.1f m" % [v["out_word"], from - pour.x], "colour": Color.WHITE, "crosses": true}
	if pour.x > to:
		return {"word": "%s %.1f m" % [v["in_word"], pour.x - to], "colour": Color.WHITE, "crosses": true}
	return {"word": "NEARLY OVER THE TRUCK", "colour": Color("#ffd23f"), "crosses": true}

## The truck as seen from the side, whichever way it's parked. Faint when the arm isn't lined up with it.
func _draw_truck(to_px: Callable, lining: Dictionary, line: float) -> void:
	if lining.is_empty():
		return
	var shapes: Dictionary = truck.side_shapes()
	var strength := 1.0 if lining["crosses"] else 0.4
	var fade := func(c: Color) -> Color:
		return Color(c.r, c.g, c.b, strength)
	_draw_hull(shapes["chassis"], to_px, fade.call(Color("#333333")), line * 0.0)
	_draw_hull(shapes["cab"], to_px, fade.call(Color("#d9482b")), line * 0.7)
	_draw_hull(shapes["tray"], to_px, fade.call(Color("#7a2a18")), line * 0.7, GOOD if lining.get("over", false) else INK)
	if truck.tray_mm > 0:
		_draw_hull(shapes["soil"], to_px, fade.call(SOIL), 0.0)

func _draw_hull(corners: PackedVector3Array, to_px: Callable, colour: Color, edge: float, edge_colour := INK) -> void:
	var points := PackedVector2Array()
	for w: Vector3 in corners:
		var p := machine.side_point(w)
		points.append(to_px.call(Vector2(p.x, p.y)))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() < 4:
		return
	draw_colored_polygon(hull.slice(0, hull.size() - 1), colour)
	if edge > 0.0:
		draw_polyline(hull, edge_colour, edge)

func _say(font: Font, at: Vector2, word: String, font_size: int, colour: Color) -> void:
	draw_string_outline(font, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 6, INK)
	draw_string(font, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, colour)
