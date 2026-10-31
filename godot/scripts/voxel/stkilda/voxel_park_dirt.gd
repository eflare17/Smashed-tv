class_name VoxelParkDirt
extends Node3D
## Dirt you can dig along Luna Park's wall (the owner, 31 Oct: the first mission's break-in, "make the ground diggable
## around the perimeter and the inside of the fence"; a real dig, block by block): a strip BAND m either side of the
## wall along its long straight runs (not round the corners or by Mr Moon), the back yard's ground (VoxelTerrain, its
## 12.5 cm blocks) laid in patches up to PATCH m long, turned to the wall, DEPTH m deep: dirt with clay in pockets and
## the odd stone (the pick's), bedrock at the bottom. Deep enough to dig down beside the wall, under it (its foot's at
## the ground) and up the other side. Over the strip the town's ground, the park's paving and the shade along the wall
## are cut away (the dirt's top is level with the ground), and so is the floor you walk on. The shovel and the pick dig
## it (VoxelTool). It's all put back the next time you come (reset).

const BAND := 3.5               # m of dirt either side of the wall
const PATCH := 16.0             # m along, at most (a VoxelTerrain's grid)
const RUN_MIN := 30.0           # m: a straight run of the wall this long gets dirt
const BEND := 4.0               # degrees: segments turning less than this are one straight run
const END_GAP := 3.0            # m left as it was at each end of a run (the corners)
const ROW := 0.125              # m: the floor's rows, where it's cut round the strip
const MAX_CUTS := 32            # (the ground's shader takes this many)

var sk: VoxelStKilda
var patches: Array[Patch] = []
var cuts: Array = []            # [start (Vector2), along (Vector2, unit), length, half width]
var ring := PackedVector2Array()

## One patch of the dirt: VoxelTerrain turned to the wall (its x along the wall, its middle z the wall's line), only
## the band either side of the wall made (the rest of its grid left empty), the ring round that never digging.
class Patch extends VoxelTerrain:
	var x1 := VoxelTerrain.NX   # blocks along it
	var z0 := 0                 # the band's blocks across it
	var z1 := VoxelTerrain.NZ
	var dug := false

	func generate() -> void:
		_hash.clear()
		cells.resize(NX * NY * NZ)
		cells.fill(AIR)
		for z in range(z0, z1):
			for y in NY:
				var m := BEDROCK if y <= 1 else (EDGE if z == z0 or z == z1 - 1 else DIRT)
				var row := (z * NY + y) * NX
				for x in x1:
					cells[row + x] = m
				if y > 1:
					cells[row] = EDGE
					cells[row + x1 - 1] = EDGE
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		# clay in pockets, the odd stone (the shovel can't: the pick can)
		for k in int(x1 * (z1 - z0) / 900.0) + 2:
			_lump(Vector3i(rng.randi_range(2, x1 - 3), rng.randi_range(4, NY - 5), rng.randi_range(z0 + 2, z1 - 3)), rng.randf_range(2.0, 4.5), CLAY)
		for k in int(x1 * (z1 - z0) / 500.0) + 2:
			_lump(Vector3i(rng.randi_range(2, x1 - 3), rng.randi_range(3, NY - 3), rng.randi_range(z0 + 2, z1 - 3)), rng.randf_range(0.6, 1.6), STONE)

	func _lump(c: Vector3i, r: float, m: int) -> void:
		var ri := ceili(r)
		for z in range(maxi(c.z - ri, z0 + 1), mini(c.z + ri + 1, z1 - 1)):
			for y in range(maxi(c.y - ri, 2), mini(c.y + ri + 1, NY)):
				for x in range(maxi(c.x - ri, 1), mini(c.x + ri + 1, x1 - 1)):
					if Vector3(x - c.x, y - c.y, z - c.z).length() <= r and cells[idx(x, y, z)] == DIRT:
						cells[idx(x, y, z)] = m

	## Only the chunks the band's in meshed (the rest are empty).
	func band_chunks() -> Array:
		var out := []
		var per := NX / CS
		for c in per * (NZ / CS):
			var cx := (c % per) * CS
			var cz := (c / per) * CS
			if cx < x1 and cz + CS > z0 and cz < z1:
				out.append(c)
		return out

	func wdig(c: Vector3, r: float, hardest: int) -> Dictionary:
		dug = true
		return dig(to_local(c), r, hardest)

	func wfill(c: Vector3, r: float, n: int) -> int:
		dug = true
		return fill(to_local(c), r, n)

	func wcontains(p: Vector3) -> bool:
		var l := to_local(p)
		var c := cell_of(l)
		return contains(l) and c.x < x1 and c.z >= z0 and c.z < z1

	func wcentre(c: Vector3i) -> Vector3:
		return to_global(centre_of(c.x, c.y, c.z))

	## The ground's top here (world y; the bottom if it's dug to bedrock).
	func wsurface(p: Vector3) -> float:
		var l := to_local(p)
		return to_global(Vector3(l.x, surface_y(l), l.z)).y

	func reset() -> void:
		if not dug:
			return
		dug = false
		generate()
		for c in band_chunks():
			_dirty[c] = true

