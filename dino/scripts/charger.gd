class_name Charger
extends Prey
## A big horned plant-eater that fights back. It grazes and ignores you, but bite it and it gets angry: it turns
## on you, closes in, stops and paws the ground (flashing: the warning), then charges in a straight line, horns
## first. A hit hurts and throws you; a rock stops it dead. After a charge it blows for a moment, then comes again,
## until it calms down (a while after the last bite). Dead, it's a lot of food.
## PLACEHOLDER: everything about it is to be decided; these are numbers to try.

enum { ANGRY = 30, PAW, CHARGE, TIRED }

const WALK := 34.0
const CHARGE_SPEED := 150.0
const DAMAGE := 18.0
const CALM_AFTER := 8.0

var _angry_t := 0.0
var _did_hit := false

func _ready() -> void:
	var art := ArtLoader.rig("charger")
	build(art if not art.is_empty() else DinoArt.charger())
	if art.is_empty():
		half_w = 18.0
		slump_drop = 9.0
	wander_speed = 16.0

func step(delta: float, threat: Vector2, rng: RandomNumberGenerator) -> void:
	if held_step(delta, rng):
		return
	_t -= delta
	_angry_t -= delta
	var to: float = game.player.global_position.x - global_position.x
	match state:
		GRAZE, FLEE:
			state = GRAZE
			if _t <= 0.0:
				_t = rng.randf_range(2.0, 4.0)
				_dir = [-1.0, 0.0, 0.0, 1.0][rng.randi() % 4]
			vel.x = move_toward(vel.x, _dir * wander_speed * leg_speed(), delta * 200.0)
			if _dir != 0.0:
				set_facing(_dir)
		ANGRY:
			set_facing(to)
			vel.x = move_toward(vel.x, signf(to) * WALK * leg_speed(), delta * 200.0)
			if absf(to) < 120.0:
				state = PAW
				_t = 0.7
				game.sfx.play("thud", 0.1, -8.0)
			elif _angry_t <= 0.0:
				state = GRAZE
		PAW:
			set_facing(to)
			vel.x = move_toward(vel.x, 0.0, delta * 400.0)
			if _t <= 0.0 and crippled():
				# can't get up to speed any more: it just plods at you
				state = ANGRY
			elif _t <= 0.0:
				state = CHARGE
				_t = 1.1
				_did_hit = false
				vel.x = facing * CHARGE_SPEED * leg_speed()
				game.sfx.play("cry", 0.1, 0.0)
		CHARGE:
			vel.x = facing * CHARGE_SPEED * leg_speed()
			if not _did_hit and (game.player.covers(_horns(), 4.0) or game.player.covers(Vector2(_horns().x, game.player.global_position.y - game.player.height * game.player.size * 0.5), 4.0)):
				_did_hit = true
				game.creature_hit(self, DAMAGE)
			if _t <= 0.0 or blocked != 0:
				if blocked != 0:
					game.shake(0.5)
				state = TIRED
				_t = 1.0
		TIRED:
			vel.x = move_toward(vel.x, 0.0, delta * 300.0)
			if _t <= 0.0:
				state = ANGRY if _angry_t > 0.0 else GRAZE
		DEAD:
			vel.x = move_toward(vel.x, 0.0, delta * 300.0)
	move(delta)
	if state == GRAZE and blocked != 0:
		_dir = -float(blocked)
	if state == DEAD:
		_slump(delta)
	else:
		animate(delta, absf(vel.x) > 3.0, 3.0 + absf(vel.x) * 0.1)
		if state == PAW:
			(rig.material as ShaderMaterial).set_shader_parameter("flash", 0.4 if int(_t * 14.0) % 2 == 0 else 0.0)
	_bleed_step(delta, rng)

func _horns() -> Vector2:
	# the front of the head
	return front_point()

## Bitten: flash, and now it's angry (it doesn't run). True if that killed it.
func hurt(from: Vector2) -> bool:
	flash = 0.07
	if state == DEAD:
		return false
	vel.x += signf(global_position.x - from.x) * 30.0
	if mass_fraction() < DIE_MASS or zone_fraction(DinoArt.HEAD) < DIE_HEAD:
		die()
		return true
	_angry_t = CALM_AFTER
	if state == GRAZE or state == FLEE:
		state = ANGRY
	return false
