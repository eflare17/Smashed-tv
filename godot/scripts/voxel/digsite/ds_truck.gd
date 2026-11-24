class_name DsTruck
extends DsMachine
## The tip truck (stage 10), like the digger game's Truck: six wheels, it turns as it rolls (steered wheels), quicker
## than the rest but it won't climb as steep. What a bucket pours over its tray (the Dingo's, the Bobcat's, the
## excavator's) are clods (DsDirt) that land in the tray, its floor and walls boxes to them, and are its load once
## they lie still there; badly aimed they go down its side (the dirt physics' stage 6). R tips the tray up and out it
## pours over the tail as clods, into a heap behind (F lowers it). It hauls concrete supports down: parked by the site office, L loads it with them
## (paid for, $8 each); on foot at its back, G takes one into your backpack. In co-op the host's game runs it, as every
## machine; a guest's loading and taking go to the host as events and come back. Owned by the voxel session.

const CAPACITY := 4000 * DsTerrain.MM  # mm in the tray (4000 blocks of 125 mm over a column: 8 m3)
const TIP_RATE := 0.45          # of the way up a second
const TIP_EASE := 4.0           # per second: its ram eases in and out (the dirt physics' stage 4)
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

var tip = 0.0                  # the tray, 0 down .. 1 right up
var tip_cmd = 0.0
var _v_tip = 0.0               # its ram, eased (-1 .. 1)
var tray_load = {}             # material -> mm in the tray
var load_n = 0
var props = 0                  # concrete supports on it
var caught = 0                 # (tests: mm of clods that landed in its tray and became its load)
var _pour_acc = 0.0
var _tray: Node3D
var _lump: MeshInstance3D
var _props_mesh: MeshInstance3D
var _look: Node3D
var _wheels = []
var _shake: Node3D              # (its body and tray: what its engine shakes; not its wheels)
var _ram: DsRam
var _tip_was = 0.0
# its tipping ram (the owner, 9 Nov): stages sliding out of each other, from its chassis behind the cab to the top of
# the tray's front, as a real tipper's
const RAM_BASE := Vector3(1.38, 0.84, 0.0)
const RAM_TOP := Vector3(5.05, 0.5, 0.0)     # (in the tray's frame: out in front of its front wall, so tipped right
                                              # up the ram stays clear of it)
var _roll = 0.0

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
	sway_k = 0.7                    # (long, on six wheels: it rocks less)

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
	var kit = DsKit.new()
	DsProps.truck_body(kit)
	_mesh(_shake, kit)
	var wk = DsKit.new()
	DsProps.wheel(wk, 0.34)
	var wide = DsKit.new()
	DsProps.wheel(wide, 0.56)
	var tyre = wk.mesh()
	var tyre2 = wide.mesh()
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
	var m = MeshInstance3D.new()
	m.mesh = kit.mesh()
	m.material_override = DsExcavator.mat()
	parent.add_child(m)
	return m

func _wheel(mesh: Mesh, at: Vector3, r: float) -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = DsExcavator.mat()
	mi.position = at
	mi.basis = Basis.IDENTITY.scaled(Vector3(r, r, 1.0))
	_look.add_child(mi)
	_wheels.append([mi, r])

## Whether a point's over the tray (a bucket pouring there fills it)
func over_tray(p: Vector3) -> bool:
	var l = global_transform.affine_inverse() * p
	var t = TRAY_AT
	return absf(l.x - t.x) < TRAY.x * 0.5 + 0.1 and absf(l.z - t.z) < TRAY.z * 0.5 + 0.1 and l.y > t.y - 0.2 and l.y < t.y + TRAY.y + 4.5 and tip < 0.2

## Its body for the clods: its chassis, up to the tray's floor (its cab's another: clod_boxes)
func body_box() -> Array:
	return [global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), Vector3(width * 0.5, 0.6, length * 0.5)]

## The tray as boxes, for the clods: its floor and four walls (front, left, right, tailgate), tipping with it; the
## tailgate's not there once it's tipping (kind 0), so what's in it runs out the back
func tray_boxes() -> Array:
	if _tray == null:
		return []
	var t = _tray.global_transform
	var out = []
	for b: Array in TRAY_BOXES:
		out.append([t * Transform3D(Basis.IDENTITY, b[0]), b[1], DsDirt.K_TRAY])
	if tip > 0.1:
		out[4][2] = 0
	return out

# (in the tray's own frame: x forward from its hinge, y up from its floor's underside, z across)
const WALL := 0.06
const TRAY_BOXES := [
	[Vector3(TRAY_LONG * 0.5, -0.12, 0.0), Vector3(TRAY_LONG * 0.5, 0.2, TRAY_HALF)],
	[Vector3(TRAY_LONG - WALL, 0.08 + TRAY_HIGH * 0.5, 0.0), Vector3(WALL, TRAY_HIGH * 0.5, TRAY_HALF)],
	[Vector3(TRAY_LONG * 0.5, 0.08 + TRAY_HIGH * 0.5, -TRAY_HALF + WALL), Vector3(TRAY_LONG * 0.5, TRAY_HIGH * 0.5, WALL)],
	[Vector3(TRAY_LONG * 0.5, 0.08 + TRAY_HIGH * 0.5, TRAY_HALF - WALL), Vector3(TRAY_LONG * 0.5, TRAY_HIGH * 0.5, WALL)],
	[Vector3(WALL, 0.08 + TRAY_HIGH * 0.5, 0.0), Vector3(WALL, TRAY_HIGH * 0.5, TRAY_HALF)]]

