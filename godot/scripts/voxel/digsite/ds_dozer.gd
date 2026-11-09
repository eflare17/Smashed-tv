class_name DsDozer
extends DsMachine
## The bulldozer (the owner, 8 Nov: "put a bulldozer in there"), the digger game's Dozer: its model (DsProps.bulldozer,
## dozer_blade, its tracks), its numbers. R/F raise and lower the blade. Driving on, its cutting edge cuts everything
## standing above it (DsTerrain.blade): the loose soil at once, firm ground a bit at a time, and banks it up against
## the blade, the rest rolling off its ends; the heap goes with it, picked up again as it drives on, so you push dirt
## about. What's banked against the blade pushes back: the more of it, the slower it goes, and the tracks bog. It
## won't cut rock (stone and harder): it stops dead. As the digger game's: it moves only what it sweeps through (no
## travel, nothing moved: a stalled blade can't pump a heap up), the blade's held steady while the machine pitches under
## it (else it cuts a dip, drives down into it and digs deeper still), and Q's CUT holds the edge a set depth (T/G, 5
## cm steps) under where the ground began, so it takes an even layer off. In co-op the host's game runs it. Owned by
## the voxel session.

# (the digger game's: dozer.gd)
const EDGE_X := 2.85            # the blade's cutting edge, ahead of the middle
const HALF_WIDTH := 2.15
const ARM_PIVOT := Vector3(0.85, 0.78, 0.0)
const LIFT_MIN := -0.3          # the edge this far under the tracks' bottoms (m) ...
const LIFT_MAX := 1.15          # ... up to this
const LIFT_SPEED := 0.55
const START_LIFT := 0.35
const HEAP := 1.25              # m over the edge it banks soil up against the blade (1.6 stood level with the blade's top,
                                # so the heap showed over and through its curled top edge: the owner, 9 Nov)
const LIP := 0.2                # m the blade's top curls out ahead of its edge: the soil's kept off that too
const MOUTH := 1.7              # m over the edge the blade reaches
const FIRM := 3                 # firm blocks it cuts off a column at full sweep
const HARDEST := 2              # soil and clay: stone stops it
const BOG := 3500.0             # loose blocks banked ahead that bring it nearly to a stop
const CUT_BOG := 3000.0         # firm blocks a second cut that would bring it to a stop (a deep cut is slow going)
const SWEEP_DEPTH := 0.25       # m the blade travels to clear what stands in front of it
const STEADY_OVER := 2.5        # m of travel the blade's height is averaged over, so one bump doesn't dig the next one
const STEADY_SHARE := 0.9       # how much of the machine's pitching the blade takes out
const STEADY_MOST := 0.45       # m
const CUT_READ := -0.4          # m from the edge CUT reads where the ground began (behind it: the last of it comes off there)
const CUT_STEP := 5             # cm
const CUT_MOST := 50
const CUT_TOP := 2.0            # m/s with CUT on: taking a layer off is a steady job
const HOLD_LIFT_MIN := -0.9     # CUT may reach further down (the machine riding on a heap)
const HOLD_LIFT_SPEED := 1.1

var lift := START_LIFT
var lift_cmd := 0.0
var push_load := 0.0            # loose dirt banked against the blade (blocks: 125 mm over a column)
var moved := 0                  # (tests: mm it's moved)
var cut_on := false
var cut_cm := 20
var edge_gap := 0.0             # m from the edge down to the ground under it (negative: in it)
var _steady := 0.0
var _edge_avg := NAN
var _keys_was := {}
var cut_rate := 0.0             # firm blocks a second it's cutting (smoothed)
var _jam_t := 0.0               # (a moment since the blade was too full to take more)
var _look: Node3D
var _pivot: MeshInstance3D
var _tracks: DsTrackRig
var _was := Vector3.INF

func _init() -> void:
	kind = "bulldozer"
	length = 4.0
	width = 2.9
	max_speed = 3.2
	accel = 1.4
	turn_rate = 0.8
	max_climb = deg_to_rad(30.0)
	step_up = 0.4
	wall_look = 0.6
	seat = Vector3(0, 1.15, 0.8)
	pipe = Vector3(0.38, 2.8, -1.0)     # (the stack's top: DsProps.bulldozer's (1.0, 2.75, 0.38), turned as _look turns it)

