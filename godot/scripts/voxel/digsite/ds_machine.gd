class_name DsMachine
extends Node3D
## A Dig Site machine (stage 6 on): something with tracks or wheels you drive on the voxel ground, the Dingo first,
## then the Bobcat, the excavator, the tip truck and the drill. Like the digger game's Machine: W/S drive (it takes
## a moment to get going and to stop), A/D turn (skid steer: on the spot too), the ground under its four corners
## sets its height, its nose-up and its lean. It won't climb what's too steep for it (MAX_CLIMB) or a step taller
## than STEP: the driver's told; it drives down into a hole fine (and has to find a ramp out). It has weight (the dirt
## physics' stage 4, "the Dig Site feels pretty clunky"): its drive pulls hardest standing and not at all at its top
## speed, what it's pushing (drive_resist) pulls the other way, so loaded it lugs down instead of being held to a
## speed; its tracks slip when it's held back (slip, track_v: what its tracks and its dust show); it's eased into a
## turn; it brakes for a bank it's coming up to instead of stopping dead at it; and its body rocks on its tracks (sway:
## nose up pulling away, down braking or leaning into a load, a thud when it lands). Only the
## game that runs the ground (solo, or the host) moves it; the guest's shows the host's (its state 20 times a
## second, eased between) and sends its driver's controls. Subclasses add their tools (a bucket, an arm, a tray, a
## drill head) through _tool(dt), net_more()/net_take_more() and _cmds_more(). Owned by the voxel session.

const STATE_HZ := 20.0
const GRAVITY := 9.8
const RIDE_EASE := 10.0         # per second: its height and lean ease to the ground under it (the digger game's)
const FALL_FROM := 0.3          # m: further under it than this, the ground's a drop and it falls

var site: Node3D                # DigSite
var id = 0                     # 1 .. 99 (its fast messages' id; its driver's controls go as id + 128)
var kind = ""                  # its name: "Dingo"
var driver = 0                 # 0 nobody, 1 the host (or solo), 2 the guest
# how it's made and how it goes (a subclass sets these)
var length = 1.6               # m, the footprint (tracks) front to back ...
var width = 1.0                # ... and side to side
var max_speed = 2.2            # m/s forward (backward: 70% of it)
var accel = 1.8                # m/s2, getting going (stopping: twice that)
var turn_rate = 1.5            # rad/s, on the spot (less at speed)
var max_climb = deg_to_rad(30.0)
var step_up = 0.3              # m: the tallest step it'll climb
var wall_look = 1.0            # m ahead of its leading wheels a bank's looked for (a dozer: no further than its blade)
var seat = Vector3(0, 0.35, 0.75)   # where the driver stands/sits (its feet), from its middle
var pipe = Vector3(0.3, 1.5, 0.3)   # its exhaust stack's top, from its middle
var turn_needs_speed = false   # (a truck: steered wheels, it only turns rolling)
var body_high = 1.0            # m: its body as a box for the clods (body_box): this tall, its footprint wide and long
var tool_kind = DsDirt.K_BUCKET   # what its keepout_boxes() are to the clods (a dozer's: K_BLADE)
# where it is
var yaw = 0.0
var speed = 0.0
var pitch = 0.0                # nose up +
var roll = 0.0
var _vy = 0.0
# its controls (its driver's: here or sent)
var throttle = 0.0             # -1 .. 1
var steer = 0.0                # -1 (left) .. 1
var blocked = ""               # why it stopped, for the driver ("" : it's going)
var auto = false               # (the tests: its controls set straight, not read from the keys)
# the guest's: the host's last state, eased to
var _to_pos = Vector3.INF
var _to = {}
var _state_t = 0.0
var _body: AnimatableBody3D
# Its engine shaking it a little (the web game's _shake_body, about a third as much; the owner, 9 Nov): shake_node's
# what shakes (its body and what's on it, not its wheels or tracks: a subclass sets it), a few mm ticking over, more
# the harder it works. Seen alike on both games (speed and driver come over the wire); its digging doesn't feel it.
var effort_now = 0.0           # how hard it's working besides driving, this frame (0 .. 1: shake_effort(), once a frame)
var cut_now = 0.0              # how much dirt its blade or bucket is cutting or pushing, this frame (0 .. 1: a subclass's)
var clunk_weight = 0.8
var _stop_was = true
var _clunk_wait = 0.0
var tracked = true             # (on tracks: they clatter)
var sfx: DsSfx
var shake_node: Node3D
var shake_idle = 0.0018        # m up and down, ticking over
var shake_work = 0.0045        # more at full speed
var shake_pitch = 0.0007       # rad
var shake_hz = 58.0            # (rad a second: its main buzz)
var _shake_clock = 0.0
# Its weight (stage 4)
const PULL := 2.5               # its drive: accel * PULL m/s2 standing, falling to none at its top speed (so it's as
                                # quick off the mark as it was and eases up to its top speed instead of hitting it)
