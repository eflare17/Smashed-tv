class_name VoxelBody
extends Node3D
## A block character you can shoot holes in (the PC voxel arena test, PLAN.md 20 Oct): its own copy of every part's
## voxel grid, one skinned mesh, posed by VoxelAnim. A shot is traced into the part grids exactly (the ray turned
## into each bone's rest space, then stepped cell by cell), the cubes round the hit are removed, and only the parts
## that changed are meshed again, on a worker thread (VoxelArena's queue). Inside, the parts are flesh, with bone down
## the limbs and a skull round the head's middle, so a hole shows meat. Owned by the voxel session.

signal died(body: VoxelBody)

const FLESH := [Color8(150, 22, 28), Color8(120, 14, 20), Color8(176, 40, 44), Color8(98, 10, 16)]
const BONE := Color8(226, 220, 204)
const BRAIN := [Color8(218, 150, 162), Color8(196, 124, 140), Color8(232, 172, 180)]
static var _brain_ints := {}          # the brain colours as cell values (to count brain knocked out)
const LIMBS := ["arm", "forearm", "thigh", "shin"]

var model: VoxelModel
var key := ""
var vm := 0.025                       # metres a cube
var skeleton: Skeleton3D
var parts := {}                       # name -> {grid, origin: Vector3 (in cubes), bone: int, arrays, start: int, left: int, gone: bool, dirty: bool}
var alive := true
var yaw := 0.0
var speed := 0.0
var odo := 0.0                        # metres walked
const CRAWL_M := 0.4                  # metres one worm wave (bunch + reach) covers with no legs
var attack := 0.0
## Hit reaction (the owner, 20 Oct): seconds left staggering (no pushing forward), the shove (m/s, world), and how
## hard the last hit was (0..1, for the flinch).
var stagger := 0.0
var knock := Vector3.ZERO
var flinch := 0.0
var flinch_head := false
var push_through := 0.0               # seconds after a stagger when hits only nudge (so held fire can't pin them)
## Knocked flying (a bat, a hammer's slam): in the air at air_v, turning over backward at tumble_v (radians a
## second); landed, they lie down_t seconds, then take UP_T getting up. Dead ones fly too and just lie there.
var airborne := false
var air_v := Vector3.ZERO
var tumble := 0.0
var tumble_v := 0.0
var down_t := 0.0
var up_t := 0.0
const UP_T := 0.6
const DOWN_T := 1.3
## Top-down Jared: the weapon held (a VoxelAnim weapon pose: "", "blaster", "shotgun", "spud" ...) and its kick.
var weapon := ""
var recoil := 0.0

## Sent flying at v (m/s, world), turning over backward at spin radians a second.
func launch(v: Vector3, spin: float = 6.0) -> void:
	airborne = true
	air_v = v
	tumble = 0.0
	tumble_v = spin
	knock = Vector3.ZERO
	down_t = 0.0
	up_t = 0.0
	position.y = maxf(position.y, 0.02)

## In the air, lying where they landed, or getting up: not walking, not swinging.
func floored() -> bool:
	return airborne or down_t > 0.0 or up_t > 0.0

## A shot landed: shoved back along dir by how many cubes it knocked out, staggering a moment.
func hit_react(dir: Vector3, cubes: int, part: String) -> void:
	var heavy := 0.5 if key == "brute" else 1.0
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var through := push_through > 0.0 and stagger <= 0.0
	knock += flat * clampf(0.3 + cubes * 0.02, 0.3, 1.2) * heavy * (0.25 if through else 1.0)
	if knock.length() > 3.0:
		knock = knock.normalized() * 3.0
	flinch = minf(1.0, flinch + (0.2 if through else 0.5) + cubes * 0.01)
	flinch_head = part == "head"
	if not through and stagger <= 0.0:
		stagger = 0.3 + 0.15 * heavy
		push_through = stagger + 0.6

## Each physics step: the shove slides them back and fades; the stagger runs out; in the air they fly and fall.
func react_step(dt: float) -> void:
	if airborne:
		position += air_v * dt
		air_v.y -= 9.8 * dt
		tumble += tumble_v * dt
		if position.y <= 0.0 and air_v.y < 0.0:
			# down: a slide along the floor, then lying there a while
			position.y = 0.0
			airborne = false
			knock = Vector3(air_v.x, 0.0, air_v.z) * 0.35
			down_t = DOWN_T
			stagger = 0.0
	elif down_t > 0.0:
		down_t -= dt
		if down_t <= 0.0:
			down_t = 0.0
			up_t = UP_T
	elif up_t > 0.0:
		up_t = maxf(0.0, up_t - dt)
	position += knock * dt
	knock *= exp(-dt * 6.0)
	stagger = maxf(0.0, stagger - dt)
	push_through = maxf(0.0, push_through - dt)
	flinch = maxf(0.0, flinch - dt * 2.8)
var t := 0.0
var dead_t := 0.0
var height := 1.8
var radius := 0.5
## Health: shots take it by where they land (the head most) and how many cubes they knock out.
var hp := 100.0
## The brain: how many cubes of it there were, and how many are gone. A quarter gone kills (the owner, 20 Oct).
var brain_start := 0
var brain_lost := 0
const BRAIN_KILL := 0.25
const REF_VM := 0.023                 # the cube size health per cube is reckoned at (a grunt, one sprite pixel a cube)
const MIN_PIECE := 12                 # fewer cubes than this cut loose fly off as bits, not a piece
const BODY_TOUGH := 10.0              # body shots take this many times more cubes than before to kill
const PART_HITS := {"hand": 1, "forearm": 2, "shin": 2, "foot": 2, "arm": 3, "thigh": 3}
const PART_WEIGHT := {"head": 3.2, "torso": 1.2, "pelvis": 1.0}
## Can't die (VoxelArena's F6): shoot them to pieces.
static var immortal := false
var _mat: Material

static var _flesh_cache := {}         # "key|chunk" -> {part: grid with flesh inside}

## Sets it up from a voxel model (the enemy's key), cube size, and how many sprite pixels a cube (1 or 2).
func setup(key_: String, cube_m: float, chunk: int, mat: Material) -> void:
	key = key_
	model = VoxelModel.get_model(key)
	_mat = mat
	vm = cube_m
	var grids := _flesh_grids(model, key, chunk)
	# the rig's pivots are in the model's own voxels (one a sprite pixel): a pixel is cube_m / chunk metres
	model.voxel_m = cube_m / float(chunk)
	skeleton = model.make_skeleton()
	add_child(skeleton)
	var top := 0.0
	var shared := _shared_meshes(model, key, chunk, cube_m, grids)
	for n in model.parts_for(""):
		var p: Dictionary = model.parts[n]
		var g: Dictionary = grids[n]
		var o := Vector3(p.origin) / float(chunk)
		var b := int(p.bone)
		# each part a mesh of its own on its bone (its cubes placed from the bone's pivot)
		var att := BoneAttachment3D.new()
		att.bone_idx = b
		skeleton.add_child(att)
		var mi := MeshInstance3D.new()
		mi.material_override = mat
		mi.mesh = shared[n]
		att.add_child(mi)
		parts[n] = {"grid": {"size": g.size, "cells": g.cells}, "origin": o, "bone": b, "mesh": mi,
			"pivot": model.bone_pivot[b] * model.voxel_m, "start": int(shared[n].get_meta("count")),
			"left": int(shared[n].get_meta("count")), "gone": false, "dirty": false, "job": -1, "hits": 0}
		top = maxf(top, (o.y + (g.size as Vector3i).y) * cube_m)
		if n == "head":
			for c in (g.cells as PackedInt32Array):
				if _brain_ints.has(c):
					brain_start += 1
	height = top

