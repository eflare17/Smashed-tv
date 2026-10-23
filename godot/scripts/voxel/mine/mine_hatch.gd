class_name MineHatch
extends Node3D
## The way down to the mine (the owner, 23 Oct): a garage roller door in the yard side of the arena's south wall,
## between the buyer and the back door, with a MINE sign over it and hazard stripes. E at it: the door rolls up on the
## lift shaft's dark and you're down. Owned by the voxel session.

const AT := Vector3(10.6, 0, 22.5)      # the door's middle at the foot of the wall (it faces the yard: +z)
const W := 1.9
const H := 2.3

var open_k := 0.0               # 0 shut .. 1 rolled up
var want := 0.0
var _slats: Node3D

func setup() -> void:
	position = AT
	var steel := _mat(Color8(150, 154, 160), 0.45, 0.7)
	var frame := _mat(Color8(70, 72, 78), 0.5, 0.6)
	var dark := _mat(Color8(6, 6, 8), 1.0, 0.0)
	# the dark of the shaft behind it
	_box(Vector3(W, H, 0.02), Vector3(0, H * 0.5, 0.012), dark)
	# the posts, the roller's housing over it
	for x in [-W * 0.5 - 0.06, W * 0.5 + 0.06]:
		_box(Vector3(0.12, H + 0.1, 0.14), Vector3(x, (H + 0.1) * 0.5, 0.07), frame)
	_box(Vector3(W + 0.36, 0.34, 0.3), Vector3(0, H + 0.2, 0.15), frame)
	# hazard stripes along the housing
	var yel := _mat(Color8(240, 190, 30), 0.6, 0.0)
	var blk := _mat(Color8(20, 20, 20), 0.6, 0.0)
	for k in 10:
		_box(Vector3((W + 0.36) / 10.0, 0.08, 0.01), Vector3(-(W + 0.36) * 0.5 + (k + 0.5) * (W + 0.36) / 10.0, H + 0.08, 0.305), yel if k % 2 == 0 else blk)
	# the door: ribbed slats, rolled up into the housing as it opens
	_slats = Node3D.new()
	add_child(_slats)
	for k in 12:
		var s := _box(Vector3(W, H / 12.0 - 0.01, 0.04), Vector3(0, (k + 0.5) * H / 12.0, 0.05), steel, _slats)
		s.set_meta("y", (k + 0.5) * H / 12.0)
	var handle := _box(Vector3(0.3, 0.04, 0.05), Vector3(0, 0.25, 0.08), frame, _slats)
	handle.set_meta("y", 0.25)
	# the sign
	var l := Label3D.new()
	l.text = "MINE"
	l.font_size = 72
	l.pixel_size = 0.005
	l.outline_size = 12
	l.modulate = Color8(255, 210, 60)
	l.position = Vector3(0, H + 0.62, 0.05)
	add_child(l)
	var l2 := Label3D.new()
	l2.text = "authorised diggers only"
	l2.font_size = 32
	l2.pixel_size = 0.004
	l2.outline_size = 6
	l2.position = Vector3(0, H + 0.4, 0.05)
	add_child(l2)
	# a lamp over the door
	var lamp := _box(Vector3(0.18, 0.1, 0.12), Vector3(0, H + 0.95, 0.12), _mat(Color8(255, 200, 120), 0.3, 0.0, 3.0))
	var lt := OmniLight3D.new()
	lt.light_color = Color8(255, 190, 110)
	lt.omni_range = 3.5
	lt.light_energy = 0.8
	lt.position = Vector3(0, -0.2, 0.4)
	lamp.add_child(lt)

func _process(dt: float) -> void:
	open_k = move_toward(open_k, want, dt * 1.6)
	# each slat slides up into the housing (they bunch at the top)
	for s in _slats.get_children():
		var y: float = s.get_meta("y")
		var top := H + 0.1
		var ny := lerpf(y, top, open_k)
		s.position.y = ny
		s.visible = ny < top - 0.02 or open_k < 0.99

## Looking at the door from eye along dir, within reach.
func pick(eye: Vector3, dir: Vector3, reach := 2.6) -> bool:
	var box := AABB(AT + Vector3(-W * 0.5 - 0.1, 0, -0.1), Vector3(W + 0.2, H + 0.5, 0.5))
	var hit = box.intersects_ray(eye, dir)
	return hit != null and (hit as Vector3).distance_to(eye) <= reach

func _mat(c: Color, rough := 0.9, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m

func _box(size: Vector3, at: Vector3, m: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi
