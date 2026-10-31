# (Copied from stkilda-godot scripts/town/luna_rides.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkLunaRides
extends RefCounted
## Luna Park's rides and buildings inside its wall. Stage 1 (the heritage three): the Carousel (1913) in its white
## eight-sided building, turning, its horses rising and falling; the Ghost Train's front (1934); Luna Palace, the
## 1927 "fairytale castle" (the dodgems and the arcade inside). Stage 2 (the tall ones): the Sky Rider Ferris wheel,
## the Supernova tower, Pharaoh's Curse and the Coney Drop. Stage 3 (the spinning rides): the Spider, the Power Surge,
## the Arabian Merry. All moving. Where each is: OpenStreetMap; what they look like and the guesses:
## reference/luna_park/NOTES.md. They stand where the map had plain blocks, which are left out (skip_ids()).

const CAROUSEL_WAY := 60252361          # its building's outline (data/luna.json)
const GHOST_TRAIN := "w60252364"        # the map's buildings (data/town.json)
const LUNA_PALACE := "w60252363"
const SKY_RIDER := 9232875705           # (stage 2: the map's points or outlines for them, data/luna.json)
const CONEY_DROP := 9232875725
const SUPERNOVA := 1000251783
const PHARAOH := 1409388255
const POWER_SURGE := 1000251782
const SPIDER := 1000251778             # (stage 3)
const ARABIAN := 1000251781
## Moving rides only move when you're this close (they stand still further off: keeps a phone fast).
const MOVE_NEAR := 160.0

const WHITE := Color("#f4f1ea")
const WHITE_SHADE := Color("#dcd8ce")
const CREAM := Color("#efe3c8")
const BULB := Color("#fff3c4")
const DARK := Color("#1d1b22")

## The map's plain blocks these replace.
static func skip_ids() -> Array:
	return [GHOST_TRAIN, LUNA_PALACE, "w%d" % CAROUSEL_WAY] + SkLunaExtras.REPLACES

## Build them all; returns where you can stand in front of each, for the big map: {name: [spot, which way to face]}.
static func build(parent: Node3D, town: SkTownBuilder, face: Transform3D, els: Array) -> Dictionary:
	var spots := {}
	var into := -face.basis.z                     # (the way into the park from the face)
	for e in els:
		if e.type == "way" and int(e.id) == CAROUSEL_WAY:
			var ring := PackedVector2Array()
			for g in e.geometry:
				ring.append(town.project(g.lat, g.lon))
			var n := _carousel(parent, ring)
			spots["Luna Park - Carousel"] = _spot_before(n.position, into, 16.5)
	for b in town.data.buildings:
		if b.get("id", "") == GHOST_TRAIN:
			var n := _ghost_train(parent, SkTownBuilder._pts(b.p), parent.get_node_or_null("Carousel"))
			spots["Luna Park - Ghost Train"] = _spot_before(n.position, n.transform.basis.z, -12.0)
		elif b.get("id", "") == LUNA_PALACE:
			var n := _luna_palace(parent, SkTownBuilder._pts(b.p), Vector2(face.origin.x, face.origin.z))
			spots["Luna Park - Luna Palace (dodgems)"] = _spot_before(n.position, n.transform.basis.z, -24.0)
	# stage 2: the tall ones
	var at := {}                                  # the map's id -> where it is (map x, z)
	for e in els:
		var id := int(e.id)
		if not (id in [SKY_RIDER, CONEY_DROP, SUPERNOVA, PHARAOH, POWER_SURGE, SPIDER, ARABIAN]):
			continue
		if e.type == "node":
			at[id] = town.project(e.lat, e.lon)
		else:
			var c := Vector2.ZERO
			for g in e.geometry:
				c += town.project(g.lat, g.lon)
			at[id] = c / e.geometry.size()
	if at.has(SKY_RIDER):
		# turned to face across between the Carousel and the Power Surge, so neither's in the wheel's way
		var p: Vector2 = at[SKY_RIDER]
		var along: Vector2 = (at.get(POWER_SURGE, p + Vector2(0, 1)) - p).normalized()
		var n := _sky_rider(parent, p, along)
		spots["Luna Park - Sky Rider (Ferris wheel)"] = _spot_before(n.position, n.transform.basis.z, -16.0)
	if at.has(SUPERNOVA):
		var n := _supernova(parent, at[SUPERNOVA])
		spots["Luna Park - Supernova"] = _spot_before(n.position, into, 14.0)
	if at.has(PHARAOH):
		# swinging across from the coaster's track (toward the Supernova)
		var p: Vector2 = at[PHARAOH]
		var along: Vector2 = (at.get(SUPERNOVA, p + Vector2(1, 0)) - p).normalized()
		var n := _pharaoh(parent, p, along)
		spots["Luna Park - Pharaoh's Curse"] = _spot_before(n.position, n.transform.basis.z, -15.0)
	if at.has(CONEY_DROP):
		var n := _coney_drop(parent, at[CONEY_DROP])
		spots["Luna Park - Coney Drop"] = _spot_before(n.position, into, 9.0)
	# stage 3: the spinning rides (Twin Dragon, the Enterprise and Speedy Beetle were taken out, 2026-10-27: the owner
	# didn't want them)
	if at.has(SPIDER):
		var n := _spider(parent, at[SPIDER])
		spots["Luna Park - Spider"] = _spot_before(n.position, into, 13.0)
	if at.has(POWER_SURGE):
		var n := _power_surge(parent, at[POWER_SURGE])
		spots["Luna Park - Power Surge"] = _spot_before(n.position, into, 13.0)
	if at.has(ARABIAN):
		var n := _arabian_merry(parent, at[ARABIAN])
		spots["Luna Park - Arabian Merry"] = _spot_before(n.position, into, 11.0)
	return spots

## A spot `back` m from `at` against `dir` (so standing there facing `at`): [spot, facing].
static func _spot_before(at: Vector3, dir: Vector3, back: float) -> Array:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	return [Vector3(at.x, 0, at.z) - d * back, d * signf(back)]

## The smallest rectangle round an outline: [middle, along (unit), half its length that way, half its width].
static func _rect(ring: PackedVector2Array) -> Array:
	var best := INF
	var out := []
	for k in ring.size():
		var d := ring[(k + 1) % ring.size()] - ring[k]
		if d.length() < 0.5:
			continue
		var u := d.normalized()
		var v := u.orthogonal()
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in ring:
			var q := Vector2(p.dot(u), p.dot(v))
			lo = lo.min(q)
			hi = hi.max(q)
		var area := (hi.x - lo.x) * (hi.y - lo.y)
		if area < best:
			best = area
			var mid := (lo + hi) / 2.0
			out = [u * mid.x + v * mid.y, u, (hi.x - lo.x) / 2.0, (hi.y - lo.y) / 2.0]
	return out

## A node standing at a rectangle's middle, turned so its +z (its front) looks toward `toward` along one of the
## rectangle's sides: [node, half its width (x), half its depth (z)].
static func _facing(parent: Node3D, name: String, r: Array, toward: Vector2) -> Array:
	var mid: Vector2 = r[0]
	var u: Vector2 = r[1]
	var v := u.orthogonal()
	var to := toward - mid
	var front: Vector2
	var half_w: float
	var half_d: float
	if absf(to.dot(u)) > absf(to.dot(v)):
		front = u * signf(to.dot(u))
		half_w = r[3]
		half_d = r[2]
	else:
		front = v * signf(to.dot(v))
		half_w = r[2]
		half_d = r[3]
	var n := Node3D.new()
	n.name = name
	n.transform = Transform3D(Basis(Vector3.UP, atan2(front.x, front.y)), Vector3(mid.x, 0, mid.y))
	parent.add_child(n)
	return [n, half_w, half_d]

