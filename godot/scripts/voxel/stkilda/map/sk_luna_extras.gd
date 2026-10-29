# (Copied from stkilda-godot scripts/town/luna_extras.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkLunaExtras
extends RefCounted
## Luna Park, stage 4: everything else inside the wall. The map's small buildings as what they are (Cafe Luna, the gift
## shop, the ticket booth, and the long one by the station: House of Carnivale, a GUESS), kept under the Scenic Railway
## where it passes over them; Moon Balloons (a kids' ride the map hasn't got), put in the open; and lamps, benches and
## bins about the place. What they look like and the guesses: reference/luna_park/NOTES.md. (The Happy Swing, Road
## Runner, the carnival game stalls and the food kiosk were taken out, 2026-10-27: the owner didn't want them.)
##
## The map doesn't say where Moon Balloons is, so it goes in the open space near where the aerial photo shows small
## rides (_Room finds the open space: clear of every ride's swing, the coaster's track, the buildings and the wall).

## The map's buildings left out (SkLunaRides.skip_ids): the ticket booth, built here in its own looks; and the food kiosk
## (taken out, with nothing in its place).
const REPLACES := ["w1409388256", "w1409388254"]
## The map's buildings, by id: what each is, what its sign says, its colours [walls, trim].
const SHOPS := {
	"w1000251780": ["Cafe Luna", "CAFE LUNA", Color("#2e3a5c"), Color("#f2c230")],
	"w1000251784": ["Gift Shop", "GIFTS", Color("#c8202a"), Color("#f2c230")],
	"w1409388256": ["Ticket booth", "TICKETS", Color("#2f6fd0"), Color("#f2c230")],
	"w60252365": ["House of Carnivale", "HOUSE OF CARNIVALE", Color("#7a2f6f"), Color("#f2c230")],
}
## How far each moving ride reaches round its middle as it goes (so nothing's put where it swings).
const REACH := {"PharaohsCurse": 11.0, "Supernova": 9.5, "Spider": 10.0, "PowerSurge": 9.0,
	"ArabianMerry": 7.0, "ConeyDrop": 4.5}

const WHITE := Color("#f4f1ea")
const RED := Color("#c8202a")
const YELLOW := Color("#f2c230")
const PINK := Color("#d8367f")

static func build(parent: Node3D, town: SkTownBuilder, face: Transform3D, els: Array) -> Dictionary:
	var spots := {}
	var into := -face.basis.z
	var track: PackedVector3Array = []
	var r := SkScenicRailway.route(town, face, els)
	if not r.is_empty():
		track = r[0]
	var wall := PackedVector2Array()
	for e in els:
		if e.type == "way" and int(e.id) == SkLunaPark.WALL_WAY:
			for g in e.geometry:
				wall.append(town.project(g.lat, g.lon))
	if wall.size() < 4:
		return spots
	# the shops on the map's outlines
	for b in town.data.buildings:
		if SHOPS.has(b.get("id", "")):
			var n := _shop(parent, SkTownBuilder._pts(b.p), SHOPS[b.id], track, wall)
			if n and b.id == "w1000251780":
				spots["Luna Park - Cafe Luna"] = SkLunaRides._spot_before(n.position, into, 10.0)
	# what's in the way: the rides (as they are now, and how far each swings), the shops, the coaster, the wall
	var room := _Room.new(wall, track)
	for c in parent.get_children():
		if not (c is Node3D) or c.name in ["Town", "SkLunaPark", "ParkWall", "ParkPaving", "SkScenicRailway"]:
			continue
		var n := c as Node3D
		var box := _ground_rect(n)
		if box.size == Vector2.ZERO or not Geometry2D.is_point_in_polygon(box.get_center(), wall):
			continue
		if REACH.has(String(n.name)):
			room.circle(Vector2(n.position.x, n.position.z), REACH[String(n.name)])
		else:
			room.rect(box.grow(1.0))
	var rail := parent.get_node_or_null("SkScenicRailway")
	if rail and rail.has_meta("board"):                # (the coaster's boarding spot and its sign)
		var b: Vector3 = rail.get_meta("board")
		room.circle(Vector2(b.x, b.z), 4.0)
	# the kids' rides, together near the Arabian Merry (where the aerial photo shows small round rides)
	var merry := parent.get_node_or_null("ArabianMerry")
	var kids_hint := Vector2(merry.position.x, merry.position.z) if merry else room.middle()
	var at := room.take(kids_hint, 5.0)
	if at != Vector2.INF:
		var n := _moon_balloons(parent, at)
		spots["Luna Park - Moon Balloons"] = SkLunaRides._spot_before(n.position, n.transform.basis.z, -9.0)
	# lamps (with a bench and now and then a bin beside them) dotted about the open ground
	var holder := Node3D.new()
	var body := StaticBody3D.new()
	body.collision_layer = SkData.LAYER_WORLD
	body.collision_mask = 0
	var k := 0
	for p in room.spread(13.0, 1.4):
		_lamp(holder, body, Vector3(p.x, 0, p.y), k)
		k += 1
	var mi := SkLunaRides._bake(parent, holder, "LunaParkLamps")
	mi.visibility_range_end = 260.0
	parent.add_child(body)
	return spots

