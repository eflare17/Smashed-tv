class_name DsDingo
extends DsMachine
## The Dingo (stage 6): a stand-on mini loader, its bucket on two arms out front, like the digger game's (Loader:
## LIFT_RATE, CURL_RATE, POUR_FROM). R/F raise and lower the arms, the right mouse button curls the bucket back (it
## holds), the left tips it forward (it pours). Drive at the ground with the bucket low and it bites the voxel ground
## into the bucket (soil and clay: not rock, it stops dead on that); lift it, drive, tip it and what's in it pours
## out where the bucket's edge is, loose, and slumps into a pile (DsTerrain.dump). The game that runs the ground does
## the digging and pouring; the guest's shows the arms and the bucket from the host's state. Owned by the voxel
## session.

const LIFT_RATE := 0.75         # rad/s, the arms
const CURL_RATE := 1.3
const ARM_LOW := -0.95          # rad from level: the bucket's edge just under its tracks ...
const ARM_HIGH := 0.95          # ... and up high (over a truck's side)
const CURL_MIN := -0.95         # the bucket's floor against level: tipped right forward ...
const CURL_MAX := 0.75          # ... curled right back
const POUR_FROM := -0.2         # tipped this far it starts to pour ...
const POUR_ALL := -0.7          # ... and by here it all comes out fast
const CAPACITY := 260           # blocks the bucket holds (0.5 m3)
const BITE_EVERY := 0.08        # s between bites
const POUR_RATE := 300.0        # blocks a second, tipped right forward
const HARDEST := 2              # soil and clay (DsMats.HARD)

var arm := 0.0                  # radians from level
var curl := 0.0                 # the bucket's floor against level (up +: holding; tipped forward -: pouring)
var lift_cmd := 0.0
var curl_cmd := 0.0
var bucket := {}                # material -> blocks in it
var load_n := 0
var push_load := 0              # loose blocks banked against the bucket (it slows it)
var dug := 0                    # (tests: blocks its bucket's taken or pushed)
var firm_rate := 1              # firm blocks off a column each tick (the Bobcat: 2)
var bog := 900.0                # banked blocks that bring it nearly to a stop
var _pour_acc := 0.0
var _look: Node3D               # the model, turned to face -z (the digger game's face +x)
var _arms: MeshInstance3D
var _bucket: MeshInstance3D
var _lump: MeshInstance3D
var _tracks: DsTrackRig
var _wheels := []               # (the Bobcat's) [node, radius]
var _roll := 0.0
# the digger game's Loader numbers (the Bobcat changes these: DsBobcat), in its frame: x forward, y up
var capacity := CAPACITY
var hardest := HARDEST
var pivot := Vector2(-0.1, 0.85)
var arm_len := 1.15
var arm_low := ARM_LOW
var arm_high := ARM_HIGH
var bucket_len := 0.42
var bucket_half := 0.5
var bucket_high := 0.36

func _init() -> void:
	kind = "Dingo"
	length = 1.6
	width = 1.0
	max_speed = 2.0
	accel = 1.6
	turn_rate = 1.6
	max_climb = deg_to_rad(28.0)
	step_up = 0.26
	seat = Vector3(0, 0.23, 0.92)

func _add(parent: Node3D, kit: DsKit) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = DsExcavator.mat()
	parent.add_child(m)
	return m

func _build() -> void:
	super()
	_look = Node3D.new()
	_look.rotation.y = PI * 0.5
	add_child(_look)
	_build_body()
	_build_arms()

## (the digger game's Dingo: its body, its tracks)
func _build_body() -> void:
	var kit := DsKit.new()
	DsProps.dingo_body(kit)
	_add(_look, kit)
	var frames := DsKit.new()
	DsProps.track_frames(frames, 0.44, 0.1, 0.56, 0.72, 0.6)
	var frame := _add(_look, frames)
	frame.scale = Vector3(1.0, 0.42, 1.0)
	_tracks = DsTrackRig.new()
	_tracks.scale = Vector3(1.0, 0.42, 1.0)
	_look.add_child(_tracks)
	var wheel_list: Array[Vector3] = [Vector3(-0.6, 0.5, 0.2), Vector3(0.6, 0.5, 0.2)]
	_tracks.setup(DsExcavator.mat(), DsProps.track_path(0.56, 0.74, 0.62), 0.44, 0.23, 0.56, wheel_list, 0.14)

## The arms and the bucket (the digger game's loader_arms, loader_bucket) and the load in it
func _build_arms() -> void:
	var kit := DsKit.new()
	DsProps.loader_arms(kit, arm_len, 0.84 if kind == "Bobcat" else 0.3, 0.16 if kind == "Bobcat" else 0.07)
	_arms = _add(_look, kit)
	kit = DsKit.new()
	DsProps.loader_bucket(kit, bucket_len, bucket_half, bucket_high)
	_bucket = _add(_look, kit)
	kit = DsKit.new()
	kit.prism([Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.28, 0.72), Vector2(-0.4, 1.0)], -0.5, 0.5, DsProps.DIRT)
	_lump = _add(_bucket, kit)
	_lump.visible = false

func fx_load() -> int:
	return load_n

func fx_pour_at() -> Vector3:
	return edge()

## The bucket's floor against level (radians: up +, tipped forward -): it pours below POUR_FROM
func tip() -> float:
	return curl

func _pin() -> Vector2:
	return pivot + Vector2(cos(arm), sin(arm)) * arm_len

## The bucket's lip, its two ends, in the world
func edge_ends() -> Array:
	var p := _pin()
	var l := Vector3(p.x + cos(curl) * bucket_len, p.y + sin(curl) * bucket_len, 0.0)
	return [_look.global_transform * (l + Vector3(0, 0, -bucket_half)), _look.global_transform * (l + Vector3(0, 0, bucket_half))]

