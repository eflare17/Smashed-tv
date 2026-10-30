class_name VoxelBreakables
extends Node3D
## St Kilda's buildings you can smash (the owner, 29 Oct: "distructable building"): the map's buildings in the slice
## round Luna Park (Cafe Luna's neighbours, the Palais, the flats and shops on the Esplanade), not Mr Moon, the
## coaster or the rides. Each looks just as the St Kilda game draws it (its own copy of the town's walls, windows and
## roof) until it's first hit; then it's swapped for its walls in blocks about BLOCK m across (its colours, a window
## where the storeys' windows are) and a roof of tiles. A bullet knocks a block out, the shotgun a few (a block a
## pellet), a blast a round hole; the block breaks into bricks that fall and pile up (the vacuum takes them: Brick). A block
## with nothing joining it down to the ground (round any way: up the wall, along it, round a corner) falls, and smashes
## where it lands; knock enough of a building's walls out and its roof comes down. It's all built again the next time
## you come (VoxelStKilda.home resets it). The walls stand on columns of box shapes (a shape a run of blocks), so you
## and the shots stop at them before and after. Luna Park's own buildings too (add_park: the Ghost Train, Luna Palace,
## the shops): those keep their own model, holes cut in it where blocks go, the blocks behind showing through.

const BLOCK := 1.0              # a block's width along a wall (m; each wall's own share of that)
const THICK := 0.8              # a wall's thickness
const TILE := 2.0               # a roof tile
const GLASS := Color("#1d3563")         # (the St Kilda game's window blue)
const FALL_MAX := 500           # blocks falling at once (more: they burst where they are)
const ROOF_GOES := 0.55         # the roof falls in when less than this of the walls are standing
const SPAN := 4                # blocks a wall bridges over a gap, each side (more and it falls)
const BRICK := 0.125            # a brick's face, about (a block breaks into its width and height in these, and its depth in BRICK_D)
const BRICK_D := 0.27           # a brick's depth, about
const SX := 8                   # bricks across a block (its wall's share of BLOCK), and up it: about its height in BRICKs
const KNOCK_LEFT := 0.35        # a block with less than this of its bricks left goes: the rest drop out
const CRUMBLE := 0.12           # the share of bricks that crumble to cubes instead
const FLY_MAX := 4000           # bricks flying at once (more: they drop straight onto the pile under them)
const LIE_MAX := 150000         # bricks lying about (more: they crumble)
const PILE := 0.3               # a pile's floor cell
const NO_SHOPS :=["w1000251780", "w1000251784"]   # (Cafe Luna, the Gift Shop: Luna Park's own shop is on that outline)

var sk: VoxelStKilda
var list: Array[Building] = []
var _fall_mm: MultiMeshInstance3D
var _fall: Array = []           # [{at, v, spin, basis, size, col, paint}]
# bricks (the owner, 30 Oct: "like how the characters are ... brick size", "most fall"): a knocked-out block, or one
# that's fallen and landed, breaks into pieces about BRICK across, each the colour of the wall where it was; they fly,
# bounce and lie where they stop, piled up, till the next visit. A few just crumble (the voxel game's little cubes).
var _fly_mm: MultiMeshInstance3D
var _fp := PackedVector3Array()   # flying: where, how fast, size, spin, which way up, colour
var _fv := PackedVector3Array()
var _fs := PackedVector3Array()
var _fspin := PackedVector3Array()
var _fb: Array[Basis] = []
var _fc := PackedColorArray()
var _fbuf := PackedFloat32Array()
var _lie_mm: MultiMeshInstance3D
var _lp := PackedVector3Array()   # lying: where, colour, how tall a part of its pile
var _lc := PackedColorArray()
var _lh := PackedFloat32Array()
var _cells := {}                  # PILE m floor cell -> PackedInt32Array of the bricks lying there
var _heights := {}                # PILE m floor cell -> how high the pile there is
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
	_fall_mm = _mm_of(FALL_MAX)
	_fly_mm = _mm_of(FLY_MAX)
	_lie_mm = _mm_of(LIE_MAX)
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
	_fp.clear()
	_fv.clear()
	_fs.clear()
	_fspin.clear()
	_fb.clear()
	_fc.clear()
	_fly_mm.multimesh.visible_instance_count = 0
	_lp.clear()
	_lc.clear()
	_lh.clear()
	_cells.clear()
	_heights.clear()
	_lie_mm.multimesh.visible_instance_count = 0

