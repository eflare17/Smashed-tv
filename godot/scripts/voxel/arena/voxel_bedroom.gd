class_name VoxelBedroom
extends Node3D
## The bedroom (the owner, 21 Oct, Stage 3: "rebuild from Smashed TV: two beds, a chest at the end of each bed (one per
## player)"), through a door in the arena's south wall. Laid out like the HTML game's bedroom (its floor picture: the
## planks, the rug, the dumbbell, the books; the door top left; the beds against the top wall, a nightstand by them; the
## wardrobe and the full-length mirror), at the voxel game's size (the HTML game's units at 2.25 cm: 9.9 x 7.7 m), with
## a second bed. Each bed has its player's chest at its foot (VoxelStorages makes them, with their padlocks). E at a
## bed lies you down on it (health back faster; WASD, Space or E gets you up); E at the wardrobe opens its doors. The
## mirror shows the room (a second camera rendering the reflection) and you in it. A safe room: enemies can't come in
## and don't go for someone in here. Owned by the voxel session.

const X0 := -4.95               # the room's floor (world metres): x across ...
const X1 := 4.95
const Z0 := 22.5                # ... z from the arena's south wall's outer face ...
const Z1 := 30.2                # ... to its own back wall
const H := 2.7                  # ceiling height
const DOOR_X0 := -2.9           # the doorway in the arena's south wall (the HTML game's BED_DOOR: x 110, 64 wide)
const DOOR_X1 := -1.45
const DOOR_H := 2.1
const WALL := 0.25              # the room's own walls' thickness
const BED_W := 1.3
const BED_L := 2.1
const BED_TOP := 0.55           # the mattress's top
## The beds' middles (x), player 1's (the host's) by the nightstand on the right, as in the HTML game, player 2's left.
const BED_X := {1: 3.55, 2: 1.15}
const BED_COL := {1: Color8(46, 72, 150), 2: Color8(46, 120, 70)}    # duvets: the HTML game's blue; green
const NIGHT_X := 2.35
const WARD_X := -3.1            # the wardrobe and the mirror, against the back wall, facing the beds
const MIRROR_X := -1.1
const MIRROR_W := 0.8
const MIRROR_H := 1.8

var arena: Node3D
var ceiling: Node3D
var _door: Node3D
var _door_shape: CollisionShape3D
var _door_k := 0.0
var _ward_doors: Array[Node3D] = []
var ward_open := false
var _ward_k := 0.0
var mirror: VoxelMirror
var _floor_tex: Texture2D

## Inside the house (the bedroom or its doorway): the enemies keep out and don't go for anyone in here.
static func in_house(p: Vector3) -> bool:
	return p.z > 21.6 and p.x > X0 - 0.3 and p.x < X1 + 0.3 and p.z < Z1 + 0.3

## Where player i's chest stands: the foot of their bed.
static func chest_spot(i: int) -> Vector3:
	return Vector3(BED_X[i], 0, Z0 + BED_L + 0.36)

func setup(arena_: Node3D) -> void:
	arena = arena_
	_floor_tex = load("res://assets/voxel/art/bedroom_floor.png") if ResourceLoader.exists("res://assets/voxel/art/bedroom_floor.png") else null
	_shell()
	for i in [1, 2]:
		_bed(i)
	_nightstand()
	_wardrobe()
	mirror = VoxelMirror.new()
	add_child(mirror)
	mirror.setup(arena, Vector3(MIRROR_X, 0.08 + MIRROR_H * 0.5, Z1 - 0.06), Vector3(0, 0, -1), MIRROR_W, MIRROR_H)
	_lights()

# ---------------------------------------------------------------- each frame

