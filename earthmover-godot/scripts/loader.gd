class_name Loader
extends Machine
## The small machines that carry a bucket on two arms: the Bobcat and the Dingo. Drive at the dirt with the bucket low and it fills,
## lift it and tip it out, on the ground or into a truck. A full bucket with its edge down just pushes, like a tiny dozer. The
## Dingo can swap its bucket for a trencher. Every number here is a first guess, to tune by feel.

const BOBCAT := "Bobcat"
const DINGO := "Dingo"
const LIFT_RATE := 0.75         # rad a second, the arms
const CURL_RATE := 1.3
const ARM_EASE := 5.0
const POUR_FROM := -0.05        # radians, the bucket tipped forward: it starts to pour
const POUR_ALL := -0.7          # and by here none of it stays
const CURL_MIN := -0.95
const CURL_MAX := 0.75
const FRICTION := 0.22          # how hard soil drags, per its weight: less than a dozer's, as most of it's going in the bucket
const SWEEP := 0.25             # m the edge travels to clear what's in front of it
const CHUNK := 240              # mm a falling chunk carries (0.015 m3)
# The Dingo's trencher. The Bobcat's big one (owner, 9 Nov) has its own numbers, set in setup().
const CHAIN_MOST := 1.5         # m below the tracks
const CHAIN_RATE := 0.9         # m a second, lowering or raising it
const CHAIN_X := 0.72           # how far ahead of the middle it cuts
const CHAIN_SPEED := 0.6        # m/s: as fast as the machine crawls with it in the ground
const CHAIN_CUT := 42           # mm off a cell in a tick
const CHAIN_HALF := 0.125       # m either side of the middle: two cells of the dirt grid
const THROW_NEAR := 0.95        # m to the right the soil lands, at least, and more for a deep cut: there's more of it to clear the slot
const THROW_FAR := 1.5
const THROW_DEEP := 0.25        # m further out for each m of depth
const PIPE_EVERY := 0.5         # m of ground between each length laid
const PIPE_SPEED := 0.8         # m/s, laying
const PIPE_AT := -0.75          # how far ahead of the middle it lays: behind the machine
const GRADE_FALL := 0.03        # m the floor drops for each m nearer the drain, with GRADE on
const PLAN_NEAR := 1.5         # m: this near a job's planned trench line, the trencher shows its aim
const TOO_DEEP := 0.1          # m under the aim that says to come up: a deep dip and back up again is a rise the water stops at
const DEPTH_STOP := 0.02       # m past the aim the chain can go, by hand, on a job
const GRADE_START := 0.45       # m the chain goes down to before GRADE takes the floor from there
const PIPE_SNAP := 0.6          # m either side of the layer it looks for the bottom of the trench
const TRENCH_LOW := 0.2         # m below the ground either side, for pipe to go down
const ROCK_SCRAPE_MM := 90      # how far below rock the edge can be pressed before it stops the machine dead
const SPREAD_MM := 50           # what backing up with the bucket low leaves behind
const RAKE_REACH := 10          # cells, 2.5 m: how far round a spreading bucket rakes leftover soil into a low trench
const REACH_BELOW := 0.03       # m: spreading, the edge reaches no lower than this below the firm ground under the bucket
const DRAG_LOW := 0.22          # m above the firm ground the edge has to be to spread
const SPREAD_CURL := 0.15        # where the SPREAD button holds the bucket: flat, edge just off the ground
const POUR_WIDTH := 0.5          # how much of the bucket's width a load comes out of: the middle, so it lands in a heap
# The Bobcat's big trencher, for 40 cm pipe: a slot half as wide again as the Dingo's (three cells of the dirt grid to its two),
# down to 2 m, the chain on the arms' ends.
const BIG_CHAIN_MOST := 2.0
const BIG_CHAIN_X := 1.45       # where it cuts, ahead of the middle: out past the front wheels
const BIG_CHAIN_LEN := 2.6
const BIG_MOUNT_ARM := -0.55    # the arms hold the chain's head down at the front

var kind := BOBCAT
var lift_cmd := 0.0
var curl_cmd := 0.0

var arm := 0.0                  # radians from level
var curl := 0.25                # the bucket floor against the machine: up holds, down pours
var bucket_mm := 0
var bucket_dust := 0            # how much of what's in the bucket is cracker dust
var spreading := false          # moving soil out flat
## GRADE, the trencher's laser level: it sets the chain's depth itself so the trench floor falls steadily towards `grade_toward`
## (a job's drain), from wherever the cut began. The aim is worked out with it off too, and shown, as the depth to dig to.
var grade_on := false
var grade_toward := Vector2.INF
var plan := {}                  # a job's planned trench floor (Mission.trench_plan): the aim, the same wherever and however it's dug
var at_stop := false            # the chain's down on the depth stop
var aim_depth := -1.0
var grade_short := false
var _grade_from := Vector2.INF
var _grade_floor0 := 0.0
var spread_on := false          # the SPREAD button: the bucket floats on the ground and lays out what it meets, going either way
var trencher_on := false
var chain_depth := 0.0          # m, with the trencher on: 0 is carried clear
## m the trench floor rises (+) or falls (-) per m, measured along the last half metre cut. Less than -1 until known.
var floor_trend := -9.0
var _floor_mark := Vector3.INF
var trench_m := 0.0             # m of trench cut, for the readout and tests
var pipe_on := false
var pipes: Pipes                # where pipe it lays goes
var in_trench := false          # the pipe layer is over a trench
## The trencher this one has: the Dingo's, or the Bobcat's big one.
var chain_most := CHAIN_MOST
var chain_x := CHAIN_X
var chain_cuts: Array[float] = [-CHAIN_HALF, CHAIN_HALF]   # m either side of the middle it cuts at, a cell apart: the slot's width
var chain_beside := 0.65        # m out from the middle that the ground either side is looked for, clear of the slot
var chain_cut := CHAIN_CUT
var chain_speed := CHAIN_SPEED
var throw_near := THROW_NEAR
var throw_far := THROW_FAR
var pipe_beside := 0.45         # m out from the pipe layer that the ground either side of a trench is looked for