func _mm_of(n: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true      # (the colours are as written, like the models' own paint)
	mat.roughness = 0.95
	bm.material = mat
	mm.mesh = bm
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mmi

## The building a ray hit, if it was one of these.
func of(collider: Object) -> Building:
	if collider is StaticBody3D and (collider as Node).has_meta("breakable"):
		return list[int((collider as Node).get_meta("breakable"))]
	return null

## A shot hit the world (VoxelArena.fire): a block out where it went in, if that's one of these.
func shot(wh: Dictionary, dir: Vector3, dmg := 1.0 / 3.0) -> bool:
	var b := of(wh.get("collider"))
	if b == null:
		return false
	var cs := (wh.collider as CollisionObject3D).shape_owner_get_owner((wh.collider as CollisionObject3D).shape_find_owner(int(wh.shape)))
	if cs == null or not (cs as Node).has_meta("col"):
		return false
	var col := int((cs as Node).get_meta("col"))
	var row := clampi(floori(((wh.position as Vector3).y) / b.bh), 0, b.rows - 1)
	b.hit(col, row, dmg, wh.position, dir)
	return true

## A blast at p (a grenade's, VoxelWeaponGrenades.explode): the bricks within r of it gone (a round hole), and the roof tiles.
func blast(p: Vector3, r: float) -> void:
	for b in list:
		if not b.near(p, r + 2.0):
			continue
		b.blast_bricks(p, r)
		b.roof_blast(p, r)

func _process(dt: float) -> void:
	if not _fall.is_empty():
		_falling(dt)
	if not _fp.is_empty():
		_flying(dt)
	if _lie_mm.multimesh.visible_instance_count != _lp.size():
		_lie_mm.multimesh.visible_instance_count = _lp.size()     # (once a frame, all those laid since)
	if _lp.size() > 0 and sk.arena and sk.arena.debris and sk.arena.debris.brush != Vector3.INF:
		_vacuum(sk.arena.debris.brush, sk.arena.debris.brush_r)

func _falling(dt: float) -> void:
	var mm := _fall_mm.multimesh
	var i := 0
	while i < _fall.size():
		var f: Dictionary = _fall[i]
		f.v = (f.v as Vector3) + Vector3(0, -9.8, 0) * dt
		f.at = (f.at as Vector3) + (f.v as Vector3) * dt
		f.basis = (f.basis as Basis).rotated((f.spin as Vector3).normalized(), (f.spin as Vector3).length() * dt).orthonormalized()
		if (f.at as Vector3).y < (f.size as Vector3).y * 0.5:
			# landed: in bricks, each the colour it was up on the wall
			var v: Vector3 = f.v
			bricks(Transform3D((f.basis as Basis).scaled(f.size), f.at), f.col, f.paint, Vector3(v.x * 0.5, -v.y * 0.25, v.z * 0.5), 1.5, f.piece)
			_fall.remove_at(i)
			continue
		i += 1
	mm.visible_instance_count = _fall.size()
	for k in _fall.size():
		var f: Dictionary = _fall[k]
		mm.set_instance_transform(k, Transform3D((f.basis as Basis).scaled(f.size), f.at))
		mm.set_instance_color(k, f.col)

## A block coming down from at (world), its size and colour; paint: its bricks' colours (Building.paint_of), or none.
func drop(at: Vector3, size: Vector3, col: Color, push: Vector3, paint := PackedColorArray(), basis := Basis.IDENTITY, piece := BRICK) -> void:
	var xf := Transform3D(basis.scaled(size), at)
	if _fall.size() >= FALL_MAX:
		bricks(xf, col, paint, push, 2.0, piece)
		return
	_fall.append({"at": at, "v": push + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.8), randf_range(-0.6, 0.6)),
		"spin": Vector3(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)), "basis": basis,
		"size": size, "col": col, "paint": paint, "piece": piece})

