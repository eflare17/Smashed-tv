class_name Excavator
extends Machine
## The excavator. Its tracks only move it about; the work is done by the house turning on them and the arm reaching out from it.
## The player moves the bucket's pin up, down, in and out, and the boom and stick work out how to get it there. Soil the teeth
## cut goes in the bucket and is really gone from the ground, and tipping the bucket drops it as real falling chunks.
## Every number here is a first guess, to tune by feel.

const MASS := 22000.0           # kg
const TOP_SPEED := 1.5          # m/s: an excavator is slow on its tracks
const BACK_SPEED := 1.5
const TURN := 0.55              # rad/s

const SHOULDER := Vector2(1.0, 1.85)   # where the boom meets the house: out from the middle, up from the ground
const ARM_Z := 0.25             # the arm sits to the right of the middle, with the cab beside it
const BOOM := 5.6               # m
const STICK := 2.9
const BUCKET_GROW := 1.2        # the bucket's drawn 20% bigger all round than first built, to fit the 1.8x load (owner's ask, 8 Nov)
const BUCKET := 1.35 * BUCKET_GROW        # pin to teeth
const BUCKET_HALF := 0.62 * BUCKET_GROW   # half its width
const BOOM_LOW := -0.87         # radians from level: about 50 degrees below
const BOOM_HIGH := 1.2
const ELBOW_MIN := 0.55         # radians between boom and stick, fully folded in
const ELBOW_MAX := 2.85
const NEAREST := 2.7            # m from the middle the pin can come in to: any nearer and the bucket hits the machine

const REACH_SPEED := 2.3        # m a second, the pin moving out or in
const RAISE_SPEED := 2.0
const SWING_SPEED := 0.8        # rad a second
const CURL_SPEED := 1.7
const ARM_EASE := 5.0           # how quick the arm is to reach the speed asked for, per second
const SWING_EASE := 1.7         # the house is heavy: it takes a moment to start and stop turning

const CURL_MIN := 0.3           # radians: bucket tipped fully out, teeth pointing away and open side down
const CURL_MAX := 3.5           # curled fully in, open side up
const CURL_HOLDS := 2.3         # curled this far or more it keeps its whole load
const CURL_EMPTY := 0.95        # opened this far, it holds nothing
const CURL_ASSIST := 0.8        # rad a second it curls by itself while being dragged through the soil

const CURL_LIFT := 1.6          # rad a second it curls by itself, lifting a load
## The load was 1.2 m3; the owner found that felt like nothing next to the dozer, so it's 1.8x, and it digs and tips that much faster.
const CAPACITY := 34560         # mm on one cell's area: 2.16 m3 heaped (the big one, 1.9x, about 14.8 m3)
const HEAPED := 27000           # over this it's heaped, and a fast move shakes some off
const POUR_RATE := 28800        # mm a second, tipping out at most: a full bucket empties as quick as before
const CHUNK := 480              # mm a falling chunk carries (0.03 m3)
const FIRM_RATE := 9           # mm of firm ground the teeth take from a cell in a tick (with the wider bucket, about 1.8x as fast)
const SWEEP := 0.22             # m the teeth travel to clear what stands in front of them
const BOG_AT := 1800.0          # mm a tick it takes to slow the arm right down
const STAB_MOST := 0.8          # m the teeth can be pushed into ground without dragging

var dig_mode := true            # the left thumb swings the house, or drives the tracks
var swing_cmd := 0.0
var reach_cmd := 0.0
var raise_cmd := 0.0
var curl_cmd := 0.0

var swing := 0.0                # radians, the house against the tracks
var wrist := Vector2(5.2, 2.7)  # the bucket's pin, in the house's own up-and-out plane
var curl := 2.7
var bucket_mm := 0
var bucket_dust := 0
var _pour_dust := 0
var _mat: Material
var stopped_by_rock := false
var _swing_blocked := false
## The teeth meeting something buried (a job's find): how fast they were going, in m a second, for the game to read and set back
## to -1. Faster than KNOCK_SPEED (times the machine's size) is a knock that marks it.
var touch_speed := -1.0
const KNOCK_SPEED := 1.6     # m a second per size: only a slam, a curl or swing into it near flat out (the owner found half stick too strict)
const SOFT_LANDING := 0.35   # m per size over something buried that the bucket eases off coming down
const SOFT_SLOWEST := 0.3    # how fast it's still coming down as it lands, of what was asked
## The pegged-out pad it's digging, if any: the readout says how much more there is to take out where the teeth are.
var pad: Pad

