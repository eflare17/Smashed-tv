class_name VoxelPieces
extends Node3D
## The bits a melee weapon takes off a body in one go (VoxelBody.slice / carve's "pieces"): an arm, half a forearm, a
## head, legs from the knee. Each is a real rigid body with its own meshes (a whole part keeps the mesh it had; a part's
## cut-off end is meshed on a worker thread and shows a frame or two later) and a box round each part's share, so it
## tumbles, bounces and lies on the floor. Once it comes to rest it's made a body again (a VoxelBody fragment, dead,
## posed where it lay), so every weapon can go on cutting it up (the owner, 20 Oct: "always cut up the body"); knocked
## flying, a fragment is a piece again. The vacuum's brush pulls pieces, fragments and corpses apart into cubes. Owned
## by the voxel session; every melee weapon spawns through the arena's one VoxelPieces.

static var MAX_PIECES := 30      # (the settings set it: VoxelSettings)
const PIECE_LIFE := 600.0       # they lie there a good while (the vacuum takes them)
const REST_V := 0.12            # m/s (and radians a second) under which a piece counts as lying still ...
const REST_T := 0.35            # ... for this long: then it's made a body to cut up

var arena: Node3D
## Co-op: the host's is told every piece made, func(body, list, vel, spin, rb), and every piece that came to rest as a
## fragment body, func(rb, fragment); a guest's pieces are copies the host's positions move (puppet: no physics of
## their own, they never settle or go by themselves).
var net_rec: Callable
var net_rec_frag: Callable
var puppet := false
var _pieces := []               # [{rb, t, still, cells: [{part, grid, origin, local, mi}], vm, key, chunk}]
var _mesh_jobs := []            # [{id, out: {arrays}, mi: WeakRef}]

func setup(arena_: Node3D) -> void:
	arena = arena_

func count() -> int:
	return _pieces.size()

## Everything one hit took off body b (a slice / carve result's pieces) as one rigid body, flung at vel and spinning
## at spin (radians a second, world axis * speed). Returns the rigid body (null if there was nothing).
func spawn(b: VoxelBody, list: Array, vel: Vector3, spin: Vector3) -> RigidBody3D:
	if puppet and not VoxelBody._net_replay:
		return null                # (a guest's: the host's pieces come as copies, spawn_copy)
	var rb := _make(b.vm, b.key, b.chunk_n, b.knock, list, vel, spin)
	if rb and net_rec.is_valid():
		net_rec.call(b, list, vel + b.knock * 0.5, spin, rb)
	return rb

## A guest's copy of one of the host's pieces: the same cubes, moved by the host's positions (no physics).
func spawn_copy(key: String, chunk: int, vm: float, list: Array, xform: Transform3D) -> RigidBody3D:
	var rb := _make(vm, key, chunk, Vector3.ZERO, list, Vector3.ZERO, Vector3.ZERO)
	if rb:
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
		rb.global_transform = xform
	return rb

func _make(vm: float, key: String, chunk: int, knock: Vector3, list: Array, vel: Vector3, spin: Vector3) -> RigidBody3D:
	var centre := Vector3.ZERO
	var count_c := 0
	for e in list:
		if int(e.count) <= 0:
			continue
		centre += (e.xform as Transform3D) * (e.box_at as Vector3) * int(e.count)
		count_c += int(e.count)
	if count_c == 0:
		return null
	centre /= float(count_c)
	var rb := RigidBody3D.new()
	rb.collision_layer = 2
	rb.collision_mask = 1
	rb.mass = clampf(count_c * 0.002, 0.3, 30.0)
	rb.continuous_cd = true
	arena.add_child(rb)
	rb.global_transform = Transform3D(Basis.IDENTITY, centre)
	var inv := rb.global_transform.affine_inverse()
	var keep := []
	for e in list:
		if int(e.count) <= 0:
			continue
		var local := inv * (e.xform as Transform3D)
		var mi := MeshInstance3D.new()
		keep.append({"part": String(e.get("part", "")), "grid": e.grid, "origin": e.origin, "local": local, "mi": mi})
		mi.material_override = arena._mat
		mi.transform = local
		rb.add_child(mi)
		if e.has("mesh") and e.mesh != null:
			mi.mesh = e.mesh
		else:
			var g: Dictionary = e.grid
			var o: Vector3 = e.origin
			var out := {}
			var id := WorkerThreadPool.add_task(func(): out["arrays"] = VoxMesher.mesh(g, o, vm))
			_mesh_jobs.append({"id": id, "out": out, "mi": weakref(mi)})
		# a part that came off at its joint (not cut through): a torn end there, not a flat face
		if bool(e.get("seam", false)):
			var cols := VoxelBody.seam_cols(e.grid.cells, e.grid.size, -(e.origin as Vector3) - Vector3(0.5, 0.5, 0.5), true,
				bool(e.get("limb", false)), randi())
			if not cols.is_empty():
				var sm := VoxelBody.seam_mesh(cols, e.origin, vm)
				sm.transform = local
				rb.add_child(sm)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = (e.box as Vector3).max(Vector3.ONE * vm * 2.0)
		cs.shape = bx
		cs.transform = local * Transform3D(Basis.IDENTITY, e.box_at)
		rb.add_child(cs)
	rb.linear_velocity = vel + knock * 0.5
	rb.angular_velocity = spin
	_pieces.append({"rb": rb, "t": 0.0, "still": 0.0, "cells": keep, "vm": vm, "key": key, "chunk": chunk})
	while _pieces.size() > MAX_PIECES:
		(_pieces[0].rb as RigidBody3D).queue_free()
		_pieces.remove_at(0)
	return rb

