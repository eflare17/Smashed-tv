class_name MineShip
extends Node3D
## The digging ship (the owner, 23 Oct: the Motherload-style mine): drives along the floor of what's dug, drills left,
## right and down (slower in harder rock, a boulder only with a good enough drill), flies up on its thrusters, falls,
## and takes damage landing hard. Seen side-on: x across, y up, the ground's front at z = 0.5. Its look changes with
## each upgrade (the drill's bit, the fuel tanks, the cargo bay, the hull's plating, the lamps). The mine (VoxelMine)
## runs it, pays for the fuel and does the rest. Owned by the voxel session.

signal drilled(x: int, r: int, t: int)
signal bumped(speed: float, landing: bool)

const HALF := 0.4               # half the ship's size (it fits a 1 m tunnel)
const GRAV := 12.0
const THRUST := 27.0
const DRIVE := 5.2              # driving speed on the ground ...
const FLY := 4.2                # ... and steering in the air
const ACC_G := 30.0
const ACC_A := 9.0
const MAX_UP := 7.0
const MAX_FALL := 17.0
const FALL_SAFE := 8.8          # landing faster than this hurts
const BUMP_SAFE := 6.0          # hitting a wall faster than this hurts
const HULL_COLS := [Color8(240, 186, 40), Color8(50, 168, 160), Color8(196, 52, 50), Color8(62, 66, 76)]
const DRILL_COLS := [Color8(170, 172, 180), Color8(196, 128, 70), Color8(240, 200, 60), Color8(170, 240, 255)]

var ground: MineGround
var p := Vector2()
var v := Vector2()
var face := 1                   # 1 right, -1 left
var grounded := false
var thrusting := false
var driving := false
var drilling := false
var drill_tile := Vector2i()
var drill_dir := Vector2i()
var drill_k := 0.0
var drill_secs := 1.0
var drill_from := Vector2()
var drill_to := Vector2()
var drill_level := 0            # the drill's upgrade level (a boulder needs at least its own)
var drill_power := 1.0
var grav_k := 1.0               # (the mushroom caves make it floaty)
var refused := ""               # why a drill just now didn't start ("too_hard", "need2" ...), or ""
var hardness := 0.0             # the tile being drilled's (the whine's pitch)
var _drill_down := 0.0          # 0 drill forward .. 1 drill down
var _spin := 0.0
var _model: Node3D
var _drill_piv: Node3D
var _drill_bit: Node3D
var _flames: Array[MeshInstance3D] = []
var lamp: OmniLight3D
var spot: SpotLight3D

func _ready() -> void:
	lamp = OmniLight3D.new()
	lamp.light_color = Color8(255, 236, 200)
	lamp.position = Vector3(0, 0.3, 1.1)
	lamp.shadow_enabled = false
	add_child(lamp)
	spot = SpotLight3D.new()
	spot.light_color = Color8(255, 240, 210)
	spot.spot_angle = 38.0
	spot.light_energy = 2.2
	add_child(spot)

# ---------------------------------------------------------------- moving