static func _bake(n: Node3D, holder: Node3D, name := "Mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = SkModels.bake(holder)
	mi.material_override = SkModels.baked_material()
	holder.free()
	n.add_child(mi)
	return mi

static func _solid(n: Node3D, size: Vector3, at: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = SkData.LAYER_WORLD
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = at
	b.add_child(cs)
	n.add_child(b)

## A cone (or a slice of one) standing up.
static func _cone(parent: Node3D, r0: float, r1: float, tall: float, pos: Vector3, c: Color, sides := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = tall
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.material_override = SkModels.mat(c)
	parent.add_child(mi)
	return mi

# ================================================================ the Carousel

const CAROUSEL_R := 7.5                  # the ride's platform (GUESS: a usual four-row size)
const ROWS := [[3.4, 12], [4.5, 14], [5.6, 16], [6.7, 18]]     # [radius, horses] a row (GUESS)
const HORSES := [[Color("#e9d2a6"), Color("#b5743d")], [Color("#f2ede4"), Color("#7b4a2c")], [Color("#f4f1ea"), Color("#c23a32")],
	[Color("#2a2627"), Color("#d6b04c")], [Color("#c8925a"), Color("#f2ede4")], [Color("#8a5a3a"), Color("#f2ede4")]]

static func _carousel(parent: Node3D, ring: PackedVector2Array) -> Node3D:
	if ring.size() > 3 and ring[0].is_equal_approx(ring[-1]):
		ring.remove_at(ring.size() - 1)
	var mid := Vector2.ZERO
	for p in ring:
		mid += p
	mid /= ring.size()
	var n := Node3D.new()
	n.name = "Carousel"
	n.position = Vector3(mid.x, 0, mid.y)
	parent.add_child(n)
	# its building: piers at the outline's corners, an arch over each side under a white band with portholes and bulbs,
	# lanterns on the piers, a pale grey roof up to a little lantern on top
	var holder := Node3D.new()
	var corners := []
	for p in ring:
		corners.append(Vector3(p.x - mid.x, 0, p.y - mid.y))
	var band_lo := 4.6
	var band_hi := 6.4
	for k in corners.size():
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % corners.size()]
		var along := (b - a)
		var len := along.length()
		var yaw := -atan2(along.z, along.x)
		var c := (a + b) / 2.0
		var out := Vector3(c.x, 0, c.z).normalized()
		SkModels.box(holder, Vector3(1.1, band_hi, 1.1), a + Vector3(0, band_hi / 2.0, 0), WHITE)
		var band := SkModels.box(holder, Vector3(len, band_hi - band_lo, 0.5), c + Vector3(0, (band_hi + band_lo) / 2.0, 0), WHITE)
		band.rotation.y = yaw
		# the arch: the opening's top corners filled in, stepping in toward the middle
		for s in [-1.0, 1.0]:
			for step in 3:
				var w := (len / 2.0) * (0.34 - step * 0.1)
				var piece := SkModels.box(holder, Vector3(w, 0.45, 0.45), c + along.normalized() * s * (len / 2.0 - w / 2.0) + Vector3(0, band_lo - 0.22 - step * 0.45, 0), WHITE_SHADE)
				piece.rotation.y = yaw
		# the bulbs round the arch and along the band, the portholes, the lantern on the pier
		for q in 9:
			var t := (q + 0.5) / 9.0
			var p := a.lerp(b, t) + out * 0.28 + Vector3(0, band_lo + 0.12, 0)
			SkModels.box(holder, Vector3(0.14, 0.14, 0.14), p, BULB)
			SkModels.box(holder, Vector3(0.14, 0.14, 0.14), a.lerp(b, t) + out * 0.28 + Vector3(0, band_hi - 0.15, 0), BULB)
		for q in 3:
			var p := a.lerp(b, 0.3 + q * 0.2) + out * 0.27 + Vector3(0, band_lo + 0.95, 0)
			var hole := SkModels.cyl(holder, 0.2, 0.06, p, Color("#4a4d55"), true, 10)
			hole.rotation = Vector3(PI / 2.0, yaw, 0)
		SkModels.box(holder, Vector3(0.45, 0.6, 0.45), a + Vector3(a.x, 0, a.z).normalized() * 0.65 + Vector3(0, 4.1, 0), Color("#fbf6e6"))
	# the roof: a low pyramid up from the band's top, then a little lantern
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3(0, band_hi + 3.0, 0)
	for k in corners.size():
		var a: Vector3 = corners[k] * 1.04 + Vector3(0, band_hi, 0)
		var b: Vector3 = corners[(k + 1) % corners.size()] * 1.04 + Vector3(0, band_hi, 0)
		var nrm := (b - a).cross(apex - a).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		st.set_normal(nrm)
		st.set_color(Color("#c9ccce"))
		st.add_vertex(a)
		if (b - a).cross(apex - a).dot(nrm) > 0.0:
			st.add_vertex(apex)
			st.add_vertex(b)
		else:
			st.add_vertex(b)
			st.add_vertex(apex)
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	roof.mesh = st.commit()
	roof.material_override = SkWornLook.material()
	n.add_child(roof)
	_cone(holder, 1.4, 1.4, 1.0, Vector3(0, band_hi + 2.9, 0), WHITE, 8)
	_cone(holder, 1.6, 0.0, 1.0, Vector3(0, band_hi + 3.9, 0), Color("#b9bdc0"), 8)
	# the black iron fence round it, 2 m out, with a gateway in the middle of each side (where they are: GUESS)
	var fence := []                                  # [from, to] of each length of it
	for k in corners.size():
		var a: Vector3 = corners[k] + Vector3(corners[k].x, 0, corners[k].z).normalized() * 2.0
		var b: Vector3 = corners[(k + 1) % corners.size()] + Vector3(corners[(k + 1) % corners.size()].x, 0, corners[(k + 1) % corners.size()].z).normalized() * 2.0
		var gap := 1.6 / a.distance_to(b)
		fence.append([a, a.lerp(b, 0.5 - gap)])
		fence.append([a.lerp(b, 0.5 + gap), b])
	for f in fence:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		for y in [0.25, 1.0]:
			_strut(holder, a + Vector3(0, y, 0), b + Vector3(0, y, 0), 0.06, Color("#1b1c1f"))
		var bars := int(a.distance_to(b) / 0.18)
		for q in bars + 1:
			var p := a.lerp(b, float(q) / maxf(1.0, bars))
			SkModels.box(holder, Vector3(0.03, 1.05, 0.03), p + Vector3(0, 0.55, 0), Color("#1b1c1f"))
			if q % 6 == 0:
				SkModels.box(holder, Vector3(0.09, 1.25, 0.09), p + Vector3(0, 0.62, 0), Color("#1b1c1f"))
				SkModels.ball(holder, 0.07, p + Vector3(0, 1.3, 0), Color("#1b1c1f"))
	_bake(n, holder, "Building").material_override = SkWornLook.material()
	for k in corners.size():
		_solid(n, Vector3(1.1, band_hi, 1.1), corners[k] + Vector3(0, band_hi / 2.0, 0))
	for f in fence:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var bar := Node3D.new()
		n.add_child(bar)
		bar.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) / 2.0)
		_solid(bar, Vector3(0.12, 1.2, a.distance_to(b)), Vector3(0, 0.6, 0))
	# the ride itself, turning
	var spin := Spinner.new()
	spin.name = "Ride"
	n.add_child(spin)
	var ride := Node3D.new()
	SkModels.cyl(ride, CAROUSEL_R, 0.5, Vector3(0, 0.35, 0), Color("#6f7a86"), true, 32)
	SkModels.cyl(ride, CAROUSEL_R + 0.05, 0.1, Vector3(0, 0.62, 0), Color("#55606b"), true, 32)
	# the middle: a drum of mirrors and gold
	SkModels.cyl(ride, 2.0, 3.6, Vector3(0, 2.4, 0), CREAM, true, 16)
	for k in 8:
		var a := TAU * k / 8.0
		var m := SkModels.box(ride, Vector3(0.7, 1.4, 0.06), Vector3(cos(a) * 2.02, 2.6, sin(a) * 2.02), Color("#b9d3e2"))
		m.rotation.y = -a + PI / 2.0
		var f := SkModels.box(ride, Vector3(0.9, 1.6, 0.04), Vector3(cos(a) * 2.0, 2.6, sin(a) * 2.0), Color("#d9ab3a"))
		f.rotation.y = -a + PI / 2.0
	# the canopy: its cream rim (with gold crowns, framed panels and bulbs), and its top
	SkModels.cyl(ride, CAROUSEL_R + 0.2, 1.1, Vector3(0, 4.75, 0), CREAM, true, 32)
	SkModels.cyl(ride, CAROUSEL_R + 0.25, 0.12, Vector3(0, 4.2, 0), Color("#e8d9b5"), true, 32)      # (its ceiling: cream)
	_cone(ride, CAROUSEL_R + 0.1, 1.0, 1.9, Vector3(0, 6.25, 0), Color("#d8c39a"), 24)
	for k in 12:
		var a := TAU * k / 12.0
		var at := Vector3(cos(a), 0, sin(a)) * (CAROUSEL_R + 0.25)
		var panel := SkModels.box(ride, Vector3(1.3, 0.75, 0.08), at + Vector3(0, 4.8, 0), Color("#d9ab3a"))
		panel.rotation.y = -a + PI / 2.0
		# (its oval painted panel: a sky over a green hill, in a cream frame)
		var oval := Node3D.new()
		ride.add_child(oval)
		oval.position = at + Vector3(0, 4.8, 0)
		oval.rotation.y = -a + PI / 2.0
		for o in [[0.3, Color("#f3e6c4"), 0.06], [0.25, Color("#7fb3d1"), 0.08]]:
			var d := _disc(oval, o[0], 0.04, Vector3(0, 0, o[2]), o[1])
			d.scale = Vector3(1.55, 1.0, 1.0)
		SkModels.box(oval, Vector3(0.62, 0.12, 0.02), Vector3(0, -0.12, 0.13), Color("#5f9a4a"))
		var crown := SkModels.box(ride, Vector3(0.6, 0.6, 0.15), at + Vector3(0, 5.55, 0), Color("#d9ab3a"))
		crown.rotation = Vector3(0, -a + PI / 2.0, PI / 4.0)
	# rows of bulbs under the ceiling, and red stencilled flowers round its rim
	for rr in [2.6, 4.0, 5.4, 6.8]:
		for k in int(rr * 4.0):
			var a := TAU * k / int(rr * 4.0)
			SkModels.box(ride, Vector3(0.1, 0.1, 0.1), Vector3(cos(a) * rr, 4.08, sin(a) * rr), BULB)
	for k in 24:
		var a := TAU * (k + 0.5) / 24.0
		var flower := SkModels.box(ride, Vector3(0.35, 0.35, 0.05), Vector3(cos(a), 0, sin(a)) * (CAROUSEL_R + 0.22) + Vector3(0, 4.45, 0), Color("#a83a32"))
		flower.rotation = Vector3(0, -a + PI / 2.0, PI / 4.0)
	for k in 48:
		var a := TAU * (k + 0.5) / 48.0
		SkModels.box(ride, Vector3(0.12, 0.12, 0.12), Vector3(cos(a), 0, sin(a)) * (CAROUSEL_R + 0.3) + Vector3(0, 4.12, 0), BULB)
	# the rim's scalloped lower edge (gold points)
	for k in 96:
		var a := TAU * k / 96.0
		var sc := SkModels.box(ride, Vector3(0.32, 0.32, 0.05), Vector3(cos(a), 0, sin(a)) * (CAROUSEL_R + 0.24) + Vector3(0, 4.2, 0), Color("#d9ab3a"))
		sc.rotation = Vector3(0, -a + PI / 2.0, PI / 4.0)
	# the brass poles, and the horses on them (they ride up and down: Spinner moves them)
	var horses := []
	var kinds := []
	for h in HORSES.size():
		kinds.append(_horse(HORSES[h][0], HORSES[h][1]))
	kinds.append(_chariot())
	var count := 0
	var spots := []                              # [which kind, where it stands, how far it rises, its phase]
	for row in ROWS:
		var r: float = row[0]
		var many: int = row[1]
		for k in many:
			var a := TAU * (k + 0.5 * (count % 2)) / many
			var at := Vector3(cos(a), 0, sin(a)) * r
			SkModels.cyl(ride, 0.05, 3.55, at + Vector3(0, 2.38, 0), Color("#d9b24a"), true, 6)
			for y in [1.05, 3.75]:                   # (the twisted brass's bands)
				SkModels.cyl(ride, 0.08, 0.1, at + Vector3(0, y, 0), Color("#e8c25a"), true, 6)
			var chariot := r > 6.0 and k % 9 == 4
			var kind: int = kinds.size() - 1 if chariot else (k * 7 + count * 3) % HORSES.size()
			# (facing round the way it turns: anticlockwise from above)
			spots.append([kind, Transform3D(Basis(Vector3.UP, -a), at + Vector3(0, 0.6, 0)), 0.0 if chariot else 0.35, float(k) * 1.7 + count])
		count += 1
	_bake(spin, ride, "Platform")
	# the horses, drawn in one batch for each paint job (sixty separate ones were sixty draws)
	var batches := []
	var used := []
	for kind in kinds.size():
		used.append(0)
	for s in spots:
		used[s[0]] += 1
	for kind in kinds.size():
		batches.append(_batch(spin, kinds[kind], used[kind], "Horses%d" % kind))
		used[kind] = 0
	for s in spots:
		var i: int = used[s[0]]
		used[s[0]] += 1
		var b: MultiMeshInstance3D = batches[s[0]]
		b.multimesh.set_instance_transform(i, s[1])
		horses.append([b, i, s[1], s[2], s[3]])
	spin.horses = horses
	# people on about half the horses, astride, holding the pole (a few kids waving)
	var seats := []
	for h in horses:
		if float(h[3]) > 0.0 and _taken(0.5):
			seats.append([(h[0] as MultiMeshInstance3D).multimesh, h[1], _seat(Vector3(-0.32, 1.36, 0), -PI / 2.0, 0.85)])
	spin.riders = _riders(spin, seats, 0.0, 0.8, 0.15)
	return n

