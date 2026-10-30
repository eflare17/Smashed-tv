class_name VoxelCarousel
extends RefCounted
## The Carousel made over (the owner, 31 Oct: "way less horses", then a carousel to match them, from their photo of
## one), as an open ride (the owner OK'd: its building's taken away, its black iron fence kept):
##   - RING of the owner's carousel horses (assets/models/carousel_horse/horse.res, made by tools/carousel_horse.gd),
##     each on a twisted gold pole from the floor to the ceiling, riding up and down it, people on about half;
##   - a grey diamond-plate metal floor with a gold edge, on a deep red base;
##   - in the middle, a column of red panels patterned in gold, between tall gold-framed mirrors;
##   - a cream ceiling with gold ribs out from the middle and gold rings round, warm bulbs all along the ribs;
##   - round its rim, gold crests on cream with bulbs above and below, a deep red drape hanging under it;
##   - a cream roof up to a gold top.
## Its bulbs are lit by day and glow at night (SkRideLights' bulbs, warm white here, smaller), and the ride's coloured
## light and pools at night come from SkRideLights (it finds the new roof as it found the old). Done here, over what
## SkLunaRides built (that's copied from the St Kilda game: not changed here).

const RING := 12
const R := 4.9                      # the horses' ring (between the column and the platform's edge)
const RISE := 0.35                  # how far up and down they ride (as the old ones)
const EDGE := 7.5                   # the platform's radius (SkLunaRides.CAROUSEL_R)
const FLOOR := 0.67                 # the platform's top
const CEILING := 4.2                # the ceiling
const RIM_TOP := 5.3                # the rim's top
const MID := 2.0                    # the middle column's radius
const POLE_R := 0.045
const HIPS := Vector3(-0.2, 1.3, 0)  # where a rider sits on a horse (the seat's just behind the pole)

const GOLD := Color("#e2b443")
const GOLD_DARK := Color("#b8862a")
const RED := Color("#8e1c22")
const RED_DARK := Color("#5e1116")
const CREAM := Color("#f2e7cf")
const IRON := Color("#1b1c1f")       # (SkLunaRides' fence)
const WARM := [Color(1.0, 0.86, 0.55), Color(1.0, 0.93, 0.72), Color(1.0, 0.8, 0.45)]

static func dress(carousel: Node3D) -> void:
	if carousel == null:
		return
	var spin := carousel.get_node_or_null("Ride") as SkLunaRides.Spinner
	if spin == null:
		return
	_open(carousel)
	for c in spin.get_children():
		spin.remove_child(c)
		c.free()
	_ride(spin)
	_horses(spin)

## Its building off: the piers, arches, band and roof (and the piers' collision), the fence kept (the building's mesh
## cut down to its black iron).
static func _open(carousel: Node3D) -> void:
	var roof := carousel.get_node_or_null("Roof")
	if roof:
		carousel.remove_child(roof)
		roof.free()
	for c in carousel.get_children():
		if c is StaticBody3D:                 # (the piers': the fence's are each under a node of their own)
			carousel.remove_child(c)
			c.free()
	var mi := carousel.get_node_or_null("Building") as MeshInstance3D
	if mi == null:
		return
	var m := mi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if col[idx[t]].is_equal_approx(IRON):
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		if not keep.is_empty():
			arr[Mesh.ARRAY_INDEX] = keep
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.name = "Fence"
	mi.mesh = out

