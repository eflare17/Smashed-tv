# (Copied from stkilda-godot scripts/world/impact_puff.gd by tools/stkilda_sync.sh: don't edit here, edit there and re-run.)
class_name SkImpactPuff
extends Node3D
## The smack where a bat lands (the owner's pick, 2026-10-31): a bright white flash that swells and fades in a blink,
## and a few little puffs bursting out from it, the way the bat was going, slowing and fading.

const FLASH := 0.08                     # s the flash lasts
const PUFFS := 7
const LIFE := 0.3

static var _ball: SphereMesh

var _t := 0.0
var _flash: MeshInstance3D
var _puffs: Array = []                  # [mesh, velocity]

## A puff at `at`, bursting mostly along `push` (the bat's way).
static func at_point(parent: Node, at: Vector3, push: Vector3, rng: RandomNumberGenerator) -> void:
	var p := SkImpactPuff.new()
	parent.add_child(p)
	p.global_position = at
	p.top_level = true
	p._flash = p._sphere(0.05, Color(1, 1, 1, 0.75))
	var dir := push.normalized() if push.length() > 0.01 else Vector3.UP
	for k in PUFFS:
		var v := (dir * rng.randf_range(0.5, 1.5) + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1))).normalized()
		p._puffs.append([p._sphere(rng.randf_range(0.015, 0.03), Color(1, 1, 1, 0.6)), v * rng.randf_range(1.5, 3.0)])

func _sphere(r: float, c: Color) -> MeshInstance3D:
	if _ball == null:
		_ball = SphereMesh.new()
		_ball.radius = 1.0
		_ball.height = 2.0
		_ball.radial_segments = 10
		_ball.rings = 5
	var mi := MeshInstance3D.new()
	mi.mesh = _ball
	mi.scale = Vector3.ONE * r
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	mi.material_override = m
	add_child(mi)
	return mi

func _process(dt: float) -> void:
	_t += dt
	var f := _t / FLASH
	if _flash:
		_flash.scale = Vector3.ONE * lerpf(0.05, 0.17, sqrt(minf(f, 1.0)))
		(_flash.material_override as StandardMaterial3D).albedo_color.a = 0.75 * (1.0 - minf(f, 1.0))
		if f >= 1.0:
			_flash.queue_free()
			_flash = null
	var g := minf(_t / LIFE, 1.0)
	for p in _puffs:
		var mi := p[0] as MeshInstance3D
		p[1] = (p[1] as Vector3) * exp(-dt * 6.0)
		mi.position += (p[1] as Vector3) * dt
		mi.scale *= 1.0 + dt * 1.2
		(mi.material_override as StandardMaterial3D).albedo_color.a = 0.6 * (1.0 - g)
	if _t >= LIFE:
		queue_free()
