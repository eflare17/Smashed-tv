# (Copied from stkilda-godot scripts/town/facades.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkFacades
extends RefCounted
## The fronts of the map's buildings, so the grey blocks read as buildings: rows of windows up each storey, glass
## shopfronts with a door and an awning along the street for the shops, front doors and framed windows on the
## houses, a roller door on the sheds and warehouses, and a darker band along the top of every wall. It's the same
## few patterns everywhere, sized to each wall; in the town centre each building gets the kind of front it has on
## Street View (a shopfront with or without an awning, offices, glass, a blank wall, a car park's decks).
##
## The windows and shopfronts are small pixel-art pictures (made here, at start-up) repeated along each wall, one
## picture per window bay, so a whole wall's windows are one flat piece: cheap enough for phones. The doors,
## awnings and bands are plain coloured shapes added to the buildings' own mesh.

const BAY := 3.0                 # metres per window along a wall
const STOREY := 3.2              # metres per floor
const OUT := 0.04                # how far in front of the wall the windows sit
const HOUSES := ["house", "detached", "semidetached_house", "cabin", "bungalow", "terrace", "residential"]
const PLAIN := ["industrial", "warehouse", "shed", "roof", "parking", "garage", "garages", "service",
	"greenhouse", "pavilion"]
const SHOPS := ["yes", "retail", "commercial", "supermarket", "kiosk"]

const GLASS := Color("#3b5068")
const GLASS_HI := Color("#6c87a3")
const FRAME := Color("#dcd8cf")
const SILL := Color("#9a968d")
const SHOP_FRAME := Color("#3b3f45")
const DOOR := Color("#2a2d33")
const HOUSE_DOOR := Color("#6b4a33")
const ROLLER := Color("#7a7f86")
const AWNING := Color("#34383e")
const CAR_PARK := Color("#26282c")      # the dark gap between a car park's decks

## The windows' materials (SkDayNight lights them at night).
static var glass: Array = []

var town: SkTownBuilder
var _windows := SurfaceTool.new()      # one storey of office / flat windows per picture
var _shop := SurfaceTool.new()         # a shopfront bay per picture
var _house := SurfaceTool.new()        # a house window per picture

func _init(t: SkTownBuilder) -> void:
	town = t
	for st in [_windows, _shop, _house]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

## Dress one wall (a to b on the map, facing n, h tall) of a building of this kind (street: it faces a street;
## tools/osm_to_town.gd works that out). Plain coloured bits (doors, the
## awning, the band along the top) go into `st`, the building's own mesh. `look` is the front it has on Street
## View (see SkTownBuilder._block), "" for the usual one for its kind; `bands` its bands of colour (see _bands).
func wall(st: SurfaceTool, a: Vector2, b: Vector2, n2: Vector2, h: float, kind: String, wall_col: Color, street: bool, look := "", bands := "") -> void:
	var len := a.distance_to(b)
	var n := Vector3(n2.x, 0, n2.y)
	# the darker band along the top
	_flat_quad(st, a, b, n, h - 0.32, h - 0.04, OUT * 0.75, wall_col.darkened(0.22))
	if bands != "":
		_bands(st, a, b, n, h, street, bands)
	if len < 2.5 or h < 2.4:
		return
	var d := (b - a) / len
	var mid := (a + b) / 2.0
	var bays := maxi(1, roundi((len - 0.6) / BAY))
	var a1 := a + d * 0.3
	var b1 := b - d * 0.3
	if look != "" and _look(st, a1, b1, mid, d, n, h, bays, look, street):
		return
	if kind in PLAIN:
		if street and len >= 5.0 and h >= 4.0:             # a roller door
			_flat_quad(st, mid - d * 1.8, mid + d * 1.8, n, 0.0, minf(3.4, h - 0.8), OUT, ROLLER)
			for k in 7:
				var y := 0.45 * (k + 1)
				_flat_quad(st, mid - d * 1.8, mid + d * 1.8, n, y, y + 0.05, OUT * 2.0, ROLLER.darkened(0.2))
		return
	if kind in HOUSES:
		_picture(_house, a1, b1, n, 0.0, minf(STOREY, h - 0.3), bays, 1.0)
		if street:
			_flat_quad(st, mid - d * 0.5, mid + d * 0.5, n, 0.0, 2.2, OUT * 2.0, HOUSE_DOOR)
		return
	var floors := maxi(1, floori((h - 0.4) / STOREY))
	if street and kind in SHOPS and h >= 3.6:
		# a glass shopfront along the street, a door in the middle of it, an awning over the footpath
		_picture(_shop, a1, b1, n, 0.0, STOREY, bays, 1.0)
		_flat_quad(st, mid - d * 0.8, mid + d * 0.8, n, 0.0, 2.5, OUT * 2.0, DOOR)
		if len >= 6.0 and h <= 14.0:
			_awning(st, a1, b1, n, 3.05, 1.7)
		if floors > 1:
			_picture(_windows, a1, b1, n, STOREY, STOREY * floors, bays, floors - 1)
	else:
		_picture(_windows, a1, b1, n, 0.0, STOREY * floors, bays, floors)
		if street:
			_flat_quad(st, mid - d * 0.7, mid + d * 0.7, n, 0.0, 2.4, OUT * 2.0, DOOR)
	# a slim ledge along each floor line (a string course), so the wall has some depth (on the walls facing a street: elsewhere it'd cost more than it shows)
	if floors > 1 and street:
		for fl in range(1, floors):
			_ledge(st, a, b, n, STOREY * fl - 0.06, wall_col.lightened(0.12))

