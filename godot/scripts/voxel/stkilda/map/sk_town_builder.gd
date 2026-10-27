# (Copied from stkilda-godot scripts/town/town_builder.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkTownBuilder
extends RefCounted
## Builds the town from data/town.json (OpenStreetMap, made by tools/osm_to_town.gd): dry grass everywhere, the
## parks greener, Victoria Park Lake and the creeks, the railway, every road (asphalt, with a footpath band each
## side), and every building as a plain grey block at its real outline. Postcard scale: distances are half the
## real ones (town.json's "scale"), road widths and building heights are full size.
##
## Businesses go on lots: lot_at() finds the spot for a street address on its street and hands back a Node3D
## facing the street (a business scene's front faces +z, its kerb line at z = kerb), and clears the map's own
## buildings off that patch first.
##
## Game axes: x east, z south (north is -z), y up; the origin is the Maude St Mall.

const C_GROUND := Color("#999a5c")        # dry grass, a touch greener than the workshop's
const C_PARK := Color("#7f9a52")
const C_PITCH := Color("#6f9a4a")
const C_WATER := Color("#4f86a6")
const C_SEA := Color("#3f7fa3")
const C_SAND_EDGE := Color("#d8c89a")      # where the sea meets the land: a strip of wet sand
const C_DECK := Color("#9a7b58")           # the piers' timber decks
const C_ROCK := Color("#7c7a73")           # the breakwater and groynes
const C_WATER_EDGE := Color("#8a8460")
const C_ROAD := SkData.C_ASPHALT
const C_PATH := SkData.C_PATH
const C_MALL := Color("#cdbfa8")
const C_MEDIAN := Color("#8fa858")      # the grass down the middle of a divided road
const C_BALLAST := Color("#7d766c")
const C_RAIL := Color("#5a5650")
const GREYS := [Color("#b9b7b2"), Color("#aeaca7"), Color("#c4c2bc"), Color("#a5a39f"), Color("#bdbab3")]
## Wall colours by kind of building, like Shepparton's streets: houses in red and cream brick, render and
## weatherboard; the town centre's shops painted cream, sand, terracotta, sage and grey above the awnings, some
## bare red brick; sheds and factories in Colorbond greys and creams; the big stores in tilt-up concrete.
const WALLS := {
	"house": [Color("#b0624a"), Color("#c48560"), Color("#a5573f"), Color("#e4d9c3"), Color("#d8c8ab"), Color("#efe8da"),
		Color("#c9b79a"), Color("#9c6650")],
	"shop": [Color("#e8dfcb"), Color("#d9c6a2"), Color("#c99d78"), Color("#b6bdb6"), Color("#e7d6bd"), Color("#a9b8a3"),
		Color("#b5674c"), Color("#dcd3c4"), Color("#c3a98a")],
	"shed": [Color("#c7cac5"), Color("#a1a8aa"), Color("#8a948f"), Color("#d6d1c4"), Color("#b9bdb4"), Color("#6f7b7c")],
	"big": [Color("#d6d2c8"), Color("#cbc6ba"), Color("#ddd8cc")],
	"civic": [Color("#b9705a"), Color("#d8cfbd"), Color("#c4b9a5")],
}

## Which colour set a building takes.
static func _palette(kind: String, area: float) -> Array:
	if kind in SkFacades.HOUSES:
		return WALLS.house
	if kind in SkFacades.PLAIN:
		return WALLS.shed
	if kind in ["college", "university", "school", "church", "hall", "police", "fire_station", "train_station", "hospital"]:
		return WALLS.civic
	if area > 2500.0:
		return WALLS.big
	return WALLS.shop
const PATH_W := 3.0                        # each footpath band
## The kinds of ground (tools/osm_to_town.gd sorts the map's land use into these): its colour, and how high it lies
## (the layers stack: plain grass 0, these, parks 0.03, the car parks and courts over those).
const AREAS := {
	"homes": [Color("#a2a966"), 0.012], "shops": [Color("#b5b09e"), 0.012], "industry": [Color("#aaa38e"), 0.012],
	"paddock": [Color("#b8a960"), 0.012], "school": [Color("#a3b469"), 0.018], "grass": [Color("#8fa858"), 0.022],
	"wood": [Color("#6f8848"), 0.022], "orchard": [Color("#7f9a4e"), 0.022],
	"oval": [Color("#6aa04a"), 0.034], "court": [Color("#3f7f63"), 0.036], "playground": [Color("#c4a070"), 0.036],
	"parking": [Color("#5b6067"), 0.04],
	"beach": [Color("#e3d4a8"), 0.024],
}
const NO_PATH := ["service", "pedestrian", "trunk_link", "primary_link", "secondary_link", "tertiary_link"]


