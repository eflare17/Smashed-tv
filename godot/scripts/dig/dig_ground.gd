class_name DigGround
extends Node3D
## The yard's ground drawn and made solid: it takes over from the World's flat yard floor.
##
## - Untouched ground (no stored chunk of the DigVolume at the ground's top there) is flat, in three meshes:
##   "DigGrass" the yard picture (the World's own texture), "DigSoilSolid" soil all over a cell (ploughed rows,
##   dug-over dirt) and "DigSoil" the soil's edges (vertex alpha with a scissor, so the edge runs round between
##   cells). Built in chunks of D.CHUNK cells and put together, so the whole flat yard is three draws.
## - Dug ground (stored chunks) is drawn smooth by DigMesher, one mesh per chunk ("Cave_x_y_z"): holes, tunnels,
##   caves, their tops wearing the yard picture or the soil.
## - All of it uses one terrain shader (both looks: lit "high", and the phone's unlit "low" with the look's own
##   tint and lamps), with a cutaway: top-down, while a player is underground, the earth above him near him isn't
##   drawn (the global dig_cut), so he can be seen in his tunnel.
## - The World's yard floor surface is hidden (a material that draws nothing).
## - Collision: the World's Ground (an endless plane at 0) becomes slabs round the region; inside, a flat box for
##   each untouched 16-cell column and the dug chunks' triangles (ConcavePolygonShape3D), on layer 1 (the world).
##   Players walk by DigBody (Dig moves them on the volume), so their capsules don't collide with it.

const D := preload("res://scripts/dig/dig_data.gd")
const U := 0.025

var grid: DigGrid
var vol: DigVolume
var world: Node3D
var mesher := DigMesher.new()
var _garr: Dictionary = {}            # flat chunk index -> [vertices, uvs] of its level yard
var _sarr: Dictionary = {}            # flat chunk index -> [vertices, uv2s, colours] of its soil's edge cells
var _oarr: Dictionary = {}            # flat chunk index -> [vertices, uv2s, colours] of its soil all over
var _grass_mi: MeshInstance3D
var _soil_mi: MeshInstance3D
var _solid_mi: MeshInstance3D
var _caves: Dictionary = {}           # Vector3i -> MeshInstance3D
var _cave_shapes: Dictionary = {}     # Vector3i -> CollisionShape3D
var _col_boxes: Dictionary = {}       # Vector2i (16-cell column) -> CollisionShape3D (flat, untouched)
var _yard_tex: Texture2D
var _yard_rects: Array = []
var _yard_o := Vector2(-45, -50)
var _yard_size := Vector2(2048, 2048)
var _body: StaticBody3D
var _mats: Dictionary = {}            # "pic" / "soil" / "edge" / "cave" -> ShaderMaterial
var _quality := ""
var _look: Node
var _draw_t := 0.0
var _q_t := 0.0
var _soil_seen: Dictionary = {}       # top chunk -> the grid version its soil was drawn at

## Hides the World's yard floor, swaps its endless ground for slabs, and builds everything.
func setup(g: DigGrid, v: DigVolume, w: Node3D) -> void:
	grid = g
	vol = v
	world = w
	name = "DigGround"
	_yard_tex = w.get("_yard_tex") if w else null
	var sz = w.get("_yard_size") if w else null
	if sz is Vector2:
		_yard_size = sz
	var Y: Dictionary = GameData.data.get("YARD", {"ox": -45, "oy": -50})
	_yard_o = Vector2(float(Y.ox), float(Y.oy))
	_yard_rects = yard_rects()
	mesher.vol = vol
	mesher.grid = grid
	mesher.yard_o = _yard_o
	mesher.yard_size = _yard_size
	register_globals()
	_look = w.get_tree().root.find_child("LookPass", true, false) if w else null
	_make_mats()
	_hide_world_yard(_yard_tex)
	_grass_mi = _mi("DigGrass", _mats.pic)
	_solid_mi = _mi("DigSoilSolid", _mats.soil)
	_soil_mi = _mi("DigSoil", _mats.edge)
	_body = StaticBody3D.new()
	_body.name = "DigGroundBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_slabs()
	for i in DigGrid.chunks_x() * DigGrid.chunks_y():
		_build_flat(i)
	_commit()
	for key in vol.chunks.keys():
		_build_cave(key)
	_columns_all()
	grid.dirty.clear()
	vol.dirty.clear()