func _process(dt: float) -> void:
	# the door swings open (into the room) as anyone comes near it, shut again after
	var mid := Vector3((DOOR_X0 + DOOR_X1) * 0.5, 0, 22.0)
	var near := false
	for p in _players():
		if Vector2(p.x - mid.x, p.z - mid.z).length() < 2.0:
			near = true
	var was := _door_k
	_door_k = move_toward(_door_k, 1.0 if near else 0.0, dt * 3.0)
	if was == 0.0 and _door_k > 0.0:
		arena.sound.play("chest_open", mid + Vector3.UP, -6.0, 0.7)
	if _door_k == 0.0 and was > 0.0:
		arena.sound.play("chest_close", mid + Vector3.UP, -6.0, 0.8)
	_door.rotation.y = -deg_to_rad(95.0) * ease(_door_k, -1.8)
	if _door_shape.disabled != (_door_k > 0.05):
		_door_shape.set_deferred("disabled", _door_k > 0.05)     # (open: walk through it)
	var wk := 1.0 if ward_open else 0.0
	if _ward_k != wk:
		_ward_k = move_toward(_ward_k, wk, dt * 4.0)
		for k in _ward_doors.size():
			_ward_doors[k].rotation.y = (1.0 if k == 0 else -1.0) * -deg_to_rad(100.0) * ease(_ward_k, -2.0)
	ceiling.visible = not arena.top_down          # (from above: the room without its lid)

func _players() -> Array:
	var out := [arena.player.global_position]
	if arena.net and arena.net.linked and arena.net._o_body and is_instance_valid(arena.net._o_body):
		out.append(arena.net._o_body.global_position)
	return out

## The bed (1 or 2) a look from eye along dir lands on within reach, and how far: [bed (0: none), distance].
func bed_hit(eye: Vector3, dir: Vector3, reach := 2.4) -> Array:
	var best := 0
	var bd := INF
	for i in [1, 2]:
		var box := AABB(Vector3(BED_X[i] - BED_W * 0.5, 0, Z0), Vector3(BED_W, 1.1, BED_L))
		var hit = box.intersects_ray(eye, dir)
		if hit != null and (hit as Vector3).distance_to(eye) <= reach and (hit as Vector3).distance_to(eye) < bd:
			bd = (hit as Vector3).distance_to(eye)
			best = i
	return [best, bd]

func bed_at(eye: Vector3, dir: Vector3, reach := 2.4) -> int:
	return int(bed_hit(eye, dir, reach)[0])

## Looking at the wardrobe within reach.
func wardrobe_at(eye: Vector3, dir: Vector3, reach := 2.2) -> bool:
	var box := AABB(Vector3(WARD_X - 0.7, 0, Z1 - 0.62), Vector3(1.4, 2.0, 0.62))
	var hit = box.intersects_ray(eye, dir)
	return hit != null and (hit as Vector3).distance_to(eye) <= reach

## Lying on bed i: where the body goes (on the mattress) and where the eye is (on the pillow).
func lie_spot(i: int) -> Vector3:
	return Vector3(BED_X[i], BED_TOP, Z0 + BED_L * 0.55)

func lie_eye(i: int) -> Vector3:
	return Vector3(BED_X[i], BED_TOP + 0.28, Z0 + 0.38)

## Where you stand after getting up from bed i: beside it, toward the room's middle.
func up_spot(i: int) -> Vector3:
	return Vector3(BED_X[i] - BED_W * 0.5 - 0.45, 0, Z0 + BED_L * 0.6)

# ---------------------------------------------------------------- building it

func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _mesh_box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi

# a solid box (collision and looks)
func _solid(size: Vector3, at: Vector3, m: Material, parent: Node3D = self) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = at
	parent.add_child(sb)
	_mesh_box(sb, size, Vector3.ZERO, m)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	return sb