var root: Node3D
var sun: DirectionalLight3D
var environment: Environment
var data: Dictionary
var bounds := Rect2()                      # everything on the map (x, z)
var _segs := []                            # road centre-line pieces for street names: [a, b, name, half width]
var _grid := {}                            # 50 m cells -> indices into _segs
var _cleared := []                         # [Transform3D of a lot, its Rect2 in lot space] (no map buildings)
var skip := {}                             # the map's buildings (ids) to leave out: the Scenic Railway runs through them
var _font: SystemFont

func build(parent: Node3D, lots: Array = []) -> Node3D:
	root = Node3D.new()
	root.name = "Town"
	parent.add_child(root)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Arial Black", "Impact", "sans-serif"])
	_font.font_weight = 900
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/stkilda/town.json"))
	_index_roads()
	_cleared = lots
	_light()
	_flat_things()
	_buildings()
	_landmarks()
	SkTownTrees.new().build(self)
	SkTownRoads.new().build(self)
	return root

## Map coordinates (game metres) for a latitude / longitude.
func project(lat: float, lon: float) -> Vector2:
	var lat0: float = data.origin[0]
	var lon0: float = data.origin[1]
	var s: float = data.scale
	return Vector2((lon - lon0) * 111320.0 * cos(deg_to_rad(lat0)) * s, -(lat - lat0) * 110574.0 * s)

static func _pts(flat: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		p.append(Vector2(flat[i], flat[i + 1]))
	return p

# ================================================================ lots

## Where a business at (lat, lon) on `street` goes: the nearest point on that street, the lot on the address's
## side of it, turned so its +z faces the street, with its kerb line (z = kerb, lot space) on the road's edge.
## Pass the result (with the lot's rect, lot space) to build() so the map's own buildings there are left out.
func lot_at(lat: float, lon: float, street: String, kerb: float) -> Transform3D:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string("res://data/stkilda/town.json"))
	var at := project(lat, lon)
	var best := INF
	var on := Vector2.ZERO
	var half := 4.5
	for r in data.roads:
		if r.n != street:
			continue
		var p := _pts(r.p)
		for i in p.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(at, p[i], p[i + 1])
			if q.distance_to(at) < best:
				best = q.distance_to(at)
				on = q
				half = r.w / 2.0
	var out := (at - on).normalized()          # from the street toward the lot
	if best == INF or out == Vector2.ZERO:
		return Transform3D(Basis(), Vector3(at.x, 0, at.y))
	var face := -out                           # the lot's +z points at the street
	var yaw := atan2(face.x, face.y)
	var origin := on + out * (half + kerb)
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(origin.x, 0, origin.y))

func _in_lot(c: Vector2) -> bool:
	for l in _cleared:
		var xf: Transform3D = l[0]
		var local := xf.affine_inverse() * Vector3(c.x, 0, c.y)
		if (l[1] as Rect2).has_point(Vector2(local.x, local.z)):
			return true
	return false

# ================================================================ street names

func _index_roads() -> void:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for r in data.roads:
		var p := _pts(r.p)
		for v in p:
			lo = lo.min(v)
			hi = hi.max(v)
		bounds = Rect2(lo, hi - lo)
		if r.n == "":
			continue
		for i in p.size() - 1:
			var k := _segs.size()
			_segs.append([p[i], p[i + 1], r.n, r.w / 2.0])
			var a := p[i].min(p[i + 1]) - Vector2(10, 10)
			var b := p[i].max(p[i + 1]) + Vector2(10, 10)
			for cx in range(floori(a.x / 50.0), floori(b.x / 50.0) + 1):
				for cz in range(floori(a.y / 50.0), floori(b.y / 50.0) + 1):
					var key := Vector2i(cx, cz)
					if not _grid.has(key):
						_grid[key] = []
					_grid[key].append(k)

## The street you're on (or right next to), or "" off the roads.
func street_at(pos: Vector3) -> String:
	var at := Vector2(pos.x, pos.z)
	var best := INF
	var name := ""
	for k in _grid.get(Vector2i(floori(at.x / 50.0), floori(at.y / 50.0)), []):
		var s: Array = _segs[k]
		var d: float = Geometry2D.get_closest_point_to_segment(at, s[0], s[1]).distance_to(at) - s[3]
		if d < best:
			best = d
			name = s[2]
	return name if best < 6.0 else ""