## Where a node's meshes are on the ground (map x, z), as they are now.
static func _ground_rect(n: Node3D) -> Rect2:
	var out := Rect2()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var g: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		var r := Rect2(Vector2(g.position.x, g.position.z), Vector2(g.size.x, g.size.z))
		if first:
			out = r
			first = false
		else:
			out = out.merge(r)
	return out

# ================================================================ finding room

## The open ground inside the park, on a 1.5 m grid: how far each point is from the nearest thing in the way.
class _Room:
	const STEP := 1.5
	const TRACK_CLEAR := 3.4             # (the coaster's deck and its trestles' feet)
	const WALL_CLEAR := 1.5
	var pts := PackedVector2Array()
	var clear := PackedFloat32Array()    # metres to the nearest thing in the way

	func _init(wall: PackedVector2Array, track: PackedVector3Array) -> void:
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in wall:
			lo = lo.min(p)
			hi = hi.max(p)
		# the track, filed by 10 m squares
		var cells := {}
		for q in track:
			var key := Vector2i(floori(q.x / 10.0), floori(q.z / 10.0))
			if not cells.has(key):
				cells[key] = PackedVector2Array()
			cells[key].append(Vector2(q.x, q.z))
		var x := lo.x
		while x < hi.x:
			var z := lo.y
			while z < hi.y:
				var p := Vector2(x, z)
				if Geometry2D.is_point_in_polygon(p, wall):
					var d := INF
					for i in wall.size():
						d = minf(d, Geometry2D.get_closest_point_to_segment(p, wall[i], wall[(i + 1) % wall.size()]).distance_to(p) - WALL_CLEAR)
					var key := Vector2i(floori(x / 10.0), floori(z / 10.0))
					for dx in [-1, 0, 1]:
						for dz in [-1, 0, 1]:
							for q in cells.get(key + Vector2i(dx, dz), PackedVector2Array()):
								d = minf(d, q.distance_to(p) - TRACK_CLEAR)
					d = minf(d, 14.0)              # (no further than that matters)
					if d > 0.0:
						pts.append(p)
						clear.append(d)
				z += STEP
			x += STEP

	## Something round in the way.
	func circle(at: Vector2, r: float) -> void:
		for i in pts.size():
			clear[i] = minf(clear[i], pts[i].distance_to(at) - r)

	## Something square in the way.
	func rect(box: Rect2) -> void:
		for i in pts.size():
			var p := pts[i]
			var dx := maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0)
			var dz := maxf(maxf(box.position.y - p.y, p.y - box.end.y), 0.0)
			clear[i] = minf(clear[i], Vector2(dx, dz).length() if (dx > 0.0 or dz > 0.0) else -1.0)

	func middle() -> Vector2:
		var m := Vector2.ZERO
		for p in pts:
			m += p
		return m / maxf(1.0, pts.size())

	## The open spot nearest `hint` with room for something `r` round; it's then in the way of what comes after.
	## INF if there's nowhere.
	func take(hint: Vector2, r: float) -> Vector2:
		var best := -1
		for i in pts.size():
			if clear[i] >= r and (best < 0 or pts[i].distance_squared_to(hint) < pts[best].distance_squared_to(hint)):
				best = i
		if best < 0:
			return Vector2.INF
		var at := pts[best]
		circle(at, r + 0.5)
		return at

	## Spots about `every` m apart across the open ground, each with room for something `r` round.
	func spread(every: float, r: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		var used := {}
		for i in pts.size():
			var p := pts[i]
			var key := Vector2i(floori(p.x / every), floori(p.y / every))
			if used.has(key) or clear[i] < r:
				continue
			# (the spot nearest the middle of its square)
			var mid := (Vector2(key) + Vector2(0.5, 0.5)) * every
			if p.distance_to(mid) > every * 0.3:
				continue
			used[key] = true
			out.append(p)
			circle(p, r)
		return out

# ================================================================ the shops

## A shop on the map's outline: painted walls, a striped awning along the side facing the park's middle, its sign. Kept
## under the Scenic Railway where it passes over (lower there, or left out if there's no room under it).
static func _shop(parent: Node3D, ring: PackedVector2Array, look: Array, track: PackedVector3Array, wall: PackedVector2Array) -> Node3D:
	if ring.size() > 3 and ring[0].is_equal_approx(ring[-1]):
		ring.remove_at(ring.size() - 1)
	var r := SkLunaRides._rect(ring)
	if r.is_empty():
		return null
	var mid: Vector2 = r[0]
	var lo := 4.5
	var half: float = maxf(r[2], r[3])
	for q in track:
		if Vector2(q.x, q.z).distance_to(mid) < half + 2.6:
			# over the roof (or close by): keep under it
			var on := false
			for k in ring.size():
				if Geometry2D.get_closest_point_to_segment(Vector2(q.x, q.z), ring[k], ring[(k + 1) % ring.size()]).distance_to(Vector2(q.x, q.z)) < 2.6:
					on = true
			if on or Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), ring):
				lo = minf(lo, q.y - 1.0)
	if lo < 2.4:
		return null
	# its front faces the park's middle
	var centre := Vector2.ZERO
	for p in wall:
		centre += p
	centre /= wall.size()
	var f := SkLunaRides._facing(parent, String(look[0]).replace(" ", ""), r, centre)
	var n: Node3D = f[0]
	var hw: float = f[1]
	var hd: float = f[2]
	var walls: Color = look[2]
	var trim: Color = look[3]
	var holder := Node3D.new()
	SkModels.box(holder, Vector3(hw * 2.0, lo, hd * 2.0), Vector3(0, lo / 2.0, 0), walls)
	SkModels.box(holder, Vector3(hw * 2.0 + 0.3, 0.3, hd * 2.0 + 0.3), Vector3(0, lo, 0), trim)
	# its front: a counter and doorway, the awning (red and white stripes)
	SkModels.box(holder, Vector3(hw * 1.6, 1.0, 0.3), Vector3(0, 0.5, hd + 0.1), trim.darkened(0.15))
	SkModels.box(holder, Vector3(hw * 1.6, lo * 0.45, 0.1), Vector3(0, 1.0 + lo * 0.225, hd + 0.02), Color("#1f2a33"))
	var stripes := maxi(4, int(hw * 2.0 / 0.9))
	for k in stripes:
		var x := -hw + (k + 0.5) * hw * 2.0 / stripes
		var s := SkModels.box(holder, Vector3(hw * 2.0 / stripes, 0.1, 1.6), Vector3(x, lo - 0.5, hd + 0.7), RED if k % 2 == 0 else WHITE)
		s.rotation.x = 0.35
	SkLunaRides._bake(n, holder, "Shop")
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Black", "Impact", "sans-serif"])
	var l := Label3D.new()
	l.name = "Sign"
	l.text = look[1]
	l.font = font
	l.font_size = 72
	l.pixel_size = minf(0.8, hw * 1.7 / maxf(4.0, String(look[1]).length() * 0.75)) / 72.0
	l.modulate = trim
	l.outline_modulate = Color("#1a1c2c")
	l.outline_size = 10
	l.position = Vector3(0, lo - 0.05, hd + 1.55)
	n.add_child(l)
	SkLunaRides._solid(n, Vector3(hw * 2.0, lo, hd * 2.0), Vector3(0, lo / 2.0, 0))
	return n