## Many copies of one mesh drawn in one go (one draw for them all), each placed by set_instance_transform; no
## shadows (small moving parts: their shadows cost a draw each and you'd hardly see them).
static func _batch(parent: Node3D, mesh: Mesh, count: int, name := "Batch") -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.name = name
	mi.multimesh = mm
	mi.material_override = SkModels.baked_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 500.0
	parent.add_child(mi)
	return mi

# ================================================================ people riding (the owner: a packed park)

static var _rider_rng: RandomNumberGenerator

## SkPeople riding, all in one batch (SkCrowd's townsfolk), under `parent` (the ride's moving part): `seats` is a list of
## [what they ride on (a batch's MultiMesh, or a node under `parent`), which copy in the batch, where on it (their
## feet at its origin, facing -z)]. How they sit: `legs` 0 hanging down .. 1 straight out in front; `hold` arms out in
## front holding on; `cheer` how many have their arms right up in the air.
static func _riders(parent: Node3D, seats: Array, legs: float, hold: float, cheer: float) -> Riders:
	if _rider_rng == null:
		_rider_rng = RandomNumberGenerator.new()
		_rider_rng.seed = 1912
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = SkCrowd.person_mesh()
	mm.instance_count = seats.size()
	for k in seats.size():
		mm.set_instance_custom_data(k, Color(float(_rider_rng.randi() % 8) / 16.0, _rider_rng.randf() * TAU,
			float(_rider_rng.randi() % 6) / 8.0 + float(_rider_rng.randi() % 5) / 64.0, _rider_rng.randf()))
	var r := Riders.new()
	r.name = "Riders"
	r.multimesh = mm
	var m := SkCrowd.material().duplicate() as ShaderMaterial
	m.set_shader_parameter("legs", legs)
	m.set_shader_parameter("hold", hold)
	m.set_shader_parameter("cheer", cheer)
	r.material_override = m
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.visibility_range_end = 220.0
	r.seats = seats
	parent.add_child(r)
	r.follow()
	return r

## Where a rider sits: their hips (0.88 up a standing person) at `hips`, turned `yaw`, `s` their size.
static func _seat(hips: Vector3, yaw: float, s := 0.95) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), hips - Vector3(0, 0.88 * s, 0))

## Whether to fill a seat (`fill` of them are, the same ones every time).
static func _taken(fill: float) -> bool:
	if _rider_rng == null:
		_rider_rng = RandomNumberGenerator.new()
		_rider_rng.seed = 1912
	return _rider_rng.randf() < fill

## The riders on a ride: follow() puts each back on what they ride on (after the ride's moved it).
class Riders extends MultiMeshInstance3D:
	var seats: Array = []

	func follow() -> void:
		var buf := multimesh.buffer           # (written in one go: see SkCrowd.put)
		for i in seats.size():
			var s: Array = seats[i]
			var on := Transform3D.IDENTITY
			if s[0] is MultiMesh:
				on = (s[0] as MultiMesh).get_instance_transform(s[1])
			elif s[0] is Node3D:
				on = (s[0] as Node3D).transform
			SkCrowd.put(buf, i, on * (s[2] as Transform3D))
		multimesh.buffer = buf

## A carousel horse, prancing, facing -z... no: along +x (it's turned to face round the ride).
static func _horse(coat: Color, mane: Color) -> ArrayMesh:
	var h := Node3D.new()
	SkModels.box(h, Vector3(1.25, 0.5, 0.36), Vector3(0, 1.0, 0), coat)                  # body
	var neck := SkModels.box(h, Vector3(0.32, 0.7, 0.26), Vector3(0.55, 1.42, 0), coat)
	neck.rotation.z = -0.5
	SkModels.box(h, Vector3(0.5, 0.24, 0.24), Vector3(0.88, 1.72, 0), coat)             # head
	var m := SkModels.box(h, Vector3(0.36, 0.5, 0.1), Vector3(0.48, 1.55, 0), mane)
	m.rotation.z = -0.5
	for s in [-1.0, 1.0]:
		var fl := SkModels.box(h, Vector3(0.12, 0.55, 0.12), Vector3(0.45, 0.65, s * 0.12), coat)
		fl.rotation.z = 0.9
		var bl := SkModels.box(h, Vector3(0.12, 0.6, 0.12), Vector3(-0.48, 0.55, s * 0.12), coat)
		bl.rotation.z = -0.35
	SkModels.box(h, Vector3(0.45, 0.12, 0.42), Vector3(-0.05, 1.3, 0), Color("#6a2b2b"))   # saddle
	_disc(h, 0.24, 0.05, Vector3(0.1, 1.0, 0.21), Color("#d9ab3a"))      # (the gold shield on its saddle)
	SkModels.box(h, Vector3(0.1, 0.1, 0.05), Vector3(0.1, 1.0, 0.25), Color("#c0262c"))      # (its jewel)
	var tail := SkModels.box(h, Vector3(0.12, 0.5, 0.12), Vector3(-0.68, 0.95, 0), mane)
	tail.rotation.z = 0.4
	var mesh := SkModels.bake(h)
	h.free()
	return mesh

## The pink and blue chariot.
static func _chariot() -> ArrayMesh:
	var h := Node3D.new()
	SkModels.box(h, Vector3(1.4, 0.7, 0.9), Vector3(0, 0.55, 0), Color("#d8366f"))
	SkModels.box(h, Vector3(1.45, 0.25, 0.95), Vector3(0, 0.95, 0), Color("#3d7fd0"))
	SkModels.box(h, Vector3(0.2, 0.9, 0.95), Vector3(0.65, 1.0, 0), Color("#d9ab3a"))
	_disc(h, 0.32, 0.08, Vector3(0, 0.35, 0.5), Color("#f4f1ea"))
	var mesh := SkModels.bake(h)
	h.free()
	return mesh

## Turns the carousel and rides its horses up and down (only when you're near: it stands still further off).
class Spinner extends Node3D:
	var horses: Array = []             # [its batch, its number in it, where it stands, how far it rises, its phase]
	var riders: Riders = null
	var _t := 0.0

	func _process(dt: float) -> void:
		if not SkLunaRides._near(self):
			return
		_t += dt
		rotation.y = fposmod(rotation.y + dt * 0.45, TAU)
		for h in horses:
			var xf: Transform3D = h[2]
			xf.origin.y = 0.6 + (sin(_t * 2.2 + float(h[4])) * 0.5 + 0.5) * float(h[3])
			(h[0] as MultiMeshInstance3D).multimesh.set_instance_transform(h[1], xf)
		if riders:
			riders.follow()

# ================================================================ the Ghost Train

const GHOST_H := 6.0
const LAVENDER := Color("#a19ec0")

