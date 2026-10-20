class_name VoxelSword
extends Node3D
## The sword (the owner, 20 Oct): a slash is a flat sweep of the blade, the plane through your eye along where you
## look and the way you swing. Every cube the blade passes through is cut out (VoxelBody.slice), and whatever that
## leaves hanging comes off whole: an arm, half a forearm, a leg at the knee, the top of a head, the head. The bits
## that come off are real pieces (rigid bodies with their own meshes) that tumble, bounce and lie on the floor.
## A hit freezes the game for a blink (hit-stop) so the cut lands heavy. Owned by the voxel session.

const REACH := 2.6              # metres from the eye the blade reaches
const COS_ARC := 0.17           # the sweep: 80 degrees each side of where you look
const SWING_T := 0.2            # seconds a swing takes
const CUT_AT := 0.06            # seconds in when the blade passes through
const BACK_T := 0.18            # seconds back to rest after
const COOLDOWN := 0.38
const MAX_PIECES := 30
const PIECE_LIFE := 600.0       # they lie there a good while (the vacuum takes them)
const ARC := 1.35               # radians the blade sweeps each side

var arena: Node3D
var view: Node3D                # the blade in hand (first person), on the camera
var _blade: Node3D
var _trail: MeshInstance3D
var _t := -1.0                  # seconds into the swing (-1: at rest)
var _eye := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _side := Vector3.RIGHT
var _n := Vector3.UP
var _apex := Vector3.ZERO       # where the swoosh fans out from (the hand, not the eye, so it isn't seen edge-on)
var _side_cam := Vector3.RIGHT  # the swing's direction in the camera's own space (for the blade in hand)
var _cut_done := false
var _cd := 0.0
var _pieces := []               # [{rb: RigidBody3D, t: float, cells: [{grid, origin, local}], vm}]
var _mesh_jobs := []            # [{id, out: {arrays}, mi: WeakRef}]
var _stop_n := 0
var last := {}                  # the last cut, for the self-test: {cut, parts, pieces, killed}

func setup(arena_: Node3D, cam: Camera3D) -> void:
	arena = arena_
	view = Node3D.new()
	cam.add_child(view)
	_blade = Node3D.new()
	view.add_child(_blade)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.8, 0.85)
	steel.metallic = 0.9
	steel.roughness = 0.22
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.55, 0.42, 0.15)
	gold.metallic = 0.7
	gold.roughness = 0.4
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.22, 0.12, 0.07)
	grip.roughness = 0.9
	# a blocky sword like the rest: blade, guard, grip and pommel, held at the grip (the node's origin)
	_part(Vector3(0.045, 0.95, 0.01), Vector3(0, 0.6, 0), steel)
	_part(Vector3(0.02, 0.06, 0.012), Vector3(0, 1.1, 0), steel)
	_part(Vector3(0.2, 0.03, 0.04), Vector3(0, 0.11, 0), gold)
	_part(Vector3(0.035, 0.17, 0.035), Vector3(0, 0.01, 0), grip)
	_part(Vector3(0.055, 0.045, 0.055), Vector3(0, -0.09, 0), gold)
	view.visible = false
	_trail = MeshInstance3D.new()
	_trail.mesh = ImmediateMesh.new()
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.vertex_color_use_as_albedo = true
	_trail.material_override = tm
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.top_level = true
	add_child(_trail)
	_rest_pose()

