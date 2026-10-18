class_name VoxMesher
extends RefCounted
## Greedy meshing: a voxel grid to as few quads as it takes (neighbouring faces of the same colour on the same plane
## merge into one rectangle), with per-vertex colours, so a whole character is one material and one draw call.
## Owned by the voxel session. All static.
##
## A grid is {size: Vector3i, cells: PackedInt32Array} with 0 for empty and 0xRRGGBB + 1 for a voxel, index
## x + size.x * (y + size.y * z) (VoxFile.model_grid gives one). Faces between two filled cells are never made.

## Builds the quads. origin: where cell (0, 0, 0)'s corner sits, in voxels; scale: metres per voxel.
## Returns {verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray (sRGB values),
## indices: PackedInt32Array, quads: int}.
static func mesh(g: Dictionary, origin: Vector3 = Vector3.ZERO, scale: float = 1.0) -> Dictionary:
	var s: Vector3i = g.size
	var cells: PackedInt32Array = g.cells
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var dims := [s.x, s.y, s.z]
	var strides := [1, s.x, s.x * s.y]
	var quads := 0
	for axis in 3:
		var ua: int = (axis + 1) % 3
		var va: int = (axis + 2) % 3
		var nA: int = dims[axis]
		var nU: int = dims[ua]
		var nV: int = dims[va]
		var sA: int = strides[axis]
		var sU: int = strides[ua]
		var sV: int = strides[va]
		var mask := PackedInt32Array()
		mask.resize(nU * nV)
		for di in 2:
			var dir: int = 1 - di * 2
			var nrm := Vector3.ZERO
			nrm[axis] = float(dir)
			for i in nA:
				# the faces on this slice's side
				var any := false
				var base := i * sA
				var has_next: bool = (i + dir) >= 0 and (i + dir) < nA
				var off: int = dir * sA
				for v in nV:
					var row := base + v * sV
					var mrow := v * nU
					for u in nU:
						var idx := row + u * sU
						var c := cells[idx]
						if c != 0 and (not has_next or cells[idx + off] == 0):
							mask[mrow + u] = c
							any = true
						else:
							mask[mrow + u] = 0
				if not any:
					continue
				var plane := float(i + (1 if dir > 0 else 0))
				for v in nV:
					var u := 0
					while u < nU:
						var c := mask[v * nU + u]
						if c == 0:
							u += 1
							continue
						var w := 1
						while u + w < nU and mask[v * nU + u + w] == c:
							w += 1
						var h := 1
						var grow := true
						while v + h < nV and grow:
							var r := (v + h) * nU
							for k in w:
								if mask[r + u + k] != c:
									grow = false
									break
							if grow:
								h += 1
						for hv in h:
							var r2 := (v + hv) * nU
							for k in w:
								mask[r2 + u + k] = 0
						_quad(verts, normals, colors, indices, axis, ua, va, plane, u, v, w, h, nrm, c, origin, scale, dir)
						quads += 1
						u += w
	return {"verts": verts, "normals": normals, "colors": colors, "indices": indices, "quads": quads}

static func _quad(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array,
		axis: int, ua: int, va: int, plane: float, u: int, v: int, w: int, h: int, nrm: Vector3, c: int, origin: Vector3,
		scale: float, dir: int) -> void:
	var k := c - 1
	var col := Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)
	var p := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var uv := [[u, v], [u + w, v], [u + w, v + h], [u, v + h]]
	for j in 4:
		var q := Vector3.ZERO
		q[axis] = plane
		q[ua] = float(uv[j][0])
		q[va] = float(uv[j][1])
		p[j] = (q + origin) * scale
	var b := verts.size()
	for j in 4:
		verts.append(p[j])
		normals.append(nrm)
		colors.append(col)
	# Godot draws clockwise faces as the front: (u, v, normal) is right-handed, so +dir needs the reverse order
	if dir > 0:
		indices.append_array([b, b + 2, b + 1, b, b + 3, b + 2])
	else:
		indices.append_array([b, b + 1, b + 2, b, b + 2, b + 3])

## Half the resolution (the phones' low look): a cell of the result is filled when at least half its eight are,
## coloured with their average.
static func downsample(g: Dictionary) -> Dictionary:
	var s: Vector3i = g.size
	var cells: PackedInt32Array = g.cells
	var n := Vector3i((s.x + 1) / 2, (s.y + 1) / 2, (s.z + 1) / 2)
	var out := PackedInt32Array()
	out.resize(n.x * n.y * n.z)
	for z in n.z:
		for y in n.y:
			for x in n.x:
				var cnt := 0
				var r := 0
				var gg := 0
				var b := 0
				for dz in 2:
					var zz := z * 2 + dz
					if zz >= s.z:
						continue
					for dy in 2:
						var yy := y * 2 + dy
						if yy >= s.y:
							continue
						for dx in 2:
							var xx := x * 2 + dx
							if xx >= s.x:
								continue
							var c := cells[xx + s.x * (yy + s.y * zz)]
							if c != 0:
								c -= 1
								cnt += 1
								r += (c >> 16) & 255
								gg += (c >> 8) & 255
								b += c & 255
				if cnt >= 3:
					out[x + n.x * (y + n.y * z)] = (((r / cnt) << 16) | ((gg / cnt) << 8) | (b / cnt)) + 1
	return {"size": n, "cells": out}

## Faces a grid would show without merging (for tests: greedy meshing must never make more quads than this).
static func face_count(g: Dictionary) -> int:
	var s: Vector3i = g.size
	var cells: PackedInt32Array = g.cells
	var n := 0
	for z in s.z:
		for y in s.y:
			for x in s.x:
				if cells[x + s.x * (y + s.y * z)] == 0:
					continue
				for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					var q: Vector3i = Vector3i(x, y, z) + d
					if q.x < 0 or q.y < 0 or q.z < 0 or q.x >= s.x or q.y >= s.y or q.z >= s.z or cells[q.x + s.x * (q.y + s.y * q.z)] == 0:
						n += 1
	return n
