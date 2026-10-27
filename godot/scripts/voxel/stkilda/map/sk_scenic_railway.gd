# (Copied from stkilda-godot scripts/town/scenic_railway.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkScenicRailway
extends RefCounted
## Luna Park's Great Scenic Railway (1912): the white timber roller coaster round the edge of the park, twice round:
## the first lap (the outer track) with the lift up to its 16 m peak above the entrance and the big drops, the second
## (the inner track) with small hills. Its track bed (a boarded trough with a walkway and a white handrail), the
## trestles under it, sheds over the covered bits, and its three red trains going round. Where it runs is
## OpenStreetMap's (data/luna.json); the facts and the guesses: reference/luna_park/NOTES.md.

const OUTER := 302587792                 # the first lap's track (the map's way)
const INNER := 972795635                 # the second lap's
const COVERED := [972795634, 972795636]  # the covered bits: the station, and a tunnel
## The first lap: from the station up the lift to the peak above the entrance, then its drops, back to the station
## height (m). GUESS but for the peak (published: 16 m, above the entrance).
const STATION_H := 3.0
const PEAK_H := 16.0
const LAP1_HILLS := [3.0, 11.0, 3.5, 9.0, 3.0, 7.5, 3.5]
const LAP2_HILLS := [6.5, 3.5, 6.0, 3.5, 5.5, 3.5, 5.0, 3.5]
const STEP := 1.0                        # the track's points this far apart (m)
const CROSS_BACK := 80.0                 # the first lap goes over to the second's track this far short of the station
const SHARED_NEAR := 3.0                 # the map's two tracks closer than this are one track (both laps on it)
const SHARED_FAR := 6.5                  # ...and further apart than this, each its own (eased in between)
## How fast the trains go, times their real speed: you can change it while you ride (from SPEED_MIN to SPEED_MAX).
## All of them at once, so they stay spaced out.
static var speed := 1.0
const SPEED_MIN := 0.25
const SPEED_MAX := 3.0
const BENT := 4.0                        # a trestle bent every this far
const GAUGE := 2.4                       # the trough's width
const WHITE := Color("#f2f0ea")
const WHITE_SHADE := Color("#d9d6cd")
const RAIL := Color("#55575b")

## The whole ride, one way round: [points (x, y, z), the distance along at each, where the lift ends (distance), how
## many of the points are the first lap's].
static var _route_cache := []                # (the ride's the same every time it's asked for: work it out once)

static func route(town: SkTownBuilder, face: Transform3D, els: Array) -> Array:
	if _route_cache.is_empty():
		_route_cache = _route(town, face, els)
	return _route_cache

