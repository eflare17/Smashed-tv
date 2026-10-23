class_name VoxelReshape
extends RefCounted
## Block characters made solid from every side (the owner, 23 Oct: Gothica's and Jared's side views "look bad", Jared
## "a bit blurry, a little off"). The models were made from flat front and back pictures, so seen from the side every
## part is a slab with square edges, each row of the picture stretched through it (stripes), the faces flat. This
## reshapes a part's grid (model axes: x across, y up, z forward) as it's loaded (VoxelModel.grid, for models with
## "reshape"), all in code:
## - roundify(): each part's slices (across, at each height) trimmed to a rounded oval, so limbs are round and bodies
##   bodies, not boxes;
## - recolour(): the cubes on its sides and tops (not the front or back pictures) coloured from what that height of
##   the front and the back is (the row's average, dark outlines and details left out, smoothed over neighbouring
##   rows), blended front to back: no stripes; the pictures' dark outline round the front's edge filled the same way;
##   hair gets strands running down instead;
## - joints(): limbs reach a little up into the part above, so a bent elbow or knee shows no gap;
## - face(): a nose, brow, lips and chin built out from the face (FACES), ears for whoever's hair doesn't cover them;
## - glasses(): the arms of a pair of glasses run back along the head.
## shape() gives the part's rounded shape (middle, half-sizes) for the shader's smooth shading (VoxelJiggle.shader:
## each part lit as the rounded thing it stands for, not its cubes' steps). Owned by the voxel session.

## How round each kind of part is made (a superellipse's power: 2 an oval, higher squarer); null: left alone.
const ROUND := {"torso": 2.5, "pelvis": 2.6, "skirt": 2.3, "head": 2.4, "arm": 2.1, "forearm": 2.1, "hand": 2.4,
	"thigh": 2.2, "shin": 2.1, "foot": 3.0}
## Limbs reaching up into the part above (cubes).
const JOINT := {"forearm": 3, "hand": 2, "shin": 3, "foot": 2}     # (not the shoulders or hips: nothing above to hide it)
## Faces (model voxels: y the model's own height, x from the head's middle column): each feature [bottom y, top y,
## half-width at the bottom, half-width at the top, cubes out at the bottom, cubes out at the top].
const FACES := {
	"jared": {"nose": [119, 123, 2, 1, 3, 1], "tash": [116, 119, 7, 6, 1, 1], "chin": [110, 113, 6, 6, 1, 1],
		"ears": [119, 126]},
	"goth": {"nose": [115, 118, 1, 1, 2, 1], "chin": [108, 110, 4, 3, 1, 1]},
}

## Long hair kept off the side of the face (model voxels): over these heights, every column of hair further forward
## than z is moved back so its front is at z. From the front it frames her face as before; from the side the cheek
## shows and the hair falls behind it (it ran forward past her face, a dark band across her cheek seen side on).
const HAIR_CLEAR := {"goth": {"y0": 104, "y1": 129, "z": 2}}

static func hair_clear(g: Dictionary, origin: Vector3i, c: Dictionary) -> Dictionary:
	var s: Vector3i = g.size
	var src: PackedInt32Array = g.cells
	var cells := src.duplicate()
	for y in range(maxi(0, int(c.y0) - origin.y), s.y):
		# (above the face's top, let further forward a little more each row: no ledge over her forehead)
		var cz := int(c.z) - origin.z + int(maxf(0.0, (y + origin.y - int(c.y1)) * 0.7))
		for x in s.x:
			var top := -1
			for z in range(s.z - 1, cz, -1):
				if src[_i(s, x, y, z)] != 0:
					top = z
					break
			if top < 0:
				continue
			var d := top - cz
			for z in range(maxi(0, cz - 8), s.z):
				cells[_i(s, x, y, z)] = 0
			for z in range(maxi(0, cz - 8), s.z):
				var v := src[_i(s, x, y, z)]
				if v != 0 and z - d >= 0:
					cells[_i(s, x, y, z - d)] = v
	return {"size": s, "cells": cells}