var pivot := Vector2.ZERO
var arm_len := 1.0
var arm_low := 0.0
var arm_high := 1.0
var bucket_len := 0.5
var bucket_half := 0.5
var bucket_high := 0.5
var mouth_mm := 500             # how much above the edge it can bite off at once
var capacity := 8000
var firm_rate := 4
var dig_drag := 3.0             # N for each mm taken in a tick
var pour_rate := 8000

var _arms: MeshInstance3D
var _bucket: MeshInstance3D
var _lump: MeshInstance3D
var _chain: MeshInstance3D
var _spool: MeshInstance3D
var _body: Node3D
var _driver: MeshInstance3D       # the Dingo's driver standing on the back, gone when he's stepped off
var _v_lift := 0.0
var _v_curl := 0.0
var _edge_was := Vector3.ZERO
var _pour_store := 0
var _pour_dust := 0
var _full_back := 1.7
var _full_top := 1.7
var _mat: Material
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _was_clear := true
var _cut_was := Vector3.ZERO

func setup(s: DirtSim, v: GroundView, mat: Material, at: Vector2, dir: Vector2, which: String) -> void:
	sim = s
	view = v
	spot = at
	angle = atan2(-dir.y, dir.x)
	kind = which
	machine_name = which
	_mat = mat
	_rng.seed = 51
	stuck_word = "TOO MUCH: back up and raise the bucket"
	_body = Node3D.new()
	add_child(_body)
	var kit := MeshKit.new()
	if which == BOBCAT:
		hint = "Bucket low, drive into the dirt, then RAISE and DUMP. SPREAD flattens a heap. ATTACH for the big trencher, then pipe. Tap again for the next machine"
		mass = 3600.0
		top_speed = 3.4
		back_speed = 3.0
		turn_rate = 1.7
		support_x = 0.62
		support_z = 0.8
		track_z = 0.8
		track_rear = 0.6
		rut_half = 0.16
		rut_mm = 20
		pivot = Vector2(-0.82, 1.62)
		arm_len = 2.3
		arm_low = -0.82
		arm_high = 1.0
		bucket_len = 0.72
		bucket_half = 0.92
		bucket_high = 0.62
		mouth_mm = 480
		capacity = 8000         # 0.5 m3
		firm_rate = 5
		pour_rate = 7000
		view_dist = 9.0
		view_aim = 1.0
		view_pitch = 21.0
		eye = Vector3(0.1, 1.7, 0.0)
		pipe = Vector3(-1.05, 1.55, 0.35)
		fp_back = 1.1
		fp_front = 1.5
		fp_r = 0.95
		body_reach = 1.3
		Props.bobcat_body(kit)
		_add_mesh(_body, kit, mat)
		var w := MeshKit.new()
		Props.wheel(w, 0.32)
		var tyre := w.mesh()
		for side: float in [-1.0, 1.0]:
			for x: float in [-0.62, 0.62]:
				_add_wheel(tyre, mat, Vector3(x, 0.38, side * 0.84), 0.38)
		chain_most = BIG_CHAIN_MOST
		chain_x = BIG_CHAIN_X
		chain_cuts = [-0.25, 0.0, 0.25]
		chain_beside = 0.9
		chain_cut = 60
		# A touch quicker than the Dingo's, so 40 m of street isn't a long crawl.
		chain_speed = 0.75
		# Thrown clear of the right-hand wheels.
		throw_near = 1.3
		throw_far = 2.0
		pipe_beside = 0.65
		kit = MeshKit.new()
		Props.trencher(kit, BIG_CHAIN_LEN, 2.2)
		_chain = _add_mesh(_body, kit, mat)
		_chain.visible = false
		kit = MeshKit.new()
		Props.pipe_spool(kit)
		_spool = _add_mesh(_body, kit, mat)
		_spool.visible = false
		_spool.scale = Vector3.ONE * 1.6
		_spool.position = Vector3(0.3, -0.45, 0.0)
	else:
		hint = "Tap SPREAD and drive over a heap to flatten it. Tap ATTACH for the trencher: LOWER it and drive. Tap again for pipe: drive along the trench"
		mass = 1400.0
		top_speed = 1.7
		back_speed = 1.7
		turn_rate = 1.25
		support_x = 0.55
		support_z = 0.52
		side_lean_most = 0.14
		track_z = 0.44
		track_rear = 0.55
		rut_half = 0.115
		rut_mm = 10
		pivot = Vector2(-0.1, 0.85)
		arm_len = 1.15
		arm_low = -0.85
		arm_high = 0.95
		bucket_len = 0.42
		bucket_half = 0.5
		bucket_high = 0.36
		mouth_mm = 260
		capacity = 1920         # 0.12 m3
		firm_rate = 2
		pour_rate = 2200
		view_dist = 6.0
		view_side = 0.5
		view_aim = 0.7
		view_pitch = 22.0
		eye = Vector3(-0.8, 1.55, 0.0)
		pipe = Vector3(-0.35, 1.05, 0.2)
		fp_back = 1.2
		fp_front = 0.95
		fp_r = 0.6
		body_reach = 0.8
		Props.dingo_body(kit)
		_add_mesh(_body, kit, mat)
		var man := MeshKit.new()
		Props.dingo_driver(man)
		_driver = _add_mesh(_body, man, mat)
		var frames := MeshKit.new()
		Props.track_frames(frames, 0.44, 0.1, 0.56, 0.72, 0.6)
		var frame := _add_mesh(self, frames, mat)
		frame.scale = Vector3(1.0, 0.42, 1.0)
		tracks = TrackRig.new()
		tracks.scale = Vector3(1.0, 0.42, 1.0)
		add_child(tracks)
		var wheel_list: Array[Vector3] = [Vector3(-0.6, 0.5, 0.2), Vector3(0.6, 0.5, 0.2)]
		tracks.setup(mat, Props.track_path(0.56, 0.74, 0.62), 0.44, 0.23, 0.56, wheel_list, 0.14)
		kit = MeshKit.new()
		Props.trencher(kit, 1.15)
		_chain = _add_mesh(_body, kit, mat)
		_chain.visible = false
		kit = MeshKit.new()
		Props.pipe_spool(kit)
		_spool = _add_mesh(_body, kit, mat)
		_spool.visible = false
		_chain.position = Vector3(0.35, 0.72, 0.0)
	_speed_cap = top_speed
	_full_back = back_speed
	_full_top = top_speed
	arm = lerpf(arm_low, arm_high, 0.18)
	kit = MeshKit.new()
	Props.loader_arms(kit, arm_len, 0.84 if which == BOBCAT else 0.3, 0.16 if which == BOBCAT else 0.07)
	_arms = _add_mesh(_body, kit, mat)
	kit = MeshKit.new()
	Props.loader_bucket(kit, bucket_len, bucket_half, bucket_high)
	_bucket = _add_mesh(_body, kit, mat)
	kit = MeshKit.new()
	kit.prism([Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.28, 0.72), Vector2(-0.4, 1.0)], -0.5, 0.5, Props.DIRT)
	_lump = _add_mesh(_bucket, kit, mat)
	_lump.visible = false
	y_smooth = sim.track_height_at(spot)
	_settle(1.0)
	_pose()
	teeth = _edge_world()
	_edge_was = teeth
	blade_a = Vector2(teeth.x, teeth.z)
	blade_b = blade_a

