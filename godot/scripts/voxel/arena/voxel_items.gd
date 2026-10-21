class_name VoxelItems
## Everything that can be carried or stored (the owner, 21 Oct, Stage 2: "a proper inventory" in place of the
## vacuum's counts): an item id -> its name, the colour its little cube icon is drawn in (and the cubes it's dropped as),
## how many go in one slot, a line saying what it is. The vacuum's cubes come in by their colour (of_colour). Later
## stages add theirs here (tools, seeds, worms, eggs). Owned by the voxel session.

const ITEMS := {
	"blocks": {"name": "Rubble", "col": Color8(120, 118, 128), "stack": 9999, "desc": "Bits of clothes, skin and gear knocked off them."},
	"meat": {"name": "Meat", "col": Color8(150, 22, 28), "stack": 9999, "desc": "Raw red cubes. Good fertiliser one day."},
	"bone": {"name": "Bone", "col": Color8(226, 220, 204), "stack": 9999, "desc": "Bone cubes. Blood and bone, later."},
	"brain": {"name": "Brain", "col": Color8(218, 150, 162), "stack": 9999, "desc": "Pink and squishy. Worth the most."},
	"charred": {"name": "Charred bits", "col": Color8(34, 26, 22), "stack": 9999, "desc": "Burnt black by the flamethrower. Worth less."},
	"padlock": {"name": "Padlock", "col": Color8(201, 160, 64), "stack": 4, "desc": "A spin-dial padlock. L at a chest hangs it on."},
}

static var _by_col := {}

## The item a vacuumed cube of this colour is.
static func of_colour(col: Color) -> String:
	if _by_col.is_empty():
		for c in VoxelBody.FLESH:
			_by_col[(c as Color).to_rgba32()] = "meat"
		for c in VoxelBody.BRAIN:
			_by_col[(c as Color).to_rgba32()] = "brain"
		_by_col[VoxelBody.BONE.to_rgba32()] = "bone"
		_by_col[VoxelBody.CHAR.to_rgba32()] = "charred"
	return _by_col.get(col.to_rgba32(), "blocks")

## Made of cubes (what the vacuum takes): dropped, it falls as its cubes. The rest (a padlock) can't be dropped.
static func is_cubes(id: String) -> bool:
	return id in ["blocks", "meat", "bone", "brain", "charred"]

static func has(id: String) -> bool:
	return ITEMS.has(id)

static func name_of(id: String) -> String:
	return String(ITEMS[id].name) if ITEMS.has(id) else id

static func colour(id: String) -> Color:
	return ITEMS[id].col if ITEMS.has(id) else Color.MAGENTA

static func stack_max(id: String) -> int:
	return int(ITEMS[id].stack) if ITEMS.has(id) else 1

static func desc(id: String) -> String:
	return String(ITEMS[id].desc) if ITEMS.has(id) else ""
