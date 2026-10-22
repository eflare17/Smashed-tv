class_name VoxelModel
extends RefCounted
## A block character as data: its rig (assets/voxel/<char>/rig.json: bones with their pivots, parts on bones) and its
## parts (one MagicaVoxel .vox each), meshed with VoxMesher and put together as one skinned mesh (every vertex on its
## part's bone, weight 1) so a character is one draw call. Owned by the voxel session.
##
## One VoxelModel per character, shared (VoxelModel.get_model("jared")); the meshes it makes are cached by what's in
## them (the parts, the weapon, the hair style, the shirt print, the level of detail) and shared by everyone showing
## the same look. Units: metres, the feet's centre at the origin, +z forward, +y up, +x the character's left.

const DIR := "res://assets/voxel/"
## Kinds made from another's model (Stage 11, the arena's enemy variety): its parts recoloured toward tint (mix of the
## way), and the shield brute's shield added: a steel plate on a bone of its own below the left forearm (laid flat at
## rest, held up in front of it when the forearm points forward: VoxelBody pins it so).
const VARIANTS := {
	"charger": {"base": "swarmer", "tint": Color(1.0, 0.32, 0.25), "mix": 0.55},
	"thrower": {"base": "grunt", "tint": Color(0.45, 0.95, 0.3), "mix": 0.5},
	"shielder": {"base": "brute", "tint": Color(0.45, 0.6, 1.0), "mix": 0.45, "shield": true},
	"boss": {"base": "brute", "tint": Color(0.85, 0.12, 0.1), "mix": 0.55},     # (Stage 12: THE BUTCHER, twice the size)
}
const SHIELD_ORIGIN := Vector3i(-4, 19, -22)     # (model voxels, at rest: x across, y its thickness, z its height)
const SHIELD_SIZE := Vector3i(30, 2, 38)

static var _models := {}
static var _weapons := {}          # name -> {grid, origin: Vector3, arrays: {lod: Dictionary}}
static var _weapon_meta := {}

var char_name := ""
var rig: Dictionary = {}
## Metres per voxel (the pixel art's size: CharFrames.draw_height of the reference frame / its rows).
var voxel_m := 0.0125
var bone_names: PackedStringArray = PackedStringArray()
var bone_index := {}
var bone_parent: PackedInt32Array = PackedInt32Array()
var bone_pivot: PackedVector3Array = PackedVector3Array()   # voxels, model space
var parts := {}                    # name -> {bone: int, origin: Vector3i, file, grid, group, style, arrays: {lod: Dictionary}}
var _meshes := {}                  # key -> ArrayMesh

## The character a CharSprite sheet shows as blocks ("juicy_spud" -> "jared", "tyson2" -> "jared" recoloured), or "".
static func model_for_sheet(sheet: String) -> String:
	var base := CharFrames.base_char(sheet)
	match base:
		"juicy", "tyson2":
			return "jared" if has_model("jared") else ""
		"goth":
			return "goth" if has_model("goth") else ""
	return base if has_model(base) else ""

static var _has := {}

static func has_model(ch: String) -> bool:
	if not _has.has(ch):
		var dir := String(VARIANTS[ch].base) if VARIANTS.has(ch) else ch
		_has[ch] = FileAccess.file_exists(DIR + dir + "/rig.json")
	return _has[ch]

static func get_model(ch: String) -> VoxelModel:
	if _models.has(ch):
		return _models[ch]
	if not has_model(ch):
		return null
	var m := VoxelModel.new()
	if not m._load(ch):
		return null
	_models[ch] = m
	return m

var _dir := ""                     # the folder its files are in (a variant's: its base's)
var _tint := {}                    # a variant's {tint, mix}, or {}