## Starts it somewhere else, for a job.
func reposition(at: Vector2, dir: Vector2) -> void:
	spot = at
	angle = atan2(-dir.y, dir.x)
	y_smooth = sim.track_height_at(spot)
	_settle(1.0)
	_pose()
	teeth = _edge_world()
	_edge_was = teeth

func show_driver(on: bool) -> void:
	if _driver:
		_driver.visible = on

func _add_mesh(parent: Node3D, kit: MeshKit, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = mat
	parent.add_child(m)
	return m

func stop_commands() -> void:
	super()
	lift_cmd = 0.0
	curl_cmd = 0.0

func fill() -> float:
	return float(bucket_mm) / capacity

## Where the trench floor ought to be at `p` for the pipe to run downhill from where this cut began, or NAN with no cut begun.
func aim_floor(p: Vector2) -> float:
	if not plan.is_empty():
		var d := clampf((p - (plan["from"] as Vector2)).dot(plan["way"]), 0.0, plan["length"])
		return float(plan["y0"]) - float(plan.get("fall", GRADE_FALL)) * d
	if _grade_from == Vector2.INF:
		return NAN
	var nearer := grade_toward.distance_to(_grade_from) - grade_toward.distance_to(p) if grade_toward != Vector2.INF else _grade_from.distance_to(p)
	return _grade_floor0 - GRADE_FALL * nearer

## Where this cut began, or INF with none begun.
func aim_from() -> Vector2:
	return plan["from"] if not plan.is_empty() else _grade_from

func gauge_word() -> Array:
	if trencher_on:
		if on_rock:
			return ["ROCK: CAN'T CUT", Color("#ff9a4a")]
		if grade_on and grade_short:
			return ["GRADE: TOO DEEP FOR THE TRENCHER", Color("#ff6a4a")]
		if grade_on:
			return ["GRADE ON   TRENCH %.2f m DEEP" % chain_depth, Color("#7ee06a")]
		if chain_depth > 0.02 and aim_depth > 0.0:
			# How deep it ought to be here for the pipe to run downhill, and whether it is.
			var short := chain_depth < aim_depth - 0.04
			var deep := chain_depth > aim_depth + TOO_DEEP
			return ["TRENCH %.2f m DEEP   AIM %.2f m%s" % [chain_depth, aim_depth, "   GO DEEPER" if short else ("   TOO DEEP" if deep else "")], Color("#ff6a4a") if short else (Color("#ffd23f") if deep else Color("#ff9a4a"))]
		if chain_depth > 0.02:
			# Which way the floor's going, for a pipe that has to run downhill.
			var way := ""
			if floor_trend < -0.01:
				way = "   FLOOR GOING DOWN"
			elif floor_trend > 0.01:
				way = "   FLOOR GOING UP"
			elif floor_trend > -1.0:
				way = "   FLOOR LEVEL"
			return ["TRENCH %.2f m DEEP%s" % [chain_depth, way], Color("#ff9a4a")]
		return ["TRENCHER UP: LOWER IT", Color("#a8f07a")]
	if pipe_on:
		var laid := pipes.length_m if pipes else 0.0
		if not in_trench:
			return ["PIPE %.1f m   DRIVE ALONG A TRENCH" % laid, Color("#a8f07a")]
		return ["LAYING PIPE %.1f m" % laid, Color("#ff9a4a")]
	var word := "BUCKET %.2f m3" % DirtSim.to_m3(bucket_mm)
	var deep := sim.height_at(Vector2(teeth.x, teeth.z)) - teeth.y
	if spreading:
		return [word + "   SPREADING", Color("#ff9a4a")]
	if spread_on:
		return [word + "   SPREAD ON: DRIVE OVER IT", Color("#ffd23f")]
	if deep > 0.03:
		return [word + "   IN DIRT", Color("#ff9a4a")]
	if bucket_low():
		return [word + "   LOW: BACK UP TO SPREAD", Color("#ffd23f")]
	return [word, Color("#a8f07a")]

## Goes round the attachments: bucket, trencher, pipe layer. What's in the bucket gets tipped out first. The Bobcat's are the big
## ones, held on its arms.
func toggle_attachment() -> void:
	if not trencher_on and not pipe_on:
		trencher_on = true
		curl = CURL_MIN
		_pour_all_now()
		if kind == BOBCAT:
			arm = BIG_MOUNT_ARM
	elif trencher_on:
		trencher_on = false
		pipe_on = true
	else:
		pipe_on = false
		curl = 0.25
	chain_depth = 0.0
	on_rock = false
	in_trench = false
	digging = false
	top_speed = _full_top
	back_speed = _full_back
	spreading = false
	spread_on = false
	grade_on = false
	_show_attachment()
	_pose()
	hit_end = 0.6

func _show_attachment() -> void:
	_chain.visible = trencher_on
	_spool.visible = pipe_on
	var has_bucket := not trencher_on and not pipe_on
	# The Dingo's go on in place of its arms; the Bobcat's on the end of them.
	_arms.visible = has_bucket or kind == BOBCAT
	_bucket.visible = has_bucket

## The SPREAD button. RAISE, CURL or DUMP also turn it off.
func toggle_spread() -> void:
	if pipe_on:
		return
	# With the trencher on, the same button is GRADE.
	if trencher_on:
		grade_on = not grade_on
		_grade_from = Vector2.INF
		hit_end = 0.3
		return
	spread_on = not spread_on
	hit_end = 0.3

func _pour_all_now() -> void:
	var at := DirtSim.cell_of(spot + forward() * 1.0)
	sim.held -= bucket_mm + _pour_store
	sim.put(at.x, at.y, bucket_mm + _pour_store, bucket_dust + _pour_dust)
	bucket_mm = 0
	bucket_dust = 0
	_pour_store = 0
	_pour_dust = 0

## The Dingo's tracks are long for its size and bridge a slot: each corner rests on the highest ground along that stretch of track.
func _ground_at(local_x: float, local_z: float) -> float:
	if kind != DINGO:
		return super(local_x, local_z)
	var most := super(local_x, local_z)
	most = maxf(most, super(local_x * 0.4, local_z))
	return maxf(most, super(local_x * 0.4, local_z * 1.2))

func _pin() -> Vector2:
	return pivot + Vector2(cos(arm), sin(arm)) * arm_len

func _edge_local() -> Vector3:
	var p := _pin()
	return Vector3(p.x + cos(curl) * bucket_len, p.y + sin(curl) * bucket_len, 0.0)

func _edge_world() -> Vector3:
	return transform * _edge_local()

func _pose() -> void:
	var p := _pin()
	_arms.transform = Transform3D(Basis(Vector3.BACK, arm), Vector3(pivot.x, pivot.y, 0.0))
	_bucket.transform = Transform3D(Basis(Vector3.BACK, curl), Vector3(p.x, p.y, 0.0))
	if _chain:
		# Slanted down and forward: the lower it's set, the steeper it digs.
		var slant := lerpf(0.15, -1.15, clampf(chain_depth / 0.5, 0.0, 1.0))
		_chain.rotation.z = slant
		if kind == BOBCAT:
			_chain.position = Vector3(p.x, p.y, 0.0)
	var f := fill()
	_lump.visible = f > 0.03
	if _lump.visible:
		_lump.material_override = Props.dust_mat() if bucket_dust * 2 > bucket_mm else _mat
		var up := bucket_high * (0.35 + 0.95 * f)
		var along := bucket_len * (0.5 + 0.45 * minf(f * 1.4, 1.0))
		_lump.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(along, up, bucket_half * 1.9)), Vector3(along * 0.5 + 0.04, 0.02, 0.0))

