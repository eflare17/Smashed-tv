# (Copied from stkilda-godot scripts/town/ride_lights.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkRideLights
extends RefCounted
## Colourful bulbs on Luna Park's rides, lit at night (the owner's idea; where the real ones' bulbs are isn't known
## here, so they're fitted to each ride's shape): round the Sky Rider's rim and along its spokes, round the Carousel's
## canopy, in rings up the Coney Drop's tower, round the spinning rides (the Spider, Power Surge, Supernova, the Arabian
## Merry), along Pharaoh's Curse's arms, and along the roof lines of Luna Palace and the Ghost Train. Each set rides on
## the part that moves, so they turn with it; the colours chase round (a shader). They're on all the time (the real
## park keeps its bulbs lit by day too, the owner's idea), softer by day: SkDayNight sets each one's "night".
##
## At night only (the owner's pick, 2026-10-29), to make them more epic: each bulb has a soft halo of its colour, chasing
## with it; each ride gets one real light at the middle of its bulbs, slowly going through their colours, so the bulbs'
## colour spills onto the ride (none on Luna Palace or the Ghost Train: their bulbs run round their roofs; and only the
## one each, real lights being what costs on a phone); and coloured pools of light on the ground round each ride, pulsing
## with its bulbs.

const COLOURS := [Color(1.0, 0.2, 0.25), Color(1.0, 0.75, 0.1), Color(0.2, 0.9, 0.35), Color(0.25, 0.6, 1.0),
	Color(0.95, 0.35, 1.0)]
const HALO := 0.6                       # a halo's radius (a bulb's is 0.14)
const SPILL := 5.0                      # a ride's light at night

static var _mesh: SphereMesh
static var _mat: ShaderMaterial
static var _halo_mesh: QuadMesh
static var _halo_mat: ShaderMaterial
static var _pool_mat: ShaderMaterial
## Every set's material, halos' and pools' too (SkDayNight turns them up at night).
static var mats: Array = []
## 0 day .. 1 night (SkDayNight sets it): the rides' lights follow it.
static var night := 0.0
## The halos and pools, hidden by day (SkDayNight).
static var night_only: Array = []

## The rides' lights, going slowly through the bulbs' colours, each [light, its night energy, where in the colours].
class Spill extends Node:
	var lights: Array = []

	func _process(_dt: float) -> void:
		var on := SkRideLights.night
		var tm := Time.get_ticks_msec() / 1000.0
		var cols := SkRideLights.COLOURS
		for s in lights:
			var l := s[0] as OmniLight3D
			l.visible = on > 0.02
			if not l.visible:
				continue
			var f := fposmod(tm * 0.3 + float(s[2]), float(cols.size()))
			var i := int(f)
			l.light_color = (cols[i] as Color).lerp(cols[(i + 1) % cols.size()], smoothstep(0.55, 1.0, f - i))
			l.light_energy = float(s[1]) * on

