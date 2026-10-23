class_name MineShip
extends Node3D
## The digging ship (the owner, 23 Oct; the pixel mine: "really satisfying when drilling into the ground"): drives on
## what's dug, flies up on its thrusters, falls, and drills: push into the ground (or hold down) and its bit eats a
## ship-sized hole cell by cell in front of it (slower in harder rock; a boulder only with a good enough drill), the
## cracks spreading through the face, chips flying, the ship working its way in as the face gives. It pushes through
## loose rubble and sand (they're shoved aside) and water (it floats), and steps up small ledges. Landing hard hurts.
## Positions in metres (x across, y up), in front of the ground's quad (z > 0). Its look changes with each upgrade
## (the drill's bit, the fuel tanks, the cargo bay, the hull's plating, the lamps). The mine (VoxelMine) runs it,
## pays for the fuel, and takes what the drill brings up (dug). Owned by the voxel session.

signal dug(res: Dictionary, dir: Vector2)
signal bumped(speed: float, landing: bool)

const HALF := 0.4               # half the ship's size (it fits a 1 m tunnel)
const Z := 0.4                  # (in front of the ground's quad)
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
const BIT_DEPTH := 0.34         # how far ahead of the ship the drill works (metres)
const SPRAY := 0.22             # the share of what's drilled that flies off as chips
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
var drill_dir := Vector2.ZERO   # (1, 0) / (-1, 0) sideways, (0, -1) down
var drill_level := 0            # the drill's upgrade level (a boulder needs at least its own)
var drill_power := 1.0
var grav_k := 1.0               # (the mushroom caves make it floaty)
var refused := 0                # what the drill came up against just now: a level it needs, 100 nothing gets through
var hardness := 0.0             # how hard what it's drilling is (the whine's pitch, the sparks)
var broke := 0                  # cells it broke this step
var heat := 0.0                 # the bit's heat (glows in hard rock)
var wet := 0.0                  # how much of it's in water (0 .. 1)
var shove := 0                  # loose cells it pushed through this step
var _drill_down := 0.0          # 0 drill forward .. 1 drill down
var _spin := 0.0
var _rattle := 0.0
var _model: Node3D
var _drill_piv: Node3D
var _drill_bit: Node3D
var _drill_mat: StandardMaterial3D
var _flames: Array[MeshInstance3D] = []
var lamp: OmniLight3D
var spot: SpotLight3D

func _ready() -> void:
	lamp = OmniLight3D.new()
	lamp.light_color = Color8(255, 236, 200)
	lamp.position = Vector3(0, 0.3, 0.9)
	lamp.shadow_enabled = false
	add_child(lamp)
	spot = SpotLight3D.new()
	spot.light_color = Color8(255, 240, 210)
	spot.spot_angle = 38.0
	spot.light_energy = 2.2
	add_child(spot)

func _clear(at: Vector2) -> bool:
	return ground.count(at, Vector2(HALF, HALF), -1) == 0

# ---------------------------------------------------------------- moving

