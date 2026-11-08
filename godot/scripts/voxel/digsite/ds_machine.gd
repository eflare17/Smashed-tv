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

## The ground's height at a world x, z: the voxel ground's top on the grid, the field (0) round it
func ground_y(x: float, z: float) -> float:
	var tr: DsTerrain = site.terrain
	if tr == null:
		return 0.0
	# (the ground's drawn smooth: the four columns round the point blended, not one column's blocky top)
	var c := DsTerrain.CELL
	var fx := (x - tr.origin.x) / c - 0.5
	var fz := (z - tr.origin.z) / c - 0.5
	var ix := floorf(fx)
	var iz := floorf(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h := [0.0, 0.0, 0.0, 0.0]
	for k in 4:
		var wx := tr.origin.x + (ix + float(k % 2) + 0.5) * c
		var wz := tr.origin.z + (iz + float(k / 2) + 0.5) * c
		var y := tr.top_at(wx, wz)
		h[k] = 0.0 if y == -INF else y
	return lerpf(lerpf(h[0], h[1], tx), lerpf(h[2], h[3], tx), tz)

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
			if n > 1:
				_pose_now()
			_tool(dt / n)
		_block_body()
	else:
		_follow(dt)
	_pose_now()
	_pour_fx(dt)

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
	# down it drops (falling), up it climbs (at once)
	if top >= at.y:
		to.y = top
		_vy = 0.0
	else:
		_vy -= GRAVITY * dt
		to.y = maxf(top, at.y + _vy * dt)
		if to.y <= top:
			_vy = 0.0
	global_position = to
	pitch = lerpf(pitch, new_pitch, minf(1.0, dt * 10.0))
	roll = lerpf(roll, atan2(maxf(c[1], c[3]) - maxf(c[0], c[2]), width), minf(1.0, dt * 10.0))

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
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.6
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi
