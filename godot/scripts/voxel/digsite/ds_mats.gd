class_name DsMats
## The Dig Site's materials (DigSiteGrid's ids: dig_site_grid.cpp has the same list): their names, colours (the chunky
## look of the arena's yard: a block a colour, a shade off block to block), how hard they are (the tools' and machines'
## power has to reach it: 1 a shovel, 2 a good shovel, 3 the pick, 4 a good pick, 99 never) and what a block dug out
## becomes in the backpack (VoxelItems). Owned by the voxel session.

const AIR := 0
const TOPSOIL := 1
const DIRT := 2
const CLAY := 3
const SAND := 4
const GRAVEL := 5
const STONE := 6
const HARDROCK := 7
const BEDROCK := 8
const COAL := 9
const IRON := 10
const GOLD := 11
const GEM := 12
const EDGE := 13                # the ring round the site: looks like the ground, never digs
const WOOD := 14                # a wooden prop (stage 8)
const CONCRETE := 15            # a concrete support (stage 8)
const LOOSE := 0x20             # (the cell's bit: loose, not firm; stage 4)
const MASK := 0x1f

const NAME := ["air", "topsoil", "dirt", "clay", "sand", "gravel", "stone", "hard rock", "bedrock", "coal", "iron ore",
	"gold ore", "gems", "ground", "wood", "concrete"]
const COL := [Color(0, 0, 0), Color8(92, 66, 42), Color8(122, 86, 52), Color8(170, 104, 64), Color8(214, 190, 128),
	Color8(132, 126, 118), Color8(128, 126, 122), Color8(82, 80, 86), Color8(36, 34, 40), Color8(46, 44, 48),
	Color8(150, 98, 72), Color8(232, 188, 56), Color8(90, 210, 220), Color8(122, 86, 52), Color8(168, 120, 70),
	Color8(176, 176, 170)]
const GRASS := Color8(86, 124, 56)
const HARD := [0, 1, 1, 2, 1, 1, 3, 4, 99, 3, 4, 4, 5, 99, 2, 5]
## What a block dug out is in the backpack ("": nothing)
const ITEM := ["", "dirt", "dirt", "clay", "sand", "stone", "stone", "stone", "", "coal", "iron_ore", "gold", "gem", "", "", ""]

## The grid's materials handed to it (colours, hardness, the grass on top)
static func apply(g: DigSiteGrid) -> void:
	g.set_materials(PackedColorArray(COL), PackedInt32Array(HARD), GRASS)

static func name_of(m: int) -> String:
	return NAME[m & MASK] if (m & MASK) < NAME.size() else "?"