## One step: ix the steering (-1 .. 1), up the thrusters, down drill down; fuel: whether there's any left.
func step(dt: float, ix: float, up: bool, down: bool, fuel: bool) -> void:
	refused = 0
	broke = 0
	thrusting = false
	driving = false
	if not fuel:
		up = false
		down = false
		ix = 0.0
	_unstick()
	if absf(ix) > 0.1:
		face = 1 if ix > 0.0 else -1
	# the drill: down (on the ground), or sideways into what's in front
	var dir := Vector2.ZERO
	if down and absf(ix) < 0.5 and grounded:
		dir = Vector2(0, -1)
	elif absf(ix) > 0.5:
		var s := 1.0 if ix > 0.0 else -1.0
		if ground.count(p + Vector2(s * (HALF + 0.07), 0.04), Vector2(0.06, HALF - 0.1), -1) > 0:
			dir = Vector2(s, 0)
	drilling = dir != Vector2.ZERO
	drill_dir = dir if drilling else drill_dir
	if drilling:
		var c: Vector2
		var half: Vector2
		if dir.y < 0.0:
			c = p + Vector2(0, -(HALF + BIT_DEPTH * 0.5))
			half = Vector2(HALF + 0.07, BIT_DEPTH * 0.5)
		else:
			c = p + Vector2(dir.x * (HALF + BIT_DEPTH * 0.5), 0.03)
			half = Vector2(BIT_DEPTH * 0.5, HALF + 0.07)
		var cc := Vector2(c.x * MineGround.C, -c.y * MineGround.C + MineGround.SKY)
		var res: Dictionary = ground.sim.dig(cc.x, cc.y, half.x * MineGround.C, half.y * MineGround.C, 0.04 * MineGround.C,
			drill_power / BIT_DEPTH * (2.0 if dir.y < 0.0 else 1.0), drill_level, dt, SPRAY, dir.x, -dir.y, true)
		refused = int(res.refused)
		hardness = float(res.hard)
		broke = int(res.broke)
		if int(res.touched) > 0:
			heat = minf(1.0, heat + dt * hardness * 0.35 / maxf(0.6, drill_power))
		dug.emit(res, dir)
	heat = maxf(0.0, heat - dt * (0.25 if drilling else 0.6))
	# driving, flying, falling
	var target := ix * (DRIVE if grounded else FLY)
	v.x = move_toward(v.x, target, (ACC_G if grounded else ACC_A) * dt)
	if up:
		v.y += THRUST * dt
		thrusting = true
	# water: it floats and drags; loose rubble and sand drag it as it's shoved through
	wet = clampf(float(ground.count(p, Vector2(HALF + 0.1, HALF + 0.1), -5)) / 50.0, 0.0, 1.0)
	v.y -= GRAV * grav_k * (1.0 - 0.7 * wet) * dt
	if wet > 0.0:
		v *= 1.0 - minf(0.5, 2.5 * wet * dt)
	v.y = clampf(v.y, -MAX_FALL * (0.5 + 0.5 * grav_k), MAX_UP)
	driving = grounded and absf(ix) > 0.1
	var hx := _move_x(v.x * dt)
	var falling := v.y < 0.0
	var hy := _move_y(v.y * dt)
	p.y = minf(p.y, 12.0)
	var r := MineGround.cells_of(p, Vector2(HALF, HALF))
	shove = ground.sim.displace(r.position.x, r.position.y, r.size.x, r.size.y)
	if shove > 0:
		v *= 1.0 - minf(0.5, shove * 0.012)
	grounded = ground.count(p + Vector2(0, -HALF - 0.5 / MineGround.C), Vector2(HALF - 0.005, 0.5 / MineGround.C), -1) > 0
	if hy > FALL_SAFE and falling:
		bumped.emit(hy, true)
	elif hy > 2.0 and falling:
		bumped.emit(hy, false)
	if hx > BUMP_SAFE:
		bumped.emit(hx, false)
	_pose(dt)

const SUB := 0.1                # (metres a move at most: less than a cell of skipping)

## Across: in small steps, up a ledge of a cell or two on the way, stopped by a wall. -> how fast it hit (0 nothing)
func _move_x(d: float) -> float:
	var left := d
	while absf(left) > 1e-6:
		var st := clampf(left, -SUB, SUB)
		left -= st
		var np := p + Vector2(st, 0)
		if _clear(np):
			p = np
			continue
		var stepped := false
		if grounded or drilling:
			for upc in [1, 2, 3]:
				var lifted := np + Vector2(0, float(upc) / MineGround.C)
				if _clear(lifted):
					p = lifted
					stepped = true
					break
		if not stepped:
			# right up to the wall's edge
			var edge: float = (floor((p.x + HALF) * MineGround.C + 0.999) / MineGround.C - HALF - 0.0005) if st > 0.0 else (ceil((p.x - HALF) * MineGround.C - 0.999) / MineGround.C + HALF + 0.0005)
			if _clear(Vector2(edge, p.y)):
				p.x = edge
			var s := absf(v.x)
			v.x = 0.0
			return s
	return 0.0

