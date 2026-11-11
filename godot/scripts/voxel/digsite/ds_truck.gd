class_name DsTruck
extends DsMachine
## The tip truck (stage 10), like the digger game's Truck: six wheels, it turns as it rolls (steered wheels), quicker
## than the rest but it won't climb as steep. A bucket poured over its tray (the Dingo's, the Bobcat's, the
## excavator's) fills the tray instead of the ground (DsMachines.catcher); R tips the tray up and out it pours behind,
## loose, in a pile (F lowers it). It hauls concrete supports down: parked by the site office, L loads it with them
## (paid for, $8 each); on foot at its back, G takes one into your backpack. In co-op the host's game runs it, as every
## machine; a guest's loading and taking go to the host as events and come back. Owned by the voxel session.

const CAPACITY := 4000 * DsTerrain.MM  # mm in the tray (4000 blocks of 125 mm over a column: 8 m3)
const TIP_RATE := 0.45          # of the way up a second
const POUR_FROM := 0.45         # tipped this far, it pours ...
const POUR_RATE := 500.0 * DsTerrain.MM   # ... this fast (mm a second), at full tip
const PROPS_MOST := 12
const PROP_COST := 8
const TRAY := Vector3(2.4, 0.95, 4.6)    # the tray's size (across, high, long) ...
const TRAY_AT := Vector3(0, 1.28, 1.25)  # ... its floor's middle, from the truck's middle
# (the digger game's Truck: its tray hinged at its back, in its frame: x forward, y up)
const HINGE := Vector3(-3.55, 1.28, 0.0)
const TRAY_LONG := 4.6
const TRAY_HALF := 1.2
const TRAY_HIGH := 0.95

var tip := 0.0                  # the tray, 0 down .. 1 right up
var tip_cmd := 0.0
var tray_load := {}             # material -> mm in the tray
var load_n := 0
var props := 0                  # concrete supports on it
var _pour_acc := 0.0
var _tray: Node3D
var _lump: MeshInstance3D
var _props_mesh: MeshInstance3D
var _look: Node3D
var _wheels := []
var _shake: Node3D              # (its body and tray: what its engine shakes; not its wheels)
var _ram: DsRam
var _tip_was := 0.0
# its tipping ram (the owner, 9 Nov): stages sliding out of each other, from its chassis behind the cab to the top of
# the tray's front, as a real tipper's
const RAM_BASE := Vector3(1.38, 0.84, 0.0)
const RAM_TOP := Vector3(5.05, 0.5, 0.0)     # (in the tray's frame: out in front of its front wall, so tipped right
                                              # up the ram stays clear of it)
var _roll := 0.0

func _init() -> void:
	kind = "tip truck"
	tracked = false
	length = 7.6
	width = 2.5
	max_speed = 5.0
	accel = 2.2
	turn_rate = 0.9
	max_climb = deg_to_rad(22.0)
	step_up = 0.36
	seat = Vector3(0.5, 0.95, -2.4)
	pipe = Vector3(1.0, 2.6, -2.2)
	turn_needs_speed = true

func _build() -> void:
	super()
	(_body.get_child(0) as CollisionShape3D).position.y = 1.0
	_look = Node3D.new()
	_look.rotation.y = PI * 0.5
	add_child(_look)
	_shake = Node3D.new()
	_look.add_child(_shake)
	shake_node = _shake
	shake_idle = 0.0013
	shake_work = 0.0025
	shake_hz = 53.0
	var kit := DsKit.new()
	DsProps.truck_body(kit)
	_mesh(_shake, kit)
	var wk := DsKit.new()
	DsProps.wheel(wk, 0.34)
	var wide := DsKit.new()
	DsProps.wheel(wide, 0.56)
	var tyre := wk.mesh()
	var tyre2 := wide.mesh()
	for side in [-1.0, 1.0]:
		_wheel(tyre, Vector3(2.3, 0.6, side * 1.08), 0.6)
		_wheel(tyre2, Vector3(-1.5, 0.6, side * 0.98), 0.6)
		_wheel(tyre2, Vector3(-2.75, 0.6, side * 0.98), 0.6)
	_tray = Node3D.new()
	_tray.position = HINGE
	_shake.add_child(_tray)
	_ram = DsRam.make(_shake, 0.84, 0.16, 0.05, DsProps.CHARCOAL, 6, false)
	kit = DsKit.new()
	DsProps.truck_tray(kit, TRAY_LONG, TRAY_HALF, TRAY_HIGH)
	_mesh(_tray, kit)
	kit = DsKit.new()
	kit.prism([Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.32, 0.65), Vector2(0.0, 1.0), Vector2(-0.32, 0.65)], -0.5, 0.5, DsProps.DIRT)
	_lump = _mesh(_tray, kit)
	_lump.visible = false
	kit = DsKit.new()
	for k in 4:
		kit.box(Vector3(1.0 + k * 0.7, 0.3, 0.0), Vector3(0.3, 0.3, 1.8), DsProps.c("#b0b0aa"))
	_props_mesh = _mesh(_tray, kit)
	_props_mesh.visible = false

