class_name Barrow
extends Machine
## A wheelbarrow. GET IN takes its handles: then it's walked about on the stick, its one wheel out front, with the worker shown
## pushing it. Soil shovelled at it lands in the tray and stays there, and holding TIP lifts the handles and pours it out over the
## wheel. In game.machines like the rest, so pushing it, bumping into things and playing with a friend all work the same way.

const WALK := 1.7               # m/s pushed, a bit slower than walking
const BACK := 0.9
const TURN := 2.2
const EASE := 6.0
const CAPACITY := 1536          # mm on one cell's area: 0.096 m3, eight shovelfuls
const TIP_UP := 1.6             # how fast the handles go up, of the whole way a second
const TIP_DOWN := 2.5
const POUR_FROM := 0.35         # of the way up before it starts to come out
const POUR_RATE := 2400         # mm a second at most
const CHUNK := 96               # mm a falling chunk carries
const WHEEL := Vector3(0.78, 0.2, 0.0)
const TRAY_FROM := -0.25        # the tray, along it
const TRAY_TO := 0.62
const TRAY_HALF := 0.33
const TRAY_FLOOR := 0.36
const TRAY_TOP := 0.68
const HANDS := 1.25             # m behind the middle the worker stands, pushing

var tip_cmd := 0.0
var tip := 0.0                  # 0 down on its legs, 1 tipped right over the wheel
var tray_mm := 0
var tray_dust := 0
var _pour_store := 0
var _pour_dust := 0
var _tray: Node3D               # everything but the wheel and the pusher: it swings up round the wheel to tip
var _wheel: MeshInstance3D
var _lump: MeshInstance3D
var _man: Node3D
var _legs: Array[Node3D] = []
var _phase := 0.0
var _mat: Material
var _rng := RandomNumberGenerator.new()
var _pushed := false

func setup(s: DirtSim, v: GroundView, mat: Material, at: Vector2, dir: Vector2) -> void:
	sim = s
	view = v
	spot = at
	angle = atan2(-dir.y, dir.x)
	machine_name = "Barrow"
	hint = "Shovel dirt into it, push it where it's wanted, then hold TIP"
	stuck_word = ""
	mass = 120.0
	top_speed = WALK
	back_speed = BACK
	turn_rate = TURN
	view_dist = 6.0
	view_pitch = 22.0
	view_aim = 0.9
	eye = Vector3(-HANDS + 0.12, 1.36, 0.0)
	pipe = Vector3(0.0, 0.5, 0.0)
	support_x = 0.55
	support_z = 0.3
	side_lean_most = 0.25
	body_reach = 0.4
	fp_back = 0.55
	fp_front = 0.85
	fp_r = 0.36
	_rng.seed = 13
	_mat = mat
	_tray = Node3D.new()
	_tray.position = WHEEL
	add_child(_tray)
	var kit := MeshKit.new()
	Props.barrow(kit, WHEEL)
	_add(_tray, kit, mat)
	kit = MeshKit.new()
	kit.prism([Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.3, 0.6), Vector2(0.0, 1.0), Vector2(-0.3, 0.6)], -0.5, 0.5, Props.DIRT)
	_lump = _add(_tray, kit, mat)
	_lump.visible = false
	kit = MeshKit.new()
	Props.wheel(kit, 0.09)
	_wheel = _add(self, kit, mat)
	_wheel.position = WHEEL
	_wheel.scale = Vector3(0.2, 0.2, 1.0)
	# The worker pushing it, shown only while somebody is.
	_man = Node3D.new()
	_man.position = Vector3(-HANDS, 0.0, 0.0)
	add_child(_man)
	kit = MeshKit.new()
	Props.worker_body(kit)
	_add(_man, kit, mat)
	for z: float in [-0.1, 0.1]:
		var hip := Node3D.new()
		hip.position = Vector3(0.0, 0.71, z)
		_man.add_child(hip)
		kit = MeshKit.new()
		Props.worker_leg(kit)
		_add(hip, kit, mat)
		_legs.append(hip)
	for z: float in [-0.23, 0.23]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.0, 1.16, z)
		shoulder.rotation.z = 0.5
		_man.add_child(shoulder)
		kit = MeshKit.new()
		Props.worker_arm(kit)
		_add(shoulder, kit, mat)
	_man.visible = false
	y_smooth = sim.height_at(spot)
	_settle(1.0)
	sim.catchers.append(self)
	_pose()

