class_name VoxelVacuum
extends Node3D
## The vacuum gun, sucking like Astroneer's terrain tool (the owner, 20 Oct): where you point (the floor, a wall, or
## up to RANGE out in the air) a see-through brush sphere shows; hold the click and the cubes inside it (and any
## cut-off piece) come loose at a steady rate and swirl up a beam into the nozzle (VoxelDebris does the cubes,
## VoxelSword.vacuum the pieces). The mouse wheel sizes the brush. Owned by the voxel session.

const RANGE := 6.5              # metres from the nozzle the brush can be
const R_MIN := 0.35
const R_MAX := 1.6

var arena: Node3D
var view: Node3D                # the gun in hand (first person), on the camera
var brush_r := 0.8
var _sphere: MeshInstance3D
var _smat: ShaderMaterial
var _beam: MeshInstance3D
var _t := 0.0
var _glow: MeshInstance3D       # the nozzle's light, brighter while sucking

func setup(arena_: Node3D, cam: Camera3D) -> void:
	arena = arena_
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF    # the brush and beam move every frame
	view = _model()
	cam.add_child(view)
	_sphere = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 48
	sm.rings = 24
	_sphere.mesh = sm
	_smat = ShaderMaterial.new()
	_smat.shader = Shader.new()
	_smat.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform float strength = 0.35;
