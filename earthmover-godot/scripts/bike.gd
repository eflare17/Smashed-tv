class_name Bike
extends Machine
## The dirt bike: light, quick, and it flies. It's worked out side-on, along the way it's heading: two wheels on springs, each
## pushed off the ground along the ground's own slope, so a lip throws it up and the slope of a landing catches it. Off the lip it
## keeps turning end over end the way the lip left it, and the rider eases it to follow its flight, as riders do. Sliding the
## thumb further up from where it was at take-off leans it forward, down leans it back. Land it roughly along the ground and it
## rides away; land it way off and the rider comes off, and the bike's put back a little before that jump. Hold MONO on the ground
## and the front comes up and stays up, the rider holding it there, till it's let go and he sets it back down.

signal crashed
signal landed(length: float, hit: float)

const MASS := 160.0              # kg: the bike and its rider (200 till the owner asked for it lighter, 10 Nov)
const SPIN_MASS := 34.0          # kg m2: how hard it is to turn end over end
const COM_UP := 0.78             # m: the middle of its weight above the ground, sitting on its springs
const MOUNT_DOWN := 0.2          # m: the tops of the springs below that
const REAR_X := -0.74
const FRONT_X := 0.71
const WHEELBASE := FRONT_X - REAR_X
const WHEEL_R := 0.36
const TRAVEL := 0.3              # m of spring at each wheel
const SPRING := 9000.0           # N/m
const SPRING_RISE := 300000.0    # N/m3: firmer the further it's pushed in
const STOPS := 250000.0          # N/m: past its travel it's on the stops
const DAMP_IN := 1300.0          # N for each m/s it's squashing
const DAMP_OUT := 2600.0         # and coming back out: slowly, so a big landing doesn't bounce it back up in the air
const RATE_MOST := 12.0          # m/s: the fastest a spring is taken to squash, so a sharp lump can't fire it off
const PUSH_MOST := 30000.0       # N: the most a wheel takes, about fifteen times the bike's weight
const TYRE_SAMPLES := 11         # points along under each tyre where it's found to touch
const TOP := 21.0                # m/s, about 75 km/h (17 till the owner asked for it faster, 10 Nov)
const BACK := 1.5                # m/s: walked backwards with the feet
const PULL := 10.0               # m/s2 the engine gives at most
const BRAKE := 7.5               # m/s2
const TYRE_GRIP := 0.9                # how much of the weight on a tyre it can push or brake with, on firm dirt
const TYRE_LOOSE := 0.75         # of that, on deep loose soil
const ROLL_DRAG := 0.02          # of the weight on the tyres
const AIR_DRAG := 0.4            # N for each (m/s)2
const SHIFT := 0.2               # the rider moves his weight about, so speeding up and braking tip it this much of what they would
const DRIVE_SHIFT := 0.6         # of the front tyre's load, that the back tyre grips with too when it's pulling
const STEER_MOST := 0.55        # radians at the bars at walking pace, less as it goes faster
const SIDE_MOST := 7.5           # m/s2: the most it turns hard, as tyres on dirt hold
const FOLLOW := 1.3              # each second, how much of the gap between where it points and where it's flying the rider takes up
const LEAN_RATE := 2.2           # rad/s end over end the rider can lean it at, full lean
const AIR_EASE := 6.0            # rad/s2: how quickly the rider can change how fast it's turning end over end
const LEAN_REACH := 1.0          # of the stick's reach, the thumb slid from where it was at take-off for full lean
const CRASH_ANGLE := 0.96        # radians, 55 degrees: landed this far off the ground's slope, the rider comes off
const CRASH_HIT := 13.0          # m/s straight into the ground: far too hard, even landed square
const CRASH_TIME := 3.0          # s after he comes off that he gets up, if he hasn't stopped and got up before (2.2 till the owner asked for 3, 10 Nov)
const UP_AFTER := 1.3            # s after he comes off before he'll get up, once he's stopped
const STOOD := 0.5               # s he stands there before he's back on the bike
const LIE_UP := 0.18             # m the bike's lifted lying on its side, so it's on the dirt and not in it
const BIKE_KG := 100.0           # the bike on its own, for when he lands on it
const THROW := 0.8               # of the bike's speed the rider's thrown off at: the rest is lost hitting the bars and the ground (1 sent him flying)
const STEPS_A_SECOND := 240.0    # the springs are worked out this often
const MONO_ANGLE := 0.55         # radians, about 32 degrees nose up from level: how high MONO holds the front up, as a rider
                                 # holds it short of where it'd tip over backwards, whatever the slope
