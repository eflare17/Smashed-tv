class_name VoxelMeleeBat
extends VoxelMelee
## The baseball bat (the owner, 20 Oct: five melee weapons, each doing something different). Blunt: it never cuts,
## it knocks them flying. Left click is a quick level swing (wind-up, sweep, follow-through): the nearest body in the
## arc in front takes a dent where the bat lands (the cubes there fly out), loses some health and is sent flying off
## the way the bat went and back, tumbling, to lie there a moment and get up. A head hit dents deeper and hurts more.
## Hold right click to wind up a home run (the bat goes further back and glows; at full charge it shakes); let go and
## it swings as hard as it was wound: faster, further, harder, a longer hit-stop and a bigger kick. A full charge
## hits everyone in the arc, and a full-charge hit on the head knocks the head clean off (it sails away on its own)
## while the body flies too. First person the bat rests on your right shoulder; top-down it's in Jared's right hand
## and sweeps round him at chest height, or at the head with the mouse on the top of a head. The core (where the bat
## lands, what the blow does) is static so the logic test can run it.
## Owned by the voxel session.

const REACH := 2.3              # metres from the eye (top-down: the chest) the bat reaches
const COS_ARC := 0.342          # the arc in front it covers: 70 degrees each side
const SCALE_FP := 0.0135        # metres a voxel of the bat, first person
const SCALE_HAND := 0.0125      # top-down, in Jared's hand
const BAT_LEN := 40.0           # voxels from the grip to the end of the barrel
# the quick swing (left click), seconds
const WIND_T := 0.07
const ARC_T := 0.22
const BACK_T := 0.2
const COOLDOWN := 0.45
# the home run (right click)
const CHARGE_T := 0.95          # seconds held to a full charge
const WEAK_T := 0.15            # let go sooner than this: a weak swing
const HR_COOLDOWN := 0.7
# the blow
const DENT_R := 0.07            # metres: the ball knocked out where the bat lands
const DENT_R_HEAD := 0.1
const DAMAGE := 12.0
const DAMAGE_HEAD := 22.0
const NECK_R := 0.09            # the home run's ball round the neck joint (the head comes off whole)
const HEAD_V := 18.0            # m/s the head flies off at
const SIDE_V := 3.0             # the launch (m/s): along the swing, away from you, up; times the swing's force
const FWD_V := 5.0
const UP_V := 3.0
const SPIN := 7.0               # radians a second, tumbling
# rays round the aim (radians across the arc, up / down) tried in turn for where the bat lands
const FAN := [Vector2(0, 0), Vector2(0, -0.1), Vector2(0, 0.1), Vector2(-0.1, 0), Vector2(0.1, 0), Vector2(0, -0.2),
	Vector2(-0.1, -0.1), Vector2(0.1, -0.1), Vector2(0, 0.2), Vector2(-0.2, 0), Vector2(0.2, 0), Vector2(0, -0.32),
	Vector2(0, -0.45)]
# the bat's poses: th degrees round from straight ahead toward the right, ph degrees up; grips in camera space
const REST_TH := 140.0          # at rest: up and back over the right shoulder
const REST_PH := 62.0
const REST_GRIP := Vector3(0.27, -0.4, -0.62)
const WIND_TH := 120.0          # wound up: back to the right, raised
const WIND_PH := 45.0
const CONTACT_PH := 4.0         # level as it passes in front
const END_TH := -140.0          # followed through: round to the left, over the left shoulder (clear of your head)
const END_PH := 30.0
const HR_END_TH := -150.0
const HR_END_PH := 32.0
const PIVOT := Vector3(0.04, -0.3, -0.38)   # the hands go round this in a swing
const RADIUS := 0.24
const CHARGE_TH0 := 135.0       # charging: raised up behind the right shoulder, further back and higher as it charges
const CHARGE_TH1 := 165.0
const CHARGE_PH0 := 50.0
const CHARGE_PH1 := 64.0
const CHARGE_GRIP0 := Vector3(0.26, -0.3, -0.42)
const CHARGE_GRIP1 := Vector3(0.33, -0.17, -0.38)

const IDLE := 0
const SWING := 1
const CHARGE := 2