func setup(s: VoxelStKilda) -> void:
	sk = s
	name = "ParkDirt"
	ring = _ring()
	if ring.size() < 4:
		return
	for run in _runs():
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var d := (b - a).normalized()
		var use := a.distance_to(b) - END_GAP * 2.0
		var n := ceili(use / PATCH)
		var each := floorf(use / n / VoxelTerrain.CELL) * VoxelTerrain.CELL     # (whole blocks: the patches meet exactly)
		for i in n:
			_patch(a + d * (END_GAP + i * each), d, each)
	_cut_ground()
	_cut_paving()
	_cut_shade()
	_cut_floor()

## The park's wall, as SkLunaPark makes it (OpenStreetMap's outline of it).
func _ring() -> PackedVector2Array:
	var out := PackedVector2Array()
	var park = JSON.parse_string(FileAccess.get_file_as_string("res://data/stkilda/luna.json"))
	if park == null:
		return out
	for e in park.elements:
		if e.type == "way" and int(e.id) == SkLunaPark.WALL_WAY:
			for g in e.geometry:
				out.append(sk.town.project(g.lat, g.lon))
	if out.size() > 1 and out[0].is_equal_approx(out[-1]):
		out.remove_at(out.size() - 1)
	return out

## The wall's long straight runs: [[from, to]] (segments turning less than BEND one run).
func _runs() -> Array:
	var n := ring.size()
	var dirs := []
	for i in n:
		dirs.append(rad_to_deg((ring[(i + 1) % n] - ring[i]).angle()))
	var turns := func(i: int) -> bool: return absf(wrapf(float(dirs[i]) - float(dirs[(i - 1 + n) % n]), -180.0, 180.0)) >= BEND
	var first := -1
	for i in n:
		if turns.call(i):
			first = i
			break
	if first < 0:
		return []
	var out := []
	var i := first
	var start := first
	for step in n:
		var j := (i + 1) % n
		if j == first or turns.call(j):
			var a := ring[start]
			var b := ring[j]
			if a.distance_to(b) >= RUN_MIN:
				out.append([a, b])
			start = j
		i = j
	return out

func _patch(at: Vector2, d: Vector2, length: float) -> void:
	var p := Patch.new()
	var cell := VoxelTerrain.CELL
	p.x1 = mini(VoxelTerrain.NX, roundi(length / cell))
	var half := roundi(BAND / cell)
	p.z0 = VoxelTerrain.NZ / 2 - half
	p.z1 = VoxelTerrain.NZ / 2 + half
	p.seed = 1927 + patches.size() * 31
	var x := Vector3(d.x, 0, d.y)
	p.transform = Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), Vector3(at.x, 0, at.y))
	add_child(p)
	p.setup(Vector3(0, -VoxelTerrain.NY * cell, -VoxelTerrain.NZ * cell / 2.0))
	var keep := p.band_chunks()
	for c in p._dirty.keys():
		if not keep.has(c):
			p._dirty.erase(c)
	patches.append(p)
	cuts.append([at, d, p.x1 * cell, half * cell])

## The patch a collider's part of (the dirt the shovel hit), or null.
func patch_of(col: Object) -> Patch:
	if col is Node:
		var par := (col as Node).get_parent()
		if par is Patch:
			return par
	return null

## The patch with p over (or in) its dirt, or null.
func patch_at(p: Vector3) -> Patch:
	for pt in patches:
		if pt.wcontains(p):
			return pt
	return null

## The dirt's top under p (world y), or INF where there's no dirt.
func surface(p: Vector3) -> float:
	var pt := patch_at(p)
	return pt.wsurface(p) if pt else INF

## Is p over the strip (inside a cut)? grow: m more all round.
func in_cut(p: Vector2, grow := 0.0) -> bool:
	for c in cuts:
		var r := p - (c[0] as Vector2)
		var d: Vector2 = c[1]
		var along := r.dot(d)
		if along >= -grow and along <= float(c[2]) + grow and absf(r.dot(Vector2(-d.y, d.x))) <= float(c[3]) + grow:
			return true
	return false