func _shell() -> void:
	var w := X1 - X0
	var d := Z1 - Z0
	var mid := Vector3((X0 + X1) * 0.5, 0, (Z0 + Z1) * 0.5)
	# the floor: the HTML game's bedroom picture (its bed painted over: the beds are real now), pixel for pixel
	var fm := StandardMaterial3D.new()
	if _floor_tex:
		fm.albedo_texture = _floor_tex
		fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	else:
		fm.albedo_color = Color8(120, 82, 48)
	fm.roughness = 0.75
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	floor_mi.mesh = pm
	floor_mi.material_override = fm
	floor_mi.position = mid + Vector3(0, 0.002, 0)
	add_child(floor_mi)
	var fb := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(w + WALL * 2.0, 1.0, d + WALL)
	fc.shape = fsh
	fb.position = mid + Vector3(0, -0.5, WALL * 0.5)
	fb.add_child(fc)
	add_child(fb)
	# walls: the HTML game's #2b3040 outside edge; papered inside (a warm plain colour), a skirting board
	var paper := _mat(Color8(196, 178, 150), 0.95)
	var skirt := _mat(Color8(90, 60, 36))
	_solid(Vector3(WALL, H, d + WALL), Vector3(X0 - WALL * 0.5, H * 0.5, mid.z + WALL * 0.5), paper)
	_solid(Vector3(WALL, H, d + WALL), Vector3(X1 + WALL * 0.5, H * 0.5, mid.z + WALL * 0.5), paper)
	_solid(Vector3(w, H, WALL), Vector3(mid.x, H * 0.5, Z1 + WALL * 0.5), paper)
	# the room's side of the arena's wall: papered too, with the doorway (and a frame round it)
	_mesh_box(self, Vector3(DOOR_X0 - X0, H, 0.02), Vector3((X0 + DOOR_X0) * 0.5, H * 0.5, Z0 + 0.01), paper)
	_mesh_box(self, Vector3(X1 - DOOR_X1, H, 0.02), Vector3((DOOR_X1 + X1) * 0.5, H * 0.5, Z0 + 0.01), paper)
	_mesh_box(self, Vector3(DOOR_X1 - DOOR_X0, H - DOOR_H, 0.02), Vector3((DOOR_X0 + DOOR_X1) * 0.5, (H + DOOR_H) * 0.5, Z0 + 0.01), paper)
	var frame := _mat(Color8(240, 236, 226), 0.6)
	for x in [DOOR_X0 - 0.04, DOOR_X1 + 0.04]:
		_mesh_box(self, Vector3(0.08, DOOR_H, 1.08), Vector3(x, DOOR_H * 0.5, 22.0), frame)
	_mesh_box(self, Vector3(DOOR_X1 - DOOR_X0 + 0.16, 0.08, 1.08), Vector3((DOOR_X0 + DOOR_X1) * 0.5, DOOR_H + 0.04, 22.0), frame)
	for sk in [[Vector3(0.02, 0.12, d), Vector3(X0 + 0.01, 0.06, mid.z)], [Vector3(0.02, 0.12, d), Vector3(X1 - 0.01, 0.06, mid.z)],
			[Vector3(w, 0.12, 0.02), Vector3(mid.x, 0.06, Z1 - 0.01)]]:
		_mesh_box(self, sk[0], sk[1], skirt)
	# the ceiling (hidden from above), a light in its middle
	ceiling = Node3D.new()
	add_child(ceiling)
	_mesh_box(ceiling, Vector3(w + WALL * 2.0, 0.12, d + WALL), Vector3(mid.x, H + 0.06, mid.z + WALL * 0.5), _mat(Color8(232, 228, 220), 0.95))
	var shade := _mat(Color8(255, 240, 210))
	shade.emission_enabled = true
	shade.emission = Color8(255, 226, 170)
	shade.emission_energy_multiplier = 2.0
	_mesh_box(ceiling, Vector3(0.5, 0.06, 0.5), Vector3(mid.x, H - 0.03, mid.z), shade)
	# the door: a slab hinged on the doorway's left post, opening into the room
	_door = Node3D.new()
	_door.position = Vector3(DOOR_X0, 0, Z0 - 0.05)
	add_child(_door)
	var slab := _solid(Vector3(DOOR_X1 - DOOR_X0 - 0.02, DOOR_H - 0.02, 0.05), Vector3((DOOR_X1 - DOOR_X0) * 0.5, DOOR_H * 0.5, 0), _mat(Color8(150, 104, 62), 0.7), _door)
	_mesh_box(slab, Vector3(0.1, 0.03, 0.05), Vector3((DOOR_X1 - DOOR_X0) * 0.38, 0, 0.05), _mat(Color8(200, 170, 80), 0.3, 0.9))
	_door_shape = slab.get_child(1)

