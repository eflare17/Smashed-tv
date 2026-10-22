class_name VoxelTerrain
extends Node3D
## Ground you can dig (the owner, 21 Oct, Stage 4: "voxel digging with small chunky blocks (not Minecraft-sized, not
## smooth terrain). Watch performance, tune block size"). A grid of 12.5 cm blocks (CELL), 16 m by 16 m and 3 m deep,
## its top level with the floor: grass on top, dirt, pockets of clay, stones in the dirt, then stone, hard rock with
## seams of gold ore, bedrock at the bottom (and a ring round the edge that doesn't dig, so a hole never opens onto
## nothing). Each block is one byte (its material); every block's faces that show are drawn in its material's colour,
## a shade off block to block, so the ground looks built of chunky cubes. Meshed in 2 m x 2 m columns (chunks), each on
## a worker thread when something in it changes, with a matching collision mesh so you walk in the holes.
##
## dig(centre, radius, hardest) takes out every block within radius metres no harder than hardest (the tools' power);
## fill(centre, radius, n) puts up to n dirt blocks into the empty ones there, lowest first. Both are the same in every
## game given the same ground, so co-op sends only those calls (VoxelYard), and a fingerprint of each chunk catches any
## difference (that chunk is then sent whole). Owned by the voxel session.

const CELL := 0.125             # metres a block (tuned: 6.25 cm made too many faces to mesh fast in GDScript, 25 cm looked Minecraft)
const NX := 128                 # blocks across (x) ...
const NY := 24                  # ... deep ...
const NZ := 128                 # ... and along (z)
const CS := 16                  # a chunk is CS x NY x CS blocks
const AIR := 0
const GRASS := 1
const DIRT := 2
const CLAY := 3
const STONE := 4
const ROCK := 5
const GOLD := 6
const BEDROCK := 7
const EDGE := 8                 # the ring round the edge: looks like dirt, never digs
const TILLED := 9               # hoed soil (Stage 5): plants grow in it
const FILL := 10                # dirt put back in a hole: digs and looks like dirt (turf on top at the top), no worms in it
const HARD := [0, 1, 1, 2, 3, 4, 4, 99, 99, 1, 1]
const COL := [Color(0, 0, 0), Color8(64, 112, 42), Color8(116, 80, 48), Color8(168, 102, 62), Color8(128, 126, 122),
	Color8(84, 82, 86), Color8(226, 182, 52), Color8(40, 38, 42), Color8(116, 80, 48), Color8(74, 48, 30), Color8(116, 80, 48)]
const SIDE_GRASS := Color8(104, 74, 44)   # a grass block's sides: dirt with the turf on top
## The item a block dug out becomes (VoxelItems).
const ITEM := ["", "dirt", "dirt", "clay", "stone", "stone", "gold", "", "", "dirt", "dirt"]
const MAX_JOBS := 6

var origin := Vector3.ZERO      # the grid's corner (lowest x, y, z) in the world
var cells := PackedByteArray()
var _gen_hash := PackedInt64Array()     # each chunk's fingerprint as made (to know which were dug: saved, sent)
var _mesh: Array[MeshInstance3D] = []
var _shape: Array[CollisionShape3D] = []
var _dirty := {}                # chunk -> true: to mesh again
var _hash := {}                 # chunk -> its fingerprint (dropped when it changes)
var _jobs := []                 # [{id, chunk, out}]
var _mat: StandardMaterial3D
var seed := 2110
var meshed := 0                 # chunk meshes made (stats)

func setup(origin_: Vector3) -> void:
	origin = origin_
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 0.95
	var body := StaticBody3D.new()
	add_child(body)
	for c in (NX / CS) * (NZ / CS):
		var mi := MeshInstance3D.new()
		mi.material_override = _mat
		add_child(mi)
		_mesh.append(mi)
		var cs := CollisionShape3D.new()
		body.add_child(cs)
		_shape.append(cs)
	generate()
	for c in _mesh.size():
		_dirty[c] = true
	_gen_hash.resize(_mesh.size())
	for c in _mesh.size():
		_gen_hash[c] = chunk_hash(c)