## The nearest named road to a map point (looking up to 50 m or so): [how far to its edge, the nearest point on
## its middle]. [99, at] if there's none that close.
func _nearest_road(at: Vector2) -> Array:
	var best := 99.0
	var on := at
	var cell := Vector2i(floori(at.x / 50.0), floori(at.y / 50.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for k in _grid.get(cell + Vector2i(dx, dz), []):
				var s: Array = _segs[k]
				var q := Geometry2D.get_closest_point_to_segment(at, s[0], s[1])
				var d: float = q.distance_to(at) - s[3]
				if d < best:
					best = maxf(d, 0.0)
					on = q
	return [best, on]

## How far a map point is from the nearest street's edge.
func road_gap(at: Vector2) -> float:
	return _nearest_road(at)[0]

## Which way the nearest street is from a map point (unit vector; south if there's none near).
func toward_road(at: Vector2) -> Vector2:
	var on: Vector2 = _nearest_road(at)[1]
	return (on - at).normalized() if on.distance_to(at) > 0.1 else Vector2(0, 1)

## Is this map point on a business's lot (where the map's own buildings are left out)?
func in_lot(c: Vector2) -> bool:
	return _in_lot(c)

# ================================================================ light

func _light() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(150.0), 0.0)     # (from the north, as in Melbourne: north fronts are sunny)
	sun.light_energy = 0.55
	sun.light_color = Color("#fff4e2")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	root.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#3d8fd6")
	sm.sky_horizon_color = Color("#cfe6f5")
	sm.ground_horizon_color = Color("#a9cbdb")      # (below the horizon: hazy sea, out over Port Phillip)
	sm.ground_bottom_color = C_SEA
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#d3dbe6")
	e.ambient_light_energy = 0.3
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.fog_enabled = true                      # the far edge of the map fades into haze
	e.fog_light_color = Color("#cfe0ec")
	e.fog_density = 0.0006
	e.fog_sky_affect = 0.0
	env.environment = e
	environment = e
	root.add_child(env)

# ================================================================ the flat things: ground, parks, water, roads

## Everything that lies flat goes into one mesh (vertex colours), layered a few centimetres apart (enough for the depth buffer from a long way off) so the right
## one shows on top: ground, parks, water, footpaths, railway, roads.
func _flat_things() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var b := bounds.grow(160.0)
	_quad(st, b, 0.0, C_GROUND)
	# the ground under it all: houses' gardens, shops' paving, industry's gravel, school grounds, woods, paddocks
	for a in data.get("areas", []):
		if AREAS[a.k][1] < 0.03:
			_poly(st, _pts(a.p), AREAS[a.k][1], AREAS[a.k][0], a.get("i", []))
	for p in data.parks:
		_poly(st, _pts(p.p), 0.03, C_PITCH if p.k == "pitch" else C_PARK, p.get("i", []))
	# on top of the parks: playgrounds, ovals and courts with their white lines, car parks and their bays
	for a in data.get("areas", []):
		if AREAS[a.k][1] >= 0.03:
			var ring := _pts(a.p)
			_poly(st, ring, AREAS[a.k][1], AREAS[a.k][0], a.get("i", []))
			if a.k in ["oval", "court"]:
				_line(st, ring, 0.35 if a.k == "oval" else 0.15, AREAS[a.k][1] + 0.004, SkData.C_LINE, false)
	for bay in data.get("bays", []):
		_line(st, _pts(bay), 0.1, 0.046, SkData.C_LINE, false)
	for w in data.water:
		var ring := _pts(w.p)
		var sea: bool = w.get("sea", false)
		_line(st, ring, 4.0 if sea else 2.4, 0.05, C_SAND_EDGE if sea else C_WATER_EDGE, false)
		_poly(st, ring, 0.07, C_SEA if sea else C_WATER, w.get("i", []))
	# the piers' decks, the breakwater's and groynes' rocks, over the sea
	for pr in data.get("piers", []):
		var col := C_DECK if pr.k == "pier" else C_ROCK
		if pr.a:
			_poly(st, _pts(pr.p), 0.09, col)
		else:
			_line(st, _pts(pr.p), float(pr.w), 0.09, col, true)
	for s in data.streams:
		_line(st, _pts(s.p), s.w, 0.07, C_WATER, true)
	for r in data.roads:
		if not (r.k in NO_PATH) and not _in_any_lot(r):
			if r.get("o", false) and not r.get("j", false) and r.k in ["trunk", "primary", "secondary"]:
				# one side of a divided road: the footpath on its left (we drive on the left), a grass median on
				# its right, between it and the other side
				var p := _pts(r.p)
				_line(st, _offset(p, r.w / 2.0 + PATH_W / 2.0), PATH_W, 0.10, C_PATH, true)
				_line(st, _offset(p, -(r.w / 2.0 + 2.0)), 4.0, 0.10, C_MEDIAN, true)
			else:
				_line(st, _pts(r.p), r.w + PATH_W * 2.0, 0.10, C_PATH, true)
	# a mall's paving, shopfront to shopfront, under its slow lane (the Maude St Mall)
	for r in data.roads:
		if String(r.n).ends_with(" Mall"):
			_line(st, _pts(r.p), 22.0, 0.12, C_MALL, true)
	for r in data.rails:
		_line(st, _pts(r.p), 3.4, 0.12, C_BALLAST, true)
	# roads over everything (the busier ones on top, so junctions read right)
	var order: Array = data.roads.duplicate()
	order.sort_custom(func(a, c): return _rank(a.k) < _rank(c.k))
	for r in order:
		if r.k == "service" and _in_any_lot(r):
			continue
		_line(st, _pts(r.p), r.w, 0.16 if r.k == "pedestrian" else 0.14, C_MALL if r.k == "pedestrian" else C_ROAD, true)
	for r in data.rails:
		for side in [-0.72, 0.72]:
			_line(st, _offset(_pts(r.p), side), 0.12, 0.2, C_RAIL, false)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	mi.material_override = SkModels.baked_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# one big flat floor to drive and walk on
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = SkData.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(b.size.x, 1.0, b.size.y)
	cs.shape = bs
	cs.position = Vector3(b.get_center().x, -0.5, b.get_center().y)
	body.add_child(cs)
	root.add_child(body)
	_lake_edges()
	_map_edge(b.grow(-60.0))

static func _rank(k: String) -> int:
	return {"service": 0, "pedestrian": 1, "residential": 2, "unclassified": 2, "tertiary_link": 3, "tertiary": 4,
		"secondary_link": 5, "secondary": 6, "primary_link": 7, "primary": 8, "trunk_link": 9, "trunk": 10}.get(k, 0)

func _in_any_lot(r: Dictionary) -> bool:
	if _cleared.is_empty():
		return false
	var p := _pts(r.p)
	var c := Vector2.ZERO
	for v in p:
		c += v
	return _in_lot(c / p.size())

func _quad(st: SurfaceTool, r: Rect2, y: float, c: Color) -> void:
	var a := Vector3(r.position.x, y, r.position.y)
	var bb := Vector3(r.end.x, y, r.position.y)
	var cc := Vector3(r.end.x, y, r.end.y)
	var d := Vector3(r.position.x, y, r.end.y)
	_tri(st, a, bb, cc, c)
	_tri(st, a, cc, d, c)

## One upward-facing triangle (wound so its face points up).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).y < 0.0:
		var t := b
		b = c
		c = t
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)