## How many bricks a box (its basis scaled to its size) breaks into, each way: about BRICK each, one through anything thin.
static func brick_grid(xf: Transform3D, piece := BRICK) -> Vector3i:
	var s := xf.basis.get_scale()
	return Vector3i(maxi(1, roundi(s.x / piece)), maxi(1, roundi(s.y / piece)), maxi(1, roundi(s.z / (BRICK_D * piece / BRICK))))

## A box (xf: its basis scaled to its size, the middle at its origin) broken into bricks that fly off with push (and a
## spread about of `spread` m/s); paint, if any, the colour of each in turn (brick_grid's x, then y, then z), else col.
func bricks(xf: Transform3D, col: Color, paint: PackedColorArray, push: Vector3, spread: float, piece_m := BRICK) -> void:
	# (a lot in the air already, a big collapse: the rest in bigger chunks, so there aren't more than the game can move)
	var load := float(_fp.size()) / FLY_MAX
	var coarse := 1.0 if load < 0.2 else (2.0 if load < 0.5 else 3.0)
	var g0 := brick_grid(xf, piece_m)
	var g := brick_grid(xf, piece_m * coarse)
	var piece := Vector3(1.0 / g.x, 1.0 / g.y, 1.0 / g.z)
	var size := xf.basis.get_scale() * piece
	var turn := xf.basis.orthonormalized()
	var dust := []
	for z in g.z:
		for y in g.y:
			for x in g.x:
				var k := (mini(int((z + 0.5) * g0.z / g.z), g0.z - 1) * g0.y + mini(int((y + 0.5) * g0.y / g.y), g0.y - 1)) * g0.x \
						+ mini(int((x + 0.5) * g0.x / g.x), g0.x - 1)
				var c := paint[k] if k < paint.size() and paint[k].a > 0.0 else col
				var at := xf * (Vector3((x + 0.5) * piece.x, (y + 0.5) * piece.y, (z + 0.5) * piece.z) - Vector3(0.5, 0.5, 0.5))
				c = c.darkened(randf_range(0.0, 0.08))
				_cols[c.to_rgba32()] = true
				if randf() < CRUMBLE:
					dust.append({"pos": at, "col": c})
					continue
				var sz := size * Vector3(randf_range(0.8, 0.97), randf_range(0.8, 0.97), randf_range(0.75, 0.95))
				var v := push * randf_range(0.6, 1.2) + Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 1)) * spread
				if _fp.size() >= FLY_MAX:
					_lay(at, sz, c, turn)
					continue
				_fp.append(at)
				_fv.append(v)
				_fs.append(sz)
				_fspin.append(Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)))
				_fb.append(turn)
				_fc.append(c)
	if not dust.is_empty() and sk.arena and sk.arena.debris:
		sk.arena.debris.burst(dust, push.normalized() if push.length() > 0.1 else Vector3.UP, 2.0)

