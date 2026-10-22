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
var since_air := 9.0               # seconds since it last came down (a dead one is posed lying a moment after)
const UP_T := 0.6
const DOWN_T := 1.3
## Top-down Jared: the weapon held (a VoxelAnim weapon pose: "", "blaster", "shotgun", "spud" ...) and its kick.
var weapon := ""
var recoil := 0.0

## Sent flying at v (m/s, world), turning over backward at spin radians a second.
func launch(v: Vector3, spin: float = 6.0) -> void:
	if _net_block():
		return                   # (a guest: the host's snapshots move them)
	if frozen():
		_shatter_now(v)
		return
	if not airborne:
		tumble = 0.0             # hit again in the air: it keeps turning over from where it was
	airborne = true
	air_v = v
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
	if _net_block():
		return
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
			if frozen():
				_shatter_now(air_v)      # an ice statue hitting the floor breaks (it's posed as it froze: it can't lie there)
			knock = Vector3(air_v.x, 0.0, air_v.z) * 0.35
			down_t = DOWN_T
			stagger = 0.0
			since_air = 0.0
	elif down_t > 0.0:
		down_t -= dt
		if down_t <= 0.0:
			down_t = 0.0
			up_t = UP_T if legs_lost() < 2 else 0.0     # no legs to get up on: straight back to crawling
	elif up_t > 0.0:
		up_t = maxf(0.0, up_t - dt)
	since_air += dt
	position += knock * dt
	knock *= exp(-dt * 6.0)
	stagger = maxf(0.0, stagger - dt)
	push_through = maxf(0.0, push_through - dt)
	flinch = maxf(0.0, flinch - dt * 2.8)
var t := 0.0
var dead_t := 0.0
## A piece that came to rest, made a body again so it can be cut up like one (VoxelPieces): only the parts it had,
## each posed where the piece lay; never animated. Knocked flying, it's a piece again.
var fragment := false
var chunk_n := 1                      # sprite pixels a cube (setup's chunk)
var height := 1.8
var radius := 0.5
## Health: shots take it by where they land (the head most) and how many cubes they knock out.
var hp := 100.0
## The brain: how many cubes of it there were, and how many are gone. A quarter gone kills (the owner, 20 Oct).
var brain_start := 0
var brain_lost := 0
const BRAIN_KILL := 0.25
const REF_VM := 0.023                 # the cube size health per cube is reckoned at (a grunt, one sprite pixel a cube)
const LUMP_MAX := 2500                # a piece this big or smaller is split into its separate lumps (bigger: one, it's slow)
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
	chunk_n = chunk
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
		out[n] = {"size": s, "cells": _largest_lump(cells, s)}
	_flesh_cache[ck] = out
	if _brain_ints.is_empty():
		for c in BRAIN:
			_brain_ints[((c.r8 << 16) | (c.g8 << 8) | c.b8) + 1] = true
	return out

# a part's grid keeping only its biggest lump of touching cubes (a few drawn pixels stand loose of the rest: they'd
# fall off at the first cut anywhere on the part)
## (Lumps that touch the rest only at an edge or a corner, or up to two cubes away, are joined on first, the cubes between
## filled in, so they stay: they look attached.)
static func _largest_lump(cells: PackedInt32Array, s: Vector3i) -> PackedInt32Array:
	cells = cells.duplicate()
	for _pass in 3:
		var lumps := _lumps(cells, s, Vector3i.ZERO, s - Vector3i.ONE)
		if lumps.size() <= 1:
			return cells
		var best: Dictionary = lumps[0]
		for l in lumps:
			if int(l.n) > int(best.n):
				best = l
		var main := PackedByteArray()
		main.resize(cells.size())
		for j in (best.idx as PackedInt32Array):
			main[j] = 1
		var joined := false
		for l in lumps:
			if (l.idx as PackedInt32Array)[0] == (best.idx as PackedInt32Array)[0]:
				continue
			for j in (l.idx as PackedInt32Array):
				if _bridge(cells, main, s, j):
					joined = true
					break
		if not joined:
			return best.cells
	var last := _lumps(cells, s, Vector3i.ZERO, s - Vector3i.ONE)
	var keep: Dictionary = last[0]
	for l in last:
		if int(l.n) > int(keep.n):
			keep = l
	return keep.cells

# cell j (of a loose lump) next to the main lump (touching it at an edge or a corner, or up to two cubes away): fill the
# cells between with its colour so they touch face to face; true if it did
static func _bridge(cells: PackedInt32Array, main: PackedByteArray, s: Vector3i, j: int) -> bool:
	var x := j % s.x
	var y := (j / s.x) % s.y
	var z := j / (s.x * s.y)
	for reach in [1, 2, 3]:
		for dz in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					var nx: int = x + dx
					var ny: int = y + dy
					var nz: int = z + dz
					if maxi(absi(dx), maxi(absi(dy), absi(dz))) != reach or absi(dx) + absi(dy) + absi(dz) < 2:
						continue
					if nx < 0 or ny < 0 or nz < 0 or nx >= s.x or ny >= s.y or nz >= s.z or main[nx + s.x * (ny + s.y * nz)] == 0:
						continue
					# a cube at a time toward it, along x, then y, then z, filling the empty ones on the way
					var c := Vector3i(x, y, z)
					var to := Vector3i(nx, ny, nz)
					for ax in 3:
						while c[ax] != to[ax]:
							c[ax] += signi(to[ax] - c[ax])
							var k := c.x + s.x * (c.y + s.y * c.z)
							if c == to:
								break
							if cells[k] == 0:
								cells[k] = cells[j]
					return true
	return false

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
			# gone (a leg cut through has what's below taken off whole, so that counts)
			if parts.has(leg + side) and (parts[leg + side].gone or loose.has(leg + side)):
				n += 1                   # (a leg hanging by its skin is no leg to stand on: Stage 8)
				break
	return n

## How fast they can go now (1 whole, slower limping, slowest crawling).
func move_factor() -> float:
	var cold := 1.0 - 0.75 * clampf(frost, 0.0, 1.0)     # frosting over: slower and slower
	return _legs_factor() * cold

func _legs_factor() -> float:
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
	if fragment or frozen():
		_seams_step()                # (its torn ends kept, or made: a piece lying about)
		return                       # posed once where it lay / frozen solid as it stood
	# the stride at full swing for this speed; odo in the cycle VoxelAnim counts (91 units)
	var anim_odo := odo / cycle_m() * VoxelAnim.CYCLE
	var p := VoxelAnim.pose({"t": t, "moving": moving, "speed": VoxelAnim.MAX_SPEED, "odo": anim_odo, "weapon": weapon, "recoil": recoil})
	var rot: Dictionary = p.rot
	if panic_t > 0.0 and alive:
		# on fire: arms flung up and flailing, running about
		var fl := sin(t * 19.0)
		rot["arm_r"] = Quaternion.from_euler(Vector3(-2.6 + 0.6 * fl, 0, -0.5))
		rot["arm_l"] = Quaternion.from_euler(Vector3(-2.6 - 0.6 * fl, 0, 0.5))
		rot["head"] = Quaternion.from_euler(Vector3(-0.3, 0.4 * fl, 0))
	elif attack > 0.0:
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
		var side := -1.0
		for leg in ["thigh_l", "shin_l", "foot_l"]:
			if parts.has(leg) and (parts[leg].gone or loose.has(leg)):
				side = 1.0
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
		# (already on the floor, crawling or knocked down: lying at once, no getting up to fall)
		var k2 := 1.0 if (lost == 2 or down_t > 0.0 or up_t > 0.0 or since_air < 1.0) else smoothstep(0.0, 0.55, dead_t)
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
	_seams_step()
	_dangle_pose(dt)

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
	var n0 := Vector3i.ZERO           # the box face it came in through
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
			if ta > t0:
				t0 = ta
				n0 = Vector3i.ZERO
				n0[a] = -1 if d[a] > 0 else 1
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
	var n := n0
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

# damage()'s hole itself (damage() tells the co-op host about it first)
func _damage_x(hit: Dictionary, r: float) -> Dictionary:
	if frozen():
		return _shatter_res()
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

# ---------------------------------------------------------------- fire and ice

## Fire (the flamethrower): cubes set alight burn; each chars black after BURN_CHAR seconds, and crumbles to ash after
## BURN_ASH if the flame is still on it (fed by an ignite in the last FED_FOR seconds: Stage 6.5, "skin chars black
## first, then sustained flame crumbles charred voxels to ash, exposing bone"; not fed, it goes out, charred), taken
## out (what that leaves hanging falls off; the ash is lost), catching the cubes beside it as it goes (BURN_SPREAD a
## second each, far less away from the flame), never more than BURN_MAX at once. Bone doesn't burn. Alive and
## burning, they lose BURN_HURT a second and panic, running about with their arms flailing. Ice (the freeze ray): frost builds up (chill), slowing them; at 1 they're frozen
## solid for FREEZE_T seconds (blue-white, still as statues), and then any hit at all shatters them into ice cubes.
## status_step(dt) runs it all (the arena calls it every frame for a body with has_status()).
const BURN_CHAR := 0.8
const FED_FOR := 0.4             # seconds since the flame was last on a cube that still count as sustained
const FLAME_MORE := 300          # the flame's own cubes catch past BURN_MAX (the spreading can't crowd them out)
const SPREAD_OFF := 0.12         # a cube the flame isn't on spreads this much as fast (the fire dies down without it)
const BURN_ASH := 1.6
const BURN_SPREAD := 0.6
const BURN_MAX := 900
const BURN_HURT := 7.0
const BURN_TICK := 0.125         # seconds between fire steps
const CHAR := Color8(34, 26, 22)
## Burnt through: the ash falls off and is lost (VoxelDebris lets it crumble away; the vacuum gets nothing from it).
## Bone doesn't burn (Stage 6.5: "sustained flame crumbles charred voxels to ash, exposing bone").
const ASH := Color8(92, 88, 84)
const BONE_V := ((226 << 16) | (220 << 8) | 204) + 1     # (a bone cube's cell value: BONE's colour + 1)
const CHAR_V := ((34 << 16) | (26 << 8) | 22) + 1         # (a charred one's)
const ICE := Color8(176, 222, 255)
const FREEZE_T := 8.0
const FROST_FADE := 0.12        # frost a second lost when it isn't being kept up
## The arena's: what to do with the ice cubes when something shatters without a weapon there to throw them (a launch,
## a burn): func(body, bits).
static var on_shatter: Callable
var _burn := {}                 # part -> {cell index: seconds burning}
var _burn_n := 0
var _fed := {}                  # part -> {cell index: the fire clock when the flame was last on it}
var _fire_clock := 0.0
var _burn_tick := randf() * BURN_TICK     # (bodies set alight together still step on different frames)
const ASH_EVERY := 0.5          # seconds between taking the ash out (its connectivity cut fills the whole part)
var _ash := {}                  # part -> {cell index: true}: burnt to ash, waiting to be taken out
var _ash_t := randf() * ASH_EVERY
const ASH_FILL := 8              # (every 4 s a body: what burnt through drops off)
var _ash_n := randi() % ASH_FILL
var _orig := {}                 # part -> its cells' colours before fire or ice changed them (for the thaw)
var frost := 0.0
var frozen_t := 0.0
var panic_t := 0.0
var panic_dir := Vector3.FORWARD
var _panic_turn := 0.0

