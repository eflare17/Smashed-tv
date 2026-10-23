class_name Player
extends Dino
## You: walk, jump, and bite where the mouse points. A bite is a short wind-up (jaw opens, a lunge toward the spot)
## then the snap: the scene root carves the prey at that spot (it remembers the spot on the prey's body, so a
## moving prey still gets bitten where you aimed). Out of reach, you snap at the closest point you can reach.
## Hunters bite back: hurt() takes health, knocks you away and gives a moment of blinking safety.

## The stats levelling up raises (main.gd's UPGRADES). Placeholder numbers, set by feel.
var bite_radius := 4.5
var bite_cooldown := 0.42
var walk_speed := 75.0
var reach := 42.0

## Health. Hunters' bites take it; eating gives it back. PLACEHOLDER numbers.
var max_hp := 100.0
var hp := 100.0
## Seconds you can't be hurt again after a hit (and blink).
var invuln := 0.0

const JUMP := 200.0
const WIND := 0.09
const SNAP_HOLD := 0.18
## Most the body lunges forward on a bite (before growing), and how long the teeth stay on the spot after the snap.
const LUNGE := 34.0
const HOLD := 0.06
const BACK := 12.0
const MAX_SIZE := 2.0
const MOUTH_TIME := 0.35

## Seconds since the current bite started, -1 when not biting.
var bite_t := -1.0
var cool := 0.0
var aim := Vector2.ZERO
var _target_prey: Dino = null
var _target_local := Vector2.ZERO
var _target_world := Vector2.ZERO
var _snapped := false
var _mouth: Sprite2D
var _mouth_t := 0.0
var _head_base := Vector2.ZERO
var _rest_rot := 0.0
var _neck: Node2D
## The last snap: [the spot you aimed at (where it is now on the prey), where the teeth actually went] (tests).
var snap_info: Array = []
## How big you are (1 = as you start); eating whole prey grows you.
var size := 1.0

func _ready() -> void:
	build(DinoArt.player())
	_head_base = head.position
	for part in parts:
		part.carvable = false
	# the stretched neck between the body and the head while it shoots out on a bite
	_neck = Node2D.new()
	_neck.z_index = 1
	_neck.use_parent_material = true
	_neck.draw.connect(_draw_neck)
	head.get_parent().add_child(_neck)
	_mouth = Sprite2D.new()
	_mouth.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mouth.visible = false
	_mouth.z_index = 1
	head.add_child(_mouth)

## `move` -1..1, `jump` and `bite` this frame's presses, `aim_at` the mouse in the world.
func step(delta: float, move_x: float, jump: bool, bite_pressed: bool, aim_at: Vector2) -> void:
	aim = aim_at
	invuln -= delta
	rig.visible = invuln <= 0.0 or int(invuln * 14.0) % 2 == 0
	cool -= delta
	if bite_pressed and cool <= 0.0 and bite_t < 0.0:
		_start_bite()
	var lunging := bite_t >= 0.0 and bite_t < WIND
	if not lunging:
		var want := move_x * walk_speed
		vel.x = move_toward(vel.x, want, delta * (900.0 if on_ground else 400.0))
		if bite_t < 0.0 and absf(aim.x - global_position.x) > 4.0:
			set_facing(aim.x - global_position.x)
	if jump and on_ground:
		vel.y = -JUMP
		on_ground = false
		game.sfx.play("jump", 0.1, -8.0)
	move(delta)
	animate(delta, absf(vel.x) > 5.0, 12.0 * absf(vel.x) / walk_speed)
	# the snap comes after this frame's move, so the neck is where it's drawn
	if bite_t >= 0.0:
		bite_t += delta
		if bite_t >= WIND and not _snapped:
			_snap()
		if bite_t >= WIND + SNAP_HOLD:
			bite_t = -1.0
	_pose_head(delta)
	if _mouth_t > 0.0:
		_mouth_t -= delta
		if _mouth_t <= 0.0:
			_mouth.visible = false
			game.sfx.play("gulp", 0.08)

func _start_bite() -> void:
	bite_t = 0.0
	_snapped = false
	_rest_rot = head.rotation
	_target_prey = game.prey_at(aim)
	if _target_prey:
		_target_local = _target_prey.rig.to_local(aim)
	_target_world = aim
	var to := aim - neck()
	set_facing(to.x)
	var m := _lunge(to)
	vel.x = m.x / WIND
	# up high: leap so the neck gets there by the snap (rise = v t - g t^2 / 2)
	if m.y < 0.0:
		vel.y = m.y / WIND - GRAVITY * WIND * 0.5
		on_ground = false
	game.sfx.play("whoosh", 0.1, -6.0)

