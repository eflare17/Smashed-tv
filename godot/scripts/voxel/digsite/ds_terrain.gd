class_name DsTerrain
extends Node3D
## The Dig Site's ground (stage 2): DigSiteGrid (C++: scripts/voxel/digsite/native) holds the cells, 12.5 cm blocks
## like the back yard's, 512 x 192 x 512 of them (64 m across, 24 m tall: the top 4 m air over the ground, 20 m deep
## to bedrock), made from a seed. Drawn in sections (32 x 64 x 32 cells) within R_MESH of a player (the whole site, at 64 m), and only
## the ones that changed rebuilt; collision only for the sections close to a player (they walk and dig in them). The
## building waits for the next frame past BUDGET_MS a frame, nearest first, so a big change never stalls the game.
## Owned by the voxel session.

const CELL := 0.125
const W := 512
const H := 192
const D := 512
const SURFACE := 160            # the ground's base level (cell y): 20 m of ground under it, 4 m of air over
const BUDGET_MS := 4.0          # building sections a frame, at most this long (more waits for the next frame)
const R_NOW := 20.0             # m (to a section's nearest side): changed sections this near a player are redrawn all together ...
const NOW_HZ := 15.0            # ... this often (a heap crossing from one section into the next shows in both at once:
                                # redrawn one at a time, nearest first, it vanished from one before it showed in the other)
const NOW_MS := 8.0            # ... but for no longer than this a frame: a huge change (a blast) carries on next frame
const R_MESH := 96.0            # metres from a player a section's drawn (the whole 64 m site from anywhere on it: a hole in the far ground shows the sky) ...
const R_COL := 12.0             # ... and solid
const R_DROP := 110.0           # (and its drawing let go past this: the site's let go once you're well away)
const SETTLE_HZ := 20.0         # the dirt's ticks a second (stage 4: loose dirt falls and slumps, tall walls give way)
const SETTLE_US := 2500         # ... each at most this long (the rest waits for the next)
const SW := 32                  # a section's cells across (x, z) and up (DigSiteGrid's SW, SH)
const SH := 64

var grid: DigSiteGrid
var origin := Vector3.ZERO      # the grid's corner (lowest x, y, z) in the world
var site: Node3D                # DigSite
var _mat: Material
var _sec := {}                  # section index -> {mi: MeshInstance3D or null, body: StaticBody3D or null, faces: PackedVector3Array}
var _dirty := {}                # section index -> true: changed since it was built
var _dims := Vector3i.ZERO
var built_n := 0                # (tests: sections built so far)
var settle_on := true           # (the dirt runs here: solo or the host; a guest's shows the host's)
var paused := false             # (the tests: the dirt held still)
var _settle_acc := 0.0
var _now_at := 0                # (ticks, ms: the near sections last redrawn together)
var _build_ms := 2.0            # (what a section's redraw costs, on average: none's started that would run past a cap)
var settle_moves := 0           # (tests: cells the dirt's moved)

func setup(s: Node3D, at: Vector3, seed: int) -> void:
	site = s
	name = "Ground"
	grid = DigSiteGrid.new()
	grid.setup(W, H, D, SURFACE)
	DsMats.apply(grid)
	grid.generate(seed)
	origin = at - Vector3(W * CELL * 0.5, SURFACE * CELL, D * CELL * 0.5)
	var dv := grid.section_dims()
	_dims = Vector3i(int(dv.x), int(dv.y), int(dv.z))
	_mat = DsLook.ground_mat()
	for i in grid.take_dirty_sections(100000):
		_dirty[i] = true

# ---------------------------------------------------------------- where things are

## The cell a world point is in
func cell_of(p: Vector3) -> Vector3i:
	var l := (p - origin) / CELL
	return Vector3i(floori(l.x), floori(l.y), floori(l.z))

