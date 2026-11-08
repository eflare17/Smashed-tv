class_name Dozer
extends Machine
## The bulldozer: drives on the simulation's ground and pushes its soil. What's banked against the blade pushes back, so
## a big enough load stops the machine and the tracks spin. Every number here is a first guess, to tune by feel.

const MASS := 20000.0           # kg
const FRICTION := 0.5           # how hard soil drags, per its weight
const CUT_FORCE := 110.0        # N for each mm of firm ground cut in a tick, added up across the blade (full width, about 60 kN)
const TOP_SPEED := 3.2          # m/s
const BACK_SPEED := 3.6
const TURN := 0.8               # rad/s, unloaded
const EDGE_X := 2.85            # the blade's cutting edge, ahead of the middle
const HALF_WIDTH := 2.15
const ARM_PIVOT := Vector3(0.85, 0.78, 0.0)
const LIFT_MIN := -0.3          # the cutting edge against the tracks' bottoms, m
const LIFT_MAX := 1.15
const START_LIFT := 0.5         # carried clear of the ground, so it drives until the player lowers it
const LIFT_SPEED := 0.55
const FIRM_RATE := 60           # mm of firm ground the blade takes off a cell each tick at full sweep
const SWEEP_DEPTH := 0.25       # m the blade travels to clear what stands in front of it
const LEVEL_SKIM := 0.01        # m LEVEL leaves the edge above the firm ground, so it strips soil without digging
const LEVEL_LIFT_MIN := -0.9    # LEVEL may reach further down, to get under a pile the machine is riding on
const LEVEL_LIFT_SPEED := 1.1   # m a second
const LEVEL_EASE_UP := 0.8      # m a second, only while it's actually stuck
const LEVEL_EASE_DOWN := 0.6
const LEVEL_DRAG := 0.15        # LEVEL is a helping hand: the soil drags this much of its usual
const CUT_TOP := 2.0            # m/s with CUT on: taking a layer off is a steady job
const CUT_READ := -0.4          # m from the edge it reads the land: behind it, since the last of a cell comes off as the edge passes on
const CUT_CLEAN := 4            # rows of the blade's sweep: the blade itself, and what slid back behind it
const CUT_STEP := 5             # cm the + and - buttons change the depth by
const CUT_MOST := 50
const CUT_DRAG := 0.4           # like LEVEL it's a helping hand, but the soil pushes back harder
const STEADY_OVER := 2.5        # m of travel the blade's height is averaged over, so one bump doesn't dig the next one
const STEADY_SHARE := 0.9       # how much of the machine's pitching the blade takes out
const STEADY_MOST := 0.45       # m

var lift := START_LIFT
var lift_cmd := 0.0

# LEVEL: the machine works the blade to strip the loose soil down to the firm ground, wherever that is.
var level_on := false
var level_trim := 0.0           # m above the firm ground, set with RAISE and LOWER
var level_ease := 0.0

# CUT: the machine holds the blade this far below where the ground began, so it takes an even layer off and follows the land.
var cut_on := false
var cut_cm := 20
## Across as well as along: with CUT on, each end of the blade follows where the ground began on its own side, the blade tilted to
## it, so a paddock's side slope comes off as an even layer too (it used to cut level across, too deep on the high side). How much
## higher the right-hand end is than the left, in m, and the blade's tilt that shows it.
var cut_tilt := 0.0
var blade_roll := 0.0
## Riding over something buried (owner's pick, 9 Nov: it kept stopping dead on the bones): the blade's lifted this much (in its own
## metres) on top of where it's set, to clear the find just ahead, and settles back once past it.
var _ride := 0.0
const RIDE_AHEAD := 0.6         # m ahead of the edge it reads for something buried
const RIDE_CLEAR := 0.03        # m the edge clears its top by
const RIDE_DROP := 1.0          # m a second it settles back once clear
const TILT_MOST := 0.6          # m between the blade's ends, at the most

## The pad it's working in, if any: CUT stops at its height.
var pad: Pad
var at_pad := false