## Put back as it was (the next time you come).
func reset() -> void:
	for p in patches:
		p.reset()

## Everything dirty meshed now (tests, pictures).
func finish() -> void:
	for p in patches:
		p.finish()

# ---------------------------------------------------------------- cutting the town away over the strip

## The town's ground (SkGroundLook's shader) not drawn over the strip: its own copy of the shader, a hole where each cut is.
func _cut_ground() -> void:
	var g := sk.find_child("Ground", true, false) as MeshInstance3D
	if g == null or not (g.material_override is ShaderMaterial):
		push_warning("VoxelParkDirt: no Ground to cut")
		return
	var src := g.material_override as ShaderMaterial
	var code := src.shader.code
	if not code.contains("varying vec3 wpos;") or not code.contains("void fragment() {"):
		push_warning("VoxelParkDirt: the ground's shader has changed: not cut")
		return
	code = code.replace("varying vec3 wpos;", "varying vec3 wpos;\nuniform int dig_n = 0;\nuniform vec4 dig_a[%d];\nuniform vec2 dig_b[%d];" % [MAX_CUTS, MAX_CUTS])
	code = code.replace("void fragment() {", "void fragment() {\n\tfor (int i = 0; i < dig_n; i++) {\n\t\tvec2 r = wpos.xz - dig_a[i].xy;\n\t\tfloat al = dot(r, dig_a[i].zw);\n\t\tif (al >= 0.0 && al <= dig_b[i].x && abs(dot(r, vec2(-dig_a[i].w, dig_a[i].z))) <= dig_b[i].y) { discard; }\n\t}")
	var sh := Shader.new()
	sh.code = code
	var m := src.duplicate() as ShaderMaterial
	m.shader = sh
	var a := PackedVector4Array()
	var b := PackedVector2Array()
	for c in cuts.slice(0, MAX_CUTS):
		a.append(Vector4(c[0].x, c[0].y, c[1].x, c[1].y))
		b.append(Vector2(c[2], c[3]))
	a.resize(MAX_CUTS)
	b.resize(MAX_CUTS)
	m.set_shader_parameter("dig_n", mini(cuts.size(), MAX_CUTS))
	m.set_shader_parameter("dig_a", a)
	m.set_shader_parameter("dig_b", b)
	g.material_override = m

func _rect(c: Array) -> PackedVector2Array:
	var o: Vector2 = c[0]
	var d: Vector2 = c[1]
	var s := Vector2(-d.y, d.x) * float(c[3])
	var e := d * float(c[2])
	return PackedVector2Array([o - s, o + e - s, o + e + s, o + s])

## The park's paving made again, without the strip.
func _cut_paving() -> void:
	var pave := sk.find_child("ParkPaving", true, false) as MeshInstance3D
	if pave == null:
		return
	var polys: Array = [ring]
	for c in cuts:
		var next: Array = []
		for p in polys:
			for q in Geometry2D.clip_polygons(p, _rect(c)):
				next.append(q)
		polys = next
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.set_color(Color("#5f6266"))
	for p: PackedVector2Array in polys:
		var idx := Geometry2D.triangulate_polygon(p)
		for k in range(0, idx.size(), 3):
			var t := [p[idx[k]], p[idx[k + 1]], p[idx[k + 2]]]
			if (t[1] - t[0]).cross(t[2] - t[0]) > 0.0:
				t = [t[0], t[2], t[1]]        # (facing up)
			for v: Vector2 in t:
				st.add_vertex(Vector3(v.x, 0.15, v.y))
	pave.mesh = st.commit()

