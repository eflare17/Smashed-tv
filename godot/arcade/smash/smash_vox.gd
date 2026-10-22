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
const BRUTE_VEST := Color(0.75, 0.12, 0.1)
const BRUTE_PANTS := Color(0.32, 0.32, 0.36)
const MOHAWK := Color(1.0, 0.3, 0.75)
const CLUB := Color(0.45, 0.28, 0.12)
const HOST_SUIT := Color(0.16, 0.16, 0.4)
const HOST_HAIR := Color(0.1, 0.07, 0.05)
const HOST_SHINE := Color(0.45, 0.4, 0.35)
const WHITE := Color(1, 1, 1)
const BOWTIE := Color(0.9, 0.1, 0.1)
const MOUTH := Color(0.3, 0.02, 0.05)
const BILL := Color(0.35, 0.75, 0.3)
const BILL_DARK := Color(0.15, 0.45, 0.15)
const SCORCH := Color(0.07, 0.06, 0.05)
const SNIPER_SUIT := Color(0.2, 0.22, 0.26)
const HELMET := Color(0.38, 0.4, 0.44)
const VISOR := Color(1.0, 0.15, 0.1)
const MINE_SHELL := Color(0.32, 0.32, 0.36)
const BARREL := Color(0.55, 0.32, 0.12)
const HOOP := Color(0.25, 0.22, 0.2)
const HAZARD := Color(0.95, 0.25, 0.08)
const BOSS_VEST := Color(0.38, 0.12, 0.55)
const BOSS_HAIR := Color(1.0, 0.8, 0.1)
const SPIKE := Color(0.7, 0.72, 0.75)
const GOLD := Color(1.0, 0.75, 0.15)
const GOLD_LIGHT := Color(1.0, 0.9, 0.5)
const SILVER := Color(0.78, 0.8, 0.84)
const DARK := Color(0.12, 0.12, 0.14)
const CAR_RED := Color(0.9, 0.12, 0.1)
const GLASS := Color(0.55, 0.85, 1.0)

## Gib colours (chunks pick from these).
const GRUNT_GIBS := [GRUNT_SHIRT, GRUNT_SHIRT, SKIN, GRUNT_PANTS, BLOOD, BLOOD, GRUNT_CAP]
const BRUTE_GIBS := [BRUTE_VEST, BRUTE_VEST, SKIN, BRUTE_PANTS, BLOOD, BLOOD, MOHAWK]
const SNIPER_GIBS := [SNIPER_SUIT, SNIPER_SUIT, HELMET, SKIN, BLOOD, BLOOD, GUN]
const MINE_GIBS := [MINE_SHELL, MINE_SHELL, DARK, Color(1.0, 0.85, 0.2), Color(1.0, 0.5, 0.1)]
const BOSS_GIBS := [BOSS_VEST, BOSS_VEST, SKIN, BRUTE_PANTS, BLOOD, BLOOD, BOSS_HAIR, SPIKE]
const PLAYER_GIBS := [PLAYER_SUIT, PLAYER_SUIT, PLAYER_DARK, SKIN, HAIR, BLOOD, BLOOD]
const FIRE_GIBS := [Color(1.0, 0.85, 0.2), Color(1.0, 0.5, 0.1), Color(0.9, 0.25, 0.05), Color(0.25, 0.22, 0.2)]

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

## The brute: a wide grunt with a club and a mohawk (drawn 1.35x, so his voxels are chunkier too).
static func _brute_boxes(frame: int, vest := BRUTE_VEST, hair := MOHAWK) -> Array:
	var a := 1 if frame == 0 else 0
	var b := 1 - a
	return [
		[1, 0, 1 + a, 3, 3, 2 + a, BRUTE_PANTS], [5, 0, 1 + b, 7, 3, 2 + b, BRUTE_PANTS],
		[1, 0, 1 + a, 3, 0, 2 + a, BOOT], [5, 0, 1 + b, 7, 0, 2 + b, BOOT],
		[1, 4, 0, 7, 8, 4, vest], [1, 4, 0, 7, 4, 4, BOOT],
		[0, 7, 1, 0, 8, 3 + a, SKIN], [8, 7, 1, 8, 8, 3 + b, SKIN],
		[0, 8, 3 + a, 0, 8, 6 + a, CLUB], [0, 7, 6 + a, 0, 9, 7 + a, CLUB],
		[3, 9, 1, 5, 11, 3, SKIN],
		[4, 12, 0, 4, 12, 3, hair], [4, 11, 0, 4, 11, 0, hair],
		[3, 10, 3, 3, 10, 3, EYE], [5, 10, 3, 5, 10, 3, EYE],
	]