const MONO_CLEAR := 0.2          # radians, about 11 degrees: the least it's held above an uphill slope, so the front stays off it
const MONO_FOLLOW := 5.0         # each second, how much of the gap to that the rider takes up
const MONO_RATE := 2.5           # rad/s at most, lifting the front or setting it back down
const MONO_EASE := 14.0          # rad/s2: how quickly he changes how fast it's coming up or down
const MONO_FROM := 1.0           # m/s: slower than this the front stays down
const MONO_LOOK := 0.7           # radians round from straight behind the chase view swings to on a wheelie, so it's seen

var y := 0.0                     # height of the middle of its weight
var vy := 0.0                    # m/s up
var pitch := 0.0                 # radians, nose up
var spin := 0.0                  # rad/s, nose up
var stretch: Array[float] = [TRAVEL, TRAVEL]   # each spring's length now, rear then front
var touching: Array[bool] = [false, false]
var airborne := false
var air_t := 0.0
var lean := 0.0                  # the rider's lean in the air, -1 back to 1 forward
var thumb_y := NAN               # where the driving thumb is up or down, in stick reaches, down positive; NAN with no thumb
var key_y := 0.0                 # the same off the keys: W is -1, S is 1
var crash_t := -1.0
var crash_why := ""              # what threw him off, to be told
var jump_m := 0.0                # how far the last jump went, shown for a bit
var jump_show := 0.0
var ridden := false
var roll_vis := 0.0              # the lean into a turn, or onto the stand
var mono := false                # MONO held
var mono_up := false             # the front's up on MONO, or being set back down
var mono_m := 0.0                # how far the wheelie's gone, shown while it goes and a bit after
var mono_show := 0.0

var _sample_gap := WHEEL_R * 1.9 / (TYRE_SAMPLES - 1)
var _squash: Array[float] = [0.0, 0.0]
var _push: Array[float] = [0.0, 0.0]
var _thumb_y0 := NAN
var _key_y0 := 0.0
var _keys_count := false
var _from := Vector2.ZERO        # where it left the ground
var _trail: Array[Array] = []    # where it's been on the ground lately: [spot, angle], a fifth of a second apart
var _trail_t := 0.0
var _back_to: Array = []         # where it's put back if he comes off
var _aim_y := 0.0
var _yaw_rate := 0.0
var _rider_shift := 0.0

var _all: Node3D                 # everything, set down so the ground's at 0 sitting on its springs
var _rear: Node3D
var _rear_wheel: MeshInstance3D
var _front: Node3D
var _front_wheel: MeshInstance3D
var _arm: MeshInstance3D
var _rider: Node3D
var _doll: Ragdoll               # the rider gone floppy, thrown off
var _crash_aim := Vector3.ZERO  # where the camera looks while he's off: him, not the bike
var _aim_back := 1.0             # 0 to 1: the camera on its way back to the bike once he's on it again
var _stand: MeshInstance3D
var _rear_roll := 0.0
var _front_roll := 0.0
var _mono_aim := NAN             # radians nose up the rider's holding it at, NAN when it's left to itself

const PIVOT := Vector3(-0.02, 0.5, 0.0)    # where the swingarm hangs off the frame

func setup(s: DirtSim, v: GroundView, mat: Material, at: Vector2, dir: Vector2) -> void:
	sim = s
	view = v
	spot = at
	angle = atan2(-dir.y, dir.x)
	machine_name = "Dirt bike"
	hint = "Thumb up to ride, hold MONO for a wheelie. In the air, slide your thumb further up to lean forward, down to lean back: land along the slope"
	stuck_word = "STUCK: back out and go round"
	mass = MASS
	top_speed = TOP
	back_speed = BACK
	_speed_cap = TOP
	support_x = 0.72
	support_z = 0.2
	track_z = 0.0
	track_rear = -REAR_X
	rut_lines = 1
	rut_half = 0.06
	rut_mm = 10
	view_dist = 7.5
	view_pitch = 13.0
	view_aim = 1.1
	eye = Vector3(0.12, 1.62, 0.0)
	pipe = Vector3(-0.78, 0.92, 0.17)
	fp_back = 0.95
	fp_front = 1.05
	fp_r = 0.35
	body_reach = 0.7
	_build(mat)
	_settle_on_ground()
	_place()

## ---------------------------------------------------------------- what it looks like

