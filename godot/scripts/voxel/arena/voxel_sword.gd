class_name VoxelSword
extends VoxelMelee
## The sword (the owner, 20 Oct): a slash is a flat sweep of the blade, the plane through your eye along where you
## look and the way you swing. Every cube the blade passes through is cut out (VoxelBody.slice), and whatever that
## leaves hanging comes off whole: an arm, half a forearm, a leg at the knee, the top of a head, the head. The bits
## that come off are real pieces (rigid bodies with their own meshes) that tumble, bounce and lie on the floor.
## A hit freezes the game for a blink (hit-stop) so the cut lands heavy. Left click slashes the way the mouse moves,
## right click chops down (top-down: a low sweep at the legs); F slashes with any weapon out (quick()). Owned by the
## voxel session.

const REACH := 2.6              # metres from the eye the blade reaches
const COS_ARC := 0.17           # the sweep: 80 degrees each side of where you look
const SWING_T := 0.2            # seconds a swing takes
const CUT_AT := 0.06            # seconds in when the blade passes through
const BACK_T := 0.18            # seconds back to rest after
const COOLDOWN := 0.38
const ARC := 1.35               # radians the blade sweeps each side

var _blade: Node3D
var _trail: MeshInstance3D
var _t := -1.0                  # seconds into the swing (-1: at rest)
var _eye := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _side := Vector3.RIGHT
var _n := Vector3.UP
var _apex := Vector3.ZERO       # where the swoosh fans out from (the hand, not the eye, so it isn't seen edge-on)
var _side_cam := Vector3.RIGHT  # the swing's direction in the camera's own space (for the blade in hand)
var _cut_done := false
var _cd := 0.0

func _build() -> void:
	_blade = Node3D.new()
	view.add_child(_blade)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.8, 0.85)
	steel.metallic = 0.9
	steel.roughness = 0.22
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.55, 0.42, 0.15)
	gold.metallic = 0.7
	gold.roughness = 0.4
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.22, 0.12, 0.07)
	grip.roughness = 0.9
	# a blocky sword like the rest: blade, guard, grip and pommel, held at the grip (the node's origin)
	_part(Vector3(0.045, 0.95, 0.01), Vector3(0, 0.6, 0), steel)
	_part(Vector3(0.02, 0.06, 0.012), Vector3(0, 1.1, 0), steel)
	_part(Vector3(0.2, 0.03, 0.04), Vector3(0, 0.11, 0), gold)
	_part(Vector3(0.035, 0.17, 0.035), Vector3(0, 0.01, 0), grip)
	_part(Vector3(0.055, 0.045, 0.055), Vector3(0, -0.09, 0), gold)
	_trail = MeshInstance3D.new()
	_trail.mesh = ImmediateMesh.new()
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.vertex_color_use_as_albedo = true
	_trail.material_override = tm
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.top_level = true
	add_child(_trail)
	_rest_pose()