## The sniper: stands in a doorway with a long rifle and a red visor.
static func _sniper_boxes(frame: int) -> Array:
	var a := 1 if frame == 0 else 0
	var b := 1 - a
	return [
		[1, 0, 1 + a, 2, 3, 2 + a, SNIPER_SUIT], [4, 0, 1 + b, 5, 3, 2 + b, SNIPER_SUIT],
		[1, 0, 1 + a, 2, 0, 2 + a, BOOT], [4, 0, 1 + b, 5, 0, 2 + b, BOOT],
		[1, 4, 0, 5, 7, 3, SNIPER_SUIT], [1, 4, 0, 5, 4, 3, BOOT],
		[0, 6, 1, 0, 7, 4, SNIPER_SUIT], [6, 6, 1, 6, 7, 4, SNIPER_SUIT],
		[0, 7, 4, 0, 7, 9, GUN], [0, 8, 5, 0, 8, 6, GUN],
		[2, 8, 0, 4, 10, 3, SKIN], [2, 10, 0, 4, 10, 3, HELMET], [2, 8, 0, 4, 9, 0, HELMET],
		[2, 9, 3, 4, 9, 3, VISOR],
	]

## The boss: a brute in purple with gold hair and spiked shoulders (drawn about 3x).
static func _boss_boxes(frame: int) -> Array:
	var boxes := _brute_boxes(frame, BOSS_VEST, BOSS_HAIR)
	boxes.append_array([
		[0, 9, 1, 2, 9, 3, SPIKE], [6, 9, 1, 8, 9, 3, SPIKE], [0, 10, 2, 0, 10, 2, SPIKE], [8, 10, 2, 8, 10, 2, SPIKE],
		[3, 12, 1, 5, 12, 1, BOSS_HAIR],
	])
	return boxes

## The TV host, head and shoulders, facing the camera (+Z), waving a dollar bill. Frame 1 has his mouth open.
static func _host_boxes(frame: int) -> Array:
	var talk := frame == 1
	var bill_y := 1 if talk else 0
	var boxes := [
		[0, 0, 0, 12, 4, 4, HOST_SUIT],
		[5, 1, 4, 7, 4, 4, WHITE], [5, 4, 4, 7, 4, 4, BOWTIE],
		[3, 5, 0, 9, 12, 4, SKIN],
		[2, 8, 2, 2, 9, 3, SKIN], [10, 8, 2, 10, 9, 3, SKIN],
		[3, 12, 0, 9, 13, 4, HOST_HAIR], [3, 6, 0, 9, 12, 0, HOST_HAIR],
		[3, 10, 0, 3, 12, 2, HOST_HAIR], [9, 10, 0, 9, 12, 2, HOST_HAIR],
		[4, 13, 4, 7, 13, 5, HOST_HAIR], [5, 13, 2, 6, 13, 3, HOST_SHINE],
		[4, 10, 4, 4, 10, 4, WHITE], [5, 10, 4, 5, 10, 4, EYE],
		[7, 10, 4, 7, 10, 4, EYE], [8, 10, 4, 8, 10, 4, WHITE],
		[4, 11, 4, 5, 11, 4, HOST_HAIR], [7, 11, 4, 8, 11, 4, HOST_HAIR],
		[6, 9, 5, 6, 9, 5, SKIN],
		# raised arm (no fingers: a fist) with the bill above it
		[11, 4, 1, 12, 8, 3, HOST_SUIT], [11, 9, 1, 12, 10, 3, SKIN],
		[10, 11 + bill_y, 3, 13, 13 + bill_y, 3, BILL], [11, 12 + bill_y, 3, 12, 12 + bill_y, 3, BILL_DARK],
	]
	if talk:
		boxes.append_array([[4, 6, 4, 8, 7, 4, MOUTH], [4, 7, 4, 8, 7, 4, WHITE], [3, 7, 4, 3, 7, 4, MOUTH], [9, 7, 4, 9, 7, 4, MOUTH]])
	else:
		boxes.append_array([[4, 7, 4, 8, 7, 4, WHITE], [3, 8, 4, 3, 8, 4, MOUTH], [9, 8, 4, 9, 8, 4, MOUTH]])
	return boxes