var _boom_a := 0.0
var _stick_a := 0.0
var _v_swing := 0.0
var _v_reach := 0.0
var _v_raise := 0.0
var _v_curl := 0.0
var _house: Node3D
var _boom: MeshInstance3D
var _stick: MeshInstance3D
var _bucket: MeshInstance3D
var _lump: MeshInstance3D
var _rams: Array[MeshInstance3D] = []
var _bucket_speed := 0.0
var _bucket_dir := Vector2.ZERO
var _pour_store := 0
var _rng := RandomNumberGenerator.new()
var _house_rock := 0.0
var _house_rock_vel := 0.0
var _clock := 0.0
var _at_limit := false

func setup(s: DirtSim, v: GroundView, mat: Material, at: Vector2, dir: Vector2) -> void:
	sim = s
	view = v
	spot = at
	angle = atan2(-dir.y, dir.x)
	machine_name = "Excavator" if size == 1.0 else "Big excavator"
	hint = "Reach OUT, go DOWN, pull IN through the dirt, then UP, SWING and DUMP"
	view_dist = 16.0 * (sqrt(size) * 1.15 if size > 1.0 else 1.0)
	view_pitch = 27.0
	fp_back = 2.4 * size
	fp_front = 2.4 * size
	fp_r = 1.6 * size
	mass = MASS * size * size * size
	engine = ENGINE * size * size * size
	body_reach *= size
	top_speed = TOP_SPEED
	back_speed = BACK_SPEED
	turn_rate = TURN
	support_x = 1.9 * size
	support_z = 1.25 * size
	track_z = 1.25 * size
	track_rear = 1.8 * size
	_speed_cap = TOP_SPEED
	_rng.seed = 21
	var carriage := MeshKit.new()
	Props.track_frames(carriage, 1.25, 0.32, 1.9, 2.4, 2.05, size > 1.0)
	Props.excavator_carriage(carriage)
	_add_mesh(self, carriage, mat)
	tracks = TrackRig.new()
	add_child(tracks)
	tracks.setup(mat, Props.track_path(1.9, 2.43, 2.07), 1.25, 0.66, 1.59, Props.excavator_wheels())
	_house = Node3D.new()
	add_child(_house)
	var house_kit := MeshKit.new()
	Props.excavator_house(house_kit, size > 1.0)
	_add_mesh(_house, house_kit, mat)
	if size > 1.0:
		_add_beacon(_house, Vector3(0.0, 3.12 + Props.MINE_CAB_UP, -0.8), mat)
	var kit := MeshKit.new()
	Props.excavator_boom(kit, BOOM, size > 1.0)
	_boom = _add_mesh(_house, kit, mat)
	kit = MeshKit.new()
	Props.excavator_stick(kit, STICK, size > 1.0)
	_stick = _add_mesh(_house, kit, mat)
	kit = MeshKit.new()
	# Built at its first size and drawn BUCKET_GROW bigger (in _pose), so its shape and the soil in it grow together.
	Props.excavator_bucket(kit, BUCKET / BUCKET_GROW, BUCKET_HALF / BUCKET_GROW, size > 1.0)
	_bucket = _add_mesh(_house, kit, mat)
	kit = MeshKit.new()
	kit.box(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0), Props.DIRT, Basis(Vector3.RIGHT, 0.05))
	_lump = _add_mesh(_bucket, kit, mat)
	_lump.visible = false
	_mat = mat
	for k in 3:
		kit = MeshKit.new()
		kit.cone(Vector3.ZERO, Vector3(0.62, 0.0, 0.0), 0.1, 0.1, 6, Props.CHARCOAL)
		kit.cone(Vector3(0.62, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), 0.05, 0.05, 6, Props.STEEL)
		_rams.append(_add_mesh(_house, kit, mat))
	y_smooth = sim.track_height_at(spot)
	_settle(1.0)
	_solve(wrist)
	_pose()
	teeth = _teeth_now()
	blade_a = Vector2(teeth.x, teeth.z)
	blade_b = blade_a

