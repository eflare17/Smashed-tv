# (Copied from stkilda-godot scripts/world/models.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkModels
extends RefCounted
## Low-poly and voxel building blocks shared by the workshop, the vehicles and the people. Everything faces -z
## (Godot's forward): a car's bonnet and a person's face point that way.

static var _mats: Dictionary = {}

static func mat(c: Color, rough: float = 0.85) -> StandardMaterial3D:
	var k := c.to_html() + str(rough)
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[k] = m
	return m

static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rough: float = 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat(c, rough)
	parent.add_child(mi)
	return mi

## A cylinder lying on its side across x (a wheel), or standing (axis_up).
static func cyl(parent: Node3D, radius: float, length: float, pos: Vector3, c: Color, axis_up: bool = false, sides: int = 14) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	if not axis_up:
		mi.rotation.z = PI / 2.0
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi

static func ball(parent: Node3D, radius: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi

## A wheel: a tyre with a hub, spinning about x. Returns the node to spin.
static func wheel(parent: Node3D, radius: float, width: float, pos: Vector3, hub: Color) -> Node3D:
	var w := Node3D.new()
	w.position = pos
	parent.add_child(w)
	cyl(w, radius, width, Vector3.ZERO, Color("#22232b"))
	cyl(w, radius * 0.55, width + 0.02, Vector3.ZERO, hub)
	# a tread block so you can see it turn
	box(w, Vector3(width + 0.03, radius * 0.25, radius * 0.25), Vector3(0, radius * 0.8, 0), Color("#3a3b44"))
	return w

## A gum tree: a trunk and a few clumps of leaves.
static func tree(seed_v: int) -> Node3D:
	var t := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var h := rng.randf_range(4.0, 6.5)
	cyl(t, 0.22, h, Vector3(0, h / 2.0, 0), Color("#7a4a2a"), true, 8)
	var greens := [SkData.C_GRASS, SkData.C_GRASS_DARK, Color("#2c8a4c")]
	for i in 4:
		var r := rng.randf_range(1.2, 1.9)
		ball(t, r, Vector3(rng.randf_range(-1.0, 1.0), h + rng.randf_range(-0.6, 0.8), rng.randf_range(-1.0, 1.0)), greens[i % 3])
	return t

const VOX := 0.1

class Vox:
	var cells: Dictionary = {}           # Vector3i -> Color
	func put(p: Vector3i, c: Color) -> void:
		cells[p] = c
	func fill(a: Vector3i, b: Vector3i, c: Color, jitter: float = 0.0) -> void:
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
				for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
					cells[Vector3i(x, y, z)] = SkModels._shade(c, x, y, z, jitter)
	## both sides: x and -x
	func fill2(a: Vector3i, b: Vector3i, c: Color, jitter: float = 0.0) -> void:
		fill(a, b, c, jitter)
		fill(Vector3i(-a.x, a.y, a.z), Vector3i(-b.x, b.y, b.z), c, jitter)

static func _shade(c: Color, x: int, y: int, z: int, j: float) -> Color:
	if j <= 0.0:
		return c
	var h := absi((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) % 3
	return c.darkened(j) if h == 0 else (c.lightened(j * 0.6) if h == 1 else c)

static func _voxels(name: String, v: Vox, size: float = VOX) -> MultiMeshInstance3D:
	# only the voxels with an open face (the inside is never seen)
	var keep: Array = []
	var nb := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for p in v.cells:
		for d in nb:
			if not v.cells.has(p + d):
				keep.append(p)
				break
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	mm.mesh = bm
	mm.instance_count = keep.size()
	for i in keep.size():
		var p: Vector3i = keep[i]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, p.y + 0.5, p.z) * size))
		mm.set_instance_color(i, v.cells[p])
	var mi := MultiMeshInstance3D.new()
	mi.name = name
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	mi.material_override = m
	return mi