## Put the lights on the rides under `main`.
static func build(main: Node) -> void:
	var spill := Spill.new()
	spill.name = "RideSpill"
	main.add_child(spill)
	var wheel := _part(main, "SkyRider", "Wheel")
	if wheel:
		var b := _box(wheel)
		var thin := _thin_axis(b)
		var r := _span(b, thin) / 2.0 * 0.97
		_ring(wheel, b.get_center(), thin, r, 40, 1.4)
		_ring(wheel, b.get_center(), thin, r * 0.35, 12, 1.4)
		for k in 8:
			var a := TAU * k / 8.0
			var d := _in_plane(thin, a)
			_line(wheel, b.get_center() + d * r * 0.38, b.get_center() + d * r * 0.95, 6, 2.0)
		var mid := wheel.global_transform * b.get_center()
		var scl := wheel.global_basis.get_scale().x
		_spill(spill, mid, r * scl * 1.5, 0.0)
		# (pools along the ground under the wheel, across its face)
		var across := (wheel.global_basis * thin).normalized().cross(Vector3.UP).normalized()
		_pool_line(main, mid - across * r * scl, mid + across * r * scl, 5, r * scl * 0.8, 1.4)
	var roof := _part(main, "Carousel", "Roof")
	if roof:
		var b := _box(roof)
		var r := maxf(b.size.x, b.size.z) / 2.0 * 0.98
		_ring(roof, Vector3(b.get_center().x, b.position.y + 0.1, b.get_center().z), Vector3.UP, r, 36, 0.8)
		var mid := roof.global_transform * Vector3(b.get_center().x, b.position.y - 0.8, b.get_center().z)
		var rg := r * roof.global_basis.get_scale().x
		_spill(spill, mid, rg * 1.6, 1.0)
		_pool_ring(main, mid, rg * 1.05, 10, rg * 0.8, 0.8)
	var drop := main.get_node_or_null("ConeyDrop") as Node3D
	if drop:
		var b := _box(drop, 6.0)
		var r := 0.9                         # (just round the lattice: the baked tower's box takes in its wide base)
		var y := b.position.y + 4.0
		while y < b.end.y - 1.0:
			_ring(drop, Vector3(b.get_center().x, y, b.get_center().z), Vector3.UP, r, 10, 0.0)
			y += 4.0
		# (the light low down, where it's seen from the ground)
		var foot := drop.global_transform * Vector3(b.get_center().x, b.position.y, b.get_center().z)
		_spill(spill, foot + Vector3(0, 9, 0), 16.0, 2.0)
		_pool_ring(main, foot, 3.0, 6, 5.0, 0.0)
	var phase := 0.0
	for spin in [["Spider", "Body"], ["PowerSurge", "Star"], ["Supernova", "Carriage"], ["ArabianMerry", "Elephants"]]:
		var part := _part(main, spin[0], spin[1])
		if part:
			var b := _box(part)
			var r := maxf(b.size.x, b.size.z) / 2.0 * 0.92
			_ring(part, Vector3(b.get_center().x, b.get_center().y, b.get_center().z), Vector3.UP, r, 24, 2.2)
			_ring(part, Vector3(b.get_center().x, b.end.y, b.get_center().z), Vector3.UP, r * 0.3, 10, 2.2)
			var mid := part.global_transform * b.get_center()
			var rg := r * part.global_basis.get_scale().x
			phase += 1.3
			_spill(spill, mid, rg * 1.7 + 2.0, phase)
			_pool_ring(main, mid, rg, 10, maxf(5.0, rg * 1.1), 2.2)
	var arms := _part(main, "PharaohsCurse", "Arms")
	if arms:
		var b := _box(arms)
		var long := 0 if b.size.x >= b.size.z else 2
		for side in [-1.0, 1.0]:
			var a := b.get_center()
			var e := b.get_center()
			a[long] = b.position[long]
			e[long] = b.end[long]
			var off := Vector3.ZERO
			off[2 - long] = side * b.size[2 - long] / 2.0
			_line(arms, a + off, e + off, 14, 1.2)
		var mid := arms.global_transform * b.get_center()
		_spill(spill, mid, b.size[long] * arms.global_basis.get_scale().x * 0.9, 3.0)
		# (pools along the ground the way it swings: the long way across the whole ride)
		var root := main.get_node("PharaohsCurse") as Node3D
		var rb := _box(root)
		var rl := 0 if rb.size.x >= rb.size.z else 2
		var a := rb.get_center()
		var e := rb.get_center()
		a[rl] = rb.position[rl]
		e[rl] = rb.end[rl]
		_pool_line(main, root.global_transform * a, root.global_transform * e, 6, 6.0, 1.2)
	for nm in ["LunaPalace", "GhostTrain"]:
		var n := main.get_node_or_null(nm) as Node3D
		if n:
			var b := _box(n, 0.0, true)
			# (along the top of the walls, not the turrets' or the skeleton's tops)
			var y := SkLunaRides.PALACE_H + 0.3 if nm == "LunaPalace" else SkLunaRides.GHOST_H + 1.25
			var c := [Vector3(b.position.x, y, b.position.z), Vector3(b.end.x, y, b.position.z), Vector3(b.end.x, y, b.end.z), Vector3(b.position.x, y, b.end.z)]
			for k in 4:
				var a: Vector3 = c[k]
				var e: Vector3 = c[(k + 1) % 4]
				_line(n, a, e, maxi(4, int(a.distance_to(e) / 1.2)), 0.9)
				# (and a strip of pools along the foot of the wall, just outside it)
				var out := ((a + e) / 2.0 - Vector3(b.get_center().x, y, b.get_center().z))
				out = Vector3(out.x, 0, 0) if absf(a.z - e.z) > 0.01 else Vector3(0, 0, out.z)
				var ga := n.global_transform * (a + out.normalized() * 1.0)
				var ge := n.global_transform * (e + out.normalized() * 1.0)
				_pool_line(main, ga, ge, maxi(3, int(ga.distance_to(ge) / 3.0)), 4.5, 0.9)

## A ride's light: at `at`, reaching `reach`, starting `phase` into the colours.
static func _spill(spill: Spill, at: Vector3, reach: float, phase: float) -> void:
	var o := OmniLight3D.new()
	o.omni_range = reach
	o.omni_attenuation = 1.0
	o.shadow_enabled = false
	o.light_energy = 0.0
	o.visible = false
	spill.add_child(o)
	o.global_position = at
	spill.lights.append([o, SPILL, phase])

