class_name DigMesher
extends RefCounted
## Draws one stored chunk of a DigVolume as a smooth surface: marching tetrahedra (each cube of 8 samples split
## into 6 tetrahedra along its long diagonal; no case tables needed), vertices placed where the density crosses
## 0, normals from the density's gradient (smooth shading). Triangles at the ground's top (level, facing up) wear
## the yard picture, or the cell's soil (furrows, dug dirt) if it was ploughed or dug over; the rest is earth,
## tinted by depth: dirt, then clay, then stone, darker the deeper.
##
## Output arrays (metres, Godot axes) for DigGround's terrain shader: UV the yard picture, UV2 (soil tile,
## turned), COLOR (shade; alpha 1 = the yard picture, 0 = the soil atlas).

const D := preload("res://scripts/dig/dig_data.gd")
const U := 0.025
const CS := 16
const P := CS + 3                       # samples a padded side (one before, two after)

const CORNERS := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1)]
const TETRAS := [[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6], [0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6]]

## Earth colours by depth (z, units, down): dirt, clay, stone.
const DIRT_TINT := Color(1.0, 1.0, 1.0)
const CLAY_TINT := Color(1.08, 0.78, 0.6)
const STONE_TINT := Color(0.72, 0.72, 0.78)

var vol: DigVolume
var grid: DigGrid
var yard_o := Vector2(-45, -50)
var yard_size := Vector2(2048, 2048)

var _f := PackedFloat32Array()
var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var cols := PackedColorArray()

## Builds chunk key; the arrays are left in verts, normals, uvs, uv2s, cols (empty if nothing to draw).
func build(key: Vector3i) -> void:
	verts = PackedVector3Array()
	normals = PackedVector3Array()
	uvs = PackedVector2Array()
	uv2s = PackedVector2Array()
	cols = PackedColorArray()
	var i0 := key.x * CS
	var j0 := key.y * CS
	var k0 := key.z * CS
	_fetch(i0, j0, k0)
	var any_in := false
	var any_out := false
	for v in _f:
		if v > 0.0:
			any_in = true
		else:
			any_out = true
		if any_in and any_out:
			break
	if not (any_in and any_out):
		return
	# each sample row (along a) of the padded block: 0 all air, 1 all earth, 2 both. A row of cells whose four
	# sample rows are all air or all earth has nothing to draw (most of them: only the rows the surface crosses
	# are looked at cell by cell)
	var rows := PackedByteArray()
	rows.resize(P * P)
	for c in P:
		for b in P:
			var base0 := (c * P + b) * P
			var ins := 0
			for a in range(1, CS + 2):
				if _f[base0 + a] > 0.0:
					ins += 1
			rows[c * P + b] = 1 if ins == CS + 1 else (0 if ins == 0 else 2)
	var vals := PackedFloat32Array()
	vals.resize(8)
	for c in CS:
		var d0 := DigVolume.default_f(k0 + c)
		var d1 := DigVolume.default_f(k0 + c + 1)
		var flat_z := D.ZMIN + (k0 + c) * D.CELL + (d0 / (d0 - d1) * D.CELL if d0 > 0.0 and d1 <= 0.0 else 0.0)
		for b in CS:
			var r0 := rows[(c + 1) * P + b + 1]
			if r0 != 2 and rows[(c + 1) * P + b + 2] == r0 and rows[(c + 2) * P + b + 1] == r0 and rows[(c + 2) * P + b + 2] == r0:
				continue
			# untouched cells of the ground's top along the row go out as long flat strips (by their look)
			var run := -1
			var run_key := -1
			for a in CS + 1:
				var flat_key := -1
				var trivial := true
				if a < CS:
					var base := ((c + 1) * P + (b + 1)) * P + (a + 1)
					var inside := 0
					for n in 8:
						var o: Vector3i = CORNERS[n]
						var v := _f[base + (o.z * P + o.y) * P + o.x]
						vals[n] = v
						if v > 0.0:
							inside += 1
					trivial = inside == 0 or inside == 8
					if not trivial and vals[0] == d0 and vals[1] == d0 and vals[2] == d0 and vals[3] == d0 \
							and vals[4] == d1 and vals[5] == d1 and vals[6] == d1 and vals[7] == d1:
						flat_key = _top_key(i0 + a, j0 + b)
				if run >= 0 and flat_key != run_key:
					_strip(i0 + run, i0 + a, j0 + b, flat_z, run_key)
					run = -1
				if flat_key >= 0:
					if run < 0:
						run = a
						run_key = flat_key
				elif not trivial:
					_cube(a, b, c, ((c + 1) * P + (b + 1)) * P + (a + 1), vals, i0, j0, k0)

