# (Copied from stkilda-godot scripts/town/park_flags.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkParkFlags
extends Node3D
## Colour up high in Luna Park (the owner's idea, 2026-10-29: not from photos, which don't show any): pennant flags
## flapping on the tops of Luna Palace's turrets and its tower, the Moon face's two dome spikes, and the tops of the
## Carousel, the Supernova, the Coney Drop and the Arabian Merry, all streaming the same way in the sea breeze; and
## strings of bunting between the lamp posts, sagging a little, their little flags fluttering. All flapping in the
## shader, so the flags are one batch, the bunting's flags another and its strings one mesh: cheap enough for phones.

const COLOURS := [Color("#d8262e"), Color("#f2c230"), Color("#2e6fd0"), Color("#2fa84f"), Color("#f4f1ea"), Color("#e2507a")]
## Which way they stream (to the north-east: the breeze off the bay, from the south-west).
const WIND_YAW := PI / 4.0
const STRING_Y := 3.62                    # where the bunting's tied on the lamp posts (just under the globes)
const SAG := 0.8
const PENNANT_EVERY := 0.55
const SPAN := [8.0, 19.0]                 # lamp posts this far apart get a string between them

static var _mat: ShaderMaterial

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var main := get_parent()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1927
	_flags(main, rng)
	_bunting(main, rng)

# ---------------------------------------------------------------- the flags on the tops

func _flags(main: Node, rng: RandomNumberGenerator) -> void:
	var at := []                          # [where the pole stands, how big]
	var palace := main.get_node_or_null("LunaPalace") as Node3D
	if palace and palace.has_meta("flag_tops"):
		var tops: PackedVector3Array = palace.get_meta("flag_tops")
		for k in tops.size():
			at.append([palace.global_transform * tops[k], 2.2 if k == 0 else 1.4])
	var face := main.get_node_or_null("SkLunaPark") as Node3D
	if face:
		var spike := SkLunaPark.CORNICE_Y + 0.6 + 2.7 + 7.0 * 0.32 + 2.4
		for s in [-1.0, 1.0]:
			at.append([face.global_transform * Vector3(s * SkLunaPark.TOWER_X, spike, -SkLunaPark.TOWER_D / 2.0), 1.6])
	for top in [["Carousel", 10.8], ["Supernova", SkLunaRides.NOVA_H + 1.5], ["ConeyDrop", SkLunaRides.CONEY_H + 1.4], ["ArabianMerry", 9.1]]:
		var n := main.get_node_or_null(String(top[0])) as Node3D
		if n:
			at.append([n.global_position + Vector3(0, float(top[1]), 0), 1.6])
	if at.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _flag_mesh()
	mm.instance_count = at.size()
	for k in at.size():
		var s: float = at[k][1]
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, WIND_YAW + rng.randf_range(-0.15, 0.15)).scaled(Vector3.ONE * s), at[k][0]))
		var c: Color = COLOURS[k % COLOURS.size()]
		mm.set_instance_custom_data(k, Color(c.r, c.g, c.b, rng.randf()))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Flags"
	mi.multimesh = mm
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## A flagpole 1.8 m tall (its foot at the origin) with a pennant streaming along +x from near its top. UV.x: 0 the
## pole, 1 the flag (for the shader).
static func _flag_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.035
	for f in [[Vector3(-w, 0, -w), Vector3(w, 0, -w)], [Vector3(w, 0, -w), Vector3(w, 0, w)], [Vector3(w, 0, w), Vector3(-w, 0, w)], [Vector3(-w, 0, w), Vector3(-w, 0, -w)]]:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		_quad(st, a, b, b + Vector3(0, 1.8, 0), a + Vector3(0, 1.8, 0), 0.0)
	# the pennant, in strips along it (so it can ripple)
	var steps := 6
	for i in steps:
		var x0 := 1.15 * i / steps
		var x1 := 1.15 * (i + 1) / steps
		var h0 := 0.28 * (1.0 - float(i) / steps)
		var h1 := 0.28 * (1.0 - float(i + 1) / steps)
		_quad(st, Vector3(x0, 1.5 - h0, 0), Vector3(x1, 1.5 - h1, 0), Vector3(x1, 1.5 + h1, 0), Vector3(x0, 1.5 + h0, 0), 1.0)
	st.generate_normals()
	return st.commit()

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, part: float) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_uv(Vector2(part, 0))
		st.add_vertex(p)

# ---------------------------------------------------------------- the bunting