func _add(parent: Node3D, kit: MeshKit, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = mat
	parent.add_child(m)
	return m

func show_driver(on: bool) -> void:
	_pushed = on
	_man.visible = on

func stop_commands() -> void:
	super()
	tip_cmd = 0.0

func fill() -> float:
	return float(tray_mm) / CAPACITY

## How many shovelfuls are in it, of how many it holds.
func scoops() -> int:
	return roundi(float(tray_mm) / Worker.SCOOP)

func gauge_word() -> Array:
	var word := "BARROW %d OF %d SCOOPS" % [scoops(), CAPACITY / Worker.SCOOP]
	if tip > 0.05:
		return [word + "   TIPPING", Color("#ff9a4a")]
	return [word, Color("#a8f07a") if tray_mm < CAPACITY else Color("#ffd23f")]

func effort() -> float:
	return 0.0

func hit_speed() -> float:
	return 0.0

func _wear_tracks() -> void:
	pass

## The middle of the tray, in the world: where a shovelful's thrown to get it in.
func tray_middle() -> Vector3:
	return transform * (Vector3((TRAY_FROM + TRAY_TO) * 0.5, TRAY_FLOOR + 0.1 + _heap() * 0.5, 0.0))

## Soil landing in the tray stays there. Tipped, or full, it goes on past.
func catch_soil(pos: Vector3, amt: int, dust_amt := 0) -> bool:
	if tip > 0.08 or tray_mm + amt > CAPACITY:
		return false
	var at := transform.affine_inverse() * pos
	if at.x < TRAY_FROM or at.x > TRAY_TO or absf(at.z) > TRAY_HALF:
		return false
	if at.y > TRAY_FLOOR + 0.12 + _heap() or at.y < TRAY_FLOOR - 0.25:
		return false
	tray_mm += amt
	tray_dust += dust_amt
	return true

func _heap() -> float:
	return 0.32 * sqrt(fill())

func step(dt: float) -> void:
	var before := tip
	tip = clampf(tip + (TIP_UP if tip_cmd > 0.0 else -TIP_DOWN) * dt, 0.0, 1.0)
	hit_end = 0.6 if before > 0.0 and tip <= 0.0 else 0.0
	_pour(dt)
	load_t = DirtSim.to_m3(tray_mm) * 1.5
	# Tipping, it stands still. Loaded, it's a bit slower.
	var want := 0.0 if tip > 0.05 else throttle
	drive = move_toward(drive, want, EASE * dt)
	speed = drive * (WALK * lerpf(1.0, 0.8, fill()) if drive >= 0.0 else BACK)
	turn_cmd = move_toward(turn_cmd, steer if tip <= 0.05 else 0.0, EASE * 1.5 * dt)
	angle -= turn_cmd * TURN * dt
	var go := spot + forward() * speed * dt
	var got := go.clamp(Vector2(-AREA, -AREA), Vector2(AREA, AREA))
	at_edge = got != go
	spot = got
	_settle(minf(dt * 12.0, 1.0))
	_pose(dt)

## Wheel turning, the tray lifted as it's pushed and tipped right up to pour, and the pusher walking.
func _pose(dt := 0.0) -> void:
	if dt > 0.0:
		_wheel.rotation.z = fposmod(_wheel.rotation.z - speed / WHEEL.y * dt, TAU)
		_phase = fposmod(_phase + absf(speed) * dt / 1.3 * TAU + absf(turn_cmd) * dt * 4.0, TAU)
	# Handles up a little to wheel it, and right up over the wheel to tip it.
	var lifted := 0.12 if _pushed else 0.0
	_tray.rotation.z = -(lifted + tip * 0.95)
	var a := sin(_phase) * 0.5 * clampf(absf(speed) / WALK + absf(turn_cmd) * 0.4, 0.0, 1.0)
	_legs[0].rotation.z = a
	_legs[1].rotation.z = -a
	_lump.visible = tray_mm > 0
	if _lump.visible:
		_lump.material_override = Props.dust_mat() if tray_dust * 2 > tray_mm else _mat
		var f := sqrt(fill())
		_lump.scale = Vector3(0.45 + 0.4 * f, _heap() + 0.05, 0.5 + 0.35 * f)
		_lump.rotation.y = PI * 0.5
		_lump.position = Vector3((TRAY_FROM + TRAY_TO) * 0.5, TRAY_FLOOR + 0.02, 0.0) - WHEEL

## Tipped far enough, the load goes out over the front in real chunks.
func _pour(dt: float) -> void:
	pouring = 0.0
	if tip < POUR_FROM or tray_mm == 0:
		return
	var out := mini(tray_mm, ceili(POUR_RATE * dt * (tip - POUR_FROM) / (1.0 - POUR_FROM) * 2.0))
	if tip >= 0.95:
		out = mini(tray_mm, ceili(POUR_RATE * dt))
	if out <= 0:
		return
	pouring = 1.0
	var out_dust := tray_dust * out / tray_mm
	tray_mm -= out
	tray_dust -= out_dust
	_pour_store += out
	_pour_dust += out_dust
	var f := forward()
	var lip := transform * (WHEEL + Vector3(0.2, 0.25, 0.0))
	pour_spot = lip
	while _pour_store >= CHUNK or (tray_mm == 0 and _pour_store > 0):
		var amt := mini(CHUNK, _pour_store)
		var d := _pour_dust * amt / _pour_store
		_pour_store -= amt
		_pour_dust -= d
		sim.held -= amt
		var side := Vector2(sin(angle), cos(angle)) * _rng.randf_range(-0.25, 0.25)
		sim.launch(lip + Vector3(side.x, 0.0, side.y), Vector3(f.x * _rng.randf_range(0.3, 1.0), 0.2, f.y * _rng.randf_range(0.3, 1.0)), amt, d)

var _net_tip := 0.0

func _net_more() -> PackedFloat32Array:
	return PackedFloat32Array([tip, tray_mm, tray_dust])

func _net_take_more(s: PackedFloat32Array) -> void:
	_net_tip = s[NET_BASE]
	tray_mm = int(s[NET_BASE + 1])
	tray_dust = int(s[NET_BASE + 2])

func _net_pose(dt: float, k: float) -> void:
	tip = lerpf(tip, _net_tip, k)
	_pose(dt)

func _net_cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([tip_cmd])

func _net_take_cmds_more(c: PackedFloat32Array) -> void:
	tip_cmd = c[2]

## Moved, for a job, without a jolt.
func reposition(at: Vector2, dir: Vector2) -> void:
	spot = at
	angle = atan2(-dir.y, dir.x)
	y_smooth = sim.track_height_at(spot)
	basis_smooth = Basis.IDENTITY
	_settle(1.0)
	_pose()
