class_name VoxelChicken
extends Node3D
## A chicken (Stage 6), built in little cubes like everything else: a body, a head that bobs and pecks, two wings that
## flap, two legs that walk; a chick is a small yellow one. What it's doing comes from VoxelChickens (the host's, or
## alone): anim 0 standing, 1 walking, 2 pecking, 3 flapping (running off, or hopping up), 4 sitting (laying). Its
## meshes are made once per colour and shared. Owned by the voxel session.

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
	var c: Array = CHICK if key == "c" else COATS[int(key)]
	var cells := {}                 # Vector3i -> Color, in cubes of V about the part's pivot
	match part:
		"body":
			# a round-ish body, the tail up at the back, the breast forward
			_fill(cells, Vector3i(-3, 5, -4), Vector3i(3, 10, 4), c)
			_fill(cells, Vector3i(-2, 4, -3), Vector3i(2, 4, 3), c)
			_fill(cells, Vector3i(-2, 11, -3), Vector3i(2, 11, 2), c)
			_fill(cells, Vector3i(-2, 9, 5), Vector3i(2, 13, 6), [c[1], c[0]])       # the tail
			_fill(cells, Vector3i(-1, 12, 7), Vector3i(1, 14, 7), [c[1], c[1]])
			if key == "c":
				_carve(cells, Vector3i(-3, 9, 4), Vector3i(3, 14, 7))            # (a chick: no tail)
		"head":
			_fill(cells, Vector3i(-2, 0, -2), Vector3i(2, 4, 2), c)
			_fill(cells, Vector3i(-1, 1, -4), Vector3i(1, 2, -3), [BEAK, BEAK])
			cells[Vector3i(-2, 3, -1)] = EYE
			cells[Vector3i(2, 3, -1)] = EYE
			if key != "c":
				_fill(cells, Vector3i(0, 5, -2), Vector3i(0, 6, 1), [COMB, COMB])
				cells[Vector3i(0, 7, -1)] = COMB
				cells[Vector3i(0, 7, 1)] = COMB
				_fill(cells, Vector3i(0, -1, -3), Vector3i(0, 0, -3), [COMB, COMB])
		"wing":
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