## One step: ix the steering (-1 .. 1), up the thrusters, down drill down; fuel: whether there's any left.
func step(dt: float, ix: float, up: bool, down: bool, fuel: bool) -> void:
	refused = ""
	thrusting = false
	driving = false
	if drilling:
		drill_k += dt / drill_secs
		var e := clampf(drill_k, 0.0, 1.0)
		p = drill_from.lerp(drill_to, e)
		if drill_k >= 1.0:
			drilling = false
			p = drill_to
			v = Vector2.ZERO
			drilled.emit(drill_tile.x, drill_tile.y, ground.at(drill_tile.x, drill_tile.y))
		_pose(dt)
		return
	if not fuel:
		up = false
		down = false
		ix = 0.0
	if absf(ix) > 0.1:
		face = 1 if ix > 0.0 else -1
	if grounded:
		if down and absf(ix) < 0.5:
			_try_drill(Vector2i(0, 1))
		elif absf(ix) > 0.5:
			var s := 1 if ix > 0.0 else -1
			var tx := floori(p.x + s * (HALF + 0.06))
			var tr := floori(-p.y)
			var edge := float(tx) if s > 0 else float(tx + 1)
			if ground.solid_at(tx, tr) and absf(p.x + s * HALF - edge) < 0.08:
				_try_drill(Vector2i(s, 0))
	if drilling:
		_pose(dt)
		return
	var target := ix * (DRIVE if grounded else FLY)
	v.x = move_toward(v.x, target, (ACC_G if grounded else ACC_A) * dt)
	if up:
		v.y += THRUST * dt
		thrusting = true
	v.y -= GRAV * grav_k * dt
	v.y = clampf(v.y, -MAX_FALL * (0.5 + 0.5 * grav_k), MAX_UP)
	driving = grounded and absf(ix) > 0.1
	var hx := _move(0, v.x * dt)
	var falling := v.y < 0.0
	var hy := _move(1, v.y * dt)
	p.y = minf(p.y, 40.0)
	grounded = _on_floor()
	if hy > FALL_SAFE and falling:
		bumped.emit(hy, true)
	elif hy > 2.0 and falling:
		bumped.emit(hy, false)
	if hx > BUMP_SAFE:
		bumped.emit(hx, false)
	_pose(dt)

func _try_drill(d: Vector2i) -> void:
	var tx := floori(p.x) if d.y == 1 else floori(p.x + d.x * (HALF + 0.06))
	var tr := floori(-(p.y - HALF) + 0.02) if d.y == 1 else floori(-p.y)
	var t := ground.at(tx, tr)
	if not MineTiles.solid(t):
		return
	var h := MineTiles.hardness(t, ground.base_at(tx, tr))
	if h < 0.0:
		refused = "too_hard"
		return
	var need := int(MineTiles.info(t).need)
	if need > drill_level:
		refused = "need%d" % need
		return
	drilling = true
	hardness = h
	drill_tile = Vector2i(tx, tr)
	drill_dir = d
	drill_k = 0.0
	drill_secs = maxf(0.12, h / drill_power)
	drill_from = p
	if d.y == 1:
		drill_to = Vector2(tx + 0.5, -tr - 1.0 + HALF + 0.002)
	else:
		drill_to = Vector2(tx + 0.5, p.y)
	v = Vector2.ZERO

## Moves along one axis (0 x, 1 y) and out of any solid tile it ran into; returns how fast it hit (0: nothing).
func _move(axis: int, d: float) -> float:
	if absf(d) < 1e-7:
		return 0.0
	if axis == 0:
		p.x += d
	else:
		p.y += d
	var x0 := floori(p.x - HALF)
	var x1 := floori(p.x + HALF - 1e-5)
	var r0 := floori(-(p.y + HALF))
	var r1 := floori(-(p.y - HALF) - 1e-5)
	var hit := false
	var lim := INF if d > 0.0 else -INF
	for r in range(r0, r1 + 1):
		for x in range(x0, x1 + 1):
			if not ground.solid_at(x, r):
				continue
			hit = true
			if axis == 0:
				lim = minf(lim, float(x)) if d > 0.0 else maxf(lim, float(x + 1))
			else:
				lim = minf(lim, float(-r - 1)) if d > 0.0 else maxf(lim, float(-r))
	if not hit:
		return 0.0
	var s := 0.0
	if axis == 0:
		p.x = lim - HALF - 0.001 if d > 0.0 else lim + HALF + 0.001
		s = absf(v.x)
		v.x = 0.0
	else:
		p.y = lim - HALF - 0.001 if d > 0.0 else lim + HALF + 0.001
		s = absf(v.y)
		v.y = 0.0
	return s

