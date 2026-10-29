# (Copied from stkilda-godot scripts/town/town_trees.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkTownTrees
extends RefCounted
## The town's trees (data/town.json "trees", from tools/osm_to_town.gd: the map's own trees and rows of trees, the
## woods and orchards filled in, some dotted about the parks, and street trees along the suburban streets), in the
## voxel style of the workshop's gums: a pale trunk and clumps of grey-green leaves, in three shapes so they don't
## all match. Where St Kilda really has palms they're Canary Island date palms (Phoenix canariensis): the avenues of
## them in Catani Gardens, and along the foreshore roads (Jacka Boulevard, Beaconsfield Parade) and The Esplanade
## (planted 1979-80; the Victorian Heritage Database, Port Phillip council, Victorian Collections). Thousands of trees,
## so they're drawn in batches (one per CHUNK-metre square of town, each kind one shape repeated), and a batch out
## past FAR isn't drawn at all. Their tops sway a little in the breeze (a shader: each tree a little out of step).

const CHUNK := 160.0
const FAR := 520.0
const TRUNK := Color("#efe6d6")
const LEAF := Color("#84a664")
const PALM_TRUNK := Color("#8a7a66")
const FROND := Color("#5f8f3e")
const PALM_ROADS := ["Jacka Boulevard", "Beaconsfield Parade", "The Esplanade"]
const PALM_NEAR := 14.0                  # m from those roads' middles: a palm
const PALM_PARKS := ["Catani Gardens"]

static var _mat: ShaderMaterial

func build(town: SkTownBuilder) -> Node3D:
	var root := Node3D.new()
	root.name = "Trees"
	town.root.add_child(root)
	var t: Array = town.data.get("trees", [])
	if t.is_empty():
		return root
	var meshes := [_tree_mesh(0), _tree_mesh(1), _tree_mesh(2), _palm_mesh()]
	var palm_lines := []
	for r in town.data.roads:
		if r.n in PALM_ROADS:
			palm_lines.append(SkTownBuilder._pts(r.p))
	var palm_parks := []
	for p in town.data.parks:
		if p.get("n", "") in PALM_PARKS:
			palm_parks.append(SkTownBuilder._pts(p.p))
	var chunks := {}
	for i in range(0, t.size() - 2, 3):
		var at := Vector2(t[i], t[i + 1])
		if town.in_lot(at):
			continue
		var kind := absi(hash(at)) % 3
		if _palm_spot(at, palm_lines, palm_parks):
			kind = 3
		var key := Vector3i(floori(at.x / CHUNK), floori(at.y / CHUNK), kind)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append([at, float(t[i + 2])])
	for key in chunks:
		var list: Array = chunks[key]
		var palm: bool = key.z == 3
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[key.z]
		mm.instance_count = list.size()
		for k in list.size():
			var at: Vector2 = list[k][0]
			var size: float = list[k][1]
			if palm:
				size = clampf(size, 0.85, 1.15)          # (palms come about the same size)
			var h := hash(at)
			var basis := Basis(Vector3.UP, float(h % 628) / 100.0).scaled(Vector3.ONE * size)
			mm.set_instance_transform(k, Transform3D(basis, Vector3(at.x, 0, at.y)))
			var v := 0.86 + float(h % 23) / 100.0             # each a little lighter or darker than the next
			mm.set_instance_color(k, Color(v, v * (0.97 + float(h % 7) / 100.0), v))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.visibility_range_end = FAR
		mi.visibility_range_end_margin = 30.0
		mi.material_override = sway_material()
		root.add_child(mi)
		# a soft shadow under each (SkContactShade), drawn and left out with them
		var under := []
		for k in list.size():
			under.append([(list[k][0] as Vector2).x, (list[k][0] as Vector2).y, (1.6 if palm else 2.3) * float(list[k][1]), 0.34])
		var shade := SkContactShade.blobs(under, "Shade")
		shade.visibility_range_end = FAR
		shade.visibility_range_end_margin = 30.0
		root.add_child(shade)
	return root

static func _palm_spot(at: Vector2, lines: Array, parks: Array) -> bool:
	for ring in parks:
		if Geometry2D.is_point_in_polygon(at, ring):
			return true
	for line in lines:
		var p: PackedVector2Array = line
		for i in p.size() - 1:
			if Geometry2D.get_closest_point_to_segment(at, p[i], p[i + 1]).distance_to(at) < PALM_NEAR:
				return true
	return false

