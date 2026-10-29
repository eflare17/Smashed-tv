# (Copied from stkilda-godot scripts/town/luna_park.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkLunaPark
extends RefCounted
## Luna Park, St Kilda. So far its face entrance (Mr Moon) on the Esplanade: the two towers with their domes, the
## face with its open mouth (the way in: you can walk or drive through), the sunburst behind the head, the "Luna Park"
## sign, the park's front wall either side and the forecourt's black rays. What it looks like, and which sizes are
## guesses: reference/luna_park/NOTES.md.
##
## In its own space the face's front looks along +z and its middle is at x = 0; the ground is y = 0.

## Where the face stands, and which way it looks (to the Esplanade, across its forecourt): at the front of the
## curve the park's wall and the Scenic Railway's track make round the entrance (OpenStreetMap).
const FACE_LATLON := Vector2(-37.86724, 144.97683)
const FACE_DIR := Vector2(0.06, -1.0)             # (map x, z: north)
## The patch of the map (its own space) where the map's own buildings are left out: the face's footprint, and the
## forecourt's open (the map has a block there).
const CLEAR := Rect2(-15.0, -6.0, 30.0, 21.0)

const RED := Color("#c8202a")
const RED_DARK := Color("#7a1418")
const BLUE := Color("#2e5fae")
const YELLOW := Color("#f2c230")
const CREAM := Color("#f3ead2")
const WHITE := Color("#f7f4ec")
const NAVY := Color("#1d2340")
const SILVER := Color("#9ea6ad")
const FACE := Color("#e9e4d6")
const CREASE := Color("#66625c")

## The towers: how far out their middles are, how wide and deep, the red base's height, the cornice's.
const TOWER_X := 5.4
const TOWER_W := 3.6
const TOWER_D := 4.0
const BASE_H := 4.4
const CORNICE_Y := 10.4
## The head: its middle, half its width, half its height above and below the middle, how far its front bulges out.
const HEAD_Y := 3.9
const HEAD_A := 3.4
const HEAD_UP := 4.1
const HEAD_DOWN := 4.2
const HEAD_Z := -0.5
const HEAD_BULGE := 1.5
## The mouth: half its width, and where its arch starts (its top is MOUTH_SPRING + MOUTH_HALF).
const MOUTH_HALF := 2.0
const MOUTH_SPRING := 1.3
## The sunburst behind the head.
const SUN_Y := 5.4
const SUN_R := 4.4

static func xf(town: SkTownBuilder) -> Transform3D:
	if town.data.is_empty():           # (before the town's built: its map, for where things are)
		town.data = JSON.parse_string(FileAccess.get_file_as_string("res://data/stkilda/town.json"))
	var at := town.project(FACE_LATLON.x, FACE_LATLON.y)
	var d := FACE_DIR.normalized()
	return Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(at.x, 0.0, at.y))

static func build(parent: Node3D, town: SkTownBuilder) -> Node3D:
	var n := Node3D.new()
	n.name = "SkLunaPark"
	n.transform = xf(town)
	parent.add_child(n)
	var holder := Node3D.new()
	_towers(holder)
	_middle(holder)
	_features(holder)
	var mi := MeshInstance3D.new()
	mi.name = "Face entrance"
	mi.mesh = SkModels.bake(holder)
	mi.material_override = SkWornLook.material()          # (its age: SkWornLook)
	holder.free()
	n.add_child(mi)
	n.add_child(_head())
	n.add_child(_forecourt())
	_sign(n)
	_solid(n)
	var park = JSON.parse_string(FileAccess.get_file_as_string("res://data/stkilda/luna.json"))
	if park != null:
		_grounds(parent, town, n.transform, park.elements)
		SkScenicRailway.build(parent, town, n.transform, park.elements)
		var spots := SkLunaRides.build(parent, town, n.transform, park.elements)          # (the rides inside: where to stand by each)
		spots.merge(SkLunaExtras.build(parent, town, n.transform, park.elements))         # (and the rest: shops, kids' rides, stalls)
		parent.set_meta("luna_spots", spots)
		for c in parent.get_children():                                                  # (and no shadows from their small moving bits)
			if not (c.name in ["Town", "SkLunaPark"]):
				SkLunaRides.no_small_shadows(c)
	return n

# ================================================================ the park: its wall all the way round, its paving