## Bands of colour across a wall, as Street View shows them: a sign band, a fascia, a coloured base. `bands` is a
## list like "#1d3a9a@0-0.9,s#0a0a0a@3.3-5": a colour, then from and to (metres up); an "s" in front means only on
## the walls that face the street.
func _bands(st: SurfaceTool, a: Vector2, b: Vector2, n: Vector3, h: float, street: bool, bands: String) -> void:
	for item in bands.split(","):
		var s := item.strip_edges()
		if s.begins_with("s"):
			if not street:
				continue
			s = s.substr(1)
		var at := s.split("@")
		if at.size() < 2:
			continue
		var ys := at[1].split("-")
		var y0 := float(ys[0])
		var y1 := minf(float(ys[1]), h - 0.04)
		if y1 > y0:
			_flat_quad(st, a, b, n, y0, y1, OUT * 0.6, Color(at[0]))

## A wall dressed the way Street View shows it (look: shop, shopn, win, glass, blank, car). False if there's
## nothing special about this wall (a shop's side and back walls get the usual windows).
func _look(st: SurfaceTool, a1: Vector2, b1: Vector2, mid: Vector2, d: Vector2, n: Vector3, h: float, bays: int, look: String, street: bool) -> bool:
	var floors := maxi(1, floori((h - 0.4) / STOREY))
	match look:
		"blank":                                               # a plain wall: a big store's, a warehouse's
			if street and h >= 4.0:
				_flat_quad(st, mid - d * 0.9, mid + d * 0.9, n, 0.0, 2.4, OUT * 2.0, DOOR)
			return true
		"car":                                                 # a car park's open decks
			for k in floors:
				var y := STOREY * k
				_flat_quad(st, a1, b1, n, y + 1.1, y + STOREY - 0.2, OUT, CAR_PARK)
			return true
		"glass":                                               # glass all the way up
			_picture(_shop, a1, b1, n, 0.0, STOREY * floors, bays, floors)
			if street:
				_flat_quad(st, mid - d * 0.8, mid + d * 0.8, n, 0.0, 2.5, OUT * 2.0, DOOR)
			return true
		"win":
			_picture(_windows, a1, b1, n, 0.0, STOREY * floors, bays, floors)
			if street:
				_flat_quad(st, mid - d * 0.7, mid + d * 0.7, n, 0.0, 2.4, OUT * 2.0, DOOR)
			return true
		"shop", "shopn":
			if not street or h < 3.6:
				return false
			_picture(_shop, a1, b1, n, 0.0, STOREY, bays, 1.0)
			_flat_quad(st, mid - d * 0.8, mid + d * 0.8, n, 0.0, 2.5, OUT * 2.0, DOOR)
			if look == "shop" and a1.distance_to(b1) >= 5.0:
				_awning(st, a1, b1, n, 3.05, 1.7)
			if floors > 1:
				_picture(_windows, a1, b1, n, STOREY, STOREY * floors, bays, floors - 1)
			return true
	return false