func _bunting(main: Node, rng: RandomNumberGenerator) -> void:
	var posts := []
	for k in range(0, SkDayNight.lamps.size() - 1, 2):
		var mid: Vector3 = ((SkDayNight.lamps[k] as Vector3) + (SkDayNight.lamps[k + 1] as Vector3)) / 2.0
		posts.append(Vector3(mid.x, STRING_Y, mid.z))
	var swings := []
	for nm in SkCrowd.SWINGS:
		var ride := main.get_node_or_null(String(nm)) as Node3D
		if ride:
			swings.append([Vector2(ride.global_position.x, ride.global_position.z), float(SkCrowd.SWINGS[nm]) + 1.5])
	var space := get_world_3d().direct_space_state
	var strings := []
	var used := {}
	for i in posts.size():
		var near := []
		for j in posts.size():
			var d := (posts[i] as Vector3).distance_to(posts[j])
			if j != i and d > SPAN[0] and d < SPAN[1]:
				near.append([d, j])
		near.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		var made := 0
		for nj in near:
			if made >= 2:
				break
			var j: int = nj[1]
			var key := "%d-%d" % [mini(i, j), maxi(i, j)]
			if used.has(key):
				made += 1
				continue
			var a: Vector3 = posts[i]
			var b: Vector3 = posts[j]
			if not _clear(a, b, swings, space):
				continue
			used[key] = true
			strings.append([a, b])
			made += 1
	if strings.is_empty():
		return
	# the strings (thin dark ribbons) and the little flags along them
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flags := []                       # [where, which way along]
	for s in strings:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var n := int(a.distance_to(b) / PENNANT_EVERY)
		var prev := a
		for q in range(1, n + 1):
			var p := _hang(a, b, float(q) / n)
			_quad(st, prev, p, p + Vector3(0, 0.025, 0), prev + Vector3(0, 0.025, 0), 0.0)
			if q < n:
				flags.append([p, (b - a).normalized()])
			prev = p
	var line := MeshInstance3D.new()
	line.name = "BuntingStrings"
	line.mesh = st.commit()
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.12, 0.12, 0.13)
	lm.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.material_override = lm
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.visibility_range_end = 300.0
	add_child(line)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _pennant_mesh()
	mm.instance_count = flags.size()
	for k in flags.size():
		var along: Vector3 = flags[k][1]
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, atan2(-along.z, along.x)), flags[k][0]))
		var c: Color = COLOURS[k % COLOURS.size()]
		mm.set_instance_custom_data(k, Color(c.r, c.g, c.b, rng.randf()))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Bunting"
	mi.multimesh = mm
	var m := material().duplicate() as ShaderMaterial
	m.set_shader_parameter("pennant", 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 300.0
	add_child(mi)

## A point along a string from a to b (0..1), sagging in the middle.
static func _hang(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t) - Vector3(0, 4.0 * SAG * t * (1.0 - t), 0)

## Whether a string from a to b keeps clear of the moving rides' reach and of anything solid on the way.
static func _clear(a: Vector3, b: Vector3, swings: Array, space: PhysicsDirectSpaceState3D) -> bool:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for s in swings:
		var c: Vector2 = s[0]
		if Geometry2D.get_closest_point_to_segment(c, a2, b2).distance_to(c) < float(s[1]):
			return false
	var d := (b - a).normalized()
	for lift in [0.0, -SAG]:
		var from := a + d * 0.5 + Vector3(0, lift * 0.75, 0)
		var to := b - d * 0.5 + Vector3(0, lift * 0.75, 0)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, SkData.LAYER_WORLD)).is_empty():
			return false
	return true

## A little triangular flag hanging down from the string (its top edge along x at the origin).
static func _pennant_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(-0.17, 0, 0), Vector3(0.17, 0, 0), Vector3(0, -0.36, 0)]:
		st.set_uv(Vector2(1, 0))
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()

static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float pennant = 0.0;          // the bunting's little flags: swing on their string instead of streaming
varying vec3 tint;
void vertex() {
	float flag = step(0.5, UV.x);
	float ph = INSTANCE_CUSTOM.a * 6.283;
	if (pennant > 0.5) {
		// swinging about the string, each in its own time
		float a = sin(TIME * 5.5 + ph) * 0.35 + 0.15;
		float y = VERTEX.y;
		VERTEX.z = y * sin(a);
		VERTEX.y = y * cos(a);
	} else {
		// rippling, more toward the tip
		float along = max(VERTEX.x, 0.0) * flag;
		VERTEX.z += sin(TIME * 7.0 - along * 4.5 + ph) * 0.15 * along;
		VERTEX.y += sin(TIME * 5.0 - along * 3.0 + ph) * 0.03 * along;
	}
	tint = mix(vec3(0.82, 0.82, 0.8), INSTANCE_CUSTOM.rgb, flag);
}
void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.8;
}
"""
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat
