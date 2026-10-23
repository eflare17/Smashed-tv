class_name Prey
extends Dino
## The prey: wanders and grazes until you come close or bite it, then runs (it can't fight back yet). It bleeds
## from its wounds, and dies when it has lost enough of itself or its head (placeholder rule: see PLAN.md).
## Dead, it slumps to the ground and stays, still bitable.

enum { GRAZE, FLEE, DEAD }

const WANDER := 22.0
const RUN := 68.0
const SCARE := 70.0
## Placeholder death rule: under this much of its body left, or of its head.
const DIE_MASS := 0.5
const DIE_HEAD := 0.35

var state: int = GRAZE
var _t := 0.0
var _dir := 0.0
var _flee_t := 0.0
var _collapse := 0.0
var _bleed := 0.0
var _leg_rest: Array[float] = []
## In your jaws (a big bite): it can't go anywhere, it just thrashes (or, dead, hangs there).
var held := false
var _held_t := 0.0

func _ready() -> void:
	build(DinoArt.prey())
	half_w = 16.0

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
	var near := absf(threat.x - global_position.x) < SCARE and absf(threat.y - global_position.y) < 50.0
	match state:
		GRAZE:
			if near:
				_scare()
			elif _t <= 0.0:
				_t = rng.randf_range(1.5, 3.5)
				_dir = [-1.0, 0.0, 0.0, 1.0][rng.randi() % 4]
			vel.x = move_toward(vel.x, _dir * WANDER, delta * 200.0)
		FLEE:
			_flee_t -= delta
			# cornered against the edge of the world or an obstacle: turn and bolt past
			if (global_position.x < 30.0 and _dir < 0.0) or (global_position.x > game.world_w - 30.0 and _dir > 0.0) \
					or blocked * _dir > 0.0:
				_dir = -_dir
				_flee_t = maxf(_flee_t, 1.2)
			if _flee_t <= 0.0:
				if near:
					_scare()
				else:
					state = GRAZE
					_dir = 0.0
			vel.x = move_toward(vel.x, _dir * RUN, delta * 500.0)
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
	_flee_t = 1.6
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
	for l in legs:
		_leg_rest.append((l[0] as PixelPart).rotation)

## Folds the legs out and drops the body onto the ground.
func _slump(delta: float) -> void:
	var was := _collapse
	_collapse = minf(1.0, _collapse + delta * 2.2)
	var k := _collapse * _collapse
	for i in legs.size():
		var part: PixelPart = legs[i][0]
		var out := 1.35 if part.position.x > 0.0 else -1.35
		part.rotation = lerpf(_leg_rest[i], out, k)
	body.position.y = body.get_meta("y0") + k * 9.0
	for i in legs.size():
		var part: PixelPart = legs[i][0]
		part.position.y = -16.0 + k * 9.0
	rig.rotation = k * 0.05 * facing
	(rig.material as ShaderMaterial).set_shader_parameter("flash", 0.85 if flash > 0.0 else 0.0)
	flash -= delta
	if was < 1.0 and _collapse >= 1.0:
		game.prey_landed(self)

## Drips blood from its wounds, more the more it has.
func _bleed_step(delta: float, rng: RandomNumberGenerator) -> void:
	var n := wound_count()
	if n == 0:
		return
	_bleed += delta * minf(18.0, 1.0 + n * 0.12) * (0.4 if dead else 1.0)
	while _bleed >= 1.0:
		_bleed -= 1.0
		var p: Variant = random_wound(rng)
		if p != null:
			game.gore.drip(p, vel * 0.5)