static func _ghost_train(parent: Node3D, ring: PackedVector2Array, toward: Node3D) -> Node3D:
	var r := _rect(ring)
	var mid: Vector2 = r[0]
	var to := Vector2(toward.position.x, toward.position.z) if toward else mid + Vector2(1, 0)
	var f := _facing(parent, "GhostTrain", r, to)
	var n: Node3D = f[0]
	var hw: float = f[1]
	var hd: float = f[2]
	var holder := Node3D.new()
	var front := hd + 0.05
	SkModels.box(holder, Vector3(hw * 2.0, GHOST_H, hd * 2.0), Vector3(0, GHOST_H / 2.0, 0), LAVENDER.darkened(0.15))
	SkModels.box(holder, Vector3(hw * 2.0, GHOST_H + 1.4, 0.4), Vector3(0, (GHOST_H + 1.4) / 2.0, hd - 0.2), LAVENDER)
	# scrolls and columns painted on, as raised strips
	for s in [-1.0, 1.0]:
		SkModels.box(holder, Vector3(0.7, GHOST_H + 1.0, 0.25), Vector3(s * (hw - 0.6), (GHOST_H + 1.0) / 2.0, front + 0.05), Color("#c3c1d8"))
		SkModels.box(holder, Vector3(1.0, 0.4, 0.35), Vector3(s * (hw - 0.6), GHOST_H + 0.3, front + 0.1), Color("#d4d2e4"))
	# the two dark doorways the cars go in and out of
	for s in [-1.0, 1.0]:
		SkModels.box(holder, Vector3(2.6, 2.8, 0.1), Vector3(s * hw * 0.45, 1.4, front), DARK)
		_disc(holder, 1.3, 0.1, Vector3(s * hw * 0.45, 2.8, front), DARK)
		SkModels.box(holder, Vector3(2.9, 0.15, 0.3), Vector3(s * hw * 0.45, 0.08, front + 0.3), Color("#3b3b40"))     # its rails
	# the sign's dark green board, ivy hanging along the top, flames behind a row of skeletons
	SkModels.box(holder, Vector3(hw * 1.5, 1.1, 0.15), Vector3(0, 4.55, front + 0.05), Color("#173a1c"))
	for k in int(hw * 2.0 / 0.35):
		var x := -hw + 0.2 + k * 0.35
		var long := 0.3 + float(hash(k) % 5) * 0.12
		SkModels.box(holder, Vector3(0.28, long, 0.1), Vector3(x, GHOST_H - 0.05 - long / 2.0, front + 0.12), Color("#5d8f3a"))
	for k in int(hw * 2.0 / 0.9):
		var x := -hw + 0.5 + k * 0.9
		var flame := SkModels.box(holder, Vector3(0.55, 0.55, 0.08), Vector3(x, GHOST_H + 0.75, hd - 0.3), Color("#ef7d22") if k % 2 == 0 else Color("#f6c23a"))
		flame.rotation.z = PI / 4.0
		if absf(x) < 1.6:
			continue
		_skull(holder, Vector3(x, GHOST_H + 0.55, hd - 0.05), 0.42)
		SkModels.box(holder, Vector3(0.3, 0.5, 0.2), Vector3(x, GHOST_H + 0.1, hd - 0.05), Color("#e8e6e0"))   # (its ribs)
		# (playing music: a horn, a drum, a fiddle in turn)
		match k % 3:
			0:
				var horn := SkModels.cyl(holder, 0.07, 0.6, Vector3(x + 0.12, GHOST_H + 0.35, hd + 0.2), Color("#e0b23a"), true, 8)
				horn.rotation = Vector3(1.1, 0, -0.5)
				var bell := _cone(holder, 0.08, 0.2, 0.18, Vector3(x + 0.3, GHOST_H + 0.22, hd + 0.42), Color("#e0b23a"), 8)
				bell.rotation = Vector3(1.1, 0, -0.5)
			1:
				_disc(holder, 0.22, 0.25, Vector3(x, GHOST_H - 0.05, hd + 0.18), Color("#b8302c"))
				_disc(holder, 0.19, 0.27, Vector3(x, GHOST_H - 0.05, hd + 0.18), Color("#efe6d2"))
			2:
				var body := SkModels.box(holder, Vector3(0.22, 0.34, 0.08), Vector3(x - 0.08, GHOST_H + 0.12, hd + 0.12), Color("#7a4320"))
				body.rotation.z = 0.6
				var neck := SkModels.box(holder, Vector3(0.05, 0.4, 0.05), Vector3(x + 0.1, GHOST_H + 0.38, hd + 0.12), Color("#3a2010"))
				neck.rotation.z = 0.6
	# the vampire's face in the middle below, gargoyles on the corners
	SkModels.box(holder, Vector3(1.2, 1.0, 0.2), Vector3(0, GHOST_H - 0.3, front + 0.12), Color("#8d89a8"))
	for s in [-1.0, 1.0]:
		SkModels.box(holder, Vector3(0.2, 0.12, 0.1), Vector3(s * 0.25, GHOST_H - 0.2, front + 0.24), Color("#c0262c"))
		var g := Node3D.new()
		holder.add_child(g)
		g.position = Vector3(s * (hw - 0.7), GHOST_H + 1.4, hd - 0.4)
		SkModels.box(g, Vector3(0.7, 0.8, 0.9), Vector3(0, 0.4, 0), Color("#8f9097"))
		SkModels.box(g, Vector3(0.45, 0.4, 0.5), Vector3(0, 0.95, 0.3), Color("#8f9097"))
		for w in [-1.0, 1.0]:
			var wing := SkModels.box(g, Vector3(0.1, 0.8, 0.7), Vector3(w * 0.45, 0.7, -0.1), Color("#7b7c84"))
			wing.rotation.z = w * 0.5
	# the big skeleton in the top hat with his cannon, in the middle on top
	var big := Node3D.new()
	holder.add_child(big)
	big.position = Vector3(0, GHOST_H + 1.4, hd - 0.5)
	SkModels.box(big, Vector3(1.4, 1.6, 0.8), Vector3(0, 0.8, 0), Color("#3d3f47"))          # his coat
	_skull(big, Vector3(0, 2.15, 0.1), 1.0)
	SkModels.cyl(big, 0.55, 1.0, Vector3(0, 3.15, 0.05), Color("#141416"), true, 16)        # the hat
	SkModels.cyl(big, 0.56, 0.2, Vector3(0, 2.8, 0.05), Color("#9a3a3a"), true, 16)
	SkModels.cyl(big, 0.85, 0.08, Vector3(0, 2.65, 0.05), Color("#141416"), true, 16)
	var cannon := SkModels.cyl(big, 0.25, 1.6, Vector3(-0.9, 1.6, 0.6), Color("#55473d"), true, 12)
	cannon.rotation = Vector3(0.9, 0, -0.6)
	# (GUESSES, for the spooky look: painted bats on the front between the doorways and along the sides, cobwebs in the
	# top corners under the ivy)
	for b in [[Vector3(-1.2, 3.2, front + 0.02), 0.0], [Vector3(0.9, 2.4, front + 0.02), 0.0], [Vector3(-0.3, 1.4, front + 0.02), 0.0]]:
		_bat(holder, b[0], 0.0)
	for s in [-1.0, 1.0]:
		for q in 4:
			_bat(holder, Vector3(s * (hw + 0.02), 3.0 + float(q % 2) * 1.3, hd - 2.5 - q * 2.6), s * PI / 2.0)
		var corner := Vector3(s * (hw - 1.0), GHOST_H - 0.5, front + 0.2)
		for q in 5:
			var a: float = PI * 0.5 + s * (PI * 0.5 - q * PI / 8.0)
			_strut(holder, corner, corner + Vector3(cos(a) * 1.4, -absf(sin(a)) * 1.4 - 0.05, 0), 0.02, Color("#ecebf2"))
		for web in [0.5, 1.0]:
			for q in 4:
				var a0: float = PI * 0.5 + s * (PI * 0.5 - q * PI / 8.0)
				var a1: float = PI * 0.5 + s * (PI * 0.5 - (q + 1) * PI / 8.0)
				_strut(holder, corner + Vector3(cos(a0), -absf(sin(a0)), 0) * web, corner + Vector3(cos(a1), -absf(sin(a1)), 0) * web, 0.018, Color("#ecebf2"))
	_bake(n, holder, "GhostTrain").material_override = SkWornLook.material()
	# eyes glowing in the dark of the doorways (GUESS)
	var eyes := []
	for s in [-1.0, 1.0]:
		for e in [[-0.6, 1.9], [0.5, 1.2], [0.1, 2.6]]:
			for side in [-0.13, 0.13]:
				eyes.append(Vector3(s * hw * 0.45 + float(e[0]) + side, float(e[1]), front + 0.08))
	SkRideLights._bulbs(n, eyes, 0.0, [Color(1.0, 0.82, 0.15)])
	# the sign
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Chiller", "Brush Script MT", "Segoe Script", "cursive"])
	font.font_weight = 700
	var l := Label3D.new()
	l.name = "Sign"
	l.text = "Ghost Train"
	l.font = font
	l.font_size = 96
	l.pixel_size = 0.9 / 96.0
	l.modulate = Color("#9cf03c")
	l.outline_modulate = Color("#0e2410")
	l.outline_size = 10
	l.position = Vector3(0, 4.55, front + 0.16)
	n.add_child(l)
	_solid(n, Vector3(hw * 2.0, GHOST_H + 1.4, hd * 2.0), Vector3(0, (GHOST_H + 1.4) / 2.0, 0))
	return n

## A bat painted on a wall at `at`, its wall facing +z turned by `yaw`: a body, ears, wings out in a V.
static func _bat(parent: Node3D, at: Vector3, yaw: float) -> void:
	var b := Node3D.new()
	parent.add_child(b)
	b.position = at
	b.rotation.y = yaw
	var c := Color("#1d1a24")
	SkModels.box(b, Vector3(0.13, 0.24, 0.03), Vector3.ZERO, c)
	for s in [-1.0, 1.0]:
		SkModels.box(b, Vector3(0.04, 0.07, 0.03), Vector3(s * 0.04, 0.15, 0), c)
		var w := SkModels.box(b, Vector3(0.42, 0.13, 0.03), Vector3(s * 0.25, 0.05, 0), c)
		w.rotation.z = s * 0.35
		var tip := SkModels.box(b, Vector3(0.18, 0.1, 0.03), Vector3(s * 0.47, 0.1, 0), c)
		tip.rotation.z = -s * 0.5

## A skull (white, dark eyes and nose) facing +z, `s` across.
static func _skull(parent: Node3D, at: Vector3, s: float) -> void:
	SkModels.box(parent, Vector3(s, s, s * 0.9), at, Color("#efece4"))
	SkModels.box(parent, Vector3(s * 0.7, s * 0.3, s * 0.7), at + Vector3(0, -s * 0.55, 0.05 * s), Color("#e2ded4"))
	for e in [-1.0, 1.0]:
		SkModels.box(parent, Vector3(s * 0.26, s * 0.26, 0.05), at + Vector3(e * s * 0.22, s * 0.05, s * 0.46), DARK)
	SkModels.box(parent, Vector3(s * 0.12, s * 0.16, 0.05), at + Vector3(0, -s * 0.2, s * 0.46), DARK)

# ================================================================ Luna Palace

const PALACE_H := 9.0
const TOWER_H := 13.0
const CAPS := [Color("#c8202a"), Color("#2f8f86"), Color("#f2e3b3")]

