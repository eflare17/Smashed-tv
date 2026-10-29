class_name VoxelBreakables
extends Node3D
## St Kilda's buildings you can smash (the owner, 29 Oct: "distructable building"): the map's buildings in the slice
## round Luna Park (Cafe Luna's neighbours, the Palais, the flats and shops on the Esplanade), not Mr Moon, the
## coaster or the rides. Each looks just as the St Kilda game draws it (its own copy of the town's walls, windows and
## roof) until it's first hit; then it's swapped for its walls in blocks about BLOCK m across (its colours, a window
## where the storeys' windows are) and a roof of tiles. A bullet knocks a block out, the shotgun a few (a block a
## pellet), a blast a round hole; the block bursts into the voxel game's cubes (the vacuum takes them: Brick). A block
## with nothing joining it down to the ground (round any way: up the wall, along it, round a corner) falls, and smashes
## where it lands; knock enough of a building's walls out and its roof comes down. It's all built again the next time
## you come (VoxelStKilda.home resets it). The walls stand on columns of box shapes (a shape a run of blocks), so you
## and the shots stop at them before and after. Luna Park's own buildings too (add_park: the Ghost Train, Luna Palace,
## the shops): those keep their own model, holes cut in it where blocks go, the blocks behind showing through.

const BLOCK := 1.0              # a block's width along a wall (m; each wall's own share of that)
const THICK := 0.45             # a wall's thickness
const TILE := 2.0               # a roof tile
const GLASS := Color("#1d3563")         # (the St Kilda game's window blue)
const FALL_MAX := 500           # blocks falling at once (more: they burst where they are)
const CUBES := 18               # the voxel game's cubes a block bursts into
const ROOF_GOES := 0.55         # the roof falls in when less than this of the walls are standing
const SPAN := 4                # blocks a wall bridges over a gap, each side (more and it falls)
const NO_SHOPS := ["w1000251780", "w1000251784"]   # (Cafe Luna, the Gift Shop: Luna Park's own shop is on that outline)

var sk: VoxelStKilda
var list: Array[Building] = []
var _fall_mm: MultiMeshInstance3D
var _fall: Array = []           # [{at, v, spin, basis, size, col}]
var _cols := {}                 # every colour a block is (rgba32 -> true): their cubes are Brick in the backpack

## The ones to make breakable: added to the town's skip (so it doesn't draw them) before it builds. [map building]
static func pick(town: SkTownBuilder, box: Rect2) -> Array:
	var out := []
	for bd in town.data.buildings:
		var id := String(bd.get("id", ""))
		if town.skip.has(id) or String(bd.k) in ["roof", "carport"]:
			continue
		if id in NO_SHOPS:
			town.skip[id] = true          # (Luna Park's shop on it is drawn instead: no wall in the same place twice)
			continue
		var ring := _ring(bd)
		if ring.size() < 3:
			continue
		var c := Vector2.ZERO
		for v in ring:
			c += v
		if not box.has_point(c / ring.size()):
			continue
		out.append(bd)
		town.skip[id] = true
	return out

static func _ring(bd: Dictionary) -> PackedVector2Array:
	var ring := SkTownBuilder._pts(bd.p)
	if ring.size() > 3 and ring[0].is_equal_approx(ring[-1]):
		ring.remove_at(ring.size() - 1)
	return ring

func setup(s: VoxelStKilda, picked: Array) -> void:
	sk = s
	name = "Breakables"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_fall_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	bm.material = mat
	mm.mesh = bm
	mm.instance_count = FALL_MAX
	mm.visible_instance_count = 0
	_fall_mm.multimesh = mm
	add_child(_fall_mm)
	for bd in picked:
		var b := Building.new()
		b.make(self, bd)
		list.append(b)
	VoxelItems.brick_cols = _cols