var edge_gap := 0.0             # m from the blade's cutting edge down to the ground under it; negative is below the surface
var bit_ground := false         # the blade touched down this tick

var _steady := 0.0              # the correction that holds the blade steady while the machine pitches
var _edge_avg := NAN
var _pivot: MeshInstance3D
var _body: MeshInstance3D
var _clock := 0.0
var _was_clear := true

func setup(s: DirtSim, v: GroundView, mat: Material, at: Vector2, dir: Vector2) -> void:
	sim = s
	view = v
	spot = at
	angle = atan2(-dir.y, dir.x)
	machine_name = "Dozer" if size == 1.0 else "Big dozer"
	stuck_word = "TOO MUCH TO PUSH: back up, raise the blade, or try LEVEL"
	fp_front = 2.7 * size
	fp_back = 2.3 * size
	fp_r = 1.6 * size
	mass = MASS * size * size * size
	engine = ENGINE * size * size * size
	support_x *= size
	support_z *= size
	track_z *= size
	track_rear *= size
	body_reach *= size
	view_dist *= sqrt(size) * 1.15 if size > 1.0 else 1.0
	view_aim *= size
	top_speed = TOP_SPEED
	back_speed = BACK_SPEED
	turn_rate = TURN
	var frame_kit := MeshKit.new()
	Props.track_frames(frame_kit, 1.15, 0.3, 1.8, 2.3, 1.95, size > 1.0)
	var frame := MeshInstance3D.new()
	frame.mesh = frame_kit.mesh()
	frame.material_override = mat
	add_child(frame)
	var body_kit := MeshKit.new()
	Props.bulldozer(body_kit, size > 1.0)
	_body = MeshInstance3D.new()
	_body.mesh = body_kit.mesh()
	_body.material_override = mat
	add_child(_body)
	if size > 1.0:
		_add_beacon(self, Vector3(-0.45, 3.2, 0.5), mat)
	var blade_kit := MeshKit.new()
	Props.dozer_blade(blade_kit, size > 1.0)
	_pivot = MeshInstance3D.new()
	_pivot.mesh = blade_kit.mesh()
	_pivot.material_override = mat
	add_child(_pivot)
	tracks = TrackRig.new()
	add_child(tracks)
	tracks.setup(mat, Props.track_path(1.8, 2.33, 1.97), 1.15, 0.62, 1.47, Props.dozer_wheels())
	y_smooth = sim.track_height_at(spot)
	_settle(1.0)
	_place_blade()

func stop_commands() -> void:
	super()
	lift_cmd = 0.0

func can_shove(tree_down: bool) -> bool:
	return not (tree_down and lift > 0.9)

func _place_blade() -> void:
	var swing := asin(clampf((lift + _steady / size + _ride) / (EDGE_X - ARM_PIVOT.x), -0.9, 0.9))
	var turn := Basis(Vector3.BACK, swing)
	var t := Transform3D(turn, ARM_PIVOT - turn * ARM_PIVOT)
	if absf(blade_roll) > 0.0001:
		# Tilted about the middle of its cutting edge.
		var mid := t * Vector3(EDGE_X, 0.0, 0.0)
		var r := Basis(Vector3.RIGHT, blade_roll)
		t = Transform3D(r, mid - r * mid) * t
	_pivot.transform = t

## Turns LEVEL on or off.
func set_level(on: bool) -> void:
	level_on = on
	if on:
		cut_on = false
	level_trim = 0.0
	level_ease = 0.0

## Turns CUT on or off. RAISE turns it off too.
func set_cut(on: bool) -> void:
	cut_on = on
	level_ease = 0.0
	if on:
		level_on = false
		level_trim = 0.0

## Deeper or shallower, in steps. A big one can take off twice as much.
func change_cut(steps: int) -> void:
	cut_cm = clampi(cut_cm + steps * CUT_STEP, CUT_STEP, cut_most())

func cut_most() -> int:
	return CUT_MOST * (2 if size > 1.5 else 1)