const BRAKE := 1.0              # x accel: its brakes besides, let go or driven against the way it's going
const UPHILL := 0.4             # the resistance of a slope as steep as it'll climb (of its drive standing)
const YAW_EASE := 4.0           # per second: its turning eased to what's asked ...
const YAW_JERK := 5.0           # ... and changing by no more than turn_rate * this a second
const LOOK_FROM := 0.5          # m/s: going faster than this it looks for a bank where it could just stop ...
const LOOK_MOST := 2.5          # ... no further off than this (m)
const SLIP_FROM := 0.35         # resistance (of its drive standing) from which its tracks start to slip; at 1 they only slip
const LUG_REVS := 0.7           # stalled, its tracks turn at this share of what's asked of them (its engine's lugging)
const TRACK_EASE := 8.0
const SWAY_HZ := 10.0           # rad/s: its body on its tracks, a spring ...
const SWAY_DAMP := 0.4          # ... that rocks once or twice
const SWAY_ACC := 0.0105        # rad a m/s2 (0.6 degrees): nose up pulling away, down braking
const SWAY_LOAD := 0.021        # rad (1.2 degrees): nose down leaning into what's holding it back
const SWAY_MOST := 0.056        # rad (3.2 degrees) it's asked for at the most; about 4 with its overshoot
const SWAY_END := 0.08
const THUD_FROM := 1.6          # m/s: coming down faster than this and stopped, it's landed
var track_v = 0.0              # m/s: what its tracks (or wheels) are doing: its speed, and more when they slip
var slip = 0.0                 # 0 .. 1: how much of its tracks' turning isn't moving it
var resist = 0.0               # what's holding it back, of its drive standing (1: it stalls flat out) (the game that runs it)
var lug = 0.0                  # 0 .. 1: how hard its engine's labouring (both games)
var sway = 0.0                 # rad, nose up +: its body rocking on its tracks (its look only: its tool doesn't feel it)
var sway_k = 1.0               # (a subclass: how much it rocks)
var bob = 0.0                  # m: its body down on its springs (a landing)
var bumped = 0.0               # m/s it was doing (back: -) when a bank stopped it this frame (0: none did)
var _sway_v = 0.0
var _bob_v = 0.0
var _acc = 0.0
var _speed_was = 0.0
var _y_was = NAN
var _fall_was = 0.0
var _yaw_v = 0.0
var _track_more = 0.0
var _wall_gap = -1.0           # m to a bank it's braking for (-1: none)
var _wall_dir = 0.0
var _wall_yaw = 0.0
var _cap_y = INF               # (looking ahead: ground over this is its blade's to cut, not a bank)
var _slip_dust: CPUParticles3D
var _slip_clods: CPUParticles3D
var _thud_dust: CPUParticles3D

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
	var cs = CollisionShape3D.new()
	var sh = BoxShape3D.new()
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
	var f = Vector3(-sin(yaw_), 0, -cos(yaw_)) * (length * 0.5)
	var r = Vector3(cos(yaw_), 0, -sin(yaw_)) * (width * 0.5)
	var out = PackedFloat32Array()
	for p in [at + f - r, at + f + r, at - f - r, at - f + r]:
		out.append(ground_y(p.x, p.z))
	return out

func runs() -> bool:
	return site.net == null or site.net.runs()

## Its body as a box, for the clods (DsDirt.set_boxes): [where its middle is (world), half its size]
func body_box() -> Array:
	return [global_transform * Transform3D(Basis.IDENTITY, Vector3(0, body_high * 0.5, 0)), Vector3(width * 0.5, body_high * 0.5, length * 0.5)]

## Every box of it the clods bump into: [[Transform3D, half its size, DsDirt.K_*]]: its body, and its blade or bucket
## (keepout_boxes(), where it has one). The same boxes in the same order every time.
func clod_boxes() -> Array:
	var b = body_box()
	var out = [[b[0], b[1], DsDirt.K_BODY]]
	if has_method("keepout_boxes"):
		for k: Array in call("keepout_boxes"):
			out.append([k[0], k[1], tool_kind])
	return out

# ---------------------------------------------------------------- each frame

func step(dt: float) -> void:
	if runs():
		# (in steps of no more than ~1/45 s: a slow frame drives and digs the same as quick ones)
		var n = clampi(ceili(dt * 45.0), 1, 6)
		for i in n:
			_drive(dt / n)
			_pose_now()             # (its tool's worked out from where it is now, not where it was last frame)
			_tool(dt / n)
		_block_body()
	else:
		_follow(dt)
	_pose_now()
	_fx_clock += dt
	_pour_fx(dt)
	effort_now = shake_effort()
	_weight_fx(dt)
	_dust_fx()
	_shake_body(dt)
	if sfx == null and driver != 0:
		sfx = DsSfx.new()
		add_child(sfx)
		sfx.position = Vector3(0, 1.0, 0)
		sfx.setup(length / 4.0)
	if sfx:
		sfx.update(dt, self, tracked, _stream_t > 0.0 and fx_load() >= 0)
		# (a clunk when its tool comes to the end of its travel or lands: at_stop() going true)
		var stop = at_stop()
		_clunk_wait -= dt
		if stop and not _stop_was and driver != 0 and _clunk_wait <= 0.0:
			sfx.clunked(clunk_weight)
			_clunk_wait = 0.7           # (a blade skimming the ground doesn't rattle them off)
		_stop_was = stop

