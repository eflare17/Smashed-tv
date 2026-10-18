class_name DigGround
extends Node3D
## The yard's ground drawn and made solid from a DigGrid: it takes over from the World's flat yard floor.
##
## - Meshes: three, so the whole yard is at most three draws. "DigGrass" wears the yard picture (the World's own texture, so
##   it looks exactly as before) on level ground; "DigSoil" wears the soil atlas (dug dirt, furrows, weedy
##   furrows) on every cell that's dug, piled or ploughed and round their edges (vertex alpha with a scissor, so
##   the soil's edge runs round between cells; "DigSoilSolid" is the cells soil all over, opaque and cheaper), shaded by slope and depth so holes read in the unlit phone look
##   too. They're built from chunks of D.CHUNK x D.CHUNK cells: a change rebuilds its chunks' arrays, then the
##   two meshes are put together again from every chunk's (cheap: untouched chunks are a few big quads). Their
##   materials are plain unshaded StandardMaterial3Ds, so the look pass lights them like the rest of the World
##   (it lights whatever is added under the World).
## - The World's yard floor surface is hidden (a material that draws nothing), so it can't cover the holes.
## - Collision: the World's Ground (an endless plane at 0) becomes four slabs round the dig region, and inside it
##   a HeightMapShape3D of the grid (on layer 1, the world, like the plane was). Players walk by their own
##   height (Player sets y from dz), so Dig stands them on the ground (and keeps their capsule out of this
##   shape: a collision exception), but anything physical lands in the holes.

const D := preload("res://scripts/dig/dig_data.gd")
const U := 0.025

var grid: DigGrid
var world: Node3D
var _garr: Dictionary = {}            # chunk index -> [vertices, uvs] of its level ground
var _sarr: Dictionary = {}            # chunk index -> [vertices, uvs, colours] of its soil's edge cells
var _oarr: Dictionary = {}            # chunk index -> [vertices, uvs, colours] of its soil all over (no edge)
var _grass_mi: MeshInstance3D
var _soil_mi: MeshInstance3D          # the soil's edges (alpha scissor)
var _solid_mi: MeshInstance3D         # soil all over a cell (opaque: cheaper to draw)
var _solid_mat: StandardMaterial3D
var _h := PackedFloat32Array()        # the heightmap's heights (cells, up)
var _yard_mat: StandardMaterial3D
var _soil_mat: StandardMaterial3D
var _yard_rects: Array = []           # where the World drew the yard picture (round the house), HTML units
var _yard_o := Vector2(-45, -50)
var _yard_size := Vector2(2048, 2048)
var _body: StaticBody3D
var _hmap: HeightMapShape3D
var _hmap_dirty := false
var _hmap_t := 0.0
var _draw_t := 0.0

## Hides the World's yard floor, swaps its endless ground for slabs, and builds every chunk.
func setup(g: DigGrid, w: Node3D) -> void:
	grid = g
	world = w
	name = "DigGround"
	var tex: Texture2D = w.get("_yard_tex") if w else null
	var sz = w.get("_yard_size") if w else null
	if sz is Vector2:
		_yard_size = sz
	var Y: Dictionary = GameData.data.get("YARD", {"ox": -45, "oy": -50})
	_yard_o = Vector2(float(Y.ox), float(Y.oy))
	_yard_rects = yard_rects()
	_yard_mat = _mat(tex)
	_soil_mat = _mat(soil_atlas())
	_soil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_soil_mat.alpha_scissor_threshold = 0.5
	_solid_mat = _mat(soil_atlas())
	_hide_world_yard(tex)
	_grass_mi = MeshInstance3D.new()
	_grass_mi.name = "DigGrass"
	_grass_mi.material_override = _yard_mat
	_grass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grass_mi)
	_soil_mi = MeshInstance3D.new()
	_soil_mi.name = "DigSoil"
	_soil_mi.material_override = _soil_mat
	_soil_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_soil_mi)
	_solid_mi = MeshInstance3D.new()
	_solid_mi.name = "DigSoilSolid"
	_solid_mi.material_override = _solid_mat
	_solid_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_solid_mi)
	_collision()
	for i in DigGrid.chunks_x() * DigGrid.chunks_y():
		_build_chunk(i)
	_commit()
	grid.dirty.clear()
	grid.hdirty.clear()

