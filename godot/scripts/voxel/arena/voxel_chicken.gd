class_name VoxelChicken
extends Node3D
## A chicken (Stage 6), built in little cubes like everything else: a body, a head that bobs and pecks, two wings that
## flap, two legs that walk; a chick is a small yellow one. What it's doing comes from VoxelChickens (the host's, or
## alone): anim 0 standing, 1 walking, 2 pecking, 3 flapping (running off, or hopping up), 4 sitting (laying). Its
## meshes are made once per colour and shared. Killed (out in the yard), it's a carcass (carcass()): plucked, lying limp
## on its side, its feathers scattered round. Owned by the voxel session.

const V := 0.034                    # a cube, metres (a hen ~0.45 m tall)
## Feather colours: white, brown (a shaver), black (an australorp); the chick's.
const COATS := [
	[Color8(238, 236, 228), Color8(214, 210, 198)],
	[Color8(150, 82, 40), Color8(118, 60, 30)],
	[Color8(36, 36, 42), Color8(58, 64, 72)],
]
const CHICK := [Color8(246, 214, 92), Color8(232, 192, 70)]
const COMB := Color8(204, 30, 34)
const BEAK := Color8(232, 160, 40)
const LEG := Color8(226, 170, 60)
const EYE := Color8(16, 12, 10)
## A plucked bird's skin (a carcass), and its shut eye.
const PLUCK := [Color8(242, 206, 176), Color8(224, 178, 146)]
const SHUT := Color8(150, 96, 80)

static var _meshes := {}            # "coat,part" -> ArrayMesh
static var _mat: StandardMaterial3D

var coat := 0
var chick := false
var anim := 0
var _body: MeshInstance3D
var _head: Node3D
var _wings: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _t := 0.0
var _phase := 0.0

func build(coat_: int, chick_: bool) -> void:
	coat = coat_
	chick = chick_
	for c in get_children():
		c.queue_free()
	_wings.clear()
	_legs.clear()
	_t = randf() * 10.0
	var key := "c" if chick else str(coat)
	var root := Node3D.new()           # (scaled for a chick, so the bob and the legs keep their sizes)
	root.name = "Root"
	add_child(root)
	_body = MeshInstance3D.new()
	_body.mesh = _part(key, "body")
	_body.material_override = _mat
	root.add_child(_body)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.36, -0.13)
	root.add_child(_head)
	var hm := MeshInstance3D.new()
	hm.mesh = _part(key, "head")
	hm.material_override = _mat
	_head.add_child(hm)
	for s in [-1, 1]:
		var w := Node3D.new()
		w.position = Vector3(s * 0.1, 0.3, -0.02)
		root.add_child(w)
		var wm := MeshInstance3D.new()
		wm.mesh = _part(key, "wing")
		wm.material_override = _mat
		wm.scale.x = s
		w.add_child(wm)
		_wings.append(w)
		var l := Node3D.new()
		l.position = Vector3(s * 0.05, 0.18, 0.0)
		root.add_child(l)
		var lm := MeshInstance3D.new()
		lm.mesh = _part(key, "leg")
		lm.material_override = _mat
		l.add_child(lm)
		_legs.append(l)
	root.scale = Vector3.ONE * (0.5 if chick else 1.0)

func _process(dt: float) -> void:
	if _head == null:
		return
	_t += dt
	var walk := anim == 1 or anim == 3
	_phase += dt * (16.0 if anim == 3 else (9.0 if walk else 0.0))
	var sw := sin(_phase)
	for k in 2:
		_legs[k].rotation.x = (sw if k == 0 else -sw) * (0.6 if walk else 0.0)
		_legs[k].visible = anim != 4
	_body.position.y = (absf(sw) * 0.02 if walk else 0.0) - (0.15 if anim == 4 else 0.0)
	_head.position.y = 0.36 + _body.position.y
	# the head: bobbing forward and back as it walks, dipping to peck, looking about when it stands
	if anim == 2:
		var pk := maxf(0.0, sin(_t * 9.0))
		_head.rotation = Vector3(-pk * 1.1, 0, 0)
		_head.position.z = -0.13 - pk * 0.05
	elif walk:
		_head.rotation = Vector3.ZERO
		_head.position.z = -0.13 - absf(sw) * 0.04
	else:
		_head.rotation = Vector3(0, sin(_t * 1.3) * 0.6 * float(int(_t * 0.7) % 2), 0)
		_head.position.z = -0.13
	# the wings: tucked in, flapping when it runs off or hops up
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		var fl := (0.4 + 0.9 * (0.5 + 0.5 * sin(_t * 30.0))) if anim == 3 else 0.0
		_wings[k].rotation = Vector3(0, 0, s * fl)
		_wings[k].position.y = 0.3 + _body.position.y