func _build() -> void:
	super()
	(_body.get_child(0) as CollisionShape3D).position.y = 0.7
	_look = Node3D.new()
	_look.rotation.y = PI * 0.5
	add_child(_look)
	var frame := DsKit.new()
	DsProps.track_frames(frame, 1.15, 0.3, 1.8, 2.3, 1.95, false)
	_mesh(_look, frame)
	var body := DsKit.new()
	DsProps.bulldozer(body, false)
	_mesh(_look, body)
	var bk := DsKit.new()
	DsProps.dozer_blade(bk, false)
	_pivot = _mesh(_look, bk)
	_tracks = DsTrackRig.new()
	_look.add_child(_tracks)
	_tracks.setup(DsExcavator.mat(), DsProps.track_path(1.8, 2.33, 1.97), 1.15, 0.62, 1.47, DsProps.dozer_wheels())

func _mesh(parent: Node3D, kit: DsKit) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = DsExcavator.mat()
	parent.add_child(m)
	return m

func _pose_tool() -> void:
	if _pivot == null:
		return
	_pivot.transform = _blade_pose(lift + _steady)

func _blade_pose(l: float) -> Transform3D:
	var swing := asin(clampf(l / (EDGE_X - ARM_PIVOT.x), -0.9, 0.9))
	var turn := Basis(Vector3.BACK, swing)
	return Transform3D(turn, ARM_PIVOT - turn * ARM_PIVOT)

## The edge's middle in the world with the blade at l
func _edge_at(l: float) -> Vector3:
	return _look.global_transform * (_blade_pose(l) * Vector3(EDGE_X, 0.0, 0.0))

## The blade's cutting edge, its two ends, in the world
func edge_ends() -> Array:
	var t := _look.global_transform * _pivot.transform
	return [t * Vector3(EDGE_X, 0.0, -HALF_WIDTH), t * Vector3(EDGE_X, 0.0, HALF_WIDTH)]

func edge() -> Vector3:
	var e: Array = edge_ends()
	return ((e[0] as Vector3) + (e[1] as Vector3)) * 0.5

## The blade's steel as a box (world, half sizes), for DsClods to keep lumps out of (the blade's profile: x 2.68 to 3.08
## forward, up to 1.75, 2.15 each side, in its pivot's frame)
func keepout_boxes() -> Array:
	if _pivot == null:
		return []
	return [[_pivot.global_transform * Transform3D(Basis.IDENTITY, Vector3(2.88, 0.86, 0.0)), Vector3(0.26, 0.92, 2.2)]]

func read_input() -> void:
	super()
	lift_cmd = float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))
	if _pressed(KEY_Q):
		set_cut(not cut_on)
	if _pressed(KEY_T):
		cut_cm = clampi(cut_cm + CUT_STEP, CUT_STEP, CUT_MOST)
	if _pressed(KEY_G):
		cut_cm = clampi(cut_cm - CUT_STEP, CUT_STEP, CUT_MOST)

func _pressed(k: Key) -> bool:
	var on := Input.is_physical_key_pressed(k)
	var was: bool = _keys_was.get(k, false)
	_keys_was[k] = on
	return on and not was

func set_cut(on: bool) -> void:
	cut_on = on

func stop_cmds() -> void:
	super()
	lift_cmd = 0.0

func keys() -> String:
	return "W/S drive   A/D turn   R/F blade up/down (lower it into the ground to cut, push the heap)\nQ CUT: hold the blade under where the ground began (T/G deeper/shallower)   V view   wheel zoom   E get off"

func status() -> String:
	var word := ("CUT %d cm" % cut_cm) if cut_on else ("Blade %+.2f m" % edge_gap)
	if push_load > 0:
		word += "   pushing %.1f t" % (push_load * 0.0031)
	return word + ("   " + blocked if blocked != "" else "")

func _drive(dt: float) -> void:
	# the push_load pushes back: slower with more banked against the blade
	var k := 1.0 - 0.85 * pow(clampf(float(push_load) / BOG, 0.0, 1.0), 1.3) * (0.6 if cut_on else 1.0)
	k *= clampf(1.0 - cut_rate / CUT_BOG, 0.3, 1.0)
	var top := max_speed
	max_speed = minf(top, CUT_TOP if cut_on else top) * k
	super(dt)
	max_speed = top