func clod_boxes() -> Array:
	var out = super()
	# (its cab, forward of the tray)
	out.append([global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.9, -2.55)), Vector3(width * 0.5, 0.7, 1.25), DsDirt.K_BODY])
	out.append_array(tray_boxes())
	return out

## Room in its tray (mm), less what's already falling into it or lying in it not yet its load: the clods in it and
## over it (DsMachine.let_go pours no more than this over it)
func room() -> int:
	var d: DsDirt = site.dirt
	var coming = 0
	if d != null and d.n > 0:
		coming = d.mass_in(global_transform * Transform3D(Basis.IDENTITY, TRAY_AT + Vector3(0, 2.6, 0)), Vector3(TRAY.x * 0.5 + 0.1, 2.8, TRAY.z * 0.5 + 0.1))
	return maxi(0, CAPACITY - load_n - coming)

## mm of m poured in (a bucket over it): -> how many fitted

func take(m: int, n: int) -> int:
	var k = mini(n, CAPACITY - load_n)
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
	var f = float(load_n) / CAPACITY
	_lump.visible = f > 0.01
	if _lump.visible:
		var up = TRAY_HIGH * (0.25 + 0.9 * f)
		_lump.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(TRAY_LONG * 0.92, up, TRAY_HALF * 1.85)), Vector3(TRAY_LONG * 0.5, 0.08, 0.0))
	_props_mesh.visible = props > 0 and load_n == 0
	for w in _wheels:
		var r: float = w[1]
		(w[0] as Node3D).basis = Basis(Vector3.BACK, -_roll / r).scaled(Vector3(r, r, 1.0))

# (its tray down on the chassis, or right up)
func at_stop() -> bool:
	return tip < 0.005 or tip > 0.995

# (the tray going up or down: its pump's working)
func shake_effort() -> float:
	var moving = absf(tip - _tip_was) / maxf(get_process_delta_time(), 0.001)
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
	var s = "Tray %d%%" % int(100.0 * load_n / CAPACITY)
	if props > 0:
		s += "   %d concrete supports on it" % props
	return s + ("   " + blocked if blocked != "" else "")

func _follow(dt: float) -> void:
	super(dt)
	_roll += track_v * dt

func _tool(dt: float) -> void:
	_roll += track_v * dt
	_v_tip = move_toward(_v_tip, tip_cmd, TIP_EASE * dt)
	tip = clampf(tip + _v_tip * TIP_RATE * dt, 0.0, 1.0)
	if (tip <= 0.0 and _v_tip < 0.0) or (tip >= 1.0 and _v_tip > 0.0):
		_v_tip = 0.0
	_pose_tool()
	# the clods lying still in the tray, under its rim, are its load (the dirt physics' stage 6: what a bucket pours
	# over it are clods that land in it, or don't), tipped or not (its floor's a box to them: they'd creep down it).
	# All of them: what's poured is no more than there's room for (room()), and a few thrown in over that heap it.
	if _tray:
		var took = _take_in(0, _tray.global_transform * Transform3D(Basis.IDENTITY, Vector3(TRAY_LONG * 0.5, 0.08 + TRAY_HIGH * 0.5, 0.0)), Vector3(TRAY_LONG * 0.5 - WALL, TRAY_HIGH * 0.5, TRAY_HALF - WALL), 1 << 30, tray_load, dt)
		load_n += took
		caught += took
	if tip > POUR_FROM and load_n > 0:
		var k = (tip - POUR_FROM) / (1.0 - POUR_FROM)
		_pour_acc += POUR_RATE * k * dt
		var n = int(_pour_acc)
		if n <= 0:
			return
		_pour_acc -= n
		# (out over the tray's tail as clods, sliding off its floor as it slopes, across its width)
		var tt = _tray.global_transform
		var d: DsDirt = site.dirt
		var back: Vector3 = -tt.basis.x
		var v0 = forward() * speed
		while n > 0 and load_n > 0:
			var m = _most()
			var w: float = d.randf01() if d else 0.5
			var u: float = d.randf01() if d else 0.5
			var at: Vector3 = tt * Vector3(-0.5 - 0.15 * u, 0.3 + 0.3 * u, (w - 0.5) * 2.0 * (TRAY_HALF - 0.3))
			var put: int = let_go(at, m, mini(n, int(tray_load[m])), null, v0 + back * (1.4 + 1.6 * k), 0.4, 0.1)
			if put <= 0:
				break
			tray_load[m] = int(tray_load[m]) - put
			if int(tray_load[m]) <= 0:
				tray_load.erase(m)
			load_n -= put
			n -= put

func _most() -> int:
	var best = DsMats.DIRT
	var bn = -1
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
