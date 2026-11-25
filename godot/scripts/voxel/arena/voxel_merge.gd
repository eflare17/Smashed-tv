class_name VoxelMerge
extends RefCounted
## Static props drawn in fewer calls (the owner, 25 Nov: the browser game on a Galaxy S25 "was a bit laggy"). The
## house and the yard are built of little boxes, each its own MeshInstance3D with its own plain colour, and the
## Compatibility renderer the browser uses draws every one of them on its own: stood in the arena looking at the house
## that was 491 draw calls for a hundred thousand triangles, nearly all of it overhead.
##
## bake(node) takes the MeshInstance3Ds that are direct children of `node` -- the parts that never move; anything that
## swings or spins hangs off a node of its own, so it's left alone -- and joins the plainly coloured ones into one mesh
## for each (roughness, metallic) pair, each box's colour carried in the mesh's vertex colours. Nothing is thrown away:
## the originals are only hidden, so whatever built them can still hold and read them.
##
## It leaves alone anything it can't reproduce exactly: a textured, glowing, see-through or shader material, a mesh
## with more than one surface, a node with children of its own. And it does nothing to a group of one. Owned by the
## voxel phone-performance session.

## Returns the draw calls saved.
static func bake(node: Node3D) -> int:
	var groups := {}
	for c in node.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null or mi.get_child_count() > 0:
			continue
		if mi.mesh.get_surface_count() != 1 or mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] == null:
			continue
		var m := mi.material_override as StandardMaterial3D
		if not _plain(m) or mi.get_surface_override_material_count() > 0 and mi.get_surface_override_material(0) != null:
			continue
		var key := "%.4f|%.4f|%d|%d" % [m.roughness, m.metallic, int(m.cull_mode), int(m.shading_mode)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	var saved := 0
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		saved += list.size() - 1
		_join(node, list)
	return saved

## A material whose look one shared vertex-coloured material can reproduce exactly.
static func _plain(m: StandardMaterial3D) -> bool:
	return m != null and m.albedo_texture == null and m.normal_enabled == false and m.roughness_texture == null \
		and m.metallic_texture == null and m.emission_enabled == false and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
		and m.vertex_color_use_as_albedo == false and m.albedo_color.a >= 0.999 and m.rim_enabled == false \
		and m.clearcoat_enabled == false and m.refraction_enabled == false and m.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED

static func _join(node: Node3D, list: Array) -> void:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var col := PackedColorArray()
	for mi: MeshInstance3D in list:
		var a := mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var xf := mi.transform             # (a direct child: this is already where it sits in `node`)
		var c: Color = (mi.material_override as StandardMaterial3D).albedo_color
		if idx.is_empty():
			idx = PackedInt32Array(range(vs.size()))
		for i in idx:
			v.append(xf * vs[i])
			n.append((xf.basis * ns[i]).normalized())
			col.append(c)
		mi.visible = false
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = col
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var first := list[0].material_override as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.roughness = first.roughness
	m.metallic = first.metallic
	m.cull_mode = first.cull_mode
	m.shading_mode = first.shading_mode
	m.vertex_color_use_as_albedo = true
	# (not vertex_color_is_srgb: albedo_color goes to the shader as it is, so the colours taken from it must too)
	var mi := MeshInstance3D.new()
	mi.name = "Baked"
	mi.mesh = am
	mi.material_override = m
	mi.cast_shadow = (list[0] as MeshInstance3D).cast_shadow
	node.add_child(mi)