## Pools on the ground round a ring (centre `c`, radius `r`), each `size` across.
static func _pool_ring(main: Node, c: Vector3, r: float, count: int, size: float, chase: float) -> void:
	var at := []
	for k in count:
		at.append(c + Vector3(cos(TAU * k / count), 0, sin(TAU * k / count)) * r)
	_pools(main, at, size, chase)

static func _pool_line(main: Node, a: Vector3, b: Vector3, count: int, size: float, chase: float) -> void:
	var at := []
	for k in count:
		at.append(a.lerp(b, float(k) / maxf(1.0, count - 1)))
	_pools(main, at, size, chase)

## Coloured pools of light on the ground at `at` (world space; the height's ignored), each a bulb colour in turn,
## pulsing round at `chase` like the bulbs.
static func _pools(main: Node, at: Array, size: float, chase: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _halo()
	mm.instance_count = at.size()
	var flat := Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3(size, size, size))
	for k in at.size():
		var p: Vector3 = at[k]
		mm.set_instance_transform(k, Transform3D(flat, Vector3(p.x, SkContactShade.Y + 0.02, p.z)))
		var c: Color = COLOURS[k % COLOURS.size()]
		mm.set_instance_custom_data(k, Color(c.r, c.g, c.b, float(k) / at.size()))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "NightPools"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := pool_material().duplicate() as ShaderMaterial
	m.set_shader_parameter("chase", chase)
	m.set_shader_parameter("count", float(at.size()))
	mmi.material_override = m
	mmi.visibility_range_end = 300.0
	mmi.visible = false
	mats.append(m)
	night_only.append(mmi)
	main.add_child(mmi)
	if main is Node3D:
		mmi.global_transform = Transform3D.IDENTITY

static func _part(main: Node, ride: String, part: String) -> Node3D:
	var n := main.get_node_or_null(ride)
	if n == null:
		return null
	return n.find_child(part, true, false) as Node3D

## The box round a node's meshes, in its own space (only the tall ones' if `tall` is more than 0: a tower's, not its
## base's; only the ones up off the ground if `high`).
static func _box(n: Node3D, tall := 0.0, high := false) -> AABB:
	var inv := n.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	var meshes := n.find_children("*", "GeometryInstance3D", true, false)
	if n is GeometryInstance3D:
		meshes.append(n)                    # (a part that's a mesh itself: the Carousel's roof)
	for c in meshes:
		var g := c as GeometryInstance3D
		var b := inv * g.global_transform * g.get_aabb()
		if b.size.y < tall or (high and b.end.y < 2.0) or b.size.length() > 120.0:
			continue
		out = b if first else out.merge(b)
		first = false
	return out

static func _thin_axis(b: AABB) -> Vector3:
	if b.size.x <= b.size.y and b.size.x <= b.size.z:
		return Vector3.RIGHT
	if b.size.z <= b.size.y:
		return Vector3.BACK
	return Vector3.UP

## How wide a box is across the plane at right angles to `axis` (its smaller side there).
static func _span(b: AABB, axis: Vector3) -> float:
	if axis == Vector3.RIGHT:
		return minf(b.size.y, b.size.z)
	if axis == Vector3.BACK:
		return minf(b.size.x, b.size.y)
	return minf(b.size.x, b.size.z)

static func _in_plane(axis: Vector3, a: float) -> Vector3:
	var u := Vector3.UP if axis != Vector3.UP else Vector3.RIGHT
	var v := axis.cross(u).normalized()
	return u * cos(a) + v * sin(a)

static func _ring(n: Node3D, c: Vector3, axis: Vector3, r: float, count: int, chase: float) -> void:
	var at := []
	for k in count:
		at.append(c + _in_plane(axis.normalized(), TAU * k / count) * r)
	_bulbs(n, at, chase)

static func _line(n: Node3D, a: Vector3, b: Vector3, count: int, chase: float) -> void:
	var at := []
	for k in count:
		at.append(a.lerp(b, float(k) / maxf(1.0, count - 1)))
	_bulbs(n, at, chase)