static func _luna_palace(parent: Node3D, ring: PackedVector2Array, face: Vector2) -> Node3D:
	var f := _facing(parent, "LunaPalace", _rect(ring), face)
	var n: Node3D = f[0]
	var hw: float = f[1]
	var hd: float = f[2]
	var holder := Node3D.new()
	var front := hd + 0.05
	SkModels.box(holder, Vector3(hw * 2.0, PALACE_H, hd * 2.0), Vector3(0, PALACE_H / 2.0, 0), WHITE)
	SkModels.box(holder, Vector3(hw * 2.0 + 0.3, 0.35, hd * 2.0 + 0.3), Vector3(0, 4.3, 0), WHITE_SHADE)       # the ledge between floors
	SkModels.box(holder, Vector3(hw * 2.0 + 0.3, 0.4, hd * 2.0 + 0.3), Vector3(0, PALACE_H, 0), WHITE_SHADE)
	# the round tower at the front corner, its slit windows and its battlements
	var tower := Vector3(-hw + 3.0, 0, hd - 3.0)
	SkModels.cyl(holder, 4.0, TOWER_H, tower + Vector3(0, TOWER_H / 2.0, 0), WHITE, true, 20)
	for k in 12:
		var a := TAU * k / 12.0
		SkModels.box(holder, Vector3(0.9, 0.8, 0.9), tower + Vector3(cos(a) * 3.7, TOWER_H + 0.4, sin(a) * 3.7), WHITE)
	for y in [5.5, 9.0]:
		for k in 3:
			var a := PI * 0.15 + k * PI * 0.25
			SkModels.box(holder, Vector3(0.25, 1.1, 0.25), tower + Vector3(cos(a) * 4.0, y, sin(a) * 4.0), DARK)
	# upstairs: tall round-arched windows (the 2008 photo: dark glass, white glazing bars, a fan in the arch) in a
	# white frame on a sill; downstairs: a deep arcade of arches between square pillars; along the front
	var span := hw * 2.0 - 8.0
	var many := maxi(2, int(span / 4.5))
	var glass := Color("#24303d")
	for k in many:
		var x := -hw + 7.0 + (k + 0.5) * span / many
		SkModels.box(holder, Vector3(2.5, 2.4, 0.1), Vector3(x, 6.0, front + 0.02), WHITE_SHADE)
		_disc(holder, 1.25, 0.1, Vector3(x, 7.2, front + 0.02), WHITE_SHADE)
		SkModels.box(holder, Vector3(2.0, 2.4, 0.1), Vector3(x, 6.0, front + 0.06), glass)
		_disc(holder, 1.0, 0.1, Vector3(x, 7.2, front + 0.06), glass)
		SkModels.box(holder, Vector3(2.8, 0.18, 0.35), Vector3(x, 4.78, front + 0.12), WHITE_SHADE)
		SkModels.box(holder, Vector3(0.08, 3.3, 0.06), Vector3(x, 6.45, front + 0.12), WHITE)
		SkModels.box(holder, Vector3(2.0, 0.08, 0.06), Vector3(x, 7.2, front + 0.12), WHITE)
		SkModels.box(holder, Vector3(2.0, 0.06, 0.06), Vector3(x, 5.9, front + 0.12), WHITE)
		for a in [PI / 4.0, 3.0 * PI / 4.0]:
			_strut(holder, Vector3(x, 7.2, front + 0.12), Vector3(x + cos(a) * 0.98, 7.2 + sin(a) * 0.98, front + 0.12), 0.06, WHITE)
		SkModels.box(holder, Vector3(2.6, 3.0, 0.1), Vector3(x, 1.5, front), Color("#2b2a2e"))
		_disc(holder, 1.3, 0.1, Vector3(x, 3.0, front), Color("#2b2a2e"))
	for k in many + 1:
		var px := -hw + 7.0 + k * span / many
		SkModels.box(holder, Vector3(0.7, 3.4, 0.35), Vector3(px, 1.7, front + 0.15), WHITE_SHADE)
		SkModels.box(holder, Vector3(0.95, 0.25, 0.5), Vector3(px, 3.45, front + 0.18), WHITE)
	# slim turrets along the top with pointed caps in red, teal and cream
	var tops := PackedVector3Array([tower + Vector3(0, TOWER_H, 0)])      # (for SkParkFlags: a flag on each)
	var t := 0
	for side in [[Vector3(1, 0, 0), hd, hw], [Vector3(0, 0, 1), hw, hd], [Vector3(-1, 0, 0), hd, hw]]:
		var out: Vector3 = side[0]
		var across := Vector3(out.z, 0, -out.x)
		var reach: float = side[1]
		var edge: float = side[2]
		var k := -reach + 2.0
		while k <= reach - 1.5:
			var at := out * (edge - 0.5) + across * k
			if at.distance_to(tower) > 5.0:
				_cone(holder, 0.55, 0.55, 3.2, at + Vector3(0, PALACE_H + 1.6, 0), WHITE, 10)
				_cone(holder, 0.7, 0.0, 1.8, at + Vector3(0, PALACE_H + 4.1, 0), CAPS[t % CAPS.size()], 10)
				SkModels.cyl(holder, 0.68, 0.25, at + Vector3(0, PALACE_H + 3.1, 0), WHITE_SHADE, true, 10)      # (a band under its cap)
				# the corbel it stands on, stepping out from the wall below
				var c1 := SkModels.box(holder, Vector3(1.0, 0.45, 0.5), at + out * 0.6 + Vector3(0, PALACE_H - 0.3, 0), WHITE_SHADE)
				c1.rotation.y = atan2(out.x, out.z)
				var c2 := SkModels.box(holder, Vector3(0.6, 0.4, 0.3), at + out * 0.55 + Vector3(0, PALACE_H - 0.7, 0), WHITE_SHADE)
				c2.rotation.y = atan2(out.x, out.z)
				tops.append(at + Vector3(0, PALACE_H + 4.95, 0))
				t += 1
			k += 4.5
	n.set_meta("flag_tops", tops)
	_bake(n, holder, "LunaPalace").material_override = SkWornLook.material()
	_solid(n, Vector3(hw * 2.0, PALACE_H, hd * 2.0), Vector3(0, PALACE_H / 2.0, 0))
	_solid(n, Vector3(7.0, TOWER_H, 7.0), tower + Vector3(0, TOWER_H / 2.0, 0))
	return n

## A flat disc facing +z (a shield, a wheel, the round top of an arch).
static func _disc(parent: Node3D, r: float, thick: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := _cone(parent, r, r, thick, pos, c, 16)
	mi.rotation.x = PI / 2.0
	return mi

## The map's other plain blocks inside the park's wall that aren't anything (a "house" Microsoft's outlines found where
## the rides stand): their ids, to leave out.
static func stray_blocks(town: SkTownBuilder, els: Array) -> Array:
	var wall := PackedVector2Array()
	for e in els:
		if e.type == "way" and int(e.id) == SkLunaPark.WALL_WAY:
			for g in e.geometry:
				wall.append(town.project(g.lat, g.lon))
	var out := []
	if wall.size() < 4:
		return out
	for b in town.data.buildings:
		if not b.get("ms", false):
			continue
		var ring := SkTownBuilder._pts(b.p)
		var mid := Vector2.ZERO
		for p in ring:
			mid += p
		if Geometry2D.is_point_in_polygon(mid / ring.size(), wall):
			out.append(b.get("id", ""))
	return out

## A square steel member from a to b, w thick.
static func _strut(parent: Node3D, a: Vector3, b: Vector3, w: float, c: Color) -> MeshInstance3D:
	var d := b - a
	var mi := SkModels.box(parent, Vector3(w, w, maxf(d.length(), 0.01)), (a + b) / 2.0, c)
	if d.length() > 0.001:
		var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
		mi.basis = Basis.looking_at(d, up)
	return mi

## Is the camera near enough for this ride to move?
static func _near(n: Node3D) -> bool:
	var cam := n.get_viewport().get_camera_3d()
	return cam != null and cam.global_position.distance_to(n.global_position) < MOVE_NEAR

## A node at a map point whose local +x looks along `along` (map x, z).
static func _placed(parent: Node3D, name: String, at: Vector2, along: Vector2) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.transform = Transform3D(Basis(Vector3.UP, atan2(-along.y, along.x)), Vector3(at.x, 0, at.y))
	parent.add_child(n)
	return n

# ================================================================ the Sky Rider (Ferris wheel, 1971)

const WHEEL_R := 10.0                    # (GUESS: 20 m across)
const HUB_Y := 12.0
const GONDOLAS := 16
const STEEL_BLUE := Color("#3b55b8")
const STEEL_PURPLE := Color("#6b45a8")
const RED := Color("#c8202a")
const YELLOW := Color("#f2c230")

static func _sky_rider(parent: Node3D, at: Vector2, along: Vector2) -> Node3D:
	var n := _placed(parent, "SkyRider", at, along)
	# the two A-frame legs either side of the wheel, a brace across each, a loading deck
	var holder := Node3D.new()
	for z in [-1.9, 1.9]:
		for x in [-6.5, 6.5]:
			_strut(holder, Vector3(x, 0, z * 1.6), Vector3(0, HUB_Y, z), 0.45, STEEL_PURPLE)
		_strut(holder, Vector3(-3.6, 5.5, z * 1.3), Vector3(3.6, 5.5, z * 1.3), 0.3, STEEL_BLUE)
	SkModels.box(holder, Vector3(5.0, 0.6, 4.4), Vector3(0, 0.3, 0), Color("#8d8f94"))
	SkModels.box(holder, Vector3(5.2, 0.15, 4.6), Vector3(0, 0.65, 0), YELLOW)
	_bake(n, holder, "Frame")
	# the wheel: two red rims, spokes in blue and purple with bulbs along them, cross bars the gondolas hang from
	var wheel := SkyWheel.new()
	wheel.name = "Wheel"
	wheel.position = Vector3(0, HUB_Y, 0)
	n.add_child(wheel)
	var w := Node3D.new()
	_disc(w, 0.7, 4.2, Vector3.ZERO, Color("#d7dade"))
	for z in [-1.0, 1.0]:
		for k in GONDOLAS:
			var a0 := TAU * k / GONDOLAS
			var a1 := TAU * (k + 1) / GONDOLAS
			var p0 := Vector3(cos(a0), sin(a0), 0) * WHEEL_R + Vector3(0, 0, z)
			var p1 := Vector3(cos(a1), sin(a1), 0) * WHEEL_R + Vector3(0, 0, z)
			_strut(w, p0, p1, 0.32, RED)
			var q0 := Vector3(cos(a0), sin(a0), 0) * WHEEL_R * 0.62 + Vector3(0, 0, z * 1.25)
			var q1 := Vector3(cos(a1), sin(a1), 0) * WHEEL_R * 0.62 + Vector3(0, 0, z * 1.25)
			_strut(w, q0, q1, 0.2, STEEL_PURPLE)
			_strut(w, Vector3(0, 0, z * 1.8), p0, 0.22, STEEL_BLUE if k % 2 == 0 else STEEL_PURPLE)
			for q in 4:
				SkModels.box(w, Vector3(0.14, 0.14, 0.14), Vector3(0, 0, z * 1.8).lerp(p0, 0.25 + q * 0.2) + Vector3(0, 0, z * 0.15), BULB)
	for k in GONDOLAS:
		var a := TAU * k / GONDOLAS
		var p := Vector3(cos(a), sin(a), 0) * WHEEL_R
		_strut(w, p + Vector3(0, 0, -1.1), p + Vector3(0, 0, 1.1), 0.18, Color("#d7dade"))
	_bake(wheel, w, "Spokes")
	# the gondolas: open benches, yellow frames, red seats, hanging from the cross bars (kept level as it turns)
	var g := Node3D.new()
	SkModels.box(g, Vector3(1.5, 0.12, 1.9), Vector3(0, -1.75, 0), YELLOW)                 # floor
	SkModels.box(g, Vector3(0.5, 0.45, 1.8), Vector3(-0.35, -1.45, 0), RED)                # seat
	SkModels.box(g, Vector3(0.12, 0.6, 1.8), Vector3(-0.62, -1.1, 0), RED)                 # its back
	SkModels.box(g, Vector3(0.1, 0.1, 1.8), Vector3(0.45, -1.05, 0), RED)                  # the bar
	for z in [-0.9, 0.9]:
		_strut(g, Vector3(0, 0, z), Vector3(-0.7, -1.75, z), 0.1, YELLOW)
		_strut(g, Vector3(0, 0, z), Vector3(0.7, -1.75, z), 0.1, YELLOW)
	var gm := SkModels.bake(g)
	g.free()
	wheel.batch = _batch(wheel, gm, GONDOLAS, "Gondolas")
	for k in GONDOLAS:
		var a := TAU * k / GONDOLAS
		wheel.spots.append(Vector3(cos(a), sin(a), 0) * WHEEL_R)
	wheel.level()
	# people sat in most of the gondolas, one or two to each
	var seats := []
	for k in GONDOLAS:
		for z in [-0.42, 0.42]:
			if _taken(0.5):
				seats.append([wheel.batch.multimesh, k, _seat(Vector3(-0.42, -1.2, z), -PI / 2.0)])
	wheel.riders = _riders(wheel, seats, 1.0, 0.0, 0.1)
	for x in [-5.5, 5.5]:
		for z in [-3.0, 3.0]:
			_solid(n, Vector3(0.8, 3.0, 0.8), Vector3(x, 1.5, z))
	_solid(n, Vector3(5.0, 0.7, 4.4), Vector3(0, 0.35, 0))
	return n

## Turns the wheel (once round every 40 s), its gondolas staying level.
class SkyWheel extends Node3D:
	var gondolas: Array = []               # (separate ones, each its own mesh: Moon Balloons' are all different colours)
	var batch: MultiMeshInstance3D = null  # (or all the same, drawn in one go: the Sky Rider's)
	var spots := PackedVector3Array()      # where each of the batch's hangs
	var riders: Riders = null

	func _process(dt: float) -> void:
		if not SkLunaRides._near(self):
			return
		rotation.z = fposmod(rotation.z + dt * TAU / 40.0, TAU)
		level()

	## Keep the gondolas level as the wheel turns.
	func level() -> void:
		for g in gondolas:
			(g as Node3D).rotation.z = -rotation.z
		if batch:
			var upright := Basis(Vector3.BACK, -rotation.z)
			for i in spots.size():
				batch.multimesh.set_instance_transform(i, Transform3D(upright, spots[i]))
		if riders:
			riders.follow()

# ================================================================ the Supernova (2019: 32 m, "a 12.5 metre circle")

const NOVA_H := 32.0
const NOVA_ARMS := 12
const NOVA_ARM := 4.5
const NOVA_CHAIN := 4.0

## A square lattice tower `h` tall, `s` from its middle to each corner post, a brace across each face every `step` m.
static func _lattice(holder: Node3D, s: float, h: float, step: float, post: Color, brace: Color, w: float) -> void:
	var corners := [Vector3(-s, 0, -s), Vector3(s, 0, -s), Vector3(s, 0, s), Vector3(-s, 0, s)]
	for c in corners:
		_strut(holder, c, c + Vector3(0, h, 0), w, post)
	var y := 0.0
	var k := 0
	while y < h - step:
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			if k % 2 == 0:
				_strut(holder, a + Vector3(0, y, 0), b + Vector3(0, y + step, 0), w * 0.4, brace)
			else:
				_strut(holder, b + Vector3(0, y, 0), a + Vector3(0, y + step, 0), w * 0.4, brace)
			_strut(holder, a + Vector3(0, y + step, 0), b + Vector3(0, y + step, 0), w * 0.4, post)
		y += step
		k += 1

static func _supernova(parent: Node3D, at: Vector2) -> Node3D:
	var n := _placed(parent, "Supernova", at, Vector2(1, 0))
	var holder := Node3D.new()
	_lattice(holder, 0.8, NOVA_H, 2.0, STEEL_BLUE, Color("#8fb3e8"), 0.25)
	SkModels.box(holder, Vector3(2.4, 1.0, 2.4), Vector3(0, NOVA_H + 0.5, 0), Color("#1e2f6e"))
	SkModels.box(holder, Vector3(0.5, 0.5, 0.5), Vector3(0, NOVA_H + 1.25, 0), RED)
	SkModels.cyl(holder, 3.0, 0.5, Vector3(0, 0.25, 0), Color("#8d8f94"), true, 16)           # its loading deck
	_bake(n, holder, "Tower")
	# the carriage: a ring round the tower with its star of arms, the chairs hanging from them
	var nova := Nova.new()
	nova.name = "Carriage"
	nova.position = Vector3(0, Nova.LOW, 0)
	n.add_child(nova)
	var c := Node3D.new()
	SkModels.cyl(c, 1.5, 0.8, Vector3.ZERO, Color("#1e2f6e"), true, 12)
	for i in NOVA_ARMS:
		var a := TAU * i / NOVA_ARMS
		var tip := Vector3(cos(a) * NOVA_ARM, 0.35 * NOVA_ARM, sin(a) * NOVA_ARM)
		_strut(c, Vector3(cos(a), 0, sin(a)) * 1.2, tip, 0.18, STEEL_BLUE)
		SkModels.box(c, Vector3(0.18, 0.18, 0.18), tip + Vector3(0, 0.15, 0), BULB)
	_bake(nova, c, "Arms")
	var chair := Node3D.new()
	_strut(chair, Vector3(0, 0, -0.45), Vector3(0, -NOVA_CHAIN, -0.45), 0.05, Color("#2a2c30"))
	_strut(chair, Vector3(0, 0, 0.45), Vector3(0, -NOVA_CHAIN, 0.45), 0.05, Color("#2a2c30"))
	SkModels.box(chair, Vector3(0.55, 0.12, 1.2), Vector3(0, -NOVA_CHAIN - 0.05, 0), Color("#2b5fbf"))
	SkModels.box(chair, Vector3(0.12, 0.55, 1.2), Vector3(-0.25, -NOVA_CHAIN + 0.25, 0), Color("#2b5fbf"))
	var cm := SkModels.bake(chair)
	chair.free()
	nova.batch = _batch(nova, cm, NOVA_ARMS, "Chairs")
	for i in NOVA_ARMS:
		var a := TAU * i / NOVA_ARMS
		# where each hangs from, its local x pointing out from the tower
		nova.chairs.append(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * NOVA_ARM, 0.35 * NOVA_ARM, sin(a) * NOVA_ARM)))
	var seats := []
	for i in NOVA_ARMS:
		if _taken(0.75):
			seats.append([nova.batch.multimesh, i, _seat(Vector3(-0.05, -NOVA_CHAIN + 0.02, 0), -PI / 2.0)])
	nova.riders = _riders(nova, seats, 0.3, 0.0, 0.6)
	nova.swing_chairs(0.0)
	_solid(n, Vector3(2.0, NOVA_H, 2.0), Vector3(0, NOVA_H / 2.0, 0))
	_solid(n, Vector3(6.0, 0.5, 6.0), Vector3(0, 0.25, 0))
	return n

