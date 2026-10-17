class_name SandMinerGame
extends ArcadeGame
## SAND MINER (Smashed.html, makeSandMiner / ARCADE_GAMES.miner: the owner's game, in the cabinet that was Spud
## Snake). A 384 x 256 world of falling sand: dig with the shovel and ore pops out as nuggets to collect; launch
## dirt, sticky clay or sand; upgrade the launcher with ore. The score is the ore collected, by what it's worth
## (coal 1, iron 2, sulphur 3, silver 4, gold 5, platinum 7, ruby and emerald 10). It ticks at 60 a second like
## the HTML game, and is drawn into its own 959 x 637 canvas (137 x 91 cells of 7 pixels) blown down onto the
## cabinet's screen.
##
## Ported as it is, with two changes for speed (GDScript is slower than the browser's JavaScript): the sand and
## water only move in the parts of the world where something moved last tick (16 x 16 cell chunks, woken by any
## change near them), and the world's picture is kept and repainted only where it changed, instead of every
## cell every frame.
##
## Controls: A / D walk, W or Space jump (swim up in water); the mouse aims: left digs, right (or F) launches;
## Q picks what to launch, U upgrades. Pad: left stick walks, A jumps, right stick aims, RT digs, LT / RB
## launches, X ammo, Y upgrade. Touch: on-screen walk, jump, launch, ammo and upgrade buttons; your finger on
## the screen is the shovel (and where LAUNCH throws to).

const ORE_VALUE := {7: 1, 8: 2, 9: 3, 10: 4, 4: 5, 11: 7, 12: 10, 13: 10}
const W := 384
const H := 256
const VW := 137
const VH := 91
const S := 7
const CW := VW * S          # 959: the game's own canvas
const CHT := VH * S         # 637
const EMPTY := 0
const DIRT := 1
const SAND := 2
const WATER := 3
const GOLD := 4
const ROCK := 5
const GRASS := 6
const COAL := 7
const IRON := 8
const SULPHUR := 9
const SILVER := 10
const PLATINUM := 11
const RUBY := 12
const EMERALD := 13
const CLAY := 14
const ORE_IDS := [COAL, IRON, SULPHUR, SILVER, GOLD, PLATINUM, RUBY, EMERALD]
const ORE_NAMES := ["Coal", "Iron", "Sulphur", "Silver", "Gold", "Platinum", "Ruby", "Emerald"]
const CELLS_PER_NUG := {COAL: 6, IRON: 6, SULPHUR: 6, SILVER: 7, GOLD: 7, PLATINUM: 8, RUBY: 4, EMERALD: 4}
const PW := 5
const PH := 11
const REACH := 9.0
const DIG_R := 6
const DIG_LEN := 32
const DIG_HIT := 14
const LAUNCH_SPEED := [0.0, 1.3, 1.75, 2.25, 2.8, 3.4]
const LAUNCH_COST := [null, null, [COAL, 5], [IRON, 8], [SILVER, 6], [GOLD, 6]]
const AMMO := [DIRT, CLAY, SAND]
const AMMO_NAME := {DIRT: "Dirt", CLAY: "Clay (sticky)", SAND: "Sand"}
const CLAY_BAND := 1
const CH := 16              # sand chunks
const CCX := W / CH
const CCY := H / CH
const OC := 26
const HUD_Y := 44.0

const BASE := {DIRT: [112, 74, 46], SAND: [224, 198, 122], WATER: [50, 118, 222], GOLD: [255, 206, 40], ROCK: [98, 100, 108], GRASS: [84, 150, 60]}
const SOIL := [[112, 74, 46], [150, 92, 56], [98, 76, 64], [76, 72, 80]]
const ORE_PAL := {"coal": [[37, 36, 42], [39, 39, 45], [41, 41, 47], [43, 42, 50], [53, 46, 54], [53, 57, 72], [66, 69, 91], [79, 87, 117]], "iron": [[67, 47, 47], [94, 58, 52], [141, 56, 18], [146, 67, 40], [176, 69, 27], [201, 77, 25], [181, 108, 74], [202, 140, 94]], "sulphur": [[92, 99, 12], [99, 177, 41], [172, 179, 36], [154, 219, 25], [187, 228, 13], [213, 236, 4], [226, 237, 59], [238, 249, 69]], "silver": [[81, 96, 117], [98, 117, 141], [119, 141, 164], [137, 163, 186], [148, 189, 213], [171, 214, 228], [197, 227, 237], [220, 245, 248]], "gold": [[93, 48, 20], [172, 84, 9], [207, 94, 6], [227, 112, 5], [245, 133, 3], [251, 154, 1], [251, 191, 23], [254, 223, 42]], "platinum": [[73, 91, 99], [97, 135, 170], [131, 168, 192], [169, 198, 222], [170, 227, 246], [194, 237, 249], [211, 249, 252], [246, 254, 254]], "ruby": [[114, 3, 34], [48, 44, 44], [115, 23, 48], [71, 57, 59], [185, 10, 51], [84, 69, 68], [180, 40, 81], [250, 46, 108]], "emerald": [[120, 3, 42], [148, 4, 47], [45, 72, 50], [54, 86, 51], [13, 123, 71], [43, 140, 71], [61, 193, 88], [135, 234, 157]]}
const PLX := [
	{"f": 0.10, "base": 26.0, "a": [10.0, 5.0, 2.0], "k": [0.018, 0.061, 0.19], "col": "#a8c9e2", "top": "#c3dcef"},
	{"f": 0.28, "base": 12.0, "a": [6.0, 3.0, 1.0], "k": [0.033, 0.097, 0.23], "col": "#86b98a", "top": "#9fcb9e"},
	{"f": 0.52, "base": 4.0, "a": [4.0, 2.0, 1.0], "k": [0.051, 0.13, 0.31], "col": "#649d63", "top": "#7db27a"},
]
const SPR_FW := 33
const SPR_FH := 57
const SPR_BASE := 56
const SPR_AX := 16
const SPR_SCALE := 2

# ---- tables (built once)
static var _tables_built := false
static var SOLID := PackedByteArray()
static var DIGGABLE := PackedByteArray()
static var TWINKLE := PackedByteArray()
static var ORE_ROW := PackedInt32Array()
static var pal: Array = []         # material -> PackedInt32Array(8) of packed RGBA (r in the low byte)
static var pal_ao: Array = []
static var pal_rim: Array = []
static var soil_pal: Array = []
static var soil_ao: Array = []
static var back_pal: Array = []
static var css: Array = []         # material -> Color
static var soil_css: Array = []
static var WATER_TOP := 0
static var SAND_TOP := PackedInt32Array()
static var WHITE := 0
static var OUTLINE := 0
static var sheet: Texture2D
static var ore_sheet: Texture2D
static var soil_icon: Dictionary = {}
static var sky_tex: Texture2D

# ---- world
var grid := PackedByteArray()
var stamp := PackedInt32Array()
var hv := PackedByteArray()
var surf := PackedInt32Array()
var layer := PackedByteArray()
var frame := 1
var act := PackedByteArray()        # chunks to run this tick
var act_next := PackedByteArray()   # chunks woken for the next
var rng := RandomNumberGenerator.new()

# ---- the picture of the world (repainted where it changed)
var pix := PackedByteArray()
var img: Image
var tex: ImageTexture
var shaded := PackedByteArray()     # chunks painted at least once
var dirty: PackedInt32Array = PackedInt32Array()
var shade_mark := PackedInt32Array()
var shade_gen := 0
var _pix_changed := true
var _water_frame := -1

