class_name DsExcavator
extends DsMachine
## The excavator (stage 10), like the digger game's Excavator: on tracks, its house (the cab, the engine, the boom)
## slews round on top, the boom, the stick and the bucket on the end of it. It digs from where it stands, down below
## its own tracks (a trench, a pit), stronger than the loaders (it breaks stone too, not hard rock). Z/X slew the
## house, R/F the boom up and down, T/G the stick out and in, the right mouse button curls the bucket in (digging as
## it goes when it's in the ground), the left opens it (it pours out: over the tip truck's tray, into the truck).
## W/S and A/D drive its tracks. You sit in the cab; your view slews with the house. In co-op the host's game runs it.
## Owned by the voxel session.

const SLEW_RATE := 0.7          # rad/s
const BOOM_RATE := 0.45
const STICK_RATE := 0.65
const CURL_RATE := 1.1
const BOOM_MIN := -0.7
const BOOM_MAX := 1.0
const STICK_MIN := -2.5         # folded right in (rad from the boom's line)
const STICK_MAX := -0.3
const CURL_MIN := -1.4          # open (pouring)
const CURL_MAX := 1.2           # curled in (holding)
const POUR_FROM := -0.5
const CAPACITY := 420
const HARDEST := 3              # soil, clay, stone
const BITE_R := 0.28
const BITE_EVERY := 0.1
const POUR_RATE := 400.0
const BOOM_LEN := 2.6
const STICK_LEN := 1.7
const BOOM_PIVOT := Vector3(0.3, 0.55, -0.75)   # on the house

var slew := 0.0
var boom := 0.3
var stick := -1.3
var curl := 0.4
var slew_cmd := 0.0
var boom_cmd := 0.0
var stick_cmd := 0.0
var curl_cmd := 0.0
var bucket := {}
var load_n := 0
var _bite_t := 0.0
var _pour_acc := 0.0
var _house: Node3D
var _boom: Node3D
var _stick: Node3D
var _bucket: Node3D
var _lump: MeshInstance3D

func _init() -> void:
	kind = "excavator"
	length = 2.8
	width = 2.1
	max_speed = 1.2
	accel = 1.0
	turn_rate = 0.8
	max_climb = deg_to_rad(30.0)
	step_up = 0.36
	seat = Vector3(-0.55, 0.45, -0.25)          # (on the house)

func _build() -> void:
	super()
	var yellow := Color8(236, 178, 36)
	var dark := Color8(36, 36, 40)
	for sx in [-1.0, 1.0]:
		_box(self, Vector3(0.5, 0.55, 2.8), Vector3(sx * 0.8, 0.28, 0), dark, 0.4)
	_box(self, Vector3(1.0, 0.25, 1.0), Vector3(0, 0.6, 0), Color8(60, 60, 64), 0.5)
	_house = Node3D.new()
	_house.position = Vector3(0, 0.7, 0)
	add_child(_house)
	_box(_house, Vector3(2.0, 0.7, 2.2), Vector3(0, 0.35, 0.2), yellow)
	_box(_house, Vector3(2.0, 0.6, 0.5), Vector3(0, 0.4, 1.2), Color8(60, 60, 64), 0.5)       # the counterweight
	_box(_house, Vector3(0.85, 1.2, 1.0), Vector3(-0.55, 1.3, -0.35), yellow)                 # the cab
	_box(_house, Vector3(0.8, 0.6, 0.04), Vector3(-0.55, 1.45, -0.86), Color8(120, 160, 190), 0.8)
	_boom = Node3D.new()
	_boom.position = BOOM_PIVOT
	_house.add_child(_boom)
	_box(_boom, Vector3(0.3, 0.4, BOOM_LEN), Vector3(0, 0, -BOOM_LEN * 0.5), yellow)
	_stick = Node3D.new()
	_stick.position = Vector3(0, 0, -BOOM_LEN)
	_boom.add_child(_stick)
	_box(_stick, Vector3(0.24, 0.3, STICK_LEN), Vector3(0, 0, -STICK_LEN * 0.5), yellow)
	_bucket = Node3D.new()
	_bucket.position = Vector3(0, 0, -STICK_LEN)
	_stick.add_child(_bucket)
	var steel := Color8(90, 90, 96)
	_box(_bucket, Vector3(0.7, 0.05, 0.5), Vector3(0, -0.25, -0.2), steel, 0.6)
	_box(_bucket, Vector3(0.7, 0.5, 0.05), Vector3(0, 0, 0.05), steel, 0.6)
	for sx in [-1.0, 1.0]:
		_box(_bucket, Vector3(0.05, 0.45, 0.5), Vector3(sx * 0.35, -0.05, -0.2), steel, 0.6)
	_lump = _box(_bucket, Vector3(0.6, 0.35, 0.45), Vector3(0, -0.07, -0.18), Color8(122, 86, 52), 0.0)
	_lump.visible = false

