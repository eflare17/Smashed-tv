class_name Truck
extends Machine
## The dump truck. It steers like a road vehicle, so it can't turn on the spot. Soil falling on its tray stays there as real
## soil, it gets heavier and slower the more it carries, and raising the tray pours the load out the back as falling chunks.
## Every number here is a first guess, to tune by feel.
## On the mine it's the haul truck instead: the same truck, built far bigger, with the big excavator to fill it.

const EMPTY_MASS := 13000.0     # kg
const TOP_SPEED_EMPTY := 7.0    # m/s, about 25 km/h: fast for a site, and a big change from the machines that dig
const BACK_SPEED_EMPTY := 3.0
const WHEELBASE := 4.3
const STEER_MOST := 0.55        # radians at the front wheels
const CAPACITY := 128000        # mm on one cell's area: 8 m3
const HINGE := Vector3(-3.55, 1.28, 0.0)
const TRAY_LONG := 4.6
const TRAY_HALF := 1.2
const TRAY_HIGH := 0.95
const TIP_UP := 0.42            # rad a second
const TIP_DOWN := 0.5
const TIP_MOST := 0.95
const POUR_FROM := 0.22         # radians tilted before the load starts to go
const POUR_ALL := 0.75          # and by here none of it stays
const POUR_RATE := 44000        # mm a second, at most
const CHUNK := 1600             # mm a falling chunk carries (0.1 m3)

# The haul truck: about 11 m long and 7 wide, the tray's rim 5 m up. It takes five or six of the big excavator's buckets.
const HAUL_MASS := 65000.0
const EMPTY_RUT := 50           # mm its tyres press into loose soil empty
const FULL_RUT := 100           # and full
const HAUL_TOP := 8.0           # m/s, about 30 km/h empty
const HAUL_WHEELBASE := 6.2
const HAUL_STEER := 0.6
const HAUL_CAPACITY := 640000   # 40 m3
const HAUL_HINGE := Vector3(-4.6, 3.15, 0.0)
const HAUL_TRAY_LONG := 6.5
const HAUL_TRAY_HALF := 3.3
const HAUL_TRAY_HIGH := 2.0
const HAUL_WHEEL_R := 1.5

## Set before setup for the mine's haul truck.
var haul := false
var empty_mass := EMPTY_MASS
var top_empty := TOP_SPEED_EMPTY
var back_empty := BACK_SPEED_EMPTY
var wheelbase := WHEELBASE
var steer_most := STEER_MOST
var capacity := CAPACITY
var hinge := HINGE
var tray_long := TRAY_LONG
var tray_half := TRAY_HALF
var tray_high := TRAY_HIGH
var tip_up := TIP_UP
var tip_most := TIP_MOST
var pour_rate := POUR_RATE
var chunk := CHUNK
var bumper := Vector2(3.3, 1.25)    # how far ahead the front is, and half its width
var _chassis := [Vector3(-3.8, 0.4, -1.0), Vector3(2.8, 1.1, 1.0)]   # for the side-on picture
var _cab := [Vector3(1.65, 1.1, -1.2), Vector3(3.3, 2.9, 1.2)]

var tip_cmd := 0.0              # 1 raises the tray; let go and it comes down
var tip := 0.0
var tray_mm := 0
var tray_dust := 0
var _pour_dust := 0
var _mat: Material

var _tray: Node3D
var _lump: MeshInstance3D
var _body: Node3D
var _pour_store := 0
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _was_up := false