func step(dt: float) -> void:
	_clock += dt
	hit_end = 0.0
	moved_tick = 0
	digging = false
	if trencher_on:
		_work_chain(dt)
	elif pipe_on:
		_work_pipe()
	else:
		_work_bucket(dt)
	_rock_it(dt)
	var share := 1.0 - clampf(bog * 0.5, 0.0, 0.5)
	# With the chain down it can only be eased round, as the slot it's in holds it to a line.
	if trencher_on and chain_depth > 0.02:
		share = 0.3
	_drive(dt, _drag(), false, share)
	# Eased onto the ground, so lumps and clods rock it rather than jolt it.
	_settle(minf(dt * (7.0 if kind == DINGO else 12.0), 1.0))

var _dig_force := 0.0

func _drag() -> float:
	return _dig_force

func _work_bucket(dt: float) -> void:
	if spread_on and (lift_cmd > 0.05 or absf(curl_cmd) > 0.05):
		spread_on = false
	var want_lift := -1.0 if spread_on else lift_cmd
	var want_curl := clampf((SPREAD_CURL - curl) * 6.0, -1.0, 1.0) if spread_on else curl_cmd
	_v_lift = move_toward(_v_lift, want_lift, ARM_EASE * dt)
	_v_curl = move_toward(_v_curl, want_curl, ARM_EASE * 1.4 * dt)
	var was_arm := arm
	var was_curl := curl
	arm = clampf(arm + _v_lift * LIFT_RATE * dt, arm_low, arm_high)
	curl = clampf(curl + _v_curl * CURL_RATE * dt, CURL_MIN, CURL_MAX)
	if (arm >= arm_high and was_arm < arm_high) or (curl <= CURL_MIN and was_curl > CURL_MIN) or (curl >= CURL_MAX and was_curl < CURL_MAX):
		hit_end = 0.5
	if arm <= arm_low and was_arm > arm_low:
		hit_end = 0.8
	hyd = clampf(maxf(absf(_v_lift), absf(_v_curl)), 0.0, 1.0)
	_pose()
	var now := _edge_world()
	_cut(_edge_was, now)
	_edge_was = now
	teeth = now
	_pour(dt)
	var side := transform.basis * Vector3.BACK * bucket_half
	blade_a = Vector2(now.x - side.x, now.z - side.z)
	blade_b = Vector2(now.x + side.x, now.z + side.z)
	_back_drag(dt)
	load_t = DirtSim.to_m3(bucket_mm) * 1.5