static func _route(town: SkTownBuilder, face: Transform3D, els: Array) -> Array:
	var outer := _loop(town, els, OUTER, face)
	var inner := _loop(town, els, INNER, face)
	if outer.size() < 10 or inner.size() < 10:
		return []
	# start both at the station (the first covered bit's middle), going the map's way round (up the west side to the
	# entrance)
	var station := Vector2.ZERO
	for e in els:
		if e.type == "way" and int(e.id) == COVERED[0]:
			for g in e.geometry:
				station += town.project(g.lat, g.lon)
			station /= e.geometry.size()
	outer = _from(outer, station)
	inner = _from(inner, station)
	var peak_at := 0
	var fp := Vector2(face.origin.x, face.origin.z)
	for i in outer.size():
		if outer[i].distance_to(fp) < outer[peak_at].distance_to(fp):
			peak_at = i
	var pts := PackedVector3Array()
	var lift_end := 0.0
	# the first lap: up the lift to the peak, then the drops, round to CROSS_BACK m short of the station, where it
	# goes over to the second lap's track (so the two changes of track, this one and the one back into the station,
	# aren't in the same place: they crossed over each other)
	var n := outer.size() - int(CROSS_BACK / STEP)
	for i in n:
		var h: float
		if i <= peak_at:
			h = _ease(STATION_H, PEAK_H, float(i) / maxi(peak_at, 1))
		else:
			h = _hills(PEAK_H, LAP1_HILLS, STATION_H, float(i - peak_at) / (n - peak_at))
		pts.append(Vector3(outer[i].x, h, outer[i].y))
	lift_end = peak_at * STEP
	# the second lap: from beside there all the way round the inner track, and on past it again to beside the station
	inner = _from(inner, outer[n - 1])
	var to_station := 0
	for i in inner.size():
		if inner[i].distance_to(outer[0]) < inner[to_station].distance_to(outer[0]):
			to_station = i
	var m := inner.size()
	var lap2 := inner.duplicate()
	lap2.append_array(inner.slice(0, to_station + 1))
	# (where the map's two tracks run within a few metres of each other, by the station, they're one track: the second
	# lap goes along the first lap's, at its height, easing out onto its own track where they part)
	var h1 := PackedFloat32Array()
	for j in outer.size():
		h1.append(pts[j].y if j < n else STATION_H)
	for i in lap2.size():
		var h := STATION_H                            # (level over the bit it goes along twice)
		if i > to_station and i < m:
			h = _hills(STATION_H, LAP2_HILLS, STATION_H, float(i - to_station) / (m - to_station))
		var q := lap2[i]
		var j := 0
		for k in outer.size():
			if outer[k].distance_squared_to(q) < outer[j].distance_squared_to(q):
				j = k
		# (the nearest point on the first lap's line there, not just its nearest point: they're a metre apart)
		var on := outer[j]
		var on_h := h1[j]
		for k2 in [j - 1, j]:
			var a := posmod(k2, outer.size())
			var b := posmod(k2 + 1, outer.size())
			var c := Geometry2D.get_closest_point_to_segment(q, outer[a], outer[b])
			if c.distance_to(q) < on.distance_to(q):
				on = c
				var t := c.distance_to(outer[a]) / maxf(0.001, outer[a].distance_to(outer[b]))
				on_h = lerpf(h1[a], h1[b], t)
		var w := 1.0 - smoothstep(SHARED_NEAR, SHARED_FAR, on.distance_to(q))
		q = q.lerp(on, w)
		pts.append(Vector3(q.x, lerpf(h, on_h, w), q.y))
	# over to the second lap's track along the first lap's last stretch, not in one jump
	var over := Vector2(pts[n].x, pts[n].z) - outer[n - 1]
	var ease_n := mini(30, n / 4)
	for k in ease_n:
		var i := n - ease_n + k
		pts[i] += Vector3(over.x, 0, over.y) * smoothstep(0.0, 1.0, float(k + 1) / ease_n)
	# and back over to the first lap's track for the station, the same way
	var back := outer[0] - Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z)
	for k in ease_n:
		var i := pts.size() - ease_n + k
		pts[i] += Vector3(back.x, 0, back.y) * smoothstep(0.0, 1.0, float(k + 1) / ease_n)
	var along := PackedFloat32Array()
	var s := 0.0
	for i in pts.size():
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
		along.append(s)
	return [pts, along, lift_end, n]

## Smoothly from a to b (t from 0 to 1).
static func _ease(a: float, b: float, t: float) -> float:
	return lerpf(a, b, 0.5 - 0.5 * cos(clampf(t, 0.0, 1.0) * PI))

## From `start`, over the hills, to `end`: evenly spaced (t from 0 to 1).
static func _hills(start: float, hills: Array, end: float, t: float) -> float:
	var keys := [start]
	keys.append_array(hills)
	keys.append(end)
	var f := clampf(t, 0.0, 0.9999) * (keys.size() - 1)
	var k := int(f)
	return _ease(keys[k], keys[k + 1], f - k)