## The windows, shopfronts and house windows as three meshes (one material each).
func commit(parent: Node3D) -> void:
	var pics := [[_windows, _window_picture(), "Windows"], [_shop, _shop_picture(), "Shopfronts"],
		[_house, _house_picture(), "HouseWindows"]]
	for p in pics:
		var mi := MeshInstance3D.new()
		mi.name = p[2]
		mi.mesh = (p[0] as SurfaceTool).commit()
		var gm := _glass_material(p[1])
		gm.set_shader_parameter("lit", {"Windows": 0.45, "Shopfronts": 0.85, "HouseWindows": 0.35}[p[2]])
		gm.set_shader_parameter("bright", {"Windows": 1.4, "Shopfronts": 0.55, "HouseWindows": 1.2}[p[2]])
		glass.append(gm)
		mi.material_override = gm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)

# ================================================================ shapes

## A flat coloured rectangle on a wall (a to b along it, y0 to y1 up), `out` in front of it, facing n.
static func _flat_quad(st: SurfaceTool, a: Vector2, b: Vector2, n: Vector3, y0: float, y1: float, out: float, c: Color) -> void:
	var o := n * out
	var p0 := Vector3(a.x, y0, a.y) + o
	var p1 := Vector3(b.x, y0, b.y) + o
	var p2 := Vector3(b.x, y1, b.y) + o
	var p3 := Vector3(a.x, y1, a.y) + o
	st.set_normal(n)
	st.set_color(c)
	SkTownBuilder._face(st, p0, p1, p2, n)
	SkTownBuilder._face(st, p0, p2, p3, n)

## A picture repeated along a wall: `across` times along it, `up` times up it.
static func _picture(st: SurfaceTool, a: Vector2, b: Vector2, n: Vector3, y0: float, y1: float, across: float, up: float) -> void:
	var o := n * OUT
	var c := [Vector3(a.x, y0, a.y) + o, Vector3(b.x, y0, b.y) + o, Vector3(b.x, y1, b.y) + o, Vector3(a.x, y1, a.y) + o]
	var uv := [Vector2(0, up), Vector2(across, up), Vector2(across, 0), Vector2(0, 0)]
	for t in [[0, 1, 2], [0, 2, 3]]:
		var order: Array = t
		if (c[t[1]] - c[t[0]]).cross(c[t[2]] - c[t[0]]).dot(n) > 0.0:
			order = [t[0], t[2], t[1]]
		for k in order:
			st.set_normal(n)
			st.set_uv(uv[k])
			st.add_vertex(c[k])

## An awning along a wall at height y, sticking out `deep`: its top, its front edge and its underside.
static func _awning(st: SurfaceTool, a: Vector2, b: Vector2, n: Vector3, y: float, deep: float) -> void:
	var n2 := Vector2(n.x, n.z)
	var fa := a + n2 * deep
	var fb := b + n2 * deep
	var t := 0.16
	st.set_color(AWNING)
	for face in [[Vector3.UP, y + t], [Vector3.DOWN, y]]:
		var up: Vector3 = face[0]
		var fy: float = face[1]
		st.set_normal(up)
		SkTownBuilder._face(st, Vector3(a.x, fy, a.y), Vector3(b.x, fy, b.y), Vector3(fb.x, fy, fb.y), up)
		SkTownBuilder._face(st, Vector3(a.x, fy, a.y), Vector3(fb.x, fy, fb.y), Vector3(fa.x, fy, fa.y), up)
	_flat_quad(st, fa, fb, n, y, y + t, 0.0, AWNING.darkened(0.15))

# ================================================================ the pictures (32 x 32 pixels, one bay each)

static func _image() -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	img.fill_rect(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1), c)

