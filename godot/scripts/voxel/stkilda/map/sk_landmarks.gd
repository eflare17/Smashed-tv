# (Copied from stkilda-godot scripts/town/landmarks.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkLandmarks
extends RefCounted
## Shepparton's landmarks, built from what's published about them (each one says where its details come from).

# ================================================================ SAM

## Shepparton Art Museum (530 Wyndham St, the south-east corner of Victoria Park Lake), from the architects' and
## builder's descriptions: a 33 m x 33 m cube five storeys tall, wrapped in four L-shaped metal plates, each a
## different height so they seem to float; the foot of each L sticks out as a verandah over the ground floor's
## glass. The plates: low-sheen zinc to the south, matt charcoal over the Wyndham St entry (east), metallic
## mid-grey to the park (north), rusty corten steel to the lake (west). The plates' exact heights are a GUESS.
static func sam(parent: Node3D, at: Vector2) -> Node3D:
	var n := Node3D.new()
	n.name = "SAM"
	n.position = Vector3(at.x, 0, at.y)
	parent.add_child(n)
	var holder := Node3D.new()
	const S := 33.0
	const H := 26.0
	const GROUND := 4.6              # the ground floor's glass, under the verandahs
	# the body behind the plates, the ground floor's dark glass, the roof
	SkModels.box(holder, Vector3(S - 1.0, H, S - 1.0), Vector3(0, H / 2.0, 0), Color("#3a3d42"))
	SkModels.box(holder, Vector3(S - 0.6, GROUND - 0.4, S - 0.6), Vector3(0, (GROUND - 0.4) / 2.0, 0), Color("#25333f"))
	SkModels.box(holder, Vector3(S - 1.2, 0.4, S - 1.2), Vector3(0, H + 0.2, 0), Color("#8d9196"))
	# the four plates: which side (its outward direction), colour, how tall, how far its verandah sticks out
	var plates := [
		[Vector3(0, 0, 1), Color("#a7adb1"), H - 3.0, 5.5],        # south: zinc
		[Vector3(1, 0, 0), Color("#4a4c50"), H + 1.5, 7.0],        # east, over the Wyndham St entry: charcoal
		[Vector3(0, 0, -1), Color("#8e9499"), H - 1.0, 5.0],       # north, to the park: mid-grey
		[Vector3(-1, 0, 0), Color("#9a4e2c"), H + 0.5, 6.0],       # west, to the lake: corten
	]
	for i in plates.size():
		var out: Vector3 = plates[i][0]
		var c: Color = plates[i][1]
		var top: float = plates[i][2]
		var deep: float = plates[i][3]
		var across := Vector3(out.z, 0, out.x).abs()
		var w := S + 0.6 - (1.2 if i % 2 == 0 else 0.0)           # (so neighbouring plates don't overlap)
		var face := out * (S / 2.0 + 0.25)
		# the upright of the L
		SkModels.box(holder, across * w + Vector3(0, top - GROUND, 0) + out.abs() * 0.5, face + Vector3(0, (top + GROUND) / 2.0, 0), c)
		# its foot: the verandah
		SkModels.box(holder, across * w + Vector3(0, 0.5, 0) + out.abs() * deep, face + out * (deep / 2.0) + Vector3(0, GROUND - 0.25, 0), c)
		# lines across the plate where its sheets meet
		for k in range(1, int((top - GROUND) / 3.2)):
			SkModels.box(holder, across * (w - 0.2) + Vector3(0, 0.06, 0) + out.abs() * 0.04, face + out * 0.27 + Vector3(0, GROUND + k * 3.2, 0), c.darkened(0.18))
	var mi := MeshInstance3D.new()
	mi.mesh = SkModels.bake(holder)
	mi.material_override = SkModels.baked_material()
	holder.free()
	n.add_child(mi)
	var b := StaticBody3D.new()
	b.collision_layer = SkData.LAYER_WORLD
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(S, H, S)
	cs.shape = bs
	cs.position.y = H / 2.0
	b.add_child(cs)
	n.add_child(b)
	return n

# ================================================================ the Moooving Art cows

## Shepparton's Moooving Art: life-size fibreglass cows, each painted by a different artist, around town. The main
## herd is in Monash Park (the corner of the Midland Hwy and Fryers St; at least eight there, the guides say), and
## the map has more at the Botanic Gardens. Each cow's paint here is a GUESS: bright colours and patterns in the
## spirit of the real ones, not copies of them.
const COW_PAINT := [
	[Color("#f2c230"), Color("#2b6cb0"), Color("#e2483d")], [Color("#ffffff"), Color("#e86aa6"), Color("#3fb5a0")],
	[Color("#3b82c4"), Color("#f5d547"), Color("#ffffff")], [Color("#e9573f"), Color("#2e2e2e"), Color("#f4e9d1")],
	[Color("#7bc96f"), Color("#f39c35"), Color("#8e44ad")], [Color("#f4e9d1"), Color("#1f6f8b"), Color("#e2483d")],
	[Color("#8e44ad"), Color("#f5d547"), Color("#2ecc71")], [Color("#ff8fb1"), Color("#ffffff"), Color("#2b6cb0")],
	[Color("#1f6f8b"), Color("#f39c35"), Color("#ffffff")], [Color("#2e2e2e"), Color("#f2c230"), Color("#e86aa6")],
]