## The pivot-relative origin (in cubes) a part is meshed from.
func mesh_origin(n: String) -> Vector3:
	var p: Dictionary = parts[n]
	return Vector3(p.origin) - (p.pivot as Vector3) / vm

# every fresh body of a kind shows the same meshes until it's shot
static var _shared := {}
static func _shared_meshes(md: VoxelModel, key_: String, chunk: int, cube_m: float, grids: Dictionary) -> Dictionary:
	var ck := "%s|%d|%.5f" % [key_, chunk, cube_m]
	if _shared.has(ck):
		return _shared[ck]
	var out := {}
	for n in md.parts_for(""):
		var p: Dictionary = md.parts[n]
		var g: Dictionary = grids[n]
		var o := Vector3(p.origin) / float(chunk) - md.bone_pivot[int(p.bone)] * md.voxel_m / cube_m
		var am := array_mesh(VoxMesher.mesh(g, o, cube_m))
		var cnt := 0
		for c in (g.cells as PackedInt32Array):
			if c != 0:
				cnt += 1
		am.set_meta("count", cnt)
		out[n] = am
	_shared[ck] = out
	return out

## Quads (VoxMesher.mesh's) as a mesh; null when there are none.
static func array_mesh(a: Dictionary) -> ArrayMesh:
	var am := ArrayMesh.new()
	if a.is_empty() or (a.verts as PackedVector3Array).is_empty():
		return am
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a.verts
	arr[Mesh.ARRAY_NORMAL] = a.normals
	arr[Mesh.ARRAY_COLOR] = a.colors
	arr[Mesh.ARRAY_INDEX] = a.indices
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

# the model's grids at this chunk size, with flesh (and bone) inside instead of the builder's dark fill
static func _flesh_grids(md: VoxelModel, key_: String, chunk: int) -> Dictionary:
	var ck := "%s|%d" % [key_, chunk]
	if _flesh_cache.has(ck):
		return _flesh_cache[ck]
	var out := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key_)
	for n in md.parts_for(""):
		var g := md.grid(n)
		if chunk > 1:
			g = VoxMesher.downsample(g)
		var s: Vector3i = g.size
		var cells: PackedInt32Array = (g.cells as PackedInt32Array).duplicate()
		var limb := false
		for l in LIMBS:
			if String(n).begins_with(l):
				limb = true
		# the head: a skull two cubes in, the brain inside it (or, in a head too small for both, all brain)
		var head_deep := 0
		if n == "head":
			for z in s.z:
				for y in s.y:
					for x in s.x:
						if cells[x + s.x * (y + s.y * z)] != 0:
							head_deep = maxi(head_deep, _depth(g, x, y, z))
		for z in s.z:
			for y in s.y:
				for x in s.x:
					var i := x + s.x * (y + s.y * z)
					if cells[i] == 0 or _surface(g, x, y, z):
						continue
					var c: Color = FLESH[rng.randi() % FLESH.size()]
					if limb and _near_axis(g, x, y, z, 1.3):
						c = BONE
					elif n == "head":
						var dp := _depth(g, x, y, z)
						if head_deep >= 3 and dp == 2:
							c = BONE                              # the skull
						else:
							c = BRAIN[rng.randi() % BRAIN.size()]
					cells[i] = ((c.r8 << 16) | (c.g8 << 8) | c.b8) + 1
		out[n] = {"size": s, "cells": cells}
	_flesh_cache[ck] = out
	if _brain_ints.is_empty():
		for c in BRAIN:
			_brain_ints[((c.r8 << 16) | (c.g8 << 8) | c.b8) + 1] = true
	return out

static func _filled(g: Dictionary, x: int, y: int, z: int) -> bool:
	var s: Vector3i = g.size
	if x < 0 or y < 0 or z < 0 or x >= s.x or y >= s.y or z >= s.z:
		return false
	return (g.cells as PackedInt32Array)[x + s.x * (y + s.y * z)] != 0

static func _surface(g: Dictionary, x: int, y: int, z: int) -> bool:
	return not (_filled(g, x + 1, y, z) and _filled(g, x - 1, y, z) and _filled(g, x, y + 1, z) and _filled(g, x, y - 1, z)
		and _filled(g, x, y, z + 1) and _filled(g, x, y, z - 1))

static func _depth(g: Dictionary, x: int, y: int, z: int) -> int:
	for d in range(1, 4):
		for o in [Vector3i(d, 0, 0), Vector3i(-d, 0, 0), Vector3i(0, d, 0), Vector3i(0, -d, 0), Vector3i(0, 0, d), Vector3i(0, 0, -d)]:
			if not _filled(g, x + o.x, y + o.y, z + o.z):
				return d
	return 4

static func _near_axis(g: Dictionary, x: int, y: int, z: int, r: float) -> bool:
	# the middle of this row of the part (across x and z)
	var s: Vector3i = g.size
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for zz in s.z:
		for xx in s.x:
			if (g.cells as PackedInt32Array)[xx + s.x * (y + s.y * zz)] != 0:
				sx += xx
				sz += zz
				n += 1
	if n == 0:
		return false
	return Vector2(x - sx / n, z - sz / n).length() <= r

# ---------------------------------------------------------------- meshes

## The parts waiting to be meshed again (VoxelArena hands them to worker threads).
func dirty_parts() -> Array:
	var out := []
	for n in parts:
		if parts[n].dirty and int(parts[n].job) < 0:
			out.append(n)
	return out

## A worker's result for a part: its mesh swapped in.
func set_part_arrays(n: String, arrays: Dictionary) -> void:
	if not parts.has(n):
		return
	var p: Dictionary = parts[n]
	p.job = -1
	(p.mesh as MeshInstance3D).mesh = array_mesh(arrays)

func triangles() -> int:
	var t := 0
	for n in parts:
		var m: Mesh = (parts[n].mesh as MeshInstance3D).mesh
		if m and m.get_surface_count() > 0:
			t += m.surface_get_array_index_len(0) / 3
	return t

# ---------------------------------------------------------------- moving