# Dirt let go of (the owner, 10 Nov: "the dust appears before it's even dropped"; 24 Nov: the dirt should "feel like"
# the buildings' bricks): what a bucket pours or a tray tips is a stream of clods (DsDirt: the dirt physics' stage 6)
# from where it comes out, going as its lip goes. They fall, hit what's under them, roll; over a truck's tray they
# land in it and are its load once they lie still (DsTruck._take_in), and badly aimed they go over its side.
const POUR_MOST := 40 * DsDirt.CLOD    # mm let go in a step at the most (40 clods)
const TEAR := 0.1               # of what a bucket's lip cuts, torn off as crumbs tumbling ahead of it, not into it
var _fx_clock = 0.0
var pour_clods = true          # (tests: false, what it pours lands at once, as before the clods: the baseline)
var poured = 0                 # (tests: mm it's let go)
var torn = 0                   # (tests: mm its lip's torn off or its full bucket's spilled, as clods)

## Lets n mm of m go at p, going at v, over the truck (DsMachines.catcher) or the ground: as clods (each up to `spread`
## m/s off v, from within `within` m of p). -> how many mm it let go (no more than a truck has room for, with what's
## already falling into it, nor than POUR_MOST). What's under a crumb's worth, and all of it when there's no room for
## more clods, goes straight where it's bound: the truck's tray, or the ground under p.
## For `free` s they go through buckets' boxes (they're coming out of one).
func let_go(p: Vector3, m: int, n: int, truck, v := Vector3.ZERO, spread := 0.35, within := 0.08, free := DsDirt.POUR_FREE) -> int:
	if truck:
		n = mini(n, truck.room())
	n = mini(n, POUR_MOST)
	if n <= 0:
		return 0
	poured += n
	var d: DsDirt = site.dirt
	var whole = n - n % DsDirt.MM
	if d == null or not pour_clods or (truck and not d.has_room(4)):
		whole = 0
	var odd = n - whole
	if odd > 0:
		if truck:
			odd -= truck.take(m, odd)
		if odd > 0:
			# (a pour stops at the height it came from; what's left, if the heap's already that high, goes on top of it)
			odd -= site.terrain.pour(p, m, odd)
			if odd > 0:
				var c = site.terrain.cell_of(p)
				site.terrain.grid.put_layer(c.x, c.z, odd, m)
	if whole > 0:
		d.spawn_mass(p, v, m, whole, spread, within, free)
	return n

## How where it pours from (p, this step) is going: what it pours goes with it. Eased over an eighth of a second (a
## ram's jitter, a couple of cm in a step, is over a metre a second, and threw clods from an excavator's bucket 4 m up
## clean over the truck's cab), and none of a jump (carried somewhere by a test: it's standing).
func _pour_v(p: Vector3, dt: float) -> Vector3:
	var raw: Vector3 = (p - _pour_p) / maxf(dt, 0.001) if _pour_p.is_finite() else Vector3.ZERO
	_pour_p = p
	if raw.length() > 8.0:
		_pour_vel = Vector3.ZERO
	else:
		_pour_vel = _pour_vel.lerp(raw, minf(1.0, dt * 8.0))
	return _pour_vel
var _pour_p = Vector3.INF
var _pour_vel = Vector3.ZERO

## How long dirt takes to fall h m (from standing)
static func fall_time(h: float) -> float:
	return sqrt(2.0 * maxf(h, 0.0) / 9.8)

