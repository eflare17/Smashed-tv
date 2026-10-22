extends RefCounted
## Smash arcade: builds every mesh in code (no imported assets). Characters are boxes of 0.1 m voxels, only the
## faces with no neighbour are kept, and each face gets a fixed shade so the unshaded materials still read as 3D.
## Front of a character is +Z, its right hand is -X, feet at y = 0.

const VOX := 0.1

const SKIN := Color(0.95, 0.72, 0.52)
const GRUNT_SHIRT := Color(0.36, 0.62, 0.22)
const GRUNT_PANTS := Color(0.42, 0.3, 0.18)
const GRUNT_CAP := Color(0.85, 0.15, 0.12)
const PLAYER_SUIT := Color(0.15, 0.55, 1.0)
const PLAYER_DARK := Color(0.1, 0.18, 0.45)
const HAIR := Color(0.95, 0.82, 0.3)
const GUN := Color(0.25, 0.25, 0.28)
const BOOT := Color(0.12, 0.1, 0.1)
const EYE := Color(0.1, 0.05, 0.05)
const BLOOD := Color(0.6, 0.03, 0.03)

## Gib colours (chunks pick from these).
const GRUNT_GIBS := [GRUNT_SHIRT, GRUNT_SHIRT, SKIN, GRUNT_PANTS, BLOOD, BLOOD, GRUNT_CAP]
const PLAYER_GIBS := [PLAYER_SUIT, PLAYER_SUIT, PLAYER_DARK, SKIN, HAIR, BLOOD, BLOOD]

const _DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const _SHADE := [0.9, 0.62, 1.0, 0.5, 0.82, 0.72]
const _CORNERS := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]

# boxes are [x0, y0, z0, x1, y1, z1, colour], inclusive voxel coordinates
static func _grunt_boxes(frame: int) -> Array:
	var a := 1 if frame == 0 else 0
	var b := 1 - a
	return [
		# legs, one forward one back, swapped between the two frames
		[1, 0, 1 + a, 2, 3, 2 + a, GRUNT_PANTS], [4, 0, 1 + b, 5, 3, 2 + b, GRUNT_PANTS],
		[1, 0, 1 + a, 2, 0, 2 + a, BOOT], [4, 0, 1 + b, 5, 0, 2 + b, BOOT],
		[1, 4, 0, 5, 7, 3, GRUNT_SHIRT],
		# arms reaching for the player
		[0, 6, 1, 0, 7, 3 + a, SKIN], [6, 6, 1, 6, 7, 3 + b, SKIN],
		[0, 5, 1, 0, 5, 2, GRUNT_SHIRT], [6, 5, 1, 6, 5, 2, GRUNT_SHIRT],
		[2, 8, 0, 4, 10, 3, SKIN],
		[2, 10, 0, 4, 10, 3, GRUNT_CAP], [2, 9, 0, 4, 9, 0, GRUNT_CAP],
		[2, 9, 3, 2, 9, 3, EYE], [4, 9, 3, 4, 9, 3, EYE],
	]

static func _player_boxes(frame: int) -> Array:
	var a := 1 if frame == 0 else 0
	var b := 1 - a
	return [
		[1, 0, 1 + a, 2, 3, 2 + a, PLAYER_DARK], [4, 0, 1 + b, 5, 3, 2 + b, PLAYER_DARK],
		[1, 0, 1 + a, 2, 0, 2 + a, BOOT], [4, 0, 1 + b, 5, 0, 2 + b, BOOT],
		[1, 4, 0, 5, 8, 3, PLAYER_SUIT], [1, 4, 0, 5, 4, 3, PLAYER_DARK],
		# right arm (-X) holds the gun out front, left arm swings
		[0, 6, 1, 0, 7, 4, PLAYER_SUIT], [0, 7, 3, 0, 8, 7, GUN],
		[6, 5, 1 + b, 6, 8, 2 + b, PLAYER_SUIT],
		[2, 9, 0, 4, 11, 3, SKIN],
		[2, 11, 0, 4, 11, 3, HAIR], [2, 9, 0, 4, 10, 0, HAIR],
		[2, 10, 3, 2, 10, 3, EYE], [4, 10, 3, 4, 10, 3, EYE],
	]

static func grunt_mesh(frame: int) -> ArrayMesh:
	return from_boxes(_grunt_boxes(frame), Vector3(3.5, 0, 2))

static func player_mesh(frame: int) -> ArrayMesh:
	return from_boxes(_player_boxes(frame), Vector3(3.5, 0, 2))