## Legs lost (0, 1 or 2): one off and they limp, both and they crawl on their arms.
func legs_lost() -> int:
	var n := 0
	for side in ["_l", "_r"]:
		for leg in ["thigh", "shin", "foot"]:
			# gone, or cut through (the sword took the rest of the leg below)
			if parts.has(leg + side) and (parts[leg + side].gone or (leg != "foot" and parts[leg + side].get("severed", false))):
				n += 1
				break
	return n

## How fast they can go now (1 whole, slower limping, slowest crawling).
func move_factor() -> float:
	var lost := legs_lost()
	if lost == 2:
		# a worm moves in pulses: the tail (the body's root) slides up fast as it bunches, and nearly stops as the
		# head reaches out ahead of it
		return 0.3 * (1.0 + 0.85 * sin(odo / CRAWL_M * TAU))
	return [1.0, 0.45][lost]

## Metres a whole walk cycle (two steps) covers, from the leg's length, so the feet keep up with the ground (a grunt's
## short legs take quick steps; VoxelAnim's cycle is Jared's sprites').
func cycle_m() -> float:
	var hip := model.bone("thigh_l")
	var ank := model.bone("foot_l")
	var leg := 0.9
	if hip >= 0 and ank >= 0:
		leg = (model.bone_pivot[hip].y - model.bone_pivot[ank].y) * model.voxel_m + 0.06
	return maxf(0.3, leg * 2.3)

func animate(dt: float, moving: bool) -> void:
	t += dt
	# the stride at full swing for this speed; odo in the cycle VoxelAnim counts (91 units)
	var anim_odo := odo / cycle_m() * VoxelAnim.CYCLE
	var p := VoxelAnim.pose({"t": t, "moving": moving, "speed": VoxelAnim.MAX_SPEED, "odo": anim_odo, "weapon": weapon, "recoil": recoil})
	var rot: Dictionary = p.rot
	if attack > 0.0:
		var k := sin(clampf(attack, 0.0, 1.0) * PI)
		rot["arm_r"] = Quaternion.from_euler(Vector3(-1.5 * k, 0.2, -0.1))
		rot["arm_l"] = Quaternion.from_euler(Vector3(-1.2 * k, -0.2, 0.1))
	elif moving and weapon == "":
		# arms swinging against the legs, elbows a little bent (no reaching forward)
		var ph := anim_odo / VoxelAnim.CYCLE * TAU
		rot["arm_r"] = Quaternion.from_euler(Vector3(-0.45 * sin(ph), 0, -0.12))
		rot["arm_l"] = Quaternion.from_euler(Vector3(0.45 * sin(ph), 0, 0.12))
		rot["forearm_r"] = Quaternion.from_euler(Vector3(-0.45, 0, 0))
		rot["forearm_l"] = Quaternion.from_euler(Vector3(-0.45, 0, 0))
	if flinch > 0.0 and alive:
		# knocked back: the chest and head thrown back, arms flung up, a stumbling step
		var f := smoothstep(0.0, 1.0, flinch)
		rot["chest"] = (rot.get("chest", Quaternion.IDENTITY) as Quaternion) * Quaternion.from_euler(Vector3(-0.45 * f, 0, 0))
		rot["head"] = Quaternion.from_euler(Vector3((-0.9 if flinch_head else -0.35) * f, 0, 0))
		rot["arm_r"] = (rot.get("arm_r", Quaternion.IDENTITY) as Quaternion) * Quaternion.from_euler(Vector3(-0.7 * f, 0, -0.4 * f))
		rot["arm_l"] = (rot.get("arm_l", Quaternion.IDENTITY) as Quaternion) * Quaternion.from_euler(Vector3(-0.7 * f, 0, 0.4 * f))
		rot["thigh_l"] = (rot.get("thigh_l", Quaternion.IDENTITY) as Quaternion) * Quaternion.from_euler(Vector3(0.35 * f, 0, 0))
		rot["shin_l"] = (rot.get("shin_l", Quaternion.IDENTITY) as Quaternion) * Quaternion.from_euler(Vector3(0.3 * f, 0, 0))
	var turn := Quaternion.IDENTITY
	var lift := Vector3(p.pos) * model.voxel_m
	var lost := legs_lost()
	var pivot := Vector3.ZERO
	if alive and lost == 2:
		# no legs: a worm on the floor. Each wave the middle humps up and the tail draws in (bunch), then the head
		# and arms stretch out forward and the hump flattens (reach); the body wiggles side to side as it goes.
		var hip_y: float = model.bone_pivot[maxi(0, model.bone("hips"))].y * model.voxel_m
		var w := odo / CRAWL_M * TAU
		var h := 0.5 - 0.5 * cos(w)        # 0 stretched flat .. 1 bunched up
		var sw := sin(w)                   # > 0 bunching, < 0 reaching
		pivot = Vector3(0, hip_y, 0)
		turn = Quaternion.from_euler(Vector3(PI / 2.0 * 0.95 - 0.95 * h, 0, 0))
		lift = Vector3(0, -hip_y + 0.12 - 0.05 * h, 0)
		rot = {"hips": Quaternion.from_euler(Vector3(0, 0, 0.25 * sw)),
			"chest": Quaternion.from_euler(Vector3(1.5 * h, 0, -0.4 * sw)),
			"head": Quaternion.from_euler(Vector3(-1.0 - 0.35 * h, 0, 0.3 * sw)),
			"arm_r": Quaternion.from_euler(Vector3(-2.7 + 0.9 * h, 0, -0.3 - 0.15 * sw)),
			"arm_l": Quaternion.from_euler(Vector3(-2.7 + 0.9 * h, 0, 0.3 - 0.15 * sw)),
			"forearm_r": Quaternion.from_euler(Vector3(-1.1 * h, 0, 0)),
			"forearm_l": Quaternion.from_euler(Vector3(-1.1 * h, 0, 0))}
	elif alive and lost == 1:
		# one leg: a hop and a lean onto the one left
		var side := 1.0 if (parts.has("thigh_l") and parts["thigh_l"].gone) or (parts.has("shin_l") and parts["shin_l"].gone) else -1.0
		turn = Quaternion.from_euler(Vector3(0.15, 0, -0.12 * side))
		lift.y += absf(sin(odo / 0.5 * PI)) * 0.06
	if airborne:
		# turning over backward about the middle, arms and legs flung out
		pivot = Vector3(0, height * 0.5, 0)
		turn = Quaternion.from_euler(Vector3(-tumble, 0, 0))
		lift = Vector3.ZERO
		rot = {"arm_r": Quaternion.from_euler(Vector3(-2.6, 0, -0.6)), "arm_l": Quaternion.from_euler(Vector3(-2.6, 0, 0.6)),
			"thigh_l": Quaternion.from_euler(Vector3(-0.7, 0, 0.2)), "thigh_r": Quaternion.from_euler(Vector3(-0.4, 0, -0.2)),
			"shin_l": Quaternion.from_euler(Vector3(0.9, 0, 0)), "shin_r": Quaternion.from_euler(Vector3(0.5, 0, 0)),
			"head": Quaternion.from_euler(Vector3(-0.5, 0, 0))}
	elif not alive:
		# toppled backward about the feet, over half a second
		var k2 := smoothstep(0.0, 0.55, dead_t)
		turn = Quaternion.from_euler(Vector3(-PI / 2.0 * k2, 0, 0))
		lift = Vector3(0, 0.12 * k2, 0)
		rot = {}
	elif down_t > 0.0 or up_t > 0.0:
		# flat on their back where they landed, then pushing back up
		var k3 := 1.0 if down_t > 0.0 else smoothstep(0.0, 1.0, up_t / UP_T)
		pivot = Vector3.ZERO
		turn = Quaternion.from_euler(Vector3(-PI / 2.0 * k3, 0, 0))
		lift = Vector3(0, 0.12 * k3, 0)
		rot = {"arm_r": Quaternion.from_euler(Vector3(-0.4 * k3, 0, -0.9 * k3)), "arm_l": Quaternion.from_euler(Vector3(-0.4 * k3, 0, 0.9 * k3)),
			"head": Quaternion.from_euler(Vector3(-0.3 * k3, 0, 0))}
	for i in model.bone_names.size():
		if model.bone_parent[i] >= 0:
			skeleton.set_bone_pose_rotation(i, rot.get(model.bone_names[i], Quaternion.IDENTITY))
	var r := maxi(0, model.bone("hips"))
	var face := Quaternion(Vector3.UP, yaw)
	var ph := model.bone_pivot[r] * model.voxel_m
	skeleton.set_bone_pose_position(r, face * (pivot + turn * (ph - pivot) + lift))
	skeleton.set_bone_pose_rotation(r, face * turn * (rot.get("hips", Quaternion.IDENTITY) as Quaternion))