## A bucket's bite (mm by material, from DsTerrain.blade) less what its lip tears off: TEAR of it, in whole crumbs,
## let go as clods from a to b (the lip's ends) going at v and up, to tumble on ahead; and with `room` mm of room in
## the bucket, what's over that too (it's full: the rest rolls off). -> the counts that go in the bucket
func _tear(counts: PackedInt32Array, room: int, a: Vector3, b: Vector3, v: Vector3) -> PackedInt32Array:
	var d: DsDirt = site.dirt
	if d == null or not pour_clods:
		return counts
	for m in counts.size():
		var c = counts[m]
		if c <= 0:
			continue
		_tear_due += TEAR * c
		var off = 0
		if _tear_due >= DsDirt.CRUMB:
			off = mini(int(_tear_due) / DsDirt.CRUMB * DsDirt.CRUMB, c / DsDirt.CRUMB * DsDirt.CRUMB)
			_tear_due -= off
		if c - off > room:
			off += (c - off - room + DsDirt.CRUMB - 1) / DsDirt.CRUMB * DsDirt.CRUMB
			off = mini(off, c)
		room -= c - off
		counts[m] = c - off
		torn += off
		while off > 0:
			var one = mini(off, DsDirt.CLOD if d.randf01() < 0.4 else DsDirt.CRUMB)
			off -= one
			var p: Vector3 = a.lerp(b, d.randf01())
			d.spawn(p + Vector3(0, 0.12 + 0.1 * d.randf01(), 0), v + Vector3(d.randf01() - 0.5, 1.0 + 1.2 * d.randf01(), d.randf01() - 0.5), m, one, DsDirt.POUR_FREE)
	return counts
var _tear_due = 0.0

## The clods lying still in a box of it (in, the box's middle and axes in its own frame; half its size) taken into a
## load (material -> mm), up to room mm: -> the mm taken. Only where the dirt runs, and while there are clods at a
## bucket or a tray at all.
func _take_in(key: int, box: Transform3D, half: Vector3, room: int, load: Dictionary, dt: float) -> int:
	var d: DsDirt = site.dirt
	var was: Transform3D = _box_was.get(key, box)
	_box_was[key] = box
	if d == null or d.held_n == 0 or room <= 0:
		return 0
	return d.take_in(box, was, half, room, dt, load)
var _box_was = {}

func _shake_body(dt: float) -> void:
	if shake_node == null:
		return
	if driver == 0:
		shake_node.transform = Transform3D.IDENTITY
		return
	if _shake_clock == 0.0:
		_shake_clock = id * 1.7         # (not all in step)
	_shake_clock += dt
	var c = _shake_clock
	var work = clampf(absf(speed) / max_speed + effort_now, 0.0, 1.0)
	shake_node.position.y = sin(c * shake_hz) * (shake_idle + shake_work * work) + sin(c * shake_hz * 0.64) * shake_work * 0.3 * work
	shake_node.position.y += bob
	shake_node.rotation.z = sin(c * shake_hz * 0.4) * shake_pitch * work + shake_lean() + sway

## Its body rocking on its tracks, on both games (from what both know: its speed, its slip, where it is): nose up as it
## pulls away, down as it brakes or leans into a load, a spring that rocks once or twice; and a thud when it lands
func _weight_fx(dt: float) -> void:
	dt = clampf(dt, 0.001, 0.05)
	if not runs():
		# (the guest's: its tracks from the host's slip)
		lug = slip
		track_v = speed / (1.0 - slip) if slip < 0.9 else maxf(absf(speed), LUG_REVS * max_speed) * (signf(speed) if absf(speed) > 0.05 else 1.0)
	_acc = lerpf(_acc, clampf((speed - _speed_was) / dt, -8.0, 8.0), 1.0 - exp(-10.0 * dt))
	_speed_was = speed
	var want = clampf(_acc * SWAY_ACC - lug * SWAY_LOAD, -SWAY_MOST, SWAY_MOST) * sway_k
	if absf(bumped) > 0.4:
		_sway_v -= bumped * 0.14 * sway_k
		if sfx and driver != 0:
			sfx.clunked(clampf(absf(bumped) / 3.0, 0.1, 1.0) * clunk_weight)
	bumped = 0.0
	# (landing: it was coming down fast and it's stopped)
	var py = global_position.y
	var fall = 0.0 if is_nan(_y_was) else (py - _y_was) / dt
	_y_was = py
	if _fall_was < -THUD_FROM and _fall_was > -20.0 and fall > _fall_was * 0.3:
		_thud(-_fall_was)
	_fall_was = fall
	var n = clampi(ceili(dt * 90.0), 1, 4)
	var h = dt / n
	for i in n:
		_sway_v += (SWAY_HZ * SWAY_HZ * (want - sway) - 2.0 * SWAY_DAMP * SWAY_HZ * _sway_v) * h
		sway += _sway_v * h
		_bob_v += (-196.0 * bob - 9.8 * _bob_v) * h
		bob += _bob_v * h
	if absf(sway) > SWAY_END:
		sway = clampf(sway, -SWAY_END, SWAY_END)
		_sway_v = 0.0
	bob = clampf(bob, -0.09, 0.05)