static func kind(part: String) -> String:
	for k in ["forearm", "arm", "hand", "thigh", "shin", "foot", "torso", "pelvis", "skirt", "head"]:
		if part.begins_with(k):
			return k
	return ""

## The whole treatment for one part: its grid and origin (model voxels, the grid's corner) -> {grid, origin}.
static func part(ch: String, name: String, g: Dictionary, origin: Vector3i, group: String) -> Dictionary:
	var k := kind(name)
	var hair := group.begins_with("hair") or name.begins_with("hair")
	if ROUND.has(k) and not hair:
		g = despeckle(g)
		g = roundify(g, float(ROUND[k]), k == "head")         # (a face stays as drawn: only the back of the head rounded)
	if k in ["arm", "forearm", "thigh", "shin"]:
		g = unline(g)
	if hair and HAIR_CLEAR.has(ch):
		g = hair_clear(g, origin, HAIR_CLEAR[ch])
	g = recolour(g, hair)
	if name == "head" and FACES.has(ch):
		g = face(g, origin, FACES[ch])
	if name == "glasses":
		var r := glasses(g, origin)
		g = r.grid
		origin = r.origin
	if JOINT.has(k):
		g = joints(g, int(JOINT[k]))
	return {"grid": g, "origin": origin}

static func _i(s: Vector3i, x: int, y: int, z: int) -> int:
	return x + s.x * (y + s.y * z)

static func _col(v: int) -> Color:
	var k := v - 1
	return Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)

static func _val(c: Color) -> int:
	return ((c.r8 << 16) | (c.g8 << 8) | c.b8) + 1

static func _at(g: Dictionary, x: int, y: int, z: int) -> int:
	var s: Vector3i = g.size
	if x < 0 or y < 0 or z < 0 or x >= s.x or y >= s.y or z >= s.z:
		return 0
	return (g.cells as PackedInt32Array)[_i(s, x, y, z)]

# ---------------------------------------------------------------- round

## Each slice (one height) trimmed to the rounded oval that fits it (a superellipse of power n).
static func roundify(g: Dictionary, n: float, back_only := false) -> Dictionary:
	var s: Vector3i = g.size
	var src: PackedInt32Array = g.cells
	var cells: PackedInt32Array = src.duplicate()
	# the front and back pictures, to put back on the new surface after (no inside cubes showing)
	var fpic := {}
	var bpic := {}
	for y in s.y:
		for x in s.x:
			for z in range(s.z - 1, -1, -1):
				if src[_i(s, x, y, z)] != 0:
					fpic[Vector2i(x, y)] = src[_i(s, x, y, z)]
					break
			for z in s.z:
				if src[_i(s, x, y, z)] != 0:
					bpic[Vector2i(x, y)] = src[_i(s, x, y, z)]
					break
	# each slice's extent, then smoothed over the slices either side (an even taper, not a stack of rings)
	var ext := []
	for y in s.y:
		var x0 := s.x
		var x1 := -1
		var z0 := s.z
		var z1 := -1
		for z in s.z:
			for x in s.x:
				if cells[_i(s, x, y, z)] != 0:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					z0 = mini(z0, z)
					z1 = maxi(z1, z)
		ext.append([x0, x1, z0, z1] if x1 >= 0 else null)
	for y in s.y:
		if ext[y] == null:
			continue
		var e0: Array = ext[y]
		if e0[1] - e0[0] < 3 or e0[3] - e0[2] < 3:
			continue
		var acc := Vector4.ZERO
		var w := 0.0
		for dy in range(-3, 4):
			var e = ext[clampi(y + dy, 0, s.y - 1)]
			if e == null:
				continue
			var wt := 1.0 - absf(dy) / 4.0
			acc += Vector4((e[0] + e[1] + 1) * 0.5, (e[1] - e[0] + 1) * 0.5, (e[2] + e[3] + 1) * 0.5, (e[3] - e[2] + 1) * 0.5) * wt
			w += wt
		acc /= w
		var cx := acc.x
		var cz := acc.z
		# (never inside the slice's own extent by more than a cube: the outline of the picture kept)
		var rx := maxf(acc.y, (e0[1] - e0[0] + 1) * 0.5 - 1.0) + 0.35
		var rz := maxf(acc.w, (e0[3] - e0[2] + 1) * 0.5 - 1.0) + 0.35
		for z in range(e0[2], e0[3] + 1):
			for x in range(e0[0], e0[1] + 1):
				if back_only and z + 0.5 > cz:
					continue
				var e := pow(absf(x + 0.5 - cx) / rx, n) + pow(absf(z + 0.5 - cz) / rz, n)
				if e > 1.0:
					cells[_i(s, x, y, z)] = 0
	for y in s.y:
		for x in s.x:
			var k := Vector2i(x, y)
			if not fpic.has(k):
				continue
			for z in range(s.z - 1, -1, -1):
				if cells[_i(s, x, y, z)] != 0:
					cells[_i(s, x, y, z)] = fpic[k]
					break
			for z in s.z:
				if cells[_i(s, x, y, z)] != 0:
					if z < s.z - 1 and cells[_i(s, x, y, z + 1)] != 0:
						cells[_i(s, x, y, z)] = bpic[k]
					break
	return {"size": s, "cells": cells}

