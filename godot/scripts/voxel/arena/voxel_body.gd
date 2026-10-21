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
			if parts.has(leg + side) and parts[leg + side].gone:
				n += 1
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
			if parts.has(leg) and parts[leg].gone:
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

## Knocks out the cubes within r cubes of the hit (a round hole); returns the ones knocked out as
## [{pos: world, col: Color}] (for the flying bits) and whether that killed it or blew a limb off.
func damage(hit: Dictionary, r: float) -> Dictionary:
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

## Fire (the flamethrower): cubes set alight burn; each chars black after BURN_CHAR seconds and crumbles to ash after
## BURN_ASH (taken out: what that leaves hanging falls off), catching the cubes beside it as it goes (BURN_SPREAD a
## second each), never more than BURN_MAX at once. Alive and burning, they lose BURN_HURT a second and panic, running
## about with their arms flailing. Ice (the freeze ray): frost builds up (chill), slowing them; at 1 they're frozen
## solid for FREEZE_T seconds (blue-white, still as statues), and then any hit at all shatters them into ice cubes.
## status_step(dt) runs it all (the arena calls it every frame for a body with has_status()).
const BURN_CHAR := 0.8
const BURN_ASH := 2.4
const BURN_SPREAD := 0.6
const BURN_MAX := 900
const BURN_HURT := 7.0
const BURN_TICK := 0.125         # seconds between fire steps
const CHAR := Color8(34, 26, 22)
const ICE := Color8(176, 222, 255)
const FREEZE_T := 8.0
const FROST_FADE := 0.12        # frost a second lost when it isn't being kept up
## The arena's: what to do with the ice cubes when something shatters without a weapon there to throw them (a launch,
## a burn): func(body, bits).
static var on_shatter: Callable
var _burn := {}                 # part -> {cell index: seconds burning}
var _burn_n := 0
var _burn_tick := randf() * BURN_TICK     # (bodies set alight together still step on different frames)
const ASH_EVERY := 0.5          # seconds between taking the ash out (its connectivity cut fills the whole part)
var _ash := {}                  # part -> {cell index: true}: burnt to ash, waiting to be taken out
var _ash_t := randf() * ASH_EVERY
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
	if frozen():
		return 0
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
		var lo: Vector3i = box.lo
		var hi: Vector3i = box.hi
		var s: Vector3i = p.grid.size
		for z in range(lo.z, hi.z + 1):
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var i := x + s.x * (y + s.y * z)
					if st[i] == 2 and not bd.has(i) and _burn_n < BURN_MAX:
						bd[i] = 0.0
						_burn_n += 1
						n += 1
		_burn[nm] = bd
	if n > 0 and alive:
		panic_t = maxf(panic_t, 1.0)
	return n

## Frost building up (amount: a share of frozen solid). True if that froze them solid.
func chill(amount: float) -> bool:
	if frozen():
		return false
	frost = minf(1.0, frost + amount)
	if _burn_n > 0:
		_burn.clear()                # the cold puts the fire out (the ash not yet fallen stays, charred)
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
	return _shatter_res()

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
	var res := _shatter_res()
	if on_shatter.is_valid() and not (res.bits as Array).is_empty():
		on_shatter.call(self, res.bits, dir)
	return bool(res.killed)

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
	var ash := {}
	var flames := []
	var catch := []                   # [part, index] catching this step
	for nm in _burn.keys():
		var p: Dictionary = parts[nm]
		var bd: Dictionary = _burn[nm]
		if p.gone:
			_burn_n -= bd.size()
			_burn.erase(nm)
			continue
		var s: Vector3i = p.grid.size
		var cells: PackedInt32Array = p.grid.cells
		var recol := false
		var gone := PackedInt32Array()
		var b: int = p.bone
		var m := skeleton.global_transform * skeleton.get_bone_global_pose(b) * Transform3D(Basis.IDENTITY, -model.bone_pivot[b] * model.voxel_m)
		var o: Vector3 = p.origin
		for i in bd.keys():
			if cells[i] == 0:
				bd.erase(i)
				_burn_n -= 1
				continue
			var t0: float = bd[i]
			var t1 := t0 + step
			bd[i] = t1
			if t0 < BURN_CHAR and t1 >= BURN_CHAR:
				if not recol:
					cells = cells.duplicate()
					recol = true
				cells[i] = ((CHAR.r8 << 16) | (CHAR.g8 << 8) | CHAR.b8) + 1     # (for good: the thaw keeps it)
			if t1 >= BURN_ASH:
				gone.append(i)
				bd.erase(i)
				_burn_n -= 1
				continue
			# catching the cubes beside it
			if randf() < BURN_SPREAD * step * 6.0:
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
		if i2 < 0 or i2 >= cells2.size() or cells2[i2] == 0 or (_ash.has(c[0]) and (_ash[c[0]] as Dictionary).has(i2)):
			continue
		var bd2: Dictionary = _burn.get(c[0], {})
		if not bd2.has(i2):
			bd2[i2] = 0.0
			_burn[c[0]] = bd2
			_burn_n += 1
	out.flames = flames
	if alive:
		panic_t = maxf(panic_t, 0.6)
		hurt(BURN_HURT * step)
	_ash_t += step
	# (ash_ok false: not this frame, another body took its ash out; the last of a fire always goes)
	if not _ash.is_empty() and (_ash_t >= ASH_EVERY or _burn_n == 0) and (ash_ok or _burn_n == 0):
		_ash_t = 0.0
		for nm2 in _ash:
			ash[nm2] = PackedInt32Array((_ash[nm2] as Dictionary).keys())
		_ash.clear()
		var r := _remove({"plane": false, "mask": ash, "bits_every": 3})
		for bt in r.bits:
			bt.col = (bt.col as Color).lerp(CHAR, 0.6)      # ash
		out.removed = r
	return out

## A part and everything hanging from it taken off whole (a harpoon's yank): {pieces (VoxelPieces.spawn's list),
## parts, killed}. Nothing if it's gone already.
func sever(part: String) -> Dictionary:
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
			"mesh": mesh if not p.dirty and int(p.job) < 0 else null, "box_at": bbx.get_center(), "box": bbx.size, "count": int(p.left)})
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
	return _remove({"plane": true, "eye": eye, "n": n, "fwd": fwd, "reach": reach, "cos_arc": cos_arc, "half_t": half_t})

## A blow that scoops out every cube within r metres of the segment a-b (a == b: a ball, a crater; long: a tunnel, a
## chainsaw's kerf); whatever is left no longer joined to its joint comes off, as with slice. hp_per_cube: the health
## each body (torso) cube taken costs; bits_every: one flying bit for every this many cubes taken. Returns what slice
## does.
func carve(a: Vector3, b: Vector3, r: float, hp_per_cube: float = 0.08, bits_every: int = 2) -> Dictionary:
	return _remove({"plane": false, "a": a, "b": b, "r": r, "hp_per_cube": hp_per_cube, "bits_every": maxi(1, bits_every)})

## Health off the body (a blunt blow, a burn); true if that killed it.
func hurt(amount: float) -> bool:
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
	var res := {"bits": [], "cut": 0, "parts": [], "pieces": [], "killed": false, "head_off": false}
	if frozen():
		return _shatter_res()
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
			res.pieces.append({"part": nm, "grid": {"size": s, "cells": cells}, "origin": mesh_origin(nm), "xform": att,
				"mesh": mesh if not p.dirty and int(p.job) < 0 else null, "box_at": bb.get_center(), "box": bb.size, "count": int(p.left)})
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