## It's landed, coming down at v m/s: its body drops on its springs, its nose dips, a thump, dust from under it
func _thud(v: float) -> void:
	var k = clampf((v - THUD_FROM) / 4.0, 0.15, 1.0)
	_bob_v -= minf(v, 6.0) * 0.3
	_sway_v -= k * 0.25 * sway_k
	if sfx:
		sfx.clunked(k * clunk_weight * 1.2)
	if _thud_dust == null:
		var s = clampf(length / 5.0, 0.35, 1.0)
		_thud_dust = puffs(Color("#d6bd98"), 22, 1.1)
		_thud_dust.one_shot = true
		_thud_dust.explosiveness = 0.95
		_thud_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_thud_dust.emission_box_extents = Vector3(width * 0.55, 0.05, length * 0.5)
		_thud_dust.direction = Vector3(0, 1, 0)
		_thud_dust.spread = 75.0
		_thud_dust.initial_velocity_min = 0.6 * s
		_thud_dust.initial_velocity_max = 2.2 * s
		_thud_dust.gravity = Vector3(0, 0.2, 0)
		_thud_dust.scale_amount_min = 0.7 * s
		_thud_dust.scale_amount_max = 1.6 * s
		add_child(_thud_dust)
	_thud_dust.global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3(0, 0.1, 0))
	_thud_dust.restart()
	_thud_dust.emitting = true

## (a subclass) its tool at the end of its travel or resting on the ground, by what both games know of it
func at_stop() -> bool:
	return false

## (a subclass) how hard it's working besides driving (0 .. 1: an arm swinging, a tray going up)
func shake_effort() -> float:
	return 0.0

## (a subclass) how far it leans back under load (rad)
func shake_lean() -> float:
	return 0.0

## Its body solid to the loose dirt (the host's: the dirt runs there): a heap slumping, or soil sliding off a blade,
## banks against its tracks and wheels instead of flowing in under it (and lifting it up onto the pile)
func _block_body() -> void:
	var tr: DsTerrain = site.terrain
	if tr == null:
		return
	var f = forward()
	var r = right() * (width * 0.5)
	var front = Vector3(global_position.x, global_position.y, global_position.z) + f * (length * 0.5)
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
		var src = DsLook.clod_mesh(1).surface_get_arrays(0)
		var pts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var order: PackedInt32Array = src[Mesh.ARRAY_INDEX]
		var at = PackedVector3Array()
		var nrm = PackedVector3Array()
		var tint = PackedColorArray()
		var browns = [DsMats.COL[DsMats.DIRT], DsMats.COL[DsMats.DIRT].darkened(0.25), DsMats.COL[DsMats.TOPSOIL]]
		for k in range(0, order.size(), 3):
			var a = pts[order[k]] * 0.5
			var b = pts[order[k + 1]] * 0.5
			var c = pts[order[k + 2]] * 0.5
			var n = (c - a).cross(b - a).normalized()
			for p: Vector3 in [a, b, c]:
				at.append(p)
				nrm.append(n)
				tint.append(browns[(k / 3) % browns.size()])
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = at
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = tint
		_lump_mesh = ArrayMesh.new()
		_lump_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_lump_mat = StandardMaterial3D.new()
		_lump_mat.vertex_color_use_as_albedo = true
		_lump_mat.roughness = 1.0
	var p = CPUParticles3D.new()
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
func work_fx(at: Vector3, across: float, on: bool, face := NAN) -> void:
	if _work_dust == null:
		var k = clampf(length / 4.0, 0.4, 1.0)
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
		p.global_transform = Transform3D(Basis(Vector3.UP, yaw if is_nan(face) else face), at)
		p.emission_box_extents = Vector3(across, 0.2, 0.2)
		p.emitting = on

## A puff emitter (the digger game's): soft balls that grow and fade
static func puffs(colour: Color, amount: int, life: float) -> CPUParticles3D:
	var ball = SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 6
	ball.rings = 3
	var p = CPUParticles3D.new()
	p.mesh = ball
	var m = StandardMaterial3D.new()
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
	var fade = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade
	var grow = Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	return p

