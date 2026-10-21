class_name VoxelStorage
extends StaticBody3D
## A chest or a cabinet to keep things in (the owner, 21 Oct, Stage 2: "storage chests/cabinets"): solid (you walk
## round it, enemies too), built of chunky wooden planks with iron bands (the chest, a lid on hinges at the back) or
## of painted steel (the cabinet, two doors on side hinges). Walk up and press E to open it: the lid swings up (the
## doors open) while either player has it open, and the inventory screen shows its slots beside your backpack. Its
## insides are a VoxelInventory; VoxelStorages keeps them (saved, and the host's in co-op). Owned by the voxel session.

const KINDS := {
	"chest": {"name": "Chest", "slots": 18, "cols": 9, "size": Vector3(1.0, 0.74, 0.62)},
	"cabinet": {"name": "Cabinet", "slots": 27, "cols": 9, "size": Vector3(0.92, 1.85, 0.52)},
}
const WOOD := Color8(124, 84, 50)
const WOOD_DARK := Color8(92, 60, 34)
const IRON := Color8(64, 64, 70)
const BRASS := Color8(196, 158, 70)
const STEEL := Color8(88, 104, 98)
const STEEL_DARK := Color8(60, 72, 68)
const OPEN_SPEED := 5.0

var sid := ""
var kind := "chest"
var title := ""
var inv: VoxelInventory
var open_here := false          # this player has it open ...
var open_there := false         # ... the other player has (co-op)
var _k := 0.0                   # 0 shut .. 1 open
var _hinges: Array[Node3D] = []
var _sound: VoxelSound

func setup(sid_: String, kind_: String, sound: VoxelSound) -> void:
	sid = sid_
	kind = kind_
	_sound = sound
	title = String(KINDS[kind].name)
	inv = VoxelInventory.new(int(KINDS[kind].slots))
	var size: Vector3 = KINDS[kind].size
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	add_child(cs)
	if kind == "chest":
		_build_chest(size)
	else:
		_build_cabinet(size)

func cols() -> int:
	return int(KINDS[kind].cols)

## Half its width and depth (level), for keeping walkers out of it.
func half() -> Vector2:
	var s: Vector3 = KINDS[kind].size
	return Vector2(s.x, s.z) * 0.5

## Where you stand to use it (in front of it).
func front() -> Vector3:
	var s: Vector3 = KINDS[kind].size
	return global_transform * Vector3(0, 0, s.z * 0.5 + 0.1)

## How well a look from eye along dir picks this one: > 0 within reach and in view (bigger: nearer the middle of the
## view), 0 otherwise.
func pick_score(eye: Vector3, dir: Vector3, reach: float) -> float:
	var s: Vector3 = KINDS[kind].size
	var mid := global_transform * Vector3(0, s.y * 0.5, 0)
	var to := mid - eye
	var flat := Vector2(to.x, to.z).length() - maxf(s.x, s.z) * 0.5
	if flat > reach:
		return 0.0
	var d := to.normalized().dot(dir)
	if d < 0.55:
		return 0.0
	return d / (1.0 + maxf(flat, 0.0))

func _process(dt: float) -> void:
	var want := 1.0 if (open_here or open_there) else 0.0
	if want == _k:
		return
	var was := _k
	_k = move_toward(_k, want, dt * OPEN_SPEED)
	if was == 0.0 and _sound:
		_sound.play("chest_open" if kind == "chest" else "cabinet_open", global_position + Vector3.UP * 0.5, -2.0)
	if _k == 0.0 and _sound:
		_sound.play("chest_close" if kind == "chest" else "cabinet_close", global_position + Vector3.UP * 0.5, -3.0)
	var e := ease(_k, -2.2)          # (quick off the hinge, slowing at the top)
	if kind == "chest":
		_hinges[0].rotation.x = -deg_to_rad(105.0) * e
	else:
		_hinges[0].rotation.y = -deg_to_rad(110.0) * e
		_hinges[1].rotation.y = deg_to_rad(110.0) * e