## Luna Park's own buildings (the owner, 30 Oct: "just do the ones in luna park"), built by SkLunaRides and
## SkLunaExtras, named here with the colour their blocks are: each box the park model stands you off with (its
## StaticBody's box shapes) becomes walls in blocks round that box, and the model's own box is taken away (the blocks'
## walls stop you instead). Not the rides (the Carousel's a ride), Mr Moon or the coaster.
func add_park() -> void:
	var park := {"GhostTrain": SkLunaRides.LAVENDER.darkened(0.15), "LunaPalace": SkLunaRides.WHITE}
	for id in SkLunaExtras.SHOPS:
		var look: Array = SkLunaExtras.SHOPS[id]
		park[String(look[0]).replace(" ", "")] = look[2]
	var back := sk.global_transform.affine_inverse()
	for nm in park:
		var n := sk.get_node_or_null(NodePath(String(nm))) as Node3D
		if n == null:
			continue
		var group: Array[Building] = []
		var mats := VoxelBreakables.holed(n)
		for sb in n.get_children():
			if not sb is StaticBody3D:
				continue
			for cs in (sb as Node).get_children():
				if not (cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D):
					continue
				var size: Vector3 = ((cs as CollisionShape3D).shape as BoxShape3D).size
				var xf: Transform3D = back * (cs as Node3D).global_transform
				var r := PackedVector2Array()
				for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var p := xf * Vector3(k.x * size.x / 2.0, 0, k.y * size.z / 2.0)
					r.append(Vector2(p.x, p.z))
				if group.size() >= 2:
					continue                # (the shader takes two boxes a model)
				var b := Building.new()
				b.make_over(self, n, String(nm), r, xf.origin.y + size.y / 2.0, park[nm])
				b.holes_on(mats, group.size(), Transform3D(xf.basis, Vector3(xf.origin.x, 0, xf.origin.z)).affine_inverse(),
						size.x / 2.0, size.z / 2.0)
				list.append(b)
				group.append(b)
			(sb as StaticBody3D).collision_layer = 0          # (the blocks' walls stand there now)
		for b in group:
			b.partners = group.filter(func(x): return x != b)

## A park model's own look (the baked shops' plain colours, or the Ghost Train's worn paint) with holes in it: where a
## block's been knocked out (the wall's column and row, from where on its box a bit of the model is) or a roof tile's
## gone, that bit's not drawn, and you see the blocks behind (drawn just inside it) through the hole. Up to two boxes a
## model (Luna Palace: its block and its tower; b1 first, if you're in it).
const HOLES := """
varying vec3 hole_p;
uniform mat4 b0_inv;
uniform vec4 b0_dim;
uniform ivec4 b0_n;
uniform int b0_rows = 1;
uniform sampler2D b0_alive : filter_nearest;
uniform vec4 b0_roof;
uniform sampler2D b0_roof_on : filter_nearest;
uniform mat4 b1_inv;
uniform vec4 b1_dim;
uniform ivec4 b1_n;
uniform int b1_rows = 1;
uniform sampler2D b1_alive : filter_nearest;
uniform vec4 b1_roof;
uniform sampler2D b1_roof_on : filter_nearest;

// -1: not on this box; 0: standing; 1: knocked out
int hole_at(vec3 p, mat4 inv, vec4 dim, ivec4 n, int rows, sampler2D alive, vec4 roof, sampler2D roof_on, float margin) {
	if (dim.w < 0.5) { return -1; }
	vec3 q = (inv * vec4(p, 1.0)).xyz;
	float hw = dim.x;
	float hd = dim.y;
	float h = dim.z;
	float dx = hw - abs(q.x);
	float dz = hd - abs(q.z);
	if (dx < -margin || dz < -margin) { return -1; }
	if (q.y > h - 0.3 && min(dx, dz) > 0.55) {
		ivec2 t = ivec2(floor((p.xz - roof.xy) / 2.0));
		if (t.x < 0 || t.y < 0 || t.x >= int(roof.z) || t.y >= int(roof.w)) { return 0; }
		return texelFetch(roof_on, t, 0).r < 0.5 ? 1 : 0;
	}
	int side = 0;
	float along = 0.0;
	float len = 2.0 * hw;
	if (dx < dz) {
		side = q.x > 0.0 ? 1 : 3;
		len = 2.0 * hd;
		along = q.x > 0.0 ? q.z + hd : hd - q.z;
	} else {
		side = q.z > 0.0 ? 2 : 0;
		along = q.z > 0.0 ? hw - q.x : q.x + hw;
	}
	int off = 0;
	int ns = n.x;
	if (side >= 1) { off += n.x; ns = n.y; }
	if (side >= 2) { off += n.y; ns = n.z; }
	if (side >= 3) { off += n.z; ns = n.w; }
	int c = off + clamp(int(floor(along / (len / float(ns)))), 0, ns - 1);
	int r = clamp(int(floor(q.y / (h / float(rows)))), 0, rows - 1);
	return texelFetch(alive, ivec2(c, r), 0).r < 0.5 ? 1 : 0;
}

bool holed(vec3 p) {
	int a = hole_at(p, b1_inv, b1_dim, b1_n, b1_rows, b1_alive, b1_roof, b1_roof_on, 0.4);
	if (a >= 0) { return a == 1; }
	return hole_at(p, b0_inv, b0_dim, b0_n, b0_rows, b0_alive, b0_roof, b0_roof_on, 2.0) == 1;
}
"""

