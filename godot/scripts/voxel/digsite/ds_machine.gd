class_name DsMachine
extends Node3D
## A Dig Site machine (stage 6 on): something with tracks or wheels you drive on the voxel ground, the Dingo first,
## then the Bobcat, the excavator, the tip truck and the drill. Like the digger game's Machine: W/S drive (it takes
## a moment to get going and to stop), A/D turn (skid steer: on the spot too), the ground under its four corners
## sets its height, its nose-up and its lean. It won't climb what's too steep for it (MAX_CLIMB) or a step taller
## than STEP: it stops dead, the driver told; it drives down into a hole fine (and has to find a ramp out). Only the
## game that runs the ground (solo, or the host) moves it; the guest's shows the host's (its state 20 times a
## second, eased between) and sends its driver's controls. Subclasses add their tools (a bucket, an arm, a tray, a
## drill head) through _tool(dt), net_more()/net_take_more() and _cmds_more(). Owned by the voxel session.

const STATE_HZ := 20.0
const GRAVITY := 9.8
const RIDE_EASE := 10.0         # per second: its height and lean ease to the ground under it (the digger game's)
const FALL_FROM := 0.3          # m: further under it than this, the ground's a drop and it falls

var site: Node3D                # DigSite
var id := 0                     # 1 .. 99 (its fast messages' id; its driver's controls go as id + 128)
var kind := ""                  # its name: "Dingo"
var driver := 0                 # 0 nobody, 1 the host (or solo), 2 the guest
# how it's made and how it goes (a subclass sets these)
var length := 1.6               # m, the footprint (tracks) front to back ...
var width := 1.0                # ... and side to side
var max_speed := 2.2            # m/s forward (backward: 70% of it)
var accel := 1.8                # m/s2, getting going (stopping: twice that)
var turn_rate := 1.5            # rad/s, on the spot (less at speed)
var max_climb := deg_to_rad(30.0)
var step_up := 0.3              # m: the tallest step it'll climb
var wall_look := 1.0            # m ahead of its leading wheels a bank's looked for (a dozer: no further than its blade)
var seat := Vector3(0, 0.35, 0.75)   # where the driver stands/sits (its feet), from its middle
var pipe := Vector3(0.3, 1.5, 0.3)   # its exhaust stack's top, from its middle
var turn_needs_speed := false   # (a truck: steered wheels, it only turns rolling)
# where it is
var yaw := 0.0
var speed := 0.0
var pitch := 0.0                # nose up +
var roll := 0.0
var _vy := 0.0
# its controls (its driver's: here or sent)
var throttle := 0.0             # -1 .. 1
var steer := 0.0                # -1 (left) .. 1
var blocked := ""               # why it stopped, for the driver ("" : it's going)
var auto := false               # (the tests: its controls set straight, not read from the keys)
# the guest's: the host's last state, eased to
var _to_pos := Vector3.INF
var _to := {}
var _state_t := 0.0
var _body: AnimatableBody3D

func setup(s: Node3D, id_: int, at: Vector3, yaw_: float) -> void:
	site = s
	id = id_
	yaw = yaw_
	_build()
	global_position = at
	global_position.y = ground_y(at.x, at.z)
	_pose_now()

## Makes its model (a subclass), and its body: the player bumps into it
func _build() -> void:
	_body = AnimatableBody3D.new()
	_body.sync_to_physics = false
	_body.collision_layer = 1
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, 0.8, length)
	cs.shape = sh
	cs.position = Vector3(0, 0.45, 0)
	_body.add_child(cs)
	add_child(_body)

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))

func right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))

## The ground's height at a world x, z: the voxel ground's surface on the grid (the loose layer and all, blended between
## the four columns round the point, so it's smooth: DsTerrain.height_at), its edge carrying on round it
func ground_y(x: float, z: float) -> float:
	var tr: DsTerrain = site.terrain
	if tr == null:
		return 0.0
	return tr.height_at(x, z)

## The ground under its four corners: [front left, front right, back left, back right]
func _corners(at: Vector3, yaw_: float) -> PackedFloat32Array:
	var f := Vector3(-sin(yaw_), 0, -cos(yaw_)) * (length * 0.5)
	var r := Vector3(cos(yaw_), 0, -sin(yaw_)) * (width * 0.5)
	var out := PackedFloat32Array()
	for p in [at + f - r, at + f + r, at - f - r, at - f + r]:
		out.append(ground_y(p.x, p.z))
	return out

func runs() -> bool:
	return site.net == null or site.net.runs()

