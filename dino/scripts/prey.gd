class_name Prey
extends Dino
## Prey: wanders and grazes until you come close or bite it, then runs. It bleeds from its wounds, and dies when
## it has lost enough of itself or its head (placeholder rule: see PLAN.md). Dead, it slumps to the ground and
## stays, still bitable. `kind` (set before it's added) picks which: GRAZER, the big long-necked one, or RUNNER,
## a small fast skittish one (little meat, but your size at the start). Hunter, Charger and Flyer build on this.

enum { GRAZE, FLEE, DEAD }
enum { GRAZER, RUNNER }

## Placeholder death rule: under this much of its body left, or of its head.
const DIE_MASS := 0.5
const DIE_HEAD := 0.35

var kind: int = GRAZER
## PLACEHOLDER numbers per kind (set in _ready).
var wander_speed := 22.0
var run_speed := 68.0
var scare_range := 70.0
## How far the body drops when it dies (about its leg length).
var slump_drop := 9.0
## Seconds a scare runs for, then seconds it has to catch its breath before it can bolt again.
var flee_time := 1.6
var rest_time := 0.0
var _rest := 0.0
var _leg_y0: Array[float] = []

var state: int = GRAZE
var _t := 0.0
var _dir := 0.0
var _flee_t := 0.0
var _collapse := 0.0
var _bleed := 0.0
var _leg_rest: Array[float] = []
## Seconds dead. Past the game's ROT_TIME the meat is rotten: it darkens and feeds you nothing.
var dead_t := 0.0
## In your jaws (a big bite): it can't go anywhere, it just thrashes (or, dead, hangs there).
var held := false
var _held_t := 0.0

func _ready() -> void:
	if kind == RUNNER:
		build(DinoArt.runner())
		half_w = 6.0
		wander_speed = 30.0
		run_speed = 85.0
		flee_time = 0.9
		rest_time = 0.8
		scare_range = 95.0
		slump_drop = 6.0
	else:
		# the big grazer outruns you flat out, but only in bursts: catch it cornered, tired, or with the big lunge
		build(DinoArt.prey())
		half_w = 16.0
		run_speed = 105.0
		flee_time = 1.4
		rest_time = 1.3

## Held in your jaws: thrash in place and bleed. Returns true if it was (and the normal step is skipped).
func held_step(delta: float, rng: RandomNumberGenerator) -> bool:
	if not held:
		if _held_t > 0.0:
			_held_t = 0.0
			if not dead:
				rig.rotation = 0.0
		return false
	_held_t += delta
	vel = Vector2.ZERO
	if not dead:
		rig.rotation = sin(_held_t * 37.0) * 0.12
		animate(delta, true, 22.0)
	_bleed_step(delta, rng)
	return true

func step(delta: float, threat: Vector2, rng: RandomNumberGenerator) -> void:
	if held_step(delta, rng):
		return
	_t -= delta
	_rest -= delta
	var near := absf(threat.x - global_position.x) < scare_range and absf(threat.y - global_position.y) < 50.0
	match state:
		GRAZE:
			if near and _rest <= 0.0:
				_scare()
			elif _t <= 0.0:
				_t = rng.randf_range(1.5, 3.5)
				_dir = [-1.0, 0.0, 0.0, 1.0][rng.randi() % 4]
			vel.x = move_toward(vel.x, _dir * wander_speed, delta * 200.0)
		FLEE:
			_flee_t -= delta
			# cornered against the edge of the world or an obstacle: turn and bolt past
			if (global_position.x < 30.0 and _dir < 0.0) or (global_position.x > game.world_w - 30.0 and _dir > 0.0) \
					or blocked * _dir > 0.0:
				_dir = -_dir
				_flee_t = maxf(_flee_t, 1.2)
			if _flee_t <= 0.0:
				if near and rest_time <= 0.0:
					_scare()
				else:
					state = GRAZE
					_rest = rest_time
					_dir = 0.0
			vel.x = move_toward(vel.x, _dir * run_speed, delta * 500.0)
		DEAD:
			vel.x = move_toward(vel.x, 0.0, delta * 300.0)
	if _dir != 0.0 and state != DEAD:
		set_facing(_dir)
	move(delta)
	# wandering into a rock: turn around
	if state == GRAZE and blocked != 0:
		_dir = -float(blocked)
	if state == DEAD:
		_slump(delta)
	else:
		animate(delta, absf(vel.x) > 3.0, 3.0 + absf(vel.x) * 0.13)
	_bleed_step(delta, rng)

func _scare() -> void:
	state = FLEE
	_flee_t = flee_time
	var away := signf(global_position.x - game.player.global_position.x)
	_dir = away if away != 0.0 else 1.0

## Bitten (the scene root calls this after carving): flash, flinch, run. Returns true if that killed it.
func hurt(from: Vector2) -> bool:
	flash = 0.07
	if state == DEAD:
		return false
	vel.x += signf(global_position.x - from.x) * 60.0
	if mass_fraction() < DIE_MASS or zone_fraction(DinoArt.HEAD) < DIE_HEAD:
		die()
		return true
	_scare()
	return false

func die() -> void:
	state = DEAD
	dead = true
	_leg_rest.clear()
	_leg_y0.clear()
	for l in legs:
		_leg_rest.append((l[0] as PixelPart).rotation)
		_leg_y0.append((l[0] as PixelPart).position.y)

## Folds the legs out and drops the body onto the ground.
func _slump(delta: float) -> void:
	var was := _collapse
	_collapse = minf(1.0, _collapse + delta * 2.2)
	var k := _collapse * _collapse
	for i in legs.size():
		var part: PixelPart = legs[i][0]
		var out := 1.35 if part.position.x > 0.0 else -1.35
		part.rotation = lerpf(_leg_rest[i], out, k)
	body.position.y = body.get_meta("y0") + k * slump_drop
	for i in legs.size():
		var part: PixelPart = legs[i][0]
		part.position.y = _leg_y0[i] + k * slump_drop
	rig.rotation = k * 0.05 * facing
	(rig.material as ShaderMaterial).set_shader_parameter("flash", 0.85 if flash > 0.0 else 0.0)
	flash -= delta
	if was < 1.0 and _collapse >= 1.0:
		game.prey_landed(self)

func rotten() -> bool:
	return dead and dead_t >= game.ROT_TIME

## Dead: counts the seconds and goes green-grey as it rots (every kind calls this from its step).
func _rot_step(delta: float) -> void:
	if not dead:
		return
	dead_t += delta
	var k: float = clampf((dead_t - game.ROT_TIME * 0.6) / (game.ROT_TIME * 0.6), 0.0, 1.0)
	rig.modulate = Color.WHITE.lerp(Color(0.55, 0.62, 0.45), k)

## Drips blood from its wounds, more the more it has.
func _bleed_step(delta: float, rng: RandomNumberGenerator) -> void:
	_rot_step(delta)
	var n := wound_count()
	if n == 0:
		return
	_bleed += delta * minf(18.0, 1.0 + n * 0.12) * (0.4 if dead else 1.0)
	while _bleed >= 1.0:
		_bleed -= 1.0
		var p: Variant = random_wound(rng)
		if p != null:
			game.gore.drip(p, vel * 0.5)