## A loop of track (map x, z) every STEP m, smoothed; kept 6 m behind the face's front where it passes the
## entrance (so it goes behind the towers).
static func _loop(town: SkTownBuilder, els: Array, id: int, face: Transform3D) -> PackedVector2Array:
	var raw := PackedVector2Array()
	for e in els:
		if e.type == "way" and int(e.id) == id:
			for g in e.geometry:
				raw.append(town.project(g.lat, g.lon))
	if raw.size() < 4:
		return raw
	if raw[0].is_equal_approx(raw[-1]):
		raw.remove_at(raw.size() - 1)
	var inv := face.affine_inverse()
	for i in raw.size():
		var l := inv * Vector3(raw[i].x, 0, raw[i].y)
		if absf(l.x) < 20.0 and l.z > -7.0:
			# (eased in from 20 m either side, so it doesn't kink)
			var w := smoothstep(20.0, 10.0, absf(l.x))
			l.z = lerpf(l.z, minf(l.z, -7.0), w)
			var g := face * l
			raw[i] = Vector2(g.x, g.z)
	raw = _no_doubling_back(raw, 100.0)
	# smooth the corners (three times round: cut each corner a quarter of the way in)
	for k in 3:
		var sm := PackedVector2Array()
		for i in raw.size():
			var a := raw[i]
			var b := raw[(i + 1) % raw.size()]
			sm.append(a.lerp(b, 0.25))
			sm.append(a.lerp(b, 0.75))
		raw = sm
	# and every STEP m
	var out := PackedVector2Array()
	var carry := 0.0
	for i in raw.size():
		var a := raw[i]
		var b := raw[(i + 1) % raw.size()]
		var seg := a.distance_to(b)
		var t := carry
		while t < seg:
			out.append(a.lerp(b, t / seg))
			t += STEP
		carry = t - seg
	out = _no_doubling_back(out, 60.0)
	# round off what corners are left: each point to the average of the 9 m round it, a few times over
	for _round in 3:
		var avg := PackedVector2Array()
		for i in out.size():
			var sum := Vector2.ZERO
			for k in range(-4, 5):
				sum += out[(i + k + out.size()) % out.size()]
			avg.append(sum / 9.0)
		out = avg
	return out

## A loop without its points where the line turns back on itself (more than `deg` from one piece to the next): the
## map's outer track goes back over itself by the station, which flicked the train round.
static func _no_doubling_back(loop: PackedVector2Array, deg: float) -> PackedVector2Array:
	var again := true
	while again and loop.size() > 6:
		again = false
		for i in loop.size():
			var a := loop[(i + loop.size() - 1) % loop.size()]
			var b := loop[i]
			var c := loop[(i + 1) % loop.size()]
			if (b - a).length() < 0.01 or (c - b).length() < 0.01 or absf((b - a).angle_to(c - b)) > deg_to_rad(deg):
				loop.remove_at(i)
				again = true
				break
	return loop

## The same loop, starting at the point nearest `at`.
static func _from(loop: PackedVector2Array, at: Vector2) -> PackedVector2Array:
	var best := 0
	for i in loop.size():
		if loop[i].distance_to(at) < loop[best].distance_to(at):
			best = i
	var out := loop.slice(best)
	out.append_array(loop.slice(0, best))
	return out

# ================================================================ building it

static func build(parent: Node3D, town: SkTownBuilder, face: Transform3D, els: Array) -> Node3D:
	var r := route(town, face, els)
	var n := Node3D.new()
	n.name = "SkScenicRailway"
	parent.add_child(n)
	if r.is_empty():
		return n
	var pts: PackedVector3Array = r[0]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var posts := PackedVector3Array()
	_deck(st, pts, r[3])
	_trestles(st, pts, posts)
	_sheds(st, pts, town, els, r[3])
	var mi := MeshInstance3D.new()
	mi.name = "Track"
	mi.mesh = st.commit()
	mi.material_override = SkModels.baked_material()
	n.add_child(mi)
	# the posts are solid (so you can't drive through them)
	var body := StaticBody3D.new()
	body.collision_layer = SkData.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(posts)
	cs.shape = shape
	body.add_child(cs)
	n.add_child(body)
	# the three trains, spread out round the ride
	for k in 3:
		var t := Train.new()
		t.name = "Train%d" % (k + 1)
		t.setup(r, float(k) / 3.0)
		n.add_child(t)
	_boarding(n, pts)
	return n

