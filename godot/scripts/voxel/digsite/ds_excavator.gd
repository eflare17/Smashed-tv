class_name DsExcavator
extends DsMachine
## The excavator (stage 10), the digger game's own (earthmover Excavator: its model from DsProps, its tracks DsTrackRig,
## its arm worked out the same way): a 20-tonne machine on tracks, its house (the cab, the engine, the boom) slewing
## round on top. You move the bucket's pin, not the joints: R/F raise and lower it, T/G reach it out and pull it in,
## and the boom and stick work out how to get it there (elbow up, as an excavator's always is). Z/X slew the house,
## the right mouse button curls the bucket in (holding; it digs as it goes through the ground), the left opens it
## (it pours out: over the tip truck's tray, into the truck). W/S and A/D drive its tracks. Its teeth bite the voxel
## ground below its own tracks too; stronger than the loaders (it breaks stone, not hard rock). You sit in its cab;
## your view slews with the house. In co-op the host's game runs it. Owned by the voxel session.

# (the digger game's numbers: excavator.gd)
const SHOULDER := Vector2(1.0, 1.85)   # where the boom meets the house: out from the middle, up from the ground
const ARM_Z := 0.25
const BOOM := 5.6
const STICK := 2.9
const BUCKET := 1.35
const BUCKET_HALF := 0.62
const BOOM_LOW := -0.87
const BOOM_HIGH := 1.2
const ELBOW_MIN := 0.55
const ELBOW_MAX := 2.85
const NEAREST := 2.7
const REACH_SPEED := 2.3
const RAISE_SPEED := 2.0
const SWING_SPEED := 0.8
const CURL_SPEED := 1.7
const ARM_EASE := 5.0
const SWING_EASE := 1.7
const CURL_MIN := 0.3           # tipped right out, open side down
const CURL_MAX := 3.5           # curled right in, open side up
const CURL_HOLDS := 2.3         # curled this far it keeps it all ...
const CURL_EMPTY := 0.95        # ... opened this far, nothing
const STAB_MOST := 0.8          # m its teeth push into the ground before it has to drag
# (the Dig Site's)
const CAPACITY := 620 * DsTerrain.MM   # mm (620 blocks of 125 mm over a column: 1.2 m3)
const HEAPED := 0.78            # of CAPACITY: past this it's heaped up out of the bucket's open side (the digger game's 27000/34560)
const LOAD_LEVELS := 12         # the soil in the bucket drawn at so many levels filling its hollow ...
const HEAP_LEVELS := 6          # ... and so many heaped
const HEAP_TALL := 0.3          # m the heap stands at its fullest, in the middle
const HARDEST := 3              # soil, clay, stone
const FIRM_RATE := 9.0          # firm blocks a second its teeth cut off a column (loose ones: all at once)
const POUR_RATE := 520.0 * DsTerrain.MM
const SEAT_MODEL := Vector3(0.45, 1.2, -0.8)    # (in the house, the digger game's way round: the cab's floor)

var swing := 0.0
var wrist := Vector2(5.2, 2.7)  # the bucket's pin, in the house's up-and-out plane
var curl := 2.7
var swing_cmd := 0.0
var reach_cmd := 0.0
var raise_cmd := 0.0
var curl_cmd := 0.0
var bucket := {}
var load_n := 0
var _boom_a := 0.0
var _stick_a := 0.0
var _v_swing := 0.0
var _v_reach := 0.0
var _v_raise := 0.0
var _v_curl := 0.0
var dug := 0                    # (tests: mm its teeth have taken)
var bog := 0.0                  # how much the ground's holding the arm back (0 .. 0.85)
var _firm_acc := 0.0
var _pour_acc := 0.0
var _look: Node3D               # the model, turned to face -z (the digger game's face +x)
var _house: Node3D
var _boom: MeshInstance3D
var _stick: MeshInstance3D
var _bucket: MeshInstance3D
var _lump: MeshInstance3D
var _loads: Array[ArrayMesh] = []
var _rams: Array[MeshInstance3D] = []
var _tracks: DsTrackRig
static var prop_mat: Material