## (SkModels.baked_material as a shader: its colours, srgb, as rough)
const BAKED := """
shader_type spatial;
render_mode cull_back;

void vertex() {
}

void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
	ROUGHNESS = 0.8;
}
"""

## Its look with the holes put in: [ShaderMaterial] per material it had (the model's meshes given those).
static func holed(node: Node3D) -> Array:
	var made := {}
	var out := []
	for mi in SkModels._mesh_instances(node, []):
		var m := (mi as MeshInstance3D).material_override
		if not (m == SkModels.baked_material() or m is ShaderMaterial):
			continue                       # (only the looks it knows how to put holes in)
		if made.has(m):
			(mi as MeshInstance3D).material_override = made[m]
			continue
		var code := BAKED
		var hm := ShaderMaterial.new()
		if m is ShaderMaterial:
			code = ((m as ShaderMaterial).shader as Shader).code
			for u in RenderingServer.get_shader_parameter_list(((m as ShaderMaterial).shader as Shader).get_rid()):
				hm.set_shader_parameter(u.name, (m as ShaderMaterial).get_shader_parameter(u.name))
		var at := code.find("\n", code.find("render_mode") if code.contains("render_mode") else code.find("shader_type"))
		code = code.insert(at + 1, HOLES)
		code = code.replace("void vertex() {", "void vertex() {\n\thole_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;")
		code = code.replace("void fragment() {", "void fragment() {\n\tif (holed(hole_p)) { discard; }")
		var sh := Shader.new()
		sh.code = code
		hm.shader = sh
		made[m] = hm
		out.append(hm)
		(mi as MeshInstance3D).material_override = hm
	return out

## Built again, as new (the next visit).
func reset() -> void:
	for b in list:
		b.reset()
	_fall.clear()
	_fall_mm.multimesh.visible_instance_count = 0

## The building a ray hit, if it was one of these.
func of(collider: Object) -> Building:
	if collider is StaticBody3D and (collider as Node).has_meta("breakable"):
		return list[int((collider as Node).get_meta("breakable"))]
	return null

## A shot hit the world (VoxelArena.fire): a block out where it went in, if that's one of these.
func shot(wh: Dictionary, dir: Vector3) -> bool:
	var b := of(wh.get("collider"))
	if b == null:
		return false
	var cs := (wh.collider as CollisionObject3D).shape_owner_get_owner((wh.collider as CollisionObject3D).shape_find_owner(int(wh.shape)))
	if cs == null or not (cs as Node).has_meta("col"):
		return false
	var col := int((cs as Node).get_meta("col"))
	var row := clampi(floori(((wh.position as Vector3).y) / b.bh), 0, b.rows - 1)
	b.knock([[col, row]], dir)
	return true