## An area filled in (its triangles from the map data when it has them: tools/osm_to_town.gd works them out).
func _poly(st: SurfaceTool, ring: PackedVector2Array, y: float, c: Color, tris: Array = []) -> void:
	if ring.size() > 3 and ring[0].is_equal_approx(ring[-1]):
		ring.remove_at(ring.size() - 1)
	var idx := PackedInt32Array(tris) if not tris.is_empty() else Geometry2D.triangulate_polygon(ring)
	for i in range(0, idx.size(), 3):
		_tri(st, Vector3(ring[idx[i]].x, y, ring[idx[i]].y), Vector3(ring[idx[i + 1]].x, y, ring[idx[i + 1]].y),
			Vector3(ring[idx[i + 2]].x, y, ring[idx[i + 2]].y), c)

## A strip of width w along a line, with round-ish joints (an octagon at each point) so bends and junctions fill.
func _line(st: SurfaceTool, p: PackedVector2Array, w: float, y: float, c: Color, joints: bool) -> void:
	var h := w / 2.0
	for i in p.size() - 1:
		var d := (p[i + 1] - p[i])
		if d.length() < 0.01:
			continue
		var n := d.normalized().orthogonal() * h
		var a := p[i] + n
		var b := p[i] - n
		var e := p[i + 1] - n
		var f := p[i + 1] + n
		_tri(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(e.x, y, e.y), c)
		_tri(st, Vector3(a.x, y, a.y), Vector3(e.x, y, e.y), Vector3(f.x, y, f.y), c)
	if joints:
		for v in p:
			for k in 8:
				var a0 := TAU * k / 8.0
				var a1 := TAU * (k + 1) / 8.0
				_tri(st, Vector3(v.x, y, v.y), Vector3(v.x + cos(a0) * h, y, v.y + sin(a0) * h),
					Vector3(v.x + cos(a1) * h, y, v.y + sin(a1) * h), c)

