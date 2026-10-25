class_name Player
extends Dino
## You: walk, jump, and bite where the mouse points. The neck stays its own length: to bite, the whole body
## lunges (or leaps, for a spot up high, or steps back, for one right under your nose) so the teeth meet exactly on
## the spot. It remembers the spot on the prey's body, so a moving prey still gets bitten where you aimed; past
## your range the teeth meet at the closest point they can reach.
##  - Quick bite (left click): a fast snap, a small chunk.
##  - Big bite (hold right click to charge, let go to bite): a heavier lunge; if it lands on something the jaws
##    clamp on and you shake it, tearing pixels out the whole time, then rip a big chunk away. You're stuck while
##    you shake (hunters can get you). Anything bigger than you breaks free early, the bigger the sooner.
## Hunters bite back: hurt() takes health, knocks you away (and out of a grab) and gives a moment of blinking safety.

enum { QUICK, BIG }

## Your four forms, in order: name, the size the rig is drawn at when you become it, how big you can grow before
## the next, walk speed, seconds between bites, bite radius, health, and the whole bodies eaten to reach the
## next form. PLACEHOLDER names and numbers.
const STAGES := [
	{"name": "HATCHLING", "size": 0.5, "max_size": 0.75, "speed": 92.0, "cool": 0.34, "bite": 3.2, "hp": 60.0, "meals": 4},
	{"name": "RAPTOR", "size": 0.8, "max_size": 1.15, "speed": 78.0, "cool": 0.42, "bite": 4.5, "hp": 100.0, "meals": 8},
	{"name": "ALLOSAUR", "size": 1.3, "max_size": 1.7, "speed": 64.0, "cool": 0.5, "bite": 6.5, "hp": 170.0, "meals": 14},
	{"name": "TYRANT", "size": 2.0, "max_size": 2.5, "speed": 54.0, "cool": 0.6, "bite": 9.0, "hp": 280.0, "meals": 99999},
]
var stage := 0
## The imported sprites for each form (art/<name>_*.png), with DinoArt's placeholders as the fallback.
const FORM_ART := ["hatchling", "raptor", "allosaur", "tyrant"]

## The stats (the form's, plus what levelling up has added: main.gd's UPGRADES). apply_stage() sets them.
var bite_radius := 4.5
var bite_cooldown := 0.42
var walk_speed := 75.0
var bite_bonus := 0.0
var speed_mult := 1.0
var cool_mult := 1.0
var hp_bonus := 0.0

## Health. Hunters' bites take it; eating gives it back. PLACEHOLDER numbers.
var max_hp := 100.0
var hp := 100.0
## Seconds you can't be hurt again after a hit (and blink).
var invuln := 0.0

const JUMP := 200.0
## Per kind (QUICK, BIG): the wind-up before the snap, and the furthest the body lunges (before growing).
const WIND := [0.07, 0.13]
const LUNGE := [40.0, 62.0]
const BACK := 12.0
## How long the teeth stay on the spot after a quick snap.
const SNAP_HOLD := 0.16
const HOLD := 0.05
## Seconds of holding right click for a full charge; the big bite's rip, from no charge to full, in bite radii.
const CHARGE_TIME := 0.8
## Level-ups raise these: how far the body lunges, how fast the big bite charges, how long (and hard) the shake.
var lunge_mult := 1.0
var charge_time := CHARGE_TIME
var shake_mult := 1.0
const RIP := [1.5, 2.3]
## The shake: how long (no charge to full), how often it tears, and how big each tear is (in bite radii).
const SHAKE := [0.45, 0.9]
const TEAR_EVERY := 0.07
const TEAR := 0.6
const MOUTH_TIME := 0.35

## Seconds since the current bite started, -1 when not biting; which kind it is.
var bite_t := -1.0
var bite_kind := QUICK
var cool := 0.0
var aim := Vector2.ZERO
## Holding right click: how charged (0..1).
var charging := false
var charge := 0.0
## Clamped onto something: {who, local (the spot in its rig), t, length, breaks_at, tear_t, offset, charge}.
var grab := {}
var _target_prey: Dino = null
var _target_local := Vector2.ZERO
## The part of the prey the spot is on (a part moves within the rig: a slumping body, a swinging leg).
var _target_part: PixelPart = null
var _target_world := Vector2.ZERO
var _snapped := false
var _big_was := false
var _bite_charge := 0.0
var _mouth: Sprite2D
var _mouth_t := 0.0
var _head_base := Vector2.ZERO
var _rest_rot := 0.0
## The last snap: [the spot you aimed at (where it is now on the prey), where the teeth actually went] (tests).
var snap_info: Array = []
## How big you are (1 = the size the art is drawn); eating whole bodies grows you, within the form.
var size := 0.5