# ---------------------------------------------------------------- each frame

func step(dt: float) -> void:
	if runs():
		# (in steps of no more than ~1/45 s: a slow frame drives and digs the same as quick ones)
		var n := clampi(ceili(dt * 45.0), 1, 6)
		for i in n:
			_drive(dt / n)
			_pose_now()             # (its tool's worked out from where it is now, not where it was last frame)
			_tool(dt / n)
		_block_body()
	else:
		_follow(dt)
	_pose_now()
	_pour_fx(dt)
	_dust_fx()

## Its body solid to the loose dirt (the host's: the dirt runs there): a heap slumping, or soil sliding off a blade,
## banks against its tracks and wheels instead of flowing in under it (and lifting it up onto the pile)
func _block_body() -> void:
	var tr: DsTerrain = site.terrain
	if tr == null:
		return
	var f := forward()
	var r := right() * (width * 0.5)
	var front := Vector3(global_position.x, global_position.y, global_position.z) + f * (length * 0.5)
	tr.block(id + 1000, front - r, front + r, f, length, 1.0)

var _dust: CPUParticles3D
var _exhaust: CPUParticles3D
var _pour_dust: CPUParticles3D
var _work_dust: CPUParticles3D         # (the digger game's: dust and flying lumps where a blade or bucket is moving dirt)
var _work_clods: CPUParticles3D
static var _lump_mesh: ArrayMesh
static var _lump_mat: StandardMaterial3D

## Where its exhaust comes out (the top of its stack; a subclass whose stack moves, the excavator's on its house, says)
func exhaust_at() -> Vector3:
	return global_transform * pipe

## Flying lumps of dirt (the digger game's _chunks with its _flying_lump): a lumpy little rock in two browns, lit
static func chunks(amount: int) -> CPUParticles3D:
	if _lump_mesh == null:
		var src := DsLook.clod_mesh(1).surface_get_arrays(0)
		var pts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var order: PackedInt32Array = src[Mesh.ARRAY_INDEX]
		var at := PackedVector3Array()
		var nrm := PackedVector3Array()
		var tint := PackedColorArray()
		var browns := [DsMats.COL[DsMats.DIRT], DsMats.COL[DsMats.DIRT].darkened(0.25), DsMats.COL[DsMats.TOPSOIL]]
		for k in range(0, order.size(), 3):
			var a := pts[order[k]] * 0.5
			var b := pts[order[k + 1]] * 0.5
			var c := pts[order[k + 2]] * 0.5
			var n := (c - a).cross(b - a).normalized()
			for p: Vector3 in [a, b, c]:
				at.append(p)
				nrm.append(n)
				tint.append(browns[(k / 3) % browns.size()])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = at
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = tint
		_lump_mesh = ArrayMesh.new()
		_lump_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_lump_mat = StandardMaterial3D.new()
		_lump_mat.vertex_color_use_as_albedo = true
		_lump_mat.roughness = 1.0
	var p := CPUParticles3D.new()
	p.mesh = _lump_mesh
	p.material_override = _lump_mat
	p.amount = amount
	p.lifetime = 0.9
	p.emitting = false
	p.local_coords = false
	p.gravity = Vector3(0.0, -13.0, 0.0)
	p.angular_velocity_min = -280.0
	p.angular_velocity_max = 280.0
	return p

## Dust and flying lumps where its blade or bucket is moving dirt (the digger game's clods and dust): at `at`, along
## the edge `across` m either side, thrown forward and up; on while it's working
func work_fx(at: Vector3, across: float, on: bool) -> void:
	if _work_dust == null:
		var k := clampf(length / 4.0, 0.4, 1.0)
		_work_dust = puffs(Color("#c9a77c"), 26, 1.3)
		_work_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_work_dust.direction = Vector3(0, 1, 0)
		_work_dust.spread = 50.0
		_work_dust.initial_velocity_min = 0.4
		_work_dust.initial_velocity_max = 1.3
		_work_dust.gravity = Vector3(0, 0.2, 0)
		_work_dust.scale_amount_min = 0.8 * k
		_work_dust.scale_amount_max = 1.7 * k
		add_child(_work_dust)
		_work_clods = chunks(26)
		_work_clods.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_work_clods.direction = Vector3(0.0, 1.0, -0.5)      # (up, and ahead: its forward's -z)
		_work_clods.spread = 42.0
		_work_clods.initial_velocity_min = 1.8 * k
		_work_clods.initial_velocity_max = 4.2 * k
		_work_clods.scale_amount_min = 0.2 * k
		_work_clods.scale_amount_max = 0.5 * k
		add_child(_work_clods)
	for p: CPUParticles3D in [_work_dust, _work_clods]:
		p.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
		p.emission_box_extents = Vector3(across, 0.2, 0.2)
		p.emitting = on