static func _offset(p: PackedVector2Array, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in p.size():
		var d := (p[mini(i + 1, p.size() - 1)] - p[maxi(i - 1, 0)]).normalized()
		out.append(p[i] + d.orthogonal() * by)
	return out

## You can't drive into the lake: a low invisible wall round each bit of water (left open where a road crosses).
func _lake_edges() -> void:
	var body := StaticBody3D.new()
	body.name = "WaterEdge"
	body.collision_layer = SkData.LAYER_WORLD
	body.collision_mask = 0
	root.add_child(body)
	# every road piece, filed by the 50 m squares it passes through (so each bit of shore only looks at the roads
	# near it: checking them all, all round every lake and creek, took half a minute)
	var cells := {}
	for r in data.roads:
		var p := _pts(r.p)
		for i in p.size() - 1:
			var pad: float = r.w / 2.0 + 2.0
			var c := [p[i], p[i + 1], pad]
			var lo := p[i].min(p[i + 1]) - Vector2.ONE * pad
			var hi := p[i].max(p[i + 1]) + Vector2.ONE * pad
			for cx in range(floori(lo.x / 50.0), floori(hi.x / 50.0) + 1):
				for cz in range(floori(lo.y / 50.0), floori(hi.y / 50.0) + 1):
					var key := Vector2i(cx, cz)
					if not cells.has(key):
						cells[key] = []
					cells[key].append(c)
	# the piers (and rocks) you can walk out on: the shore's left open where one meets it, and its own sides walled
	# where they're over the sea (like a railing)
	var decks := []
	for pr in data.get("piers", []):
		var p := _pts(pr.p)
		if not pr.a:
			var l := _offset(p, float(pr.w) / 2.0)
			var r := _offset(p, -float(pr.w) / 2.0)
			r.reverse()
			l.append_array(r)
			p = l
		if p.size() > 3 and p[0].is_equal_approx(p[-1]):
			p.remove_at(p.size() - 1)
		decks.append(p)
		var lo := Vector2(INF, INF)
		var hi := -lo
		for v in p:
			lo = lo.min(v)
			hi = hi.max(v)
		for cx in range(floori((lo.x - 3.0) / 50.0), floori((hi.x + 3.0) / 50.0) + 1):
			for cz in range(floori((lo.y - 3.0) / 50.0), floori((hi.y + 3.0) / 50.0) + 1):
				var key := Vector2i(cx, cz)
				if not cells.has(key):
					cells[key] = []
				cells[key].append([p])
	var seas := []
	for w in data.water:
		if w.get("sea", false):
			seas.append(_pts(w.p))
	var faces := PackedVector3Array()
	for p in decks:
		for i in p.size():
			var a0: Vector2 = p[i]
			var b0: Vector2 = p[(i + 1) % p.size()]
			var parts := maxi(1, ceili(a0.distance_to(b0) / 5.0))
			for k in parts:
				var a := a0.lerp(b0, float(k) / parts)
				var b := a0.lerp(b0, float(k + 1) / parts)
				var mid := (a + b) / 2.0
				var side := (b - a).normalized().orthogonal() * 0.6
				var wet := false
				for s in seas:
					if Geometry2D.is_point_in_polygon(mid, s):
						wet = true
				var joined := false             # (where two decks meet, it's open)
				for q in decks:
					if q != p and (Geometry2D.is_point_in_polygon(mid + side, q) or Geometry2D.is_point_in_polygon(mid - side, q)):
						joined = true
				if wet and not joined:
					var up := Vector3(0, 1.2, 0)
					faces.append_array(PackedVector3Array([Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, 0, b.y) + up,
						Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y) + up, Vector3(a.x, 0, a.y) + up]))
	for w in data.water:
		var ring := _pts(w.p)
		for i in ring.size() - 1:
			# (in bits of 5 m or less: a long stretch of shore with a bridge across one end of it was walled off whole,
			# right across the road, since only its middle was checked)
			var parts := maxi(1, ceili(ring[i].distance_to(ring[i + 1]) / 5.0))
			for k in parts:
				var a := ring[i].lerp(ring[i + 1], float(k) / parts)
				var b := ring[i].lerp(ring[i + 1], float(k + 1) / parts)
				var mid := (a + b) / 2.0
				var open := false
				for c in cells.get(Vector2i(floori(mid.x / 50.0), floori(mid.y / 50.0)), []):
					if c.size() == 1:             # a pier's deck
						if Geometry2D.is_point_in_polygon(mid, c[0]):
							open = true
							break
					elif Geometry2D.get_closest_point_to_segment(mid, c[0], c[1]).distance_to(mid) < c[2]:
						open = true
						break
				if not open:
					var a0 := Vector3(a.x, 0, a.y)
					var b0 := Vector3(b.x, 0, b.y)
					var up := Vector3(0, 1.2, 0)
					faces.append_array(PackedVector3Array([a0, b0, b0 + up, a0, b0 + up, a0 + up]))
	# all of it one shape
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)

