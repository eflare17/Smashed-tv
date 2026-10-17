class_name WorldBuilder
extends Node3D
## CONTRACT. Builds the lobby, bedroom and yard (floors, walls, solids, props) with collision, from
## GameData.data. Owned by the World task.
##
## Everything is laid out in the HTML game's units (x across, y down the screen, z up) and turned into Godot's
## space at the edge (GameData.world_to_3d: 1 unit = 0.025 m). What's where:
## - Floors: the lounge picture inside the lounge's walls, the bedroom picture on the bedroom, the yard picture
##   under the rest (each solid's spread-out art painted over, as the HTML game's first person does), the props'
##   shadows printed on the floors, grass beyond. The pool is a hole with its water a little below the floor.
## - The house: its walls (ARENA.wall thick, SHROOM_WALL tall) with the bedroom doorway and the back door cut
##   through (a lintel over each), painted inside, weatherboards outside; a ceiling indoors and the hipped roof
##   (wearing the roof from the yard picture). Seen from above (the top-down view) the roof and ceiling go and the
##   walls are cut down to low strips, as the HTML game draws them there (cutaway).
## - Every solid of the yard at its height, its sides in the HTML game's first-person materials, its top its piece
##   of the yard picture; gable roofs on the garage and the shed; the ute in three blocks; the trampoline and the
##   water tank round. The yard's edges are fences (FENCE_H). From above (cutaway) they aren't stood up: the yard
##   picture shows them there as the HTML game's top-down view does (FullMesh / CutMesh), so nothing tall hides
##   the player; their collision stays the same. (The esky, which isn't in the picture, stands in both.)
## - The lounge's furniture and machines as upright cut-outs of the HTML game's own art (scripts/world/props/,
##   captured from its drawing functions; the tower, the slot machine and the wardrobe from assets/), standing on
##   their feet, leaning back to lie flat as the camera looks down so the top-down view shows them as drawn.
## - Collision: one StaticBody3D for the walls and fences, one per solid (named Solid_<name>). Solids' shapes are
##   inset so a player capsule of radius player_radius stops where the HTML game stops him (it lets him half his
##   radius into furniture, a unit off the water, 0.7 of it into the tower).

const GD := preload("res://scripts/game_data.gd")
const WT := preload("res://scripts/world/world_tex.gd")
const U := GD.UNIT

## The visual layer (number, as in the editor; its bit is 1 << (ROOF_LAYER - 1)) the house at full height (its
## walls, lintels, ceiling and roof: FullMesh) is on, and CUT_LAYER the house's walls cut down low (CutMesh). By
## default the World shows one or the other by how steeply the camera in use looks down (cutaway), so nothing
## else needs to know; a camera can also leave one out of its cull_mask (top_down_cull_mask(), fp_cull_mask()).
const ROOF_LAYER := 2
const CUT_LAYER := 3
## Surface groups (_st).
const G_ALL := 0
const G_FULL := 1
const G_CUT := 2
## The sun's to the north: how lit each side is, by the way it looks (FP_LIT).
const LIT := {"N": 1.0, "E": 0.9, "W": 0.9, "S": 0.76}
const WALL_TOP := Color8(16, 18, 24)
const CEILING := Color8(78, 75, 70)
const GRASS := Color8(82, 136, 52)
## Heights (units) of the lounge's and bedroom's furniture, which the HTML game draws but never measures up.
const FURNITURE_H := {"table": 30, "bench": 40, "rack": 64, "legpress": 60, "wardrobe": 96, "bed": 20, "nightstand": 26,
	"mirror": 92, "cab_miner": 104, "cab_bricks": 104, "slot": 124, "tower": 121, "pool": 0}

## The player's collision radius, in HTML units (T.radius); solids are inset to suit it. Set before build().
@export var player_radius: float = 14.0
## Add a WorldEnvironment (sky, the HTML game's distance haze). Off if main brings its own.
@export var make_environment: bool = true
## Build the trampoline's frame, mat and net (and its collision, tramp_body). Off if the trampoline task builds it.
@export var include_trampoline: bool = true
## The house seen from above: -1 (auto) cuts its walls down to cutaway_height and leaves off its roof and ceiling
## whenever the camera in use looks down more steeply than cutaway_pitch_deg (the top-down view: the HTML game
## draws its walls as flat strips there), and shows it whole otherwise (first person, which looks at most 34
## degrees down). 0: always whole. 1: always cut.
@export var cutaway: int = -1
@export var cutaway_pitch_deg: float = 45.0
## How high (units) the house's walls stand when cut away.
@export var cutaway_height: float = 18.0

## What later parts may want: the cut-outs by name ("tower", "bench", "rack", "legpress", "table", "rope",
## "cab_miner", "cab_bricks", "slot", "wardrobe", "mirror"), each a MeshInstance3D standing at its feet.
var props: Dictionary = {}
## The solids' bodies by name ("table", "bbq", "garage", "tramp", "pool"...).
var solids: Dictionary = {}
## The trampoline's body (a cylinder r × h): the trampoline adds a collision exception for whoever's on it.
var tramp_body: StaticBody3D
## The pool's water surface (a MeshInstance3D), for whoever makes it ripple.
var pool_water: MeshInstance3D
## The environment it made (make_environment): the sky and the haze. The haze is for first person; a camera high
## over the yard may want it off (environment.fog_enabled), or a Camera3D.environment of its own.
var environment: Environment

var _sts: Dictionary = {}          # surface key -> [SurfaceTool, Material, group (G_*)]
var _cur_group := G_ALL            # the group _st puts G_ALL surfaces in (the yard's solids: G_FULL)
var _yard_orig: Image              # the yard picture as it is (its solids not painted out), for the view from above
var _tex_cache: Dictionary = {}
var _walls_body: StaticBody3D
var _yard_tex: ImageTexture
var _yard_ox := 0.0
var _yard_oy := 0.0
var _yard_size := Vector2(2048, 2048)
var _lounge_tex: ImageTexture
var _bed_tex: ImageTexture

# ---------------------------------------------------------------- the contract

## Build everything as children of this node.
func build() -> void:
	var t0 := Time.get_ticks_msec()
	_walls_body = StaticBody3D.new()
	_walls_body.name = "Walls"
	add_child(_walls_body)
	var ground := StaticBody3D.new()   # the ground everywhere (the pool's water is a solid of its own)
	ground.name = "Ground"
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	add_child(ground)
	var steps := [_floors, _house, _lounge_solids, _yard_solids, _yard_fences, _yard_flat, _props, _commit]
	var times := []
	for f in steps:
		var t1 := Time.get_ticks_msec()
		f.call()
		times.append("%s %d" % [f.get_method(), Time.get_ticks_msec() - t1])
	print("WorldBuilder: ", ", ".join(times))
	if make_environment:
		_environment()
	print("WorldBuilder: built in %d ms" % (Time.get_ticks_msec() - t0))

## The solid boxes on the ground, in HTML units: [{x0, y0, x1, y1, h}], for walking round things
## (Gothica uses it). Each also has "m" (what it is); the round ones (the trampoline, the tank) are their
## bounding boxes with cx, cy, r as well; the pool is the water (h 0).
func ground_boxes() -> Array:
	var out: Array = []
	for b in _lounge_boxes():
		out.append(b.duplicate())
	for s in GameData.data.get("YARD_SOLIDS", []):
		var b: Dictionary = {}
		if s.has("r"):
			b = {"x0": s.cx - s.r, "y0": s.cy - s.r, "x1": s.cx + s.r, "y1": s.cy + s.r, "cx": s.cx, "cy": s.cy, "r": s.r}
		else:
			b = {"x0": s.x0, "y0": s.y0, "x1": s.x1, "y1": s.y1}
		b["h"] = s.h
		b["m"] = s.m
		out.append(b)
	return out