## Thin dark lines drawn across a limb (the picture's outlines between its segments: rings round it in blocks) filled
## from the cubes above and below; broader shading kept.
static func unline(g: Dictionary) -> Dictionary:
	var s: Vector3i = g.size
	var src: PackedInt32Array = g.cells
	var cells := src.duplicate()
	for z in s.z:
		for y in range(1, s.y - 1):
			for x in s.x:
				var v := src[_i(s, x, y, z)]
				if v == 0:
					continue
				for span in [1, 2]:
					var a := _at(g, x, y + span, z)
					var b := _at(g, x, y - 1, z)
					if a == 0 or b == 0:
						continue
					var ca := _col(a)
					var cb := _col(b)
					var c := _col(v)
					var l := (ca.get_luminance() + cb.get_luminance()) * 0.5
					if c.get_luminance() < l * 0.72:
						var m := ca.lerp(cb, 0.5)
						cells[_i(s, x, y, z)] = _val(m)
						if span == 2 and _col(src[_i(s, x, y + 1, z)]).get_luminance() < l * 0.72:
							cells[_i(s, x, y + 1, z)] = _val(m)
						break
	return {"size": s, "cells": cells}

## Thin bits sticking out (a cube with only one neighbour, or with none above or below it) taken off.
static func despeckle(g: Dictionary, passes := 2) -> Dictionary:
	var s: Vector3i = g.size
	var cells: PackedInt32Array = (g.cells as PackedInt32Array).duplicate()
	for p in passes:
		var gg := {"size": s, "cells": cells.duplicate()}
		for z in s.z:
			for y in s.y:
				for x in s.x:
					var i := _i(s, x, y, z)
					if cells[i] == 0:
						continue
					var up := int(_at(gg, x, y + 1, z) != 0) + int(_at(gg, x, y - 1, z) != 0)
					var across := int(_at(gg, x + 1, y, z) != 0) + int(_at(gg, x - 1, y, z) != 0)
					var deep := int(_at(gg, x, y, z + 1) != 0) + int(_at(gg, x, y, z - 1) != 0)
					if up + across + deep <= 1 or up == 0:          # (a plate one cube thick sticking out sideways too)
						cells[i] = 0
	return {"size": s, "cells": cells}

# ---------------------------------------------------------------- recolour