# ---- state
var pl := {"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "ground": false, "face": 1}
var walk_t := 0.0
var dig_t := 0
var cam_xf := 0.0
var cam_yf := 0.0
var cam_x := 0
var cam_y := 0
var mouse := {"sx": 0.0, "sy": 0.0, "down": false, "launch": false, "inside": false}
var debris: Array = []
var shots: Array = []
var launch_lvl := 1
var launch_t := 0
var launching := false
var ammo := DIRT
var toast = null
var horizon_y := 60.0
var ref_cam_y := 0.0
var clouds: Array = []
var nuggets: Array = []
var popups: Array = []
var inv := PackedInt32Array()
var ore_carry := PackedFloat32Array()
var _acc := 0.0
var _keys: Dictionary = {}
var _aim_world = null              # the last place aimed at (world cells), for the pad and the touch LAUNCH button

func title() -> String:
	return "SAND MINER"

func hint(device: String) -> String:
	match device:
		"pad": return "stick walk · A jump · right stick aim · RT dig · LT launch · X ammo · Y upgrade"
		"touch": return "buttons walk and jump · your finger digs · LAUNCH throws there"
	return "A/D walk · W jump · mouse: left digs, right or F launches · Q ammo · U upgrade"

func touch_buttons() -> Array:
	return [["left", "◀", "left", 0, 0], ["right", "▶", "left", 0, 1],
		["jump_btn", "JUMP", "right", 0, 0], ["launch", "LAUNCH", "right", 0, 1],
		["q", "AMMO", "right", 1, 0], ["u", "UPGRADE", "right", 1, 1]]

func _init(seed: int = -1) -> void:
	_build_tables()
	if seed < 0:
		rng.randomize()
	else:
		rng.seed = seed
	grid.resize(W * H)
	stamp.resize(W * H)
	hv.resize(W * H)
	surf.resize(W)
	layer.resize(W * H)
	act.resize(CCX * CCY)
	act_next.resize(CCX * CCY)
	shaded.resize(CCX * CCY)
	shade_mark.resize(W * H)
	pix.resize(W * H * 4)
	inv.resize(16)
	ore_carry.resize(16)
	generate()
	img = Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, pix)
	tex = ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- tables

static func _pack(r: float, g: float, b: float) -> int:
	var v := (255 << 24) | (int(minf(255, b)) << 16) | (int(minf(255, g)) << 8) | int(minf(255, r))
	return v - 4294967296 if v >= 2147483648 else v

static func _shade(c: int, f: float) -> int:
	var u := c & 0xFFFFFFFF
	return _pack((u & 255) * f, ((u >> 8) & 255) * f, ((u >> 16) & 255) * f)

static func _col(c: int) -> Color:
	var u := c & 0xFFFFFFFF
	return Color8(u & 255, (u >> 8) & 255, (u >> 16) & 255)

static func _build_tables() -> void:
	if _tables_built:
		return
	_tables_built = true
	SOLID.resize(16)
	DIGGABLE.resize(16)
	TWINKLE.resize(16)
	ORE_ROW.resize(16)
	ORE_ROW.fill(-1)
	for i in ORE_IDS.size():
		ORE_ROW[ORE_IDS[i]] = i
	for m in [DIRT, SAND, CLAY, ROCK] + ORE_IDS:
		SOLID[m] = 1
	for m in [DIRT, SAND, CLAY] + ORE_IDS:
		DIGGABLE[m] = 1
	for m in [SILVER, GOLD, PLATINUM, RUBY, EMERALD]:
		TWINKLE[m] = 1
	pal.resize(16)
	pal_ao.resize(16)
	pal_rim.resize(16)
	css.resize(16)
	for m in BASE:
		var c: Array = BASE[m]
		var start := 0.8 if m == GOLD else 0.85
		var stp := 0.07 if m == GOLD else 0.04
		var p := PackedInt32Array()
		p.resize(8)
		for v in 8:
			var f := start + v * stp
			p[v] = _pack(c[0] * f, c[1] * f, c[2] * f)
		pal[m] = p
		css[m] = Color8(c[0], c[1], c[2])
	WHITE = _pack(255, 255, 250)
	OUTLINE = _pack(10, 6, 5)
	for L in SOIL.size():
		var a := PackedInt32Array()
		var b := PackedInt32Array()
		var k := PackedInt32Array()
		a.resize(8); b.resize(8); k.resize(8)
		for v in 8:
			var f := 0.85 + v * 0.04
			var c: Array = SOIL[L]
			var col := _pack(c[0] * f, c[1] * f, c[2] * f)
			a[v] = col
			b[v] = _shade(col, 0.78)
			k[v] = _shade(col, 0.44 + (v & 3) * 0.02)
		soil_pal.append(a)
		soil_ao.append(b)
		back_pal.append(k)
		soil_css.append(Color8(SOIL[L][0], SOIL[L][1], SOIL[L][2]))
	var names := ["coal", "iron", "sulphur", "silver", "gold", "platinum", "ruby", "emerald"]
	for i in names.size():
		var id: int = ORE_IDS[i]
		var cols: Array = ORE_PAL[names[i]]
		var p := PackedInt32Array()
		p.resize(8)
		for v in 8:
			p[v] = _pack(cols[v][0], cols[v][1], cols[v][2])
		pal[id] = p
		css[id] = Color8(cols[4][0], cols[4][1], cols[4][2])
	pal[CLAY] = soil_pal[CLAY_BAND]
	css[CLAY] = soil_css[CLAY_BAND]
	for m in 16:
		if pal[m] == null:
			continue
		var ao := PackedInt32Array()
		var rim := PackedInt32Array()
		for c in pal[m]:
			ao.append(_shade(c, 0.78))
			rim.append(_shade(c, 0.55))
		pal_ao[m] = ao
		pal_rim[m] = rim
	WATER_TOP = _pack(150, 200, 250)
	for c in pal[SAND]:
		SAND_TOP.append(_shade(c, 1.12))
	var man: Dictionary = GameData.manifest if GameData else {}
	if man.has("MINER_SHEET.src"):
		sheet = GameData.tex(String(man["MINER_SHEET.src"]))
	if man.has("MINER_ORES.src"):
		ore_sheet = GameData.tex(String(man["MINER_ORES.src"]))
	soil_icon[DIRT] = _make_clod(SOIL[0], 7)
	soil_icon[CLAY] = _make_clod([204, 112, 62], 3)
	soil_icon[SAND] = _make_clod([224, 198, 122], 11)
	var g := Gradient.new()
	g.set_color(0, Color("#79c4f5"))
	g.set_color(1, Color("#cfe9fb"))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	sky_tex = gt

