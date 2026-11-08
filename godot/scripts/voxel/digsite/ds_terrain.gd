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
var _mat: StandardMaterial3D
var _sec := {}                  # section index -> {mi: MeshInstance3D or null, body: StaticBody3D or null, faces: PackedVector3Array}
var _dirty := {}                # section index -> true: changed since it was built
var _dims := Vector3i.ZERO
var built_n := 0                # (tests: sections built so far)
var settle_on := true           # (the dirt runs here: solo or the host; a guest's shows the host's)
var paused := false             # (the tests: the dirt held still)
var _settle_acc := 0.0
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
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.95
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

func _process(dt: float) -> void:
	_settle_acc += dt
	if settle_on and not paused and _settle_acc >= 1.0 / SETTLE_HZ:
		_settle_acc = 0.0
		settle_moves += grid.settle(SETTLE_US)
	step(BUDGET_MS)

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
				if _dirty.has(i) or s.is_empty() or (want_col and not has_col and int(s.get("nf", 0)) > 0) or (not want_col and has_col):
					due.append([dist, i, want_col])
	if due.is_empty():
		return 0
	due.sort_custom(func(a, b): return a[0] < b[0])
	var n := 0
	for e in due:
		if n > 0 and (Time.get_ticks_usec() - t0) / 1000.0 > budget_ms:
			break
		_build(int(e[1]), bool(e[2]))
		n += 1
	return n

func _free(i: int) -> void:
	var s: Dictionary = _sec.get(i, {})
	if s.get("mi") != null:
		(s.mi as Node).queue_free()
	if s.get("body") != null:
		(s.body as Node).queue_free()
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
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			if mi == null:
				mi = MeshInstance3D.new()
				mi.material_override = _mat
				mi.position = origin
				add_child(mi)
			mi.mesh = m
		s = {"mi": mi, "body": s.get("body"), "faces": faces, "nf": faces.size() / 6}
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

## Everything near the players built now, whatever it takes (arriving: the screen's black anyway)
func build_now(max_ms := 3000.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < max_ms:
		if step(50.0) == 0:
			break

## Whether a collider is the Dig Site's ground
static func is_ground(col: Object) -> bool:
	return col is Node and (col as Node).has_meta("digsite")