func _build(mat: Material) -> void:
	_all = Node3D.new()
	add_child(_all)
	var kit := MeshKit.new()
	Props.bike_body(kit)
	_add_mesh(_all, kit, mat)
	kit = MeshKit.new()
	Props.bike_swingarm(kit)
	_arm = _add_mesh(_all, kit, mat)
	_arm.position = PIVOT
	var wheel_kit := MeshKit.new()
	Props.wheel(wheel_kit, 0.12)
	var tyre := wheel_kit.mesh()
	_rear = Node3D.new()
	_all.add_child(_rear)
	_rear_wheel = MeshInstance3D.new()
	_rear_wheel.mesh = tyre
	_rear_wheel.material_override = mat
	_rear.add_child(_rear_wheel)
	_front = Node3D.new()
	_all.add_child(_front)
	_front_wheel = MeshInstance3D.new()
	_front_wheel.mesh = tyre
	_front_wheel.material_override = mat
	_front.add_child(_front_wheel)
	kit = MeshKit.new()
	Props.bike_fork_legs(kit)
	_add_mesh(_front, kit, mat)
	_rider = Node3D.new()
	_all.add_child(_rider)
	kit = MeshKit.new()
	Props.bike_rider(kit)
	_add_mesh(_rider, kit, mat)
	_doll = Ragdoll.new()
	add_child(_doll)
	_doll.setup(sim, mat)
	kit = MeshKit.new()
	kit.cone(Vector3(-0.1, 0.42, -0.16), Vector3(-0.22, 0.0, -0.42), 0.02, 0.02, 4, Props.BLACK)
	_stand = _add_mesh(_all, kit, mat)
	_stand.visible = false