# ---------------------------------------------------------------- shots

## The nearest cube a ray hits ({} if none): {dist (m), part, cell: Vector3i, point (world), normal (world)}.
func trace(from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	# a quick upright cylinder first
	var c := global_position
	var flat := Vector2(from.x - c.x, from.z - c.z)
	var d2 := Vector2(dir.x, dir.z)
	var reach := maxf(height, radius) + 0.4
	if d2.length_squared() > 0.000001:
		var tt := clampf(-flat.dot(d2) / d2.length_squared(), 0.0, max_d)
		if (flat + d2 * tt).length() > reach:
			return {}
	elif flat.length() > reach:
		return {}
	var best := {}
	var best_d := max_d
	var skel := skeleton.global_transform
	for n in parts:
		var p: Dictionary = parts[n]
		if p.gone or int(p.left) <= 0:
			continue
		var b: int = p.bone
		var bind := Transform3D(Basis.IDENTITY, -model.bone_pivot[b] * model.voxel_m)
		var m := skel * skeleton.get_bone_global_pose(b) * bind
		var inv := m.affine_inverse()
		var o: Vector3 = (inv * from) / vm - Vector3(p.origin)
		var dd: Vector3 = (inv.basis * dir).normalized()
		var h := _dda(p.grid, o, dd, best_d / vm)
		if h.is_empty():
			continue
		var dist: float = h.t * vm
		if dist < best_d:
			best_d = dist
			best = {"dist": dist, "part": n, "cell": h.cell, "point": from + dir * dist, "normal": (m.basis * Vector3(h.n)).normalized()}
	return best

# Amanatides & Woo: step through the grid's cells along the ray until a filled one
static func _dda(g: Dictionary, o: Vector3, d: Vector3, max_t: float) -> Dictionary:
	var s: Vector3i = g.size
	var cells: PackedInt32Array = g.cells
	var lo := Vector3.ZERO
	var hi := Vector3(s)
	# into the box
	var t0 := 0.0
	var t1 := max_t
	for a in 3:
		if absf(d[a]) < 0.000001:
			if o[a] < lo[a] or o[a] > hi[a]:
				return {}
		else:
			var ta := (lo[a] - o[a]) / d[a]
			var tb := (hi[a] - o[a]) / d[a]
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return {}
	var p := o + d * (t0 + 0.0001)
	var cell := Vector3i(clampi(floori(p.x), 0, s.x - 1), clampi(floori(p.y), 0, s.y - 1), clampi(floori(p.z), 0, s.z - 1))
	var step := Vector3i(1 if d.x > 0 else -1, 1 if d.y > 0 else -1, 1 if d.z > 0 else -1)
	var tmax := Vector3.ZERO
	var tdelta := Vector3.ZERO
	for a in 3:
		if absf(d[a]) < 0.000001:
			tmax[a] = INF
			tdelta[a] = INF
		else:
			var nb := float(cell[a] + (1 if d[a] > 0 else 0))
			tmax[a] = t0 + (nb - p[a]) / d[a]
			tdelta[a] = absf(1.0 / d[a])
	var n := Vector3i.ZERO
	# the face entered first: the box face, or the last step
	var tcur := t0
	for _i in (s.x + s.y + s.z) * 2:
		if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= s.x or cell.y >= s.y or cell.z >= s.z or tcur > t1:
			return {}
		if cells[cell.x + s.x * (cell.y + s.y * cell.z)] != 0:
			return {"t": tcur, "cell": cell, "n": n}
		if tmax.x < tmax.y and tmax.x < tmax.z:
			cell.x += step.x
			tcur = tmax.x
			tmax.x += tdelta.x
			n = Vector3i(-step.x, 0, 0)
		elif tmax.y < tmax.z:
			cell.y += step.y
			tcur = tmax.y
			tmax.y += tdelta.y
			n = Vector3i(0, -step.y, 0)
		else:
			cell.z += step.z
			tcur = tmax.z
			tmax.z += tdelta.z
			n = Vector3i(0, 0, -step.z)
	return {}

## Knocks out the cubes within r cubes of the hit (a round hole); returns the ones knocked out as
## [{pos: world, col: Color}] (for the flying bits) and whether that killed it or blew a limb off.
func damage(hit: Dictionary, r: float) -> Dictionary:
	var n: String = hit.part
	var p: Dictionary = parts[n]
	p.grid = {"size": p.grid.size, "cells": (p.grid.cells as PackedInt32Array).duplicate()}
	var g: Dictionary = p.grid
	var s: Vector3i = g.size
	var cells: PackedInt32Array = g.cells
	var c: Vector3i = hit.cell
	var out := []
	var ri := ceili(r)
	var b: int = p.bone
	var bind := Transform3D(Basis.IDENTITY, -model.bone_pivot[b] * model.voxel_m)
	var m := skeleton.global_transform * skeleton.get_bone_global_pose(b) * bind
	for z in range(c.z - ri, c.z + ri + 1):
		for y in range(c.y - ri, c.y + ri + 1):
			for x in range(c.x - ri, c.x + ri + 1):
				if x < 0 or y < 0 or z < 0 or x >= s.x or y >= s.y or z >= s.z:
					continue
				if Vector3(x - c.x, y - c.y, z - c.z).length() > r:
					continue
				var i := x + s.x * (y + s.y * z)
				var v := cells[i]
				if v == 0:
					continue
				cells[i] = 0
				p.left = int(p.left) - 1
				if _brain_ints.has(v):
					brain_lost += 1
				var k := v - 1
				out.append({"pos": m * ((Vector3(x, y, z) + Vector3(p.origin) + Vector3(0.5, 0.5, 0.5)) * vm),
					"col": Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)})
	p.dirty = true
	p.hits = int(p.get("hits", 0)) + 1
	var res := {"bits": out, "killed": false, "limb": ""}
	# a limb hit enough times comes off (and what hangs from it)
	var base := n.trim_suffix("_l").trim_suffix("_r")
	if PART_HITS.has(base) and int(p.hits) >= int(PART_HITS[base]) and not p.gone:
		res.limb = n
		res.bits.append_array(_blow(n))
	if alive:
		# limbs come off without killing; the chest and hips take ten times the cubes they used to; the head kills
		# only once a quarter of the brain is gone (the owner, 20 Oct)
		if base != "head":
			hp -= float(out.size()) * 1.4 * float(PART_WEIGHT.get(base, 0.0)) / BODY_TOUGH
		var brain_dead := brain_start > 0 and float(brain_lost) >= float(brain_start) * BRAIN_KILL
		if (hp <= 0.0 or brain_dead) and not immortal:
			res.killed = true
			alive = false
			died.emit(self)
	return res

