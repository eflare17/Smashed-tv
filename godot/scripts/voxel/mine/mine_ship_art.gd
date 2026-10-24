class_name MineShipArt
extends RefCounted
## The Mole, Juicy Jared's digger, in pixel art (the owner, 24 Oct: "it needs to look like it's Juicy Jared inside the
## little capsule", propeller blades to start, bigger blades, then boosters): a yellow capsule whose nose is its drill,
## tracks along its belly, a glass bubble with Jared in it (his shades, his moustache, his green singlet). Each upgrade
## shows: the drill's bit bigger and steel, bronze, gold, diamond; the hull's plating; the fuel tanks; the cargo pod
## (bulging with ore when it's nearly full); more lamps; the lift (a wooden propeller, big metal blades, twin boosters,
## a mega booster). Drawn as grids of palette letters, outlined in the ground's own dark outline, cut into layers the
## ship stacks (the body, the tracks, the drill, the lift, the flames, the hose) so they can move on their own. All the
## layers share one canvas: W x H pixels, the ship's middle at (CX, CY) (pixel edges), PX metres a pixel. Owned by the
## voxel session.

const W := 78
const H := 52
const OX := 15                  # (the drawing's own origin on the canvas)
const OY := 7
const CX := 23 + OX             # the ship's middle (its 0.8 m square: hull and tracks 36 px across, 36 down)
const CY := 18 + OY
const PX := 0.8 / 36.0
const OUTLINE := Color8(10, 6, 5)

const BASE := {
	"K": Color8(10, 6, 5),
	"w": Color8(240, 252, 255), "G": Color8(120, 200, 240), "g": Color8(58, 118, 178),
	"1": Color8(233, 121, 84), "2": Color8(176, 86, 73), "3": Color8(252, 166, 111),
	"X": Color8(50, 28, 36), "x": Color8(92, 56, 58), "Z": Color8(32, 18, 26),
	"U": Color8(10, 125, 205), "u": Color8(120, 225, 255),
	"N": Color8(64, 176, 72), "n": Color8(30, 112, 46),
	"L": Color8(255, 230, 110), "H": Color8(244, 186, 38), "h": Color8(200, 132, 24), "j": Color8(140, 86, 20),
	"M": Color8(176, 180, 188), "m": Color8(104, 108, 118),
	"T": Color8(46, 46, 52), "t": Color8(88, 88, 96), "W": Color8(168, 172, 180), "V": Color8(110, 112, 122),
	"Y": Color8(255, 250, 210), "y": Color8(255, 204, 96),
	"R": Color8(220, 62, 40), "r": Color8(146, 32, 26), "C": Color8(150, 108, 64), "c": Color8(104, 72, 42),
	"A": Color8(196, 150, 96), "a": Color8(128, 90, 54),
	"O": Color8(255, 160, 40), "o": Color8(255, 92, 24), "F": Color8(255, 244, 160),
	"Q": Color8(120, 200, 255), "q": Color8(230, 245, 255),
	"P": Color8(232, 190, 60), "p": Color8(170, 120, 30),       # gold trim
}
# the guest's Mole in co-op (upg "coat" 1): the hull blue (the host's stays yellow)
const COAT_BLUE := {"L": Color8(170, 225, 255), "H": Color8(48, 136, 232), "h": Color8(28, 92, 182), "j": Color8(16, 54, 118)}
const DRILL_PAL := [
	{"D": Color8(232, 236, 242), "d": Color8(160, 168, 180), "s": Color8(84, 90, 104)},
	{"D": Color8(244, 196, 130), "d": Color8(200, 130, 72), "s": Color8(118, 68, 36)},
	{"D": Color8(255, 242, 160), "d": Color8(240, 198, 60), "s": Color8(156, 106, 20)},
	{"D": Color8(236, 255, 255), "d": Color8(150, 230, 250), "s": Color8(56, 148, 190)},
]
const FLAME := "OoFQq"
# his head and shoulders looking out at you (10 x 12)
const JARED := [
	"..XXXXXX..",
	".XXXXXXXXX",
	"XXXx111XXX",
	"X11111111X",
	"KUUuKKUUuK",
	"1UUUKKUUU1",
	"1111131111",
	"1ZZZZZZZZ1",
	"2ZZZ22ZZZ2",
	".21111112.",
	"11NN11NN11",
	"11NNNNNN11",
]
const ORE_BITS := [Color8(222, 120, 60), Color8(200, 210, 225), Color8(255, 210, 60), Color8(90, 220, 255), Color8(230, 90, 180)]


