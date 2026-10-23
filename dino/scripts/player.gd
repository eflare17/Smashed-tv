class_name Player
extends Dino
## You: walk, jump, and bite where the mouse points. A bite is a short wind-up (jaw opens, a lunge toward the spot)
## then the snap: the scene root carves the prey at that spot (it remembers the spot on the prey's body, so a
## moving prey still gets bitten where you aimed). Out of reach, you snap at the closest point you can reach.


## The stats levelling up will raise (step 2). Placeholder numbers, set by feel.
var bite_radius := 4.5
var bite_cooldown := 0.42
var walk_speed := 75.0
var reach := 42.0

const JUMP := 200.0
const WIND := 0.09
const SNAP_HOLD := 0.18
const LUNGE := 190.0
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

func _ready() -> void:
	build(DinoArt.player())
	_head_base = head.position
	for part in parts:
		part.carvable = false
	_mouth = Sprite2D.new()
	_mouth.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mouth.visible = false
	_mouth.z_index = 1
	head.add_child(_mouth)

## `move` -1..1, `jump` and `bite` this frame's presses, `aim_at` the mouse in the world.
func step(delta: float, move_x: float, jump: bool, bite_pressed: bool, aim_at: Vector2) -> void:
	aim = aim_at
	cool -= delta
	if bite_pressed and cool <= 0.0 and bite_t < 0.0:
		_start_bite()
	var lunging := bite_t >= 0.0 and bite_t < WIND
	if bite_t >= 0.0:
		bite_t += delta
		if bite_t >= WIND and not _snapped:
			_snap()
		if bite_t >= WIND + SNAP_HOLD:
			bite_t = -1.0
	if not lunging:
		var want := move_x * walk_speed
		vel.x = move_toward(vel.x, want, delta * (900.0 if on_ground else 400.0))
		if bite_t < 0.0 and absf(aim.x - global_position.x) > 4.0:
			set_facing(aim.x - global_position.x)
	if jump and on_ground:
		vel.y = -JUMP
		on_ground = false
		game.sfx.play("jump", 0.1, -8.0)
	move(delta, game.GROUND_Y, 12.0, game.WORLD_W - 12.0)
	animate(delta, absf(vel.x) > 5.0, 12.0 * absf(vel.x) / walk_speed)
	_pose_head(delta)
	if _mouth_t > 0.0:
		_mouth_t -= delta
		if _mouth_t <= 0.0:
			_mouth.visible = false
			game.sfx.play("gulp", 0.08)

func _start_bite() -> void:
	bite_t = 0.0
	_snapped = false
	_target_prey = game.prey_at(aim)
	if _target_prey:
		_target_local = _target_prey.rig.to_local(aim)
	_target_world = aim
	var to := aim - neck()
	set_facing(to.x)
	# lunge toward the spot: further for a far one, and a hop if it's up high
	vel.x = signf(to.x) * LUNGE * clampf(absf(to.x) / reach, 0.3, 1.0)
	if on_ground and to.y < -10.0:
		vel.y = -minf(170.0, -to.y * 4.0)
		on_ground = false
	game.sfx.play("whoosh", 0.1, -6.0)

func target_point() -> Vector2:
	var p := _target_world
	if _target_prey and is_instance_valid(_target_prey):
		p = _target_prey.rig.to_global(_target_local)
	return clamp_reach(p)

## `p`, or the nearest point to it within reach of the neck.
func clamp_reach(p: Vector2) -> Vector2:
	var from := neck()
	var d := p - from
	return from + d.limit_length(reach)

func _snap() -> void:
	_snapped = true
	cool = bite_cooldown
	var p := target_point()
	_target_world = p
	game.player_bite(self, p)

## Holds a bitten-off chunk (a picture in the head's own frame) in the mouth for a moment, then swallows it.
func hold(img: Image) -> void:
	if img == null:
		return
	_mouth.texture = ImageTexture.create_from_image(img)
	var tip: Vector2 = head.get_meta("tip")
	_mouth.position = tip + head.offset + Vector2(-3, 0)
	_mouth.visible = true
	_mouth_t = MOUTH_TIME

func jaw_tip() -> Vector2:
	return head.to_world(head.get_meta("tip"))

## The head turns toward the aim (toward the bite target while biting); the jaw opens on the wind-up.
func _pose_head(delta: float) -> void:
	var look := aim
	if bite_t >= 0.0:
		look = target_point() if not _snapped else _target_world
	var l := (head.get_parent() as Node2D).to_local(look) - _head_base
	var want := clampf(atan2(l.y, maxf(l.x, 1.0)), -1.0, 0.8)
	head.rotation = lerp_angle(head.rotation, want, minf(1.0, delta * (30.0 if bite_t >= 0.0 else 10.0)))
	# the neck shoots out on a bite so the jaws reach the spot, then pulls back
	var stretch := 0.0
	if bite_t >= 0.0:
		var tip: Vector2 = head.get_meta("tip")
		var head_len := (tip + head.offset).length()
		stretch = clampf(l.length() - head_len, 0.0, reach - head_len)
		stretch *= minf(1.0, bite_t / WIND) if bite_t < WIND else maxf(0.0, 1.0 - (bite_t - WIND) / SNAP_HOLD)
	head.position = _head_base + Vector2(cos(head.rotation), sin(head.rotation)) * stretch
	var open := 0.0
	if bite_t >= 0.0 and bite_t < WIND:
		open = 0.9
	elif _mouth_t > 0.0:
		open = 0.15
	jaw.rotation = lerpf(jaw.rotation, open, minf(1.0, delta * (40.0 if open < jaw.rotation else 25.0)))

## Where the neck meets the head (at rest): reach is measured from here.
func neck() -> Vector2:
	return (head.get_parent() as Node2D).to_global(_head_base)
