class_name Worker
extends Machine
## The driver on foot. He climbs down off a machine, walks about on the same stick that drives (push to walk, sideways to turn),
## and climbs into whichever machine he walks up to. Kept in game.machines like the rest, so the camera, the buttons and playing
## with a friend all work with him the same way. While he's in a machine he's hidden and out of everyone's way.

const WALK := 2.2               # m/s, a brisk walk
const BACK := 1.1               # stepping backwards
const TURN := 3.2               # rad/s on the spot
const EASE := 7.0               # how fast he gets going and stops
const STRIDE := 1.4             # m a full step of both legs takes
const SWING := 0.55             # radians the legs swing at a walk

var on_foot := false
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _phase := 0.0
var _swing := 0.0

func setup(s: DirtSim, v: GroundView, mat: Material, at: Vector2, dir: Vector2) -> void:
	sim = s
	view = v
	spot = at
	angle = atan2(-dir.y, dir.x)
	machine_name = "On foot"
	hint = "Walk up to a machine and tap GET IN"
	stuck_word = ""
	mass = 90.0
	top_speed = WALK
	back_speed = BACK
	turn_rate = TURN
	view_dist = 5.5
	view_pitch = 17.0
	view_aim = 1.1
	eye = Vector3(0.12, 1.36, 0.0)
	pipe = Vector3(0.0, 1.0, 0.0)
	body_reach = 0.3
	fp_back = 0.12
	fp_front = 0.12
	fp_r = 0.28
	var kit := MeshKit.new()
	Props.worker_body(kit)
	_add(self, kit, mat)
	for z: float in [-0.1, 0.1]:
		var hip := Node3D.new()
		hip.position = Vector3(0.0, 0.71, z)
		add_child(hip)
		kit = MeshKit.new()
		Props.worker_leg(kit)
		_add(hip, kit, mat)
		_legs.append(hip)
	for z: float in [-0.23, 0.23]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.0, 1.16, z)
		add_child(shoulder)
		kit = MeshKit.new()
		Props.worker_arm(kit)
		_add(shoulder, kit, mat)
		_arms.append(shoulder)
	visible = false
	_place()

func _add(parent: Node3D, kit: MeshKit, mat: Material) -> void:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = mat
	parent.add_child(m)

## Steps down here, facing this way.
func step_off(at: Vector2, facing: float) -> void:
	spot = at
	angle = facing
	speed = 0.0
	drive = 0.0
	turn_cmd = 0.0
	on_foot = true
	visible = true
	_place()

## Climbs aboard something: gone from the ground until he steps off again.
func climb_on() -> void:
	stop_commands()
	speed = 0.0
	on_foot = false
	visible = false

func step(dt: float) -> void:
	if not on_foot:
		return
	drive = move_toward(drive, throttle, EASE * dt)
	speed = drive * (WALK if drive >= 0.0 else BACK)
	turn_cmd = move_toward(turn_cmd, steer, EASE * 1.5 * dt)
	angle -= turn_cmd * TURN * dt
	var want := spot + forward() * speed * dt
	var got := want.clamp(Vector2(-AREA, -AREA), Vector2(AREA, AREA))
	at_edge = got != want
	spot = got
	_place()
	_walk_pose(dt)

## Stands him on the ground, upright whatever its slope.
func _place() -> void:
	transform = Transform3D(Basis(Vector3.UP, angle), Vector3(spot.x, sim.height_at(spot), spot.y))

## Legs and arms swinging in time with how far he's gone, arms against legs. Turning on the spot shuffles them a little.
func _walk_pose(dt: float) -> void:
	var going := maxf(absf(speed), absf(turn_cmd) * 0.6)
	_phase = fposmod(_phase + going * dt / STRIDE * TAU, TAU)
	_swing = lerpf(_swing, clampf(going / WALK, 0.0, 1.0), minf(dt * 8.0, 1.0))
	var a := sin(_phase) * SWING * _swing
	_legs[0].rotation.z = a
	_legs[1].rotation.z = -a
	_arms[0].rotation.z = -a * 0.8
	_arms[1].rotation.z = a * 0.8

func footprint() -> Array:
	# Hidden in a machine, he's nowhere anyone can bump into.
	if not on_foot:
		return [Vector2(9999.0, 9999.0), Vector2(9999.0, 9999.0), 0.0]
	return super()

func effort() -> float:
	return 0.0

func hit_speed() -> float:
	return 0.0

## Boots leave no track marks in the grass.
func _wear_tracks() -> void:
	pass

func _net_pose(dt: float, _k: float) -> void:
	_walk_pose(dt)