## Every piece, newest last: [{rb, t, cells, vm}] (a weapon may push them about).
func list() -> Array:
	return _pieces

func step(dt: float) -> void:
	_poll_meshes()
	if puppet:
		_pieces = _pieces.filter(func(pc): return is_instance_valid(pc.rb))
		return
	for i in range(_pieces.size() - 1, -1, -1):
		var pc: Dictionary = _pieces[i]
		pc.t += dt
		if not is_instance_valid(pc.rb):      # (freed by something else: a typed assignment of it would fail)
			_pieces.remove_at(i)
			continue
		var rb: RigidBody3D = pc.rb
		if rb.global_position.y < -3.0:
			# knocked over the walls: nothing out there to land on
			rb.queue_free()
			_pieces.remove_at(i)
			continue
		pc.still = float(pc.still) + dt if rb.linear_velocity.length() < REST_V and rb.angular_velocity.length() < REST_V * 2.0 else 0.0
		# lying still, or (after a moment) just rocking about on the floor: a body to cut up
		var rocking := float(pc.t) > 1.5 and rb.global_position.y < 0.7 and rb.linear_velocity.length() < 0.5 and rb.angular_velocity.length() < 1.5
		if (float(pc.still) >= REST_T and float(pc.t) > 0.6) or rocking:
			_settle(i)
			continue
		if pc.t > PIECE_LIFE:
			var k := clampf(1.0 - (pc.t - PIECE_LIFE) / 0.5, 0.0, 1.0)
			for c in rb.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).scale = Vector3.ONE * maxf(0.01, k)
			if k <= 0.0:
				rb.queue_free()
				_pieces.remove_at(i)

# piece i lying still: a dead body of its own (only its parts, each where it lies) takes its place
func _settle(i: int) -> void:
	var pc: Dictionary = _pieces[i]
	var rb: RigidBody3D = pc.rb
	_pieces.remove_at(i)
	var grids := {}
	var xforms := {}
	for e in pc.cells:
		var n := String(e.part)
		if n == "":
			continue
		var cells: PackedInt32Array = e.grid.cells
		if grids.has(n):
			# two lumps of the same part: one grid
			var both: PackedInt32Array = (grids[n].cells as PackedInt32Array).duplicate()
			for j in cells.size():
				if cells[j] != 0:
					both[j] = cells[j]
			grids[n] = {"cells": both, "mesh": null}
		else:
			var mi: MeshInstance3D = e.mi
			var mesh: Mesh = mi.mesh if is_instance_valid(mi) and mi.mesh != null and mi.mesh.get_surface_count() > 0 else null
			grids[n] = {"cells": cells, "mesh": mesh}
		xforms[n] = rb.global_transform * (e.local as Transform3D)
	if grids.is_empty():
		rb.queue_free()
		return
	var f := VoxelBody.new()
	arena.add_child(f)
	f.setup(String(pc.key), float(pc.vm), int(pc.chunk), arena._mat)
	f.global_position = Vector3(rb.global_position.x, 0.0, rb.global_position.z)
	f.make_fragment(grids, xforms)
	arena.bodies.append(f)
	if net_rec_frag.is_valid():
		net_rec_frag.call(rb, f, grids, xforms)
	rb.queue_free()

## A fragment knocked flying (b.airborne, the bat, a slam): a piece again, flying off at its air speed.
func from_fragment(b: VoxelBody) -> void:
	var list := b.as_pieces()
	arena.bodies.erase(b)
	if not list.is_empty():
		spawn(b, list, b.air_v, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * b.tumble_v)
	b.queue_free()