var _rig: Node3D                # the bat in hand, first person (posed in camera space, under view)
var _bat_mat: StandardMaterial3D
var _hand_mat: StandardMaterial3D  # top-down: lighter, to show on the dark floor from up there
var _hand_bat: ArrayMesh
var _hand: Node3D               # top-down: the bat's pivot in Jared's hand (freed with it)
var _trail: MeshInstance3D
var _flash: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _flash_t := -1.0
var _flash_size := 0.3
var _mode := IDLE
var _t := 0.0                   # seconds into the swing
var _th := REST_TH              # the pose now
var _ph := REST_PH
var _grip := REST_GRIP
var _from_th := 0.0             # the pose the swing started from
var _from_ph := 0.0
var _from_grip := Vector3.ZERO
var _wind_t := WIND_T           # this swing's timing and arc
var _arc_t := ARC_T
var _back_t := BACK_T
var _th0 := WIND_TH
var _ph0 := WIND_PH
var _th1 := END_TH
var _ph1 := END_PH
var _hr := false                # a home run (right click)
var _power := 0.0               # its charge, 0.3 .. 1
var _full := false
var _struck := false
var _charge := 0.0              # seconds wound up
var _want_charge := false       # right click down, waiting for the last swing to finish
var _buffer := 0.0              # a left click a moment early: swings as soon as it can
var _cd := 0.0
var _cd_max := COOLDOWN
var _clock := 0.0
var _shake := Vector3.ZERO
var _queue := []                # a full home run's other bodies, still to take it: [body, hit, v, side, force, full]

func _build() -> void:
	_bat_mat = StandardMaterial3D.new()
	_bat_mat.vertex_color_use_as_albedo = true
	_bat_mat.vertex_color_is_srgb = true
	_bat_mat.albedo_color = Color(1.35, 1.3, 1.25)
	_bat_mat.roughness = 0.8
	_bat_mat.emission_enabled = true
	_bat_mat.emission = Color(1.0, 0.58, 0.2)
	_bat_mat.emission_energy_multiplier = 0.0
	_hand_mat = _bat_mat.duplicate()
	_hand_mat.albedo_color = Color(2.0, 1.9, 1.75)
	_rig = Node3D.new()
	view.add_child(_rig)
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelArena._gun_mesh("bat", SCALE_FP)
	mi.material_override = _bat_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(mi)
	_hand_bat = VoxelArena._gun_mesh("bat", SCALE_HAND)
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
	# the knock: a ring of air thrown out where the bat lands, facing you
	_flash = MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.8
	rm.outer_radius = 1.0
	rm.rings = 24
	rm.ring_segments = 6
	_flash.mesh = rm
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1.0, 0.85, 0.6, 0.0)
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.top_level = true
	_flash.visible = false
	# moved in _process: interpolated between physics ticks it would slide in from the last spot (slowly, in a hit-stop)
	_flash.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_flash)
	_apply_pose()

# ---------------------------------------------------------------- the buttons

func ready_to_swing() -> bool:
	return _cd <= 0.0 and _mode != CHARGE

## Mid-swing or winding up.
func busy() -> bool:
	return _mode != IDLE

func cooling() -> float:
	return clampf(_cd / maxf(_cd_max, 0.01), 0.0, 1.0)