# a part and the ones hanging from it: off, as flying bits (some of their cubes)
func _blow(n: String) -> Array:
	var out := []
	var chain := [n]
	var b0: int = parts[n].bone
	for m2 in parts:
		var bb: int = parts[m2].bone
		var pb := model.bone_parent[bb]
		while pb >= 0:
			if pb == b0:
				chain.append(m2)
				break
			pb = model.bone_parent[pb]
	for nn in chain:
		var p: Dictionary = parts[nn]
		if p.gone:
			continue
		var g: Dictionary = p.grid
		var s: Vector3i = g.size
		var cells: PackedInt32Array = (g.cells as PackedInt32Array).duplicate()
		var b: int = p.bone
		var bind := Transform3D(Basis.IDENTITY, -model.bone_pivot[b] * model.voxel_m)
		var m := skeleton.global_transform * skeleton.get_bone_global_pose(b) * bind
		var i := 0
		for z in s.z:
			for y in s.y:
				for x in s.x:
					var v := cells[i]
					if v != 0:
						if (i % 3) == 0:
							var k := v - 1
							out.append({"pos": m * ((Vector3(x, y, z) + Vector3(p.origin) + Vector3(0.5, 0.5, 0.5)) * vm),
								"col": Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)})
						cells[i] = 0
					i += 1
		g.cells = cells
		p.left = 0
		p.gone = true
		p.dirty = false
		(p.mesh as MeshInstance3D).visible = false
	return out

# ---------------------------------------------------------------- the sword

## A sword cut (the owner, 20 Oct): the blade sweeps the plane through eye with normal n. Cubes within half_t metres
## of it, no further than reach from eye and inside the swing's arc (cos_arc round fwd), are cut out; then whatever
## the cut left no longer joined to its part's joint comes off as a piece, with every part hanging from it.
## Returns {bits: [{pos, col}] (the cut-out cubes, for the flying bits), cut: int, parts: [cut part names],
## pieces: [{part, grid, origin, xform}] (the part's cells that came off, its mesh origin and its mesh's world
## transform now), killed: bool, head_off: bool}.
func slice(eye: Vector3, n: Vector3, fwd: Vector3, reach: float, cos_arc: float, half_t: float) -> Dictionary:
	return _remove({"plane": true, "eye": eye, "n": n, "fwd": fwd, "reach": reach, "cos_arc": cos_arc, "half_t": half_t})

## A blow that scoops out every cube within r metres of the segment a-b (a == b: a ball, a crater; long: a tunnel, a
## chainsaw's kerf); whatever is left no longer joined to its joint comes off, as with slice. hp_per_cube: the health
## each body (torso) cube taken costs; bits_every: one flying bit for every this many cubes taken. Returns what slice
## does.
func carve(a: Vector3, b: Vector3, r: float, hp_per_cube: float = 0.08, bits_every: int = 2) -> Dictionary:
	return _remove({"plane": false, "a": a, "b": b, "r": r, "hp_per_cube": hp_per_cube, "bits_every": maxi(1, bits_every)})

## Health off the body (a blunt blow, a burn); true if that killed it.
func hurt(amount: float) -> bool:
	if not alive:
		return false
	hp -= amount
	if hp <= 0.0 and not immortal:
		alive = false
		died.emit(self)
		return true
	return false