## A canvas of palette letters ("." empty).
class Grid:
	var c := PackedByteArray()
	var pal := {}
	var dots := {}              # (letter: an exact colour, for the cargo's ore)

	func _init(p: Dictionary) -> void:
		c.resize(W * H)
		c.fill(46)          # "."
		pal = p

	func put(x: int, y: int, ch: String) -> void:
		x += OX
		y += OY
		if x >= 0 and x < W and y >= 0 and y < H and ch != ".":
			c[y * W + x] = ch.unicode_at(0)

	func at(x: int, y: int) -> String:
		x += OX
		y += OY
		if x < 0 or x >= W or y < 0 or y >= H:
			return "."
		return String.chr(c[y * W + x])

	func rows(x0: int, y0: int, rr: Array) -> void:
		for j in rr.size():
			var r: String = rr[j]
			for i in r.length():
				put(x0 + i, y0 + j, r[i])

	## Filled ellipse (centre and radii in drawing pixels); shade(dx, dy) -> a letter; top: only its upper half.
	func ellipse(cx: float, cy: float, rx: float, ry: float, shade: Callable, top := false) -> void:
		for y in range(int(floor(cy - ry)) - 1, int(ceil(cy + ry)) + 1):
			for x in range(int(floor(cx - rx)) - 1, int(ceil(cx + rx)) + 1):
				var dx := (x + 0.5 - cx) / rx
				var dy := (y + 0.5 - cy) / ry
				if dx * dx + dy * dy <= 1.0 and (not top or y + 0.5 <= cy):
					put(x, y, shade.call(dx, dy))

	## The dark outline round everything drawn (not round flames: they glow).
	func outline() -> Grid:
		var add := []
		for y in H:
			for x in W:
				if c[y * W + x] != 46:
					continue
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + o.x
					var ny: int = y + o.y
					if nx < 0 or ny < 0 or nx >= W or ny >= H:
						continue
					var ch := String.chr(c[ny * W + nx])
					if ch != "." and ch != "K" and not FLAME.contains(ch):
						add.append(y * W + x)
						break
		for i in add:
			c[i] = 75       # "K"
		return self

	func image() -> Image:
		var im := Image.create(W, H, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		for y in H:
			for x in W:
				var b := c[y * W + x]
				if b == 46:
					continue
				var ch := String.chr(b)
				var col: Color = dots[ch] if dots.has(ch) else pal.get(ch, Color.MAGENTA)
				im.set_pixel(x, y, col)
		return im


static func _hull(dx: float, dy: float) -> String:
	var v := -dy * 0.8 - dx * 0.25
	return "L" if v > 0.55 else ("H" if v > -0.15 else ("h" if v > -0.6 else "j"))


## A cone pointing right from x0 (half height half0 at its base) to its tip at x1, flutes in chevrons to the tip.
static func _cone(g: Grid, x0: int, x1: int, cy: float, half0: float, spin: int) -> void:
	for x in range(x0, x1 + 1):
		var half := half0 * float(x1 - x) / float(x1 - x0)
		var y0 := int(floor(cy - half))
		var y1 := int(ceil(cy + half)) - 1
		if y1 < y0:
			y0 = int(cy)
			y1 = y0
		for y in range(y0, y1 + 1):
			var ch := "s" if (x + int(absf(y + 0.5 - cy)) + spin) % 3 == 0 else ("D" if y < cy - half * 0.25 else "d")
			g.put(x, y, ch)


static func _tex(g: Grid) -> ImageTexture:
	return ImageTexture.create_from_image(g.image())


## Everything that doesn't move: the capsule, Jared in his bubble, the plating, the tanks, the cargo pod, the lamps.
## upg: {hull, tank, cargo, lights} 0..3; full: the cargo pod's bulging (0..1).
static func body(upg: Dictionary, full: float) -> ImageTexture:
	var hl := int(upg.get("hull", 0))
	var tl := int(upg.get("tank", 0))
	var cl := int(upg.get("cargo", 0))
	var ll := int(upg.get("lights", 0))
	var g := Grid.new(BASE.merged(COAT_BLUE, true) if int(upg.get("coat", 0)) == 1 else BASE)
	# the cargo pod on its back, behind the bubble (bigger each level; ore poking out the top when it's full)
	var pw := 7 + cl * 2
	var ph := 4 + cl
	for y in range(15 - ph, 16):
		for x in range(7, 7 + pw):
			g.put(x, y, "C" if y > 15 - ph else "c")
	for x in range(7, 7 + pw, 3):
		g.put(x, 15 - ph + 1, "c")
	if full > 0.6:
		var n := int((full - 0.5) * 2.0 * pw)
		for i in n:
			var ch: String = ["@", "#", "$", "%", "&"][i % 5]
			g.dots[ch] = ORE_BITS[i % 5]
			g.put(7 + 1 + (i * 3) % maxi(1, pw - 2), 15 - ph - 1 - (i % 2), ch)
	# the fuel: a red jerry can on its back (the tanks down its side come after the capsule)
	if tl == 0:
		g.rows(3, 12, ["rRR", "RRR", "RRr", "rrr"])
	elif tl >= 3:
		g.rows(1, 10, ["rRRRRr", "RRRRRR", "rrrrrr"])
	# the bubble with Jared in it
	g.ellipse(22.0, 17.0, 8.0, 12.4, func(dx: float, dy: float) -> String: return "G" if dy < -0.35 else "g", true)
	g.rows(17, 6, JARED.slice(0, 11))
	for q in [Vector2i(16, 9), Vector2i(16, 10), Vector2i(17, 7), Vector2i(17, 8)]:
		g.put(q.x, q.y, "w")
	# the capsule
	for y in range(16, 30):
		var inset: int = {16: 3, 17: 1, 28: 1, 29: 3}.get(y, 0)
		for x in range(5 + inset, 40):
			g.put(x, y, _hull((x - 22) / 17.0, (y - 22.5) / 7.0))
	# its panel lines, a hazard stripe behind the drill, Jared's green badge
	for y in range(18, 26):
		g.put(12, y, "K")
		g.put(37, y, "K" if y % 2 else "y")
	g.rows(7, 19, ["NNNN", "NKKN", "NNNN"])
	# fuel tanks down its side: one, then a longer one
	if tl >= 1:
		var tlen := 14 if tl == 1 else 22
		for x in range(14, 14 + tlen):
			g.put(x, 27, "R" if x % 6 else "r")
			g.put(x, 28, "r")
		g.put(14 + tlen, 27, "m")
		g.put(14 + tlen, 28, "m")
	# the plating: a riveted band (Plated), armour plates (Armoured), gold trim (the Tank)
	if hl >= 1:
		for x in range(7, 39):
			g.put(x, 26, "j" if x % 4 else "K")
	if hl >= 2:
		for k in 3:
			var x0 := 14 + k * 7
			for y in range(21, 26):
				for x in range(x0, x0 + 5):
					g.put(x, y, "j" if (y == 21 or x == x0) else "h")
			g.put(x0 + 1, 22, "K")
			g.put(x0 + 3, 22, "K")
	if hl >= 3:
		for x in range(8, 39):
			g.put(x, 17, "P" if x % 6 else "p")
		g.rows(7, 19, ["PPPP", "PKKP", "PPPP"])
	# the lamps on its nose, more each level
	for k in ll + 1:
		var lp: Vector2i = [Vector2i(33, 18), Vector2i(33, 21), Vector2i(29, 18), Vector2i(29, 21)][k]
		g.rows(lp.x, lp.y, ["YY", "Yy"])
	# the drill's collar
	for y in range(16, 30):
		g.put(40, y, "M" if y < 23 else "m")
		g.put(41, y, "m")
	return _tex(g.outline())


## The tracks (frame 0 / 1: the treads a link along, for rolling).
static func tracks(frame: int) -> ImageTexture:
	var g := Grid.new(BASE)
	for x in range(6, 40):
		var on := (x + frame) % 2 == 0
		g.put(x, 30, "T" if on else "t")
		g.put(x, 35, "t" if on else "T")
	for k in 5:
		var cx := 9 + k * 7
		g.rows(cx - 2, 31, [".WWW.", "WWVWW", "WVVVW", ".WWW."] if (frame % 2 == 0) else [".WVW.", "WWWWW", "VWWWV", ".WVW."])
	for y in range(31, 35):
		g.put(5, y, "T")
		g.put(40, y, "T")
	return _tex(g.outline())


## The drill: tier 0..3 (steel, bronze, gold, diamond: bigger each), spin 0..2 its flutes a third of a turn on.
static func drill(tier: int, spin: int) -> ImageTexture:
	var p := BASE.duplicate()
	p.merge(DRILL_PAL[clampi(tier, 0, 3)], true)
	var g := Grid.new(p)
	_cone(g, 42, 54 + tier, 22.5, 6.6 + 0.4 * tier, spin)
	return _tex(g.outline())


## The lift: 0 a wooden propeller, 1 big metal blades (frame 0/1: the blades blurred one way, the other), 2 twin
## boosters, 3 a mega booster.
static func lift(level: int, frame: int) -> ImageTexture:
	var g := Grid.new(BASE)
	if level <= 1:
		var x := 22
		var y := 4
		for k in 4:
			g.put(x, y - 1 - k, "m")
		g.rows(x - 1, y - 6, ["MMM"])
		var span := 9 if level == 0 else 15
		var blade := "A" if level == 0 else "M"
		var dark := "a" if level == 0 else "m"
		for i in range(1, span + 1):
			var tip := i >= span - 2
			# (the blur: the tips come and go with the frame)
			if tip and (i + frame) % 2 == 0:
				continue
			g.put(x - i, y - 6, dark if tip else blade)
			g.put(x + i, y - 6, dark if tip else blade)
			if level == 1 and i < span - 4:
				g.put(x - i, y - 7, dark)
				g.put(x + i, y - 7, dark)
	elif level == 2:
		for k in 2:
			g.rows(2, 18 + k * 4, ["MMMMm", "mmmmm", "MMMMm"])
	else:
		g.rows(-1, 17, ["..MMMMMm", ".MMMMMMm", "MmmmmmMm", "mmmmmmmm", "MmmmmmMm", ".MMMMMMm", "..MMMMMm"])
	return _tex(g.outline())


## The lift's flames (frame 0/1 flickering): the boosters' out the back, the propeller's none.
static func flames(level: int, frame: int) -> ImageTexture:
	var g := Grid.new(BASE)
	if level == 2:
		for k in 2:
			var rr := ["FOo", "FOOo", "FOo"] if frame == 0 else ["FO", "FOOoo", "FOo"]
			for j in rr.size():
				var r: String = rr[j]
				for i in r.length():
					g.put(1 - i, 18 + k * 4 + j, r[i])
	elif level == 3:
		var fl := ["..qqQQOo", ".qqqQQOOoo", "qqqqQQQOOoo", "qqqqQQQOOooo", "qqqqQQQOOoo", ".qqqQQOOoo", "..qqQQOo"]
		for j in fl.size():
			var r: String = fl[j]
			for i in r.length():
				if frame == 1 and i == r.length() - 1:
					continue
				g.put(-2 - i, 17 + j, r[i])
	return _tex(g)


## The hose out of its back for unloading at the box and sucking water up: out (0..1) how far it's run out.
static func hose(out: float) -> ImageTexture:
	var g := Grid.new(BASE)
	var n := int(round(out * 7.0))
	for i in n:
		g.put(4 - i, 22, "M")
		g.put(4 - i, 23, "m")
	if n >= 7:
		g.rows(-6, 22, ["MMM", "mMMm", ".mMMm", "..mMM"])
	return _tex(g.outline())


## Where the hose's nozzle is, in metres from the ship's middle (facing right, level).
static func nozzle() -> Vector2:
	return Vector2((-4 - CX + OX) * PX, -(26 - CY + OY) * PX)