func burning() -> bool:
	return _burn_n > 0

func frozen() -> bool:
	return frozen_t > 0.0

func has_status() -> bool:
	return _burn_n > 0 or frost > 0.0 or frozen_t > 0.0 or panic_t > 0.0

## Sets it alight within r metres of at (world). Returns how many cubes caught.
func ignite(at: Vector3, r: float) -> int:
	if frozen() or _net_block():
		return 0                 # (a guest: fire burns in the host's game, its char and ash come as events)
	var n := 0
	for nm in parts:
		var p: Dictionary = parts[nm]
		if p.gone or _burn_n >= BURN_MAX:
			continue
		var b: int = p.bone
		var m := skeleton.global_transform * skeleton.get_bone_global_pose(b) * Transform3D(Basis.IDENTITY, -model.bone_pivot[b] * model.voxel_m)
		var base := m * ((Vector3(p.origin) + Vector3(0.5, 0.5, 0.5)) * vm)
		var st := PackedByteArray()
		var cells: PackedInt32Array = p.grid.cells
		st.resize(cells.size())
		var box := {}
		if _mark_capsule(st, cells, p.grid.size, base, Basis(m.basis.x * vm, m.basis.y * vm, m.basis.z * vm), at, at, r, box) == 0:
			continue
		var bd: Dictionary = _burn.get(nm, {})
		var fd: Dictionary = _fed.get(nm, {})
		var lo: Vector3i = box.lo
		var hi: Vector3i = box.hi
		var s: Vector3i = p.grid.size
		for z in range(lo.z, hi.z + 1):
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var i := x + s.x * (y + s.y * z)
					if st[i] != 2 or cells[i] == BONE_V:
						continue
					if bd.has(i):
						fd[i] = _fire_clock          # (alight already: the flame kept on it)
					elif _burn_n < BURN_MAX + FLAME_MORE:
						bd[i] = BURN_CHAR if cells[i] == CHAR_V else 0.0     # (charred already: on its way to ash)
						fd[i] = _fire_clock
						_burn_n += 1
						n += 1
		_burn[nm] = bd
		_fed[nm] = fd
	if n > 0 and alive:
		panic_t = maxf(panic_t, 1.0)
	return n

# chill() itself
func _chill_x(amount: float) -> bool:
	if frozen():
		return false
	frost = minf(1.0, frost + amount)
	if _burn_n > 0:
		_burn.clear()                # the cold puts the fire out (the ash not yet fallen stays, charred)
		_fed.clear()
		_burn_n = 0
		_ash.clear()
	if frost >= 1.0:
		_freeze()
		return true
	return false

func _freeze() -> void:
	frozen_t = FREEZE_T
	frost = 1.0
	panic_t = 0.0
	knock = Vector3.ZERO
	for nm in parts:
		var p: Dictionary = parts[nm]
		if p.gone:
			continue
		var cells: PackedInt32Array = (p.grid.cells as PackedInt32Array).duplicate()
		if not _orig.has(nm):
			_orig[nm] = cells.duplicate()
		for i in cells.size():
			var v := cells[i]
			if v != 0:
				var k := v - 1
				var c := Color8((k >> 16) & 255, (k >> 8) & 255, k & 255).lerp(ICE, 0.7)
				c = c.lightened(0.08 * float((i * 7) % 3))
				cells[i] = ((c.r8 << 16) | (c.g8 << 8) | c.b8) + 1
		p.grid = {"size": p.grid.size, "cells": cells}
		p.dirty = true

# thawed: the colours back on the cubes still there
func _thaw() -> void:
	_net_in("thaw", [])
	_net_depth -= 1
	frozen_t = 0.0
	frost = 0.0
	for nm in _orig:
		var p: Dictionary = parts[nm]
		if p.gone:
			continue
		var cells: PackedInt32Array = (p.grid.cells as PackedInt32Array).duplicate()
		var was: PackedInt32Array = _orig[nm]
		for i in cells.size():
			if cells[i] != 0 and was[i] != 0:
				cells[i] = was[i]
		p.grid = {"size": p.grid.size, "cells": cells}
		p.dirty = true
	_orig.clear()

## Shattered (frozen, then hit): every cube flies off as ice; returns what a cut would ({bits, cut, parts, pieces: [],
## killed, head_off, shattered: true}). Not frozen: nothing ({}).
func shatter() -> Dictionary:
	if not frozen():
		return {}
	if _net_block():
		return _no_cut()           # (a guest: the host's shatter comes as an event)
	_net_in("shatter", [Vector3.ZERO])
	var res := _shatter_res()
	_net_depth -= 1
	return res

func _shatter_res() -> Dictionary:
	var res := {"bits": [], "cut": 0, "parts": [], "pieces": [], "killed": false, "head_off": false, "shattered": true}
	if immortal:
		_thaw()                      # (can't die: the ice just breaks off)
		return res
	var total := cubes_left()
	var every := maxi(1, total / 2500)
	var j := 0
	for nm in parts:
		var p: Dictionary = parts[nm]
		if p.gone:
			continue
		var b: int = p.bone
		var m := skeleton.global_transform * skeleton.get_bone_global_pose(b) * Transform3D(Basis.IDENTITY, -model.bone_pivot[b] * model.voxel_m)
		var s: Vector3i = p.grid.size
		var cells: PackedInt32Array = p.grid.cells
		var o: Vector3 = p.origin
		var i := 0
		for z in s.z:
			for y in s.y:
				for x in s.x:
					var v := cells[i]
					if v != 0:
						if j % every == 0:
							var k := v - 1
							res.bits.append({"pos": m * ((Vector3(x, y, z) + o + Vector3(0.5, 0.5, 0.5)) * vm), "col": Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)})
						j += 1
					i += 1
		var empty := PackedInt32Array()
		empty.resize(cells.size())
		p.grid = {"size": s, "cells": empty}
		p.left = 0
		p.gone = true
		p.dirty = false
		(p.mesh as MeshInstance3D).visible = false
		res.parts.append(nm)
	res.cut = total
	frozen_t = 0.0
	frost = 0.0
	_orig.clear()
	if alive:
		alive = false
		res.killed = true
		res.head_off = true
		died.emit(self)
	return res

# shattered by something with no cut to hand the cubes back through (a launch, a blow's health): the arena throws them
func _shatter_now(dir: Vector3) -> bool:
	_net_in("shatter", [dir])
	var res := _shatter_res()
	_net_depth -= 1
	if on_shatter.is_valid() and not (res.bits as Array).is_empty():
		on_shatter.call(self, res.bits, dir)
	return bool(res.killed)

## Knocks out the cubes within r cubes of the hit (a round hole); returns the ones knocked out as
## [{pos: world, col: Color}] (for the flying bits) and whether that killed it or blew a limb off.
func damage(hit: Dictionary, r: float) -> Dictionary:
	if _net_block():
		return _no_cut()
	_net_in("damage", [hit, r])
	var res := _damage_x(hit, r)
	_net_depth -= 1
	return res

## A part and everything hanging from it taken off whole (a harpoon's yank): {pieces (VoxelPieces.spawn's list),
## parts, killed}. Nothing if it's gone already.
func sever(part: String) -> Dictionary:
	if _net_block():
		return _no_cut()
	_net_in("sever", [part])
	var res := _sever_x(part)
	_net_depth -= 1
	return res

## Frost building up (amount: a share of frozen solid). True if that froze them solid.
func chill(amount: float) -> bool:
	if _net_block():
		return false
	# (told only when it freezes them: a guest's frost comes from the snapshots, near enough for the look but not
	# for deciding)
	_net_depth += 1
	var froze := _chill_x(amount)
	_net_depth -= 1
	if froze:
		_net_in("freeze", [])
		_net_depth -= 1
	return froze

## Health off the body (a blunt blow, a burn); true if that killed it.
func hurt(amount: float) -> bool:
	if _net_block():
		return false
	_net_in("hurt", [amount])
	var res := _hurt_x(amount)
	_net_depth -= 1
	return res