static func _make_clod(base: Array, seed: int) -> Texture2D:
	var im := Image.create(OC, OC, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var N := 11
	var P := 2
	var o := (OC - N * P) / 2
	var inside := func(x: int, y: int) -> bool:
		var dx := x - 5.0
		var dy := (y - 5.6) * 1.15
		return dx * dx + dy * dy <= 22.0
	for y in N:
		for x in N:
			if not inside.call(x, y):
				continue
			var edge: bool = not inside.call(x - 1, y) or not inside.call(x + 1, y) or not inside.call(x, y - 1) or not inside.call(x, y + 1)
			var f := 0.9 + r.randf() * 0.15
			if x + y < 8: f += 0.12
			if x + y > 13: f -= 0.18
			if r.randf() < 0.12: f -= 0.25
			var c := Color("#0a0605") if edge else Color8(int(minf(255, base[0] * f)), int(minf(255, base[1] * f)), int(minf(255, base[2] * f)))
			im.fill_rect(Rect2i(o + x * P, o + y * P, P, P), c)
	return ImageTexture.create_from_image(im)

# ---------------------------------------------------------------- world generation

func _rf() -> float:
	return rng.randf()

func _ellipse(cx: float, cy: float, rx: float, ry: float, fn: Callable) -> void:
	for y in range(int(floor(cy - ry - 1)), int(cy + ry + 1) + 1):
		if y < 0 or y >= H - 1:
			continue
		for x in range(int(floor(cx - rx - 1)), int(cx + rx + 1) + 1):
			if x < 0 or x >= W:
				continue
			var nx := (x - cx) / rx
			var ny := (y - cy) / ry
			if nx * nx + ny * ny <= 0.85 + _rf() * 0.3:
				fn.call(y * W + x, x, y)

func generate() -> void:
	grid.fill(0)
	stamp.fill(0)
	debris.clear()
	for i in hv.size():
		hv[i] = rng.randi() % 8
	var p1 := _rf() * 6.28
	var p2 := _rf() * 6.28
	var p3 := _rf() * 6.28
	for x in W:
		surf[x] = int(floor(60 + sin(x * 0.025 + p1) * 10 + sin(x * 0.011 + p2) * 14 + sin(x * 0.09 + p3) * 2.5))
		for y in range(surf[x], H):
			grid[y * W + x] = DIRT
		var depth := 6 + int(floor(sin(x * 0.2) * 1.5 + 1.5 + _rf() * 3))
		for y in range(H - depth, H):
			grid[y * W + x] = ROCK
	var q1 := _rf() * 6.28
	var q2 := _rf() * 6.28
	var q3 := _rf() * 6.28
	for x in W:
		var b1 := 16 + sin(x * 0.07 + q1) * 3 + sin(x * 0.023 + q2) * 4
		var b2 := 58 + sin(x * 0.05 + q2) * 5 + sin(x * 0.017 + q3) * 6
		var b3 := 112 + sin(x * 0.04 + q3) * 6 + sin(x * 0.013 + q1) * 8
		for y in range(surf[x], H):
			var d := y - surf[x] + (_rf() - 0.5) * 5
			layer[y * W + x] = 0 if d < b1 else (1 if d < b2 else (2 if d < b3 else 3))
		for y in surf[x]:
			layer[y * W + x] = 0
	for n in 30:
		var cx := int(10 + _rf() * (W - 20))
		var cy := int(surf[cx] + 25 + _rf() * (H - surf[cx] - 45))
		_ellipse(cx, cy, 2 + _rf() * 4, 2 + _rf() * 3, func(i, _x, _y): if grid[i] == DIRT: grid[i] = ROCK)
	for n in 16:
		var cx := int(24 + _rf() * (W - 48))
		var cy := int(surf[cx] + 22 + _rf() * (H - surf[cx] - 52))
		var rx := 8 + _rf() * 10
		var ry := 5 + _rf() * 5
		var carved: Array[int] = []
		_ellipse(cx, cy, rx, ry, func(i, _x, _y):
			if grid[i] == DIRT or grid[i] == ROCK:
				grid[i] = 0
				carved.append(i))
		var kind := _rf()
		for i in carved:
			var y := i / W
			if kind < 0.55:
				if y > cy + ry * 0.1: grid[i] = WATER
			elif kind < 0.8:
				if y > cy + ry * 0.4: grid[i] = SAND
	var ore_gen := [[COAL, 28, 0.02, 0.55, 2.5, 5.0, 0.9], [IRON, 22, 0.08, 0.70, 2.0, 4.0, 0.85], [SULPHUR, 10, 0.30, 0.90, 2.0, 3.5, 0.85], [SILVER, 16, 0.25, 0.85, 2.0, 3.5, 0.8],
		[GOLD, 16, 0.35, 0.95, 2.0, 3.0, 0.8], [PLATINUM, 8, 0.60, 1.00, 1.5, 2.5, 0.8], [RUBY, 6, 0.65, 1.00, 1.2, 2.0, 0.9], [EMERALD, 6, 0.65, 1.00, 1.2, 2.0, 0.9]]
	for og in ore_gen:
		var id: int = og[0]
		for n in og[1]:
			var cx := int(10 + _rf() * (W - 20))
			var top := surf[cx] + 6
			var bot := H - 14
			var cy := int(top + (og[2] + _rf() * (og[3] - og[2])) * (bot - top))
			var rx: float = og[4] + _rf() * (og[5] - og[4])
			var ry := rx * (0.6 + _rf() * 0.5)
			var fill: float = og[6]
			_ellipse(cx, cy, rx, ry, func(i, _x, _y): if grid[i] == DIRT and _rf() < fill: grid[i] = id)
	var gx := W / 2 + 10
	_ellipse(gx, surf[gx] + 11, 4, 3, func(i, _x, _y): if grid[i] == DIRT: grid[i] = GOLD)
	var cx2 := W / 2 + 28
	_ellipse(cx2, surf[cx2] + 8, 5, 3, func(i, _x, _y): if grid[i] == DIRT: grid[i] = COAL)
	var cx3 := W / 2 - 4
	_ellipse(cx3, surf[cx3] + 22, 4, 3, func(i, _x, _y): if grid[i] == DIRT: grid[i] = IRON)
	var px := W / 2 - 16
	var pcy := surf[px] + 16
	var pond: Array[int] = []
	_ellipse(px, pcy, 9, 5, func(i, _x, _y):
		if grid[i] == DIRT:
			grid[i] = 0
			pond.append(i))
	for i in pond:
		if i / W > pcy:
			grid[i] = WATER
	pl.x = W / 2.0 - PW / 2.0
	pl.y = float(surf[W / 2] - PH - 3)
	pl.vx = 0.0
	pl.vy = 0.0
	pl.face = 1
	dig_t = 0
	inv.fill(0)
	ore_carry.fill(0)
	nuggets.clear()
	popups.clear()
	shots.clear()
	launch_lvl = 1
	toast = null
	ammo = DIRT
	cam_xf = clampf(pl.x + PW / 2.0 - VW / 2.0, 0, W - VW)
	cam_yf = clampf(pl.y + PH / 2.0 - VH / 2.0, 0, H - VH)
	cam_x = roundi(cam_xf)
	cam_y = roundi(cam_yf)
	var sum := 0.0
	for x in W:
		sum += surf[x]
	horizon_y = sum / W
	ref_cam_y = cam_yf
	clouds.clear()
	for n in 7:
		var blobs: Array = []
		var w := 6 + int(_rf() * 8)
		for k in 4:
			blobs.append([int(_rf() * w), -int(_rf() * 3), 3 + int(_rf() * 5), 2 + int(_rf() * 2)])
		clouds.append({"x": _rf() * W * 1.2, "y": horizon_y - 44 + _rf() * 22, "blobs": blobs, "spd": 0.004 + _rf() * 0.006})
	act.fill(1)
	act_next.fill(1)
	shaded.fill(0)
	dirty.clear()

# ---------------------------------------------------------------- changes: wake the sand, repaint the picture

func _wake(i: int) -> void:
	var x := i % W
	var y := i / W
	var cx := x / CH
	var cy := y / CH
	act_next[cy * CCX + cx] = 1
	var lx := x % CH
	var ly := y % CH
	if lx == 0 and cx > 0: act_next[cy * CCX + cx - 1] = 1
	elif lx == CH - 1 and cx < CCX - 1: act_next[cy * CCX + cx + 1] = 1
	if ly == 0 and cy > 0: act_next[(cy - 1) * CCX + cx] = 1
	elif ly == CH - 1 and cy < CCY - 1: act_next[(cy + 1) * CCX + cx] = 1

## Change a cell (digging, a shot landing): wakes the sand round it and marks the picture.
func set_cell(i: int, m: int) -> void:
	grid[i] = m
	_wake(i)
	dirty.append(i)

func _mv(a: int, b: int) -> void:
	var t := grid[a]
	grid[a] = grid[b]
	grid[b] = t
	stamp[a] = frame
	stamp[b] = frame
	_wake(a)
	_wake(b)
	dirty.append(a)
	dirty.append(b)

# ---------------------------------------------------------------- sand simulation

func sim_step() -> void:
	frame = (frame + 1) & 0xFFFF
	if frame == 0:
		frame = 1
	var ltr := (frame & 1) == 0
	var tmp := act
	act = act_next
	act_next = tmp
	act_next.fill(0)
	for ccy in range(CCY - 1, -1, -1):
		var any := false
		for ccx in CCX:
			if act[ccy * CCX + ccx]:
				any = true
				break
		if not any:
			continue
		var y_top := ccy * CH
		var y_bot := mini(H - 2, y_top + CH - 1)
		for y in range(y_bot, y_top - 1, -1):
			var row := y * W
			for k in CCX:
				var ccx := k if ltr else CCX - 1 - k
				if not act[ccy * CCX + ccx]:
					continue
				var x0 := ccx * CH
				for j in CH:
					var x := x0 + j if ltr else x0 + CH - 1 - j
					var idx := row + x
					var m := grid[idx]
					if (m != SAND and m != WATER) or stamp[idx] == frame:
						continue
					var below := idx + W
					var b := grid[below]
					var d := -1 if rng.randf() < 0.5 else 1
					if m == WATER:
						if b == 0:
							_mv(idx, below); continue
						if x + d >= 0 and x + d < W and grid[below + d] == 0:
							_mv(idx, below + d); continue
						if x - d >= 0 and x - d < W and grid[below - d] == 0:
							_mv(idx, below - d); continue
						var tx := -1
						for s in 2:
							if tx >= 0:
								break
							var dir := -d if s else d
							var nx := x
							for kk in range(1, 6):
								var t := x + dir * kk
								if t < 0 or t >= W or grid[row + t] != 0:
									break
								nx = t
							if nx != x:
								tx = nx
						if tx >= 0:
							_mv(idx, row + tx)
					else:
						if b == 0 or (b == WATER and (m == GOLD or rng.randf() < 0.6)):
							_mv(idx, below); continue
						if x + d >= 0 and x + d < W:
							var c := grid[below + d]
							if c == 0 or (c == WATER and m == GOLD):
								_mv(idx, below + d); continue
						if x - d >= 0 and x - d < W:
							var c2 := grid[below - d]
							if c2 == 0 or (c2 == WATER and m == GOLD):
								_mv(idx, below - d); continue

## How many chunks are awake (tests: it settles).
func awake_chunks() -> int:
	var n := 0
	for v in act_next:
		n += v
	return n

# ---------------------------------------------------------------- player

func solid_at(x: int, y: int) -> bool:
	if x < 0 or x >= W or y >= H:
		return true
	if y < 0:
		return false
	return SOLID[grid[y * W + x]] == 1

func solid_rect(rx: int, ry: int) -> bool:
	for y in range(ry, ry + PH):
		for x in range(rx, rx + PW):
			if solid_at(x, y):
				return true
	return false

func _move_x(dx: float) -> void:
	var rem := dx
	while absf(rem) > 1e-6:
		var s := signf(rem) * minf(1.0, absf(rem))
		rem -= s
		var nx: float = pl.x + s
		if not solid_rect(int(floor(nx)), int(floor(pl.y))):
			pl.x = nx
			continue
		var ok := false
		for up in range(1, 4):
			if not solid_rect(int(floor(nx)), int(floor(pl.y)) - up):
				pl.x = nx
				pl.y -= up
				ok = true
				break
		if not ok:
			pl.vx = 0.0
			break

func _move_y(dy: float) -> void:
	var rem := dy
	while absf(rem) > 1e-6:
		var s := signf(rem) * minf(1.0, absf(rem))
		rem -= s
		var ny: float = pl.y + s
		if not solid_rect(int(floor(pl.x)), int(floor(ny))):
			pl.y = ny
			continue
		pl.vy = 0.0
		break

func _step_player() -> void:
	var fx := int(floor(pl.x))
	var fy := int(floor(pl.y))
	var wet := 0
	for y in range(fy, fy + PH):
		if y < 0 or y >= H:
			continue
		for x in range(fx, fx + PW):
			if x >= 0 and x < W and grid[y * W + x] == WATER:
				wet += 1
	var in_w := wet / float(PW * PH)
	var left := _keys.has("a")
	var right := _keys.has("d")
	var up := _keys.has("w")
	var ax := (1 if right else 0) - (1 if left else 0)
	pl.vx = ax * 0.7 * (1 - 0.45 * in_w)
	if ax:
		pl.face = ax
		walk_t += 0.28 * (0.6 if in_w > 0.3 else 1.0)
	pl.vy += 0.13 - 0.09 * in_w
	if in_w > 0.2:
		pl.vy *= 0.93
	if up:
		if in_w > 0.3:
			pl.vy = maxf(pl.vy - 0.22, -1.0)
		elif pl.ground:
			pl.vy = -1.6
	pl.vy = minf(pl.vy, 3.0)
	_move_x(pl.vx)
	_move_y(pl.vy)
	pl.ground = solid_rect(int(floor(pl.x)), int(floor(pl.y)) + 1)
	if solid_rect(int(floor(pl.x)), int(floor(pl.y))):
		for k in range(1, 9):
			if not solid_rect(int(floor(pl.x)), int(floor(pl.y)) - k):
				pl.y -= k
				break

# ---------------------------------------------------------------- digging

func mouse_world() -> Vector2:
	return Vector2(mouse.sx / S + cam_x, mouse.sy / S + cam_y)

func dig_target() -> Vector2:
	var m := mouse_world()
	var c := Vector2(pl.x + PW / 2.0, pl.y + PH / 2.0)
	var d := m - c
	if d.length() > REACH:
		d *= REACH / d.length()
	return c + d

func do_dig() -> void:
	var t := dig_target()
	var cx := roundi(t.x)
	var cy := roundi(t.y)
	var got := PackedInt32Array()
	got.resize(16)
	var sx := PackedFloat32Array()
	sx.resize(16)
	var sy := PackedFloat32Array()
	sy.resize(16)
	for dy in range(-DIG_R, DIG_R + 1):
		for dx in range(-DIG_R, DIG_R + 1):
			if dx * dx + dy * dy > DIG_R * DIG_R + 1:
				continue
			var x := cx + dx
			var y := cy + dy
			if x < 0 or x >= W or y < 0 or y >= H - 1:
				continue
			var i := y * W + x
			var m := grid[i]
			if DIGGABLE[m]:
				var L := layer[i]
				set_cell(i, 0)
				if ORE_ROW[m] >= 0:
					got[m] += 1
					sx[m] += x
					sy[m] += y
				elif m == DIRT and L == CLAY_BAND:
					got[CLAY] += 1
				else:
					got[m] += 1
				if debris.size() < 400 and rng.randf() < 0.3:
					debris.append({"x": float(x), "y": float(y), "vx": (rng.randf() - 0.5) * 1.4 + (t.x - (pl.x + PW / 2.0)) * 0.03,
						"vy": -rng.randf() * 1.5 - 0.3, "life": 30 + int(rng.randf() * 20), "m": m, "L": L})
	for id in [DIRT, CLAY, SAND]:
		if not got[id]:
			continue
		inv[id] += got[id]
		popups.append({"x": cx + (4 if id == SAND else (1 if id == CLAY else -2)), "y": cy - 3 - (3 if id == CLAY else 0), "id": id, "t": 0, "n": got[id]})
	for id in ORE_IDS:
		if not got[id]:
			continue
		var per: int = CELLS_PER_NUG[id]
		var n := int(floor((ore_carry[id] + got[id]) / per))
		ore_carry[id] = (ore_carry[id] + got[id]) - n * per
		if n == 0 and got[id] >= 3:
			n = 1
			ore_carry[id] = 0
		var ox := sx[id] / got[id]
		var oy := sy[id] / got[id]
		var away := signf(ox - (pl.x + PW / 2.0))
		if away == 0:
			away = pl.face
		for k in n:
			if nuggets.size() >= 250:
				break
			nuggets.append({"id": id, "x": ox + (rng.randf() - 0.5) * 3, "y": oy + (rng.randf() - 0.5) * 2,
				"vx": (rng.randf() - 0.5) * 0.9 - away * 0.25, "vy": -1.3 - rng.randf() * 0.9, "age": 0, "ph": rng.randi() % 4})
	noise(0.06, 500, 1, 0.06)                            # the shovel bites

func _update_nuggets() -> void:
	var pcx: float = pl.x + PW / 2.0
	var pcy: float = pl.y + PH / 2.0
	var i := nuggets.size() - 1
	while i >= 0:
		var g: Dictionary = nuggets[i]
		g.age += 1
		if g.age > 14 and g.x > pl.x - 1.5 and g.x < pl.x + PW + 1.5 and g.y > pl.y - 1 and g.y < pl.y + PH + 2:
			inv[g.id] += 1
			var val: int = ORE_VALUE.get(g.id, 1)
			score += val
			tone(0.07, 900 + val * 60, 1500, 0.05)        # ching
			popups.append({"x": g.x, "y": g.y - 3, "id": g.id, "t": 0})
			nuggets[i] = nuggets[nuggets.size() - 1]
			nuggets.pop_back()
			i -= 1
			continue
		var dx: float = pcx - g.x
		var dy: float = pcy - g.y
		var d := Vector2(dx, dy).length()
		if d == 0:
			d = 1
		if g.age > 14 and d < 10:
			var f := 0.05 + 0.1 * (1 - d / 10)
			g.vx += dx / d * f
			g.vy += dy / d * f
		var gi := int(floor(g.y)) * W + int(floor(g.x))
		var wet := gi >= 0 and gi < W * H and grid[gi] == WATER
		g.vy = minf(g.vy + (0.05 if wet else 0.12), 0.8 if wet else 2.5)
		if wet:
			g.vx *= 0.92
		var nx: float = g.x + g.vx
		if solid_at(int(floor(nx)), int(floor(g.y))):
			g.vx *= -0.4
		else:
			g.x = nx
		var rem: float = g.vy
		while absf(rem) > 1e-4:
			var st := signf(rem) * minf(1.0, absf(rem))
			rem -= st
			if solid_at(int(floor(g.x)), int(floor(g.y + st))):
				g.vy = -g.vy * 0.35 if g.vy > 0.8 else 0.0
				g.vx *= 0.75
				break
			g.y += st
		if solid_at(int(floor(g.x)), int(floor(g.y)) + 1) and absf(g.vy) < 0.01:
			g.vx *= 0.8
		var k := 0
		while k < 12 and solid_at(int(floor(g.x)), int(floor(g.y))):
			g.y -= 1
			k += 1
		if g.y > H + 5 or g.x < -2 or g.x > W + 2:
			nuggets[i] = nuggets[nuggets.size() - 1]
			nuggets.pop_back()
		i -= 1
	var j := popups.size() - 1
	while j >= 0:
		popups[j].t += 1
		if popups[j].t > 45:
			popups.remove_at(j)
		j -= 1

# ---------------------------------------------------------------- the launcher

func show_toast(text: String) -> void:
	toast = {"text": text, "t": 0}

func cycle_ammo(dir: int) -> void:
	ammo = AMMO[(AMMO.find(ammo) + dir + AMMO.size()) % AMMO.size()]
	show_toast("Ammo: " + AMMO_NAME[ammo])

func try_upgrade() -> void:
	var nxt := launch_lvl + 1
	if nxt > 5:
		show_toast("Launcher is maxed out")
		return
	var id: int = LAUNCH_COST[nxt][0]
	var n: int = LAUNCH_COST[nxt][1]
	if inv[id] >= n:
		inv[id] -= n
		launch_lvl = nxt
		show_toast("Launcher upgraded to Lv " + str(nxt) + "!")
		tone(0.25, 500, 1200, 0.1)
	else:
		show_toast("Need " + str(n) + " " + ORE_NAMES[ORE_ROW[id]] + " (you have " + str(inv[id]) + ")")

func launch_origin() -> Vector2:
	return Vector2(pl.x + PW / 2.0 + pl.face * 1.5, pl.y + 3)

func launch_vel(spread: bool) -> Vector2:
	var m := mouse_world()
	var o := launch_origin()
	var a := atan2(m.y - o.y, m.x - o.x) + ((rng.randf() - 0.5) * 0.12 if spread else 0.0)
	var v: float = LAUNCH_SPEED[launch_lvl] * ((0.93 + rng.randf() * 0.1) if spread else 1.0)
	return Vector2(cos(a) * v, sin(a) * v)

func do_launch() -> void:
	var mx := mouse_world().x
	var cx: float = pl.x + PW / 2.0
	if absf(mx - cx) > 0.5:
		pl.face = 1 if mx > cx else -1
	launch_t += 1
	var m: int = ammo if inv[ammo] > 0 else 0
	if not m:
		if launch_t % 40 == 1:
			show_toast("Out of clay - dig the orange layer under the topsoil" if ammo == CLAY else ("Out of sand" if ammo == SAND else "Out of dirt - dig some first"))
		return
	if shots.size() >= 700:
		return
	inv[m] -= 1
	var o := launch_origin()
	var v := launch_vel(true)
	shots.append({"x": o.x, "y": o.y, "vx": v.x, "vy": v.y, "m": m})

func _settle_shot(p: Dictionary) -> void:
	var x := int(floor(p.x))
	var y := int(floor(p.y))
	if x < 0 or x >= W or y < 0:
		return
	if x >= int(floor(pl.x)) - 1 and x <= int(floor(pl.x)) + PW and y >= int(floor(pl.y)) - 1 and y <= int(floor(pl.y)) + PH - 4:
		inv[p.m] += 1
		return
	y = mini(y, H - 2)
	var k := 0
	while k < 8 and SOLID[grid[y * W + x]]:
		y -= 1
		k += 1
	if y < 0:
		return
	var i := y * W + x
	if grid[i] == WATER:
		for yy in range(y - 1, maxi(0, y - 20) - 1, -1):
			if grid[yy * W + x] == EMPTY:
				set_cell(yy * W + x, WATER)
				break
			if grid[yy * W + x] != WATER:
				break
	set_cell(i, p.m)

func _update_shots() -> void:
	var i := shots.size() - 1
	while i >= 0:
		var p: Dictionary = shots[i]
		var ci := int(floor(p.y)) * W + int(floor(p.x))
		var wet := ci >= 0 and ci < W * H and grid[ci] == WATER
		p.vy += 0.03 if wet else 0.09
		if wet:
			p.vx *= 0.85
			p.vy = minf(p.vy, 0.5)
		var n := maxi(1, ceili(maxf(absf(p.vx), absf(p.vy))))
		var dead := false
		for k in n:
			var nx: float = p.x + p.vx / n
			var ny: float = p.y + p.vy / n
			if nx < 0 or nx >= W:
				dead = true
				break
			if ny >= H - 1 or solid_at(int(floor(nx)), int(floor(ny))):
				if p.m == CLAY:
					_settle_shot(p)
					dead = true
					break
				var below := solid_at(int(floor(p.x)), int(floor(p.y)) + 1)
				if below or (int(floor(ny)) > int(floor(p.y)) and int(floor(nx)) == int(floor(p.x))):
					_settle_shot(p)
					dead = true
				else:
					p.vx = 0.0
					p.vy = maxf(0.0, p.vy) * 0.5
				break
			p.x = nx
			p.y = ny
		if dead or p.y < -60:
			shots[i] = shots[shots.size() - 1]
			shots.pop_back()
		i -= 1

func _handle_mouse() -> void:
	launching = (mouse.launch or _keys.has("e")) and not mouse.down
	if launching:
		do_launch()
	else:
		launch_t = 0
	if mouse.down:
		var mx := mouse_world().x
		var cx: float = pl.x + PW / 2.0
		if absf(mx - cx) > 0.5:
			pl.face = 1 if mx > cx else -1
		dig_t += 1
		if dig_t == DIG_HIT:
			do_dig()
		if dig_t >= DIG_LEN:
			dig_t = 0
	else:
		dig_t = 0

func _update_debris() -> void:
	var i := debris.size() - 1
	while i >= 0:
		var p: Dictionary = debris[i]
		p.x += p.vx
		p.y += p.vy
		p.vy += 0.1
		p.life -= 1
		if p.life <= 0 or p.y >= H:
			debris[i] = debris[debris.size() - 1]
			debris.pop_back()
		i -= 1

func tick() -> void:
	_step_player()
	_handle_mouse()
	sim_step()
	_update_debris()
	_update_nuggets()
	_update_shots()
	if toast != null:
		toast.t += 1
		if toast.t > 150:
			toast = null
	var tx := clampf(pl.x + PW / 2.0 - VW / 2.0, 0, W - VW)
	var ty := clampf(pl.y + PH / 2.0 - VH / 2.0, 0, H - VH)
	cam_xf += (tx - cam_xf) * 0.12
	cam_yf += (ty - cam_yf) * 0.12
	cam_x = roundi(cam_xf)
	cam_y = roundi(cam_yf)

# ---------------------------------------------------------------- the cabinet's stick

## The cabinet's keys, stick, pointer and buttons as the game's own keys and mouse (input in the HTML game).
func _input_from(st: Dictionary) -> void:
	_keys.clear()
	var held: Dictionary = st.get("held", {})
	var x: float = st.get("x", 0.0)
	var y: float = st.get("y", 0.0)
	if x < -0.3: _keys["a"] = true
	if x > 0.3: _keys["d"] = true
	if y < -0.5 or held.has("jump"): _keys["w"] = true
	if held.has("launch"): _keys["e"] = true
	var pressed: Dictionary = st.get("pressed", {})
	if pressed.has("q"): cycle_ammo(1)
	if pressed.has("u"): try_upgrade()
	var c := Vector2(pl.x + PW / 2.0, pl.y + PH / 2.0)
	var aim: Vector2 = st.get("aim", Vector2.ZERO)
	var p = st.get("ptr", null)
	mouse.down = false
	mouse.launch = st.get("ptr_alt", false)
	if aim.length() > 0.25:                             # the pad's right stick aims, from where he stands
		_aim_world = c + aim.normalized() * (REACH + 14.0) * minf(1.0, aim.length() * 1.2)
		mouse.inside = true
		mouse.down = held.has("dig")
	elif p != null and (st.get("ptr_in", false) or st.get("ptr_down", false)):
		var pv: Vector2 = p
		mouse.inside = st.get("ptr_in", false) and (not st.get("touch", false) or st.get("ptr_down", false))
		_aim_world = Vector2(pv.x * CW / SW / S + cam_x, pv.y * CHT / SH / S + cam_y)
		mouse.down = st.get("ptr_down", false) and st.get("ptr_in", false)
	else:
		mouse.inside = false
		mouse.down = held.has("dig")
	if _aim_world == null:
		_aim_world = c + Vector2(pl.face * 10.0, -6.0)
	var aw: Vector2 = _aim_world
	if not mouse.inside and aim.length() <= 0.25 and p == null:
		aw = c + Vector2(pl.face * 10.0, -6.0)            # nothing aiming: in front of him, a little up
	mouse.sx = (aw.x - cam_x) * S
	mouse.sy = (aw.y - cam_y) * S

func step(dt: float, st: Dictionary) -> void:
	if not live:
		return
	_input_from(st)
	_acc += minf(100.0, dt * 1000.0)
	var n := 0
	while _acc >= 1000.0 / 60.0 and n < 4:
		tick()
		_acc -= 1000.0 / 60.0
		n += 1
	if n == 4:
		_acc = 0.0

# ---------------------------------------------------------------- the picture of the world

func _shade_cell(x: int, y: int) -> int:
	var idx := y * W + x
	var m := grid[idx]
	var v := hv[idx]
	if m == WATER:
		if y > 0 and grid[idx - W] == EMPTY:
			return WATER_TOP
		return pal[WATER][(v + (frame >> 4)) & 7]
	if m == SAND:
		if y > 0 and grid[idx - W] == EMPTY and y < H - 1 and grid[idx + W] != EMPTY:
			return SAND_TOP[v]
		return pal[SAND][v]
	if m:
		var up := grid[idx - W] if y > 0 else 1
		var dn := grid[idx + W] if y < H - 1 else 1
		var lf := grid[idx - 1] if x > 0 else 1
		var rt := grid[idx + 1] if x < W - 1 else 1
		var edge := up == EMPTY or dn == EMPTY or lf == EMPTY or rt == EMPTY
		if m == DIRT and edge and y <= surf[x] + 2 and y >= surf[x] - 1:
			return pal[GRASS][v]
		if edge:
			return pal_ao[CLAY][v] if m == CLAY else OUTLINE
		var ao := (y > 1 and grid[idx - 2 * W] == EMPTY) or (y < H - 2 and grid[idx + 2 * W] == EMPTY) or (x > 1 and grid[idx - 2] == EMPTY) or (x < W - 2 and grid[idx + 2] == EMPTY) \
			or (y > 0 and x > 0 and grid[idx - W - 1] == EMPTY) or (y > 0 and x < W - 1 and grid[idx - W + 1] == EMPTY) \
			or (y < H - 1 and x > 0 and grid[idx + W - 1] == EMPTY) or (y < H - 1 and x < W - 1 and grid[idx + W + 1] == EMPTY)
		if m == DIRT:
			return soil_ao[layer[idx]][v] if ao else soil_pal[layer[idx]][v]
		if m == CLAY:
			return soil_ao[CLAY_BAND][v] if ao else soil_pal[CLAY_BAND][v]
		var rim := (ORE_ROW[m] >= 0 or m == ROCK) and (up != m or dn != m or lf != m or rt != m)
		if rim:
			return pal_rim[m][v]
		return pal_ao[m][v] if ao else pal[m][v]
	if y > surf[x] + 1:
		return back_pal[layer[idx]][v]
	return 0                                          # sky: see through to the hills

func _paint(x: int, y: int) -> void:
	pix.encode_s32((y * W + x) * 4, _shade_cell(x, y))

func _paint_chunk(ccx: int, ccy: int) -> void:
	for y in range(ccy * CH, ccy * CH + CH):
		for x in range(ccx * CH, ccx * CH + CH):
			_paint(x, y)
	shaded[ccy * CCX + ccx] = 1
	_pix_changed = true

## Bring the picture up to date for what's on screen.
func refresh_picture() -> void:
	# chunks coming into view for the first time
	var c0 := maxi(0, cam_x / CH)
	var c1 := mini(CCX - 1, (cam_x + VW) / CH)
	var r0 := maxi(0, cam_y / CH)
	var r1 := mini(CCY - 1, (cam_y + VH) / CH)
	for cy in range(r0, r1 + 1):
		for cx in range(c0, c1 + 1):
			if not shaded[cy * CCX + cx]:
				_paint_chunk(cx, cy)
	# what changed, and round it (edges and shading look two cells out)
	if not dirty.is_empty():
		shade_gen += 1
		for i in dirty:
			var x := i % W
			var y := i / W
			for yy in range(maxi(0, y - 2), mini(H, y + 3)):
				for xx in range(maxi(0, x - 2), mini(W, x + 3)):
					var j := yy * W + xx
					if shade_mark[j] == shade_gen or not shaded[(yy / CH) * CCX + xx / CH]:
						continue
					shade_mark[j] = shade_gen
					_paint(xx, yy)
		dirty.clear()
		_pix_changed = true
	# the water ripples every 16 frames
	var wf := frame >> 4
	if wf != _water_frame:
		_water_frame = wf
		for y in range(cam_y, mini(H, cam_y + VH + 1)):
			var row := y * W
			for x in range(cam_x, mini(W, cam_x + VW + 1)):
				if grid[row + x] == WATER:
					_paint(x, y)
		_pix_changed = true
	if _pix_changed:
		img.set_data(W, H, false, Image.FORMAT_RGBA8, pix)
		tex.update(img)
		_pix_changed = false

# ---------------------------------------------------------------- drawing

func draw(ci: CanvasItem, s: Rect2) -> void:
	refresh_picture()
	var k := Vector2(s.size.x / CW, s.size.y / CHT)
	ci.draw_set_transform(s.position, 0.0, k)
	ci.draw_texture_rect(sky_tex, Rect2(0, 0, CW, CHT), false)
	_draw_parallax(ci)
	ci.draw_texture_rect_region(tex, Rect2(0, 0, CW, CHT), Rect2(cam_x, cam_y, VW, VH))
	_draw_twinkles(ci)
	for p in debris:
		ci.draw_rect(Rect2(roundi((p.x - cam_x) * S), roundi((p.y - cam_y) * S), S - 1, S - 1), soil_css[p.L] if p.m == DIRT else css[p.m])
	for p in shots:
		var sx := roundi((p.x - cam_x) * S) - 3
		var sy := roundi((p.y - cam_y) * S) - 3
		ci.draw_rect(Rect2(sx - 1, sy - 1, S + 1, S + 1), Color("#0a0605"))
		ci.draw_rect(Rect2(sx, sy, S - 1, S - 1), soil_css[0] if p.m == DIRT else (soil_css[CLAY_BAND] if p.m == CLAY else css[SAND]))
	if launching and mouse.inside:
		_draw_aim_arc(ci)
	_draw_nuggets(ci)
	_draw_miner(ci, (pl.x - cam_x) * S, (pl.y - cam_y) * S)
	_draw_inventory(ci)
	_draw_launcher_hud(ci)
	if mouse.inside and not launching:
		var t := dig_target()
		ci.draw_arc(Vector2((t.x - cam_x) * S, (t.y - cam_y) * S), (DIG_R + 0.5) * S, 0, TAU, 40, Color(1, 1, 1, 0.85), 2.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_twinkles(ci: CanvasItem) -> void:
	# a twinkling ore cell is one where (idx * 7 + (frame >> 3) * 13) % 97 == 0: idx = -(frame >> 3) * 13 * 14 mod 97
	var kk := frame >> 3
	var c := posmod(-kk * 13 * 14, 97)
	for y in range(cam_y, mini(H - 1, cam_y + VH)):
		if y < 1:
			continue
		var row := y * W
		var x := posmod(c - row, 97)
		while x < W:
			if x >= cam_x and x < cam_x + VW and x > 0 and x < W - 1:
				var idx := row + x
				var m := grid[idx]
				if TWINKLE[m] and grid[idx - W] != EMPTY and grid[idx + W] != EMPTY and grid[idx - 1] != EMPTY and grid[idx + 1] != EMPTY:
					ci.draw_rect(Rect2((x - cam_x) * S, (y - cam_y) * S, S, S), Color8(255, 255, 250))
			x += 97

func _draw_parallax(ci: CanvasItem) -> void:
	var dy := cam_yf - ref_cam_y
	for c in clouds:
		c.x += c.spd
		var sx := fposmod(c.x - cam_xf * 0.06, W * 1.2) - 20
		var sy: float = c.y - cam_yf + dy * 0.95
		if sx > VW + 10:
			continue
		for b in c.blobs:
			ci.draw_rect(Rect2(roundi((sx + b[0]) * S), roundi((sy + b[1] + 1) * S), b[2] * S, b[3] * S), Color("#dbe9f5"))
			ci.draw_rect(Rect2(roundi((sx + b[0]) * S), roundi((sy + b[1]) * S), b[2] * S, b[3] * S), Color.WHITE)
	for L in PLX:
		var ox: float = cam_xf * L.f
		var ix := int(floor(ox))
		var fx := (ox - ix) * S
		var base_y: float = horizon_y - cam_yf + dy * (1 - L.f)
		var top_c := Color(L.top)
		var col_c := Color(L.col)
		for col in range(-1, VW + 2):
			var xx := col + ix
			var h: float = L.base + L.a[0] * sin(xx * L.k[0]) + L.a[1] * sin(xx * L.k[1] + 1.7) + L.a[2] * sin(xx * L.k[2] + 4.1)
			var top := roundi(base_y - h)
			var sx2 := roundi(col * S - fx)
			var sy2 := top * S
			if sy2 >= CHT:
				continue
			ci.draw_rect(Rect2(sx2, sy2, S, S), top_c)
			ci.draw_rect(Rect2(sx2, sy2 + S, S, CHT - sy2), col_c)

func _draw_aim_arc(ci: CanvasItem) -> void:
	var p := launch_origin()
	var v := launch_vel(false)
	for k in 220:
		v.y += 0.09
		var n := p + v
		if n.x < 0 or n.x >= W or n.y >= H - 1 or solid_at(int(floor(n.x)), int(floor(n.y))):
			ci.draw_rect(Rect2(roundi((p.x - cam_x) * S) - 6, roundi((p.y - cam_y) * S) - 6, 12, 12), Color(1, 1, 1, 0.9), false, 2.0)
			break
		p = n
		if k % 3 == 0:
			ci.draw_rect(Rect2(roundi((p.x - cam_x) * S) - 1, roundi((p.y - cam_y) * S) - 1, 3, 3), Color(1, 1, 1, 0.8))

func _draw_icon(ci: CanvasItem, id: int, x: float, y: float, alpha: float = 1.0) -> void:
	if ORE_ROW[id] >= 0:
		if ore_sheet:
			ci.draw_texture_rect_region(ore_sheet, Rect2(x, y, OC, OC), Rect2(0, ORE_ROW[id] * OC, OC, OC), Color(1, 1, 1, alpha))
	elif soil_icon.has(id):
		ci.draw_texture(soil_icon[id], Vector2(x, y), Color(1, 1, 1, alpha))

static func _fmt(n: int) -> String:
	if n >= 10000:
		return str(n / 1000) + "k"
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)

func _text(ci: CanvasItem, p: Vector2, txt: String, size: int, col: Color, outline: bool = false) -> void:
	var f := font()
	if outline:
		ci.draw_string_outline(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, col.a))
	ci.draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_nuggets(ci: CanvasItem) -> void:
	if ore_sheet:
		var t := frame >> 3
		for g in nuggets:
			var sx := roundi((g.x - cam_x) * S - OC / 2.0)
			var sy := roundi((g.y - cam_y) * S - OC + 5)
			if sx < -OC or sy < -OC or sx > CW or sy > CHT:
				continue
			ci.draw_texture_rect_region(ore_sheet, Rect2(sx, sy, OC, OC), Rect2(((g.ph + t) & 3) * OC, ORE_ROW[g.id] * OC, OC, OC))
			if (g.id == RUBY or g.id == EMERALD) and ((frame + g.ph * 17) % 70) < 7:
				var gx: int = sx + 8 + (g.ph * 5) % 10
				var gy: int = sy + 6 + (g.ph * 3) % 6
				ci.draw_rect(Rect2(gx - 3, gy, 7, 1), Color.WHITE)
				ci.draw_rect(Rect2(gx, gy - 3, 1, 7), Color.WHITE)
	for p in popups:
		var px := roundi((p.x - cam_x) * S)
		var py := roundi((p.y - cam_y) * S - p.t * 0.8)
		var a: float = 1.0 - p.t / 45.0
		_draw_icon(ci, p.id, px - OC + 2, py - OC / 2.0, a)
		_text(ci, Vector2(px + 4, py + 5), "+" + str(p.get("n", 1)), 14, Color(1, 1, 1, a), true)