## The bucket's teeth in the world
func edge() -> Vector3:
	return _bucket.global_transform * Vector3(0, -0.25, -0.45)

func seat_world() -> Vector3:
	return _house.global_transform * seat

func view_yaw() -> float:
	return yaw + slew

func _pose_tool() -> void:
	if _house == null:
		return
	_house.rotation.y = slew
	_boom.rotation.x = boom
	_stick.rotation.x = stick
	_bucket.rotation.x = curl
	_lump.visible = load_n > 0
	if load_n > 0:
		_lump.scale = Vector3(1.0, clampf(float(load_n) / CAPACITY, 0.15, 1.0), 1.0)

func read_input() -> void:
	super()
	slew_cmd = float(Input.is_physical_key_pressed(KEY_X)) - float(Input.is_physical_key_pressed(KEY_Z))
	boom_cmd = float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))
	stick_cmd = float(Input.is_physical_key_pressed(KEY_T)) - float(Input.is_physical_key_pressed(KEY_G))
	curl_cmd = float(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) - float(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))

func stop_cmds() -> void:
	super()
	slew_cmd = 0.0
	boom_cmd = 0.0
	stick_cmd = 0.0
	curl_cmd = 0.0

func keys() -> String:
	return "W/S A/D tracks   Z/X slew   R/F boom   T/G stick out/in   right mouse: curl in (dig)   left mouse: open (pour; over the truck: in it)   E get off"

func status() -> String:
	return "Bucket %d%%" % int(100.0 * load_n / CAPACITY) + ("   " + blocked if blocked != "" else "")

func _tool(dt: float) -> void:
	slew = wrapf(slew - slew_cmd * SLEW_RATE * dt, -PI, PI)
	boom = clampf(boom + boom_cmd * BOOM_RATE * dt, BOOM_MIN, BOOM_MAX)
	stick = clampf(stick + stick_cmd * STICK_RATE * dt, STICK_MIN, STICK_MAX)
	curl = clampf(curl + curl_cmd * CURL_RATE * dt, CURL_MIN, CURL_MAX)
	_pose_tool()
	var tr: DsTerrain = site.terrain
	var e := edge()
	# digging: the teeth in the ground, the bucket curling in or being pulled in or down, room in it
	_bite_t += dt
	if _bite_t >= BITE_EVERY:
		_bite_t = 0.0
		var pulling := curl_cmd > 0.0 or stick_cmd < 0.0 or boom_cmd < 0.0
		if pulling and curl > POUR_FROM and load_n < CAPACITY and tr.contains(e) and e.y < tr.top_at(e.x, e.z) - 0.02:
			var got: Dictionary = tr.dig(e, BITE_R, HARDEST)
			var counts: PackedInt32Array = got.counts
			for m in counts.size():
				if counts[m] > 0:
					bucket[m] = int(bucket.get(m, 0)) + counts[m]
					load_n += counts[m]
			blocked = "Hard rock: too hard for the bucket" if int(got.n) == 0 and int(got.refused) > HARDEST else ""
	# pouring: opened, out it comes at the teeth (over the truck: in its tray)
	if curl < POUR_FROM and load_n > 0:
		var k := clampf((POUR_FROM - curl) / (POUR_FROM - CURL_MIN), 0.2, 1.0)
		_pour_acc += POUR_RATE * k * dt
		var n := int(_pour_acc)
		if n > 0:
			_pour_acc -= n
			var truck = site.machines.catcher(e, self)
			while n > 0 and load_n > 0:
				var m := _most()
				var take := mini(n, int(bucket[m]))
				var put: int = truck.take(m, take) if truck else site.blasts._dump_spread(e, m, take)
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
	return PackedFloat32Array([slew, boom, stick, curl, float(load_n)])

func net_take_more(f: PackedFloat32Array) -> void:
	if f.size() >= 5:
		slew = lerp_angle(slew, f[0], 0.5)
		boom = lerpf(boom, f[1], 0.5)
		stick = lerpf(stick, f[2], 0.5)
		curl = lerpf(curl, f[3], 0.5)
		load_n = int(f[4])

func _cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([slew_cmd, boom_cmd, stick_cmd, curl_cmd])

func _take_cmds_more(f: PackedFloat32Array) -> void:
	if f.size() >= 4:
		slew_cmd = clampf(f[0], -1.0, 1.0)
		boom_cmd = clampf(f[1], -1.0, 1.0)
		stick_cmd = clampf(f[2], -1.0, 1.0)
		curl_cmd = clampf(f[3], -1.0, 1.0)