## What the edge cuts going from p0 to p1. Only forward or curling up through the soil: going backwards it just drags over.
func _cut(p0: Vector3, p1: Vector3) -> void:
	# Spreading it floats over what it's laying out, and nothing goes in the bucket.
	if spread_on:
		on_rock = false
		_dig_force = 0.0
		bog = lerpf(bog, 0.0, 0.15)
		return
	var f := forward()
	var path := Vector2(p1.x - p0.x, p1.z - p0.z)
	var going := path.dot(f)
	var curling := _v_curl > 0.05
	on_rock = false
	_dig_force = 0.0
	var worked := 0.0
	var side3 := transform.basis * Vector3.BACK
	var side := Vector2(side3.x, side3.z).normalized()
	var mid := Vector2(p1.x, p1.z)
	var a := mid - side * bucket_half
	var b := mid + side * bucket_half
	var edge_mm := int(p1.y * 1000.0)
	var in_soil := sim.height_at(mid) > p1.y
	# Rock under the edge stops it dead.
	var at_mid := DirtSim.cell_of(mid)
	var n_mid := clampi(at_mid.y, 0, DirtSim.CELLS - 1) * DirtSim.CELLS + clampi(at_mid.x, 0, DirtSim.CELLS - 1)
	# But a bucket held just on it only scrapes along, or lowering it on a sealed road would stop the machine.
	if sim.rock[n_mid] != 0 and sim.bed[n_mid] > edge_mm + ROCK_SCRAPE_MM:
		on_rock = true
	if in_soil and (going > 0.0003 or curling):
		digging = true
		var room := capacity - bucket_mm
		if room > 0:
			var dist := path.length()
			var share := clampf(dist / SWEEP, 0.0, 1.0)
			var steps := int(a.distance_to(b) / (DirtSim.CELL_M * 0.75)) + 1
			for s in steps + 1:
				var p := a.lerp(b, float(s) / steps)
				var at := DirtSim.cell_of(p)
				if at.x < 1 or at.y < 1 or at.x >= DirtSim.CELLS - 1 or at.y >= DirtSim.CELLS - 1:
					continue
				var n := at.y * DirtSim.CELLS + at.x
				var high := sim.bed[n] + sim.soil[n] - edge_mm
				if high <= 0 or room <= 0:
					continue
				var r: Array = sim.bite(at.x, at.y, mini(ceili(mini(high, mouth_mm) * share), room), firm_rate)
				room -= r[0]
				bucket_mm += r[0]
				bucket_dust += r[2]
				moved_tick += r[0]
				worked += r[0] + r[1] * 10.0
		else:
			# Full, with its edge down, it can only push what's in front of it along.
			var pushed: Array = sim.blade(a, b, f, edge_mm, firm_rate, clampf(maxf(speed, 0.0) * 1.0 / 60.0 / SWEEP, 0.0, 1.0))
			moved_tick += pushed[0]
			worked += pushed[0] * 0.2 + pushed[1] * 8.0
			on_rock = on_rock or pushed[2]
	if in_soil:
		_dig_force = sim.load_ahead(a, b, f, edge_mm) * 1000.0 * 9.8 * FRICTION + worked * dig_drag
	moved_m3 += DirtSim.to_m3(moved_tick)
	bog = lerpf(bog, clampf(worked / 500.0, 0.0, 1.0), 0.15)