func _add_mesh(parent: Node3D, kit: MeshKit, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = mat
	parent.add_child(m)
	return m

## The way the house faces, on the ground.
func house_forward() -> Vector2:
	var a := angle + swing
	return Vector2(cos(a), -sin(a))

func view_forward() -> Vector2:
	return house_forward() if dig_mode else forward()

## In dig mode the camera looks at the work, ahead of the machine, rather than at the machine.
func camera_aim() -> Vector3:
	if not dig_mode:
		return position + Vector3(0.0, 1.8 * size, 0.0)
	var f := house_forward()
	return position + Vector3(f.x * 2.5, 1.4, f.y * 2.5) * size

func exhaust_point() -> Vector3:
	return _house.to_global(Vector3(-1.72, 3.05, 0.8))

func cab_eye() -> Vector3:
	return _house.to_global(Vector3(0.6, 2.55 + (Props.MINE_CAB_UP if size > 1.0 else 0.0), -0.8))

func effort() -> float:
	return maxf(absf(throttle), hyd * 0.8)

func hit_speed() -> float:
	return _bucket_speed

func push_dir() -> Vector2:
	return _bucket_dir if _bucket_speed > 0.1 else forward()

func stop_commands() -> void:
	super()
	swing_cmd = 0.0
	reach_cmd = 0.0
	raise_cmd = 0.0
	curl_cmd = 0.0

func gauge_word() -> Array:
	if on_rock:
		# Resting on something buried, it's no rock: it's what the job's after.
		if _gap_to_find(teeth) < 0.3:
			return ["ON IT: GENTLY", Color("#ffd23f")]
		return ["ROCK: CAN'T DIG", Color("#ff9a4a")]
	var word := "BUCKET %.1f m3" % DirtSim.to_m3(bucket_mm)
	var at := Vector2(teeth.x, teeth.z)
	if pad and pad.inside(at):
		var left := sim.height_at(at) - pad.level
		if left > pad.tol_up:
			return [word + "   %.1f m TO THE FLOOR" % left, Color("#ff9a4a")]
		if left < -pad.tol_down:
			return [word + "   TOO DEEP %.1f m" % -left, Color("#7ab8ff")]
		return [word + "   AT THE FLOOR", Color("#a8f07a")]
	var deep := teeth_depth()
	if deep > 0.03:
		return [word + "   IN %.1f m" % deep, Color("#ff9a4a")]
	return [word, Color("#a8f07a")]

func fill() -> float:
	return float(bucket_mm) / capacity()

## What its bucket holds, heaped: a big one's bucket is bigger every way.
func capacity() -> int:
	return int(CAPACITY * size * size * size)

## How far below the ground the teeth are, in m.
func teeth_depth() -> float:
	return sim.height_at(Vector2(teeth.x, teeth.z)) - teeth.y

## Sets the boom and stick to bring the pin as near to `want` as they can reach, and leaves the pin where it actually got to.
func _solve(want: Vector2) -> void:
	var w := Vector2(maxf(want.x, NEAREST), want.y)
	var v := w - SHOULDER
	var far := sqrt(BOOM * BOOM + STICK * STICK - 2.0 * BOOM * STICK * cos(ELBOW_MAX))
	var near := sqrt(BOOM * BOOM + STICK * STICK - 2.0 * BOOM * STICK * cos(ELBOW_MIN))
	var d := clampf(v.length(), near, far)
	if v.length() < 0.001:
		v = Vector2(1.0, 0.0)
	v = v.normalized() * d
	# The elbow up, as an excavator's always is.
	var a := v.angle() + acos(clampf((BOOM * BOOM + d * d - STICK * STICK) / (2.0 * BOOM * d), -1.0, 1.0))
	var boom_a := clampf(a, BOOM_LOW, BOOM_HIGH)
	var elbow := SHOULDER + Vector2(cos(boom_a), sin(boom_a)) * BOOM
	var to := (SHOULDER + v) - elbow
	# If the boom had to stop short, the stick keeps its angle to it within what the joint allows.
	var between := wrapf(boom_a - to.angle() + PI, 0.0, TAU)
	between = clampf(between if between <= PI else TAU - between, ELBOW_MIN, ELBOW_MAX)
	_boom_a = boom_a
	_stick_a = boom_a + between - PI
	wrist = elbow + Vector2(cos(_stick_a), sin(_stick_a)) * STICK
	if wrist.x < NEAREST:
		wrist.x = NEAREST
		var drop := asin(clampf((wrist.x - elbow.x) / STICK, -1.0, 1.0))
		_stick_a = -PI * 0.5 + drop
		wrist.y = elbow.y + sin(_stick_a) * STICK

## Teeth direction in the plane: curl 0 points straight out, a quarter turn straight down, a half turn back at the machine.
func _teeth_local() -> Vector3:
	return Vector3(wrist.x + cos(-curl) * BUCKET, wrist.y + sin(-curl) * BUCKET, ARM_Z)

func _teeth_now() -> Vector3:
	return transform * (Basis(Vector3.UP, swing) * _teeth_local())

## Puts every part where the numbers say.
func _pose() -> void:
	_house.transform = Transform3D(Basis(Vector3.UP, swing) * Basis(Vector3.BACK, _house_rock), Vector3.ZERO)
	var shoulder := Vector3(SHOULDER.x, SHOULDER.y, ARM_Z)
	var elbow := Vector3(SHOULDER.x + cos(_boom_a) * BOOM, SHOULDER.y + sin(_boom_a) * BOOM, ARM_Z)
	var pin := Vector3(wrist.x, wrist.y, ARM_Z)
	var boom_b := Basis(Vector3.BACK, _boom_a)
	var stick_b := Basis(Vector3.BACK, _stick_a)
	var bucket_b := Basis(Vector3.BACK, -curl)
	_boom.transform = Transform3D(boom_b, shoulder)
	_stick.transform = Transform3D(stick_b, elbow)
	_bucket.transform = Transform3D(bucket_b * Basis.from_scale(Vector3.ONE * BUCKET_GROW), pin)
	_ram(0, Vector3(1.75, 1.3, ARM_Z), shoulder + boom_b * Vector3(2.5, 0.05, 0.0))
	_ram(1, shoulder + boom_b * Vector3(BOOM * 0.55, 1.02, 0.0), elbow + stick_b * Vector3(-0.58, 0.42, 0.0))
	_ram(2, elbow + stick_b * Vector3(0.1, 0.34, 0.0), pin + bucket_b * Vector3(0.0, 0.42 * BUCKET_GROW, 0.0))
	var f := fill()
	_lump.visible = f > 0.02
	if _lump.visible:
		_lump.material_override = Props.dust_mat() if bucket_dust * 2 > bucket_mm else _mat
		# The soil in the bucket: fills its hollow, then heaps up out of the open side.
		var deep := 0.3 + 0.62 * minf(f * 1.3, 1.0)
		var long := 0.5 + 0.55 * minf(f * 1.5, 1.0)
		_lump.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(long, deep, BUCKET_HALF / BUCKET_GROW * 1.86)), Vector3(0.58, 0.46 - deep * 0.5, 0.0))