## A puff emitter (the digger game's): soft balls that grow and fade
static func puffs(colour: Color, amount: int, life: float) -> CPUParticles3D:
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 6
	ball.rings = 3
	var p := CPUParticles3D.new()
	p.mesh = ball
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = colour
	# (after the grass and the lumps: they're in the see-through pass too, drawn later, and with nothing behind a puff
	# but grass the grass painted over it, so smoke and dust only showed against the sky: the owner, 9 Nov, "the
	# smoke's not coming out of the stack")
	m.render_priority = 2
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	return p

# dust off the tracks as it drives, exhaust from the stack while it's driven, dust where it pours
func _dust_fx() -> void:
	if _dust == null:
		# (sized to the machine: a Dingo's puffs are a third of a truck's)
		var k := clampf(length / 5.0, 0.35, 1.0)
		_dust = puffs(Color("#d6bd98"), 18, 1.0)
		_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_dust.emission_box_extents = Vector3(width * 0.45, 0.05, length * 0.2)
		_dust.direction = Vector3(0, 1, 0)
		_dust.spread = 40.0
		_dust.initial_velocity_min = 0.2 * k
		_dust.initial_velocity_max = 0.8 * k
		_dust.gravity = Vector3.ZERO
		_dust.scale_amount_min = 0.5 * k
		_dust.scale_amount_max = 1.1 * k
		add_child(_dust)
		# (bigger and slower off the stack than the digger game's, which seen from a camera beside it only showed once
		# they'd risen 2 m clear: the owner, 9 Nov, "the smoke's not coming out of the stack")
		var ke := maxf(k, 0.8)
		_exhaust = puffs(Color("#2f2f2f"), 24, 1.5)
		_exhaust.direction = Vector3(0, 1, 0)
		_exhaust.spread = 12.0
		_exhaust.initial_velocity_min = 0.8 * ke
		_exhaust.initial_velocity_max = 1.5 * ke
		_exhaust.gravity = Vector3(0.25, 0.25, 0.0)
		_exhaust.scale_amount_min = 0.38 * ke
		_exhaust.scale_amount_max = 0.7 * ke
		add_child(_exhaust)
		_pour_dust = puffs(Color("#d8c6a4"), 14, 1.2)
		_pour_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_pour_dust.emission_sphere_radius = 0.5
		_pour_dust.direction = Vector3(0, 1, 0)
		_pour_dust.spread = 60.0
		_pour_dust.initial_velocity_min = 0.3
		_pour_dust.initial_velocity_max = 1.0
		_pour_dust.gravity = Vector3(0, 0.4, 0)
		_pour_dust.scale_amount_min = 0.8
		_pour_dust.scale_amount_max = 1.7
		add_child(_pour_dust)
	# (dust off the back of the tracks, low down, whichever way it's going)
	_dust.global_position = global_position - forward() * signf(speed) * (length * 0.4) + Vector3(0, 0.1, 0)
	_dust.emitting = absf(speed) > 0.4
	_exhaust.global_position = exhaust_at()
	_exhaust.emitting = driver != 0
	# (its tracks or tyres wear the grass bare where they go: the digger game's track marks)
	if absf(speed) > 0.05 and site.terrain:
		site.terrain.wear_tracks(self)
	_exhaust.speed_scale = 0.6 + 0.8 * clampf(absf(throttle), 0.0, 1.0)      # (worked hard, it puffs faster)
	var pouring := _stream_t > 0.0 and fx_load() >= 0
	if pouring:
		var at := fx_pour_at()
		_pour_dust.global_position = Vector3(at.x, ground_y(at.x, at.z) + 0.3, at.z)
	_pour_dust.emitting = pouring

## (a subclass) what it's carrying (blocks; -1: nothing to carry) and where it comes out when it pours
func fx_load() -> int:
	return -1

func fx_pour_at() -> Vector3:
	return global_position

var _stream: CPUParticles3D
var _last_load := -1
var _stream_t := 0.0