## A blast at p (a grenade's, VoxelWeaponGrenades.explode): the blocks within r of it gone, and the roof tiles.
func blast(p: Vector3, r: float) -> void:
	for b in list:
		if not b.near(p, r + 2.0):
			continue
		var out := []
		for c in b.cols.size():
			var mid: Vector3 = b.cols[c].mid
			if Vector2(mid.x - p.x, mid.z - p.z).length() > r + b.cw(c):
				continue
			for row in b.rows:
				if b.alive[c * b.rows + row] and b.block_at(c, row).distance_to(p) < r:
					out.append([c, row])
		if not out.is_empty():
			b.knock(out, Vector3.ZERO, p)
		b.roof_blast(p, r)

func _process(dt: float) -> void:
	if _fall.is_empty():
		return
	var mm := _fall_mm.multimesh
	var i := 0
	while i < _fall.size():
		var f: Dictionary = _fall[i]
		f.v = (f.v as Vector3) + Vector3(0, -9.8, 0) * dt
		f.at = (f.at as Vector3) + (f.v as Vector3) * dt
		f.basis = (f.basis as Basis).rotated((f.spin as Vector3).normalized(), (f.spin as Vector3).length() * dt).orthonormalized()
		if (f.at as Vector3).y < (f.size as Vector3).y * 0.5:
			_smash(f.at, f.col, f.v)
			_fall.remove_at(i)
			continue
		i += 1
	mm.visible_instance_count = _fall.size()
	for k in _fall.size():
		var f: Dictionary = _fall[k]
		mm.set_instance_transform(k, Transform3D((f.basis as Basis).scaled(f.size), f.at))
		mm.set_instance_color(k, f.col)

## A block coming down from at (world), its size and colour.
func drop(at: Vector3, size: Vector3, col: Color, push: Vector3) -> void:
	if _fall.size() >= FALL_MAX:
		_smash(at, col, push)
		return
	_fall.append({"at": at, "v": push + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.8), randf_range(-0.6, 0.6)),
		"spin": Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)), "basis": Basis(Vector3.UP, randf() * TAU),
		"size": size, "col": col})

## A block burst into the voxel game's cubes.
func _smash(at: Vector3, col: Color, dir: Vector3) -> void:
	var a := sk.arena
	if a == null or a.debris == null:
		return
	var bits := []
	for k in CUBES:
		var c := col.darkened(randf_range(0.0, 0.15)) if k % 3 else col.lightened(0.06)
		_cols[c.to_rgba32()] = true
		bits.append({"pos": at + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), "col": c})
	a.debris.burst(bits, dir.normalized() if dir.length() > 0.1 else Vector3.UP, 2.5)

# ================================================================ one building