func _tool(dt: float) -> void:
	_jam_t = maxf(_jam_t - dt, 0.0)
	if _jam_t > 0.0 and blocked.begins_with("Too steep"):
		blocked = "The blade's full: back up, or raise it"     # (what's really stopping it)
	if cut_on and lift_cmd > 0.05:
		set_cut(false)
	if cut_on:
		_hold_cut(dt)
	else:
		lift = clampf(lift + lift_cmd * LIFT_SPEED * dt, LIFT_MIN, LIFT_MAX)
	_steady_blade(dt)
	_pose_tool()
	_tracks.update(speed + steer * 0.8, speed - steer * 0.8, dt)
	var tr: DsTerrain = site.terrain
	var e: Array = edge_ends()
	var a: Vector3 = e[0]
	var b: Vector3 = e[1]
	var mid := (a + b) * 0.5
	edge_gap = mid.y - ground_y(mid.x, mid.z)
	var f := forward()
	# working only going forward (or trying to): a parked blade doesn't dig, and it moves only what it sweeps through
	if speed > 0.02 or (throttle > 0.05 and speed > -0.05):
		var share := clampf(maxf(speed, 0.0) * dt / SWEEP_DEPTH, 0.0, 1.0)
		var r: Dictionary = tr.blade(a, b, f, 2, MOUTH, FIRM, HARDEST, 0, HEAP, share)
		moved += int(r.moved)
		_jam(int(r.jammed), int(r.moved))
		# (from the blade back to the tracks nothing's left standing above the edge, or above where the tracks ride
		# if that's higher: the blade's swept through all of it. So a step it cut before the machine dipped, or
		# dirt that's tumbled over the blade's top, can't stop it or lift it; it goes in front of the blade)
		var base := (global_transform * Vector3(0, 0, -length * 0.5)).y
		var rows := ceili((EDGE_X - length * 0.5) / 0.22) + 1
		var r2: Dictionary = tr.blade(Vector3(a.x, maxf(a.y, base), a.z), Vector3(b.x, maxf(b.y, base), b.z), f, rows, MOUTH, 999, HARDEST, 0, HEAP, 1.0)
		moved += int(r2.moved)
		if int(r2.jammed) > 0:
			# (what's between the blade and the tracks couldn't be cleared: the heap in front has no more room. It
			# stops dead rather than creeping on with the ground standing up through the blade: the owner, 9 Nov)
			_jam_t = 1.0
			speed = minf(speed, 0.0)
			blocked = "The blade's full: back up, or raise it"
		cut_rate = lerpf(cut_rate, float(r.cut) / DsTerrain.MM / maxf(dt, 0.001), minf(1.0, dt * 4.0))
		if bool(r.rock) and int(r.moved) == 0 and throttle > 0.05:
			speed = minf(speed, 0.0)
			blocked = "Rock: the blade won't cut it (dynamite, or the excavator)"
	else:
		cut_rate = lerpf(cut_rate, 0.0, minf(1.0, dt * 4.0))
	push_load = tr.load_ahead(a, b, f, HEAP + 0.3)
	# (the blade's a wall, and its push arms and the gap back to the tracks closed: the heap can't slump back through)
	# (and up to the sky: a heap grown over the blade's top used to come to rest on top of the blocked cells, a shelf
	# floating over the blade and the bonnet; now what spills over slides off ahead or to the sides)
	tr.block(id, a + f * LIP, b + f * LIP, f, EDGE_X - length * 0.5 + 0.15 + LIP, MOUTH + 6.0)

## What it couldn't move (no room left in front: the heap's as high as it'll go) holds it back, so the blade doesn't
## pass through what it can't shift: it stalls against a full blade
func _jam(jammed: int, did: int) -> void:
	if jammed <= 0:
		return
	_jam_t = 1.0
	var k := clampf(float(jammed) / float(jammed + did + 1), 0.0, 1.0)
	speed = minf(speed, max_speed * (1.0 - k))
	if k > 0.6:
		blocked = "The blade's full: back up, or raise it"

## CUT: the edge held cut_cm under where the ground began, read across the blade just behind it
func _hold_cut(dt: float) -> void:
	var f := forward()
	var ahead := global_position + f * (EDGE_X + CUT_READ)
	var side := right() * HALF_WIDTH * 0.8
	var tr: DsTerrain = site.terrain
	var began := (tr.start_at(ahead.x, ahead.z) + tr.start_at(ahead.x + side.x, ahead.z + side.z) + tr.start_at(ahead.x - side.x, ahead.z - side.z)) / 3.0
	var want := began - cut_cm * 0.01
	var err := want - _edge_at(lift + _steady).y
	lift = clampf(lift + clampf(err * 8.0, -1.0, 1.0) * HOLD_LIFT_SPEED * dt, HOLD_LIFT_MIN, LIFT_MAX)