## A stretched ram between two points, in the house's own space.
func _ram(k: int, a: Vector3, b: Vector3) -> void:
	var along := b - a
	var x := along.normalized()
	var z := Vector3.BACK
	var y := z.cross(x).normalized()
	_rams[k].transform = Transform3D(Basis(x * along.length(), y, z), a)

var _net_arm := PackedFloat32Array([0.0, 5.2, 2.7, 2.7, 0.0, 0.0])

func _net_more() -> PackedFloat32Array:
	return PackedFloat32Array([swing, wrist.x, wrist.y, curl, _boom_a, _stick_a, bucket_mm, bucket_dust, int(dig_mode)])

func _net_take_more(s: PackedFloat32Array) -> void:
	_net_arm = s.slice(NET_BASE, NET_BASE + 6)
	bucket_mm = int(s[NET_BASE + 6])
	bucket_dust = int(s[NET_BASE + 7])
	dig_mode = s[NET_BASE + 8] != 0.0

func _net_pose(dt: float, k: float) -> void:
	_clock += dt
	swing = lerp_angle(swing, _net_arm[0], k)
	wrist = wrist.lerp(Vector2(_net_arm[1], _net_arm[2]), k)
	curl = lerpf(curl, _net_arm[3], k)
	_boom_a = lerpf(_boom_a, _net_arm[4], k)
	_stick_a = lerpf(_stick_a, _net_arm[5], k)
	_pose()