# slice and carve: the cubes a blade's plane or a capsule takes, then what's left hanging off, part by part
func _remove(opt: Dictionary) -> Dictionary:
	var plane: bool = opt.plane
	var eye: Vector3 = opt.get("eye", Vector3.ZERO)
	var n: Vector3 = opt.get("n", Vector3.UP)
	var fwd: Vector3 = opt.get("fwd", Vector3.FORWARD)
	var reach: float = opt.get("reach", 0.0)
	var cos_arc: float = opt.get("cos_arc", 0.0)
	var half_t: float = opt.get("half_t", 0.0)
	var ca: Vector3 = opt.get("a", Vector3.ZERO)
	var cb: Vector3 = opt.get("b", Vector3.ZERO)
	var cr: float = opt.get("r", 0.0)
	var every: int = opt.get("bits_every", 2)
	var res := {"bits": [], "cut": 0, "parts": [], "pieces": [], "killed": false, "head_off": false}
	var by_bone := {}
	for nm in parts:
		by_bone[int(parts[nm].bone)] = nm
	var names := parts.keys()
	names.sort_custom(func(a, b): return int(parts[a].bone) < int(parts[b].bone))
	var root: String = names[0]
	var stat := {}            # part -> PackedByteArray: 0 empty, 1 kept, 2 cut, 3 came off (this cut)
	var whole := {}           # part -> true: off whole (its joint went with its parent's piece)
	var quick := {}           # part -> [cut marks, its cells after]: cut the quick way (nothing came off it)
	var body_cut := 0
	var brain_hit := 0
	for nm in names:
		var p: Dictionary = parts[nm]
		if p.gone:
			continue
		var b: int = p.bone
		var g: Dictionary = p.grid
		var s: Vector3i = g.size
		var cells: PackedInt32Array = g.cells
		var bind := Transform3D(Basis.IDENTITY, -model.bone_pivot[b] * model.voxel_m)
		var att := skeleton.global_transform * skeleton.get_bone_global_pose(b)
		var m := att * bind
		var o := Vector3(p.origin)
		# off whole if the nearest part up the chain lost the cubes this one hangs from
		var pb := model.bone_parent[b]
		while pb >= 0 and not by_bone.has(pb):
			pb = model.bone_parent[pb]
		if pb >= 0:
			var par: String = by_bone[pb]
			if whole.has(par):
				whole[nm] = true
			elif quick.has(par):
				var qp: Dictionary = parts[par]
				var jq: Vector3 = model.bone_pivot[b] * model.voxel_m / vm - Vector3(qp.origin) - Vector3(0.5, 0.5, 0.5)
				if not _joint_kept(quick[par][1], quick[par][0], qp.grid.size, jq):
					whole[nm] = true
			elif stat.has(par):
				var pp: Dictionary = parts[par]
				var jt: Vector3 = model.bone_pivot[b] * model.voxel_m / vm - Vector3(pp.origin) - Vector3(0.5, 0.5, 0.5)
				var near := _near_cells(stat[par], pp.grid.size, jt, 1.5)
				var kept := false
				for i in near:
					if stat[par][i] == 1:
						kept = true
						break
				if not near.is_empty() and not kept:
					whole[nm] = true
		if whole.has(nm):
			var mesh: Mesh = (p.mesh as MeshInstance3D).mesh
			var bb := mesh.get_aabb() if mesh else AABB()
			res.pieces.append({"part": nm, "grid": {"size": s, "cells": cells}, "origin": mesh_origin(nm), "xform": att,
				"mesh": mesh, "box_at": bb.get_center(), "box": bb.size, "count": int(p.left)})
			if nm == "head":
				res.head_off = true
			p.grid = {"size": s, "cells": PackedInt32Array()}
			(p.grid.cells as PackedInt32Array).resize(cells.size())
			p.left = 0
			p.gone = true
			p.dirty = false
			(p.mesh as MeshInstance3D).visible = false
			res.parts.append(nm)
			continue
		var base := m * ((o + Vector3(0.5, 0.5, 0.5)) * vm)
		var ex := m.basis.x * vm
		var ey := m.basis.y * vm
		var ez := m.basis.z * vm
		var d0 := 0.0
		var dx := 0.0
		var dy := 0.0
		var dz := 0.0
		# st while cutting: 2 cut, 4 still joined (reached from the joint), 0 anything else
		var st := PackedByteArray()
		var ncut := 0
		var clo := Vector3i(s)                # the cut cells' box (in cells)
		var chi := Vector3i(-1, -1, -1)
		if not plane:
			st.resize(cells.size())
			var box := {}
			ncut = _mark_capsule(st, cells, s, base, Basis(ex, ey, ez), ca, cb, cr, box)
			if ncut > 0:
				clo = box.lo
				chi = box.hi
		else:
			# the cut: distance from the plane is linear in the cell, so step it
			d0 = n.dot(base - eye)
			dx = n.dot(ex)
			dy = n.dot(ey)
			dz = n.dot(ez)
			# quick out: the grid's corners all one side of the blade
			var lo := INF
			var hi := -INF
			for c in 8:
				var dc := d0 + dx * float((c & 1) * (s.x - 1)) + dy * float(((c >> 1) & 1) * (s.y - 1)) + dz * float(((c >> 2) & 1) * (s.z - 1))
				lo = minf(lo, dc)
				hi = maxf(hi, dc)
			if lo > half_t or hi < -half_t:
				continue
			st.resize(cells.size())
		for z in (s.z if plane else 0):
			for y in s.y:
				# only the stretch of the row the blade passes through
				var dyz := d0 + dy * y + dz * z
				var x0 := 0
				var x1 := s.x - 1
				if absf(dx) > 0.000001:
					var xa := (-half_t - dyz) / dx
					var xb := (half_t - dyz) / dx
					x0 = maxi(0, ceili(minf(xa, xb)))
					x1 = mini(s.x - 1, floori(maxf(xa, xb)))
				elif absf(dyz) > half_t:
					continue
				var row := s.x * (y + s.y * z)
				for x in range(x0, x1 + 1):
					if cells[row + x] != 0:
						var q := base + ex * x + ey * y + ez * z - eye
						var ql := q.length()
						if ql <= reach and q.dot(fwd) >= ql * cos_arc:
							st[row + x] = 2
							ncut += 1
							clo = Vector3i(mini(clo.x, x), mini(clo.y, y), mini(clo.z, z))
							chi = Vector3i(maxi(chi.x, x), maxi(chi.y, y), maxi(chi.z, z))
		if ncut == 0:
			continue
		p.grid = {"size": s, "cells": cells.duplicate()}
		cells = p.grid.cells
		# what stays is what's still joined to the joint (the root part's: the hips, where the legs hang); a joint
		# in the cut itself keeps the side toward its parent (the head cut at the neck comes off whole). The root
		# part (the body itself) never comes off whole: it keeps what's joined to its nearest cubes left.
		var jb := b if nm != root else 0
		var sk := skeleton.global_transform
		var jw: Vector3 = sk * skeleton.get_bone_global_pose(jb).origin
		var jp: Vector3 = model.bone_pivot[jb] * model.voxel_m / vm - o - Vector3(0.5, 0.5, 0.5)
		var keep_side := 0.0
		var keep_dir := Vector3.ZERO
		var joint_cut: bool = nm != root and (absf(n.dot(jw - eye)) <= half_t + vm if plane else _seg_dist(jw, ca, cb) <= cr + vm)
		var box_v := (chi.x - clo.x + 7) * (chi.y - clo.y + 7) * (chi.z - clo.z + 7)
		if not joint_cut and box_v * 5 < cells.size() * 2 and not _may_split(st, cells, s, clo, chi):
			# the cut can't have split the part (the cubes round it all still join up close by) and the joint is
			# whole: just take the cut cubes out, no fill over the whole part
			for z in range(clo.z, chi.z + 1):
				for y in range(clo.y, chi.y + 1):
					var row2 := s.x * (y + s.y * z)
					for x in range(clo.x, chi.x + 1):
						var i2 := row2 + x
						if st[i2] != 2:
							continue
						var v3 := cells[i2]
						if (i2 % every) == 0:
							var k5 := v3 - 1
							res.bits.append({"pos": base + ex * x + ey * y + ez * z, "col": Color8((k5 >> 16) & 255, (k5 >> 8) & 255, k5 & 255)})
						if _brain_ints.has(v3):
							brain_hit += 1
						cells[i2] = 0
			quick[nm] = [st, cells]
			res.cut += ncut
			res.parts.append(nm)
			if nm == "torso":
				body_cut += ncut
			p.left = int(p.left) - ncut
			if int(p.left) <= 0:
				p.left = 0
				p.gone = true
				(p.mesh as MeshInstance3D).visible = false
			else:
				p.dirty = true
			continue
		if joint_cut:
			var ref := jw + Vector3.DOWN
			if nm != root and model.bone_parent[b] >= 0:
				ref = sk * skeleton.get_bone_global_pose(model.bone_parent[b]).origin
			if plane:
				keep_side = signf(n.dot(ref - eye))
			else:
				keep_dir = ref - jw
		# (the joint in the cut: the cubes nearest it may be cut ones, and if none left is as near, it all comes off;
		# else the nearest ones left)
		var seed := _near_filled(cells, s, jp, 4.0 if joint_cut else 1.5, PackedByteArray() if joint_cut else st)
		var q2 := PackedInt32Array()
		for k in seed:
			if st[k] != 0:
				continue
			var kx0 := k % s.x
			var ky0 := (k / s.x) % s.y
			var kz0 := k / (s.x * s.y)
			if keep_side != 0.0 and signf(d0 + dx * kx0 + dy * ky0 + dz * kz0) != keep_side:
				continue
			if keep_dir != Vector3.ZERO and (base + ex * kx0 + ey * ky0 + ez * kz0 - jw).dot(keep_dir) <= 0.0:
				continue
			st[k] = 4
			q2.append(k)
		var head_i := 0
		var sx := s.x
		var sxy := s.x * s.y
		var nall := cells.size()
		while head_i < q2.size():
			var k: int = q2[head_i]
			head_i += 1
			var kx := k % sx
			var k2 := k - 1
			if kx > 0 and st[k2] == 0 and cells[k2] != 0:
				st[k2] = 4
				q2.append(k2)
			k2 = k + 1
			if kx < sx - 1 and st[k2] == 0 and cells[k2] != 0:
				st[k2] = 4
				q2.append(k2)
			var ky := (k / sx) % s.y
			k2 = k - sx
			if ky > 0 and st[k2] == 0 and cells[k2] != 0:
				st[k2] = 4
				q2.append(k2)
			k2 = k + sx
			if ky < s.y - 1 and st[k2] == 0 and cells[k2] != 0:
				st[k2] = 4
				q2.append(k2)
			k2 = k - sxy
			if k2 >= 0 and st[k2] == 0 and cells[k2] != 0:
				st[k2] = 4
				q2.append(k2)
			k2 = k + sxy
			if k2 < nall and st[k2] == 0 and cells[k2] != 0:
				st[k2] = 4
				q2.append(k2)
		# st after: 1 kept, 2 cut, 3 came off, 0 empty
		var off_cells := PackedInt32Array()
		off_cells.resize(cells.size())
		var noff := 0
		var nkept := q2.size()
		var olo := Vector3i(s)
		var ohi := Vector3i(-1, -1, -1)
		var i := 0
		for z in s.z:
			for y in s.y:
				for x in s.x:
					var v := cells[i]
					if v != 0:
						var sv := st[i]
						if sv == 4:
							st[i] = 1
						elif sv == 2:
							if (i % every) == 0:
								var k3 := v - 1
								res.bits.append({"pos": base + ex * x + ey * y + ez * z, "col": Color8((k3 >> 16) & 255, (k3 >> 8) & 255, k3 & 255)})
							if _brain_ints.has(v):
								brain_hit += 1
							cells[i] = 0
						else:
							st[i] = 3
							if _brain_ints.has(v):
								brain_hit += 1
							off_cells[i] = v
							cells[i] = 0
							noff += 1
							olo = Vector3i(mini(olo.x, x), mini(olo.y, y), mini(olo.z, z))
							ohi = Vector3i(maxi(ohi.x, x), maxi(ohi.y, y), maxi(ohi.z, z))
					i += 1
		stat[nm] = st
		res.cut += ncut
		res.parts.append(nm)
		if nm == "torso":
			body_cut += ncut
		if noff > 0 and noff < MIN_PIECE:
			# a few cubes left floating at the cut's edge: they fly off with the rest, no piece
			for j in off_cells.size():
				var v2 := off_cells[j]
				if v2 != 0:
					var k4 := v2 - 1
					res.bits.append({"pos": base + ex * (j % s.x) + ey * ((j / s.x) % s.y) + ez * (j / (s.x * s.y)),
						"col": Color8((k4 >> 16) & 255, (k4 >> 8) & 255, k4 & 255)})
			noff = 0
		if noff > 0:
			if noff * 4 > noff + nkept:
				p["severed"] = true     # a real chunk of it, not a sliver off the skin
			var mo := mesh_origin(nm)
			res.pieces.append({"part": nm, "grid": {"size": s, "cells": off_cells}, "origin": mo, "xform": att,
				"box_at": ((Vector3(olo) + Vector3(ohi) + Vector3.ONE) * 0.5 + mo) * vm, "box": (Vector3(ohi - olo) + Vector3.ONE) * vm, "count": noff})
		p.left = nkept
		if nkept == 0:
			p.gone = true
			(p.mesh as MeshInstance3D).visible = false
			if nm == "head":
				res.head_off = true
		else:
			p.dirty = true
	brain_lost += brain_hit
	if alive and not res.parts.is_empty():
		# a slash through the body takes a third of its health, a carve by the cubes it took; the head off (or a
		# quarter of the brain) kills
		if plane and body_cut > 6:
			hp -= 34.0
		elif not plane:
			# (a cube's worth by its size: twice the cube, eight times the health)
			hp -= float(body_cut) * float(opt.get("hp_per_cube", 0.08)) * pow(vm / REF_VM, 3.0)
		var brain_dead := brain_start > 0 and float(brain_lost) >= float(brain_start) * BRAIN_KILL
		if (hp <= 0.0 or brain_dead or res.head_off) and not immortal:
			res.killed = true
			alive = false
			died.emit(self)
	return res

