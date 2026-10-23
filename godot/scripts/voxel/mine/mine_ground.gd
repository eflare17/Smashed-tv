class_name MineGround
extends Node3D
## The mine's ground (the owner, 23 Oct: "the graphics from my sand digging game ... every pixel destructible, really
## satisfying when drilling"): a pixel world (MineSim, the mine_sim GDExtension) of 8 cells a metre, 50 m across and
## 150 m down with 6 m of sky over it, made the same every time from a seed: topsoil and clay, grey stone, deep red
## rock, black basalt and glowing crystal rock (the zones' edges wavy), ores in little veins (coal near the top ..
## diamonds at the bottom, rarer and richer the deeper), sand that falls when it's undermined, pockets of water,
## boulders that need a better drill, gas pockets, lava pockets, little caves, the mushroom caves and the cathedral
## with its giant mushroom, the worm's cavern at the bottom, and the trial hazards (the sewers, the cop bunker, the
## rival dealers' tunnels) when they're switched on. Drawn as Sand Miner was: a window of cells round the camera
## painted each frame onto a quad at z = 0 in the mine's 3D world (lit by the ship's lamps and the caves' glow), the
## ship, the critters and the decor just in front of it. Positions here are in metres, x across, y up (the ground's
## top at y = 0); "depth" is metres down. Owned by the voxel session.