func _net_cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([swing_cmd, reach_cmd, raise_cmd, curl_cmd])

func _net_take_cmds_more(c: PackedFloat32Array) -> void:
	swing_cmd = c[2]
	reach_cmd = c[3]
	raise_cmd = c[4]
	curl_cmd = c[5]

## One physics tick.
func step(dt: float) -> void:
	_clock += dt
	var was := _teeth_now()
	_move_house(dt)
	_move_arm(dt)
	teeth = _teeth_now()
	_dig(was, teeth, dt)
	_pour(dt)
	_pose()

	var moved := (teeth - was) / dt
	_bucket_speed = Vector2(moved.x, moved.z).length()
	_bucket_dir = Vector2(moved.x, moved.z).normalized()
	blade_a = Vector2(teeth.x, teeth.z)
	var pin_world := transform * (Basis(Vector3.UP, swing) * Vector3(wrist.x, wrist.y, ARM_Z))
	blade_b = Vector2(pin_world.x, pin_world.z)
	load_t = DirtSim.to_m3(bucket_mm) * 1.5
	hyd = clampf(maxf(maxf(absf(_v_reach), absf(_v_raise)), maxf(absf(_v_swing), absf(_v_curl))), 0.0, 1.0)

	_drive(dt, 0.0)
	_rock_machine(dt)
	_settle(minf(dt * 10.0, 1.0))

func _move_house(dt: float) -> void:
	var cmd := swing_cmd if dig_mode else 0.0
	# Swung through the ground, the soil holds it back.
	var deep := teeth_depth() > 0.15
	var limit := cmd * (0.22 if deep else 1.0)
	_v_swing = move_toward(_v_swing, limit, SWING_EASE * dt)
	var swung_from := swing
	swing -= _v_swing * SWING_SPEED * dt
	# Swung sideways into something buried, it stops against it.
	_swing_blocked = false
	var now := _teeth_now()
	if _on_find_at(now) and not _on_find_at(teeth):
		if not on_rock:
			_touched(now, dt, true)
		swing = swung_from
		_v_swing = 0.0
		_swing_blocked = true