# ================================================================ the kids' rides

## Moon Balloons: "this small version of the classic Ferris wheel": a pink frame, balloon-shaped cages in pink,
## yellow, blue and green. (Its size: a GUESS, 7 m across.)
static func _moon_balloons(parent: Node3D, at: Vector2) -> Node3D:
	var n := SkLunaRides._placed(parent, "MoonBalloons", at, Vector2(1, 0))
	var holder := Node3D.new()
	const HUB := 6.0                     # (high enough that the balloon at the bottom clears the platform)
	for z in [-1.0, 1.0]:
		for x in [-2.6, 2.6]:
			SkLunaRides._strut(holder, Vector3(x, 0, z * 1.4), Vector3(0, HUB, z * 0.9), 0.3, PINK)
	SkModels.cyl(holder, 3.4, 0.4, Vector3(0, 0.2, 0), Color("#3d7fd0"), true, 16)
	SkLunaRides._bake(n, holder, "Frame")
	var wheel := SkLunaRides.SkyWheel.new()
	wheel.name = "Wheel"
	wheel.position.y = HUB
	n.add_child(wheel)
	var w := Node3D.new()
	for i in 6:
		var a := TAU * i / 6.0
		SkLunaRides._strut(w, Vector3.ZERO, Vector3(cos(a), sin(a), 0) * 3.3, 0.22, PINK)
		SkLunaRides._strut(w, Vector3(cos(a), sin(a), 0) * 3.3, Vector3(cos(a + TAU / 6.0), sin(a + TAU / 6.0), 0) * 3.3, 0.16, Color("#9a3fb8"))
	SkLunaRides._disc(w, 0.5, 1.8, Vector3.ZERO, YELLOW)
	SkLunaRides._bake(wheel, w, "Spokes")
	var colours := [PINK, YELLOW, Color("#3d7fd0"), Color("#4fbf3a"), Color("#ef7d22"), Color("#e2507a")]
	for i in 6:
		var a := TAU * i / 6.0
		var g := Node3D.new()
		# the balloon: round on top, narrowing down to its ropes (a cone wide at the top read as a roof upside down)
		SkModels.ball(g, 0.85, Vector3(0, -0.6, 0), colours[i])
		SkLunaRides._cone(g, 0.28, 0.62, 0.55, Vector3(0, -1.325, 0), colours[i], 10)
		for k in 6:
			var b := TAU * k / 6.0
			SkLunaRides._strut(g, Vector3(cos(b) * 0.3, -1.6, sin(b) * 0.3), Vector3(cos(b) * 0.7, -2.3, sin(b) * 0.7), 0.06, Color("#d7dade"))
		SkLunaRides._cone(g, 0.75, 0.6, 0.4, Vector3(0, -2.45, 0), colours[i], 10)       # its basket
		var gm := SkModels.bake(g)
		g.free()
		var mi := MeshInstance3D.new()
		mi.mesh = gm
		mi.material_override = SkModels.baked_material()
		mi.position = Vector3(cos(a), sin(a), 0) * 3.3 + Vector3(0, 0.6, 0)
		wheel.add_child(mi)
		wheel.gondolas.append(mi)
	SkLunaRides._solid(n, Vector3(6.0, 0.4, 3.0), Vector3(0, 0.2, 0))
	return n

