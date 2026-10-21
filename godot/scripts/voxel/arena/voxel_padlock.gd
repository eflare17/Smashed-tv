class_name VoxelPadlock
extends Node3D
## A spin-dial combination padlock (the owner, 21 Oct, Stage 3: "a physical spin-dial combination padlock on each
## chest (no typed password)"): a brass body with four number wheels along its front and a steel shackle. Real size
## (about 6 cm): one hangs on a chest's hasp; another, held up in front of the camera, is the one you dial
## (VoxelLockView). Each wheel turns a digit at a time with a click; open, the shackle stands up and swings aside.
## Owned by the voxel session.

const W := 0.056                # body width ...
const H := 0.05                 # ... height ...
const D := 0.024                # ... depth
const DIALS := 4
const DIAL_R := 0.0085          # a wheel's radius ...
const DIAL_W := 0.0105          # ... and width
const BRASS := Color8(201, 160, 64)
const STEEL := Color8(185, 188, 196)
const WHEEL := Color8(40, 40, 44)
const TURN_SPEED := 14.0        # how fast a wheel catches up with its digit (1/s)

var dials := PackedInt32Array([0, 0, 0, 0])
var open := false
var _wheels: Array[Node3D] = []
var _shown := PackedFloat32Array([0, 0, 0, 0])   # each wheel's angle now, in digits (eases to dials)
var _shackle: Node3D
var _k := 0.0                   # 0 shut .. 1 open
var digit_labels := true        # (the little one on the chest: no digits, too small to read)

func _ready() -> void:
	_build()

## Turns wheel i by d digits (wrapping 0-9).
func spin(i: int, d: int) -> void:
	dials[i] = posmod(dials[i] + d, 10)

func code() -> String:
	var s := ""
	for v in dials:
		s += str(v)
	return s

func set_code(c: String) -> void:
	for i in mini(DIALS, c.length()):
		dials[i] = int(c[i])
	for i in DIALS:
		_shown[i] = dials[i]

## The wheels spun to a random code (hiding the code just locked).
func scramble() -> void:
	for i in DIALS:
		dials[i] = randi() % 10

## Where wheel i is (world), for picking it with the mouse.
func wheel_pos(i: int) -> Vector3:
	return _wheels[i].global_position if i < _wheels.size() else global_position

func shackle_pos() -> Vector3:
	return global_transform * Vector3(0, H * 0.5 + 0.02, 0)

func _process(dt: float) -> void:
	for i in mini(DIALS, _wheels.size()):
		# the shortest way round to the digit, eased
		var want := float(dials[i])
		var diff := fposmod(want - _shown[i] + 5.0, 10.0) - 5.0
		_shown[i] += diff * minf(1.0, dt * TURN_SPEED)
		_wheels[i].rotation.x = _shown[i] * TAU / 10.0
	var goal := 1.0 if open else 0.0
	if _k != goal:
		_k = move_toward(_k, goal, dt * 6.0)
		# up out of the body first, then swung round on its left leg
		var up := minf(1.0, _k * 2.0)
		var swing := maxf(0.0, _k * 2.0 - 1.0)
		_shackle.position = Vector3(-W * 0.28, H * 0.5 + 0.012 * up, 0)
		_shackle.rotation.y = -PI * 0.5 * swing

func _mat(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m

func _build() -> void:
	var brass := _mat(BRASS, 0.85, 0.3)
	var steel := _mat(STEEL, 0.9, 0.22)
	var dark := _mat(WHEEL, 0.3, 0.55)
	# the body (its middle at the origin)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W, H, D)
	body.mesh = bm
	body.material_override = brass
	add_child(body)
	# the shackle: a U of steel, its legs in the body; the pivot on the left leg
	_shackle = Node3D.new()
	_shackle.position = Vector3(-W * 0.28, H * 0.5, 0)
	add_child(_shackle)
	var span := W * 0.56
	var thick := 0.0065
	var leg_h := 0.018
	for x in [0.0, span]:
		var leg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = thick * 0.5
		cm.bottom_radius = thick * 0.5
		cm.height = leg_h
		cm.radial_segments = 12
		leg.mesh = cm
		leg.material_override = steel
		leg.position = Vector3(x, leg_h * 0.5 - 0.004, 0)
		_shackle.add_child(leg)
	# the arc over the top: short pieces round a half circle
	var segs := 10
	var rr := span * 0.5
	for k in segs:
		var a0 := PI * float(k) / segs
		var a1 := PI * float(k + 1) / segs
		var p0 := Vector3(rr - cos(a0) * rr, sin(a0) * rr, 0)
		var p1 := Vector3(rr - cos(a1) * rr, sin(a1) * rr, 0)
		var piece := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = thick * 0.5
		pm.bottom_radius = thick * 0.5
		pm.height = p0.distance_to(p1) + thick * 0.3
		pm.radial_segments = 10
		piece.mesh = pm
		piece.material_override = steel
		piece.position = (p0 + p1) * 0.5 + Vector3(0, leg_h - 0.004, 0)
		piece.rotation.z = atan2(p1.y - p0.y, p1.x - p0.x) - PI * 0.5
		_shackle.add_child(piece)
	# the four wheels along the front, half sunk into the body, a little window above each
	var gap := (W - DIALS * DIAL_W) / (DIALS + 1)
	for i in DIALS:
		var wheel := Node3D.new()
		wheel.position = Vector3(-W * 0.5 + gap + DIAL_W * 0.5 + i * (DIAL_W + gap), -H * 0.12, D * 0.5 - DIAL_R * 0.45)
		add_child(wheel)
		_wheels.append(wheel)
		var cyl := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = DIAL_R
		cm2.bottom_radius = DIAL_R
		cm2.height = DIAL_W
		cm2.radial_segments = 20
		cyl.mesh = cm2
		cyl.material_override = dark
		cyl.rotation.z = PI * 0.5      # (its axis along x)
		wheel.add_child(cyl)
		# ridges round the edge, for grip
		for r in 10:
			var a := (r + 0.5) * TAU / 10.0
			var ridge := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(DIAL_W * 1.02, DIAL_R * 0.18, DIAL_R * 0.18)
			ridge.mesh = rm
			ridge.material_override = dark
			ridge.position = Vector3(0, sin(a) * DIAL_R, cos(a) * DIAL_R)
			ridge.rotation.x = -a
			wheel.add_child(ridge)
		if digit_labels:
			for k in 10:
				# digit k faces out at k tenths of a turn (the wheel turned k tenths brings it to the front)
				var th := k * TAU / 10.0
				var l := Label3D.new()
				l.text = str(k)
				l.font_size = 48
				l.pixel_size = DIAL_R * 0.022
				l.outline_size = 0
				l.modulate = Color(0.95, 0.95, 0.9)
				l.position = Vector3(0, sin(th), cos(th)) * DIAL_R * 1.01
				l.rotation.x = -th
				l.double_sided = false
				l.no_depth_test = false
				wheel.add_child(l)
	# the line the digits are read at
	var mark := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(W * 0.96, 0.0012, 0.002)
	mark.mesh = mm
	mark.material_override = _mat(Color8(150, 30, 30), 0.0, 0.6)
	mark.position = Vector3(0, -H * 0.12 + DIAL_R * 0.62, D * 0.5 + 0.0008)
	add_child(mark)
	set_code(code())