func _draw_inventory(ci: CanvasItem) -> void:
	var have: Array = []
	for id in AMMO + ORE_IDS:
		if inv[id] > 0 or id == ammo:
			have.append(id)
	var slot := 62
	var w := have.size() * slot + 10
	ci.draw_rect(Rect2(10, HUD_Y + 10, w, 38), Color(15 / 255.0, 10 / 255.0, 8 / 255.0, 0.6))
	for i in have.size():
		var id: int = have[i]
		var x := 16 + i * slot
		if id == ammo:
			ci.draw_rect(Rect2(x - 3, HUD_Y + 13, slot - 4, 32), Color("#ffd36b"), false, 2.0)
		_draw_icon(ci, id, x, HUD_Y + 16)
		_text(ci, Vector2(x + OC + 4, HUD_Y + 35), _fmt(inv[id]), 15, Color.WHITE)

func _draw_launcher_hud(ci: CanvasItem) -> void:
	var f := font()
	var y := CHT - 44.0
	var text := "Launcher Lv " + str(launch_lvl)
	var nxt := launch_lvl + 1
	var up := ("U: upgrade  " + str(inv[LAUNCH_COST[nxt][0]]) + "/" + str(LAUNCH_COST[nxt][1])) if nxt <= 5 else "MAX range"
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var qw := f.get_string_size("Q:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var uw := f.get_string_size(up, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var x_ammo := 18 + tw + 14
	var x_up := x_ammo + qw + 6 + OC + 14
	var w := x_up + uw + ((OC + 10) if nxt <= 5 else 10) - 10
	ci.draw_rect(Rect2(10, y, w, 34), Color(15 / 255.0, 10 / 255.0, 8 / 255.0, 0.6))
	_text(ci, Vector2(18, y + 22), text, 14, Color("#ffd36b"))
	_text(ci, Vector2(x_ammo, y + 22), "Q:", 14, Color.WHITE)
	_draw_icon(ci, ammo, x_ammo + qw + 4, y + 4)
	_text(ci, Vector2(x_up, y + 22), up, 14, Color.WHITE)
	if nxt <= 5:
		_draw_icon(ci, LAUNCH_COST[nxt][0], x_up + uw + 4, y + 4)
	if toast != null:
		var a: float = minf(1.0, (150 - toast.t) / 30.0)
		var ttw := f.get_string_size(toast.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 28
		ci.draw_rect(Rect2((CW - ttw) / 2.0, HUD_Y + 60, ttw, 34), Color(15 / 255.0, 10 / 255.0, 8 / 255.0, 0.75 * a))
		_text(ci, Vector2(CW / 2.0 - (ttw - 28) / 2.0, HUD_Y + 83), toast.text, 17, Color(1, 1, 1, a))

func _draw_miner(ci: CanvasItem, sx: float, sy: float) -> void:
	if sheet == null:
		ci.draw_rect(Rect2(sx, sy, PW * S, PH * S), Color("#e9c46a"))
		return
	var f := 0
	var row := 1
	var bob := 0.0
	if mouse.down:
		row = 0
		f = mini(7, dig_t / 4)
	elif launching:
		row = 0
		f = 5 + ((launch_t >> 2) & 1)
	elif not pl.ground:
		f = 2
	elif absf(pl.vx) > 0.01:
		f = int(floor(walk_t * 0.8)) % 8
	else:
		row = 0
		f = 7
		bob = -SPR_SCALE if sin(frame * 0.06) > 0.55 else 0.0
	var k := SPR_SCALE
	var ox := roundf(sx + PW * S / 2.0)
	var oy := roundf(sy + PH * S) + bob
	var dw := SPR_FW * k
	var dx := ox - SPR_AX * k
	if pl.face > 0:                                   # the sheet faces left: flip him round his middle
		dx = ox + SPR_AX * k
		dw = -dw
	ci.draw_texture_rect_region(sheet, Rect2(dx, oy - (SPR_BASE + 1) * k, dw, SPR_FH * k), Rect2(f * SPR_FW, row * SPR_FH, SPR_FW, SPR_FH))

static func mini(ci: CanvasItem, r: Rect2, t: float) -> void:
	ci.draw_rect(r, Color("#79c4f5"))
	var gy := r.position.y + r.size.y * 0.42
	ci.draw_rect(Rect2(r.position.x, gy - 3, r.size.x, 3), Color("#86b98a"))
	var bands := ["#704a2e", "#965c38", "#624c40", "#4c4850"]
	for i in bands.size():
		ci.draw_rect(Rect2(r.position.x, gy + i * (r.size.y * 0.15), r.size.x, r.size.y * 0.15 + 1), Color(bands[i]))
	ci.draw_rect(Rect2(r.position.x, gy, r.size.x, 2), Color("#54963c"))
	var tw := int(floor(t * 3))
	var spots := [[0.2, 0.62, "#ffce28"], [0.7, 0.75, "#c2edf9"], [0.45, 0.88, "#fa2e6c"], [0.85, 0.58, "#ffce28"]]
	for i in spots.size():
		var sp: Array = spots[i]
		ci.draw_rect(Rect2(r.position.x + sp[0] * r.size.x, r.position.y + sp[1] * r.size.y, 3, 2), Color(sp[2]))
		if (tw + i) % 4 == 0:
			ci.draw_rect(Rect2(r.position.x + sp[0] * r.size.x + 1, r.position.y + sp[1] * r.size.y - 1, 1, 1), Color.WHITE)
	var dx := r.position.x + r.size.x * (0.3 + 0.2 * sin(t * 0.6))
	ci.draw_rect(Rect2(dx - 3, gy + 2, 9, 6), Color("#1a1311"))
	ci.draw_rect(Rect2(dx, gy + 2 - (int(floor(t * 4)) % 2), 3, 4), Color("#e9c46a"))