## Holds the cutting edge the set depth below where the ground began, measured across the blade just ahead of it.
func _hold_cut(dt: float) -> void:
	var ahead := spot + forward() * (EDGE_X * size + CUT_READ)
	var side := Vector2(sin(angle), cos(angle)) * HALF_WIDTH * size * 0.8
	var began := (sim.start_at(ahead) + sim.start_at(ahead + side) + sim.start_at(ahead - side)) / 3.0
	var want := began - cut_cm * 0.01
	# Inside a pegged-out pad it goes no deeper than the pad's height, so it can't dig the floor too low.
	var floor_y := pad.level_at(sim, ahead) if pad else 0.0
	if pad and pad.inside(ahead):
		want = maxf(want, floor_y)
	at_pad = pad != null and pad.inside(ahead) and want <= floor_y + 0.001
	_blade_to(want, dt)
	# Each end the same depth under where the ground began on its side, and no deeper than a pad there wants.
	var ends: Array[float] = []
	for p: Vector2 in [ahead - side, ahead + side]:
		var end_want := sim.start_at(p) - cut_cm * 0.01
		if pad and pad.inside(p):
			end_want = maxf(end_want, pad.level_at(sim, p))
		ends.append(end_want)
	cut_tilt = clampf((ends[1] - ends[0]) / 0.8, -TILT_MOST * size, TILT_MOST * size)
	# The blade drawn tilted to match, less what the machine leaning already does.
	var leaning := (transform.basis * Vector3(0.0, 0.0, 2.0 * HALF_WIDTH)).y
	var roll_want := -asin(clampf((cut_tilt - leaning) / (2.0 * HALF_WIDTH * size), -0.3, 0.3))
	blade_roll = lerpf(blade_roll, roll_want, minf(dt * 6.0, 1.0))

## Something buried under the blade or just ahead of it: the blade's lifted to ride up and over its top rather than the machine
## stopping dead against it, and settles back to where it was set once it's past.
func _ride_over(dt: float) -> void:
	var lowest := INF
	for z: float in [-HALF_WIDTH, HALF_WIDTH]:
		lowest = minf(lowest, (transform * (_pivot.transform * Vector3(EDGE_X, 0.0, z))).y)
	var a3 := transform * (_pivot.transform * Vector3(EDGE_X, 0.0, -HALF_WIDTH))
	var b3 := transform * (_pivot.transform * Vector3(EDGE_X, 0.0, HALF_WIDTH))
	var top := sim.find_top_along(Vector2(a3.x, a3.z), Vector2(b3.x, b3.z), forward(), RIDE_AHEAD * size)
	# The edge's height goes up one for one with the lift, so this is how much lift it wants on top of where it's set, if any.
	var wanted := 0.0
	if top > -INF:
		wanted = maxf((top + RIDE_CLEAR - (lowest - _ride * size)) / size, 0.0)
	var was := _ride
	_ride = wanted if wanted > _ride else maxf(wanted, _ride - RIDE_DROP * dt)
	if _ride != was:
		_place_blade()

## Holds the cutting edge just above the firm ground ahead of it. RAISE and LOWER set how far above.
func _hold_level(dt: float) -> void:
	level_trim += lift_cmd * LIFT_SPEED * 0.5 * dt
	var ahead := spot + forward() * (EDGE_X * size + 0.3)
	_blade_to(sim.firm_at(ahead) + LEVEL_SKIM + level_trim, dt)

func _blade_to(want: float, dt: float) -> void:
	var edge: float = (transform * (_pivot.transform * Vector3(EDGE_X, 0.0, 0.0))).y
	# Only properly stuck does it let go a little, and it comes straight back down once it's moving.
	if slipping and want + level_ease - edge < 0.2:
		level_ease += LEVEL_EASE_UP * dt
	else:
		level_ease = maxf(level_ease - LEVEL_EASE_DOWN * dt, 0.0)
	var err := want + level_ease - edge
	lift = clampf(lift + clampf(err * 8.0, -1.0, 1.0) * LEVEL_LIFT_SPEED * dt, LEVEL_LIFT_MIN, LIFT_MAX)