# a row's colour as seen from the front (dz 1) or the back (dz -1): the average of the cubes facing that way, the dark
# ones (outlines, eyes, print) left out unless the row's mostly dark; with how far forward/back that face is
static func _rows(g: Dictionary, dz: int) -> Array:
	var s: Vector3i = g.size
	var out := []
	for y in s.y:
		var cols := []
		var lsum := 0.0
		var reach := -1 if dz > 0 else s.z
		for x in s.x:
			for zz in s.z:
				var z := s.z - 1 - zz if dz > 0 else zz
				var v := _at(g, x, y, z)
				if v != 0:
					var c := _col(v)
					cols.append(c)
					lsum += c.get_luminance()
					reach = maxi(reach, z) if dz > 0 else mini(reach, z)
					break
		if cols.is_empty():
			out.append(null)
			continue
		var mean_l := lsum / cols.size()
		var max_l := 0.0
		for c: Color in cols:
			max_l = maxf(max_l, c.get_luminance())
		var acc := Color(0, 0, 0)
		var n := 0
		for c: Color in cols:
			if c.get_luminance() >= maxf(mean_l * 0.6, max_l * 0.55):
				acc += c
				n += 1
		if n == 0:
			for c: Color in cols:
				acc += c
			n = cols.size()
		out.append({"c": acc / n, "l": mean_l, "z": reach})
	# smoothed over the rows either side (no stripes)
	var sm := []
	for y in s.y:
		var acc2 := Color(0, 0, 0)
		var w := 0.0
		var zr := 0
		var ok := false
		for dy in range(-2, 3):
			var r = out[clampi(y + dy, 0, s.y - 1)]
			if r == null:
				continue
			var wt := 1.0 if dy == 0 else (0.7 if absi(dy) == 1 else 0.4)
			acc2 += (r.c as Color) * wt
			w += wt
			if dy == 0:
				zr = int(r.z)
				ok = true
		if w == 0.0 or not ok:
			sm.append(null)
		else:
			sm.append({"c": acc2 / w, "l": float(out[y].l), "z": zr})
	return sm

## The sides and tops coloured from the front's and back's rows (blended through the depth); the front's dark outline
## at its edges filled the same; hair given strands running down.
static func recolour(g: Dictionary, hair: bool) -> Dictionary:
	var s: Vector3i = g.size
	var src: PackedInt32Array = g.cells
	var cells := src.duplicate()
	var fr := _rows(g, 1)
	var bk := _rows(g, -1)
	# each row's outermost x (the outline is only there), each column's front and back (the pictures)
	var xlo := PackedInt32Array()
	var xhi := PackedInt32Array()
	xlo.resize(s.y)
	xhi.resize(s.y)
	var zf_col := PackedInt32Array()
	var zb_col := PackedInt32Array()
	zf_col.resize(s.x * s.y)
	zb_col.resize(s.x * s.y)
	for y in s.y:
		xlo[y] = s.x
		xhi[y] = -1
		for x in s.x:
			zf_col[x + s.x * y] = -1
			zb_col[x + s.x * y] = s.z
			for z in s.z:
				if src[_i(s, x, y, z)] != 0:
					xlo[y] = mini(xlo[y], x)
					xhi[y] = maxi(xhi[y], x)
					zf_col[x + s.x * y] = maxi(zf_col[x + s.x * y], z)
					zb_col[x + s.x * y] = mini(zb_col[x + s.x * y], z)
	for z in s.z:
		for y in s.y:
			for x in s.x:
				var i := _i(s, x, y, z)
				var v := src[i]
				if v == 0:
					continue
				var front := _at(g, x, y, z + 1) == 0
				var back := _at(g, x, y, z - 1) == 0
				var side := _at(g, x - 1, y, z) == 0 or _at(g, x + 1, y, z) == 0
				var top := _at(g, x, y + 1, z) == 0 or _at(g, x, y - 1, z) == 0
				if not (side or top):
					continue
				var f = fr[y]
				var b = bk[y]
				if f == null or b == null:
					continue
				if front or back:
					# the picture's own face: only its dark outline at the very edge filled in
					var r = f if front else b
					var c0 := _col(v)
					var rim := x <= xlo[y] + 1 or x >= xhi[y] - 1
					if side and rim and c0.get_luminance() < float(r.l) * 0.55 and not hair:
						cells[i] = _val(c0.lerp(r.c, 0.85))
					continue
				var zf := float(f.z)
				var zb := float(b.z)
				var t := clampf((z - zb) / maxf(1.0, zf - zb), 0.0, 1.0)
				var c := (b.c as Color).lerp(f.c, smoothstep(0.25, 0.6, t))
				# near the front or back picture (its own steps, seen from the front) mostly as it was
				var dfront := zf_col[x + s.x * y] - z
				var dback := z - zb_col[x + s.x * y]
				var keep := 1.0 - smoothstep(1.0, 4.0, float(mini(dfront, dback)))
				if hair:
					# strands: light and dark running down (the same all the way down a strand), a sheen band
					var h := absi(int(x * 73856093) ^ int(z * 19349663)) % 1000 / 1000.0
					c = c * (0.72 + 0.5 * h)
				else:
					var h2 := absi(int(x * 73856093) ^ int(y * 19349663) ^ int(z * 83492791)) % 1000 / 1000.0
					c = c * (0.96 + 0.08 * h2)
				c = c.lerp(_col(v), keep)
				c.a = 1.0
				cells[i] = _val(Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1)))
	return {"size": s, "cells": cells}