func _load(ch: String) -> bool:
	char_name = ch
	_dir = ch
	if VARIANTS.has(ch):
		_dir = String(VARIANTS[ch].base)
		_tint = VARIANTS[ch]
	var f := FileAccess.open(DIR + _dir + "/rig.json", FileAccess.READ)
	if f == null:
		return false
	var j = JSON.parse_string(f.get_as_text())
	if not (j is Dictionary):
		return false
	rig = j
	var sheet := String(rig.get("ref_sheet", "juicy"))
	var key := String(rig.get("ref_key", "front_a"))
	var rows := float(rig.get("ref_rows", 160))
	voxel_m = CharFrames.draw_height(sheet, key) / rows * GameData.UNIT
	for b in rig.get("bones", []):
		bone_index[String(b.name)] = bone_names.size()
		bone_names.append(String(b.name))
		var pv: Array = b.pivot
		bone_pivot.append(Vector3(pv[0], pv[1], pv[2]))
	for b in rig.get("bones", []):
		var par := String(b.get("parent", ""))
		bone_parent.append(int(bone_index.get(par, -1)))
	for p in rig.get("parts", []):
		var o: Array = p.origin
		parts[String(p.name)] = {"bone": int(bone_index.get(String(p.bone), 0)), "origin": Vector3i(int(o[0]), int(o[1]), int(o[2])),
			"file": String(p.file), "group": String(p.get("group", "")), "style": String(p.get("style", "")),
			"optional": bool(p.get("optional", false)), "grid": null, "arrays": {}}
	if bool(_tint.get("shield", false)) and bone_index.has("forearm_l"):
		bone_index["shield"] = bone_names.size()
		bone_names.append("shield")
		var hl: Vector3 = bone_pivot[bone("hand_l")] if bone("hand_l") >= 0 else Vector3(23, 21, 0)
		bone_pivot.append(Vector3(hl.x, SHIELD_ORIGIN.y + SHIELD_SIZE.y, 0.0))
		bone_parent.append(bone("forearm_l"))
		parts["shield"] = {"bone": bone("shield"), "origin": SHIELD_ORIGIN, "file": "", "group": "", "style": "",
			"optional": false, "grid": shield_grid(), "arrays": {}}
	return true