## Why a blade left to itself makes waves: the blade is far ahead of the tracks, so it lifts more than the tracks climb. It cuts
## a dip, the machine drives down into it, the blade digs deeper still, and round it goes. So while the blade is working it
## keeps to the height it's been averaging over the last few metres, with the machine pitching underneath it.
func _steady_blade(dt: float) -> void:
	var swing := asin(clampf(lift / (EDGE_X - ARM_PIVOT.x), -0.9, 0.9))
	var turn := Basis(Vector3.BACK, swing)
	var raw: float = (transform * (ARM_PIVOT + turn * (Vector3(EDGE_X, 0.0, 0.0) - ARM_PIVOT))).y
	if is_nan(_edge_avg):
		_edge_avg = raw
	# Moving the blade is the driver's say, and high up there's nothing to hold steady against.
	var working := not level_on and not cut_on and lift_cmd == 0.0 and edge_gap < 0.25
	if not working:
		_edge_avg = raw
		_steady = move_toward(_steady, 0.0, 1.5 * dt)
		return
	_edge_avg = lerpf(_edge_avg, raw, minf(absf(speed) * dt / (STEADY_OVER * size), 1.0))
	_steady = clampf((_edge_avg - raw) * STEADY_SHARE, -STEADY_MOST * size, STEADY_MOST * size)

## One physics tick.
func step(dt: float) -> void:
	if cut_on and lift_cmd > 0.05:
		set_cut(false)
	top_speed = CUT_TOP if cut_on else TOP_SPEED
	if level_on:
		_hold_level(dt)
	elif cut_on:
		_hold_cut(dt)
	else:
		lift = clampf(lift + lift_cmd * LIFT_SPEED * dt, LIFT_MIN, LIFT_MAX)
	if not cut_on:
		cut_tilt = 0.0
		blade_roll = lerpf(blade_roll, 0.0, minf(dt * 6.0, 1.0))
	_steady_blade(dt)
	_place_blade()
	_ride_over(dt)
	hyd = absf(lift_cmd)

	# Where the cutting edge really is, with the machine tipped as it is.
	var a3 := transform * (_pivot.transform * Vector3(EDGE_X, 0.0, -HALF_WIDTH))
	var b3 := transform * (_pivot.transform * Vector3(EDGE_X, 0.0, HALF_WIDTH))
	var a := Vector2(a3.x, a3.z)
	var b := Vector2(b3.x, b3.z)
	var edge_mm := int((a3.y + b3.y) * 500.0)
	edge_gap = (a3.y + b3.y) * 0.5 - sim.height_at((a + b) * 0.5)
	bit_ground = _was_clear and edge_gap < 0.0
	if edge_gap < 0.0:
		_was_clear = false
	elif edge_gap > 0.12:
		_was_clear = true
	blade_a = a
	blade_b = b
	moved_tick = 0
	var f := forward()

	var cut := 0
	on_rock = false
	# Only working when it's going forward or trying to: a parked machine doesn't dig.
	if speed > 0.02 or (throttle > 0.05 and speed > -0.05):
		# It moves what it sweeps through: no travel, no soil moved, so a stalled blade can't pump soil up a pile.
		var share := clampf(maxf(speed, 0.0) * dt / SWEEP_DEPTH, 0.0, 1.0)
		var r: Array = sim.blade(a, b, f, edge_mm, ceili(FIRM_RATE * size), share, CUT_CLEAN if cut_on else 2, size, int(cut_tilt * 1000.0))
		moved_m3 += DirtSim.to_m3(r[0])
		moved_tick = r[0]
		cut = r[1]
		on_rock = r[2]
	load_t = sim.load_ahead(a, b, f, edge_mm, size)

	var drag := load_t * 1000.0 * 9.8 * FRICTION + cut * CUT_FORCE
	if level_on:
		drag *= LEVEL_DRAG
	elif cut_on:
		drag *= CUT_DRAG
	_drive(dt, drag, level_on or cut_on, 1.0 - clampf(load_t / (20.0 * size * size * size), 0.0, 0.65))
	_shake_body(dt)
	_settle(minf(dt * 10.0, 1.0))