## The soft shade along the foot of the wall (SkContactShade) not over the strip (it'd hang over the holes).
func _cut_shade() -> void:
	var mi := sk.find_child("SkContactShade", true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var col = arr[Mesh.ARRAY_COLOR]
	var ix = arr[Mesh.ARRAY_INDEX]
	var order := PackedInt32Array()
	if ix is PackedInt32Array and not (ix as PackedInt32Array).is_empty():
		order = ix
	else:
		for i in v.size():
			order.append(i)
	var nv := PackedVector3Array()
	var nc := PackedColorArray()
	for k in range(0, order.size(), 3):
		var mid := (v[order[k]] + v[order[k + 1]] + v[order[k + 2]]) / 3.0
		if in_cut(Vector2(mid.x, mid.z), 0.3):
			continue
		for j in 3:
			nv.append(v[order[k + j]])
			if col is PackedColorArray and not (col as PackedColorArray).is_empty():
				nc.append(col[order[k + j]])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	if nc.size() == nv.size() and not nc.is_empty():
		out[Mesh.ARRAY_COLOR] = nc
	var ns := PackedVector3Array()
	ns.resize(nv.size())
	ns.fill(Vector3.UP)
	out[Mesh.ARRAY_NORMAL] = ns
	var am := ArrayMesh.new()
	if not nv.is_empty():
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mi.mesh = am

## The floor you walk on (the town's one big box) cut round the strip: the box outside the strip's reach, and inside
## it a flat floor in rows ROW m wide with the strip left out of each (where a row's only partly over the strip, the
## floor's kept: at worst a lip a few cm into the dirt, never a gap).
func _cut_floor() -> void:
	var floor_body := sk.find_child("Floor", true, false) as StaticBody3D
	if floor_body == null or cuts.is_empty():
		return
	var cs: CollisionShape3D = null
	for c in floor_body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			cs = c
	if cs == null:
		return
	var bs := cs.shape as BoxShape3D
	var whole := Rect2(Vector2(cs.position.x - bs.size.x / 2.0, cs.position.z - bs.size.z / 2.0), Vector2(bs.size.x, bs.size.z))
	var near := Rect2(_rect(cuts[0])[0], Vector2.ZERO)
	for c in cuts:
		for p in _rect(c):
			near = near.expand(p)
	near = near.grow(1.0).intersection(whole)
	cs.queue_free()
	# the box round it, in four
	for r in [Rect2(whole.position, Vector2(near.position.x - whole.position.x, whole.size.y)),
			Rect2(Vector2(near.end.x, whole.position.y), Vector2(whole.end.x - near.end.x, whole.size.y)),
			Rect2(Vector2(near.position.x, whole.position.y), Vector2(near.size.x, near.position.y - whole.position.y)),
			Rect2(Vector2(near.position.x, near.end.y), Vector2(near.size.x, whole.end.y - near.end.y))]:
		if r.size.x <= 0.01 or r.size.y <= 0.01:
			continue
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, 1.0, r.size.y)
		var part := CollisionShape3D.new()
		part.shape = box
		part.position = Vector3(r.get_center().x, -0.5, r.get_center().y)
		floor_body.add_child(part)
	# inside: rows
	var faces := PackedVector3Array()
	var z := near.position.y
	while z < near.end.y - 0.0001:
		var z2 := minf(z + ROW, near.end.y)
		var gone: Array = []                  # [from x, to x] left out of this row
		for c in cuts:
			var g0 := _across(c, z)
			var g1 := _across(c, z2)
			if g0.x <= g0.y and g1.x <= g1.y:
				var lo := maxf(g0.x, g1.x)
				var hi := minf(g0.y, g1.y)
				if lo < hi:
					gone.append(Vector2(lo, hi))
		gone.sort_custom(func(p, q): return p.x < q.x)
		var x := near.position.x
		for g: Vector2 in gone:
			if g.x > x:
				_quad(faces, x, minf(g.x, near.end.x), z, z2)
			x = maxf(x, g.y)
		if x < near.end.x:
			_quad(faces, x, near.end.x, z, z2)
		z = z2
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	var rows := CollisionShape3D.new()
	rows.name = "FloorRows"
	rows.shape = sh
	floor_body.add_child(rows)

# where the line across the map at z crosses a cut's rectangle: Vector2(from x, to x) (from > to: it doesn't)
func _across(c: Array, z: float) -> Vector2:
	var o: Vector2 = c[0]
	var d: Vector2 = c[1]
	var lo := -INF
	var hi := INF
	# along it, 0..length; across it, -half..half: each a straight line in x
	for f in [[d.x, (z - o.y) * d.y - o.x * d.x, 0.0, float(c[2])], [-d.y, (z - o.y) * d.x + o.x * d.y, -float(c[3]), float(c[3])]]:
		var a: float = f[0]
		var b: float = f[1]
		if absf(a) < 1e-6:
			if b < f[2] or b > f[3]:
				return Vector2(1, 0)
			continue
		var x0 := (float(f[2]) - b) / a
		var x1 := (float(f[3]) - b) / a
		lo = maxf(lo, minf(x0, x1))
		hi = minf(hi, maxf(x0, x1))
	return Vector2(lo, hi)

static func _quad(f: PackedVector3Array, x0: float, x1: float, z0: float, z1: float) -> void:
	if x1 - x0 < 0.001:
		return
	f.append_array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)])