## The park's wall (OpenStreetMap's outline of it), cream with a red cap like either side of the face, left open
## where the face stands; and pale paving inside it. As tall as the photo shows beside the face for WALL_NEAR m
## either side of it, lower the rest of the way round (GUESS: only the bit by the face was seen), under the coaster.
const WALL_H := 4.6
const WALL_LOW := 2.4
const WALL_NEAR := 22.0
const WALL_WAY := 15477129

static func _grounds(parent: Node3D, town: SkTownBuilder, face: Transform3D, els: Array) -> void:
	var ring := PackedVector2Array()
	for e in els:
		if e.type == "way" and int(e.id) == WALL_WAY:
			for g in e.geometry:
				ring.append(town.project(g.lat, g.lon))
	if ring.size() < 4:
		return
	if ring[0].is_equal_approx(ring[-1]):
		ring.remove_at(ring.size() - 1)
	var holder := Node3D.new()
	var body := StaticBody3D.new()
	body.name = "ParkWall"
	body.collision_layer = SkData.LAYER_WORLD
	body.collision_mask = 0
	var inv := face.affine_inverse()
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var mid := (a + b) / 2.0
		var local := inv * Vector3(mid.x, 0, mid.y)
		if absf(local.x) < TOWER_X + TOWER_W / 2.0 and local.z > -TOWER_D - 2.0:
			continue                     # (the face's there)
		var len := a.distance_to(b)
		if len < 0.05:
			continue
		var yaw := -atan2(b.y - a.y, b.x - a.x)
		var wh := WALL_H if local.length() < WALL_NEAR else WALL_LOW
		var w := SkModels.box(holder, Vector3(len + 0.4, wh, 0.5), Vector3(mid.x, wh / 2.0, mid.y), CREAM)
		w.rotation.y = yaw
		var cap := SkModels.box(holder, Vector3(len + 0.5, 0.25, 0.6), Vector3(mid.x, wh + 0.1, mid.y), RED)
		cap.rotation.y = yaw
		SkTownBuilder._wall(body, a, b, wh)
		SkContactShade.line(a, b, 1.3, 0.3)
	var mi := MeshInstance3D.new()
	mi.name = "ParkWall"
	mi.mesh = SkModels.bake(holder)
	mi.material_override = SkModels.baked_material()
	holder.free()
	parent.add_child(mi)
	parent.add_child(body)
	# the paving inside
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var idx := Geometry2D.triangulate_polygon(ring)
	for k in range(0, idx.size(), 3):
		_up(st, Vector3(ring[idx[k]].x, 0.15, ring[idx[k]].y), Vector3(ring[idx[k + 1]].x, 0.15, ring[idx[k + 1]].y),
			Vector3(ring[idx[k + 2]].x, 0.15, ring[idx[k + 2]].y), Color("#5f6266"))           # (dark grey asphalt, as in the photos)
	var pave := MeshInstance3D.new()
	pave.name = "ParkPaving"
	pave.mesh = st.commit()
	pave.material_override = _asphalt()
	pave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(pave)

# ================================================================ the towers

