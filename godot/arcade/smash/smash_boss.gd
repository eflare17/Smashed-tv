extends Node3D
## Smash arcade: the boss, Big Tony, a brute three times the size, every BOSS_EVERY rooms. One of him, so he's a
## plain MeshInstance3D (two walk frames), built once and shown when a boss room starts.
## He walks in through a door, then cycles: chase the player for a while, then one attack:
##  - CHARGE: stops and glows (the wind-up), then charges in a straight line, flattening grunts, until he hits a
##    wall (stunned for a moment, the screen shakes) or runs out of steam;
##  - THROW: rolls 3-5 barrels at the player (SmashEShots BARREL);
##  - SUMMON: roars and calls a swarm of grunts in through all four doors.
## Under half health he's faster, winds up quicker and throws more. Killed, he shakes and blows up in a string
## of blasts before he pops. Sounds, shakes, score and gibs are the scene root's: he tells it through
## game.boss_event(name, position).

const SmashVox := preload("smash_vox.gd")

const RADIUS := 1.25
const SCALE := 3.0
const WALK := 1.5
const CHARGE_SPEED := 10.0
const DOOR_N := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
enum { OFF, ENTER, CHASE, WINDUP, CHARGE, STUNNED, THROW, SUMMON, DYING }

var half := 10.0
var door_half := 1.5

## Drawn (alive or dying).
var active := false
## 1 while he can be hit (SmashShots tests targets with a count), else 0.
var count := 0
var pos := Vector2.ZERO
var facing := Vector2(0, 1)
var hp := 0
var max_hp := 1
var state := OFF
## Attacks started so far (the bench checks he fights back).
var attacks := 0

var _t := 0.0
var _door := 0
var _phase := 0.0
var _flash := 0.0
var _charge_dir := Vector2.ZERO
var _throws_left := 0
var _boom_t := 0.0
var _model: MeshInstance3D
var _frames: Array[Mesh] = []
var _mat: StandardMaterial3D

func _init() -> void:
	name = "SmashBoss"
	_mat = SmashVox.flat_material()
	for f in 2:
		_frames.append(SmashVox.boss_mesh(f))
	_model = MeshInstance3D.new()
	_model.mesh = _frames[0]
	_model.material_override = _mat
	_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.scale = Vector3.ONE * SCALE
	_model.visible = false
	add_child(_model)

func clear() -> void:
	active = false
	count = 0
	state = OFF
	_model.visible = false

## Big Tony walks in through door `d` with `health` HP.
func start(d: int, health: int) -> void:
	active = true
	count = 1
	max_hp = health
	hp = health
	state = ENTER
	_door = d
	facing = DOOR_N[d]
	pos = -facing * (half + 3.0)
	_t = 0.0
	_flash = 0.0
	_model.visible = true

func angry() -> bool:
	return hp * 2 < max_hp

