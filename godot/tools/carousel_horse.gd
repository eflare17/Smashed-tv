extends SceneTree
## Makes the Carousel's horse (assets/models/carousel_horse/horse.res) from the owner's model
## (CarouselHorse.3mf, "Carousel Horse" by Cookiemint on MakerWorld; the owner's, for their own use): coloured like
## the owner's photo (white, a gold mane and tail, a deep red seat on a pink blanket trimmed blue, gold-and-teal and
## gold-and-blue bands across the chest and rump, a red bridle with a pink jewel, dark hooves), its own short pole
## taken off (the ride has long ones it rides up and down), cut down from ~370,000 triangles to about TRIS (close up, fewer smear its colours), and sized
## and turned for the ride: facing +x, its pole's line at x = z = 0, its hooves LIFT up.
##   godot --headless --path . -s tools/carousel_horse.gd
## Parts are found by where they are (side on: the model's z along it, y up, in mm) and, for straps and trim, by how
## far they stand out of the surface (relief: against a smoothed copy of the horse).

const SRC := "res://assets/models/carousel_horse/CarouselHorse.3mf"
const OUT := "res://assets/models/carousel_horse/horse.res"
const TRIS := 30000
const LONG := 1.75          # nose to tail (m)
const LIFT := 0.25          # its hooves this far up from where it stands

const WHITE := Color("#f4f0e6")
const GOLD := Color("#e2b443")
const SEAT := Color("#7a2a22")
const PINK := Color("#e98bb8")
const BLUE := Color("#2f63c9")
const TEAL := Color("#1fa59a")
const STRAP := Color("#b3262e")
const JEWEL := Color("#e0218a")
const HOOF := Color("#3a2a24")
const EYE := Color("#1c1410")

var pos: PackedVector3Array
var nrm: PackedVector3Array
var relief: PackedFloat32Array
var hung := PackedByteArray()   # the scallops hung from the bands (filled inside their creases)
var lift_x := 0.0               # the raised front leg's x
var pole := Vector2.ZERO        # the pole's middle (x, z)

func _initialize() -> void:
	var idx := _read()
	_normals(idx)
	_relief(idx)
	_scallops(idx)
	var n := 0
	var low := INF
	var length := Vector2(INF, -INF)
	for p in pos:
		low = minf(low, p.y)
		length = Vector2(minf(length.x, p.z), maxf(length.y, p.z))
		if p.y > 28.0:
			pole += Vector2(p.x, p.z)
			n += 1
	pole /= n
	n = 0
	for p in pos:
		if p.y > -24.0 and p.y < -22.0 and p.z > 25.5 and p.z < 28.0:
			lift_x += p.x
			n += 1
	lift_x /= n
	var col := PackedColorArray()
	col.resize(pos.size())
	for i in pos.size():
		col[i] = _shade(_colour(i), relief[i])
	# its own pole off (and the ball on top, the foot below)
	var keep := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var off := false
		for k in 3:
			off = off or _pole(pos[idx[t + k]], 2.0)
		if not off:
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
	# cut down
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = pos
	a[Mesh.ARRAY_NORMAL] = nrm
	a[Mesh.ARRAY_COLOR] = col
	a[Mesh.ARRAY_INDEX] = keep
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, a)
	im.generate_lods(25.0, 60.0, [])
	var best := keep
	for l in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, l)
		print("lod %d: %d triangles" % [l, li.size() / 3])
		if absi(li.size() / 3 - TRIS) < absi(best.size() / 3 - TRIS):
			best = li
	# only the corners it still uses, sized and turned for the ride
	var s := LONG / (length.y - length.x)
	var at := PackedInt32Array()
	at.resize(pos.size())
	at.fill(-1)
	var p2 := PackedVector3Array()
	var c2 := PackedColorArray()
	var i2 := PackedInt32Array()
	for v in best:
		if at[v] < 0:
			at[v] = p2.size()
			var q := pos[v] - Vector3(pole.x, low, pole.y)
			p2.append(Vector3(q.z, q.y, -q.x) * s + Vector3(0, LIFT, 0))
			c2.append(col[v])
		i2.append(at[v])
	pos = p2
	_normals(i2)
	var b := []
	b.resize(Mesh.ARRAY_MAX)
	b[Mesh.ARRAY_VERTEX] = p2
	b[Mesh.ARRAY_NORMAL] = nrm
	b[Mesh.ARRAY_COLOR] = c2
	b[Mesh.ARRAY_INDEX] = i2
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b)
	m.resource_name = "CarouselHorse"
	ResourceSaver.save(m, OUT, ResourceSaver.FLAG_COMPRESS)
	print("saved %s: %d triangles, %d corners, %.3f m a mm, its seat %.2f m up" % [OUT, i2.size() / 3, p2.size(), s,
		(4.5 - low) * s + LIFT])
	quit()