func _ready() -> void:
	_mouth = Sprite2D.new()
	_mouth.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mouth.visible = false
	_mouth.z_index = 1
	set_stage(0)
	hp = max_hp

## Becomes form `s`: new art on the rig, the form's size and stats (keeping what levelling up added).
func set_stage(s: int) -> void:
	stage = s
	if _mouth.get_parent():
		_mouth.get_parent().remove_child(_mouth)
	clear_rig()
	var art := ArtLoader.rig(FORM_ART[s])
	build(art if not art.is_empty() else DinoArt.form(s))
	_head_base = head.position
	for part in parts:
		part.carvable = false
	head.add_child(_mouth)
	size = STAGES[s].size
	scale = Vector2(size, size)
	apply_stage()

## The stats from the form plus the level-up bonuses.
func apply_stage() -> void:
	var st: Dictionary = STAGES[stage]
	bite_radius = st.bite + bite_bonus
	walk_speed = st.speed * speed_mult
	bite_cooldown = st.cool * cool_mult
	var was_max := max_hp
	max_hp = st.hp + hp_bonus
	hp = minf(max_hp, hp + maxf(0.0, max_hp - was_max))

func stage_name() -> String:
	return STAGES[stage].name

## Whole bodies eaten to reach the next form (or -1 at the top).
func meals_to_evolve() -> int:
	return STAGES[stage].meals if stage < STAGES.size() - 1 else -1

## `move_x` -1..1, `jump` and `bite_pressed` this frame's presses, `big_held` right click down, `aim_at` the mouse.
func step(delta: float, move_x: float, jump: bool, bite_pressed: bool, aim_at: Vector2, big_held := false) -> void:
	aim = aim_at
	invuln -= delta
	rig.visible = invuln <= 0.0 or int(invuln * 14.0) % 2 == 0
	cool -= delta
	var big_pressed := big_held and not _big_was
	_big_was = big_held
	if not grab.is_empty():
		_grab_step(delta)
		_finish_step(delta)
		return
	if big_pressed and cool <= 0.0 and bite_t < 0.0:
		charging = true
		charge = 0.0
	if charging:
		charge = minf(1.0, charge + delta / charge_time)
		if not big_held:
			charging = false
			_bite_charge = charge
			_start_bite(BIG)
	elif bite_pressed and cool <= 0.0 and bite_t < 0.0:
		_start_bite(QUICK)
	var lunging: bool = bite_t >= 0.0 and bite_t < WIND[bite_kind]
	if not lunging:
		var want := move_x * walk_speed * (0.35 if charging else 1.0)
		vel.x = move_toward(vel.x, want, delta * (900.0 if on_ground else 400.0))
		if bite_t < 0.0 and absf(aim.x - global_position.x) > 4.0:
			set_facing(aim.x - global_position.x)
	if jump and on_ground and not charging:
		vel.y = -JUMP
		on_ground = false
		game.sfx.play("jump", 0.1, -8.0)
	move(delta)
	animate(delta, absf(vel.x) > 5.0, 12.0 * absf(vel.x) / walk_speed)
	# the snap comes after this frame's move, so the head is where it's drawn
	if bite_t >= 0.0:
		bite_t += delta
		if bite_t >= WIND[bite_kind] and not _snapped:
			_snap()
		if grab.is_empty() and bite_t >= WIND[bite_kind] + SNAP_HOLD:
			bite_t = -1.0
	# the body throws itself into a lunge, and crouches while charging
	var lean := 0.0
	if bite_t >= 0.0 and bite_t < WIND[bite_kind]:
		lean = 0.12 if bite_kind == QUICK else 0.2
	rig.rotation = lerpf(rig.rotation, lean * facing, minf(1.0, delta * 30.0))
	rig.position.y = lerpf(rig.position.y, 2.0 * charge if charging else 0.0, minf(1.0, delta * 20.0))
	_finish_step(delta)

func _finish_step(delta: float) -> void:
	_pose_head(delta)
	if _mouth_t > 0.0:
		_mouth_t -= delta
		if _mouth_t <= 0.0:
			_mouth.visible = false
			game.sfx.play("gulp", 0.08)

