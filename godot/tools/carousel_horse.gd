extends SceneTree
## Makes the Carousel's horse (assets/models/carousel_horse/horse.res) from the owner's model
## (CarouselHorse.3mf, "Carousel Horse" by Cookiemint on MakerWorld; the owner's, for their own use): coloured like
## the owner's photo (white, a gold mane and tail, a deep red seat on a pink blanket trimmed blue, gold-and-teal and
## gold-and-blue bands across the chest and rump, a red bridle with a pink jewel, dark hooves), its own short pole
## taken off (the ride has long ones it rides up and down), cut down from ~370,000 triangles to about TRIS (close up, fewer smear its colours), and sized
## and turned for the ride: facing +x, its pole's line at x = z = 0, its hooves LIFT up.
##   godot --headless --path . -s tools/carousel_horse.gd
## Or, to print it in colour (the owner, 31 Oct): the owner's 3MF again, whole (every triangle, its own pole and stand),
## painted with Bambu Studio's filaments (FILAMENTS: 1 white .. 7 dark brown), the project set for seven filaments:
##   godot --headless --path . -s tools/carousel_horse.gd -- --bambu=C:/somewhere/CarouselHorse-coloured.3mf
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bambu="):
			_bambu(arg.trim_prefix("--bambu="), idx)
			quit()
			return
		if arg == "--leg":
			_leg_map()
			quit()
			return
		if arg.begins_with("--preview="):
			_preview(arg.trim_prefix("--preview="), idx)
			return
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
const LIFTED := [Vector2(21.5, -19.0), Vector2(25.9, -19.0), Vector2(25.1, -26.8), Vector2(21.5, -26.8)]   # (its hoof turned back, sole out behind)
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

# how far q is from the nearest of the bridle's straps (side on)
static func _strap_d(q: Vector2) -> float:
	var d := INF
	for s in STRAPS:
		d = minf(d, q.distance_to(Geometry2D.get_closest_point_to_segment(q, s[0], s[1])))
	return d

func _colour(i: int) -> Color:
	var p := pos[i]
	var z := p.z
	var y := p.y
	var q := Vector2(z, y)
	var r := relief[i]
	if _pole(p, 2.6):
		return GOLD
	if y < -33.8 or (absf(p.x - lift_x) < 3.5 and Geometry2D.is_point_in_polygon(q, LIFTED)):
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
		var sd := _strap_d(q)
		if sd < 0.45 or (sd < 0.85 and r > -0.05):             # (right on its line, or where it stands out beside it)
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

# ---------------------------------------------------------------- printing it in colour (Bambu Studio)

## The filaments, in Bambu Studio's order (1 the part's own: left unpainted), and which of the colours goes on which.
const FILAMENTS := ["#F4F0E6", "#E2B443", "#E98BB8", "#2F63C9", "#B3262E", "#1FA59A", "#3A2A24"]
const SLOT := {"f4f0e6": 1, "e2b443": 2, "e98bb8": 3, "e0218a": 3, "2f63c9": 4, "7a2a22": 5, "b3262e": 5, "1fa59a": 6,
	"3a2a24": 7, "1c1410": 7}

## The owner's 3MF again with every triangle of the horse painted its filament (Bambu Studio's "paint_color", as its
## colour painting saves it: a triangle all one filament), and its project set for FILAMENTS. Everything else as it was.
func _bambu(out_path: String, idx: PackedInt32Array) -> void:
	var paint := _labels(idx)
	var zin := ZIPReader.new()
	zin.open(SRC)
	var zout := ZIPPacker.new()
	if zout.open(out_path) != OK:
		push_error("can't write " + out_path)
		return
	for f in zin.get_files():
		var data := zin.read_file(f)
		if f == "3D/Objects/object_5.model":
			data = _painted(data, paint)
		elif f == "Metadata/project_settings.config":
			data = _seven(data)
		zout.start_file(f)
		zout.write_file(data)
		zout.close_file()
	zout.close()
	zin.close()
	print("saved ", out_path)

# the horse's triangles (object 2's) with their filaments
func _painted(data: PackedByteArray, paint: PackedByteArray) -> PackedByteArray:
	var lines := data.get_string_from_utf8().split("\n")
	var obj := 0
	var t := 0
	for i in lines.size():
		var l := lines[i]
		if l.contains("<object "):
			obj = 2 if l.contains("id=\"2\"") else 1
		elif obj == 2 and l.contains("<triangle ") and t < paint.size():
			var slot := paint[t]
			t += 1
			if slot > 1:
				lines[i] = l.replace("/>", " paint_color=\"%s\"/>" % _paint_code(slot))
	print("painted %d of the horse's triangles" % t)
	return "\n".join(lines).to_utf8_buffer()