func _mi(n: String, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

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

## ---------------------------------------------------------------- the terrain shader

const SHADER := """
shader_type spatial;
render_mode cull_disabled%RM%;
%LOWFN%
uniform sampler2D pic : source_color, filter_nearest_mipmap;
uniform sampler2D atlas : source_color, filter_nearest, repeat_enable;
// 0 the yard picture; 1 the soil atlas (COLOR.a: the soil's edge, cut at a half); 2 either (COLOR.a 1: picture)
uniform int mode = 0;
global uniform vec4 dig_cut;
varying vec3 wpos;
varying vec3 wnrm;
vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	if (dig_cut.w > 0.0 && wpos.y > dig_cut.y) {
		vec2 d = wpos.xz - dig_cut.xz;
		if (dot(d, d) < dig_cut.w * dig_cut.w) discard;
	}
	vec4 c;
	if (mode == 0 || (mode == 2 && COLOR.a > 0.5)) {
		c = texture(pic, UV);
	} else {
		// the soil atlas, laid on whichever plane the face is most along (a tile is 32 units: 0.8 m)
		vec3 n = abs(wnrm);
		vec2 p = (n.y >= n.x && n.y >= n.z) ? wpos.xz : ((n.x >= n.z) ? wpos.zy : wpos.xy);
		p /= 0.8;
		if (UV2.y > 0.5) p = p.yx;
		c = texture(atlas, vec2((UV2.x + fract(p.x)) / 4.0, fract(p.y)));
	}
	ALBEDO = c.rgb * lin(max(COLOR.rgb, vec3(0.0)));
	%ALPHA%
	%LIGHT%
}
"""

## The look's globals (the low look's tint and lamps: LookPass registers them; here too in case it isn't
## installed) and dig_cut.
static var _globals_done := false
static func register_globals() -> void:
	if _globals_done:
		return
	_globals_done = true
	if not ProjectSettings.has_setting("shader_globals/dig_cut"):
		RenderingServer.global_shader_parameter_add("dig_cut", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	LookPass.register_globals()

func _code(high: bool, scissor: bool) -> String:
	return SHADER.replace("%RM%", ", specular_disabled, diffuse_lambert" if high else ", unshaded") \
		.replace("%LOWFN%", "" if high else LookPass.LOW_FN) \
		.replace("%ALPHA%", "ALPHA = COLOR.a; ALPHA_SCISSOR_THRESHOLD = 0.5;" if scissor else "") \
		.replace("%LIGHT%", "ROUGHNESS = 1.0;" if high else "ALBEDO *= look_light(wpos);")

static var _shaders: Dictionary = {}
func _shader(high: bool, scissor: bool) -> Shader:
	var k := "%s%s" % [high, scissor]
	if not _shaders.has(k):
		var s := Shader.new()
		s.code = _code(high, scissor)
		_shaders[k] = s
	return _shaders[k]

func _quality_now() -> String:
	if _look and is_instance_valid(_look):
		return String(_look.get("quality"))
	return "low"

func _make_mats() -> void:
	_quality = _quality_now()
	var high := _quality == "high"
	var atlas := soil_atlas()
	for k in ["pic", "soil", "edge", "cave"]:
		var m := ShaderMaterial.new()
		m.shader = _shader(high, k == "edge")
		m.set_shader_parameter("pic", _yard_tex)
		m.set_shader_parameter("atlas", atlas)
		m.set_shader_parameter("mode", {"pic": 0, "soil": 1, "edge": 1, "cave": 2}[k])
		_mats[k] = m

## The look changed (F8, or the automatic drop on a slow desktop): the same materials, the other shaders.
func _check_quality(delta: float) -> void:
	_q_t += delta
	if _q_t < 0.5:
		return
	_q_t = 0.0
	if _look == null or not is_instance_valid(_look):
		_look = get_tree().root.find_child("LookPass", true, false)
	var q := _quality_now()
	if q == _quality:
		return
	_quality = q
	for k in _mats:
		_mats[k].shader = _shader(q == "high", k == "edge")

## ---------------------------------------------------------------- taking over from the World

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

## The World's Ground plane, swapped for four slabs round the region.
func _slabs() -> void:
	var x0 := D.X0
	var y0 := D.Y0
	var x1 := D.X0 + D.NX * D.CELL
	var y1 := D.Y0 + D.NY * D.CELL
	var g: StaticBody3D = world.get_node_or_null("Ground") if world else null
	if g == null:
		return
	for c in g.get_children():
		if c is CollisionShape3D and c.shape is WorldBoundaryShape3D:
			g.remove_child(c)
			c.queue_free()
	var far := 20000.0
	for r in [Rect2(-far, -far, 2 * far, y0 + far), Rect2(-far, y1, 2 * far, far), Rect2(-far, y0, x0 + far, y1 - y0),
			Rect2(x1, y0, far, y1 - y0)]:
		g.add_child(_box_shape(r))

func _box_shape(r: Rect2) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(r.size.x * U, 2.0, r.size.y * U)
	cs.shape = b
	cs.position = Vector3((r.position.x + r.size.x / 2.0) * U, -1.0, (r.position.y + r.size.y / 2.0) * U)
	return cs

## The collision body (for collision exceptions).
func body() -> StaticBody3D:
	return _body

## ---------------------------------------------------------------- collision inside the region

func _columns_all() -> void:
	for cj in int(ceil(float(D.NY) / 16.0)):
		for ci in int(ceil(float(D.NX) / 16.0)):
			_column(Vector2i(ci, cj))

## A 16-cell column: a flat box while its top is untouched, else nothing (its chunks' triangles are the floor).
func _column(c: Vector2i) -> void:
	var stored := vol.chunks.has(Vector3i(c.x, c.y, DigVolume.top_layer()))
	var box: CollisionShape3D = _col_boxes.get(c)
	if stored and box:
		box.queue_free()
		_col_boxes.erase(c)
	elif not stored and box == null:
		var r := Rect2(D.X0 + c.x * 16 * D.CELL, D.Y0 + c.y * 16 * D.CELL, 16 * D.CELL, 16 * D.CELL)
		box = _box_shape(r)
		_body.add_child(box)
		_col_boxes[c] = box

## ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if grid == null:
		return
	_check_quality(delta)
	# dug chunks: one a frame, the nearest to the player first (a dig changes a few: spread out, no stall)
	if not vol.dirty.is_empty():
		var near := _nearest_dirty()
		vol.dirty.erase(near)
		_cave_changed(near)
		_column(Vector2i(near.x, near.y))
	# the flat yard: at most ten times a second (ploughing changes cells on every step)
	_draw_t += delta
	if _draw_t < 0.1 or grid.dirty.is_empty():
		return
	_draw_t = 0.0
	_flat_changed()

func _nearest_dirty() -> Vector3i:
	var p = get_tree().get_first_node_in_group("player")
	var at := Vector3(800, 1200, 0)
	if p is Node3D:
		at = GameData.from_3d(p.global_position)
	var best: Vector3i = vol.dirty.keys()[0]
	var best_d := INF
	for key in vol.dirty:
		var c := Vector3(D.X0 + (key.x * 16 + 8) * D.CELL, D.Y0 + (key.y * 16 + 8) * D.CELL, D.ZMIN + (key.z * 16 + 8) * D.CELL)
		var d := c.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = key
	return best

## Brings the meshes and the collision up to date now (also for the tests).
func flush() -> void:
	flush_draw()

func flush_draw() -> void:
	var keys := vol.dirty.keys()
	vol.dirty.clear()
	for key in keys:
		_cave_changed(key)
	_flat_changed()
	for key in keys:
		_column(Vector2i(key.x, key.y))

## A dug chunk changed: redraw it; the flat yard there goes or comes back with its top chunk.
func _cave_changed(key: Vector3i) -> void:
	_build_cave(key)
	if key.z == DigVolume.top_layer():
		for cy in range(key.y * 16, mini(D.NY, key.y * 16 + 16), 8):
			for cx in range(key.x * 16, mini(D.NX, key.x * 16 + 16), 8):
				grid.dirty[DigGrid.chunk_of_cell(cx, cy)] = true

## The flat yard's changed chunks; soil on dug ground changes its chunks' tops' look too.
func _flat_changed() -> void:
	if grid.dirty.is_empty():
		return
	var keys2 := grid.dirty.keys()
	grid.dirty.clear()
	var redo := {}
	for i in keys2:
		_build_flat(i)
		var ncx := DigGrid.chunks_x()
		var fx: int = (i % ncx) * D.CHUNK
		var fy: int = (i / ncx) * D.CHUNK
		for oy in [0, 16]:
			for ox in [0, 16]:
				var key := Vector3i((fx + ox) >> 4, (fy + oy) >> 4, DigVolume.top_layer())
				if vol.chunks.has(key):
					redo[key] = true
	_commit()
	# (soil marks on dug chunks: redrawn in the queue, one a frame)
	for key in redo:
		if not _soil_seen.has(key) or _soil_seen[key] != grid.version:
			_soil_seen[key] = grid.version
			vol.dirty[key] = true

func _build_cave(key: Vector3i) -> void:
	var mi: MeshInstance3D = _caves.get(key)
	var cs: CollisionShape3D = _cave_shapes.get(key)
	if not vol.chunks.has(key):
		if mi:
			mi.queue_free()
			_caves.erase(key)
		if cs:
			cs.queue_free()
			_cave_shapes.erase(key)
		return
	mesher.build(key)
	if mi == null:
		mi = _mi("Cave_%d_%d_%d" % [key.x, key.y, key.z], _mats.cave)
		_caves[key] = mi
	if mesher.verts.is_empty():
		mi.mesh = null
		mi.visible = false
		if cs:
			cs.queue_free()
			_cave_shapes.erase(key)
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = mesher.verts
	arr[Mesh.ARRAY_NORMAL] = mesher.normals
	arr[Mesh.ARRAY_TEX_UV] = mesher.uvs
	arr[Mesh.ARRAY_TEX_UV2] = mesher.uv2s
	arr[Mesh.ARRAY_COLOR] = mesher.cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = m
	mi.visible = true
	if cs == null:
		cs = CollisionShape3D.new()
		cs.shape = ConcavePolygonShape3D.new()
		_body.add_child(cs)
		_cave_shapes[key] = cs
	(cs.shape as ConcavePolygonShape3D).set_faces(mesher.verts)

func _build_flat(ci: int) -> void:
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
	# each cell, one round the chunk too: 0 grass, 1 soil, 2 drawn by the smooth mesh (its top chunk is stored)
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
			if vol.top_stored(cx, cy):
				k = 2
			elif grid.soil[cy * D.NX + cx] != D.GRASS:
				k = 1
			if k:
				st[(cy - cy0 + 1) * w + cx - cx0 + 1] = k
				any = true
	# how much each corner is soil (only soil cells count: the smooth mesh does its own)
	var va := PackedFloat32Array()
	if any:
		va.resize((w - 1) * (h - 1))
		for vy in h - 1:
			for vx in w - 1:
				var n := 0
				for o in [vy * w + vx, vy * w + vx + 1, (vy + 1) * w + vx, (vy + 1) * w + vx + 1]:
					if st[o] == 1:
						n += 1
				va[vy * (w - 1) + vx] = n / 4.0
	# level yard: runs of cells along each row, a run going on down while the rows below have the same one
	var open := {}
	for cy in range(cy0, cy1 + 1):
		var runs := {}
		if cy < cy1:
			var run := -1
			for cx in range(cx0, cx1 + 1):
				var kk := st[(cy - cy0 + 1) * w + cx - cx0 + 1] if cx < cx1 else 2
				var level := cx < cx1 and kk != 2
				if any and level:
					var i0 := (cy - cy0) * (w - 1) + cx - cx0
					var al := [va[i0], va[i0 + 1], va[i0 + w], va[i0 + w - 1]]
					if al[0] == 1.0 and al[1] == 1.0 and al[2] == 1.0 and al[3] == 1.0:
						_soil_cell(ov, ouv, oc, cx, cy, al)
						level = false                 # (soil all over it: no yard under it to draw)
					elif al[0] > 0.0 or al[1] > 0.0 or al[2] > 0.0 or al[3] > 0.0:
						_soil_cell(sv, suv, sc, cx, cy, al)
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

## The three flat meshes put together from every chunk's arrays.
func _commit() -> void:
	var gv := PackedVector3Array()
	var guv := PackedVector2Array()
	for ci in _garr:
		gv.append_array(_garr[ci][0])
		guv.append_array(_garr[ci][1])
	_grass_mi.mesh = _mesh(gv, guv, PackedVector2Array(), PackedColorArray())
	for pair in [[_sarr, _soil_mi], [_oarr, _solid_mi]]:
		var v := PackedVector3Array()
		var u2 := PackedVector2Array()
		var c := PackedColorArray()
		for ci in pair[0]:
			v.append_array(pair[0][ci][0])
			u2.append_array(pair[0][ci][1])
			c.append_array(pair[0][ci][2])
		pair[1].mesh = _mesh(v, PackedVector2Array(), u2, c)
		pair[1].visible = not v.is_empty()

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

## A level soil cell a hair over the yard: its tile (a grass cell on the soil's edge takes its neighbour's),
## how much each corner is soil (alpha).
func _soil_cell(sv: PackedVector3Array, suv: PackedVector2Array, sc: PackedColorArray, cx: int, cy: int, al: Array) -> void:
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
	var tile := 0
	if s == D.ROWS_X or s == D.ROWS_Y:
		tile = 2 if grid.weedy(src) else 1
	elif s == D.DIRT and grid.weedy(src):
		tile = 3
	var t2 := Vector2(tile, 1 if s == D.ROWS_Y else 0)
	var x0 := D.X0 + cx * D.CELL
	var y0 := D.Y0 + cy * D.CELL
	var ps := [Vector2(x0, y0), Vector2(x0 + D.CELL, y0), Vector2(x0 + D.CELL, y0 + D.CELL), Vector2(x0, y0 + D.CELL)]
	for k in [0, 1, 2, 0, 2, 3]:
		sv.append(Vector3(ps[k].x * U, 0.3 * U, ps[k].y * U))
		suv.append(t2)
		sc.append(Color(0.92, 0.92, 0.92, float(al[k])))

func _mesh(v: PackedVector3Array, uv: PackedVector2Array, uv2: PackedVector2Array, col: PackedColorArray) -> ArrayMesh:
	if v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var n := PackedVector3Array()
	n.resize(v.size())
	n.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = n
	if not uv.is_empty():
		arr[Mesh.ARRAY_TEX_UV] = uv
	if not uv2.is_empty():
		arr[Mesh.ARRAY_TEX_UV2] = uv2
	if not col.is_empty():
		arr[Mesh.ARRAY_COLOR] = col
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## ---------------------------------------------------------------- the soil pictures

## Four 32 x 32 tiles side by side (each covers 32 units, a unit a pixel like the yard picture): dug dirt, fresh
## furrows (running across), weedy furrows, weedy dirt. Pixel art, made here.
static var _atlas: ImageTexture
static func soil_atlas() -> ImageTexture:
	if _atlas:
		return _atlas
	var im := Image.create(128, 32, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1985
	var dirt := [Color8(104, 74, 48), Color8(94, 66, 42), Color8(114, 82, 54), Color8(86, 60, 38)]
	var grass := [Color8(72, 128, 46), Color8(86, 146, 52), Color8(60, 112, 40)]
	for tile in 4:
		for y in 32:
			for x in 32:
				var c: Color = dirt[rng.randi() % 4]
				if tile == 1 or tile == 2:
					# furrows: a ridge, its sunny side, the trough and its shade, every 8 pixels
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
	_atlas = ImageTexture.create_from_image(im)
	return _atlas