func _move_arm(dt: float) -> void:
	var slow := lerpf(1.0, 0.22, bog)
	_v_reach = move_toward(_v_reach, reach_cmd * slow, ARM_EASE * dt)
	_v_raise = move_toward(_v_raise, raise_cmd * slow, ARM_EASE * dt)
	_v_curl = move_toward(_v_curl, curl_cmd * slow, ARM_EASE * 1.4 * dt)
	var before := wrist
	var before_curl := curl
	var before_boom := _boom_a
	var before_stick := _stick_a
	var want := wrist + Vector2(_v_reach * REACH_SPEED, _v_raise * RAISE_SPEED) * dt
	# Let down over something buried, it eases off in the last bit, so it lands on it softly.
	if want.y < wrist.y:
		var gap := _gap_to_find(teeth)
		if gap < SOFT_LANDING * size:
			want.y = wrist.y + (want.y - wrist.y) * lerpf(SOFT_SLOWEST, 1.0, clampf(gap / (SOFT_LANDING * size), 0.0, 1.0))
	# Pushing down, the teeth only go so far into the ground before there's no pushing any further.
	var deep := teeth_depth()
	if deep > STAB_MOST * size and _v_raise < 0.0:
		want.y = wrist.y
	_solve(want)
	var spin := _v_curl * CURL_SPEED
	# Dragged towards the machine through the soil, the bucket curls by itself, so it fills and comes up holding its load.
	if deep > 0.05 and _v_reach < -0.1:
		spin += CURL_ASSIST
	# Lifting a load, it curls by itself to keep hold of it, unless the player's tipping it out.
	if bucket_mm > 0 and _v_raise > 0.1 and curl < CURL_HOLDS and curl_cmd >= 0.0:
		spin += CURL_LIFT
	curl = clampf(curl + spin * dt, CURL_MIN, CURL_MAX)
	var ended := (curl <= CURL_MIN and spin < 0.0 and before_curl > CURL_MIN) or (curl >= CURL_MAX and spin > 0.0 and before_curl < CURL_MAX)
	hit_end = 0.8 if ended else 0.0
	var stuck := wrist.distance_to(want) > 0.002
	if stuck and not _at_limit and before.distance_to(wrist) > 0.0:
		hit_end = maxf(hit_end, 0.35)
	_at_limit = stuck
	# Rock can't be cut, or pushed through, and nor can something buried. Already against a find's side, it can still come up off it.
	stopped_by_rock = _swing_blocked
	var now := _teeth_now()
	var into_find := _on_find_at(now) and not (_on_find_at(teeth) and now.y > teeth.y)
	if _on_rock_at(now):
		wrist = before
		curl = before_curl
		_boom_a = before_boom
		_stick_a = before_stick
		_v_reach = 0.0
		_v_raise = 0.0
		_v_curl = 0.0
		if not on_rock and not _swing_blocked:
			hit_end = 1.0
		stopped_by_rock = true
	elif into_find:
		# Something buried: the teeth can't go into it, but nothing stops dead. Tried again without the lowering (dragged along its
		# top, to scrape the dirt off it), then without the curl as well, then the curl alone; or, if none of those clear it, held.
		var wanted_curl := curl
		var ok := false
		for tried: Array in [[Vector2(want.x, before.y), wanted_curl], [Vector2(want.x, before.y), before_curl], [before, wanted_curl]]:
			wrist = before
			_boom_a = before_boom
			_stick_a = before_stick
			_solve(tried[0])
			curl = tried[1]
			var p := _teeth_now()
			if not _on_find_at(p) and not _on_rock_at(p):
				ok = true
				break
		if not ok:
			wrist = before
			curl = before_curl
			_boom_a = before_boom
			_stick_a = before_stick
		_v_raise = maxf(_v_raise, 0.0)
		if not on_rock and not _swing_blocked:
			_touched(now, dt, false)
		stopped_by_rock = true
	on_rock = stopped_by_rock

## How far the teeth at `p` are above something buried right under them, in m, or INF with nothing there.
func _gap_to_find(p: Vector3) -> float:
	var at := DirtSim.cell_of(Vector2(p.x, p.z))
	var n := clampi(at.y, 0, DirtSim.CELLS - 1) * DirtSim.CELLS + clampi(at.x, 0, DirtSim.CELLS - 1)
	if sim.hard[n] <= DirtSim.BED_FLOOR:
		return INF
	return p.y - sim.hard[n] * 0.001

func _on_rock_at(p: Vector3) -> bool:
	var at := DirtSim.cell_of(Vector2(p.x, p.z))
	var n := clampi(at.y, 0, DirtSim.CELLS - 1) * DirtSim.CELLS + clampi(at.x, 0, DirtSim.CELLS - 1)
	return sim.rock[n] != 0 and sim.bed[n] * 0.001 > p.y

## Whether the teeth at `p` would be in something buried.
func _on_find_at(p: Vector3) -> bool:
	var at := DirtSim.cell_of(Vector2(p.x, p.z))
	var n := clampi(at.y, 0, DirtSim.CELLS - 1) * DirtSim.CELLS + clampi(at.x, 0, DirtSim.CELLS - 1)
	return sim.hard[n] * 0.001 > p.y