# Bambu Studio's (PrusaSlicer's) code for a whole triangle painted filament n: 4, 8, then 0C, 1C, 2C ...
static func _paint_code(n: int) -> String:
	if n == 1:
		return "4"
	if n == 2:
		return "8"
	return "%XC" % (n - 3)

# the project set for seven filaments: their colours, each like the one it had (the slicer takes a filament's settings
# it doesn't list from the first's), flushing between each two
func _seven(data: PackedByteArray) -> PackedByteArray:
	var cfg = JSON.parse_string(data.get_string_from_utf8())
	if not (cfg is Dictionary):
		return data
	var n := FILAMENTS.size()
	for key in cfg.keys():
		var v = cfg[key]
		if String(key).begins_with("filament_") and v is Array and (v as Array).size() == 1:
			var more := []
			for k in n:
				more.append(v[0])
			cfg[key] = more
	cfg["filament_colour"] = FILAMENTS
	var selfs := []
	for k in n:
		selfs.append(str(k + 1))
	cfg["filament_self_index"] = selfs
	var flush := []
	for a in n:
		for b in n:
			flush.append("0" if a == b else "280")
	cfg["flush_volumes_matrix"] = flush
	var vec := []
	for k in n * 2:
		vec.append("140")
	cfg["flush_volumes_vector"] = vec
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tower="):          # (where the purge tower stands: x,y mm on the plate)
			var xy := arg.trim_prefix("--tower=").split_floats(",")
			cfg["wipe_tower_x"] = [str(xy[0])]
			cfg["wipe_tower_y"] = [str(xy[1])]
	for key in ["different_settings_to_system", "inherits_group"]:
		if cfg.has(key) and cfg[key] is Array and (cfg[key] as Array).size() == 3:
			var a: Array = cfg[key]
			var b := [a[0]]
			for k in n:
				b.append(a[1])
			b.append(a[2])
			cfg[key] = b
	return JSON.stringify(cfg, "    ").to_utf8_buffer()

## Each of the horse's triangles' filament (FILAMENTS, 1..), from its corners' colours (most of them).
func _labels(idx: PackedInt32Array) -> PackedByteArray:
	var paint := PackedByteArray()
	paint.resize(idx.size() / 3)
	for t in paint.size():
		var s := []
		for k in 3:
			s.append(int(SLOT.get(_colour(idx[t * 3 + k]).to_html(false), 1)))
		paint[t] = s[1] if s[1] == s[2] else s[0]           # (most of its corners)
	_tidy(idx, paint)
	var counts := {}
	for v in paint:
		counts[v] = int(counts.get(v, 0)) + 1
	print("triangles by filament: ", counts)
	return paint

## (Checking the painting) pictures of the horse in its filaments' colours, flat, from round about, into dir.
func _preview(dir: String, idx: PackedInt32Array) -> void:
	var paint := _labels(idx)
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var mid := Vector3.ZERO
	for p in pos:
		mid += p
	mid /= pos.size()
	for t in paint.size():
		var col := Color(FILAMENTS[paint[t] - 1])
		for k in [0, 1, 2]:
			v.append(pos[idx[t * 3 + k]])
			c.append(col)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in v.size():
		st.set_color(c[i])
		st.add_vertex(v[i])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.8
	mi.material_override = m
	root.add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.6, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#d8d8d8")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root.add_child(env)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.current = true
	# [name, where from (round the middle), look at, how far]
	var views := [["left", Vector3(-1, 0.25, 0.15), mid, 120.0], ["right", Vector3(1, 0.25, -0.15), mid, 120.0],
		["front", Vector3(-0.4, 0.2, 1), mid, 120.0], ["head_l", Vector3(-1, 0.2, 0.4), Vector3(0, 15, 28), 40.0],
		["head_r", Vector3(1, 0.2, 0.4), Vector3(0, 15, 28), 40.0], ["hoof_l", Vector3(-1, -0.2, 0.5), Vector3(lift_x, -23, 28), 22.0],
		["hoof_r", Vector3(1, -0.4, 0.6), Vector3(lift_x, -23, 28), 22.0], ["hoof_under", Vector3(0.2, -1, 0.5), Vector3(lift_x, -23, 28), 22.0],
		["chest", Vector3(-0.6, 0.0, 1), Vector3(0, -2, 18), 45.0], ["saddle", Vector3(-1, 0.4, 0), Vector3(0, 2, -3), 50.0]]
	for vw in views:
		var look: Vector3 = vw[2]
		cam.position = look + (vw[1] as Vector3).normalized() * float(vw[3])
		cam.look_at(look, Vector3.UP)
		for k in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, vw[0]])
		print("SHOT ", vw[0])
	quit()