func _init() -> void:
	kind = "excavator"
	length = 4.1
	width = 3.2
	max_speed = 1.5
	accel = 1.0
	turn_rate = 0.55
	max_climb = deg_to_rad(30.0)
	step_up = 0.4
	pipe = Vector3(-0.8, 2.3, -1.6)

static func mat() -> Material:
	return DsLook.prop_mat()

func _add(parent: Node3D, kit: DsKit) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = mat()
	parent.add_child(m)
	return m

func _build() -> void:
	super()
	(_body.get_child(0) as CollisionShape3D).position.y = 0.6
	_look = Node3D.new()
	_look.rotation.y = PI * 0.5
	add_child(_look)
	var carriage := DsKit.new()
	DsProps.track_frames(carriage, 1.25, 0.32, 1.9, 2.4, 2.05, false)
	DsProps.excavator_carriage(carriage)
	_add(_look, carriage)
	_tracks = DsTrackRig.new()
	_look.add_child(_tracks)
	_tracks.setup(mat(), DsProps.track_path(1.9, 2.43, 2.07), 1.25, 0.66, 1.59, DsProps.excavator_wheels())
	_house = Node3D.new()
	_look.add_child(_house)
	var hk := DsKit.new()
	DsProps.excavator_house(hk, false)
	_add(_house, hk)
	var kit := DsKit.new()
	DsProps.excavator_boom(kit, BOOM, false)
	_boom = _add(_house, kit)
	kit = DsKit.new()
	DsProps.excavator_stick(kit, STICK, false)
	_stick = _add(_house, kit)
	kit = DsKit.new()
	DsProps.excavator_bucket(kit, BUCKET, BUCKET_HALF, false)
	_bucket = _add(_house, kit)
	_build_loads()
	_lump = MeshInstance3D.new()
	_lump.material_override = mat()
	_bucket.add_child(_lump)
	_lump.visible = false
	for k in 3:
		kit = DsKit.new()
		kit.cone(Vector3.ZERO, Vector3(0.62, 0.0, 0.0), 0.1, 0.1, 6, DsProps.CHARCOAL)
		kit.cone(Vector3(0.62, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), 0.05, 0.05, 6, DsProps.STEEL)
		_rams.append(_add(_house, kit))
	_solve(wrist)

## Sets the boom and stick to bring the pin as near to want as they can reach (the digger game's, as it is)
func _solve(want: Vector2) -> void:
	var w := Vector2(maxf(want.x, NEAREST), want.y)
	var v := w - SHOULDER
	var far := sqrt(BOOM * BOOM + STICK * STICK - 2.0 * BOOM * STICK * cos(ELBOW_MAX))
	var near := sqrt(BOOM * BOOM + STICK * STICK - 2.0 * BOOM * STICK * cos(ELBOW_MIN))
	var d := clampf(v.length(), near, far)
	if v.length() < 0.001:
		v = Vector2(1.0, 0.0)
	v = v.normalized() * d
	var a := v.angle() + acos(clampf((BOOM * BOOM + d * d - STICK * STICK) / (2.0 * BOOM * d), -1.0, 1.0))
	var boom_a := clampf(a, BOOM_LOW, BOOM_HIGH)
	var elbow := SHOULDER + Vector2(cos(boom_a), sin(boom_a)) * BOOM
	var to := (SHOULDER + v) - elbow
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

func _teeth_local() -> Vector3:
	return Vector3(wrist.x + cos(-curl) * BUCKET, wrist.y + sin(-curl) * BUCKET, ARM_Z)

## The teeth's two ends (across the bucket) in the world
func teeth_ends() -> Array:
	var t := _teeth_local()
	var g := _look.global_transform
	var r := Basis(Vector3.UP, swing)
	return [g * (r * (t + Vector3(0, 0, -BUCKET_HALF))), g * (r * (t + Vector3(0, 0, BUCKET_HALF)))]

## The bucket's teeth in the world
func edge() -> Vector3:
	return _look.global_transform * (Basis(Vector3.UP, swing) * _teeth_local())

func fx_load() -> int:
	return load_n

func fx_pour_at() -> Vector3:
	return pour_point()

## Where what's in the bucket comes out, opened: under its pin (it doesn't swing away with the teeth)
func pour_point() -> Vector3:
	return _look.global_transform * (Basis(Vector3.UP, swing) * Vector3(wrist.x + 0.4, wrist.y - 0.4, ARM_Z))