func press(button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		if _mode == CHARGE:
			return
		if ready_to_swing():
			_start_swing(false, 0.0)
		elif _cd < 0.15:
			_buffer = 0.15
	elif button == MOUSE_BUTTON_RIGHT:
		_want_charge = true
		if ready_to_swing():
			_begin_charge()

func hold(button: int, _dt: float) -> void:
	# a right click held through the last swing starts winding up once it's done
	if button == MOUSE_BUTTON_RIGHT and _want_charge and _mode != CHARGE and ready_to_swing():
		_begin_charge()

func release(button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	_want_charge = false
	if _mode != CHARGE:
		return
	if shooter.weapon != "bat":
		# put away wound up: no swing
		_mode = IDLE
		_charge = 0.0
		return
	var c := clampf(_charge / CHARGE_T, 0.0, 1.0)
	_start_swing(true, 0.3 if _charge < WEAK_T else lerpf(0.3, 1.0, c))

func on_select() -> void:
	_th = REST_TH
	_ph = REST_PH
	_grip = REST_GRIP

func on_deselect() -> void:
	if _mode == CHARGE:
		_mode = IDLE
		_charge = 0.0
	_want_charge = false
	_buffer = 0.0

func _begin_charge() -> void:
	_mode = CHARGE
	_charge = 0.0
	# from wherever the last swing's way back left it (round behind you): on round, not back across the front
	_th = fposmod(_th, 360.0)

## Starts a swing from the pose it's in: the quick one (left), or a home run at power (0.3 .. 1).
func _start_swing(hr: bool, power: float) -> void:
	if arena:
		sfx("swoosh_bat", Vector3.INF, 0.0, 1.1 - 0.2 * power)
	_mode = SWING
	_t = 0.0
	_struck = false
	_hr = hr
	_power = power
	_full = hr and power >= 0.999
	_from_th = fposmod(_th, 360.0)        # on the right or behind: it sweeps from there round the front
	_from_ph = _ph
	_from_grip = _grip
	if hr:
		# already wound up: straight into the sweep, faster the harder
		_wind_t = 0.0
		_th0 = _from_th
		_ph0 = _ph
		_th1 = HR_END_TH
		_ph1 = HR_END_PH
		_arc_t = lerpf(0.26, 0.19, power)
		_back_t = 0.3
		_cd = HR_COOLDOWN
	else:
		_wind_t = WIND_T
		_th0 = WIND_TH
		_ph0 = WIND_PH
		_th1 = END_TH
		_ph1 = END_PH
		_arc_t = ARC_T
		_back_t = BACK_T
		_cd = COOLDOWN
	_cd_max = _cd
	_buffer = 0.0
	if arena != null and top_down():
		shooter.avatar.attack = 0.5

func step(dt: float) -> void:
	_clock += dt
	_flash_step(dt)
	if not _queue.is_empty():
		var q: Array = _queue.pop_front()
		if is_instance_valid(q[0]):
			_land(q[0], q[1], q[2], q[3], q[4], q[5])
	_cd = maxf(0.0, _cd - dt)
	if _buffer > 0.0:
		_buffer -= dt
		if ready_to_swing():
			_start_swing(false, 0.0)
	_shake = Vector3.ZERO
	var glow := 0.0
	match _mode:
		SWING:
			_t += dt
			var p := _swing_pose(_t)
			_th = p[0]
			_ph = p[1]
			_grip = p[2]
			if not _struck and _t >= _wind_t and (_th <= 0.0 or _t >= _wind_t + _arc_t):
				_struck = true
				_strike()
			if _t >= _wind_t + _arc_t + _back_t:
				_mode = IDLE
				_th = wrapf(_th, -180.0, 180.0)
			glow = 0.6 * _power * _power * clampf(1.0 - (_t - _wind_t - _arc_t) / 0.15, 0.0, 1.0) if _hr else 0.0
		CHARGE:
			_charge = minf(CHARGE_T, _charge + dt)
			var c := _charge / CHARGE_T
			var k := 1.0 - exp(-dt * 14.0)
			_th = lerpf(_th, lerpf(CHARGE_TH0, CHARGE_TH1, c), k)
			_ph = lerpf(_ph, lerpf(CHARGE_PH0, CHARGE_PH1, c), k)
			_grip = _grip.lerp(CHARGE_GRIP0.lerp(CHARGE_GRIP1, c), k)
			glow = 0.04 + 0.3 * c * c
			if c >= 1.0:
				# full: it shakes and the glow throbs
				_shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.007
				glow += 0.12 + 0.12 * sin(_clock * 40.0)
		_:
			var k2 := 1.0 - exp(-dt * 16.0)
			_th = lerpf(_th, REST_TH, k2)
			_ph = lerpf(_ph, REST_PH, k2)
			_grip = _grip.lerp(REST_GRIP + Vector3(0, 0.004 * sin(_clock * 1.8), 0), k2)
	_bat_mat.emission_energy_multiplier = glow
	_hand_mat.emission_energy_multiplier = glow * 2.0
	_apply_pose()
	_draw_trail()

# ---------------------------------------------------------------- the blow

func _strike() -> void:
	var t0 := Time.get_ticks_usec()
	var from := eye()
	if top_down():
		var pp: Vector3 = shooter.player.global_position
		var mr: Array = shooter.mouse_ray()
		from.y = pp.y + swing_height(arena.bodies, mr[0], mr[1], pp) if not mr.is_empty() else from.y
	var bs := frame()
	var fwd := look()
	var side := bs.x
	var force := 3.0 * _power if _hr else 1.0
	var list := targets(arena.bodies, from, fwd, side, _full)
	var t1 := Time.get_ticks_usec()
	last = {"swing": "R" if _hr else "L", "power": snappedf(_power, 0.01) if _hr else 1.0, "full": _full,
		"hits": list.size(), "parts": [], "cubes": 0, "pieces": 0, "head_off": false, "killed": 0, "v": 0.0, "carve_ms": 0.0}
	# the nearest takes it now; a full home run's others one a frame after (a carve costs ms; the hit-stop hides it)
	for i in list.size():
		var e: Array = list[i]
		var v := push_velocity(fwd, side, force)
		if i == 0:
			_land(e[0], e[1], v, side, force, _full)
		else:
			_queue.append([e[0], e[1], v, side, force, _full])
	last["trace_ms"] = snappedf((t1 - t0) / 1000.0, 0.01)
	last["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	if list.is_empty():
		return
	# the blow lands: a freeze, a kick, a puff, harder the harder the swing
	var p01 := clampf((_power - 0.3) / 0.7, 0.0, 1.0) if _hr else 0.0
	if _hr:
		hit_stop(0.14 if bool(last.head_off) else lerpf(0.07, 0.12, p01), 0.02 if _full else 0.05)
		shooter.kick = maxf(float(shooter.kick), 0.8 + 1.2 * p01)
	else:
		hit_stop(0.06, 0.05)
		shooter.kick = maxf(float(shooter.kick), 0.7)
	_flash.global_position = (list[0][1] as Dictionary).point
	_flash_size = 0.3 + 0.35 * p01
	_flash_t = 0.0
	_flash.visible = true
	_flash_mat.albedo_color = Color(1.0, 0.9, 0.75, 0.6) if not _full else Color(1.0, 0.75, 0.4, 0.8)
	_flash_step(0.0)

# one body takes the blow (blow's), then the cubes knocked out and any head fly; what it did is added to last
func _land(b: VoxelBody, h: Dictionary, v: Vector3, side: Vector3, force: float, full: bool) -> void:
	sfx("home_run" if full else "thwack", h.get("point", b.global_position), 3.0 if full else 0.0)
	var r := blow(b, h, v, SPIN + 3.0 * (force - 1.0), force, full)
	var res: Dictionary = r.res
	last.parts.append(String(h.part))
	last.cubes += int(r.cubes)
	last.pieces += (res.pieces as Array).size()
	last.head_off = bool(last.head_off) or bool(r.head_off)
	last.killed += 1 if bool(r.killed) else 0
	last.v = snappedf(v.length(), 0.1)
	last.carve_ms = snappedf(float(last.carve_ms) + float(r.ms), 0.01)
	var flat_f := Vector3.UP.cross(side).normalized()
	var travel := -side
	# the cubes knocked out fly on with the bat
	spray(res, (travel * 0.55 + flat_f * 0.8 + Vector3.UP * 0.25).normalized(), 2.2 + 1.3 * force)
	if bool(r.head_off):
		# the head sails off on its own, far
		fling(b, res, (flat_f * 0.8 + Vector3.UP * 0.55 + travel * 0.3).normalized() * HEAD_V,
			side * randf_range(10.0, 16.0) + Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)))
	else:
		fling(b, res, v * 0.8, Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)))