# the horse (the 3MF's object 2: object 1's the stand it's printed on), in Godot's axes: x, z up, -y
func _read() -> PackedInt32Array:
	var zip := ZIPReader.new()
	zip.open(SRC)
	var x := XMLParser.new()
	x.open_buffer(zip.read_file("3D/Objects/object_5.model"))
	zip.close()
	var obj := 0
	var idx := PackedInt32Array()
	while x.read() == OK:
		if x.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var n := x.get_node_name()
		if n == "object":
			obj = int(x.get_named_attribute_value("id"))
		elif obj == 2 and n == "vertex":
			pos.append(Vector3(float(x.get_named_attribute_value("x")), float(x.get_named_attribute_value("z")), -float(x.get_named_attribute_value("y"))))
		elif obj == 2 and n == "triangle":
			idx.append_array([int(x.get_named_attribute_value("v1")), int(x.get_named_attribute_value("v3")), int(x.get_named_attribute_value("v2"))])
	return idx

func _normals(idx: PackedInt32Array) -> void:
	nrm.resize(pos.size())
	nrm.fill(Vector3.ZERO)
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		var f := (pos[i2] - pos[i0]).cross(pos[i1] - pos[i0])
		nrm[i0] += f
		nrm[i1] += f
		nrm[i2] += f
	for i in nrm.size():
		nrm[i] = nrm[i].normalized()

# how far each corner stands out of a smoothed copy of the horse (+ out, - in)
func _relief(idx: PackedInt32Array) -> void:
	var s := pos.duplicate()
	var sum := PackedVector3Array()
	var cnt := PackedInt32Array()
	sum.resize(pos.size())
	cnt.resize(pos.size())
	for it in 24:
		sum.fill(Vector3.ZERO)
		cnt.fill(0)
		for t in range(0, idx.size(), 3):
			var i0 := idx[t]
			var i1 := idx[t + 1]
			var i2 := idx[t + 2]
			sum[i0] += s[i1] + s[i2]
			sum[i1] += s[i0] + s[i2]
			sum[i2] += s[i0] + s[i1]
			cnt[i0] += 2
			cnt[i1] += 2
			cnt[i2] += 2
		for i in s.size():
			if cnt[i] > 0:
				s[i] = sum[i] / cnt[i]
	relief.resize(pos.size())
	for i in pos.size():
		relief[i] = (pos[i] - s[i]).dot(nrm[i]) - 0.08      # (the smoothing shrinks it a little: this much is nothing)

# a little light on what stands out and dark in the creases, so the carving reads
static func _shade(c: Color, r: float) -> Color:
	var k := clampf(1.08 + r * 0.35, 0.6, 1.15)
	return Color(c.r * k, c.g * k, c.b * k)

# the line through (z0,y0)-(z1,y1), at z
static func _line(z: float, z0: float, y0: float, z1: float, y1: float) -> float:
	return y0 + (y1 - y0) * (z - z0) / (z1 - z0)

# where the mane starts on the neck (z, at height y): it's mane behind this
static func _mane_edge(y: float) -> float:
	const PTS := [[2.0, 7.5], [4.0, 9.0], [10.0, 11.4], [15.0, 13.9], [20.0, 15.4], [25.0, 21.5], [28.5, 24.5], [40.0, 24.5]]
	for k in range(1, PTS.size()):
		if y <= PTS[k][0]:
			var t: float = (y - PTS[k - 1][0]) / (PTS[k][0] - PTS[k - 1][0])
			return lerpf(PTS[k - 1][1], PTS[k][1], clampf(t, 0.0, 1.0))
	return 24.5

# the raised front hoof, side on
const LIFTED := [Vector2(30.6, -21.4), Vector2(28.4, -25.7), Vector2(25.0, -25.9), Vector2(24.8, -20.8), Vector2(26.7, -19.7)]
# the saddle's outline, side on
const SADDLE := [Vector2(10.4, 6.5), Vector2(10.4, -2.5), Vector2(7.5, -6.8), Vector2(-9.5, -6.8), Vector2(-12.2, -4.5),
	Vector2(-12.8, 6.0), Vector2(-14.2, 11.2), Vector2(-9.0, 9.0), Vector2(5.0, 7.5)]
# the bridle's straps, side on: [from, to]
const STRAPS := [[Vector2(24.8, 25.5), Vector2(24.6, 21.5)], [Vector2(24.6, 21.5), Vector2(25.6, 19.4)],
	[Vector2(25.6, 19.6), Vector2(29.8, 19.6)], [Vector2(25.7, 18.8), Vector2(31.0, 10.8)],
	[Vector2(35.8, 12.6), Vector2(31.0, 10.6)], [Vector2(31.0, 10.6), Vector2(30.6, 6.2)]]
const CREASE := -0.04           # less than this: the crease round a scallop (a fill stops there)
const FILL_MAX := 1700          # a scallop's fill bigger than this has leaked onto the body: not one

func _pole(p: Vector3, r: float) -> bool:
	return Vector2(p.x, p.z).distance_to(pole) < r and (p.y > 7.5 or p.y < -12.0)