## The vacuum gun's brush (a sphere at brush, r metres): pieces, fragments and corpses inside it come apart into their
## cubes, which go up the beam. for_other: the other player's vacuum (the host's game, for a guest): what was in them
## is given to them (VoxelStorages.give_other), none of it flies here.
func vacuum(brush: Vector3, r: float, for_other := false) -> void:
	var theirs := {}                     # item id -> how many (for_other)
	if puppet:
		if arena.net:
			arena.net.send_vac(brush, r)      # (a guest's: the host's vacuum takes them, for this player)
		return
	for b in arena.bodies.duplicate():
		if b.alive or not is_instance_valid(b):
			continue
		var near := false
		for n in b.parts:
			var p: Dictionary = b.parts[n]
			if p.gone:
				continue
			var mi: MeshInstance3D = p.mesh
			if mi.mesh and (mi.global_transform * mi.mesh.get_aabb().get_center()).distance_to(brush) <= r + 0.25:
				near = true
				break
		if not near:
			continue
		var counts := {}
		var bits: Array = b.cubes(400, counts)
		if for_other:
			_count_into(theirs, bits, counts)
		else:
			arena.debris.suck(bits)
			_take(counts)
		arena.bodies.erase(b)
		b.queue_free()
	for i in range(_pieces.size() - 1, -1, -1):
		var pc: Dictionary = _pieces[i]
		if not is_instance_valid(pc.rb):
			continue
		var rb: RigidBody3D = pc.rb
		if pc.t < 0.4 or rb.global_position.distance_to(brush) > r + 0.3:
			continue
		# a few hundred fly in; the rest count straight away, a colour at a time
		var counts := {}
		var bits := cubes_of(pc, 400, counts)
		if for_other:
			_count_into(theirs, bits, counts)
		else:
			arena.debris.suck(bits)
			_take(counts)
		rb.queue_free()
		_pieces.remove_at(i)
	if for_other and not theirs.is_empty():
		arena.stash.give_other(theirs)

# cubes counted by cell value (a colour + 1) into the backpack, a colour at a time
func _take(counts: Dictionary) -> void:
	for v in counts:
		var k := int(v) - 1
		arena.debris.take(Color8((k >> 16) & 255, (k >> 8) & 255, k & 255), int(counts[v]))

# a guest's share: the cubes that would have flown plus the ones counted, as items
static func _count_into(out: Dictionary, bits: Array, counts: Dictionary) -> void:
	for bt in bits:
		var id := VoxelItems.of_colour(bt.col)
		out[id] = int(out.get(id, 0)) + 1
	for v in counts:
		var k := int(v) - 1
		var id2 := VoxelItems.of_colour(Color8((k >> 16) & 255, (k >> 8) & 255, k & 255))
		out[id2] = int(out.get(id2, 0)) + int(counts[v])

## A piece's cubes where they are now: [{pos, col}]; with most > 0 only about that many, spread through it, the rest
## counted into counts (cell value -> how many).
static func cubes_of(pc: Dictionary, most: int = 0, counts: Dictionary = {}) -> Array:
	var bits := []
	var total := 0
	for e in pc.cells:
		for v in (e.grid.cells as PackedInt32Array):
			if v != 0:
				total += 1
	var every := maxi(1, ceili(float(total) / float(most))) if most > 0 else 1
	var seen := 0
	var rb: RigidBody3D = pc.rb
	var vm: float = pc.vm
	for e in pc.cells:
		var g: Dictionary = e.grid
		var s: Vector3i = g.size
		var cells: PackedInt32Array = g.cells
		var xf: Transform3D = rb.global_transform * (e.local as Transform3D)
		var o: Vector3 = e.origin
		var j := 0
		for z in s.z:
			for y in s.y:
				for x in s.x:
					var v := cells[j]
					if v != 0:
						if seen % every == 0:
							var k := v - 1
							bits.append({"pos": xf * ((Vector3(x, y, z) + o + Vector3(0.5, 0.5, 0.5)) * vm),
								"col": Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)})
						else:
							counts[v] = int(counts.get(v, 0)) + 1
						seen += 1
					j += 1
	return bits

# pieces' meshes made on worker threads: swapped in when done
func _poll_meshes() -> void:
	for i in range(_mesh_jobs.size() - 1, -1, -1):
		var j: Dictionary = _mesh_jobs[i]
		if not WorkerThreadPool.is_task_completed(j.id):
			continue
		WorkerThreadPool.wait_for_task_completion(j.id)
		var mi = (j.mi as WeakRef).get_ref()
		if mi and is_instance_valid(mi) and j.out.has("arrays") and not (j.out.arrays.verts as PackedVector3Array).is_empty():
			(mi as MeshInstance3D).mesh = VoxelBody.array_mesh(j.out.arrays)
		_mesh_jobs.remove_at(i)

## Waits for any piece still being meshed (before quitting).
func finish_jobs() -> void:
	for j in _mesh_jobs:
		WorkerThreadPool.wait_for_task_completion(j.id)
	_mesh_jobs.clear()

func _exit_tree() -> void:
	finish_jobs()