func setup(s: DirtSim, v: GroundView, mat: Material, at: Vector2, dir: Vector2) -> void:
	sim = s
	view = v
	spot = at
	angle = atan2(-dir.y, dir.x)
	machine_name = "Truck"
	hint = "Park by a digger and let it fill you, then hold TIP to pour it out"
	view_dist = 15.0
	view_pitch = 20.0
	eye = Vector3(2.55, 2.45, -0.5)
	pipe = Vector3(1.6, 3.1, -1.1)
	support_x = 2.4
	support_z = 1.05
	track_z = 1.05
	track_rear = 2.4
	rut_half = 0.28
	fp_back = 3.6
	fp_front = 3.3
	fp_r = 1.25
	body_reach = 1.6
	if haul:
		_make_haul()
	mass = empty_mass
	top_speed = top_empty
	back_speed = back_empty
	_speed_cap = top_empty
	_rng.seed = 41
	_body = Node3D.new()
	add_child(_body)
	var kit := MeshKit.new()
	if haul:
		Props.haul_body(kit)
	else:
		Props.truck_body(kit)
	_add_mesh(_body, kit, mat)
	_tray = Node3D.new()
	_tray.position = hinge
	_body.add_child(_tray)
	kit = MeshKit.new()
	if haul:
		Props.haul_tray(kit, tray_long, tray_half, tray_high)
	else:
		Props.truck_tray(kit, tray_long, tray_half, tray_high)
	_add_mesh(_tray, kit, mat)
	kit = MeshKit.new()
	# A heap: wide at the bottom, a long ridge along the top. Scaled to how much is in it.
	kit.prism([Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.32, 0.65), Vector2(0.0, 1.0), Vector2(-0.32, 0.65)], -0.5, 0.5, Props.DIRT)
	_lump = _add_mesh(_tray, kit, mat)
	_mat = mat
	_lump.rotation.y = PI * 0.5
	_lump.visible = false
	if haul:
		var wheel_kit := MeshKit.new()
		Props.wheel(wheel_kit, 1.15)
		var front := wheel_kit.mesh()
		wheel_kit = MeshKit.new()
		Props.wheel(wheel_kit, 1.0)
		var rear := wheel_kit.mesh()
		for side: float in [-1.0, 1.0]:
			_add_wheel(front, mat, Vector3(3.0, HAUL_WHEEL_R, side * 2.45), HAUL_WHEEL_R, true)
			_add_wheel(rear, mat, Vector3(-3.2, HAUL_WHEEL_R, side * 1.85), HAUL_WHEEL_R)
			_add_wheel(rear, mat, Vector3(-3.2, HAUL_WHEEL_R, side * 2.95), HAUL_WHEEL_R)
		_add_beacon(_body, Vector3(3.3, 6.12, -2.05), mat)
	else:
		var wheel_kit := MeshKit.new()
		Props.wheel(wheel_kit, 0.34)
		var wide_kit := MeshKit.new()
		Props.wheel(wide_kit, 0.56)
		var tyre := wheel_kit.mesh()
		var wide := wide_kit.mesh()
		for side: float in [-1.0, 1.0]:
			_add_wheel(tyre, mat, Vector3(2.3, 0.6, side * 1.08), 0.6, true)
			_add_wheel(wide, mat, Vector3(-1.5, 0.6, side * 0.98), 0.6)
			_add_wheel(wide, mat, Vector3(-2.75, 0.6, side * 0.98), 0.6)
	y_smooth = sim.track_height_at(spot)
	_settle(1.0)
	sim.catchers.append(self)
	_place_blade_points()

## Everything about the haul truck that isn't the road truck's.
func _make_haul() -> void:
	machine_name = "Haul truck"
	hint = "Back up beside the big excavator to be filled, then take it up the ramp and hold TIP to dump it"
	empty_mass = HAUL_MASS
	top_empty = HAUL_TOP
	back_empty = 3.0
	wheelbase = HAUL_WHEELBASE
	steer_most = HAUL_STEER
	capacity = HAUL_CAPACITY
	hinge = HAUL_HINGE
	tray_long = HAUL_TRAY_LONG
	tray_half = HAUL_TRAY_HALF
	tray_high = HAUL_TRAY_HIGH
	tip_up = 0.3
	tip_most = 0.9
	pour_rate = 110000
	chunk = 4800
	engine = ENGINE * HAUL_MASS / EMPTY_MASS
	bumper = Vector2(6.3, 3.3)
	_chassis = [Vector3(-4.7, 0.2, -3.5), Vector3(6.3, 3.95, 3.5)]
	_cab = [Vector3(2.4, 3.95, -3.0), Vector3(4.9, 6.0, -1.1)]
	view_dist = 27.0
	view_pitch = 22.0
	view_aim = 3.6
	eye = Vector3(3.9, 5.35, -2.05)
	pipe = Vector3(1.8, 4.3, 1.3)
	support_x = 3.1
	support_z = 2.5
	track_z = 2.5
	track_rear = 3.2
	rut_half = 1.0
	fp_back = 4.7
	fp_front = 6.3
	fp_r = 3.4
	body_reach = 3.4

