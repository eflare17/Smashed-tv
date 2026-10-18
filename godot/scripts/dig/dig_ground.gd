class_name DigGround
extends Node3D
## The yard's ground drawn and made solid from a DigGrid: it takes over from the World's flat yard floor.
##
## - Meshes: one pair of MeshInstance3Ds per chunk of D.CHUNK x D.CHUNK cells. "G" wears the yard picture (the
##   World's own texture, so it looks exactly as before) on level grass; "S" wears the soil atlas (dug dirt,
##   furrows, weedy furrows) on every cell that's dug, piled or ploughed, shaded by its slope and depth so holes
##   read in the unlit phone look too. Untouched chunks are a few big quads (the yard's rectangles, round the
##   house). Their materials are plain unshaded StandardMaterial3Ds, so the look pass lights them like the rest
##   of the World (it lights whatever is added under the World).
## - The World's yard floor surface is hidden (a material that draws nothing), so it can't cover the holes.
## - Collision: the World's Ground (an endless plane at 0) becomes four slabs round the dig region, and inside it
##   a HeightMapShape3D of the grid (on layer 1, the world, like the plane was). Players walk by their own
##   height (Player sets y from dz), so Dig stands them on the ground (and keeps their capsule out of this
##   shape: a collision exception), but anything physical lands in the holes.

const D := preload("res://scripts/dig/dig_data.gd")
const U := 0.025

var grid: DigGrid
var world: Node3D
var _chunks: Dictionary = {}          # chunk index -> [G MeshInstance3D, S MeshInstance3D]
var _yard_mat: StandardMaterial3D
var _soil_mat: StandardMaterial3D
var _yard_rects: Array = []           # where the World drew the yard picture (round the house), HTML units
var _yard_o := Vector2(-45, -50)
var _yard_size := Vector2(2048, 2048)
var _body: StaticBody3D
var _hmap: HeightMapShape3D
var _hmap_dirty := false
var _hmap_t := 0.0

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
	_hide_world_yard(tex)
	_collision()
	for i in DigGrid.chunks_x() * DigGrid.chunks_y():
		_build_chunk(i)
	grid.dirty.clear()

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

func _update_hmap() -> void:
	var h := PackedFloat32Array()
	h.resize(grid.depth.size())
	var k := -1.0 / D.CELL
	for i in grid.depth.size():
		h[i] = grid.depth[i] * k
	_hmap.map_data = h
	_hmap_dirty = false

## The collision body (for collision exceptions).
func body() -> StaticBody3D:
	return _body

## ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if grid == null:
		return
	if not grid.dirty.is_empty():
		var keys := grid.dirty.keys()
		grid.dirty.clear()
		for i in keys:
			_build_chunk(i)
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
	var crect := Rect2(D.X0 + cx0 * D.CELL, D.Y0 + cy0 * D.CELL, (cx1 - cx0) * D.CELL, (cy1 - cy0) * D.CELL)
	# level grass: runs of flat cells along each row, clipped to the yard picture's rectangles
	for cy in range(cy0, cy1):
		var run := -1
		for cx in range(cx0, cx1 + 1):
			var flat := cx < cx1 and grid.cell_flat(cx, cy)
			if flat and run < 0:
				run = cx
			elif not flat and run >= 0:
				_grass(gv, guv, Rect2(D.X0 + run * D.CELL, D.Y0 + cy * D.CELL, (cx - run) * D.CELL, D.CELL))
				run = -1
			if not flat and cx < cx1:
				_soil_cell(sv, suv, sc, cx, cy)
	# (the region's edge chunks: the yard picture past the region, round it)
	if cx0 == 0 or cy0 == 0 or cx1 == D.NX or cy1 == D.NY:
		_outside(gv, guv, crect, cx0 == 0, cy0 == 0, cx1 == D.NX, cy1 == D.NY)
	var pair: Array = _chunks.get(ci, [])
	if pair.is_empty():
		var g := MeshInstance3D.new()
		g.name = "DigG%d" % ci
		g.material_override = _yard_mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		var s := MeshInstance3D.new()
		s.name = "DigS%d" % ci
		s.material_override = _soil_mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		pair = [g, s]
		_chunks[ci] = pair
	pair[0].mesh = _mesh(gv, guv, PackedColorArray())
	pair[0].visible = not gv.is_empty()
	pair[1].mesh = _mesh(sv, suv, sc)
	pair[1].visible = not sv.is_empty()

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

## A soil cell: its four corners at their depths, the atlas tile for its soil, shaded by slope and depth.
func _soil_cell(sv: PackedVector3Array, suv: PackedVector2Array, sc: PackedColorArray, cx: int, cy: int) -> void:
	var i := cy * D.NX + cx
	var s := grid.soil[i]
	var tile := 0                                    # dirt
	if s == D.ROWS_X or s == D.ROWS_Y:
		tile = 2 if grid.weedy(i) else 1
	elif s == D.DIRT and grid.weedy(i):
		tile = 3
	var vi := cy * DigGrid.VW + cx
	var h := [grid.depth[vi], grid.depth[vi + 1], grid.depth[vi + DigGrid.VW + 1], grid.depth[vi + DigGrid.VW]]
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
	# light from the north and a little from above (the sun's to the north), darker deeper down
	var gx: float = ((h[1] + h[2]) - (h[0] + h[3])) * 0.5 / D.CELL
	var gy: float = ((h[2] + h[3]) - (h[0] + h[1])) * 0.5 / D.CELL
	var n := Vector3(gx, 1.0, gy).normalized()        # (depth grows down: a wall facing north has gy > 0)
	var lit := clampf(0.78 + 0.3 * n.dot(Vector3(0.0, 0.55, -0.83).normalized()) - 0.1, 0.55, 1.05)
	var cols: Array = []
	for k in 4:
		var deep := clampf(float(h[k]) / D.MAX_DEPTH, 0.0, 1.0)
		var v := lit * (1.0 - 0.32 * deep)
		cols.append(Color(v, v, v))
	for k in [0, 1, 2, 0, 2, 3]:
		sv.append(Vector3(ps[k].x * U, -h[k] * U, ps[k].y * U))
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