## Up and down: in small steps, stopped flush against what it hits. -> how fast it hit (0 nothing)
func _move_y(d: float) -> float:
	var left := d
	while absf(left) > 1e-6:
		var st := clampf(left, -SUB, SUB)
		left -= st
		var np := p + Vector2(0, st)
		if _clear(np):
			p = np
			continue
		var edge: float = (floor((p.y - HALF) * MineGround.C + 0.0001) / MineGround.C + HALF + 0.0005) if st < 0.0 else (ceil((p.y + HALF) * MineGround.C - 0.0001) / MineGround.C - HALF - 0.0005)
		if _clear(Vector2(p.x, edge)):
			p.y = edge
		var s := absf(v.y)
		v.y = 0.0
		return s
	return 0.0

## Inside rock somehow (it turned solid round it): out to the nearest clear spot.
func _unstick() -> void:
	if _clear(p):
		return
	for rad in [0.125, 0.25, 0.375, 0.5, 0.75, 1.0, 1.5, 2.0]:
		for o in [Vector2(0, rad), Vector2(-rad, 0), Vector2(rad, 0), Vector2(0, -rad), Vector2(rad, rad), Vector2(-rad, rad)]:
			if _clear(p + o):
				p += o
				v = Vector2.ZERO
				return

## Put somewhere (a teleport, the tow truck): stopped, not drilling.
func place(at: Vector2) -> void:
	p = at
	v = Vector2.ZERO
	drilling = false
	grounded = false
	_pose(0.0)

# ---------------------------------------------------------------- the look

func _pose(dt: float) -> void:
	_rattle = move_toward(_rattle, (0.02 + hardness * 0.012) if (drilling and broke >= 0) else 0.0, dt * 0.5) if dt > 0.0 else 0.0
	var jit := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _rattle if drilling else Vector3.ZERO
	position = Vector3(p.x, p.y, Z) + jit
	if _model == null:
		return
	_model.rotation.y = 0.0 if face > 0 else PI
	var want := 1.0 if (drilling and drill_dir.y < 0.0) else 0.0
	_drill_down = move_toward(_drill_down, want, dt * 8.0)
	if drilling:
		_spin += dt * (30.0 + 20.0 * hardness)
	_drill_piv.position = Vector3(lerpf(0.33, 0.0, _drill_down), lerpf(-0.12, -0.34, _drill_down), 0.0)
	_drill_piv.rotation.z = lerpf(0.0, -PI * 0.5, _drill_down)
	_drill_bit.rotation.x = _spin
	if _drill_mat:
		_drill_mat.emission_enabled = heat > 0.05 or drill_level == 3
		var hot := Color(1.0, 0.35, 0.05).lerp(Color(1.0, 0.85, 0.4), heat)
		_drill_mat.emission = hot if heat > 0.05 else DRILL_COLS[drill_level]
		_drill_mat.emission_energy_multiplier = heat * 4.0 if heat > 0.05 else 0.8
	_model.rotation.z = (-v.x * 0.04 * face if not grounded else 0.0)
	for f in _flames:
		f.visible = thrusting
		if thrusting:
			f.scale = Vector3(1, randf_range(0.7, 1.25), 1)
	spot.position = Vector3(0.3 * face, 0.0, 0.3)
	var aim := Vector3(face, -0.5, -0.4).normalized() if not (drilling and drill_dir.y < 0.0) else Vector3(0.05 * face, -1, -0.3).normalized()
	if is_inside_tree():
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
	var dm := _m(DRILL_COLS[dl], 0.3, 0.9, 0.8)
	_drill_mat = dm
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