## The shield brute's shield: a steel plate, a dark rim with rivets, a red cross on its face (the face: y 0, the
## side away from him once it's held up).
static func shield_grid() -> Dictionary:
	var s := SHIELD_SIZE
	var cells := PackedInt32Array()
	cells.resize(s.x * s.y * s.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cx := (s.x - 1) / 2.0
	var cz := (s.z - 1) / 2.0
	for z in s.z:
		for y in s.y:
			for x in s.x:
				# the corners cut off
				var ex := minf(x, s.x - 1 - x)
				var ez := minf(z, s.z - 1 - z)
				if ex + ez < 3:
					continue
				var c := Color8(118, 128, 142)
				var rim := ex < 2 or ez < 2
				if rim:
					c = Color8(66, 70, 80)
					if y == 0 and int(ex) == 0 and int(ez) % 5 == 2 or y == 0 and int(ez) == 0 and int(ex) % 5 == 2:
						c = Color8(196, 200, 208)          # rivets
				elif y == 0:
					var u := (x - cx) / cx
					var w := (z - cz) / cz
					if absf(absf(u) - absf(w)) < 0.12 and absf(u) < 0.8:
						c = Color8(150, 26, 30)            # the cross
					elif absf(u) < 0.14 and absf(w) < 0.14:
						c = Color8(196, 200, 208)          # the boss in the middle
				var v := rng.randf_range(-6, 6)
				c = Color8(clampi(c.r8 + int(v), 0, 255), clampi(c.g8 + int(v), 0, 255), clampi(c.b8 + int(v), 0, 255))
				cells[x + s.x * (y + s.y * z)] = ((c.r8 << 16) | (c.g8 << 8) | c.b8) + 1
	return {"size": s, "cells": cells}

func bone(name: String) -> int:
	return int(bone_index.get(name, -1))

## The part's voxel grid (model axes), loaded on first use.
func grid(part: String) -> Dictionary:
	var p: Dictionary = parts[part]
	if p.grid == null:
		var v := VoxFile.load_file(DIR + (_dir if _dir != "" else char_name) + "/" + String(p.file))
		p.grid = v.model_grid() if v else {"size": Vector3i.ZERO, "cells": PackedInt32Array()}
		if not _tint.is_empty():
			p.grid = _tinted(p.grid, _tint.tint, float(_tint.mix))
	return p.grid

# a grid's colours turned toward tint (keeping how light each is)
static func _tinted(g: Dictionary, tint: Color, mix: float) -> Dictionary:
	var cells: PackedInt32Array = (g.cells as PackedInt32Array).duplicate()
	for i in cells.size():
		var v := cells[i]
		if v == 0:
			continue
		var k := v - 1
		var c := Color8((k >> 16) & 255, (k >> 8) & 255, k & 255)
		var l := c.get_luminance()
		var t := Color(clampf(tint.r * l * 1.8, 0, 1), clampf(tint.g * l * 1.8, 0, 1), clampf(tint.b * l * 1.8, 0, 1))
		c = c.lerp(t, mix)
		cells[i] = ((c.r8 << 16) | (c.g8 << 8) | c.b8) + 1
	return {"size": g.size, "cells": cells}

## Replaces a part's voxels (the shirt print repaints the torso's front); its meshes are made again.
func set_grid(part: String, g: Dictionary) -> void:
	parts[part].grid = g
	parts[part].arrays = {}
	_meshes.clear()

## The part's quads in metres (model space), at a level of detail (0 full, 1 half).
func part_arrays(part: String, lod: int) -> Dictionary:
	var p: Dictionary = parts[part]
	if not p.arrays.has(lod):
		var g := grid(part)
		var origin := Vector3(p.origin)
		if lod > 0:
			g = VoxMesher.downsample(g)
			origin = origin / 2.0
		p.arrays[lod] = VoxMesher.mesh(g, origin, voxel_m * (2.0 if lod > 0 else 1.0))
	return p.arrays[lod]

## The parts a look uses: everything but the optional ones (hair styles other than the one asked for).
func parts_for(style: String) -> PackedStringArray:
	var out := PackedStringArray()
	var have_style := false
	for n in parts:
		if parts[n].group == "hair" and parts[n].style == style:
			have_style = true
	for n in parts:
		var p: Dictionary = parts[n]
		if p.group == "hair":
			if (have_style and p.style == style) or (not have_style and p.style == "classic"):
				out.append(n)
		else:
			out.append(n)
	return out

# ---------------------------------------------------------------- skeleton

## A Skeleton3D with this rig's bones at rest (pure offsets from the parent's pivot).
func make_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	for i in bone_names.size():
		sk.add_bone(bone_names[i])
	for i in bone_names.size():
		sk.set_bone_parent(i, bone_parent[i])
		var par := bone_parent[i]
		var off := bone_pivot[i] - (bone_pivot[par] if par >= 0 else Vector3.ZERO)
		var rest := Transform3D(Basis.IDENTITY, off * voxel_m)
		sk.set_bone_rest(i, rest)
		sk.set_bone_pose_position(i, rest.origin)
		sk.set_bone_pose_rotation(i, Quaternion.IDENTITY)
	return sk

func make_skin() -> Skin:
	var s := Skin.new()
	for i in bone_names.size():
		s.add_named_bind(bone_names[i], Transform3D(Basis.IDENTITY, -bone_pivot[i] * voxel_m))
	return s

# ---------------------------------------------------------------- weapons

static func weapon_meta() -> Dictionary:
	if _weapon_meta.is_empty():
		var f := FileAccess.open(DIR + "weapons/weapons.json", FileAccess.READ)
		if f:
			var j = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				_weapon_meta = j
	return _weapon_meta

## A weapon's quads in its own space (metres; the grip at the origin, the barrel toward +z, up +y).
static func weapon_arrays(name: String, lod: int, scale: float) -> Dictionary:
	var meta := weapon_meta()
	if not meta.has(name):
		return {}
	if not _weapons.has(name):
		var v := VoxFile.load_file(DIR + "weapons/" + String(meta[name].file))
		if v == null:
			return {}
		var o: Array = meta[name].origin
		_weapons[name] = {"grid": v.model_grid(), "origin": Vector3(o[0], o[1], o[2]), "arrays": {}}
	var w: Dictionary = _weapons[name]
	if not w.arrays.has(lod):
		var g: Dictionary = w.grid
		var origin: Vector3 = w.origin
		if lod > 0:
			g = VoxMesher.downsample(g)
			origin = origin / 2.0
		w.arrays[lod] = VoxMesher.mesh(g, origin, scale * (2.0 if lod > 0 else 1.0))
	return w.arrays[lod]

# ---------------------------------------------------------------- the mesh

## One skinned mesh: the parts for the hair style, plus attachments [{arrays, bone: String, xform: Transform3D}]
## (weapons: their own space placed in model space at rest). recolour: {green, blue, boost} (Tornado Tyson) or {}.
## key: what makes this look different from others (for the cache).
func build_mesh(key: String, style: String, lod: int, attachments: Array = [], recolour: Dictionary = {}) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var top := -1e9
	var bottom := 1e9
	for n in parts_for(style):
		var g := grid(n)
		var o := Vector3(parts[n].origin)
		top = maxf(top, o.y + g.size.y)
		bottom = minf(bottom, o.y)
	for n in parts_for(style):
		var a := part_arrays(n, lod)
		_append(verts, normals, colors, bones, weights, indices, a, int(parts[n].bone), Transform3D.IDENTITY)
	for at in attachments:
		var a2: Dictionary = at.arrays
		if a2.is_empty():
			continue
		_append(verts, normals, colors, bones, weights, indices, a2, maxi(0, bone(String(at.bone))), at.xform)
	if not recolour.is_empty():
		_recolour(verts, colors, recolour, top * voxel_m, bottom * voxel_m)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[key] = am
	return am

func _append(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, bones: PackedInt32Array,
		weights: PackedFloat32Array, indices: PackedInt32Array, a: Dictionary, b: int, xf: Transform3D) -> void:
	var base := verts.size()
	var av: PackedVector3Array = a.verts
	var an: PackedVector3Array = a.normals
	if xf == Transform3D.IDENTITY:
		verts.append_array(av)
		normals.append_array(an)
	else:
		for v in av:
			verts.append(xf * v)
		for nn in an:
			normals.append((xf.basis * nn).normalized())
	colors.append_array(a.colors)
	var n := av.size()
	var bb := PackedInt32Array()
	bb.resize(n * 4)
	var ww := PackedFloat32Array()
	ww.resize(n * 4)
	for i in n:
		bb[i * 4] = b
		ww[i * 4] = 1.0
	bones.append_array(bb)
	weights.append_array(ww)
	var ai: PackedInt32Array = a.indices
	if base == 0:
		indices.append_array(ai)
	else:
		var shifted := ai.duplicate()
		for i in shifted.size():
			shifted[i] += base
		indices.append_array(shifted)

## The HTML game's recolourImage (CharSprite's shader does it to the pictures): greens become the palette's green
## hue, the singlet's blues (in its band of the body) the palette's blue.
static func _recolour(verts: PackedVector3Array, colors: PackedColorArray, pal: Dictionary, top: float, bottom: float) -> void:
	var g := float(pal.get("green", 22.0)) / 360.0
	var bl := float(pal.get("blue", 125.0)) / 360.0
	var boost := float(pal.get("boost", 1.15))
	var span := maxf(0.001, top - bottom)
	for i in colors.size():
		var c := colors[i]
		var h := c.h * 360.0
		var frac := (top - verts[i].y) / span
		var nh := -1.0
		if h >= 75.0 and h < 185.0 and c.s > 0.2:
			nh = g
		elif h >= 185.0 and h < 265.0 and c.s > 0.28 and frac > 0.22 and frac < 0.58:
			nh = bl
		if nh >= 0.0:
			colors[i] = Color.from_hsv(nh, minf(1.0, c.s * boost), c.v)
