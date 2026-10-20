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
var attack := 0.0
## Hit reaction (the owner, 20 Oct): seconds left staggering (no pushing forward), the shove (m/s, world), and how
## hard the last hit was (0..1, for the flinch).
var stagger := 0.0
var knock := Vector3.ZERO
var flinch := 0.0
var flinch_head := false
var push_through := 0.0               # seconds after a stagger when hits only nudge (so held fire can't pin them)

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

## Each physics step: the shove slides them back and fades; the stagger runs out.
func react_step(dt: float) -> void:
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
		for leg in ["thigh", "shin"]:
			if parts.has(leg + side) and parts[leg + side].gone:
				n += 1
				break
	return n

## How fast they can go now (1 whole, slower limping, slowest crawling).
func move_factor() -> float:
	return [1.0, 0.45, 0.3][legs_lost()]

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
	var p := VoxelAnim.pose({"t": t, "moving": moving, "speed": VoxelAnim.MAX_SPEED, "odo": anim_odo, "weapon": ""})
	var rot: Dictionary = p.rot
	if attack > 0.0:
		var k := sin(clampf(attack, 0.0, 1.0) * PI)
		rot["arm_r"] = Quaternion.from_euler(Vector3(-1.5 * k, 0.2, -0.1))
		rot["arm_l"] = Quaternion.from_euler(Vector3(-1.2 * k, -0.2, 0.1))
	elif moving:
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
		# no legs: face down on the floor, pulling along on the arms in turn
		var hip_y: float = model.bone_pivot[maxi(0, model.bone("hips"))].y * model.voxel_m
		pivot = Vector3(0, hip_y, 0)
		turn = Quaternion.from_euler(Vector3(PI / 2.0 * 0.92, 0, 0))
		lift = Vector3(0, -hip_y + 0.16, 0)
		var a := odo / 0.5 * TAU
		rot = {"head": Quaternion.from_euler(Vector3(-1.1, 0, 0)),
			"arm_r": Quaternion.from_euler(Vector3(-2.4 + 0.7 * sin(a), 0, -0.25)),
			"arm_l": Quaternion.from_euler(Vector3(-2.4 + 0.7 * sin(a + PI), 0, 0.25)),
			"forearm_r": Quaternion.from_euler(Vector3(-0.6 * maxf(0.0, cos(a)), 0, 0)),
			"forearm_l": Quaternion.from_euler(Vector3(-0.6 * maxf(0.0, cos(a + PI)), 0, 0))}
	elif alive and lost == 1:
		# one leg: a hop and a lean onto the one left
		var side := 1.0 if (parts.has("thigh_l") and parts["thigh_l"].gone) or (parts.has("shin_l") and parts["shin_l"].gone) else -1.0
		turn = Quaternion.from_euler(Vector3(0.15, 0, -0.12 * side))
		lift.y += absf(sin(odo / 0.5 * PI)) * 0.06
	if not alive:
		# toppled backward about the feet, over half a second
		var k2 := smoothstep(0.0, 0.55, dead_t)
		turn = Quaternion.from_euler(Vector3(-PI / 2.0 * k2, 0, 0))
		lift = Vector3(0, 0.12 * k2, 0)
		rot = {}
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
