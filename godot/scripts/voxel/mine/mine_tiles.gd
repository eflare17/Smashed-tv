class_name MineTiles
extends RefCounted
## The dig mode's ground (the owner, 23 Oct: "build it all", the Motherload-style mine under the yard): what each 1 m
## tile is, how hard it is to drill, what it's worth, and its picture: a 16 x 16 pixel square in one texture (the
## atlas), drawn here in code so it can be changed. Ores and other things set in the rock are drawn over the rock of
## their depth (the "over" pictures: see-through round them), so a gold vein in red rock shows the red rock round it.
## Owned by the voxel session.

const PX := 16                  # pixels a tile's picture
const COLS := 8                 # pictures a row in the atlas

# what a tile is (the ground's tiles array) ...
const AIR := 0                  # dug out, or open cave
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
const SPORE := 19               # a spore clump (mushroom caves): sells
const LAVA := 20                # flows out into what you've dug, burns
const GAS := 21                 # a gas pocket: goes off when drilled
const BRICK := 22               # the sewers' walls
const JUNK := 23                # sewer junk: a bit of cash
const CONCRETE := 24            # the cop bunker's walls (needs Mk II)
const EVIDENCE := 25            # the bunker's evidence lockers
const STASH := 26               # the rival dealers' stockpile
const HOARD := 27               # the worm's diamond hoard
const SHROOM := 28              # the giant mushroom in the cathedral
const TIMBER := 29              # the rival tunnels' props (drillable, soft)

# ... and what's behind an open tile (the bg array): the back wall's picture
const BG_EARTH := 0
const BG_MUSH := 1
const BG_SEWER := 2
const BG_BUNKER := 3
const BG_RIVAL := 4
const BG_WORM := 5
const BG_CATHEDRAL := 6

## Each tile: its name, how hard (seconds to drill it with the first drill), the drill level it needs, whether it's
## drawn over the rock of its depth, what goes in the cargo hold ("": nothing), its atlas picture.
const INFO := {
	AIR: {"name": "air", "hard": 0.0, "need": 0, "over": false, "cargo": "", "pic": 0},
	DIRT: {"name": "topsoil", "hard": 0.32, "need": 0, "over": false, "cargo": "", "pic": 1},
	CLAY: {"name": "clay", "hard": 0.5, "need": 0, "over": false, "cargo": "", "pic": 2},
	STONE: {"name": "stone", "hard": 0.95, "need": 0, "over": false, "cargo": "", "pic": 3},
	RED: {"name": "red rock", "hard": 1.5, "need": 0, "over": false, "cargo": "", "pic": 4},
	BASALT: {"name": "basalt", "hard": 2.2, "need": 0, "over": false, "cargo": "", "pic": 5},
	CRYSTAL: {"name": "crystal rock", "hard": 3.0, "need": 0, "over": false, "cargo": "", "pic": 6},
	BEDROCK: {"name": "bedrock", "hard": -1.0, "need": 0, "over": false, "cargo": "", "pic": 7},
	PAD: {"name": "concrete pad", "hard": -1.0, "need": 0, "over": false, "cargo": "", "pic": 8},
	HARD1: {"name": "granite boulder", "hard": 2.0, "need": 1, "over": true, "cargo": "", "pic": 9},
	HARD2: {"name": "ironstone boulder", "hard": 3.0, "need": 2, "over": true, "cargo": "", "pic": 10},
	HARD3: {"name": "obsidian boulder", "hard": 4.0, "need": 3, "over": true, "cargo": "", "pic": 11},
	COAL: {"name": "coal", "hard": 0.0, "need": 0, "over": true, "cargo": "coal", "pic": 12},
	COPPER: {"name": "copper", "hard": 0.0, "need": 0, "over": true, "cargo": "copper", "pic": 13},
	SILVER: {"name": "silver", "hard": 0.0, "need": 0, "over": true, "cargo": "silver", "pic": 14},
	GOLD: {"name": "gold", "hard": 0.0, "need": 0, "over": true, "cargo": "gold", "pic": 15},
	OPAL: {"name": "opal", "hard": 0.0, "need": 0, "over": true, "cargo": "opal", "pic": 16},
	DIAMOND: {"name": "diamond", "hard": 0.0, "need": 0, "over": true, "cargo": "diamond", "pic": 17},
	FOOLS: {"name": "gold?", "hard": 0.0, "need": 0, "over": true, "cargo": "", "pic": 15},
	SPORE: {"name": "spore clump", "hard": 0.25, "need": 0, "over": true, "cargo": "spore", "pic": 19},
	LAVA: {"name": "lava", "hard": -1.0, "need": 0, "over": false, "cargo": "", "pic": 20},
	GAS: {"name": "gas pocket", "hard": 0.0, "need": 0, "over": true, "cargo": "", "pic": 21},
	BRICK: {"name": "old brick", "hard": 0.7, "need": 0, "over": false, "cargo": "", "pic": 22},
	JUNK: {"name": "junk", "hard": 0.4, "need": 0, "over": true, "cargo": "junk", "pic": 23},
	CONCRETE: {"name": "bunker concrete", "hard": 2.4, "need": 1, "over": false, "cargo": "", "pic": 24},
	EVIDENCE: {"name": "evidence locker", "hard": 0.8, "need": 0, "over": false, "cargo": "evidence", "pic": 25},
	STASH: {"name": "rival stash", "hard": 0.5, "need": 0, "over": true, "cargo": "stash", "pic": 26},
	HOARD: {"name": "hoard diamond", "hard": 0.4, "need": 0, "over": true, "cargo": "hoard", "pic": 27},
	SHROOM: {"name": "giant mushroom", "hard": 0.6, "need": 0, "over": false, "cargo": "shroom", "pic": 28},
	TIMBER: {"name": "timber prop", "hard": 0.3, "need": 0, "over": false, "cargo": "", "pic": 29},
}
## The back walls' pictures (an open tile's)
const BG_PIC := {BG_MUSH: 32, BG_SEWER: 33, BG_BUNKER: 34, BG_RIVAL: 35, BG_WORM: 36, BG_CATHEDRAL: 37}
const PIC_GRASS := 38           # the grass on top of the ground
const PIC_NONE := 39            # nothing (see-through): an over picture for plain rock