## Every frame for a body with has_status(): the fire spreading and eating, the frost fading, the thaw, the panic.
## Returns {flames: [world points burning, for VoxelFlames], removed: a cut result of the cubes burnt to ash (or {})}.
## ash_ok false holds the ash back a frame (taking it out costs a fill over the part: the arena lets one body a frame).
func status_step(dt: float, ash_ok: bool = true) -> Dictionary:
	var out := {"flames": [], "removed": {}}
	if frozen():
		frozen_t -= dt
		if frozen_t <= 0.0:
			_thaw()
		return out
	if frost > 0.0:
		frost = maxf(0.0, frost - FROST_FADE * dt)
	if panic_t > 0.0:
		panic_t = maxf(0.0, panic_t - dt)
		_panic_turn -= dt
		if _panic_turn <= 0.0:
			_panic_turn = randf_range(0.35, 0.8)
			var a := randf() * TAU
			panic_dir = Vector3(cos(a), 0, sin(a))
	if _burn_n == 0:
		return out
	_burn_tick += dt
	if _burn_tick < BURN_TICK:
		return out
	var step := _burn_tick
	_burn_tick = 0.0
	_fire_clock += step
	var ash := {}
	var flames := []
	var catch := []                   # [part, index] catching this step
	var charred := {}                 # part -> the cubes charred this step (told to a co-op guest)
	for nm in _burn.keys():
		var p: Dictionary = parts[nm]
		var bd: Dictionary = _burn[nm]
		if p.gone:
			_burn_n -= bd.size()
			_burn.erase(nm)
			_fed.erase(nm)
			continue
		var fd: Dictionary = _fed.get(nm, {})
		var s: Vector3i = p.grid.size
		var cells: PackedInt32Array = p.grid.cells
		var recol := false
		var gone := PackedInt32Array()
		var b: int = p.bone
		var m := skeleton.global_transform * skeleton.get_bone_global_pose(b) * Transform3D(Basis.IDENTITY, -model.bone_pivot[b] * model.voxel_m)
		var o: Vector3 = p.origin
		for i in bd.keys():
			if cells[i] == 0 or cells[i] == BONE_V:
				bd.erase(i)
				fd.erase(i)
				_burn_n -= 1
				continue
			var t0: float = bd[i]
			var t1 := t0 + step
			bd[i] = t1
			var fed_now := _fire_clock - float(fd.get(i, -INF)) <= FED_FOR
			if t0 < BURN_CHAR and t1 >= BURN_CHAR:
				if not recol:
					cells = cells.duplicate()
					recol = true
				cells[i] = ((CHAR.r8 << 16) | (CHAR.g8 << 8) | CHAR.b8) + 1     # (for good: the thaw keeps it)
				if net_rec.is_valid():
					var ch: PackedInt32Array = charred.get(nm, PackedInt32Array())
					ch.append(i)
					charred[nm] = ch          # (a packed array out of a dictionary is a copy: put it back)
			if t1 >= BURN_ASH:
				if fed_now:
					gone.append(i)            # (the flame still on it: ash)
				bd.erase(i)                   # (else it goes out, charred)
				fd.erase(i)
				_burn_n -= 1
				continue
			# catching the cubes beside it
			if randf() < BURN_SPREAD * step * (6.0 if fed_now else 6.0 * SPREAD_OFF):
				var dr := randi() % 6
				var cx: int = i % s.x
				var cy: int = (i / s.x) % s.y
				var cz: int = i / (s.x * s.y)
				if [cx < s.x - 1, cx > 0, cy < s.y - 1, cy > 0, cz < s.z - 1, cz > 0][dr]:     # (not round the grid's edge)
					catch.append([nm, i + [1, -1, s.x, -s.x, s.x * s.y, -s.x * s.y][dr]])
			if flames.size() < 14 and randf() < 0.25:
				flames.append(m * ((Vector3(i % s.x, (i / s.x) % s.y, i / (s.x * s.y)) + o + Vector3(0.5, 0.5, 0.5)) * vm))
		if recol:
			p.grid = {"size": s, "cells": cells}
			p.dirty = true
		if not gone.is_empty():
			var pend: Dictionary = _ash.get(nm, {})
			for gi in gone:
				pend[gi] = true
			_ash[nm] = pend
		if bd.is_empty():
			_burn.erase(nm)
	for c in catch:
		if _burn_n >= BURN_MAX:
			break
		var p2: Dictionary = parts[c[0]]
		var cells2: PackedInt32Array = p2.grid.cells
		var i2: int = c[1]
		# (bone doesn't burn; charred, it's had its fire: only the flame itself takes it to ash)
		if i2 < 0 or i2 >= cells2.size() or cells2[i2] == 0 or cells2[i2] == BONE_V or cells2[i2] == CHAR_V or (_ash.has(c[0]) and (_ash[c[0]] as Dictionary).has(i2)):
			continue
		var bd2: Dictionary = _burn.get(c[0], {})
		if not bd2.has(i2):
			bd2[i2] = 0.0
			_burn[c[0]] = bd2
			_burn_n += 1
	out.flames = flames
	if alive:
		panic_t = maxf(panic_t, 0.6)
		_net_depth += 1                # (the burn's health goes to a guest in the snapshots, not as events)
		hurt(BURN_HURT * step)
		_net_depth -= 1
	_ash_t += step
	# (ash_ok false: not this frame, another body took its ash out; the last of a fire always goes)
	if not _ash.is_empty() and (_ash_t >= ASH_EVERY or _burn_n == 0) and (ash_ok or _burn_n == 0):
		_ash_t = 0.0
		for nm2 in _ash:
			ash[nm2] = PackedInt32Array((_ash[nm2] as Dictionary).keys())
		_ash.clear()
		# the fill over the whole part (what's burnt through drops off) only every ASH_FILL-th time and at the end:
		# it costs 10-25 ms; in between the ash cubes just go
		_ash_n += 1
		var quick := _ash_n % ASH_FILL != 0 and _burn_n > 0
		if net_rec.is_valid():
			net_rec.call(self, "burn", [charred, ash, quick], [])
			charred = {}
		var r := _remove({"plane": false, "mask": ash, "bits_every": 3, "quick": quick})
		for bt in r.bits:
			bt.col = ASH                                  # (crumbles away: lost)
		out.removed = r
	if not charred.is_empty():
		net_rec.call(self, "burn", [charred, {}, false], [])
	return out

# sever() itself
func _sever_x(part: String) -> Dictionary:
	var res := {"bits": [], "cut": 0, "parts": [], "pieces": [], "killed": false, "head_off": false}
	if not parts.has(part) or parts[part].gone:
		return res
	if frozen():
		return _shatter_res()
	var b0: int = parts[part].bone
	for nm in parts:
		var p: Dictionary = parts[nm]
		if p.gone:
			continue
		var bb: int = p.bone
		var hangs := bb == b0
		var pb := model.bone_parent[bb]
		while not hangs and pb >= 0:
			hangs = pb == b0
			pb = model.bone_parent[pb]
		if not hangs:
			continue
		var cells: PackedInt32Array = p.grid.cells
		var s: Vector3i = p.grid.size
		var att := skeleton.global_transform * skeleton.get_bone_global_pose(bb)
		var mesh: Mesh = (p.mesh as MeshInstance3D).mesh
		var bbx := mesh.get_aabb() if mesh else AABB()
		res.pieces.append({"part": nm, "grid": {"size": s, "cells": cells}, "origin": mesh_origin(nm), "xform": att,
			"mesh": mesh if not p.dirty and int(p.job) < 0 else null, "box_at": bbx.get_center(), "box": bbx.size, "count": int(p.left),
			"seam": nm == part, "limb": _is_limb(nm)})
		var empty := PackedInt32Array()
		empty.resize(cells.size())
		p.grid = {"size": s, "cells": empty}
		p.left = 0
		p.gone = true
		p.dirty = false
		(p.mesh as MeshInstance3D).visible = false
		res.parts.append(nm)
		if nm == "head":
			res.head_off = true
	if alive and res.head_off and not immortal:
		res.killed = true
		alive = false
		died.emit(self)
	_update_loose()
	_seams_step()
	return res

# ---------------------------------------------------------------- lying pieces made bodies again

## Becomes a fragment: dead, only the parts in grids ({part: {cells, mesh (or null)}}) kept, each part's mesh placed at
## xforms[part] (world: where its BoneAttachment would be), the rest gone.
func make_fragment(grids: Dictionary, xforms: Dictionary) -> void:
	fragment = true
	alive = false
	dead_t = 99.0
	brain_start = 0
	var skel_inv := skeleton.global_transform.affine_inverse()
	for n in parts:
		var p: Dictionary = parts[n]
		var mi: MeshInstance3D = p.mesh
		p.job = -1
		if not grids.has(n):
			var empty := PackedInt32Array()
			empty.resize((p.grid.cells as PackedInt32Array).size())
			p.grid = {"size": p.grid.size, "cells": empty}
			p.left = 0
			p.gone = true
			p.dirty = false
			mi.visible = false
			continue
		var g: Dictionary = grids[n]
		var cells: PackedInt32Array = g.cells
		var left := 0
		for v in cells:
			if v != 0:
				left += 1
		p.grid = {"size": p.grid.size, "cells": cells}
		p.left = left
		p.gone = left == 0
		mi.visible = left > 0
		if g.get("mesh") != null:
			mi.mesh = g.mesh
			p.dirty = false
		else:
			p.dirty = left > 0
	# each part's bone set so its mesh lands where the piece's did (parents first: the bones are in that order)
	for i in model.bone_names.size():
		var n2: String = ""
		for n in parts:
			if int(parts[n].bone) == i:
				n2 = n
		if n2 != "" and xforms.has(n2):
			skeleton.set_bone_global_pose(i, skel_inv * (xforms[n2] as Transform3D))
	_seams_step()                    # (its torn end, lying there)

## Cubes still on it.
func cubes_left() -> int:
	var n := 0
	for k in parts:
		if not parts[k].gone:
			n += int(parts[k].left)
	return n

## Its cubes where they are now: [{pos, col}]; with most > 0 only about that many, spread through it, the rest counted
## into counts (cell value -> how many). (The vacuum taking a body.)
func cubes(most: int = 0, counts: Dictionary = {}) -> Array:
	var bits := []
	var every := maxi(1, ceili(float(cubes_left()) / float(most))) if most > 0 else 1
	var seen := 0
	for n in parts:
		var p: Dictionary = parts[n]
		if p.gone:
			continue
		var b: int = p.bone
		var m := skeleton.global_transform * skeleton.get_bone_global_pose(b) * Transform3D(Basis.IDENTITY, -model.bone_pivot[b] * model.voxel_m)
		var s: Vector3i = p.grid.size
		var cells: PackedInt32Array = p.grid.cells
		var o: Vector3 = p.origin
		var j := 0
		for z in s.z:
			for y in s.y:
				for x in s.x:
					var v := cells[j]
					if v != 0:
						if seen % every == 0:
							var k := v - 1
							bits.append({"pos": m * ((Vector3(x, y, z) + o + Vector3(0.5, 0.5, 0.5)) * vm),
								"col": Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)})
						else:
							counts[v] = int(counts.get(v, 0)) + 1
						seen += 1
					j += 1
	return bits

## What it's made of as pieces (VoxelPieces.spawn's list): each part left, where it is now.
func as_pieces() -> Array:
	var out := []
	for n in parts:
		var p: Dictionary = parts[n]
		if p.gone or int(p.left) <= 0:
			continue
		var b: int = p.bone
		var att := skeleton.global_transform * skeleton.get_bone_global_pose(b)
		var mesh: Mesh = (p.mesh as MeshInstance3D).mesh
		var lo := Vector3i(p.grid.size)
		var hi := Vector3i(-1, -1, -1)
		var s: Vector3i = p.grid.size
		var cells: PackedInt32Array = p.grid.cells
		var j := 0
		for z in s.z:
			for y in s.y:
				for x in s.x:
					if cells[j] != 0:
						lo = Vector3i(mini(lo.x, x), mini(lo.y, y), mini(lo.z, z))
						hi = Vector3i(maxi(hi.x, x), maxi(hi.y, y), maxi(hi.z, z))
					j += 1
		var mo := mesh_origin(n)
		out.append({"part": n, "grid": {"size": s, "cells": cells}, "origin": mo, "xform": att,
			"mesh": mesh if not p.dirty and int(p.job) < 0 else null,
			"box_at": ((Vector3(lo) + Vector3(hi) + Vector3.ONE) * 0.5 + mo) * vm, "box": (Vector3(hi - lo) + Vector3.ONE) * vm,
			"count": int(p.left)})
	return out

# ---------------------------------------------------------------- the sword

## A sword cut (the owner, 20 Oct): the blade sweeps the plane through eye with normal n. Cubes within half_t metres
## of it, no further than reach from eye and inside the swing's arc (cos_arc round fwd), are cut out; then whatever
## the cut left no longer joined to its part's joint comes off as a piece, with every part hanging from it.
## Returns {bits: [{pos, col}] (the cut-out cubes, for the flying bits), cut: int, parts: [cut part names],
## pieces: [{part, grid, origin, xform}] (the part's cells that came off, its mesh origin and its mesh's world
## transform now), killed: bool, head_off: bool}.
func slice(eye: Vector3, n: Vector3, fwd: Vector3, reach: float, cos_arc: float, half_t: float) -> Dictionary:
	if _net_block():
		return _no_cut()
	_net_in("slice", [eye, n, fwd, reach, cos_arc, half_t])
	var res := _remove({"plane": true, "eye": eye, "n": n, "fwd": fwd, "reach": reach, "cos_arc": cos_arc, "half_t": half_t})
	_net_depth -= 1
	return res

