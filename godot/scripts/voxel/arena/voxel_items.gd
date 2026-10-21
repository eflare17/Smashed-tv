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
	"dirt": {"name": "Dirt", "col": Color8(116, 80, 48), "stack": 9999, "desc": "Dug out of the yard. The shovel's right click puts it back."},
	"clay": {"name": "Clay", "col": Color8(168, 102, 62), "stack": 9999, "desc": "Sticky orange clay from the yard."},
	"stone": {"name": "Stone", "col": Color8(128, 126, 122), "stack": 9999, "desc": "Broken out with the pick. The tool bench wants it."},
	"gold": {"name": "Gold nugget", "col": Color8(236, 190, 56), "stack": 999, "desc": "From the gold ore deep down. For a silly golden shovel."},
	"worm": {"name": "Worm", "col": Color8(214, 120, 128), "stack": 99, "desc": "Wriggly. Found digging the dirt; for a worm farm one day."},
}

static var _by_col := {}
static var EXTRA := {}          # the farm's (seeds, buds, castings: VoxelFarm.items), made the first time asked

static func _extra() -> Dictionary:
	if EXTRA.is_empty():
		EXTRA = VoxelFarm.items()
	return EXTRA

static func _info(id: String) -> Dictionary:
	return ITEMS[id] if ITEMS.has(id) else _extra().get(id, {})

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
	return ITEMS.has(id) or _extra().has(id)

static func name_of(id: String) -> String:
	return String(_info(id).get("name", id))

static func colour(id: String) -> Color:
	return _info(id).get("col", Color.MAGENTA)

static func stack_max(id: String) -> int:
	return int(_info(id).get("stack", 1))

static func desc(id: String) -> String:
	return String(_info(id).get("desc", ""))