static func idx(x: int, y: int, z: int) -> int:
	return (z * NY + y) * NX + x

func at(x: int, y: int, z: int) -> int:
	if x < 0 or x >= NX or z < 0 or z >= NZ or y < 0:
		return EDGE
	if y >= NY:
		return AIR
	return cells[idx(x, y, z)]

## The block a world point is in: Vector3i (may be outside the grid).
func cell_of(p: Vector3) -> Vector3i:
	var l := (p - origin) / CELL
	return Vector3i(floori(l.x), floori(l.y), floori(l.z))

func centre_of(x: int, y: int, z: int) -> Vector3:
	return origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * CELL

func contains(p: Vector3) -> bool:
	var l := p - origin
	return l.x >= 0.0 and l.z >= 0.0 and l.x < NX * CELL and l.z < NZ * CELL

# ---------------------------------------------------------------- making the ground

## The ground as made (the same every game: a fixed seed).
func generate() -> void:
	_hash.clear()
	cells.resize(NX * NY * NZ)
	cells.fill(AIR)
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.08
	var n2 := FastNoiseLite.new()
	n2.seed = seed + 7
	n2.frequency = 0.15
	var n3 := FastNoiseLite.new()
	n3.seed = seed + 13
	n3.frequency = 0.22
	n3.fractal_octaves = 1
	for z in NZ:
		for x in NX:
			var edge := x == 0 or z == 0 or x == NX - 1 or z == NZ - 1
			# how deep each layer starts (blocks down from the top), wavy
			var dirt_to := 6 + int(round(n.get_noise_2d(x, z) * 2.5))          # dirt to ~0.75 m
			var stone_to := 14 + int(round(n.get_noise_2d(x + 300, z) * 3.0))  # stone to ~1.75 m, then rock
			for y in NY:
				var depth := NY - 1 - y
				var m := DIRT
				if y <= 1:
					m = BEDROCK
				elif edge:
					m = EDGE
				elif depth == 0:
					m = GRASS
				elif depth < dirt_to:
					m = DIRT
					var cl := n2.get_noise_3d(x, y * 2.0, z)
					if cl > 0.42 and depth > 2:
						m = CLAY
					elif n3.get_noise_3d(x * 1.7, y * 1.7, z * 1.7) > 0.62:
						m = STONE          # (a stone in the dirt: the shovel can't, the pick can)
				elif depth < stone_to:
					m = STONE if n2.get_noise_3d(x, y * 1.5, z) > -0.3 else CLAY
				else:
					m = ROCK
				if (m == STONE or m == ROCK) and depth > 10 and n3.get_noise_3d(x + 900, y * 2.0, z) > 0.74:
					m = GOLD         # (seams of it, rare)
				cells[idx(x, y, z)] = m

# ---------------------------------------------------------------- digging

## Every block within r metres of c no harder than hardest taken out. Returns {item id: how many} for what came out,
## "_cells": the blocks taken ([Vector3i, ...], for the dust) and "_worms": those of them a worm was in.
func dig(c: Vector3, r: float, hardest: int) -> Dictionary:
	var out := {"_cells": [], "_worms": []}
	var lo := cell_of(c - Vector3.ONE * r)
	var hi := cell_of(c + Vector3.ONE * r)
	var r2 := r * r
	for z in range(maxi(1, lo.z), mini(NZ - 1, hi.z + 1)):
		for y in range(maxi(2, lo.y), mini(NY, hi.y + 1)):
			for x in range(maxi(1, lo.x), mini(NX - 1, hi.x + 1)):
				var i := idx(x, y, z)
				var m := cells[i]
				if m == AIR or HARD[m] > hardest:
					continue
				if centre_of(x, y, z).distance_squared_to(c) > r2:
					continue
				cells[i] = AIR
				var it: String = ITEM[m]
				if it != "":
					out[it] = int(out.get(it, 0)) + 1
				(out._cells as Array).append(Vector3i(x, y, z))
				if (m == GRASS or m == DIRT) and worm_in(x, y, z):
					(out._worms as Array).append(Vector3i(x, y, z))      # (dirt as made only: not stone, not dirt put back)
				_touch(x, z)
	return out

