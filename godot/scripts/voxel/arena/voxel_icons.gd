class_name VoxelIcons
## Each item's own little picture in the backpack and the chests (the owner, 29 Oct: "give icons in the invtory"), in
## place of the same cube in different colours: a steak, a bone, a brain, a pile of rubble, burnt lumps, a mound of
## dirt, a lump of clay, a rock, a gold nugget, a worm, a padlock, a brick, a seed, a bud, an egg, grain, a poo, a
## chicken, a bag of blood and bone. Pixel art, 16 by 16, drawn in the item's own colour (VoxelItems.colour: a bud's
## the colour of its strain) with darker and lighter shades of it, made the first time asked and kept.
##
## The art: a row a string, one letter a pixel: . nothing, o outline (the colour darkest), d dark, m the colour,
## l light, w lightest (or as the icon says), e an ember's orange, s steel, k near black.

const SIZE := 16
const UP := 4                  # drawn this many screen pixels a pixel (made big here, so it stays sharp)

const ART := {
	"meat": ["", "", ".....oooooo", "...oommmmmmoo", "..ommmmmmmmmmo", ".ommmwwmmmmmmmo", ".ommwwwwmmmmmmo",
		".ommmwwmmmmmmmo", ".ommmmmmmmmmmdo", "..ommmmmmmmmddo", "..oddmmmmmmddo", "...ooddddddoo", ".....oooooo"],
	"bone": ["", "", "", "..oo........oo", ".olwo......olwo", ".olwlooooooolwo", "..olwwwwwwwwlo", ".olllooooooollo",
		".ollo......ollo", "..oo........oo"],
	"brain": ["", "", ".....oooooo", "...oollmlllmoo", "..olmlllmlllmlo", ".olllmllmlllllmo", ".olmllllmllmlllo",
		".ollllmllmlllmlo", ".olmllmlllllmllo", "..olllllmllllo", "...oodmmmmddoo", ".....oddddo"],
	"rubble": ["", "", "......ooooo", "......ollmo", "......olmdo", "......ooooo", "..ooooo.ooooo", "..ollmo.ollmo",
		"..olmdo.olmdo", "..ooooo.ooooo"],
	"charred": ["", "", ".....oooo", "....ommmdo", "...ommemmdo", "...ommmmmdo.oo", "..oo.oddddo.omdo", ".ommdo.oooomemdo",
		".omemdo...ommmdo", ".ommmdo....oddo", "..oddo......oo"],
	"mound": ["", "", "", "", "......oooo", "....oolmmmoo", "...olmmmdmmmo", "..olmmdmmmmdmo", ".olmmmmmmdmmmmo",
		".ommdmmmmmmmdmo", ".oooooooooooooo"],
	"lump": ["", "", "", ".....oooooo", "...oollllmmoo", "..ollmmmmmmmdo", "..olmmmmmmmmdo", "..ommmmmmmmddo",
		"...oddmmmdddo", "....ooooooooo"],
	"rock": ["", "", "......ooooo", "....ooolllmo", "...olllmmmmdo", "..ollmmmmmmmdo", "..olmmmmmmmddo",
		".olmmmmmmmdddo", ".ommmmmmmddddo", "..oooooooooooo"],
	"nugget": ["", "", "......ooooo", "....ooolwlmo", "...ollwmmmmdo", "..ollmmmmlmmdo", "..olmmmmmmmddo",
		".olmmlmmmmdddo", ".ommmmmmmddddo", "..oooooooooooo"],
	"worm": ["", "", "..........ooo", ".........ollmo", "....ooo..olo", "...ollmo.olmo", "..olo.olmmlo", "..olo..oooo",
		".olmo", "..oo"],
	"padlock": ["", ".....ssssss", "....s......s", "...s..ssss..s", "...s.s....s.s", "..oooooooooooo", "..olllllllllmo",
		"..olllkkklllmo", "..ollllkllmmmo", "..olllllllmmmo", "..ommmmmmmmmmo", "..oooooooooooo"],
	"brick": ["", "", "", "..oooooooooooo", "..ollllllllllo", "..olmmmmmmmmdo", "..olmmmmmmmmdo", "..oddddddddddo",
		"..oooooooooooo", "....oooooooooooo", "....ollllllllllo", "....odddddddddddo", "....oooooooooooo"],
	"seed": ["", "", "......oooo", ".....olllmo", "....ollmmmdo", "....olmmmmdo", "....olmmmmdo", "....olmmmddo",
		".....ommddo", "......oooo"],
	"bud": ["", ".......o", "......olo", "...o..olo..o", "..olo.olo.olo", "...olollolo", "....ollmllo", "...ollmmmllo",
		"...olmmmmmdo", "....olmmmdo", ".....ommdo", "......oo"],
	"egg": ["", "......oooo", ".....owwllo", "....owlllllo", "....olllllmo", "...olllllllmo", "...ollllllmmo",
		"...olllllmmmo", "....ollmmmmo", ".....oooooo"],
	"grain": ["", "", "......ol", "...ol....ol", "......ol...ol", "..ol.ol..ol", ".....ollol.ol", "...olmlmlmlmlo",
		"..olmmmmmmmmmmo", "..oooooooooooo"],
	"poo": ["", ".......oo", "......olmo", ".....ollmmo", "....oommmmoo", "...ollllmmmmo", "..oommmmmmmdoo",
		".olllllmmmmmmdo", ".ommmmmmmmmmddo", "..oooooooooooo"],
	"chicken": ["", "", "....oooooo", "..oollllllmoo", ".olllllllllmmo", ".ollllllllmmmdo", ".olllllllmmmmdo",
		"..ommmmmmmmmdo", "...oommmmmddoo", "..wo..oooo..ow", ".ww..........ww"],
	"bag": ["", "......o..o", ".......oo", "......olmo", "....oollmmoo", "...ollllmmmmo", "..ollwwwwmmmdo",
		"..ollwkwkmmmdo", "..ollllmmmmmdo", "..ommmmmmmmddo", "...oooooooooo"],
}

