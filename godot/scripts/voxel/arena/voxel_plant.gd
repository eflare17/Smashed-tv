class_name VoxelPlant
extends Node3D
## A weed plant growing in the yard (Stage 5: "bring the weed growing mechanics across"), built in cubes from the HTML
## game's own plant art (assets/voxel/art/weed_sheet.png, its WEED_SHEET: six strains down, four stages across, 44 x
## 64 each; a seventh row added, Bush Kush, from the owner's own picture): each picture's pixels become cubes, two of the pictures crossed through each other so it's a plant from
## every side. Dry it droops (squashed down, yellowed), wilted it goes brown (as the HTML game's weedArt), and a drop
## bobs over it asking for water; ready, its buds glint. It sways in the breeze. Meshes are made once per strain,
## stage and look, and shared. Owned by the voxel session.

const SHEET := "res://assets/voxel/art/weed_sheet.png"
const W := 44
const H := 64
const FOOT := Vector2(21.5, 60.0)   # the stem's foot in the picture
const VOX := 0.017                  # metres a pixel (a ready plant ~1 m tall)
const BUSHY := [6]                  # strains built as a round bush, not crossed slabs (Bush Kush: the owner, "shouldn't
                                    # it be more bushy?") ...
const BUSH_SCALE := 1.3             # ... and a bit bigger (its picture's smaller than the others')

static var _img: Image
static var _meshes := {}            # "s,stage,look" -> ArrayMesh
static var _mat: StandardMaterial3D

var strain := 0
var stage := 0
var look := 0                       # 0 healthy, 1 dry, 2 wilted
var _mi: MeshInstance3D
var _drop: MeshInstance3D
var _wet: MeshInstance3D
var _t := 0.0

func _ready() -> void:
	_t = randf() * 10.0
	_mi = MeshInstance3D.new()
	add_child(_mi)
	# the damp patch of soil round its foot (watered)
	_wet = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.5, 0.5)
	_wet.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.12, 0.07, 0.04, 0.6)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.3
	_wet.material_override = wm
	_wet.position.y = 0.004
	add_child(_wet)
	# the drop over it, wanting water
	_drop = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.1
	_drop.mesh = sm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color8(124, 200, 255)
	dm.emission_enabled = true
	dm.emission = Color8(60, 140, 255)
	dm.emission_energy_multiplier = 0.6
	_drop.material_override = dm
	add_child(_drop)
	_apply()

## Shows strain s at stage st (0 seedling .. 3 ready) looking lk (0 healthy, 1 dry, 2 wilted), watered or not.
func show_as(s: int, st: int, lk: int, wet: bool) -> void:
	_wet.visible = wet
	if s == strain and st == stage and lk == look and _mi.mesh != null:
		return
	strain = s
	stage = st
	look = lk
	_apply()

func _apply() -> void:
	if _mi == null:
		return
	_mi.mesh = mesh_for(strain, stage, look)
	_mi.material_override = _mat
	_drop.visible = look > 0
	_drop.position.y = _top(strain, stage, look) + 0.12

func _process(dt: float) -> void:
	_t += dt
	if look == 0:
		_mi.rotation = Vector3(sin(_t * 1.1) * 0.035, 0, cos(_t * 0.8) * 0.03)     # in the breeze, from its foot
	else:
		_mi.rotation = Vector3.ZERO
	if _drop.visible:
		_drop.position.y = _top(strain, stage, look) + 0.12 + sin(_t * 4.0) * 0.02

## How tall the picture's plant stands (metres above its foot).
static var _tops := {}               # s, stage, look -> the height (worked out once: it scans the sheet)

static func _top(s: int, st: int, lk: int) -> float:
	var k := s * 100 + st * 10 + lk
	if _tops.has(k):
		return _tops[k]
	_load()
	var top := int(FOOT.y)
	for y in int(FOOT.y):
		var found := false
		for x in W:
			if _img.get_pixel(st * W + x, s * H + y).a > 0.5:
				found = true
				break
		if found:
			top = y
			break
	var squash: float = [1.0, 54.0 / 60.0, 47.0 / 60.0][lk]
	_tops[k] = (FOOT.y - top) * VOX * squash * (BUSH_SCALE if s in BUSHY else 1.0)
	return _tops[k]

static func _load() -> void:
	if _img == null:
		var tex: Texture2D = load(SHEET)
		_img = tex.get_image()
		if _img.is_compressed():
			_img.decompress()
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.85