## One tree, about 5.5 m tall: a trunk and clumps of leaves (each tree is then made a little lighter or darker). Three
## shapes: the spreading one, a taller narrower one, a low wide one.
static func _tree_mesh(shape: int) -> ArrayMesh:
	var holder := Node3D.new()
	var clumps := [[Vector3(2.6, 1.5, 2.5), Vector3(0, 3.3, 0), 0.9], [Vector3(1.6, 1.3, 1.6), Vector3(0.95, 4.1, 0.5), 1.0],
			[Vector3(1.7, 1.2, 1.5), Vector3(-0.85, 4.3, -0.45), 0.95], [Vector3(1.3, 1.0, 1.3), Vector3(0.1, 5.0, -0.1), 1.0],
			[Vector3(1.2, 0.9, 1.1), Vector3(-0.3, 3.9, 1.0), 0.92]]        # clumps of leaves, lighter on top
	var trunk := 3.0
	if shape == 1:
		trunk = 3.6
		clumps = [[Vector3(1.9, 1.8, 1.9), Vector3(0, 3.8, 0), 0.9], [Vector3(1.5, 1.6, 1.4), Vector3(0.3, 5.1, 0.2), 0.95],
			[Vector3(1.1, 1.3, 1.1), Vector3(-0.2, 6.2, -0.1), 1.0], [Vector3(1.2, 1.0, 1.0), Vector3(-0.7, 4.6, 0.6), 0.92]]
	elif shape == 2:
		trunk = 2.4
		clumps = [[Vector3(3.4, 1.3, 3.0), Vector3(0, 2.9, 0), 0.9], [Vector3(2.0, 1.1, 1.8), Vector3(1.1, 3.6, -0.4), 0.97],
			[Vector3(1.9, 1.0, 2.0), Vector3(-1.0, 3.7, 0.5), 0.95], [Vector3(1.4, 0.8, 1.4), Vector3(0.2, 4.2, 0.2), 1.0]]
	SkModels.box(holder, Vector3(0.36, trunk, 0.36), Vector3(0, trunk / 2.0, 0), TRUNK)
	for c in clumps:
		SkModels.box(holder, c[0], c[1], LEAF.lightened(float(c[2]) - 0.9))
	var mesh := SkModels.bake(holder)
	holder.free()
	return mesh

## A Canary Island date palm, about 10 m: a thick straight trunk in rings, a fat knob where the fronds start, and a
## crown of long fronds arching out and drooping at the tips, with a few dead brown ones hanging under. (Kept to a few
## pieces: there are hundreds of them.)
static func _palm_mesh() -> ArrayMesh:
	var holder := Node3D.new()
	var top := 8.6
	var rings := 5
	for k in rings:
		var y := top * k / rings
		var w := 0.78 - 0.1 * float(k) / rings
		SkModels.box(holder, Vector3(w, top / rings + 0.02, w), Vector3(0, y + top / rings / 2.0, 0), PALM_TRUNK.darkened(0.08 * (k % 2)))
	SkModels.box(holder, Vector3(1.0, 0.9, 1.0), Vector3(0, top + 0.35, 0), PALM_TRUNK.lightened(0.1))
	for f in 8:
		var ang := TAU * f / 8.0 + (0.2 if f % 2 else 0.0)
		var d := Vector3(cos(ang), 0, sin(ang))
		var rise := 0.35 if f % 2 == 0 else 0.15
		# each frond: three pieces, out and up, out, then out and down
		var a := Vector3(0, top + 0.6, 0)
		for seg in 2:
			var drop: float = [rise, -0.9][seg]
			var b: Vector3 = a + d * 2.1 + Vector3(0, drop, 0)
			var piece := SkModels.box(holder, Vector3(0.55 - seg * 0.15, 0.08, 2.25), (a + b) / 2.0, FROND.lightened(0.05 * seg))
			piece.basis = Basis.looking_at(b - a, Vector3.UP)
			a = b
	for f in 3:
		var ang := TAU * f / 3.0 + 0.4
		var d := Vector3(cos(ang), 0, sin(ang))
		var piece := SkModels.box(holder, Vector3(0.12, 1.6, 0.35), Vector3(0, top - 0.3, 0) + d * 0.6, Color("#8a6a3e"))
		piece.rotation = Vector3(d.z * 0.35, 0, -d.x * 0.35)
	var mesh := SkModels.bake(holder)
	holder.free()
	return mesh

## The trees' material: their own colours (and each tree's lighter or darker), the tops swaying a little, more the
## higher up, each tree out of step with the next.
static func sway_material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_back;
void vertex() {
	vec3 at = MODEL_MATRIX[3].xyz;
	float up = max(0.0, VERTEX.y - 2.4);
	float phase = at.x * 0.11 + at.z * 0.07;
	float sway = sin(TIME * 1.1 + phase) * 0.6 + sin(TIME * 2.3 + phase * 1.7) * 0.25;
	VERTEX.x += up * up * 0.0035 * sway;
	VERTEX.z += up * up * 0.0025 * sin(TIME * 0.9 + phase * 1.3);
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
}
"""
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat
