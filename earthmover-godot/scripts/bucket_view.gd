class_name BucketView
extends Control
## A small live picture of the machine from the side: the arm, the bucket at its true angle, and the real ground under it.
## It's there because from the driver's view the machine itself often hides the bucket.

const SKY := Color(0.12, 0.14, 0.18, 0.88)
var DIRT := Color("#7d4329")
var BODY := Color("#d8a400")
var ARM := Color("#ffd23f")
const STEEL := Color("#e8e8e8")
var SOIL := Color("#6b4423")
const DUST := Color("#c9c6bb")
const TIPPING := Color("#ff9a4a")
const GOOD := Color("#a8f07a")
const LEVEL_LINE := Color(1.0, 1.0, 1.0, 0.45)
const INK := Color.BLACK
const NEAR_TRUCK := 16.0        # m: further off than this it isn't what's being lined up with

var machine: Machine
var truck: Truck                # to line up with, when there's one on site
var water_y := NAN              # m: the flood's level in the world, for the trench picture, or NAN with none
var _below := 0.9               # m below the ground the trench picture goes down to, eased toward what's needed

const SLOT := Color(0.07, 0.05, 0.04)
const WATER := Color(0.3, 0.55, 0.95, 0.6)
const UPHILL := Color("#ff4a3a")
const AIM := Color(1.0, 1.0, 1.0, 0.85)
const TRENCH_BEHIND := 7.0      # m of trench shown behind the chain
const TRENCH_AHEAD := 2.0       # and ahead of it
const TRENCH_ABOVE := 0.35      # m of sky over the ground at the chain
const TRENCH_BELOW := 1.85      # m below it at most, a bit more than the chain reaches
const TRENCH_BELOW_LEAST := 0.9 # and at least, so a shallow trench is drawn big
const UPHILL_SLACK := 0.05      # m the floor can rise before it says so: the chain leaves bumps smaller than this

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if machine == null or size.y < 8.0:
		return
	if machine is Loader and (machine as Loader).trencher_on:
		_draw_trench(machine as Loader)
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