## The map's buildings the ride runs through (within reach of the track and taller than it is there): their ids, to
## leave out. (They're the map's plain blocks for the park's rides and cafe; the real ones sit under or beside it.)
static func in_the_way(town: SkTownBuilder, face: Transform3D, els: Array) -> Dictionary:
	var r := route(town, face, els)
	var out := {}
	if r.is_empty():
		return out
	var pts: PackedVector3Array = r[0]
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in pts:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	var area := Rect2(lo, hi - lo).grow(5.0)
	for b in town.data.buildings:
		var ring := SkTownBuilder._pts(b.p)
		if not area.has_point(ring[0]):
			continue
		for p in pts:
			var q := Vector2(p.x, p.z)
			if float(b.h) < p.y - 0.4:
				continue
			var near := Geometry2D.is_point_in_polygon(q, ring)
			for k in ring.size() - 1:
				if near:
					break
				near = Geometry2D.get_closest_point_to_segment(q, ring[k], ring[k + 1]).distance_to(q) < GAUGE / 2.0 + 1.2
			if near:
				out[b.get("id", "")] = true
				break
	return out

## The train due at the station next (the one furthest round), for you to get on.
static func next_train(n: Node3D) -> Train:
	var best: Train = null
	for c in n.get_children():
		if c is Train and (best == null or (c as Train).here() > best.here()):
			best = c
	return best

## Space the other trains out evenly behind and ahead of `t` (a third of the way round each), so you don't ride up
## behind one just leaving the station. (They all go the same speed at the same spot, so they stay spaced.)
static func space_out(n: Node3D, t: Train) -> void:
	var k := 1
	for c in n.get_children():
		if c is Train and c != t:
			var o := c as Train
			o.s = t.s + o.total * k / 3.0
			k += 1

## Where you get on: on the ground inside the park beside the station (BOARD_IN m in from the first lap's track
## there), marked with a sign and a yellow ring. Kept on the railway's node as its "board" meta (map x, y, z).
const BOARD_IN := 7.0

static func _boarding(n: Node3D, pts: PackedVector3Array) -> void:
	var p := pts[0]
	var at := Vector3(p.x, 0, p.z) + _across(pts, 0) * BOARD_IN      # (to the right going round: into the park)
	n.set_meta("board", at)
	n.set_meta("board_into", _across(pts, 0))
	var holder := Node3D.new()
	var ring := SkModels.cyl(holder, 1.6, 0.04, at + Vector3(0, 0.18, 0), Color("#f2c230"), true, 24)
	ring.name = "Ring"
	SkModels.cyl(holder, 1.3, 0.05, at + Vector3(0, 0.185, 0), Color("#6f7275"), true, 24)
	var back := _across(pts, 0) * 1.8
	for side in [-0.9, 0.9]:
		var d: Vector3 = Vector3(pts[1].x - p.x, 0, pts[1].z - p.z).normalized() * side
		SkModels.box(holder, Vector3(0.12, 2.6, 0.12), at + back + d + Vector3(0, 1.3, 0), WHITE)
	var mi := MeshInstance3D.new()
	mi.name = "BoardingSpot"
	mi.mesh = SkModels.bake(holder)
	mi.material_override = SkModels.baked_material()
	holder.free()
	n.add_child(mi)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Black", "Impact", "sans-serif"])
	var l := Label3D.new()
	l.name = "BoardingSign"
	l.text = "THE GREAT\nSCENIC RAILWAY\nride it: E"
	l.font = font
	l.font_size = 64
	l.pixel_size = 0.9 / 64.0
	l.modulate = Color("#f2c230")
	l.outline_modulate = Color("#c8202a")
	l.outline_size = 14
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = at + back + Vector3(0, 3.4, 0)
	n.add_child(l)