func _add_mesh(parent: Node3D, kit: MeshKit, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = mat
	parent.add_child(m)
	return m

func stop_commands() -> void:
	super()
	tip_cmd = 0.0

func fill() -> float:
	return float(tray_mm) / capacity

func gauge_word() -> Array:
	var word := "LOAD %.1f m3" % DirtSim.to_m3(tray_mm)
	if tip > 0.03:
		return [word + "   TIPPING", Color("#ff9a4a")]
	return [word, Color("#a8f07a")]

## Road-style steering: how fast it turns depends on how fast it's going.
func _turning(_turn_share: float) -> float:
	return speed / wheelbase * tan(turn_cmd * steer_most)

## Soil landing on the tray stays in it. Tipped, or full, it goes on past.
func catch_soil(pos: Vector3, amt: int, dust_amt := 0) -> bool:
	if tip > 0.04 or tray_mm + amt > capacity:
		return false
	var at := transform.affine_inverse() * pos
	var x := at.x - hinge.x
	if x < 0.0 or x > tray_long or absf(at.z) > tray_half:
		return false
	# The heap's surface: it lands when it gets down to whatever's already there.
	var top := hinge.y + 0.1 + _heap_high() * 0.7
	if at.y > top or at.y < hinge.y - 0.3:
		return false
	tray_mm += amt
	tray_dust += dust_amt
	return true

func _heap_high() -> float:
	return tray_high * (0.263 + 1.316 * sqrt(fill()))

func step(dt: float) -> void:
	_clock += dt
	var want := tip_up if tip_cmd > 0.0 else -TIP_DOWN
	# Slower to lift heavy, and it doesn't drive off with it up without slowing down.
	if tip_cmd > 0.0:
		want *= lerpf(1.0, 0.6, fill())
	var before := tip
	tip = clampf(tip + want * dt, 0.0, tip_most)
	hyd = clampf(absf(tip - before) / dt / tip_up, 0.0, 1.0) if tip_cmd > 0.0 else 0.0
	hit_end = 0.0
	if before < tip_most and tip >= tip_most:
		hit_end = 0.7
	elif before > 0.0 and tip <= 0.0:
		hit_end = 1.0
	_pour(dt)
	mass = empty_mass + DirtSim.to_m3(tray_mm) * 1500.0
	load_t = DirtSim.to_m3(tray_mm) * 1.5
	# Its tyres sink further in loose soil with a load on (owner, 9 Nov): 5 cm empty, 10 cm full.
	rut_mm = int(lerpf(EMPTY_RUT, FULL_RUT, fill()))
	# Loaded, it's slower. With the tray up it creeps.
	top_speed = top_empty * lerpf(1.0, 0.6, fill()) * (0.3 if tip > 0.1 else 1.0)
	back_speed = back_empty * (0.5 if tip > 0.1 else 1.0)
	_drive(dt, 0.0)
	_place_blade_points()
	_sway(dt)
	_settle(minf(dt * 8.0, 1.0))

var _net_tip := 0.0

func _net_more() -> PackedFloat32Array:
	return PackedFloat32Array([tip, tray_mm, tray_dust])

func _net_take_more(s: PackedFloat32Array) -> void:
	_net_tip = s[NET_BASE]
	tray_mm = int(s[NET_BASE + 1])
	tray_dust = int(s[NET_BASE + 2])

func _net_pose(dt: float, k: float) -> void:
	_clock += dt
	tip = lerpf(tip, _net_tip, k)
	_sway(dt)

func _net_cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([tip_cmd])

func _net_take_cmds_more(c: PackedFloat32Array) -> void:
	tip_cmd = c[2]

## What it hits a tree with: the front bumper.
func _place_blade_points() -> void:
	var f := forward()
	var side := Vector2(sin(angle), cos(angle))
	var front := spot + f * bumper.x
	blade_a = front - side * bumper.y
	blade_b = front + side * bumper.y

func _sway(_dt: float) -> void:
	var load_share := fill()
	# Heavy, the back squats. The springs let the body ride over the chassis, and the engine shakes it a little.
	_body.rotation.z = rock_pitch * 1.3 + 0.02 * load_share + sin(_clock * 41.0) * 0.001 * absf(drive)
	_body.rotation.x = rock_roll * 1.4
	_body.position.y = sin(_clock * 53.0) * 0.004 - 0.05 * load_share
	_tray.rotation.z = tip
	var show := tray_mm > 0
	_lump.visible = show
	if show:
		_lump.material_override = Props.dust_mat() if tray_dust * 2 > tray_mm else _mat
		var f := sqrt(fill())
		var along := tray_long * (0.348 + 0.609 * f)
		var across := tray_half * 2.0 * (0.458 + 0.521 * f)
		# A small load slides back towards the hinge as it tips, a big one fills the tray.
		var slide := minf(tip * 0.6, 0.5) * (1.0 - f)
		_lump.scale = Vector3(across, _heap_high(), along)
		_lump.position = Vector3(tray_long * 0.5 - (tray_long - along) * 0.5 * slide, 0.08, 0.0)

## Tilted past where it holds, the load goes out the back in real chunks.
func _pour(dt: float) -> void:
	var share := clampf((tip - POUR_FROM) / (POUR_ALL - POUR_FROM), 0.0, 1.0)
	var over := maxi(tray_mm - int(capacity * (1.0 - share)), 0)
	if tip <= POUR_FROM or tray_mm == 0:
		over = 0
	# Whatever's left once it's fully up still comes out.
	if tip >= POUR_ALL:
		over = tray_mm
	var out := mini(over, ceili(pour_rate * dt))
	pouring = lerpf(pouring, clampf(float(out) / (pour_rate * dt), 0.0, 1.0), minf(dt * 8.0, 1.0))
	if out <= 0:
		return
	var out_dust := tray_dust * out / tray_mm
	tray_mm -= out
	tray_dust -= out_dust
	_pour_store += out
	_pour_dust += out_dust
	var edge := hinge - Vector3(0.1, 0.1, 0.0)
	pour_spot = transform * edge
	var f := forward()
	var drop := tray_high / TRAY_HIGH
	while _pour_store >= chunk or (tray_mm == 0 and _pour_store > 0):
		var amt := mini(chunk, _pour_store)
		var chunk_dust := _pour_dust * amt / _pour_store
		_pour_store -= amt
		_pour_dust -= chunk_dust
		sim.held -= amt
		var at := transform * (edge + Vector3(0.0, _rng.randf_range(0.0, 0.4 * drop), _rng.randf_range(-tray_half, tray_half) * 0.9))
		sim.launch(at, Vector3(-f.x * _rng.randf_range(0.8, 2.0), -0.5, -f.y * _rng.randf_range(0.8, 2.0)), amt, chunk_dust)

## ---------------------------------------------------------------- for the side-on picture of whoever's loading it
## Its parts as corners in the world: tray, what's in it, cab and chassis.
func side_shapes() -> Dictionary:
	var on_body := transform * _body.transform
	var on_tray := on_body * _tray.transform
	return {
		"chassis": _corners(on_body, _chassis[0], _chassis[1]),
		"cab": _corners(on_body, _cab[0], _cab[1]),
		"tray": _corners(on_tray, Vector3(0.0, 0.0, -tray_half), Vector3(tray_long, tray_high, tray_half)),
		"soil": _corners(on_tray, Vector3(0.1, 0.05, -tray_half), Vector3(tray_long - 0.1, 0.05 + _heap_high(), tray_half)),
		"floor": _corners(on_tray, Vector3(0.0, 0.0, -tray_half), Vector3(tray_long, 0.0, tray_half)).slice(0, 4),
	}

func _corners(t: Transform3D, a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for y: float in [a.y, b.y]:
		for corner: Vector2 in [Vector2(a.x, a.z), Vector2(b.x, a.z), Vector2(b.x, b.z), Vector2(a.x, b.z)]:
			out.append(t * Vector3(corner.x, y, corner.y))
	return out

## Whether soil let go here would come down in the tray, and whether it's above the sides to start with.
func over_tray(w: Vector3) -> bool:
	var at := transform.affine_inverse() * w
	var x := at.x - hinge.x
	return x >= 0.0 and x <= tray_long and absf(at.z) <= tray_half

func tray_rim() -> float:
	return (transform * Vector3(hinge.x, hinge.y + tray_high, 0.0)).y