static func grunt_mesh(frame: int) -> ArrayMesh:
	return from_boxes(_grunt_boxes(frame), Vector3(3.5, 0, 2))

static func player_mesh(frame: int) -> ArrayMesh:
	return from_boxes(_player_boxes(frame), Vector3(3.5, 0, 2))

static func brute_mesh(frame: int) -> ArrayMesh:
	return from_boxes(_brute_boxes(frame), Vector3(4.5, 0, 2.5))

static func sniper_mesh(frame: int) -> ArrayMesh:
	return from_boxes(_sniper_boxes(frame), Vector3(3.5, 0, 2))

static func boss_mesh(frame: int) -> ArrayMesh:
	return from_boxes(_boss_boxes(frame), Vector3(4.5, 0, 2.5))

## A floating mine, centred on the origin: a spiked ball with a light on top (white, so it takes the tint).
static func mine_mesh() -> ArrayMesh:
	return from_boxes([
		[1, 1, 0, 4, 4, 5, MINE_SHELL], [0, 1, 1, 5, 4, 4, MINE_SHELL], [1, 0, 1, 4, 5, 4, MINE_SHELL],
		[2, 2, -1, 3, 3, -1, SPIKE], [2, 2, 6, 3, 3, 6, SPIKE], [-1, 2, 2, -1, 3, 3, SPIKE], [6, 2, 2, 6, 3, 3, SPIKE],
		[2, 5, 2, 3, 5, 3, WHITE], [2, -1, 2, 3, -1, 3, SPIKE],
	], Vector3(2.5, 2.5, 2.5))

## A barrel lying across its direction of travel (its length along X), centred on the origin.
static func barrel_mesh() -> ArrayMesh:
	return from_boxes([
		[0, 1, 0, 7, 4, 5, BARREL], [0, 0, 1, 7, 5, 4, BARREL],
		[1, 1, 0, 1, 4, 5, HOOP], [1, 0, 1, 1, 5, 4, HOOP], [6, 1, 0, 6, 4, 5, HOOP], [6, 0, 1, 6, 5, 4, HOOP],
		[0, 1, 1, 0, 4, 4, HAZARD], [7, 1, 1, 7, 4, 4, HAZARD],
	], Vector3(4, 2.5, 2.5))

## Prizes, in SmashPrizes order: cash, gold bar, toaster, VCR, car.
static func prize_mesh(kind: int) -> ArrayMesh:
	match kind:
		0:
			return from_boxes([[0, 0, 0, 5, 1, 3, BILL], [2, 0, 0, 3, 1, 3, WHITE]], Vector3(3, 0, 2))
		1:
			return from_boxes([[0, 0, 0, 5, 1, 2, GOLD], [1, 2, 0, 4, 2, 2, GOLD_LIGHT]], Vector3(3, 0, 1.5))
		2:
			return from_boxes([[0, 0, 0, 5, 4, 3, SILVER], [1, 4, 1, 1, 4, 2, DARK], [4, 4, 1, 4, 4, 2, DARK],
					[6, 2, 1, 6, 2, 1, DARK]], Vector3(3, 0, 2))
		3:
			return from_boxes([[0, 0, 0, 8, 1, 5, DARK], [2, 1, 5, 5, 1, 5, Color(0.4, 0.4, 0.42)],
					[6, 1, 5, 7, 1, 5, Color(0.2, 1.0, 0.4)]], Vector3(4.5, 0, 3))
	return from_boxes([
		[0, 1, 0, 11, 2, 5, CAR_RED], [3, 3, 1, 8, 3, 4, GLASS], [3, 4, 1, 8, 4, 4, CAR_RED],
		[1, 0, 0, 2, 1, 0, BOOT], [9, 0, 0, 10, 1, 0, BOOT], [1, 0, 5, 2, 1, 5, BOOT], [9, 0, 5, 10, 1, 5, BOOT],
		[11, 2, 1, 11, 2, 1, Color(1, 1, 0.6)], [11, 2, 4, 11, 2, 4, Color(1, 1, 0.6)],
	], Vector3(6, 0, 3))