## Top-down: how high the bat swings (metres off the floor) for the mouse's ray from o along d: at the head when the
## first body in reach of pp the ray meets is met on the top half of its head (the crown, as seen from up there; lower
## down, the chin hides the chest), else at the chest.
static func swing_height(list: Array, o: Vector3, d: Vector3, pp: Vector3) -> float:
	var best := INF
	var y := 1.15
	for b in list:
		if not is_instance_valid(b) or Vector2(b.global_position.x - pp.x, b.global_position.z - pp.z).length() > REACH + 0.5:
			continue
		var h: Dictionary = b.trace(o, d, 40.0)
		if h.is_empty() or float(h.dist) >= best:
			continue
		best = float(h.dist)
		y = 1.15
		if String(h.part) == "head":
			var hc := part_centre(b, "head")
			if (h.point as Vector3).y >= hc.y:
				y = hc.y - pp.y
	return y

## Who the bat hits swinging from `from` round fwd (where you look; side: your right): [[body, hit], ...] nearest
## first, only the nearest unless all (a full home run hits everyone in the arc). Hits in the swing's own fan of rays
## come before ones found aiming straight at a body's middle (one lying down or in the air).
static func targets(list: Array, from: Vector3, fwd: Vector3, side: Vector3, all: bool) -> Array:
	var found := []
	for b in list:
		if not is_instance_valid(b):
			continue
		var h := strike_point(b, from, fwd, side)
		if not h.is_empty():
			found.append([int(h.tier) * 100.0 + float(h.dist), b, h])
	found.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var out := []
	for f in found:
		out.append([f[1], f[2]])
		if not all:
			break
	return out