# ---------------------------------------------------------------- a carcass

static var _feather_mesh: BoxMesh

## A killed chicken: plucked, lying limp on its side (the head flopped down, the legs stuck out stiff), its feathers
## scattered round on the ground (seed: where they lie). Its own node, not animated.
static func carcass(coat_: int, chick_: bool, seed: int) -> Node3D:
	var key := "pc" if chick_ else "p" + str(coat_)
	var k := 0.5 if chick_ else 1.0
	var n := Node3D.new()
	n.name = "Carcass"
	var root := Node3D.new()
	root.rotation.z = PI * 0.5                    # (on its side: its up toward -x, its left side up)
	root.position = Vector3(0.26 * k, 3.5 * V * k, 0.0)
	root.scale = Vector3.ONE * k
	n.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = _part(key, "body")
	body.material_override = _mat
	root.add_child(body)
	var head := Node3D.new()
	head.position = Vector3(-0.03, 0.34, -0.15)
	head.rotation = Vector3(0.5, 0.0, 1.15)       # (flopped down onto the ground)
	root.add_child(head)
	var hm := MeshInstance3D.new()
	hm.mesh = _part(key, "head")
	hm.material_override = _mat
	head.add_child(hm)
	for s in [-1, 1]:
		var w := MeshInstance3D.new()
		w.mesh = _part(key, "wing")
		w.material_override = _mat
		w.scale.x = s
		w.position = Vector3(s * 0.11, 0.3, -0.02)
		w.rotation.z = s * 0.25
		root.add_child(w)
		var l := Node3D.new()
		l.position = Vector3(s * 0.05, 0.16, 0.0)
		l.rotation.x = 0.35 + 0.25 * s            # (stiff, a little apart)
		root.add_child(l)
		var lm := MeshInstance3D.new()
		lm.mesh = _part(key, "leg")
		lm.material_override = _mat
		l.add_child(lm)
	# the feathers round it, flat on the ground
	var cols: Array = CHICK if chick_ else COATS[coat_]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = feather_mesh()
	mm.instance_count = 9 if chick_ else 16
	for i in mm.instance_count:
		var a := rng.randf() * TAU
		var r := (0.12 + rng.randf() * 0.45) * (0.7 if chick_ else 1.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
		mm.set_instance_transform(i, Transform3D(b, Vector3(cos(a) * r, 0.006 + rng.randf() * 0.004, sin(a) * r)))
		mm.set_instance_color(i, (cols[0] as Color).lerp(cols[1], rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = feather_mat()
	n.add_child(mmi)
	return n

## A feather: a flat little slip (shared by the carcasses' and the ones flying off a hit hen).
static func feather_mesh() -> BoxMesh:
	if _feather_mesh == null:
		_feather_mesh = BoxMesh.new()
		_feather_mesh.size = Vector3(0.03, 0.006, 0.075)
	return _feather_mesh

static var _fmat: StandardMaterial3D
static func feather_mat() -> StandardMaterial3D:
	if _fmat == null:
		_fmat = StandardMaterial3D.new()
		_fmat.vertex_color_use_as_albedo = true
		_fmat.vertex_color_is_srgb = true
		_fmat.roughness = 1.0
		_fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _fmat

# ---------------------------------------------------------------- the cubes

static func _part(key: String, part: String) -> ArrayMesh:
	var mk := key + "," + part
	if _meshes.has(mk):
		return _meshes[mk]
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.9
	var plucked := key.begins_with("p")          # (a carcass's: "p0".."p2", "pc")
	var base := key.trim_prefix("p")
	var c: Array = PLUCK if plucked else (CHICK if base == "c" else COATS[int(base)])
	var cells := {}                 # Vector3i -> Color, in cubes of V about the part's pivot
	match part:
		"body":
			# a round-ish body, the tail up at the back, the breast forward
			_fill(cells, Vector3i(-3, 5, -4), Vector3i(3, 10, 4), c)
			_fill(cells, Vector3i(-2, 4, -3), Vector3i(2, 4, 3), c)
			_fill(cells, Vector3i(-2, 11, -3), Vector3i(2, 11, 2), c)
			_fill(cells, Vector3i(-2, 9, 5), Vector3i(2, 13, 6), [c[1], c[0]])       # the tail
			_fill(cells, Vector3i(-1, 12, 7), Vector3i(1, 14, 7), [c[1], c[1]])
			if base == "c" or plucked:
				_carve(cells, Vector3i(-3, 9, 4), Vector3i(3, 14, 7))            # (a chick, a plucked one: no tail)
			if plucked:
				_fill(cells, Vector3i(-1, 9, 5), Vector3i(1, 10, 5), c)             # (the parson's nose)
		"head":
			_fill(cells, Vector3i(-2, 0, -2), Vector3i(2, 4, 2), c)
			_fill(cells, Vector3i(-1, 1, -4), Vector3i(1, 2, -3), [BEAK, BEAK])
			cells[Vector3i(-2, 3, -1)] = SHUT if plucked else EYE
			cells[Vector3i(2, 3, -1)] = SHUT if plucked else EYE
			if base != "c":
				_fill(cells, Vector3i(0, 5, -2), Vector3i(0, 6, 1), [COMB, COMB])
				cells[Vector3i(0, 7, -1)] = COMB
				cells[Vector3i(0, 7, 1)] = COMB
				_fill(cells, Vector3i(0, -1, -3), Vector3i(0, 0, -3), [COMB, COMB])
		"wing":
			if plucked:
				_fill(cells, Vector3i(0, -2, -2), Vector3i(0, 1, 1), [c[1], c[0]])   # (plucked: a bare little wing)
			else:
				_fill(cells, Vector3i(0, -3, -3), Vector3i(0, 1, 4), [c[1], c[0]])
		"leg":
			_fill(cells, Vector3i(0, -4, 0), Vector3i(0, -1, 0), [LEG, LEG])
			_fill(cells, Vector3i(0, -5, -2), Vector3i(0, -5, 1), [LEG, LEG])
			cells[Vector3i(-1, -5, -2)] = LEG
			cells[Vector3i(1, -5, -2)] = LEG
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3i in cells:
		_cube(st, Vector3(p) * V, cells[p], cells, p)
	st.generate_normals()
	var m := st.commit()
	_meshes[mk] = m
	return m

# a box of cubes from a to b (inclusive), each a shade between the two colours
static func _fill(cells: Dictionary, a: Vector3i, b: Vector3i, cols: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(a) ^ hash(b)
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				var t := rng.randf()
				cells[Vector3i(x, y, z)] = (cols[0] as Color).lerp(cols[1], t * t)

static func _carve(cells: Dictionary, a: Vector3i, b: Vector3i) -> void:
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				cells.erase(Vector3i(x, y, z))

const _DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const _SHADE := [0.86, 0.86, 1.0, 0.6, 0.8, 0.95]

# a cube's faces that nothing covers (clockwise, Godot's front)
static func _cube(st: SurfaceTool, o: Vector3, c: Color, cells: Dictionary, p: Vector3i) -> void:
	var h := V * 0.5
	for k in 6:
		var d: Vector3i = _DIRS[k]
		if cells.has(p + d):
			continue
		var n := Vector3(d)
		var u := Vector3(0, 1, 0) if absf(n.y) < 0.5 else Vector3(1, 0, 0)
		var w := n.cross(u)
		var mid := o + n * h
		var a := mid - u * h - w * h
		var b := mid + u * h - w * h
		var cc := mid + u * h + w * h
		var dd := mid - u * h + w * h
		var col := Color(c.r * _SHADE[k], c.g * _SHADE[k], c.b * _SHADE[k])
		for q in [a, cc, b, a, dd, cc]:          # (u, w, n right-handed: this way round is clockwise from outside)
			st.set_color(col)
			st.add_vertex(q)