# dust off the tracks as it drives, exhaust from the stack while it's driven, dust where it pours
func _dust_fx() -> void:
	if _dust == null:
		# (sized to the machine: a Dingo's puffs are a third of a truck's)
		var k = clampf(length / 5.0, 0.35, 1.0)
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
		var ke = maxf(k, 0.8)
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
	# (its tracks slipping: dirt and dust thrown out behind them, the harder the more they slip)
	var spinning: bool = slip > 0.3 and absf(track_v) > 0.4 and driver != 0
	if spinning and _slip_dust == null:
		var k = clampf(length / 5.0, 0.35, 1.0)
		_slip_dust = puffs(Color("#b89a6e"), 26, 0.9)
		_slip_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_slip_dust.emission_box_extents = Vector3(width * 0.5, 0.05, 0.15)
		_slip_dust.spread = 28.0
		_slip_dust.initial_velocity_min = 1.2 * k
		_slip_dust.initial_velocity_max = 3.2 * k
		_slip_dust.gravity = Vector3(0, 0.3, 0)
		_slip_dust.scale_amount_min = 0.6 * k
		_slip_dust.scale_amount_max = 1.4 * k
		add_child(_slip_dust)
		_slip_clods = chunks(18)
		_slip_clods.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_slip_clods.emission_box_extents = Vector3(width * 0.5, 0.04, 0.1)
		_slip_clods.spread = 24.0
		_slip_clods.initial_velocity_min = 1.6 * k
		_slip_clods.initial_velocity_max = 4.0 * k
		_slip_clods.scale_amount_min = 0.16 * k
		_slip_clods.scale_amount_max = 0.42 * k
		add_child(_slip_clods)
	if _slip_dust:
		if spinning:
			var back = signf(track_v)
			var at = global_position - forward() * back * (length * 0.5) + Vector3(0, 0.12, 0)
			for p: CPUParticles3D in [_slip_dust, _slip_clods]:
				p.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
				p.direction = Vector3(0.0, 0.55, back)      # (out behind its tracks, and up: its forward's -z)
		_slip_dust.emitting = spinning
		_slip_clods.emitting = spinning and tracked
	_exhaust.global_position = exhaust_at()
	_exhaust.emitting = driver != 0
	# (its tracks or tyres wear the grass bare where they go: the digger game's track marks)
	if absf(speed) > 0.05 and site.terrain:
		site.terrain.wear_tracks(self)
	_exhaust.speed_scale = 0.6 + 0.8 * clampf(maxf(absf(throttle), lug), 0.0, 1.0)      # (worked hard, it puffs faster)
	# (the dust where it lands, once it's landed: as long after it starts pouring as it takes to fall, on both games)
	while not _dust_due.is_empty() and float(_dust_due[0][0]) <= _fx_clock:
		var d: Array = _dust_due.pop_front()
		_dust_left = 0.25
		_pour_dust.global_position = d[1]
	_dust_left -= get_process_delta_time()
	_pour_dust.emitting = _dust_left > 0.0

## (a subclass) what it's carrying (blocks; -1: nothing to carry) and where it comes out when it pours
func fx_load() -> int:
	return -1

func fx_pour_at() -> Vector3:
	return global_position

## Where what it pours lands under at (the ground; a truck's tray under it)
func fx_pour_floor(at: Vector3) -> float:
	var truck = site.machines.catcher(at, self) if site and site.machines else null
	if truck:
		return (truck.global_transform * DsTruck.TRAY_AT).y + 0.3
	return ground_y(at.x, at.z)

var _dust_due = []             # [when, where]: pour dust due where it lands
var _dust_left = 0.0

var _stream: CPUParticles3D
var _last_load = -1
var _stream_t = 0.0

# dirt falling where it pours (a bucket tipping, the excavator opening, the truck's tray up): whenever its load's going
# down, in both games (the guest's sees the load in the host's state)
func _pour_fx(dt: float) -> void:
	var n = fx_load()
	if n < 0:
		return
	if _last_load >= 0 and n < _last_load:
		_stream_t = 0.25
		var at = fx_pour_at()
		var floor = fx_pour_floor(at)
		_dust_due.append([_fx_clock + fall_time(at.y - floor), Vector3(at.x, floor + 0.3, at.z)])
	_last_load = n
	_stream_t -= dt
	var on = _stream_t > 0.0
	if on and _stream == null:
		_stream = CPUParticles3D.new()
		# (where the stream's real clods, solo or the host's, a few crumbs with them; a guest sees no clods yet)
		_stream.amount = 14 if runs() and pour_clods and site.dirt != null else 60
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
		var bm = BoxMesh.new()
		bm.size = Vector3.ONE * 0.08
		var m = StandardMaterial3D.new()
		m.albedo_color = Color8(122, 86, 52)
		m.roughness = 1.0
		bm.material = m
		_stream.mesh = bm
		add_child(_stream)
	if _stream:
		_stream.emitting = on
		if on:
			_stream.global_position = fx_pour_at()

## (a subclass) what's holding it back going dir (1 forward, -1 back), of its drive standing: 0 nothing, 1 and it
## stalls flat out (a blade's load, a bucket in a heap); between, flat out it settles at that much less of its top speed
func drive_resist(_dir: float) -> float:
	return 0.0

## (a subclass) its top speed now (a dozer's CUT: a steady job)
func top_speed() -> float:
	return max_speed

## (a subclass) looking ahead for a bank going dir: ground over this height's its tool's to cut, not a bank (INF: none is)
func cut_floor(_dir: float) -> float:
	return INF