func _flying(dt: float) -> void:
	var mm := _fly_mm.multimesh
	var i := 0
	while i < _fp.size():
		var v := _fv[i] + Vector3(0, -9.8, 0) * dt
		var p := _fp[i] + v * dt
		var s := _fs[i]
		var floor_ := _height(p)
		if p.y - s.y * 0.5 <= floor_ and v.y < 0.0:
			if v.y < -2.5:
				# a bounce
				v = Vector3(v.x * 0.55, -v.y * 0.3, v.z * 0.55)
				_fspin[i] *= 0.5
				p.y = floor_ + s.y * 0.5
			else:
				_lay(p, s, _fc[i], _fb[i])
				var last := _fp.size() - 1
				_fp[i] = _fp[last]
				_fv[i] = _fv[last]
				_fs[i] = _fs[last]
				_fspin[i] = _fspin[last]
				_fb[i] = _fb[last]
				_fc[i] = _fc[last]
				_fp.resize(last)
				_fv.resize(last)
				_fs.resize(last)
				_fspin.resize(last)
				_fb.resize(last)
				_fc.resize(last)
				continue
		var sp := _fspin[i]
		_fb[i] = _fb[i].rotated(sp.normalized(), sp.length() * dt).orthonormalized() if sp.length() > 0.01 else _fb[i]
		_fv[i] = v
		_fp[i] = p
		i += 1
	# (all at once: the whole buffer, each a 3x4 transform and a colour)
	if _fbuf.size() != FLY_MAX * 16:
		_fbuf.resize(FLY_MAX * 16)
	for k in _fp.size():
		var b := _fb[k]
		var s := _fs[k]
		var p := _fp[k]
		var c := _fc[k]
		var o := k * 16
		_fbuf[o] = b.x.x * s.x
		_fbuf[o + 1] = b.y.x * s.y
		_fbuf[o + 2] = b.z.x * s.z
		_fbuf[o + 3] = p.x
		_fbuf[o + 4] = b.x.y * s.x
		_fbuf[o + 5] = b.y.y * s.y
		_fbuf[o + 6] = b.z.y * s.z
		_fbuf[o + 7] = p.y
		_fbuf[o + 8] = b.x.z * s.x
		_fbuf[o + 9] = b.y.z * s.y
		_fbuf[o + 10] = b.z.z * s.z
		_fbuf[o + 11] = p.z
		_fbuf[o + 12] = c.r
		_fbuf[o + 13] = c.g
		_fbuf[o + 14] = c.b
		_fbuf[o + 15] = c.a
	RenderingServer.multimesh_set_buffer(mm.get_rid(), _fbuf)
	mm.visible_instance_count = _fp.size()

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / PILE), floori(p.z / PILE))

## How high the pile under p is (the ground's 0).
func _height(p: Vector3) -> float:
	return float(_heights.get(_cell(p), 0.0))

## A brick come to rest at p (on top of the pile there), lying flat-ish, its long side the way it was going.
func _lay(p: Vector3, s: Vector3, c: Color, turn: Basis) -> void:
	if _lp.size() >= LIE_MAX:
		if sk.arena and sk.arena.debris:
			sk.arena.debris.burst([{"pos": p, "col": c}], Vector3.UP, 1.0)
		return
	# (down the side of the pile while it's too steep here: a heap, not a spike)
	for step in 8:
		var low := _height(p)
		var to := Vector3.ZERO
		for d in [Vector3(PILE, 0, 0), Vector3(-PILE, 0, 0), Vector3(0, 0, PILE), Vector3(0, 0, -PILE),
				Vector3(PILE, 0, PILE), Vector3(-PILE, 0, PILE), Vector3(PILE, 0, -PILE), Vector3(-PILE, 0, -PILE)]:
			var hh := _height(p + d)
			if hh < low - BRICK * 0.5:
				low = hh
				to = d
		if to == Vector3.ZERO:
			break
		p += to * randf_range(0.8, 1.2)
	var cell := _cell(p)
	var h := _height(p)
	var yaw := atan2(turn.x.x, turn.x.z) + randf_range(-0.3, 0.3)
	var b := Basis(Vector3.UP, yaw)
	if h > 0.05:
		b = b.rotated(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized(), randf_range(0.0, 0.35))
	var flat := minf(s.y, s.z)          # (it lies on its widest side)
	var size := Vector3(s.x, flat, maxf(s.y, s.z))
	var at := Vector3(p.x, h + flat * 0.5, p.z)
	var i := _lp.size()
	_lp.append(at)
	_lc.append(c)
	_lh.append(flat * 0.8)
	_heights[cell] = h + flat * 0.8
	if not _cells.has(cell):
		_cells[cell] = PackedInt32Array()
	(_cells[cell] as PackedInt32Array).append(i)
	var mm := _lie_mm.multimesh
	mm.set_instance_transform(i, Transform3D(b.scaled(size), at))
	mm.set_instance_color(i, c)