## Which way is across the track at point i (level, to its right going along).
static func _across(pts: PackedVector3Array, i: int) -> Vector3:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var d := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	return Vector3(-d.z, 0, d.x)

## The track bed all the way round: the boarded floor, low side boards (the trough the cars run in), the two rails,
## a walkway along one side with its white handrail on posts: the first lap's on the outside (by the park's wall),
## the second's on the inside (the two laps run side by side).
static func _deck(st: SurfaceTool, pts: PackedVector3Array, lap1: int) -> void:
	var g := GAUGE / 2.0
	for i in pts.size() - 1:
		if pts[i].distance_to(pts[i + 1]) > STEP * 3.0:
			continue                         # (where the first lap's end meets the second's start)
		var a := pts[i]
		var b := pts[i + 1]
		var xa := _across(pts, i)
		var xb := _across(pts, i + 1)
		var side := -1.0 if i < lap1 else 1.0      # (which side the walkway is)
		var wa := xa * side
		var wb := xb * side
		# the floor, its underside, the rails
		_strip(st, a + wa * (g + 0.9), b + wb * (g + 0.9), a - wa * g, b - wb * g, Vector3.UP, WHITE_SHADE)
		_strip(st, a + wa * (g + 0.9) - Vector3(0, 0.3, 0), b + wb * (g + 0.9) - Vector3(0, 0.3, 0), a - wa * g - Vector3(0, 0.3, 0), b - wb * g - Vector3(0, 0.3, 0), Vector3.DOWN, WHITE_SHADE.darkened(0.2))
		for s in [-0.55, 0.55]:
			var up := Vector3(0, 0.03, 0)
			_strip(st, a + xa * (s - 0.05) + up, b + xb * (s - 0.05) + up, a + xa * (s + 0.05) + up, b + xb * (s + 0.05) + up, Vector3.UP, RAIL)
		# the side boards, both sides of the trough
		for s in [-g, g]:
			var lo := Vector3(0, -0.3, 0)
			var hi := Vector3(0, 0.5, 0)
			_strip(st, a + xa * s + lo, b + xb * s + lo, a + xa * s + hi, b + xb * s + hi, xa * signf(s), WHITE)
			_strip(st, a + xa * s + lo, b + xb * s + lo, a + xa * s + hi, b + xb * s + hi, -xa * signf(s), WHITE_SHADE)
		# the handrail along the walkway's outer edge, on posts every 2 m
		var rail := Vector3(0, 1.0, 0)
		_beam(st, a + wa * (g + 0.85) + rail, b + wb * (g + 0.85) + rail, 0.08, WHITE)
		if i % 2 == 0:
			_beam(st, a + wa * (g + 0.85), a + wa * (g + 0.85) + rail, 0.08, WHITE)