## And an invisible fence round the whole map.
func _map_edge(r: Rect2) -> void:
	var body := StaticBody3D.new()
	body.name = "MapEdge"
	body.collision_layer = SkData.LAYER_WORLD
	body.collision_mask = 0
	root.add_child(body)
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		_wall(body, c[i], c[(i + 1) % 4], 30.0)

static func _wall(body: StaticBody3D, a: Vector2, b: Vector2, h: float) -> void:
	var len := a.distance_to(b)
	if len < 0.05:
		return
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(len + 0.3, h, 0.3)
	cs.shape = bs
	var m := (a + b) / 2.0
	cs.position = Vector3(m.x, h / 2.0, m.y)
	cs.rotation.y = -atan2(b.y - a.y, b.x - a.x)
	body.add_child(cs)

# ================================================================ buildings

## Every building on the map as a plain grey block: walls up its outline, a flat roof, a few greys so neighbours
## read apart. One mesh, one collision trimesh (the walls).
func _buildings() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := PackedVector3Array()
	var fronts := SkFacades.new(self)
	var i := 0
	for bd in data.buildings:
		var ring := _pts(bd.p)
		if ring.size() > 3 and ring[0].is_equal_approx(ring[-1]):
			ring.remove_at(ring.size() - 1)
		if ring.size() < 3:
			continue
		var c := Vector2.ZERO
		for v in ring:
			c += v
		c /= ring.size()
		if _in_lot(c) or skip.has(bd.get("id", "")):
			continue
		i += 1
		var pal := _palette(String(bd.k), absf(_ring_area(ring)))
		var col: Color = Color(bd.c) if bd.has("c") else pal[hash(bd.p[0]) % pal.size()]
		_block(st, walls, ring, float(bd.h), col, fronts, String(bd.k), bd.get("s", []).map(func(x): return int(x)), String(bd.get("f", "")), String(bd.get("bands", "")))
	var mi := MeshInstance3D.new()
	mi.name = "Buildings"
	mi.mesh = st.commit()
	mi.material_override = SkModels.baked_material()
	root.add_child(mi)
	fronts.commit(root)
	var body := StaticBody3D.new()
	body.name = "BuildingWalls"
	body.collision_layer = SkData.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(walls)
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)

## One building: its walls (dressed by SkFacades), and a flat roof or a house's hip roof. `look` is its front as seen on
## Street View (tools/osm_to_town.gd: shop, shopn, win, glass, blank, car), "" for the usual one for its kind;
## `bands` its bands of colour (SkFacades._bands).
func _block(st: SurfaceTool, walls: PackedVector3Array, ring: PackedVector2Array, h: float, col: Color, fronts: SkFacades = null, kind := "yes", street_walls: Array = [], look := "", bands := "") -> void:
	if kind in ["roof", "carport"]:
		_canopy(st, ring, h)
		return
	# a house: single-storey walls (two-storey if it's tall) under a hip roof
	var house := kind in SkFacades.HOUSES and ring.size() <= 12
	if house:
		h = 2.9 if h < 6.5 else 5.8
	for k in ring.size():
		var a := ring[k]
		var b := ring[(k + 1) % ring.size()]
		var d := b - a
		if d.length() < 0.01:
			continue
		# the wall faces whichever side is outside the outline
		var n2 := d.normalized().orthogonal()
		if Geometry2D.is_point_in_polygon((a + b) / 2.0 + n2 * 0.05, ring):
			n2 = -n2
		var n := Vector3(n2.x, 0, n2.y)
		var shade: Color = col.darkened(0.12 if absf(n.x) > absf(n.z) else 0.0)
		var p0 := Vector3(a.x, 0, a.y)
		var p1 := Vector3(b.x, 0, b.y)
		var p2 := Vector3(b.x, h, b.y)
		var p3 := Vector3(a.x, h, a.y)
		st.set_normal(n)
		st.set_color(shade)
		_face(st, p0, p1, p2, n)
		_face(st, p0, p2, p3, n)
		walls.append_array(PackedVector3Array([p0, p1, p2, p0, p2, p3]))
		if fronts:
			fronts.wall(st, a, b, n2, h, kind, shade, k in street_walls, look, bands)
	if house:
		_hip_roof(st, ring, h)
		return
	st.set_normal(Vector3.UP)
	var idx := Geometry2D.triangulate_polygon(ring)
	var roof: Color = FLAT_ROOFS[hash(ring[0]) % FLAT_ROOFS.size()]
	for k in range(0, idx.size(), 3):
		_tri(st, Vector3(ring[idx[k]].x, h, ring[idx[k]].y), Vector3(ring[idx[k + 1]].x, h, ring[idx[k + 1]].y),
			Vector3(ring[idx[k + 2]].x, h, ring[idx[k + 2]].y), roof)