# dirt falling where it pours (a bucket tipping, the excavator opening, the truck's tray up): whenever its load's going
# down, in both games (the guest's sees the load in the host's state)
func _pour_fx(dt: float) -> void:
	var n := fx_load()
	if n < 0:
		return
	if _last_load >= 0 and n < _last_load:
		_stream_t = 0.25
	_last_load = n
	_stream_t -= dt
	var on := _stream_t > 0.0
	if on and _stream == null:
		_stream = CPUParticles3D.new()
		_stream.amount = 60
		_stream.lifetime = 0.9
		_stream.local_coords = false
		_stream.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_stream.emission_box_extents = Vector3(0.25, 0.05, 0.25)
		_stream.direction = Vector3.DOWN
		_stream.spread = 20.0
		_stream.initial_velocity_min = 0.3
		_stream.initial_velocity_max = 1.0
		_stream.gravity = Vector3(0, -9.8, 0)
		_stream.scale_amount_min = 0.6
		_stream.scale_amount_max = 1.5
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.08
		var m := StandardMaterial3D.new()
		m.albedo_color = Color8(122, 86, 52)
		m.roughness = 1.0
		bm.material = m
		_stream.mesh = bm
		add_child(_stream)
	if _stream:
		_stream.emitting = on
		if on:
			_stream.global_position = fx_pour_at()

## (the game that runs it) moves it by its controls over the ground
func _drive(dt: float) -> void:
	var want := throttle * max_speed * (1.0 if throttle >= 0.0 else 0.7)
	var a := accel if absf(want) > absf(speed) and signf(want) == signf(speed) or is_zero_approx(speed) else accel * 2.0
	speed = move_toward(speed, want, a * dt)
	var turn_k := 1.0 - 0.5 * clampf(absf(speed) / max_speed, 0.0, 1.0)
	if turn_needs_speed:
		turn_k = clampf(absf(speed) / 1.5, 0.0, 1.0) * (1.0 if speed >= 0.0 else -1.0)    # (wheels: it turns as it rolls)
	var new_yaw := yaw - steer * turn_rate * turn_k * dt
	var at := global_position
	var to := at + Vector3(-sin(new_yaw), 0, -cos(new_yaw)) * speed * dt
	# the site's fence
	var half: float = site.SIZE * 0.5 - 0.6
	to.x = clampf(to.x, site.AT.x - half, site.AT.x + half)
	to.z = clampf(to.z, site.AT.z - half, site.AT.z + half)
	var c := _corners(to, new_yaw)
	var hf := maxf(c[0], c[1])
	var hb := maxf(c[2], c[3])
	var top := maxf(hf, hb)
	var new_pitch := atan2(hf - hb, length)
	blocked = ""
	var going := speed * dt
	var uphill := new_pitch if going > 0.0 else -new_pitch      # (nose-up the way it's going)
	if absf(going) > 0.0:
		if top - at.y > step_up:
			blocked = "Too big a step: find a ramp"
		elif uphill > max_climb and uphill > _uphill_now(going):
			blocked = "Too steep for the %s" % kind
		elif _wall_ahead(to, new_yaw, signf(going), at.y):
			blocked = "Too steep for the %s" % kind
	if blocked != "":
		speed = 0.0
		to = at
		c = _corners(at, new_yaw)
		top = maxf(maxf(c[0], c[1]), maxf(c[2], c[3]))
		hf = maxf(c[0], c[1])
		hb = maxf(c[2], c[3])
		new_pitch = atan2(hf - hb, length)
	yaw = new_yaw
	# where it rests (the digger game's: on its corners' average, or a crest between its tracks if that's higher),
	# eased to, as are its pitch and roll (the owner, 9 Nov: "it's still so jumpy": it climbed each block's 12.5 cm
	# step in one frame, and the camera behind it jolted with it). Off a real drop it falls.
	var ml := ground_y(to.x - right().x * width * 0.5, to.z - right().z * width * 0.5)
	var mr := ground_y(to.x + right().x * width * 0.5, to.z + right().z * width * 0.5)
	var rest := maxf((c[0] + c[1] + c[2] + c[3]) * 0.25, maxf(ml, mr))
	var k := 1.0 - exp(-RIDE_EASE * dt)
	if rest < at.y - FALL_FROM or _vy < 0.0:
		_vy -= GRAVITY * dt
		to.y = maxf(rest, at.y + _vy * dt)
		if to.y <= rest:
			_vy = 0.0
	else:
		to.y = lerpf(at.y, rest, k)
	global_position = to
	var lean_f := (c[0] + c[1] - c[2] - c[3]) * 0.5
	var lean_r := (c[1] + c[3] - c[0] - c[2]) * 0.5
	pitch = lerpf(pitch, atan2(lean_f, length), k)
	roll = lerpf(roll, atan2(lean_r, width), k)