static func _towers(h: Node3D) -> void:
	for s in [-1.0, 1.0]:
		var x: float = s * TOWER_X
		# the red base: blue upright stripes near the ground, a framed poster on the front
		SkModels.box(h, Vector3(TOWER_W, BASE_H, TOWER_D), Vector3(x, BASE_H / 2.0, -TOWER_D / 2.0), RED)
		for k in 6:
			SkModels.box(h, Vector3(0.07, 0.9, 0.04), Vector3(x - 1.25 + k * 0.5, 0.55, 0.01), BLUE)
		SkModels.box(h, Vector3(1.6, 2.0, 0.08), Vector3(x, 2.6, 0.04), YELLOW)
		SkModels.box(h, Vector3(1.3, 1.7, 0.1), Vector3(x, 2.6, 0.05), Color("#2a6f8a"))
		# the yellow band with its row of cream panels
		SkModels.box(h, Vector3(TOWER_W + 0.3, 0.8, TOWER_D + 0.3), Vector3(x, BASE_H + 0.4, -TOWER_D / 2.0), YELLOW)
		for k in 6:
			SkModels.box(h, Vector3(0.36, 0.42, 0.05), Vector3(x - 1.5 + k * 0.6, BASE_H + 0.4, 0.17), Color("#f6eedc"))
		# the tall blue panel with its white diamond lattice, between yellow pilasters
		var top := CORNICE_Y
		var y0 := BASE_H + 0.8
		SkModels.box(h, Vector3(TOWER_W - 0.2, top - y0, TOWER_D - 0.2), Vector3(x, (top + y0) / 2.0, -TOWER_D / 2.0), BLUE)
		for side in [-1.0, 1.0]:
			SkModels.box(h, Vector3(0.32, top - y0, TOWER_D), Vector3(x + side * (TOWER_W / 2.0 - 0.16), (top + y0) / 2.0, -TOWER_D / 2.0), YELLOW)
			SkModels.box(h, Vector3(0.08, top - y0, 0.06), Vector3(x + side * (TOWER_W / 2.0 - 0.4), (top + y0) / 2.0, -0.08), RED)
		var row := 0
		var yy := y0 + 0.35
		while yy < top - 0.3:
			var shift := 0.2 if row % 2 == 1 else 0.0
			var xx := x - 1.05 + shift
			while xx < x + 1.1:
				var d := SkModels.box(h, Vector3(0.17, 0.17, 0.04), Vector3(xx, yy, -0.08), WHITE)
				d.rotation.z = PI / 4.0
				xx += 0.4
			yy += 0.4
			row += 1
		# the cornice, cream with a red edge
		SkModels.box(h, Vector3(TOWER_W + 0.8, 0.6, TOWER_D + 0.8), Vector3(x, top + 0.3, -TOWER_D / 2.0), CREAM)
		SkModels.box(h, Vector3(TOWER_W + 0.9, 0.16, TOWER_D + 0.9), Vector3(x, top + 0.05, -TOWER_D / 2.0), RED)
		# the lookout: white corner posts, a little white railing, a yellow arched panel with a red opening
		var lo := top + 0.6
		for cx in [-1.3, 1.3]:
			for cz in [-1.3, 1.3]:
				SkModels.box(h, Vector3(0.28, 2.4, 0.28), Vector3(x + cx, lo + 1.2, -TOWER_D / 2.0 + cz), WHITE)
		SkModels.box(h, Vector3(2.4, 2.4, 2.4), Vector3(x, lo + 1.2, -TOWER_D / 2.0), BLUE.darkened(0.2))
		SkModels.box(h, Vector3(2.0, 1.9, 0.12), Vector3(x, lo + 1.35, -TOWER_D / 2.0 + 1.25), YELLOW)
		SkModels.box(h, Vector3(1.0, 1.3, 0.14), Vector3(x, lo + 1.15, -TOWER_D / 2.0 + 1.27), RED)
		_disc(h, 0.5, 0.14, Vector3(x, lo + 1.8, -TOWER_D / 2.0 + 1.27), RED)
		SkModels.box(h, Vector3(2.9, 0.5, 0.1), Vector3(x, lo + 0.25, -TOWER_D / 2.0 + 1.45), WHITE)
		# its roof, then the grey-silver bell of a dome and its spike
		SkModels.box(h, Vector3(3.5, 0.3, 3.5), Vector3(x, lo + 2.55, -TOWER_D / 2.0), CREAM)
		SkModels.box(h, Vector3(3.6, 0.1, 3.6), Vector3(x, lo + 2.4, -TOWER_D / 2.0), RED)
		var bell := [1.5, 1.6, 1.55, 1.35, 1.05, 0.7, 0.35, 0.12]
		var by := lo + 2.7
		for i in bell.size() - 1:
			_cone(h, bell[i], bell[i + 1], 0.32, Vector3(x, by + 0.16, -TOWER_D / 2.0), SILVER.darkened(0.08 * float(i % 2)))
			by += 0.32
		SkModels.cyl(h, 0.05, 2.4, Vector3(x, by + 1.2, -TOWER_D / 2.0), Color("#cfd3d6"), true, 6)
		SkModels.ball(h, 0.14, Vector3(x, by + 0.1, -TOWER_D / 2.0), Color("#cfd3d6"))