## A set of bulbs (in n's own space), each a colour in turn, chasing round at `chase` (0: steady).
static func _bulbs(n: Node3D, at: Array, chase: float, colours: Array = COLOURS) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _bulb()
	mm.instance_count = at.size()
	# (bulbs a constant size however the ride's scaled)
	var s := n.global_transform.basis.get_scale()
	var undo := Basis().scaled(Vector3(1.0 / maxf(s.x, 0.01), 1.0 / maxf(s.y, 0.01), 1.0 / maxf(s.z, 0.01)))
	for k in at.size():
		mm.set_instance_transform(k, Transform3D(undo, at[k]))
		var c: Color = colours[k % colours.size()]
		mm.set_instance_custom_data(k, Color(c.r, c.g, c.b, float(k) / at.size()))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "NightLights"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := material().duplicate() as ShaderMaterial
	m.set_shader_parameter("chase", chase)
	m.set_shader_parameter("count", float(at.size()))
	mmi.material_override = m
	mmi.visibility_range_end = 400.0
	mats.append(m)
	n.add_child(mmi)
	# the halos: the same bulbs again, as soft discs of their colour facing the camera (night only)
	var hm := MultiMesh.new()
	hm.transform_format = MultiMesh.TRANSFORM_3D
	hm.use_custom_data = true
	hm.mesh = _halo()
	hm.instance_count = at.size()
	for k in at.size():
		hm.set_instance_transform(k, mm.get_instance_transform(k))
		hm.set_instance_custom_data(k, mm.get_instance_custom_data(k))
	var hmi := MultiMeshInstance3D.new()
	hmi.name = "NightHalos"
	hmi.multimesh = hm
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hmi.extra_cull_margin = HALO * 2.0
	var h := halo_material().duplicate() as ShaderMaterial
	h.set_shader_parameter("chase", chase)
	h.set_shader_parameter("count", float(at.size()))
	hmi.material_override = h
	hmi.visibility_range_end = 400.0
	hmi.visible = false
	mats.append(h)
	night_only.append(hmi)
	n.add_child(hmi)

static func _bulb() -> SphereMesh:
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 0.14
		_mesh.height = 0.28
		_mesh.radial_segments = 6
		_mesh.rings = 3
	return _mesh

static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_back;
uniform float chase = 1.0;
uniform float count = 10.0;
uniform float night = 0.0;           // 0 day (softer: lit bulbs in the sun) .. 1 night (glowing)
varying vec4 bulb;
void vertex() {
	bulb = INSTANCE_CUSTOM;
}
void fragment() {
	// each bulb bright in turn going round (steady ones just twinkle a little)
	float on = chase > 0.0 ? 0.35 + 0.65 * step(0.5, fract(bulb.a * count / 5.0 - TIME * chase)) : 0.8 + 0.2 * sin(TIME * 3.0 + bulb.a * 40.0);
	ALBEDO = bulb.rgb * mix(0.5 + 0.8 * on, 0.4 + 2.4 * on, night);          // (over white: it glows)
}
"""
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat

static func _halo() -> QuadMesh:
	if _halo_mesh == null:
		_halo_mesh = QuadMesh.new()
		_halo_mesh.size = Vector2(1, 1)
	return _halo_mesh

## A bulb's halo: a soft disc of its colour, turned to face the camera and drawn just in front of the bulb (so a wall
## right behind doesn't cut it in half), brightening and dimming as the bulb chases. Night only.
static func halo_material() -> ShaderMaterial:
	if _halo_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float chase = 1.0;
uniform float count = 10.0;
uniform float night = 0.0;
uniform float size = %s;
varying vec4 bulb;
void vertex() {
	bulb = INSTANCE_CUSTOM;
	vec4 c = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	c.xyz += normalize(-c.xyz) * size * 0.7;
	POSITION = PROJECTION_MATRIX * (c + vec4(VERTEX.xy * size * 2.0, 0.0, 0.0));
}
void fragment() {
	float on = chase > 0.0 ? 0.35 + 0.65 * step(0.5, fract(bulb.a * count / 5.0 - TIME * chase)) : 0.8 + 0.2 * sin(TIME * 3.0 + bulb.a * 40.0);
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	ALBEDO = bulb.rgb;
	ALPHA = a * on * night * 0.85;
}
""" % HALO
		_halo_mat = ShaderMaterial.new()
		_halo_mat.shader = sh
	return _halo_mat

## A pool of coloured light on the ground: soft-edged, added over what's there, pulsing round with the ride's bulbs.
static func pool_material() -> ShaderMaterial:
	if _pool_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float chase = 1.0;
uniform float count = 10.0;
uniform float night = 0.0;
varying vec4 pool;
void vertex() {
	pool = INSTANCE_CUSTOM;
}
void fragment() {
	float on = chase > 0.0 ? 0.55 - 0.45 * sin(6.2832 * (pool.a * count / 5.0 - TIME * chase)) : 0.85 + 0.15 * sin(TIME * 3.0 + pool.a * 40.0);
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 1.3);
	ALBEDO = pool.rgb;
	ALPHA = a * on * night * 0.9;
}
"""
		_pool_mat = ShaderMaterial.new()
		_pool_mat.shader = sh
	return _pool_mat
