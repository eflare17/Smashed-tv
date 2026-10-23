class_name VoxelSculpt
extends RefCounted
## Block characters sculpted in code (the owner, 23 Oct: "rebuild from scratch, do Jared first"), not stretched out
## of flat pictures: each part a set of smooth shapes (signed distance functions: ellipsoids, capsules, rounded boxes,
## blended together), filled with cubes at the model's own voxel size, each surface cube painted by what it is and
## shaded a little by which way it faces and how tucked in it is (creases darker), so it reads as a solid figure
## from every side. The models' rigs (bones, pivots) are kept, so they move as before; only the parts' cubes are new.
## part(ch, name) gives a built part's {grid, origin} (model voxels) or {} (the part from its file as before);
## VoxelModel asks for models with "built" (VoxelModel.VARIANTS). Owned by the voxel session.

const LIGHT := Vector3(0.35, 0.8, 0.5)     # where the painted shading's light comes from (up, a little forward)

static func part(ch: String, name: String) -> Dictionary:
	match ch:
		"jared":
			return JaredBuild.part(name)
		"goth":
			return GothBuild.part(name)
	return {}

# ---------------------------------------------------------------- distance functions (negative inside, in voxels)

static func ellipsoid(p: Vector3, c: Vector3, r: Vector3) -> float:
	var q := (p - c) / r
	var k0 := q.length()
	var k1 := ((p - c) / (r * r)).length()
	if k1 < 1e-6:
		return -minf(r.x, minf(r.y, r.z))
	return k0 * (k0 - 1.0) / k1

static func capsule(p: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / maxf(1e-6, ba.dot(ba)), 0.0, 1.0)
	return (pa - ba * h).length() - r

## A capsule whose radius goes from ra at a to rb at b (a limb tapering).
static func cone_capsule(p: Vector3, a: Vector3, b: Vector3, ra: float, rb: float) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / maxf(1e-6, ba.dot(ba)), 0.0, 1.0)
	return (pa - ba * h).length() - lerpf(ra, rb, h)

static func round_box(p: Vector3, c: Vector3, half: Vector3, r: float) -> float:
	var q := (p - c).abs() - half + Vector3(r, r, r)
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - r

## Two shapes blended into one with a fillet of about k voxels where they meet.
static func smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)

static func smax(a: float, b: float, k: float) -> float:
	return -smin(-a, -b, k)

## A repeatable noise (0..1) at a voxel: texture.
static func hash3(x: float, y: float, z: float) -> float:
	var h := int(floor(x) * 73856093) ^ int(floor(y) * 19349663) ^ int(floor(z) * 83492791)
	return float(absi(h) % 1009) / 1009.0

## Smooth value noise (0..1) at a point, s voxels a cell.
static func noise3(p: Vector3, s: float) -> float:
	var q := p / s
	var i := q.floor()
	var f := q - i
	f = f * f * (Vector3(3, 3, 3) - 2.0 * f)
	var n000 := hash3(i.x, i.y, i.z)
	var n100 := hash3(i.x + 1, i.y, i.z)
	var n010 := hash3(i.x, i.y + 1, i.z)
	var n110 := hash3(i.x + 1, i.y + 1, i.z)
	var n001 := hash3(i.x, i.y, i.z + 1)
	var n101 := hash3(i.x + 1, i.y, i.z + 1)
	var n011 := hash3(i.x, i.y + 1, i.z + 1)
	var n111 := hash3(i.x + 1, i.y + 1, i.z + 1)
	return lerpf(lerpf(lerpf(n000, n100, f.x), lerpf(n010, n110, f.x), f.y),
		lerpf(lerpf(n001, n101, f.x), lerpf(n011, n111, f.x), f.y), f.z)

# ---------------------------------------------------------------- filling a part