## A slice of a cone, standing (for the domes).
static func _cone(parent: Node3D, r0: float, r1: float, tall: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = tall
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.material_override = SkModels.mat(c)
	parent.add_child(mi)
	return mi

## A flat disc facing the front (+z): an eye's iris, a round window.
static func _disc(parent: Node3D, r: float, thick: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := _cone(parent, r, r, thick, pos, c)
	mi.rotation.x = PI / 2.0
	return mi

# ================================================================ between the towers: the wall, the sunburst

static func _middle(h: Node3D) -> void:
	var w := TOWER_X * 2.0 - TOWER_W            # between the towers
	var top := CORNICE_Y + 0.4
	var mouth_top := MOUTH_SPRING + MOUTH_HALF
	# the wall the head stands against, left open for the way in (the mouth's tunnel goes through it)
	var side := (w / 2.0 - MOUTH_HALF)
	for s in [-1.0, 1.0]:
		SkModels.box(h, Vector3(side, top, TOWER_D - 0.6), Vector3(s * (MOUTH_HALF + side / 2.0), top / 2.0, -0.6 - (TOWER_D - 0.6) / 2.0), RED)
	SkModels.box(h, Vector3(MOUTH_HALF * 2.0, top - mouth_top, TOWER_D - 0.6), Vector3(0, (top + mouth_top) / 2.0, -0.6 - (TOWER_D - 0.6) / 2.0), RED)
	# the band across the top, yellow-trimmed
	SkModels.box(h, Vector3(w + 0.2, 0.7, 0.5), Vector3(0, top - 0.35, -0.5), RED)
	SkModels.box(h, Vector3(w + 0.2, 0.14, 0.55), Vector3(0, top - 0.75, -0.5), YELLOW)
	# blue lattice in the corners above the arch (the spandrels)
	for s in [-1.0, 1.0]:
		SkModels.box(h, Vector3(1.6, 2.6, 0.06), Vector3(s * (w / 2.0 - 0.8), top - 2.2, -0.57), BLUE)
	# the sunburst: a navy disc, orange and yellow rays, inside a white band and a red outline (the upper part;
	# the head covers the rest)
	var c := Vector3(0, SUN_Y, -0.56)
	var navy := PackedVector3Array()
	var white := PackedVector3Array()
	var red := PackedVector3Array()
	var orange := PackedVector3Array()
	var gold := PackedVector3Array()
	var steps := 40
	for i in steps:
		var a0 := deg_to_rad(-20.0 + 220.0 * i / steps)
		var a1 := deg_to_rad(-20.0 + 220.0 * (i + 1) / steps)
		_ring_bit(navy, c, 0.0, SUN_R, a0, a1, 0.0)
		_ring_bit(white, c, SUN_R, SUN_R + 0.4, a0, a1, 0.02)
		_ring_bit(red, c, SUN_R + 0.4, SUN_R + 0.6, a0, a1, 0.02)
	var rays := 22
	for i in rays:
		var a := deg_to_rad(-12.0 + 204.0 * (i + 0.5) / rays)
		var half := deg_to_rad(204.0 / rays * 0.36)
		var tip := c + Vector3(cos(a), sin(a), 0) * (SUN_R - 0.05) + Vector3(0, 0, 0.03)
		var l := c + Vector3(cos(a - half), sin(a - half), 0) * 2.4 + Vector3(0, 0, 0.03)
		var r := c + Vector3(cos(a + half), sin(a + half), 0) * 2.4 + Vector3(0, 0, 0.03)
		(orange if i % 2 == 0 else gold).append_array(PackedVector3Array([l, tip, r]))
	_tris(h, navy, Vector3.BACK, NAVY)
	_tris(h, white, Vector3.BACK, WHITE)
	_tris(h, red, Vector3.BACK, RED)
	_tris(h, orange, Vector3.BACK, Color("#ef8a1c"))
	_tris(h, gold, Vector3.BACK, Color("#f7cf3a"))
	# inside the mouth: the tunnel's dark red walls and arched roof, back to the park
	var deep := TOWER_D + 0.8
	for s in [-1.0, 1.0]:
		SkModels.box(h, Vector3(0.2, MOUTH_SPRING, deep), Vector3(s * (MOUTH_HALF + 0.1), MOUTH_SPRING / 2.0, -deep / 2.0 + 0.6), RED_DARK)
	for k in 10:
		var a := PI * (k + 0.5) / 10.0
		var p := Vector3(cos(a) * (MOUTH_HALF + 0.1), MOUTH_SPRING + sin(a) * (MOUTH_HALF + 0.1), -deep / 2.0 + 0.6)
		var piece := SkModels.box(h, Vector3(0.2, MOUTH_HALF * PI / 10.0 + 0.08, deep), p, RED_DARK)
		piece.rotation.z = a
	SkModels.box(h, Vector3(MOUTH_HALF * 2.0, 0.04, deep), Vector3(0, 0.18, -deep / 2.0 + 0.6), Color("#8f8a80"))

## Triangles from a list (three points each), all facing n, in one colour.
static func _tris(parent: Node3D, pts: PackedVector3Array, n: Vector3, c: Color) -> void:
	if pts.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(n)
	for i in range(0, pts.size(), 3):
		var a := pts[i]
		var b := pts[i + 1]
		var d := pts[i + 2]
		st.add_vertex(a)
		if (b - a).cross(d - a).dot(n) > 0.0:
			st.add_vertex(d)
			st.add_vertex(b)
		else:
			st.add_vertex(b)
			st.add_vertex(d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = SkModels.mat(c)
	parent.add_child(mi)

## A bit of a ring (from angle a0 to a1, radius r0 to r1) round c, in the x-y plane, z further out.
static func _ring_bit(out: PackedVector3Array, c: Vector3, r0: float, r1: float, a0: float, a1: float, z: float) -> void:
	var p0 := c + Vector3(cos(a0) * r0, sin(a0) * r0, z)
	var p1 := c + Vector3(cos(a1) * r0, sin(a1) * r0, z)
	var q0 := c + Vector3(cos(a0) * r1, sin(a0) * r1, z)
	var q1 := c + Vector3(cos(a1) * r1, sin(a1) * r1, z)
	out.append_array(PackedVector3Array([p0, q0, q1, p0, q1, p1]))

# ================================================================ the face

## How far the head's front stands out at (x, y) (its own space), or NAN off the head. Its outline is rounder above
## the middle and squarer below (the jowls come down to the ground either side of the mouth).
static func head_z(x: float, y: float) -> float:
	var u := absf(x) / HEAD_A
	var v := (y - HEAD_Y) / (HEAD_UP if y > HEAD_Y else HEAD_DOWN)
	var r := pow(u, 2.2) + pow(absf(v), 2.2 if y > HEAD_Y else 5.0)
	if r > 1.0:
		return NAN
	return HEAD_Z + HEAD_BULGE * pow(1.0 - r, 0.45)

static func in_mouth(x: float, y: float) -> bool:
	return absf(x) < MOUTH_HALF and (y < MOUTH_SPRING or Vector2(x, y - MOUTH_SPRING).length() < MOUTH_HALF)

## The head: its front as one curved surface (left open at the mouth), coloured as it goes: cream, red lips round the
## mouth, grey smile lines from the nose down to the chin.
static func _head() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 0.12
	var x0 := -HEAD_A
	var y0 := 0.0
	var nx := int(ceil(HEAD_A * 2.0 / step))
	var ny := int(ceil((HEAD_Y + HEAD_UP) / step))
	for i in nx:
		for j in ny:
			var xa := x0 + i * step
			var ya := y0 + j * step
			var mid := Vector2(xa + step / 2.0, ya + step / 2.0)
			if in_mouth(mid.x, mid.y):
				continue
			var corners := [Vector2(xa, ya), Vector2(xa + step, ya), Vector2(xa + step, ya + step), Vector2(xa, ya + step)]
			var ps := []
			var ok := true
			for c in corners:
				var z := head_z(c.x, c.y)
				if is_nan(z):
					# (at the edge: pull the corner in to where the head's front meets the wall)
					z = HEAD_Z
					if is_nan(head_z(mid.x, mid.y)):
						ok = false
				ps.append(Vector3(c.x, c.y, z))
			if not ok:
				continue
			var col := _head_colour(mid.x, mid.y)
			var n: Vector3 = (ps[1] - ps[0]).cross(ps[3] - ps[0]).normalized()
			if n.z < 0.0:
				n = -n
			st.set_normal(n)
			st.set_color(col)
			for t in [[0, 1, 2], [0, 2, 3]]:
				# (Godot draws the side where the corners go clockwise: wind each one to face out)
				var a: Vector3 = ps[t[0]]
				var b: Vector3 = ps[t[1]]
				var e: Vector3 = ps[t[2]]
				st.add_vertex(a)
				if (b - a).cross(e - a).dot(n) > 0.0:
					st.add_vertex(e)
					st.add_vertex(b)
				else:
					st.add_vertex(b)
					st.add_vertex(e)
	st.index()
	var mi := MeshInstance3D.new()
	mi.name = "Head"
	mi.mesh = st.commit()
	mi.material_override = SkModels.baked_material()
	return mi

static func _head_colour(x: float, y: float) -> Color:
	# the lips: a red band round the mouth
	var d := 99.0
	if y < MOUTH_SPRING:
		d = absf(x) - MOUTH_HALF if absf(x) >= MOUTH_HALF else 99.0
	else:
		d = Vector2(x, y - MOUTH_SPRING).length() - MOUTH_HALF
	if d >= 0.0 and d < 0.32:
		return RED
	# the smile lines: from beside the nose, out and down round the mouth to the chin
	if y > 0.4 and y < 4.1:
		var line := 0.95 + (4.1 - y) * 0.5 - pow(maxf(0.0, 1.6 - y), 2.0) * 0.25
		if absf(absf(x) - line) < 0.12:
			return CREASE
	# a crease under each eye and down each cheek's edge
	if absf(Vector2(absf(x) - 1.3, (y - 4.75) * 1.6).length() - 0.75) < 0.05 and y < 4.75:
		return CREASE.lightened(0.25)
	if absf(absf(x) - 2.85) < 0.06 and y > 1.0 and y < 4.6:
		return CREASE.lightened(0.2)
	return FACE.darkened(0.04 * clampf((absf(x) - 2.4), 0.0, 1.0))

## The eyes, brows, nose and teeth, stuck on the head's front.
static func _features(h: Node3D) -> void:
	for s in [-1.0, 1.0]:
		var ex: float = s * 1.3
		var ey := 5.05
		var ez := head_z(ex, ey)
		var white := SkModels.ball(h, 0.5, Vector3(ex, ey, ez - 0.02), WHITE)
		white.scale = Vector3(1.7, 0.62, 0.35)
		_disc(h, 0.27, 0.06, Vector3(ex, ey, ez + 0.16), Color("#5b8fd6"))
		_disc(h, 0.11, 0.06, Vector3(ex, ey, ez + 0.19), Color("#1a1c2c"))
		# the heavy lid and arched brow, in grey
		var lid := SkModels.box(h, Vector3(1.75, 0.1, 0.22), Vector3(ex, ey + 0.33, ez + 0.06), CREASE)
		lid.rotation.z = -s * 0.08
		for k in 2:
			var bx: float = ex + s * (-0.45 + k * 0.85)
			var by := 5.95 + (0.18 if k == 0 else 0.0)
			var brow := SkModels.box(h, Vector3(0.95, 0.24, 0.35), Vector3(bx, by, head_z(bx, by) + 0.08), CREASE.lightened(0.15))
			brow.rotation.z = s * (0.32 if k == 0 else -0.3)
	# the nose: a big bulb and its wings
	var nz := head_z(0.0, 4.2)
	var nose := SkModels.ball(h, 0.55, Vector3(0, 4.15, nz + 0.25), FACE)
	nose.scale = Vector3(1.05, 1.55, 1.2)
	for s in [-1.0, 1.0]:
		SkModels.ball(h, 0.36, Vector3(s * 0.5, 3.75, head_z(s * 0.5, 3.75) + 0.12), FACE.darkened(0.03))
	# the upper teeth, hanging along the top of the mouth
	for k in 9:
		var a := PI * (0.2 + 0.6 * k / 8.0)
		var tx := cos(a) * (MOUTH_HALF - 0.28)
		var ty := MOUTH_SPRING + sin(a) * (MOUTH_HALF - 0.28)
		var tz := head_z(cos(a) * (MOUTH_HALF + 0.4), MOUTH_SPRING + sin(a) * (MOUTH_HALF + 0.4))
		if is_nan(tz):
			tz = HEAD_Z + 0.5
		var tooth := SkModels.box(h, Vector3(0.36, 0.5, 0.25), Vector3(tx, ty, tz - 0.2), WHITE)
		tooth.rotation.z = a - PI / 2.0

# ================================================================ the forecourt, the sign

## The forecourt: a half circle of pale paving with long thin black rays spreading out from the mouth.
static func _forecourt() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var r := 14.0
	var c := Vector3(0, 0.17, 0.6)
	for i in 32:
		var a0 := PI * i / 32.0
		var a1 := PI * (i + 1) / 32.0
		_up(st, c, c + Vector3(cos(a0) * r, 0, sin(a0) * r), c + Vector3(cos(a1) * r, 0, sin(a1) * r), Color("#d9d4c8"))
	var rays := 15
	for i in rays:
		var a := PI * (i + 0.5) / rays
		var side := Vector3(-sin(a), 0, cos(a)) * 0.5
		var out := Vector3(cos(a), 0, sin(a))
		var base := c + out * 1.4 + Vector3(0, 0.005, 0)
		_up(st, base - side, base + side, base + out * (r - 1.5), Color("#1f1f22"))
	var mi := MeshInstance3D.new()
	mi.name = "Forecourt"
	mi.mesh = st.commit()
	mi.material_override = SkModels.baked_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	if (b - a).cross(c - a).y > 0.0:
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(b)
		st.add_vertex(c)

## The cream oval "Luna Park" sign at the top, red-rimmed, its name in red script.
static func _sign(n: Node3D) -> void:
	var h := Node3D.new()
	var y := CORNICE_Y + 0.55
	var rim := SkModels.cyl(h, 1.0, 0.25, Vector3(0, y, -0.25), RED, false, 24)
	rim.rotation = Vector3(PI / 2.0, 0, 0)
	rim.scale = Vector3(2.5, 1.0, 0.85)
	var plate := SkModels.cyl(h, 0.88, 0.3, Vector3(0, y, -0.22), Color("#f3e3c0"), false, 24)
	plate.rotation = Vector3(PI / 2.0, 0, 0)
	plate.scale = Vector3(2.5, 1.0, 0.85)
	var mi := MeshInstance3D.new()
	mi.mesh = SkModels.bake(h)
	mi.material_override = SkModels.baked_material()
	h.free()
	n.add_child(mi)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Brush Script MT", "Segoe Script", "cursive"])
	font.font_weight = 700
	var l := Label3D.new()
	l.name = "Sign"
	l.text = "Luna Park"
	l.font = font
	l.font_size = 128
	l.pixel_size = 0.72 / 128.0
	l.modulate = Color("#c0262c")
	l.outline_size = 0
	l.position = Vector3(0, y - 0.02, -0.06)
	l.double_sided = false
	n.add_child(l)

## What you bump into: the towers, the walls either side, and the head and its wall round the mouth (the mouth
## itself is open: the way in).
static func _solid(n: Node3D) -> void:
	var b := StaticBody3D.new()
	b.name = "Solid"
	b.collision_layer = SkData.LAYER_WORLD
	b.collision_mask = 0
	n.add_child(b)
	var top := CORNICE_Y + 0.4
	var mouth_top := MOUTH_SPRING + MOUTH_HALF
	var front := HEAD_Z + HEAD_BULGE * 0.6
	var boxes := [
		[Vector3(TOWER_W, top, TOWER_D), Vector3(-TOWER_X, top / 2.0, -TOWER_D / 2.0)],
		[Vector3(TOWER_W, top, TOWER_D), Vector3(TOWER_X, top / 2.0, -TOWER_D / 2.0)],
	]
	var side := TOWER_X - TOWER_W / 2.0 - MOUTH_HALF
	for s in [-1.0, 1.0]:
		boxes.append([Vector3(side, top, TOWER_D + front), Vector3(s * (MOUTH_HALF + side / 2.0), top / 2.0, (front - TOWER_D) / 2.0)])
	boxes.append([Vector3(MOUTH_HALF * 2.0, top - mouth_top, TOWER_D + front), Vector3(0, (top + mouth_top) / 2.0, (front - TOWER_D) / 2.0)])
	for bx in boxes:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = bx[0]
		cs.shape = shape
		cs.position = bx[1]
		b.add_child(cs)

## The park's asphalt: dark grey, with a fine grain and big soft patches of wear (lighter where it's walked on most,
## darker where it's been patched), laid over the ground in world space so it never stretches.
static func _asphalt() -> StandardMaterial3D:
	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_VALUE
	grain.frequency = 0.5
	grain.seed = 3
	var wear := FastNoiseLite.new()
	wear.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wear.frequency = 0.012
	wear.fractal_octaves = 3
	wear.seed = 11
	var g := grain.get_seamless_image(256, 256)
	var w := wear.get_seamless_image(256, 256)
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var v := 0.86 + (g.get_pixel(x, y).r - 0.5) * 0.12 + (w.get_pixel(x, y).r - 0.5) * 0.22
			img.set_pixel(x, y, Color(v, v, v * 1.01))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(1.0 / 24.0, 1.0 / 24.0, 1.0 / 24.0)      # (the pattern repeats every 24 m)
	mat.roughness = 0.95
	return mat