## How far the body lunges for a spot `to` away from the neck: along the line to it until the spot is at a
## comfortable bite distance (stepping back for one right under your nose), at most LUNGE, and only up (a leap).
func _lunge(to: Vector2) -> Vector2:
	var comfy := reach * size * 0.7
	var move := to - to.normalized() * comfy
	var fwd := signf(to.x) if to.x != 0.0 else facing
	var along := clampf(move.x * fwd, -BACK * size, LUNGE * size)
	return Vector2(along * fwd, clampf(move.y, -LUNGE * size, 0.0))

## Where a bite at `p` started now would land: after the lunge, the nearest point within reach (the aim marker).
func predict_bite(p: Vector2) -> Vector2:
	# a bite turns you to face the spot first, which moves the neck to that side
	var n := neck() - global_position
	if signf(p.x - global_position.x) * facing < 0.0:
		n.x = -n.x
	var from := global_position + n
	from += _lunge(p - from)
	return from + (p - from).limit_length(reach * size)

func target_point() -> Vector2:
	var p := _target_world
	if _target_prey and is_instance_valid(_target_prey):
		p = _target_prey.rig.to_global(_target_local)
	return clamp_reach(p)

## `p`, or the nearest point to it within reach of the neck.
func clamp_reach(p: Vector2) -> Vector2:
	var from := neck()
	return from + (p - from).limit_length(reach * size)

func _snap() -> void:
	_snapped = true
	# the lunge stops dead on the snap (a leap just hangs there and drops)
	vel.x = 0.0
	vel.y = maxf(vel.y, 0.0)
	cool = bite_cooldown
	var wanted := _target_world
	if _target_prey and is_instance_valid(_target_prey):
		wanted = _target_prey.rig.to_global(_target_local)
	var p := clamp_reach(wanted)
	snap_info = [wanted, p]
	_target_world = p
	game.player_bite(self, p)

## Bitten by a hunter at `from`: loses `amount` health (unless still blinking from the last hit), knocked away.
## True if it hurt.
func hurt(amount: float, from: Vector2) -> bool:
	if invuln > 0.0 or hp <= 0.0:
		return false
	hp = maxf(0.0, hp - amount)
	invuln = 0.6
	flash = 0.08
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
	return absf(d.x) < 16.0 * size + margin and d.y > -30.0 * size - margin and d.y < margin

func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)

## A little bigger (after finishing a meal), up to MAX_SIZE.
func grow(amount: float) -> void:
	size = minf(MAX_SIZE, size + amount)
	scale = Vector2(size, size)

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

## Off a bite, the head turns toward the aim. On a bite, the neck stretches and the head turns so the teeth meet
## exactly on the spot (solved, not eased, by the snap), then it holds there a moment and pulls back. The jaw
## opens on the wind-up and snaps shut on the spot.
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
		# the teeth, seen from the head's pivot; put them on `d` by stretching the neck along the head's own line
		var t := _tip() + head.offset
		# (negative: the neck pulls in, for a spot closer than the head is long)
		var s := maxf(2.0 - t.x, sqrt(maxf(d.length_squared() - t.y * t.y, 0.0)) - t.x)
		var rot := d.angle() - Vector2(s + t.x, t.y).angle()
		var k := 1.0
		if bite_t < WIND:
			k = bite_t / WIND
		elif bite_t > WIND + HOLD:
			k = maxf(0.0, 1.0 - (bite_t - WIND - HOLD) / (SNAP_HOLD - HOLD))
		head.rotation = lerp_angle(_rest_rot, rot, k)
		head.position = _head_base + Vector2(cos(rot), sin(rot)) * s * k
	_neck.queue_redraw()
	var open := 0.0
	if bite_t >= 0.0 and bite_t < WIND:
		open = 0.9
	elif _mouth_t > 0.0:
		open = 0.15
	jaw.rotation = lerpf(jaw.rotation, open, minf(1.0, delta * (40.0 if open < jaw.rotation else 25.0)))

func _draw_neck() -> void:
	var a := _head_base + Vector2(-4, 2)
	var b := head.position
	if a.distance_to(b) < 5.0:
		return
	var skin: Color = DinoArt.PLAYER_SKIN
	_neck.draw_line(a.round(), b.round(), skin.darkened(0.55), 6.0)
	_neck.draw_line(a.round(), b.round(), skin, 4.0)
	_neck.draw_line(a.round() + Vector2(0, -1), b.round() + Vector2(0, -1), skin.lightened(0.18), 1.0)

## Where the neck meets the head (at rest): reach is measured from here.
func neck() -> Vector2:
	return (head.get_parent() as Node2D).to_global(_head_base)