## The Supernova's carriage: rests at the bottom for loading, rides up the tower spinning faster, spins at the top
## (the chairs swinging out as far as the speed throws them), and comes back down.
class Nova extends Node3D:
	const LOW := 1.5 + 4.0 - 1.6           # (the chairs just off the deck)
	const HIGH := 26.0
	const SPIN := 1.55                     # rad/s at the top: about 35 km/h at the chairs (Luna Park's figure)
	const SWING_R := 6.5                   # the chairs' circle (half of Luna Park's 12.5 m, and a bit)
	const CYCLE := [[8.0, "rest"], [12.0, "up"], [14.0, "top"], [12.0, "down"]]
	var chairs: Array = []                 # where each chair hangs from (its local x out from the tower)
	var batch: MultiMeshInstance3D
	var riders: Riders = null
	var _t := 0.0
	var _spin := 0.0

	func _process(dt: float) -> void:
		if not SkLunaRides._near(self):
			return
		_t += dt
		var total := 0.0
		for c in CYCLE:
			total += float(c[0])
		var t := fposmod(_t, total)
		var h := LOW
		var w := 0.0
		for c in CYCLE:
			var len: float = c[0]
			if t < len:
				var u := t / len
				match c[1]:
					"up":
						h = lerpf(LOW, HIGH, smoothstep(0.0, 1.0, u))
						w = SPIN * u
					"top":
						h = HIGH
						w = SPIN
					"down":
						h = lerpf(HIGH, LOW, smoothstep(0.0, 1.0, u))
						w = SPIN * (1.0 - u)
				break
			t -= len
		position.y = h
		_spin = fposmod(_spin + w * dt, TAU)
		rotation.y = _spin
		# the chairs swing out: tan(angle) = w^2 r / g
		swing_chairs(atan(w * w * SWING_R / 9.8))

	func swing_chairs(lean: float) -> void:
		var out := Basis(Vector3.BACK, lean)
		for i in chairs.size():
			var at: Transform3D = chairs[i]
			batch.multimesh.set_instance_transform(i, Transform3D(at.basis * out, at.origin))
		if riders:
			riders.follow()

# ================================================================ Pharaoh's Curse (2001: "flung 19 meters into the air")

const PIVOT_Y := 10.0
const ARM := 8.5

static func _pharaoh(parent: Node3D, at: Vector2, along: Vector2) -> Node3D:
	var n := _placed(parent, "PharaohsCurse", at, along)
	var holder := Node3D.new()
	# the A-frame support, splayed across the swing so the arms clear it, and its axle
	for z in [-1.0, 1.0]:
		for x in [-3.5, 3.5]:
			_strut(holder, Vector3(x, 0, z * 4.5), Vector3(0, PIVOT_Y, z * 1.6), 0.6, Color("#1f3f8f"))
	_strut(holder, Vector3(0, PIVOT_Y, -1.9), Vector3(0, PIVOT_Y, 1.9), 0.7, Color("#c9a24a"))
	SkModels.box(holder, Vector3(6.0, 0.5, 4.0), Vector3(0, 0.25, 0), Color("#8d8f94"))      # the loading deck
	_bake(n, holder, "Support")
	# the two arms, each a car at one end and a counterweight at the other
	var g := Node3D.new()
	_strut(g, Vector3(0, 1.2, 0), Vector3(0, -ARM, 0), 0.7, Color("#2b5fbf"))
	SkModels.box(g, Vector3(1.6, 1.6, 0.9), Vector3(0, 1.6, 0), Color("#2a2c30"))           # counterweight
	SkModels.box(g, Vector3(3.2, 1.4, 2.0), Vector3(0, -ARM - 0.3, 0), WHITE)                # the car
	SkModels.box(g, Vector3(3.0, 0.6, 1.6), Vector3(0, -ARM + 0.6, 0), RED)                  # its seats
	for x in [-1.5, -0.5, 0.5, 1.5]:
		_strut(g, Vector3(x, -ARM + 0.4, -1.0), Vector3(x, -ARM + 1.6, -1.0), 0.08, Color("#9aa0a6"))
		_strut(g, Vector3(x, -ARM + 0.4, 1.0), Vector3(x, -ARM + 1.6, 1.0), 0.08, Color("#9aa0a6"))
	SkModels.box(g, Vector3(3.4, 0.25, 2.2), Vector3(0, -ARM - 1.0, 0), RED)
	var gm := SkModels.bake(g)
	g.free()
	var swing := Pendulum.new()
	swing.name = "Arms"
	swing.position = Vector3(0, PIVOT_Y, 0)
	n.add_child(swing)
	for z in [-0.75, 0.75]:
		var arm := Node3D.new()
		arm.position.z = z
		swing.add_child(arm)
		var mi := MeshInstance3D.new()
		mi.mesh = gm
		mi.material_override = SkModels.baked_material()
		arm.add_child(mi)
		swing.arms.append(arm)
	# a full car on each (it's the big thrill: arms up)
	var seats := []
	for arm in swing.arms:
		var out := signf((arm as Node3D).position.z)
		for x in [-1.2, -0.4, 0.4, 1.2]:
			if _taken(0.85):
				seats.append([arm, 0, _seat(Vector3(x, -ARM + 0.92, 0.1 * out), PI if out > 0.0 else 0.0)])
	swing.riders = _riders(swing, seats, 1.0, 0.6, 0.7)
	for x in [-3.0, 3.0]:
		for z in [-3.8, 3.8]:
			_solid(n, Vector3(1.0, 3.0, 1.0), Vector3(x, 1.5, z))
	return n