func _add_mesh(parent: Node3D, kit: MeshKit, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = mat
	parent.add_child(m)
	return m

func show_driver(on: bool) -> void:
	ridden = on
	if crash_t < 0.0:
		_rider.visible = on

func gauge_word() -> Array:
	if crash_t >= 0.0:
		return ["OFF!", Color("#ff9a4a")]
	if mono_show > 0.0:
		return ["MONO %.1f m" % mono_m, Color("#ffd23f")]
	if jump_show > 0.0:
		return ["JUMP %.1f m" % jump_m, Color("#ffd23f")]
	return ["%d km/h" % roundi(Vector2(speed, vy).length() * 3.6), Color("#a8f07a")]

## Where the camera looks: the bike, or the rider while he's off it, and gliding back once he's on again.
func camera_aim() -> Vector3:
	var at := Vector3(position.x, _aim_y + view_aim, position.z)
	if crash_t >= 0.0:
		return _crash_aim
	if _aim_back < 1.0:
		return _crash_aim.lerp(at, smoothstep(0.0, 1.0, _aim_back))
	return at

## What's solid on the site for him to run into once he's off: `walls` as [a, b, radius, how high], and how far out he can go.
func crash_site(walls: Array, edge: float) -> void:
	_doll.walls = walls
	_doll.edge = edge

func effort() -> float:
	# Off the ground the throttle's still open and the engine screams.
	return clampf(absf(throttle) + (0.3 if airborne else 0.0), 0.0, 1.0)

func hit_speed() -> float:
	return absf(speed)

func stop_commands() -> void:
	super.stop_commands()
	mono = false

## Hit a tree: going at any lick, he's off.
func jolt() -> void:
	if absf(speed) > 3.0 and crash_t < 0.0:
		_crash("ran into something")
	else:
		speed *= 0.3

## In the air it's over anything parked, so only on the ground does it run into things.
func footprint() -> Array:
	if airborne and y - sim.height_at(spot) > COM_UP + 1.2:
		return [spot + Vector2(9999.0, 9999.0), spot + Vector2(9999.0, 9999.0), 0.0]
	return super.footprint()

## ---------------------------------------------------------------- each tick

func step(dt: float) -> void:
	jump_show = maxf(jump_show - dt, 0.0)
	if crash_t < 0.0:
		_aim_back = minf(_aim_back + dt * 2.0, 1.0)
	mono_show = maxf(mono_show - dt, 0.0)
	if crash_t >= 0.0:
		_crash_step(dt)
		_place()
		return
	if not ridden:
		throttle = 0.0
		steer = 0.0
		mono = false
		# Parked and still, it rests till the ground under it changes or someone gets on.
		if _resting(dt):
			return
	else:
		_rest_t = 0.0
	var was_air := airborne
	if airborne:
		lean = _air_lean()
	else:
		lean = 0.0
	_mono_step(dt)
	view_side = MONO_LOOK if mono_up else 0.0
	var n := maxi(ceili(dt * STEPS_A_SECOND), 1)
	var h := dt / n
	var hit := 0.0
	for k in n:
		hit = maxf(hit, _sub_step(h))
	var on := touching[0] or touching[1]
	if on:
		_steer(dt)
		if was_air:
			_landed(hit)
			if crash_t >= 0.0:
				_place()
				return
		airborne = false
		air_t = 0.0
		_remember(dt)
		_print_ruts()
		if absf(speed) > 0.05 and touching[0]:
			_wear_tracks()
	else:
		turn_cmd = move_toward(turn_cmd, steer, TURN_EASE * dt)
		_yaw_rate = 0.0
		if not airborne and _was_up(dt):
			_took_off()
		air_t += dt
	_check_upset()
	# Leaning into a turn, as far as the turn needs; parked, over onto its stand.
	var want_roll := clampf(atan2(speed * _yaw_rate, 9.8), -0.8, 0.8) if ridden else -0.24
	roll_vis = lerpf(roll_vis, want_roll, minf(dt * 6.0, 1.0))
	_stand.visible = not ridden and absf(speed) < 0.2
	_rider_shift = lerpf(_rider_shift, lean * 0.16 + (-0.07 if mono_up else 0.0) + clampf(-(speed - _last_speed) / dt * 0.01, -0.06, 0.06), minf(dt * 8.0, 1.0))
	_last_speed = speed
	_spin_my_wheels(dt)
	_place()
	_place_bumper()


var _rest_t := 0.0
var _offs := 0                   # times he's come off
var _rest_ground := Vector2.ZERO

## Parked: once it's been still a second it stops working anything out, until the ground under a wheel moves (a blade went by).
func _resting(dt: float) -> bool:
	var f := forward()
	var under := Vector2(sim.height_at(spot + f * REAR_X), sim.height_at(spot + f * FRONT_X))
	if _rest_t >= 1.0:
		if under.distance_to(_rest_ground) < 0.01:
			return true
		_rest_t = 0.0
		return false
	var still := absf(speed) < 0.03 and absf(vy) < 0.03 and absf(spin) < 0.03 and touching[0] and touching[1]
	_rest_t = _rest_t + dt if still else 0.0
	_rest_ground = under
	return false
var _last_speed := 0.0
var _up_for := 0.0

## Only a real hop counts as taking off, not a tyre skipping off a lump.
func _was_up(dt: float) -> bool:
	_up_for += dt
	return _up_for > 0.08

## One small step of the springs, the engine and the brakes. Returns how hard a wheel came down, m/s into the ground.
func _sub_step(h: float) -> float:
	var f := forward()
	var cp := cos(pitch)
	var sp := sin(pitch)
	var along := Vector2(cp, sp)       # the bike's length, side-on: x along the way it's heading, y up
	var up := Vector2(-sp, cp)
	var force := Vector2(0.0, -MASS * 9.8)
	var torque := 0.0
	var hit := 0.0
	var tans: Array[Vector2] = [Vector2.RIGHT, Vector2.RIGHT]
	var arms: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	var loose := 0.0
	for w in 2:
		var x := REAR_X if w == 0 else FRONT_X
		var mount := Vector2(0.0, y) + along * x - up * MOUNT_DOWN
		# The tyre's a circle: it rests on whichever bit of ground under it holds it highest, found along it and then
		# narrowed down between the samples, so the push turns smoothly as the slope under it changes. Off an edge it's the
		# edge it rolls over, pushing back and up, not a wall.
		var reach := mount.x - up.x * stretch[w]
		var best_k := 0
		var need := -INF
		var tops := PackedFloat32Array()
		tops.resize(TYRE_SAMPLES)
		for k in TYRE_SAMPLES:
			var d := (k - (TYRE_SAMPLES - 1) * 0.5) * _sample_gap
			var top := sim.height_at(spot + f * (reach + d)) + sqrt(maxf(WHEEL_R * WHEEL_R - d * d, 0.0))
			tops[k] = top
			if top > need:
				need = top
				best_k = k
		var d_best := (best_k - (TYRE_SAMPLES - 1) * 0.5) * _sample_gap
		if best_k > 0 and best_k < TYRE_SAMPLES - 1:
			var a := tops[best_k - 1]
			var c0 := tops[best_k + 1]
			var bend := a - 2.0 * tops[best_k] + c0
			if bend < -0.00001:
				d_best += clampf(0.5 * (a - c0) / bend, -0.5, 0.5) * _sample_gap
		var s := (mount.y - need) / maxf(up.y, 0.25)
		if s >= TRAVEL:
			stretch[w] = TRAVEL
			touching[w] = false
			_squash[w] = 0.0
			_push[w] = 0.0
			continue
		var touch := Vector2(reach + d_best, sim.height_at(spot + f * (reach + d_best)))
		var nrm := (Vector2(reach, need) - touch).normalized()
		# However sheer the ground, it can only push the bike back so hard: a tyre into a wall stops it, it doesn't fire it off.
		if nrm.y < 0.34:
			nrm = Vector2(signf(nrm.x) * 0.94, 0.34)
		var c := TRAVEL - s
		var rate := clampf((c - _squash[w]) / h, -RATE_MOST, RATE_MOST)
		if not touching[w]:
			# First touch: how fast it's coming into the ground, square on to it.
			var into := -(Vector2(speed, vy).dot(nrm))
			hit = maxf(hit, into)
			rate = clampf(into, 0.0, RATE_MOST)
		_squash[w] = c
		var push := SPRING * c + SPRING_RISE * c * c * c + (DAMP_IN if rate > 0.0 else DAMP_OUT) * rate
		if c > TRAVEL:
			push += STOPS * (c - TRAVEL) + DAMP_IN * 3.0 * rate
		push = clampf(push, 0.0, PUSH_MOST)
		_push[w] = push
		stretch[w] = clampf(s, 0.0, TRAVEL)
		touching[w] = true
		tans[w] = Vector2(nrm.y, -nrm.x)
		arms[w] = touch - Vector2(0.0, y)
		var at := spot + f * touch.x
		var fw := nrm * push
		force += fw
		torque += arms[w].x * fw.y - arms[w].y * fw.x
		var cell := DirtSim.cell_of(at)
		loose += sim.soil[clampi(cell.y, 0, DirtSim.CELLS - 1) * DirtSim.CELLS + clampi(cell.x, 0, DirtSim.CELLS - 1)] * 0.5
	# The tyres: the back one drives, both brake, each only as hard as its weight on the dirt lets it.
	if touching[0] or touching[1]:
		var grip := TYRE_GRIP * lerpf(1.0, TYRE_LOOSE, clampf(loose / 200.0, 0.0, 1.0))
		var tan := (tans[0] if touching[0] else tans[1])
		var v := Vector2(speed, vy).dot(tan)
		var want := 0.0                    # N along the ground, forward
		var on_back_only := true
		if throttle > 0.05:
			var target := TOP * (0.25 * minf(throttle / 0.1, 1.0) + 0.75 * throttle)
			want = clampf((target - v) * MASS * 2.0, -1.5 * MASS, PULL * MASS)
		elif throttle < -0.05 and v > 0.3:
			want = -BRAKE * MASS * minf(-throttle * 1.3, 1.0)
			on_back_only = false
		elif throttle < -0.05:
			want = clampf((throttle * BACK - v) * MASS * 2.0, -2.0 * MASS, 2.0 * MASS)
		elif absf(v) < 0.6:
			# Nothing asked: he holds it on the brake, even on a slope.
			want = -(v * MASS / h) * 0.5 - force.dot(tan)
			on_back_only = false
		else:
			# Off the throttle it slows on the engine, and stops in a few seconds.
			want = -signf(v) * 2.0 * MASS
		# Pulling, the rider's weight and the pull itself shift most of the front's load onto the back tyre (more than the bike's
		# shown tipping back, which SHIFT keeps small), so it grips with that too.
		var most := grip * (_push[0] + (DRIVE_SHIFT * _push[1] if on_back_only else _push[1]))
		var got := clampf(want, -most, most)
		var drag := -signf(v) * ROLL_DRAG * (_push[0] + _push[1])
		for w in 2:
			if not touching[w]:
				continue
			var share := (1.0 if w == 0 else 0.0) if on_back_only else _push[w] / maxf(_push[0] + _push[1], 1.0)
			var fw := tans[w] * (got * share + drag * _push[w] / maxf(_push[0] + _push[1], 1.0))
			force += fw
			torque += (arms[w].x * fw.y - arms[w].y * fw.x) * SHIFT
	var vel := Vector2(speed, vy)
	force -= vel * vel.length() * AIR_DRAG
	speed += force.x / MASS * h
	vy += force.y / MASS * h
	if not is_nan(_mono_aim) and touching[0]:
		# On MONO the rider holds the front up where he wants it with the throttle and his weight, or sets it back down.
		var want_up := clampf((_mono_aim - pitch) * MONO_FOLLOW, -MONO_RATE, MONO_RATE)
		spin = move_toward(spin, want_up, MONO_EASE * h)
	elif touching[0] or touching[1]:
		spin += torque / SPIN_MASS * h
	else:
		# In the air: the rider eases it to follow its flight, and leans it on top of that.
		var path := atan2(vy, maxf(absf(speed), 0.5)) if speed >= 0.0 else -atan2(vy, absf(speed))
		var want_spin := wrapf(path - pitch, -PI, PI) * FOLLOW - lean * LEAN_RATE
		spin = move_toward(spin, want_spin, AIR_EASE * h)
	spin = clampf(spin, -6.0, 6.0)
	pitch = wrapf(pitch + spin * h, -PI, PI)
	var next := spot + f * speed * h
	var held := next.clamp(Vector2(-AREA, -AREA), Vector2(AREA, AREA))
	at_edge = held != next
	if at_edge:
		speed = 0.0
	spot = held
	y += vy * h
	# Nothing it meets should ever fling it faster than a bike can go.
	speed = clampf(speed, -25.0, 25.0)
	vy = clampf(vy, -30.0, 30.0)
	return hit

## Steering, on the ground: road-style, gentler the faster it goes, never tighter than its tyres hold.
func _steer(dt: float) -> void:
	_up_for = 0.0
	turn_cmd = move_toward(turn_cmd, steer, TURN_EASE * dt)
	var most := STEER_MOST * lerpf(1.0, 0.3, clampf(absf(speed) / TOP, 0.0, 1.0))
	var turning := speed / WHEELBASE * tan(turn_cmd * most)
	var cap := SIDE_MOST / maxf(absf(speed), 0.5)
	_yaw_rate = clampf(turning, -cap, cap) if touching[1] or mono_up else 0.0
	angle -= _yaw_rate * dt

## The thumb slid up from where it was as it left the ground leans it forward, down leans it back. A thumb put down in the air
## starts from level. The keys: W or S held through take-off do nothing till they're let go.
func _air_lean() -> float:
	var l := 0.0
	if not is_nan(thumb_y):
		if is_nan(_thumb_y0):
			_thumb_y0 = thumb_y
		l = -(thumb_y - _thumb_y0) / LEAN_REACH
	else:
		_thumb_y0 = NAN
	if key_y != _key_y0:
		_keys_count = true
	if _keys_count:
		l -= key_y
	return clampf(l, -1.0, 1.0)

func _took_off() -> void:
	_mono_end()
	airborne = true
	air_t = 0.0
	_from = spot
	_thumb_y0 = thumb_y
	_key_y0 = key_y
	_keys_count = false
	# Put back to where it was a couple of seconds before, for a run at it again.
	_back_to = _trail[maxi(_trail.size() - 10, 0)] if not _trail.is_empty() else [spot, angle]

## Back on the ground: how it landed.
func _landed(hit: float) -> void:
	if air_t < 0.25:
		return
	var off := absf(wrapf(pitch - _ground_angle(), -PI, PI))
	if off > CRASH_ANGLE or hit > CRASH_HIT:
		_crash("came down too hard" if hit > CRASH_HIT else ("landed nose first" if pitch < _ground_angle() else "landed with the nose too high"))
		return
	_back_to = []
	var length := spot.distance_to(_from)
	if length > 2.0:
		jump_m = length
		jump_show = 3.0
		mono_show = 0.0
	landed.emit(length, hit)

## The slope of the ground under it, along the way it's heading, in radians.
func _ground_angle() -> float:
	var f := forward()
	var back := sim.height_at(spot + f * REAR_X)
	var front := sim.height_at(spot + f * FRONT_X)
	return atan2(front - back, WHEELBASE)

## Upside down, or its middle on the ground: he's off.
func _check_upset() -> void:
	if crash_t >= 0.0:
		return
	var off := absf(wrapf(pitch - (_rear_slope() if mono_up else _ground_angle()), -PI, PI))
	if off > 1.4 or y < sim.height_at(spot) + 0.3:
		_crash("went over")

## Where it's been on the ground lately, for putting it back.
func _remember(dt: float) -> void:
	_trail_t += dt
	if _trail_t < 0.2 and not _trail.is_empty():
		return
	_trail_t = 0.0
	_trail.append([spot, angle])
	if _trail.size() > 30:
		_trail.pop_front()

## ---------------------------------------------------------------- coming off

func _crash(why: String) -> void:
	_crash_aim = camera_aim()
	_aim_back = 1.0
	_mono_end()
	crash_why = why
	crash_t = 0.0
	airborne = false
	if _back_to.is_empty():
		_back_to = _trail[maxi(_trail.size() - 10, 0)] if not _trail.is_empty() else [spot, angle]
	# The rider goes on without it, floppy, turning end over end as the bike was.
	var side := Vector3(sin(angle), 0.0, cos(angle))
	_rider.visible = false
	# He rolls the way it was turning, or one way then the other.
	_offs += 1
	var roll_way := signf(turn_cmd) if absf(turn_cmd) > 0.1 else (1.0 if _offs % 2 == 0 else -1.0)
	_doll.throw(transform * _all.transform * _rider.transform, Vector3(forward().x * speed * THROW, vy + 0.4, forward().y * speed * THROW), side, spin, roll_way)
	crashed.emit()

func _crash_step(dt: float) -> void:
	crash_t += dt
	# The bike goes over on its side and slides to a stop.
	speed = move_toward(speed, 0.0, 7.0 * dt)
	var next := (spot + forward() * speed * dt).clamp(Vector2(-AREA, -AREA), Vector2(AREA, AREA))
	spot = next
	var ground := sim.height_at(spot)
	vy -= 9.8 * dt
	# Lying over, it rests on its side on the dirt.
	var lying := ground + COM_UP + LIE_UP * clampf(roll_vis / 1.35, 0.0, 1.0)
	y = maxf(y + vy * dt, lying)
	if y <= lying:
		vy = 0.0
	pitch = lerp_angle(pitch, _ground_angle(), minf(dt * 5.0, 1.0))
	roll_vis = lerpf(roll_vis, 1.35, minf(dt * 5.0, 1.0))
	# The rider: thrown, flopping and sliding, then lying where he ends up.
	# He can land on the bike, or it can slide into him: either way each shoves the other.
	var f := forward()
	_doll.bike_a = transform * Vector3(REAR_X, 0.55, 0.0)
	_doll.bike_b = transform * Vector3(FRONT_X, 0.55, 0.0)
	_doll.bike_vel = Vector3(f.x * speed, 0.0, f.y * speed)
	_doll.bike_solid = true
	_doll.step(dt)
	speed += _doll.shoved.dot(Vector3(f.x, 0.0, f.y)) / BIKE_KG
	_doll.shoved = Vector3.ZERO
	var hips := (_doll.points[Ragdoll.HIP_L] + _doll.points[Ragdoll.HIP_R]) * 0.5
	_crash_aim = _crash_aim.lerp(hips + Vector3(0.0, 0.45, 0.0), minf(dt * 5.0, 1.0))
	# Once he's stopped he gets up, and a moment after he's on his feet he's back on it.
	if (crash_t > UP_AFTER and _doll.settled()) or crash_t > CRASH_TIME:
		_doll.get_up()
	if _doll.stood() > STOOD:
		_put_back()

## Back on it, stopped, a little before the jump that threw him.
func _put_back() -> void:
	crash_t = -1.0
	_aim_back = 0.0
	spot = _back_to[0]
	angle = _back_to[1]
	_back_to = []
	speed = 0.0
	vy = 0.0
	spin = 0.0
	lean = 0.0
	airborne = false
	air_t = 0.0
	roll_vis = 0.0
	_mono_end()
	_doll.visible = false
	_rider.visible = ridden
	_settle_on_ground()

## The game's put it somewhere (a job's start, out of the way): set straight down there, stopped, the rider on it if he's riding.
func _settle(_k: float) -> void:
	_rest_t = 0.0
	_aim_back = 1.0
	if crash_t >= 0.0:
		crash_t = -1.0
		_doll.visible = false
		_rider.visible = ridden
	vy = 0.0
	spin = 0.0
	airborne = false
	air_t = 0.0
	_mono_end()
	_back_to = []
	_trail.clear()
	_settle_on_ground()
	_place()

## Straight onto its wheels where it stands, sitting on its springs.
func _settle_on_ground() -> void:
	pitch = _ground_angle()
	var sag := _sag()
	y = maxf(sim.height_at(spot + forward() * REAR_X), sim.height_at(spot + forward() * FRONT_X)) + MOUNT_DOWN + TRAVEL - sag + WHEEL_R
	_aim_y = y - COM_UP
	for w in 2:
		stretch[w] = TRAVEL - sag
		_squash[w] = sag
		touching[w] = true

## How far each spring's squashed with the bike standing still on flat ground, each wheel taking half its weight.
static func _sag() -> float:
	var c := 0.08
	for k in 8:
		c -= (SPRING * c + SPRING_RISE * c * c * c - MASS * 4.9) / (SPRING + 3.0 * SPRING_RISE * c * c)
	return c

## ---------------------------------------------------------------- the wheelie

## MONO held, on the back wheel and going: the front comes up to MONO_ANGLE and stays there. Let go (or too slow) and it's set
## back down till the front tyre touches. How far it went is counted while the front's off the ground.
func _mono_step(dt: float) -> void:
	var on_back := touching[0] and not airborne
	var ground := _ground_angle()
	if mono and on_back and speed > MONO_FROM:
		if not mono_up:
			mono_up = true
			mono_m = 0.0
		_mono_aim = maxf(MONO_ANGLE, _rear_slope() + MONO_CLEAR)
	elif mono_up and on_back and not touching[1] and pitch - ground > 0.03:
		_mono_aim = ground
	else:
		_mono_end()
		return
	if not touching[1]:
		mono_m += absf(speed) * dt
		# A jump just landed is shown for a moment first.
		if mono_m > 1.0 and jump_show < 1.5:
			mono_show = 3.0
			jump_show = 0.0

## The slope of the ground under the back tyre alone, along the way it's heading: on a wheelie the front's nowhere near the
## ground, so the ground under it says nothing.
func _rear_slope() -> float:
	var f := forward()
	var x := REAR_X * cos(pitch) + (MOUNT_DOWN + stretch[0]) * sin(pitch)
	return atan2(sim.height_at(spot + f * (x + 0.3)) - sim.height_at(spot + f * (x - 0.3)), 0.6)

## Back to the bike left to itself. What it went is still shown for a bit.
func _mono_end() -> void:
	mono_up = false
	_mono_aim = NAN

## ---------------------------------------------------------------- placing it

## The whole bike from where it is: tipped end over end, then leaned over about the line its tyres touch along.
func _place() -> void:
	var f := forward()
	var along := Vector3(f.x * cos(pitch), sin(pitch), f.y * cos(pitch))
	var up := Vector3(-f.x * sin(pitch), cos(pitch), -f.y * sin(pitch))
	var across := along.cross(up)
	var b := Basis(along, up, across) * Basis(Vector3.RIGHT, roll_vis)
	var mid := Vector3(spot.x, y, spot.y)
	var low := mid - up * COM_UP
	transform = Transform3D(b, low)
	_aim_y = lerpf(_aim_y, low.y, 0.12)
	var mount := COM_UP - MOUNT_DOWN
	_rear.position = Vector3(REAR_X, mount - stretch[0], 0.0)
	_front.position = Vector3(FRONT_X, mount - stretch[1], 0.0)
	_front.basis = Basis(Vector3.UP, -turn_cmd * 0.35)
	_rear_wheel.basis = Basis(Vector3.BACK, _rear_roll).scaled(Vector3(WHEEL_R, WHEEL_R, 1.0))
	_front_wheel.basis = Basis(Vector3.BACK, _front_roll).scaled(Vector3(WHEEL_R, WHEEL_R, 1.0))
	# The swingarm reaches from its pivot to the back axle.
	var to_axle := _rear.position - PIVOT
	_arm.basis = Basis(Vector3.BACK, atan2(-to_axle.y, -to_axle.x)) * Basis.from_scale(Vector3(to_axle.length(), 1.0, 1.0))
	if crash_t < 0.0:
		_rider.position = Vector3(_rider_shift, 0.0, 0.0)

func _spin_my_wheels(dt: float) -> void:
	var v := speed
	# In the air with the throttle open, the back wheel spins up; off it, it slows.
	_rear_roll = fposmod(_rear_roll - (v + (throttle * 10.0 if not touching[0] else 0.0)) / WHEEL_R * dt, TAU)
	_front_roll = fposmod(_front_roll - v / WHEEL_R * dt, TAU)

## What hits a tree first: the front wheel.
func _place_bumper() -> void:
	var front := spot + forward() * (FRONT_X + WHEEL_R)
	blade_a = front
	blade_b = front

## ---------------------------------------------------------------- online

func _net_more() -> PackedFloat32Array:
	var s := PackedFloat32Array([y, pitch, roll_vis, stretch[0], stretch[1], _rider_shift, crash_t, 0.0, 0.0, 0.0, 0.0, jump_m, jump_show, float(airborne), float(ridden), mono_m, mono_show, float(mono_up)])
	# Thrown off, where each bit of him is.
	if crash_t >= 0.0:
		s.append_array(_doll.net_points())
	return s

func _net_take_more(s: PackedFloat32Array) -> void:
	var k := NET_BASE
	_net_bike = s.slice(k, k + 18 + Ragdoll.COUNT * 3)

var _net_bike := PackedFloat32Array()

func _net_pose(dt: float, k: float) -> void:
	if _net_bike.size() < 18:
		return
	var b := _net_bike
	y = lerpf(y, b[0], k)
	pitch = lerp_angle(pitch, b[1], k)
	roll_vis = lerpf(roll_vis, b[2], k)
	stretch[0] = b[3]
	stretch[1] = b[4]
	_rider_shift = b[5]
	var was_crash := crash_t >= 0.0
	crash_t = b[6]
	jump_m = b[11]
	jump_show = b[12]
	airborne = b[13] > 0.5
	mono_m = b[15]
	mono_show = b[16]
	mono_up = b[17] > 0.5
	view_side = MONO_LOOK if mono_up else 0.0
	if crash_t >= 0.0:
		_rider.visible = false
		_doll.net_take(b.slice(18), k if was_crash else 1.0)
	elif was_crash:
		_doll.visible = false
		_rider.visible = ridden
	_spin_my_wheels(dt)
	_place()

func _net_cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([99.0 if is_nan(thumb_y) else thumb_y, key_y, 1.0 if mono else 0.0])

func _net_take_cmds_more(c: PackedFloat32Array) -> void:
	if c.size() < 4:
		return
	thumb_y = NAN if c[2] > 98.0 else c[2]
	key_y = c[3]
	mono = c.size() > 4 and c[4] > 0.5