## Where the bat lands on b ({} if b isn't in the arc within reach): trace's hit plus dir (the ray's way) and tier
## (0: on the swing's fan of rays, 1: aimed at one of its middle parts).
static func strike_point(b: VoxelBody, from: Vector3, fwd: Vector3, side: Vector3, reach: float = REACH,
		cos_arc: float = COS_ARC) -> Dictionary:
	if b.skeleton == null:
		return {}
	var flat_f := Vector3.UP.cross(side).normalized()
	var lv := b.global_position - from
	lv.y = 0.0
	var d := lv.length()
	if d > reach + 0.35:
		return {}
	var lim := acos(cos_arc)
	if d > 0.3 and acos(clampf(lv.dot(flat_f) / d, -1.0, 1.0)) > lim + atan2(0.35, d):
		return {}
	# the swing's plane: through the eye, along where you look and across; first the look swung round to b
	var f := fwd.normalized()
	var s := (side - f * side.dot(f)).normalized()
	var u := s.cross(f).normalized()
	var to := b.global_position - from
	var a0 := atan2(to.dot(s), to.dot(f))
	for o in FAN:
		var off: Vector2 = o
		var a := clampf(a0 + off.x, -lim, lim)
		var dir := ((f * cos(a) + s * sin(a)) * cos(off.y) + u * sin(off.y)).normalized()
		var h := b.trace(from, dir, reach)
		if not h.is_empty():
			h["dir"] = dir
			h["tier"] = 0
			return h
	# then straight at its middle parts
	for n in ["torso", "head", "thigh_l", "thigh_r"]:
		if not b.parts.has(n) or bool(b.parts[n].gone):
			continue
		var dv := part_centre(b, n) - from
		if dv.length() > reach + 0.2:
			continue
		var dl := Vector3(dv.x, 0.0, dv.z)
		if dl.length() > 0.3 and dl.normalized().dot(flat_f) < cos_arc:
			continue
		var h2 := b.trace(from, dv.normalized(), reach + 0.3)
		if not h2.is_empty():
			h2["dir"] = dv.normalized()
			h2["tier"] = 1
			return h2
	return {}

## What the bat does landing on b at hit (strike_point's): a dent there (the cubes knocked out), health off, and b
## sent flying at push (m/s) tumbling at spin. force: 1 a quick swing, up to 3 a full home run (a bigger dent, more
## damage); full: a home run, which on the head knocks the head clean off (a ball at the neck joint: the whole head
## comes away as a piece). Returns {res: carve's result, cubes, part, head_off, killed, ms}.
static func blow(b: VoxelBody, hit: Dictionary, push: Vector3, spin: float, force: float, full: bool) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var part := String(hit.part)
	var head := part == "head"
	var res := {}
	if head and full and b.parts.has("head") and not bool(b.parts.head.gone):
		var neck := neck_point(b)
		res = b.carve(neck, neck, NECK_R, 0.08, 1)
	if res.is_empty() or not bool(res.head_off):
		var r := (DENT_R_HEAD if head else DENT_R) * (1.0 + 0.25 * (force - 1.0))
		var c: Vector3 = (hit.point as Vector3) + (hit.dir as Vector3) * r * 0.35
		var dent := b.carve(c, c, r, 0.08, 2)
		if res.is_empty():
			res = dent
		else:
			res.bits.append_array(dent.bits)
			res.cut = int(res.cut) + int(dent.cut)
			res.pieces.append_array(dent.pieces)
			res.killed = bool(res.killed) or bool(dent.killed)
			res.head_off = bool(res.head_off) or bool(dent.head_off)
	var dmg := (DAMAGE_HEAD if head else DAMAGE) * (0.35 + 0.65 * force)
	var killed := bool(res.killed)
	if b.alive:
		killed = b.hurt(dmg) or killed
	b.launch(push, spin)
	return {"res": res, "cubes": int(res.cut), "part": part, "head_off": bool(res.head_off), "killed": killed,
		"ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)}

## The launch: along the swing (right to left), away from you, up; force times (a home run goes more straight out).
static func push_velocity(fwd: Vector3, side: Vector3, force: float) -> Vector3:
	var flat_f := Vector3.UP.cross(side).normalized()
	if flat_f.length() < 0.5:
		flat_f = Vector3(fwd.x, 0.0, fwd.z).normalized()
	return (-side * SIDE_V * (1.0 - 0.15 * (force - 1.0)) + flat_f * FWD_V + Vector3.UP * UP_V) * force

## The neck joint in the world (the head's bone).
static func neck_point(b: VoxelBody) -> Vector3:
	var hb := b.model.bone("head")
	return b.skeleton.global_transform * b.skeleton.get_bone_global_pose(hb).origin

## The middle of a part's grid in the world.
static func part_centre(b: VoxelBody, n: String) -> Vector3:
	var p: Dictionary = b.parts[n]
	var bi: int = p.bone
	var bind := Transform3D(Basis.IDENTITY, -b.model.bone_pivot[bi] * b.model.voxel_m)
	var m := b.skeleton.global_transform * b.skeleton.get_bone_global_pose(bi) * bind
	return m * ((Vector3(p.origin) + Vector3(p.grid.size) * 0.5) * b.vm)

# ---------------------------------------------------------------- the look

## The pose t seconds into the swing: [th, ph, grip]. Wind-up from where it was, the sweep round the hands' circle
## (slow, fast through the middle, slowing into the follow-through), then on round behind you, low across the
## shoulders, back up to the right shoulder (not back across the front, and never through your head).
func _swing_pose(t: float) -> Array:
	if t < _wind_t:
		var s := smoothstep(0.0, 1.0, t / _wind_t)
		return [lerpf(_from_th, _th0, s), lerpf(_from_ph, _ph0, s), _from_grip.lerp(_arc_grip(_th0, _ph0), s)]
	var u := (t - _wind_t) / _arc_t
	if u < 1.0:
		var e := u * u * (3.0 - 2.0 * u)
		var th := lerpf(_th0, _th1, e)
		var ph := _arc_ph(th)
		var g := _arc_grip(th, ph)
		if _wind_t <= 0.0:
			g = _from_grip.lerp(g, smoothstep(0.0, 0.35, u))
		return [th, ph, g]
	var k := clampf((t - _wind_t - _arc_t) / _back_t, 0.0, 1.0)
	var s2 := k * k * (3.0 - 2.0 * k)
	var dip := sin(PI * s2)
	return [lerpf(_th1, REST_TH - 360.0, s2), lerpf(_ph1, REST_PH, s2) - 30.0 * dip,
		_arc_grip(_th1, _ph1).lerp(REST_GRIP, s2) + Vector3(0, -0.2, -0.05) * dip]

# the bat's lift on the sweep: raised wound up, level through the middle, up again following through
func _arc_ph(th: float) -> float:
	if th >= 0.0:
		return lerpf(CONTACT_PH, _ph0, clampf(th / maxf(_th0, 1.0), 0.0, 1.0))
	return lerpf(CONTACT_PH, _ph1, clampf(th / minf(_th1, -1.0), 0.0, 1.0))

# the hands on their circle, higher the more the bat is raised
static func _arc_grip(th: float, ph: float) -> Vector3:
	var a := deg_to_rad(th)
	return PIVOT + Vector3(RADIUS * sin(a), 0.15 * sin(deg_to_rad(ph)), -RADIUS * cos(a))

# the way the bat points at th, ph, in camera space (x right, y up, -z ahead)
static func _dir(th: float, ph: float) -> Vector3:
	var a := deg_to_rad(th)
	var e := deg_to_rad(ph)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))

