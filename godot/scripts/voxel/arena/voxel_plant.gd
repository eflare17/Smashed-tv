class_name VoxelPlant
extends Node3D
## A weed plant growing in the yard (Stage 5: "bring the weed growing mechanics across"), built in cubes from the HTML
## game's own plant art (assets/voxel/art/weed_sheet.png, its WEED_SHEET: six strains down, four stages across, 44 x
## 64 each): each picture's pixels become cubes, two of the pictures crossed through each other so it's a plant from
## every side. Dry it droops (squashed down, yellowed), wilted it goes brown (as the HTML game's weedArt), and a drop
## bobs over it asking for water; ready, its buds glint. It sways in the breeze. Meshes are made once per strain,
## stage and look, and shared. Owned by the voxel session.

const SHEET := "res://assets/voxel/art/weed_sheet.png"
const W := 44
const H := 64
const FOOT := Vector2(21.5, 60.0)   # the stem's foot in the picture
const VOX := 0.017                  # metres a pixel (a ready plant ~1 m tall)

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
static func _top(s: int, st: int, lk: int) -> float:
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
	return (FOOT.y - top) * VOX * squash

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