var _net_lift := START_LIFT
var _net_steady := 0.0

func _net_more() -> PackedFloat32Array:
	return PackedFloat32Array([lift, _steady, edge_gap, int(level_on) | int(cut_on) << 1, cut_cm])

func _net_take_more(s: PackedFloat32Array) -> void:
	_net_lift = s[NET_BASE]
	_net_steady = s[NET_BASE + 1]
	edge_gap = s[NET_BASE + 2]
	var flags := int(s[NET_BASE + 3])
	level_on = flags & 1 != 0
	cut_on = flags & 2 != 0
	cut_cm = int(s[NET_BASE + 4])

func _net_pose(dt: float, k: float) -> void:
	lift = lerpf(lift, _net_lift, k)
	_steady = lerpf(_steady, _net_steady, k)
	_place_blade()
	_shake_body(dt)

func _net_cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([lift_cmd])

func _net_take_cmds_more(c: PackedFloat32Array) -> void:
	lift_cmd = c[2]

## The engine shaking the machine, and the body swaying on its mounts. The tracks stay on the ground under it.
func _shake_body(dt: float) -> void:
	_clock += dt
	var work := absf(drive)
	_body.position.y = sin(_clock * 58.0) * (0.006 + 0.014 * work) + sin(_clock * 37.0) * 0.004 * work
	var lean := clampf(load_t / (25.0 * size * size * size), 0.0, 1.0) * 0.012 * work
	_body.rotation.z = rock_pitch + lean + sin(_clock * 23.0) * 0.0015 * work
	_body.rotation.x = rock_roll

## ---------------------------------------------------------------- the side-on picture
func side_view() -> Dictionary:
	var profile: Array[Vector2] = [Vector2(EDGE_X, 0.0), Vector2(2.82, 0.14), Vector2(2.68, 0.55), Vector2(2.7, 1.1), Vector2(2.9, 1.62), Vector2(3.08, 1.72), Vector2(2.9, 1.72), Vector2(2.72, 1.62), Vector2(2.52, 1.1), Vector2(2.5, 0.55), Vector2(2.66, 0.0)]
	var pose := _pivot.transform
	var edge3 := pose * Vector3(EDGE_X, 0.0, 0.0)
	var edge := Vector2(edge3.x, edge3.y)
	var shape: Array[Vector2] = []
	for p: Vector2 in profile:
		var q := pose * Vector3(p.x, p.y, 0.0)
		shape.append(Vector2(q.x, q.y) - edge)
	return {
		"low": -1.2, "high": 3.2, "left": -2.2,
		"body": [Rect2(-2.3, 0.0, 4.6, 0.7), Rect2(-2.2, 0.7, 3.1, 0.9), Rect2(-1.7, 1.6, 1.4, 1.2)],
		"joints": [Vector2(ARM_PIVOT.x, ARM_PIVOT.y), edge],
		"pin": edge,
		"turn": 0.0,
		"shape": shape,
		"reach": 0.0,
		"level_long": 1.2,
		"fill_from": Vector2.ZERO,
		"fill": 0.0,
		"dust": false,
		"angle": rad_to_deg(pose.basis.get_euler().z),
		"pours": false,
		"down": -edge_gap,
		"near": 0.06,
		"blade": true,
	}

## For the checks: put back somewhere else, settled, blade where it was.
func reposition_for_test(at: Vector2, dir: Vector2) -> void:
	spot = at
	angle = atan2(-dir.y, dir.x)
	speed = 0.0
	drive = 0.0
	y_smooth = sim.track_height_at(spot)
	basis_smooth = Basis.IDENTITY
	_settle(1.0)