static func _edge(q: Vector2, poly: Array) -> float:
	var d := INF
	for k in poly.size():
		d = minf(d, q.distance_to(Geometry2D.get_closest_point_to_segment(q, poly[k], poly[(k + 1) % poly.size()])))
	return d

static func _near_strap(q: Vector2) -> bool:
	for s in STRAPS:
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, s[0], s[1])) < 0.85:
			return true
	return false

func _colour(i: int) -> Color:
	var p := pos[i]
	var z := p.z
	var y := p.y
	var q := Vector2(z, y)
	var r := relief[i]
	if _pole(p, 2.6):
		return GOLD
	if y < -33.8 or (absf(p.x - lift_x) < 2.5 and Geometry2D.is_point_in_polygon(q, LIFTED)):
		return HOOF
	if (z < -28.5 and y > -20.0) or (z < -26.5 and y > -12.0):
		return GOLD                         # the tail
	# the head: eye, jewel, bridle, forelock
	if z > 22.0 and y > 4.0:
		if q.distance_to(Vector2(31.4, 15.6)) < 0.9:
			return EYE
		var rose := q.distance_to(Vector2(25.7, 18.8))
		if rose < 1.0 and absf(p.x) > 3.0:
			return JEWEL
		if rose < 1.6 and absf(p.x) > 3.0:
			return GOLD
		if q.distance_to(Vector2(32.4, 21.5)) < 2.6 and absf(p.x) < 3.0:
			return GOLD                     # the forelock
		if _near_strap(q) and r > -0.05:
			return STRAP
	if z > 7.0 and y > 2.0 and z < _mane_edge(y) and not (y < 8.0 and z < 9.5):
		return GOLD                         # the mane
	if z > 22.0 and y > 4.0:
		return WHITE
	# the saddle: the seat, the blanket, blue on its raised trim and round its edge, its strap hanging down
	if Geometry2D.is_point_in_polygon(q, SADDLE):
		if y > _line(z, 5.3, 3.3, -11.5, 5.5) + 0.3:
			return SEAT
		if r > 0.12 or _edge(q, SADDLE) < 0.7:
			return BLUE
		return PINK
	if z > 1.6 and z < 5.4 and y > -14.0 and y <= -6.0 and absf(p.x) > 3.0:
		return SEAT
	# the band across the chest: a gold strap, teal scallops hung from it, gold studs
	var top := _line(z, 23.5, 0.6, 9.3, 5.4)
	if z >= 9.5 and z < 28.0 and y < top + 0.4 and y > top - 1.8:
		return GOLD
	if z >= 9.5 and z < 28.0 and y <= top - 1.8 and y > top - 8.0 and hung[i] == 1:
		return GOLD if r > 0.3 else TEAL
	# the band across the rump: the same, blue
	var rt := _line(z, -11.0, 0.6, -26.0, 0.1)
	if z <= -12.0 and z > -28.0 and y < rt + 0.3 and y > rt - 2.4:
		return GOLD
	if z <= -12.0 and z > -28.0 and y <= rt - 2.4 and y > rt - 7.5 and hung[i] == 1:
		return GOLD if r > 0.3 else BLUE
	return WHITE

# under the chest band's strap, or the rump's
func _zone(p: Vector3) -> bool:
	var top := _line(p.z, 23.5, 0.6, 9.3, 5.4)
	if p.z >= 9.5 and p.z < 28.0 and p.y <= top - 1.2 and p.y > top - 6.8:
		return true
	var rt := _line(p.z, -11.0, 0.6, -26.0, 0.1)
	return p.z <= -12.0 and p.z > -28.0 and p.y <= rt - 1.8 and p.y > rt - 7.5

# the scallops: from their raised rims, filled inward, stopped at the creases round them
func _scallops(idx: PackedInt32Array) -> void:
	var nb := []
	nb.resize(pos.size())
	for i in pos.size():
		nb[i] = PackedInt32Array()
	for t in range(0, idx.size(), 3):
		for k in 3:
			var a := idx[t + k]
			if _zone(pos[a]):
				var l: PackedInt32Array = nb[a]           # (a copy: put back)
				l.append(idx[t + (k + 1) % 3])
				l.append(idx[t + (k + 2) % 3])
				nb[a] = l
	hung.resize(pos.size())
	hung.fill(0)
	var seen := PackedByteArray()
	seen.resize(pos.size())
	for i in pos.size():
		if seen[i] or not _zone(pos[i]) or relief[i] < 0.12:
			continue
		var comp := PackedInt32Array([i])
		seen[i] = 1
		var k := 0
		while k < comp.size():
			var v := comp[k]
			k += 1
			for w in nb[v]:
				if not seen[w] and _zone(pos[w]) and relief[w] > CREASE:
					seen[w] = 1
					comp.append(w)
		if comp.size() < FILL_MAX:
			for v in comp:
				hung[v] = 1