## The ground just ahead of its leading corners rising steeper than it climbs (a pit's wall, a bank), measured from
## where it rides (base: its height now; a hole under a corner, its own bucket's bite, doesn't count)
func _wall_ahead(at: Vector3, yaw_: float, dir: float, base: float) -> bool:
	var f := Vector3(-sin(yaw_), 0, -cos(yaw_)) * dir
	var r := Vector3(cos(yaw_), 0, -sin(yaw_)) * (width * 0.5)
	var lead := at + f * (length * 0.5)
	var lim := tan(max_climb)
	for p in [lead - r, lead + r, lead]:
		# (loose dirt isn't a wall: tracks and wheels climb it or shove through it; a bank of firm ground is)
		var q: Vector3 = p + f * 0.3
		var from := maxf(base, ground_y(p.x, p.z))
		var rise := minf(ground_y(q.x, q.z), site.terrain.firm_at(q.x, q.z)) - from
		if rise / 0.3 > lim and rise > 0.08:
			# (a lip it steps up onto isn't a wall: a bank is, rising on past what it steps up)
			var q2: Vector3 = p + f * wall_look
			if minf(ground_y(q2.x, q2.z), site.terrain.firm_at(q2.x, q2.z)) - from > step_up:
				return true
	return false

func _uphill_now(going: float) -> float:
	return pitch if going > 0.0 else -pitch

## (a subclass) its tool, each frame on the game that runs it
func _tool(_dt: float) -> void:
	pass

func _pose_now() -> void:
	basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	_pose_tool()

## (a subclass) its tool's parts posed
func _pose_tool() -> void:
	pass

## Where its driver's feet go
func seat_world() -> Vector3:
	return global_transform * seat

## Which way its driver faces (the view turns with this: an excavator's house slews)
func view_yaw() -> float:
	return yaw

# ---------------------------------------------------------------- the network

## Its state, for the guest's game: where, its tool, its driver
func net_state() -> PackedByteArray:
	var f := PackedFloat32Array([global_position.x, global_position.y, global_position.z, yaw, pitch, roll, speed, float(driver)])
	f.append_array(net_more())
	return f.to_byte_array()

func net_take(d: PackedByteArray) -> void:
	var f := d.to_float32_array()
	if f.size() < 8:
		return
	_to_pos = Vector3(f[0], f[1], f[2])
	_to = {"yaw": f[3], "pitch": f[4], "roll": f[5]}
	speed = f[6]
	driver = int(f[7])
	net_take_more(f.slice(8))

## (a subclass) its tool's state, as floats
func net_more() -> PackedFloat32Array:
	return PackedFloat32Array()

func net_take_more(_f: PackedFloat32Array) -> void:
	pass

## (the guest's) eased to the host's last state
func _follow(dt: float) -> void:
	if _to_pos == Vector3.INF:
		return
	var k := minf(1.0, dt * 12.0)
	if global_position.distance_to(_to_pos) > 4.0:
		k = 1.0
	global_position = global_position.lerp(_to_pos, k)
	yaw = lerp_angle(yaw, float(_to.yaw), k)
	pitch = lerpf(pitch, float(_to.pitch), k)
	roll = lerpf(roll, float(_to.roll), k)

## Its driver's controls (the guest's, to the host)
func net_cmds() -> PackedByteArray:
	var f := PackedFloat32Array([throttle, steer])
	f.append_array(_cmds_more())
	return f.to_byte_array()

func net_take_cmds(d: PackedByteArray) -> void:
	var f := d.to_float32_array()
	if f.size() < 2:
		return
	throttle = clampf(f[0], -1.0, 1.0)
	steer = clampf(f[1], -1.0, 1.0)
	_take_cmds_more(f.slice(2))

func _cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array()

func _take_cmds_more(_f: PackedFloat32Array) -> void:
	pass

## (a subclass) its controls from the keys and mouse, while this player drives it
func read_input() -> void:
	throttle = float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	steer = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))

func stop_cmds() -> void:
	throttle = 0.0
	steer = 0.0

## (a subclass) its keys, for the help line
func keys() -> String:
	return "W/S drive   A/D turn   E get off"

## (a subclass) what it says to its driver (its load, why it stopped)
func status() -> String:
	return blocked

# ---------------------------------------------------------------- model helpers

func _box(parent: Node3D, size: Vector3, at: Vector3, col: Color, metal := 0.2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = DsLook.flat(col)
	mi.position = at
	parent.add_child(mi)
	return mi