## The plant's cubes as one mesh (cached): the picture's pixels on two crossed slabs a cube thick, standing on its foot.
static func mesh_for(s: int, st: int, lk: int) -> ArrayMesh:
	var key := "%d,%d,%d" % [s, st, lk]
	if _meshes.has(key):
		return _meshes[key]
	_load()
	var squash: float = [1.0, 54.0 / 60.0, 47.0 / 60.0][lk]
	var tint: Color = [Color(0, 0, 0, 0), Color(176 / 255.0, 154 / 255.0, 58 / 255.0, 0.42), Color(118 / 255.0, 78 / 255.0, 40 / 255.0, 0.6)][lk]
	# the opaque pixels (picture rows 0..59 above the foot)
	var px := {}
	for y in int(FOOT.y):
		for x in W:
			var c := _img.get_pixel(st * W + x, s * H + y)
			if c.a > 0.5 and c.r + c.g + c.b > 0.22:      # (the picture's black outline left out: in cubes it's specks)
				if tint.a > 0.0:
					c = c.lerp(Color(tint.r, tint.g, tint.b), tint.a)
				px[Vector2i(x, y)] = c
	var st_tool := SurfaceTool.new()
	st_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	if s in BUSHY:
		var bm := _bush(px, VOX * BUSH_SCALE, VOX * BUSH_SCALE * squash)
		_meshes[key] = bm
		return bm
	var sx := VOX
	var sy := VOX * squash
	for slab in 2:
		for p: Vector2i in px:
			var c: Color = px[p]
			var u := (float(p.x) - FOOT.x) * sx
			var v := (FOOT.y - float(p.y) - 1.0) * sy
			var o := Vector3(u, v, -sx * 0.5) if slab == 0 else Vector3(sx * 0.5, v, u)
			var size := Vector3(sx, sy, sx)
			var nb := [px.has(p + Vector2i(1, 0)), px.has(p + Vector2i(-1, 0)), px.has(p + Vector2i(0, -1)), px.has(p + Vector2i(0, 1))]
			_cube(st_tool, o, size, c, nb, slab)
	st_tool.generate_normals()
	var m := st_tool.commit()
	_meshes[key] = m
	return m

## A round bush from the picture (px: its pixels -> colours): each row a disc of cubes as wide as the row, the picture
## its outline from the front and the back, again (a couple of rows lower, so it's not the same) from the sides, and
## from the corners the two together; each side shows the picture's leaves as seen from that way, darker deeper in.
## Only the faces showing are made.
static func _bush(px: Dictionary, sx: float, sy: float) -> ArrayMesh:
	var cx := int(FOOT.x)
	var NY := int(FOOT.y)
	# the picture as flat arrays (fast to look in): its colours and whether a pixel's there, rows' reach from the stem
	var pic := PackedColorArray()
	pic.resize(W * NY)
	var has := PackedByteArray()
	has.resize(W * NY)
	var reach_of := PackedInt32Array()
	reach_of.resize(NY)
	for p: Vector2i in px:
		if p.y < NY and p.x >= 0 and p.x < W:
			pic[p.y * W + p.x] = px[p]
			has[p.y * W + p.x] = 1
			reach_of[p.y] = maxi(reach_of[p.y], absi(p.x - cx) + 1)
	var R := 22
	var NX := 2 * R + 1
	var cells := PackedByteArray()
	cells.resize(NX * NX * NY)
	var cols := PackedColorArray()
	cols.resize(NX * NX * NY)
	for y in NY:
		var reach := reach_of[y]
		if reach == 0:
			continue
		var ys := mini(y + 2, NY - 1)        # (the sides' outline: the picture a couple of rows down)
		var row := y * W
		var rows := ys * W
		for vz in range(-reach, reach + 1):
			for vx in range(-reach, reach + 1):
				var d2 := vx * vx + vz * vz
				if d2 > reach * reach:
					continue
				var ax := absi(vx)
				var az := absi(vz)
				var fx := cx + vx
				var sxp := cx - vz
				# in it if it's inside the front's outline (the picture across x) or the side's (across z)
				var front := ax >= az and fx >= 0 and fx < W and has[row + fx] == 1
				var side := az >= ax and sxp >= 0 and sxp < W and has[rows + sxp] == 1
				var d := sqrt(float(d2))
				if not front and not side and d > reach * 0.72:
					continue
				# its colour: the picture as seen from the way it faces (front or back: across x; the sides: across
				# z, mirrored round the back), else the outline's, else the nearest the picture has in the row
				var c := Color(0, 0, 0, 0)
				if az >= ax:
					if fx >= 0 and fx < W and has[row + fx] == 1:
						c = pic[row + fx]
				else:
					var qx := cx + (-vz if vx > 0 else vz)
					if qx >= 0 and qx < W and has[rows + qx] == 1:
						c = pic[rows + qx]
				if c.a == 0.0:
					if front:
						c = pic[row + fx]
					elif side:
						c = pic[rows + sxp]
				if c.a == 0.0:
					for k in range(0, reach + 1):
						var kx := cx + (k if vx >= 0 else -k)
						if kx >= 0 and kx < W and has[row + kx] == 1:
							c = pic[row + kx]
							break
				if c.a == 0.0:
					continue
				var i := (y * NX + (vz + R)) * NX + (vx + R)
				cells[i] = 1
				var k2 := 0.7 + 0.3 * clampf(d / float(reach), 0.0, 1.0)
				cols[i] = Color(c.r * k2, c.g * k2, c.b * k2, 1.0)
	var dirs := [[Vector3i(1, 0, 0), 0.85], [Vector3i(-1, 0, 0), 0.85], [Vector3i(0, 1, 0), 1.0], [Vector3i(0, -1, 0), 0.6], [Vector3i(0, 0, 1), 0.95], [Vector3i(0, 0, -1), 0.8]]
	var size := Vector3(sx, sy, sx)
	# (straight into the mesh's arrays: much quicker than a SurfaceTool)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var vcols := PackedColorArray()
	for i in cells.size():
		if cells[i] == 0:
			continue
		var vx := i % NX - R
		var vz := (i / NX) % NX - R
		var y := i / (NX * NX)
		var c: Color = cols[i]
		var o := Vector3(vx * sx - sx * 0.5, (FOOT.y - float(y) - 1.0) * sy, vz * sx - sx * 0.5)
		for dd in dirs:
			var n: Vector3i = dd[0]
			var nx := vx + n.x
			var nz := vz + n.z
			var ny := y - n.y               # (picture rows run down; up is a row less)
			if nx >= -R and nx <= R and nz >= -R and nz <= R and ny >= 0 and ny < NY and cells[(ny * NX + (nz + R)) * NX + (nx + R)] == 1:
				continue
			var k: float = dd[1]
			_face(verts, norms, vcols, o, size, n, Color(c.r * k, c.g * k, c.b * k))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = vcols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## One face of a cube at o (its low corner) of size s, facing n