func _start_bite(kind: int) -> void:
	bite_kind = kind
	bite_t = 0.0
	_snapped = false
	_rest_rot = head.rotation
	_target_prey = game.prey_at(aim)
	if _target_prey:
		_target_part = _target_prey.part_at(aim)
		_target_local = _target_part.to_local(aim)
	_target_world = aim
	var to := aim - neck()
	set_facing(to.x)
	var m := _lunge(to, kind)
	vel.x = m.x / WIND[kind]
	# up high: leap so the head gets there by the snap (rise = v t - g t^2 / 2)
	if m.y < 0.0:
		vel.y = m.y / WIND[kind] - GRAVITY * WIND[kind] * 0.5
		on_ground = false
	game.sfx.play("whoosh", 0.1, -6.0 if kind == QUICK else -2.0)

## The head's length from the neck to where the teeth meet (in the world).
func head_len() -> float:
	return (_tip() + head.offset).length() * size * art_k

## How far the body lunges for a spot `to` away from the neck: until the head just reaches it (stepping back for
## one right under your nose), at most LUNGE for that bite, and only up (a leap).
func _lunge(to: Vector2, kind: int) -> Vector2:
	var want := to - to.normalized() * head_len() * 0.95
	var fwd := signf(to.x) if to.x != 0.0 else facing
	var along := clampf(want.x * fwd, -BACK * size, LUNGE[kind] * size * lunge_mult)
	return Vector2(along * fwd, clampf(want.y, -LUNGE[kind] * size * lunge_mult, 0.0))

## Where a bite at `p` started now would land (the aim marker): after the lunge, the nearest point the head reaches.
func predict_bite(p: Vector2, kind := QUICK) -> Vector2:
	# a bite turns you to face the spot first, which moves the neck to that side
	var n := neck() - global_position
	if signf(p.x - global_position.x) * facing < 0.0:
		n.x = -n.x
	var from := global_position + n
	from += _lunge(p - from, kind)
	return from + (p - from).limit_length(head_len())

func target_point() -> Vector2:
	var p := _target_world
	if _target_prey and is_instance_valid(_target_prey):
		p = _target_part.to_global(_target_local)
	return clamp_reach(p)

## `p`, or the nearest point to it the head reaches from where the neck is now.
func clamp_reach(p: Vector2) -> Vector2:
	var from := neck()
	return from + (p - from).limit_length(head_len())

func _snap() -> void:
	_snapped = true
	# the lunge stops dead on the snap (a leap just hangs there and drops)
	vel.x = 0.0
	vel.y = maxf(vel.y, 0.0)
	var wanted := _target_world
	if _target_prey and is_instance_valid(_target_prey):
		wanted = _target_part.to_global(_target_local)
	var p := clamp_reach(wanted)
	snap_info = [wanted, p]
	_target_world = p
	if bite_kind == QUICK:
		cool = bite_cooldown
		game.player_bite(self, p, bite_radius)
		return
	cool = bite_cooldown * 1.6
	var who: Prey = game.big_bite(self, p, _bite_charge)
	if who:
		grab = {
			"who": who, "part": who.part_at(p), "local": who.part_at(p).to_local(p), "t": 0.0, "charge": _bite_charge,
			"length": lerpf(SHAKE[0], SHAKE[1], _bite_charge) * shake_mult, "tear_t": 0.0, "offset": global_position - p,
		}
		grab["breaks_at"] = game.break_free_time(self, who, grab.length)
		who.held = true

## Clamped on: the body is locked to the spot (it moves with them), the head shakes, a tear every TEAR_EVERY,
## and at the end the rip; or they break free first.
func _grab_step(delta: float) -> void:
	# (it may have been eaten up or tidied away under you)
	if not is_instance_valid(grab.who) or not game.creatures.has(grab.who):
		release()
		return
	var who: Prey = grab.who
	grab.t += delta
	var spot: Vector2 = (grab.part as PixelPart).to_global(grab.local)
	var jolt := sin(grab.t * 42.0)
	global_position = spot + grab.offset + Vector2(jolt * 2.0 * size, 0)
	vel = Vector2.ZERO
	_target_world = spot
	bite_t = WIND[BIG]
	grab.tear_t -= delta
	if grab.tear_t <= 0.0:
		grab.tear_t = TEAR_EVERY
		var r := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * bite_radius * 0.8
		game.grab_tear(self, who, spot + r, bite_radius * TEAR)
	if grab.t >= grab.breaks_at and not who.dead:
		game.broke_free(self, who)
		release()
	elif grab.t >= grab.length:
		game.grab_rip(self, who, spot, bite_radius * lerpf(RIP[0], RIP[1], grab.charge) * sqrt(shake_mult))
		release()
	animate(delta, false, 0.0)

## Lets go (after the rip, when they break free, or when you're hit).
func release() -> void:
	if not grab.is_empty() and is_instance_valid(grab.who):
		(grab.who as Prey).held = false
	grab = {}
	bite_t = -1.0
	rig.rotation = 0.0
	vel = Vector2(-facing * 50.0, -60.0)
	on_ground = false