## Trestle bents every BENT m: two posts down to the ground with ledgers across and a diagonal brace between each
## pair of ledgers, and stringers along under the bed from bent to bent. The posts go into `solid` (as faces).
static func _trestles(st: SurfaceTool, pts: PackedVector3Array, solid: PackedVector3Array) -> void:
	var every := int(BENT / STEP)
	var prev := []
	for i in range(0, pts.size(), every):
		var p := pts[i]
		var x := _across(pts, i)
		var top := p.y - 0.3
		if top < 0.4:
			prev = []
			continue
		var l := Vector3(p.x, 0, p.z) - x * (GAUGE / 2.0 + 0.3)
		var r := Vector3(p.x, 0, p.z) + x * (GAUGE / 2.0 + 0.1)
		# the posts lean in a little going up (a trestle's batter)
		var lean := x * minf(0.6, top * 0.03)
		_beam(st, l - lean, l + Vector3(0, top, 0), 0.22, WHITE)
		_beam(st, r + lean, r + Vector3(0, top, 0), 0.22, WHITE)
		for q in [l - lean, r + lean]:
			var c: Vector3 = q
			var s := 0.25
			var bottom := [c + Vector3(-s, 0, -s), c + Vector3(s, 0, -s), c + Vector3(s, 0, s), c + Vector3(-s, 0, s)]
			for k in 4:
				var a0: Vector3 = bottom[k]
				var b0: Vector3 = bottom[(k + 1) % 4]
				var up := Vector3(0, minf(top, 3.0), 0)
				solid.append_array(PackedVector3Array([a0, b0, b0 + up, a0, b0 + up, a0 + up]))
		# ledgers every 3 m up, the top one under the bed; diagonals between them
		var y := 3.0
		var last := 0.3
		var flip := false
		while true:
			var yy := minf(y, top)
			var la := l.lerp(l - lean, 1.0 - yy / top) + Vector3(0, yy, 0)
			var ra := r.lerp(r + lean, 1.0 - yy / top) + Vector3(0, yy, 0)
			_beam(st, la - x * 0.2, ra + x * 0.2, 0.14, WHITE_SHADE)
			var lb := l.lerp(l - lean, 1.0 - last / top) + Vector3(0, last, 0)
			var rb := r.lerp(r + lean, 1.0 - last / top) + Vector3(0, last, 0)
			_beam(st, lb if flip else rb, ra if flip else la, 0.11, WHITE_SHADE)
			flip = not flip
			last = yy
			if yy >= top:
				break
			y += 3.0
		# stringers along from the last bent
		if not prev.is_empty():
			_beam(st, prev[0], l + Vector3(0, top, 0), 0.16, WHITE_SHADE)
			_beam(st, prev[1], r + Vector3(0, top, 0), 0.16, WHITE_SHADE)
		prev = [l + Vector3(0, top, 0), r + Vector3(0, top, 0)]

## Sheds over the covered bits (the station, and a tunnel): walls either side of the track and a roof. Over the first
## lap's track only (and the last run into the station): the second lap's runs beside them.
static func _sheds(st: SurfaceTool, pts: PackedVector3Array, town: SkTownBuilder, els: Array, lap1: int) -> void:
	for e in els:
		if e.type != "way" or not (int(e.id) in COVERED):
			continue
		var line := PackedVector2Array()
		for g in e.geometry:
			line.append(town.project(g.lat, g.lon))
		# the track points under it: within 4 m of its line
		for i in pts.size() - 1:
			var p := Vector2(pts[i].x, pts[i].z)
			var near := INF
			for k in line.size() - 1:
				near = minf(near, Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1]).distance_to(p))
			if near > 4.0 or pts[i].distance_to(pts[i + 1]) > STEP * 3.0 or (i >= lap1 and i < pts.size() - 35):
				continue
			var a := pts[i]
			var b := pts[i + 1]
			var xa := _across(pts, i)
			var xb := _across(pts, i + 1)
			var w := GAUGE / 2.0 + 1.1
			var h := Vector3(0, 3.0, 0)
			for s in [-w, w]:
				_strip(st, a + xa * s, b + xb * s, a + xa * s + h, b + xb * s + h, xa * signf(s), Color("#e6e1d3"))
				_strip(st, a + xa * s, b + xb * s, a + xa * s + h, b + xb * s + h, -xa * signf(s), Color("#8f8a80"))
			_strip(st, a - xa * (w + 0.3) + h, b - xb * (w + 0.3) + h, a + xa * (w + 0.3) + h, b + xb * (w + 0.3) + h, Vector3.UP, Color("#6b2a24"))
			_strip(st, a - xa * (w + 0.3) + h, b - xb * (w + 0.3) + h, a + xa * (w + 0.3) + h, b + xb * (w + 0.3) + h, Vector3.DOWN, Color("#4a4640"))