## The ride (all of it turning with the Spinner).
static func _ride(spin: Node3D) -> void:
	var h := Node3D.new()
	var top := Node3D.new()                  # (the rim, its drape and the roof: SkRideLights hangs its lights by them)
	var bulbs := []
	# the base and the floor's gold edge
	SkModels.cyl(h, EDGE, 0.5, Vector3(0, 0.35, 0), RED_DARK, true, 48)
	SkModels.cyl(h, EDGE + 0.04, 0.08, Vector3(0, 0.56, 0), GOLD, true, 48)
	SkModels.cyl(h, EDGE + 0.04, 0.06, Vector3(0, 0.16, 0), GOLD, true, 48)
	for k in 24:                           # (gold studs round the base)
		var a := TAU * (k + 0.5) / 24.0
		SkModels.ball(h, 0.07, Vector3(cos(a), 0, sin(a)) * (EDGE + 0.02) + Vector3(0, 0.36, 0), GOLD)
	# the middle: red panels patterned in gold between tall gold-framed mirrors (the mirrors are drawn apart: glass)
	var mirrors := Node3D.new()
	var sides := 16
	var w := 2.0 * MID * tan(PI / sides)
	var tall := CEILING - FLOOR
	for k in sides:
		var a := TAU * k / sides
		var out := Vector3(cos(a), 0, sin(a))
		var at := out * MID * cos(PI / sides) + Vector3(0, FLOOR + tall / 2.0, 0)
		var face := Basis(Vector3.UP, -a + PI / 2.0)
		if k % 2 == 0:
			_put(SkModels.box(h, Vector3(w, tall, 0.1), at, RED), face)
			for row in 4:                      # its gold pattern
				var y := FLOOR + 0.55 + row * 0.8
				_fleur(h, out * (MID * cos(PI / sides) + 0.06) + Vector3(0, y, 0), face)
			_frame(h, at + out * 0.05, face, w - 0.06, tall - 0.1, 0.06)
		else:
			_put(SkModels.box(h, Vector3(w, tall, 0.1), at, GOLD_DARK), face)
			var glass := SkModels.box(mirrors, Vector3(w - 0.22, tall - 0.7, 0.04), at + out * 0.06 + Vector3(0, -0.1, 0), Color.WHITE)
			_put(glass, face)
			_frame(h, at + out * 0.08 + Vector3(0, -0.1, 0), face, w - 0.14, tall - 0.62, 0.07)
			var knob := SkModels.ball(h, 0.11, at + out * 0.1 + Vector3(0, tall / 2.0 - 0.15, 0), GOLD)
			knob.scale = Vector3(1.0, 1.4, 1.0)
	# the ceiling: cream, gold ribs out from the middle with bulbs all along them, gold rings round
	SkModels.cyl(h, EDGE + 0.2, 0.1, Vector3(0, CEILING + 0.05, 0), CREAM, true, 48)
	var ribs := 24
	for k in ribs:
		var a := TAU * k / ribs
		var out := Vector3(cos(a), 0, sin(a))
		var mid := out * (MID + EDGE) / 2.0 + Vector3(0, CEILING - 0.03, 0)
		var rib := SkModels.box(h, Vector3(EDGE - MID, 0.06, 0.12), mid, GOLD)
		rib.rotation.y = -a
		var r := MID + 0.3
		while r < EDGE - 0.1:
			bulbs.append(out * r + Vector3(0, CEILING - 0.1, 0))
			r += 0.42
	for rr in [MID + 0.05, 3.6, 5.6, EDGE + 0.1]:
		_ring(h, rr, CEILING - 0.02, 0.07, 0.1, GOLD)
	# the rim: cream with gold bands top and bottom, gold crests, bulbs along it
	SkModels.cyl(top, EDGE + 0.2, RIM_TOP - CEILING, Vector3(0, (RIM_TOP + CEILING) / 2.0, 0), CREAM, true, 48)
	_ring(top, EDGE + 0.22, CEILING + 0.08, 0.06, 0.12, GOLD)
	_ring(top, EDGE + 0.22, RIM_TOP - 0.06, 0.06, 0.12, GOLD)
	for k in RING:
		var a := TAU * (k + 0.5) / RING
		var out := Vector3(cos(a), 0, sin(a))
		_crest(top, out * (EDGE + 0.25) + Vector3(0, (RIM_TOP + CEILING) / 2.0, 0), Basis(Vector3.UP, -a + PI / 2.0))
	for k in 96:
		var a := TAU * (k + 0.5) / 96.0
		var out := Vector3(cos(a), 0, sin(a))
		bulbs.append(out * (EDGE + 0.3) + Vector3(0, RIM_TOP - 0.2, 0))
		if k % 2 == 0:
			bulbs.append(out * (EDGE + 0.3) + Vector3(0, CEILING + 0.25, 0))
	# the red drape hung under the rim, its points tipped with gold
	for k in 48:
		var a := TAU * (k + 0.5) / 48.0
		var out := Vector3(cos(a), 0, sin(a))
		var face := Basis(Vector3.UP, -a + PI / 2.0)
		var d := SkLunaRides._disc(top, 0.26, 0.04, out * (EDGE + 0.24) + Vector3(0, CEILING - 0.02, 0), RED)
		d.basis = face * Basis(Vector3.RIGHT, PI / 2.0)
		d.scale = Vector3(1.0, 1.0, 1.25)
		_put(SkModels.box(top, Vector3(0.06, 0.06, 0.06), out * (EDGE + 0.27) + Vector3(0, CEILING - 0.3, 0), GOLD), face)
	# the roof, cream up to a gold top
	SkLunaRides._cone(top, EDGE + 0.15, 1.0, 1.9, Vector3(0, RIM_TOP + 0.95, 0), CREAM, 32)
	SkModels.cyl(top, 1.05, 0.12, Vector3(0, RIM_TOP + 1.9, 0), GOLD, true, 16)
	SkLunaRides._cone(top, 0.9, 0.0, 1.2, Vector3(0, RIM_TOP + 2.55, 0), GOLD, 12)
	SkModels.ball(top, 0.22, Vector3(0, RIM_TOP + 3.25, 0), GOLD)
	for part in [[h, "Body"], [top, "Roof"]]:   # (SkRideLights hangs its lights by "Roof", as it did the building's)
		var mi := MeshInstance3D.new()
		mi.name = part[1]
		mi.mesh = SkModels.bake(part[0])
		mi.material_override = SkModels.baked_material()
		(part[0] as Node3D).free()
		spin.add_child(mi)
	var glass := MeshInstance3D.new()
	glass.name = "Mirrors"
	glass.mesh = SkModels.bake(mirrors)
	mirrors.free()
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#c8d9e6")
	gm.metallic = 0.45            # (all metal reads black where there's nothing bright to reflect)
	gm.roughness = 0.1
	glass.material_override = gm
	spin.add_child(glass)
	var fl := MeshInstance3D.new()
	fl.name = "Floor"
	var cm := CylinderMesh.new()
	cm.top_radius = EDGE
	cm.bottom_radius = EDGE
	cm.height = 0.1
	cm.radial_segments = 48
	cm.rings = 1
	fl.mesh = cm
	fl.position = Vector3(0, FLOOR - 0.05, 0)
	fl.material_override = _plate()
	spin.add_child(fl)
	_bulbs(spin, bulbs)