## Bitten by a hunter at `from`: loses `amount` health (unless still blinking from the last hit), knocked away.
## True if it hurt.
func hurt(amount: float, from: Vector2) -> bool:
	if invuln > 0.0 or hp <= 0.0:
		return false
	if not grab.is_empty():
		release()
	hp = maxf(0.0, hp - amount)
	invuln = 0.6
	flash = 0.08
	charging = false
	charge = 0.0
	var away := signf(global_position.x - from.x)
	vel = Vector2((away if away != 0.0 else -facing) * 140.0, -90.0)
	on_ground = false
	bite_t = -1.0
	return true

## Out of health: slumped over on the ground.
func die_look() -> void:
	dead = true
	rig.visible = true
	rig.rotation = -facing * 0.35
	rig.position.y = 5.0
	for l in legs:
		(l[0] as PixelPart).rotation = 1.2 if l[1] == 0.0 else -0.9
	head.rotation = 0.5
	jaw.rotation = 0.6

## True if `p` is on (or within `margin` of) your body: a box from your feet to your back, nose to tail.
func covers(p: Vector2, margin: float) -> bool:
	var d := p - global_position
	return absf(d.x) < half_w * 2.0 * size + margin and d.y > -height * size - margin and d.y < margin

func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)

## A little bigger (after finishing a meal), up to this form's limit.
func grow(amount: float) -> void:
	size = minf(STAGES[stage].max_size, size + amount)
	scale = Vector2(size, size)

## How much of you there is (pixels, grown), to compare with what you grab.
func mass() -> float:
	var n := 0
	for part in parts:
		n += part.pixels_total()
	return n * size * size * art_k * art_k

## Holds a bitten-off chunk (a picture in the head's own frame) in the mouth for a moment, then swallows it.
func hold(img: Image) -> void:
	if img == null:
		return
	_mouth.texture = ImageTexture.create_from_image(img)
	_mouth.position = _tip() + head.offset + Vector2(-2, 0)
	_mouth.visible = true
	_mouth_t = MOUTH_TIME

## Where the teeth meet, in the head's pixels.
func _tip() -> Vector2:
	return head.get_meta("tip")

## Where the teeth meet, in the world.
func jaw_tip() -> Vector2:
	return head.to_world(_tip())

## Off a bite, the head turns toward the aim. On a bite, it turns so the teeth meet exactly on the spot (solved,
## not eased, by the snap); for a spot closer than the head is long, the neck pulls in a little. The jaw opens on
## the wind-up (wider charging), snaps shut on the spot, and while clamped on the head thrashes.
func _pose_head(delta: float) -> void:
	var parent := head.get_parent() as Node2D
	if bite_t < 0.0:
		var l := parent.to_local(aim) - _head_base
		var want := clampf(atan2(l.y, maxf(l.x, 1.0)), -1.0, 0.8)
		head.rotation = lerp_angle(head.rotation, want, minf(1.0, delta * 10.0))
		head.position = head.position.lerp(_head_base, minf(1.0, delta * 20.0))
	else:
		var goal := target_point() if not _snapped else _target_world
		var d := parent.to_local(goal) - _head_base
		var t := _tip() + head.offset
		d = d.limit_length(t.length())
		var s := clampf(sqrt(maxf(d.length_squared() - t.y * t.y, 0.0)) - t.x, 2.0 - t.x, 0.0)
		var rot := d.angle() - Vector2(s + t.x, t.y).angle()
		var k := 1.0
		var wind: float = WIND[bite_kind]
		if bite_t < wind:
			k = bite_t / wind
		elif grab.is_empty() and bite_t > wind + HOLD:
			k = maxf(0.0, 1.0 - (bite_t - wind - HOLD) / (SNAP_HOLD - HOLD))
		head.rotation = lerp_angle(_rest_rot, rot, k)
		head.position = _head_base + Vector2(cos(rot), sin(rot)) * s * k
		if not grab.is_empty():
			head.rotation += sin(grab.t * 42.0) * 0.18
	var open := 0.0
	if charging:
		open = 0.3 + charge * 0.7
	elif bite_t >= 0.0 and bite_t < WIND[bite_kind]:
		open = 0.9 if bite_kind == QUICK else 1.1
	elif _mouth_t > 0.0:
		open = 0.15
	jaw.rotation = lerpf(jaw.rotation, open, minf(1.0, delta * (40.0 if open < jaw.rotation else 25.0)))

## Where the neck meets the head (at rest): the head reaches from here.
func neck() -> Vector2:
	return (head.get_parent() as Node2D).to_global(_head_base)