## Up to n dirt blocks put into the empty blocks within r metres of c, lowest first (no higher than the ground's top).
## Returns how many went in.
func fill(c: Vector3, r: float, n: int) -> int:
	var lo := cell_of(c - Vector3.ONE * r)
	var hi := cell_of(c + Vector3.ONE * r)
	var r2 := r * r
	var spots := []
	for z in range(maxi(1, lo.z), mini(NZ - 1, hi.z + 1)):
		for y in range(maxi(2, lo.y), mini(NY, hi.y + 1)):
			for x in range(maxi(1, lo.x), mini(NX - 1, hi.x + 1)):
				if cells[idx(x, y, z)] == AIR and centre_of(x, y, z).distance_squared_to(c) <= r2:
					spots.append(Vector3i(x, y, z))
	spots.sort_custom(func(a: Vector3i, b: Vector3i): return a.y < b.y or (a.y == b.y and (a.z * NX + a.x) < (b.z * NX + b.x)))
	var k := 0
	for s: Vector3i in spots:
		if k >= n:
			break
		cells[idx(s.x, s.y, s.z)] = FILL
		_touch(s.x, s.z)
		k += 1
	return k

## The hoe (Stage 5): each planting spot in keys (VoxelFarm's: 4 x 4 blocks, keyed x * 1000 + z by spot) gets its
## middle 2 x 2 blocks on top turned to tilled soil, where they're grass or dirt (a row of little mounds, grass between).
## Returns how many blocks it turned.
func till(keys: Array, spot_cells: int) -> int:
	var n := 0
	for key in keys:
		var sx := int(key) / 1000 * spot_cells
		var sz := int(key) % 1000 * spot_cells
		for dz in [spot_cells / 2 - 1, spot_cells / 2]:
			for dx in [spot_cells / 2 - 1, spot_cells / 2]:
				var x: int = sx + dx
				var z: int = sz + dz
				if x < 1 or z < 1 or x >= NX - 1 or z >= NZ - 1:
					continue
				for y in range(NY - 1, 1, -1):
					var m := cells[idx(x, y, z)]
					if m == AIR:
						continue
					if m == GRASS or m == DIRT or m == FILL:
						cells[idx(x, y, z)] = TILLED
						_touch(x, z)
						n += 1
					break
	return n

## Whether there's a worm in block (x, y, z) (dug out of dirt as made: about one block in three hundred).
static func worm_in(x: int, y: int, z: int) -> bool:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	return posmod(h, 331) == 0

# the chunk (x, z) is in needs meshing again; a block on a chunk's edge, its neighbour too
func _touch(x: int, z: int) -> void:
	var cx := x / CS
	var cz := z / CS
	var per := NX / CS
	_dirty[cz * per + cx] = true
	_hash.erase(cz * per + cx)
	if x % CS == 0 and cx > 0:
		_dirty[cz * per + cx - 1] = true
	if x % CS == CS - 1 and cx < per - 1:
		_dirty[cz * per + cx + 1] = true
	if z % CS == 0 and cz > 0:
		_dirty[(cz - 1) * per + cx] = true
	if z % CS == CS - 1 and cz < NZ / CS - 1:
		_dirty[(cz + 1) * per + cx] = true

# ---------------------------------------------------------------- fingerprints, saving, sending

func chunk_count() -> int:
	return _mesh.size()

## A chunk's blocks as bytes (row by row: each row of CS blocks lies together in cells).
func chunk_bytes(c: int) -> PackedByteArray:
	var per := NX / CS
	var x0 := (c % per) * CS
	var z0 := (c / per) * CS
	var out := PackedByteArray()
	for z in range(z0, z0 + CS):
		for y in NY:
			var i := idx(x0, y, z)
			out.append_array(cells.slice(i, i + CS))
	return out