static func _put(n: Node3D, b: Basis) -> void:
	n.basis = b * n.basis

## A gold fleur-de-lis on a panel, at `at` facing out along `face`'s z: a middle petal, two curled out, a band.
static func _fleur(h: Node3D, at: Vector3, face: Basis) -> void:
	var f := Node3D.new()
	h.add_child(f)
	f.transform = Transform3D(face, at)
	var mid := SkModels.box(f, Vector3(0.09, 0.3, 0.03), Vector3(0, 0.06, 0), GOLD)
	mid.rotation.z = 0.0
	for s in [-1.0, 1.0]:
		var p := SkModels.box(f, Vector3(0.07, 0.22, 0.03), Vector3(s * 0.11, 0.02, 0), GOLD)
		p.rotation.z = s * 0.6
		SkModels.ball(f, 0.035, Vector3(s * 0.19, 0.1, 0), GOLD)
	SkModels.box(f, Vector3(0.3, 0.05, 0.035), Vector3(0, -0.04, 0), GOLD)
	var tip := SkModels.box(f, Vector3(0.08, 0.08, 0.03), Vector3(0, 0.22, 0), GOLD)
	tip.rotation.z = PI / 4.0
	var foot := SkModels.box(f, Vector3(0.06, 0.12, 0.03), Vector3(0, -0.12, 0), GOLD)
	foot.rotation.z = 0.0

## A gold frame round a w x t opening at `at`, facing out along `face`'s z.
static func _frame(h: Node3D, at: Vector3, face: Basis, w: float, t: float, bar: float) -> void:
	for s in [-1.0, 1.0]:
		_put(SkModels.box(h, Vector3(bar, t, 0.05), at + face * Vector3(s * (w - bar) / 2.0, 0, 0), GOLD), face)
		_put(SkModels.box(h, Vector3(w, bar, 0.05), at + face * Vector3(0, s * (t - bar) / 2.0, 0), GOLD), face)

## A gold crest on the rim: a shield with a crown over it and scrolls each side.
static func _crest(h: Node3D, at: Vector3, face: Basis) -> void:
	var c := Node3D.new()
	h.add_child(c)
	c.transform = Transform3D(face, at)
	var shield := SkLunaRides._disc(c, 0.28, 0.06, Vector3(0, -0.02, 0.04), GOLD)
	shield.scale = Vector3(0.85, 1.0, 1.25)
	SkLunaRides._disc(c, 0.17, 0.06, Vector3(0, -0.02, 0.08), RED)
	for k in 3:
		var p := SkModels.box(c, Vector3(0.1, 0.1, 0.05), Vector3((k - 1) * 0.12, 0.34, 0.04), GOLD)
		p.rotation.z = PI / 4.0
	SkModels.box(c, Vector3(0.36, 0.06, 0.05), Vector3(0, 0.27, 0.04), GOLD)
	for s in [-1.0, 1.0]:
		var sc := SkLunaRides._disc(c, 0.12, 0.05, Vector3(s * 0.42, -0.05, 0.03), GOLD)
		sc.scale = Vector3(1.4, 1.0, 0.8)
		SkModels.ball(c, 0.05, Vector3(s * 0.58, 0.02, 0.04), GOLD)

## A gold ring round the middle at radius r, height y.
static func _ring(h: Node3D, r: float, y: float, tall: float, wide: float, c: Color) -> void:
	var n := maxi(16, int(TAU * r / 0.5))
	for k in n:
		var a := TAU * (k + 0.5) / n
		var b := SkModels.box(h, Vector3(wide, tall, TAU * r / n + 0.02), Vector3(cos(a), 0, sin(a)) * r + Vector3(0, y, 0), c)
		b.rotation.y = -a