## Which picture each item is (the rest by the start of their id: seeds and buds of every strain).
const OF := {"blocks": "rubble", "meat": "meat", "bone": "bone", "brain": "brain", "charred": "charred",
	"padlock": "padlock", "dirt": "mound", "clay": "lump", "stone": "rock", "gold": "nugget", "worm": "worm",
	"brick": "brick", "castings": "mound", "egg": "egg", "grain": "grain", "poo": "poo", "chicken_carcass": "chicken",
	"roast_chicken": "chicken", "burnt_chicken": "chicken", "blood_bone": "bag"}
## Letters that aren't shades of the item's colour, for some.
const FIXED := {"meat": {"w": Color(0.96, 0.9, 0.8)}, "chicken": {"w": Color(0.95, 0.92, 0.85)},
	"bag": {"w": Color(0.93, 0.9, 0.82), "k": Color(0.55, 0.12, 0.1)}, "padlock": {"k": Color(0.1, 0.08, 0.06)}}

static var _made := {}         # item id -> ImageTexture (or null: no picture, the cube then)

## The item's picture, or null (draw the cube).
static func of(id: String) -> Texture2D:
	if _made.has(id):
		return _made[id]
	var art := String(OF.get(id, ""))
	if art == "":
		if id.begins_with("seed_"):
			art = "seed"
		elif id.begins_with("bud_"):
			art = "bud"
	var tex: Texture2D = null
	if ART.has(art):
		tex = _paint(ART[art], VoxelItems.colour(id), FIXED.get(art, {}))
	_made[id] = tex
	return tex

static func _paint(rows: Array, c: Color, fixed: Dictionary) -> ImageTexture:
	var pal := {"o": c.darkened(0.6), "d": c.darkened(0.28), "m": c, "l": c.lightened(0.25), "w": c.lightened(0.55),
		"e": Color(1.0, 0.5, 0.1), "s": Color(0.62, 0.64, 0.68), "k": c.darkened(0.75)}
	pal.merge(fixed, true)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var top := maxi(0, (SIZE - rows.size()) / 2)       # (the picture in the middle, up and down)
	for y in rows.size():
		var row := String(rows[y])
		for x in mini(row.length(), SIZE):
			var ch := row[x]
			if pal.has(ch) and top + y < SIZE:
				img.set_pixel(x, top + y, pal[ch])
	img.resize(SIZE * UP, SIZE * UP, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)