## The padded samples round the chunk, copied a chunk's block at a time (the chunk and its neighbours).
func _fetch(i0: int, j0: int, k0: int) -> void:
	_f.resize(P * P * P)
	var key0 := Vector3i(i0 >> 4, j0 >> 4, k0 >> 4)
	for dz in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var key: Vector3i = key0 + Vector3i(dx, dy, dz)
				# the padded block's range (a, b, c: 0..P-1) this chunk covers
				var a0 := maxi(0, key.x * CS - (i0 - 1))
				var a1 := mini(P, key.x * CS + CS - (i0 - 1))
				var b0 := maxi(0, key.y * CS - (j0 - 1))
				var b1 := mini(P, key.y * CS + CS - (j0 - 1))
				var c0 := maxi(0, key.z * CS - (k0 - 1))
				var c1 := mini(P, key.z * CS + CS - (k0 - 1))
				if a0 >= a1 or b0 >= b1 or c0 >= c1:
					continue
				var ch = vol.chunks.get(key)
				if ch == null:
					for c in range(c0, c1):
						var dv := DigVolume.default_f(k0 + c - 1)
						for b in range(b0, b1):
							var base := (c * P + b) * P
							for a in range(a0, a1):
								_f[base + a] = dv
					continue
				var d: PackedByteArray = ch.d
				for c in range(c0, c1):
					var lk := (k0 + c - 1) - key.z * CS
					for b in range(b0, b1):
						var lj := (j0 + b - 1) - key.y * CS
						var base := (c * P + b) * P
						var src := (lk * CS + lj) * CS - key.x * CS + (i0 - 1)
						for a in range(a0, a1):
							_f[base + a] = d.decode_s8(src + a) * 0.25

## For each tetrahedron and each mask of its corners inside the earth: the triangles, as cube-corner pairs
## (the edges they cross), 3 pairs a triangle. Made once.
static var _cases: Array = []
static func _make_cases() -> void:
	for t in TETRAS:
		var per_mask: Array = []
		for m in 16:
			var ins: Array = []
			var outs: Array = []
			for q in 4:
				if m & (1 << q):
					ins.append(t[q])
				else:
					outs.append(t[q])
			var tris := PackedInt32Array()
			if ins.size() == 1:
				tris.append_array([ins[0], outs[0], ins[0], outs[1], ins[0], outs[2]])
			elif ins.size() == 3:
				tris.append_array([outs[0], ins[0], outs[0], ins[1], outs[0], ins[2]])
			elif ins.size() == 2:
				tris.append_array([ins[0], outs[0], ins[0], outs[1], ins[1], outs[1]])
				tris.append_array([ins[0], outs[0], ins[1], outs[1], ins[1], outs[0]])
			per_mask.append(tris)
		_cases.append(per_mask)

var _epos := PackedVector3Array()     # this cell's edge crossings (HTML units), by corner pair p * 8 + q
var _enrm := PackedVector3Array()
var _eset := PackedByteArray()

func _cube(a: int, b: int, c: int, base: int, vals: PackedFloat32Array, i0: int, j0: int, k0: int) -> void:
	if _cases.is_empty():
		_make_cases()
	if _epos.size() != 64:
		_epos.resize(64)
		_enrm.resize(64)
		_eset.resize(64)
	_eset.fill(0)
	var bx := D.X0 + (i0 + a) * D.CELL
	var by := D.Y0 + (j0 + b) * D.CELL
	var bz := D.ZMIN + (k0 + c) * D.CELL
	var top_key := -2
	for ti in 6:
		var t: Array = TETRAS[ti]
		var m := 0
		for q in 4:
			if vals[t[q]] > 0.0:
				m |= 1 << q
		if m == 0 or m == 15:
			continue
		var tris: PackedInt32Array = _cases[ti][m]
		var n := 0
		while n < tris.size():
			# the triangle's three crossings
			for e in 3:
				var p: int = tris[n + e * 2]
				var q2: int = tris[n + e * 2 + 1]
				var id := p * 8 + q2
				if _eset[id] == 0:
					_eset[id] = 1
					var vp := vals[p]
					var vq := vals[q2]
					var tt := vp / (vp - vq) if absf(vp - vq) > 0.00001 else 0.5
					var op: Vector3i = CORNERS[p]
					var oq: Vector3i = CORNERS[q2]
					_epos[id] = Vector3(bx + lerpf(op.x, oq.x, tt) * D.CELL, by + lerpf(op.y, oq.y, tt) * D.CELL, bz + lerpf(op.z, oq.z, tt) * D.CELL)
					var gp := _grad(base + (op.z * P + op.y) * P + op.x)
					var gq := _grad(base + (oq.z * P + oq.y) * P + oq.x)
					var nn := -(gp.lerp(gq, tt))
					_enrm[id] = nn.normalized() if nn.length_squared() > 0.000001 else Vector3(0, 0, 1)
			var i_a := tris[n] * 8 + tris[n + 1]
			var i_b := tris[n + 2] * 8 + tris[n + 3]
			var i_c := tris[n + 4] * 8 + tris[n + 5]
			var p0 := _epos[i_a]
			var p1 := _epos[i_b]
			var p2 := _epos[i_c]
			var n0 := _enrm[i_a]
			var n1 := _enrm[i_b]
			var n2 := _enrm[i_c]
			# the ground's top (level, facing up) wears the yard picture or the soil; the rest is earth
			var key := -1
			if p0.z > -3.0 and p1.z > -3.0 and p2.z > -3.0 and n0.z + n1.z + n2.z > 2.25:
				if top_key == -2:
					top_key = _top_key(i0 + a, j0 + b)
				key = top_key
			_vert(p0, n0, key)
			_vert(p1, n1, key)
			_vert(p2, n2, key)
			n += 6