## (the game that runs it) moves it by its controls over the ground
func _drive(dt: float) -> void:
	# its drive against what's holding it back, over its weight: flat out with nothing in its way it settles at its top
	# speed; held back by r, at (1 - r) of it; at r >= 1 it stalls, its tracks slipping
	var vt = throttle * top_speed() * (1.0 if throttle >= 0.0 else 0.7)
	var pull = accel * PULL
	var dir = signf(speed) if absf(speed) > 0.02 else signf(vt)      # (the way it's going, or trying to)
	var r = 0.0
	if dir != 0.0:
		r = maxf(drive_resist(dir), 0.0) + UPHILL * clampf(pitch * dir / max_climb, 0.0, 1.2)
	resist = r
	var a = pull * (vt - speed) / max_speed
	if absf(speed) > 0.02 and (is_zero_approx(vt) or signf(vt) != signf(speed)):
		a -= signf(speed) * accel * BRAKE
	if absf(speed) <= 0.02 and (absf(a) <= pull * r or is_zero_approx(vt)):
		speed = 0.0
	else:
		speed += (a - dir * pull * r) * dt
		# (what holds it back and its brakes stop it: they don't send it the other way)
		if speed * dir < 0.0 and signf(vt) != -dir:
			speed = 0.0
	# its turning, eased (and never changing faster than YAW_JERK)
	var turn_k = 1.0 - 0.5 * clampf(absf(speed) / max_speed, 0.0, 1.0)
	if turn_needs_speed:
		turn_k = clampf(absf(speed) / 1.5, 0.0, 1.0) * (1.0 if speed >= 0.0 else -1.0)    # (wheels: it turns as it rolls)
	var jerk = turn_rate * YAW_JERK * dt
	_yaw_v += clampf((-steer * turn_rate * turn_k - _yaw_v) * (1.0 - exp(-YAW_EASE * dt)), -jerk, jerk)
	var new_yaw = yaw + _yaw_v * dt
	_look_ahead(dt, new_yaw)
	var at = global_position
	var to = at + Vector3(-sin(new_yaw), 0, -cos(new_yaw)) * speed * dt
	# the site's fence
	var half: float = site.SIZE * 0.5 - 0.6
	to.x = clampf(to.x, site.AT.x - half, site.AT.x + half)
	to.z = clampf(to.z, site.AT.z - half, site.AT.z + half)
	var c = _corners(to, new_yaw)
	var hf = maxf(c[0], c[1])
	var hb = maxf(c[2], c[3])
	var top = maxf(hf, hb)
	var new_pitch = atan2(hf - hb, length)
	blocked = ""
	var going = speed * dt
	var uphill = new_pitch if going > 0.0 else -new_pitch      # (nose-up the way it's going)
	if absf(going) > 0.0:
		if top - at.y > step_up:
			blocked = "Too big a step: find a ramp"
		elif uphill > max_climb and uphill > _uphill_now(going):
			blocked = "Too steep for the %s" % kind
		elif _wall_ahead(to, new_yaw, signf(going), at.y):
			blocked = "Too steep for the %s" % kind
	if blocked != "":
		# (it's against a bank. It was braking for it if it saw it coming (_look_ahead), so there's little left to lose)
		if absf(speed) > absf(bumped):
			bumped = speed
		speed = 0.0
		_wall_gap = -1.0
		to = at
		c = _corners(at, new_yaw)
		top = maxf(maxf(c[0], c[1]), maxf(c[2], c[3]))
		hf = maxf(c[0], c[1])
		hb = maxf(c[2], c[3])
		new_pitch = atan2(hf - hb, length)
	yaw = new_yaw
	# its tracks: held back, they turn faster than it goes (slip), up to LUG_REVS of what's asked with it standing
	var s = 0.0
	if not is_zero_approx(vt) and signf(vt) == dir:
		s = 1.0 if blocked != "" else clampf((r - SLIP_FROM) / (1.0 - SLIP_FROM), 0.0, 1.0)
	_track_more = lerpf(_track_more, s * maxf((vt * LUG_REVS - speed) * signf(vt), 0.0) * signf(vt), 1.0 - exp(-TRACK_EASE * dt))
	if absf(_track_more) < 0.01:
		_track_more = 0.0
	track_v = speed + _track_more
	slip = clampf(1.0 - speed / track_v, 0.0, 1.0) if absf(track_v) > 0.15 and _track_more != 0.0 else 0.0
	lug = clampf(maxf(r, slip), 0.0, 1.0) if not is_zero_approx(vt) else 0.0
	# where it rests (the digger game's: on its corners' average, or a crest between its tracks if that's higher),
	# eased to, as are its pitch and roll (the owner, 9 Nov: "it's still so jumpy": it climbed each block's 12.5 cm
	# step in one frame, and the camera behind it jolted with it). Off a real drop it falls.
	var ml = ground_y(to.x - right().x * width * 0.5, to.z - right().z * width * 0.5)
	var mr = ground_y(to.x + right().x * width * 0.5, to.z + right().z * width * 0.5)
	var rest = maxf((c[0] + c[1] + c[2] + c[3]) * 0.25, maxf(ml, mr))
	var k = 1.0 - exp(-RIDE_EASE * dt)
	if rest < at.y - FALL_FROM or _vy < 0.0:
		_vy -= GRAVITY * dt
		to.y = maxf(rest, at.y + _vy * dt)
		if to.y <= rest:
			_vy = 0.0
	else:
		to.y = lerpf(at.y, rest, k)
	global_position = to
	var lean_f = (c[0] + c[1] - c[2] - c[3]) * 0.5
	var lean_r = (c[1] + c[3] - c[0] - c[2]) * 0.5
	pitch = lerpf(pitch, atan2(lean_f, length), k)
	roll = lerpf(roll, atan2(lean_r, width), k)