static func _texture(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## An office / flat window: framed glass with a bar down the middle and a sill.
static func _window_picture() -> ImageTexture:
	var img := _image()
	_rect(img, 6, 6, 25, 23, FRAME)
	_rect(img, 7, 7, 24, 22, GLASS)
	_rect(img, 7, 7, 24, 9, GLASS_HI)
	_rect(img, 15, 7, 16, 22, FRAME)
	_rect(img, 5, 24, 26, 25, SILL)
	return _texture(img)

## A shopfront bay: tall glass down to the footpath between dark posts, a dark bar along the top.
static func _shop_picture() -> ImageTexture:
	var img := _image()
	_rect(img, 0, 6, 31, 7, SHOP_FRAME)
	_rect(img, 0, 8, 1, 31, SHOP_FRAME)
	_rect(img, 30, 8, 31, 31, SHOP_FRAME)
	_rect(img, 2, 8, 29, 29, GLASS)
	_rect(img, 2, 8, 29, 11, GLASS_HI)
	for k in 6:                                            # a streak of reflection
		_rect(img, 18 + k, 12 + k * 2, 19 + k, 13 + k * 2, GLASS_HI)
	_rect(img, 0, 30, 31, 31, SHOP_FRAME)
	return _texture(img)

## A house window: white frame, a cross of glazing bars.
static func _house_picture() -> ImageTexture:
	var img := _image()
	_rect(img, 9, 9, 22, 22, Color("#f1efe8"))
	_rect(img, 10, 10, 21, 21, GLASS)
	_rect(img, 10, 10, 21, 11, GLASS_HI)
	_rect(img, 15, 10, 16, 21, Color("#f1efe8"))
	_rect(img, 10, 15, 21, 16, Color("#f1efe8"))
	_rect(img, 8, 23, 23, 23, SILL)
	return _texture(img)

## A slim ledge along a wall at height y: its front, its top and (darker) its underside, sticking out 0.12 m.
static func _ledge(st: SurfaceTool, a: Vector2, b: Vector2, n: Vector3, y: float, c: Color) -> void:
	var t := 0.12
	_flat_quad(st, a, b, n, y, y + t, 0.12, c)
	var n2 := Vector2(n.x, n.z)
	var fa := a + n2 * 0.12
	var fb := b + n2 * 0.12
	for face in [[Vector3.UP, y + t, c.lightened(0.1)], [Vector3.DOWN, y, c.darkened(0.35)]]:
		var up: Vector3 = face[0]
		var fy: float = face[1]
		st.set_normal(up)
		st.set_color(face[2])
		SkTownBuilder._face(st, Vector3(a.x, fy, a.y), Vector3(b.x, fy, b.y), Vector3(fb.x, fy, fb.y), up)
		SkTownBuilder._face(st, Vector3(a.x, fy, a.y), Vector3(fb.x, fy, fb.y), Vector3(fa.x, fy, fa.y), up)

## The windows' glass catching the sky (there are no real reflections in the plain renderer): where a picture's pixel
## is glass (bluish), the sky's colour is mixed in, more the more side-on you see it, and the street's darker colour
## where the reflection would be looking down; the frames stay as they are.
static func _glass_material(pic: Texture2D) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back;
uniform sampler2D pic : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec3 sky_top : source_color = vec3(0.16, 0.45, 0.79);
uniform vec3 sky_low : source_color = vec3(0.66, 0.80, 0.92);
uniform float night = 0.0;
uniform float lit = 0.45;                   // (how many of the windows have a light on at night)
uniform float bright = 1.4;
void fragment() {
	vec4 t = texture(pic, UV);
	if (t.a < 0.5) { discard; }
	vec3 c = t.rgb;
	float glass = step(0.03, c.b - c.r);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 r = reflect(-v, nw);
	float fres = pow(1.0 - clamp(dot(v, nw), 0.0, 1.0), 2.5);
	vec3 sky = mix(sky_low, sky_top, clamp(r.y * 2.5, 0.0, 1.0));
	if (r.y < 0.0) { sky = sky_low * 0.35; }
	c = mix(c, sky, glass * (0.3 + 0.55 * fres) * (1.0 - night * 0.8));
	// at night: some windows lit, a warm glow (each window picture its own: on or off)
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float key = dot(floor(w / vec3(2.9, 3.2, 2.9)), vec3(12.9898, 78.233, 37.719));
	float on = step(1.0 - lit, fract(sin(key) * 43758.5453));
	EMISSION = vec3(1.0, 0.78, 0.48) * glass * on * night * bright * (0.75 + 0.25 * fract(key * 7.13));
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.12, glass);
	SPECULAR = mix(0.3, 0.9, glass);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("pic", pic)
	return m