## A blow that scoops out every cube within r metres of the segment a-b (a == b: a ball, a crater; long: a tunnel, a
## chainsaw's kerf); whatever is left no longer joined to its joint comes off, as with slice. hp_per_cube: the health
## each body (torso) cube taken costs; bits_every: one flying bit for every this many cubes taken. Returns what slice
## does.
func carve(a: Vector3, b: Vector3, r: float, hp_per_cube: float = 0.08, bits_every: int = 2) -> Dictionary:
	if _net_block():
		return _no_cut()
	_net_in("carve", [a, b, r, hp_per_cube, bits_every])
	var res := _remove({"plane": false, "a": a, "b": b, "r": r, "hp_per_cube": hp_per_cube, "bits_every": maxi(1, bits_every)})
	_net_depth -= 1
	return res

# hurt() itself
func _hurt_x(amount: float) -> bool:
	if frozen():
		return _shatter_now(Vector3.UP)
	if not alive:
		return false
	hp -= amount
	if hp <= 0.0 and not immortal:
		alive = false
		died.emit(self)
		return true
	return false

# a 6-neighbour fill from q over the uncut cubes (st 0), marking them mark
static func _flood(q: PackedInt32Array, st: PackedByteArray, cells: PackedInt32Array, s: Vector3i, mark: int) -> void:
	var sx := s.x
	var sxy := s.x * s.y
	var nall := cells.size()
	var h := 0
	while h < q.size():
		var k: int = q[h]
		h += 1
		var kx := k % sx
		var ky := (k / sx) % s.y
		if kx > 0 and st[k - 1] == 0 and cells[k - 1] != 0:
			st[k - 1] = mark
			q.append(k - 1)
		if kx < sx - 1 and st[k + 1] == 0 and cells[k + 1] != 0:
			st[k + 1] = mark
			q.append(k + 1)
		if ky > 0 and st[k - sx] == 0 and cells[k - sx] != 0:
			st[k - sx] = mark
			q.append(k - sx)
		if ky < s.y - 1 and st[k + sx] == 0 and cells[k + sx] != 0:
			st[k + sx] = mark
			q.append(k + sx)
		if k - sxy >= 0 and st[k - sxy] == 0 and cells[k - sxy] != 0:
			st[k - sxy] = mark
			q.append(k - sxy)
		if k + sxy < nall and st[k + sxy] == 0 and cells[k + sxy] != 0:
			st[k + sxy] = mark
			q.append(k + sxy)

# the cut cubes (st 2, in the box clo..chi) taken out of part p, nothing else coming off: their bits into res (every
# every-th), res.cut and p.left counted; returns how many were brain
func _take_cut(p: Dictionary, st: PackedByteArray, cells: PackedInt32Array, s: Vector3i, clo: Vector3i, chi: Vector3i,
		base: Vector3, ex: Vector3, ey: Vector3, ez: Vector3, every: int, res: Dictionary, ncut: int,
		idx := PackedInt32Array()) -> int:
	var brain := 0
	if not idx.is_empty():
		# the cells to take are known (fire's ash, scattered over the part): just those, not the box round them
		for i2 in idx:
			if i2 < 0 or i2 >= cells.size() or st[i2] != 2 or cells[i2] == 0:
				continue
			var v4 := cells[i2]
			if (i2 % every) == 0:
				var k6 := v4 - 1
				res.bits.append({"pos": base + ex * (i2 % s.x) + ey * ((i2 / s.x) % s.y) + ez * (i2 / (s.x * s.y)),
					"col": Color8((k6 >> 16) & 255, (k6 >> 8) & 255, k6 & 255)})
			if _brain_ints.has(v4):
				brain += 1
			cells[i2] = 0
		clo = chi + Vector3i.ONE                # (the box loop below does nothing)
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
					brain += 1
				cells[i2] = 0
	res.cut += ncut
	p.left = int(p.left) - ncut
	if int(p.left) <= 0:
		p.left = 0
		p.gone = true
		(p.mesh as MeshInstance3D).visible = false
	else:
		p.dirty = true
	return brain

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
	var mask: Dictionary = opt.get("mask", {})          # part -> cell indices to take (fire's ash): no shape
	var masked := not mask.is_empty()
	var quick_only: bool = opt.get("quick", false)        # just take the cubes out, no fill (fire's ash, mostly)
	var res := {"bits": [], "cut": 0, "parts": [], "pieces": [], "killed": false, "head_off": false}
	if frozen():
		return _shatter_res()
	var was_hanging := _dangle.keys()
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
		var par := _parent_part(nm, by_bone, root)
		if par != "":
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
			var par_whole := false
			var ppb := model.bone_parent[int(p.bone)]
			for k5 in whole:
				if int(parts[k5].bone) == ppb:
					par_whole = true
			res.pieces.append({"part": nm, "grid": {"size": s, "cells": cells}, "origin": mesh_origin(nm), "xform": att,
				"mesh": mesh if not p.dirty and int(p.job) < 0 else null, "box_at": bb.get_center(), "box": bb.size, "count": int(p.left),
				"seam": not par_whole, "limb": _is_limb(nm)})
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
		if masked:
			if not mask.has(nm):
				continue
			st.resize(cells.size())
			for i in (mask[nm] as PackedInt32Array):
				if i >= 0 and i < cells.size() and cells[i] != 0 and st[i] != 2:
					st[i] = 2
					ncut += 1
					var mc := Vector3i(i % s.x, (i / s.x) % s.y, i / (s.x * s.y))
					clo = Vector3i(mini(clo.x, mc.x), mini(clo.y, mc.y), mini(clo.z, mc.z))
					chi = Vector3i(maxi(chi.x, mc.x), maxi(chi.y, mc.y), maxi(chi.z, mc.z))
		elif not plane:
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
		var jq := jw - eye
		var in_sweep := jq.length() <= reach + vm and jq.dot(fwd) >= jq.length() * cos_arc - vm
		var joint_cut: bool = nm != root and not masked and ((absf(n.dot(jq)) <= half_t + vm and in_sweep) if plane else _seg_dist(jw, ca, cb) <= cr + vm)
		var box_v := (chi.x - clo.x + 7) * (chi.y - clo.y + 7) * (chi.z - clo.z + 7)
		if not joint_cut and (quick_only or (box_v < cells.size() and not _may_split(st, cells, s, clo, chi))):
			# the cut can't have split the part (the cubes round it all still join up close by) and the joint is
			# whole: just take the cut cubes out, no fill over the whole part
			brain_hit += _take_cut(p, st, cells, s, clo, chi, base, ex, ey, ez, every, res, ncut,
				mask[nm] if masked else PackedInt32Array())
			quick[nm] = [st, cells]
			res.parts.append(nm)
			if nm == "torso":
				body_cut += ncut
			continue
		if joint_cut:
			var ref := jw + Vector3.DOWN
			if nm != root and model.bone_parent[b] >= 0:
				ref = sk * skeleton.get_bone_global_pose(model.bone_parent[b]).origin
			if plane:
				keep_side = signf(n.dot(ref - eye))
				if keep_side == 0.0:
					# the parent's joint right on the blade: the side its nearest cube left is on (not both)
					var par2 := _parent_part(nm, by_bone, root)
					if par2 != "":
						var pp2: Dictionary = parts[par2]
						var jt2: Vector3 = model.bone_pivot[b] * model.voxel_m / vm - Vector3(pp2.origin) - Vector3(0.5, 0.5, 0.5)
						var ki := _nearest_filled_cell(pp2.grid.cells, pp2.grid.size, jt2)
						if ki >= 0:
							keep_side = signf(n.dot(_cell_world(par2, ki) - eye))
					if keep_side == 0.0:
						keep_side = 1.0
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
			if nm == root and not q2.is_empty():
				# the body itself keeps one side only: the one its nearest cube left is on (a chop down the middle
				# takes the other half off)
				var kb: int = q2[0]
				var db := Vector3(kb % s.x, (kb / s.x) % s.y, kb / (s.x * s.y)).distance_to(jp)
				if Vector3(kx0, ky0, kz0).distance_to(jp) < db:
					st[kb] = 0
					q2[0] = k
					st[k] = 4
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
		if masked and nm == root and q2.size() * 10 < int(p.left) - ncut:
			# fire's scattered ash can leave the cube nearest the hips a crumb on its own: the body keeps its biggest
			# lump instead (the crumb comes off), not the crumb with everything else falling off
			var big := q2
			var swapped := false
			for k0 in nall:
				if cells[k0] == 0 or st[k0] != 0:
					continue
				var lump := PackedInt32Array([k0])
				st[k0] = 5
				_flood(lump, st, cells, s, 5)
				if lump.size() > big.size():
					big = lump
					swapped = true
			if swapped:
				for k0 in q2:
					st[k0] = 5
				for k0 in big:
					st[k0] = 4
				q2 = big
			for k0 in nall:
				if st[k0] == 5:
					st[k0] = 0
		if q2.size() == int(p.left) - ncut:
			# everything left is still joined (a crater, a tunnel): just take the cut cubes out, not a pass over
			# every cube of the part to sort what came off
			brain_hit += _take_cut(p, st, cells, s, clo, chi, base, ex, ey, ez, every, res, ncut)
			quick[nm] = [st, cells]
			res.parts.append(nm)
			if nm == "torso":
				body_cut += ncut
			continue
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
		if noff > 0:
			# each lump that came off is a piece of its own; a few cubes left floating at the cut's edge just fly
			# off with the rest
			var mo := mesh_origin(nm)
			var lumps := _lumps(off_cells, s, olo, ohi) if noff <= LUMP_MAX else \
				[{"cells": off_cells, "idx": PackedInt32Array(), "n": noff, "lo": olo, "hi": ohi}]
			for comp in lumps:
				var cc: PackedInt32Array = comp.cells
				if int(comp.n) < MIN_PIECE:
					for j in comp.idx:
						var k4 := cc[j] - 1
						res.bits.append({"pos": base + ex * (j % s.x) + ey * ((j / s.x) % s.y) + ez * (j / (s.x * s.y)),
							"col": Color8((k4 >> 16) & 255, (k4 >> 8) & 255, k4 & 255)})
					continue
				var clo2: Vector3i = comp.lo
				var chi2: Vector3i = comp.hi
				res.pieces.append({"part": nm, "grid": {"size": s, "cells": cc}, "origin": mo, "xform": att,
					"box_at": ((Vector3(clo2) + Vector3(chi2) + Vector3.ONE) * 0.5 + mo) * vm, "box": (Vector3(chi2 - clo2) + Vector3.ONE) * vm, "count": int(comp.n)})
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
		elif not plane and not masked:
			# (a cube's worth by its size: twice the cube, eight times the health)
			hp -= float(body_cut) * float(opt.get("hp_per_cube", 0.08)) * pow(vm / REF_VM, 3.0)
		var brain_dead := brain_start > 0 and float(brain_lost) >= float(brain_start) * BRAIN_KILL
		if (hp <= 0.0 or brain_dead or res.head_off) and not immortal:
			res.killed = true
			alive = false
			died.emit(self)
	if not res.parts.is_empty():
		_update_loose()
		_seams_step()
		if not masked:
			_jerk(was_hanging, res.parts)
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
		var lk := (kx - x0) + bw * (ky - y0 + bh * (kz - z0))
		# (the six neighbours spelt out: a loop with arithmetic per step costs twice as much)
		if kx > x0 and seen[lk - 1] == 0 and cells[k - 1] != 0 and st[k - 1] != 2:
			seen[lk - 1] = 1
			q.append(k - 1)
		if kx < x1 and seen[lk + 1] == 0 and cells[k + 1] != 0 and st[k + 1] != 2:
			seen[lk + 1] = 1
			q.append(k + 1)
		if ky > y0 and seen[lk - bw] == 0 and cells[k - sx] != 0 and st[k - sx] != 2:
			seen[lk - bw] = 1
			q.append(k - sx)
		if ky < y1 and seen[lk + bw] == 0 and cells[k + sx] != 0 and st[k + sx] != 2:
			seen[lk + bw] = 1
			q.append(k + sx)
		if kz > z0 and seen[lk - bw * bh] == 0 and cells[k - sxy] != 0 and st[k - sxy] != 2:
			seen[lk - bw * bh] = 1
			q.append(k - sxy)
		if kz < z1 and seen[lk + bw * bh] == 0 and cells[k + sxy] != 0 and st[k + sxy] != 2:
			seen[lk + bw * bh] = 1
			q.append(k + sxy)
	for e in edge:
		if seen[(e % sx - x0) + bw * ((e / sx) % s.y - y0 + bh * (e / sxy - z0))] == 0:
			return true
	return false

