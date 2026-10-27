# (Copied from stkilda-godot scripts/town/town_trees.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkTownTrees
extends RefCounted
## The town's trees (data/town.json "trees", from tools/osm_to_town.gd: the map's own trees and rows of trees, the
## woods and orchards filled in, some dotted about the parks, and street trees along the suburban streets), in the
## voxel style of the workshop's gums: a pale trunk and clumps of grey-green leaves. Thousands of them, so
## they're drawn in batches (one per CHUNK-metre square of town, each one the same few boxes repeated), and a batch
## out past FAR isn't drawn at all.

const CHUNK := 160.0
const FAR := 520.0
const TRUNK := Color("#efe6d6")
const LEAF := Color("#84a664")

func build(town: SkTownBuilder) -> Node3D:
	var root := Node3D.new()
	root.name = "Trees"
	town.root.add_child(root)
	var t: Array = town.data.get("trees", [])
	if t.is_empty():
		return root
	var mesh := _tree_mesh()
	var chunks := {}
	for i in range(0, t.size() - 2, 3):
		var at := Vector2(t[i], t[i + 1])
		if town.in_lot(at):
			continue
		var key := Vector2i(floori(at.x / CHUNK), floori(at.y / CHUNK))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append([at, float(t[i + 2])])
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for k in list.size():
			var at: Vector2 = list[k][0]
			var size: float = list[k][1]
			var h := hash(at)
			var basis := Basis(Vector3.UP, float(h % 628) / 100.0).scaled(Vector3.ONE * size)
			mm.set_instance_transform(k, Transform3D(basis, Vector3(at.x, 0, at.y)))
			var v := 0.86 + float(h % 23) / 100.0             # each a little lighter or darker than the next
			mm.set_instance_color(k, Color(v, v * (0.97 + float(h % 7) / 100.0), v))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.visibility_range_end = FAR
		mi.visibility_range_end_margin = 30.0
		mi.material_override = SkModels.baked_material()
		root.add_child(mi)
	return root

## One tree, about 5.5 m tall: a trunk and clumps of leaves (each tree is then made a little lighter or darker).
static func _tree_mesh() -> ArrayMesh:
	var holder := Node3D.new()
	SkModels.box(holder, Vector3(0.36, 3.0, 0.36), Vector3(0, 1.5, 0), TRUNK)
	for c in [[Vector3(2.6, 1.5, 2.5), Vector3(0, 3.3, 0), 0.9], [Vector3(1.6, 1.3, 1.6), Vector3(0.95, 4.1, 0.5), 1.0],
			[Vector3(1.7, 1.2, 1.5), Vector3(-0.85, 4.3, -0.45), 0.95], [Vector3(1.3, 1.0, 1.3), Vector3(0.1, 5.0, -0.1), 1.0],
			[Vector3(1.2, 0.9, 1.1), Vector3(-0.3, 3.9, 1.0), 0.92]]:        # clumps of leaves, lighter on top
		SkModels.box(holder, c[0], c[1], LEAF.lightened(float(c[2]) - 0.9))
	var mesh := SkModels.bake(holder)
	holder.free()
	return mesh