## The two arms swinging the opposite way to each other: pumped higher and higher until they go right over the top a
## few times, then braked back to rest (a pendulum, pushed).
class Pendulum extends Node3D:
	const PUMP := 0.9
	const MAX_W := 2.6
	const CYCLE := 60.0
	var arms: Array = []
	var riders: Riders = null
	var _a := 0.0
	var _w := 0.0
	var _t := 0.0

	func _process(dt: float) -> void:
		if not SkLunaRides._near(self):
			return
		_t = fposmod(_t + dt, CYCLE)
		var push := 0.0
		if _t > 8.0 and _t < 38.0:
			push = PUMP * (signf(_w) if absf(_w) > 0.01 else 1.0)       # (pump it up)
		elif _t >= 38.0:
			push = -PUMP * 1.4 * signf(_w)                               # (brake)
			if absf(_w) < 0.05 and absf(_a) < 0.05:
				push = 0.0
				_w = 0.0
		var steps := 4
		for i in steps:
			var h := dt / steps
			_w += (-(9.8 / SkLunaRides.ARM) * sin(_a) + push - 0.05 * _w) * h
			_w = clampf(_w, -MAX_W, MAX_W)
			_a += _w * h
		_a = wrapf(_a, -PI, PI)
		(arms[0] as Node3D).rotation.z = _a
		(arms[1] as Node3D).rotation.z = -_a
		if riders:
			riders.follow()

# ================================================================ the Coney Drop (2010: "Spring 13 metres into the air")

const CONEY_H := 18.0

static func _coney_drop(parent: Node3D, at: Vector2) -> Node3D:
	var n := _placed(parent, "ConeyDrop", at, Vector2(1, 0))
	var holder := Node3D.new()
	_lattice(holder, 0.7, CONEY_H, 1.5, WHITE, WHITE_SHADE, 0.22)
	_cone(holder, 1.2, 0.2, 1.4, Vector3(0, CONEY_H + 0.7, 0), RED, 12)
	SkModels.cyl(holder, 3.6, 0.4, Vector3(0, 0.2, 0), Color("#8d8f94"), true, 16)
	_bake(n, holder, "Tower")
	# the seats round the tower, under the red and white striped canopy
	var drop := ConeyCar.new()
	drop.name = "Seats"
	drop.position.y = ConeyCar.LOW
	n.add_child(drop)
	var c := Node3D.new()
	SkModels.cyl(c, 1.4, 0.6, Vector3(0, 0.3, 0), Color("#d7dade"), true, 12)
	for i in 12:
		var a := TAU * i / 12.0
		var out := Vector3(cos(a), 0, sin(a))
		var seat := SkModels.box(c, Vector3(0.6, 1.1, 0.7), out * 2.0, RED)
		seat.rotation.y = -a
		var back := SkModels.box(c, Vector3(0.15, 1.3, 0.7), out * 1.65 + Vector3(0, 0.2, 0), Color("#8a1a1f"))
		back.rotation.y = -a
		SkModels.box(c, Vector3(0.12, 0.12, 0.12), out * 2.4 + Vector3(0, 0.75, 0), Color("#d9ab3a"))
	for i in 16:
		var a := TAU * (i + 0.5) / 16.0
		var out := Vector3(cos(a), 0, sin(a))
		var panel := SkModels.box(c, Vector3(0.12, 1.5, 1.45), out * 2.6 + Vector3(0, 1.75, 0), RED if i % 2 == 0 else WHITE)
		panel.basis = Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 0.75)
	_bake(drop, c, "Ring")
	# people in most of the seats, facing out, legs dangling
	var seats := []
	for i in 12:
		var a := TAU * i / 12.0
		var out := Vector3(cos(a), 0, sin(a))
		if _taken(0.7):
			seats.append([null, 0, _seat(out * 2.1 + Vector3(0, 0.56, 0), atan2(-out.x, -out.z))])
	_riders(drop, seats, 0.15, 0.0, 0.55)
	_solid(n, Vector3(1.6, CONEY_H, 1.6), Vector3(0, CONEY_H / 2.0, 0))
	return n

## The Coney Drop's seats: rest, spring up to 13 m, bounce and drop in stages, rest again.
class ConeyCar extends Node3D:
	const LOW := 1.2
	## [seconds to get there, height]
	const KEYS := [[6.0, 1.2], [1.4, 13.0], [1.5, 13.0], [0.6, 8.0], [1.0, 11.5], [0.8, 11.5], [0.6, 5.5], [1.0, 9.0], [0.8, 9.0], [0.9, 1.2]]
	var _t := 0.0

	func _process(dt: float) -> void:
		if not SkLunaRides._near(self):
			return
		var total := 0.0
		for k in KEYS:
			total += float(k[0])
		_t = fposmod(_t + dt, total)
		var t := _t
		var from := LOW
		for k in KEYS:
			var len: float = k[0]
			var to: float = k[1]
			if t < len:
				position.y = lerpf(from, to, smoothstep(0.0, 1.0, t / len))
				return
			t -= len
			from = to

# ================================================================ stage 3: the spinning rides

## Is it running? A ride's cycle: [seconds, what it's doing]; returns [the step's name, how far through it (0..1)].
static func _step(cycle: Array, t: float) -> Array:
	var total := 0.0
	for c in cycle:
		total += float(c[0])
	t = fposmod(t, total)
	for c in cycle:
		if t < float(c[0]):
			return [c[1], t / float(c[0])]
		t -= float(c[0])
	return [cycle[0][1], 0.0]

# ---------------------------------------------------------------- the Spider (an "Octopus")

const SPIDER_LEGS := 8
const SPIDER_LEG := 7.5

static func _spider(parent: Node3D, at: Vector2) -> Node3D:
	var n := _placed(parent, "Spider", at, Vector2(1, 0))
	var holder := Node3D.new()
	SkModels.cyl(holder, 2.0, 0.5, Vector3(0, 0.25, 0), Color("#3a3a40"), true, 16)
	SkModels.cyl(holder, 0.9, 3.6, Vector3(0, 2.3, 0), Color("#1d1b22"), true, 12)
	_bake(n, holder, "Base")
	var spin := Octopus.new()
	spin.name = "Body"
	spin.position.y = 4.2
	n.add_child(spin)
	var b := Node3D.new()
	var belly := SkModels.ball(b, 2.0, Vector3(0, 0.6, 0), Color("#1d1b22"))
	belly.scale = Vector3(1.0, 0.7, 1.0)
	_skull(b, Vector3(0, 2.4, 0), 1.4)                                                    # its face
	SkModels.cyl(b, 0.7, 1.4, Vector3(0, 3.8, 0), Color("#141416"), true, 12)              # its top hat
	SkModels.cyl(b, 1.1, 0.12, Vector3(0, 3.1, 0), Color("#141416"), true, 12)
	SkModels.cyl(b, 0.72, 0.25, Vector3(0, 3.3, 0), Color("#9a3a3a"), true, 12)
	_bake(spin, b, "Body")
	# the legs: each lifts and drops (about where it joins the body) as the body turns; a cup at its end spins
	var leg := Node3D.new()
	_strut(leg, Vector3(0.6, 0, 0), Vector3(SPIDER_LEG * 0.55, 1.4, 0), 0.35, Color("#26252b"))
	_strut(leg, Vector3(SPIDER_LEG * 0.55, 1.4, 0), Vector3(SPIDER_LEG, -0.6, 0), 0.3, Color("#26252b"))
	var lm := SkModels.bake(leg)
	leg.free()
	var cup := Node3D.new()
	SkModels.cyl(cup, 1.0, 1.0, Vector3(0, 0.0, 0), Color("#141416"), true, 12)
	SkModels.cyl(cup, 0.8, 0.6, Vector3(0, 0.45, 0), Color("#c0262c"), true, 12)
	SkModels.box(cup, Vector3(1.6, 0.8, 0.12), Vector3(0, 0.5, -0.75), Color("#141416"))
	var cm := SkModels.bake(cup)
	cup.free()
	spin.leg_batch = _batch(spin, lm, SPIDER_LEGS, "Legs")
	spin.cup_batch = _batch(spin, cm, SPIDER_LEGS, "Cups")
	for i in SPIDER_LEGS:
		spin.legs.append([TAU * i / SPIDER_LEGS, float(i) * TAU / 4.0, 0.0])
	# two to a cup in most of them, facing out of the cup's open side
	var seats := []
	for i in SPIDER_LEGS:
		for x in [-0.35, 0.35]:
			if _taken(0.7):
				seats.append([spin.cup_batch.multimesh, i, _seat(Vector3(x, 0.76, -0.25), PI)])
	spin.riders = _riders(spin, seats, 1.0, 0.5, 0.5)
	spin.pose()
	_solid(n, Vector3(4.0, 0.5, 4.0), Vector3(0, 0.25, 0))
	_solid(n, Vector3(1.8, 4.0, 1.8), Vector3(0, 2.0, 0))
	return n

## Turns the Spider, its legs lifting and dropping in turn and its cups spinning.
class Octopus extends Node3D:
	const CYCLE := [[8.0, "rest"], [5.0, "start"], [30.0, "run"], [5.0, "stop"]]
	var legs: Array = []                   # [which way it points round the body, its phase, its cup's spin]
	var leg_batch: MultiMeshInstance3D
	var cup_batch: MultiMeshInstance3D
	var riders: Riders = null
	var _t := 0.0
	var _go := 0.0

	## Each leg lifted (about where it joins the body) and its cup turned on its end.
	func pose() -> void:
		for i in legs.size():
			var l: Array = legs[i]
			var lift := (sin(_t * 1.6 + float(l[1])) * 0.32 + 0.12) * _go
			var leg := Transform3D(Basis(Vector3.UP, float(l[0])) * Basis(Vector3.BACK, lift), Vector3.ZERO)
			leg_batch.multimesh.set_instance_transform(i, leg)
			cup_batch.multimesh.set_instance_transform(i, leg * Transform3D(Basis(Vector3.UP, float(l[2])), Vector3(SkLunaRides.SPIDER_LEG, -1.6, 0)))
		if riders:
			riders.follow()

	func _process(dt: float) -> void:
		if not SkLunaRides._near(self):
			return
		_t += dt
		var st := SkLunaRides._step(CYCLE, _t)
		match st[0]:
			"rest":
				_go = 0.0
			"start":
				_go = float(st[1])
			"run":
				_go = 1.0
			"stop":
				_go = 1.0 - float(st[1])
		rotation.y = fposmod(rotation.y + dt * 1.1 * _go, TAU)
		for l in legs:
			l[2] = fposmod(float(l[2]) + dt * 2.0 * _go, TAU)
		pose()

# ---------------------------------------------------------------- the Power Surge ("one gravity and two motor driven rotations")