## The teeth just met something buried, moving to `now`: how fast, for the game to read, and a clunk if that's a knock. Come down
## onto it, that's how fast they were coming down. Come at it from the side, only a swing of the whole house counts: the arm dragged
## or curled against its side is just a touch, as that's how it's dug round.
func _touched(now: Vector3, dt: float, swung: bool) -> void:
	var move := now - teeth
	var from_above := not _on_find_at(Vector3(now.x, teeth.y, now.z))
	var speed := 0.0
	if from_above:
		speed = maxf(-move.y, 0.0)
	elif swung:
		speed = Vector2(move.x, move.z).length()
	touch_speed = speed / maxf(dt, 0.0001)
	var hard := touch_speed / (KNOCK_SPEED * size)
	hit_end = clampf(hard * 0.8, 0.5, 1.0) if hard >= 1.0 else 0.0

## What the teeth cut as they go from p0 to p1.
func _dig(p0: Vector3, p1: Vector3, dt: float) -> void:
	moved_tick = 0
	digging = false
	var side3 := (transform.basis * Basis(Vector3.UP, swing)) * Vector3.BACK
	var side := Vector2(side3.x, side3.z).normalized()
	var path := Vector2(p1.x - p0.x, p1.z - p0.z)
	var dist := path.length()
	var in_house := house_forward()
	# It only cuts dragged towards the machine, the open side leading. Pushed the other way, the back of the bucket just shoves.
	var inward := -path.dot(in_house)
	var worked := 0.0
	if inward > 0.0002 and curl < CURL_MAX - 0.05:
		var room := capacity() - bucket_mm
		var along := int(dist / 0.12) + 1
		var share := clampf(dist / SWEEP, 0.0, 1.0)
		var across := maxi(6, int(ceil(BUCKET_HALF * 2.0 * size / 0.2)) + 1)
		for k in along + 1:
			var p := p0.lerp(p1, float(k) / along)
			for w in across:
				var offset := lerpf(-BUCKET_HALF, BUCKET_HALF, w / float(across - 1)) * size
				var at := DirtSim.cell_of(Vector2(p.x, p.z) + side * offset)
				if at.x < 1 or at.y < 1 or at.x >= DirtSim.CELLS - 1 or at.y >= DirtSim.CELLS - 1:
					continue
				var n := at.y * DirtSim.CELLS + at.x
				var high := sim.bed[n] + sim.soil[n] - int(p.y * 1000.0)
				if high <= 0:
					continue
				digging = true
				if room <= 0:
					worked += 200.0
					continue
				var r: Array = sim.bite(at.x, at.y, mini(ceili(high * share), room), ceili(FIRM_RATE * size))
				room -= r[0]
				bucket_mm += r[0]
				bucket_dust += r[2]
				moved_tick += r[0]
				worked += r[0] + r[1] * 12.0
	elif teeth_depth() > 0.05 and (absf(_v_reach) > 0.05 or absf(_v_raise) > 0.05):
		worked = 300.0
	moved_m3 += DirtSim.to_m3(moved_tick)
	bog = lerpf(bog, clampf(worked / (BOG_AT * size * size), 0.0, 1.0), minf(dt * 10.0, 1.0))

## How much the bucket can hold, the way it's tilted.
func _holds() -> int:
	return int(capacity() * clampf((curl - CURL_EMPTY) / (CURL_HOLDS - CURL_EMPTY), 0.0, 1.0))

## What it can't hold falls out, in real chunks of soil. A heaped bucket sheds some when it's thrown about.
func _pour(dt: float) -> void:
	var heaped := int(HEAPED * size * size * size)
	var chunk := int(CHUNK * size * size)
	var over := maxi(bucket_mm - _holds(), 0)
	var out := mini(over, ceili(POUR_RATE * size * size * size * dt))
	if bucket_mm > heaped and over == 0:
		var fast := absf(_v_swing) + absf(_v_reach) + absf(_v_raise)
		out = mini(bucket_mm - heaped, ceili(fast * 500.0 * dt))
	pouring = lerpf(pouring, clampf(float(out) / (POUR_RATE * size * size * size * dt), 0.0, 1.0), minf(dt * 10.0, 1.0))
	if out <= 0:
		return
	var out_dust := bucket_dust * out / bucket_mm
	bucket_mm -= out
	bucket_dust -= out_dust
	_pour_store += out
	_pour_dust += out_dust
	var side3 := (transform.basis * Basis(Vector3.UP, swing)) * Vector3.BACK
	var pin_world := transform * (Basis(Vector3.UP, swing) * Vector3(wrist.x, wrist.y, ARM_Z))
	pour_spot = teeth.lerp(pin_world, 0.25)
	while _pour_store >= chunk or (bucket_mm == 0 and _pour_store > 0):
		var amt := mini(chunk, _pour_store)
		var chunk_dust := _pour_dust * amt / _pour_store
		_pour_store -= amt
		_pour_dust -= chunk_dust
		sim.held -= amt
		var f := house_forward()
		var at := pour_spot + side3 * _rng.randf_range(-BUCKET_HALF, BUCKET_HALF)
		sim.launch(at, Vector3(f.x * _rng.randf_range(0.2, 0.7), -0.4, f.y * _rng.randf_range(0.2, 0.7)), amt, chunk_dust)

