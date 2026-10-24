class_name MineTiles
extends RefCounted
## The mine's materials (the owner, 23 Oct: "the graphics from my sand digging game ... every pixel destructible"):
## what each cell of the pixel world (MineSim) is, how hard it is to drill, what drilling it brings up, and its eight
## shades, as Sand Miner (the cabinet game in Smashed.html) shaded its dirt, sand, water and ores; and the back walls
## seen where it's dug. apply() hands it all to a MineSim. Owned by the voxel session.

const AIR := 0
const DIRT := 1                 # topsoil
const CLAY := 2
const STONE := 3                # grey stone
const RED := 4                  # deep red rock
const BASALT := 5               # black basalt
const CRYSTAL := 6              # the glowing crystal rock at the bottom
const BEDROCK := 7              # nothing gets through (the edges and the bottom)
const PAD := 8                  # the concrete under the buildings up top
const HARD1 := 9                # boulders that need a better drill: Mk II ...
const HARD2 := 10               # ... Mk III ...
const HARD3 := 11               # ... Mk IV
const COAL := 12
const COPPER := 13
const SILVER := 14
const GOLD := 15
const OPAL := 16
const DIAMOND := 17
const FOOLS := 18               # fool's gold (in the mushroom caves): crumbles to nothing
const SPORE := 19               # spore clumps (mushroom caves): sell
const LAVA := 20                # flows out into what you've dug, burns
const GAS := 21                 # a gas pocket: goes off when drilled
const BRICK := 22               # the sewers' walls
const JUNK := 23                # sewer junk: a bit of cash
const CONCRETE := 24            # the cop bunker's walls (needs Mk II)
const EVIDENCE := 25            # the bunker's evidence lockers
const STASH := 26               # the rival dealers' stockpile
const HOARD := 27               # the worm's diamond hoard
const SHROOM := 28              # the giant mushroom in the cathedral
const TIMBER := 29              # the rival tunnels' props
const SAND := 30                # falls and piles
const WATER := 31               # flows and pools
const OBSIDIAN := 32            # lava that met water

# the back walls (what's behind an open cell)
const BG_SKY := 0
const BG_DIRT := 1              # the earth's own, by zone: 1..6 (DIRT .. CRYSTAL's)
const BG_MUSH := 10
const BG_SEWER := 11
const BG_BUNKER := 12
const BG_RIVAL := 13
const BG_WORM := 14
const BG_CATHEDRAL := 15

const F := {"solid": 1, "falls": 2, "liquid": 4, "dig": 8, "twinkle": 16, "rim": 32, "crumble": 64, "softedge": 128,
	"toplit": 256, "anim": 512, "glow": 1024, "hot": 2048, "wet": 4096, "grass": 8192, "nochip": 16384}