func set_chunk_bytes(c: int, b: PackedByteArray) -> void:
	if b.size() != CS * NY * CS:
		return
	var per := NX / CS
	var x0 := (c % per) * CS
	var z0 := (c / per) * CS
	var j := 0
	for z in range(z0, z0 + CS):
		for y in NY:
			var i := idx(x0, y, z)
			for x in CS:
				cells[i + x] = b[j]
				j += 1
	_dirty[c] = true
	_hash.erase(c)
	for d in [-1, 1, -per, per]:
		if c + d >= 0 and c + d < _mesh.size():
			_dirty[c + d] = true

func chunk_hash(c: int) -> int:
	if not _hash.has(c):
		_hash[c] = hash(chunk_bytes(c))
	return _hash[c]

func hashes() -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(_mesh.size())
	for c in _mesh.size():
		out[c] = chunk_hash(c)
	return out

## The chunks dug or filled since the ground was made: {chunk: zstd bytes}.
func changed_chunks() -> Dictionary:
	var out := {}
	for c in _mesh.size():
		if chunk_hash(c) != _gen_hash[c]:
			var b := chunk_bytes(c)
			out[c] = b.compress(FileAccess.COMPRESSION_ZSTD)
	return out

## Back to the ground as made, with these chunks as given (changed_chunks' output).
func load_chunks(d: Dictionary) -> void:
	generate()
	for c in _mesh.size():
		_dirty[c] = true
	for k in d:
		var c := int(k)
		if c >= 0 and c < _mesh.size():
			var raw: PackedByteArray = d[k]
			set_chunk_bytes(c, raw.decompress(CS * NY * CS, FileAccess.COMPRESSION_ZSTD))

# ---------------------------------------------------------------- meshing

func _process(_dt: float) -> void:
	_poll()
	# the dirty chunks off to be meshed, a few at a time
	if _dirty.is_empty() or _jobs.size() >= MAX_JOBS:
		return
	for c in _dirty.keys():
		if _jobs.size() >= MAX_JOBS:
			break
		if _jobs.any(func(j): return j.chunk == c):
			continue             # (still being meshed: again once it's back)
		_dirty.erase(c)
		var out := {}
		var block := _padded(c)
		var per := NX / CS
		var id := WorkerThreadPool.add_task(_mesh_job.bind(block, c % per * CS, c / per * CS, out))
		_jobs.append({"id": id, "chunk": c, "out": out})

## Everything dirty meshed now, waiting for it (tests; loading).
func finish() -> void:
	var guard := 0
	while (not _dirty.is_empty() or not _jobs.is_empty()) and guard < 1000:
		_process(0.0)
		for j in _jobs:
			if not j.get("done", false):
				WorkerThreadPool.wait_for_task_completion(j.id)
				j.done = true
		_poll()
		guard += 1

func _poll() -> void:
	var keep := []
	for j in _jobs:
		if not j.get("done", false):
			if not WorkerThreadPool.is_task_completed(j.id):
				keep.append(j)
				continue
			WorkerThreadPool.wait_for_task_completion(j.id)
		var o: Dictionary = j.out
		var c: int = j.chunk
		var verts: PackedVector3Array = o.get("v", PackedVector3Array())
		if verts.is_empty():
			_mesh[c].mesh = null
			_shape[c].shape = null
		else:
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = o.n
			arr[Mesh.ARRAY_COLOR] = o.c
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			_mesh[c].mesh = am
			var sh := ConcavePolygonShape3D.new()
			sh.set_faces(verts)
			_shape[c].shape = sh
		meshed += 1
	_jobs = keep