## A cell's middle in the world
func centre_of(c: Vector3i) -> Vector3:
	return origin + (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * CELL

## A world point in cell units (for the grid's spheres)
func to_cells(p: Vector3) -> Vector3:
	return (p - origin) / CELL

func contains(p: Vector3) -> bool:
	var c := cell_of(p)
	return c.x >= 0 and c.z >= 0 and c.x < W and c.z < D and c.y >= 0 and c.y < H

## The material at a world point (the cell byte: DsMats.MASK for the material)
func cell_at(p: Vector3) -> int:
	var c := cell_of(p)
	return grid.get_cell(c.x, c.y, c.z)

## The ground's top at a world x, z (its highest solid cell's top), or -INF off the grid
## The firm ground's top at (x, z), under any loose dirt lying on it
func firm_at(x: float, z: float) -> float:
	var c := cell_of(Vector3(x, 0, z))
	var y := grid.firm_top(c.x, c.z)
	return -INF if y < 0 else origin.y + (y + 1) * CELL

func top_at(x: float, z: float) -> float:
	var c := cell_of(Vector3(x, 0, z))
	var y := grid.column_top(c.x, c.z)
	return -INF if y < 0 else origin.y + (y + 1) * CELL

# ---------------------------------------------------------------- digging (the tools use these, stage 3)

## Every block within r metres of p no harder than hardest taken out: {counts: PackedInt32Array by material, n, refused}
func dig(p: Vector3, r: float, hardest: int) -> Dictionary:
	return grid.dig_sphere(to_cells(p), r / CELL, hardest)

## Up to most blocks of m put into the empty ones within r of p, lowest first: how many
func fill(p: Vector3, r: float, m: int, most: int, loose := true) -> int:
	return grid.fill_sphere(to_cells(p), r / CELL, m, most, loose)

# ---------------------------------------------------------------- drawing

func _sec_index(sx: int, sy: int, sz: int) -> int:
	return (sy * _dims.z + sz) * _dims.x + sx

func _sec_centre(i: int) -> Vector3:
	var sx := i % _dims.x
	var sz := (i / _dims.x) % _dims.z
	var sy := i / (_dims.x * _dims.z)
	return origin + Vector3((sx + 0.5) * SW, (sy + 0.5) * SH, (sz + 0.5) * SW) * CELL

## Where the players are (the sections near them are drawn and made solid)
func _near_points() -> Array:
	var out := []
	var a = site.arena
	if a and a.player:
		out.append(a.player.global_position)
	var n = a.get("net") if a else null
	if n != null and n.linked and n.get("_o_target") != null:
		out.append(n._o_target)
	return out

## The ground's changes as DsNet actions (done here, and on the host's ground for a guest)
func hook(n: DsNet) -> void:
	n.register_op("dig", func(a: Array, _again: bool): return grid.dig_sphere(a[0], float(a[1]), int(a[2])))
	n.register_op("fill", func(a: Array, _again: bool): return grid.fill_sphere(a[0], float(a[1]), int(a[2]), int(a[3]), bool(a[4])))
	n.register_op("drop", func(a: Array, _again: bool): return grid.drop_column(int(a[0]), int(a[1]), int(a[2]), int(a[3])))
	n.register_op("cut", func(a: Array, _again: bool): return blade(a[0], a[1], a[2], int(a[3]), float(a[4]), int(a[5]), int(a[6]), int(a[7]), float(a[8])))
	n.register_op("pour", func(a: Array, _again: bool): return pour(a[0], int(a[1]), int(a[2])))

func _process(dt: float) -> void:
	_settle_acc += dt
	settle_on = site.net == null or site.net.runs()
	if settle_on and not paused and _settle_acc >= 1.0 / SETTLE_HZ:
		_settle_acc = 0.0
		settle_moves += grid.settle(SETTLE_US)
		if site.get("caves") != null:
			site.caves.poll()
	step(BUDGET_MS)

## A machine's cutting edge from a to b (world) going fwd: what stands above it (to mouth m over it) cut, firm ground at
## most firm_most a column, up to take_most into its bucket (the counts), the rest banked ahead up to heap m over the
## edge (DigSiteGrid.blade_sweep: the digger game's way)
func blade(a: Vector3, b: Vector3, fwd: Vector3, rows: int, mouth: float, firm_most: int, hardest: int, take_most: int, heap: float, share := 1.0) -> Dictionary:
	return grid.blade_sweep(to_cells(a), to_cells(b), fwd, rows, mouth / CELL, firm_most, hardest, take_most, heap / CELL, share)

## A machine's blade (or bucket) solid to the loose dirt: from its edge a to b, back thick m against fwd and up high m
## (owner: the machine's id; its last ones cleared)
func block(owner: int, a: Vector3, b: Vector3, fwd: Vector3, thick: float, high: float) -> void:
	grid.block_blade(owner, to_cells(a), to_cells(b), fwd, thick / CELL, high / CELL)

func unblock(owner: int) -> void:
	grid.unblock(owner)

## The ground's height at (x, z) as the site was made (before anyone dug): a dozer's CUT holds its depth under it
func start_at(x: float, z: float) -> float:
	var c := cell_of(Vector3(x, 0, z))
	return origin.y + (grid.start_top(c.x, c.z) + 1) * CELL

## Loose blocks banked against an edge from a to b going fwd (up to reach m over it): the weight it's pushing
func load_ahead(a: Vector3, b: Vector3, fwd: Vector3, reach: float) -> int:
	return grid.load_ahead(to_cells(a), to_cells(b), fwd, reach / CELL)

## n loose blocks of m poured from a bucket at world point p: under it first, then round it, never piled up past the
## bucket itself (DigSiteGrid.pour_at): -> how many landed
func pour(p: Vector3, m: int, n: int) -> int:
	var c := cell_of(p)
	return grid.pour_at(c.x, c.z, c.y, m, n)

## n loose blocks of m dumped at world point p (on the ground's top there; they slump into a pile): -> how many
func dump(p: Vector3, m: int, n: int) -> int:
	var c := cell_of(p)
	return grid.drop_column(c.x, c.z, m, n)

## Builds what's due near the players for up to budget_ms (nearest first). -> sections built
func step(budget_ms: float) -> int:
	for i in grid.take_dirty_sections(100000):
		_dirty[i] = true
	var pts := _near_points()
	if pts.is_empty():
		return 0
	var t0 := Time.get_ticks_usec()
	var due := []                   # [distance, index, want_col]
	var now := []                   # (near, built, changed: redrawn together)
	for sy in _dims.y:
		for sz in _dims.z:
			for sx in _dims.x:
				var i := _sec_index(sx, sy, sz)
				var c := _sec_centre(i)
				var dist := INF
				for p: Vector3 in pts:
					dist = minf(dist, Vector2(c.x - p.x, c.z - p.z).length())
				var s: Dictionary = _sec.get(i, {})
				var want_col := dist < R_COL + 3.0
				if dist > R_DROP:
					if not s.is_empty():
						_free(i)
					continue
				if dist > R_MESH and s.is_empty():
					continue
				var has_col: bool = s.get("body") != null
				if dist - SW * CELL * 0.71 < R_NOW and _dirty.has(i) and not s.is_empty():
					now.append([dist, i, want_col])
				elif _dirty.has(i) or s.is_empty() or (want_col and not has_col and int(s.get("nf", 0)) > 0) or (not want_col and has_col):
					due.append([dist, i, want_col])
	var n := 0
	var ms := Time.get_ticks_msec()
	if not now.is_empty() and ms - _now_at >= int(1000.0 / NOW_HZ):
		now.sort_custom(func(a, b): return a[0] < b[0])
		var done := true
		for e in now:
			if n > 0 and (Time.get_ticks_usec() - t0) / 1000.0 + _build_ms > NOW_MS:
				done = false
				break
			_timed_build(int(e[1]), bool(e[2]))
			n += 1
		if done:
			_now_at = ms                # (else the rest's built next frame, not a tick later)
	if due.is_empty():
		return n
	due.sort_custom(func(a, b): return a[0] < b[0])
	var built_now := n
	n = 0
	# (its own time, after the batch: on a slow frame the batch runs every frame, and the rest mustn't starve; at least
	# one a frame when there was no batch)
	var t1 := Time.get_ticks_usec()
	var own_ms := budget_ms if built_now == 0 else budget_ms * 0.5
	for e in due:
		if (n > 0 or built_now > 0) and (Time.get_ticks_usec() - t1) / 1000.0 + _build_ms > own_ms:
			break
		_timed_build(int(e[1]), bool(e[2]))
		n += 1
	return n + built_now

func _timed_build(i: int, want_col: bool) -> void:
	var t := Time.get_ticks_usec()
	_build(i, want_col)
	_build_ms = lerpf(_build_ms, (Time.get_ticks_usec() - t) / 1000.0, 0.2)

func _free(i: int) -> void:
	var s: Dictionary = _sec.get(i, {})
	if s.get("mi") != null:
		(s.mi as Node).queue_free()
	if s.get("body") != null:
		(s.body as Node).queue_free()
	for k in ["grass", "clods"]:
		if s.get(k):
			(s[k] as Node).queue_free()
	_sec.erase(i)
	_dirty[i] = true                # (rebuilt when it's near again)

func _build(i: int, want_col: bool) -> void:
	var s: Dictionary = _sec.get(i, {})
	var rebuild: bool = _dirty.has(i) or s.is_empty()
	var faces: PackedVector3Array = s.get("faces", PackedVector3Array())
	if rebuild:
		_dirty.erase(i)
		var sx := i % _dims.x
		var sz := (i / _dims.x) % _dims.z
		var sy := i / (_dims.x * _dims.z)
		var arr: Array = grid.mesh_section(sx, sy, sz)
		faces = arr[0]
		var mi: MeshInstance3D = s.get("mi")
		if faces.is_empty():
			if mi:
				mi.queue_free()
				mi = null
		else:
			var a := []
			a.resize(Mesh.ARRAY_MAX)
			a[Mesh.ARRAY_VERTEX] = faces
			a[Mesh.ARRAY_NORMAL] = arr[1]
			a[Mesh.ARRAY_COLOR] = arr[2]
			a[Mesh.ARRAY_CUSTOM0] = arr[3]
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			if mi == null:
				mi = MeshInstance3D.new()
				mi.material_override = _mat
				mi.position = origin
				add_child(mi)
			mi.mesh = m
		# what stands on it: grass where it's untouched, lumps on the loose dirt
		var dec: Array = grid.decor_section(sx, sy, sz, DsLook.BLADES_PER_M2) if not faces.is_empty() else [PackedFloat32Array(), PackedFloat32Array()]
		var grass := _multi(s.get("grass"), dec[0], 12, DsLook.blade_mesh(), DsLook.grass_mat(), false)
		var clods := _multi(s.get("clods"), dec[1], 16, DsLook.clod_mesh(sx + sz * 3), DsLook.clod_mat(), true)
		s = {"mi": mi, "body": s.get("body"), "faces": faces, "nf": faces.size() / 6, "grass": grass, "clods": clods}
		built_n += 1
	# collision: near a player, from the same faces
	var body: StaticBody3D = s.get("body")
	if want_col and not faces.is_empty():
		if body == null:
			body = StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.position = origin
			body.set_meta("digsite", true)
			add_child(body)
			var cs := CollisionShape3D.new()
			body.add_child(cs)
		if rebuild or (body.get_child(0) as CollisionShape3D).shape == null:
			var sh := ConcavePolygonShape3D.new()
			sh.backface_collision = true
			sh.set_faces(faces)
			(body.get_child(0) as CollisionShape3D).shape = sh
	elif body != null and (not want_col or faces.is_empty()):
		body.queue_free()
		body = null
	s["body"] = body
	_sec[i] = s

## A section's grass or clods: the MultiMesh filled from the grid's buffer (made, kept or dropped as there's anything)
func _multi(mmi: MultiMeshInstance3D, buf: PackedFloat32Array, stride: int, mesh: Mesh, mat: Material, colours: bool) -> MultiMeshInstance3D:
	var n := buf.size() / stride
	if n == 0:
		if mmi:
			mmi.queue_free()
		return null
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = colours
		mm.mesh = mesh
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.position = origin
		add_child(mmi)
	mmi.multimesh.instance_count = n
	mmi.multimesh.buffer = buf
	return mmi

## Everything near the players built now, whatever it takes (arriving: the screen's black anyway)
func build_now(max_ms := 3000.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		if step(50.0) == 0:
			break

## Whether a collider is the Dig Site's ground
static func is_ground(col: Object) -> bool:
	return col is Node and (col as Node).has_meta("digsite")
