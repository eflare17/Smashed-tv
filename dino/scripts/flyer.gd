class_name Flyer
extends Prey
## A pterodactyl. It circles above you, then hangs in the air screeching (flashing: the warning), then dives at
## you in a straight line, raking you if it connects, and climbs back up to circle again. You can bite it when it
## comes low (it lunges and leaps like anything else). Bite enough of a wing away and it crashes down and can only
## flap about on the ground; dead, it drops and is food like anything else. Its origin is its body: it flies.
## PLACEHOLDER: everything about it is to be decided; these are numbers to try.

enum { CIRCLE = 20, AIM, DIVE, CLIMB, STAGGER, GROUNDED }

const FLY := 70.0
const DIVE_SPEED := 200.0
const DAMAGE := 8.0
## Under this much wing left, it can't fly.
const CRIPPLED := 0.6

var _home_y := 80.0
var _wander := 0.0
var _flap := 0.0
var _did_hit := false
## The wings' angle lying dead (the code-drawn wing points forward, the sprite's trails back).
var _wing_rest := 1.1

func _ready() -> void:
	var art := ArtLoader.rig("flyer")
	build(art if not art.is_empty() else DinoArt.flyer())
	if not art.is_empty():
		_wing_rest = art.get("wing_rest", 1.1)
	if art.is_empty():
		half_w = 6.0
		foot = 5.0
	slump_drop = 0.0
	state = CIRCLE
	on_ground = false
	_t = randf_range(2.5, 4.0)
	_home_y = randf_range(100.0, 130.0)

func step(delta: float, threat: Vector2, rng: RandomNumberGenerator) -> void:
	if held_step(delta, rng):
		_flap_wings(delta, 24.0)
		return
	_t -= delta
	var player: Player = game.player
	var target := player.global_position + Vector2(0, -12.0 * player.size)
	var ground: float = game.GROUND_Y
	if state != DEAD and state != GROUNDED and not _can_fly():
		state = GROUNDED
		vel = Vector2(vel.x * 0.3, 0.0)
		game.sfx.play("cry", 0.1, -2.0)
	match state:
		CIRCLE:
			# drift about above you, side to side
			_wander += delta
			var want := Vector2(player.global_position.x + sin(_wander * 0.9) * 90.0, _home_y + sin(_wander * 2.3) * 8.0)
			vel = vel.lerp((want - position).limit_length(FLY), minf(1.0, delta * 2.0))
			position += vel * delta
			set_facing(vel.x if absf(vel.x) > 8.0 else target.x - position.x)
			_flap_wings(delta, 9.0)
			if _t <= 0.0:
				state = AIM
				_t = 0.55
				game.sfx.play("cry", 0.1, 2.0)
		AIM:
			vel = vel.lerp(Vector2.ZERO, minf(1.0, delta * 6.0))
			position += vel * delta
			set_facing(target.x - position.x)
			_flap_wings(delta, 16.0)
			if _t <= 0.0:
				# aimed so the beak, out in front, goes through you
				vel = (target - _beak()).normalized() * DIVE_SPEED
				_did_hit = false
				state = DIVE
				_t = 1.4
				game.sfx.play("whoosh", 0.1, 0.0)
		DIVE:
			position += vel * delta
			# skims the ground rather than going into it
			if position.y > ground - 12.0:
				position.y = ground - 12.0
				vel.y = minf(vel.y, 0.0)
			_fold_wings(delta)
			if not _did_hit and (player.covers(_beak(), 3.0) or player.covers(position, 2.0)):
				_did_hit = true
				game.creature_hit(self, DAMAGE)
			if _t <= 0.0 or (position.x - target.x) * signf(vel.x) > 50.0:
				state = CLIMB
		CLIMB:
			vel = vel.lerp(Vector2(signf(vel.x) * FLY, -FLY * 1.3), minf(1.0, delta * 3.0))
			position += vel * delta
			_flap_wings(delta, 15.0)
			if position.y < _home_y:
				state = CIRCLE
				_t = rng.randf_range(2.5, 4.5)
		STAGGER:
			vel.y += 300.0 * delta
			position += vel * delta
			_flap_wings(delta, 22.0)
			if _t <= 0.0:
				state = CLIMB
		GROUNDED:
			# can't fly: flops along the ground, away from you
			vel.x = move_toward(vel.x, -signf(target.x - position.x) * 14.0, delta * 100.0)
			move(delta)
			_flap_wings(delta, 6.0)
		DEAD:
			vel.x = move_toward(vel.x, 0.0, delta * 100.0)
			move(delta)
			if on_ground:
				for w in wings:
					w.rotation = lerpf(w.rotation, _wing_rest, minf(1.0, delta * 8.0))
				_slump(delta)
	if state != DEAD and state != GROUNDED:
		position.y = minf(position.y, ground - 10.0)
		position.x = clampf(position.x, 10.0, game.world_w - 10.0)
	(rig.material as ShaderMaterial).set_shader_parameter("flash", 0.85 if flash > 0.0 else
			(0.4 if state == AIM and int(_t * 16.0) % 2 == 0 else 0.0))
	flash -= delta
	_bleed_step(delta, rng)

func _can_fly() -> bool:
	return wings.size() == 2 and wings[0].zone_fraction_ok(CRIPPLED) and wings[1].zone_fraction_ok(CRIPPLED)

func _flap_wings(delta: float, speed: float) -> void:
	_flap += delta * speed
	for w in wings:
		w.rotation = sin(_flap) * 0.9 - 0.25

func _fold_wings(delta: float) -> void:
	for w in wings:
		w.rotation = lerpf(w.rotation, -0.9, minf(1.0, delta * 12.0))

func _beak() -> Vector2:
	return front_point()

## Bitten: flash, a jolt down; it climbs away. True if that killed it.
func hurt(from: Vector2) -> bool:
	flash = 0.07
	if state == DEAD:
		return false
	if mass_fraction() < DIE_MASS or zone_fraction(DinoArt.HEAD) < DIE_HEAD:
		die()
		vel = Vector2(signf(global_position.x - from.x) * 40.0, 0.0)
		return true
	if state != GROUNDED:
		state = STAGGER
		_t = 0.3
		vel = Vector2(signf(global_position.x - from.x) * 60.0, 30.0)
	return false