func seat_world() -> Vector3:
	return _look.global_transform * (Basis(Vector3.UP, swing) * SEAT_MODEL)

func view_yaw() -> float:
	return yaw + swing

func _pose_tool() -> void:
	if _house == null:
		return
	_house.transform = Transform3D(Basis(Vector3.UP, swing), Vector3.ZERO)
	var shoulder := Vector3(SHOULDER.x, SHOULDER.y, ARM_Z)
	var elbow := Vector3(SHOULDER.x + cos(_boom_a) * BOOM, SHOULDER.y + sin(_boom_a) * BOOM, ARM_Z)
	var pin := Vector3(wrist.x, wrist.y, ARM_Z)
	var boom_b := Basis(Vector3.BACK, _boom_a)
	var stick_b := Basis(Vector3.BACK, _stick_a)
	var bucket_b := Basis(Vector3.BACK, -curl)
	_boom.transform = Transform3D(boom_b, shoulder)
	_stick.transform = Transform3D(stick_b, elbow)
	_bucket.transform = Transform3D(bucket_b, pin)
	_ram(0, Vector3(1.75, 1.3, ARM_Z), shoulder + boom_b * Vector3(2.5, 0.05, 0.0))
	_ram(1, shoulder + boom_b * Vector3(BOOM * 0.55, 1.02, 0.0), elbow + stick_b * Vector3(-0.58, 0.42, 0.0))
	_ram(2, elbow + stick_b * Vector3(0.1, 0.34, 0.0), pin + bucket_b * Vector3(0.0, 0.42, 0.0))
	var f := float(load_n) / CAPACITY
	_lump.visible = f > 0.02
	if _lump.visible:
		# the soil in the bucket: fills its hollow from the back, then heaps up out of the open side
		var k := 0
		if f <= HEAPED:
			k = clampi(int(ceil(f / HEAPED * LOAD_LEVELS)) - 1, 0, LOAD_LEVELS - 1)
		else:
			k = LOAD_LEVELS - 1 + clampi(int(ceil((f - HEAPED) / (1.0 - HEAPED) * HEAP_LEVELS)), 0, HEAP_LEVELS)
		_lump.mesh = _loads[k]

## The bucket as a box (world, half sizes), for DsClods to keep lumps out of (its hollow: -0.08 to 1.35 along, -0.28 to
## 0.52 up, in its own frame)
func keepout_boxes() -> Array:
	if _bucket == null:
		return []
	return [[_bucket.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.64, 0.12, 0.0)), Vector3(0.76, 0.44, BUCKET_HALF + 0.04)]]

func _ram(k: int, a: Vector3, b: Vector3) -> void:
	var along := b - a
	var x := along.normalized()
	var z := Vector3.BACK
	var y := z.cross(x).normalized()
	_rams[k].transform = Transform3D(Basis(x * along.length(), y, z), a)

func read_input() -> void:
	super()
	swing_cmd = float(Input.is_physical_key_pressed(KEY_X)) - float(Input.is_physical_key_pressed(KEY_Z))
	raise_cmd = float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))
	reach_cmd = float(Input.is_physical_key_pressed(KEY_T)) - float(Input.is_physical_key_pressed(KEY_G))
	curl_cmd = float(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) - float(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))

func stop_cmds() -> void:
	super()
	swing_cmd = 0.0
	raise_cmd = 0.0
	reach_cmd = 0.0
	curl_cmd = 0.0

func keys() -> String:
	return "W/S A/D tracks   Z/X swing   R/F bucket up/down   T/G reach out/in\nright mouse: curl in (dig)   left mouse: open (pour)   V view   wheel zoom   E get off"

func status() -> String:
	return "Bucket %d%%" % int(100.0 * load_n / CAPACITY) + ("   " + blocked if blocked != "" else "")