# how near the bat's axis comes to the eye posed at th, ph with the hands at grip, metres
static func _clearance(th: float, ph: float, grip: Vector3) -> float:
	return Geometry3D.get_closest_point_to_segment(Vector3.ZERO, grip, grip + _dir(th, ph) * BAT_LEN * SCALE_FP).length()

# the bat along z (its top up as near as it can be)
static func _bat_basis(z: Vector3) -> Basis:
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x).normalized(), z)

func _apply_pose() -> void:
	var dc := _dir(_th, _ph)
	if _rig:
		_rig.transform = Transform3D(_bat_basis(dc), _grip + _shake)
	if _hand != null and is_instance_valid(_hand):
		# the hand's weapon space: +z out of the fist (ahead), +y up, -x his right
		_hand.transform = Transform3D(_bat_basis(Vector3(-dc.x, dc.y, -dc.z)), _shake)

func hand_mesh() -> Node3D:
	var root := Node3D.new()
	_hand = Node3D.new()
	root.add_child(_hand)
	var mi := MeshInstance3D.new()
	mi.mesh = _hand_bat
	mi.material_override = _hand_mat
	_hand.add_child(mi)
	_apply_pose()
	return root

func hand_pose() -> String:
	return "spud"

func draw_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var u := r.size / Vector2(10, 5)
	var wood := Color(0.8, 0.58, 0.34, col.a)
	var tape := Color(0.3, 0.26, 0.24, col.a)
	for bx in [[Rect2(0.3, 1.85, 0.5, 1.3), tape], [Rect2(0.8, 2.15, 2.0, 0.7), tape], [Rect2(2.8, 2.1, 1.7, 0.8), wood],
			[Rect2(4.5, 1.9, 1.6, 1.2), wood], [Rect2(6.1, 1.6, 3.3, 1.8), wood], [Rect2(9.4, 1.75, 0.35, 1.5), wood]]:
		ci.draw_rect(Rect2(r.position + (bx[0] as Rect2).position * u, (bx[0] as Rect2).size * u), bx[1])