# ---------------------------------------------------------------- joints

## The part reaching k cubes further up (into the part above), each layer a cube in from the one below at its edges, so
## it stays hidden inside until the joint bends.
static func joints(g: Dictionary, k: int) -> Dictionary:
	var s: Vector3i = g.size
	var src: PackedInt32Array = g.cells
	var top := -1
	for y in range(s.y - 1, -1, -1):
		for z in s.z:
			for x in s.x:
				if src[_i(s, x, y, z)] != 0:
					top = y
					break
			if top >= 0:
				break
		if top >= 0:
			break
	if top < 0:
		return g
	var ns := Vector3i(s.x, top + 1 + k, s.z)
	var cells := PackedInt32Array()
	cells.resize(ns.x * ns.y * ns.z)
	for z in s.z:
		for y in mini(s.y, ns.y):
			for x in s.x:
				cells[_i(ns, x, y, z)] = src[_i(s, x, y, z)]
	for j in range(1, k + 1):
		var below := top + j - 1
		var y := top + j
		for z in s.z:
			for x in s.x:
				var v := cells[_i(ns, x, below, z)]
				if v == 0:
					continue
				var edge := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var xx: int = x + d.x
					var zz: int = z + d.y
					if xx < 0 or zz < 0 or xx >= ns.x or zz >= ns.z or cells[_i(ns, xx, below, zz)] == 0:
						edge = true
				if not edge:
					cells[_i(ns, x, y, z)] = v
	return {"size": ns, "cells": cells}

# ---------------------------------------------------------------- the face

