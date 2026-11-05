class_name Machine
extends Node3D
## What every tracked machine shares: resting on the ground, driving, turning, the tracks, and a body with some weight to it.

const GRIP := 0.75              # of its weight the tracks can push with before slipping
const LOOSE_GRIP := 0.55        # of its usual grip, on deep loose soil
const ROLLING := 7000.0         # N, for a machine of ROLLING_MASS or more
const ROLLING_MASS := 20000.0   # kg
const AREA := 26.0              # how far from the middle a machine can go
const ENGINE := 150000.0        # N, the most the tracks are driven with
const DRIVE_STIFF := 0.6        # m/s behind the speed asked for at which the tracks are pushing flat out
const DRIVE_UP := 0.6           # a second: how fast the drive comes on. It's about 1.7 s to full, so it gets going like 20 tonnes
const DRIVE_DOWN := 1.1         # and how fast it comes off, which is what brakes it
const TURN_EASE := 2.6
const ROCK_ACCEL := 0.014       # radians of nose-up for each m/s2
const ROCK_TURN := 0.05         # radians of lean for each m/s of speed times rad/s of turn
const ROCK_LIMIT := 0.06
const ROCK_SPRING := 42.0
const ROCK_DAMP := 5.0
const RUT_EVERY := 0.25         # m of track travel between each print in loose soil
const RUT_DEEP := 34            # mm squeezed out to the side at a cleat
const RUT_SHALLOW := 12         # and between cleats
const RUT_MIN_SOIL := 60        # mm: firm ground takes no print

var sim: DirtSim
var view: GroundView
var angle := 0.0
var spot := Vector2.ZERO
var speed := 0.0
var y_smooth := 0.0
var basis_smooth := Basis.IDENTITY

var throttle := 0.0             # what's asked for
var steer := 0.0
var drive := 0.0                # what the machine is actually doing about it
var turn_cmd := 0.0

var mass := 20000.0
var top_speed := 3.2
var back_speed := 3.6
var turn_rate := 0.8
var support_x := 1.8            # the corners it rests on
var support_z := 1.15
var track_z := 1.15             # middle of each track
var track_rear := 1.7

# For the readout, the sound and the tests.
var load_t := 0.0
var slipping := false
var on_rock := false
var moved_m3 := 0.0
var moved_tick := 0
var at_edge := false
var hyd := 0.0                  # how hard the hydraulics are working, 0 to 1
var blade_a := Vector2.ZERO     # what it hits things with
var blade_b := Vector2.ZERO
var teeth := Vector3.ZERO       # the working end, in the world
var bog := 0.0                  # 0 to 1: how hard the soil is holding it
var digging := false
var pouring := 0.0              # 0 to 1, soil falling out of it
var pour_spot := Vector3.ZERO
var hit_end := 0.0              # how hard something just came to the end of its travel, for the sound

var machine_name := "Machine"
var hint := ""                  # said once when the player climbs on
var view_dist := 13.0
var view_pitch := 19.0
var view_aim := 1.6             # how high above the ground the camera looks
var view_side := 0.0            # radians round from straight behind
var stuck_word := "STUCK: back up and try again"
var eye := Vector3(-0.75, 2.72, 0.0)
var pipe := Vector3(0.75, 3.0, 0.55)
var body_reach := 2.2           # m from the middle at which it hits a tree
var fp_back := 2.3
var fp_front := 2.3
var fp_r := 1.5
var wheels: Array[Dictionary] = []

var tracks: TrackRig
var tilt := Basis.IDENTITY      # the whole machine rocking on its tracks, as an excavator does
var rock_pitch := 0.0           # the body swaying on its mounts, as it speeds up, brakes and turns
var rock_roll := 0.0
var _pitch_vel := 0.0
var _roll_vel := 0.0
var _speed_cap := 3.2
var _rut_travel: Array[float] = [0.0, 0.0]
var _rut_count := 0

func forward() -> Vector2:
	return Vector2(cos(angle), -sin(angle))

## Which way the camera should sit behind.
func view_forward() -> Vector2:
	return forward()

func camera_aim() -> Vector3:
	return position + Vector3(0.0, view_aim, 0.0)

func exhaust_point() -> Vector3:
	return to_global(pipe)

func cab_eye() -> Vector3:
	return to_global(eye)

func effort() -> float:
	return absf(throttle)

## How fast what it hits things with is moving, and which way a tree it hits goes over.
func hit_speed() -> float:
	return absf(speed)

func push_dir() -> Vector2:
	return forward() * signf(speed)

## Whether its working end carries a fallen tree along.
func can_shove(_tree_down: bool) -> bool:
	return false

## Roughly the ground the machine stands on: a line down its length and how far either side of it. For bumping into another.
func footprint() -> Array:
	return [spot - forward() * fp_back, spot + forward() * fp_front, fp_r]