const SURGE_ARMS := 5
const SURGE_ARM := 5.2

static func _power_surge(parent: Node3D, at: Vector2) -> Node3D:
	var n := _placed(parent, "PowerSurge", at, Vector2(1, 0))
	var holder := Node3D.new()
	SkModels.cyl(holder, 4.5, 0.5, Vector3(0, 0.25, 0), Color("#4a4d55"), true, 20)
	# the yellow and orange tower, with POWER SURGE down it
	SkModels.box(holder, Vector3(1.6, 7.0, 1.6), Vector3(0, 3.5, 0), Color("#f2b400"))
	SkModels.box(holder, Vector3(1.7, 7.0, 0.5), Vector3(0, 3.5, 0.65), Color("#ef7d22"))
	_bake(n, holder, "Tower")
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Black", "Impact", "sans-serif"])
	for s in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "P\nO\nW\nE\nR"
		l.font = font
		l.font_size = 64
		l.pixel_size = 0.9 / 64.0
		l.line_spacing = -20.0
		l.modulate = Color("#c8202a")
		l.outline_modulate = Color("#ffe066")
		l.outline_size = 8
		l.position = Vector3(0, 4.2, 0.95 * s)
		l.rotation.y = 0.0 if s > 0.0 else PI
		n.add_child(l)
	var surge := Surge.new()
	surge.name = "Head"
	surge.position.y = 7.2
	n.add_child(surge)
	var star := Node3D.new()
	star.name = "Star"
	surge.add_child(star)
	surge.star = star
	var st := Node3D.new()
	SkModels.cyl(st, 1.2, 1.0, Vector3.ZERO, Color("#c8202a"), true, 10)
	for i in SURGE_ARMS:
		var a := TAU * i / SURGE_ARMS
		_strut(st, Vector3.ZERO, Vector3(cos(a), 0, sin(a)) * SURGE_ARM, 0.55, Color("#c8202a") if i % 2 == 0 else Color("#ef7d22"))
		for q in 5:
			SkModels.box(st, Vector3(0.15, 0.15, 0.15), Vector3(cos(a), 0, sin(a)) * (1.2 + q * 0.9) + Vector3(0, 0.32, 0), BULB)
	_bake(star, st, "Star")
	var seat := Node3D.new()
	SkModels.box(seat, Vector3(1.8, 0.2, 1.0), Vector3(0, -0.6, 0), Color("#2a2c30"))
	for x in [-0.5, 0.5]:
		SkModels.box(seat, Vector3(0.6, 0.9, 0.7), Vector3(x, -0.2, 0), Color("#4fbf3a"))
		SkModels.box(seat, Vector3(0.5, 0.3, 0.6), Vector3(x, 0.35, -0.1), Color("#f2c230"))
	var sm := SkModels.bake(seat)
	seat.free()
	for i in SURGE_ARMS:
		var a := TAU * i / SURGE_ARMS
		var holder2 := Node3D.new()
		holder2.position = Vector3(cos(a), 0, sin(a)) * SURGE_ARM
		holder2.rotation.y = -a
		star.add_child(holder2)
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = SkModels.baked_material()
		holder2.add_child(mi)
		surge.seats.append(holder2)
	# two to a pair of seats on most arms (they roll over with them)
	var seats := []
	for s in surge.seats:
		for x in [-0.5, 0.5]:
			if _taken(0.75):
				seats.append([s, 0, _seat(Vector3(x, 0.27, -0.1), PI)])
	surge.riders = _riders(star, seats, 1.0, 0.4, 0.6)
	_solid(n, Vector3(1.8, 7.0, 1.8), Vector3(0, 3.5, 0))
	return n

## The Power Surge: the star spins, its head tips over and back, and each pair of seats rolls round its arm.
class Surge extends Node3D:
	const CYCLE := [[8.0, "rest"], [6.0, "start"], [24.0, "run"], [6.0, "stop"]]
	var star: Node3D
	var seats: Array = []
	var riders: Riders = null
	var _t := 0.0
	var _go := 0.0

	func _process(dt: float) -> void:
		if not SkLunaRides._near(self):
			return
		_t += dt
		var st := SkLunaRides._step(CYCLE, _t)
		match st[0]:
			"rest":
				_go = 0.0
			"start":
				_go = float(st[1])
			"run":
				_go = 1.0
			"stop":
				_go = 1.0 - float(st[1])
		rotation.x = sin(_t * 0.5) * 1.1 * _go
		star.rotation.y = fposmod(star.rotation.y + dt * 1.6 * _go, TAU)
		for s in seats:
			(s as Node3D).rotation.x = fposmod((s as Node3D).rotation.x + dt * 1.3 * _go, TAU) if _go > 0.01 else lerp_angle((s as Node3D).rotation.x, 0.0, dt * 2.0)
		if riders:
			riders.follow()

# ---------------------------------------------------------------- the Arabian Merry (flying elephants)

const MERRY_N := 8
const MERRY_ARM := 4.6

static func _arabian_merry(parent: Node3D, at: Vector2) -> Node3D:
	var n := _placed(parent, "ArabianMerry", at, Vector2(1, 0))
	var holder := Node3D.new()
	SkModels.cyl(holder, 6.2, 0.4, Vector3(0, 0.2, 0), Color("#2fb3a6"), true, 24)
	SkModels.cyl(holder, 1.3, 4.6, Vector3(0, 2.7, 0), Color("#ef8a3a"), true, 8)
	for k in 8:
		var a := TAU * k / 8.0
		SkModels.box(holder, Vector3(0.35, 4.0, 0.12), Vector3(cos(a) * 1.32, 2.6, sin(a) * 1.32), Color("#e2507a") if k % 2 == 0 else Color("#f2c230"))
	SkModels.cyl(holder, 1.6, 0.4, Vector3(0, 5.2, 0), Color("#c8202a"), true, 8)
	# the onion dome, striped
	var bulge := [1.2, 1.7, 1.8, 1.6, 1.2, 0.7, 0.25]
	for i in bulge.size() - 1:
		_cone(holder, bulge[i], bulge[i + 1], 0.45, Vector3(0, 5.6 + i * 0.45, 0), [Color("#ef7d22"), Color("#e2507a"), Color("#3d7fd0")][i % 3], 12)
	SkModels.cyl(holder, 0.05, 1.0, Vector3(0, 8.6, 0), Color("#d9ab3a"), true, 6)
	_bake(n, holder, "Tower")
	var merry := Merry.new()
	merry.name = "Elephants"
	merry.position.y = 3.6
	n.add_child(merry)
	var e := Node3D.new()
	SkModels.box(e, Vector3(1.6, 1.1, 1.1), Vector3(0, 0, 0), Color("#f2f0ea"))                   # body
	SkModels.box(e, Vector3(0.9, 0.9, 0.9), Vector3(0.95, 0.35, 0), Color("#f2f0ea"))            # head
	for s in [-1.0, 1.0]:
		var ear := SkModels.box(e, Vector3(0.6, 0.9, 0.1), Vector3(0.75, 0.4, s * 0.62), Color("#f4c6cf"))
		ear.rotation.x = s * 0.4
		SkModels.box(e, Vector3(0.3, 0.08, 0.08), Vector3(1.45, 0.0, s * 0.2), Color("#fffbe8"))
	var trunk := SkModels.box(e, Vector3(0.25, 0.9, 0.25), Vector3(1.5, -0.2, 0), Color("#f2f0ea"))
	trunk.rotation.z = 0.5
	SkModels.box(e, Vector3(1.2, 0.3, 1.2), Vector3(-0.1, 0.65, 0), Color("#3d7fd0"))             # its saddle-cloth
	SkModels.box(e, Vector3(0.6, 0.3, 0.6), Vector3(0.95, 0.9, 0), Color("#c8202a"))             # its hat
	var em := SkModels.bake(e)
	e.free()
	var arm := Node3D.new()
	_strut(arm, Vector3(0, 0, 0), Vector3(MERRY_ARM, 0, 0), 0.22, Color("#d9ab3a"))
	var am := SkModels.bake(arm)
	arm.free()
	merry.arm_batch = _batch(merry, am, MERRY_N, "Arms")
	merry.elephant_batch = _batch(merry, em, MERRY_N, "Elephants")
	for i in MERRY_N:
		merry.arms.append([TAU * i / MERRY_N, float(i)])
	# kids astride most of the elephants
	var seats := []
	for i in MERRY_N:
		if _taken(0.7):
			seats.append([merry.elephant_batch.multimesh, i, _seat(Vector3(-0.15, 0.82, 0), -PI / 2.0, 0.62)])
	merry.riders = _riders(merry, seats, 0.0, 0.7, 0.35)
	merry.pose()
	_solid(n, Vector3(2.8, 5.0, 2.8), Vector3(0, 2.5, 0))
	return n

## The elephants fly round, each rising and falling on its own.
class Merry extends Node3D:
	const CYCLE := [[8.0, "rest"], [30.0, "run"]]
	var arms: Array = []                   # [which way it points round the tower, its phase]
	var arm_batch: MultiMeshInstance3D
	var elephant_batch: MultiMeshInstance3D
	var riders: Riders = null
	var _t := 0.0
	var _go := 0.0

	func _process(dt: float) -> void:
		if not SkLunaRides._near(self):
			return
		_t += dt
		var st := SkLunaRides._step(CYCLE, _t)
		_go = move_toward(_go, 1.0 if st[0] == "run" else 0.0, dt * 0.4)
		rotation.y = fposmod(rotation.y + dt * 0.8 * _go, TAU)
		pose()

	## Each arm lifted, its elephant kept level at its end, facing round the way it turns.
	func pose() -> void:
		for i in arms.size():
			var a: Array = arms[i]
			var lift := (sin(_t * 0.9 + float(a[1]) * 1.3) * 0.28 + 0.05) * _go - 0.3 * (1.0 - _go)
			var arm := Transform3D(Basis(Vector3.UP, float(a[0])) * Basis(Vector3.BACK, lift), Vector3.ZERO)
			arm_batch.multimesh.set_instance_transform(i, arm)
			var tip := arm * Vector3(SkLunaRides.MERRY_ARM, 0.2, 0)
			elephant_batch.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(a[0]) - PI / 2.0), tip))
		if riders:
			riders.follow()

## No shadows from the small moving pieces under `root` (each shadow is another draw; on a small part you'd hardly see
## it): any mesh under a ride's moving part that's under 4 m across.
static func no_small_shadows(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var moving := false
		var up := mi.get_parent()
		while up and up != root:
			if up is Spinner or up is SkyWheel or up is Nova or up is Pendulum or up is Octopus \
					or up is Surge or up is Merry or up is ConeyCar:
				moving = true
				break
			up = up.get_parent()
		if moving and mi.get_aabb().get_longest_axis_size() < 4.0:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