func _on_floor() -> bool:
	var r := floori(-(p.y - HALF - 0.03))
	for x in range(floori(p.x - HALF + 0.02), floori(p.x + HALF - 0.02) + 1):
		if ground.solid_at(x, r):
			return true
	return false

## Put somewhere (a teleport, the tow truck): stopped, not drilling.
func place(at: Vector2) -> void:
	p = at
	v = Vector2.ZERO
	drilling = false
	grounded = false
	_pose(0.0)

# ---------------------------------------------------------------- the look

func _pose(dt: float) -> void:
	position = Vector3(p.x, p.y, 0.0)
	if _model == null:
		return
	_model.rotation.y = 0.0 if face > 0 else PI
	var want := 1.0 if (drilling and drill_dir.y == 1) else 0.0
	_drill_down = move_toward(_drill_down, want, dt * 8.0)
	if drilling:
		_spin += dt * 30.0
	_drill_piv.position = Vector3(lerpf(0.33, 0.0, _drill_down), lerpf(-0.12, -0.34, _drill_down), 0.0)
	_drill_piv.rotation.z = lerpf(0.0, -PI * 0.5, _drill_down)
	_drill_bit.rotation.x = _spin
	# a tilt with the speed in the air, a judder drilling
	_model.rotation.z = (-v.x * 0.04 * face if not grounded else 0.0) + (sin(_spin * 1.7) * 0.03 if drilling else 0.0)
	for f in _flames:
		f.visible = thrusting
		if thrusting:
			f.scale = Vector3(1, randf_range(0.7, 1.25), 1)
	spot.position = Vector3(0.3 * face, 0.0, 0.6)
	var aim := Vector3(face, -0.5, -0.25).normalized() if not (drilling and drill_dir.y == 1) else Vector3(0.05 * face, -1, -0.2).normalized()
	spot.look_at(spot.global_position + aim, Vector3.UP if absf(aim.y) < 0.95 else Vector3.FORWARD)