static func host_mesh(frame: int) -> ArrayMesh:
	return from_boxes(_host_boxes(frame), Vector3(6.5, 0, 2))

## A rocket pointing +Z, centred on the origin.
static func rocket_mesh() -> ArrayMesh:
	return from_boxes([
		[0, 0, 0, 1, 1, 3, Color(0.9, 0.2, 0.15)], [0, 0, 4, 1, 1, 4, Color(0.8, 0.8, 0.8)],
		[0, 0, -1, 1, 1, -1, Color(1.0, 0.8, 0.2)],
	], Vector3(1, 1, 2))

## Pickup crate: white (the slot's material tints it), banded so it reads as a box.
static func crate_mesh() -> ArrayMesh:
	return from_boxes([
		[0, 0, 0, 5, 5, 5, WHITE], [0, 2, 0, 5, 3, 5, Color(0.55, 0.55, 0.55)],
	], Vector3(3, 0, 3))

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

## The arena is three kinds of mesh so each room can re-tint them through their materials (nothing rebuilt):
## the checkered floor plus the corridor floors (greys), the walls (white), and one door frame per door.
## `half` is half the inside width; door k is turned k quarter-turns from north (0 N, 1 E, 2 S, 3 W).
static func floor_mesh(half: float, door_half: float, corridor: float) -> ArrayMesh:
	var m := _Arrays.new()
	var tile := 2.0
	var n := int(half * 2 / tile)
	for i in n:
		for j in n:
			var c := Color(0.8, 0.8, 0.8) if (i + j) % 2 == 0 else WHITE
			m.box(Vector3(-half + i * tile, -0.2, -half + j * tile), Vector3(tile, 0.2, tile), c)
	for k in 4:
		_turned_box(m, Vector3(-door_half, -0.2, -half - 1.0 - corridor), Vector3(door_half, 0, -half), k, Color(0.45, 0.45, 0.5))
	return m.commit()

static func walls_mesh(half: float, door_half: float, corridor: float) -> ArrayMesh:
	var m := _Arrays.new()
	var t := 1.0
	var h := 1.2
	for k in 4:
		_turned_box(m, Vector3(-half - t, 0, -half - t), Vector3(-door_half - 0.4, h, -half), k, WHITE)
		_turned_box(m, Vector3(door_half + 0.4, 0, -half - t), Vector3(half + t, h, -half), k, WHITE)
		_turned_box(m, Vector3(-door_half - t, 0, -half - t - corridor), Vector3(-door_half, h, -half - t), k, WHITE)
		_turned_box(m, Vector3(door_half, 0, -half - t - corridor), Vector3(door_half + t, h, -half - t), k, WHITE)
	return m.commit()

static func door_mesh(half: float, door_half: float, k: int) -> ArrayMesh:
	var m := _Arrays.new()
	var t := 1.0
	var h := 1.6
	_turned_box(m, Vector3(-door_half - 0.4, 0, -half - t), Vector3(-door_half, h, -half), k, WHITE)
	_turned_box(m, Vector3(door_half, 0, -half - t), Vector3(door_half + 0.4, h, -half), k, WHITE)
	return m.commit()

static func _turned_box(m: _Arrays, a: Vector3, b: Vector3, k: int, color: Color) -> void:
	a = _turn(a, k)
	b = _turn(b, k)
	m.box(a.min(b), (a - b).abs(), color)

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

## Explosion flash picture: a chunky ragged disc, brighter in the middle.
static func boom_texture() -> ImageTexture:
	var s := 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5 - s * 0.5, y + 0.5 - s * 0.5).length() / (s * 0.5)
			var edge := 0.85 + rng.randf() * 0.15
			img.set_pixel(x, y, Color(1, 1, 1, 0) if d > edge else Color(1, 1, 1, 1.0 if d < 0.5 else 0.7))
	return ImageTexture.create_from_image(img)

## Unshaded vertex-colour material shared by the voxel meshes. Its albedo colour tints them (rooms, flashes).
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