func _drive(dt: float) -> void:
	var top := max_speed
	max_speed = top * (1.0 - 0.75 * clampf(float(push_load) / bog, 0.0, 1.0))
	super(dt)
	max_speed = top

## The bucket's cutting edge in the world
func edge() -> Vector3:
	var p := _pin()
	return _look.global_transform * Vector3(p.x + cos(curl) * bucket_len, p.y + sin(curl) * bucket_len, 0.0)

func _pose_tool() -> void:
	if _arms == null:
		return
	var p := _pin()
	_arms.transform = Transform3D(Basis(Vector3.BACK, arm), Vector3(pivot.x, pivot.y, 0.0))
	_bucket.transform = Transform3D(Basis(Vector3.BACK, curl), Vector3(p.x, p.y, 0.0))
	var f := float(load_n) / capacity
	_lump.visible = f > 0.03
	if _lump.visible:
		var up := bucket_high * (0.35 + 0.95 * f)
		var along := bucket_len * (0.5 + 0.45 * minf(f * 1.4, 1.0))
		_lump.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(along, up, bucket_half * 1.9)), Vector3(along * 0.5 + 0.04, 0.02, 0.0))

## Tracks and wheels turning with how it goes
func _spin(dt: float) -> void:
	if _tracks:
		_tracks.update(speed + steer * 0.6, speed - steer * 0.6, dt)
	_roll += speed * dt
	for w in _wheels:
		var r: float = w[1]
		(w[0] as Node3D).basis = Basis(Vector3.BACK, -_roll / r).scaled(Vector3(r, r, 1.0))

func read_input() -> void:
	super()
	lift_cmd = float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))
	curl_cmd = float(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) - float(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))

func stop_cmds() -> void:
	super()
	lift_cmd = 0.0
	curl_cmd = 0.0

func keys() -> String:
	return "W/S drive   A/D turn   R/F arms up/down\nright mouse: curl the bucket   left mouse: tip it   V view   wheel zoom   E get off"

func status() -> String:
	var s := "Bucket %d%%" % int(100.0 * load_n / capacity)
	return s + ("   " + blocked if blocked != "" else "")

func _follow(dt: float) -> void:
	super(dt)
	_spin(dt)

func _tool(dt: float) -> void:
	_spin(dt)
	arm = clampf(arm + lift_cmd * LIFT_RATE * dt, arm_low, arm_high)
	curl = clampf(curl + curl_cmd * CURL_RATE * dt, CURL_MIN, CURL_MAX)
	_pose_tool()
	var tr: DsTerrain = site.terrain
	var e := edge()
	# the bucket's lip through the ground (the digger game's way, DsTerrain.blade): going forward, not tipped, what
	# stands above the lip goes in (firm ground only so fast), and once it's full the rest banks up ahead of it (it
	# pushes, like a small dozer); what's banked against it slows it
	push_load = 0
	if (speed > 0.03 or throttle > 0.05) and tip() > POUR_FROM:
		var ends := edge_ends()
		var f := forward()
		var rows := 2 + ceili(absf(speed) * dt / 0.22)      # (the whole strip it swept this frame, however slow the frame)
		var r: Dictionary = tr.blade(ends[0], ends[1], f, rows, bucket_high + 0.1, firm_rate, hardest, capacity - load_n, bucket_high + 0.35)
		var counts: PackedInt32Array = r.counts
		for m in counts.size():
			if counts[m] > 0:
				bucket[m] = int(bucket.get(m, 0)) + counts[m]
				load_n += counts[m]
		dug += int(r.taken) + int(r.moved)
		if bool(r.rock) and int(r.taken) + int(r.moved) == 0 and speed > 0.0:
			speed = 0.0
			blocked = "Rock: the %s's bucket won't take it" % kind
			if site.net:
				site.net.event("fx", ["dig_clang", e, 0])
		push_load = tr.load_ahead(ends[0], ends[1], f, bucket_high + 0.3)
	# pouring: tipped forward, it comes out where the edge is, loose (a pile)
	if tip() < POUR_FROM and load_n > 0:
		var k := clampf((POUR_FROM - tip()) / (POUR_FROM - POUR_ALL), 0.0, 1.0)
		_pour_acc += POUR_RATE * k * dt
		var n := int(_pour_acc)
		if n > 0:
			_pour_acc -= n
			n = mini(n, load_n)
			while n > 0 and load_n > 0:
				var m := _most()
				var take := mini(n, int(bucket[m]))
				var truck = site.machines.catcher(e, self)
				var put: int = truck.take(m, take) if truck else tr.pour(e, m, take)
				if put <= 0:
					break
				bucket[m] = int(bucket[m]) - put
				if int(bucket[m]) <= 0:
					bucket.erase(m)
				load_n -= put
				n -= put

func _most() -> int:
	var best := DsMats.DIRT
	var bn := -1
	for m in bucket:
		if int(bucket[m]) > bn:
			best = int(m)
			bn = int(bucket[m])
	return best

func net_more() -> PackedFloat32Array:
	return PackedFloat32Array([arm, curl, float(load_n)])

func net_take_more(f: PackedFloat32Array) -> void:
	if f.size() >= 3:
		arm = lerpf(arm, f[0], 0.5)
		curl = lerpf(curl, f[1], 0.5)
		load_n = int(f[2])

func _cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([lift_cmd, curl_cmd])

func _take_cmds_more(f: PackedFloat32Array) -> void:
	if f.size() >= 2:
		lift_cmd = clampf(f[0], -1.0, 1.0)
		curl_cmd = clampf(f[1], -1.0, 1.0)