func _bed(i: int) -> void:
	var x: float = BED_X[i]
	var wood := _mat(Color8(98, 62, 36), 0.7)
	var root := Node3D.new()
	root.position = Vector3(x, 0, Z0)
	add_child(root)
	# frame, legs, headboard against the wall, the mattress, the duvet over its foot end, two pillows
	_solid(Vector3(BED_W, 0.3, BED_L), Vector3(0, 0.15 + 0.08, BED_L * 0.5), wood, root)
	for lx in [-1.0, 1.0]:
		for lz in [0.06, BED_L - 0.06]:
			_mesh_box(root, Vector3(0.08, 0.08, 0.08), Vector3(lx * (BED_W * 0.5 - 0.04), 0.04, lz), wood)
	_solid(Vector3(BED_W + 0.08, 1.05, 0.08), Vector3(0, 0.525, 0.04), wood, root)
	_mesh_box(root, Vector3(BED_W + 0.04, 0.06, 0.12), Vector3(0, 1.08, 0.06), wood)
	_mesh_box(root, Vector3(BED_W - 0.06, BED_TOP - 0.38, BED_L - 0.12), Vector3(0, (BED_TOP + 0.38) * 0.5, BED_L * 0.5 + 0.02), _mat(Color8(238, 238, 232), 0.95))
	var duvet := _mat(BED_COL[i], 0.95)
	_mesh_box(root, Vector3(BED_W + 0.02, 0.07, BED_L * 0.62), Vector3(0, BED_TOP + 0.02, BED_L - BED_L * 0.31), duvet)
	_mesh_box(root, Vector3(BED_W + 0.03, 0.26, 0.04), Vector3(0, BED_TOP - 0.1, BED_L + 0.0), duvet)          # hanging over the foot
	for px in [-0.3, 0.3]:
		_mesh_box(root, Vector3(0.5, 0.12, 0.34), Vector3(px * BED_W / 1.3, BED_TOP + 0.05, 0.3), _mat(Color8(250, 250, 248), 0.95))
	# a name card on the headboard: P1 / P2
	var l := Label3D.new()
	l.text = "P%d" % i
	l.font_size = 64
	l.pixel_size = 0.004
	l.modulate = Color(1, 0.95, 0.8)
	l.outline_size = 8
	l.position = Vector3(0, 0.85, 0.085)
	root.add_child(l)

func _nightstand() -> void:
	var wood := _mat(Color8(108, 70, 40), 0.7)
	var root := Node3D.new()
	root.position = Vector3(NIGHT_X, 0, Z0 + 0.25)
	add_child(root)
	_solid(Vector3(0.55, 0.55, 0.45), Vector3(0, 0.275, 0), wood, root)
	_mesh_box(root, Vector3(0.45, 0.16, 0.02), Vector3(0, 0.36, 0.23), _mat(Color8(130, 88, 52), 0.7))
	_mesh_box(root, Vector3(0.08, 0.02, 0.02), Vector3(0, 0.36, 0.245), _mat(Color8(210, 180, 90), 0.3, 0.9))
	# a lamp: a base, a stem, a glowing shade, its warm light
	_mesh_box(root, Vector3(0.14, 0.03, 0.14), Vector3(0, 0.565, 0), _mat(Color8(60, 60, 64), 0.4, 0.6))
	_mesh_box(root, Vector3(0.025, 0.22, 0.025), Vector3(0, 0.69, 0), _mat(Color8(60, 60, 64), 0.4, 0.6))
	var shade := _mat(Color8(250, 230, 190))
	shade.emission_enabled = true
	shade.emission = Color8(255, 200, 120)
	shade.emission_energy_multiplier = 1.5
	_mesh_box(root, Vector3(0.24, 0.16, 0.24), Vector3(0, 0.84, 0), shade)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.78, 0.5)
	lamp.light_energy = 0.9
	lamp.omni_range = 3.2
	lamp.position = Vector3(0, 0.84, 0.1)
	root.add_child(lamp)