func _part(size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blade.add_child(mi)

func ready_to_swing() -> bool:
	return _cd <= 0.0

## Mid-swing or on the way back (with another weapon out the blade shows only then).
func busy() -> bool:
	return _t >= 0.0

func cooling() -> float:
	return clampf(_cd / COOLDOWN, 0.0, 1.0)

func press(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		slash(swing_dir())
	elif button == MOUSE_BUTTON_RIGHT:
		slash(Vector2(0, 1), true)

## F: a slash with whatever weapon is out.
func quick(low: bool = false) -> void:
	slash(Vector2(0, 1) if low else swing_dir(), low)

## One slash, sv the way it goes on screen (x right, y down); low: right click (first person: straight down;
## top-down: a level sweep at the legs).
func slash(sv: Vector2, low: bool = false) -> void:
	if not ready_to_swing():
		return
	if top_down():
		var pp: Vector3 = arena.player.global_position
		var f := look()
		var e := pp + Vector3(0, 0.45 if low else 1.15, 0)
		var right := f.cross(Vector3.UP).normalized()
		var sx := signf(sv.x) if absf(sv.x) > 0.01 else 1.0
		var tilt := 0.0 if low else 0.3 * sx
		var side := (right * sx * cos(tilt) + Vector3.DOWN * sin(absf(tilt))).normalized()
		arena.avatar.attack = 0.5
		swing(e, f, side, e, Vector3(1, 0, 0))
		return
	var bs: Basis = arena.cam.global_transform.basis
	var side_cam := Vector3(sv.x, -sv.y, 0.0).normalized()
	var side2 := (bs * side_cam).normalized()
	var apex: Vector3 = arena.cam.global_position + bs * Vector3(0.05, -0.28, -0.1)
	swing(arena.cam.global_position, -bs.z, side2, apex, side_cam)

func hand_mesh() -> Node3D:
	var root := Node3D.new()
	box(root, Vector3(0.012, 0.05, 0.95), Vector3(0, 0, 0.6), mat(Color(0.78, 0.8, 0.85), 0.9, 0.22))
	box(root, Vector3(0.04, 0.2, 0.03), Vector3(0, 0, 0.11), mat(Color(0.55, 0.42, 0.15), 0.7, 0.4))
	box(root, Vector3(0.035, 0.035, 0.17), Vector3(0, 0, 0.01), mat(Color(0.22, 0.12, 0.07)))
	return root

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	for b in [[Rect2(0.4, 2.15, 1.6, 0.7), Color(0.55, 0.32, 0.18)], [Rect2(2.0, 1.2, 0.5, 2.6), Color(0.9, 0.75, 0.3)],
			[Rect2(2.5, 2.0, 6.6, 1.0), Color(1, 1, 1)], [Rect2(9.1, 2.2, 0.6, 0.6), Color(1, 1, 1)]]:
		var c: Color = b[1]
		ci.draw_rect(Rect2(r.position + (b[0] as Rect2).position * u, (b[0] as Rect2).size * u), Color(c.r, c.g, c.b, col.a))

func swinging() -> bool:
	return _t >= 0.0 and _t < SWING_T

## Starts a slash: from (the eye) along fwd, the blade travelling side (both world, at right angles); apex is where the
## swoosh is drawn from; side_cam is side in the camera's own space (the blade in hand follows it).
func swing(from: Vector3, fwd: Vector3, side: Vector3, apex: Vector3, side_cam: Vector3) -> void:
	_eye = from
	_fwd = fwd.normalized()
	_side = (side - _fwd * side.dot(_fwd)).normalized()
	_n = _fwd.cross(_side).normalized()
	_apex = apex
	_side_cam = side_cam.normalized()
	_t = 0.0
	_cut_done = false
	_cd = COOLDOWN

func step(dt: float) -> void:
	_cd = maxf(0.0, _cd - dt)
	if _t >= 0.0:
		_t += dt
		if not _cut_done and _t >= CUT_AT:
			_cut_done = true
			_cut()
		if _t >= SWING_T + BACK_T:
			_t = -1.0
	_pose_blade()
	_draw_trail()

# ---------------------------------------------------------------- the cut

func _cut() -> void:
	var t0 := Time.get_ticks_usec()
	var hit := false
	var res_all := {"cut": 0, "parts": [], "pieces": 0, "killed": false}
	for b in arena.bodies:
		var flat := Vector2(b.global_position.x - _eye.x, b.global_position.z - _eye.z)
		if flat.length() > REACH + 0.8:
			continue
		var ts := Time.get_ticks_usec()
		var r: Dictionary = b.slice(_eye, _n, _fwd, REACH, COS_ARC, b.vm * 0.9)
		res_all["slice_ms"] = snappedf((Time.get_ticks_usec() - ts) / 1000.0, 0.1)
		if int(r.cut) == 0 and (r.pieces as Array).is_empty():
			continue
		hit = true
		res_all.cut += int(r.cut)
		res_all.parts.append_array(r.parts)
		res_all.pieces += (r.pieces as Array).size()
		res_all.killed = res_all.killed or bool(r.killed)
		spray(r, _side, 2.2)
		# flung the way the blade went, a little up, spinning in the swing
		fling(b, r, _side * randf_range(1.6, 2.8) + Vector3.UP * randf_range(1.0, 2.2),
			_n * randf_range(4.0, 8.0) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)))
		if b.alive and not (r.parts as Array).is_empty():
			b.hit_react(_side, 30, String(r.parts[0]))
	res_all["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	last = res_all
	if hit:
		hit_stop()

# ---------------------------------------------------------------- the look

func _rest_pose() -> void:
	_blade.transform = Transform3D(Basis.from_euler(Vector3(-0.55, 0.25, -0.35)), Vector3(0.3, -0.32, -0.42))

# the blade in hand: at rest low on the right; in a swing it sweeps across the view along the swing, edge first
func _swing_xform(th: float) -> Transform3D:
	var f := Vector3(0, 0, -1)
	var s := _side_cam
	var nl := f.cross(s).normalized()
	var dir := (f * cos(th) + s * sin(th)).normalized()
	var tg := (-f * sin(th) + s * cos(th)).normalized()
	var bs := Basis(tg, dir, tg.cross(dir).normalized())
	var at := Vector3(0.06, -0.24, -0.12) - nl * 0.06 + dir * 0.12
	return Transform3D(bs, at)

func _pose_blade() -> void:
	if _t < 0.0:
		_rest_pose()
		return
	var rest := Transform3D(Basis.from_euler(Vector3(-0.55, 0.25, -0.35)), Vector3(0.3, -0.32, -0.42))
	if _t < SWING_T:
		var k := _t / SWING_T
		var th := lerpf(-ARC, ARC, k * k * (3.0 - 2.0 * k))
		var x := _swing_xform(th)
		# the first moment: from rest up into the wind-up
		var w := clampf(_t / 0.04, 0.0, 1.0)
		_blade.transform = rest.interpolate_with(x, w) if w < 1.0 else x
	else:
		var k2 := clampf((_t - SWING_T) / BACK_T, 0.0, 1.0)
		_blade.transform = _swing_xform(ARC).interpolate_with(rest, k2 * k2 * (3.0 - 2.0 * k2))

# the swoosh: a fan in the swing's plane from the hand, bright at the blade, fading behind it
func _draw_trail() -> void:
	var im: ImmediateMesh = _trail.mesh
	im.clear_surfaces()
	if _t < 0.0 or _t > SWING_T + 0.1:
		return
	var k := clampf(_t / SWING_T, 0.0, 1.0)
	var th1 := lerpf(-ARC, ARC, k * k * (3.0 - 2.0 * k))
	var fade := 1.0 - clampf((_t - SWING_T) / 0.1, 0.0, 1.0)
	var th0 := maxf(-ARC, th1 - 1.6)
	var steps := 14
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in steps + 1:
		var th := lerpf(th0, th1, float(i) / steps)
		var a := float(i) / steps
		var dir := (_fwd * cos(th) + _side * sin(th)).normalized()
		var c := Color(0.9, 0.95, 1.0, 0.45 * a * a * fade)
		im.surface_set_color(c)
		im.surface_add_vertex(_apex + dir * 0.45)
		im.surface_set_color(Color(c.r, c.g, c.b, c.a * 0.3))
		im.surface_add_vertex(_apex + dir * (REACH * 0.85))
	im.surface_end()