## Each material: name, hardness (seconds a metre to drill with the first drill; < 0 never), the drill level it
## needs, what goes in the hold ("" nothing), cells a cargo item, its ways, its colour (the base of its shades) or
## shades of its own, what it glows
const INFO := {
	AIR: {"name": "air", "hard": 0.0, "need": 0, "cargo": "", "per": 0, "f": []},
	DIRT: {"name": "topsoil", "hard": 0.32, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig", "crumble", "grass"], "col": [112, 74, 46]},
	CLAY: {"name": "clay", "hard": 0.5, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig", "crumble", "softedge"], "col": [150, 92, 56]},
	STONE: {"name": "stone", "hard": 0.95, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig"], "col": [112, 112, 118]},
	RED: {"name": "red rock", "hard": 1.5, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig"], "col": [132, 56, 42]},
	BASALT: {"name": "basalt", "hard": 2.2, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig"], "col": [52, 50, 58]},
	CRYSTAL: {"name": "crystal rock", "hard": 3.0, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig", "glow"],
		"shades": [[56, 48, 92], [58, 50, 95], [60, 52, 98], [62, 53, 101], [64, 55, 104], [66, 57, 107], [70, 60, 112], [150, 120, 230]], "glow": [0.3, 0.2, 0.7]},
	BEDROCK: {"name": "bedrock", "hard": -1.0, "need": 0, "cargo": "", "per": 0, "f": ["solid"], "col": [26, 26, 30]},
	PAD: {"name": "concrete pad", "hard": -1.0, "need": 0, "cargo": "", "per": 0, "f": ["solid"], "col": [140, 140, 136]},
	HARD1: {"name": "granite boulder", "hard": 2.0, "need": 1, "cargo": "", "per": 0, "f": ["solid", "dig", "rim"], "col": [168, 158, 148]},
	HARD2: {"name": "ironstone boulder", "hard": 3.0, "need": 2, "cargo": "", "per": 0, "f": ["solid", "dig", "rim"], "col": [124, 88, 76]},
	HARD3: {"name": "obsidian boulder", "hard": 4.0, "need": 3, "cargo": "", "per": 0, "f": ["solid", "dig", "rim", "glow"], "col": [44, 30, 64], "glow": [0.35, 0.15, 0.6]},
	COAL: {"name": "coal", "hard": 1.0, "need": 0, "cargo": "coal", "per": 10, "f": ["solid", "dig", "rim"],
		"shades": [[37, 36, 42], [39, 39, 45], [41, 41, 47], [43, 42, 50], [53, 46, 54], [53, 57, 72], [66, 69, 91], [79, 87, 117]]},
	COPPER: {"name": "copper", "hard": 1.1, "need": 0, "cargo": "copper", "per": 10, "f": ["solid", "dig", "rim"],
		"shades": [[94, 48, 30], [126, 62, 34], [156, 76, 38], [184, 92, 44], [204, 110, 56], [222, 132, 72], [236, 158, 98], [248, 188, 132]]},
	SILVER: {"name": "silver", "hard": 1.2, "need": 0, "cargo": "silver", "per": 9, "f": ["solid", "dig", "rim", "twinkle"],
		"shades": [[81, 96, 117], [98, 117, 141], [119, 141, 164], [137, 163, 186], [148, 189, 213], [171, 214, 228], [197, 227, 237], [220, 245, 248]]},
	GOLD: {"name": "gold", "hard": 1.3, "need": 0, "cargo": "gold", "per": 9, "f": ["solid", "dig", "rim", "twinkle"],
		"shades": [[93, 48, 20], [172, 84, 9], [207, 94, 6], [227, 112, 5], [245, 133, 3], [251, 154, 1], [251, 191, 23], [254, 223, 42]]},
	OPAL: {"name": "opal", "hard": 1.4, "need": 0, "cargo": "opal", "per": 8, "f": ["solid", "dig", "rim", "twinkle", "glow"],
		"shades": [[60, 120, 140], [90, 170, 190], [130, 210, 220], [240, 150, 220], [150, 230, 170], [250, 220, 140], [200, 170, 250], [245, 250, 255]], "glow": [0.35, 0.5, 0.6]},
	DIAMOND: {"name": "diamond", "hard": 1.6, "need": 0, "cargo": "diamond", "per": 7, "f": ["solid", "dig", "rim", "twinkle", "glow"],
		"shades": [[73, 91, 99], [97, 135, 170], [131, 168, 192], [169, 198, 222], [170, 227, 246], [194, 237, 249], [211, 249, 252], [246, 254, 254]], "glow": [0.5, 0.75, 0.85]},
	FOOLS: {"name": "gold?", "hard": 0.6, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig", "rim", "twinkle"],
		"shades": [[93, 48, 20], [172, 84, 9], [207, 94, 6], [227, 112, 5], [245, 133, 3], [251, 154, 1], [251, 191, 23], [254, 223, 42]]},
	SPORE: {"name": "spore clump", "hard": 0.25, "need": 0, "cargo": "spore", "per": 8, "f": ["solid", "dig", "rim", "glow"],
		"shades": [[110, 40, 120], [140, 50, 150], [170, 60, 170], [200, 80, 190], [220, 110, 210], [235, 140, 225], [245, 170, 235], [250, 210, 245]], "glow": [0.6, 0.2, 0.6]},
	LAVA: {"name": "lava", "hard": -1.0, "need": 0, "cargo": "", "per": 0, "f": ["liquid", "anim", "hot", "glow"],
		"shades": [[150, 30, 10], [200, 50, 10], [240, 80, 10], [255, 110, 20], [255, 140, 30], [255, 170, 40], [255, 200, 60], [255, 230, 110]], "glow": [1.0, 0.45, 0.1]},
	GAS: {"name": "gas pocket", "hard": 0.6, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig", "glow", "nochip"], "col": [92, 120, 60], "glow": [0.12, 0.28, 0.04]},
	BRICK: {"name": "old brick", "hard": 0.7, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig"],
		"shades": [[120, 64, 46], [132, 72, 50], [110, 58, 42], [126, 70, 52], [116, 62, 46], [138, 78, 56], [80, 48, 36], [64, 58, 52]]},
	JUNK: {"name": "junk", "hard": 0.4, "need": 0, "cargo": "junk", "per": 8, "f": ["solid", "dig", "rim"],
		"shades": [[40, 40, 44], [70, 70, 76], [200, 40, 40], [230, 230, 230], [60, 140, 70], [90, 90, 200], [150, 150, 150], [30, 30, 30]]},
	CONCRETE: {"name": "bunker concrete", "hard": 2.4, "need": 1, "cargo": "", "per": 0, "f": ["solid", "dig"],
		"shades": [[140, 142, 146], [132, 134, 138], [146, 148, 152], [126, 128, 132], [150, 152, 156], [120, 122, 126], [90, 92, 96], [70, 72, 76]]},
	EVIDENCE: {"name": "evidence locker", "hard": 0.8, "need": 0, "cargo": "evidence", "per": 12, "f": ["solid", "dig"],
		"shades": [[70, 90, 120], [74, 94, 126], [70, 90, 120], [64, 84, 112], [80, 100, 130], [230, 200, 40], [40, 50, 70], [30, 36, 50]]},
	STASH: {"name": "rival stash", "hard": 0.5, "need": 0, "cargo": "stash", "per": 10, "f": ["solid", "dig"],
		"shades": [[230, 230, 220], [232, 232, 222], [200, 200, 190], [216, 216, 206], [160, 124, 64], [180, 140, 80], [100, 70, 40], [80, 56, 32]]},
	HOARD: {"name": "hoard diamond", "hard": 0.4, "need": 0, "cargo": "hoard", "per": 6, "f": ["solid", "dig", "rim", "twinkle", "glow"],
		"shades": [[150, 200, 220], [170, 220, 240], [190, 235, 250], [210, 245, 255], [225, 250, 255], [240, 252, 255], [250, 255, 255], [255, 255, 255]], "glow": [0.7, 0.85, 1.0]},
	SHROOM: {"name": "giant mushroom", "hard": 0.6, "need": 0, "cargo": "shroom", "per": 14, "f": ["solid", "dig", "glow"],
		"shades": [[190, 40, 100], [210, 50, 110], [220, 60, 120], [235, 80, 140], [245, 100, 160], [250, 120, 180], [255, 240, 230], [255, 255, 250]], "glow": [0.5, 0.15, 0.35]},
	TIMBER: {"name": "timber", "hard": 0.3, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig"],
		"shades": [[130, 90, 50], [120, 84, 46], [110, 76, 42], [124, 86, 48], [104, 70, 38], [140, 98, 56], [70, 46, 26], [60, 40, 22]]},
	SAND: {"name": "sand", "hard": 0.05, "need": 0, "cargo": "", "per": 0, "f": ["solid", "falls", "dig", "toplit"], "col": [224, 198, 122]},
	WATER: {"name": "water", "hard": -1.0, "need": 0, "cargo": "", "per": 0, "f": ["liquid", "anim", "wet"],
		"shades": [[40, 100, 200], [44, 108, 208], [48, 114, 214], [50, 118, 222], [54, 124, 226], [58, 130, 230], [64, 138, 234], [72, 146, 238]]},
	OBSIDIAN: {"name": "obsidian", "hard": 1.1, "need": 0, "cargo": "", "per": 0, "f": ["solid", "dig", "rim", "twinkle"],
		"shades": [[62, 48, 86], [54, 42, 76], [70, 56, 98], [46, 36, 66], [58, 46, 82], [96, 82, 130], [40, 30, 58], [30, 22, 44]]},
}

## The back walls: their colour (or a material's, darkened as Sand Miner did) and pattern (0 grain, 1 brick, 2 planks,
## 3 tiles)
const BACKS := {
	1: {"of": DIRT}, 2: {"of": CLAY}, 3: {"of": STONE}, 4: {"of": RED}, 5: {"of": BASALT}, 6: {"of": CRYSTAL},
	BG_MUSH: {"col": [62, 30, 76], "pattern": 0},
	BG_SEWER: {"col": [84, 70, 60], "pattern": 1},
	BG_BUNKER: {"col": [76, 80, 86], "pattern": 3},
	BG_RIVAL: {"col": [84, 58, 36], "pattern": 2},
	BG_WORM: {"col": [84, 40, 42], "pattern": 0},
	BG_CATHEDRAL: {"col": [44, 32, 86], "pattern": 0},
}

## Which back wall the earth has in each zone (by its rock)
const ZONE_BACK := {DIRT: 1, CLAY: 2, STONE: 3, RED: 4, BASALT: 5, CRYSTAL: 6}

static func info(t: int) -> Dictionary:
	return INFO.get(t, INFO[AIR])

static func is_ore(t: int) -> bool:
	return String(info(t).cargo) != ""

## Eight shades from a base colour (Sand Miner's: 0.85 .. 1.13 of it)
static func ramp(c: Array) -> PackedColorArray:
	var out := PackedColorArray()
	for v in 8:
		var f := 0.85 + v * 0.04
		out.append(Color(minf(1.0, c[0] / 255.0 * f), minf(1.0, c[1] / 255.0 * f), minf(1.0, c[2] / 255.0 * f)))
	return out

static func shades(t: int) -> PackedColorArray:
	var i := info(t)
	if i.has("shades"):
		var out := PackedColorArray()
		for c in i.shades:
			out.append(Color8(int(c[0]), int(c[1]), int(c[2])))
		return out
	return ramp(i.get("col", [255, 0, 255]))

static func flags(t: int) -> int:
	var n := 0
	for f in info(t).f:
		n |= int(F[f])
	return n

## Everything handed to the pixel world
static func apply(sim: MineSim) -> void:
	for t in INFO:
		var i: Dictionary = INFO[t]
		var g: Array = i.get("glow", [0.0, 0.0, 0.0])
		sim.set_material(t, flags(t), float(i.hard), int(i.need), shades(t), Color(g[0], g[1], g[2]))
	for b in BACKS:
		var bi: Dictionary = BACKS[b]
		var base := shades(int(bi.of)) if bi.has("of") else ramp(bi.col)
		var dark := PackedColorArray()
		for v in 8:
			var k := (0.44 + (v & 3) * 0.02) if bi.has("of") else 1.0
			if v == 7:
				k *= 0.6             # (the mortar, the gaps)
			dark.append(Color(base[v].r * k, base[v].g * k, base[v].b * k))
		sim.set_back(b, dark, int(bi.get("pattern", 0)))
	sim.set_special(BASALT, OBSIDIAN, BEDROCK)