# the part a part hangs from: up the bones to the first one with a part; the legs (whose hips have none) hang from the
# body itself; "" for the root
func _parent_part(nm: String, by_bone: Dictionary, root: String) -> String:
	var pb := model.bone_parent[int(parts[nm].bone)]
	while pb >= 0 and not by_bone.has(pb):
		pb = model.bone_parent[pb]
	if pb >= 0:
		return by_bone[pb]
	return root if nm != root else ""

# where cell i of part nm's grid is in the world now
func _cell_world(nm: String, i: int) -> Vector3:
	var p: Dictionary = parts[nm]
	var b: int = p.bone
	var s: Vector3i = p.grid.size
	var m := skeleton.global_transform * skeleton.get_bone_global_pose(b) * Transform3D(Basis.IDENTITY, -model.bone_pivot[b] * model.voxel_m)
	return m * ((Vector3(i % s.x, (i / s.x) % s.y, i / (s.x * s.y)) + Vector3(p.origin) + Vector3(0.5, 0.5, 0.5)) * vm)

# the filled cell nearest pt (in cells), -1 if none
static func _nearest_filled_cell(cells: PackedInt32Array, s: Vector3i, pt: Vector3) -> int:
	for r in [6, 1000]:
		var best := -1
		var bd := INF
		for z in range(clampi(floori(pt.z) - r, 0, s.z - 1), clampi(ceili(pt.z) + r, 0, s.z - 1) + 1):
			for y in range(clampi(floori(pt.y) - r, 0, s.y - 1), clampi(ceili(pt.y) + r, 0, s.y - 1) + 1):
				var row := s.x * (y + s.y * z)
				for x in range(clampi(floori(pt.x) - r, 0, s.x - 1), clampi(ceili(pt.x) + r, 0, s.x - 1) + 1):
					if cells[row + x] != 0:
						var d := Vector3(x, y, z).distance_squared_to(pt)
						if d < bd:
							bd = d
							best = row + x
		if best >= 0:
			return best
	return -1

# the cubes that came off a part (cells: a full-size grid of them, inside lo..hi) split into lumps that touch (face to
# face): [{cells: a full-size grid of that lump, idx: its indices, n, lo, hi}]
static func _lumps(cells: PackedInt32Array, s: Vector3i, lo: Vector3i, hi: Vector3i) -> Array:
	var out := []
	var seen := PackedByteArray()
	seen.resize(cells.size())
	var sx := s.x
	var sxy := s.x * s.y
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var i0 := x + sx * (y + s.y * z)
				if cells[i0] == 0 or seen[i0] == 1:
					continue
				var idx := PackedInt32Array([i0])
				seen[i0] = 1
				var h := 0
				var l2 := Vector3i(x, y, z)
				var h2 := Vector3i(x, y, z)
				while h < idx.size():
					var k: int = idx[h]
					h += 1
					var kx := k % sx
					var ky := (k / sx) % s.y
					var kz := k / sxy
					l2 = Vector3i(mini(l2.x, kx), mini(l2.y, ky), mini(l2.z, kz))
					h2 = Vector3i(maxi(h2.x, kx), maxi(h2.y, ky), maxi(h2.z, kz))
					for d in 6:
						var nx := kx + (1 if d == 0 else (-1 if d == 1 else 0))
						var ny := ky + (1 if d == 2 else (-1 if d == 3 else 0))
						var nz := kz + (1 if d == 4 else (-1 if d == 5 else 0))
						if nx < 0 or ny < 0 or nz < 0 or nx >= sx or ny >= s.y or nz >= s.z:
							continue
						var j := nx + sx * (ny + s.y * nz)
						if cells[j] != 0 and seen[j] == 0:
							seen[j] = 1
							idx.append(j)
				var g := PackedInt32Array()
				g.resize(cells.size())
				for j in idx:
					g[j] = cells[j]
				out.append({"cells": g, "idx": idx, "n": idx.size(), "lo": l2, "hi": h2})
	return out

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
		# nothing near (the joint well outside this grid): the whole grid
		for i in cells.size():
			st[i] = 1 if cells[i] != 0 else (2 if cut[i] == 2 else 0)
		near = _near_cells(st, s, pt, 1.5)
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

# ---------------------------------------------------------------- co-op (VoxelNet)
## A guest's game: bodies change only by the host's events (every cut, hole, freeze... made here is blocked: the
## guest's own weapons run for the look and sound, the host's copy of them does the cutting).
static var net_locked := false
## The host's: told every change to a body, func(body, what, args, pose), so the guest can make the same one.
static var net_rec: Callable
static var _net_replay := false        # making one of the host's changes (allowed while locked; not told again)
var net_id := 0                        # the body's number in both games (0: not shared yet)
var _net_depth := 0

func _net_block() -> bool:
	return net_locked and not _net_replay

func _no_cut() -> Dictionary:
	return {"bits": [], "cut": 0, "parts": [], "pieces": [], "killed": false, "head_off": false}

# a change starting: the host tells the guest (the outermost only: a carve's own hurt isn't told again); each
# _net_in is matched by a _net_depth -= 1 when it's done
func _net_in(what: String, args: Array) -> void:
	if _net_depth == 0 and not _net_replay and net_rec.is_valid():
		net_rec.call(self, what, args, pose())
	_net_depth += 1

## The pose cuts are made against: the skeleton's place and every bone's own position and turn.
func pose() -> Array:
	var bones := PackedFloat32Array()
	var n := skeleton.get_bone_count()
	bones.resize(n * 7)
	for i in n:
		var pp := skeleton.get_bone_pose_position(i)
		var q := skeleton.get_bone_pose_rotation(i)
		bones[i * 7] = pp.x
		bones[i * 7 + 1] = pp.y
		bones[i * 7 + 2] = pp.z
		bones[i * 7 + 3] = q.x
		bones[i * 7 + 4] = q.y
		bones[i * 7 + 5] = q.z
		bones[i * 7 + 6] = q.w
	return [skeleton.global_transform, bones]

func _set_pose(p: Array) -> void:
	skeleton.global_transform = p[0]
	var bones: PackedFloat32Array = p[1]
	for i in mini(skeleton.get_bone_count(), bones.size() / 7):
		skeleton.set_bone_pose_position(i, Vector3(bones[i * 7], bones[i * 7 + 1], bones[i * 7 + 2]))
		skeleton.set_bone_pose_rotation(i, Quaternion(bones[i * 7 + 3], bones[i * 7 + 4], bones[i * 7 + 5], bones[i * 7 + 6]))

## The guest making one of the host's changes, in the pose the host made it in; returns what the change returned.
func net_apply(what: String, args: Array, p: Array) -> Dictionary:
	_net_replay = true
	var was := pose()
	var was_local := skeleton.transform
	if not p.is_empty():
		_set_pose(p)
	var res := {}
	match what:
		"carve":
			res = carve(args[0], args[1], args[2], args[3], args[4])
		"slice":
			res = slice(args[0], args[1], args[2], args[3], args[4], args[5])
		"damage":
			res = damage(args[0], args[1])
		"sever":
			res = sever(args[0])
		"freeze":
			if not frozen():
				_freeze()
		"hurt":
			hurt(args[0])
		"shatter":
			if frozen():
				res = _shatter_res()
		"thaw":
			if frozen():
				_thaw()
		"burn":
			res = _net_burn(args[0], args[1], args[2])
	_set_pose(was)
	skeleton.transform = was_local
	_net_replay = false
	return res

# fire on the host: the cubes charred this step (part -> indices) and the ash taken out (part -> indices, or {}),
# made the same here
func _net_burn(charred: Dictionary, ash: Dictionary, quick: bool) -> Dictionary:
	var cv := ((CHAR.r8 << 16) | (CHAR.g8 << 8) | CHAR.b8) + 1
	for nm in charred:
		if not parts.has(nm) or parts[nm].gone:
			continue
		var p: Dictionary = parts[nm]
		var cells: PackedInt32Array = (p.grid.cells as PackedInt32Array).duplicate()
		for i in (charred[nm] as PackedInt32Array):
			if i >= 0 and i < cells.size() and cells[i] != 0:
				cells[i] = cv
		p.grid = {"size": p.grid.size, "cells": cells}
		p.dirty = true
	if ash.is_empty():
		return {}
	var r := _remove({"plane": false, "mask": ash, "bits_every": 3, "quick": quick})
	for bt in r.bits:
		bt.col = ASH
	return r

## A number that's the same in both games while the body's cubes are (the co-op check).
func fingerprint() -> int:
	var h := 17
	var names := parts.keys()
	names.sort()
	for nm in names:
		var p: Dictionary = parts[nm]
		h = hash([h, nm, p.gone, hash(p.grid.cells)])
	return h

## The body's cubes, to send whole (joining, or putting a guest's right): part -> [size, compressed cells, gone, left].
func grids_out() -> Dictionary:
	var out := {}
	for nm in parts:
		var p: Dictionary = parts[nm]
		var raw := (p.grid.cells as PackedInt32Array).to_byte_array()
		out[nm] = [p.grid.size, raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size(), p.gone, int(p.left)]
	return out

## Takes grids_out()'s cubes as its own.
func grids_in(d: Dictionary) -> void:
	for nm in d:
		if not parts.has(nm):
			continue
		var e: Array = d[nm]
		var p: Dictionary = parts[nm]
		var cells := (e[1] as PackedByteArray).decompress(int(e[2]), FileAccess.COMPRESSION_ZSTD).to_int32_array()
		p.grid = {"size": e[0], "cells": cells}
		p.gone = bool(e[3])
		p.left = int(e[4])
		p.dirty = not p.gone
		(p.mesh as MeshInstance3D).visible = not p.gone
	_update_loose()
	_seams_step()