static func _face(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, o: Vector3, s: Vector3, n: Vector3i, c: Color) -> void:
	var q: Array
	if n.x != 0:
		var x := o.x + (s.x if n.x > 0 else 0.0)
		q = [Vector3(x, o.y, o.z), Vector3(x, o.y + s.y, o.z), Vector3(x, o.y + s.y, o.z + s.z), Vector3(x, o.y, o.z + s.z)]
	elif n.y != 0:
		var y := o.y + (s.y if n.y > 0 else 0.0)
		q = [Vector3(o.x, y, o.z), Vector3(o.x, y, o.z + s.z), Vector3(o.x + s.x, y, o.z + s.z), Vector3(o.x + s.x, y, o.z)]
	else:
		var z := o.z + (s.z if n.z > 0 else 0.0)
		q = [Vector3(o.x, o.y, z), Vector3(o.x + s.x, o.y, z), Vector3(o.x + s.x, o.y + s.y, z), Vector3(o.x, o.y + s.y, z)]
	# (wound to face n: flipped for the ones facing the positive way)
	var order := [0, 1, 2, 0, 2, 3] if (n.x + n.y + n.z) < 0 else [0, 2, 1, 0, 3, 2]
	var nv := Vector3(n)
	for k in order:
		verts.append(q[k])
		norms.append(nv)
		cols.append(c)

# a pixel's cube: its front and back always, its sides where the picture has no neighbour (nb: +x, -x, up, down in the
# picture); slab 1 is turned a quarter round (its across is z)
static func _cube(t: SurfaceTool, o: Vector3, s: Vector3, c: Color, nb: Array, slab: int) -> void:
	var faces := []
	# across (the picture's x) is x for slab 0, z for slab 1; the cube's thin way is the other
	var ax := Vector3(s.x, 0, 0) if slab == 0 else Vector3(0, 0, s.x)
	var th := Vector3(0, 0, s.z) if slab == 0 else Vector3(-s.z, 0, 0)    # (so across x up is always the front's way out)
	var up := Vector3(0, s.y, 0)
	var a := o
	faces.append([a + th, a + th + ax, a + th + ax + up, a + th + up, 0.95])     # front
	faces.append([a + ax, a, a + up, a + ax + up, 0.8])                          # back
	if not nb[0]:
		faces.append([a + ax + th, a + ax, a + ax + up, a + ax + th + up, 0.85])
	if not nb[1]:
		faces.append([a, a + th, a + th + up, a + up, 0.85])
	if not nb[2]:
		faces.append([a + up + th, a + up + th + ax, a + up + ax, a + up, 1.0])
	if not nb[3]:
		faces.append([a, a + ax, a + ax + th, a + th, 0.6])
	for f in faces:
		var k: float = f[4]
		var col := Color(c.r * k, c.g * k, c.b * k)
		for i in [0, 2, 1, 0, 3, 2]:
			t.set_color(col)
			t.add_vertex(f[i])