## The cull mask for a top-down camera: everything but the house at full height (its walls, ceiling and roof).
static func top_down_cull_mask() -> int:
	return 0xFFFFF & ~(1 << (ROOF_LAYER - 1))

## The cull mask for a first-person camera: everything but the house's cut-down walls.
static func fp_cull_mask() -> int:
	return 0xFFFFF & ~(1 << (CUT_LAYER - 1))

# ---------------------------------------------------------------- helpers

static func P(x: float, y: float, z: float = 0.0) -> Vector3:
	return Vector3(x * U, z * U, y * U)

func _d() -> Dictionary:
	return GameData.data

func _T(k: String, def: float = 0.0) -> float:
	return float(_d().get("T", {}).get(k, def))

## A material: a picture (or a plain colour), unshaded, nearest, the vertex colour as light.
func _mat(tex: Texture2D, col: Color = Color.WHITE, alpha: int = 0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = col
	if tex:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if alpha == 1:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	elif alpha == 2:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

## The SurfaceTool collecting everything drawn with one material in one group (made the first time it's asked for).
## group: G_ALL (always drawn), G_FULL (the house at full height, its ceiling and roof: not from above), G_CUT
## (the house's walls cut down low: only from above).
func _st(key: String, make: Callable, group: int = G_ALL) -> SurfaceTool:
	if group == G_ALL:
		group = _cur_group
	key += "#%d" % group
	if not _sts.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_sts[key] = [st, make.call(), group]
	return _sts[key][0]

func _col_st(c: Color, group: int = G_ALL) -> SurfaceTool:
	return _st("col_" + c.to_html(), func(): return _mat(null, c), group)

func _tri(st: SurfaceTool, p: Array, uv: Array, col: Color) -> void:
	for i in 3:
		st.set_color(col)
		st.set_uv(uv[i])
		st.add_vertex(p[i])

func _quad(st: SurfaceTool, p: Array, uv: Array, col: Color) -> void:
	_tri(st, [p[0], p[1], p[2]], [uv[0], uv[1], uv[2]], col)
	_tri(st, [p[0], p[2], p[3]], [uv[0], uv[2], uv[3]], col)

## A flat rectangle at height z, its picture by uvf(x, y) -> Vector2.
func _flat(st: SurfaceTool, x0: float, y0: float, x1: float, y1: float, z: float, uvf: Callable, col: Color = Color.WHITE) -> void:
	_quad(st, [P(x0, y0, z), P(x1, y0, z), P(x1, y1, z), P(x0, y1, z)],
		[uvf.call(x0, y0), uvf.call(x1, y0), uvf.call(x1, y1), uvf.call(x0, y1)], col)

func _no_uv(_x: float, _y: float) -> Vector2:
	return Vector2.ZERO

## A wall face: the vertical rectangle along one side of a box, from (ax, ay) to (bx, by), z0 to z1. face: the
## way it looks (N, E, S, W). uvf(u, z) -> Vector2, u being along the face in world units (x for N/S, y for E/W).
func _side(st: SurfaceTool, ax: float, ay: float, bx: float, by: float, z0: float, z1: float, face: String, uvf: Callable) -> void:
	var ua := ax if face == "N" or face == "S" else ay
	var ub := bx if face == "N" or face == "S" else by
	_quad(st, [P(ax, ay, z0), P(bx, by, z0), P(bx, by, z1), P(ax, ay, z1)],
		[uvf.call(ua, z0), uvf.call(ub, z0), uvf.call(ub, z1), uvf.call(ua, z1)], Color(LIT[face], LIT[face], LIT[face]))

## The four sides of box b (x0..x1, y0..y1) from z0 to z1, each by side_st(face) -> [SurfaceTool, uvf] (or null: skip).
func _box_sides(b: Dictionary, z0: float, z1: float, side_st: Callable) -> void:
	var x0: float = b.x0
	var x1: float = b.x1
	var y0: float = b.y0
	var y1: float = b.y1
	for f in [["N", x0, y0, x1, y0], ["S", x0, y1, x1, y1], ["W", x0, y0, x0, y1], ["E", x1, y0, x1, y1]]:
		var r = side_st.call(f[0])
		if r == null:
			continue
		_side(r[0], f[1], f[2], f[3], f[4], z0, z1, f[0], r[1])

## A collision box (x0..x1, y0..y1, z0..z1 in units) on body, shrunk by inset on the ground.
func _coll_box(body: StaticBody3D, b: Dictionary, z0: float, z1: float, inset: float = 0.0) -> void:
	var x0: float = float(b.x0) + inset
	var x1: float = float(b.x1) - inset
	var y0: float = float(b.y0) + inset
	var y1: float = float(b.y1) - inset
	if x1 - x0 < 1:
		x0 = (float(b.x0) + float(b.x1)) / 2 - 0.5; x1 = x0 + 1
	if y1 - y0 < 1:
		y0 = (float(b.y0) + float(b.y1)) / 2 - 0.5; y1 = y0 + 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3((x1 - x0) * U, (z1 - z0) * U, (y1 - y0) * U)
	cs.shape = bs
	cs.position = P((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	body.add_child(cs)

func _body(name_: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Solid_" + name_
	add_child(body)
	solids[name_] = body
	return body

## A picture from the manifest as an Image (RGBA8), or null.
func _img(key_or_path: String) -> Image:
	var v = GameData.manifest.get(key_or_path, key_or_path)
	if v is Array:
		v = v[0] if v.size() > 0 else ""
	if v is Dictionary:
		v = v.get("idle_a", "")
	var path := String(v)
	if path == "":
		push_warning("WorldBuilder: no picture " + key_or_path)
		return null
	var t: Texture2D = GameData.tex(path)
	if t == null:
		return null
	var im := t.get_image()
	if im == null:
		return null
	im = im.duplicate()
	if im.is_compressed():
		im.decompress()
	if im.has_mipmaps():
		im.clear_mipmaps()
	im.convert(Image.FORMAT_RGBA8)
	return im

func _tex_from(im: Image, mip: bool = true) -> ImageTexture:
	if mip:
		im.generate_mipmaps()
	return ImageTexture.create_from_image(im)

## A side texture for solid s (made once per key).
func _side_tex(key: String, s: Dictionary, face: String, u0: float, w: int, zh: int) -> ImageTexture:
	if not _tex_cache.has(key):
		_tex_cache[key] = WT.side_texture(s, face, u0, w, zh)
	return _tex_cache[key]

## The yard picture's texture coordinates for world (x, y).
func _yard_uv(x: float, y: float) -> Vector2:
	return Vector2((x - _yard_ox) / _yard_size.x, (y - _yard_oy) / _yard_size.y)

func _yard_st() -> SurfaceTool:
	return _st("yard", func(): return _mat(_yard_tex))

# ---------------------------------------------------------------- floors

## The prop cut-outs: where each is drawn in the HTML game (world units) and its picture. "shadow": its faint
## parts (shadows, sheen), printed on the floor. Pictures captured from Smashed.html's drawing functions at 2x.
const PROP_DIR := "res://scripts/world/props/"
const PROPS := {
	"bench": {"rect": [367, 59, 475, 130], "shadow": [386, 112, 454, 130]},
	"rack": {"rect": [507, 33, 549, 112], "shadow": [504, 96, 552, 112]},
	"legpress": {"rect": [420, 154, 520, 236], "shadow": [420, 154, 520.5, 236]},
	"table": {"rect": [109, 268, 221, 323], "shadow": [109, 274.5, 221, 328]},
	"rope": {"rect": [339, 16, 351.5, 167], "shadow": [338.5, 16, 352, 167.5]},
	"cab_miner": {"rect": [144, 12, 200, 116], "shadow": [143, 112.5, 201, 121]},
	"cab_bricks": {"rect": [214, 12, 270, 116], "shadow": [213, 112.5, 271, 121]},
	"slot": {"asset": "SLOT_SPRITES", "shadow": [55, 107.5, 125, 121]},
	"tower": {"asset": "TOWER_IMG.src"},
	"wardrobe": {"asset": "assets/art/wardrobe-0.png", "shadow": [146, 615.5, 214, 625]},
	"mirror": {"rect": [216, 524, 276, 616], "shadow": [212, 613, 280, 619]},
}

## Print each prop's shadow whose rect lies on floor picture im (2 px per unit, its corner at world fx, fy).
func _print_shadows(im: Image, fx: float, fy: float) -> void:
	for n in PROPS:
		var p: Dictionary = PROPS[n]
		if not p.has("shadow"):
			continue
		var r: Array = p.shadow
		var px := int(round((float(r[0]) - fx) * 2))
		var py := int(round((float(r[1]) - fy) * 2))
		if px < 0 or py < 0 or px >= im.get_width() or py >= im.get_height():
			continue
		var t = load(PROP_DIR + n + "_shadow.png")
		if t == null:
			continue
		var sh: Image = t.get_image().duplicate()
		if sh.is_compressed():
			sh.decompress()
		sh.convert(Image.FORMAT_RGBA8)
		im.blend_rect(sh, Rect2i(0, 0, sh.get_width(), sh.get_height()), Vector2i(px, py))

## How much further than its art (x0, y0, x1, y1) a solid's picture is painted out: the trampoline's shadow and a
## leg spill past its art rect in the yard picture.
const PAINT_MORE := {"tramp": [-4, 0, 30, 4]}

func _floors() -> void:
	var d := _d()
	var A: Dictionary = d.ARENA
	var wl: float = A.wall
	var B: Dictionary = d.BEDROOM
	var Y: Dictionary = d.YARD
	# the yard picture, its solids' spread-out art painted over
	var yim := _img("YARD_IMG@1985")
	_yard_ox = Y.ox
	_yard_oy = Y.oy
	if yim:
		_yard_orig = yim.duplicate()
		_yard_size = Vector2(yim.get_width(), yim.get_height())
		var t0 := Time.get_ticks_msec()
		for s in d.get("YARD_SOLIDS", []):
			if s.has("art"):
				var s2: Dictionary = s.duplicate(true)
				var more: Array = PAINT_MORE.get(s.m, [0, 0, 0, 0])
				for i in 4:
					s2.art[i] = float(s2.art[i]) + more[i]
				WT.paint_out(yim, s2, int(Y.ox), int(Y.oy))
		print("WorldBuilder: yard painted in %d ms" % (Time.get_ticks_msec() - t0))
		_yard_tex = _tex_from(yim)
	# the lounge: its picture at 2x, the props' shadows printed on it
	var lw: float = float(A.w) - wl * 2
	var lh: float = float(A.h) - wl * 2
	var lim := _img("LOUNGE_IMG.src")
	if lim:
		lim.resize(int(lw * 2), int(lh * 2), Image.INTERPOLATE_NEAREST)
		_print_shadows(lim, wl, wl)
		_lounge_tex = _tex_from(lim)
	var bim := _img("assets/art/bedroom.png")
	var bw: float = float(B.x1) - float(B.x0)
	var bh: float = float(B.y1) - float(B.y0)
	if bim:
		bim.resize(int(bw * 2), int(bh * 2), Image.INTERPOLATE_NEAREST)
		_print_shadows(bim, B.x0, B.y0)
		_bed_tex = _tex_from(bim)
	# the lounge's floor, round the pool's hole
	var lst := _st("lounge", func(): return _mat(_lounge_tex))
	var luv := func(x: float, y: float) -> Vector2: return Vector2((x - wl) / lw, (y - wl) / lh)
	var w := _pool_hole()
	var lx0 := wl
	var ly0 := wl
	var lx1: float = float(A.w) - wl
	var ly1: float = float(A.h) - wl
	_flat(lst, lx0, ly0, lx1, w.y0, 0, luv)
	_flat(lst, lx0, w.y1, lx1, ly1, 0, luv)
	_flat(lst, lx0, w.y0, w.x0, w.y1, 0, luv)
	_flat(lst, w.x1, w.y0, lx1, w.y1, 0, luv)
	# the bedroom
	var bst := _st("bedroom", func(): return _mat(_bed_tex))
	_flat(bst, B.x0, B.y0, B.x1, B.y1, 0, func(x: float, y: float) -> Vector2: return Vector2((x - B.x0) / bw, (y - B.y0) / bh))
	# the doorways' floors (fpFloor's colours)
	var areas: Array = d.calls.lobbyAreas
	var bd: Dictionary = areas[2]
	var dd: Dictionary = areas[3]
	_flat(_col_st(Color("#6a472f")), bd.x0, A.h - wl, bd.x1, A.h, 0, _no_uv)
	_flat(_col_st(Color("#77736c")), dd.x0, A.h - wl, dd.x1, _back_door_y1(), 0, _no_uv)
	# the yard: its picture everywhere but under the house
	var hx: float = A.w
	var hy: float = _back_door_y1()
	var wx: float = float(B.x1) + wl
	var wy: float = _south_y0()
	var ix0: float = Y.ox
	var iy0: float = Y.oy
	var ix1: float = Y.ox + _yard_size.x
	var iy1: float = Y.oy + _yard_size.y
	var yst := _yard_st()
	var yuv := Callable(self, "_yard_uv")
	_flat(yst, ix0, iy0, ix1, 0, 0, yuv)
	_flat(yst, ix0, 0, 0, iy1, 0, yuv)
	_flat(yst, hx, 0, ix1, hy, 0, yuv)
	_flat(yst, wx, hy, ix1, wy, 0, yuv)
	_flat(yst, 0, wy, ix1, iy1, 0, yuv)
	# grass beyond the picture, out to the horizon
	var g := _col_st(GRASS)
	var far := 8000.0
	_flat(g, -far, -far, far, iy0, 0, _no_uv)
	_flat(g, -far, iy1, far, far, 0, _no_uv)
	_flat(g, -far, iy0, ix0, iy1, 0, _no_uv)
	_flat(g, ix1, iy0, far, iy1, 0, _no_uv)

## Where the house's back wall stands (the foot of it, on the deck): BACK_DOOR.y1, the deck's top edge.
func _back_door_y1() -> float:
	return float(_d().calls.lobbyAreas[4].y0)

## The top of the big yard south of the house (YARD_AREAS[2].y0): the wing's back wall.
func _south_y0() -> float:
	return float(_d().calls.lobbyAreas[6].y0)

## The pool's hole in the floor: the water as drawn (POOL, 9 in from its edge).
func _pool_hole() -> Dictionary:
	var p: Dictionary = _d().POOL
	return {"x0": p.x0 + 9, "y0": p.y0 + 9, "x1": p.x1 - 9, "y1": p.y1 - 9}

# ---------------------------------------------------------------- the house

func _house() -> void:
	var d := _d()
	var A: Dictionary = d.ARENA
	var wl: float = A.wall
	var WALL: float = d.get("SHROOM_WALL", 150)
	var areas: Array = d.calls.lobbyAreas
	var indoor: Array = [areas[0], areas[1], areas[2], areas[3]]
	var hy := _back_door_y1()
	var wx: float = float(d.BEDROOM.x1) + wl
	var wy := _south_y0()
	var blocks := [{"x0": 0.0, "y0": 0.0, "x1": float(A.w), "y1": hy}, {"x0": 0.0, "y0": hy, "x1": wx, "y1": wy}]
	# a grid on every edge there is; each cell is a room's floor, wall, or outside
	var xs := {}
	var ys := {}
	for r in blocks + indoor:
		xs[float(r.x0)] = true; xs[float(r.x1)] = true
		ys[float(r.y0)] = true; ys[float(r.y1)] = true
	var gx: Array = xs.keys()
	var gy: Array = ys.keys()
	gx.sort(); gy.sort()
	var inside := func(rs: Array, x: float, y: float) -> bool:
		for r in rs:
			if x > float(r.x0) and x < float(r.x1) and y > float(r.y0) and y < float(r.y1):
				return true
		return false
	var nx := gx.size() - 1
	var ny := gy.size() - 1
	var kind := []   # 0 outside, 1 floor, 2 wall
	for j in ny:
		for i in nx:
			var cx: float = (gx[i] + gx[i + 1]) / 2
			var cy: float = (gy[j] + gy[j + 1]) / 2
			var k := 0
			if inside.call(blocks, cx, cy):
				k = 1 if inside.call(indoor, cx, cy) else 2
			kind.append(k)
	var at := func(i: int, j: int) -> int:
		if i < 0 or j < 0 or i >= nx or j >= ny:
			return 0
		return kind[j * nx + i]
	var in_tex := func(): return _mat(_side_tex("in", {"m": "in", "h": WALL}, "N", 0, 4, int(WALL)))
	var out_tex := func(): return _mat(_side_tex("house", {"m": "house", "h": WALL}, "N", 0, 4, int(WALL)))
	var in_st := _st("wall_in", in_tex, G_FULL)
	var out_st := _st("wall_out", out_tex, G_FULL)
	var in_cut := _st("wall_in", in_tex, G_CUT)
	var out_cut := _st("wall_out", out_tex, G_CUT)
	var wuv := func(u: float, z: float) -> Vector2: return Vector2(u / 4.0, (WALL - z) / WALL)
	var top := _col_st(WALL_TOP, G_FULL)
	var top_cut := _col_st(WALL_TOP, G_CUT)
	var CUT := minf(cutaway_height, WALL)
	for j in ny:
		var run0 := -1
		for i in nx + 1:
			var wall: bool = i < nx and at.call(i, j) == 2
			if wall:
				var x0: float = gx[i]
				var x1: float = gx[i + 1]
				var y0: float = gy[j]
				var y1: float = gy[j + 1]
				_flat(top, x0, y0, x1, y1, WALL, _no_uv)
				_flat(top_cut, x0, y0, x1, y1, CUT, _no_uv)
				for f in [["N", 0, -1, x0, y0, x1, y0], ["S", 0, 1, x0, y1, x1, y1], ["W", -1, 0, x0, y0, x0, y1], ["E", 1, 0, x1, y0, x1, y1]]:
					var nk: int = at.call(i + f[1], j + f[2])
					if nk == 2:
						continue
					_side(in_st if nk == 1 else out_st, f[3], f[4], f[5], f[6], 0, WALL, f[0], wuv)
					_side(in_cut if nk == 1 else out_cut, f[3], f[4], f[5], f[6], 0, CUT, f[0], wuv)
				if run0 < 0:
					run0 = i
			if not wall and run0 >= 0:
				_coll_box(_walls_body, {"x0": gx[run0], "y0": gy[j], "x1": gx[i], "y1": gy[j + 1]}, -40, WALL)
				run0 = -1
	# lintels over the doorways (FP_LINTEL: 84 up to the top), their faces inside and out
	var Z0 := 84.0
	for a in [areas[2], areas[3]]:
		var x0: float = a.x0
		var x1: float = a.x1
		var y0: float = float(A.h) - wl
		var y1: float = hy if a == areas[3] else float(A.h)
		var under := _col_st(Color8(60, 54, 48), G_FULL)
		_flat(under, x0, y0, x1, y1, Z0, _no_uv)
		_flat(top, x0, y0, x1, y1, WALL, _no_uv)
		_side(in_st, x0, y0, x1, y0, Z0, WALL, "N", wuv)
		_side(out_st if a == areas[3] else in_st, x0, y1, x1, y1, Z0, WALL, "S", wuv)
		_coll_box(_walls_body, {"x0": x0, "y0": y0, "x1": x1, "y1": y1}, Z0, WALL)
	# the ceiling indoors, and the roof: both hidden from above (G_FULL)
	var ceil_st := _col_st(CEILING, G_FULL)
	for a in indoor:
		var y1: float = a.y1
		if a == areas[3]:
			y1 = hy
		_flat(ceil_st, a.x0, a.y0, a.x1, y1, WALL - 0.5, _no_uv)
	_house_roof(blocks, WALL)

## The house's roof (b329): a hipped L, the main block's and the wing's meeting in valleys, each block hipped on
## its own rectangle from the top (FP_HOUSE_ROOF.rects: y0 0), k 0.5 up from the eaves at the top of the walls.
## The depth test makes the two one roof. It wears the roof painted in the yard picture: the main block's 1:1
## across and 503 of the picture down its 566; the wing's from x 27, squeezed 383/476 across and 840/884 down.
func _house_roof(blocks: Array, WALL: float) -> void:
	var k := 0.5
	var main: Dictionary = blocks[0]
	var wing := {"x0": 0.0, "y0": 0.0, "x1": blocks[1].x1, "y1": blocks[1].y1}
	var pics := [
		{"x0": 0.0, "sx": 1.0, "sy": 503.0 / float(main.y1)},
		{"x0": 27.0, "sx": 383.0 / float(wing.x1), "sy": 840.0 / float(wing.y1)}]
	var rects := [main, wing]
	for n in 2:
		var r: Dictionary = rects[n]
		var M: Dictionary = pics[n]
		var st := _st("roof%d" % n, func(): return _mat(_yard_tex), G_FULL)
		var uvf := func(x: float, y: float) -> Vector2: return _yard_uv(M.x0 + x * M.sx, y * M.sy)
		_hipped(st, r, WALL, k, uvf)

## A hipped roof over r from height h at its eaves, rising k for each unit in.
func _hipped(st: SurfaceTool, r: Dictionary, h: float, k: float, uvf: Callable) -> void:
	var x0: float = r.x0
	var x1: float = r.x1
	var y0: float = r.y0
	var y1: float = r.y1
	var w := x1 - x0
	var dpt := y1 - y0
	var half := minf(w, dpt) / 2
	var top := h + k * half
	var a: Vector2
	var b: Vector2
	if w >= dpt:
		a = Vector2(x0 + half, (y0 + y1) / 2); b = Vector2(x1 - half, (y0 + y1) / 2)
	else:
		a = Vector2((x0 + x1) / 2, y0 + half); b = Vector2((x0 + x1) / 2, y1 - half)
	var c := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	var face := func(pts: Array, lit: float) -> void:
		var p := []
		var uv := []
		for q in pts:
			p.append(P(q.x, q.y, q.z))
			uv.append(uvf.call(q.x, q.y))
		var col := Color(lit, lit, lit)
		if p.size() == 3:
			_tri(st, p, uv, col)
		else:
			_quad(st, p, uv, col)
	var A3 := Vector3(a.x, a.y, top)
	var B3 := Vector3(b.x, b.y, top)
	var C := []
	for q in c:
		C.append(Vector3(q.x, q.y, h))
	if w >= dpt:
		face.call([C[0], C[1], B3, A3], 1.0)        # north slope
		face.call([C[3], A3, B3, C[2]], 0.82)       # south
		face.call([C[0], A3, C[3]], 0.92)           # west hip
		face.call([C[1], C[2], B3], 0.92)           # east hip
	else:
		face.call([C[0], C[1], A3], 1.0)
		face.call([C[3], B3, C[2]], 0.82)
		face.call([C[0], A3, B3, C[3]], 0.92)
		face.call([C[1], C[2], B3, A3], 0.92)

# ---------------------------------------------------------------- the lounge and the bedroom

## The lounge's and the bedroom's solids, named, in units, with heights.
func _lounge_boxes() -> Array:
	var d := _d()
	var c: Dictionary = d.calls
	var out: Array = []
	var add := func(n: String, b: Dictionary) -> void:
		out.append({"x0": float(b.x0), "y0": float(b.y0), "x1": float(b.x1), "y1": float(b.y1), "h": float(FURNITURE_H.get(n, 40)), "m": n})
	add.call("table", c.tableBox)
	add.call("bench", c.benchBox)
	add.call("rack", c.rackBox)
	add.call("legpress", c.legBox)
	add.call("wardrobe", c.wardBox)
	var bb: Array = c.bedBoxes
	add.call("bed", bb[0])
	add.call("nightstand", bb[1])
	add.call("mirror", bb[2])
	var cabs: Array = d.get("CABINETS", [])
	var cb: Array = c.cabBoxes
	for i in mini(cabs.size(), cb.size()):
		add.call("cab_" + String(cabs[i].game), cb[i])
	var sl: Dictionary = c.get("slot", {"x": 90, "y": 110})
	add.call("slot", {"x0": sl.x - 26, "x1": sl.x + 26, "y0": sl.y - 8, "y1": sl.y + 6})
	var tk := _T("towerScale", 1.25)
	var tx := _T("towerX", 604)
	var ty := _T("towerY", 190)
	add.call("tower", {"x0": tx - 19 * tk, "x1": tx + 19 * tk, "y0": ty - 9 * tk, "y1": ty})
	var p: Dictionary = d.POOL
	add.call("pool", {"x0": p.x0 + 6, "y0": p.y0 + 6, "x1": p.x1 - 6, "y1": p.y1 - 6})
	return out

func _lounge_solids() -> void:
	var R := _T("radius", 14)
	for b in _lounge_boxes():
		var n: String = b.m
		var body := _body(n)
		match n:
			"pool":
				_coll_box(body, b, -60, 60, player_radius - 1)
			"tower":
				_coll_box(body, b, 0, b.h, player_radius - R * 0.7)
			_:
				_coll_box(body, b, 0, maxf(b.h, 40), player_radius - R * 0.5)
	_bed_boxes()
	_pool()

## The bed and the nightstand: in the bedroom's picture, so stood up as boxes wearing their piece of it on top,
## their sides the picture's edge pulled down (so the colours carry on round them).
func _bed_boxes() -> void:
	var d := _d()
	var B: Dictionary = d.BEDROOM
	var bw: float = float(B.x1) - float(B.x0)
	var bh: float = float(B.y1) - float(B.y0)
	var st := _st("bedroom", func(): return _mat(_bed_tex))
	var buv := func(x: float, y: float) -> Vector2: return Vector2((x - B.x0) / bw, (y - B.y0) / bh)
	for item in [[d.BED, FURNITURE_H.bed], [d.NIGHTSTAND, FURNITURE_H.nightstand]]:
		var b: Dictionary = item[0]
		var h: float = item[1]
		_flat(st, b.x0, b.y0, b.x1, b.y1, h, buv)
		var edge := {"N": float(b.y0) + 0.3, "S": float(b.y1) - 0.3, "W": float(b.x0) + 0.3, "E": float(b.x1) - 0.3}
		_box_sides(b, 0, h, func(f: String):
			var e: float = edge[f]
			if f == "N" or f == "S":
				return [st, func(u: float, _z: float) -> Vector2: return buv.call(u, e)]
			return [st, func(u: float, _z: float) -> Vector2: return buv.call(e, u)])

## The pool: a hole in the floor (cut by _floors), its tiled sides going down to the water a little below, the
## water wearing its own piece of the lounge picture.
func _pool() -> void:
	var d := _d()
	var A: Dictionary = d.ARENA
	var wl: float = A.wall
	var lw: float = float(A.w) - wl * 2
	var lh: float = float(A.h) - wl * 2
	var w := _pool_hole()
	var depth := 3.0
	var tile := _st("pool_side", func(): return _mat(null, Color8(150, 170, 176)))
	_box_sides(w, -depth, 0, func(_f: String): return [tile, func(_u: float, _z: float) -> Vector2: return Vector2.ZERO])
	var mi := MeshInstance3D.new()
	mi.name = "PoolWater"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_flat(st, w.x0, w.y0, w.x1, w.y1, -depth, func(x: float, y: float) -> Vector2: return Vector2((x - wl) / lw, (y - wl) / lh))
	mi.mesh = st.commit()
	mi.material_override = _mat(_lounge_tex)
	add_child(mi)
	pool_water = mi

# ---------------------------------------------------------------- the yard

## The yard's solids that stand up in the view from above too (the rest are drawn there by the yard picture).
const SEEN_FROM_ABOVE := ["esky"]

## How wide a stretch of each material repeats (units): its texture is that wide and wraps. 0: one of its own per face.
const TILE_W := {"fence": 352, "garage": 384, "shed": 160, "wood": 8, "bed": 8, "junk": 44, "tank": 8, "esky": 8,
	"compost": 8, "bbq": 24, "bush": 128, "car": 0}

func _yard_solids() -> void:
	_cur_group = G_FULL
	_yard_solids_3d()
	_cur_group = G_ALL

## The view from above (cutaway): the yard's solids aren't stood up, the yard picture shows them as the HTML game
## draws them (its art for each one that spreads past its ground; the rest are in the floor's picture already).
func _yard_flat() -> void:
	if _yard_orig == null:
		return
	var W := _yard_orig.get_width()
	var H := _yard_orig.get_height()
	for s in _d().get("YARD_SOLIDS", []):
		if not s.has("art") or (s.m == "tramp" and not include_trampoline):
			continue
		var more: Array = PAINT_MORE.get(s.m, [0, 0, 0, 0])
		var ax0: float = maxf(float(s.art[0]) + more[0], _yard_ox)
		var ay0: float = maxf(float(s.art[1]) + more[1], _yard_oy)
		var ax1: float = minf(float(s.art[2]) + more[2], _yard_ox + W)
		var ay1: float = minf(float(s.art[3]) + more[3], _yard_oy + H)
		var r := Rect2i(int(ax0 - _yard_ox), int(ay0 - _yard_oy), int(ax1 - ax0), int(ay1 - ay0))
		if r.size.x < 1 or r.size.y < 1:
			continue
		var tex := _tex_from(_yard_orig.get_region(r))
		var st := _st("flat_%s_%d_%d" % [s.m, r.position.x, r.position.y], func(): return _mat(tex), G_CUT)
		_flat(st, ax0, ay0, ax0 + r.size.x, ay0 + r.size.y, 0.4,
			func(x: float, y: float) -> Vector2: return Vector2((x - ax0) / r.size.x, (y - ay0) / r.size.y))
	_yard_orig = null

func _yard_solids_3d() -> void:
	var d := _d()
	var R := _T("radius", 14)
	var inset := player_radius - R * 0.5
	var n := 0
	for s in d.get("YARD_SOLIDS", []):
		n += 1
		var m: String = s.m
		# the esky isn't in the yard picture (the HTML game draws it over): it stands from above too
		_cur_group = G_ALL if m in SEEN_FROM_ABOVE else G_FULL
		var name_ := m if not solids.has(m) else "%s_%d" % [m, n]
		if m == "tramp":
			if include_trampoline:
				_tramp(s, inset)
			continue
		var body := _body(name_)
		if s.has("r"):
			_round_solid(s)
			var cs := CollisionShape3D.new()
			var cy := CylinderShape3D.new()
			cy.radius = maxf(1.0, float(s.r) - inset) * U
			cy.height = float(s.h) * U
			cs.shape = cy
			cs.position = P(s.cx, s.cy, float(s.h) / 2)
			body.add_child(cs)
			continue
		for q in s.get("fp", [s]):
			_box_solid(q, s, name_)
		_coll_box(body, s, 0, maxf(float(s.h), 24), inset)   # (at least 24: above the capsule's round bottom)

## One box of the yard at its height: its sides in its material, its top its piece of the yard picture (the
## esky's white lid), or a gable roof if it has one.
func _box_solid(q: Dictionary, s: Dictionary, name_: String) -> void:
	var m: String = q.m
	var h: float = q.h
	var roof: Dictionary = s.get("roof", {})
	var peak := h
	if not roof.is_empty():
		var span: float = (float(q.x1) - float(q.x0)) if roof.ridge == "y" else (float(q.y1) - float(q.y0))
		peak = h + float(roof.k) * span / 2
	var zh := int(ceil(peak))
	var tw: int = TILE_W.get(m, 8)
	var front: Dictionary = ART_FRONT.get(m, {})
	var art: Array = s.get("art", [])
	var side := func(f: String):
		if f == "S" and not front.is_empty() and art.size() == 4:
			# its front, as the yard picture draws it (under the roof there): the wall, and the gable over it
			var fw: Array = front.wall
			var ax: float = art[0]
			var ay: float = art[1]
			var gp: float = front.get("gable_peak", fw[0])
			return [_yard_st(), func(u: float, z: float) -> Vector2:
				var py: float = lerpf(fw[1], fw[0], z / h) if z <= h + 0.01 else lerpf(fw[0], gp, (z - h) / maxf(1.0, peak - h))
				return _yard_uv(u, ay + py)]
		var along_x := f == "N" or f == "S"
		var u0: float = float(q.x0) if along_x else float(q.y0)
		var length := int(ceil((float(q.x1) - float(q.x0)) if along_x else (float(q.y1) - float(q.y0))))
		var unique := tw == 0 or (m == "garage" and f == "S") or (m == "shed" and f == "S")
		var key := "%s_%s_%d" % [name_, f, zh] if unique else "%s_%d_%d" % [m, int(h), zh]
		var tex: ImageTexture
		if unique:
			tex = _side_tex(key + "_" + String(q.get("part", "")), q, f, u0, length, zh)
		else:
			tex = _side_tex(key, q, f, 0, tw, zh)
		var alpha := 1 if m == "bush" else 0
		var st := _st("side_" + key + "_" + String(q.get("part", "")) if unique else "side_" + key, func(): return _mat(tex, Color.WHITE, alpha))
		var uvf: Callable
		if unique:
			uvf = func(u: float, z: float) -> Vector2: return Vector2((u - u0) / length, (zh - z) / zh)
		else:
			uvf = func(u: float, z: float) -> Vector2: return Vector2(u / tw, (zh - z) / zh)
		return [st, uvf]
	_box_sides(q, 0, h, side)
	if roof.is_empty():
		var top_st: SurfaceTool = _col_st(Color8(230, 234, 238)) if m == "esky" else _yard_st()
		_flat(top_st, q.x0, q.y0, q.x1, q.y1, h, Callable(self, "_yard_uv"))
		return
	_gable(q, s, roof, side)

## A gable roof (b329) on box q: ridge along y (the garage: sloping up from its west and east walls) or along x
## (the shed: from north and south), k up for each unit in. It reaches out to the edge of the solid's art (the
## eaves). Its gable ends are the walls going up to it.
func _gable(q: Dictionary, s: Dictionary, roof: Dictionary, side: Callable) -> void:
	var h: float = q.h
	var k: float = roof.k
	var m: String = q.m
	var art: Array = s.get("art", [q.x0, q.y0, q.x1, q.y1])
	var x0: float = q.x0
	var x1: float = q.x1
	var y0: float = q.y0
	var y1: float = q.y1
	var ridge_y: bool = roof.ridge == "y"
	# the gable ends: triangles up from the top of the end walls
	for f in (["N", "S"] if ridge_y else ["W", "E"]):
		var r = side.call(f)
		var st: SurfaceTool = r[0]
		var uvf: Callable = r[1]
		var lit: float = LIT[f]
		var col := Color(lit, lit, lit)
		if ridge_y:
			var yy := y0 if f == "N" else y1
			var cx := (x0 + x1) / 2
			var top := h + k * (cx - x0)
			_tri(st, [P(x0, yy, h), P(x1, yy, h), P(cx, yy, top)], [uvf.call(x0, h), uvf.call(x1, h), uvf.call(cx, top)], col)
		else:
			var xx := x0 if f == "W" else x1
			var cy := (y0 + y1) / 2
			var top := h + k * (cy - y0)
			_tri(st, [P(xx, y0, h), P(xx, y1, h), P(xx, cy, top)], [uvf.call(y0, h), uvf.call(y1, h), uvf.call(cy, top)], col)
	# the two slopes, out to the eaves
	if ART_FRONT.has(m) and s.has("art"):
		_gable_pic(q, s, roof)
		return
	var ax0: float = art[0]
	var ay0: float = art[1]
	var ax1: float = art[2]
	var ay1: float = art[3]
	if ridge_y:
		var cx := (x0 + x1) / 2
		var top := h + k * (cx - x0)
		var length := int(ceil(ay1 - ay0))
		var tex := _roof_tex(m, length)
		var st := _st("roof_" + m, func(): return _mat(tex))
		var uv := func(_x: float, y: float) -> Vector2: return Vector2((y - ay0) / length, 0.5)
		var zw := h - k * (x0 - ax0)
		var ze := h - k * (ax1 - x1)
		_quad(st, [P(ax0, ay0, zw), P(cx, ay0, top), P(cx, ay1, top), P(ax0, ay1, zw)], [uv.call(0, ay0), uv.call(0, ay0), uv.call(0, ay1), uv.call(0, ay1)], Color(0.88, 0.88, 0.88))
		_quad(st, [P(ax1, ay0, ze), P(cx, ay0, top), P(cx, ay1, top), P(ax1, ay1, ze)], [uv.call(0, ay0), uv.call(0, ay0), uv.call(0, ay1), uv.call(0, ay1)], Color(0.88, 0.88, 0.88))
	else:
		var cy := (y0 + y1) / 2
		var top := h + k * (cy - y0)
		var length := int(ceil(ax1 - ax0))
		var tex := _roof_tex(m, length)
		var st := _st("roof_" + m, func(): return _mat(tex))
		var zn := h - k * (y0 - ay0)
		var zs := h - k * (ay1 - y1)
		var u0 := 0.0
		var u1 := 1.0
		_quad(st, [P(ax0, ay0, zn), P(ax1, ay0, zn), P(ax1, cy, top), P(ax0, cy, top)], [Vector2(u0, 0.5), Vector2(u1, 0.5), Vector2(u1, 0.5), Vector2(u0, 0.5)], Color(1, 1, 1))
		_quad(st, [P(ax0, ay1, zs), P(ax1, ay1, zs), P(ax1, cy, top), P(ax0, cy, top)], [Vector2(u0, 0.5), Vector2(u1, 0.5), Vector2(u1, 0.5), Vector2(u0, 0.5)], Color(0.7, 0.7, 0.7))

## Where, in a solid's art (picture units from its art's top-left), its roof and its front are drawn: the yard
## picture shows the garage and the shed from above and in front, the roof above and the front wall under it.
## garage: the roof's top edge at its eaves and at its ridge, its bottom edge (the gable) at the eaves and the
## ridge, the front wall's top and bottom, and the gable's peak. shed: the roof's top edge, its ridge, its
## bottom edge, and the front wall's top and bottom.
const ART_FRONT := {
	"garage": {"top": [35, 5], "bottom": [350, 310], "wall": [355, 487], "gable_peak": 312},
	"shed": {"top": 10, "ridge": 82, "bottom": 188, "wall": [190, 345]},
}

## A gable roof wearing its piece of the yard picture (squeezed into the roof's own length), out to the eaves.
func _gable_pic(q: Dictionary, s: Dictionary, roof: Dictionary) -> void:
	var F: Dictionary = ART_FRONT[q.m]
	var art: Array = s.art
	var h: float = q.h
	var k: float = roof.k
	var ax0: float = art[0]
	var ay0: float = art[1]
	var ax1: float = art[2]
	var ay1: float = art[3]
	var st := _yard_st()
	var pic := func(ax: float, py: float) -> Vector2: return _yard_uv(ax, ay0 + py)
	var col := Color.WHITE
	if roof.ridge == "y":
		var cx := (float(q.x0) + float(q.x1)) / 2
		var top := h + k * (cx - float(q.x0))
		var zw := h - k * (float(q.x0) - ax0)
		var ze := h - k * (ax1 - float(q.x1))
		var t: Array = F.top
		var b: Array = F.bottom
		_quad(st, [P(ax0, ay0, zw), P(cx, ay0, top), P(cx, ay1, top), P(ax0, ay1, zw)],
			[pic.call(ax0, t[0]), pic.call(cx, t[1]), pic.call(cx, b[1]), pic.call(ax0, b[0])], col)
		_quad(st, [P(ax1, ay0, ze), P(cx, ay0, top), P(cx, ay1, top), P(ax1, ay1, ze)],
			[pic.call(ax1, t[0]), pic.call(cx, t[1]), pic.call(cx, b[1]), pic.call(ax1, b[0])], col)
	else:
		var cy := (float(q.y0) + float(q.y1)) / 2
		var top := h + k * (cy - float(q.y0))
		var zn := h - k * (float(q.y0) - ay0)
		var zs := h - k * (ay1 - float(q.y1))
		_quad(st, [P(ax0, ay0, zn), P(ax1, ay0, zn), P(ax1, cy, top), P(ax0, cy, top)],
			[pic.call(ax0, F.top), pic.call(ax1, F.top), pic.call(ax1, F.ridge), pic.call(ax0, F.ridge)], col)
		_quad(st, [P(ax0, cy, top), P(ax1, cy, top), P(ax1, ay1, zs), P(ax0, ay1, zs)],
			[pic.call(ax0, F.ridge), pic.call(ax1, F.ridge), pic.call(ax1, F.bottom), pic.call(ax0, F.bottom)], col)

func _roof_tex(m: String, length: int) -> ImageTexture:
	var key := "roof_%s_%d" % [m, length]
	if not _tex_cache.has(key):
		_tex_cache[key] = WT.roof_texture(m, length)
	return _tex_cache[key]

## A ring of quads round (cx, cy) radius r from z0 to z1, its texture wrapping every tw units round it.
func _cylinder(st: SurfaceTool, cx: float, cy: float, r: float, z0: float, z1: float, tw: float, zh: float, segs: int = 48) -> void:
	var circ := TAU * r
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := Vector2(cx + cos(a0) * r, cy + sin(a0) * r)
		var p1 := Vector2(cx + cos(a1) * r, cy + sin(a1) * r)
		var u0 := circ * i / segs / tw
		var u1 := circ * (i + 1) / segs / tw
		var mid := (a0 + a1) / 2
		var nx := cos(mid)
		var ny := sin(mid)
		var lit := (0.7 + 0.3 * maxf(0.0, -ny * 0.9 + nx * 0.25))   # lit where it faces the sun (the north)
		_quad(st, [P(p0.x, p0.y, z0), P(p1.x, p1.y, z0), P(p1.x, p1.y, z1), P(p0.x, p0.y, z1)],
			[Vector2(u0, (zh - z0) / zh), Vector2(u1, (zh - z0) / zh), Vector2(u1, (zh - z1) / zh), Vector2(u0, (zh - z1) / zh)], Color(lit, lit, lit))

## The water tank: corrugated, round; its rim and its water on top.
func _round_solid(s: Dictionary) -> void:
	var h: float = s.h
	var zh := int(ceil(h))
	var tex := _side_tex("tank_%d" % zh, s, "N", 0, 8, zh)
	var st := _st("tank_side", func(): return _mat(tex))
	_cylinder(st, s.cx, s.cy, s.r, 0, h, 8, zh)
	var top_tex := WT.tank_top_texture(float(s.r), 128)
	var tst := _st("tank_top", func(): return _mat(top_tex, Color.WHITE, 1))
	var r: float = s.r
	_flat(tst, float(s.cx) - r, float(s.cy) - r, float(s.cx) + r, float(s.cy) + r, h,
		func(x: float, y: float) -> Vector2: return Vector2((x - (float(s.cx) - r)) / (2 * r), (y - (float(s.cy) - r)) / (2 * r)))

## The trampoline (b326): legs, its frame and springs, the blue pad, the mat, the net on its poles; a cylinder
## to bump into (tramp_body).
func _tramp(s: Dictionary, inset: float) -> void:
	var tr: Dictionary = _d().get("TRAMP", {"cx": s.cx, "cy": s.cy, "r": s.r, "mat": 32, "net": 64})
	var q := s.duplicate()
	q["tramp"] = tr
	var h: float = s.h
	var zh := int(ceil(h))
	var circ := TAU * float(s.r)
	var tw := int(round(circ / 2))
	var tex := _side_tex("tramp_side", q, "N", 0, tw, zh)
	var st := _st("tramp_side", func(): return _mat(tex, Color.WHITE, 2))
	_cylinder(st, s.cx, s.cy, s.r, 0, h, circ / 2.0, zh, 64)
	var top_tex := WT.tramp_top_texture(tr, 256)
	var tst := _st("tramp_top", func(): return _mat(top_tex, Color.WHITE, 1))
	var r: float = s.r
	var mat_z: float = tr.get("mat", 32)
	_flat(tst, float(s.cx) - r, float(s.cy) - r, float(s.cx) + r, float(s.cy) + r, mat_z,
		func(x: float, y: float) -> Vector2: return Vector2((x - (float(s.cx) - r)) / (2 * r), (y - (float(s.cy) - r)) / (2 * r)))
	var body := _body("tramp")
	tramp_body = body
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = maxf(1.0, r - inset) * U
	cy.height = h * U
	cs.shape = cy
	cs.position = P(s.cx, s.cy, h / 2)
	body.add_child(cs)

## The fences round the yard: wherever its walkable ground (YARD_AREAS) stops and the house doesn't (FP_FENCE),
## a paling fence FENCE_H tall, just outside.
func _yard_fences() -> void:
	_cur_group = G_FULL
	_yard_fences_3d()
	_cur_group = G_ALL

func _yard_fences_3d() -> void:
	var d := _d()
	var a: Array = d.calls.lobbyAreas
	var east: Dictionary = a[5]
	var south: Dictionary = a[6]
	var FH: float = d.get("FENCE_H", 58)
	var th := 4.0
	var runs := [
		{"x0": float(east.x0), "y0": float(east.y0) - th, "x1": float(east.x1) + th, "y1": float(east.y0)},     # north, by the driveway's gate
		{"x0": float(east.x1), "y0": float(east.y0) - th, "x1": float(east.x1) + th, "y1": float(south.y1) + th},   # east
		{"x0": float(south.x0) - th, "y0": float(south.y1), "x1": float(east.x1) + th, "y1": float(south.y1) + th},  # south
		{"x0": float(south.x0) - th, "y0": float(south.y0), "x1": float(south.x0), "y1": float(south.y1) + th},     # west
	]
	var fs := {"m": "fence", "h": FH}
	var zh := int(ceil(FH))
	var tex := _side_tex("fence_edge", fs, "N", 0, 352, zh)
	var st := _st("fence_edge", func(): return _mat(tex))
	var uvf := func(u: float, z: float) -> Vector2: return Vector2(u / 352.0, (zh - z) / zh)
	var rail := _col_st(Color8(58, 46, 32))
	for r in runs:
		_box_sides(r, 0, FH, func(_f: String): return [st, uvf])
		_flat(rail, r.x0, r.y0, r.x1, r.y1, FH, _no_uv)
		_coll_box(_walls_body, r, -40, FH)

# ---------------------------------------------------------------- the props

const PROP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, world_vertex_coords, depth_draw_opaque;
// A cut-out standing on its feet (this node's origin), turned square to the camera, and leaning back to lie
// flat as the camera looks down, so from above it reads as the top-down picture and from eye height it stands.
uniform sampler2D tex : source_color, filter_nearest;
uniform float lean_max = 1.35;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - o;
	vec3 cr = INV_VIEW_MATRIX[0].xyz;
	vec3 r = vec3(cr.x, 0.0, cr.z);
	r = length(r) > 1e-4 ? normalize(r) : vec3(1.0, 0.0, 0.0);
	vec3 fh = vec3(r.z, 0.0, -r.x);
	float pitch = asin(clamp(INV_VIEW_MATRIX[2].y, -1.0, 1.0));
	float th = min(lean_max, max(pitch, 0.0) * smoothstep(0.35, 0.9, pitch));
	vec3 up = cos(th) * vec3(0.0, 1.0, 0.0) + sin(th) * fh;
	VERTEX = o + r * local.x + up * local.y;
}
void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""

var _prop_shader: Shader

## Each prop: its picture standing at the middle of its bottom edge (where the HTML game draws it, its feet
## there), as wide and tall as it's drawn top-down.
func _props() -> void:
	_prop_shader = Shader.new()
	_prop_shader.code = PROP_SHADER
	var T := func(k: String, def: float) -> float: return _T(k, def)
	for n in PROPS:
		var p: Dictionary = PROPS[n]
		var tex: Texture2D
		var rect: Array
		if p.has("asset"):
			var path = GameData.manifest.get(p.asset, p.asset)
			if path is Dictionary:
				path = path.get("idle_a", "")
			if path is Array:
				path = path[0]
			tex = GameData.tex(String(path))
			if tex == null:
				continue
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			match n:
				"tower":
					var k: float = T.call("towerScale", 1.25)
					var dw := tw / 2 * k
					var dh := th / 2 * k
					var tx: float = T.call("towerX", 604)
					var ty: float = T.call("towerY", 190)
					rect = [round(tx - 19 * k), round(ty - dh), round(tx - 19 * k) + round(dw), round(ty - dh) + round(dh)]
				"slot":
					var sl: Dictionary = _d().calls.get("slot", {"x": 90, "y": 110})
					var hh: float = 92 * float(T.call("slotScale", 1.35))
					var dw := hh * tw / th
					rect = [round(sl.x - dw / 2), round(sl.y + 6 - hh), round(sl.x - dw / 2) + round(dw), round(sl.y + 6 - hh) + round(hh)]
				"wardrobe":
					var W: Dictionary = _d().get("WARD", {"x": 180, "y": 620, "s": 1})
					var ws: float = W.get("s", 1)
					var dw := tw / 2 * ws
					var dh := th / 2 * ws
					rect = [round(W.x - dw / 2), round(W.y - dh), round(W.x - dw / 2) + round(dw), round(W.y - dh) + round(dh)]
		else:
			tex = load(PROP_DIR + n + ".png")
			rect = p.rect
		if tex == null:
			continue
		var x0: float = rect[0]
		var y0: float = rect[1]
		var x1: float = rect[2]
		var y1: float = rect[3]
		var w := (x1 - x0) * U
		var h := (y1 - y0) * U
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(st, [Vector3(-w / 2, 0, 0), Vector3(w / 2, 0, 0), Vector3(w / 2, h, 0), Vector3(-w / 2, h, 0)],
			[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], Color.WHITE)
		var mi := MeshInstance3D.new()
		mi.name = "Prop_" + n
		mi.mesh = st.commit()
		var sm := ShaderMaterial.new()
		sm.shader = _prop_shader
		sm.set_shader_parameter("tex", tex)
		mi.material_override = sm
		mi.extra_cull_margin = h + w
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = P((x0 + x1) / 2, y1, 0.2)
		mi.set_meta("rect", rect)
		add_child(mi)
		props[n] = mi

# ---------------------------------------------------------------- finishing

var _full_mesh: MeshInstance3D
var _cut_mesh: MeshInstance3D

func _commit() -> void:
	var meshes := [ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()]
	for key in _sts:
		var e: Array = _sts[key]
		var st: SurfaceTool = e[0]
		var target: ArrayMesh = meshes[e[2]]
		st.commit(target)
		target.surface_set_material(target.get_surface_count() - 1, e[1])
	var names := ["WorldMesh", "FullMesh", "CutMesh"]
	var layers := [1, 1 << (ROOF_LAYER - 1), 1 << (CUT_LAYER - 1)]
	var mis := []
	for g in 3:
		var mi := MeshInstance3D.new()
		mi.name = names[g]
		mi.mesh = meshes[g]
		mi.layers = layers[g]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mis.append(mi)
	_full_mesh = mis[1]
	_cut_mesh = mis[2]
	_sts.clear()
	_update_cutaway()

func _process(_dt: float) -> void:
	_update_cutaway()

## Shows the house whole or cut away (cutaway), by the camera in use.
func _update_cutaway() -> void:
	if _full_mesh == null:
		return
	var cut := cutaway == 1
	if cutaway < 0:
		var cam: Camera3D = null
		if is_inside_tree():
			cam = get_viewport().get_camera_3d()
		# the camera looks along -Z: it looks down by asin(Z.y)
		cut = cam != null and cam.global_basis.z.normalized().y > sin(deg_to_rad(cutaway_pitch_deg))
	_full_mesh.visible = not cut
	_cut_mesh.visible = cut

## True when the house is cut away (the top-down view) just now.
func is_cut_away() -> bool:
	return _cut_mesh != null and _cut_mesh.visible

## The sky, and the haze the HTML game mixes in with distance (towards 204, 218, 232; half by 3200 units).
func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color8(62, 122, 214)
	sm.sky_horizon_color = Color8(170, 205, 236)
	sm.ground_horizon_color = Color8(170, 205, 236)
	sm.ground_bottom_color = GRASS
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color8(204, 218, 232)
	env.fog_density = 0.5
	env.fog_depth_begin = 20.0
	env.fog_depth_end = 80.0
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0
	environment = env
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)