## Why a blade left to itself makes waves: it's far ahead of the tracks, so it lifts more than the tracks climb. It
## cuts a dip, the machine drives down into it, the blade digs deeper still, and round it goes. So while it's working
## it keeps to the height it's been averaging over the last few metres, the machine pitching under it.
func _steady_blade(dt: float) -> void:
	var raw := _edge_at(lift).y
	if is_nan(_edge_avg):
		_edge_avg = raw
	var working := not cut_on and lift_cmd == 0.0 and edge_gap < 0.25
	if not working:
		_edge_avg = raw
		_steady = move_toward(_steady, 0.0, 1.5 * dt)
		return
	_edge_avg = lerpf(_edge_avg, raw, minf(absf(speed) * dt / STEADY_OVER, 1.0))
	# (never lifted much past the tracks' bottoms, or it leaves a step of firm ground the tracks can't climb)
	_steady = clampf((_edge_avg - raw) * STEADY_SHARE, -STEADY_MOST, minf(STEADY_MOST, maxf(-lift, 0.0) + 0.1))

func _follow(dt: float) -> void:
	super(dt)
	_tracks.update(speed, speed, dt)

var _moved_was := 0
var _tumble: CPUParticles3D

# (the digger game's _update_blade_fx) while it's pushing dirt: dust and flying lumps at the blade, and lumps tumbling
# down the front of the heap, more of them the more it's carrying
func _dust_fx() -> void:
	super()
	var pushing: bool = speed > 0.15 and (moved != _moved_was or (not runs() and push_load > 20.0))
	_moved_was = moved
	var e: Array = edge_ends()
	var mid: Vector3 = ((e[0] as Vector3) + (e[1] as Vector3)) * 0.5
	work_fx(Vector3(mid.x, ground_y(mid.x, mid.z) + 0.25, mid.z), HALF_WIDTH * 0.93, pushing)
	if _tumble == null:
		_tumble = DsMachine.chunks(40)
		_tumble.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_tumble.emission_box_extents = Vector3(HALF_WIDTH * 0.88, 0.1, 0.15)
		_tumble.direction = Vector3(0.0, 0.15, -1.0)
		_tumble.spread = 16.0
		_tumble.initial_velocity_min = 0.7
		_tumble.initial_velocity_max = 1.6
		_tumble.gravity = Vector3(0.0, -7.0, 0.0)
		_tumble.lifetime = 0.7
		_tumble.scale_amount_min = 0.25
		_tumble.scale_amount_max = 0.7
		_tumble.angular_velocity_min = -420.0
		_tumble.angular_velocity_max = 420.0
		add_child(_tumble)
	var tonnes := push_load * 0.0031
	var top := mid + forward() * 0.45
	_tumble.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(top.x, ground_y(top.x, top.z) + 0.2, top.z))
	_tumble.emitting = pushing and tonnes > 0.6
	_tumble.scale_amount_max = lerpf(0.45, 0.9, clampf(tonnes / 10.0, 0.0, 1.0))

func net_more() -> PackedFloat32Array:
	return PackedFloat32Array([lift, float(push_load), _steady, edge_gap, float(cut_on), float(cut_cm)])

func net_take_more(f: PackedFloat32Array) -> void:
	if f.size() >= 6:
		lift = lerpf(lift, f[0], 0.5)
		push_load = f[1]
		_steady = lerpf(_steady, f[2], 0.5)
		edge_gap = f[3]
		if site.machines.driving != self:       # (the driver's own toggles stand: the host's echo lags)
			cut_on = f[4] > 0.5
			cut_cm = int(f[5])

func _cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([lift_cmd, float(cut_on), float(cut_cm)])

func _take_cmds_more(f: PackedFloat32Array) -> void:
	if f.size() >= 3:
		lift_cmd = clampf(f[0], -1.0, 1.0)
		cut_on = f[1] > 0.5
		cut_cm = clampi(int(f[2]), CUT_STEP, CUT_MOST)