## Whether the edge is down near the firm ground, where backing up spreads what's on it.
func bucket_low() -> bool:
	return teeth.y - sim.firm_at(Vector2(teeth.x, teeth.z)) < DRAG_LOW

## Laying out what's on the ground at an even depth: with SPREAD on, driving either way once the bucket's down, or backing up with
## the bucket lowered by hand.
func _back_drag(dt: float) -> void:
	spreading = false
	back_speed = _full_back
	top_speed = _full_top
	var down := arm <= arm_low + 0.15
	var backing := speed < -0.03 and (down if spread_on else bucket_low())
	var pushing := speed > 0.03 and spread_on and down
	if not backing and not pushing:
		return
	# The bucket's floor is wider and longer than a trench: it rests on the highest firm ground under it, so it can't follow a slot down.
	var stands := -99.0
	var f := forward()
	for k in 5:
		var p := blade_a.lerp(blade_b, k / 4.0)
		for along: float in [-0.8, -0.4, 0.0, 0.4]:
			stands = maxf(stands, sim.firm_at(p + f * along))
	var moved := sim.drag(blade_a, blade_b, forward() * signf(speed), SPREAD_MM, clampf(absf(speed) * dt / 0.12, 0.0, 1.0), int((stands - REACH_BELOW) * 1000.0))
	# Over a trench that's still low after backfilling, it rakes the leftover soil round about in, so the trench can be finished flat.
	# Every cell across the bucket, so none of a wide trench is missed.
	var spans := maxi(int(ceil(bucket_half * 2.0 / DirtSim.CELL_M)), 4)
	for k in spans + 1:
		var at := DirtSim.cell_of(blade_a.lerp(blade_b, float(k) / spans) - f * 0.2)
		if at.x < 1 or at.y < 1 or at.x >= DirtSim.CELLS - 1 or at.y >= DirtSim.CELLS - 1:
			continue
		if sim.clean_cut[at.y * DirtSim.CELLS + at.x] == 1:
			moved += sim.rake_into(at.x, at.y, RAKE_REACH)
	if moved <= 0:
		return
	spreading = true
	digging = true
	moved_tick += moved
	moved_m3 += DirtSim.to_m3(moved)
	# The more it's shifting the slower it goes, but it never bogs right down: it's only a thin layer.
	var slowed := 1.0 - 0.5 * clampf(moved / 150.0, 0.0, 1.0)
	back_speed = _full_back * slowed
	top_speed = _full_top * slowed

## How much it can hold, tipped as it is.
func _holds() -> int:
	return int(capacity * clampf((curl - POUR_ALL) / (POUR_FROM - POUR_ALL), 0.0, 1.0))

func _pour(dt: float) -> void:
	var over := maxi(bucket_mm - _holds(), 0)
	var out := mini(over, ceili(pour_rate * dt))
	pouring = lerpf(pouring, clampf(float(out) / (pour_rate * dt), 0.0, 1.0), minf(dt * 10.0, 1.0))
	if out <= 0:
		return
	var out_dust := bucket_dust * out / bucket_mm
	bucket_mm -= out
	bucket_dust -= out_dust
	_pour_store += out
	_pour_dust += out_dust
	pour_spot = teeth
	var f := forward()
	var side3 := transform.basis * Vector3.BACK
	while _pour_store >= CHUNK or (bucket_mm == 0 and _pour_store > 0):
		var amt := mini(CHUNK, _pour_store)
		var chunk_dust := _pour_dust * amt / _pour_store
		_pour_store -= amt
		_pour_dust -= chunk_dust
		sim.held -= amt
		var at := teeth + side3 * _rng.randf_range(-bucket_half, bucket_half) * POUR_WIDTH
		sim.launch(at, Vector3(f.x * _rng.randf_range(0.1, 0.3) + f.x * speed, -0.4, f.y * _rng.randf_range(0.1, 0.3) + f.y * speed), amt, chunk_dust)

