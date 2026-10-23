class_name MineGround
extends Node3D
## The dig mode's ground (the owner, 23 Oct: the Motherload-style mine): W x D tiles of 1 m, seen side-on, made the
## same every time from a seed: topsoil and clay, grey stone, deep red rock, black basalt and glowing crystal rock at
## the bottom (the zones' edges wavy), ores set in it (coal near the top .. diamonds at the bottom, rarer and richer
## the deeper), boulders that need a better drill, gas pockets, lava pockets, little caves, the mushroom caves and the
## mushroom cathedral with its giant mushroom, the worm's cavern at the bottom, and the trial hazards (the sewers, the
## cop bunker, the rival dealers' tunnels) when they're switched on. Drawn in 8 x 8 tile chunks (only a changed
## chunk is drawn again): a tile's front face, and where it's dug, the back wall and the walls of the tunnel. Lava
## flows out into what's dug, and cools to basalt when it's sat still a while. Owned by the voxel session.

const W := 50                   # tiles across (the outer two bedrock)
const D := 150                  # tiles down (the bottom one bedrock)
const CH := 8                   # a chunk's tiles across and down
const MARGIN := 16              # bedrock drawn past the edges (so the view never shows the end of the world)
const LAVA_T := 0.12            # seconds between lava's moves
const LAVA_COOL := 30.0         # seconds lava sits still before it's basalt
## The buildings up top: [name, first tile, last tile] (concrete pads under them)
const BUILDINGS := [["lift", 3, 6], ["fuel", 9, 12], ["trader", 15, 19], ["mechanic", 22, 26]]
## The ores: [tile, first row, last row, the row they're most at, the chance a tile is one there]
const ORES := [
	[MineTiles.COAL, 3, 62, 16, 0.055],
	[MineTiles.COPPER, 10, 96, 38, 0.038],
	[MineTiles.SILVER, 28, 126, 64, 0.03],
	[MineTiles.GOLD, 52, 148, 94, 0.024],
	[MineTiles.OPAL, 78, 148, 118, 0.018],
	[MineTiles.DIAMOND, 100, 148, 140, 0.016],
]

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D atlas : filter_nearest, source_color;
uniform sampler2D glow : filter_nearest, source_color;
uniform float glint = 1.0;
void fragment() {
	vec4 b = texture(atlas, UV);
	vec4 o = texture(atlas, UV2);
	ALBEDO = mix(b.rgb, o.rgb, o.a) * COLOR.rgb;
	ROUGHNESS = 1.0;
	float tw = pow(max(0.0, sin(TIME * 1.9 + COLOR.a * 61.0)), 18.0);
	vec3 g = texture(glow, UV).rgb + texture(glow, UV2).rgb * o.a;
	EMISSION = g * (0.7 + 3.5 * tw * glint) * (0.4 + 0.6 * COLOR.rgb);
}
"""

var seed_ := 1
var flags := {"sewers": true, "cops": true, "rivals": true}
var tiles := PackedByteArray()
var base := PackedByteArray()     # the rock of each tile's depth (what an ore's drawn over)
var bg := PackedByteArray()       # what's behind each tile once it's open
## where things are, for the rest of the mine: "caves" [[cx, cy, rx, ry]], "cathedral" [cx, cy, rx, ry, stem x, floor
## row], "bunker" [x0, r0, x1, r1], "sewer" [[x0, r, x1]], "rival" [Vector2i tunnel tiles], "lanterns" [Vector2],
## "worm" [cx, cy, rx, ry], "lava" [Vector2i pocket middles]
var features := {}
var mat: ShaderMaterial
var _chunks := {}                 # Vector2i -> MeshInstance3D
var _dirty := {}                  # Vector2i -> true: to be drawn again
var _lava := {}                   # tile index -> seconds it's sat still
var _lava_t := 0.0
var _decor := {}                  # tile index (what it stands on) -> [Node3D]
var _decor_root: Node3D
var changed := 0                  # tiles changed since the last save (the mine saves when it's more than none)
var keep_clear := Rect2i()        # (the tiles round the ship) lava doesn't cool to rock here

func _ready() -> void:
	var at: Array = MineTiles.build_atlas()
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	mat.set_shader_parameter("atlas", ImageTexture.create_from_image(at[0]))
	mat.set_shader_parameter("glow", ImageTexture.create_from_image(at[1]))

# ---------------------------------------------------------------- tiles

static func idx(x: int, r: int) -> int:
	return x + r * W

static func inside(x: int, r: int) -> bool:
	return x >= 0 and x < W and r >= 0 and r < D

## The tile at (x, row): above the ground air, past the sides and the bottom bedrock.
func at(x: int, r: int) -> int:
	if r < 0:
		return MineTiles.AIR if x >= 0 and x < W else MineTiles.BEDROCK
	if x < 0 or x >= W or r >= D:
		return MineTiles.BEDROCK
	return tiles[x + r * W]

func base_at(x: int, r: int) -> int:
	return base[x + r * W] if inside(x, r) else MineTiles.BEDROCK

func bg_at(x: int, r: int) -> int:
	return bg[x + r * W] if inside(x, r) else MineTiles.BG_EARTH

func solid_at(x: int, r: int) -> bool:
	return MineTiles.solid(at(x, r))

## A tile changed: drawn again (and the chunk next door if it's on the edge: that one's tunnel wall), lava woken.
func set_tile(x: int, r: int, t: int) -> void:
	if not inside(x, r):
		return
	var i := x + r * W
	if tiles[i] == t:
		return
	tiles[i] = t
	changed += 1
	_mark(x, r)
	if t == MineTiles.LAVA:
		_lava[i] = 0.0
	elif t == MineTiles.AIR:
		_lava.erase(i)
		# lava next to it can flow now
		for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			if inside(x + d.x, r + d.y) and tiles[idx(x + d.x, r + d.y)] == MineTiles.LAVA:
				_lava[idx(x + d.x, r + d.y)] = 0.0
		# whatever stood on it falls away
		if _decor.has(i):
			for n in _decor[i]:
				if is_instance_valid(n):
					n.queue_free()
			_decor.erase(i)

func _mark(x: int, r: int) -> void:
	var c := Vector2i(x / CH, r / CH)
	_dirty[c] = true
	if x % CH == 0 and x > 0:
		_dirty[Vector2i(c.x - 1, c.y)] = true
	if x % CH == CH - 1 and x < W - 1:
		_dirty[Vector2i(c.x + 1, c.y)] = true
	if r % CH == 0 and r > 0:
		_dirty[Vector2i(c.x, c.y - 1)] = true
	if r % CH == CH - 1 and r < D - 1:
		_dirty[Vector2i(c.x, c.y + 1)] = true

## The world point of a tile's middle (x across, y up: the ground's top is y = 0).
static func centre(x: int, r: int) -> Vector2:
	return Vector2(x + 0.5, -r - 0.5)

static func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(-p.y))

## Which building's pad a tile across is under ("": none)
static func building_at(x: float) -> String:
	for b in BUILDINGS:
		if x >= float(b[1]) and x < float(b[2]) + 1.0:
			return String(b[0])
	return ""

static func building_x(name: String) -> float:
	for b in BUILDINGS:
		if String(b[0]) == name:
			return (float(b[1]) + float(b[2]) + 1.0) * 0.5
	return 30.0

# ---------------------------------------------------------------- making it

func generate(s: int, fl: Dictionary) -> void:
	seed_ = s
	flags = fl.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var nz := FastNoiseLite.new()
	nz.seed = s
	nz.frequency = 0.07
	tiles.resize(W * D)
	base.resize(W * D)
	bg.resize(W * D)
	bg.fill(MineTiles.BG_EARTH)
	features = {"caves": [], "sewer": [], "rival": [], "lanterns": [], "lava": [], "mush": []}
	for r in D:
		for x in W:
			var zr := r + nz.get_noise_2d(x * 1.3, r * 0.6) * 6.0
			var t := MineTiles.DIRT
			if r <= 2:
				t = MineTiles.DIRT
			elif zr < 6.0:
				t = MineTiles.DIRT
			elif zr < 19.0:
				t = MineTiles.CLAY if nz.get_noise_2d(x * 4.0, r * 4.0) > -0.35 else MineTiles.DIRT
			elif zr < 50.0:
				t = MineTiles.STONE
			elif zr < 86.0:
				t = MineTiles.RED
			elif zr < 121.0:
				t = MineTiles.BASALT
			else:
				t = MineTiles.CRYSTAL
			base[idx(x, r)] = t
			tiles[idx(x, r)] = t
	_ores(rng)
	_boulders(rng)
	_gas(rng)
	_little_caves(rng)
	_mush_caves(rng)
	_cathedral(rng)
	if flags.get("sewers", true):
		_sewers(rng)
	if flags.get("cops", true):
		_bunker(rng)
	if flags.get("rivals", true):
		_rivals(rng)
	_lava_pockets(rng)              # (after the tunnels: the pockets keep clear of them)
	_worm_cavern(rng)
	# the edges and the bottom; the pads under the buildings
	for r in D:
		tiles[idx(0, r)] = MineTiles.BEDROCK
		tiles[idx(W - 1, r)] = MineTiles.BEDROCK
	for x in W:
		tiles[idx(x, D - 1)] = MineTiles.BEDROCK
	for b in BUILDINGS:
		for x in range(int(b[1]), int(b[2]) + 1):
			tiles[idx(x, 0)] = MineTiles.PAD
			bg[idx(x, 0)] = MineTiles.BG_EARTH
	_lava.clear()
	for i in tiles.size():
		if tiles[i] == MineTiles.LAVA:
			_lava[i] = 0.0
	changed = 0

func _plain(x: int, r: int) -> bool:
	return inside(x, r) and tiles[idx(x, r)] == base[idx(x, r)] and x > 0 and x < W - 1

func _ores(rng: RandomNumberGenerator) -> void:
	for r in range(2, D - 1):
		for x in range(1, W - 1):
			if not _plain(x, r):
				continue
			for o in ORES:
				var a := int(o[1])
				var b := int(o[2])
				var pk := int(o[3])
				if r < a or r > b:
					continue
				var k := 1.0 - absf(r - pk) / float(maxi(1, pk - a if r < pk else b - pk))
				if rng.randf() < float(o[4]) * clampf(k, 0.15, 1.0):
					tiles[idx(x, r)] = int(o[0])
					# a vein: a neighbour or two the same
					for n in rng.randi_range(0, 2):
						var nx := x + rng.randi_range(-1, 1)
						var nr := r + rng.randi_range(0, 1)
						if _plain(nx, nr):
							tiles[idx(nx, nr)] = int(o[0])
					break

func _boulders(rng: RandomNumberGenerator) -> void:
	for r in range(20, D - 1):
		for x in range(1, W - 1):
			if not _plain(x, r) or rng.randf() > 0.013:
				continue
			var t := MineTiles.HARD1
			if r >= 60 and r < 100:
				t = MineTiles.HARD1 if rng.randf() < 0.6 else MineTiles.HARD2
			elif r >= 100 and r < 128:
				t = MineTiles.HARD2 if rng.randf() < 0.7 else MineTiles.HARD3
			elif r >= 128:
				t = MineTiles.HARD3 if rng.randf() < 0.6 else MineTiles.HARD2
			tiles[idx(x, r)] = t
			for n in rng.randi_range(0, 3):
				var nx := x + rng.randi_range(-1, 1)
				var nr := r + rng.randi_range(-1, 1)
				if _plain(nx, nr) and nr >= 20:
					tiles[idx(nx, nr)] = t

func _gas(rng: RandomNumberGenerator) -> void:
	for r in range(25, D - 2):
		for x in range(1, W - 1):
			if _plain(x, r) and rng.randf() < 0.005:
				tiles[idx(x, r)] = MineTiles.GAS
				if rng.randf() < 0.5 and _plain(x + 1, r):
					tiles[idx(x + 1, r)] = MineTiles.GAS

func _little_caves(rng: RandomNumberGenerator) -> void:
	for k in 16:
		var x := rng.randi_range(3, W - 4)
		var r := rng.randi_range(14, D - 6)
		for s in rng.randi_range(4, 11):
			if inside(x, r) and x > 0 and x < W - 1:
				tiles[idx(x, r)] = MineTiles.AIR
			x = clampi(x + rng.randi_range(-1, 1), 2, W - 3)
			r = clampi(r + (rng.randi_range(-1, 1) if rng.randf() < 0.4 else 0), 12, D - 3)

## Carves an ellipse open with a back wall; returns the tiles opened.
func _carve(cx: float, cy: float, rx: float, ry: float, bgk: int, rng: RandomNumberGenerator, rough := 0.25) -> Array:
	var out := []
	for r in range(int(cy - ry - 1), int(cy + ry + 2)):
		for x in range(int(cx - rx - 1), int(cx + rx + 2)):
			if not inside(x, r) or x <= 0 or x >= W - 1 or r >= D - 1:
				continue
			var d := Vector2((x + 0.5 - cx) / rx, (r + 0.5 - cy) / ry).length()
			if d <= 1.0 - rng.randf() * rough * (1.0 if d > 0.7 else 0.0):
				tiles[idx(x, r)] = MineTiles.AIR
				bg[idx(x, r)] = bgk
				out.append(Vector2i(x, r))
	return out

func _mush_caves(rng: RandomNumberGenerator) -> void:
	var rows := [32, 47, 63, 79, 96]
	for k in rows.size():
		var cy := float(rows[k] + rng.randi_range(-3, 3))
		var cx := rng.randf_range(8.0, W - 9.0)
		var rx := rng.randf_range(4.5, 6.5)
		var ry := rng.randf_range(2.6, 3.4)
		var open := _carve(cx, cy, rx, ry, MineTiles.BG_MUSH, rng)
		features.caves.append([cx, cy, rx, ry])
		_mush_dress(open, rng, 0.35)

## A mushroom cave's floor dressed: spore clumps, fool's gold in its walls, mushrooms (decor) on its floor.
func _mush_dress(open: Array, rng: RandomNumberGenerator, spore_k: float) -> void:
	for c in open:
		var below := Vector2i(c.x, c.y + 1)
		if inside(below.x, below.y) and tiles[idx(below.x, below.y)] != MineTiles.AIR and not open.has(below):
			if rng.randf() < spore_k * 0.4:
				tiles[idx(c.x, c.y)] = MineTiles.SPORE
			else:
				features.mush.append([c.x, c.y, rng.randf()])
	for c in open:
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var w: Vector2i = c + d
			if _plain(w.x, w.y) and rng.randf() < 0.22:
				tiles[idx(w.x, w.y)] = MineTiles.FOOLS

func _cathedral(rng: RandomNumberGenerator) -> void:
	var cx := float(W / 2 + rng.randi_range(-8, 8))
	var cy := 113.0 + rng.randi_range(-2, 2)
	var rx := 10.0
	var ry := 6.5
	var open := _carve(cx, cy, rx, ry, MineTiles.BG_CATHEDRAL, rng, 0.15)
	# its floor: the lowest open row under the middle
	var sx := int(cx)
	var fl := int(cy)
	while fl + 1 < D and tiles[idx(sx, fl + 1)] == MineTiles.AIR:
		fl += 1
	# the giant mushroom: a stem two wide, five tall, a cap nine wide on it
	for r in range(fl - 4, fl + 1):
		for x in [sx, sx + 1]:
			tiles[idx(x, r)] = MineTiles.SHROOM
	for r in [fl - 6, fl - 5]:
		for x in range(sx - 4 + (1 if r == fl - 6 else 0), sx + 6 - (1 if r == fl - 6 else 0)):
			if inside(x, r):
				tiles[idx(x, r)] = MineTiles.SHROOM
	features["cathedral"] = [cx, cy, rx, ry, sx, fl]
	var rest := open.filter(func(c): return tiles[idx(c.x, c.y)] == MineTiles.AIR)
	_mush_dress(rest, rng, 0.5)

func _lava_pockets(rng: RandomNumberGenerator) -> void:
	var made := 0
	var tries := 0
	while made < 10 and tries < 200:
		tries += 1
		var cx := rng.randf_range(4.0, W - 5.0)
		var cy := rng.randf_range(70.0, D - 5.0)
		var rx := rng.randf_range(1.4, 3.0)
		var ry := rng.randf_range(1.0, 2.0)
		# not in a cave or the cathedral
		var ok := true
		for r in range(int(cy - ry - 1), int(cy + ry + 2)):
			for x in range(int(cx - rx - 1), int(cx + rx + 2)):
				if not inside(x, r) or tiles[idx(x, r)] == MineTiles.AIR or bg[idx(x, r)] != MineTiles.BG_EARTH:
					ok = false
		if not ok:
			continue
		for r in range(int(cy - ry), int(cy + ry + 1)):
			for x in range(int(cx - rx), int(cx + rx + 1)):
				if inside(x, r) and x > 0 and x < W - 1 and Vector2((x + 0.5 - cx) / rx, (r + 0.5 - cy) / ry).length() <= 1.05:
					tiles[idx(x, r)] = MineTiles.LAVA
		features.lava.append(Vector2i(int(cx), int(cy)))
		made += 1

func _sewers(rng: RandomNumberGenerator) -> void:
	for s in [[5, 7, 41], [9, 3, 27]]:
		var r: int = s[0]
		var x0: int = s[1] + rng.randi_range(-1, 1)
		var x1: int = s[2] + rng.randi_range(-1, 1)
		for x in range(x0 - 1, x1 + 2):
			for rr in range(r - 2, r + 2):
				var edge := x == x0 - 1 or x == x1 + 1 or rr == r - 2 or rr == r + 1
				if not inside(x, rr) or x <= 0 or x >= W - 1:
					continue
				if edge:
					tiles[idx(x, rr)] = MineTiles.JUNK if rng.randf() < 0.12 else MineTiles.BRICK
				else:
					tiles[idx(x, rr)] = MineTiles.AIR
					bg[idx(x, rr)] = MineTiles.BG_SEWER
		features.sewer.append([x0, r, x1])

func _bunker(rng: RandomNumberGenerator) -> void:
	# somewhere clear of the mushroom caves (a few goes at it)
	var x0 := rng.randi_range(14, W - 20)
	var r0 := rng.randi_range(40, 44)
	for k in 40:
		var clear := true
		for r in range(r0 - 1, r0 + 9):
			for x in range(x0 - 1, x0 + 17):
				if inside(x, r) and bg[idx(x, r)] != MineTiles.BG_EARTH:
					clear = false
		if clear:
			break
		x0 = rng.randi_range(3, W - 20)
		r0 = rng.randi_range(36, 54)
	var x1 := x0 + 15
	var r1 := r0 + 7
	for r in range(r0, r1 + 1):
		for x in range(x0, x1 + 1):
			var shell := x == x0 or x == x1 or r == r0 or r == r1
			if shell:
				tiles[idx(x, r)] = MineTiles.CONCRETE
			else:
				tiles[idx(x, r)] = MineTiles.AIR
				bg[idx(x, r)] = MineTiles.BG_BUNKER
	# a wall across the middle with a door in it
	var mx := (x0 + x1) / 2
	for r in range(r0 + 1, r1 - 2):
		tiles[idx(mx, r)] = MineTiles.CONCRETE
	# the evidence lockers on the floor
	for k in 5:
		var x := rng.randi_range(x0 + 1, x1 - 1)
		if x != mx:
			tiles[idx(x, r1 - 1)] = MineTiles.EVIDENCE
	# weak spots: cracks the lights show through
	for k in 3:
		var side := rng.randi_range(0, 2)
		var cx := rng.randi_range(x0 + 2, x1 - 2) if side < 2 else (x0 if rng.randf() < 0.5 else x1)
		var cr := r0 if side == 0 else (r1 if side == 1 else rng.randi_range(r0 + 2, r1 - 2))
		tiles[idx(cx, cr)] = MineTiles.STONE
	features["bunker"] = [x0, r0, x1, r1]

func _rivals(rng: RandomNumberGenerator) -> void:
	var r := rng.randi_range(70, 74)
	var cells := []
	var x := 3
	var ends := []
	while x < W - 3:
		for rr in [r, r + 1]:
			if inside(x, rr):
				tiles[idx(x, rr)] = MineTiles.AIR
				bg[idx(x, rr)] = MineTiles.BG_RIVAL
				cells.append(Vector2i(x, rr))
		if x % 5 == 0 and inside(x, r - 1):
			tiles[idx(x, r - 1)] = MineTiles.TIMBER
		if x % 9 == 4:
			features.lanterns.append(Vector2(x + 0.5, -r - 0.2))
		x += 1
		if rng.randf() < 0.12:
			r = clampi(r + rng.randi_range(-1, 1), 66, 84)
			for rr in [r, r + 1]:
				tiles[idx(x - 1, rr)] = MineTiles.AIR
				bg[idx(x - 1, rr)] = MineTiles.BG_RIVAL
	ends.append(Vector2i(3, cells[0].y))
	ends.append(Vector2i(W - 4, cells[cells.size() - 1].y))
	# a branch down to a dead end, a stash at its foot
	var bx := rng.randi_range(12, W - 12)
	var br := 0
	for c in cells:
		if c.x == bx:
			br = maxi(br, c.y)
	for rr in range(br, br + 8):
		tiles[idx(bx, rr)] = MineTiles.AIR
		bg[idx(bx, rr)] = MineTiles.BG_RIVAL
		cells.append(Vector2i(bx, rr))
	ends.append(Vector2i(bx, br + 8))
	# the stockpiles: at the ends of the tunnels
	for e in ends:
		for k in 3:
			var sx: int = clampi(e.x + rng.randi_range(-1, 1), 1, W - 2)
			var sr: int = e.y + (1 if k == 0 else rng.randi_range(-1, 1))
			if inside(sx, sr) and (tiles[idx(sx, sr)] != MineTiles.AIR or k > 0):
				tiles[idx(sx, sr)] = MineTiles.STASH
	# their shortcut: a shaft up from the tunnel to just under the topsoil, its top capped with timber
	var sx2 := rng.randi_range(30, W - 6)
	var bk: Array = features.get("bunker", [])
	if not bk.is_empty() and sx2 >= int(bk[0]) - 1 and sx2 <= int(bk[2]) + 1:
		sx2 = int(bk[0]) - 2 if int(bk[0]) - 2 >= 3 else int(bk[2]) + 2      # (not down through the cops' bunker)
	var top := 0
	for c in cells:
		if c.x == sx2:
			top = c.y if top == 0 else mini(top, c.y)
	if top > 0:
		for rr in range(12, top):
			tiles[idx(sx2, rr)] = MineTiles.AIR
			bg[idx(sx2, rr)] = MineTiles.BG_RIVAL
			cells.append(Vector2i(sx2, rr))
		tiles[idx(sx2, 11)] = MineTiles.TIMBER
		tiles[idx(sx2, 10)] = MineTiles.TIMBER
		features["shortcut"] = [sx2, 12, top]
	features.rival = cells

func _worm_cavern(rng: RandomNumberGenerator) -> void:
	var cx := float(W / 2 + rng.randi_range(-6, 6))
	var cy := 141.5
	_carve(cx, cy, 11.0, 4.5, MineTiles.BG_WORM, rng, 0.3)
	features["worm"] = [cx, cy, 11.0, 4.5]

# ---------------------------------------------------------------- saving

func save_data() -> Dictionary:
	return {"seed": seed_, "flags": flags, "tiles": Marshalls.raw_to_base64(tiles)}

## The ground from a save: made from its seed again (the same every time), then the tiles as they were left.
func load_data(d: Dictionary) -> bool:
	generate(int(d.get("seed", 1)), d.get("flags", flags) if typeof(d.get("flags")) == TYPE_DICTIONARY else flags)
	var raw := Marshalls.base64_to_raw(String(d.get("tiles", "")))
	if raw.size() != W * D:
		return false
	tiles = raw
	# the decor whose floor's gone, gone; the lava where it lies now
	_lava.clear()
	for i in tiles.size():
		if tiles[i] == MineTiles.LAVA:
			_lava[i] = 0.0
	changed = 0
	return true

# ---------------------------------------------------------------- drawing

## Everything drawn from scratch (a new ground or a loaded one).
func build_all() -> void:
	for c in _chunks:
		(_chunks[c] as Node).queue_free()
	_chunks.clear()
	_dirty.clear()
	if _decor_root:
		_decor_root.queue_free()
	_decor_root = Node3D.new()
	add_child(_decor_root)
	_decor.clear()
	for cy in ceili(float(D) / CH):
		for cx in ceili(float(W) / CH):
			_build_chunk(Vector2i(cx, cy))
	_margin()
	_dress()

func _process(dt: float) -> void:
	var n := 0
	for c in _dirty.keys():
		_build_chunk(c)
		_dirty.erase(c)
		n += 1
		if n >= 6:
			break

## Lava moves (the mine calls this while you're down there): falls into what's open below, spreads sideways, cools.
## Returns true if any moved.
func lava_step(dt: float) -> bool:
	_lava_t += dt
	if _lava_t < LAVA_T or _lava.is_empty():
		return false
	var step := _lava_t
	_lava_t = 0.0
	var moved := false
	var keys := _lava.keys()
	keys.sort()
	keys.reverse()                # (bottom rows first: a column falls together)
	for i in keys:
		if not _lava.has(i) or tiles[i] != MineTiles.LAVA:
			_lava.erase(i)
			continue
		var x: int = i % W
		var r: int = i / W
		var to := -1
		if r + 1 < D and tiles[idx(x, r + 1)] == MineTiles.AIR:
			to = idx(x, r + 1)
		else:
			# sideways only when it's pushed (lava on top of it or under it, or behind it) or there's a drop to run into: a pocket
			# drains out into a tunnel and the puddle settles; a lone blob doesn't slosh back and forth for ever
			var above := (r > 0 and tiles[idx(x, r - 1)] == MineTiles.LAVA) or (r + 1 < D and tiles[idx(x, r + 1)] == MineTiles.LAVA)    # (on top of the pool: spills over)
			var sides := [-1, 1] if randf() < 0.5 else [1, -1]
			for s in sides:
				if x + s <= 0 or x + s >= W - 1 or tiles[idx(x + s, r)] != MineTiles.AIR:
					continue
				var drop: bool = r + 1 < D and tiles[idx(x + s, r + 1)] == MineTiles.AIR
				var behind: bool = x - s >= 0 and x - s < W and tiles[idx(x - s, r)] == MineTiles.LAVA
				if (above or behind or drop) and randf() < 0.45:
					to = idx(x + s, r)
					break
		if to >= 0:
			tiles[i] = MineTiles.AIR
			tiles[to] = MineTiles.LAVA
			_lava.erase(i)
			_lava[to] = 0.0
			_mark(x, r)
			_mark(to % W, to / W)
			changed += 1
			moved = true
			# the lava round where it was can move now
			for d in _SIDES:
				var nx: int = x + d.x
				var nr: int = r + d.y
				if inside(nx, nr) and tiles[idx(nx, nr)] == MineTiles.LAVA:
					_lava[idx(nx, nr)] = 0.0
		else:
			_lava[i] = float(_lava[i]) + step
			if float(_lava[i]) > LAVA_COOL and _next_to_air(x, r) and not keep_clear.has_point(Vector2i(x, r)):
				tiles[i] = MineTiles.BASALT
				base[i] = MineTiles.BASALT
				_lava.erase(i)
				_mark(x, r)
				changed += 1
			elif not _next_to_air(x, r):
				_lava.erase(i)        # (sealed in: asleep till something's dug next to it)
	return moved

func _next_to_air(x: int, r: int) -> bool:
	return at(x - 1, r) == MineTiles.AIR or at(x + 1, r) == MineTiles.AIR or at(x, r - 1) == MineTiles.AIR or at(x, r + 1) == MineTiles.AIR

## Lava tiles open to air near p (for their glow lights): up to n, nearest first.
func lava_near(p: Vector2, n: int) -> Array:
	var out := []
	for i in _lava:
		var c := centre(int(i) % W, int(i) / W)
		if c.distance_to(p) < 18.0:
			out.append(c)
	out.sort_custom(func(a, b): return a.distance_to(p) < b.distance_to(p))
	return out.slice(0, n)

class Quads:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var ix := PackedInt32Array()

	## A quad: corners a, b, c, d (going round), facing n; pictures base and over (MineGround._uvc: each picture's
	## corners, mirrored by flip); its corners' colours k0..k3 (alpha: the glint's phase).
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, p0: int, p1: int, k0: Color, flip := 0,
			k1 := Color(-1, 0, 0), k2 := Color(), k3 := Color()) -> void:
		var s := v.size()
		v.push_back(a)
		v.push_back(b)
		v.push_back(c)
		v.push_back(d)
		nrm.push_back(n)
		nrm.push_back(n)
		nrm.push_back(n)
		nrm.push_back(n)
		uv.append_array(MineGround._uvc[p0 * 4 + flip])
		uv2.append_array(MineGround._uvc[p1 * 4 + flip])
		col.push_back(k0)
		if k1.r < 0.0:
			col.push_back(k0)
			col.push_back(k0)
			col.push_back(k0)
		else:
			col.push_back(k1)
			col.push_back(k2)
			col.push_back(k3)
		ix.push_back(s)
		ix.push_back(s + 2)
		ix.push_back(s + 1)
		ix.push_back(s)
		ix.push_back(s + 3)
		ix.push_back(s + 2)

	func mesh(m: Material) -> ArrayMesh:
		var am := ArrayMesh.new()
		if v.is_empty():
			return am
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_INDEX] = ix
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(0, m)
		return am

## Each picture's corners (bottom-left round to top-left) in the atlas, four ways: as it is, mirrored across, upside
## down, both ([pic * 4 + flip]); each tile's picture and whether it's drawn over the rock ([tile])
static var _uvc: Array[PackedVector2Array] = []
static var _tpic := PackedInt32Array()
static var _tover := PackedByteArray()
static var _tflip := PackedByteArray()      # 0: never mirrored, 1: across only, 3: across and upside down

static func _tables() -> void:
	if not _uvc.is_empty():
		return
	for p in MineTiles.COLS * 6:
		var r := MineTiles.uv(p)
		for f in 4:
			var u0 := r.position.x
			var u1 := r.end.x
			var v0 := r.position.y
			var v1 := r.end.y
			if f & 1:
				var tu := u0
				u0 = u1
				u1 = tu
			if f & 2:
				var tv := v0
				v0 = v1
				v1 = tv
			_uvc.append(PackedVector2Array([Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)]))
	_tpic.resize(64)
	_tover.resize(64)
	_tflip.resize(64)
	for t in MineTiles.INFO:
		_tpic[t] = int(MineTiles.INFO[t].pic)
		_tover[t] = 1 if MineTiles.INFO[t].over else 0
		var fl := 0
		if t <= MineTiles.BEDROCK or (t >= MineTiles.HARD1 and t <= MineTiles.DIAMOND) or t == MineTiles.FOOLS or t == MineTiles.HOARD:
			fl = 3
		if t == MineTiles.CRYSTAL:
			fl = 1
		_tflip[t] = fl

## The pictures a solid tile's face shows: [base, over]
func _pics(x: int, r: int) -> Vector2i:
	var t := at(x, r)
	if _tover[t]:
		return Vector2i(_tpic[base_at(x, r)], _tpic[t])
	return Vector2i(_tpic[t], MineTiles.PIC_NONE)

static func _hash(x: int, r: int) -> float:
	return float(absi((x * 73856093) ^ (r * 19349663)) % 1000) / 1000.0

## Open (dug or cave) for the corner shading: inside the ground and air (above the ground counts as not)
func _open(x: int, r: int) -> bool:
	return r >= 0 and x >= 0 and x < W and r < D and tiles[x + r * W] == MineTiles.AIR

func _build_chunk(c: Vector2i) -> void:
	_tables()
	var q := Quads.new()
	var x0 := c.x * CH
	var r0 := c.y * CH
	var x1 := mini(W, x0 + CH)
	var r1 := mini(D, r0 + CH)
	# the front faces' corner shading, once a corner: darker the more of the four tiles round it are open (a soft
	# shadow along the tunnels' edges)
	var cw := x1 - x0 + 1
	var ao := PackedFloat32Array()
	ao.resize(cw * (r1 - r0 + 1))
	for r in range(r0, r1 + 1):
		for x in range(x0, x1 + 1):
			var n := int(_open(x - 1, r - 1)) + int(_open(x, r - 1)) + int(_open(x - 1, r)) + int(_open(x, r))
			ao[(x - x0) + (r - r0) * cw] = 1.0 - 0.22 * n
	for r in range(r0, r1):
		for x in range(x0, x1):
			_tile_quads(q, x, r, ao, (x - x0) + (r - r0) * cw, cw)
	var mi: MeshInstance3D = _chunks.get(c)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_chunks[c] = mi
	mi.mesh = q.mesh(mat)

const _SIDES: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]

func _tile_quads(q: Quads, x: int, r: int, ao: PackedFloat32Array, ai: int, cw: int) -> void:
	var t := tiles[x + r * W]
	var x0 := float(x)
	var x1 := x0 + 1.0
	var y1 := float(-r)
	var y0 := y1 - 1.0
	var h := _hash(x, r)
	var shade := 1.0 - h * 0.1
	if t != MineTiles.AIR:
		var p0: int
		var p1: int
		if _tover[t]:
			p0 = _tpic[base[x + r * W]]
			p1 = _tpic[t]
		else:
			p0 = _tpic[t]
			p1 = MineTiles.PIC_NONE
		# the rock's picture mirrored at random (so it doesn't look tiled), darker in the corners by what's dug
		var fl := (int(h * 997.0) % 4) & (_tflip[t] & (3 if _tflip[base[x + r * W]] == 3 else 1))
		var a_bl := shade * ao[ai + cw]
		var a_br := shade * ao[ai + cw + 1]
		var a_tr := shade * ao[ai + 1]
		var a_tl := shade * ao[ai]
		q.quad(Vector3(x0, y0, 0.5), Vector3(x1, y0, 0.5), Vector3(x1, y1, 0.5), Vector3(x0, y1, 0.5), Vector3(0, 0, 1),
			p0, p1, Color(a_bl, a_bl, a_bl, h), fl, Color(a_br, a_br, a_br, h), Color(a_tr, a_tr, a_tr, h), Color(a_tl, a_tl, a_tl, h))
		if r == 0:
			q.quad(Vector3(x0, y1, 0.5), Vector3(x1, y1, 0.5), Vector3(x1, y1, -0.5), Vector3(x0, y1, -0.5), Vector3(0, 1, 0),
				MineTiles.PIC_GRASS if t != MineTiles.PAD else _tpic[MineTiles.PAD], MineTiles.PIC_NONE, Color(1, 1, 1, h))
		if t == MineTiles.LAVA:
			# lava's open faces glow too (its sides, into what's dug)
			for d in _SIDES:
				if d.y <= 0 and at(x + d.x, r + d.y) == MineTiles.AIR and r + d.y >= 0:
					_side(q, x, r, d, Vector2i(p0, p1), 0.95, h)
		return
	# open: the back wall ...
	var b := bg[x + r * W]
	var bp: int = MineTiles.BG_PIC.get(b, _tpic[base[x + r * W]])
	var bk := (0.24 if b == MineTiles.BG_EARTH else 0.7) * shade
	q.quad(Vector3(x0, y0, -0.5), Vector3(x1, y0, -0.5), Vector3(x1, y1, -0.5), Vector3(x0, y1, -0.5), Vector3(0, 0, 1),
		bp, MineTiles.PIC_NONE, Color(bk, bk, bk, h))
	# ... and the walls of the tunnel (the solid tiles round it, their faces into it)
	for d in _SIDES:
		if r + d.y < 0:
			continue
		var n := at(x + d.x, r + d.y)
		if n != MineTiles.AIR and n != MineTiles.LAVA:
			_side(q, x, r, d, _pics(x + d.x, r + d.y), 0.5 if d.y == 0 else (0.38 if d.y < 0 else 0.7), h)

## The wall between open tile (x, r) and its neighbour the way d goes, facing into the open tile.
func _side(q: Quads, x: int, r: int, d: Vector2i, pp: Vector2i, k: float, h: float) -> void:
	var x0 := float(x)
	var x1 := x0 + 1.0
	var y1 := float(-r)
	var y0 := y1 - 1.0
	var col := Color(k, k, k, h)
	if d.x == -1:
		q.quad(Vector3(x0, y0, 0.5), Vector3(x0, y0, -0.5), Vector3(x0, y1, -0.5), Vector3(x0, y1, 0.5), Vector3(1, 0, 0), pp.x, pp.y, col)
	elif d.x == 1:
		q.quad(Vector3(x1, y0, -0.5), Vector3(x1, y0, 0.5), Vector3(x1, y1, 0.5), Vector3(x1, y1, -0.5), Vector3(-1, 0, 0), pp.x, pp.y, col)
	elif d.y == -1:
		q.quad(Vector3(x0, y1, -0.5), Vector3(x1, y1, -0.5), Vector3(x1, y1, 0.5), Vector3(x0, y1, 0.5), Vector3(0, -1, 0), pp.x, pp.y, col)
	else:
		q.quad(Vector3(x0, y0, 0.5), Vector3(x1, y0, 0.5), Vector3(x1, y0, -0.5), Vector3(x0, y0, -0.5), Vector3(0, 1, 0), pp.x, pp.y, col)

## Bedrock past the edges and the bottom, grass on top of it past the edges (never changes).
func _margin() -> void:
	_tables()
	var q := Quads.new()
	var bp := int(MineTiles.info(MineTiles.BEDROCK).pic)
	var dp := int(MineTiles.info(MineTiles.DIRT).pic)
	for r in range(0, D + MARGIN):
		for x in range(-MARGIN, W + MARGIN):
			if x >= 0 and x < W and r < D:
				continue
			var h := _hash(x, r)
			var p := dp if r < 3 else bp
			var k := 1.0 - h * 0.1
			q.quad(Vector3(x, -r - 1, 0.5), Vector3(x + 1, -r - 1, 0.5), Vector3(x + 1, -r, 0.5), Vector3(x, -r, 0.5), Vector3(0, 0, 1), p, MineTiles.PIC_NONE, Color(k, k, k, h))
			if r == 0:
				q.quad(Vector3(x, 0, 0.5), Vector3(x + 1, 0, 0.5), Vector3(x + 1, 0, -0.5), Vector3(x, 0, -0.5), Vector3(0, 1, 0), MineTiles.PIC_GRASS, MineTiles.PIC_NONE, Color(1, 1, 1, h))
	var mi := MeshInstance3D.new()
	mi.mesh = q.mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_decor_root.add_child(mi)

## Things that stand about: mushrooms in the caves, the rival tunnels' props and lanterns.
func _dress() -> void:
	var stem := StandardMaterial3D.new()
	stem.albedo_color = Color8(230, 220, 200)
	var caps := []
	for h in [0.8, 0.9, 0.55, 0.15]:
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color.from_hsv(h, 0.75, 0.95)
		cm.emission_enabled = true
		cm.emission = Color.from_hsv(h, 0.8, 1.0)
		cm.emission_energy_multiplier = 0.9
		caps.append(cm)
	for m in features.get("mush", []):
		var x: int = m[0]
		var r: int = m[1]
		if at(x, r) != MineTiles.AIR or at(x, r + 1) == MineTiles.AIR:
			continue
		var n := Node3D.new()
		var k: float = m[2]
		var sz := 0.5 + k * 0.5
		n.position = Vector3(x + 0.5 + (k - 0.5) * 0.4, -r - 1.0, -0.15 + k * 0.3)
		var s := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.05 * sz
		cy.bottom_radius = 0.08 * sz
		cy.height = 0.45 * sz
		s.mesh = cy
		s.material_override = stem
		s.position.y = 0.225 * sz
		n.add_child(s)
		var c := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.24 * sz
		sp.height = 0.22 * sz
		c.mesh = sp
		c.material_override = caps[int(k * 97) % caps.size()]
		c.position.y = 0.46 * sz
		n.add_child(c)
		_decor_root.add_child(n)
		_on(idx(x, r + 1), n)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color8(120, 82, 46)
	for c in features.get("rival", []):
		# a prop each side of the tunnel under each timber lintel
		if at(c.x, c.y - 1) == MineTiles.TIMBER and at(c.x, c.y + 2) != MineTiles.AIR and at(c.x, c.y + 1) == MineTiles.AIR:
			for z in [-0.38, 0.38]:
				var p := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.14, 2.0, 0.14)
				p.mesh = bm
				p.material_override = wood
				p.position = Vector3(c.x + 0.5, -c.y - 1.0, z)
				_decor_root.add_child(p)
				_on(idx(c.x, c.y + 2), p)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color8(255, 200, 110)
	glass.emission_enabled = true
	glass.emission = Color8(255, 170, 70)
	glass.emission_energy_multiplier = 2.5
	for l in features.get("lanterns", []):
		var lm := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.14, 0.2, 0.14)
		lm.mesh = bm2
		lm.material_override = glass
		lm.position = Vector3(l.x, l.y, -0.3)
		_decor_root.add_child(lm)
		var lt := OmniLight3D.new()
		lt.light_color = Color8(255, 170, 80)
		lt.omni_range = 4.5
		lt.light_energy = 1.4
		lt.position = Vector3(0, 0, 0.5)
		lm.add_child(lt)
		var tr := tile_of(Vector2(l.x, l.y + 0.5))
		_on(idx(tr.x, tr.y), lm)

func _on(i: int, n: Node3D) -> void:
	if not _decor.has(i):
		_decor[i] = []
	_decor[i].append(n)