## Voxel boxes -> one mesh of the outside faces. `center` (in voxels) lands on the origin.
static func from_boxes(boxes: Array, center: Vector3) -> ArrayMesh:
	var grid := {}
	for bx in boxes:
		for x in range(bx[0], bx[3] + 1):
			for y in range(bx[1], bx[4] + 1):
				for z in range(bx[2], bx[5] + 1):
					grid[Vector3i(x, y, z)] = bx[6]
	var m := _Arrays.new()
	var unit := Vector3.ONE * VOX
	for v: Vector3i in grid:
		for f in 6:
			if not grid.has(v + _DIRS[f]):
				m.quad((Vector3(v) - center) * VOX, unit, f, grid[v])
	return m.commit()

## A plain shaded box (used for the bullet and the gib cube).
static func box_mesh(size: Vector3, color: Color) -> ArrayMesh:
	var m := _Arrays.new()
	m.box(-size * 0.5, size, color)
	return m.commit()

## The arena: checkered floor, walls with a door gap in the middle of each side, and a short corridor behind
## every door that the grunts walk in through. `half` is half the inside width.
static func arena_mesh(half: float, door_half: float, corridor: float) -> ArrayMesh:
	var m := _Arrays.new()
	var tile := 2.0
	var n := int(half * 2 / tile)
	for i in n:
		for j in n:
			var c := Color(0.25, 0.23, 0.22) if (i + j) % 2 == 0 else Color(0.31, 0.29, 0.27)
			m.box(Vector3(-half + i * tile, -0.2, -half + j * tile), Vector3(tile, 0.2, tile), c)
	var wall := Color(0.55, 0.22, 0.6)
	var post := Color(1.0, 0.6, 0.1)
	var t := 1.0
	var h := 1.2
	for k in 4:
		# laid out for the north side, then turned to the other three
		var boxes := [
			[Vector3(-half - t, 0, -half - t), Vector3(-door_half, h, -half), wall],
			[Vector3(door_half, 0, -half - t), Vector3(half + t, h, -half), wall],
			[Vector3(-door_half - 0.4, 0, -half - t), Vector3(-door_half, h + 0.4, -half), post],
			[Vector3(door_half, 0, -half - t), Vector3(door_half + 0.4, h + 0.4, -half), post],
			[Vector3(-door_half - t, 0, -half - t - corridor), Vector3(-door_half, h, -half - t), wall],
			[Vector3(door_half, 0, -half - t - corridor), Vector3(door_half + t, h, -half - t), wall],
			[Vector3(-door_half, -0.2, -half - t - corridor), Vector3(door_half, 0, -half), Color(0.12, 0.12, 0.16)],
		]
		for bx in boxes:
			var a := _turn(bx[0], k)
			var b := _turn(bx[1], k)
			m.box(a.min(b), (a - b).abs(), bx[2])
	return m.commit()

static func _turn(p: Vector3, k: int) -> Vector3:
	for i in k:
		p = Vector3(-p.z, p.y, p.x)
	return p

## Splat picture: a chunky blob with a few drops, white (the instance colour tints it).
static func splat_texture() -> ImageTexture:
	var s := 24
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var blobs := [[Vector2(12, 12), 6.0]]
	for i in 7:
		var a := rng.randf() * TAU
		var d := rng.randf_range(4.0, 10.0)
		blobs.append([Vector2(12, 12) + Vector2(cos(a), sin(a)) * d, rng.randf_range(1.0, 3.2)])
	for y in s:
		for x in s:
			for bl in blobs:
				if Vector2(x + 0.5, y + 0.5).distance_to(bl[0]) < bl[1]:
					img.set_pixel(x, y, Color(1, 1, 1, 1))
					break
	return ImageTexture.create_from_image(img)

## Unshaded vertex-colour material shared by the voxel meshes.
static func flat_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	return mat

class _Arrays:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func quad(origin: Vector3, size: Vector3, f: int, color: Color) -> void:
		var base := verts.size()
		var c := Color(color.r * _SHADE[f], color.g * _SHADE[f], color.b * _SHADE[f], color.a)
		for corner: Vector3 in _CORNERS[f]:
			verts.append(origin + corner * size)
			cols.append(c)
		# Godot's front faces are clockwise seen from outside: flip if this corner order isn't
		var n := Vector3(_DIRS[f])
		if (verts[base + 1] - verts[base]).cross(verts[base + 2] - verts[base]).dot(n) > 0.0:
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func box(origin: Vector3, size: Vector3, color: Color) -> void:
		for f in 6:
			quad(origin, size, f, color)

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return mesh