void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	float bands = 0.5 + 0.5 * sin(UV.y * 60.0 + TIME * 8.0 * strength);
	ALBEDO = vec3(0.3, 1.0, 0.65) * (0.05 + rim * (0.9 + 0.5 * bands)) * strength;
}
"""
	_sphere.material_override = _smat
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sphere.top_level = true
	_sphere.visible = false
	add_child(_sphere)
	_beam = MeshInstance3D.new()
	_beam.mesh = ImmediateMesh.new()
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.vertex_color_use_as_albedo = true
	_beam.material_override = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	add_child(_beam)

## The mouse wheel: a bigger or smaller brush.
func wheel(up: bool) -> void:
	brush_r = clampf(brush_r * (1.12 if up else 1.0 / 1.12), R_MIN, R_MAX)

## Each frame: out (the gun in hand), sucking (the click held). Places the brush where it points and runs the suck.
func step(dt: float, out: bool, sucking: bool) -> void:
	_t += dt
	var top: bool = arena.top_down
	view.visible = out and not top
	var debris: VoxelDebris = arena.debris
	(_beam.mesh as ImmediateMesh).clear_surfaces()
	if not out:
		_sphere.visible = false
		debris.brush = Vector3.INF
		arena.sound.stop("vacuum")
		return
	var aimv := _aim()
	var nozzle: Vector3 = aimv[0]
	var at: Vector3 = aimv[1]
	_sphere.visible = true
	var pulse := 1.0 + (0.04 * sin(_t * 22.0) if sucking else 0.0)
	_sphere.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * brush_r * pulse), at)
	_smat.set_shader_parameter("strength", 0.9 if sucking else 0.3)
	if _glow:
		(_glow.material_override as StandardMaterial3D).emission_energy_multiplier = 4.0 if sucking else 1.2
	if sucking and arena.backpack_full():
		sucking = false               # (nowhere to put it: the HUD says so)
		arena.say("Backpack full: empty it into a chest (E at one)", 1.0)
	if not sucking:
		debris.brush = Vector3.INF
		arena.sound.stop("vacuum")
		return
	arena.sound.loop("vacuum", "vacuum_loop", null, -6.0)
	arena.stash.vac_brush(at, brush_r)     # (co-op: the same lying cubes go in the other game)
	debris.nozzle = nozzle
	debris.brush = at
	debris.brush_r = brush_r
	arena.pieces.vacuum(at, brush_r)
	arena._kick = maxf(arena._kick, 0.1 + randf() * 0.08)
	_draw_beam(nozzle, at)

# [nozzle, brush centre]: the brush goes where the aim meets the world (first person: the view's middle; top-down:
# the mouse on the floor), no further than RANGE from the nozzle
func _aim() -> Array:
	var cam: Camera3D = arena.cam
	var from: Vector3
	var dir: Vector3
	var nozzle: Vector3
	if arena.top_down:
		var mp := arena.get_viewport().get_mouse_position()
		from = cam.project_ray_origin(mp)
		dir = cam.project_ray_normal(mp)
		var pp: Vector3 = arena.player.global_position + Vector3(0, 1.0, 0)
		var flat := Vector3(from.x - pp.x, 0, from.z - pp.z)
		nozzle = pp + (flat.normalized() * -0.0)
	else:
		var bs := cam.global_transform.basis
		from = cam.global_position
		dir = -bs.z
		nozzle = from + bs * Vector3(0.12, -0.17, -0.62)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 40.0)
	q.exclude = [arena.player.get_rid()]
	q.collision_mask = 1
	var hit := arena.get_world_3d().direct_space_state.intersect_ray(q)
	var at: Vector3 = hit.position if not hit.is_empty() else from + dir * RANGE
	if arena.top_down:
		var pp2: Vector3 = arena.player.global_position + Vector3(0, 1.0, 0)
		nozzle = pp2 + Vector3(at.x - pp2.x, 0, at.z - pp2.z).normalized() * 0.4
	var off := at - nozzle
	if off.length() > RANGE:
		at = nozzle + off.normalized() * RANGE
	return [nozzle, at]

# the beam: three strands twisting from the nozzle out to the brush, and a faint core
func _draw_beam(a: Vector3, b: Vector3) -> void:
	var im: ImmediateMesh = _beam.mesh
	var ab := b - a
	var ax := ab.normalized()
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.95 else Vector3.RIGHT).normalized()
	var w := ax.cross(u)
	var segs := 32
	for k in 3:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in segs + 1:
			var s := float(i) / segs
			var ph := s * 14.0 - _t * 16.0 + k * TAU / 3.0
			var r := 0.015 + 0.13 * s
			im.surface_set_color(Color(0.4, 1.0, 0.7, 0.7 * (1.0 - s * 0.6)))
			im.surface_add_vertex(a + ab * s + (u * cos(ph) + w * sin(ph)) * r)
		im.surface_end()
	# the core: a thin ribbon facing the camera
	var cam: Camera3D = arena.cam
	var side := ax.cross((cam.global_position - a).normalized()).normalized() * 0.012
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in 2:
		var p := a if i == 0 else b
		var c := Color(0.5, 1.0, 0.75, 0.5 if i == 0 else 0.15)
		im.surface_set_color(c)
		im.surface_add_vertex(p - side)
		im.surface_set_color(c)
		im.surface_add_vertex(p + side)
	im.surface_end()

func _model() -> Node3D:
	var root := Node3D.new()
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.2, 0.45, 0.3)
	body.metallic = 0.4
	body.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.1)
	dark.roughness = 0.6
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.4, 1.0, 0.6)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 1.0, 0.5)
	glow.emission_energy_multiplier = 1.2
	for b in [[Vector3(0.12, 0.13, 0.42), Vector3(0, 0, 0), body], [Vector3(0.2, 0.2, 0.08), Vector3(0, 0, -0.25), dark],
			[Vector3(0.14, 0.14, 0.02), Vector3(0, 0, -0.295), glow], [Vector3(0.09, 0.2, 0.16), Vector3(0, 0.15, 0.06), body],
			[Vector3(0.05, 0.14, 0.06), Vector3(0, -0.12, 0.1), dark], [Vector3(0.06, 0.06, 0.2), Vector3(0, 0.15, 0.06), glow]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[0]
		mi.mesh = bm
		mi.position = b[1]
		mi.material_override = b[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		if b[2] == glow and _glow == null:
			_glow = mi
	root.position = Vector3(0.24, -0.23, -0.5)
	root.rotation = Vector3(0.05, 0.08, 0)
	root.scale = Vector3.ONE * 0.5
	root.visible = false
	return root