## A bank it's coming up to (the hard stop there was: it went from full speed to none in a frame): at speed it looks
## where it could just stop (its speed squared over twice what its brakes do) for what would stop it (_wall_ahead), and
## having seen it holds its speed to what it can still stop from in what's left, so it's nearly standing when it gets
## there. Not a bank after all (its blade's cut it away, it's turned off it): it's forgotten.
func _look_ahead(dt: float, yaw_: float) -> void:
	var dir = signf(speed)
	var stop = accel * PULL
	if _wall_gap >= 0.0 and (dir != _wall_dir or absf(angle_difference(yaw_, _wall_yaw)) > 0.12):
		_wall_gap = -1.0
	if _wall_gap < 0.0:
		if absf(speed) < LOOK_FROM:
			return
		var d = minf(speed * speed / (2.0 * stop) + absf(speed) * dt, LOOK_MOST)
		_cap_y = cut_floor(dir)
		var hit = _wall_ahead(global_position + Vector3(-sin(yaw_), 0, -cos(yaw_)) * dir * d, yaw_, dir, -INF)
		_cap_y = INF
		if not hit:
			return
		_wall_gap = d
		_wall_dir = dir
		_wall_yaw = yaw_
	_wall_gap -= absf(speed) * dt
	if _wall_gap < -0.4:
		_wall_gap = -1.0
		return
	var most = sqrt(2.0 * stop * maxf(_wall_gap, 0.0)) + 0.2
	if absf(speed) > most:
		speed = dir * maxf(most, absf(speed) - stop * 2.0 * dt)

## The ground just ahead of its leading corners rising steeper than it climbs (a pit's wall, a bank), measured from
## where it rides (base: its height now; a hole under a corner, its own bucket's bite, doesn't count)
func _wall_ahead(at: Vector3, yaw_: float, dir: float, base: float) -> bool:
	var f = Vector3(-sin(yaw_), 0, -cos(yaw_)) * dir
	var r = Vector3(cos(yaw_), 0, -sin(yaw_)) * (width * 0.5)
	var lead = at + f * (length * 0.5)
	var lim = tan(max_climb)
	for p in [lead - r, lead + r, lead]:
		# (loose dirt isn't a wall: tracks and wheels climb it or shove through it; a bank of firm ground is)
		var q: Vector3 = p + f * 0.3
		var from = maxf(base, ground_y(p.x, p.z))
		var rise = minf(minf(ground_y(q.x, q.z), site.terrain.firm_at(q.x, q.z)), _cap_y) - from
		if rise / 0.3 > lim and rise > 0.08:
			# (a lip it steps up onto isn't a wall: a bank is, rising on past what it steps up)
			var q2: Vector3 = p + f * wall_look
			if minf(minf(ground_y(q2.x, q2.z), site.terrain.firm_at(q2.x, q2.z)), _cap_y) - from > step_up:
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
	# (its tracks' slip rides with its driver: the whole number's who, the rest half the slip, so nothing's added)
	var f = PackedFloat32Array([global_position.x, global_position.y, global_position.z, yaw, pitch, roll, speed, float(driver) + clampf(slip, 0.0, 1.0) * 0.5])
	f.append_array(net_more())
	return f.to_byte_array()

func net_take(d: PackedByteArray) -> void:
	var f = d.to_float32_array()
	if f.size() < 8:
		return
	_to_pos = Vector3(f[0], f[1], f[2])
	_to = {"yaw": f[3], "pitch": f[4], "roll": f[5]}
	speed = f[6]
	driver = int(f[7])
	slip = clampf((f[7] - driver) * 2.0, 0.0, 1.0)
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
	var k = minf(1.0, dt * 12.0)
	if global_position.distance_to(_to_pos) > 4.0:
		k = 1.0
	global_position = global_position.lerp(_to_pos, k)
	yaw = lerp_angle(yaw, float(_to.yaw), k)
	pitch = lerpf(pitch, float(_to.pitch), k)
	roll = lerpf(roll, float(_to.roll), k)

## Its driver's controls (the guest's, to the host)
func net_cmds() -> PackedByteArray:
	var f = PackedFloat32Array([throttle, steer])
	f.append_array(_cmds_more())
	return f.to_byte_array()

func net_take_cmds(d: PackedByteArray) -> void:
	var f = d.to_float32_array()
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
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = DsLook.flat(col)
	mi.position = at
	parent.add_child(mi)
	return mi