## The vacuum's brush at p: the bricks lying in it crumble into the voxel game's cubes, which it then sucks up (Brick).
func _vacuum(p: Vector3, r: float) -> void:
	var lo := _cell(p - Vector3(r, 0, r))
	var hi := _cell(p + Vector3(r, 0, r))
	var budget := 12
	var dust := []
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var cell := Vector2i(cx, cz)
			if not _cells.has(cell):
				continue
			var ids: PackedInt32Array = _cells[cell]
			while not ids.is_empty() and budget > 0:
				var i := ids[ids.size() - 1]
				if _lp[i].distance_to(p) > r + BRICK:
					break
				ids.resize(ids.size() - 1)
				budget -= 1
				_heights[cell] = maxf(0.0, float(_heights[cell]) - _lh[i])
				for k in 4:
					dust.append({"pos": _lp[i] + Vector3(randf_range(-0.08, 0.08), randf_range(-0.05, 0.05), randf_range(-0.08, 0.08)), "col": _lc[i]})
				_lie_mm.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), _lp[i]))
			_cells[cell] = ids
	if not dust.is_empty():
		sk.arena.debris.burst(dust, Vector3.UP, 0.5)

## How many bricks are lying about, and flying.
func bricks_lying() -> int:
	return _lp.size()

func bricks_flying() -> int:
	return _fp.size()

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
	var sy := 1                   # bricks up a block (SX across)
	var sub := PackedByteArray()            # [(col * rows + row) * SX * sy + y * SX + x]: each block's bricks there
	var left := PackedInt32Array()          # [col * rows + row]: its bricks there
	var damaged := PackedByteArray()        # [col * rows + row]: a brick or more gone (drawn brick by brick then)
	var chipped := 0                # bricks knocked out since it was last built
	var walls: MultiMeshInstance3D  # the damaged blocks' bricks
	var _sub_cols := {}             # block -> its bricks' colours (PackedColorArray, as sub)
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
	var _paint := {}              # (a park model's) PAINT m cell -> the colour of its paint there (its vertex colours)
	var _painted := false

	## The colour of each brick a block (xf, its wall facing n) breaks into, from the model's own paint on the outside of
	## it there (a park model's: the sign's green, a skeleton's white); empty for the town's (its blocks' colour does).
	func paint_of(xf: Transform3D, n: Vector2) -> PackedColorArray:
		var out := PackedColorArray()
		if not over:
			return out
		if not _painted:
			_paint_grid()
		var g := VoxelBreakables.brick_grid(xf)
		var out_n := Vector3(n.x, 0, n.y) * (THICK * 0.5 + 0.05)
		for z in g.z:
			for y in g.y:
				for x in g.x:
					var at := xf * (Vector3((x + 0.5) / g.x, (y + 0.5) / g.y, (z + 0.5) / g.z) - Vector3(0.5, 0.5, 0.5)) + out_n
					out.append(_paint_at(at))
		return out

	const PAINT := 0.2

	## A block's bricks' colour where there's no paint: a park model's own colour; the town's, its block's (written for
	## the blocks' paint, which takes colours as they're lit: the bricks', as written).
	func brick_col(c: int, row: int) -> Color:
		return col if over else _block_col(c, row).linear_to_srgb()

	func _paint_grid() -> void:
		_painted = true
		var box := _box.grow(1.5)
		for mi in pretty.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			if m == null or not (mi as MeshInstance3D).is_visible_in_tree():
				continue
			var gx := (mi as MeshInstance3D).global_transform
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				if arr[Mesh.ARRAY_COLOR] == null:
					continue
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
				if cs.size() != vs.size():
					continue
				# (all over each triangle, PAINT apart: a big plain wall has its vertices only at its corners)
				var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var tris := ix.size() / 3 if ix.size() > 0 else vs.size() / 3
				for t in tris:
					var i0 := ix[t * 3] if ix.size() > 0 else t * 3
					var a := gx * vs[i0]
					var b := gx * vs[ix[t * 3 + 1] if ix.size() > 0 else t * 3 + 1]
					var c := gx * vs[ix[t * 3 + 2] if ix.size() > 0 else t * 3 + 2]
					if not (box.has_point(a) or box.has_point(b) or box.has_point(c)):
						continue
					var steps := clampi(ceili(maxf(a.distance_to(b), a.distance_to(c)) / PAINT), 1, 60)
					for i in steps + 1:
						for j in steps + 1 - i:
							var p := a + (b - a) * (float(i) / steps) + (c - a) * (float(j) / steps)
							_paint[Vector3i((p / PAINT).floor())] = cs[i0]

	## The paint nearest p (a few cells round), or clear: none (the block's own colour then).
	func _paint_at(p: Vector3) -> Color:
		var at := Vector3i((p / PAINT).floor())
		if _paint.has(at):
			return _paint[at]
		var best := Color(0, 0, 0, 0)
		var far := 1 << 20
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for dz in range(-2, 3):
					var k := at + Vector3i(dx, dy, dz)
					var d := dx * dx + dy * dy + dz * dz
					if d < far and _paint.has(k):
						far = d
						best = _paint[k]
		return best

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
				_alive_img.set_pixel(c, r, Color.WHITE if alive[c * rows + r] and not damaged[c * rows + r] else Color.BLACK)
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
		sy = maxi(1, roundi(bh / BRICK))
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
		walls = _mm_node("Bricks", 0)
		((walls.multimesh.mesh as BoxMesh).material as StandardMaterial3D).vertex_color_is_srgb = true     # (paint as written)
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
		var per := SX * sy
		sub.resize(alive.size() * per)
		sub.fill(1)
		left.resize(alive.size())
		left.fill(per)
		damaged.resize(alive.size())
		damaged.fill(0)
		chipped = 0
		_sub_cols.clear()
		walls.visible = false
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

	## A shot into block [c, row] at p, going dir, dmg (VoxelArena.fire's "wall": the pistol a third, a shotgun pellet
	## less) the size of the bite: the bricks round where it went in knocked out, just those (the owner, 30 Oct: "i just
	## want it to blow out the small blocks"). Into a hole already: the nearest brick of that block still there.
	func hit(c: int, row: int, dmg: float, p: Vector3, dir: Vector3) -> void:
		var i := c * rows + row
		if alive[i] == 0:
			return
		var n: Vector2 = cols[c].n
		var push := Vector3(n.x, 0.3, n.y) * 1.5 - dir * 0.4
		var n3 := Vector3(n.x, 0, n.y)
		p -= n3 * (p - block_at(c, row)).dot(n3)          # (on the wall's middle, where its bricks' middles are)
		var out := _chip(c, row, p, 0.06 + dmg * 0.25, push, 0.8)
		if out < 0:
			knock([[c, row]], dir)
		elif out == 0:
			if _chip(c, row, p, 0.45, push, 0.8, true) < 0:
				knock([[c, row]], dir)
			else:
				_draw()
		else:
			_draw()

	## A blast at p, r: the bricks within r of it out, all round (a round hole); blocks with too few left go too.
	func blast_bricks(p: Vector3, r: float) -> void:
		var out := []
		var any := false
		for c in cols.size():
			var mid: Vector3 = cols[c].mid
			if Vector2(mid.x - p.x, mid.z - p.z).length() > r + cw(c):
				continue
			for row in rows:
				if alive[c * rows + row] and block_at(c, row).distance_to(p) < r + 0.8:
					var got := _chip(c, row, p, r, (block_at(c, row) - p).normalized() * 4.5 + Vector3.UP * 1.5, 2.0)
					if got < 0:
						out.append([c, row])
					elif got > 0:
						any = true
		if not out.is_empty():
			knock(out, Vector3.ZERO, p)
		elif any:
			_draw()

	## A brick's middle (world): block [c, row]'s brick x across, y up.
	func sub_at(c: int, row: int, x: int, y: int) -> Vector3:
		var d: Vector2 = cols[c].dir
		return block_at(c, row) + Vector3(d.x, 0, d.y) * (((x + 0.5) / SX - 0.5) * cw(c)) + Vector3.UP * (((y + 0.5) / sy - 0.5) * bh)

	# Block [c, row]'s bricks within r of p (nearest: just the nearest one within r) knocked out, flying off with push:
	# how many (-1: too few left now, the block's to go).
	func _chip(c: int, row: int, p: Vector3, r: float, push: Vector3, spread: float, nearest := false) -> int:
		var i := c * rows + row
		var per := SX * sy
		var d: Vector2 = cols[c].dir
		var bx := Basis(Vector3(d.x, 0, d.y), Vector3.UP, Vector3(-(cols[c].n as Vector2).x, 0, -(cols[c].n as Vector2).y))
		var piece := Vector3(cw(c) / SX, bh / sy, THICK)
		var gone := PackedInt32Array()
		var best := INF
		for y in sy:
			for x in SX:
				var k := i * per + y * SX + x
				if sub[k] == 0:
					continue
				var dd := sub_at(c, row, x, y).distance_to(p)
				if dd < r:
					if nearest:
						if dd < best:
							best = dd
							gone = PackedInt32Array([k])
					else:
						gone.append(k)
		if gone.is_empty():
			return 0
		if whole:
			_to_blocks()
		var cs := _cols_of(c, row)
		for k in gone:
			sub[k] = 0
			var j := k - i * per
			owner.bricks(Transform3D(bx.scaled(piece), sub_at(c, row, j % SX, j / SX)), cs[j], PackedColorArray(), push, spread)
		damaged[i] = 1
		left[i] -= gone.size()
		chipped += gone.size()
		if left[i] < per * KNOCK_LEFT:
			return -1
		return gone.size()

	# block [c, row]'s bricks' colours (its paint where it's a park model's, else its own), worked out the first time
	func _cols_of(c: int, row: int) -> PackedColorArray:
		var i := c * rows + row
		if _sub_cols.has(i):
			return _sub_cols[i]
		var out := PackedColorArray()
		var base := brick_col(c, row)
		var n: Vector2 = cols[c].n
		var to := Vector3(n.x, 0, n.y) * (THICK * 0.5 + 0.05)
		if over and not _painted:
			_paint_grid()
		for y in sy:
			for x in SX:
				var pc := _paint_at(sub_at(c, row, x, y) + to) if over else Color(0, 0, 0, 0)
				out.append(pc if pc.a > 0.0 else base)
		_sub_cols[i] = out
		return out

	# a damaged block that's going (knocked out or fallen): what's left of it in bricks, flying off with push
	func _rest(c: int, row: int, push: Vector3, spread: float) -> void:
		var i := c * rows + row
		var per := SX * sy
		var cs := _cols_of(c, row)
		var d: Vector2 = cols[c].dir
		var bx := Basis(Vector3(d.x, 0, d.y), Vector3.UP, Vector3(-(cols[c].n as Vector2).x, 0, -(cols[c].n as Vector2).y))
		var piece := Vector3(cw(c) / SX, bh / sy, THICK)
		for j in per:
			if sub[i * per + j]:
				sub[i * per + j] = 0
				owner.bricks(Transform3D(bx.scaled(piece), sub_at(c, row, j % SX, j / SX)), cs[j], PackedColorArray(), push, spread)

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
			var n: Vector2 = cols[cr[0]].n
			# (a shot: mostly spilling out of the wall at your feet, a little the way it went; a blast: away from it)
			var push := Vector3(n.x, 0.3, n.y) * 1.8 + dir * 0.8 if from == Vector3.INF else (at - from).normalized() * 5.0 + Vector3.UP * 1.5
			var xf := _block_xf(cr[0], cr[1])
			if damaged[i]:
				_rest(cr[0], cr[1], push * 0.5, 0.8 if from == Vector3.INF else 2.0)      # (what's left of it: a few bricks dropping out)
			else:
				owner.bricks(xf, brick_col(cr[0], cr[1]), paint_of(xf, n), push, 1.0 if from == Vector3.INF else 2.0)
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
				owner.bricks(Transform3D(Basis.IDENTITY.scaled(Vector3(TILE, 0.3, TILE)), roof_tiles[i]), roof_col.linear_to_srgb(), PackedColorArray(),
						((roof_tiles[i] as Vector3) - p).normalized() * 4.0 + Vector3.UP * 2.0, 1.5, BRICK * 2.0)
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
				var nn: Vector2 = cols[c].n
				if damaged[i]:
					_rest(c, r, Vector3(nn.x, 0, nn.y) * 0.5, 0.6)       # (a holed one: down in its bricks)
				else:
					owner.drop(xf.origin, Vector3(float(cols[c].w), bh, THICK), brick_col(c, r), Vector3(nn.x, 0, nn.y) * randf_range(0.0, 1.0),
							paint_of(xf, nn), xf.basis.orthonormalized())
				touched[c] = true

	func _roof_down() -> void:
		var k := 0
		for i in roof_tiles.size():
			if roof_on[i]:
				roof_on[i] = 0
				k += 1
				owner.drop(roof_tiles[i], Vector3(TILE, 0.3, TILE), roof_col.linear_to_srgb(), Vector3.ZERO, PackedColorArray(), Basis.IDENTITY, BRICK * 2.0)

	func _draw() -> void:
		var mm := blocks.multimesh
		var k := 0
		for c in cols.size():
			for r in rows:
				if alive[c * rows + r] and not damaged[c * rows + r]:
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
		_draw_bricks()
		var rm := roof.multimesh
		k = 0
		for i in roof_tiles.size():
			if roof_on[i]:
				rm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(TILE, 0.3, TILE)), roof_tiles[i] - Vector3(0, 0.06 if over else 0.0, 0)))
				rm.set_instance_color(k, roof_col)
				k += 1
		rm.visible_instance_count = k
		_holes()

	# the holed blocks, brick by brick: each a bar through the wall (so a hole's sides show), in its paint
	func _draw_bricks() -> void:
		var per := SX * sy
		var n_out := 0
		for i in alive.size():
			if alive[i] and damaged[i]:
				n_out += left[i]
		var mm := walls.multimesh
		walls.visible = n_out > 0
		if n_out == 0:
			mm.visible_instance_count = 0
			return
		if mm.instance_count < n_out:
			mm.instance_count = n_out + n_out / 2 + 256
		var buf := PackedFloat32Array()
		buf.resize(mm.instance_count * 16)
		var k := 0
		for i in alive.size():
			if not (alive[i] and damaged[i]):
				continue
			var c := i / rows
			var r := i % rows
			var d: Vector2 = cols[c].dir
			var n: Vector2 = cols[c].n
			var ax := Vector3(d.x, 0, d.y) * (cw(c) / SX)
			var ay := Vector3.UP * (bh / sy)
			var az := Vector3(-n.x, 0, -n.y) * THICK
			var cs := _cols_of(c, r)
			for j in per:
				if sub[i * per + j] == 0:
					continue
				var p := sub_at(c, r, j % SX, j / SX)
				var col_: Color = cs[j]
				var o := k * 16
				buf[o] = ax.x
				buf[o + 1] = ay.x
				buf[o + 2] = az.x
				buf[o + 3] = p.x
				buf[o + 4] = ax.y
				buf[o + 5] = ay.y
				buf[o + 6] = az.y
				buf[o + 7] = p.y
				buf[o + 8] = ax.z
				buf[o + 9] = ay.z
				buf[o + 10] = az.z
				buf[o + 11] = p.z
				buf[o + 12] = col_.r
				buf[o + 13] = col_.g
				buf[o + 14] = col_.b
				buf[o + 15] = 1.0
				k += 1
		mm.buffer = buf
		mm.visible_instance_count = k

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