class Building:
	var owner: VoxelBreakables
	var data: Dictionary
	var ring: PackedVector2Array
	var h := 3.0
	var col := Color.WHITE
	var rows := 1
	var bh := 1.0                 # a block's height
	var cols: Array = []          # per column along the walls (round the outline, in order): {a, dir, w, n (out), mid, glass}
	var alive := PackedByteArray()          # [col * rows + row]
	var standing := 0
	var whole := true             # not hit yet: drawn as the St Kilda game draws it
	var root: Node3D
	var pretty: Node3D
	var blocks: MultiMeshInstance3D
	var roof: MultiMeshInstance3D
	var roof_tiles: Array = []    # Vector3 middles
	var roof_on := PackedByteArray()
	var roof_col := Color.GRAY
	var body: StaticBody3D
	var _shapes: Array = []       # per column: its CollisionShape3Ds
	var _box := AABB()
	var windows := true           # (a window every other block, the middle row of three: the town's, not Luna Park's)
	var partners: Array = []      # (the other boxes of the same park model: all to blocks together)
	var over := false             # a park model's: it stays, with holes in it (VoxelBreakables.HOLES), blocks behind
	var _mats: Array = []
	var _hk := ""
	var _alive_img: Image
	var _alive_tex: ImageTexture
	var _roof_img: Image
	var _roof_tex: ImageTexture
	var _roof_grid := Vector2i.ZERO
	var _signs: Array = []        # [[Label3D, the block behind it]]
	var _bulbs: Array = []        # [[MultiMesh, instance, its transform, the block it's on]]

	func make(o: VoxelBreakables, bd: Dictionary) -> void:
		owner = o
		data = bd
		ring = VoxelBreakables._ring(bd)
		var town := o.sk.town
		var kind := String(bd.k)
		h = float(bd.h)
		if kind in SkFacades.HOUSES and ring.size() <= 12:
			h = 2.9 if h < 6.5 else 5.8
		var pal := SkTownBuilder._palette(kind, absf(SkTownBuilder._ring_area(ring)))
		col = Color(bd.c) if bd.has("c") else pal[hash(bd.p[0]) % pal.size()]
		roof_col = SkTownBuilder.FLAT_ROOFS[hash(ring[0]) % SkTownBuilder.FLAT_ROOFS.size()]
		root = Node3D.new()
		root.name = String(bd.get("id", "Building"))
		o.add_child(root)
		# as the St Kilda game draws it (until it's hit)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var fronts := SkFacades.new(town)
		town._block(st, PackedVector3Array(), ring, float(bd.h), col, fronts, kind, bd.get("s", []).map(func(x): return int(x)),
				String(bd.get("f", "")), String(bd.get("bands", "")))
		pretty = Node3D.new()
		pretty.name = "AsDrawn"
		root.add_child(pretty)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = SkModels.baked_material()
		pretty.add_child(mi)
		fronts.commit(pretty)
		_shape(o)

	## One of Luna Park's own (the owner, 30 Oct: "just do the ones in luna park"): the park's own model (node) looks
	## as it is till it's hit, then this box of it (ring, tall) goes to blocks in colour c, and the model's put away.
	func make_over(o: VoxelBreakables, node: Node3D, nm: String, r: PackedVector2Array, tall: float, c: Color) -> void:
		owner = o
		data = {"id": nm, "n": nm, "k": "luna"}
		ring = r
		h = tall
		col = c
		roof_col = c.darkened(0.35)
		windows = false
		root = Node3D.new()
		root.name = nm
		o.add_child(root)
		pretty = node
		over = true
		_shape(o)

	## The park model's holes: which of its two boxes this is (k), the box's ground (world to its own: x across, z
	## deep, y up from the ground), half its width and depth. The model's signs go when the block behind them does.
	func holes_on(mats: Array, k: int, inv: Transform3D, hw: float, hd: float) -> void:
		_mats = mats
		_hk = "b%d_" % k
		var per := Vector4i.ZERO
		var side := 0
		var last := Vector2.INF
		for c in cols.size():
			var d: Vector2 = cols[c].dir
			if c > 0 and not d.is_equal_approx(last):
				side += 1
			last = d
			per[mini(side, 3)] += 1
		_alive_img = Image.create(cols.size(), rows, false, Image.FORMAT_R8)
		_alive_tex = ImageTexture.create_from_image(_alive_img)
		var lo := Vector2(_box.position.x, _box.position.z)
		_roof_grid = Vector2i(ceili(_box.size.x / TILE) + 1, ceili(_box.size.z / TILE) + 1)
		_roof_img = Image.create(_roof_grid.x, _roof_grid.y, false, Image.FORMAT_R8)
		_roof_img.fill(Color.WHITE)
		_roof_tex = ImageTexture.create_from_image(_roof_img)
		for m in _mats:
			var sm := m as ShaderMaterial
			sm.set_shader_parameter(_hk + "inv", Projection(inv))
			sm.set_shader_parameter(_hk + "dim", Vector4(hw, hd, h, 1.0))
			sm.set_shader_parameter(_hk + "n", per)
			sm.set_shader_parameter(_hk + "rows", rows)
			sm.set_shader_parameter(_hk + "alive", _alive_tex)
			sm.set_shader_parameter(_hk + "roof", Vector4(lo.x, lo.y, _roof_grid.x, _roof_grid.y))
			sm.set_shader_parameter(_hk + "roof_on", _roof_tex)
		for l in pretty.find_children("*", "Label3D", true, false):
			var at := (l as Node3D).global_position
			var best := INF
			var bi := -1
			for c in cols.size():
				for r in rows:
					var dd := block_at(c, r).distance_to(at)
					if dd < best:
						best = dd
						bi = c * rows + r
			if best < 3.0:
				_signs.append([l, bi])
		# (and its bulbs, the Ghost Train's eyes: each goes with the block it's on)
		for mmi in pretty.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := (mmi as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				var xf := mm.get_instance_transform(i)
				var at := (mmi as Node3D).global_transform * xf.origin
				var best := INF
				var bi := -1
				for c in cols.size():
					var r := clampi(floori(at.y / bh), 0, rows - 1)
					var dd := block_at(c, r).distance_to(at)
					if dd < best:
						best = dd
						bi = c * rows + r
				if best < 1.5:
					_bulbs.append([mm, i, xf, bi])
		_holes()

	# the model's holes as the blocks are now
	func _holes() -> void:
		if _alive_img == null:
			return
		for c in cols.size():
			for r in rows:
				_alive_img.set_pixel(c, r, Color.WHITE if alive[c * rows + r] else Color.BLACK)
		_alive_tex.update(_alive_img)
		var lo := Vector2(_box.position.x, _box.position.z)
		for i in roof_tiles.size():
			var t: Vector3 = roof_tiles[i]
			var g := Vector2i(floori((t.x - lo.x) / TILE), floori((t.z - lo.y) / TILE))
			if g.x >= 0 and g.y >= 0 and g.x < _roof_grid.x and g.y < _roof_grid.y:
				_roof_img.set_pixel(g.x, g.y, Color.WHITE if roof_on[i] else Color.BLACK)
		_roof_tex.update(_roof_img)
		for s in _signs:
			(s[0] as Node3D).visible = alive[int(s[1])] == 1
		for bb in _bulbs:
			var xf: Transform3D = bb[2]
			(bb[0] as MultiMesh).set_instance_transform(int(bb[1]), xf if alive[int(bb[3])] == 1 else xf.scaled_local(Vector3.ZERO))

	# its blocks, roof tiles and walls to stop you and the shots (ring, h, col set)
	func _shape(o: VoxelBreakables) -> void:
		rows = maxi(1, roundi(h / (SkFacades.STOREY / 3.0)))
		bh = h / rows
		for k in ring.size():
			var a := ring[k]
			var b := ring[(k + 1) % ring.size()]
			var d := b - a
			if d.length() < 0.05:
				continue
			var n2 := d.normalized().orthogonal()
			if Geometry2D.is_point_in_polygon((a + b) / 2.0 + n2 * 0.05, ring):
				n2 = -n2
			var n := maxi(1, roundi(d.length() / BLOCK))
			var w := d.length() / n
			for i in n:
				var at := a + d.normalized() * (i + 0.5) * w
				cols.append({"a": at, "dir": d.normalized(), "w": w, "n": n2,
					"mid": Vector3(at.x - n2.x * THICK * 0.5, h * 0.5, at.y - n2.y * THICK * 0.5),
					"glass": windows and (i % 2 == 1) and n >= 3 and i < n - 1, "shade": absf(n2.x) > absf(n2.y)})
		var lo := Vector2(INF, INF)
		var hi := -lo
		for v in ring:
			lo = lo.min(v)
			hi = hi.max(v)
		_box = AABB(Vector3(lo.x, 0, lo.y), Vector3(hi.x - lo.x, h, hi.y - lo.y))
		var y := lo.y + TILE * 0.5
		while y < hi.y:
			var x := lo.x + TILE * 0.5
			while x < hi.x:
				if Geometry2D.is_point_in_polygon(Vector2(x, y), ring):
					roof_tiles.append(Vector3(x, h - 0.15, y))
				x += TILE
			y += TILE
		# in blocks (after)
		blocks = _mm_node("Blocks", cols.size() * rows)
		roof = _mm_node("Roof", roof_tiles.size())
		body = StaticBody3D.new()
		body.name = "Walls"
		body.collision_layer = 1 | SkData.LAYER_WORLD
		body.collision_mask = 0
		body.set_meta("breakable", o.list.size())
		root.add_child(body)
		_shapes.resize(cols.size())
		reset()

	func _mm_node(nm: String, n: int) -> MultiMeshInstance3D:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var bm := BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		bm.material = mat
		mm.mesh = bm
		mm.instance_count = n
		var mmi := MultiMeshInstance3D.new()
		mmi.name = nm
		mmi.multimesh = mm
		mmi.visible = false
		root.add_child(mmi)
		return mmi

	func reset() -> void:
		whole = true
		alive.resize(cols.size() * rows)
		alive.fill(1)
		standing = alive.size()
		roof_on.resize(roof_tiles.size())
		roof_on.fill(1)
		pretty.visible = true
		blocks.visible = false
		roof.visible = false
		for c in cols.size():
			_column(c)
		_holes()

	func near(p: Vector3, r: float) -> bool:
		return _box.grow(r).has_point(p)

	func cw(c: int) -> float:
		return float(cols[c].w)

	## A block's middle (world).
	func block_at(c: int, row: int) -> Vector3:
		var cc: Dictionary = cols[c]
		var n: Vector2 = cc.n
		var a: Vector2 = cc.a
		return Vector3(a.x - n.x * THICK * 0.5, (row + 0.5) * bh, a.y - n.y * THICK * 0.5)

	func _block_xf(c: int, row: int) -> Transform3D:
		var cc: Dictionary = cols[c]
		var d: Vector2 = cc.dir
		var n: Vector2 = cc.n
		var bx := Basis(Vector3(d.x, 0, d.y) * float(cc.w), Vector3.UP * bh, Vector3(-n.x, 0, -n.y) * THICK)
		return Transform3D(bx, block_at(c, row))

	func _block_col(c: int, row: int) -> Color:
		var cc: Dictionary = cols[c]
		var k := row % 3
		var c0 := col.darkened(0.3 if bool(cc.shade) else 0.18)     # (as dark as the drawn walls look, lit the same)
		if bool(cc.glass) and k == 1 and rows >= 2:
			return GLASS
		var j := hash(Vector2i(c, row)) % 7
		return c0.darkened(0.03 * (j % 3)).lightened(0.02 * int(j == 5))

	## Knock these blocks out ([col, row] each): burst into cubes; then whatever's left hanging falls.
	func knock(which: Array, dir: Vector3, from := Vector3.INF) -> void:
		if whole:
			_to_blocks()
		var touched := {}
		for cr in which:
			var i: int = cr[0] * rows + cr[1]
			if alive[i] == 0:
				continue
			alive[i] = 0
			standing -= 1
			var at := block_at(cr[0], cr[1])
			var push := dir * 3.0 if from == Vector3.INF else (at - from).normalized() * 5.0
			owner._smash(at, _block_col(cr[0], cr[1]), push)
			touched[cr[0]] = true
		_hanging(touched)
		if float(standing) / alive.size() < ROOF_GOES:
			_roof_down()
		for c in touched:
			_column(c)
		_draw()
		if owner.sk.nav:
			owner.sk.nav.changed()         # (a way through, maybe: the walking map made again)

	## The roof tiles within r of p.
	func roof_blast(p: Vector3, r: float) -> void:
		var any := false
		for i in roof_tiles.size():
			if roof_on[i] and (roof_tiles[i] as Vector3).distance_to(p) < r:
				if whole:
					_to_blocks()
				roof_on[i] = 0
				owner._smash(roof_tiles[i], roof_col, Vector3.UP)
				any = true
		if any:
			_draw()

	func _to_blocks() -> void:
		whole = false
		pretty.visible = over             # (a park model stays: its holes show the blocks)
		blocks.visible = true
		roof.visible = true
		_draw()
		for p in partners:
			if p.whole:
				p._to_blocks()

	# Every block not held up: held is joined to the ground (the bottom row) through its neighbours (up, down, along,
	# round the corner), but only so far sideways: a wall bridges a gap of SPAN blocks each side at most (going up or down
	# a column costs nothing, along a row a block each), past that it comes down.
	func _hanging(touched: Dictionary) -> void:
		var cost := PackedInt32Array()
		cost.resize(alive.size())
		cost.fill(1 << 20)
		var now := PackedInt32Array()              # (a 0-1 search: the ones at this cost, then the next)
		for c in cols.size():
			if alive[c * rows]:
				cost[c * rows] = 0
				now.append(c * rows)
		var n := cols.size()
		for k in SPAN + 1:
			var next := PackedInt32Array()
			while not now.is_empty():
				var i := now[now.size() - 1]
				now.remove_at(now.size() - 1)
				if cost[i] != k:
					continue
				var c := i / rows
				var r := i % rows
				for j in [i + 1 if r < rows - 1 else -1, i - 1 if r > 0 else -1]:
					if j >= 0 and alive[j] and cost[j] > k:
						cost[j] = k
						now.append(j)
				for j in [((c + 1) % n) * rows + r, ((c - 1 + n) % n) * rows + r]:
					if alive[j] and cost[j] > k + 1:
						cost[j] = k + 1
						next.append(j)
			now = next
		for i in alive.size():
			if alive[i] and cost[i] > SPAN:
				alive[i] = 0
				standing -= 1
				var c := i / rows
				var r := i % rows
				var xf := _block_xf(c, r)
				owner.drop(xf.origin, Vector3(float(cols[c].w), bh, THICK), _block_col(c, r), Vector3.ZERO)
				touched[c] = true

	func _roof_down() -> void:
		var k := 0
		for i in roof_tiles.size():
			if roof_on[i]:
				roof_on[i] = 0
				k += 1
				owner.drop(roof_tiles[i], Vector3(TILE, 0.3, TILE), roof_col, Vector3.ZERO)

	func _draw() -> void:
		var mm := blocks.multimesh
		var k := 0
		for c in cols.size():
			for r in rows:
				if alive[c * rows + r]:
					var xf := _block_xf(c, r)
					if over:
						# (just inside the model's skin and under its top: seen only through the holes)
						var n: Vector2 = cols[c].n
						xf = Transform3D(Basis(xf.basis.x * 0.98, xf.basis.y * 0.98, xf.basis.z * 0.8),
								xf.origin - Vector3(n.x, 0, n.y) * THICK * 0.1 - Vector3(0, 0.02, 0))
					mm.set_instance_transform(k, xf)
					mm.set_instance_color(k, _block_col(c, r))
					owner._cols[_block_col(c, r).to_rgba32()] = true
					k += 1
		mm.visible_instance_count = k
		var rm := roof.multimesh
		k = 0
		for i in roof_tiles.size():
			if roof_on[i]:
				rm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(TILE, 0.3, TILE)), roof_tiles[i] - Vector3(0, 0.06 if over else 0.0, 0)))
				rm.set_instance_color(k, roof_col)
				k += 1
		rm.visible_instance_count = k
		_holes()

	# a column's collision: a box for each run of blocks still there
	func _column(c: int) -> void:
		for s in (_shapes[c] if _shapes[c] != null else []):
			(s as Node).free()
		var mine := []
		var r := 0
		while r < rows:
			if not alive[c * rows + r]:
				r += 1
				continue
			var r0 := r
			while r < rows and alive[c * rows + r]:
				r += 1
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(float(cols[c].w) + 0.02, (r - r0) * bh, THICK)
			cs.shape = box
			var xf := _block_xf(c, r0)
			cs.transform = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3(0, ((r - r0) - 1) * bh * 0.5, 0))
			cs.set_meta("col", c)
			body.add_child(cs)
			mine.append(cs)
		_shapes[c] = mine