static func herd(parent: Node3D, at: Vector2, count: int, spread: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in count:
		var c := cow(COW_PAINT[(seed_v + i) % COW_PAINT.size()], rng.randi())
		var a := TAU * i / count + rng.randf_range(-0.3, 0.3)
		var r := spread * (0.4 + 0.6 * rng.randf())
		c.position = Vector3(at.x + cos(a) * r, 0, at.y + sin(a) * r)
		c.rotation.y = rng.randf_range(0, TAU)
		parent.add_child(c)

## One cow (it faces -z), about life size, on a little plinth, painted in three colours: a base coat, patches, and
## its legs and face.
static func cow(paint: Array, seed_v: int) -> Node3D:
	var holder := Node3D.new()
	var base: Color = paint[0]
	var spot: Color = paint[1]
	var trim: Color = paint[2]
	SkModels.box(holder, Vector3(1.4, 0.18, 2.6), Vector3(0, 0.09, 0), Color("#9a968d"))           # the plinth
	SkModels.box(holder, Vector3(0.85, 0.85, 1.9), Vector3(0, 1.25, 0), base)                       # body
	for lx in [-0.28, 0.28]:
		for lz in [-0.7, 0.7]:
			SkModels.box(holder, Vector3(0.2, 0.85, 0.2), Vector3(lx, 0.6, lz), trim)               # legs
			SkModels.box(holder, Vector3(0.22, 0.12, 0.22), Vector3(lx, 0.24, lz), Color("#2b2b2b")) # hooves
	SkModels.box(holder, Vector3(0.5, 0.5, 0.6), Vector3(0, 1.5, -1.15), base)                     # head
	SkModels.box(holder, Vector3(0.42, 0.28, 0.2), Vector3(0, 1.36, -1.48), trim)                  # nose
	for ex in [-0.33, 0.33]:
		SkModels.box(holder, Vector3(0.2, 0.1, 0.12), Vector3(ex, 1.7, -1.05), base.darkened(0.15)) # ears
		SkModels.box(holder, Vector3(0.07, 0.07, 0.07), Vector3(ex * 0.55, 1.6, -1.46), Color("#151515")) # eyes
	SkModels.box(holder, Vector3(0.08, 0.6, 0.08), Vector3(0, 1.15, 1.0), trim)                    # tail
	# the paint job: patches on the sides and back
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for k in 7:
		var side := -1.0 if k % 2 == 0 else 1.0
		var sz := Vector3(0.04, rng.randf_range(0.25, 0.5), rng.randf_range(0.3, 0.7))
		var p := Vector3(side * 0.44, rng.randf_range(1.05, 1.45), rng.randf_range(-0.7, 0.7))
		if k == 6:
			sz = Vector3(rng.randf_range(0.3, 0.6), 0.04, rng.randf_range(0.4, 0.9))
			p = Vector3(0, 1.69, rng.randf_range(-0.4, 0.4))
		SkModels.box(holder, sz, p, spot)
	var n := Node3D.new()
	n.name = "Cow"
	var mi := MeshInstance3D.new()
	mi.mesh = SkModels.bake(holder)
	mi.material_override = SkModels.baked_material()
	holder.free()
	n.add_child(mi)
	return n

# ================================================================ the Maude St Mall

## The Maude St Mall (and any other pedestrian street on the map): paved from shopfront to shopfront, with two rows of
## trees down it, benches between them and lamp posts along the middle. The exact layout is a GUESS (Street View
## couldn't be checked for it); it's the usual pattern for a country-town mall.
static func malls(town: SkTownBuilder) -> void:
	var holder := Node3D.new()
	var lamps := []
	var benches := []
	for r in town.data.roads:
		var lane: bool = String(r.n).ends_with(" Mall")       # (the Maude St Mall: a slow lane down the middle)
		if not lane and (r.k != "pedestrian" or r.n == ""):
			continue
		var p := SkTownBuilder._pts(r.p)
		for i in p.size() - 1:
			var a := p[i]
			var b := p[i + 1]
			var len := a.distance_to(b)
			var d := (b - a) / maxf(len, 0.01)
			var side := d.orthogonal()
			var s := 6.0
			while s < len - 3.0:
				var at := a + d * s
				var off := 3.6 if lane else 0.0
				for sg in ([-1.0, 1.0] if lane else [0.0]):
					lamps.append(at + side * off * sg)
				var bo := 7.5 if lane else 2.2
				benches.append([at + side * bo + d * 5.0, d])
				benches.append([at - side * bo + d * 5.0, -d])
				s += 14.0
	for at in lamps:
		SkModels.box(holder, Vector3(0.14, 4.5, 0.14), Vector3(at.x, 2.25, at.y), Color("#3a3f45"))
		SkModels.box(holder, Vector3(0.5, 0.18, 0.5), Vector3(at.x, 4.55, at.y), Color("#f3ead2"))
	for bn in benches:
		var at: Vector2 = bn[0]
		var d: Vector2 = bn[1]
		var bench := SkModels.box(holder, Vector3(0.5, 0.12, 1.8), Vector3(at.x, 0.62, at.y), Color("#9c6b43"))
		bench.rotation.y = atan2(d.x, d.y)
		var legs := SkModels.box(holder, Vector3(0.4, 0.45, 1.5), Vector3(at.x, 0.38, at.y), Color("#4a4f55"))
		legs.rotation.y = atan2(d.x, d.y)
	if lamps.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "MallFurniture"
	mi.mesh = SkModels.bake(holder)
	mi.material_override = SkModels.baked_material()
	mi.visibility_range_end = 400.0
	holder.free()
	town.root.add_child(mi)