## With the trencher on: the trench from the side, along the way the machine faces. The ground, the slot cut so far with its floor
## (red where it goes uphill, so the water would stop there), the floor to aim for, dashed, and the chain going down into it.
func _draw_trench(l: Loader) -> void:
	var t := trench_line(l)
	var f := l.forward()
	var chain := l.spot + f * Loader.CHAIN_X
	var at_chain: float = t["at_chain"]
	var top: float = at_chain + TRENCH_ABOVE
	var strip := size.y * 0.14
	var tall := size.y - strip * 2.0
	var span := TRENCH_BEHIND + TRENCH_AHEAD
	var line := maxf(size.y * 0.012, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), SKY)
	var xs: Array[float] = t["xs"]
	var tops: Array[float] = t["tops"]
	var floors: Array[float] = t["floors"]
	var cut: Array[bool] = t["cut"]
	var uphill: Array[bool] = t["uphill"]
	var n := xs.size()
	# Deep enough for the chain, the aim and the floor shown, and no deeper, so a shallow trench isn't a thin line.
	var aim_here := l.aim_floor(chain)
	var deepest := maxf(l.chain_depth, l.aim_depth)
	for k in n:
		if cut[k]:
			deepest = maxf(deepest, at_chain - floors[k])
	_below = lerpf(_below, clampf(deepest + 0.35, TRENCH_BELOW_LEAST, TRENCH_BELOW), 0.08)
	var to_px := func(x: float, y: float) -> Vector2:
		return Vector2((x + TRENCH_BEHIND) / span * size.x, strip + clampf((top - y) / (TRENCH_ABOVE + _below), -0.05, 1.05) * tall)
	var bottom := size.y - strip
	for k in range(1, n):
		var a: Vector2 = to_px.call(xs[k - 1], tops[k - 1])
		var b: Vector2 = to_px.call(xs[k], tops[k])
		draw_colored_polygon(PackedVector2Array([a, b, Vector2(b.x, bottom), Vector2(a.x, bottom)]), DIRT)
	for k in range(1, n):
		if cut[k - 1] and cut[k]:
			draw_colored_polygon(PackedVector2Array([to_px.call(xs[k - 1], tops[k - 1]), to_px.call(xs[k], tops[k]),
				to_px.call(xs[k], floors[k]), to_px.call(xs[k - 1], floors[k - 1])]), SLOT)
	# The flood, where the ground's under it, down into the slot there.
	if not is_nan(water_y):
		for k in range(1, n):
			var low_a: float = floors[k - 1] if cut[k - 1] else tops[k - 1]
			var low_b: float = floors[k] if cut[k] else tops[k]
			if tops[k - 1] < water_y and tops[k] < water_y:
				draw_colored_polygon(PackedVector2Array([to_px.call(xs[k - 1], water_y), to_px.call(xs[k], water_y),
					to_px.call(xs[k], minf(low_b, water_y)), to_px.call(xs[k - 1], minf(low_a, water_y))]), WATER)
	for k in range(1, n):
		draw_line(to_px.call(xs[k - 1], tops[k - 1]), to_px.call(xs[k], tops[k]), INK, line)
	for k in range(1, n):
		if cut[k - 1] and cut[k]:
			var bad := uphill[k] or uphill[k - 1]
			draw_line(to_px.call(xs[k - 1], floors[k - 1]), to_px.call(xs[k], floors[k]), UPHILL if bad else GOOD, line * (2.0 if bad else 1.4))

	# The floor to aim for, from where this cut began on to a bit ahead of the chain.
	if not is_nan(aim_here):
		var from_x := clampf((l.aim_from() - chain).dot(f), -TRENCH_BEHIND, 0.0)
		var a: Vector2 = to_px.call(from_x, l.aim_floor(chain + f * from_x))
		var b: Vector2 = to_px.call(TRENCH_AHEAD, l.aim_floor(chain + f * TRENCH_AHEAD))
		draw_dashed_line(a, b, AIM, maxf(line * 0.8, 1.5), line * 3.0)

	# The machine on the ground behind the chain, and the chain going down.
	var body_a: Vector2 = to_px.call(-1.6, at_chain + 0.32)
	var body_b: Vector2 = to_px.call(0.05, at_chain)
	var body := Rect2(body_a, body_b - body_a)
	draw_rect(body, BODY)
	draw_rect(body, INK, false, line * 0.7)
	var teeth_y := at_chain - l.chain_depth
	var short := _short(l)
	var chain_top: Vector2 = to_px.call(0.25, at_chain + 0.25)
	var chain_end: Vector2 = to_px.call(0.0, teeth_y)
	draw_line(chain_top, chain_end, INK, line * 3.4)
	draw_line(chain_top, chain_end, TIPPING if short else ARM, line * 2.0)
	draw_circle(chain_end, line * 2.4, INK)
	draw_circle(chain_end, line * 1.5, STEEL)
	# Where the teeth ought to be, beside them.
	if not is_nan(aim_here):
		var goal: Vector2 = to_px.call(0.0, aim_here)
		draw_line(goal + Vector2(-line * 5.0, 0.0), goal + Vector2(line * 5.0, 0.0), AIM, line * 1.2)
		if short:
			_draw_down_arrow(Vector2(chain_end.x + line * 9.0, chain_end.y), goal.y, line)

	# Words: how deep and how deep to go along the top; what to do along the bottom.
	draw_rect(Rect2(0.0, 0.0, size.x, strip), Color(0.05, 0.05, 0.05))
	draw_rect(Rect2(0.0, size.y - strip, size.x, strip), Color(0.05, 0.05, 0.05))
	var font := ThemeDB.fallback_font
	var font_size := int(strip * 0.68)
	var gap := size.y * 0.02
	var base_y := strip * 0.76
	_say(font, Vector2(gap, base_y), "DEPTH %.2f m" % l.chain_depth if l.chain_depth > 0.02 else "CHAIN UP", font_size, Color.WHITE)
	if not is_nan(aim_here):
		var aim_word := "AIM %.2f m" % l.aim_depth
		var wide := font.get_string_size(aim_word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		_say(font, Vector2(size.x - wide - gap, base_y), aim_word, font_size, AIM)
	var said := trench_word(l, t["any_uphill"])
	_say_fit(font, Vector2(gap, size.y - strip * 0.24), said[0], font_size, size.x - gap * 2.0, said[1])

## Whether the chain's short of the depth it ought to be at, GRADE not doing it.
func _short(l: Loader) -> bool:
	return l.aim_depth > 0.0 and l.chain_depth < l.aim_depth - 0.04 and not l.grade_on

## What to do, along the bottom of the trench picture: the words and their colour.
func trench_word(l: Loader, any_uphill: bool) -> Array:
	var short := _short(l)
	if any_uphill and (l.chain_depth <= 0.02 or not short) and not l.grade_on:
		return ["RED GOES UPHILL: DIG IT DEEPER", UPHILL]
	if l.grade_on:
		return ["GRADE ON: JUST DRIVE", GOOD]
	if short:
		return ["GO DEEPER %.2f m: LOWER" % (l.aim_depth - l.chain_depth), UPHILL]
	if l.chain_depth > 0.02 and l.aim_depth > 0.0 and l.chain_depth > l.aim_depth + Loader.TOO_DEEP:
		return ["TOO DEEP %.2f m: RAISE" % (l.chain_depth - l.aim_depth), Color("#ffd23f")]
	if l.chain_depth > 0.02 and l.aim_depth > 0.0:
		return ["ON THE AIM: KEEP GOING", GOOD]
	return ["LOWER IT TO DIG", Color("#ffd23f")]

## The trench along the way the machine faces, every quarter metre from behind it to ahead: the ground beside the slot, the
## slot's floor, whether it's been cut there, and whether the floor goes uphill there on the way to the drain.
func trench_line(l: Loader) -> Dictionary:
	var sim := l.sim
	var f := l.forward()
	var side := Vector2(sin(l.angle), cos(l.angle))
	var chain := l.spot + f * Loader.CHAIN_X
	var ground := func(p: Vector2) -> float:
		return minf(sim.height_at(p + side * 0.65), sim.height_at(p - side * 0.65))
	var step := 0.25
	var xs: Array[float] = []
	var tops: Array[float] = []
	var floors: Array[float] = []
	var cut: Array[bool] = []
	var x := -TRENCH_BEHIND
	while x <= TRENCH_AHEAD + 0.001:
		var p := chain + f * x
		var g: float = ground.call(p)
		var fl := minf(sim.firm_at(p), g)
		xs.append(x)
		tops.append(g)
		floors.append(fl)
		cut.append(g - fl > 0.08)
		x += step
	var n := xs.size()
	# The water runs toward the drain: any floor higher than the floor before it, on the way there, stops it.
	var forward_flow := true
	if l.grade_toward != Vector2.INF:
		forward_flow = l.grade_toward.distance_to(chain + f * TRENCH_AHEAD) < l.grade_toward.distance_to(chain - f * TRENCH_BEHIND)
	var uphill: Array[bool] = []
	uphill.resize(n)
	uphill.fill(false)
	var lowest := INF
	var any_uphill := false
	for m in n:
		var k := m if forward_flow else n - 1 - m
		# The face the chain's cutting now always rises to the ground in front of it: that's not the trench yet.
		if l.chain_depth > 0.02 and xs[k] > -0.3:
			continue
		if not cut[k]:
			lowest = INF
			continue
		if floors[k] > lowest + UPHILL_SLACK:
			uphill[k] = true
			any_uphill = true
		lowest = minf(lowest, floors[k])
	return {"xs": xs, "tops": tops, "floors": floors, "cut": cut, "uphill": uphill, "any_uphill": any_uphill, "at_chain": ground.call(chain)}

## A red arrow pointing down from `at` to the height `to_y`, beside the chain: lower it this far.
func _draw_down_arrow(at: Vector2, to_y: float, line: float) -> void:
	var end := Vector2(at.x, maxf(to_y, at.y + line * 6.0))
	draw_line(at, end, INK, line * 2.6)
	draw_line(at, end, UPHILL, line * 1.4)
	var head := PackedVector2Array([end + Vector2(-line * 3.5, -line * 4.0), end + Vector2(line * 3.5, -line * 4.0), end + Vector2(0.0, line * 1.5)])
	draw_colored_polygon(head, UPHILL)
	draw_polyline(PackedVector2Array([head[0], head[1], head[2], head[0]]), INK, line * 0.6)

## Words that shrink to fit across `room`.
func _say_fit(font: Font, at: Vector2, word: String, font_size: int, room: float, colour: Color) -> void:
	var wide := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	if wide > room:
		font_size = int(font_size * room / wide)
	_say(font, at, word, font_size, colour)

## What the driver needs to do to get the load over the tray: empty if there's no truck about.
func _truck_word(v: Dictionary) -> Dictionary:
	if truck == null or not v.has("pour"):
		return {}
	if truck.spot.distance_to(machine.spot) > NEAR_TRUCK * (2.0 if truck.haul else 1.0):
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
	_draw_hull(shapes["cab"], to_px, fade.call(Color("#e8e6df") if truck.haul else Color("#d9482b")), line * 0.7)
	_draw_hull(shapes["tray"], to_px, fade.call(Color("#9a9c98") if truck.haul else Color("#7a2a18")), line * 0.7, GOOD if lining.get("over", false) else INK)
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

## The mine's colours: fleet-white machines and red dirt. Called once the site's known.
func set_mine(on: bool) -> void:
	if not on:
		return
	DIRT = Color("#a8492a")
	SOIL = Color("#8f3d22")
	BODY = Color("#c9cac5")
	ARM = Color("#f2f1ec")
