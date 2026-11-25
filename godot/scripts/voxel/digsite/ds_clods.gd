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
var _per = 0
var _loose = PackedInt32Array()

func setup(s: Node3D) -> void:
	site = s
	name = "Clods"
	var tr: DsTerrain = site.terrain
	var mat: ShaderMaterial = DsLook.clod_mat()
	var cols = PackedVector3Array()
	for c: Color in DsMats.COL:
		cols.append(Vector3(c.r, c.g, c.b))
	while cols.size() < 16:
		cols.append(Vector3(0.45, 0.25, 0.16))
	mat.set_shader_parameter("soil_cols", cols)
	var side_m = 32 * DsTerrain.CELL
	var nx = DsTerrain.W / 32
	var nz = DsTerrain.D / 32
	_per = int(CLODS_PER_M2 * side_m * side_m)
	var gr = RandomNumberGenerator.new()
	gr.seed = 29
	for pz in nz:
		for px in nx:
			var mm = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = DsLook.clod_mesh(px + pz * 2)
			mm.instance_count = _per
			for i in _per:
				mm.set_instance_transform(i, _one(gr, side_m))
			var inst = MultiMeshInstance3D.new()
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

# a lump's place in its patch, its size and how it's turned, from the generator (the same every game)
static func _one(gr: RandomNumberGenerator, side_m: float) -> Transform3D:
	# big enough to overlap and hide the ground under them, with some small ones to fill in
	var size = lerpf(0.07, 0.34, pow(gr.randf(), 1.7))
	var b = Basis(Vector3(gr.randf_range(-1.0, 1.0), gr.randf_range(-1.0, 1.0), gr.randf_range(-1.0, 1.0)).normalized(), gr.randf() * TAU)
	b = b * Basis.from_scale(Vector3(size * gr.randf_range(0.85, 1.35), size, size * gr.randf_range(0.8, 1.25)))
	return Transform3D(b, Vector3(gr.randf() * side_m, 0.0, gr.randf() * side_m))

## (the tests': a headless run keeps no instance's transform) The lumps of `big` size or more (the shader's size: its
## instance's y scale) laid within r m of p: [{root: where (world), size, patch, index}], from the same generator
func laid_near(p: Vector3, r: float, big: float) -> Array:
	var out = []
	var side_m = 32 * DsTerrain.CELL
	var gr = RandomNumberGenerator.new()
	gr.seed = 29
	for k in _patches.size():
		var base: Vector3 = _patches[k].position
		for i in _per:
			var t = _one(gr, side_m)
			var root = base + t.origin
			var size = t.basis.y.length()
			if size >= big and Vector2(root.x - p.x, root.z - p.z).length() <= r:
				out.append({"root": root, "size": size, "patch": k, "index": i})
	return out

func _on_loose(per: PackedInt32Array) -> void:
	_loose = per

func _process(_dt: float) -> void:
	if site == null or not site.get("active"):
		return
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var at = cam.global_position
	var side_m = 32 * DsTerrain.CELL
	for k in _patches.size():
		var inst = _patches[k]
		var any = k < _loose.size() and _loose[k] > 0
		var n = 0
		if any:
			var mid = inst.position + Vector3(side_m * 0.5, 0.0, side_m * 0.5)
			var d = Vector2(at.x - mid.x, at.z - mid.z).length()
			n = int(_per * (1.0 if d < 22.0 else (0.6 if d < 36.0 else 0.3)))
		if inst.multimesh.visible_instance_count != n:
			inst.multimesh.visible_instance_count = n
			inst.visible = n > 0
	# the blades and buckets near the camera, for the shader to keep lumps out of
	var rx = []
	var ry = []
	var rz = []
	var half = PackedVector3Array()
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
	var n_keep = rx.size()
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

# ---------------------------------------------------------------- what a lump's drawn as (the tests')

## shaders/ds_clod.gdshader's vertex(), worked out here for one lump (the tests': a headless run draws nothing): the
## lump rooted at `root` (world), `size` big (its instance's y scale), from the ground's two textures' bytes
## (DigSiteGrid.show_topo_bytes, show_offsets). `calm` as the shader's uniform of that name (0: as it was before the
## dirt physics' stage 9). -> {h: the ground under it (m over the grid's corner), keep: how much of its size it's
## drawn at, angle: how far it's turned (rad), col: its colour, shift: where it's shuffled to}. Not the blades' and
## buckets' keep-out. Keep the two the same.
static func lump_drawn(topo: PackedByteArray, off: PackedByteArray, origin: Vector3, root: Vector3, size: float, calm: float) -> Dictionary:
	const C := DsTerrain.CELL
	var w: int = DsTerrain.W
	var d: int = DsTerrain.D
	var ax = root.x - origin.x
	var az = root.z - origin.z
	var gx = ax / C - 0.5
	var gz = az / C - 0.5
	var cx = floori(gx)
	var cz = floori(gz)
	var fx = gx - cx
	var fz = gz - cz
	var hh = [0.0, 0.0, 0.0, 0.0]
	for k in 4:
		var qx = clampi(cx + (k & 1), 0, w - 1)
		var qz = clampi(cz + (k >> 1), 0, d - 1)
		var i = qz * w + qx
		hh[k] = (topo[i * 4] + 1.0 + off.decode_half(i * 2)) * C
	var h = lerpf(lerpf(hh[0], hh[1], fx), lerpf(hh[2], hh[3], fx), fz)
	var col_x = clampi(floori(ax / C), 0, w - 1)
	var col_z = clampi(floori(az / C), 0, d - 1)
	var ci = col_z * w + col_x
	var deep = topo[ci * 4 + 1] / 8.0 * C
	var keep = smoothstep(size * 0.12, size * 0.8, deep)
	var seed = fposmod(root.x * 12.9898 + root.z * 78.233, 1.0)
	var rate = lerpf(7.0 + seed * 9.0, (0.4 + seed * 0.4) / maxf(size, 0.07), calm)
	var col: Color = DsMats.COL[clampi(topo[ci * 4 + 2], 0, 15)]
	if calm > 0.0:
		# (its colour: the soil over its whole foot, not its middle column's alone)
		var reach = maxf(size * 0.6, C) / C
		var sum = Vector3(col.r, col.g, col.b) * 2.0
		for k in 4:
			var tx = clampi(floori(ax / C + (reach if k == 0 else (-reach if k == 1 else 0.0))), 0, w - 1)
			var tz = clampi(floori(az / C + (reach if k == 2 else (-reach if k == 3 else 0.0))), 0, d - 1)
			var c2: Color = DsMats.COL[clampi(topo[(tz * w + tx) * 4 + 2], 0, 15)]
			sum += Vector3(c2.r, c2.g, c2.b)
		var mixed = sum / 6.0
		col = col.lerp(Color(mixed.x, mixed.y, mixed.z), calm)
	var amp = lerpf(0.1, 0.1 * clampf(0.12 / maxf(size, 0.07), 0.25, 1.0), calm)
	return {"h": h, "keep": keep, "angle": h * rate, "col": col,
		"shift": Vector3(sin(h * 5.0 + seed * 20.0), 0.0, cos(h * 4.0 + seed * 31.0)) * amp}