# the chunk's blocks with a one-block border round them (x, z), copied so the worker never reads blocks being dug
func _padded(c: int) -> PackedByteArray:
	var per := NX / CS
	var x0 := (c % per) * CS - 1
	var z0 := (c / per) * CS - 1
	var w := CS + 2
	var b := PackedByteArray()
	b.resize(w * NY * w)
	var j := 0
	for z in range(z0, z0 + w):
		for y in NY:
			for x in range(x0, x0 + w):
				b[j] = at(x, y, z)
				j += 1
	return b

const _DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const _SHADE := [0.86, 0.86, 1.0, 0.6, 0.78, 0.78]

# (a worker thread) the faces that show: every block's sides with no block next to them, as triangles, each block a
# shade off its neighbours, deeper ones darker
func _mesh_job(b: PackedByteArray, wx0: int, wz0: int, out: Dictionary) -> void:
	var w := CS + 2
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var o := origin
	for z in range(1, w - 1):
		for y in NY:
			for x in range(1, w - 1):
				var m := b[(z * NY + y) * w + x]
				if m == AIR:
					continue
				var gx := wx0 + x - 1
				var gz := wz0 + z - 1
				var hsh := ((gx * 92837111) ^ (y * 689287499) ^ (gz * 283923481)) & 0xFFFF
				var vary := 0.9 + 0.2 * float(hsh % 101) / 100.0
				var deep := lerpf(0.72, 1.0, float(y) / float(NY - 1))
				var look := GRASS if m == FILL and y == NY - 1 else m     # (filled back to the top: turf again)
				var base: Color = COL[look]
				for d in 6:
					var dv: Vector3i = _DIRS[d]
					var ny := y + dv.y
					var nm := 0
					if ny >= NY:
						nm = AIR
					elif ny < 0:
						nm = BEDROCK
					else:
						nm = b[((z + dv.z) * NY + ny) * w + x + dv.x]
					if nm != AIR:
						continue
					var col := base
					if look == GRASS and d != 2:
						col = SIDE_GRASS
					elif m == EDGE and d == 2 and y == NY - 1:
						col = COL[GRASS]          # (the edge ring's top: turf like the rest)
					elif m == TILLED and d == 2 and ((gx + gz) & 1) == 0:
						col = col.darkened(0.18)  # (furrowed: every other block darker)
					var k: float = vary * deep * _SHADE[d]
					col = Color(col.r * k, col.g * k, col.b * k)
					var p := o + Vector3(gx, y, gz) * CELL
					var q := _quad(p, d)
					var nv := Vector3(dv)
					for v in q:
						verts.append(v)
						norms.append(nv)
						cols.append(col)
	out.v = verts
	out.n = norms
	out.c = cols

# a face of the block at corner p, as two triangles (clockwise seen from outside: Godot's front faces)
func _quad(p: Vector3, d: int) -> Array:
	var s := CELL
	var a: Vector3
	var b2: Vector3
	var c: Vector3
	var e: Vector3
	match d:
		0:
			a = p + Vector3(s, 0, 0); b2 = p + Vector3(s, s, 0); c = p + Vector3(s, s, s); e = p + Vector3(s, 0, s)
		1:
			a = p + Vector3(0, 0, s); b2 = p + Vector3(0, s, s); c = p + Vector3(0, s, 0); e = p
		2:
			a = p + Vector3(0, s, 0); b2 = p + Vector3(0, s, s); c = p + Vector3(s, s, s); e = p + Vector3(s, s, 0)
		3:
			a = p; b2 = p + Vector3(s, 0, 0); c = p + Vector3(s, 0, s); e = p + Vector3(0, 0, s)
		4:
			a = p + Vector3(s, 0, s); b2 = p + Vector3(s, s, s); c = p + Vector3(0, s, s); e = p + Vector3(0, 0, s)
		_:
			a = p; b2 = p + Vector3(0, s, 0); c = p + Vector3(s, s, 0); e = p + Vector3(s, 0, 0)
	return [a, c, b2, a, e, c]

func _exit_tree() -> void:
	for j in _jobs:
		if not j.get("done", false):
			WorkerThreadPool.wait_for_task_completion(j.id)
	_jobs.clear()