## Lets go of every control.
func stop_commands() -> void:
	throttle = 0.0
	steer = 0.0

## What the on-screen readout says: the words, and a colour.
func gauge_word() -> Array:
	return ["", Color.WHITE]

## How fast it's turning: rad/s, positive to the right. Tracks and skid-steers turn on the spot; a truck overrides this.
func _turning(turn_share: float) -> float:
	return turn_cmd * turn_rate * turn_share

## Adds a wheel that turns with the ground.
func _add_wheel(mesh: Mesh, mat: Material, at: Vector3, radius: float, steers := false) -> void:
	var w := MeshInstance3D.new()
	w.mesh = mesh
	w.material_override = mat
	w.position = at
	add_child(w)
	wheels.append({"node": w, "r": radius, "right": at.z > 0.0, "steers": steers, "roll": 0.0})
	w.basis = Basis.IDENTITY.scaled(Vector3(radius, radius, 1.0))

func _spin_wheels(left: float, right: float, dt: float) -> void:
	for w: Dictionary in wheels:
		var v: float = right if w["right"] else left
		w["roll"] = fposmod(float(w["roll"]) - v / float(w["r"]) * dt, TAU)
		var r: float = w["r"]
		var aim := Basis(Vector3.UP, -turn_cmd * 0.55) if w["steers"] else Basis.IDENTITY
		(w["node"] as MeshInstance3D).basis = aim * Basis(Vector3.BACK, w["roll"]).scaled(Vector3(r, r, 1.0))

func _ground_at(local_x: float, local_z: float) -> float:
	var f := forward()
	var side := Vector2(sin(angle), cos(angle))
	return sim.track_height_at(spot + f * local_x + side * local_z)

## How deep the loose soil is under the tracks, in mm.
func _loose_under() -> float:
	var f := forward()
	var side := Vector2(sin(angle), cos(angle))
	var total := 0
	for s: float in [-support_z, support_z]:
		for along: float in [-1.5, 0.0, 1.5]:
			var at := DirtSim.cell_of(spot + f * along + side * s)
			total += sim.soil[clampi(at.y, 0, DirtSim.CELLS - 1) * DirtSim.CELLS + clampi(at.x, 0, DirtSim.CELLS - 1)]
	return total / 6.0

## Rests the machine on its tracks: tips it to the ground under their four corners.
func _settle(k: float) -> void:
	var fl := _ground_at(support_x, -support_z)
	var fr := _ground_at(support_x, support_z)
	var bl := _ground_at(-support_x, -support_z)
	var br := _ground_at(-support_x, support_z)
	var f := forward()
	var along := Vector3(f.x, ((fl + fr) - (bl + br)) * 0.25 / support_x, f.y).normalized()
	var across := Vector3(sin(angle), ((fr + br) - (fl + bl)) * 0.25 / support_z, cos(angle)).normalized()
	var up := across.cross(along).normalized()
	across = along.cross(up).normalized()
	var want := Basis(along, up, across)
	basis_smooth = basis_smooth.slerp(want.orthonormalized(), k).orthonormalized() if k < 1.0 else want.orthonormalized()
	# On a sharp crest the corners hang lower than the middle: it sits on the crest, or the crest comes up through it.
	var rest := maxf((fl + fr + bl + br) * 0.25, maxf(_ground_at(0.0, -support_z), _ground_at(0.0, support_z)))
	y_smooth = lerpf(y_smooth, rest, k)
	transform = Transform3D(basis_smooth * tilt, Vector3(spot.x, y_smooth, spot.y))