const W := 50                   # metres across (the outer metre each side bedrock)
const D := 150                  # metres down (the bottom metre bedrock)
const C := 8                    # cells a metre
const SKY := 48                 # cells of sky over the ground
const CW := W * C
const CH := D * C + SKY
const VIEW_W := 240             # the window of cells drawn round the camera
const VIEW_H := 144
const STEP_HZ := 60.0
## The buildings up top: [name, first metre, last metre] (concrete pads under them)
const BUILDINGS := [["lift", 3, 6], ["fuel", 9, 12], ["trader", 15, 19], ["mechanic", 22, 26]]

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform sampler2D albedo_tex : filter_nearest, source_color;
uniform sampler2D glow_tex : filter_nearest, source_color;
void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	EMISSION = texture(glow_tex, UV).rgb * 1.8;
}
"""

var sim: MineSim
var seed_ := 1
var flags := {"sewers": true, "cops": true, "rivals": true}
## where things are (metres; y as depth): "caves" [[cx, cy, rx, ry]], "cathedral" [cx, cy, rx, ry, stem x, floor],
## "bunker" [x0, d0, x1, d1], "sewer" [[x0, floor depth, x1]], "rival" [Vector2 tunnel spots (world)], "lanterns"
## [Vector2 world], "worm" [cx, cy, rx, ry], "lava" [Vector2 world], "mush" [Vector2 world floor spots]
var features := {}
var changed := 0                # cells changed since the last save
var keep_clear := Rect2i()      # (cells) the ship: nothing falls or flows into it, lava doesn't set round it
var frame := 0
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _img: Image
var _glow: Image
var _tex: ImageTexture
var _gtex: ImageTexture
var _step_acc := 0.0
var _decor_root: Node3D
var _decor: Array = []          # [Node3D, Vector2i the cell it stands on]
var _decor_t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	sim = MineSim.new()
	sim.setup(CW, CH, SKY)
	MineTiles.apply(sim)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_img = Image.create(VIEW_W, VIEW_H, false, Image.FORMAT_RGBA8)
	_glow = Image.create(VIEW_W, VIEW_H, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_gtex = ImageTexture.create_from_image(_glow)
	_mat.set_shader_parameter("albedo_tex", _tex)
	_mat.set_shader_parameter("glow_tex", _gtex)
	_quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(float(VIEW_W) / C, float(VIEW_H) / C)
	_quad.mesh = qm
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)

# ---------------------------------------------------------------- metres and cells

## The cell a world point's in
static func cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x * C), floori(-p.y * C) + SKY)

## A cell's middle in the world
static func world(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) / C, -((c.y + 0.5) - SKY) / C)

## The cells a box (world centre, half size) covers: Rect2i (cells)
static func cells_of(p: Vector2, half: Vector2) -> Rect2i:
	var x0 := floori((p.x - half.x) * C)
	var x1 := floori((p.x + half.x) * C - 0.001)
	var y0 := floori(-(p.y + half.y) * C) + SKY
	var y1 := floori(-(p.y - half.y) * C - 0.001) + SKY
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

## (old tile helpers, in metres: a 1 m square's middle and which one a point's in; x across, r metres down)
static func centre(x: int, r: int) -> Vector2:
	return Vector2(x + 0.5, -r - 0.5)

static func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(-p.y))

func mat_at(p: Vector2) -> int:
	var c := cell(p)
	return sim.get_cell(c.x, c.y)

func bg_at(p: Vector2) -> int:
	var c := cell(p)
	return sim.get_back(c.x, c.y)

## How many cells of a box are what (MineSim.count_rect's what: -1 what stops the ship, -2 loose, -3 liquid,
## -4 lava, -5 water, -6 empty, or a material)
func count(p: Vector2, half: Vector2, what: int) -> int:
	var r := cells_of(p, half)
	return sim.count_rect(r.position.x, r.position.y, r.size.x, r.size.y, what)

## Solid enough to stand on / bump into at a world point (one cell)
func solid_at(p: Vector2) -> bool:
	var c := cell(p)
	return sim.count_rect(c.x, c.y, 1, 1, -1) > 0

## A box of the world (centre, half size; metres) set to a material (AIR: dug out), its back wall kept
func set_box(p: Vector2, half: Vector2, m: int) -> void:
	var r := cells_of(p, half)
	sim.rect(r.position.x, r.position.y, r.end.x - 1, r.end.y - 1, m, -1, 0)

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

## cells of a depth (metres down)
static func dy(depth: float) -> float:
	return SKY + depth * C

func generate(s: int, fl: Dictionary) -> void:
	seed_ = s
	flags = fl.duplicate()
	_rng.seed = s
	sim.setup(CW, CH, SKY)
	MineTiles.apply(sim)
	features = {"caves": [], "sewer": [], "rival": [], "lanterns": [], "lava": [], "mush": []}
	var zb := PackedFloat32Array([6.0 * C, 19.0 * C, 50.0 * C, 86.0 * C, 121.0 * C])
	var zm := PackedInt32Array([MineTiles.DIRT, MineTiles.CLAY, MineTiles.STONE, MineTiles.RED, MineTiles.BASALT, MineTiles.CRYSTAL])
	var zbk := PackedInt32Array([1, 2, 3, 4, 5, 6])
	sim.fill_zones(s, zb, zm, zbk, 3.5 * C)
	# ores: [material, veins, first metre, last metre, the metre they're most at, smallest, biggest (cells)]
	var ores := [[MineTiles.COAL, 70, 3, 62, 16, 2.0, 4.2], [MineTiles.COPPER, 56, 10, 96, 38, 2.0, 4.0],
		[MineTiles.SILVER, 46, 28, 126, 64, 1.8, 3.6], [MineTiles.GOLD, 38, 52, 148, 94, 1.8, 3.4],
		[MineTiles.OPAL, 28, 78, 148, 118, 1.6, 3.0], [MineTiles.DIAMOND, 24, 100, 148, 140, 1.5, 2.8]]
	for o in ores:
		sim.scatter(int(o[0]), int(o[1]), int(dy(o[2])), int(dy(o[3])), int(dy(o[4])), float(o[5]), float(o[6]), s + int(o[0]) * 31, 1)
	# sand lenses that pour when they're undermined
	for k in 14:
		sim.blob(_rng.randf_range(3, W - 3) * C, dy(_rng.randf_range(3, 45)), _rng.randf_range(6, 14), _rng.randf_range(3, 6), MineTiles.SAND, 0.5, s + 400 + k, 1, -1)
	# boulders
	for band in [[20, 60, 50, [MineTiles.HARD1]], [60, 100, 40, [MineTiles.HARD1, MineTiles.HARD2]], [100, 128, 32, [MineTiles.HARD2, MineTiles.HARD2, MineTiles.HARD3]], [128, 148, 26, [MineTiles.HARD3, MineTiles.HARD2]]]:
		for k in int(band[2]):
			var kinds: Array = band[3]
			var r := _rng.randf_range(3.0, 6.0)
			sim.blob(_rng.randf_range(2, W - 2) * C, dy(_rng.randf_range(band[0], band[1])), r * _rng.randf_range(0.8, 1.3), r, int(kinds[_rng.randi() % kinds.size()]), 0.5, s + 600 + k, 1, -1)
	# gas pockets
	for k in 46:
		sim.blob(_rng.randf_range(2, W - 2) * C, dy(_rng.randf_range(25, 145)), _rng.randf_range(2.0, 4.0), _rng.randf_range(1.6, 3.0), MineTiles.GAS, 0.5, s + 900 + k, 1, -1)
	# little caves, and pockets of water
	for k in 16:
		var x := _rng.randf_range(4, W - 4)
		var d := _rng.randf_range(14, D - 6)
		for st in _rng.randi_range(4, 9):
			sim.blob(x * C, dy(d), _rng.randf_range(4, 8), _rng.randf_range(3, 6), MineTiles.AIR, 0.4, s + 1000 + k * 10 + st, 0, -1)
			x = clampf(x + _rng.randf_range(-1.2, 1.2), 3, W - 3)
			d = clampf(d + _rng.randf_range(-0.6, 0.6), 12, D - 3)
	for k in 8:
		var x := _rng.randf_range(6, W - 6) * C
		var d := dy(_rng.randf_range(12, 70))
		var rx := _rng.randf_range(9, 16)
		var ry := _rng.randf_range(6, 10)
		sim.blob(x, d, rx, ry, MineTiles.AIR, 0.3, s + 1300 + k, 0, -1)
		sim.fill_liquid(x, d, rx, ry, MineTiles.WATER, 0.45)
	_mush_caves()
	_cathedral()
	if flags.get("sewers", true):
		_sewers()
	if flags.get("cops", true):
		_bunker()
	if flags.get("rivals", true):
		_rivals()
	_lava_pockets()
	_worm_cavern()
	# the edges and the bottom, the pads under the buildings
	sim.rect(0, SKY, C - 1, CH - 1, MineTiles.BEDROCK, -1, 0)
	sim.rect(CW - C, SKY, CW - 1, CH - 1, MineTiles.BEDROCK, -1, 0)
	sim.rect(0, CH - C, CW - 1, CH - 1, MineTiles.BEDROCK, -1, 0)
	for b in BUILDINGS:
		sim.rect(int(b[1]) * C, SKY, (int(b[2]) + 1) * C - 1, SKY + 3, MineTiles.PAD, 1, 0)
	sim.take_changed()
	changed = 0

func _carve(cx: float, depth: float, rx: float, ry: float, bg: int, rough := 0.3) -> void:
	sim.blob(cx * C, dy(depth), rx * C, ry * C, MineTiles.AIR, rough, _rng.randi() % 100000, 0, bg)

## A world spot on the floor of the open space near (cx, depth) (or Vector2.INF)
func _floor_spot(x: float, depth_from: float, depth_to: float) -> Vector2:
	var cx := int(x * C)
	for y in range(int(dy(depth_from)), int(dy(depth_to))):
		if sim.get_cell(cx, y) == 0 and sim.count_rect(cx, y + 1, 1, 1, -1) > 0:
			return world(Vector2i(cx, y)) + Vector2(0, -0.5 / C)
	return Vector2.INF

func _mush_caves() -> void:
	var depths := [32, 47, 63, 79, 96]
	for k in depths.size():
		var cy := float(depths[k] + _rng.randi_range(-3, 3))
		var cx := _rng.randf_range(8.0, W - 9.0)
		var rx := _rng.randf_range(4.5, 6.5)
		var ry := _rng.randf_range(2.6, 3.4)
		_carve(cx, cy, rx, ry, MineTiles.BG_MUSH, 0.35)
		features.caves.append([cx, cy, rx, ry])
		_dress(cx, cy, rx, ry, 0.4)

## A mushroom cave's floor dressed: spore clumps and mushrooms on it, fool's gold in its walls
func _dress(cx: float, cy: float, rx: float, ry: float, spore_k: float) -> void:
	var x := cx - rx + 0.6
	while x < cx + rx - 0.6:
		var f := _floor_spot(x, cy - ry, cy + ry + 1.0)
		if f != Vector2.INF:
			if _rng.randf() < spore_k * 0.5:
				var c := cell(f)
				sim.blob(c.x, c.y - 1, _rng.randf_range(2.0, 3.5), _rng.randf_range(1.5, 2.5), MineTiles.SPORE, 0.4, _rng.randi() % 100000, 2, -1)
			else:
				features.mush.append(f)
		x += _rng.randf_range(0.5, 1.1)
	# fool's gold in the walls round it
	for k in 7:
		var a := _rng.randf() * TAU
		var p := Vector2(cx + cos(a) * (rx + 0.3), cy + sin(a) * (ry + 0.3))
		sim.blob(p.x * C, dy(p.y), _rng.randf_range(2.0, 3.5), _rng.randf_range(1.5, 3.0), MineTiles.FOOLS, 0.5, _rng.randi() % 100000, 1, -1)

func _cathedral() -> void:
	var cx := float(W / 2 + _rng.randi_range(-8, 8))
	var cy := 113.0 + _rng.randi_range(-2, 2)
	var rx := 10.0
	var ry := 6.5
	_carve(cx, cy, rx, ry, MineTiles.BG_CATHEDRAL, 0.15)
	# its floor under the middle
	var fl := cy
	var f := _floor_spot(cx, cy - 1.0, cy + ry + 1.0)
	if f != Vector2.INF:
		fl = -f.y
	# the giant mushroom: a stem two metres wide and five tall, a domed cap nine wide on it, white spots
	var sx := int(cx * C)
	var base := int(dy(fl))
	sim.rect(sx - C, base - 5 * C, sx + C, base, MineTiles.SHROOM, MineTiles.BG_CATHEDRAL, 0)
	sim.blob(sx, base - 5 * C, 4.5 * C, 2.6 * C, MineTiles.SHROOM, 0.05, 77, 0, -1)
	sim.rect(sx - 5 * C, base - 5 * C, sx + 5 * C, base - 5 * C + C, MineTiles.AIR, MineTiles.BG_CATHEDRAL, 0)
	sim.rect(sx - C, base - 5 * C, sx + C, base - 5 * C + C, MineTiles.SHROOM, MineTiles.BG_CATHEDRAL, 0)
	features["cathedral"] = [cx, cy, rx, ry, cx - 1.0, fl]
	_dress(cx, cy, rx, ry, 0.5)

func _sewers() -> void:
	for s in [[5.0, 7.0, 41.0], [9.0, 3.0, 27.0]]:
		var r: float = s[0]
		var x0: float = s[1] + _rng.randf_range(-1, 1)
		var x1: float = s[2] + _rng.randf_range(-1, 1)
		# a brick tube: two metres inside, half a metre of brick round it
		sim.rect(int((x0 - 0.5) * C), int(dy(r - 2.5)), int((x1 + 0.5) * C), int(dy(r + 0.5)), MineTiles.BRICK, MineTiles.BG_SEWER, 1)
		sim.rect(int(x0 * C), int(dy(r - 2.0)), int(x1 * C), int(dy(r)) - 1, MineTiles.AIR, MineTiles.BG_SEWER, 0)
		# junk set in its walls and floor
		for k in 9:
			var jx := _rng.randf_range(x0, x1)
			var jd := r + 0.25 if _rng.randf() < 0.6 else r - 2.25
			sim.blob(jx * C, dy(jd), _rng.randf_range(2.0, 3.5), 2.0, MineTiles.JUNK, 0.3, _rng.randi() % 100000, 0, -1)
		features.sewer.append([x0, r, x1])

func _bunker() -> void:
	# somewhere clear of the mushroom caves
	var x0 := _rng.randf_range(14, W - 20)
	var d0 := _rng.randf_range(40, 44)
	for k in 40:
		var clear := true
		for c in features.caves:
			if Rect2(x0 - 2, d0 - 2, 20, 12).intersects(Rect2(c[0] - c[2], c[1] - c[3], c[2] * 2, c[3] * 2)):
				clear = false
		if clear:
			break
		x0 = _rng.randf_range(3, W - 20)
		d0 = _rng.randf_range(36, 54)
	var x1 := x0 + 16.0
	var d1 := d0 + 8.0
	sim.rect(int(x0 * C), int(dy(d0)), int(x1 * C), int(dy(d1)), MineTiles.CONCRETE, MineTiles.BG_BUNKER, 5)
	sim.rect(int((x0 + 1) * C), int(dy(d0 + 1)), int((x1 - 1) * C), int(dy(d1 - 1)) - 1, MineTiles.AIR, MineTiles.BG_BUNKER, 0)
	# a wall across the middle with a door in it
	var mx := (x0 + x1) * 0.5
	sim.rect(int(mx * C) - 3, int(dy(d0 + 1)), int(mx * C) + 3, int(dy(d1 - 3.2)), MineTiles.CONCRETE, MineTiles.BG_BUNKER, 5)
	# evidence lockers on its floor
	for k in 5:
		var lx := _rng.randf_range(x0 + 1.5, x1 - 2.5)
		if absf(lx - mx) < 1.2:
			continue
		sim.rect(int(lx * C), int(dy(d1 - 2)), int(lx * C) + C - 1, int(dy(d1 - 1)) - 1, MineTiles.EVIDENCE, MineTiles.BG_BUNKER, 2)
	# cracks (weak spots of plain stone) the lights show through
	for k in 4:
		var side := _rng.randi_range(0, 2)
		var cx := _rng.randf_range(x0 + 2, x1 - 2) if side < 2 else (x0 + 0.5 if _rng.randf() < 0.5 else x1 - 0.5)
		var cd := d0 + 0.5 if side == 0 else (d1 - 0.5 if side == 1 else _rng.randf_range(d0 + 2, d1 - 2))
		sim.blob(cx * C, dy(cd), 3.5, 3.0, MineTiles.STONE, 0.6, _rng.randi() % 100000, 0, -1)
	features["bunker"] = [x0, d0, x1, d1]

func _rivals() -> void:
	var d := _rng.randf_range(70, 74)
	var x := 3.0
	var spots := []
	while x < W - 3:
		sim.blob(x * C, dy(d), 0.7 * C, 1.05 * C, MineTiles.AIR, 0.15, _rng.randi() % 100000, 0, MineTiles.BG_RIVAL)
		spots.append(Vector2(x, -d - 0.3))
		if int(x * 2) % 10 == 0:
			sim.rect(int((x - 0.3) * C), int(dy(d - 1.4)), int((x + 0.3) * C), int(dy(d - 0.95)), MineTiles.TIMBER, MineTiles.BG_RIVAL, 4)
		if int(x * 2) % 18 == 8:
			features.lanterns.append(Vector2(x, -d + 0.7))
		x += 0.5
		if _rng.randf() < 0.06:
			d = clampf(d + _rng.randf_range(-0.8, 0.8), 66, 84)
	var ends := [Vector2(3.5, d), Vector2(W - 3.5, d)]
	ends[0] = Vector2(3.5, -float(spots[0].y) - 0.3)
	# a branch down to a dead end
	var bx := _rng.randf_range(12, W - 12)
	var bd := -float(spots[int((bx - 3.0) * 2.0) % spots.size()].y) - 0.3
	for k in 16:
		sim.blob(bx * C, dy(bd + k * 0.5), 0.6 * C, 0.6 * C, MineTiles.AIR, 0.1, _rng.randi() % 100000, 0, MineTiles.BG_RIVAL)
		spots.append(Vector2(bx, -(bd + k * 0.5)))
	ends.append(Vector2(bx, bd + 8.5))
	# their stockpiles: crates at the ends
	for e in ends:
		for k in 2:
			var sx: float = clampf(e.x + _rng.randf_range(-0.8, 0.8), 1.5, W - 2.5)
			sim.rect(int(sx * C) - 3, int(dy(e.y + 0.4)), int(sx * C) + 4, int(dy(e.y + 1.2)), MineTiles.STASH, MineTiles.BG_RIVAL, 3)
	# their shortcut: a shaft up from the tunnel to just under the topsoil, capped with timber (not through the bunker)
	var sx2 := _rng.randf_range(30, W - 6)
	var bk: Array = features.get("bunker", [])
	if not bk.is_empty() and sx2 > float(bk[0]) - 1.5 and sx2 < float(bk[2]) + 1.5:
		sx2 = float(bk[0]) - 2.5 if float(bk[0]) - 2.5 >= 3.0 else float(bk[2]) + 2.5
	var top := d
	for sp in spots:
		if absf(sp.x - sx2) < 0.3:
			top = minf(top, -sp.y)
	sim.rect(int((sx2 - 0.55) * C), int(dy(12)), int((sx2 + 0.55) * C), int(dy(top)), MineTiles.AIR, MineTiles.BG_RIVAL, 0)
	sim.rect(int((sx2 - 0.55) * C), int(dy(10)), int((sx2 + 0.55) * C), int(dy(12)) - 1, MineTiles.TIMBER, MineTiles.BG_RIVAL, 4)
	for k in int(top - 12.0):
		spots.append(Vector2(sx2, -(12.5 + k)))
	features["shortcut"] = [sx2, 12, top]
	features.rival = spots

func _lava_pockets() -> void:
	var made := 0
	var tries := 0
	while made < 10 and tries < 200:
		tries += 1
		var cx := _rng.randf_range(4.0, W - 5.0)
		var cd := _rng.randf_range(70.0, D - 5.0)
		var rx := _rng.randf_range(1.4, 3.0)
		var ry := _rng.randf_range(1.0, 2.0)
		# not in a cave, a tunnel, the cathedral (an open back wall that isn't the earth's)
		var ok := true
		for t in 12:
			var p := Vector2(cx + _rng.randf_range(-rx - 1, rx + 1), cd + _rng.randf_range(-ry - 1, ry + 1))
			var c := cell(Vector2(p.x, -p.y))
			if sim.get_back(c.x, c.y) >= MineTiles.BG_MUSH or sim.get_cell(c.x, c.y) == 0:
				ok = false
		if not ok:
			continue
		_carve(cx, cd, rx, ry, -1, 0.2)
		sim.fill_liquid(cx * C, dy(cd), rx * C + 1, ry * C + 1, MineTiles.LAVA, 0.0)
		features.lava.append(Vector2(cx, -cd))
		made += 1

func _worm_cavern() -> void:
	var cx := float(W / 2 + _rng.randi_range(-6, 6))
	var cy := 141.5
	_carve(cx, cy, 11.0, 4.5, MineTiles.BG_WORM, 0.3)
	features["worm"] = [cx, cy, 11.0, 4.5]

# ---------------------------------------------------------------- saving

## The ground as bytes (its seed, its switches, and every cell, packed small)
func save_bytes() -> PackedByteArray:
	var raw := sim.get_raw()
	var head := JSON.stringify({"seed": seed_, "flags": flags, "n": raw.size(), "v": 2}).to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, head.size())
	out.append_array(head)
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out

## The ground from bytes: made from its seed again (its features, the same every time), then the cells as they were.
func load_bytes(b: PackedByteArray) -> bool:
	if b.size() < 8:
		return false
	var hn := b.decode_u32(0)
	if hn <= 0 or 4 + hn > b.size():
		return false
	var head = JSON.parse_string(b.slice(4, 4 + hn).get_string_from_utf8())
	if typeof(head) != TYPE_DICTIONARY or int(head.get("v", 0)) != 2:
		return false
	generate(int(head.get("seed", 1)), head.get("flags", flags) if typeof(head.get("flags")) == TYPE_DICTIONARY else flags)
	var raw := b.slice(4 + hn).decompress(int(head.get("n", 0)), FileAccess.COMPRESSION_ZSTD)
	if not sim.set_raw(raw):
		return false
	sim.take_changed()
	changed = 0
	return true

# ---------------------------------------------------------------- each frame

## The world moving (the mine calls it while you're down there): the sand, water and lava, the chips flying.
func tick(dt: float) -> void:
	sim.set_block(keep_clear.position.x, keep_clear.position.y, keep_clear.size.x, keep_clear.size.y)
	_step_acc = minf(_step_acc + dt, 3.0 / STEP_HZ)
	while _step_acc >= 1.0 / STEP_HZ:
		_step_acc -= 1.0 / STEP_HZ
		sim.step()
	changed += sim.take_changed()
	_decor_t -= dt
	if _decor_t <= 0.0:
		_decor_t = 0.4
		# decor whose floor's gone, gone
		for i in range(_decor.size() - 1, -1, -1):
			var c: Vector2i = _decor[i][1]
			if sim.count_rect(c.x, c.y, 1, 1, -1) == 0:
				if is_instance_valid(_decor[i][0]):
					(_decor[i][0] as Node).queue_free()
				_decor.remove_at(i)

## The window of cells round a world point drawn onto the quad
func view(at: Vector2) -> void:
	frame += 1
	var c := cell(at)
	var x0 := c.x - VIEW_W / 2
	var y0 := c.y - VIEW_H / 2
	var out: Array = sim.paint(x0, y0, VIEW_W, VIEW_H, frame)
	_img.set_data(VIEW_W, VIEW_H, false, Image.FORMAT_RGBA8, out[0])
	_glow.set_data(VIEW_W, VIEW_H, false, Image.FORMAT_RGBA8, out[1])
	_tex.update(_img)
	_gtex.update(_glow)
	_quad.position = Vector3(float(x0 + VIEW_W / 2) / C, -float(y0 + VIEW_H / 2 - SKY) / C, 0.0)

## Everything drawn from scratch (a new ground or a loaded one): the decor put in.
func build_all() -> void:
	if _decor_root:
		_decor_root.queue_free()
	_decor_root = Node3D.new()
	add_child(_decor_root)
	_decor.clear()
	_dress_nodes()

## Mushrooms on the caves' floors, the rival tunnels' props and lanterns
func _dress_nodes() -> void:
	var stem := StandardMaterial3D.new()
	stem.albedo_color = Color8(230, 220, 200)
	var caps := []
	for hue in [0.8, 0.9, 0.55, 0.15]:
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color.from_hsv(hue, 0.75, 0.95)
		cm.emission_enabled = true
		cm.emission = Color.from_hsv(hue, 0.8, 1.0)
		cm.emission_energy_multiplier = 0.9
		caps.append(cm)
	var k := 0
	for f in features.get("mush", []):
		var p: Vector2 = f
		var c := cell(p + Vector2(0, -0.1))
		if sim.get_cell(c.x, c.y - 1) != 0:
			continue
		k += 1
		var sz := 0.45 + float(k * 37 % 10) / 18.0
		var n := Node3D.new()
		n.position = Vector3(p.x, p.y, 0.2 + float(k % 3) * 0.05)
		var s := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.05 * sz
		cy.bottom_radius = 0.08 * sz
		cy.height = 0.45 * sz
		s.mesh = cy
		s.material_override = stem
		s.position.y = 0.225 * sz
		n.add_child(s)
		var cap := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.24 * sz
		sp.height = 0.22 * sz
		cap.mesh = sp
		cap.material_override = caps[k % caps.size()]
		cap.position.y = 0.46 * sz
		n.add_child(cap)
		_decor_root.add_child(n)
		_decor.append([n, cell(p + Vector2(0, -0.08))])
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color8(120, 82, 46)
	var spots: Array = features.get("rival", [])
	for i in range(0, spots.size(), 10):
		var p: Vector2 = spots[i]
		var floor_c := cell(p + Vector2(0, -1.05))
		if sim.count_rect(floor_c.x, floor_c.y, 1, 1, -1) == 0:
			continue
		for z in [-0.1, 0.25]:
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 2.0, 0.1)
			post.mesh = bm
			post.material_override = wood
			post.position = Vector3(p.x + (0.6 if z > 0.0 else -0.6), p.y - 0.05, z)
			_decor_root.add_child(post)
			_decor.append([post, floor_c])
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color8(255, 200, 110)
	glass.emission_enabled = true
	glass.emission = Color8(255, 170, 70)
	glass.emission_energy_multiplier = 2.5
	for l in features.get("lanterns", []):
		var p: Vector2 = l
		var lm := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.14, 0.2, 0.14)
		lm.mesh = bm2
		lm.material_override = glass
		lm.position = Vector3(p.x, p.y, 0.2)
		_decor_root.add_child(lm)
		var lt := OmniLight3D.new()
		lt.light_color = Color8(255, 170, 80)
		lt.omni_range = 4.5
		lt.light_energy = 1.4
		lt.position = Vector3(0, 0, 0.6)
		lm.add_child(lt)
		_decor.append([lm, cell(p + Vector2(0, 0.2))])