func _part(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blade.add_child(mi)

func ready_to_swing() -> bool:
	return _cd <= 0.0

func swinging() -> bool:
	return _t >= 0.0 and _t < SWING_T

## Starts a slash: from eye along fwd, the blade travelling side (both world, at right angles); apex is where the
## swoosh is drawn from; side_cam is side in the camera's own space (the blade in hand follows it).
func swing(eye: Vector3, fwd: Vector3, side: Vector3, apex: Vector3, side_cam: Vector3) -> void:
	_eye = eye
	_fwd = fwd.normalized()
	_side = (side - _fwd * side.dot(_fwd)).normalized()
	_n = _fwd.cross(_side).normalized()
	_apex = apex
	_side_cam = side_cam.normalized()
	_t = 0.0
	_cut_done = false
	_cd = COOLDOWN

func step(dt: float) -> void:
	_cd = maxf(0.0, _cd - dt)
	if _t >= 0.0:
		_t += dt
		if not _cut_done and _t >= CUT_AT:
			_cut_done = true
			_cut()
		if _t >= SWING_T + BACK_T:
			_t = -1.0
	_poll_meshes()
	_pose_blade()
	_draw_trail()
	for i in range(_pieces.size() - 1, -1, -1):
		var pc: Dictionary = _pieces[i]
		pc.t += dt
		var rb: RigidBody3D = pc.rb
		if pc.t > PIECE_LIFE:
			var k := clampf(1.0 - (pc.t - PIECE_LIFE) / 0.5, 0.0, 1.0)
			for c in rb.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).scale = Vector3.ONE * maxf(0.01, k)
			if k <= 0.0:
				rb.queue_free()
				_pieces.remove_at(i)

## The vacuum gun at nozzle pointing aim: pieces close in front of it come apart into their cubes, which fly in.
func vacuum(nozzle: Vector3, aim: Vector3) -> void:
	for i in range(_pieces.size() - 1, -1, -1):
		var pc: Dictionary = _pieces[i]
		var rb: RigidBody3D = pc.rb
		var to := rb.global_position - nozzle
		var d := to.length()
		if pc.t < 0.4 or d > 4.0 or (d > 1.0 and to.dot(aim) < d * 0.85):
			continue
		var bits := []
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
		# a few hundred fly in; the rest count straight away
		bits.shuffle()
		arena.debris.suck(bits.slice(0, 400))
		for bt in bits.slice(400):
			arena.debris.take(bt.col)
		rb.queue_free()
		_pieces.remove_at(i)

func pieces() -> int:
	return _pieces.size()

# ---------------------------------------------------------------- the cut

func _cut() -> void:
	var t0 := Time.get_ticks_usec()
	var hit := false
	var res_all := {"cut": 0, "parts": [], "pieces": 0, "killed": false}
	for b in arena.bodies:
		var flat := Vector2(b.global_position.x - _eye.x, b.global_position.z - _eye.z)
		if flat.length() > REACH + 0.8:
			continue
		var ts := Time.get_ticks_usec()
		var r: Dictionary = b.slice(_eye, _n, _fwd, REACH, COS_ARC, b.vm * 0.9)
		res_all["slice_ms"] = snappedf((Time.get_ticks_usec() - ts) / 1000.0, 0.1)
		if int(r.cut) == 0 and (r.pieces as Array).is_empty():
			continue
		hit = true
		res_all.cut += int(r.cut)
		res_all.parts.append_array(r.parts)
		res_all.pieces += (r.pieces as Array).size()
		res_all.killed = res_all.killed or bool(r.killed)
		arena.knocked += int(r.cut)
		arena.debris.burst(r.bits, _side, 2.2)
		if not (r.pieces as Array).is_empty():
			_piece(b, r.pieces)
		if b.alive and not (r.parts as Array).is_empty():
			b.hit_react(_side, 30, String(r.parts[0]))
	res_all["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	last = res_all
	if hit:
		arena._kick = 0.5
		_hit_stop()

# everything one cut took off one body: one rigid body, a mesh for each part's share (a whole part keeps the mesh
# it had; a part's cut-off end is meshed on a worker thread and shows a frame or two later), a box round each
func _piece(b: VoxelBody, list: Array) -> void:
	var vm: float = b.vm
	var centre := Vector3.ZERO
	var count := 0
	for e in list:
		if int(e.count) <= 0:
			continue
		centre += (e.xform as Transform3D) * (e.box_at as Vector3) * int(e.count)
		count += int(e.count)
	if count == 0:
		return
	centre /= float(count)
	var rb := RigidBody3D.new()
	rb.collision_layer = 2
	rb.collision_mask = 1
	rb.mass = clampf(count * 0.002, 0.3, 30.0)
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
	# flung the way the blade went, a little up, spinning in the swing
	rb.linear_velocity = _side * randf_range(1.6, 2.8) + Vector3.UP * randf_range(1.0, 2.2) + b.knock * 0.5
	rb.angular_velocity = _n * randf_range(4.0, 8.0) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	_pieces.append({"rb": rb, "t": 0.0, "cells": keep, "vm": vm})
	while _pieces.size() > MAX_PIECES:
		(_pieces[0].rb as RigidBody3D).queue_free()
		_pieces.remove_at(0)

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

# the game all but stops for a blink as the blade bites
func _hit_stop() -> void:
	_stop_n += 1
	var me := _stop_n
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.07, true, false, true).timeout
	if me == _stop_n:
		Engine.time_scale = 1.0

