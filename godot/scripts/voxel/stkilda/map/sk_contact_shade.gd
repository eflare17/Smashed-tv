# (Copied from stkilda-godot scripts/town/contact_shade.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkContactShade
extends RefCounted
## The soft dark where things meet the ground (what real light does in corners and under things, which the plain
## renderer the web game uses can't work out by itself): a skirt of shade on the ground round each building's foot
## and along walls, fading out over a metre or two, and a soft round shadow under the small things (trees, posts,
## lamps, benches, the car, you), so nothing looks stuck on. All the skirts are one see-through mesh; the round ones
## are one quad repeated (a MultiMesh), each sized and darkened to suit. Things being built call skirt(), line() and
## blob(); build() then makes the meshes. The sun's own shadows still fall as before: this is under them.

const Y := 0.175                         # just over the highest ground (the roads are at 0.14, the malls 0.16)

static var _skirts: SurfaceTool
static var _blobs: Array = []            # [x, z, radius, darkness]
static var _mat: StandardMaterial3D
static var _blob_mat: StandardMaterial3D
static var _quad: QuadMesh

static func begin() -> void:
	_skirts = SurfaceTool.new()
	_skirts.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blobs = []

## Shade round the outside of an outline (a building's foot): `dark` at the wall, nothing `wide` m out.
static func skirt(ring: PackedVector2Array, wide := 1.6, dark := 0.4) -> void:
	if _skirts == null:
		return
	var n := ring.size()
	if n > 2 and ring[0].is_equal_approx(ring[n - 1]):
		n -= 1
	if n < 3:
		return
	# (which way is out: the outline's turning)
	var area := 0.0
	for k in n:
		area += ring[k].cross(ring[(k + 1) % n])
	var outs: Array = []
	for k in n:
		var d := (ring[(k + 1) % n] - ring[k]).normalized()
		outs.append(Vector2(d.y, -d.x) * (1.0 if area > 0.0 else -1.0))
	for k in n:
		var a := ring[k]
		var b := ring[(k + 1) % n]
		var o: Vector2 = outs[k] * wide
		_quad_fade(a, b, a + o, b + o, dark)
		# round the corner to the next wall
		var o2: Vector2 = outs[(k + 1) % n] * wide
		if (outs[k] as Vector2).cross(outs[(k + 1) % n]) * (1.0 if area > 0.0 else -1.0) < 0.0:
			_tri_fade(b, b + o, b + o2, dark)

## Shade both sides of a wall from a to b.
static func line(a: Vector2, b: Vector2, wide := 1.2, dark := 0.35) -> void:
	if _skirts == null or a.distance_to(b) < 0.01:
		return
	var d := (b - a).normalized()
	var o := Vector2(d.y, -d.x) * wide
	_quad_fade(a, b, a + o, b + o, dark)
	_quad_fade(a, b, a - o, b - o, dark)

## A soft round shadow under something small at (x, z).
static func blob(at: Vector2, radius: float, dark := 0.4) -> void:
	_blobs.append([at.x, at.y, radius, dark])

static func _quad_fade(a: Vector2, b: Vector2, a_out: Vector2, b_out: Vector2, dark: float) -> void:
	var c0 := Color(0, 0, 0, dark)
	var c1 := Color(0, 0, 0, 0)
	_v(a, c0)
	_v(b, c0)
	_v(b_out, c1)
	_v(a, c0)
	_v(b_out, c1)
	_v(a_out, c1)

static func _tri_fade(at: Vector2, p: Vector2, q: Vector2, dark: float) -> void:
	_v(at, Color(0, 0, 0, dark))
	_v(p, Color(0, 0, 0, 0))
	_v(q, Color(0, 0, 0, 0))

static func _v(p: Vector2, c: Color) -> void:
	_skirts.set_color(c)
	_skirts.set_normal(Vector3.UP)
	_skirts.add_vertex(Vector3(p.x, Y, p.y))

## Make the meshes, under `parent`.
static func build(parent: Node3D) -> void:
	if _skirts == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "SkContactShade"
	mi.mesh = _skirts.commit()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_skirts = null
	if not _blobs.is_empty():
		parent.add_child(blobs(_blobs, "Blobs"))
	_blobs = []

## A MultiMesh of soft round shadows: `list` of [x, z, radius, darkness].
static func blobs(list: Array, name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad()
	mm.instance_count = list.size()
	for k in list.size():
		var b: Array = list[k]
		var r: float = b[2]
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(r * 2.0, 1, r * 2.0)), Vector3(b[0], Y + 0.002, b[1])))
		mm.set_instance_color(k, Color(0, 0, 0, b[3]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

## One soft round shadow to carry about (under the car, under you): `radius` m, `dark`.
static func carried(radius: float, dark: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Shade"
	mi.mesh = quad()
	mi.scale = Vector3(radius * 2.0, 1, radius * 2.0)
	mi.position.y = Y + 0.004
	var m := blob_material().duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = false
	m.albedo_color = Color(0, 0, 0, dark)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.vertex_color_use_as_albedo = true
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _mat

static func blob_material() -> StandardMaterial3D:
	if _blob_mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.75))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_blob_mat = material().duplicate() as StandardMaterial3D
		_blob_mat.albedo_texture = tex
	return _blob_mat

static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.orientation = PlaneMesh.FACE_Y
		_quad.size = Vector2(1, 1)
		_quad.material = blob_material()
	return _quad

## Shade round the foot of a whole thing (a ride, a building made specially): the outline of what of it is near the
## ground (its meshes' boxes, in its own turn), as a rectangle.
static func under_node(n: Node3D, wide := 1.7, dark := 0.42) -> void:
	var inv := n.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var xf := inv * m.global_transform
		var b := xf * m.get_aabb()
		if b.position.y > 1.5:
			continue                       # (only what comes down to the ground)
		box = b if first else box.merge(b)
		first = false
	if first or box.size.x > 80.0 or box.size.z > 80.0:
		return
	var g := n.global_transform
	var ring := PackedVector2Array()
	for c in [Vector3(box.position.x, 0, box.position.z), Vector3(box.end.x, 0, box.position.z), Vector3(box.end.x, 0, box.end.z), Vector3(box.position.x, 0, box.end.z)]:
		var w: Vector3 = g * (c as Vector3)
		ring.append(Vector2(w.x, w.z))
	skirt(ring, wide, dark)