## The yard picture's rectangles exactly as the World lays them (WorldBuilder._floor_meshes): the yard round the
## house, HTML units.
static func yard_rects() -> Array:
	var d: Dictionary = GameData.data
	var A: Dictionary = d.ARENA
	var B: Dictionary = d.BEDROOM
	var areas: Array = d.calls.lobbyAreas
	var Y: Dictionary = d.YARD
	var hx: float = A.w
	var hy: float = float(areas[4].y0)
	var wx: float = float(B.x1) + float(A.wall)
	var wy: float = float(areas[6].y0)
	var ix0: float = Y.ox
	var iy0: float = Y.oy
	var ix1: float = float(Y.ox) + 2048.0
	var iy1: float = float(Y.oy) + 2048.0
	return [Rect2(ix0, iy0, ix1 - ix0, 0 - iy0), Rect2(ix0, 0, 0 - ix0, iy1), Rect2(hx, 0, ix1 - hx, hy),
		Rect2(wx, hy, ix1 - wx, wy - hy), Rect2(0, wy, ix1, iy1 - wy)]

func _mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	if tex:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m

## ---------------------------------------------------------------- taking over from the World

## The yard floor is the WorldMesh surface wearing the yard picture: give it a material that draws nothing.
func _hide_world_yard(tex: Texture2D) -> void:
	if world == null or tex == null:
		return
	var wm: MeshInstance3D = world.get_node_or_null("WorldMesh")
	if wm == null or wm.mesh == null:
		return
	var none := ShaderMaterial.new()
	none.shader = Shader.new()
	none.shader.code = "shader_type spatial;\nrender_mode unshaded;\nvoid vertex() { POSITION = vec4(0.0, 0.0, 2.0, 1.0); }\nvoid fragment() { discard; }\n"
	for i in wm.mesh.get_surface_count():
		var m := wm.mesh.surface_get_material(i)
		if m is StandardMaterial3D and m.albedo_texture == tex:
			wm.set_surface_override_material(i, none)

## The World's Ground plane, swapped for four slabs round the region and the heightmap inside it.
func _collision() -> void:
	var x0 := D.X0
	var y0 := D.Y0
	var x1 := D.X0 + D.NX * D.CELL
	var y1 := D.Y0 + D.NY * D.CELL
	var g: StaticBody3D = world.get_node_or_null("Ground") if world else null
	if g:
		for c in g.get_children():
			if c is CollisionShape3D and c.shape is WorldBoundaryShape3D:
				g.remove_child(c)
				c.queue_free()
		var far := 20000.0
		for r in [Rect2(-far, -far, 2 * far, y0 + far), Rect2(-far, y1, 2 * far, far), Rect2(-far, y0, x0 + far, y1 - y0),
				Rect2(x1, y0, far, y1 - y0)]:
			var cs := CollisionShape3D.new()
			var b := BoxShape3D.new()
			b.size = Vector3(r.size.x * U, 2.0, r.size.y * U)
			cs.shape = b
			cs.position = Vector3((r.position.x + r.size.x / 2.0) * U, -1.0, (r.position.y + r.size.y / 2.0) * U)
			g.add_child(cs)
	_body = StaticBody3D.new()
	_body.name = "DigGroundBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	var cs := CollisionShape3D.new()
	_hmap = HeightMapShape3D.new()
	_hmap.map_width = DigGrid.VW
	_hmap.map_depth = DigGrid.VH
	cs.shape = _hmap
	# the heightmap's points are a unit apart round its middle: scale it to a cell (heights are in cells too)
	var s := D.CELL * U
	cs.scale = Vector3(s, s, s)
	cs.position = Vector3((D.X0 + D.NX * D.CELL / 2.0) * U, 0.0, (D.Y0 + D.NY * D.CELL / 2.0) * U)
	_body.add_child(cs)
	_update_hmap()

## The heights from the grid: all of them the first time, then only the chunks whose corners moved.
func _update_hmap() -> void:
	var k := -1.0 / D.CELL
	if _h.size() != grid.depth.size():
		_h.resize(grid.depth.size())
		for i in grid.depth.size():
			_h[i] = grid.depth[i] * k
	else:
		var ncx := DigGrid.chunks_x()
		for ci in grid.hdirty:
			var vx0: int = (ci % ncx) * D.CHUNK
			var vy0: int = (ci / ncx) * D.CHUNK
			for vy in range(vy0, mini(DigGrid.VH, vy0 + D.CHUNK + 1)):
				for vx in range(vx0, mini(DigGrid.VW, vx0 + D.CHUNK + 1)):
					var i := vy * DigGrid.VW + vx
					_h[i] = grid.depth[i] * k
	grid.hdirty.clear()
	_hmap.map_data = _h
	_hmap_dirty = false

