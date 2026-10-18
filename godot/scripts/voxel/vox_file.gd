class_name VoxFile
extends RefCounted
## A MagicaVoxel .vox file (one model): its size, voxels and palette. Reads and writes the SIZE / XYZI / RGBA chunks
## (version 150, what MagicaVoxel saves; other chunks are skipped). Owned by the voxel session.
##
## Axes: a .vox stores (vx, vy, vz) with z up. The characters' files (assets/voxel/<char>/*.vox, built by
## assets/voxel/tools/vox_build.py) keep the model upright with its front toward -y, so model (x, y, z) =
## (vx, vz, sy - 1 - vy): x across (the character's left), y up, z forward. cell()/model_grid() hand back model axes.

## Grid size in .vox axes (x, y = depth, z = up).
var size: Vector3i = Vector3i.ZERO
## Voxels as [vx, vy, vz, colour index 1..255] packed in one array, 4 bytes each.
var xyzi: PackedByteArray = PackedByteArray()
## 256 colours; colour index i (1..255) is palette[i - 1], as in the file.
var palette: PackedColorArray = PackedColorArray()

func count() -> int:
	return xyzi.size() / 4

## Reads a .vox file; null if it can't (missing, not a .vox, no model).
static func load_file(path: String) -> VoxFile:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return parse(f.get_buffer(f.get_length()))

static func parse(data: PackedByteArray) -> VoxFile:
	if data.size() < 20 or data.slice(0, 4).get_string_from_ascii() != "VOX ":
		return null
	var v := VoxFile.new()
	var i := 8
	var got_size := false
	while i + 12 <= data.size():
		var id := data.slice(i, i + 4).get_string_from_ascii()
		var n := data.decode_s32(i + 4)
		var kids := data.decode_s32(i + 8)
		var body := i + 12
		if id == "MAIN":
			i = body
			continue
		match id:
			"SIZE":
				if not got_size:
					v.size = Vector3i(data.decode_s32(body), data.decode_s32(body + 4), data.decode_s32(body + 8))
					got_size = true
			"XYZI":
				if v.xyzi.is_empty():
					var k := data.decode_s32(body)
					v.xyzi = data.slice(body + 4, body + 4 + k * 4)
			"RGBA":
				v.palette.resize(256)
				for j in 256:
					var o := body + j * 4
					v.palette[j] = Color8(data[o], data[o + 1], data[o + 2], data[o + 3])
		i = body + n + kids
	if not got_size:
		return null
	if v.palette.is_empty():
		v.palette = default_palette()
	return v

## Writes the file (SIZE, XYZI, RGBA), as MagicaVoxel reads it.
func save_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(to_bytes())
	return OK

func to_bytes() -> PackedByteArray:
	var size_c := _chunk("SIZE", _ints([size.x, size.y, size.z]), PackedByteArray())
	var xy := _ints([count()])
	xy.append_array(xyzi)
	var xyzi_c := _chunk("XYZI", xy, PackedByteArray())
	var pal := PackedByteArray()
	pal.resize(1024)
	for j in 256:
		var c: Color = palette[j] if j < palette.size() else Color.BLACK
		pal[j * 4] = c.r8
		pal[j * 4 + 1] = c.g8
		pal[j * 4 + 2] = c.b8
		pal[j * 4 + 3] = c.a8 if j < palette.size() else 255
	var kids := size_c
	kids.append_array(xyzi_c)
	kids.append_array(_chunk("RGBA", pal, PackedByteArray()))
	var out := "VOX ".to_ascii_buffer()
	out.append_array(_ints([150]))
	out.append_array(_chunk("MAIN", PackedByteArray(), kids))
	return out

static func _ints(a: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(a.size() * 4)
	for j in a.size():
		b.encode_s32(j * 4, int(a[j]))
	return b

static func _chunk(id: String, content: PackedByteArray, kids: PackedByteArray) -> PackedByteArray:
	var b := id.to_ascii_buffer()
	b.append_array(_ints([content.size(), kids.size()]))
	b.append_array(content)
	b.append_array(kids)
	return b

## MagicaVoxel's palette when a file has none: index i is a 6x6x6 cube colour (close enough; our files carry theirs).
static func default_palette() -> PackedColorArray:
	var p := PackedColorArray()
	p.resize(256)
	for j in 256:
		var k := j % 216
		p[j] = Color8(255 - (k % 6) * 51, 255 - ((k / 6) % 6) * 51, 255 - (k / 36) * 51)
	return p

## The model as a dense grid in model axes: {size: Vector3i (x, y up, z forward), cells: PackedInt32Array of
## 0 (empty) or 0xRRGGBB + 1}, index x + size.x * (y + size.y * z).
func model_grid() -> Dictionary:
	var ms := Vector3i(size.x, size.z, size.y)
	var cells := PackedInt32Array()
	cells.resize(ms.x * ms.y * ms.z)
	var n := count()
	for j in n:
		var o := j * 4
		var vx := xyzi[o]
		var vy := xyzi[o + 1]
		var vz := xyzi[o + 2]
		var ci := xyzi[o + 3]
		if vx >= size.x or vy >= size.y or vz >= size.z or ci == 0:
			continue
		var c: Color = palette[ci - 1]
		var mz := size.y - 1 - vy
		cells[vx + ms.x * (vz + ms.y * mz)] = ((c.r8 << 16) | (c.g8 << 8) | c.b8) + 1
	return {"size": ms, "cells": cells}

## A VoxFile from a model-axes grid (the inverse of model_grid; colours beyond 255 are merged to the nearest).
static func from_model_grid(g: Dictionary) -> VoxFile:
	var ms: Vector3i = g.size
	var cells: PackedInt32Array = g.cells
	var v := VoxFile.new()
	v.size = Vector3i(ms.x, ms.z, ms.y)
	var index := {}
	var cols: Array[int] = []
	for c in cells:
		if c != 0 and not index.has(c) and cols.size() < 255:
			index[c] = cols.size() + 1
			cols.append(c)
	v.palette.resize(256)
	for j in 256:
		if j < cols.size():
			var k := cols[j] - 1
			v.palette[j] = Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)
		else:
			v.palette[j] = Color.BLACK
	var out := PackedByteArray()
	for z in ms.z:
		for y in ms.y:
			for x in ms.x:
				var c := cells[x + ms.x * (y + ms.y * z)]
				if c == 0:
					continue
				var ci: int = index.get(c, 0)
				if ci == 0:
					ci = _nearest(cols, c)
				out.append(x)
				out.append(ms.z - 1 - z)
				out.append(y)
				out.append(ci)
	v.xyzi = out
	return v

static func _nearest(cols: Array[int], c: int) -> int:
	var best := 1
	var bd := 1 << 30
	var k := c - 1
	for j in cols.size():
		var q := cols[j] - 1
		var d := absi(((q >> 16) & 255) - ((k >> 16) & 255)) + absi(((q >> 8) & 255) - ((k >> 8) & 255)) + absi((q & 255) - (k & 255))
		if d < bd:
			bd = d
			best = j + 1
	return best