## The trencher: the chain goes down, the machine crawls, and the slot's cut in front of the tracks, between them.
func _work_chain(dt: float) -> void:
	var was := chain_depth
	# RAISE takes back control from GRADE; otherwise GRADE works the chain itself, below.
	if grade_on and lift_cmd > 0.05:
		grade_on = false
	if not grade_on:
		chain_depth = clampf(chain_depth - lift_cmd * CHAIN_RATE * dt, 0.0, chain_most)
	hyd = clampf(absf(chain_depth - was) / dt / CHAIN_RATE, 0.0, 1.0)
	if chain_depth >= chain_most and was < chain_most:
		hit_end = 0.5
	_pose()
	var f := forward()
	var side := Vector2(sin(angle), cos(angle))
	var here := spot + f * chain_x
	# Where the floor ought to be here, for a pipe that runs downhill: falling from where this cut began, nearer the drain.
	var beside := minf(sim.firm_at(here + side * chain_beside), sim.firm_at(here - side * chain_beside))
	if chain_depth <= 0.02 and not grade_on:
		_grade_from = Vector2.INF
	elif _grade_from == Vector2.INF and chain_depth >= (GRADE_START - 0.02 if grade_on else 0.2):
		_grade_from = here
		_grade_floor0 = beside - chain_depth
	at_stop = false
	aim_depth = -1.0
	if not plan.is_empty():
		# Only on or near the line: off somewhere else, there's nothing to aim for.
		var off := absf((here - (plan["from"] as Vector2)).dot(Vector2(-(plan["way"] as Vector2).y, (plan["way"] as Vector2).x)))
		if off < PLAN_NEAR:
			aim_depth = beside - aim_floor(here)
	elif _grade_from != Vector2.INF:
		var nearer := grade_toward.distance_to(_grade_from) - grade_toward.distance_to(here) if grade_toward != Vector2.INF else _grade_from.distance_to(here)
		aim_depth = beside - (_grade_floor0 - GRADE_FALL * nearer)
		# Free play: dug deeper than the aim, the aim comes down to it, as coming back up to the old one would be uphill.
		if not grade_on and chain_depth > aim_depth + 0.02:
			_grade_from = here
			_grade_floor0 = beside - chain_depth
			aim_depth = chain_depth
	# On a job, the depth stop: the chain won't go below the job's line. Dug deeper and brought back up to it would be a rise the
	# water stops at, so it never gets deeper than it.
	if not plan.is_empty() and not grade_on and aim_depth > 0.0 and chain_depth > aim_depth + DEPTH_STOP:
		chain_depth = move_toward(chain_depth, aim_depth + DEPTH_STOP, CHAIN_RATE * dt)
		at_stop = true
	if grade_on:
		var want := aim_depth if aim_depth > 0.0 else GRADE_START
		grade_short = want > chain_most
		chain_depth = move_toward(chain_depth, clampf(want, 0.05, chain_most), CHAIN_RATE * dt)
		hyd = clampf(absf(chain_depth - was) / dt / CHAIN_RATE, 0.0, 1.0)
	# Measured from the firm ground either side of the slot, not from the machine, or a machine dipping into its own cut would dig
	# deeper, dip further, and end up in a crater.
	var floor_y := beside - chain_depth
	teeth = Vector3(here.x, floor_y, here.y)
	blade_a = here
	blade_b = here
	load_t = 0.0
	on_rock = false
	_dig_force = 0.0
	var worked := 0
	if chain_depth <= 0.02:
		_floor_mark = Vector3.INF
		floor_trend = -9.0
	elif _floor_mark == Vector3.INF:
		_floor_mark = teeth
	else:
		var gone := Vector2(teeth.x - _floor_mark.x, teeth.z - _floor_mark.z).length()
		if gone >= 0.5:
			floor_trend = (teeth.y - _floor_mark.y) / gone
			_floor_mark = teeth
	if chain_depth > 0.02:
		digging = true
		var floor_mm := int(floor_y * 1000.0)
		var was_cut := Vector2(_cut_was.x, _cut_was.z)
		var steps := int(was_cut.distance_to(here) / 0.1) + 1
		if was_cut.distance_to(here) > 1.0:
			steps = 1
			was_cut = here
		for k in steps + 1:
			var p := was_cut.lerp(here, float(k) / steps)
			for w: float in chain_cuts:
				var at := DirtSim.cell_of(p + side * w)
				if at.x < 1 or at.y < 1 or at.x >= DirtSim.CELLS - 1 or at.y >= DirtSim.CELLS - 1:
					continue
				var n := at.y * DirtSim.CELLS + at.x
				if sim.rock[n] != 0 and sim.bed[n] > floor_mm:
					on_rock = true
					continue
				var throw := chain_depth * THROW_DEEP
				var to := DirtSim.cell_of(p + side * _rng.randf_range(throw_near + throw, throw_far + throw))
				worked += sim.trench(at, floor_mm, chain_cut, to)
		moved_tick = worked
		if worked > 0:
			trench_m += absf(speed) * dt
	_cut_was = teeth
	moved_m3 += DirtSim.to_m3(worked)
	bog = lerpf(bog, clampf(worked / 180.0, 0.0, 1.0), 0.15)
	# Soil coming up the chain: thrown from where the chain meets the ground, out to the right.
	pouring = 0.0
	# With the chain in the ground it crawls, whatever the stick says, and the deeper the slower.
	if chain_depth > 0.02:
		top_speed = chain_speed * lerpf(1.0, 0.45, chain_depth / chain_most)
		back_speed = 0.3
	else:
		top_speed = minf(_full_top, 1.7)
		back_speed = minf(_full_back, 1.7)
	_speed_cap = minf(_speed_cap, top_speed)

