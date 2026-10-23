class_name MineShip
extends Node3D
## The digging ship (the owner, 23 Oct; the pixel mine: "really satisfying when drilling into the ground"): drives on
## what's dug, flies up on its thrusters, falls, and drills: push into the ground (or hold down) and its bit eats a
## ship-sized hole cell by cell in front of it (slower in harder rock; a boulder only with a good enough drill), the
## cracks spreading through the face, chips flying, the ship working its way in as the face gives. It pushes through
## loose rubble and sand (they're shoved aside) and water (it floats), and steps up small ledges. Landing hard hurts.
## Positions in metres (x across, y up), in front of the ground's quad (z > 0). It's drawn in pixel art (MineShipArt:
## the Mole, Juicy Jared in its bubble), the whole of it turned to face the way it's going and tipped nose-first into
## the ground to drill down; its look changes with each upgrade. The mine (VoxelMine) runs it,
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
var _spin := 0.0
var _rattle := 0.0
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
		if ground.count(p + Vector2(s * (HALF + 0.07), 0.0), Vector2(0.06, HALF - 0.01), -1) > 0:
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
		v.y += THRUST * MineShop.LIFT_PUSH[lift_level] * dt
		thrusting = true
	# water: it floats and drags; loose rubble and sand drag it as it's shoved through
	wet = clampf(float(ground.count(p, Vector2(HALF + 0.1, HALF + 0.1), -5)) / 50.0, 0.0, 1.0)
	v.y -= GRAV * grav_k * (1.0 - 0.7 * wet) * dt
	if wet > 0.0:
		v *= 1.0 - minf(0.5, 2.5 * wet * dt)
	v.y = clampf(v.y, -MAX_FALL * (0.5 + 0.5 * grav_k), max_up)
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
	if hy > 2.0 and falling:
		squash(hy * 0.025)
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

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform sampler2D tex : filter_nearest, source_color;
uniform float self_lit = 0.3;
uniform vec3 glow = vec3(0.0);
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	EMISSION = c.rgb * self_lit + glow * dot(c.rgb, vec3(0.33));
}
"""
static var _shader: Shader

var cargo_full := 0.0           # (the mine sets it) how full the cargo bay is: the pod bulges with ore
var hose_out := 0.0             # (the mine sets it) the hose run out of its back: unloading, sucking water up
var lift_level := 0             # the lift's upgrade: 0 propeller, 1 big blades, 2 boosters, 3 mega booster
var max_up := MAX_UP            # (its climbing speed: the lift's)
var _upg := {}
var _pivot: Node3D              # the whole ship's picture: turned to face, tipped nose-down to drill
var _layers := {}               # name -> MeshInstance3D
var _drill_tex: Array[ImageTexture] = []
var _track_tex: Array[ImageTexture] = []
var _lift_tex: Array[ImageTexture] = []
var _flame_tex: Array[ImageTexture] = []
var _hose_tex := {}
var _body_full := -1
var _turn := 1.0                # -1 facing left .. 1 right (through 0: it swings round)
var _pitch := 0.0               # 0 level .. PI/2 nose-down
var _squash := 0.0
var _roll := 0.0
var _rotor := 0.0
var _flick := 0.0
var _down_t := 0.0              # (drilling down a moment ago: it stays tipped as it drops into what it dug)

func _layer(name: String, z: float, self_lit := 0.3) -> MeshInstance3D:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(MineShipArt.W, MineShipArt.H) * MineShipArt.PX
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("self_lit", self_lit)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3((MineShipArt.W * 0.5 - MineShipArt.CX) * MineShipArt.PX, (MineShipArt.CY - MineShipArt.H * 0.5) * MineShipArt.PX, z)
	_pivot.add_child(mi)
	_layers[name] = mi
	return mi

func _set_tex(name: String, t: Texture2D) -> void:
	(_layers[name].material_override as ShaderMaterial).set_shader_parameter("tex", t)

func _pose(dt: float) -> void:
	_rattle = move_toward(_rattle, (0.02 + hardness * 0.012) if (drilling and broke >= 0) else 0.0, dt * 0.5) if dt > 0.0 else 0.0
	var jit := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _rattle if drilling else Vector3.ZERO
	position = Vector3(p.x, p.y, Z) + jit
	if _pivot == null:
		return
	var snap := dt <= 0.0
	# facing: it swings round through side-on (a quick spin, not a snap)
	_turn = float(face) if snap else move_toward(_turn, float(face), dt * 11.0)
	var tsign := 1.0 if _turn >= 0.0 else -1.0
	# drilling down: the whole ship tips nose-first into the ground (and stays tipped while it's going down the hole)
	var down := drilling and drill_dir.y < 0.0
	if down:
		_down_t = 0.35
	elif dt > 0.0:
		_down_t = maxf(0.0, _down_t - dt) if (grounded or v.y > 0.5 or thrusting) else _down_t
	var want := PI * 0.5 if (down or _down_t > 0.0) else 0.0
	_pitch = want if snap else move_toward(_pitch, want, dt * 7.0)
	# leaning into the way it's going, nose up as it climbs; a squash when it lands
	var lean := 0.0
	if not grounded and _pitch < 0.1:
		lean = -v.x * 0.035 + (0.12 * tsign if thrusting else 0.0)
		if thrusting and lift_level == 0:
			lean += sin(_rotor * 0.35) * 0.06     # (the starter propeller: a bit of a wobble)
	_squash = 0.0 if snap else move_toward(_squash, 0.0, dt * 2.5)
	_pivot.scale = Vector3(maxf(0.06, absf(_turn)) * tsign * (1.0 + _squash), 1.0 - _squash, 1.0)
	_pivot.rotation.z = -_pitch * tsign + lean
	# the drill spinning, glowing as it heats
	if drilling:
		_spin += dt * (24.0 + 16.0 * hardness)
	if not _drill_tex.is_empty():
		_set_tex("drill", _drill_tex[int(_spin) % 3])
		var hot := Color(1.0, 0.35, 0.05).lerp(Color(1.0, 0.85, 0.4), heat)
		var g := Vector3(hot.r, hot.g, hot.b) * heat * 2.5 if heat > 0.05 else (Vector3(0.2, 0.5, 0.6) if drill_level == 3 else Vector3.ZERO)
		(_layers["drill"].material_override as ShaderMaterial).set_shader_parameter("glow", g)
	# the tracks rolling as it drives
	if grounded:
		_roll += v.x * dt * 18.0 * tsign
	if not _track_tex.is_empty():
		_set_tex("tracks", _track_tex[posmod(int(_roll), 2)])
	# the rotor (faster when it's lifting), the boosters' flames
	_rotor += dt * (40.0 if thrusting else 6.0)
	_flick += dt * 30.0
	if not _lift_tex.is_empty():
		_set_tex("lift", _lift_tex[int(_rotor) % 2])
		_layers["flames"].visible = thrusting and lift_level >= 2
		_set_tex("flames", _flame_tex[int(_flick) % 2])
	# the cargo pod filling up, the hose
	var fb := int(cargo_full * 5.0)
	if fb != _body_full and not _upg.is_empty():
		_body_full = fb
		_set_tex("body", MineShipArt.body(_upg, float(fb) / 5.0))
	var hs := int(round(clampf(hose_out, 0.0, 1.0) * 7.0))
	_layers["hose"].visible = hs > 0
	if hs > 0:
		if not _hose_tex.has(hs):
			_hose_tex[hs] = MineShipArt.hose(hs / 7.0)
		_set_tex("hose", _hose_tex[hs])
	spot.position = Vector3(0.3 * face, 0.0, 0.3)
	var aim := Vector3(face, -0.5, -0.4).normalized() if not down else Vector3(0.05 * face, -1, -0.3).normalized()
	if is_inside_tree():
		spot.look_at(spot.global_position + aim, Vector3.UP if absf(aim.y) < 0.95 else Vector3.FORWARD)

## A hard landing: it squashes.
func squash(k: float) -> void:
	_squash = clampf(k, 0.0, 0.3)

## Where the hose's nozzle is now (metres), turned with the ship.
func nozzle_at() -> Vector2:
	var n := MineShipArt.nozzle()
	n.x *= float(face)
	return p + n.rotated(_pivot.rotation.z if _pivot else 0.0)

## The ship drawn for its upgrades ({drill, tank, cargo, hull, lights, lift}: levels 0..3).
func build(upg: Dictionary) -> void:
	_upg = upg.duplicate()
	var dl := int(upg.get("drill", 0))
	var ll := int(upg.get("lights", 0))
	drill_level = dl
	drill_power = MineShop.k("drill", dl)
	lift_level = clampi(int(upg.get("lift", 0)), 0, 3)
	max_up = MineShop.k("lift", lift_level)
	if _pivot == null:
		_pivot = Node3D.new()
		add_child(_pivot)
		_layer("flames", -0.004, 1.6)
		_layer("lift", -0.003)
		_layer("hose", -0.002)
		_layer("body", 0.0)
		_layer("tracks", 0.002)
		_layer("drill", 0.004)
	_drill_tex.clear()
	for k in 3:
		_drill_tex.append(MineShipArt.drill(dl, k))
	if _track_tex.is_empty():
		for k in 2:
			_track_tex.append(MineShipArt.tracks(k))
	_lift_tex.clear()
	_flame_tex.clear()
	for k in 2:
		_lift_tex.append(MineShipArt.lift(lift_level, k))
		_flame_tex.append(MineShipArt.flames(lift_level, k))
	_body_full = -1
	lamp.omni_range = MineShop.k("lights", ll)
	lamp.light_energy = 1.3 + ll * 0.2
	spot.spot_range = MineShop.k("lights", ll) * 1.5
	_pose(0.0)