func _m(c: Color, rough := 0.6, metal := 0.3, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m

func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, r0: float, r1: float, h: float, at: Vector3, rot: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r0
	cm.bottom_radius = r1
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = m
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi

## The ship built for its upgrades ({drill, tank, cargo, hull, lights}: levels 0..3).
func build(upg: Dictionary) -> void:
	if _model:
		_model.queue_free()
	_flames.clear()
	_model = Node3D.new()
	add_child(_model)
	var dl := int(upg.get("drill", 0))
	var tl := int(upg.get("tank", 0))
	var cl := int(upg.get("cargo", 0))
	var hl := int(upg.get("hull", 0))
	var ll := int(upg.get("lights", 0))
	drill_level = dl
	drill_power = MineShop.k("drill", dl)
	var hull := _m(HULL_COLS[hl], 0.5, 0.35)
	var dark := _m(Color8(40, 40, 44), 0.8, 0.2)
	var steel := _m(Color8(150, 154, 162), 0.35, 0.8)
	# the tracks and their wheels
	_box(_model, Vector3(0.8, 0.16, 0.56), Vector3(0, -0.32, 0), dark)
	for wx in [-0.27, 0.0, 0.27]:
		_cyl(_model, 0.075, 0.075, 0.6, Vector3(wx, -0.32, 0), Vector3(PI * 0.5, 0, 0), steel)
	# the body, the cockpit
	_box(_model, Vector3(0.64, 0.34, 0.5), Vector3(-0.03, -0.07, 0), hull)
	_box(_model, Vector3(0.5, 0.06, 0.52), Vector3(-0.06, 0.12, 0), hull)
	var glass := _m(Color(0.5, 0.8, 1.0), 0.1, 0.1, 0.25)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.3
	dome.mesh = sm
	dome.material_override = glass
	dome.position = Vector3(0.1, 0.18, 0)
	_model.add_child(dome)
	# the hull's plating: plates at Armoured, gold trim on the Tank
	if hl >= 1:
		_box(_model, Vector3(0.66, 0.04, 0.54), Vector3(-0.03, -0.22, 0), _m(HULL_COLS[hl].darkened(0.3), 0.5, 0.5))
	if hl >= 2:
		for px in [-0.22, 0.0, 0.2]:
			_box(_model, Vector3(0.16, 0.2, 0.03), Vector3(px, -0.07, 0.26), _m(HULL_COLS[hl].darkened(0.45), 0.4, 0.6))
	if hl >= 3:
		_box(_model, Vector3(0.66, 0.025, 0.535), Vector3(-0.03, 0.03, 0), _m(Color8(230, 190, 70), 0.3, 0.9))
	# the drill: its bit bigger and finer each level
	_drill_piv = Node3D.new()
	_model.add_child(_drill_piv)
	_drill_bit = Node3D.new()
	_drill_piv.add_child(_drill_bit)
	var dm := _m(DRILL_COLS[dl], 0.3, 0.9, 0.8 if dl == 3 else 0.0)
	var dh := 0.32 + 0.05 * dl
	var dr := 0.15 + 0.02 * dl
	var cone := _cyl(_drill_bit, 0.0, dr, dh, Vector3(dh * 0.5 + 0.04, 0, 0), Vector3(0, 0, -PI * 0.5), dm)
	for k in 3:
		_box(cone, Vector3(dr * 1.5, 0.02, 0.03), Vector3(0, -dh * 0.25 + k * dh * 0.18, 0), _m(DRILL_COLS[dl].darkened(0.35), 0.4, 0.8)).rotation.y = k * 1.1
	_cyl(_drill_piv, 0.07, 0.07, 0.1, Vector3(0.02, 0, 0), Vector3(0, 0, PI * 0.5), steel)
	# the fuel tanks: a jerry can, then tanks along the side
	var red := _m(Color8(200, 40, 30), 0.5, 0.3)
	if tl == 0:
		_box(_model, Vector3(0.12, 0.16, 0.08), Vector3(-0.3, 0.02, 0.3), red)
	else:
		for k in mini(tl, 2):
			_cyl(_model, 0.06, 0.06, 0.34 + tl * 0.06, Vector3(-0.06, -0.12 + k * 0.13, 0.29), Vector3(0, 0, PI * 0.5), red)
		if tl >= 3:
			_cyl(_model, 0.07, 0.07, 0.5, Vector3(-0.1, 0.22, -0.12), Vector3(0, 0, PI * 0.5), red)
	# the cargo bay on its back
	var crate := _m(Color8(130, 96, 60), 0.85, 0.0)
	var cs := Vector3(0.18 + 0.05 * cl, 0.1 + 0.05 * cl, 0.36 + 0.03 * cl)
	_box(_model, cs, Vector3(-0.3 - 0.02 * cl, 0.15 + cs.y * 0.5, -0.02), crate)
	# the lamps on its nose
	var lampm := _m(Color8(255, 240, 180), 0.2, 0.0, 2.5)
	for k in ll + 1:
		_box(_model, Vector3(0.06, 0.06, 0.08), Vector3(0.3, 0.08 + k * 0.07, 0.18 - (k % 2) * 0.36), lampm)
	lamp.omni_range = MineShop.k("lights", ll)
	lamp.light_energy = 1.3 + ll * 0.2
	spot.spot_range = MineShop.k("lights", ll) * 1.5
	# the thrusters underneath at the back, their flames
	var flame := _m(Color8(255, 150, 40), 0.5, 0.0, 4.0)
	flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame.albedo_color.a = 0.85
	for zx in [-0.17, 0.17]:
		_cyl(_model, 0.05, 0.07, 0.1, Vector3(-0.28, -0.22, zx), Vector3.ZERO, steel)
		var f := _cyl(_model, 0.07, 0.0, 0.32, Vector3(-0.28, -0.42, zx), Vector3.ZERO, flame)
		f.visible = false
		_flames.append(f)
	_pose(0.0)