# ---------------------------------------------------------------- bones hold the body together (Stage 8)

## The owner (21 Oct): "bones hold the body together, skin/meat stays attached to blown-off bones, dangling limbs tear
## off from strain, shooting the skin finishes it". A limb is held on by its bone: while the bone runs whole through a
## joint (the parent's bone, from where it's held, reaching the joint; the limb's own bone there) it's held as it was.
## Shot or cut through the bone but still joined by flesh, it hangs: loose, swinging from the strip that's left (a
## pendulum from the joint, lagging as the body moves, flopping when it's hit), with everything below it. A dangling leg
## is no leg to stand on. Hanging there it strains (its weight, every jerk and every hit, more the thinner the strip);
## strained through, it tears off (tear_due: the host's arena takes it off as a sever, so a co-op guest gets it like
## any cut). A shot that hits a dangling limb finishes it. What comes off keeps its meat on its bones (the pieces are
## the whole parts). Hands and feet have no bone of their own: they hang if the bone above them doesn't reach them.
const JOINT_R := 3.5             # cells round a joint the bone's looked for
const STRIP_R := 3.0             # cells round a joint counted as the strip a dangling limb hangs by
const TEAR_K := 0.25             # how fast a strip strains through (its load in thousands of cubes / ten of its cubes, a second)
const HIT_STRAIN := 0.35         # a hit on the body jerks a dangling limb this much (a thin strip's worth)
var loose := {}                  # part -> true: hanging by flesh (its bone, or the bone above it, broken at the joint)
var _dangle := {}                # the top of each hanging chain -> {tip, prev, len, strain, rest: Vector3 (bone space)}
var _dangle_fx := {}             # (looks only) the top of each hanging chain -> {skin: the stretched strip, drip: blood}
const SAG := 0.07                # metres a hanging limb sags from its joint, the skin it hangs by stretched over the gap
const SWING_KEEP := 0.996        # how much of its swing a hanging limb keeps each frame (floppy: it swings a long while)
static var _skin_mat: StandardMaterial3D
static var _drip_mat: StandardMaterial3D
static var _bone0 := {}          # "key|chunk" -> part -> {top: bone cells by its own joint, joints: {child: reached}}

static func _near_count(cells: PackedInt32Array, s: Vector3i, pt: Vector3, r: float, want: int, mask: PackedByteArray = PackedByteArray()) -> int:
	var n := 0
	var lo := Vector3i(maxi(0, floori(pt.x - r)), maxi(0, floori(pt.y - r)), maxi(0, floori(pt.z - r)))
	var hi := Vector3i(mini(s.x - 1, ceili(pt.x + r)), mini(s.y - 1, ceili(pt.y + r)), mini(s.z - 1, ceili(pt.z + r)))
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var i := x + s.x * (y + s.y * z)
				if (want == 0 and cells[i] != 0) or (want != 0 and cells[i] == want):
					if (mask.is_empty() or mask[i] == 1) and Vector3(x, y, z).distance_to(pt) <= r:
						n += 1
	return n

# this part's bone cells joined to the ones by its own joint (1 in the mask), from where it's held
static func _bone_reach(cells: PackedInt32Array, s: Vector3i, top: Vector3) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(cells.size())
	var q := PackedInt32Array()
	var lo := Vector3i(maxi(0, floori(top.x - JOINT_R)), maxi(0, floori(top.y - JOINT_R)), maxi(0, floori(top.z - JOINT_R)))
	var hi := Vector3i(mini(s.x - 1, ceili(top.x + JOINT_R)), mini(s.y - 1, ceili(top.y + JOINT_R)), mini(s.z - 1, ceili(top.z + JOINT_R)))
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var i := x + s.x * (y + s.y * z)
				if cells[i] == BONE_V and Vector3(x, y, z).distance_to(top) <= JOINT_R:
					mask[i] = 1
					q.append(i)
	var h := 0
	var sxy := s.x * s.y
	while h < q.size():
		var k := q[h]
		h += 1
		var kx := k % s.x
		var ky := (k / s.x) % s.y
		for d in [[kx > 0, -1], [kx < s.x - 1, 1], [ky > 0, -s.x], [ky < s.y - 1, s.x], [k >= sxy, -sxy], [k + sxy < cells.size(), sxy]]:
			if d[0]:
				var k2: int = k + int(d[1])
				if mask[k2] == 0 and cells[k2] == BONE_V:
					mask[k2] = 1
					q.append(k2)
	return mask

# where bone b's joint is in part p's grid (cells)
func _joint_in(p: Dictionary, b: int) -> Vector3:
	return model.bone_pivot[b] * model.voxel_m / vm - Vector3(p.origin) - Vector3(0.5, 0.5, 0.5)

# the bones as they are on a whole body of this kind (where a joint has no bone to hold it, none is asked for)
func _baseline() -> Dictionary:
	var ck := "%s|%d" % [key, chunk_n]
	if _bone0.has(ck):
		return _bone0[ck]
	var grids := _flesh_grids(model, key, chunk_n)
	var by_bone := {}
	for nm in parts:
		by_bone[int(parts[nm].bone)] = nm
	var names := parts.keys()
	names.sort_custom(func(a, b): return int(parts[a].bone) < int(parts[b].bone))
	var out := {}
	for nm in names:
		var p: Dictionary = parts[nm]
		var g: Dictionary = grids[nm]
		var top := _joint_in(p, int(p.bone))
		var limb := false
		for l in LIMBS:
			limb = limb or String(nm).begins_with(l)
		# (only the limbs hold by their bones: the head's skull isn't what holds it on)
		var top_n := _near_count(g.cells, g.size, top, JOINT_R, BONE_V) if limb else 0
		# (and how much of its bone is joined to its joint when whole: some models' bones have gaps)
		var reach0 := _bone_reach(g.cells, g.size, top).count(1) if top_n > 0 else 0
		out[nm] = {"top": top_n, "reach": reach0, "joints": {}}
	for nm in names:
		var p: Dictionary = parts[nm]
		var par := _parent_part(nm, by_bone, names[0])
		if par == "" or int(out[par].top) == 0:
			continue
		var pg: Dictionary = grids[par]
		var reach := _bone_reach(pg.cells, pg.size, _joint_in(parts[par], int(parts[par].bone)))
		out[par].joints[nm] = _near_count(pg.cells, pg.size, _joint_in(parts[par], int(p.bone)), JOINT_R, BONE_V, reach)
	_bone0[ck] = out
	return out

## Which parts hang loose now (after any cut): the bone through each joint looked at, from the body down.
func _update_loose() -> void:
	if parts.is_empty() or model == null:
		return
	var base := _baseline()
	var by_bone := {}
	for nm in parts:
		by_bone[int(parts[nm].bone)] = nm
	var names := parts.keys()
	names.sort_custom(func(a, b): return int(parts[a].bone) < int(parts[b].bone))
	var held := {}               # part -> its bone held from the body (its reach mask), or true (no bone of its own)
	loose.clear()
	for nm in names:
		var p: Dictionary = parts[nm]
		if p.gone:
			continue
		var par := _parent_part(nm, by_bone, names[0])
		var ok := true
		if par != "" and not fragment:
			ok = held.has(par)
			var need: int = int(base[par].joints.get(nm, 0)) if base.has(par) else 0
			if ok and need > 0 and held[par] is PackedByteArray:
				var pp: Dictionary = parts[par]
				ok = _near_count(pp.grid.cells, pp.grid.size, _joint_in(pp, int(p.bone)), JOINT_R, BONE_V, held[par]) > 0
			var top0: int = int(base[nm].top) if base.has(nm) else 0
			if ok and top0 > 0:
				ok = _near_count(p.grid.cells, p.grid.size, _joint_in(p, int(p.bone)), JOINT_R, BONE_V) >= maxi(1, top0 / 3)
		var top0b: int = int(base[nm].top) if base.has(nm) else 0
		var reach := PackedByteArray()
		if ok and top0b > 0:
			reach = _bone_reach(p.grid.cells, p.grid.size, _joint_in(p, int(p.bone)))
			# broken in its upper half (less than half the bone joined to where it's held when whole still is): it hangs
			# from its joint (the parts swing whole, so it pivots there; broken lower down, what's below it hangs)
			var reach0 := int(base[nm].get("reach", 0))
			if reach0 > 1 and reach.count(1) * 2 < reach0:
				ok = false
		if not ok:
			loose[nm] = true
			continue
		held[nm] = reach if top0b > 0 else true
	# a chain newly hanging starts swinging from where it was; one no longer hanging (off, or the body made whole) stops
	for nm in _dangle.keys():
		if not loose.has(nm) or (parts[nm].gone):
			_dangle.erase(nm)
	for nm in loose:
		var par2 := _parent_part(nm, by_bone, names[0])
		if par2 != "" and loose.has(par2):
			continue                 # (not the top of its chain)
		if not _dangle.has(nm):
			_dangle[nm] = _new_dangle(nm)

# a hanging chain's swing: its tip where the limb points now, its length, how it points at rest (bone space)
func _new_dangle(nm: String) -> Dictionary:
	var b := int(parts[nm].bone)
	var rest := Vector3.ZERO
	for i in model.bone_names.size():
		if model.bone_parent[i] == b:
			rest = (model.bone_pivot[i] - model.bone_pivot[b]) * model.voxel_m
			break
	if rest.length() < 0.01:
		# (no bone below it: a hand, a foot) toward the middle of its cubes
		var p: Dictionary = parts[nm]
		var s: Vector3i = p.grid.size
		rest = ((Vector3(p.origin) + Vector3(s) * 0.5) - (p.pivot as Vector3) / vm) * vm
	if rest.length() < 0.01:
		rest = Vector3(0, -0.2, 0)
	var g := skeleton.global_transform * skeleton.get_bone_global_pose(b)
	var tip := g * rest
	# (it drops as it goes: a start to its swing, out and down)
	var kick := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 0.05
	# how thick the limb is just under its joint (the flesh stretched across the gap is most of that, thinning as it tears)
	var p2: Dictionary = parts[nm]
	var s2: Vector3i = p2.grid.size
	var j2 := _joint_in(p2, int(p2.bone))
	var area := 0
	for dy in [1, 2, 3]:
		var y := clampi(roundi(j2.y) - dy, 0, s2.y - 1)
		for z in s2.z:
			for x in s2.x:
				if p2.grid.cells[x + s2.x * (y + s2.y * z)] != 0:
					area += 1
	var radius := clampf(sqrt(float(area) / 3.0 / PI) * vm, 0.015, 0.1)
	return {"tip": tip, "prev": tip - kick, "len": rest.length(), "rest": rest, "strain": 0.0, "a": 0.0, "odo": odo,
		"sag": 0.0, "sag_v": 0.0, "limp": {}, "r": radius, "strip0": maxi(1, strip_cubes(nm))}

## The cubes of the chain hanging from part nm (it and everything below it), and the strip it hangs by.
func _chain_cubes(nm: String) -> int:
	var b0 := int(parts[nm].bone)
	var n := 0
	for k in parts:
		var bb := int(parts[k].bone)
		var hangs := bb == b0
		var pb := model.bone_parent[bb]
		while not hangs and pb >= 0:
			hangs = pb == b0
			pb = model.bone_parent[pb]
		if hangs and not parts[k].gone:
			n += int(parts[k].left)
	return n