## One vertex: key -1 earth (tinted by depth), 0 the yard picture, else a soil tile (see _top_key).
func _vert(p: Vector3, n: Vector3, key: int) -> void:
	verts.append(Vector3(p.x * U, p.z * U, p.y * U))
	normals.append(Vector3(n.x, n.z, n.y))
	uvs.append(Vector2((p.x - yard_o.x) / yard_size.x, (p.y - yard_o.y) / yard_size.y))
	if key == 0:
		uv2s.append(Vector2.ZERO)
		cols.append(Color(1, 1, 1, 1))
		return
	if key > 0:
		uv2s.append(Vector2(float((key - 1) >> 1), float((key - 1) & 1)))
		cols.append(Color(0.92, 0.92, 0.92, 0.0))
		return
	uv2s.append(Vector2.ZERO)
	var depth := clampf(-p.z, 0.0, 320.0)
	var tint := DIRT_TINT
	if depth > 200.0:
		tint = CLAY_TINT.lerp(STONE_TINT, clampf((depth - 200.0) / 40.0, 0.0, 1.0))
	elif depth > 80.0:
		tint = DIRT_TINT.lerp(CLAY_TINT, clampf((depth - 80.0) / 40.0, 0.0, 1.0))
	var k := 1.0 - 0.45 * depth / 320.0
	cols.append(Color(tint.r * k, tint.g * k, tint.b * k, 0.0))

## How the ground's top looks at cell (cx, cy): 0 the yard picture, else 1 + tile * 2 + turned (the soil).
func _top_key(cx: int, cy: int) -> int:
	if cx < 0 or cy < 0 or cx >= D.NX or cy >= D.NY:
		return 0
	var i := cy * D.NX + cx
	var s := grid.soil[i]
	if s == D.GRASS:
		return 0
	var wd := grid.weedy(i)
	if s == D.ROWS_X or s == D.ROWS_Y:
		return 1 + (2 if wd else 1) * 2 + (1 if s == D.ROWS_Y else 0)
	return 1 + (3 if wd else 0) * 2

## A level strip of untouched ground at height z over cells i0..i1 (exclusive) of row j, looking like key.
func _strip(i0: int, i1: int, j: int, z: float, key: int) -> void:
	var x0 := D.X0 + i0 * D.CELL
	var x1 := D.X0 + i1 * D.CELL
	var y0 := D.Y0 + j * D.CELL
	var y1 := y0 + D.CELL
	var flag := 1.0 if key == 0 else 0.0
	var tile := Vector2.ZERO if key == 0 else Vector2(float((key - 1) >> 1), float((key - 1) & 1))
	var col := Color(1, 1, 1, flag) if key == 0 else Color(0.92, 0.92, 0.92, 0.0)
	for q in [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y0), Vector2(x1, y1), Vector2(x0, y1)]:
		verts.append(Vector3(q.x * U, z * U, q.y * U))
		normals.append(Vector3.UP)
		uvs.append((q - yard_o) / yard_size)
		uv2s.append(tile)
		cols.append(col)

func _grad(i: int) -> Vector3:
	return Vector3(_f[i + 1] - _f[i - 1], _f[i + P] - _f[i - P], _f[i + P * P] - _f[i - P * P])