func _tool(dt: float) -> void:
	# the house: heavy, it takes a moment to start and stop turning
	_v_swing = move_toward(_v_swing, swing_cmd, SWING_EASE * dt)
	swing = wrapf(swing - _v_swing * SWING_SPEED * dt, -PI, PI)
	# the pin where it's asked, the boom and stick worked out; the bucket curled
	_v_reach = move_toward(_v_reach, reach_cmd, ARM_EASE * dt)
	_v_raise = move_toward(_v_raise, raise_cmd, ARM_EASE * dt)
	_v_curl = move_toward(_v_curl, curl_cmd, ARM_EASE * 1.4 * dt)
	var tr: DsTerrain = site.terrain
	var e0 := edge()
	# (how far its teeth are under the ground round them, the lower side of the bucket (a heap beside it isn't ground
	# to push into): the strip they've just cut doesn't count, or with the ground cut exactly to them it never read
	# deep, and the bucket went on down 1.8 m and couldn't lift out to pour)
	var deep := 0.0
	if tr.contains(e0):
		var across: Vector3 = _look.global_transform.basis * (Basis(Vector3.UP, swing) * Vector3(0, 0, BUCKET_HALF + 0.35))
		var side := minf(tr.surface_at(e0.x + across.x, e0.z + across.z), tr.surface_at(e0.x - across.x, e0.z - across.z))
		deep = maxf(tr.surface_at(e0.x, e0.z), side) - e0.y
	var slow := 1.0 - bog                          # (cutting firm ground holds the arm back)
	var want := wrist + Vector2(_v_reach * REACH_SPEED, _v_raise * RAISE_SPEED) * dt * slow
	if deep > STAB_MOST and _v_raise < 0.0:
		want.y = wrist.y                       # (it won't stab deeper: drag it in)
	_solve(want)
	curl = clampf(curl + _v_curl * CURL_SPEED * dt, CURL_MIN, CURL_MAX)
	_tracks.update(speed + steer * 0.8, speed - steer * 0.8, dt)
	_pose_tool()
	var e := edge()
	# digging (the digger game's way, DsTerrain.blade): the teeth dragged, pulled down or curled through the ground take
	# what stands above them in the strip they sweep, into the bucket (firm ground only so fast: in firm ground the arm
	# bogs down); rock harder than it breaks stops them
	var working := _v_curl > 0.1 or _v_reach < -0.1 or _v_raise < -0.1
	if working and curl > CURL_EMPTY + 0.4 and load_n < CAPACITY and tr.contains(e) and e.y < tr.surface_at(e.x, e.z) + 0.1:
		var ends := teeth_ends()
		var travel := e - e0
		var fwd := Vector3(travel.x, 0.0, travel.z)
		if fwd.length() < 0.002:
			fwd = Vector3.ZERO
		_firm_acc = minf(_firm_acc + FIRM_RATE * dt, 3.0)
		var firm := int(_firm_acc)
		_firm_acc -= firm
		var rows := 2 + ceili(fwd.length() / 0.22)          # (the whole strip the teeth swept this frame)
		var r: Dictionary = tr.blade(ends[0], ends[1], fwd, rows, 0.75, firm, HARDEST, CAPACITY - load_n, 0.9)
		var counts: PackedInt32Array = r.counts
		for m in counts.size():
			if counts[m] > 0:
				bucket[m] = int(bucket.get(m, 0)) + counts[m]
				load_n += counts[m]
		dug += int(r.taken) + int(r.moved)
		# (firm ground being cut, or standing over the teeth uncut, holds the arm back; loose comes easy)
		var stuck := 0.5 if int(r.taken) == 0 and e.y < tr.surface_at(e.x, e.z) - 0.1 else 0.0
		bog = lerpf(bog, clampf(float(r.cut) / DsTerrain.MM / 6.0 + stuck, 0.0, 0.85), minf(1.0, dt * 6.0))
		blocked = "Hard rock: too hard for the bucket" if bool(r.rock) and int(r.taken) == 0 else ""
	else:
		bog = 0.0
	# pouring: opened past where it holds, out it comes at the teeth (over the truck: in its tray)
	var hold := clampf((curl - CURL_EMPTY) / (CURL_HOLDS - CURL_EMPTY), 0.0, 1.0)
	if hold < 1.0 and load_n > 0:
		_pour_acc += POUR_RATE * (1.0 - hold) * dt
		var n := int(_pour_acc)
		if n > 0:
			_pour_acc -= n
			var pp := pour_point()
			var truck = site.machines.catcher(pp, self)
			while n > 0 and load_n > 0:
				var m := _most()
				var take := mini(n, int(bucket[m]))
				var put: int = truck.take(m, take) if truck else site.terrain.pour(pp, m, take)
				if put <= 0:
					break
				bucket[m] = int(bucket[m]) - put
				if int(bucket[m]) <= 0:
					bucket.erase(m)
				load_n -= put
				n -= put

