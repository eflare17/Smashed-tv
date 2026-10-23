class_name Hunter
extends Prey
## A hunter: a meat-eater that comes for you. It closes in, stops and winds up (jaw open, a yellow glint), then
## lunges and bites: if its teeth reach you, you lose health. Then it backs off a moment and comes again. It jumps
## over obstacles. You can bite it like anything else: each bite staggers it, and it dies by the same placeholder
## rule as prey (half its body, or most of its head), then it's a body to eat like any other.
## PLACEHOLDER: what hunts you, how hard and how often is all to be decided; these are numbers to try.

enum { STALK = 10, WINDUP, LUNGE, RECOVER, STAGGER }

const SPEED := 64.0
const RANGE := 34.0
const WINDUP_TIME := 0.45
const LUNGE_TIME := 0.16
const LUNGE_SPEED := 230.0
const RECOVER_TIME := 0.7
const STAGGER_TIME := 0.35
const DAMAGE := 14.0
const JUMP := 190.0

var _did_hit := false
## Turn-to-turn so a few of them don't all bite in step.
var _patience := 0.0

func _ready() -> void:
	build(DinoArt.hunter())
	half_w = 8.0
	state = STALK

func step(delta: float, threat: Vector2, rng: RandomNumberGenerator) -> void:
	_t -= delta
	var me := global_position
	var player: Player = game.player
	var to := player.global_position.x - me.x
	match state:
		STALK:
			set_facing(to)
			_patience -= delta
			if absf(to) > RANGE * 0.8 or _patience > 0.0:
				vel.x = move_toward(vel.x, signf(to) * SPEED, delta * 400.0)
				if absf(to) < RANGE * 0.6:
					vel.x = move_toward(vel.x, 0.0, delta * 800.0)
			else:
				vel.x = 0.0
				_go(WINDUP, WINDUP_TIME)
			if blocked != 0 and on_ground:
				vel.y = -JUMP
				on_ground = false
		WINDUP:
			set_facing(to)
			vel.x = move_toward(vel.x, 0.0, delta * 600.0)
			if _t <= 0.0:
				_did_hit = false
				vel.x = facing * LUNGE_SPEED
				_go(LUNGE, LUNGE_TIME)
				game.sfx.play("snap", 0.1, -4.0)
		LUNGE:
			if not _did_hit and player.covers(_teeth(), 3.0):
				_did_hit = true
				game.hunter_bit(self)
			if _t <= 0.0:
				vel.x *= 0.2
				_go(RECOVER, RECOVER_TIME)
		RECOVER:
			# back off a little
			vel.x = move_toward(vel.x, -signf(to) * SPEED * 0.4, delta * 400.0)
			if _t <= 0.0:
				_patience = rng.randf_range(0.0, 0.6)
				state = STALK
		STAGGER:
			vel.x = move_toward(vel.x, 0.0, delta * 300.0)
			if _t <= 0.0:
				state = STALK
		DEAD:
			vel.x = move_toward(vel.x, 0.0, delta * 300.0)
	move(delta)
	if state == DEAD:
		_slump(delta)
	else:
		animate(delta, absf(vel.x) > 5.0, 12.0 * absf(vel.x) / SPEED)
		_pose(delta)
	_bleed_step(delta, rng)

func _go(s: int, secs: float) -> void:
	state = s
	_t = secs

func _teeth() -> Vector2:
	if head == null or head.pixels_left() == 0:
		return global_position + Vector2(facing * 30.0, -24.0)
	return head.to_world(head.get_meta("tip"))

## The jaw hangs open on the wind-up (with a glint) and snaps shut on the lunge.
func _pose(delta: float) -> void:
	if jaw == null or head == null:
		return
	var open := 0.0
	if state == WINDUP:
		open = 0.8
	head.rotation = lerpf(head.rotation, 0.25 if state == WINDUP else 0.0, minf(1.0, delta * 12.0))
	jaw.rotation = lerpf(jaw.rotation, open, minf(1.0, delta * 25.0))
	(rig.material as ShaderMaterial).set_shader_parameter("flash", 0.85 if flash > 0.0 else
			(0.35 if state == WINDUP and int(_t * 16.0) % 2 == 0 else 0.0))

## Bitten: flash, flinch and stagger (it doesn't run). True if that killed it.
func hurt(from: Vector2) -> bool:
	flash = 0.07
	if state == DEAD:
		return false
	vel.x += signf(global_position.x - from.x) * 70.0
	if mass_fraction() < DIE_MASS or zone_fraction(DinoArt.HEAD) < DIE_HEAD:
		die()
		return true
	_go(STAGGER, STAGGER_TIME)
	return false