# the swoosh: the sweep the bat has just made (first person: the bat's own sweep; top-down: wider, level round the
# hand, out toward its reach), bright at the bat, fading behind it
func _draw_trail() -> void:
	var im: ImmediateMesh = _trail.mesh
	im.clear_surfaces()
	if _mode != SWING or _t < _wind_t:
		return
	var after := _t - _wind_t - _arc_t
	if after > 0.08:
		return
	var fade := 1.0 - clampf(after / 0.08, 0.0, 1.0)
	var th_now := _th if after <= 0.0 else _th1
	var span := 95.0 if not _hr else 130.0
	var col := Color(1.0, 0.95, 0.85, 0.36) if not _hr else Color(1.0, 0.72, 0.35, 0.45 + 0.35 * _power)
	var xf: Transform3D
	var td := top_down()
	if td:
		if _hand == null or not is_instance_valid(_hand) or not _hand.is_inside_tree():
			return
		xf = (_hand.get_parent() as Node3D).global_transform
		# level round the hand, whatever the hand's tilt
		xf = Transform3D(frame(), xf.origin)
	else:
		xf = view.global_transform
	var steps := 12
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in steps + 1:
		var th := minf(_th0, th_now + span * float(i) / steps)
		var w := 1.0 - float(i) / steps
		var a := deg_to_rad(th)
		var c := Color(col.r, col.g, col.b, col.a * w * w * fade)
		var p0: Vector3
		var p1: Vector3
		if td:
			var dl := Vector3(sin(a), 0.0, -cos(a))
			p0 = dl * 0.3
			p1 = dl * 1.5
		else:
			var g := _arc_grip(th, _arc_ph(th))
			var dc := _dir(th, _arc_ph(th))
			# the barrel's sweep, brightest at the end (it moves fastest)
			var blen := BAT_LEN * SCALE_FP
			p0 = g + dc * blen * 0.5
			p1 = g + dc * blen * 1.06
		im.surface_set_color(Color(c.r, c.g, c.b, c.a * (1.0 if td else 0.15)))
		im.surface_add_vertex(xf * p0)
		im.surface_set_color(Color(c.r, c.g, c.b, c.a * (0.35 if td else 1.0)))
		im.surface_add_vertex(xf * p1)
	im.surface_end()

func _flash_step(dt: float) -> void:
	if _flash_t < 0.0:
		return
	_flash_t += dt
	var k := _flash_t / 0.16
	if k >= 1.0:
		_flash_t = -1.0
		_flash.visible = false
		return
	# the ring's axis toward the camera, growing and fading
	var at := _flash.global_position
	var cam_at: Vector3 = shooter.cam.global_position
	var ax := (cam_at - at).normalized()
	var x := ax.cross(Vector3.UP)
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var sc := lerpf(0.08, _flash_size, sqrt(k))
	_flash.global_transform = Transform3D(Basis(x, ax, x.cross(ax)) * sc, at)
	var c := _flash_mat.albedo_color
	_flash_mat.albedo_color = Color(c.r, c.g, c.b, (0.8 if _full else 0.6) * (1.0 - k))

# ---------------------------------------------------------------- checks

static func _grunt(host: Node, at: Vector3 = Vector3.ZERO) -> VoxelBody:
	var b := VoxelBody.new()
	host.add_child(b)
	b.setup("grunt", 0.023, 1, StandardMaterial3D.new())
	b.position = at
	b.animate(0.0, false)
	return b