func _follow(dt: float) -> void:
	super(dt)
	_tracks.update(speed, speed, dt)

## Its stack's top, on the house (DsProps.excavator_house's), slewing with it
func exhaust_at() -> Vector3:
	return _look.global_transform * (Basis(Vector3.UP, swing) * Vector3(-1.75, 3.1, 0.8))

var _dug_was := 0

# (the digger game's _update_dig_fx) dirt flying and dust where its teeth are cutting, at the ground
func _dust_fx() -> void:
	super()
	var cutting: bool = dug != _dug_was or (not runs() and _v_curl > 0.1 and curl > CURL_EMPTY + 0.4 and edge().y < site.terrain.surface_at(edge().x, edge().z))
	_dug_was = dug
	var at := edge()
	at.y = maxf(at.y, ground_y(at.x, at.z) + 0.05)
	work_fx(at, BUCKET_HALF * 0.8, cutting)

func _most() -> int:
	var best := DsMats.DIRT
	var bn := -1
	for m in bucket:
		if int(bucket[m]) > bn:
			best = int(m)
			bn = int(bucket[m])
	return best

func net_more() -> PackedFloat32Array:
	return PackedFloat32Array([swing, wrist.x, wrist.y, curl, float(load_n)])

func net_take_more(f: PackedFloat32Array) -> void:
	if f.size() >= 5:
		swing = lerp_angle(swing, f[0], 0.5)
		_solve(wrist.lerp(Vector2(f[1], f[2]), 0.5))
		curl = lerpf(curl, f[3], 0.5)
		load_n = int(f[4])

func _cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([swing_cmd, reach_cmd, raise_cmd, curl_cmd])

func _take_cmds_more(f: PackedFloat32Array) -> void:
	if f.size() >= 4:
		swing_cmd = clampf(f[0], -1.0, 1.0)
		reach_cmd = clampf(f[1], -1.0, 1.0)
		raise_cmd = clampf(f[2], -1.0, 1.0)
		curl_cmd = clampf(f[3], -1.0, 1.0)

## The soil in the bucket at each level, built once (the digger game's, owner 9 Nov: "the dirt clips through the bucket": the
## old block poked out through it). It fills the bucket's own hollow, in from its shell and side plates, from the back
## towards the open side, its top lumpy; past HEAPED a rounded heap of lumps stands out of the open side, inside the plates.
func _build_loads() -> void:
	var length := BUCKET
	# the hollow, as DsProps.excavator_bucket shapes it: the shell round the back, the open side from the teeth to the heel
	var hollow := PackedVector2Array([Vector2(-0.08, 0.1), Vector2(0.35, 0.5), Vector2(0.85, 0.52), Vector2(length - 0.12, 0.14), Vector2(length, -0.02), Vector2(0.15, -0.28)])
	_loads = load_meshes(hollow, 4, 5, BUCKET_HALF - 0.06, 1.0)