## The collision body (for collision exceptions).
func body() -> StaticBody3D:
	return _body

## ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if grid == null:
		return
	# (redrawn at most ten times a second: ploughing changes cells on every step)
	_draw_t += delta
	if not grid.dirty.is_empty() and _draw_t >= 0.1:
		_draw_t = 0.0
		var keys := grid.dirty.keys()
		grid.dirty.clear()
		for i in keys:
			_build_chunk(i)
		_commit()
	if not grid.hdirty.is_empty():
		_hmap_dirty = true
	# (the heightmap is the whole region: rebuilt at most a few times a second)
	_hmap_t += delta
	if _hmap_dirty and _hmap_t > 0.15:
		_hmap_t = 0.0
		_update_hmap()

## Brings the collision up to date now (tests, and after a load).
func flush() -> void:
	if not grid.dirty.is_empty():
		var keys := grid.dirty.keys()
		grid.dirty.clear()
		for i in keys:
			_build_chunk(i)
		_commit()
	_update_hmap()

func _build_chunk(ci: int) -> void:
	var ncx := DigGrid.chunks_x()
	var cx0 := (ci % ncx) * D.CHUNK
	var cy0 := (ci / ncx) * D.CHUNK
	var cx1 := mini(D.NX, cx0 + D.CHUNK)
	var cy1 := mini(D.NY, cy0 + D.CHUNK)
	var gv := PackedVector3Array()
	var guv := PackedVector2Array()
	var sv := PackedVector3Array()
	var suv := PackedVector2Array()
	var sc := PackedColorArray()
	var ov := PackedVector3Array()
	var ouv := PackedVector2Array()
	var oc := PackedColorArray()
	var crect := Rect2(D.X0 + cx0 * D.CELL, D.Y0 + cy0 * D.CELL, (cx1 - cx0) * D.CELL, (cy1 - cy0) * D.CELL)
	# each cell's state, one cell round the chunk too: 0 grass (level), 1 soil (level), 2 off level (a hole or a pile)
	var w := cx1 - cx0 + 2
	var h := cy1 - cy0 + 2
	var st := PackedByteArray()
	st.resize(w * h)
	var any := false
	for cy in range(cy0 - 1, cy1 + 1):
		for cx in range(cx0 - 1, cx1 + 1):
			if cx < 0 or cy < 0 or cx >= D.NX or cy >= D.NY:
				continue
			var k := 0
			if grid._cell_off_level(cx, cy):
				k = 2
			elif grid.soil[cy * D.NX + cx] != D.GRASS:
				k = 1
			if k:
				st[(cy - cy0 + 1) * w + cx - cx0 + 1] = k
				any = true
	# how much each corner is soil: 1 next to a hole or pile, else the share of soil cells round it. Drawn with
	# an alpha scissor at a half, the soil's edge runs round between the cells instead of along their sides
	var va := PackedFloat32Array()
	if any:
		va.resize((w - 1) * (h - 1))
		for vy in h - 1:
			for vx in w - 1:
				var a0 := st[vy * w + vx]
				var a1 := st[vy * w + vx + 1]
				var a2 := st[(vy + 1) * w + vx]
				var a3 := st[(vy + 1) * w + vx + 1]
				if a0 == 2 or a1 == 2 or a2 == 2 or a3 == 2:
					va[vy * (w - 1) + vx] = 1.0
				else:
					va[vy * (w - 1) + vx] = (a0 + a1 + a2 + a3) / 4.0
	# level cells wear the yard picture (soil drawn over it where it's ploughed or dug over): runs of them along
	# each row, a run going on down while the rows below have the same one, so an untouched chunk is one quad
	var open := {}                                 # Vector2i(run start, run end) -> the row it started on
	for cy in range(cy0, cy1 + 1):
		var runs := {}
		if cy < cy1:
			var run := -1
			for cx in range(cx0, cx1 + 1):
				var level := cx < cx1 and st[(cy - cy0 + 1) * w + cx - cx0 + 1] != 2
				if any and cx < cx1:
					var i0 := (cy - cy0) * (w - 1) + cx - cx0
					var al := [va[i0], va[i0 + 1], va[i0 + w], va[i0 + w - 1]]
					if al[0] == 1.0 and al[1] == 1.0 and al[2] == 1.0 and al[3] == 1.0:
						_soil_cell(ov, ouv, oc, cx, cy, al, false)
						level = false                 # (soil all over it: no grass under it to draw)
					elif al[0] > 0.0 or al[1] > 0.0 or al[2] > 0.0 or al[3] > 0.0:
						_soil_cell(sv, suv, sc, cx, cy, al, level)
				if level and run < 0:
					run = cx
				elif not level and run >= 0:
					runs[Vector2i(run, cx)] = true
					run = -1
		for k in open.keys():
			if not runs.has(k):
				var r0: int = open[k]
				_grass(gv, guv, Rect2(D.X0 + k.x * D.CELL, D.Y0 + r0 * D.CELL, (k.y - k.x) * D.CELL, (cy - r0) * D.CELL))
				open.erase(k)
		for k in runs:
			if not open.has(k):
				open[k] = cy
	# (the region's edge chunks: the yard picture past the region, round it)
	if cx0 == 0 or cy0 == 0 or cx1 == D.NX or cy1 == D.NY:
		_outside(gv, guv, crect, cx0 == 0, cy0 == 0, cx1 == D.NX, cy1 == D.NY)
	_garr[ci] = [gv, guv]
	_sarr[ci] = [sv, suv, sc]
	_oarr[ci] = [ov, ouv, oc]