func step(delta: float, game, target: Vector2, touch: float, can_touch: bool) -> bool:
	if not active:
		return false
	_t += delta
	_flash -= delta
	var moving := false
	match state:
		ENTER:
			pos += facing * (WALK * delta)
			moving = true
			if pos.dot(facing) + half > RADIUS + 0.3:
				_go(CHASE)
				game.boss_event("roar", pos)
		CHASE:
			var to := target - pos
			if to.length_squared() > 0.01:
				facing = to.normalized()
			pos += facing * (WALK * (1.5 if angry() else 1.0) * delta)
			moving = true
			if _t > (1.6 if angry() else 2.6):
				attacks += 1
				var roll := randf()
				if roll < 0.4:
					_go(WINDUP)
				elif roll < 0.75 or game.horde.count > 150:
					_go(THROW)
					_throws_left = randi_range(4, 6) if angry() else randi_range(3, 4)
				else:
					_go(SUMMON)
					game.boss_event("roar", pos)
		WINDUP:
			var to := target - pos
			if to.length_squared() > 0.01:
				facing = to.normalized()
			if _t > (0.55 if angry() else 0.85):
				_charge_dir = facing
				_go(CHARGE)
				game.boss_event("charge", pos)
		CHARGE:
			pos += _charge_dir * (CHARGE_SPEED * delta)
			moving = true
			game.horde.kill_near(pos, RADIUS)
			var lim := half - RADIUS
			if absf(pos.x) > lim or absf(pos.y) > lim:
				pos = Vector2(clampf(pos.x, -lim, lim), clampf(pos.y, -lim, lim))
				_go(STUNNED)
				game.boss_event("slam", pos)
			elif _t > 1.6:
				_go(CHASE)
		STUNNED:
			if _t > 1.2:
				_go(CHASE)
		THROW:
			var to := target - pos
			if to.length_squared() > 0.01:
				facing = to.normalized()
			if _t > 0.4:
				_t = 0.0
				game.eshots.fire(pos + facing * (RADIUS + 0.3), facing.rotated(randf_range(-0.35, 0.35)), game.eshots.BARREL)
				game.boss_event("throw", pos)
				_throws_left -= 1
				if _throws_left <= 0:
					_go(CHASE)
		SUMMON:
			if _t > 0.6:
				for k in (20 if angry() else 14):
					game.horde.spawn(k % 4, randf_range(0.5, 3.0), game.waves.grunt_speed())
				_go(CHASE)
		DYING:
			_boom_t -= delta
			if _boom_t <= 0.0:
				_boom_t = 0.16
				game.boss_event("boom", pos + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)))
			if _t > 1.8:
				active = false
				state = OFF
				_model.visible = false
				game.boss_event("dead", pos)
				return false

	if state != DYING and state != CHARGE:
		var lim := half - RADIUS
		if state != ENTER:
			pos = Vector2(clampf(pos.x, -lim, lim), clampf(pos.y, -lim, lim))
		game.horde.push_out(pos, RADIUS)
	if moving:
		_phase += delta * (9.0 if state == CHARGE else 3.0)
	_place()
	return can_touch and state != DYING and (pos - target).length() < touch + RADIUS

func _go(s: int) -> void:
	state = s
	_t = 0.0

func hit_test(p: Vector2, r: float) -> int:
	if count == 0:
		return -1
	return 0 if (pos - p).length_squared() < (RADIUS + r) * (RADIUS + r) else -1

func bullet_hit(_i: int, _dir: Vector2) -> void:
	damage(1)

## Takes `amount` off; at zero he starts dying. True if that hit started it.
func damage(amount: int) -> bool:
	if count == 0:
		return false
	hp -= amount
	_flash = 0.08
	if hp <= 0:
		hp = 0
		count = 0
		_go(DYING)
		_boom_t = 0.0
		return true
	return false

func damage_radius(p: Vector2, r: float, amount: int) -> bool:
	if count > 0 and (pos - p).length() < r + RADIUS:
		return damage(amount)
	return false

func _place() -> void:
	var f := facing
	var jitter := Vector3.ZERO
	if state == DYING:
		jitter = Vector3(randf_range(-0.15, 0.15), -_t * 0.4, randf_range(-0.15, 0.15))
	_model.position = Vector3(pos.x, 0, pos.y) + jitter
	_model.basis = Basis(Vector3(f.y, 0, -f.x), Vector3.UP, Vector3(f.x, 0, f.y)).scaled(Vector3.ONE * SCALE)
	_model.mesh = _frames[int(_phase / PI) & 1]
	var c := Color.WHITE
	if _flash > 0.0 or state == DYING:
		c = Color(1.0, 0.35, 0.35)
	elif state == WINDUP and int(_t * 12.0) % 2 == 0:
		c = Color(1.0, 1.0, 0.4)
	elif state == STUNNED:
		c = Color(0.7, 0.7, 1.0)
	if _mat.albedo_color != c:
		_mat.albedo_color = c
