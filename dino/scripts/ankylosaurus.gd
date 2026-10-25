class_name Ankylosaurus
extends Prey
## A low, armoured plant-eater (agreed with the owner, 25 Oct). It grazes and doesn't run: bites on the plates of
## its back barely get through (CLANK), so you go for the soft spots, the belly, the legs and the head. Get behind
## it and it raises its tail club (flashing: the warning) and swings it: a hit hurts and throws you. Dead, it's a
## lot of food.
## PLACEHOLDER numbers throughout.

enum { WIND = 40, SWING, REST }

## Bites on the back plates are cut down to this share of their size.
const ARMOUR_K := 0.35
## The plates: body pixels above this share of the body picture's height (the belly below is soft).
const ARMOUR_Y := 0.62
const DAMAGE := 16.0
const WIND_TIME := 0.55
const SWING_TIME := 0.3
const REST_TIME := 1.6

var _did_hit := false
## The tail tip, in the last tail piece's pixels (where the club is).
var _tip := Vector2.ZERO

func _ready() -> void:
	var art := ArtLoader.rig("ankylosaurus")
	build(art if not art.is_empty() else DinoArt.charger())
	if art.is_empty():
		half_w = 18.0
	wander_speed = 12.0
	if not tails.is_empty():
		var last: PixelPart = tails[tails.size() - 1]
		var best := -1.0
		for i in last.w * last.h:
			if last.alive[i] == 1:
				var p := Vector2(i % last.w + 0.5, i / last.w + 0.5)
				if p.distance_to(-last.offset) > best:
					best = p.distance_to(-last.offset)
					_tip = p

func step(delta: float, threat: Vector2, rng: RandomNumberGenerator) -> void:
	if held_step(delta, rng):
		return
	_t -= delta
	var to: float = game.player.global_position.x - global_position.x
	var behind := to * facing < 0.0 and absf(to) < _reach() and absf(game.player.global_position.y - global_position.y) < 40.0
	match state:
		GRAZE, FLEE:
			state = GRAZE
			if behind and not game.player.dead and not tails.is_empty():
				state = WIND
				_t = WIND_TIME
				game.sfx.play("thud", 0.1, -6.0)
			elif _t <= 0.0:
				_t = rng.randf_range(2.5, 5.0)
				_dir = [-1.0, 0.0, 0.0, 1.0][rng.randi() % 4]
			vel.x = move_toward(vel.x, _dir * wander_speed * leg_speed(), delta * 150.0)
			if _dir != 0.0 and state == GRAZE:
				set_facing(_dir)
		WIND:
			vel.x = move_toward(vel.x, 0.0, delta * 300.0)
			if _t <= 0.0:
				state = SWING
				_t = SWING_TIME
				_did_hit = false
				game.sfx.play("cry", 0.1, -4.0)
		SWING:
			if not _did_hit and not tails.is_empty() and game.player.covers(_club(), 6.0):
				_did_hit = true
				game.creature_hit(self, DAMAGE)
				game.shake(0.5)
			if _t <= 0.0:
				state = REST
				_t = REST_TIME
		REST:
			vel.x = move_toward(vel.x, 0.0, delta * 300.0)
			if _t <= 0.0:
				state = GRAZE
		DEAD:
			vel.x = move_toward(vel.x, 0.0, delta * 300.0)
	move(delta)
	if state == GRAZE and blocked != 0:
		_dir = -float(blocked)
	if state == DEAD:
		_slump(delta)
	else:
		animate(delta, absf(vel.x) > 3.0, 3.0 + absf(vel.x) * 0.1)
		_club_pose()
	_bleed_step(delta, rng)

## The tail raised to strike, then the swing down through where you stand (over the usual wag).
func _club_pose() -> void:
	var k := 0.0
	match state:
		WIND:
			k = 1.0 - _t / WIND_TIME
			(rig.material as ShaderMaterial).set_shader_parameter("flash", 0.4 if int(_t * 14.0) % 2 == 0 else 0.0)
		SWING:
			k = lerpf(1.0, -1.2, 1.0 - _t / SWING_TIME)
		REST:
			k = lerpf(-1.2, 0.0, 1.0 - _t / REST_TIME)
		_:
			return
	for i in tails.size():
		tails[i].rotation = k * 0.32

## How far behind it the club reaches.
func _reach() -> float:
	if tails.is_empty():
		return 0.0
	return absf(_club().x - global_position.x) + 12.0

func _club() -> Vector2:
	return tails[tails.size() - 1].to_world(_tip)

## True if `world` is on the plates of its back.
func armour_at(world: Vector2) -> bool:
	if dead or body == null or body.zone_at(world) != DinoArt.BODY:
		return false
	return body.to_pixel(world).y < body.h * ARMOUR_Y

## Bites on the plates barely get through.
func bite(world: Vector2, radius: float, rng: RandomNumberGenerator) -> Dictionary:
	return super.bite(world, radius * (ARMOUR_K if armour_at(world) else 1.0), rng)

## Bitten: flash and flinch, but it doesn't run (it's armoured). True if that killed it.
func hurt(from: Vector2) -> bool:
	flash = 0.07
	if state == DEAD:
		return false
	vel.x += signf(global_position.x - from.x) * 15.0
	if mass_fraction() < DIE_MASS or zone_fraction(DinoArt.HEAD) < DIE_HEAD:
		die()
		return true
	return false