## The ores' extra drill time over the rock round them (a share of that rock's)
const ORE_HARD := 0.25

static func info(t: int) -> Dictionary:
	return INFO.get(t, INFO[AIR])

## Solid: the ship can't go through it (lava and air it can)
static func solid(t: int) -> bool:
	return t != AIR and t != LAVA

## Seconds to drill the tile t set in rock (base) with the first drill (< 0: it can't be drilled)
static func hardness(t: int, base: int) -> float:
	var i := info(t)
	var h := float(i.hard)
	if h < 0.0:
		return -1.0
	if i.over and t != HARD1 and t != HARD2 and t != HARD3:
		return float(info(base).hard) * (1.0 + ORE_HARD) + h
	return h

# ---------------------------------------------------------------- the atlas

## The atlas: albedo (rgb, a = 1 where drawn) and glow (what shines in the dark), both COLS x 6 pictures.
static func build_atlas() -> Array:
	var rows := 6
	var img := Image.create(COLS * PX, rows * PX, false, Image.FORMAT_RGBA8)
	var glow := Image.create(COLS * PX, rows * PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	glow.fill(Color(0, 0, 0, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_rock(img, 1, Color8(122, 84, 52), Color8(92, 62, 38), rng, 0.25, Color8(70, 48, 30))     # topsoil, little stones in it
	_rock(img, 2, Color8(168, 108, 70), Color8(140, 86, 56), rng, 0.08, Color8(120, 74, 48))
	_rock(img, 3, Color8(124, 124, 128), Color8(96, 96, 102), rng, 0.18, Color8(150, 150, 156))
	_rock(img, 4, Color8(140, 58, 44), Color8(108, 40, 32), rng, 0.2, Color8(170, 80, 60))
	_rock(img, 5, Color8(46, 44, 50), Color8(30, 29, 34), rng, 0.22, Color8(70, 68, 78))
	_rock(img, 6, Color8(60, 50, 96), Color8(40, 34, 70), rng, 0.15, Color8(110, 90, 170))
	_crystals(img, glow, 6, rng)
	_rock(img, 7, Color8(22, 22, 26), Color8(12, 12, 14), rng, 0.3, Color8(40, 40, 46))
	_pad(img, 8)
	_boulder(img, 9, Color8(170, 160, 150), Color8(120, 112, 104), rng)
	_boulder(img, 10, Color8(120, 90, 80), Color8(84, 56, 50), rng)
	_boulder(img, 11, Color8(36, 26, 52), Color8(16, 10, 26), rng, Color8(140, 90, 220))
	_ore(img, glow, 12, Color8(24, 24, 26), Color8(70, 70, 76), Color(0, 0, 0), rng, 7)
	_ore(img, glow, 13, Color8(196, 110, 60), Color8(240, 170, 110), Color(0.5, 0.25, 0.1), rng, 6)
	_ore(img, glow, 14, Color8(196, 200, 210), Color8(250, 252, 255), Color(0.55, 0.6, 0.7), rng, 6)
	_ore(img, glow, 15, Color8(230, 180, 40), Color8(255, 236, 120), Color(0.9, 0.7, 0.15), rng, 5)
	_ore(img, glow, 16, Color8(120, 210, 220), Color8(250, 160, 230), Color(0.4, 0.7, 0.8), rng, 4, true)
	_ore(img, glow, 17, Color8(200, 240, 255), Color8(255, 255, 255), Color(0.8, 0.95, 1.0), rng, 4)
	_spores(img, glow, 19, rng)
	_lava(img, glow, 20, rng)
	_gas(img, glow, 21, rng)
	_bricks(img, 22, Color8(120, 70, 50), Color8(70, 60, 54), 1.0)
	_junk(img, 23, rng)
	_concrete(img, 24, rng)
	_locker(img, 25)
	_stash(img, 26)
	_ore(img, glow, 27, Color8(220, 250, 255), Color8(255, 255, 255), Color(1.0, 1.0, 1.0), rng, 9)
	_shroom(img, glow, 28, rng)
	_timber(img, 29)
	# the back walls
	_rock(img, 32, Color8(60, 30, 70), Color8(40, 20, 50), rng, 0.2, Color8(90, 40, 110))
	_bricks(img, 33, Color8(80, 70, 60), Color8(40, 36, 32), 0.8)
	_tiles(img, 34)
	_planks(img, 35)
	_rock(img, 36, Color8(80, 40, 40), Color8(50, 22, 24), rng, 0.3, Color8(110, 60, 60))
	_rock(img, 37, Color8(40, 30, 80), Color8(24, 18, 56), rng, 0.2, Color8(80, 60, 160))
	_grass(img, 38, rng)
	return [img, glow]

static func origin(pic: int) -> Vector2i:
	return Vector2i((pic % COLS) * PX, (pic / COLS) * PX)

## The atlas UV rectangle of a picture (inset half a pixel so the next picture doesn't bleed in)
static func uv(pic: int) -> Rect2:
	var o := origin(pic)
	var w := float(COLS * PX)
	var h := float(6 * PX)
	return Rect2((o.x + 0.02) / w, (o.y + 0.02) / h, (PX - 0.04) / w, (PX - 0.04) / h)

static func _rock(img: Image, pic: int, a: Color, b: Color, rng: RandomNumberGenerator, specks: float, speck: Color) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var n := _vn(x, y, pic) * 0.6 + rng.randf() * 0.4
			var c := a.lerp(b, n)
			if rng.randf() < specks * 0.3:
				c = speck
			img.set_pixel(o.x + x, o.y + y, c)
	# a faint crack
	for k in 1:
		var x := rng.randi_range(2, PX - 3)
		var y := rng.randi_range(2, PX - 3)
		for s in rng.randi_range(3, 5):
			img.set_pixel(o.x + x, o.y + y, b.darkened(0.12))
			x = clampi(x + rng.randi_range(-1, 1), 0, PX - 1)
			y = clampi(y + 1, 0, PX - 1)

## smooth-ish value noise over a picture (so the rock has patches, not just grain)
static func _vn(x: int, y: int, s: int) -> float:
	var fx := x / 5.0
	var fy := y / 5.0
	var ix := floori(fx)
	var iy := floori(fy)
	var tx := fx - ix
	var ty := fy - iy
	var h := func(i: int, j: int) -> float: return float(absi((i * 73856093) ^ (j * 19349663) ^ (s * 83492791)) % 997) / 997.0
	return lerpf(lerpf(h.call(ix, iy), h.call(ix + 1, iy), tx), lerpf(h.call(ix, iy + 1), h.call(ix + 1, iy + 1), tx), ty)

static func _blob(img: Image, o: Vector2i, cx: float, cy: float, r: float, c: Color, hi: Color) -> void:
	for y in PX:
		for x in PX:
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			if d <= r:
				img.set_pixel(o.x + x, o.y + y, hi if (x + 0.5 - cx) < -r * 0.2 and (y + 0.5 - cy) < -r * 0.2 else c)

static func _ore(img: Image, glow: Image, pic: int, c: Color, hi: Color, g: Color, rng: RandomNumberGenerator, n: int, rainbow := false) -> void:
	var o := origin(pic)
	for k in n:
		var cx := rng.randf_range(3.0, PX - 3.0)
		var cy := rng.randf_range(3.0, PX - 3.0)
		var r := rng.randf_range(1.3, 2.4)
		var cc := c
		if rainbow:
			cc = Color.from_hsv(rng.randf(), 0.5, 0.95)
		_blob(img, o, cx, cy, r, cc, hi)
		# outline: a darker rim so it reads on any rock
		for y in PX:
			for x in PX:
				var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
				if d > r and d <= r + 0.8 and img.get_pixel(o.x + x, o.y + y).a < 0.5:
					img.set_pixel(o.x + x, o.y + y, cc.darkened(0.6))
		if g != Color(0, 0, 0):
			glow.set_pixel(o.x + int(cx - r * 0.4), o.y + int(cy - r * 0.4), g)

static func _crystals(img: Image, glow: Image, pic: int, rng: RandomNumberGenerator) -> void:
	var o := origin(pic)
	for k in 2:
		var x := rng.randi_range(2, PX - 3) if k == 0 else rng.randi_range(9, PX - 3)
		var y := rng.randi_range(6, PX - 2)
		var h := rng.randi_range(3, 5)
		var col := Color.from_hsv(rng.randf_range(0.5, 0.85), 0.6, 1.0)
		for j in h:
			for w in [0, 1]:
				if y - j >= 0 and x + w < PX:
					img.set_pixel(o.x + x + w, o.y + y - j, col if w == 0 else col.darkened(0.3))
					glow.set_pixel(o.x + x + w, o.y + y - j, col * (0.5 if w == 0 else 0.25))

static func _pad(img: Image, pic: int) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var c := Color8(150, 150, 146) if (y < 3) else Color8(120, 120, 116)
			if (x + y * 3) % 7 == 0:
				c = c.darkened(0.08)
			if y == 3 or x == 0:
				c = Color8(90, 90, 88)
			img.set_pixel(o.x + x, o.y + y, c)
	for x in PX:
		if (x / 2) % 2 == 0:
			img.set_pixel(o.x + x, o.y + 1, Color8(230, 190, 30))

static func _boulder(img: Image, pic: int, a: Color, b: Color, rng: RandomNumberGenerator, vein := Color(0, 0, 0, 0)) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var d := Vector2((x + 0.5 - 8.0) / 7.2, (y + 0.5 - 8.5) / 6.6).length()
			if d <= 1.0:
				var c := a.lerp(b, clampf(d * 0.7 + (y / 16.0) * 0.4 + rng.randf() * 0.15, 0, 1))
				if d > 0.86:
					c = b.darkened(0.4)
				img.set_pixel(o.x + x, o.y + y, c)
	if vein.a > 0.0:
		for k in 8:
			img.set_pixel(o.x + rng.randi_range(4, 11), o.y + rng.randi_range(4, 12), vein)

static func _spores(img: Image, glow: Image, pic: int, rng: RandomNumberGenerator) -> void:
	var o := origin(pic)
	for k in 9:
		var cx := rng.randf_range(3.0, 13.0)
		var cy := rng.randf_range(4.0, 14.0)
		var col := Color.from_hsv(rng.randf_range(0.75, 0.95), 0.6, 0.9)
		_blob(img, o, cx, cy, rng.randf_range(1.2, 2.2), col, col.lightened(0.4))
		glow.set_pixel(o.x + int(cx), o.y + int(cy), col * 0.6)

static func _lava(img: Image, glow: Image, pic: int, rng: RandomNumberGenerator) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var n := _vn(x, y, 99) * 0.7 + rng.randf() * 0.3
			var c := Color8(255, 90, 10).lerp(Color8(255, 220, 60), n)
			if n < 0.3:
				c = Color8(150, 30, 10)
			img.set_pixel(o.x + x, o.y + y, c)
			glow.set_pixel(o.x + x, o.y + y, c * (0.9 if n >= 0.3 else 0.3))

static func _gas(img: Image, glow: Image, pic: int, rng: RandomNumberGenerator) -> void:
	var o := origin(pic)
	for k in 6:
		var cx := rng.randf_range(3.0, 13.0)
		var cy := rng.randf_range(3.0, 13.0)
		for y in PX:
			for x in PX:
				var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
				if d < 2.2:
					img.set_pixel(o.x + x, o.y + y, Color(0.45, 0.62, 0.2, 0.55 if d > 1.2 else 0.85))
		glow.set_pixel(o.x + int(cx), o.y + int(cy), Color(0.12, 0.25, 0.02))

static func _bricks(img: Image, pic: int, a: Color, mortar: Color, k: float) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var row := y / 4
			var off := 4 if row % 2 == 1 else 0
			var c := a.lerp(a.darkened(0.25), float(((x + off) / 8 + row) % 3) / 3.0)
			if y % 4 == 3 or (x + off) % 8 == 7:
				c = mortar
			img.set_pixel(o.x + x, o.y + y, c.darkened(1.0 - k))

static func _junk(img: Image, pic: int, rng: RandomNumberGenerator) -> void:
	var o := origin(pic)
	# a bike wheel, a can, a bottle
	for a in 24:
		var ang := a / 24.0 * TAU
		img.set_pixel(o.x + int(5 + cos(ang) * 3.5), o.y + int(6 + sin(ang) * 3.5), Color8(40, 40, 44))
	for y in range(9, 14):
		for x in range(9, 12):
			img.set_pixel(o.x + x, o.y + y, Color8(200, 40, 40) if y != 10 else Color8(230, 230, 230))
	for y in range(3, 9):
		img.set_pixel(o.x + 12, o.y + y, Color8(60, 140, 70))
		img.set_pixel(o.x + 13, o.y + y, Color8(80, 170, 90))

static func _concrete(img: Image, pic: int, rng: RandomNumberGenerator) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var c := Color8(140, 142, 146).darkened(rng.randf() * 0.12)
			if y == 0 or x == 0:
				c = Color8(100, 102, 106)
			img.set_pixel(o.x + x, o.y + y, c)
	for y in [5, 11]:
		for x in [5, 11]:
			img.set_pixel(o.x + x, o.y + y, Color8(80, 80, 84))

static func _locker(img: Image, pic: int) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var c := Color8(70, 90, 120)
			if x == 0 or y == 0 or x == PX - 1 or y == PX - 1 or x == 8:
				c = Color8(40, 50, 70)
			if (y == 3 or y == 4) and (x > 1 and x < 7 or x > 9 and x < 15) and x % 2 == 0:
				c = Color8(30, 36, 50)
			if y == 9 and (x == 6 or x == 10):
				c = Color8(220, 220, 220)
			img.set_pixel(o.x + x, o.y + y, c)
	for x in range(3, 13):
		img.set_pixel(o.x + x, o.y + 13, Color8(230, 200, 40))

static func _stash(img: Image, pic: int) -> void:
	var o := origin(pic)
	# taped bricks of stuff in a crate
	for y in range(2, 15):
		for x in range(1, 15):
			var c := Color8(160, 120, 70)
			if y == 2 or y == 14 or x == 1 or x == 14:
				c = Color8(100, 70, 40)
			if y > 3 and y < 13 and x > 2 and x < 13:
				c = Color8(230, 230, 220) if ((x / 3 + y / 3) % 2 == 0) else Color8(200, 200, 190)
				if y % 3 == 0:
					c = Color8(150, 120, 60)
			img.set_pixel(o.x + x, o.y + y, c)

static func _shroom(img: Image, glow: Image, pic: int, rng: RandomNumberGenerator) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var c := Color8(220, 60, 120).lerp(Color8(255, 120, 190), _vn(x, y, 7))
			img.set_pixel(o.x + x, o.y + y, c)
			glow.set_pixel(o.x + x, o.y + y, c * 0.25)
	for k in 5:
		var cx := rng.randf_range(3, 13)
		var cy := rng.randf_range(3, 13)
		_blob(img, o, cx, cy, 1.6, Color8(255, 240, 230), Color.WHITE)

static func _timber(img: Image, pic: int) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var c := Color8(130, 90, 50).lerp(Color8(100, 66, 36), float((x * 3 + y / 4) % 5) / 5.0)
			if x == 0 or x == PX - 1:
				c = Color8(70, 46, 26)
			img.set_pixel(o.x + x, o.y + y, c)

static func _tiles(img: Image, pic: int) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var c := Color8(70, 76, 80) if (x / 8 + y / 8) % 2 == 0 else Color8(60, 64, 70)
			if x % 8 == 0 or y % 8 == 0:
				c = Color8(40, 42, 46)
			img.set_pixel(o.x + x, o.y + y, c)

static func _planks(img: Image, pic: int) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			var c := Color8(80, 56, 34).lerp(Color8(60, 40, 24), float((y * 7 + x / 5) % 4) / 4.0)
			if y % 5 == 4:
				c = Color8(36, 24, 14)
			img.set_pixel(o.x + x, o.y + y, c)

static func _grass(img: Image, pic: int, rng: RandomNumberGenerator) -> void:
	var o := origin(pic)
	for y in PX:
		for x in PX:
			img.set_pixel(o.x + x, o.y + y, Color8(70, 130, 46).lerp(Color8(96, 160, 60), rng.randf()))
