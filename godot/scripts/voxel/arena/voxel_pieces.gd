class_name VoxelPieces
extends Node3D
## The bits a melee weapon takes off a body in one go (VoxelBody.slice / carve's "pieces"): an arm, half a forearm, a
## head, legs from the knee. Each is a real rigid body with its own meshes (a whole part keeps the mesh it had; a part's
## cut-off end is meshed on a worker thread and shows a frame or two later) and a box round each part's share, so it
## tumbles, bounces and lies on the floor. The vacuum's brush pulls them apart into cubes. Owned by the voxel session;
## every melee weapon spawns through the arena's one VoxelPieces.

const MAX_PIECES := 30
const PIECE_LIFE := 600.0       # they lie there a good while (the vacuum takes them)

var arena: Node3D
var _pieces := []               # [{rb: RigidBody3D, t: float, cells: [{grid, origin, local}], vm}]
var _mesh_jobs := []            # [{id, out: {arrays}, mi: WeakRef}]

func setup(arena_: Node3D) -> void:
	arena = arena_

func count() -> int:
	return _pieces.size()

## Everything one hit took off body b (a slice / carve result's pieces) as one rigid body, flung at vel and spinning
## at spin (radians a second, world axis * speed). Returns the rigid body (null if there was nothing).
func spawn(b: VoxelBody, list: Array, vel: Vector3, spin: Vector3) -> RigidBody3D:
	var vm: float = b.vm
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
		keep.append({"grid": e.grid, "origin": e.origin, "local": local})
		var mi := MeshInstance3D.new()
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
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = (e.box as Vector3).max(Vector3.ONE * vm * 2.0)
		cs.shape = bx
		cs.transform = local * Transform3D(Basis.IDENTITY, e.box_at)
		rb.add_child(cs)
	rb.linear_velocity = vel + b.knock * 0.5
	rb.angular_velocity = spin
	_pieces.append({"rb": rb, "t": 0.0, "cells": keep, "vm": vm})
	while _pieces.size() > MAX_PIECES:
		(_pieces[0].rb as RigidBody3D).queue_free()
		_pieces.remove_at(0)
	return rb

## Every piece, newest last: [{rb, t, cells, vm}] (a weapon may push them about).
func list() -> Array:
	return _pieces

func step(dt: float) -> void:
	_poll_meshes()
	for i in range(_pieces.size() - 1, -1, -1):
		var pc: Dictionary = _pieces[i]
		pc.t += dt
		var rb: RigidBody3D = pc.rb
		if not is_instance_valid(rb):
			_pieces.remove_at(i)
			continue
		if pc.t > PIECE_LIFE:
			var k := clampf(1.0 - (pc.t - PIECE_LIFE) / 0.5, 0.0, 1.0)
			for c in rb.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).scale = Vector3.ONE * maxf(0.01, k)
			if k <= 0.0:
				rb.queue_free()
				_pieces.remove_at(i)

## The vacuum gun's brush (a sphere at brush, r metres): pieces inside it come apart into their cubes, which go up the
## beam.
func vacuum(brush: Vector3, r: float) -> void:
	for i in range(_pieces.size() - 1, -1, -1):
		var pc: Dictionary = _pieces[i]
		var rb: RigidBody3D = pc.rb
		if pc.t < 0.4 or rb.global_position.distance_to(brush) > r + 0.3:
			continue
		var bits := cubes_of(pc)
		# a few hundred fly in; the rest count straight away
		bits.shuffle()
		arena.debris.suck(bits.slice(0, 400))
		for bt in bits.slice(400):
			arena.debris.take(bt.col)
		rb.queue_free()
		_pieces.remove_at(i)

## A piece's cubes where they are now: [{pos, col}].
static func cubes_of(pc: Dictionary) -> Array:
	var bits := []
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
						var k := v - 1
						bits.append({"pos": xf * ((Vector3(x, y, z) + o + Vector3(0.5, 0.5, 0.5)) * vm),
							"col": Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)})
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