## A nose, brow, lips and chin built out from the face's front, ears on the sides (FACES).
static func face(g: Dictionary, origin: Vector3i, f: Dictionary) -> Dictionary:
	var s: Vector3i = g.size
	var grow := 4
	var ns := Vector3i(s.x, s.y, s.z + grow)
	var src: PackedInt32Array = g.cells
	var cells := PackedInt32Array()
	cells.resize(ns.x * ns.y * ns.z)
	for z in s.z:
		for y in s.y:
			for x in s.x:
				cells[_i(ns, x, y, z)] = src[_i(s, x, y, z)]
	var g2 := {"size": ns, "cells": cells}
	var mid := s.x / 2
	for feat in ["nose", "tash", "lips", "chin", "brow"]:
		if not f.has(feat):
			continue
		var a: Array = f[feat]
		var y0 := int(a[0]) - origin.y
		var y1 := int(a[1]) - origin.y
		for y in range(y0, y1 + 1):
			if y < 0 or y >= ns.y:
				continue
			var u := 0.0 if y1 == y0 else float(y - y0) / float(y1 - y0)       # 0 bottom .. 1 top
			var hw := int(round(lerpf(float(a[2]), float(a[3]), u)))
			var out := int(round(lerpf(float(a[4]), float(a[5]), u)))
			for x in range(mid - hw, mid + hw + 1):
				if x < 0 or x >= ns.x:
					continue
				var fz := -1
				for z in range(ns.z - 1, -1, -1):
					if cells[_i(ns, x, y, z)] != 0:
						fz = z
						break
				if fz < 0:
					continue
				var c := _col(cells[_i(ns, x, y, fz)])
				# the nose's sides a shade darker (its shape reads), its tip as the face
				if feat == "nose" and absi(x - mid) == hw and hw > 0:
					c = c.darkened(0.12)
				var edge_in := 1 if (absi(x - mid) == hw and hw > 1 and feat != "nose") else 0
				for k in range(1, out + 1 - edge_in):
					if fz + k < ns.z:
						cells[_i(ns, x, y, fz + k)] = _val(c)
	if f.has("ears"):
		var e: Array = f.ears
		var ey0 := int(e[0]) - origin.y
		var ey1 := int(e[1]) - origin.y
		for y in range(maxi(0, ey0), mini(ns.y, ey1 + 1)):
			for side in [-1, 1]:
				# the side's outermost cube at this height, in the middle of the head's depth
				var zs: Array = []
				for z in ns.z:
					for x in ns.x:
						if cells[_i(ns, x, y, z)] != 0:
							zs.append(z)
							break
				if zs.is_empty():
					continue
				var zc := int((int(zs.min()) + int(zs.max())) * 0.5) - 2
				for z in range(zc - 2, zc + 2):
					var ex := -1
					var xs: Array = range(ns.x) if side < 0 else range(ns.x - 1, -1, -1)
					for x in xs:
						if cells[_i(ns, x, y, z)] != 0:
							ex = x
							break
					if ex < 0:
						continue
					var nx: int = ex + side
					if nx >= 0 and nx < ns.x:
						cells[_i(ns, nx, y, z)] = _val(_col(cells[_i(ns, ex, y, z)]).darkened(0.08))
	return g2

# ---------------------------------------------------------------- glasses

## The glasses' arms run back along the sides of the head (6 cubes), from the frame's outer ends.
static func glasses(g: Dictionary, origin: Vector3i) -> Dictionary:
	var s: Vector3i = g.size
	var back := 7
	var ns := Vector3i(s.x, s.y, s.z + back)
	var src: PackedInt32Array = g.cells
	var cells := PackedInt32Array()
	cells.resize(ns.x * ns.y * ns.z)
	for z in s.z:
		for y in s.y:
			for x in s.x:
				cells[_i(ns, x, y, z + back)] = src[_i(s, x, y, z)]
	for side in [0, ns.x - 1]:
		for y in s.y:
			var c := 0
			for z in range(ns.z - 1, back - 1, -1):
				var v := cells[_i(ns, side, y, z)]
				if v != 0:
					c = v
			if c == 0:
				continue
			for z in range(0, back + 2):
				if cells[_i(ns, side, y, z)] == 0:
					cells[_i(ns, side, y, z)] = c
	return {"grid": {"size": ns, "cells": cells}, "origin": origin - Vector3i(0, 0, back)}

# ---------------------------------------------------------------- the smooth shading's shapes

## The rounded shape a part stands for (its cubes' middle and half-sizes, metres, in the part mesh's own space: the
## grid placed from origin, less the bone's pivot), for the shader: [centre, radii].
static func shape(g: Dictionary, origin: Vector3, pivot: Vector3, vm: float) -> Array:
	var s: Vector3i = g.size
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var cells: PackedInt32Array = g.cells
	for z in s.z:
		for y in s.y:
			for x in s.x:
				if cells[_i(s, x, y, z)] != 0:
					lo = lo.min(Vector3(x, y, z))
					hi = hi.max(Vector3(x + 1, y + 1, z + 1))
	if lo.x == INF:
		return [Vector3.ZERO, Vector3.ONE]
	var c := (lo + hi) * 0.5 + origin - pivot
	return [c * vm, (hi - lo) * 0.5 * vm]