## The two meshes put together from every chunk's arrays.
func _commit() -> void:
	var gv := PackedVector3Array()
	var guv := PackedVector2Array()
	var sv := PackedVector3Array()
	var suv := PackedVector2Array()
	var sc := PackedColorArray()
	for ci in _garr:
		gv.append_array(_garr[ci][0])
		guv.append_array(_garr[ci][1])
	for ci in _sarr:
		sv.append_array(_sarr[ci][0])
		suv.append_array(_sarr[ci][1])
		sc.append_array(_sarr[ci][2])
	var ov := PackedVector3Array()
	var ouv := PackedVector2Array()
	var oc := PackedColorArray()
	for ci in _oarr:
		ov.append_array(_oarr[ci][0])
		ouv.append_array(_oarr[ci][1])
		oc.append_array(_oarr[ci][2])
	_grass_mi.mesh = _mesh(gv, guv, PackedColorArray())
	_soil_mi.mesh = _mesh(sv, suv, sc)
	_soil_mi.visible = not sv.is_empty()
	_solid_mi.mesh = _mesh(ov, ouv, oc)
	_solid_mi.visible = not ov.is_empty()

## The yard picture outside the region (beyond its first/last cells), for the chunks on its edge.
func _outside(gv: PackedVector3Array, guv: PackedVector2Array, r: Rect2, left: bool, top: bool, right: bool, bottom: bool) -> void:
	var big := 3000.0
	var x0 := r.position.x - (big if left else 0.0)
	var x1 := r.end.x + (big if right else 0.0)
	if top:
		_grass(gv, guv, Rect2(x0, r.position.y - big, x1 - x0, big))
	if bottom:
		_grass(gv, guv, Rect2(x0, r.end.y, x1 - x0, big))
	if left:
		_grass(gv, guv, Rect2(r.position.x - big, r.position.y, big, r.size.y))
	if right:
		_grass(gv, guv, Rect2(r.end.x, r.position.y, big, r.size.y))

## A level rectangle of the yard picture, clipped to where the World drew it (round the house).
func _grass(gv: PackedVector3Array, guv: PackedVector2Array, r: Rect2) -> void:
	for yr in _yard_rects:
		var q: Rect2 = r.intersection(yr)
		if q.size.x <= 0.001 or q.size.y <= 0.001:
			continue
		var a := Vector2(q.position.x, q.position.y)
		var b := Vector2(q.end.x, q.position.y)
		var c := Vector2(q.end.x, q.end.y)
		var d := Vector2(q.position.x, q.end.y)
		for p in [a, b, c, a, c, d]:
			gv.append(Vector3(p.x * U, 0.0, p.y * U))
			guv.append((p - _yard_o) / _yard_size)

