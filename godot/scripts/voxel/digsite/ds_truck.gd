class_name DsTruck
extends DsMachine
## The tip truck (stage 10), like the digger game's Truck: six wheels, it turns as it rolls (steered wheels), quicker
## than the rest but it won't climb as steep. A bucket poured over its tray (the Dingo's, the Bobcat's, the
## excavator's) fills the tray instead of the ground (DsMachines.catcher); R tips the tray up and out it pours behind,
## loose, in a pile (F lowers it). It hauls concrete supports down: parked by the site office, L loads it with them
## (paid for, $8 each); on foot at its back, G takes one into your backpack. In co-op the host's game runs it, as every
## machine; a guest's loading and taking go to the host as events and come back. Owned by the voxel session.

const CAPACITY := 2400          # blocks in the tray (4.7 m3)
const TIP_RATE := 0.45          # of the way up a second
const POUR_FROM := 0.45         # tipped this far, it pours ...
const POUR_RATE := 500.0        # ... this fast (blocks a second), at full tip
const PROPS_MOST := 12
const PROP_COST := 8
const TRAY := Vector3(1.8, 0.6, 2.0)     # the tray's size ...
const TRAY_AT := Vector3(0, 1.0, 0.75)   # ... its floor's middle, from the truck's middle

var tip := 0.0                  # the tray, 0 down .. 1 right up
var tip_cmd := 0.0
var tray_load := {}             # material -> blocks in the tray
var load_n := 0
var props := 0                  # concrete supports on it
var _pour_acc := 0.0
var _tray: Node3D
var _lump: MeshInstance3D
var _props_mesh: MeshInstance3D

func _init() -> void:
	kind = "tip truck"
	length = 4.6
	width = 2.0
	max_speed = 5.0
	accel = 2.2
	turn_rate = 0.9
	max_climb = deg_to_rad(22.0)
	step_up = 0.36
	seat = Vector3(-0.45, 0.85, -1.45)
	turn_needs_speed = true

func _build() -> void:
	super()
	var red := Color8(196, 40, 36)
	var dark := Color8(36, 36, 40)
	for z in [-1.6, 0.55, 1.5]:
		for sx in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.48
			cm.bottom_radius = 0.48
			cm.height = 0.36
			w.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = dark
			w.material_override = m
			w.rotation.z = PI * 0.5
			w.position = Vector3(sx * 0.85, 0.48, z)
			add_child(w)
	_box(self, Vector3(1.4, 0.3, 4.4), Vector3(0, 0.8, 0), Color8(60, 60, 64), 0.5)
	# the cab at the front: windows, the seat on the left
	_box(self, Vector3(2.0, 1.4, 1.3), Vector3(0, 1.65, -1.55), red)
	_box(self, Vector3(1.9, 0.6, 0.04), Vector3(0, 2.0, -2.21), Color8(120, 160, 190), 0.8)
	# the tray: hinged at its back
	_tray = Node3D.new()
	_tray.position = Vector3(0, TRAY_AT.y, TRAY_AT.z + TRAY.z * 0.5)
	add_child(_tray)
	var grey := Color8(150, 150, 150)
	_box(_tray, Vector3(TRAY.x, 0.08, TRAY.z), Vector3(0, 0, -TRAY.z * 0.5), grey, 0.5)
	for sx in [-1.0, 1.0]:
		_box(_tray, Vector3(0.06, TRAY.y, TRAY.z), Vector3(sx * TRAY.x * 0.5, TRAY.y * 0.5, -TRAY.z * 0.5), grey, 0.5)
	_box(_tray, Vector3(TRAY.x, TRAY.y + 0.2, 0.06), Vector3(0, TRAY.y * 0.5 + 0.1, -TRAY.z), grey, 0.5)
	_lump = _box(_tray, Vector3(TRAY.x - 0.12, 0.5, TRAY.z - 0.1), Vector3(0, 0.25, -TRAY.z * 0.5), Color8(122, 86, 52), 0.0)
	_lump.visible = false
	_props_mesh = _box(_tray, Vector3(0.9, 0.3, 1.6), Vector3(0, 0.2, -TRAY.z * 0.5), DsMats.COL[DsMats.CONCRETE], 0.0)
	_props_mesh.visible = false

## Whether a point's over the tray (a bucket pouring there fills it)
func over_tray(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	var t := TRAY_AT
	return absf(l.x - t.x) < TRAY.x * 0.5 + 0.1 and absf(l.z - t.z) < TRAY.z * 0.5 + 0.1 and l.y > t.y - 0.2 and l.y < t.y + TRAY.y + 2.0 and tip < 0.2

## Blocks of m poured in (a bucket over it): -> how many fitted
func take(m: int, n: int) -> int:
	var k := mini(n, CAPACITY - load_n)
	if k <= 0:
		return 0
	tray_load[m] = int(tray_load.get(m, 0)) + k
	load_n += k
	return k

## Where it pours out, tipped: behind the tray
func spout() -> Vector3:
	return global_transform * Vector3(0, 0.5, TRAY_AT.z + TRAY.z * 0.5 + 0.5)

func _pose_tool() -> void:
	if _tray == null:
		return
	_tray.rotation.x = tip * 0.9
	_lump.visible = load_n > 0
	if load_n > 0:
		var k := clampf(float(load_n) / CAPACITY, 0.1, 1.0)
		_lump.scale = Vector3(1.0, k, 1.0)
		_lump.position.y = 0.25 * k
	_props_mesh.visible = props > 0 and load_n == 0

func read_input() -> void:
	super()
	tip_cmd = float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))

func stop_cmds() -> void:
	super()
	tip_cmd = 0.0

func keys() -> String:
	return "W/S drive   A/D steer   R/F tip the tray up/down   L load concrete supports (by the site office)   E get off"

func status() -> String:
	var s := "Tray %d%%" % int(100.0 * load_n / CAPACITY)
	if props > 0:
		s += "   %d concrete supports on it" % props
	return s + ("   " + blocked if blocked != "" else "")

func _tool(dt: float) -> void:
	tip = clampf(tip + tip_cmd * TIP_RATE * dt, 0.0, 1.0)
	_pose_tool()
	if tip > POUR_FROM and load_n > 0:
		var k := (tip - POUR_FROM) / (1.0 - POUR_FROM)
		_pour_acc += POUR_RATE * k * dt
		var n := int(_pour_acc)
		if n <= 0:
			return
		_pour_acc -= n
		var at := spout()
		while n > 0 and load_n > 0:
			var m := _most()
			var put: int = site.blasts._dump_spread(at, m, mini(n, int(tray_load[m])))
			if put <= 0:
				break
			tray_load[m] = int(tray_load[m]) - put
			if int(tray_load[m]) <= 0:
				tray_load.erase(m)
			load_n -= put
			n -= put

func _most() -> int:
	var best := DsMats.DIRT
	var bn := -1
	for m in tray_load:
		if int(tray_load[m]) > bn:
			best = int(m)
			bn = int(tray_load[m])
	return best

func net_more() -> PackedFloat32Array:
	return PackedFloat32Array([tip, float(load_n), float(props)])

func net_take_more(f: PackedFloat32Array) -> void:
	if f.size() >= 3:
		tip = lerpf(tip, f[0], 0.5)
		load_n = int(f[1])
		props = int(f[2])

func _cmds_more() -> PackedFloat32Array:
	return PackedFloat32Array([tip_cmd])

func _take_cmds_more(f: PackedFloat32Array) -> void:
	if f.size() >= 1:
		tip_cmd = clampf(f[0], -1.0, 1.0)