## (Checking the painting) the raised front leg side on, as text: # hoof, o the rest (z across, y down), 0.5 mm a cell.
func _leg_map() -> void:
	var grid := {}
	for i in pos.size():
		var p := pos[i]
		if absf(p.x - lift_x) < 3.0 and p.z > 17.0 and p.y < -12.0 and p.y > -34.0:
			var key := Vector2i(int(floor(p.z * 2.0)), int(floor(-p.y * 2.0)))
			var hoof := _colour(i) == HOOF
			grid[key] = "#" if hoof or grid.get(key, "") == "#" else "o"
	for row in range(24, 68):
		var line := "%5.1f " % (-row / 2.0)
		for col in range(34, 66):
			line += String(grid.get(Vector2i(col, row), "."))
		print(line)
	print("      z from 17 to 33 mm, left to right")

## The painting tidied for printing: a triangle with two of its neighbours another filament goes that one (a few times
## over: ragged edges, specks), then a little patch shut in by another filament takes it (a white gap, a coloured
## dot) but for the eyes and the jewel (KEEP_SMALL).
const TIDY_PASSES := 3
const SPECK := 150              # triangles: a white patch smaller than this, shut in, goes (a gap)
const DOT := 40                 # triangles: a coloured one smaller than this (a dot of it on the white)
const KEEP_SMALL := [3, 7]      # (the jewel's pink, the eyes' dark brown)

func _tidy(idx: PackedInt32Array, paint: PackedByteArray) -> void:
	var n := paint.size()
	# each triangle's three neighbours across its edges: every edge (its two corners) with its triangle, sorted, so a
	# shared edge's two triangles come together
	var keys := PackedInt64Array()
	keys.resize(n * 3)
	for t in n:
		for k in 3:
			var a := idx[t * 3 + k]
			var b := idx[t * 3 + (k + 1) % 3]
			keys[t * 3 + k] = ((mini(a, b) * 1048576 + maxi(a, b)) << 20) | t
	keys.sort()
	var nb := PackedInt32Array()
	nb.resize(n * 3)
	nb.fill(-1)
	var fill := PackedByteArray()
	fill.resize(n)
	for i in range(keys.size() - 1):
		if keys[i] >> 20 == keys[i + 1] >> 20:
			var t1 := int(keys[i] & 1048575)
			var t2 := int(keys[i + 1] & 1048575)
			if fill[t1] < 3 and fill[t2] < 3:
				nb[t1 * 3 + fill[t1]] = t2
				nb[t2 * 3 + fill[t2]] = t1
				fill[t1] += 1
				fill[t2] += 1
	# ragged edges, specks
	for it in TIDY_PASSES:
		var next := paint.duplicate()
		var changed := 0
		for t in n:
			var a := nb[t * 3]
			var b := nb[t * 3 + 1]
			var c := nb[t * 3 + 2]
			var la := paint[a] if a >= 0 else 0
			var lb := paint[b] if b >= 0 else 0
			var lc := paint[c] if c >= 0 else 0
			var want := 0
			if la != 0 and (la == lb or la == lc):
				want = la
			elif lb != 0 and lb == lc:
				want = lb
			if want != 0 and want != paint[t]:
				next[t] = want
				changed += 1
		paint.clear()
		paint.append_array(next)
		print("tidy pass %d: %d triangles changed" % [it, changed])
	# little patches shut in
	var seen := PackedByteArray()
	seen.resize(n)
	var filled := 0
	for t0 in n:
		if seen[t0]:
			continue
		var lab := paint[t0]
		var comp := PackedInt32Array([t0])
		seen[t0] = 1
		var k := 0
		var around := {}
		var most_n := SPECK if lab == 1 else DOT
		while k < comp.size() and comp.size() <= most_n:
			var t := comp[k]
			k += 1
			for j in 3:
				var u := nb[t * 3 + j]
				if u < 0:
					continue
				if paint[u] == lab:
					if not seen[u]:
						seen[u] = 1
						comp.append(u)
				else:
					around[paint[u]] = int(around.get(paint[u], 0)) + 1
		if comp.size() > most_n or KEEP_SMALL.has(lab) or around.is_empty():
			continue
		var best := 0
		var most := -1
		for l in around:
			if int(around[l]) > most:
				most = int(around[l])
				best = l
		for t in comp:
			paint[t] = best
		filled += comp.size()
	print("little patches filled: %d triangles" % filled)