## A triangle facing n (Godot draws the side where the corners go clockwise).
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.add_vertex(a)
	if (b - a).cross(c - a).dot(n) > 0.0:
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(b)
		st.add_vertex(c)

## A business's name floating over the map's own building at (lat, lon) (the nearest one within 60 m), for one
## that isn't built properly yet. Returns where it is (map x, z).
func name_sign(lat: float, lon: float, text: String, c: Color) -> Vector2:
	var at := project(lat, lon)
	var spot := at
	var top := 6.0
	var best := 60.0
	for bd in data.buildings:
		var ring := _pts(bd.p)
		var mid := Vector2.ZERO
		for v in ring:
			mid += v
		mid /= ring.size()
		if mid.distance_to(at) < best:
			best = mid.distance_to(at)
			top = bd.h
			spot = mid
	var l := Label3D.new()
	l.name = text
	l.text = text
	l.font = _font
	l.font_size = 96
	l.pixel_size = 4.0 / 96.0
	l.modulate = c
	l.outline_modulate = Color("#1a1c2c")
	l.outline_size = 16
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = Vector3(spot.x, top + 4.0, spot.y)
	root.add_child(l)
	return spot

## The landmarks (scripts/town/landmarks.gd): for now just the pedestrian streets' paving and benches (Acland St
## Plaza). St Kilda's own landmarks come one at a time.
func _landmarks() -> void:
	SkLandmarks.malls(self)

static func _ring_area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in ring.size():
		a += ring[i].cross(ring[(i + 1) % ring.size()])
	return a / 2.0

## Roof colours: houses' tiles and Colorbond (terracotta, red-brown, charcoal, greys), everything else's flat roof
## (zincalume, grey Colorbond, pale membrane).
const HOUSE_ROOFS := [Color("#b4583c"), Color("#a24e38"), Color("#c0694a"), Color("#4b4f55"), Color("#6f777d"),
	Color("#5b6268"), Color("#8c4a3b"), Color("#878f93")]
const FLAT_ROOFS := [Color("#c9cdcf"), Color("#b7bcbf"), Color("#a9aeb1"), Color("#d4d6d2"), Color("#9aa1a5")]
const ROOF_PITCH := 0.42          # rise per metre in (about 23 degrees, a common tiled roof)
const EAVES := 0.45               # how far it overhangs the walls

