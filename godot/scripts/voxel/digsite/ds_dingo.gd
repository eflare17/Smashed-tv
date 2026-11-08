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
const ARM_LOW := -1.05          # rad from level: the bucket's edge ~15 cm under its tracks ...
const ARM_HIGH := 0.95          # ... and up high (over a truck's side)
const CURL_MIN := -0.95         # tipped right forward
const CURL_MAX := 0.75          # curled right back
const POUR_FROM := -0.2         # tipped this far it starts to pour ...
const POUR_ALL := -0.7          # ... and by here it all comes out fast
const CAPACITY := 260           # blocks the bucket holds (0.5 m3)
const BITE_R := 0.2             # m round the edge it takes a bite
const BITE_EVERY := 0.08        # s between bites
const POUR_RATE := 300.0        # blocks a second, tipped right forward
const HARDEST := 2              # soil and clay (DsMats.HARD)
const ARM_PIVOT := Vector3(0, 0.95, -0.15)
const ARM_LEN := 1.05
const ROCK_COL := Color8(232, 180, 40)

var arm := 0.0                  # radians from level
var curl := 0.3
var lift_cmd := 0.0
var curl_cmd := 0.0
var bucket := {}                # material -> blocks in it
var load_n := 0
var _bite_t := 0.0
var _pour_acc := 0.0
var _arms: Node3D
var _bucket: Node3D
var _lump: MeshInstance3D

func _init() -> void:
	kind = "Dingo"
	length = 1.6
	width = 1.0
	max_speed = 2.0
	accel = 1.6
	turn_rate = 1.6
	max_climb = deg_to_rad(28.0)
	step_up = 0.26
	seat = Vector3(0, 0.32, 0.72)

func _build() -> void:
	super()
	var yellow := Color8(236, 178, 36)
	var dark := Color8(40, 40, 44)
	# tracks either side, the body between, the engine cover, the stand-on platform at the back, the controls
	for s in [-1.0, 1.0]:
		_box(self, Vector3(0.24, 0.32, 1.5), Vector3(s * 0.38, 0.16, 0), dark, 0.4)
		for k in 5:
			_box(self, Vector3(0.26, 0.05, 0.08), Vector3(s * 0.38, 0.33, -0.6 + k * 0.3), Color8(70, 70, 74), 0.5)
	_box(self, Vector3(0.55, 0.45, 1.1), Vector3(0, 0.5, -0.05), yellow)
	_box(self, Vector3(0.6, 0.2, 0.7), Vector3(0, 0.82, 0.05), Color8(220, 160, 28))
	_box(self, Vector3(0.7, 0.06, 0.4), Vector3(0, 0.3, 0.72), Color8(60, 60, 64), 0.6)
	_box(self, Vector3(0.5, 0.35, 0.12), Vector3(0, 1.05, 0.42), dark)
	for s in [-1.0, 1.0]:
		_box(self, Vector3(0.04, 0.5, 0.04), Vector3(s * 0.22, 1.2, 0.46), Color8(200, 40, 30))
	# the arms (from their pivot up the back of the body, to the bucket out front)
	_arms = Node3D.new()
	_arms.position = ARM_PIVOT
	add_child(_arms)
	for s in [-1.0, 1.0]:
		_box(_arms, Vector3(0.08, 0.1, ARM_LEN), Vector3(s * 0.33, 0, -ARM_LEN * 0.5), yellow)
	_box(_arms, Vector3(0.66, 0.08, 0.08), Vector3(0, 0, -ARM_LEN * 0.55), yellow)
	_bucket = Node3D.new()
	_bucket.position = Vector3(0, 0, -ARM_LEN)
	_arms.add_child(_bucket)
	# the bucket: a floor going forward from its hinge, a back, two sides
	var steel := Color8(90, 90, 96)
	_box(_bucket, Vector3(0.9, 0.04, 0.4), Vector3(0, -0.2, -0.2), steel, 0.6)
	_box(_bucket, Vector3(0.9, 0.36, 0.04), Vector3(0, -0.02, 0.0), steel, 0.6)
	for s in [-1.0, 1.0]:
		_box(_bucket, Vector3(0.04, 0.3, 0.4), Vector3(s * 0.45, -0.05, -0.2), steel, 0.6)
	_lump = _box(_bucket, Vector3(0.82, 0.3, 0.36), Vector3(0, -0.05, -0.19), Color8(122, 86, 52), 0.0)
	_lump.visible = false

## The bucket's floor against level (radians: up +, tipped forward -): it pours below POUR_FROM
func tip() -> float:
	return curl + 0.4 * arm

## The bucket's cutting edge in the world
func edge() -> Vector3:
	return _bucket.global_transform * Vector3(0, -0.2, -0.4)

func _pose_tool() -> void:
	if _arms == null:
		return
	_arms.rotation.x = arm
	_bucket.rotation.x = curl - arm * 0.6         # (the linkage keeps it roughly level as the arms go up)
	_lump.visible = load_n > 0
	if load_n > 0:
		var k := clampf(float(load_n) / CAPACITY, 0.15, 1.0)
		_lump.scale = Vector3(1.0, k, 1.0)
		_lump.position.y = -0.2 + 0.15 * k

func read_input() -> void:
	super()
	lift_cmd = float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))
	curl_cmd = float(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) - float(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))

func stop_cmds() -> void:
	super()
	lift_cmd = 0.0
	curl_cmd = 0.0

func keys() -> String:
	return "W/S drive   A/D turn   R/F arms up/down   right mouse: curl the bucket   left mouse: tip it   E get off"

func status() -> String:
	var s := "Bucket %d%%" % int(100.0 * load_n / CAPACITY)
	return s + ("   " + blocked if blocked != "" else "")

func _tool(dt: float) -> void:
	arm = clampf(arm + lift_cmd * LIFT_RATE * dt, ARM_LOW, ARM_HIGH)
	curl = clampf(curl + curl_cmd * CURL_RATE * dt, CURL_MIN, CURL_MAX)
	_pose_tool()
	var tr: DsTerrain = site.terrain
	var e := edge()
	# biting: the edge in the ground, going forward, the bucket not tipped, room in it
	_bite_t += dt
	if _bite_t >= BITE_EVERY:
		_bite_t = 0.0
		if speed > 0.15 and tip() > POUR_FROM and load_n < CAPACITY and tr.contains(e) and e.y < tr.top_at(e.x, e.z) - 0.02:
			var got: Dictionary = tr.dig(e, BITE_R, HARDEST)
			var counts: PackedInt32Array = got.counts
			for m in counts.size():
				if counts[m] > 0:
					bucket[m] = int(bucket.get(m, 0)) + counts[m]
					load_n += counts[m]
			if int(got.n) == 0 and int(got.refused) > HARDEST:
				speed = 0.0
				blocked = "Rock: the Dingo's bucket won't take it"
				if site.net:
					site.net.event("fx", ["dig_clang", e, 0])
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
				var put := tr.dump(e, m, take)
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