## Drives it one tick. `drag` is what its work is holding it back with, in N; `ignore_loose` turns off the loose-soil penalty;
## `turn_share` is how much of its turning it has left.
func _drive(dt: float, drag: float, ignore_loose := false, turn_share := 1.0) -> void:
	var easing := DRIVE_UP if absf(throttle) > absf(drive) and throttle * drive >= 0.0 else DRIVE_DOWN
	drive = move_toward(drive, throttle, easing * dt)
	turn_cmd = move_toward(turn_cmd, steer, TURN_EASE * dt)
	var before := speed
	var f := forward()
	var mg := mass * 9.8
	# Tracks hold worse on loose soil and on a slope, so a pile can't just be driven up.
	var soft := 1.0 if ignore_loose else lerpf(1.0, LOOSE_GRIP, clampf(_loose_under() / 200.0, 0.0, 1.0))
	var hold := GRIP * mg * transform.basis.y.y * soft
	# The tracks drive towards a speed, as hydraulic drives do. Even a timid push gets it going at a walk.
	var how_much := absf(drive)
	var target := signf(drive) * (0.35 * minf(how_much / 0.1, 1.0) + 0.65 * how_much) * (top_speed if drive >= 0.0 else back_speed)
	var most := minf(ENGINE, hold)
	var push := clampf((target - speed) * ENGINE / DRIVE_STIFF, -most, most)
	var slope := -mg * transform.basis.x.y
	var net := push + slope
	# Rolling drag goes with weight, or a machine as light as a Dingo has less grip on loose soil than it takes to roll at all.
	var resist := ROLLING * minf(mass / ROLLING_MASS, 1.0) + (drag if drive >= 0.0 else 0.0)
	# Tracks hold when they're not driven, so it stops and stays put on a slope instead of rolling.
	if absf(throttle) < 0.05 and absf(drive) < 0.05:
		resist = maxf(resist, hold)
	var v := speed + net / mass * dt
	var stop := resist / mass * dt
	if absf(v) <= stop:
		v = 0.0
	else:
		v -= signf(v) * stop
	if on_rock and v > 0.0:
		v = 0.0
	# The harder it's working, the slower it can go. Eased, so soil coming on is a lean, not a brick wall.
	var work := clampf((drag + maxf(-slope, 0.0)) / (GRIP * mg), 0.0, 1.0)
	_speed_cap = move_toward(_speed_cap, top_speed * (1.0 - 0.75 * work), 5.0 * dt)
	speed = clampf(v, -back_speed, _speed_cap)
	# Throttle on and going nowhere: the tracks are spinning.
	slipping = throttle > 0.3 and drive > 0.25 and speed < 0.15

	var turning := _turning(turn_share)
	angle -= turning * dt
	# Against the fence it really stops, or the blade would go on heaping soil at the edge while the machine stood still.
	var want := spot + f * speed * dt
	var got := want.clamp(Vector2(-AREA, -AREA), Vector2(AREA, AREA))
	at_edge = got != want
	if at_edge:
		speed = (got - spot).dot(f) / dt
		slipping = false
	spot = got

	var belt := speed
	if slipping:
		belt = drive * top_speed * 0.8
	var left := belt + turning * track_z
	var right := belt - turning * track_z
	if tracks:
		tracks.update(left, right, dt)
	if not wheels.is_empty():
		_spin_wheels(left, right, dt)
	_print_ruts(left, right, dt)
	_rock(dt, (speed - before) / dt, turning)
	if absf(speed) > 0.05 or absf(turn_cmd) > 0.1:
		_wear_tracks()

## The body has weight: it squats as it pulls away, dips its nose as it stops or hits a load, and leans out of a turn.
func _rock(dt: float, accel: float, turning: float) -> void:
	var want_pitch := clampf(accel * ROCK_ACCEL, -ROCK_LIMIT, ROCK_LIMIT)
	var want_roll := clampf(speed * turning * ROCK_TURN, -ROCK_LIMIT, ROCK_LIMIT)
	_pitch_vel += ((want_pitch - rock_pitch) * ROCK_SPRING - _pitch_vel * ROCK_DAMP) * dt
	rock_pitch += _pitch_vel * dt
	_roll_vel += ((want_roll - rock_roll) * ROCK_SPRING - _roll_vel * ROCK_DAMP) * dt
	rock_roll += _roll_vel * dt

## ---------------------------------------------------------------- online
## The host's word on this machine, a guest easing towards it, and what a guest's thumbs are doing.

var _net_spot := Vector2.ZERO
var _net_y := 0.0
var _net_quat := Quaternion.IDENTITY
var _net_angle := 0.0
var _net_fresh := true

func net_state() -> PackedFloat32Array:
	var q := transform.basis.orthonormalized().get_rotation_quaternion()
	var flags := int(slipping) | int(on_rock) << 1 | int(at_edge) << 2 | int(digging) << 3
	var s := PackedFloat32Array([spot.x, spot.y, position.y, q.x, q.y, q.z, q.w, angle, speed, turn_cmd, drive, throttle, hyd, pouring, pour_spot.x, pour_spot.y, pour_spot.z, load_t, bog, flags, teeth.x, teeth.y, teeth.z, moved_tick])
	s.append_array(_net_more())
	return s

const NET_BASE := 24

func net_take(s: PackedFloat32Array) -> void:
	_net_spot = Vector2(s[0], s[1])
	_net_y = s[2]
	_net_quat = Quaternion(s[3], s[4], s[5], s[6])
	_net_angle = s[7]
	speed = s[8]
	turn_cmd = s[9]
	drive = s[10]
	# Only what's somebody else's: this copy's own throttle is the thumb on it.
	hyd = s[12]
	pouring = s[13]
	pour_spot = Vector3(s[14], s[15], s[16])
	load_t = s[17]
	bog = s[18]
	var flags := int(s[19])
	slipping = flags & 1 != 0
	on_rock = flags & 2 != 0
	at_edge = flags & 4 != 0
	digging = flags & 8 != 0
	teeth = Vector3(s[20], s[21], s[22])
	moved_tick = int(s[23])
	_net_take_more(s)
	if _net_fresh or spot.distance_to(_net_spot) > 6.0:
		_net_fresh = false
		spot = _net_spot
		angle = _net_angle
		transform = Transform3D(Basis(_net_quat), Vector3(spot.x, _net_y, spot.y))