func _wardrobe() -> void:
	# the HTML game's wardrobe (its picture: dark wood, two doors with brass handles, a drawer, a crown along the top)
	var wood := _mat(Color8(84, 46, 26), 0.7)
	var dark := _mat(Color8(60, 32, 18), 0.75)
	var brass := _mat(Color8(205, 160, 60), 0.3, 0.9)
	var root := Node3D.new()
	root.position = Vector3(WARD_X, 0, Z1 - 0.3)
	root.rotation.y = PI                 # (its front toward the beds)
	add_child(root)
	var ww := 1.3
	var wh := 2.0
	var wd := 0.55
	_solid(Vector3(ww, 0.1, wd), Vector3(0, 0.05, 0), dark, root)
	_mesh_box(root, Vector3(ww, wh - 0.1, 0.03), Vector3(0, wh * 0.5 + 0.05, -wd * 0.5 + 0.015), dark)        # back
	for sx in [-1.0, 1.0]:
		_solid(Vector3(0.04, wh, wd), Vector3(sx * (ww * 0.5 - 0.02), wh * 0.5, 0), wood, root)
	_mesh_box(root, Vector3(ww + 0.1, 0.1, wd + 0.06), Vector3(0, wh + 0.05, 0.0), wood)                       # crown
	_mesh_box(root, Vector3(ww - 0.08, 0.32, 0.03), Vector3(0, 0.27, wd * 0.5 - 0.015), wood)                 # drawer
	_mesh_box(root, Vector3(0.22, 0.025, 0.03), Vector3(0, 0.27, wd * 0.5 + 0.01), brass)
	_mesh_box(root, Vector3(ww - 0.08, 0.02, wd - 0.06), Vector3(0, 0.45, 0), dark)                            # floor of the hanging space
	_mesh_box(root, Vector3(ww - 0.1, 0.02, 0.02), Vector3(0, 1.8, 0), brass)                                  # the rail
	# clothes on the rail: the gang's colours
	var cols := [Color8(220, 40, 40), Color8(40, 40, 46), Color8(240, 200, 60), Color8(60, 110, 200), Color8(150, 40, 160), Color8(235, 235, 235)]
	for k in cols.size():
		_mesh_box(root, Vector3(0.08, 0.9, 0.42), Vector3(-0.48 + k * 0.19, 1.33, 0), _mat(cols[k], 0.95))
	# the two doors, hinged at the sides
	var solid_front := _solid(Vector3(ww - 0.08, wh - 0.6, 0.02), Vector3(0, 0.45 + (wh - 0.55) * 0.5, wd * 0.5 - 0.04), dark, root)
	solid_front.get_child(0).visible = false           # (only to stop walking in; the doors are what shows)
	for sx in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(sx * (ww * 0.5 - 0.04), 0, wd * 0.5)
		root.add_child(hinge)
		_ward_doors.append(hinge)
		var dw := ww * 0.5 - 0.045
		_mesh_box(hinge, Vector3(dw, wh - 0.55, 0.03), Vector3(-sx * dw * 0.5, 0.45 + (wh - 0.55) * 0.5, 0.0), wood)
		_mesh_box(hinge, Vector3(dw - 0.12, wh - 0.8, 0.012), Vector3(-sx * dw * 0.5, 0.45 + (wh - 0.55) * 0.5, 0.018), dark)   # panel
		_mesh_box(hinge, Vector3(0.025, 0.2, 0.03), Vector3(-sx * (dw - 0.06), 1.1, 0.03), brass)

func _lights() -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.9, 0.75)
	l.light_energy = 1.3
	l.omni_range = 8.0
	l.shadow_enabled = true
	l.position = Vector3((X0 + X1) * 0.5, H - 0.15, (Z0 + Z1) * 0.5)
	add_child(l)