## The pipe layer: driving along a trench lays joined pipe down onto its floor, out behind the machine.
func _work_pipe() -> void:
	hyd = 0.0
	load_t = 0.0
	_dig_force = 0.0
	bog = 0.0
	top_speed = PIPE_SPEED
	back_speed = PIPE_SPEED
	_speed_cap = minf(_speed_cap, PIPE_SPEED)
	var f := forward()
	var side := Vector2(sin(angle), cos(angle))
	var here := spot + f * PIPE_AT
	# The pipe finds the bottom of the trench: the lowest firm ground across, a little either side of the layer, so it goes in
	# the slot even with the machine a bit off line, and never up its wall.
	var floor_y := sim.firm_at(here)
	var s := -PIPE_SNAP
	while s <= PIPE_SNAP + 0.001:
		var p := here + side * s
		var y := sim.firm_at(p)
		if y < floor_y - 0.005:
			floor_y = y
			here = p
		s += 0.125
	# A trench is ground lower than what's either side of it. The ridge beside it only makes that more so.
	var low := minf(sim.height_at(here + side * pipe_beside), sim.height_at(here - side * pipe_beside)) - floor_y
	in_trench = low > TRENCH_LOW
	teeth = Vector3(here.x, floor_y, here.y)
	blade_a = here
	blade_b = here
	if not in_trench or pipes == null or absf(speed) < 0.02:
		return
	var at := Vector3(here.x, floor_y + pipes.radius + 0.02, here.y)
	var end: Variant = pipes.last_end()
	if end == null or (end as Vector3).distance_to(at) > Pipes.JOIN_WITHIN:
		pipes.lay_to(at)
	elif (end as Vector3).distance_to(at) >= PIPE_EVERY:
		if pipes.lay_to(at):
			hit_end = 0.12

var _net_arm := 0.0
var _net_curl := 0.25
var _net_chain := 0.0

func _net_more() -> PackedFloat32Array:
	return PackedFloat32Array([arm, curl, bucket_mm, bucket_dust, int(trencher_on) | int(pipe_on) << 1 | int(spread_on) << 2 | int(spreading) << 3 | int(in_trench) << 4 | int(grade_on) << 5, chain_depth])

func _net_take_more(s: PackedFloat32Array) -> void:
	_net_arm = s[NET_BASE]
	_net_curl = s[NET_BASE + 1]
	bucket_mm = int(s[NET_BASE + 2])
	bucket_dust = int(s[NET_BASE + 3])
	var flags := int(s[NET_BASE + 4])
	var was_trench := trencher_on
	var was_pipe := pipe_on
	trencher_on = flags & 1 != 0
	pipe_on = flags & 2 != 0
	spread_on = flags & 4 != 0
	grade_on = flags & 32 != 0
	spreading = flags & 8 != 0
	in_trench = flags & 16 != 0
	_net_chain = s[NET_BASE + 5]
	if was_trench != trencher_on or was_pipe != pipe_on:
		_show_attachment()

func _net_pose(dt: float, k: float) -> void:
	_clock += dt
	arm = lerpf(arm, _net_arm, k)
	curl = lerpf(curl, _net_curl, k)
	chain_depth = lerpf(chain_depth, _net_chain, k)
	_pose()
	if not _rock_ready:
		_rock_ready = true

var _rock_ready := false

func _net_cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([lift_cmd, curl_cmd])

func _net_take_cmds_more(c: PackedFloat32Array) -> void:
	lift_cmd = c[2]
	curl_cmd = c[3]

func _rock_it(dt: float) -> void:
	# Heavy out front, the nose goes down; biting, it rides up; a Dingo jiggles about on anything.
	var out := fill() * clampf((_pin().x - pivot.x) / arm_len, 0.0, 1.0)
	var nose := -0.03 * out + 0.03 * bog
	var jig := 0.0
	if kind == DINGO:
		jig = sin(_clock * 37.0) * 0.003 * absf(drive) + sin(_clock * 23.0) * 0.002 * absf(drive)
	tilt = tilt.slerp(Basis(Vector3.BACK, nose + jig), minf(dt * 6.0, 1.0)).orthonormalized()
	_body.rotation.z = rock_pitch * 1.2 + sin(_clock * 49.0) * 0.0015 * absf(drive)
	_body.rotation.x = rock_roll * 1.5

## ---------------------------------------------------------------- the side-on picture
func side_view() -> Dictionary:
	if trencher_on or pipe_on:
		return {}
	var edge := _edge_world()
	var shape: Array[Vector2] = [Vector2(-0.02, 0.0), Vector2(bucket_len, 0.0), Vector2(0.0, bucket_high)]
	var big := kind == BOBCAT
	return {
		"low": -0.7 if big else -0.45, "high": 4.3 if big else 2.4, "left": -1.7 if big else -0.95,
		"body": [Rect2(-1.4, 0.15, 2.3, 0.6), Rect2(-1.3, 0.75, 1.15, 1.25)] if big else [Rect2(-0.75, 0.0, 1.2, 0.3), Rect2(-0.7, 0.3, 0.95, 0.6)],
		"joints": [pivot, _pin()],
		"pin": _pin(),
		"turn": curl,
		"shape": shape,
		"reach": bucket_len,
		"fill_from": Vector2.ZERO,
		"fill": fill(),
		"dust": bucket_dust * 2 > bucket_mm,
		"angle": rad_to_deg(curl),
		"pours": bucket_mm > _holds(),
		"pour": _pin() + Vector2(bucket_len, 0.0).rotated(curl),
		"has_load": bucket_mm > 0,
		"turn_word": "TURN", "out_word": "GO FORWARD", "in_word": "BACK UP",
		"down": sim.height_at(Vector2(edge.x, edge.z)) - edge.y,
	}
