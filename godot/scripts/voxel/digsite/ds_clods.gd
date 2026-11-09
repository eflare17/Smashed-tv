class_name DsClods
extends Node3D
## The lumps on the loose dirt (the owner, 9 Nov: "the dirt clips through the bucket and the blade ... really jumpy ...
## have a look at the web one"): the digger game's way. They were laid again from scratch every time a section was
## redrawn, so they shuffled about the heaps fifteen times a second, and big ones beside a blade poked through it. Now
## they're laid once, at fixed spots, in a 4 m patch per section column (CLODS_PER_M2, sizes like the digger game's),
## and their shader (shaders/ds_clod.gdshader) finds each one's height, how big it may be and its soil from the
## ground's gliding textures (DsTerrain: its top, how deep the loose dirt lies, how far the surface is still gliding),
## so dirt arriving brings lumps up out of it, scraping it away takes them with it, and moving ground turns them over.
## Near a machine's blade or bucket (each machine's keepout_boxes()) a lump's kept smaller than its distance from the
## steel, so none pokes through. Only patches with loose dirt on top are drawn; fewer far off. Owned by the voxel session.

const CLODS_PER_M2 := 40.0      # (the digger game's 28: a PC has room for more)
const KEEP_MOST := 8            # blade and bucket boxes the shader keeps lumps out of

var site: Node3D
var _patches: Array[MultiMeshInstance3D] = []
var _per := 0
var _loose := PackedInt32Array()

func setup(s: Node3D) -> void:
	site = s
	name = "Clods"
	var tr: DsTerrain = site.terrain
	var mat: ShaderMaterial = DsLook.clod_mat()
	var cols := PackedVector3Array()
	for c: Color in DsMats.COL:
		cols.append(Vector3(c.r, c.g, c.b))
	while cols.size() < 16:
		cols.append(Vector3(0.45, 0.25, 0.16))
	mat.set_shader_parameter("soil_cols", cols)
	var side_m := 32 * DsTerrain.CELL
	var nx := DsTerrain.W / 32
	var nz := DsTerrain.D / 32
	_per = int(CLODS_PER_M2 * side_m * side_m)
	var gr := RandomNumberGenerator.new()
	gr.seed = 29
	for pz in nz:
		for px in nx:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = DsLook.clod_mesh(px + pz * 2)
			mm.instance_count = _per
			for i in _per:
				# big enough to overlap and hide the ground under them, with some small ones to fill in
				var size := lerpf(0.07, 0.34, pow(gr.randf(), 1.7))
				var b := Basis(Vector3(gr.randf_range(-1.0, 1.0), gr.randf_range(-1.0, 1.0), gr.randf_range(-1.0, 1.0)).normalized(), gr.randf() * TAU)
				b = b * Basis.from_scale(Vector3(size * gr.randf_range(0.85, 1.35), size, size * gr.randf_range(0.8, 1.25)))
				mm.set_instance_transform(i, Transform3D(b, Vector3(gr.randf() * side_m, 0.0, gr.randf() * side_m)))
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			inst.material_override = mat
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			inst.position = tr.origin + Vector3(px * side_m, 0.0, pz * side_m)
			inst.custom_aabb = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(side_m + 2.0, DsTerrain.H * DsTerrain.CELL, side_m + 2.0))
			inst.visible = false
			mm.visible_instance_count = 0
			add_child(inst)
			_patches.append(inst)
	tr.loose_changed.connect(_on_loose)

func _on_loose(per: PackedInt32Array) -> void:
	_loose = per

func _process(_dt: float) -> void:
	if site == null or not site.get("active"):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	var side_m := 32 * DsTerrain.CELL
	for k in _patches.size():
		var inst := _patches[k]
		var any := k < _loose.size() and _loose[k] > 0
		var n := 0
		if any:
			var mid := inst.position + Vector3(side_m * 0.5, 0.0, side_m * 0.5)
			var d := Vector2(at.x - mid.x, at.z - mid.z).length()
			n = int(_per * (1.0 if d < 22.0 else (0.6 if d < 36.0 else 0.3)))
		if inst.multimesh.visible_instance_count != n:
			inst.multimesh.visible_instance_count = n
			inst.visible = n > 0
	# the blades and buckets near the camera, for the shader to keep lumps out of
	var rx := []
	var ry := []
	var rz := []
	var half := PackedVector3Array()
	if site.get("machines"):
		for m in site.machines.list:
			if rx.size() >= KEEP_MOST or not m.has_method("keepout_boxes") or m.global_position.distance_to(at) > 60.0:
				continue
			for box: Array in m.keepout_boxes():
				if rx.size() >= KEEP_MOST:
					break
				var inv: Transform3D = (box[0] as Transform3D).affine_inverse()
				rx.append(Vector4(inv.basis.x.x, inv.basis.y.x, inv.basis.z.x, inv.origin.x))
				ry.append(Vector4(inv.basis.x.y, inv.basis.y.y, inv.basis.z.y, inv.origin.y))
				rz.append(Vector4(inv.basis.x.z, inv.basis.y.z, inv.basis.z.z, inv.origin.z))
				half.append(box[1])
	var n_keep := rx.size()
	while rx.size() < KEEP_MOST:
		rx.append(Vector4.ZERO)
		ry.append(Vector4.ZERO)
		rz.append(Vector4.ZERO)
		half.append(Vector3.ZERO)
	var mat: ShaderMaterial = DsLook.clod_mat()
	mat.set_shader_parameter("keep_n", n_keep)
	mat.set_shader_parameter("keep_rx", rx)
	mat.set_shader_parameter("keep_ry", ry)
	mat.set_shader_parameter("keep_rz", rz)
	mat.set_shader_parameter("keep_half", half)