func strip_cubes(nm: String) -> int:
	var p: Dictionary = parts[nm]
	return _near_count(p.grid.cells, p.grid.size, _joint_in(p, int(p.bone)), STRIP_R, 0)

# (animate's end) each hanging chain swung: its tip falls and lags behind the joint as the body moves, the bone turned
# to point at it, what's below it limp; its strain built up
func _dangle_pose(dt: float) -> void:
	if _dangle_fx.size() > _dangle.size() or (not _dangle_fx.is_empty() and _dangle.is_empty()):
		_dangle_fx_clear()
	if _dangle.is_empty():
		return
	var sk := skeleton.global_transform
	for nm in _dangle:
		var d: Dictionary = _dangle[nm]
		var b := int(parts[nm].bone)
		var par := model.bone_parent[b]
		var pg := sk * (skeleton.get_bone_global_pose(par) if par >= 0 else Transform3D())
		var rest_o := skeleton.get_bone_rest(b).origin
		var joint := pg * rest_o                 # (where the joint is, not where the limb's sagged to)
		var tip: Vector3 = d.tip
		var prev: Vector3 = d.prev
		var vel := (tip - prev) * SWING_KEEP
		# walking (or shoved along) sways it side to side, in step
		var walk0 := clampf((odo - float(d.odo)) / maxf(dt, 0.0001), 0.0, 3.0)
		if walk0 > 0.05 and alive:
			var side := pg.basis.x.normalized()
			vel += side * sin(odo * 5.5) * walk0 * 0.0016 + Vector3(0, 0.0006 * walk0 * absf(sin(odo * 5.5)), 0)
		var nt := tip + vel + Vector3(0, -9.8, 0) * dt * dt
		var len_m: float = d.len
		var off := nt - joint
		nt = joint + (off.normalized() if off.length() > 0.0001 else Vector3.DOWN) * len_m
		var floor_y := global_position.y + 0.04
		var on_floor := nt.y < floor_y
		if on_floor:
			nt.y = floor_y
		var acc := ((nt - tip) - (tip - prev)).length() / maxf(dt * dt, 0.0001)
		d.a = lerpf(float(d.a), acc, 0.3)
		var swing_v := (nt - tip) / maxf(dt, 0.0001)        # (how fast the end's going: the hand's flop, the sag's bounce)
		d.prev = tip
		d.tip = nt
		# the sag: a spring, bouncing with the swing (the skin stretching and giving)
		var sag_to := SAG + 0.012 * minf(float(d.a) / 9.8, 3.0)
		d.sag_v = (float(d.sag_v) + (sag_to - float(d.sag)) * 180.0 * dt) * maxf(0.0, 1.0 - 9.0 * dt)
		d.sag = clampf(float(d.sag) + float(d.sag_v) * dt, 0.0, SAG * 2.5)
		# the bone turned to point at the tip (from how it would point unturned)
		var pb := pg.basis.orthonormalized()
		var want := (nt - joint).normalized()
		var now := (pb * (d.rest as Vector3)).normalized()
		if want.length() > 0.5 and now.length() > 0.5 and absf(now.dot(want)) < 0.9999:
			var q := Quaternion(now, want)
			var local := (pb.inverse() * Basis(q) * pb).get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(b, local)
		else:
			skeleton.set_bone_pose_rotation(b, Quaternion.IDENTITY)
		# sagged down from the joint (along the way it hangs), the stretched skin across the gap
		skeleton.set_bone_pose_position(b, rest_o + pb.inverse() * (want * float(d.sag)))
		_dangle_look(nm, d, joint, joint + want * float(d.sag))
		# limp below it: flopping the other way to the swing, a little behind it
		var lv := pb.inverse() * swing_v
		var limp: Dictionary = d.limp
		for i in model.bone_names.size():
			var pb2 := model.bone_parent[i]
			var below := false
			while pb2 >= 0:
				if pb2 == b:
					below = true
					break
				pb2 = model.bone_parent[pb2]
			if below:
				var fl: Vector2 = limp.get(i, Vector2.ZERO)
				var aim := Vector2(clampf(lv.z * 2.2, -1.1, 1.1), clampf(-lv.x * 2.2, -1.1, 1.1))
				fl = fl.lerp(aim, minf(1.0, dt * 7.0))
				limp[i] = fl
				skeleton.set_bone_pose_rotation(i, Quaternion.from_euler(Vector3(fl.x + 0.12 * sin(t * 3.0 + i), 0, fl.y)))
		# the strain: its weight, and every jerk, on the strip it hangs by (none lying on the floor)
		var walk := clampf((odo - float(d.odo)) / maxf(dt, 0.0001), 0.0, 3.0)      # (walking jolts it about)
		d.odo = odo
		if not on_floor:
			var strip := maxi(1, strip_cubes(nm))
			var load := float(_chain_cubes(nm)) / 1000.0 * (1.0 + minf(float(d.a), 60.0) / 9.8) * (1.0 + 0.5 * walk)
			d.strain = float(d.strain) + dt * TEAR_K * load * 10.0 / float(strip)

# (looks only) the skin stretched from the joint to where the limb sagged to, and blood dripping off it, faster as it
# tears; gone with the swing
func _dangle_look(nm: String, d: Dictionary, from: Vector3, to: Vector3) -> void:
	if _skin_mat == null:
		_skin_mat = StandardMaterial3D.new()
		_skin_mat.albedo_color = Color(0.62, 0.09, 0.1)
		_skin_mat.roughness = 0.35               # (wet)
		_skin_mat.metallic_specular = 0.7
		_drip_mat = StandardMaterial3D.new()
		_drip_mat.albedo_color = Color(0.45, 0.02, 0.03)
		_drip_mat.roughness = 0.2
	var fx: Dictionary = _dangle_fx.get(nm, {})
	if fx.is_empty():
		var skin := MeshInstance3D.new()
		var bm := BoxMesh.new()                  # (square: blocks like the rest of them)
		bm.size = Vector3.ONE
		skin.mesh = bm
		skin.material_override = _skin_mat
		skin.top_level = true
		add_child(skin)
		var drip := CPUParticles3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3.ONE * 0.012
		drip.mesh = dm
		drip.material_override = _drip_mat
		drip.amount = 20
		drip.lifetime = 0.9
		drip.gravity = Vector3(0, -9.8, 0)
		drip.direction = Vector3.DOWN
		drip.spread = 25.0
		drip.initial_velocity_min = 0.1
		drip.initial_velocity_max = 0.5
		drip.scale_amount_min = 0.5
		drip.scale_amount_max = 1.3
		drip.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		drip.emission_sphere_radius = 0.02
		drip.top_level = true
		add_child(drip)
		fx = {"skin": skin, "drip": drip}
		_dangle_fx[nm] = fx
	var skin2: MeshInstance3D = fx.skin
	var strip := strip_cubes(nm)
	var r: float = float(d.get("r", 0.04))
	var w := 2.0 * r * clampf(float(strip) / float(d.get("strip0", strip)), 0.3, 1.0) * 0.22
	var seg := to - from
	var lenm := maxf(seg.length(), 0.004) + 0.03         # (into the flesh at both ends)
	var y := seg.normalized() if seg.length() > 0.0005 else Vector3.DOWN
	# the flesh is the strip that's left: off to the side it's on (the middle open, the bone showing)
	if int(d.get("side_n", -1)) != strip:
		d.side_n = strip
		d.side = _strip_side(nm)
	var side: Vector3 = d.side
	side = side - y * side.dot(y)
	side = side.normalized() if side.length() > 0.0001 else y.cross(Vector3.RIGHT).normalized()
	var x := side
	var z := x.cross(y)
	skin2.global_transform = Transform3D(Basis(x * w * 0.7, y * lenm, z * w), (from + to) * 0.5 + side * (r * 1.05 - w * 0.5))
	var drip2: CPUParticles3D = fx.drip
	drip2.global_position = to
	var st := float(d.strain)
	var n := 20 if st < 0.4 else (30 if st < 0.75 else 44)       # (more as it tears)
	if drip2.amount != n:
		drip2.amount = n
	drip2.emitting = true

# which way the strip a limb hangs by lies from its joint (world: the middle of its cubes round the joint)
func _strip_side(nm: String) -> Vector3:
	var p: Dictionary = parts[nm]
	var s3: Vector3i = p.grid.size
	var j := _joint_in(p, int(p.bone))
	var sum := Vector3.ZERO
	var n := 0
	var lo := Vector3i(maxi(0, floori(j.x - STRIP_R)), maxi(0, floori(j.y - STRIP_R)), maxi(0, floori(j.z - STRIP_R)))
	var hi := Vector3i(mini(s3.x - 1, ceili(j.x + STRIP_R)), mini(s3.y - 1, ceili(j.y + STRIP_R)), mini(s3.z - 1, ceili(j.z + STRIP_R)))
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				if p.grid.cells[x + s3.x * (y + s3.y * z)] != 0 and Vector3(x, y, z).distance_to(j) <= STRIP_R:
					sum += Vector3(x, y, z) - j
					n += 1
	if n == 0:
		return Vector3.ZERO
	var b: int = p.bone
	var basis := (skeleton.global_transform * skeleton.get_bone_global_pose(b)).basis.orthonormalized()
	return basis * (sum / float(n))

# a chain no longer hanging: its looks gone, its sag put back
func _dangle_fx_clear() -> void:
	for nm in _dangle_fx.keys():
		if _dangle.has(nm):
			continue
		var fx: Dictionary = _dangle_fx[nm]
		(fx.skin as Node).queue_free()
		var drip: CPUParticles3D = fx.drip
		drip.emitting = false
		get_tree().create_timer(1.0).timeout.connect(drip.queue_free)
		_dangle_fx.erase(nm)
		if parts.has(nm):
			var b := int(parts[nm].bone)
			skeleton.set_bone_pose_position(b, skeleton.get_bone_rest(b).origin)

# ---------------------------------------------------------------- torn edges (looks only)

## Where a limb's parted from its neighbour (hanging, or off), not a flat cut: from the cubes there, a torn edge.
## Raw meat over the face, the bone sticking out jagged where the bone is (on a limb, at least one), the sleeve or skin
## round the edge torn ragged; each column of it its own length. Made of little cubes, on the part's bone like the
## part's own (so it moves with it); pieces that come off get one on their end too (VoxelPieces). Nothing to hit or take.
var _seams := {}                 # "part@joint part" -> the MultiMeshInstance3D
var _seam_sig := ""
var _seam_par := {}              # part -> the part above it ("" none)
static var _seam_mat: StandardMaterial3D
static var _seam_bone_mat: StandardMaterial3D