## A soil cell: its four corners at their depths (alpha: how much each corner is soil), the atlas tile for its soil
## (a grass cell on the soil's edge takes its neighbour's), shaded by slope and depth.
func _soil_cell(sv: PackedVector3Array, suv: PackedVector2Array, sc: PackedColorArray, cx: int, cy: int, al: Array, _level: bool) -> void:
	var i := cy * D.NX + cx
	var s := grid.soil[i]
	var src := i
	if s == D.GRASS:
		for o in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]]:
			var nx: int = cx + o[0]
			var ny: int = cy + o[1]
			if nx >= 0 and ny >= 0 and nx < D.NX and ny < D.NY and grid.soil[ny * D.NX + nx] != D.GRASS:
				src = ny * D.NX + nx
				s = grid.soil[src]
				break
	var tile := 0                                    # dirt
	if s == D.ROWS_X or s == D.ROWS_Y:
		tile = 2 if grid.weedy(src) else 1
	elif s == D.DIRT and grid.weedy(src):
		tile = 3
	var vi := cy * DigGrid.VW + cx
	var hh := [grid.depth[vi], grid.depth[vi + 1], grid.depth[vi + DigGrid.VW + 1], grid.depth[vi + DigGrid.VW]]
	var x0 := D.X0 + cx * D.CELL
	var y0 := D.Y0 + cy * D.CELL
	var ps := [Vector2(x0, y0), Vector2(x0 + D.CELL, y0), Vector2(x0 + D.CELL, y0 + D.CELL), Vector2(x0, y0 + D.CELL)]
	# the tile spans 4 x 4 cells; furrows down the yard use it turned a quarter
	var su := float(cx % 4) / 4.0
	var sv0 := float(cy % 4) / 4.0
	var uvs := [Vector2(su, sv0), Vector2(su + 0.25, sv0), Vector2(su + 0.25, sv0 + 0.25), Vector2(su, sv0 + 0.25)]
	if s == D.ROWS_Y:
		for k in 4:
			uvs[k] = Vector2(uvs[k].y, uvs[k].x)
	# light from the north and a little from above (the sun's to the north), a little darker deeper down
	var gx: float = ((hh[1] + hh[2]) - (hh[0] + hh[3])) * 0.5 / D.CELL
	var gy: float = ((hh[2] + hh[3]) - (hh[0] + hh[1])) * 0.5 / D.CELL
	var n := Vector3(gx, 1.0, gy).normalized()        # (depth grows down: a wall facing north has gy < 0)
	var lit := clampf(0.86 + 0.32 * (n.dot(Vector3(0.0, 0.55, -0.83).normalized()) - 0.55), 0.6, 1.08)
	var cols: Array = []
	for k in 4:
		var deep := clampf(float(hh[k]) / D.MAX_DEPTH, 0.0, 1.0)
		var v := lit * (1.0 - 0.18 * deep)
		cols.append(Color(v, v, v, float(al[k])))
	for k in [0, 1, 2, 0, 2, 3]:
		# (level corners sit a hair over the yard picture drawn under them; every soil cell does the same, so
		# neighbours meet exactly)
		var lift := 0.3 if float(hh[k]) == 0.0 else 0.0
		sv.append(Vector3(ps[k].x * U, (lift - float(hh[k])) * U, ps[k].y * U))
		suv.append(Vector2((float(tile) + uvs[k].x) / 4.0, uvs[k].y))
		sc.append(cols[k])

func _mesh(v: PackedVector3Array, uv: PackedVector2Array, col: PackedColorArray) -> ArrayMesh:
	if v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	if not col.is_empty():
		arr[Mesh.ARRAY_COLOR] = col
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## ---------------------------------------------------------------- the soil pictures

## Four 32 x 32 tiles side by side (each covers 4 x 4 cells, 32 units: a unit a pixel, like the yard picture):
## dug dirt, fresh furrows (running across), weedy furrows, weedy dirt. Pixel art, made here.
static var _atlas: ImageTexture
static func soil_atlas() -> ImageTexture:
	if _atlas:
		return _atlas
	var im := Image.create(128, 32, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1985
	var dirt := [Color8(104, 74, 48), Color8(94, 66, 42), Color8(114, 82, 54), Color8(86, 60, 38)]
	var grass := [Color8(72, 128, 46), Color8(86, 146, 52), Color8(60, 112, 40)]
	for tile in 4:
		for y in 32:
			for x in 32:
				var c: Color = dirt[rng.randi() % 4]
				if tile == 1 or tile == 2:
					# furrows: a ridge, its sunny side, the trough and its shade, every 8 pixels (a cell)
					var r := y % 8
					if r == 0 or r == 1:
						c = Color8(126, 92, 60) if rng.randf() < 0.8 else c
					elif r == 2:
						c = Color8(110, 80, 52)
					elif r == 5 or r == 6:
						c = Color8(70, 48, 30) if rng.randf() < 0.85 else Color8(78, 54, 34)
					elif r == 7:
						c = Color8(82, 58, 36)
				if (tile == 2 or tile == 3) and rng.randf() < 0.22:
					c = grass[rng.randi() % 3]       # weeds coming through
				elif tile == 0 and rng.randf() < 0.05:
					c = Color8(132, 118, 98)          # a stone
				im.set_pixel(tile * 32 + x, y, c)
	im.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(im)
	return _atlas
