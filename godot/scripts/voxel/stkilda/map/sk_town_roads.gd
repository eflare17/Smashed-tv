# (Copied from stkilda-godot scripts/town/town_roads.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkTownRoads
extends RefCounted
## The roads' paint and furniture, from the map (data/town.json): a dashed white centre line down two-way roads,
## edge lines on the main roads, lane lines on the divided ones (Wyndham St's two sides are each a one-way road on
## the map), grassed islands in the roundabouts, zebra stripes at the pedestrian crossings, and traffic lights at
## the lights. The lines and islands are one flat mesh; the light poles are drawn in batches.

const LINE := Color("#eeece4")
const LINE_Y := 0.175             # just over the roads (0.14) and the Mall's paving (0.16)
const DASH := 3.0
const GAP := 6.0
const MAIN := ["trunk", "primary", "secondary"]
const NO_LINES := ["service", "pedestrian", "trunk_link", "primary_link", "secondary_link", "tertiary_link"]
const ISLAND := Color("#8aa65a")
const KERB := Color("#d6d1c4")

func build(town: SkTownBuilder) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for r in town.data.roads:
		if r.k in NO_LINES or r.get("j", false):
			continue
		var p := SkTownBuilder._pts(r.p)
		var w: float = r.w
		var lanes: int = r.get("l", 0)
		if not r.get("o", false):
			if w >= 8.0:
				_dashed(st, p, 0.0, 0.12)
		elif lanes >= 2:
			for k in range(1, lanes):
				_dashed(st, p, -w / 2.0 + w * k / lanes, 0.12)
		if r.k in MAIN:
			for side in [-1.0, 1.0]:
				_solid(st, SkTownBuilder._offset(p, side * (w / 2.0 - 0.35)), 0.12)
	# roundabouts: the ring of road, then a grassed island in the middle with a kerb round it
	for r in town.data.roads:
		if not r.get("j", false):
			continue
		var ring := SkTownBuilder._pts(r.p)
		if ring.size() < 4 or not ring[0].is_equal_approx(ring[-1]):
			continue
		ring.remove_at(ring.size() - 1)
		var inner := Geometry2D.offset_polygon(ring, -float(r.w) / 2.0 - 0.2)
		for island in inner:
			var isl: PackedVector2Array = island
			if isl.size() < 3:
				continue
			town._poly(st, isl, LINE_Y + 0.02, ISLAND)
			var closed := isl.duplicate()
			closed.append(isl[0])
			town._line(st, closed, 0.35, LINE_Y + 0.03, KERB, true)
	# zebra crossings: white stripes across the road, along its direction
	var c: Array = town.data.get("crossings", [])
	for i in range(0, c.size() - 4, 5):
		var at := Vector2(c[i], c[i + 1])
		var d := Vector2(c[i + 2], c[i + 3])
		var w: float = c[i + 4]
		if w < 6.0:
			continue
		var across := d.orthogonal()
		var n := int(w / 1.2)
		for k in n:
			var o := across * (-w / 2.0 + 0.6 + k * 1.2)
			_bar(st, at + o - d * 1.5, at + o + d * 1.5, 0.55)
	var mi := MeshInstance3D.new()
	mi.name = "RoadMarkings"
	mi.mesh = st.commit()
	mi.material_override = SkModels.baked_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	town.root.add_child(mi)
	_lights(town)

## A dashed line `off` metres to the side of a road's middle.
func _dashed(st: SurfaceTool, p: PackedVector2Array, off: float, w: float) -> void:
	if off != 0.0:
		p = SkTownBuilder._offset(p, off)
	var on := 0.0                      # how far into the current dash-and-gap we are
	for i in p.size() - 1:
		var a := p[i]
		var b := p[i + 1]
		var len := a.distance_to(b)
		if len < 0.01:
			continue
		var d := (b - a) / len
		var s := 0.0
		while s < len:
			var into := fmod(on + s, DASH + GAP)
			if into < DASH:
				var e := minf(len, s + (DASH - into))
				_bar(st, a + d * s, a + d * e, w)
				s = e
			else:
				s += DASH + GAP - into
		on += len

func _solid(st: SurfaceTool, p: PackedVector2Array, w: float) -> void:
	for i in p.size() - 1:
		_bar(st, p[i], p[i + 1], w)

## A white bar from a to b, w wide, painted on the road.
func _bar(st: SurfaceTool, a: Vector2, b: Vector2, w: float) -> void:
	if a.distance_to(b) < 0.01:
		return
	var n := (b - a).normalized().orthogonal() * (w / 2.0)
	var y := LINE_Y
	SkTownBuilder._tri(st, Vector3(a.x + n.x, y, a.y + n.y), Vector3(a.x - n.x, y, a.y - n.y), Vector3(b.x - n.x, y, b.y - n.y), LINE)
	SkTownBuilder._tri(st, Vector3(a.x + n.x, y, a.y + n.y), Vector3(b.x - n.x, y, b.y - n.y), Vector3(b.x + n.x, y, b.y + n.y), LINE)

## Traffic lights: a grey pole each side of the road with a black box of three lights facing the traffic.
func _lights(town: SkTownBuilder) -> void:
	var l: Array = town.data.get("lights", [])
	if l.is_empty():
		return
	var holder := Node3D.new()
	SkModels.box(holder, Vector3(0.16, 4.2, 0.16), Vector3(0, 2.1, 0), Color("#8b9196"))
	SkModels.box(holder, Vector3(0.36, 1.0, 0.3), Vector3(0, 3.6, 0.12), Color("#1d1f22"))
	for k in 3:
		SkModels.box(holder, Vector3(0.22, 0.22, 0.04), Vector3(0, 3.92 - k * 0.32, 0.29), [Color("#d8382f"), Color("#e8a425"), Color("#3fbf5f")][k].darkened(0.25 if k != 2 else 0.0))
	var mesh := SkModels.bake(holder)
	holder.free()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = (l.size() / 5) * 2
	var n := 0
	for i in range(0, l.size() - 4, 5):
		var at := Vector2(l[i], l[i + 1])
		var d := Vector2(l[i + 2], l[i + 3])
		var w: float = l[i + 4]
		for side in [-1.0, 1.0]:
			var p: Vector2 = at + d.orthogonal() * side * (w / 2.0 + 0.8) - d * side * 4.0
			var face: Vector2 = -d * side                     # facing the traffic coming toward it
			mm.set_instance_transform(n, Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), Vector3(p.x, 0, p.y)))
			n += 1
	var mi := MultiMeshInstance3D.new()
	mi.name = "TrafficLights"
	mi.multimesh = mm
	mi.material_override = SkModels.baked_material()
	mi.visibility_range_end = 500.0
	town.root.add_child(mi)