## A four-cornered strip (a0-b0 along one edge, a1-b1 the other) facing n.
static func _strip(st: SurfaceTool, a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3, n: Vector3, c: Color) -> void:
	_tri(st, a0, b0, b1, n, c)
	_tri(st, a0, b1, a1, n, c)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	var real := (b - a).cross(c - a)
	if real.length_squared() < 0.000001:
		return
	var nn := real.normalized()
	if nn.dot(n) < 0.0:
		nn = -nn
	st.set_normal(nn)
	st.set_color(col)
	st.add_vertex(a)
	# (Godot draws the side where the corners go clockwise)
	if real.dot(nn) > 0.0:
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(b)
		st.add_vertex(c)

## A square timber from a to b, w thick.
static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, c: Color) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var f := d.normalized()
	var u := f.cross(Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT).normalized() * (w / 2.0)
	var v := f.cross(u).normalized() * (w / 2.0)
	var sides := [[u, v], [v, -u], [-u, -v], [-v, u]]
	for sd in sides:
		var p: Vector3 = sd[0]
		var q: Vector3 = sd[1]
		var n := p.normalized()
		_strip(st, a + p + q, b + p + q, a + p - q, b + p - q, n, c.darkened(0.08 if n.y < -0.3 else 0.0))
	# (the ends: only the top one shows)
	_strip(st, b + u + v, b - u + v, b + u - v, b - u - v, f, c)

# ================================================================ the trains

