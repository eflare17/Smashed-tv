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
const COL := [Color(0, 0, 0), Color8(104, 58, 38), Color8(120, 64, 44), Color8(176, 104, 62), Color8(214, 190, 128),
	Color8(132, 126, 118), Color8(128, 126, 122), Color8(82, 80, 86), Color8(36, 34, 40), Color8(46, 44, 48),
	Color8(150, 98, 72), Color8(232, 188, 56), Color8(90, 210, 220), Color8(120, 64, 44), Color8(168, 120, 70),
	Color8(176, 176, 170)]
const GRASS := Color8(86, 124, 56)
const HARD := [0, 1, 1, 2, 1, 1, 3, 4, 99, 3, 4, 4, 5, 99, 2, 5]
## How tall a firm wall of it stands straight up before it gives way (cells; 0: never, rock): clay stands best, sand
## hardly at all (DigSiteGrid's dirt, stage 4: past this, or past ~60 degrees, its rim turns loose and slumps)
const WALL := [0, 10, 12, 20, 3, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
## How wide a roof of it spans with nothing holding it up (cells; 0: never caves: bedrock, the edge, supports):
## dirt 2 m, clay 2.5 m, sand 0.75 m, stone 6 m, hard rock 8 m (DigSiteGrid's cave-ins, stage 7)
const SPAN := [0, 12, 16, 20, 6, 8, 48, 64, 0, 32, 48, 48, 64, 0, 0, 0]
## How far a blast reaches into it, of its full radius (0: never: bedrock, the edge): soft ground all of it, stone
## 60%, hard rock less (DsBlasts, stage 9)
const BLAST := [0.0, 1.0, 1.0, 0.85, 1.1, 1.0, 0.6, 0.45, 0.0, 0.65, 0.55, 0.55, 0.5, 0.0, 0.9, 0.4]
## What a block dug out is in the backpack ("": nothing)
const ITEM := ["", "dirt", "dirt", "clay", "sand", "gravel", "stone", "stone", "", "coal", "iron_ore", "gold", "gem", "", "", ""]

## The grid's materials handed to it (colours, hardness, the grass on top)
static func apply(g: DigSiteGrid) -> void:
	g.set_materials(PackedColorArray(COL), PackedInt32Array(HARD), GRASS)
	g.set_physics(PackedInt32Array(WALL))
	g.set_spans(PackedInt32Array(SPAN))

static func name_of(m: int) -> String:
	return NAME[m & MASK] if (m & MASK) < NAME.size() else "?"