# every frame: the torn edges this body needs (a part whose neighbour's gone or hanging), made again when that, or
# the cubes there, change
func _seams_step() -> void:
	if parts.is_empty() or model == null:
		return
	if _seam_par.is_empty():
		var by_bone := {}
		for k in parts:
			by_bone[int(parts[k].bone)] = k
		for k in parts:
			_seam_par[k] = by_bone.get(model.bone_parent[int(parts[k].bone)], "")
	# (the usual case, a whole body: nothing to look at)
	var any := loose.size() > 0 or not _seams.is_empty()
	if not any:
		for nm in parts:
			if parts[nm].gone:
				any = true
				break
	if not any:
		return
	var want := {}
	var sig := ""
	for nm in parts:
		var p: Dictionary = parts[nm]
		var par: String = _seam_par[nm]
		if par == "":
			continue
		if parts[par].gone:
			if not p.gone:
				want["%s@%s" % [nm, nm]] = [nm, nm]           # (a piece lying about, made a body again: its torn end)
				sig += "%s@%s:%d;" % [nm, nm, int(p.left)]
			continue
		var hanging_top := loose.has(nm) and not loose.has(par)
		if p.gone or hanging_top:
			want["%s@%s" % [par, nm]] = [par, nm]             # (the stump: the part above, at this one's joint)
			sig += "%s@%s:%d;" % [par, nm, int(parts[par].left)]
		if hanging_top and not p.gone:
			want["%s@%s" % [nm, nm]] = [nm, nm]               # (the hanging part's own end)
			sig += "%s@%s:%d;" % [nm, nm, int(p.left)]
	if sig == _seam_sig:
		return
	_seam_sig = sig
	for k in _seams.keys():
		(_seams[k] as Node).queue_free()
	_seams.clear()
	for k in want:
		var on: String = want[k][0]
		var at: String = want[k][1]
		var p2: Dictionary = parts[on]
		var j := _joint_in(p2, int(parts[at].bone))
		# (a stump's bone sticks out well past the meat; the neck has its spine)
		var stump := on != at and bool(parts[at].gone)
		var cols := seam_cols(p2.grid.cells, p2.grid.size, j, on == at, _is_limb(on) or _is_limb(at) or at == "head", hash(String(name) + k),
			2.0 if stump else (1.3 if on == at and not loose.has(on) else 1.0))
		if cols.is_empty():
			continue
		var mmi := seam_mesh(cols, mesh_origin(on), vm)
		(p2.mesh as Node).get_parent().add_child(mmi)
		_seams[k] = mmi

func _is_limb(nm: String) -> bool:
	for l in LIMBS:
		if nm.begins_with(l):
			return true
	return false

## A torn edge's columns, from a part's cubes (cells, size) round the joint j (in cells): own_end true, the part's own
## joint (the edge faces away from its cubes); false, a child's joint on the part above (faces away from its cubes too).
## bone_k: how far the bone sticks out (a stump's, twice as far).
## Each [face cell (Vector3), axis, +1/-1 out, length (cubes), colour, bone?].
static func seam_cols(cells: PackedInt32Array, s: Vector3i, j: Vector3, _own_end: bool, limb: bool, seed_: int, bone_k := 1.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	# which way is out: from the middle of the cubes round the joint to the joint
	var mid := Vector3.ZERO
	var nmid := 0
	var R := 8
	var lo := Vector3i(maxi(0, floori(j.x) - R), maxi(0, floori(j.y) - R), maxi(0, floori(j.z) - R))
	var hi := Vector3i(mini(s.x - 1, ceili(j.x) + R), mini(s.y - 1, ceili(j.y) + R), mini(s.z - 1, ceili(j.z) + R))
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				if cells[x + s.x * (y + s.y * z)] != 0:
					mid += Vector3(x, y, z)
					nmid += 1
	if nmid == 0:
		return []
	var out := j - mid / float(nmid)
	var ax := 1
	if absf(out.x) > absf(out[ax]):
		ax = 0
	if absf(out.z) > absf(out[ax]):
		ax = 2
	var sg := 1 if out[ax] >= 0.0 else -1
	var ua := (ax + 1) % 3
	var va := (ax + 2) % 3
	var dims := [s.x, s.y, s.z]
	var band := 4
	var jk := roundi(j[ax])
	var faces := []              # [cell, value, bone near]
	var any_bone := false
	for du in range(-R, R + 1):
		for dv in range(-R, R + 1):
			var c := Vector3i.ZERO
			c[ua] = roundi(j[ua]) + du
			c[va] = roundi(j[va]) + dv
			if c[ua] < 0 or c[ua] >= int(dims[ua]) or c[va] < 0 or c[va] >= int(dims[va]):
				continue
			# the outermost cube of this column near the joint
			var tt := jk + sg * band
			while tt != jk - sg * (band + 1):
				if tt >= 0 and tt < int(dims[ax]):
					c[ax] = tt
					var v := cells[c.x + s.x * (c.y + s.y * c.z)]
					if v != 0:
						var bone := false
						for back in 3:
							var c2 := c
							c2[ax] = tt - sg * back
							if c2[ax] >= 0 and c2[ax] < int(dims[ax]) and cells[c2.x + s.x * (c2.y + s.y * c2.z)] == BONE_V:
								bone = true
						any_bone = any_bone or bone
						faces.append([Vector3(c), v, bone])
						break
				tt -= sg
	if faces.is_empty():
		return []
	var centre := Vector2.ZERO
	for f in faces:
		centre += Vector2((f[0] as Vector3)[ua], (f[0] as Vector3)[va])
	centre /= float(faces.size())
	var far := 1.0
	for f in faces:
		far = maxf(far, Vector2((f[0] as Vector3)[ua], (f[0] as Vector3)[va]).distance_to(centre))
	# the bone: round where the bone cubes are at the edge (on a limb with none left there, where it would be: by the
	# joint), a good thick one, so it shows
	var bone_c := Vector2.ZERO
	var nb := 0
	for f in faces:
		if bool(f[2]):
			bone_c += Vector2((f[0] as Vector3)[ua], (f[0] as Vector3)[va])
			nb += 1
	var has_bone := nb > 0 or limb
	if nb > 0:
		bone_c /= float(nb)
	else:
		bone_c = Vector2(j[ua], j[va])
	var bone_r := 1.6 if limb else 1.1
	var cols := []
	for i in faces.size():
		var f: Array = faces[i]
		var cell: Vector3 = f[0]
		var rho := Vector2(cell[ua], cell[va]).distance_to(centre) / far
		var k := int(f[1]) - 1
		var own := Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)
		var len := 0.0
		var col := own
		var is_bone := false
		var bd2 := Vector2(cell[ua], cell[va]).distance_to(bone_c)
		if has_bone and (bd2 <= bone_r or (bool(f[2]) and bd2 <= bone_r + 1.5)):
			len = rng.randf_range(1.8, 3.2) if rng.randf() < 0.8 else rng.randf_range(1.0, 1.6)   # (bone: jagged, sticking out past the rest)
			len *= bone_k * (1.0 - 0.4 * clampf(bd2 / (bone_r + 1.5), 0.0, 1.0))           # (longest in the middle: a splintered point)
			col = Color8(244, 239, 226).darkened(rng.randf_range(0.0, 0.08))
			is_bone = true
		elif rho < 0.72:
			len = rng.randf_range(0.25, 0.9)                # (the meat)
			col = (FLESH[rng.randi() % FLESH.size()] as Color).darkened(rng.randf_range(0.0, 0.2))
		else:
			len = [0.0, 0.0, 0.3, 0.5, 0.5, 0.8, 1.2][rng.randi() % 7]       # (the sleeve, the skin: torn ragged)
			col = own if rng.randf() < 0.6 else (FLESH[rng.randi() % FLESH.size()] as Color)
		if len > 0.0:
			cols.append([cell, ax, sg, len, col, is_bone])
	return cols

## The columns as little cubes, placed like a part's own (origin: its mesh origin, in cubes; vm metres a cube): the meat
## and the skin one mesh, the bone another (it glows a touch, so it shows in the shade of the limb).
static func seam_mesh(cols: Array, origin: Vector3, vm_: float) -> Node3D:
	if _seam_mat == null:
		_seam_mat = StandardMaterial3D.new()
		_seam_mat.vertex_color_use_as_albedo = true
		_seam_mat.vertex_color_is_srgb = true
		_seam_mat.roughness = 0.55
		_seam_bone_mat = StandardMaterial3D.new()
		_seam_bone_mat.vertex_color_use_as_albedo = true
		_seam_bone_mat.vertex_color_is_srgb = true
		_seam_bone_mat.roughness = 0.7
		_seam_bone_mat.emission_enabled = true
		_seam_bone_mat.emission = Color(0.3, 0.29, 0.26)
	var node := Node3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * vm_
	for bone in [false, true]:
		var mine := []
		for c in cols:
			if bool(c[5]) == bone:
				mine.append(c)
		if mine.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = box
		mm.instance_count = mine.size()
		for i in mine.size():
			var c: Array = mine[i]
			var cell: Vector3 = c[0]
			var ax: int = c[1]
			var sg: int = c[2]
			var len: float = c[3]
			var sc := Vector3.ONE
			sc[ax] = len
			var at := cell + Vector3(0.5, 0.5, 0.5)
			at[ax] += float(sg) * (0.5 + len * 0.5 - 0.15)      # (out of the face, a little into it)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(sc), (at + origin) * vm_))
			mm.set_instance_color(i, c[4])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _seam_bone_mat if bone else _seam_mat
		node.add_child(mmi)
	return node

## (the host's arena, every frame) the top of a hanging chain strained through, to tear off ("" none).
func tear_due() -> String:
	if _net_block():
		return ""
	for nm in _dangle:
		if float(_dangle[nm].strain) >= 1.0 and not parts[nm].gone:
			return nm
	return ""

## How strained a part's chain is (0 .. 1 tears; -1 not hanging) (tests, the HUD).
func strain_of(nm: String) -> float:
	return float(_dangle[nm].strain) if _dangle.has(nm) else -1.0

# a cut (hit) on the body: every chain that was hanging already jerks (a thin strip's worth of strain), and one the cut
# took cubes from (the limb, or the strip) is finished
func _jerk(was: Array, hit_parts: Array) -> void:
	for nm in was:
		if not _dangle.has(nm):
			continue
		var d: Dictionary = _dangle[nm]
		var strip := maxi(1, strip_cubes(nm))
		d.strain = float(d.strain) + HIT_STRAIN * 10.0 / float(strip)
		for hp_ in hit_parts:
			if hp_ == nm or _hangs_from(String(hp_), nm):
				d.strain = 1.0
		# (and a kick to its swing: it flies about, then swings back)
		d.prev = (d.tip as Vector3) - Vector3(randf_range(-1, 1), randf_range(0.2, 0.6), randf_range(-1, 1)).normalized() * randf_range(0.06, 0.11)
		d.sag_v = float(d.get("sag_v", 0.0)) + 0.6

func _hangs_from(part: String, top: String) -> bool:
	if not parts.has(part) or not parts.has(top):
		return false
	var b0 := int(parts[top].bone)
	var pb := model.bone_parent[int(parts[part].bone)]
	while pb >= 0:
		if pb == b0:
			return true
		pb = model.bone_parent[pb]
	return false