# ---------------------------------------------------------------- the look

func _rest_pose() -> void:
	_blade.transform = Transform3D(Basis.from_euler(Vector3(-0.55, 0.25, -0.35)), Vector3(0.3, -0.32, -0.42))

# the blade in hand: at rest low on the right; in a swing it sweeps across the view along the swing, edge first
func _swing_xform(th: float) -> Transform3D:
	var f := Vector3(0, 0, -1)
	var s := _side_cam
	var nl := f.cross(s).normalized()
	var dir := (f * cos(th) + s * sin(th)).normalized()
	var tg := (-f * sin(th) + s * cos(th)).normalized()
	var bs := Basis(tg, dir, tg.cross(dir).normalized())
	var at := Vector3(0.06, -0.24, -0.12) - nl * 0.06 + dir * 0.12
	return Transform3D(bs, at)

func _pose_blade() -> void:
	if _t < 0.0:
		_rest_pose()
		return
	var rest := Transform3D(Basis.from_euler(Vector3(-0.55, 0.25, -0.35)), Vector3(0.3, -0.32, -0.42))
	if _t < SWING_T:
		var k := _t / SWING_T
		var th := lerpf(-ARC, ARC, k * k * (3.0 - 2.0 * k))
		var x := _swing_xform(th)
		# the first moment: from rest up into the wind-up
		var w := clampf(_t / 0.04, 0.0, 1.0)
		_blade.transform = rest.interpolate_with(x, w) if w < 1.0 else x
	else:
		var k2 := clampf((_t - SWING_T) / BACK_T, 0.0, 1.0)
		_blade.transform = _swing_xform(ARC).interpolate_with(rest, k2 * k2 * (3.0 - 2.0 * k2))

# the swoosh: a fan in the swing's plane from the hand, bright at the blade, fading behind it
func _draw_trail() -> void:
	var im: ImmediateMesh = _trail.mesh
	im.clear_surfaces()
	if _t < 0.0 or _t > SWING_T + 0.1:
		return
	var k := clampf(_t / SWING_T, 0.0, 1.0)
	var th1 := lerpf(-ARC, ARC, k * k * (3.0 - 2.0 * k))
	var fade := 1.0 - clampf((_t - SWING_T) / 0.1, 0.0, 1.0)
	var th0 := maxf(-ARC, th1 - 1.6)
	var steps := 14
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in steps + 1:
		var th := lerpf(th0, th1, float(i) / steps)
		var a := float(i) / steps
		var dir := (_fwd * cos(th) + _side * sin(th)).normalized()
		var c := Color(0.9, 0.95, 1.0, 0.45 * a * a * fade)
		im.surface_set_color(c)
		im.surface_add_vertex(_apex + dir * 0.45)
		im.surface_set_color(Color(c.r, c.g, c.b, c.a * 0.3))
		im.surface_add_vertex(_apex + dir * (REACH * 0.85))
	im.surface_end()

func _exit_tree() -> void:
	finish_jobs()
	Engine.time_scale = 1.0