# marks (st = 2) the filled cells whose middles are within r metres of the segment a-b; base, bs: a cell's middle in
# the world is base + bs * cell. Returns how many.
static func _mark_capsule(st: PackedByteArray, cells: PackedInt32Array, s: Vector3i, base: Vector3, bs: Basis, a: Vector3, b: Vector3, r: float, box: Dictionary) -> int:
	var inv := bs.inverse()
	var ac := inv * (a - base)
	var bc := inv * (b - base)
	var rc := r / bs.x.length()
	var lo := ac.min(bc) - Vector3.ONE * rc
	var hi := ac.max(bc) + Vector3.ONE * rc
	var x0 := maxi(0, ceili(lo.x))
	var y0 := maxi(0, ceili(lo.y))
	var z0 := maxi(0, ceili(lo.z))
	var x1 := mini(s.x - 1, floori(hi.x))
	var y1 := mini(s.y - 1, floori(hi.y))
	var z1 := mini(s.z - 1, floori(hi.z))
	if x0 > x1 or y0 > y1 or z0 > z1:
		return 0
	box["lo"] = Vector3i(x0, y0, z0)
	box["hi"] = Vector3i(x1, y1, z1)
	var ab := bc - ac
	var ab2 := maxf(ab.length_squared(), 0.000001)
	var r2 := rc * rc
	var n := 0
	for z in range(z0, z1 + 1):
		for y in range(y0, y1 + 1):
			var row := s.x * (y + s.y * z)
			for x in range(x0, x1 + 1):
				if cells[row + x] == 0:
					continue
				var pc := Vector3(x, y, z)
				var tt := clampf((pc - ac).dot(ab) / ab2, 0.0, 1.0)
				if (pc - (ac + ab * tt)).length_squared() <= r2:
					st[row + x] = 2
					n += 1
	return n