# ================================================================ lamps, benches, bins

## An old-style lamp post (dark green, two white globes), a green bench beside it, and every third one a yellow bin.
static func _lamp(holder: Node3D, body: StaticBody3D, at: Vector3, k: int) -> void:
	var green := Color("#2f5a3a")
	SkModels.box(holder, Vector3(0.3, 0.5, 0.3), at + Vector3(0, 0.25, 0), green)
	SkModels.cyl(holder, 0.08, 3.6, at + Vector3(0, 2.0, 0), green, true, 6)
	SkModels.box(holder, Vector3(1.0, 0.08, 0.08), at + Vector3(0, 3.6, 0), green)
	for x in [-0.5, 0.5]:
		SkModels.ball(holder, 0.22, at + Vector3(x, 3.85, 0), Color("#fbf6e6"))
	var bench := at + Vector3(0.9, 0, 0)
	SkContactShade.blob(Vector2(at.x, at.z), 0.55, 0.4)
	for x in [-0.5, 0.5]:
		SkDayNight.lamps.append(at + Vector3(x, 3.85, 0))          # (lit at night)
	SkContactShade.blob(Vector2(bench.x, bench.z), 0.95, 0.38)
	SkModels.box(holder, Vector3(0.45, 0.08, 1.5), bench + Vector3(0, 0.45, 0), Color("#3f8a4a"))
	SkModels.box(holder, Vector3(0.08, 0.45, 1.5), bench + Vector3(0.22, 0.7, 0), Color("#3f8a4a"))
	for z in [-0.6, 0.6]:
		SkModels.box(holder, Vector3(0.4, 0.45, 0.06), bench + Vector3(0, 0.22, z), Color("#2a2c30"))
	if k % 3 == 0:
		SkModels.cyl(holder, 0.28, 0.9, at + Vector3(-0.7, 0.45, 0.3), YELLOW, true, 10)
		SkContactShade.blob(Vector2(at.x - 0.7, at.z + 0.3), 0.45, 0.4)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.3, 3.0, 0.3)
	cs.shape = bs
	cs.position = at + Vector3(0, 1.5, 0)
	body.add_child(cs)
