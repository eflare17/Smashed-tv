# (Copied from stkilda-godot scripts/world/feather.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkFeather
extends MeshInstance3D
## An ibis's feather knocked out by the bat (the owner's idea, 2026-10-31: at least three pop out with every hit): it
## pops out, then flutters down, swaying side to side and rocking, lands flat on the ground, lies there a few seconds
## and shrinks away. White, a touch grey at the tip; now and then one of the dark ones off its back.

const LENGTH := 0.24                     # (bigger than a real one, so you can see them go)
const WIDTH := 0.075
const LIE := 5.0                        # s on the ground before it goes

static var _mesh: ArrayMesh
static var _white: StandardMaterial3D
static var _dark: StandardMaterial3D

var _vel := Vector3.ZERO
var _ground := 0.0
var _t := 0.0
var _phase := 0.0
var _sway := Vector3.RIGHT
var _spin := Vector3.UP
var _landed := -1.0

## `count` feathers popping out at `at`, mostly the way it was knocked (`away`), onto ground at height `ground`.
static func burst(parent: Node, at: Vector3, away: Vector3, count: int, ground: float, rng: RandomNumberGenerator) -> void:
	for k in count:
		var f := SkFeather.new()
		f.mesh = _feather_mesh()
		f.material_override = _material(rng.randf() < 0.2)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(f)
		f.global_position = at + Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1))
		f.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		var a := rng.randf() * TAU
		f._vel = away * rng.randf_range(0.5, 2.0) + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.8, 2.2) + Vector3.UP * rng.randf_range(2.0, 4.0)
		f._ground = ground + 0.02 + 0.002 * k
		f._phase = rng.randf() * TAU
		f._sway = Vector3(cos(a + 1.5), 0, sin(a + 1.5))
		f._spin = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(4.0, 9.0)

func _process(dt: float) -> void:
	_t += dt
	if _landed >= 0.0:
		_landed += dt
		if _landed > LIE:
			scale = Vector3.ONE * maxf(0.01, 1.0 - (_landed - LIE) / 0.6)
			if _landed > LIE + 0.6:
				queue_free()
		return
	# light, so the air stops it fast: it pops out, then drifts down slowly, swaying and rocking
	_vel.y -= 6.0 * dt
	_vel *= exp(-3.0 * dt)
	var drift := _sway * sin(_t * 5.0 + _phase) * 0.9 if _vel.y < 0.0 else Vector3.ZERO
	global_position += (_vel + drift) * dt
	if _vel.y > -0.2:
		rotate(_spin.normalized(), _spin.length() * dt)
	else:
		# (falling: tipping to and fro, mostly flat)
		var flat := Basis(Vector3.UP, _phase + _t * 0.6) * Basis(Vector3.RIGHT, -PI / 2.0 + sin(_t * 5.0 + _phase) * 0.6)
		global_basis = global_basis.orthonormalized().slerp(flat, minf(1.0, dt * 4.0))
	if global_position.y <= _ground:
		global_position.y = _ground
		global_basis = Basis(Vector3.UP, _phase) * Basis(Vector3.RIGHT, -PI / 2.0)
		_landed = 0.0

## A feather: a vane tapering to a tip either side of the quill, flat, along +y from its base.
static func _feather_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const N := 8
	var prev := []
	for i in N + 1:
		var y := LENGTH * float(i) / N
		var w := WIDTH * 0.5 * pow(sin(PI * clampf(float(i) / N * 0.92 + 0.08, 0.0, 1.0)), 0.7)
		var tint := Color.WHITE.lerp(Color("#bdb9b2"), pow(float(i) / N, 3.0))
		var row := [[Vector3(-w, y, 0), tint], [Vector3(0, y, 0.004), tint.darkened(0.08)], [Vector3(w, y, 0), tint]]
		if not prev.is_empty():
			for side in 2:
				for v in [prev[side], row[side], prev[side + 1], prev[side + 1], row[side], row[side + 1]]:
					st.set_color(v[1])
					st.set_normal(Vector3.BACK)
					st.add_vertex(v[0])
		prev = row
	_mesh = st.commit()
	return _mesh

static func _material(dark: bool) -> StandardMaterial3D:
	if _white == null:
		_white = StandardMaterial3D.new()
		_white.vertex_color_use_as_albedo = true
		_white.cull_mode = BaseMaterial3D.CULL_DISABLED
		_white.roughness = 0.9
		_dark = _white.duplicate() as StandardMaterial3D
		_dark.albedo_color = Color("#3a3634")
	return _dark if dark else _white