## A bucket's load at each of LOAD_LEVELS + HEAP_LEVELS levels: `hollow` its inside (in its own x-y plane, shrunk a
## little here), the open side from hollow[lip_i] to hollow[heel_i], `half` its inside half width, `scale` the lumps'
## size against the excavator's (the loaders' buckets are smaller). Shared with DsDingo.
static func load_meshes(hollow_in: PackedVector2Array, lip_i: int, heel_i: int, half: float, scale: float) -> Array[ArrayMesh]:
	var hollow := hollow_in.duplicate()
	var mid := Vector2.ZERO
	for p in hollow:
		mid += p / hollow.size()
	for i in hollow.size():
		hollow[i] = mid + (hollow[i] - mid) * 0.9
	var lip := hollow[lip_i]
	var heel := hollow[heel_i]
	var along := (heel - lip).normalized()
	var into := Vector2(-along.y, along.x)
	if into.dot(mid - lip) < 0.0:
		into = -into
	var deepest := 0.0
	for p in hollow:
		deepest = maxf(deepest, (p - lip).dot(into))
	var whole := _area(hollow)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var dark := DsProps.DIRT.darkened(0.15)
	var loads: Array[ArrayMesh] = []
	for k in LOAD_LEVELS + HEAP_LEVELS:
		var kit := DsKit.new()
		var share := minf(float(k + 1) / LOAD_LEVELS, 1.0)
		var heap := maxf(float(k + 1 - LOAD_LEVELS) / HEAP_LEVELS, 0.0)
		# where its top is, measured in from the open side, found so it holds the right share of the hollow
		var lo := 0.0
		var hi := deepest
		for i in 18:
			var try_at := (lo + hi) * 0.5
			if _area(_clip(hollow, lip, into, try_at)) > share * whole:
				lo = try_at
			else:
				hi = try_at
		var cut := (lo + hi) * 0.5
		var body := _clip(hollow, lip, into, cut)
		if body.size() >= 3:
			kit.prism(Array(body), -half, half, DsProps.DIRT)
		var top_a := lip + into * cut
		var top_b := heel + into * cut
		if heap <= 0.0:
			# where the top meets the shell at each end, kept a little in so no lump pokes through it
			var ends := _top_ends(body, lip, into, cut)
			top_a = ends[0]
			top_b = ends[1]
		var out := Vector3(-into.x, -into.y, 0.0)
		# low, rounded and close together, so they read as one heap of clods, not a row of rocks
		var rows := 6 if heap > 0.0 else 4
		var cols := 5 if heap > 0.0 else 3
		for i in rows:
			for j in cols:
				var t := lerpf(0.16, 0.84, (i + rng.randf_range(-0.3, 0.3)) / (rows - 1))
				var r := (0.13 if heap > 0.0 else 0.09) * scale * rng.randf_range(0.8, 1.2)
				# kept clear of the side plates, rough edges and all
				var z := clampf(lerpf(-half + r * 1.5, half - r * 1.5, (j + rng.randf_range(-0.25, 0.25)) / (cols - 1)), -half + r * 1.5, half - r * 1.5)
				var base2 := top_a.lerp(top_b, t)
				var dome := (1.0 - pow(2.0 * t - 1.0, 2.0)) * (1.0 - pow(z / half, 2.0))
				var tall := heap * HEAP_TALL * scale * dome + r * rng.randf_range(0.25, 0.5)
				var base := Vector3(base2.x, base2.y, z) - out * r * 0.5
				var waist := base + out * (tall * 0.6 + r * 0.25)
				var col := DsProps.DIRT if rng.randf() < 0.6 else dark
				kit.cone(base, waist, r, r * 1.1, 7, col, 0.2, rng)
				kit.cone(waist, base + out * (tall + r * 0.5), r * 1.1, r * 0.5, 7, col, 0.2, rng)
		loads.append(kit.mesh())
	return loads

## The part of a convex shape at least `cut` in from the line through `at` (measured along `into`)
static func _clip(shape: PackedVector2Array, at: Vector2, into: Vector2, cut: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in shape.size():
		var a := shape[i]
		var b := shape[(i + 1) % shape.size()]
		var da := (a - at).dot(into) - cut
		var db := (b - at).dot(into) - cut
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out

## The two ends of a clipped shape's cut edge, each pulled in a little
static func _top_ends(shape: PackedVector2Array, at: Vector2, into: Vector2, cut: float) -> Array:
	var on: Array[Vector2] = []
	for p in shape:
		if absf((p - at).dot(into) - cut) < 0.0005:
			on.append(p)
	if on.size() < 2:
		return [at + into * cut, at + into * cut]
	var a: Vector2 = on[0]
	var b: Vector2 = on[on.size() - 1]
	return [a.lerp(b, 0.08), b.lerp(a, 0.08)]

static func _area(shape: PackedVector2Array) -> float:
	var sum := 0.0
	for i in shape.size():
		var a := shape[i]
		var b := shape[(i + 1) % shape.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5