## Merge every MeshInstance3D under root (not root's MultiMeshes or labels) into one mesh, each part keeping its
## colour as a vertex colour. Draw it with baked_material().
static func bake(root: Node3D) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for mi in _mesh_instances(root, []):
		var m: Mesh = mi.mesh
		var xf := _rel(mi, root)
		var col := Color.WHITE
		if mi.material_override is StandardMaterial3D:
			col = (mi.material_override as StandardMaterial3D).albedo_color
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var base := verts.size()
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in v.size():
				verts.append(xf * v[i])
				norms.append((xf.basis * n[i]).normalized())
				cols.append(col)
			var ia = a[Mesh.ARRAY_INDEX]
			if ia == null or (ia as PackedInt32Array).is_empty():
				for i in v.size():
					idx.append(base + i)
			else:
				for i in (ia as PackedInt32Array):
					idx.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	if not verts.is_empty():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out

static var _baked_mat: StandardMaterial3D
static func baked_material() -> StandardMaterial3D:
	if _baked_mat == null:
		_baked_mat = StandardMaterial3D.new()
		_baked_mat.vertex_color_use_as_albedo = true
		_baked_mat.vertex_color_is_srgb = true
		_baked_mat.roughness = 0.8
	return _baked_mat

## Remove the MeshInstance3Ds bake() took (their collision bodies and labels stay).
static func free_meshes(root: Node3D) -> void:
	for mi in _mesh_instances(root, []):
		mi.get_parent().remove_child(mi)
		mi.free()

static func _mesh_instances(n: Node, out: Array) -> Array:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			out.append(c)
		_mesh_instances(c, out)
	return out

## n's transform relative to root (works before they're in the scene tree).
static func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