## It rocks on its tracks: forward with a load held far out, back as the teeth bite, and over as the house swings.
func _rock_machine(dt: float) -> void:
	var out := clampf((wrist.x - 4.0) / 5.0, 0.0, 1.0)
	var nose := -(0.006 + 0.014 * fill()) * out - 0.004 * absf(_v_raise) * fill()
	nose += 0.014 * bog
	# Which way that tips it depends on where the house faces, so it's worked out across the tracks' two axes.
	var pitch := nose * cos(swing)
	var roll := nose * sin(swing) + _v_swing * 0.006
	tilt = tilt.slerp(Basis(Vector3.BACK, pitch) * Basis(Vector3.RIGHT, roll), minf(dt * 5.0, 1.0)).orthonormalized()
	# The house itself gives a little when a stop or a bite comes through it.
	var want := -0.012 * _v_raise * (0.3 + fill()) + 0.01 * bog * sin(_clock * 31.0)
	_house_rock_vel += ((want - _house_rock) * 70.0 - _house_rock_vel * 7.0) * dt
	_house_rock += _house_rock_vel * dt

## ---------------------------------------------------------------- the side-on picture
func side_view() -> Dictionary:
	var elbow := SHOULDER + Vector2(cos(_boom_a), sin(_boom_a)) * BOOM
	var shape: Array[Vector2] = []
	for p: Vector2 in [Vector2(-0.08, 0.1), Vector2(0.35, 0.5), Vector2(0.85, 0.52), Vector2(BUCKET / BUCKET_GROW, -0.02), Vector2(0.15, -0.28)]:
		shape.append(p * BUCKET_GROW)
	var tip := _teeth_now()
	return {
		"low": -3.0, "high": 5.5, "left": -0.3,
		"body": [Rect2(-2.4, 0.0, 4.8, 0.85), Rect2(-2.6, 0.85, 4.0, 1.0)],
		"joints": [SHOULDER, elbow, wrist],
		"pin": wrist,
		"turn": -curl,
		"shape": shape,
		"reach": BUCKET,
		"fill_from": Vector2(0.6, 0.5) * BUCKET_GROW,
		"fill": fill(),
		"dust": bucket_dust * 2 > bucket_mm,
		"angle": rad_to_deg(curl),
		"pours": bucket_mm > _holds(),
		"pour": wrist.lerp(wrist + Vector2(BUCKET, 0.0).rotated(-curl), 0.75),
		"has_load": bucket_mm > 0,
		"turn_word": "SWING", "out_word": "REACH OUT", "in_word": "REACH IN",
		"down": sim.height_at(Vector2(tip.x, tip.z)) - tip.y,
	}

func side_ground(x: float) -> float:
	var w: Vector3 = transform * (Basis(Vector3.UP, swing) * Vector3(x, 0.0, ARM_Z))
	return (transform.affine_inverse() * Vector3(w.x, sim.height_at(Vector2(w.x, w.z)), w.z)).y

func side_point(w: Vector3) -> Vector3:
	return Basis(Vector3.UP, swing).inverse() * (transform.affine_inverse() * w) - Vector3(0.0, 0.0, ARM_Z)

func side_world(p: Vector2) -> Vector3:
	return transform * (Basis(Vector3.UP, swing) * Vector3(p.x, p.y, ARM_Z))