## A hip roof over a house: on the smallest rectangle round its outline (most houses are rectangles, or nearly),
## with eaves, rising from the top of the walls (y) to a ridge along its length.
func _hip_roof(st: SurfaceTool, ring: PackedVector2Array, y: float) -> void:
	# the smallest rectangle round the outline: try lining it up with each wall
	var best := INF
	var axis := Vector2.RIGHT
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	for k in ring.size():
		var d := ring[(k + 1) % ring.size()] - ring[k]
		if d.length() < 0.5:
			continue
		var u := d.normalized()
		var v := u.orthogonal()
		var a := Vector2(INF, INF)
		var b := -a
		for p in ring:
			var q := Vector2(p.dot(u), p.dot(v))
			a = a.min(q)
			b = b.max(q)
		var area := (b.x - a.x) * (b.y - a.y)
		if area < best:
			best = area
			axis = u
			lo = a
			hi = b
	var u := axis
	var v := u.orthogonal()
	lo -= Vector2.ONE * EAVES
	hi += Vector2.ONE * EAVES
	# along the longer side
	if hi.y - lo.y > hi.x - lo.x:
		var t := u
		u = v
		v = -t
		var a2 := Vector2(INF, INF)
		var b2 := -a2
		for c in [lo, hi, Vector2(lo.x, hi.y), Vector2(hi.x, lo.y)]:
			var p: Vector2 = c.x * axis + c.y * axis.orthogonal()
			var q := Vector2(p.dot(u), p.dot(v))
			a2 = a2.min(q)
			b2 = b2.max(q)
		lo = a2
		hi = b2
	var half := (hi.y - lo.y) / 2.0
	var rise := half * ROOF_PITCH
	var w := func(x: float, z: float, yy: float) -> Vector3:
		var p: Vector2 = u * x + v * z
		return Vector3(p.x, yy, p.y)
	var c0: Vector3 = w.call(lo.x, lo.y, y)
	var c1: Vector3 = w.call(hi.x, lo.y, y)
	var c2: Vector3 = w.call(hi.x, hi.y, y)
	var c3: Vector3 = w.call(lo.x, hi.y, y)
	var r0: Vector3 = w.call(lo.x + half, lo.y + half, y + rise)
	var r1: Vector3 = w.call(hi.x - half, lo.y + half, y + rise)
	if hi.x - lo.x < 2.0 * half:            # square: a pyramid
		r0 = (c0 + c2) / 2.0 + Vector3(0, rise, 0)
		r1 = r0
	var col: Color = HOUSE_ROOFS[hash(ring[0]) % HOUSE_ROOFS.size()]
	# the four slopes (two long ones, two hips), each facing outward and up; the far ones a touch darker
	for f in [[c0, c1, r1, r0], [c2, c3, r0, r1], [c1, c2, r1], [c3, c0, r0]]:
		var pts: Array = f
		var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
		if n.y < 0.0:
			n = -n
		st.set_normal(n)
		st.set_color(col.darkened(0.0 if n.z > 0.0 or n.x > 0.0 else 0.1))
		_face(st, pts[0], pts[1], pts[2], n)
		if pts.size() == 4:
			_face(st, pts[0], pts[2], pts[3], n)
	# the underside of the eaves, so it doesn't look hollow from below
	st.set_normal(Vector3.DOWN)
	st.set_color(Color("#e8e4da"))
	_face(st, c0, c1, c2, Vector3.DOWN)
	_face(st, c0, c2, c3, Vector3.DOWN)

## A canopy (the map's "roof": the Mall's shade structures, carports, a petrol station's): a thin roof up on posts
## at its corners, nothing to bump into but the posts... which aren't solid either (it's not worth the bother).
func _canopy(st: SurfaceTool, ring: PackedVector2Array, h: float) -> void:
	var top := maxf(h, 3.2)
	var col := Color("#d9dcd8")
	st.set_normal(Vector3.UP)
	var idx := Geometry2D.triangulate_polygon(ring)
	for k in range(0, idx.size(), 3):
		for y in [top, top - 0.25]:
			var a := Vector3(ring[idx[k]].x, y, ring[idx[k]].y)
			var b := Vector3(ring[idx[k + 1]].x, y, ring[idx[k + 1]].y)
			var c := Vector3(ring[idx[k + 2]].x, y, ring[idx[k + 2]].y)
			if y == top:
				_tri(st, a, b, c, col)
			else:
				st.set_normal(Vector3.DOWN)
				st.set_color(col.darkened(0.25))
				_face(st, a, b, c, Vector3.DOWN)
				st.set_normal(Vector3.UP)
	# posts at the corners (every other one on a curvy outline)
	var step := maxi(1, ring.size() / 8)
	for k in range(0, ring.size(), step):
		var p := ring[k]
		var c := Geometry2D.get_closest_point_to_segment(p, ring[(k + 1) % ring.size()], ring[(k + ring.size() - 1) % ring.size()])
		var inset := (c - p).normalized() * 0.3 if c.distance_to(p) > 0.01 else Vector2.ZERO
		var q := p + inset
		var s := 0.08
		var corners := [Vector3(q.x - s, 0, q.y - s), Vector3(q.x + s, 0, q.y - s), Vector3(q.x + s, 0, q.y + s), Vector3(q.x - s, 0, q.y + s)]
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			var n := (b - a).cross(Vector3.UP).normalized() * -1.0
			st.set_normal(n)
			st.set_color(Color("#5a5f66"))
			_face(st, a, b, b + Vector3(0, top, 0), n)
			_face(st, a, b + Vector3(0, top, 0), a + Vector3(0, top, 0), n)