## A head in 5 cm voxels, its bottom at y = 0, facing -z: 11 wide, 13 high, 10 deep, with a cartoon face
## (white eyes with dark pupils, brows, a nose that sticks out, a mouth, rosy cheeks, ears) and each kind's hair.
static func _head(kind: String, hair: Color) -> Vox:
	var v := Vox.new()
	var skin := Color("#dba07f")         # a touch deep: the golden-hour light bleaches paler skin out
	var skin_dk := Color("#b97d5e")
	var ink := SkData.C_INK
	var white := Color("#f7f4ee")
	var lips := Color("#9a4442")
	var brow := hair.darkened(0.35)
	const F := -5                        # the front face
	# skull and ears
	v.fill(Vector3i(-5, 0, F), Vector3i(5, 12, 4), skin)
	v.fill(Vector3i(-4, 0, F), Vector3i(4, 0, 3), skin_dk)                    # under the chin
	v.fill2(Vector3i(6, 5, -1), Vector3i(6, 7, 0), skin_dk)                   # ears
	# eyes: white with the pupil on the inside, brows over them
	v.fill2(Vector3i(3, 6, F), Vector3i(3, 7, F), white)
	v.fill2(Vector3i(2, 6, F), Vector3i(2, 7, F), ink)
	v.fill2(Vector3i(2, 7, F), Vector3i(2, 7, F), Color("#6b3f22"))           # brown eyes
	v.fill2(Vector3i(2, 9, F), Vector3i(4, 9, F), brow)
	# nose: sticks out a voxel, with a shadow under it
	v.fill(Vector3i(0, 4, F - 1), Vector3i(0, 5, F - 1), skin_dk)
	v.put(Vector3i(0, 3, F), skin_dk.darkened(0.15))
	# mouth, a small smile, and rosy cheeks
	v.fill(Vector3i(-1, 2, F), Vector3i(1, 2, F), lips)
	v.fill2(Vector3i(2, 3, F), Vector3i(2, 3, F), lips)
	v.fill2(Vector3i(4, 4, F), Vector3i(4, 4, F), skin.lerp(Color("#e5484d"), 0.3))
	match kind:
		"jaymie":
			v.fill2(Vector3i(2, 8, F), Vector3i(4, 8, F), ink)                        # lashes
			# dirty-blonde hair pulled back into a high ponytail: lighter streaks, loose strands by her face,
			# a mint stud in each ear
			var hi := hair.lightened(0.18)
			v.fill(Vector3i(-6, 10, -6), Vector3i(6, 13, 5), hair, 0.12)
			v.fill(Vector3i(-5, 14, -4), Vector3i(5, 14, 4), hair, 0.1)
			for x in range(-5, 6, 3):
				v.fill(Vector3i(x, 13, -6), Vector3i(x, 14, 4), hi)                   # combed-back streaks
			v.fill(Vector3i(-5, 10, F - 1), Vector3i(-1, 11, F - 1), hair, 0.12)      # swept fringe
			v.fill2(Vector3i(6, 3, -4), Vector3i(6, 10, 4), hair, 0.12)
			v.fill2(Vector3i(5, 1, -6), Vector3i(5, 9, -6), hi)                       # loose strands
			v.fill(Vector3i(-5, 2, 5), Vector3i(5, 10, 6), hair, 0.12)
			v.fill(Vector3i(-2, 12, 7), Vector3i(2, 15, 8), hair.darkened(0.25))      # hair tie
			v.fill(Vector3i(-3, 13, 9), Vector3i(3, 17, 11), hair, 0.12)              # the ponytail, up then down her back
			v.fill(Vector3i(-2, 2, 11), Vector3i(2, 14, 13), hair, 0.14)
			v.fill(Vector3i(-1, 2, 11), Vector3i(-1, 14, 11), hi)
			v.fill(Vector3i(-1, -7, 11), Vector3i(1, 1, 12), hair, 0.14)
			v.fill(Vector3i(0, -9, 11), Vector3i(0, -8, 11), hair.darkened(0.1))
			v.fill2(Vector3i(7, 4, -1), Vector3i(7, 4, -1), SkData.C_MINT)          # earrings
		"chloe":
			v.fill2(Vector3i(2, 8, F), Vector3i(4, 8, F), ink)                        # lashes
			# glasses: black rectangular frames round each eye, a bridge, arms back to the ears
			var fr := Color("#121216")
			for sx in [-1, 1]:
				v.fill(Vector3i(sx * 1, 5, F - 1), Vector3i(sx * 5, 5, F - 1), fr)
				v.fill(Vector3i(sx * 1, 9, F - 1), Vector3i(sx * 5, 9, F - 1), fr)
				v.fill(Vector3i(sx * 1, 5, F - 1), Vector3i(sx * 1, 9, F - 1), fr)
				v.fill(Vector3i(sx * 5, 5, F - 1), Vector3i(sx * 5, 9, F - 1), fr)
				v.fill(Vector3i(sx * 6, 8, F), Vector3i(sx * 6, 8, 0), fr)
			v.fill(Vector3i(-1, 8, F - 1), Vector3i(1, 8, F - 1), fr)
			# long straight blonde hair, a centre part with darker roots, down past her shoulders
			var roots := hair.darkened(0.3)
			var hi := hair.lightened(0.12)
			v.fill(Vector3i(-6, 10, -6), Vector3i(6, 13, 5), hair, 0.08)
			v.fill(Vector3i(-5, 14, -5), Vector3i(5, 14, 4), roots, 0.06)
			v.fill(Vector3i(-6, 13, -6), Vector3i(6, 13, -6), roots)
			v.fill(Vector3i(0, 13, -6), Vector3i(0, 14, 5), roots.darkened(0.2))          # the part
			v.fill2(Vector3i(5, -4, -6), Vector3i(6, 12, -4), hair, 0.08)               # hanging either side of her face
			v.fill2(Vector3i(6, -3, -3), Vector3i(7, 12, 5), hair, 0.08)
			v.fill(Vector3i(-6, -5, 5), Vector3i(6, 13, 7), hair, 0.08)                # down to her shoulder blades
			for x in range(-5, 6, 3):
				v.fill(Vector3i(x, -5, 7), Vector3i(x, 9, 7), hi)                       # straight lighter strands
			v.fill2(Vector3i(5, 0, -6), Vector3i(5, 10, -6), hi)
		"maddie":
			v.fill2(Vector3i(2, 8, F), Vector3i(4, 8, F), ink)                        # lashes
			# Maddie (from Where's Shane, copied from her sprite there): thick wavy brown hair, a side fringe swept
			# across her forehead, full at the sides and down past her shoulders, with lighter waves through it
			var hi := hair.lightened(0.16)
			var dk := hair.darkened(0.2)
			v.fill(Vector3i(-6, 10, -6), Vector3i(6, 14, 5), hair, 0.15)
			v.fill(Vector3i(-5, 15, -4), Vector3i(4, 15, 3), hair, 0.15)
			v.fill(Vector3i(-5, 10, F - 1), Vector3i(1, 11, F - 1), hair, 0.15)      # the side fringe
			v.fill(Vector3i(-5, 9, F - 1), Vector3i(-3, 9, F - 1), hair, 0.15)
			v.fill2(Vector3i(5, -6, -6), Vector3i(6, 12, -4), hair, 0.15)            # framing her face
			v.fill2(Vector3i(6, -6, -3), Vector3i(7, 12, 5), hair, 0.15)             # full at the sides
			v.fill(Vector3i(-7, -7, 5), Vector3i(7, 13, 7), hair, 0.15)              # down past her shoulders
			# the waves: the ends kinking out and back down the sides and the back, lighter on the outside
			var k := 0
			for y in range(-7, 12, 3):
				v.fill2(Vector3i(8 if k % 2 == 0 else 7, y, -2), Vector3i(8 if k % 2 == 0 else 7, y + 1, 4), hi)
				v.fill(Vector3i(-6, y, 8), Vector3i(6, y + 1, 8), hi if k % 2 == 0 else dk)
				k += 1
			v.fill(Vector3i(-1, 12, -6), Vector3i(3, 13, -6), hi)                    # a highlight on top
		"fletcher":
			# Fletcher (the owner's photos): short dirty-blond hair, lighter on top, a fringe swept across to his left,
			# short at the sides and back; blue eyes; green mirrored sunnies (black frames)
			v.fill2(Vector3i(2, 7, F), Vector3i(2, 7, F), Color("#5b8bbd"))           # blue eyes (under the sunnies)
			var hi := hair.lightened(0.2)
			v.fill(Vector3i(-6, 11, -6), Vector3i(6, 13, 5), hair, 0.1)
			v.fill(Vector3i(-5, 14, -5), Vector3i(5, 14, 4), hi, 0.08)              # lighter on top
			v.fill(Vector3i(-5, 13, -6), Vector3i(3, 13, -6), hi)
			v.fill(Vector3i(-6, 10, F - 1), Vector3i(2, 11, F - 1), hair, 0.1)     # the fringe, swept to his left
			v.fill(Vector3i(-6, 9, F - 1), Vector3i(-3, 9, F - 1), hair, 0.1)
			v.fill2(Vector3i(6, 7, -4), Vector3i(6, 10, 4), hair.darkened(0.08), 0.08)   # short sides
			v.fill(Vector3i(-5, 5, 5), Vector3i(5, 10, 5), hair.darkened(0.08), 0.08)    # short at the back
			var fr := Color("#18181c")
			var lens := Color("#2a9c8e")
			for sx in [-1, 1]:
				v.fill(Vector3i(sx * 1, 6, F - 1), Vector3i(sx * 5, 8, F - 1), lens)
				v.put(Vector3i(sx * 4, 8, F - 1), lens.lightened(0.45))              # the mirror's glint
				v.put(Vector3i(sx * 2, 6, F - 1), lens.darkened(0.3))
				v.fill(Vector3i(sx * 1, 9, F - 1), Vector3i(sx * 5, 9, F - 1), fr)
				v.fill(Vector3i(sx * 6, 8, F - 1), Vector3i(sx * 6, 9, 0), fr)       # the arms back to his ears
			v.fill(Vector3i(-1, 8, F - 1), Vector3i(1, 8, F - 1), fr)
		"sam":
			# a long curly brown mullet: messy curls on top, a parted fringe, long down the sides and past his
			# shoulders at the back; a short beard and a grin
			var dk_hair := hair.darkened(0.25)
			v.fill(Vector3i(-6, 10, -6), Vector3i(6, 14, 5), hair, 0.2)
			v.fill(Vector3i(-5, 9, F - 1), Vector3i(-1, 10, F - 1), hair, 0.2)
			v.fill(Vector3i(2, 9, F - 1), Vector3i(5, 10, F - 1), hair, 0.2)
			v.fill2(Vector3i(6, -5, -4), Vector3i(7, 10, 5), hair, 0.2)
			v.fill(Vector3i(-6, -8, 5), Vector3i(6, 13, 7), hair, 0.2)
			# swept back off his face, waves through the lengths (after reference/jaymie_sam_piggyback.webp)
			for x in range(-5, 6, 2):
				v.fill(Vector3i(x, 14, -5), Vector3i(x, 14, 4), hair.lightened(0.1))
			var tufts := [Vector3i(-7, 12, 0), Vector3i(7, 12, -2),
				Vector3i(-8, 2, 2), Vector3i(8, 4, 1), Vector3i(-8, -3, 3), Vector3i(8, -2, 4),
				Vector3i(-5, -9, 6), Vector3i(-1, -10, 6), Vector3i(3, -9, 6), Vector3i(6, -7, 6),
				Vector3i(-7, -9, 6), Vector3i(7, -6, 6), Vector3i(-3, 14, 6), Vector3i(4, 14, 6)]
			for p in tufts:
				v.put(p, hair.lightened(0.08))
				v.put(p + Vector3i(0, -1, 0), dk_hair)
			# the beard: jaw, chin, cheeks, a moustache, the teeth of a grin
			var beard := dk_hair
			v.fill(Vector3i(-5, -1, F), Vector3i(5, 3, F), beard, 0.12)
			v.fill2(Vector3i(5, -1, -4), Vector3i(5, 6, 1), beard, 0.12)
			v.fill2(Vector3i(4, 4, F), Vector3i(4, 5, F), beard, 0.12)
			v.fill(Vector3i(-4, -1, F - 1), Vector3i(4, 0, F - 1), beard, 0.12)
			v.fill(Vector3i(-4, -1, -4), Vector3i(4, -1, 3), beard, 0.1)
			v.fill(Vector3i(-2, 3, F), Vector3i(2, 3, F), beard.darkened(0.1))
			v.fill(Vector3i(-2, 2, F), Vector3i(2, 2, F), Color("#6a3330"))           # a flat, deadpan mouth
			v.fill2(Vector3i(2, 9, F), Vector3i(4, 9, F), dk_hair.darkened(0.2))      # heavy brows
			v.fill2(Vector3i(3, 10, F), Vector3i(4, 10, F), dk_hair.darkened(0.2))
		"kev", "kev_happy":
			# Kev (reference/people/kev.webp): short ginger hair, clippered at the sides and a bit longer on top, a short
			# full ginger beard and moustache; a friendly smile (the photo's a silly face, so not that). "kev_happy" is him
			# over the moon (the coaster video): a huge open grin, eyes squeezed shut into happy crescents, brows up
			var dk := hair.darkened(0.18)
			v.fill(Vector3i(-6, 11, -6), Vector3i(6, 13, 5), hair, 0.1)
			v.fill(Vector3i(-5, 14, -5), Vector3i(5, 15, 4), hair, 0.1)             # longer on top
			v.fill(Vector3i(-4, 14, -6), Vector3i(3, 15, -6), hair.lightened(0.08))   # swept up at the front
			v.fill2(Vector3i(6, 7, -4), Vector3i(6, 10, 4), dk, 0.08)                 # short sides
			v.fill(Vector3i(-5, 6, 5), Vector3i(5, 10, 5), dk, 0.08)                  # short at the back
			var beard := hair.darkened(0.08)
			v.fill(Vector3i(-5, -1, F), Vector3i(5, 1, F), beard, 0.1)               # chin and jaw
			v.fill2(Vector3i(5, -1, -4), Vector3i(5, 6, 0), beard, 0.1)              # up the cheeks to the sideburns
			v.fill2(Vector3i(3, 3, F), Vector3i(4, 4, F), beard, 0.1)
			v.fill(Vector3i(-4, -1, F - 1), Vector3i(4, 0, F - 1), beard, 0.1)
			v.fill(Vector3i(-4, -1, -4), Vector3i(4, -1, 3), beard, 0.08)
			v.fill(Vector3i(-2, 3, F), Vector3i(2, 3, F), beard)                      # moustache
			if kind == "kev_happy":
				# eyes shut tight in a grin: an upturned arc each side instead of open eyes
				v.fill2(Vector3i(2, 6, F), Vector3i(4, 9, F), skin)
				v.fill2(Vector3i(1, 6, F), Vector3i(1, 6, F), ink)
				v.fill2(Vector3i(2, 7, F), Vector3i(2, 7, F), ink)
				v.fill2(Vector3i(3, 7, F), Vector3i(3, 8, F), ink)
				v.fill2(Vector3i(4, 7, F), Vector3i(4, 7, F), ink)
				v.fill2(Vector3i(5, 6, F), Vector3i(5, 6, F), ink)
				v.fill2(Vector3i(2, 10, F), Vector3i(4, 10, F), hair.darkened(0.3))   # brows right up
				# the grin: wide open, top teeth, a dark mouth, the tongue, the corners turned right up into the beard
				v.fill(Vector3i(-3, 2, F), Vector3i(3, 2, F), Color("#f7f2e8"))
				v.fill(Vector3i(-3, 1, F), Vector3i(3, 1, F), Color("#4a1414"))
				v.fill(Vector3i(-2, 0, F), Vector3i(2, 0, F), Color("#4a1414"))
				v.fill(Vector3i(-1, 0, F), Vector3i(1, 0, F), Color("#d9555a"))
				v.fill2(Vector3i(4, 3, F), Vector3i(4, 3, F), Color("#4a1414"))
				v.fill2(Vector3i(4, 5, F), Vector3i(5, 5, F), skin.lerp(Color("#e5484d"), 0.45))   # rosy cheeks
			else:
				v.fill(Vector3i(-2, 2, F), Vector3i(2, 2, F), Color("#f2ece2"))       # a smile, teeth showing
				v.fill2(Vector3i(3, 2, F), Vector3i(3, 2, F), lips)
				v.fill2(Vector3i(2, 9, F), Vector3i(4, 9, F), hair.darkened(0.3))     # ginger brows
		"tow":
			# a hi-vis orange cap, short hair under it
			v.fill(Vector3i(-6, 11, -5), Vector3i(6, 14, 5), SkData.C_ORANGE)
			v.fill(Vector3i(-5, 11, -9), Vector3i(5, 11, -6), SkData.C_ORANGE_DARK)
			v.fill2(Vector3i(5, 6, -2), Vector3i(6, 10, 4), hair)
			v.fill(Vector3i(-5, 4, 4), Vector3i(5, 10, 5), hair)
		_:
			# short hair: on top, a fringe, sideburns, down the back
			v.fill(Vector3i(-6, 11, -6), Vector3i(6, 14, 5), hair, 0.12)
			v.fill(Vector3i(-5, 10, F - 1), Vector3i(3, 10, F - 1), hair, 0.12)
			v.fill2(Vector3i(6, 6, -4), Vector3i(6, 10, 4), hair, 0.12)
			v.fill(Vector3i(-5, 4, 5), Vector3i(5, 10, 5), hair, 0.12)
	return v

## A wheel's pivot at its hub (voxel units), with the voxels in a "Spin" child that turns about x. shift moves the
## voxels inside the pivot (a front wheel steers about a point nearer its middle).
static func _wheel_node(name: String, v: Vox, hub: Vector3, shift: Vector3 = Vector3.ZERO) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = name
	pivot.position = Vector3(hub.x, hub.y + 0.5, hub.z) * VOX
	var spin := Node3D.new()
	spin.name = "Spin"
	pivot.add_child(spin)
	var mi := _voxels("Voxels", v)
	mi.position = Vector3(shift.x, -0.5, shift.z) * VOX
	spin.add_child(mi)
	return pivot