## The logic test's checks: where the bat lands, what a swing and a home run do to a grunt.
static func checks(host: Node) -> Array:
	var out := []
	var was := VoxelBody.immortal
	VoxelBody.immortal = false
	var fwd := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0)
	# a quick swing at the chest from 1.4 m
	var b := _grunt(host)
	var h := strike_point(b, Vector3(0, 1.1, 1.4), fwd, side)
	out.append([not h.is_empty() and String(h.part) != "head", "a level swing at the chest lands on his body (%s)" % h.get("part", "nothing")])
	var v1 := push_velocity(fwd, side, 1.0)
	if not h.is_empty():
		var hp0 := b.hp
		var r := blow(b, h, v1, SPIN, 1.0, false)
		out.append([int(r.cubes) >= 15 and b.hp <= hp0 - 12.0, "it dents him (%d cubes out) and hurts (%.0f off)" % [int(r.cubes), hp0 - b.hp]])
		out.append([b.airborne and b.air_v.z < -3.0 and b.air_v.x < -1.5 and b.air_v.y > 1.5,
			"and sends him flying away, the way the bat went, and up (%s)" % str(b.air_v.snapped(Vector3.ONE * 0.1))])
		var lost := 0
		for n in b.parts:
			if bool(b.parts[n].gone):
				lost += 1
		out.append([lost == 0 and ((r.res as Dictionary).pieces as Array).is_empty() and b.alive, "blunt: nothing comes off, he lives"])
		for i in 150:
			b.react_step(1.0 / 60.0)
		out.append([not b.airborne and b.floored() and b.position.z < -2.0, "he lands %.1f m back and lies there" % -b.position.z])
		out.append([float(r.ms) < 40.0, "a blow costs %.1f ms" % float(r.ms)])
	b.queue_free()
	# the reach and the arc
	var b2 := _grunt(host)
	out.append([strike_point(b2, Vector3(0, 1.1, 2.9), fwd, side).is_empty(), "2.9 m away: out of reach"])
	out.append([strike_point(b2, Vector3(0, 1.1, -1.2), fwd, side).is_empty(), "behind you: missed"])
	out.append([not strike_point(b2, Vector3(-1.2, 1.1, 0.9), fwd, side).is_empty(), "off to the right inside the arc: hit"])
	out.append([strike_point(b2, Vector3(-1.6, 1.1, -0.2), fwd, side).is_empty(), "off to the right beyond the arc: missed"])
	# a swing at head height: the head, dented deeper
	var hh := strike_point(b2, Vector3(0, 1.62, 1.4), fwd, side)
	out.append([String(hh.get("part", "")) == "head", "a swing at head height hits the head (%s)" % hh.get("part", "nothing")])
	if not hh.is_empty():
		var hp1 := b2.hp
		var r2 := blow(b2, hh, v1, SPIN, 1.0, false)
		out.append([not bool(r2.head_off) and (hp1 - b2.hp >= DAMAGE_HEAD - 0.01 or not b2.alive),
			"a quick swing to the head: a deep dent (%d cubes), more hurt, the head stays on" % int(r2.cubes)])
	b2.queue_free()
	# the home run: a full charge to the head knocks it clean off and the body flies three times as fast
	var b3 := _grunt(host)
	var h3 := strike_point(b3, Vector3(0, 1.62, 1.4), fwd, side)
	if not h3.is_empty():
		var v3 := push_velocity(fwd, side, 3.0)
		var r3 := blow(b3, h3, v3, SPIN + 6.0, 3.0, true)
		var head_piece := 0
		for pc in ((r3.res as Dictionary).pieces as Array):
			if String(pc.part) == "head":
				head_piece = int(pc.count)
		out.append([bool(r3.head_off) and bool(b3.parts.head.gone) and not b3.alive, "a full home run to the head knocks it off and kills"])
		out.append([head_piece > 300, "the head comes away whole as a piece (%d cubes)" % head_piece])
		out.append([b3.airborne and b3.air_v.length() > 2.5 * v1.length(), "the body sails %.0f m/s (a swing: %.0f)" % [b3.air_v.length(), v1.length()]])
		out.append([float(r3.ms) < 60.0, "a home run costs %.1f ms" % float(r3.ms)])
	else:
		out.append([false, "a home run at head height finds the head"])
	b3.queue_free()
	# a full charge hits everyone in the arc; a swing only the nearest
	var b4 := _grunt(host, Vector3(0, 0, 0))
	var b5 := _grunt(host, Vector3(0.9, 0, 0.6))
	var both := [b4, b5]
	var one := targets(both, Vector3(0.2, 1.1, 1.6), fwd, side, false)
	var all := targets(both, Vector3(0.2, 1.1, 1.6), fwd, side, true)
	out.append([one.size() == 1 and one[0][0] == b5, "a swing hits only the nearest of two"])
	out.append([all.size() == 2, "a full home run hits both (%d)" % all.size()])
	b4.queue_free()
	b5.queue_free()
	# top-down (the camera 13 m up, 6 m back): the mouse on his chest swings at the chest, on his head at the head
	var b6 := _grunt(host)
	var cam := Vector3(0, 13.0, 7.4)
	var pp := Vector3(0, 0, 1.4)
	var y_chest := swing_height([b6], cam, (Vector3(0, 1.1, 0) - cam).normalized(), pp)
	var y_head := swing_height([b6], cam, (Vector3(0, 1.75, 0) - cam).normalized(), pp)
	var hd := strike_point(b6, pp + Vector3(0, y_head, 0), fwd, side)
	out.append([absf(y_chest - 1.15) < 0.01, "top-down, the mouse on his chest: a swing at the chest (%.2f m)" % y_chest])
	out.append([String(hd.get("part", "")) == "head",
		"top-down, the mouse on his head: a swing at %.2f m lands on the %s" % [y_head, hd.get("part", "nothing")]])
	b6.queue_free()
	# first person the bat stays clear of your eye all the way round (no clipping through the camera)
	var w := VoxelMeleeBat.new()
	var clear := 9.0
	for hr in [false, true]:
		w._th = CHARGE_TH1 if hr else REST_TH
		w._ph = CHARGE_PH1 if hr else REST_PH
		w._grip = CHARGE_GRIP1 if hr else REST_GRIP
		w._start_swing(hr, 1.0)
		var t := 0.0
		while t <= w._wind_t + w._arc_t + w._back_t:
			var p := w._swing_pose(t)
			clear = minf(clear, _clearance(p[0], p[1], p[2]))
			t += 0.005
	w.free()
	out.append([clear > 0.15, "first person a swing and a home run pass %.2f m clear of your eye" % clear])
	VoxelBody.immortal = was
	return out