func net_follow(dt: float) -> void:
	var k := minf(dt * 14.0, 1.0)
	spot = spot.lerp(_net_spot, k)
	angle = lerp_angle(angle, _net_angle, k)
	var place := position.lerp(Vector3(spot.x, _net_y, spot.y), k)
	transform = Transform3D(Basis(transform.basis.orthonormalized().get_rotation_quaternion().slerp(_net_quat, k)), Vector3(spot.x, place.y, spot.y))
	var belt := drive * top_speed * 0.8 if slipping else speed
	var turning := turn_cmd * turn_rate
	var left := belt + turning * track_z
	var right := belt - turning * track_z
	if tracks:
		tracks.update(left, right, dt)
	if not wheels.is_empty():
		_spin_wheels(left, right, dt)
	if absf(speed) > 0.05 or absf(turn_cmd) > 0.1:
		_wear_tracks()
	_net_pose(dt, k)

func net_cmds() -> PackedFloat32Array:
	var c := PackedFloat32Array([throttle, steer])
	c.append_array(_net_cmds_more())
	return c

func net_take_cmds(c: PackedFloat32Array) -> void:
	throttle = c[0]
	steer = c[1]
	_net_take_cmds_more(c)

func _net_more() -> PackedFloat32Array:
	return PackedFloat32Array()

func _net_take_more(_s: PackedFloat32Array) -> void:
	pass

func _net_pose(_dt: float, _k: float) -> void:
	pass

func _net_cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array()

func _net_take_cmds_more(_c: PackedFloat32Array) -> void:
	pass

## Hit something solid.
func jolt() -> void:
	speed *= 0.6

## Tracks leave a print in loose soil: squeezed out to the side, deep at each cleat. Whole mm moved, so the total can't change.
func _print_ruts(left: float, right: float, dt: float) -> void:
	var f := forward()
	var side := Vector2(sin(angle), cos(angle))
	for k in 2:
		_rut_travel[k] += absf(left if k == 0 else right) * dt
		if _rut_travel[k] < RUT_EVERY:
			continue
		_rut_travel[k] = 0.0
		_rut_count += 1
		var deep := RUT_DEEP if _rut_count % 4 < 2 else RUT_SHALLOW
		var sign_z := -1.0 if k == 0 else 1.0
		for w: float in [-0.25, 0.0, 0.25]:
			var at := DirtSim.cell_of(spot - f * track_rear + side * sign_z * (track_z + w))
			if at.x < 1 or at.y < 1 or at.x >= DirtSim.CELLS - 1 or at.y >= DirtSim.CELLS - 1:
				continue
			if sim.soil[at.y * DirtSim.CELLS + at.x] < RUT_MIN_SOIL:
				continue
			var got := sim.take(at.x, at.y, deep)
			# The outer edge of the track takes what comes from the outer half, the inner edge from the inner half.
			var off := 0.5 if w >= 0.0 else -0.5
			var out := DirtSim.cell_of(spot - f * track_rear + side * sign_z * (track_z + off))
			sim.put(out.x, out.y, got, sim.last_dust)

func _wear_tracks() -> void:
	var f := forward()
	var side := Vector2(sin(angle), cos(angle))
	for s: float in [-track_z, track_z]:
		for along: float in [-track_rear, 0.0, track_rear]:
			for w: float in [-0.25, 0.0, 0.25]:
				var at := DirtSim.cell_of(spot + f * along + side * (s + w))
				view.wear(at.x, at.y)

## ---------------------------------------------------------------- the side-on picture of the bucket
## What a machine with a bucket shows in BucketView, in metres in its own side-on plane with the ground at its tracks at 0. Empty for one without.
func side_view() -> Dictionary:
	return {}

## How high the ground stands `x` m ahead along that plane, measured the same way.
func side_ground(x: float) -> float:
	var w: Vector3 = transform * Vector3(x, 0.0, 0.0)
	return (transform.affine_inverse() * Vector3(w.x, sim.height_at(Vector2(w.x, w.z)), w.z)).y

## A point in the world in that plane's terms: how far ahead, how high, and how far to the right of it.
func side_point(w: Vector3) -> Vector3:
	return transform.affine_inverse() * w

## A point in that plane, in the world.
func side_world(p: Vector2) -> Vector3:
	return transform * Vector3(p.x, p.y, 0.0)