## A train going round: two red cars with a brakeman standing between them. Up the lift at a steady walk, then
## coasting: as fast as the drop from the peak allows (a bit lost to friction), up to the published 60 km/h; slow
## through the station.
class Train extends Node3D:
	var pts: PackedVector3Array
	var along: PackedFloat32Array
	var lift_end := 0.0
	var total := 0.0
	var s := 0.0
	var _cars: Array = []
	## Riding it: a camera in the front seat, and where the ride started (it's over once round both laps).
	signal ride_over
	var rider_cam: Camera3D = null
	var chase_cam: Camera3D = null         # (V: the view from behind the train)
	var chase_pivot: Node3D = null
	var rider: Node3D = null               # who's in the front seat
	var _ride_from := 0.0

	## Where it is along the ride (0 at the station, going round).
	func here() -> float:
		return fposmod(s, total)

	## You get on: it comes on round to the station (it's the train due there next), and you're in the front seat.
	func board() -> Camera3D:
		s = ceilf(s / total) * total
		_ride_from = s
		rider_cam = Camera3D.new()
		rider_cam.name = "FrontSeat"
		rider_cam.fov = 75.0
		rider_cam.near = 0.05
		rider_cam.far = 9000.0
		_cars[0].add_child(rider_cam)
		rider_cam.position = Vector3(0, 1.75, -0.95)
		rider_cam.rotation.x = -0.12
		rider_cam.current = true
		# and from behind: a camera following the train, looking down over it at you (who) in the front seat
		chase_pivot = Node3D.new()
		chase_pivot.name = "Behind"
		_cars[0].add_child(chase_pivot)
		chase_pivot.position = Vector3(0, 1.4, 0)
		chase_cam = Camera3D.new()
		chase_cam.fov = 65.0
		chase_cam.near = 0.1
		chase_cam.far = 9000.0
		chase_pivot.add_child(chase_cam)
		chase_cam.position = Vector3(0, 2.6, 9.5)
		chase_cam.rotation.x = -0.24
		_place()
		return rider_cam

	## Someone sitting in the front seat (seen from behind; hidden from the front seat itself). Legs inside the car:
	## there's no sitting pose.
	func seat(who: Node3D) -> void:
		rider = who
		_cars[0].add_child(who)
		who.position = Vector3(0, 0.05, -1.0)          # (his legs inside the car, him from the waist up above the seat backs)
		who.rotation = Vector3.ZERO
		who.visible = chase_cam.current if chase_cam else false

	## From the front seat or from behind the train.
	func view_from_behind(on: bool) -> void:
		if rider_cam == null:
			return
		chase_cam.current = on
		rider_cam.current = not on
		if rider:
			rider.visible = on

	func leave() -> void:
		if rider and rider.get_parent() == _cars[0]:
			_cars[0].remove_child(rider)
		rider = null
		for c in [rider_cam, chase_pivot]:
			if c:
				(c as Node).queue_free()
		rider_cam = null
		chase_cam = null
		chase_pivot = null

	## The front car (where you sit).
	func front() -> Node3D:
		return _cars[0]

	func setup(r: Array, at: float) -> void:
		pts = r[0]
		along = r[1]
		lift_end = r[2]
		total = along[along.size() - 1]
		s = at * total
		for k in 2:
			var car := _car()
			add_child(car)
			_cars.append(car)
		_place()

	func _car() -> Node3D:
		var holder := Node3D.new()
		var red := Color("#c4161c")
		SkModels.box(holder, Vector3(1.9, 0.55, 3.3), Vector3(0, 0.45, 0), red)
		SkModels.box(holder, Vector3(1.6, 0.2, 3.0), Vector3(0, 0.78, 0), Color("#3a1416"))
		for row in 5:
			SkModels.box(holder, Vector3(1.7, 0.5, 0.14), Vector3(0, 0.95, -1.35 + row * 0.62), red.darkened(0.15))
		SkModels.box(holder, Vector3(1.9, 0.9, 0.3), Vector3(0, 0.75, -1.65), red)        # its front
		SkModels.box(holder, Vector3(2.0, 0.12, 3.4), Vector3(0, 0.2, 0), Color("#2b2b2e"))  # the chassis
		var mi := MeshInstance3D.new()
		mi.mesh = SkModels.bake(holder)
		mi.material_override = SkModels.baked_material()
		holder.free()
		var car := Node3D.new()
		car.add_child(mi)
		return car

	## Where along the ride (wrapping round) -> [point, its direction].
	func _at(d: float) -> Array:
		d = fposmod(d, total)
		var lo := 0
		var hi := along.size() - 1
		while hi - lo > 1:
			var mid := (lo + hi) / 2
			if along[mid] <= d:
				lo = mid
			else:
				hi = mid
		var seg := maxf(along[hi] - along[lo], 0.001)
		var p := pts[lo].lerp(pts[hi], (d - along[lo]) / seg)
		var dir := (pts[hi] - pts[lo]).normalized()
		if pts[lo].distance_to(pts[hi]) > STEP * 3.0:       # (the jump from the first lap to the second)
			dir = (pts[mini(hi + 1, pts.size() - 1)] - pts[hi]).normalized()
		return [p, dir]

	func _place() -> void:
		for k in _cars.size():
			var a := _at(s - k * 3.6)
			var p: Vector3 = a[0]
			# (which way it points: from its back wheels to its front ones, so it turns smoothly through bends)
			var dir: Vector3 = (_at(s - k * 3.6 + 1.4)[0] as Vector3) - (_at(s - k * 3.6 - 1.4)[0] as Vector3)
			var car: Node3D = _cars[k]
			var basis := Basis.looking_at(dir, Vector3.UP) if dir.length() > 0.1 and absf(dir.normalized().y) < 0.99 else car.transform.basis
			car.transform = Transform3D(basis, p + Vector3(0, -0.25, 0))

	func _process(dt: float) -> void:
		var here := fposmod(s, total)
		var h: float = _at(here)[0].y
		var v: float
		if here < lift_end:
			v = 2.6                                            # (on the lift: the cable pulls it up)
		elif here > total - 25.0 or here < 8.0:
			v = 2.0                                            # (through the station)
		else:
			v = clampf(sqrt(maxf(0.0, 2.0 * 9.8 * (PEAK_H + 0.5 - h) * 0.85)), 3.0, 16.7)
		s += v * SkScenicRailway.speed * dt
		_place()
		if rider_cam and s - _ride_from >= total - 4.0:          # (round both laps and back in the station)
			ride_over.emit()
