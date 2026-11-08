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
const CAPACITY := 620           # blocks (1.2 m3)
const HARDEST := 3              # soil, clay, stone
const BITE_R := 0.32
const BITE_EVERY := 0.1
const POUR_RATE := 520.0
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
var _bite_t := 0.0
var _pour_acc := 0.0
var _look: Node3D               # the model, turned to face -z (the digger game's face +x)
var _house: Node3D
var _boom: MeshInstance3D
var _stick: MeshInstance3D
var _bucket: MeshInstance3D
var _lump: MeshInstance3D
var _rams: Array[MeshInstance3D] = []
var _tracks: DsTrackRig
static var prop_mat: StandardMaterial3D

func _init() -> void:
	kind = "excavator"
	length = 4.1
	width = 3.2
	max_speed = 1.5
	accel = 1.0
	turn_rate = 0.55
	max_climb = deg_to_rad(30.0)
	step_up = 0.4

static func mat() -> StandardMaterial3D:
	if prop_mat == null:
		prop_mat = StandardMaterial3D.new()
		prop_mat.vertex_color_use_as_albedo = true
		prop_mat.vertex_color_is_srgb = true
		prop_mat.roughness = 0.9
	return prop_mat

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
	kit = DsKit.new()
	kit.box(Vector3.ZERO, Vector3.ONE, DsProps.DIRT, Basis(Vector3.RIGHT, 0.05))
	_lump = _add(_bucket, kit)
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

## The bucket's teeth in the world
func edge() -> Vector3:
	return _look.global_transform * (Basis(Vector3.UP, swing) * _teeth_local())

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
		var deep := 0.3 + 0.62 * minf(f * 1.3, 1.0)
		var long := 0.5 + 0.55 * minf(f * 1.5, 1.0)
		_lump.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(long, deep, BUCKET_HALF * 1.86)), Vector3(0.58, 0.46 - deep * 0.5, 0.0))

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
	var deep := tr.top_at(e0.x, e0.z) - e0.y if tr.contains(e0) else 0.0
	var want := wrist + Vector2(_v_reach * REACH_SPEED, _v_raise * RAISE_SPEED) * dt
	if deep > STAB_MOST and _v_raise < 0.0:
		want.y = wrist.y                       # (it won't stab deeper: drag it in)
	_solve(want)
	curl = clampf(curl + _v_curl * CURL_SPEED * dt, CURL_MIN, CURL_MAX)
	_tracks.update(speed + steer * 0.8, speed - steer * 0.8, dt)
	_pose_tool()
	var e := edge()
	# digging: the teeth in the ground, being dragged in, pulled down or curled, room in the bucket
	_bite_t += dt
	if _bite_t >= BITE_EVERY:
		_bite_t = 0.0
		var working := _v_curl > 0.1 or _v_reach < -0.1 or _v_raise < -0.1
		if working and curl > CURL_EMPTY + 0.4 and load_n < CAPACITY and tr.contains(e) and e.y < tr.top_at(e.x, e.z) - 0.02:
			var got: Dictionary = tr.dig(e, BITE_R, HARDEST)
			var counts: PackedInt32Array = got.counts
			for m in counts.size():
				if counts[m] > 0:
					bucket[m] = int(bucket.get(m, 0)) + counts[m]
					load_n += counts[m]
			blocked = "Hard rock: too hard for the bucket" if int(got.n) == 0 and int(got.refused) > HARDEST else ""
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
				var put: int = truck.take(m, take) if truck else site.blasts._dump_spread(pp, m, take)
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
