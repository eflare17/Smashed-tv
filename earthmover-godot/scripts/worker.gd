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
# The hand tools.
const SCOOP := 192              # mm on one cell's area a shovelful holds: 0.012 m3
const DIG_AT := 0.75            # m ahead of him the shovel goes in
const FIRM_BITE := 24           # mm of firm ground a cell gives a shovel, where loose soil comes freely
const THROW_TO := 1.5           # m ahead a shovelful lands, with nothing to throw it into
const THROW_S := 0.45           # seconds a shovelful's in the air
const RAKE_AT := 1.05           # m ahead the rake's head is
const RAKE_HALF := 0.32
const RAKE_WALK := 0.6          # of his walking speed, raking
const ACT_S := 0.4              # how long a dig or a throw takes

var on_foot := false
var tool := ""                  # "shovel", "rake" or nothing in his hands
var shovel_mm := 0              # what's on the shovel
var shovel_dust := 0
var raked := 0                  # mm moved with the rake, for the checks
var _act := ""                  # "dig" or "throw" while he's doing it
var _act_t := 0.0
var _tools: Dictionary = {}     # tool -> its mesh, in his right hand
var _load: MeshInstance3D       # the dirt on the shovel
var _rng := RandomNumberGenerator.new()
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
	# The tools, in the right hand: shown only while he's holding one.
	for t: String in ["shovel", "rake"]:
		kit = MeshKit.new()
		if t == "shovel":
			Props.shovel(kit)
		else:
			Props.rake(kit)
		var held := _add(_arms[1], kit, mat)
		held.position = Vector3(0.0, -0.44, 0.0)
		held.visible = false
		_tools[t] = held
	kit = MeshKit.new()
	kit.prism([Vector2(-0.1, 0.0), Vector2(0.1, 0.0), Vector2(0.05, 0.08), Vector2(-0.05, 0.08)], -0.09, 0.09, Props.DIRT)
	_load = _add(_tools["shovel"], kit, mat)
	_load.position = Vector3(0.55, -0.6, 0.0)
	_load.visible = false
	_rng.seed = 31
	visible = false
	_place()

func _add(parent: Node3D, kit: MeshKit, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = mat
	parent.add_child(m)
	return m

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
	_act_t = maxf(_act_t - dt, 0.0)
	if _act_t <= 0.0:
		_act = ""
	# Digging or throwing, he stands to do it. Raking, he walks slowly.
	drive = move_toward(drive, 0.0 if _act != "" else throttle, EASE * dt)
	speed = drive * (WALK if drive >= 0.0 else BACK) * (RAKE_WALK if tool == "rake" else 1.0)
	turn_cmd = move_toward(turn_cmd, steer, EASE * 1.5 * dt)
	angle -= turn_cmd * TURN * dt
	var want := spot + forward() * speed * dt
	var got := want.clamp(Vector2(-AREA, -AREA), Vector2(AREA, AREA))
	at_edge = got != want
	spot = got
	_place()
	if tool == "rake" and absf(speed) > 0.05:
		var share := clampf(absf(speed) * dt / 0.2, 0.0, 1.0)
		raked += sim.rake(spot + forward() * RAKE_AT, forward(), RAKE_HALF, share)
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
	_hold_pose()

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

## ---------------------------------------------------------------- the hand tools

## Takes up a tool, or puts it away if it's the one he has. A shovelful still on the shovel goes down where he stands.
func take_tool(t: String) -> void:
	if not on_foot or _act != "":
		return
	if shovel_mm > 0:
		_throw_at(spot + forward() * 0.6, sim.height_at(spot + forward() * 0.6))
	tool = "" if tool == t else t
	_hold_pose()

## Pushes the shovel in ahead of him and lifts out a shovelful: loose soil comes freely, firm ground a bit at a time.
## Returns mm dug.
func dig() -> int:
	if not on_foot or tool != "shovel" or shovel_mm > 0 or _act != "":
		return 0
	var at := spot + forward() * DIG_AT
	var c := DirtSim.cell_of(at)
	var got := 0
	var got_dust := 0
	# A shovel's about two cells wide and two deep: a quarter from each.
	for k in 4:
		var r: Array = sim.bite(c.x + (k & 1), c.y + (k >> 1), SCOOP / 4, FIRM_BITE)
		got += r[0]
		got_dust += r[2]
	shovel_mm = got
	shovel_dust = got_dust
	_act = "dig"
	_act_t = ACT_S
	hit_end = 0.4 if got > 0 else 0.0
	_hold_pose()
	return got

## Throws the shovelful: into `target` if it's given (the middle of a barrow's tray), or a step ahead onto the ground.
func throw(target: Variant = null) -> bool:
	if not on_foot or shovel_mm <= 0 or _act != "":
		return false
	if target is Vector3:
		_throw_at(Vector2(target.x, target.z), target.y)
	else:
		var to := spot + forward() * THROW_TO
		_throw_at(to, sim.height_at(to))
	_act = "throw"
	_act_t = ACT_S
	_hold_pose()
	return true

## Off the blade in a few clods, arcing to land at `to`, `high` up.
func _throw_at(to: Vector2, high: float) -> void:
	var from := transform * (Vector3(0.55, 0.55, 0.23))
	var pieces := 4
	var left := shovel_mm
	var left_dust := shovel_dust
	for k in pieces:
		var amt := left / (pieces - k)
		var d := left_dust / (pieces - k)
		left -= amt
		left_dust -= d
		if amt <= 0:
			continue
		var aim := Vector3(to.x + _rng.randf_range(-0.08, 0.08), high, to.y + _rng.randf_range(-0.08, 0.08))
		var t := THROW_S * _rng.randf_range(0.92, 1.08)
		var v := (aim - from) / t
		v.y += 0.5 * DirtSim.GRAVITY * t
		sim.held -= amt
		sim.launch(from, v, amt, d)
	shovel_mm = 0
	shovel_dust = 0

## The right arm holds the tool steady, and swings it to dig or throw.
func _hold_pose() -> void:
	for t: String in _tools:
		(_tools[t] as Node3D).visible = t == tool
	_load.visible = tool == "shovel" and shovel_mm > 0
	if tool == "":
		return
	var k := 1.0 - _act_t / ACT_S if _act != "" else 0.0
	var swing := 0.0
	if _act == "dig":
		# Down and in, then up with it.
		swing = -0.35 * sin(k * PI)
	elif _act == "throw":
		swing = 1.1 * sin(k * PI)
	_arms[1].rotation.z = swing + (0.25 if tool == "rake" else 0.1)
	_arms[0].rotation.z = _arms[1].rotation.z * 0.8

## ---------------------------------------------------------------- online
const TOOLS := ["", "shovel", "rake"]

func _net_more() -> PackedFloat32Array:
	return PackedFloat32Array([TOOLS.find(tool), shovel_mm, shovel_dust, ["", "dig", "throw"].find(_act), _act_t])

func _net_take_more(s: PackedFloat32Array) -> void:
	tool = TOOLS[clampi(int(s[NET_BASE]), 0, 2)]
	shovel_mm = int(s[NET_BASE + 1])
	shovel_dust = int(s[NET_BASE + 2])
	_act = ["", "dig", "throw"][clampi(int(s[NET_BASE + 3]), 0, 2)]
	_act_t = s[NET_BASE + 4]