# ---------------------------------------------------------------- how it looks

func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi

func _build_chest(s: Vector3) -> void:
	var base_h := s.y * 0.72
	var lid_h := s.y - base_h
	var iron := _mat(IRON, 0.45, 0.7)
	var brass := _mat(BRASS, 0.35, 0.8)
	# the box: planks across (each a shade off), a dark inside showing when the lid's up
	var planks := 4
	for i in planks:
		var c := WOOD.lerp(WOOD_DARK, 0.15 * float((i * 7) % 3))
		_box(self, Vector3(s.x, base_h / planks - 0.008, s.z), Vector3(0, base_h / planks * (i + 0.5), 0), _mat(c))
	_box(self, Vector3(s.x - 0.08, 0.01, s.z - 0.08), Vector3(0, base_h + 0.001, 0), _mat(WOOD_DARK.darkened(0.6)))
	for x in [-0.5, 0.5]:
		_box(self, Vector3(0.05, base_h + 0.004, s.z + 0.012), Vector3(x * (s.x - 0.12), base_h * 0.5, 0), iron)
	# the lid, hinged along the back top edge
	var hinge := Node3D.new()
	hinge.position = Vector3(0, base_h, -s.z * 0.5)
	add_child(hinge)
	_hinges.append(hinge)
	_box(hinge, Vector3(s.x + 0.02, lid_h, s.z + 0.02), Vector3(0, lid_h * 0.5, s.z * 0.5), _mat(WOOD.lightened(0.05)))
	for x in [-0.5, 0.5]:
		_box(hinge, Vector3(0.05, lid_h + 0.012, s.z + 0.034), Vector3(x * (s.x - 0.12), lid_h * 0.5, s.z * 0.5), iron)
	_box(hinge, Vector3(0.1, 0.12, 0.03), Vector3(0, lid_h * 0.3, s.z + 0.02), brass)        # the hasp

func _build_cabinet(s: Vector3) -> void:
	var steel := _mat(STEEL, 0.55, 0.45)
	var dark := _mat(STEEL_DARK, 0.6, 0.4)
	var handle := _mat(Color8(200, 200, 205), 0.3, 0.9)
	var t := 0.035
	# the carcass: back, sides, top, bottom, two shelves (seen with the doors open)
	_box(self, Vector3(s.x, s.y, t), Vector3(0, s.y * 0.5, -s.z * 0.5 + t * 0.5), dark)
	for x in [-1.0, 1.0]:
		_box(self, Vector3(t, s.y, s.z), Vector3(x * (s.x * 0.5 - t * 0.5), s.y * 0.5, 0), steel)
	_box(self, Vector3(s.x, t, s.z), Vector3(0, s.y - t * 0.5, 0), steel)
	_box(self, Vector3(s.x, 0.08, s.z), Vector3(0, 0.04, 0), dark)
	for k in [0.36, 0.68]:
		_box(self, Vector3(s.x - t * 2.0, 0.02, s.z - t), Vector3(0, s.y * k, t * 0.5), steel)
	# two doors on the front edges' hinges
	for side in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(side * s.x * 0.5, 0, s.z * 0.5)
		add_child(hinge)
		_hinges.append(hinge)
		var w := s.x * 0.5 - 0.004
		_box(hinge, Vector3(w, s.y - 0.1, t), Vector3(-side * w * 0.5, s.y * 0.5 + 0.02, t * 0.5), steel)
		for v in [0.82, 0.86, 0.9]:     # vents
			_box(hinge, Vector3(w * 0.6, 0.012, 0.006), Vector3(-side * w * 0.5, s.y * v, t + 0.003), dark)
		_box(hinge, Vector3(0.025, 0.22, 0.03), Vector3(-side * (w - 0.05), s.y * 0.52, t + 0.015), handle)