# could the cut cells (st = 2, all inside lo..hi) have split the part? No if the cubes left touching the cut all join
# up with each other within 3 cells of it: any path between two cubes left that went through the cut can then go round.
static func _may_split(st: PackedByteArray, cells: PackedInt32Array, s: Vector3i, lo: Vector3i, hi: Vector3i) -> bool:
	var x0 := maxi(0, lo.x - 3)
	var y0 := maxi(0, lo.y - 3)
	var z0 := maxi(0, lo.z - 3)
	var x1 := mini(s.x - 1, hi.x + 3)
	var y1 := mini(s.y - 1, hi.y + 3)
	var z1 := mini(s.z - 1, hi.z + 3)
	var sx := s.x
	var sxy := s.x * s.y
	var edge := PackedInt32Array()
	for z in range(z0, z1 + 1):
		for y in range(y0, y1 + 1):
			var row := sx * (y + s.y * z)
			for x in range(x0, x1 + 1):
				var i := row + x
				if cells[i] == 0 or st[i] == 2:
					continue
				if (x > 0 and st[i - 1] == 2) or (x < sx - 1 and st[i + 1] == 2) or (y > 0 and st[i - sx] == 2) \
						or (y < s.y - 1 and st[i + sx] == 2) or (z > 0 and st[i - sxy] == 2) or (z < s.z - 1 and st[i + sxy] == 2):
					edge.append(i)
	if edge.is_empty():
		return true
	var bw := x1 - x0 + 1
	var bh := y1 - y0 + 1
	var seen := PackedByteArray()
	seen.resize(bw * bh * (z1 - z0 + 1))
	var q := PackedInt32Array([edge[0]])
	seen[(edge[0] % sx - x0) + bw * ((edge[0] / sx) % s.y - y0 + bh * (edge[0] / sxy - z0))] = 1
	var h := 0
	while h < q.size():
		var k: int = q[h]
		h += 1
		var kx := k % sx
		var ky := (k / sx) % s.y
		var kz := k / sxy
		for d in 6:
			var nx := kx + (1 if d == 0 else (-1 if d == 1 else 0))
			var ny := ky + (1 if d == 2 else (-1 if d == 3 else 0))
			var nz := kz + (1 if d == 4 else (-1 if d == 5 else 0))
			if nx < x0 or nx > x1 or ny < y0 or ny > y1 or nz < z0 or nz > z1:
				continue
			var j := nx + sx * (ny + s.y * nz)
			if cells[j] == 0 or st[j] == 2:
				continue
			var lj := (nx - x0) + bw * (ny - y0 + bh * (nz - z0))
			if seen[lj] == 0:
				seen[lj] = 1
				q.append(j)
	for e in edge:
		if seen[(e % sx - x0) + bw * ((e / sx) % s.y - y0 + bh * (e / sxy - z0))] == 0:
			return true
	return false

# a part cut the quick way: are any of its cubes still there among the ones (before the cut) nearest pt, a child's joint?
static func _joint_kept(cells: PackedInt32Array, cut: PackedByteArray, s: Vector3i, pt: Vector3) -> bool:
	var st := PackedByteArray()
	st.resize(cells.size())
	for z in range(clampi(floori(pt.z) - 6, 0, s.z - 1), clampi(ceili(pt.z) + 6, 0, s.z - 1) + 1):
		for y in range(clampi(floori(pt.y) - 6, 0, s.y - 1), clampi(ceili(pt.y) + 6, 0, s.y - 1) + 1):
			var row := s.x * (y + s.y * z)
			for x in range(clampi(floori(pt.x) - 6, 0, s.x - 1), clampi(ceili(pt.x) + 6, 0, s.x - 1) + 1):
				if cells[row + x] != 0:
					st[row + x] = 1
				elif cut[row + x] == 2:
					st[row + x] = 2
	var near := _near_cells(st, s, pt, 1.5)
	if near.is_empty():
		return true
	for i in near:
		if st[i] == 1:
			return true
	return false

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * tt)

# the filled cells nearest pt (in cells; with a cut mask, only ones not cut, cut[i] != 2), and any within slack cells
# further than the nearest
static func _near_filled(cells: PackedInt32Array, s: Vector3i, pt: Vector3, slack: float, cut: PackedByteArray) -> PackedInt32Array:
	var st := PackedByteArray()
	st.resize(cells.size())
	var x0 := clampi(floori(pt.x) - 8, 0, s.x - 1)
	var x1 := clampi(ceili(pt.x) + 8, 0, s.x - 1)
	for z in range(clampi(floori(pt.z) - 8, 0, s.z - 1), clampi(ceili(pt.z) + 8, 0, s.z - 1) + 1):
		for y in range(clampi(floori(pt.y) - 8, 0, s.y - 1), clampi(ceili(pt.y) + 8, 0, s.y - 1) + 1):
			var row := s.x * (y + s.y * z)
			for x in range(x0, x1 + 1):
				if cells[row + x] != 0 and (cut.is_empty() or cut[row + x] != 2):
					st[row + x] = 1
	var out := _near_cells(st, s, pt, slack)
	if out.is_empty():
		for i in cells.size():
			st[i] = 1 if cells[i] != 0 and (cut.is_empty() or cut[i] != 2) else 0
		out = _near_cells(st, s, pt, slack)
	return out

# the filled cells (status > 0) nearest pt (in cells), and any within slack cells further than the nearest
static func _near_cells(st: PackedByteArray, s: Vector3i, pt: Vector3, slack: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for r in [6, 1000]:
		var x0 := clampi(floori(pt.x) - r, 0, s.x - 1)
		var x1 := clampi(ceili(pt.x) + r, 0, s.x - 1)
		var y0 := clampi(floori(pt.y) - r, 0, s.y - 1)
		var y1 := clampi(ceili(pt.y) + r, 0, s.y - 1)
		var z0 := clampi(floori(pt.z) - r, 0, s.z - 1)
		var z1 := clampi(ceili(pt.z) + r, 0, s.z - 1)
		var best := INF
		var found := []
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var i := x + s.x * (y + s.y * z)
					if st[i] == 0:
						continue
					var d := Vector3(x, y, z).distance_to(pt)
					if d <= best + slack:
						found.append([d, i])
						best = minf(best, d)
		for f in found:
			if f[0] <= best + slack:
				out.append(f[1])
		if not out.is_empty():
			return out
	return out
