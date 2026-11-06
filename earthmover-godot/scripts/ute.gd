class_name Ute
extends Machine
## The scout ute: quick across a big site, and it does the surveying. PEG drops a survey peg out the driver's window; pegs go in
## round a patch of ground, and CLOSE turns them into a pad, levelled to the ground's own average height inside them so what comes
## off the high side fills the low side. The machines then work to it: the ground inside shows red to take off and blue to fill, the
## dozer's CUT stops at its height, and it earns stars like a job. The pegs themselves are the game's: the ute only says where.

const MASS := 2200.0            # kg
const TOP := 11.0               # m/s, about 40 km/h: fast for a site, and fun across a paddock
const BACK := 4.0
const WHEELBASE := 3.1
const STEER_MOST := 0.6         # radians at the front wheels
const WHEEL_R := 0.38
const PEG_OUT := 1.45           # m out from the middle, beside the driver's door, that a peg goes in

var _body: Node3D
var _beacon: MeshInstance3D
var _clock := 0.0

func setup(s: DirtSim, v: GroundView, mat: Material, at: Vector2, dir: Vector2) -> void:
	sim = s
	view = v
	spot = at
	angle = atan2(-dir.y, dir.x)
	machine_name = "Ute"
	hint = "Drive round a patch and tap PEG at each corner, then CLOSE IT UP: the machines work to it"
	stuck_word = "STUCK: back out and go round"
	mass = MASS
	top_speed = TOP
	back_speed = BACK
	_speed_cap = TOP
	support_x = 1.45
	support_z = 0.78
	side_lean_most = 0.35
	track_z = 0.78
	track_rear = 1.45
	view_dist = 11.0
	view_pitch = 16.0
	view_aim = 1.3
	eye = Vector3(0.15, 1.55, 0.38)
	pipe = Vector3(-2.4, 0.4, -0.5)
	fp_back = 2.55
	fp_front = 2.45
	fp_r = 0.98
	body_reach = 1.1
	_body = Node3D.new()
	add_child(_body)
	var kit := MeshKit.new()
	Props.ute_body(kit)
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = mat
	_body.add_child(m)
	kit = MeshKit.new()
	kit.box(Vector3.ZERO, Vector3(0.22, 0.14, 0.22), Props.HI_VIS)
	_beacon = MeshInstance3D.new()
	_beacon.mesh = kit.mesh()
	_beacon.material_override = mat
	_beacon.position = Vector3(0.1, 1.98, 0.0)
	_body.add_child(_beacon)
	var wheel_kit := MeshKit.new()
	Props.wheel(wheel_kit, 0.26)
	var tyre := wheel_kit.mesh()
	for side: float in [-1.0, 1.0]:
		_add_wheel(tyre, mat, Vector3(1.55, WHEEL_R, side * 0.8), WHEEL_R, true)
		_add_wheel(tyre, mat, Vector3(-1.55, WHEEL_R, side * 0.8), WHEEL_R)
	y_smooth = sim.track_height_at(spot)
	_settle(1.0)

## Road-style steering, like the truck: it turns with how fast it's going.
func _turning(_turn_share: float) -> float:
	return speed / WHEELBASE * tan(turn_cmd * STEER_MOST)

## Where a peg goes in now: beside the driver's door.
func peg_spot() -> Vector2:
	var side := Vector2(sin(angle), cos(angle))
	return spot + side * PEG_OUT - forward() * 0.2

func gauge_word() -> Array:
	return ["%d km/h" % roundi(absf(speed) * 3.6), Color("#a8f07a")]

func step(dt: float) -> void:
	_clock += dt
	_drive(dt, 0.0)
	_sway()
	_settle(minf(dt * 9.0, 1.0))
	_place_bumper()

func _net_pose(dt: float, _k: float) -> void:
	_clock += dt
	_sway()

## The body rolls and pitches on its springs, and the beacon on the roof turns.
func _sway() -> void:
	_body.rotation.z = rock_pitch * 1.6
	_body.rotation.x = rock_roll * 1.8
	_beacon.rotation.y = fposmod(_clock * 9.0, TAU)

## What it hits a tree with: the bull bar.
func _place_bumper() -> void:
	var f := forward()
	var side := Vector2(sin(angle), cos(angle))
	var front := spot + f * 2.45
	blade_a = front - side * 0.95
	blade_b = front + side * 0.95