## Fills the box lo..hi (model voxels, hi exclusive) with cubes where sdf(p) <= 0 (p: the cube's middle). Each surface
## cube is painted paint(p, n, ao) -> Color (n the surface's way out, ao 0 open .. 1 tucked in); inside cubes get
## the colour of the nearest painted surface (not seen; the gore shows flesh anyway). -> {grid, origin}
## ctx (optional): the shapes of the parts it meets (a distance function), so its creases against them shade too (an
## arm's inside darker where it meets his side), though they aren't its cubes.
static func fill(lo: Vector3i, hi: Vector3i, sdf: Callable, paint: Callable, ctx := Callable()) -> Dictionary:
	var s := hi - lo
	var n := s.x * s.y * s.z
	var dist := PackedFloat32Array()
	dist.resize(n)
	for z in s.z:
		for y in s.y:
			for x in s.x:
				dist[x + s.x * (y + s.y * z)] = float(sdf.call(Vector3(lo.x + x + 0.5, lo.y + y + 0.5, lo.z + z + 0.5)))
	var cells := PackedInt32Array()
	cells.resize(n)
	for z in s.z:
		for y in s.y:
			for x in s.x:
				var i := x + s.x * (y + s.y * z)
				if dist[i] > 0.0:
					continue
				# a surface cube: one of its six neighbours empty
				var surf := x == 0 or y == 0 or z == 0 or x == s.x - 1 or y == s.y - 1 or z == s.z - 1 \
					or dist[i - 1] > 0.0 or dist[i + 1] > 0.0 or dist[i - s.x] > 0.0 or dist[i + s.x] > 0.0 \
					or dist[i - s.x * s.y] > 0.0 or dist[i + s.x * s.y] > 0.0
				if not surf:
					cells[i] = 1                                # (filled in below)
					continue
				var p := Vector3(lo.x + x + 0.5, lo.y + y + 0.5, lo.z + z + 0.5)
				var gx := _d(dist, s, x + 1, y, z) - _d(dist, s, x - 1, y, z)
				var gy := _d(dist, s, x, y + 1, z) - _d(dist, s, x, y - 1, z)
				var gz := _d(dist, s, x, y, z + 1) - _d(dist, s, x, y, z - 1)
				var nrm := Vector3(gx, gy, gz)
				nrm = nrm.normalized() if nrm.length() > 1e-5 else Vector3.UP
				# how tucked in: the share of the cubes around it (3 out) that are solid, from about a half (flat) up
				var solid := 0
				var tot := 0
				for dz in range(-3, 4, 2):
					for dy in range(-3, 4, 2):
						for dx in range(-3, 4, 2):
							tot += 1
							if _d(dist, s, x + dx, y + dy, z + dz) <= 0.0:
								solid += 1
							elif ctx.is_valid() and float(ctx.call(p + Vector3(dx, dy, dz))) <= 0.0:
								solid += 1
				var ao := clampf((float(solid) / tot - 0.42) / 0.35, 0.0, 1.0)
				var c: Color = paint.call(p, nrm, ao)
				cells[i] = ((c.r8 << 16) | (c.g8 << 8) | c.b8) + 1
	# the inside: each column's colour from the surface in front of it
	for y in s.y:
		for x in s.x:
			var last := 0
			for z in range(s.z - 1, -1, -1):
				var i := x + s.x * (y + s.y * z)
				if cells[i] > 1:
					last = cells[i]
				elif cells[i] == 1:
					cells[i] = last if last > 1 else 0xA05040 + 1
	return {"grid": {"size": s, "cells": cells}, "origin": lo}

static func _d(dist: PackedFloat32Array, s: Vector3i, x: int, y: int, z: int) -> float:
	if x < 0 or y < 0 or z < 0 or x >= s.x or y >= s.y or z >= s.z:
		return 1.0
	return dist[x + s.x * (y + s.y * z)]

## A colour from a ramp (dark .. light) by how lit (0..1), with a little noise.
static func ramp(cols: Array, t: float) -> Color:
	t = clampf(t, 0.0, 0.999) * (cols.size() - 1)
	var i := int(t)
	return (cols[i] as Color).lerp(cols[mini(i + 1, cols.size() - 1)], t - i)

## How lit a surface is (0..1): facing the light, less where tucked in.
static func lit(n: Vector3, ao: float, flat := 0.55) -> float:
	return clampf(flat + 0.4 * n.dot(LIGHT.normalized()) - 0.55 * ao, 0.0, 1.0)