## The diamond-plate floor: grey steel with raised diamonds, two ways in turn.
static func _plate() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float bump(vec2 p) {
	vec2 c = floor(p);
	vec2 f = fract(p) - 0.5;
	bool flip = mod(c.x + c.y, 2.0) > 0.5;
	vec2 q = flip ? vec2(f.x + f.y, f.x - f.y) : vec2(f.x - f.y, f.x + f.y);
	float d = abs(q.x) / 0.42 + abs(q.y) / 0.11;
	return 1.0 - smoothstep(0.75, 1.0, d);
}
void fragment() {
	vec2 p = lp.xz / 0.09;
	float h = bump(p);
	float hx = bump(p + vec2(0.04, 0.0)) - h;
	float hz = bump(p + vec2(0.0, 0.04)) - h;
	NORMAL_MAP = normalize(vec3(-hx * 2.5, -hz * 2.5, 1.0)) * 0.5 + 0.5;
	ALBEDO = vec3(0.56, 0.58, 0.6) * (0.85 + 0.25 * h);
	METALLIC = 0.7;
	ROUGHNESS = 0.42 - 0.12 * h;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

## Its warm bulbs, as SkRideLights' (lit by day, glowing at night: SkDayNight turns them up), but smaller.
static var _small: SphereMesh
static func _bulbs(n: Node3D, at: Array) -> void:
	if _small == null:
		_small = SphereMesh.new()
		_small.radius = 0.06
		_small.height = 0.12
		_small.radial_segments = 6
		_small.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _small
	mm.instance_count = at.size()
	for k in at.size():
		mm.set_instance_transform(k, Transform3D(Basis(), at[k]))
		var c: Color = WARM[k % WARM.size()]
		mm.set_instance_custom_data(k, Color(c.r, c.g, c.b, float(k) / at.size()))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Bulbs"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := SkRideLights.material().duplicate() as ShaderMaterial
	m.set_shader_parameter("chase", 0.0)
	m.set_shader_parameter("count", float(at.size()))
	m.set_shader_parameter("night", SkRideLights.night)
	mi.material_override = m
	mi.visibility_range_end = 400.0
	SkRideLights.mats.append(m)
	n.add_child(mi)

## The horses on their poles, riding up and down, people on about half.
static func _horses(spin: SkLunaRides.Spinner) -> void:
	var poles := Node3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = load("res://assets/models/carousel_horse/horse.res")
	mm.instance_count = RING
	var horses := MultiMeshInstance3D.new()
	horses.name = "Horses"
	horses.multimesh = mm
	horses.material_override = SkModels.baked_material()
	horses.visibility_range_end = 500.0
	spin.add_child(horses)
	var list := []
	var seats := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1913
	for k in RING:
		var a := TAU * k / RING
		var at := Vector3(cos(a), 0, sin(a)) * R
		_pole(poles, at)
		# (nose first the way the ride turns: the Spinner turns it +y, so a horse at angle a moves along (sin a, 0, -cos a))
		var xf := Transform3D(Basis(Vector3.UP, PI / 2.0 - a), at + Vector3(0, FLOOR, 0))
		mm.set_instance_transform(k, xf)
		list.append([horses, k, xf, RISE, float(k) * 1.7])
		if rng.randf() < 0.5:
			seats.append([mm, k, SkLunaRides._seat(HIPS, -PI / 2.0, 0.85)])
	var pm := MeshInstance3D.new()
	pm.name = "Poles"
	pm.mesh = SkModels.bake(poles)
	pm.material_override = SkModels.baked_material()
	poles.free()
	spin.add_child(pm)
	spin.horses = list
	spin.riders = SkLunaRides._riders(spin, seats, 0.0, 0.8, 0.15)

## A twisted gold pole, floor to ceiling: a rod with a ridge wound round it, a collar at each end.
static func _pole(holder: Node3D, at: Vector3) -> void:
	SkModels.cyl(holder, POLE_R, CEILING - FLOOR, at + Vector3(0, (CEILING + FLOOR) / 2.0, 0), GOLD, true, 8)
	var steps := 40
	for s in steps:
		var t := float(s) / steps
		var y := lerpf(FLOOR + 0.1, CEILING - 0.1, t)
		var a := t * TAU * 9.0
		var b := SkModels.box(holder, Vector3(0.035, 0.11, 0.035), at + Vector3(cos(a) * POLE_R, y, sin(a) * POLE_R), GOLD_DARK)
		b.rotation = Vector3(0, -a, 0.5)
	for y in [FLOOR + 0.05, CEILING - 0.06]:
		SkModels.cyl(holder, POLE_R * 1.9, 0.1, at + Vector3(0, y, 0), GOLD.lightened(0.1), true, 8)