func _mesh(parent: Node3D, kit: DsKit) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = DsExcavator.mat()
	parent.add_child(m)
	return m

func _wheel(mesh: Mesh, at: Vector3, r: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = DsExcavator.mat()
	mi.position = at
	mi.basis = Basis.IDENTITY.scaled(Vector3(r, r, 1.0))
	_look.add_child(mi)
	_wheels.append([mi, r])

## Whether a point's over the tray (a bucket pouring there fills it)
func over_tray(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	var t := TRAY_AT
	return absf(l.x - t.x) < TRAY.x * 0.5 + 0.1 and absf(l.z - t.z) < TRAY.z * 0.5 + 0.1 and l.y > t.y - 0.2 and l.y < t.y + TRAY.y + 4.5 and tip < 0.2

## Blocks of m poured in (a bucket over it): -> how many fitted
var incoming := 0               # blocks falling into its tray from a bucket, not landed yet (DsMachine.let_go)

## Room in its tray, less what's already falling into it
func room() -> int:
	return maxi(0, CAPACITY - load_n - incoming)

func take(m: int, n: int) -> int:
	var k := mini(n, CAPACITY - load_n)
	if k <= 0:
		return 0
	tray_load[m] = int(tray_load.get(m, 0)) + k
	load_n += k
	return k

func fx_load() -> int:
	return load_n

func fx_pour_at() -> Vector3:
	return spout() + Vector3(0, 1.0, 0)

## Where it pours out, tipped: behind the tray
func spout() -> Vector3:
	return global_transform * Vector3(0, 0.5, TRAY_AT.z + TRAY.z * 0.5 + 0.7)

func _pose_tool() -> void:
	if _tray == null:
		return
	_tray.transform = Transform3D(Basis(Vector3.BACK, tip * 0.95), HINGE)
	if _ram:
		_ram.aim(RAM_BASE, _tray.transform * RAM_TOP)
	var f := float(load_n) / CAPACITY
	_lump.visible = f > 0.01
	if _lump.visible:
		var up := TRAY_HIGH * (0.25 + 0.9 * f)
		_lump.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(TRAY_LONG * 0.92, up, TRAY_HALF * 1.85)), Vector3(TRAY_LONG * 0.5, 0.08, 0.0))
	_props_mesh.visible = props > 0 and load_n == 0
	for w in _wheels:
		var r: float = w[1]
		(w[0] as Node3D).basis = Basis(Vector3.BACK, -_roll / r).scaled(Vector3(r, r, 1.0))

# (the tray going up or down: its pump's working)
func shake_effort() -> float:
	var moving := absf(tip - _tip_was) / maxf(get_process_delta_time(), 0.001)
	_tip_was = tip
	return 0.6 if moving > 0.01 else 0.0

func read_input() -> void:
	super()
	tip_cmd = float(Input.is_physical_key_pressed(KEY_R)) - float(Input.is_physical_key_pressed(KEY_F))

func stop_cmds() -> void:
	super()
	tip_cmd = 0.0

func keys() -> String:
	return "W/S drive   A/D steer   R/F tip the tray up/down\nL load concrete supports (by the site office)   V view   wheel zoom   E get off"

func status() -> String:
	var s := "Tray %d%%" % int(100.0 * load_n / CAPACITY)
	if props > 0:
		s += "   %d concrete supports on it" % props
	return s + ("   " + blocked if blocked != "" else "")

func _follow(dt: float) -> void:
	super(dt)
	_roll += speed * dt

func _tool(dt: float) -> void:
	_roll += speed * dt
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
			var put: int = let_go(at + Vector3(0, 1.2, 0), m, mini(n, int(tray_load[m])), null)
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
