class_name Touch
extends Node2D
## Phone and tablet controls. It switches itself on at the first touch (and back off if a real mouse moves), so
## the mouse and keyboard keep working on a PC.
##  - Touch a creature (anywhere on the screen) and that's where you bite: a quick tap is a quick bite, holding
##    charges the big bite and letting go bites with it, right on that spot.
##  - Left half, off any creature: a stick that appears where your thumb lands. Drag left/right to walk; a quick
##    swipe up jumps.
##  - Bottom right: the JUMP button, and beside it BITE (the rest of the right half works as BITE too). BITE goes
##    for the spot you last touched on the nearest creature, or its body; tap or hold it like a creature.
## main.gd reads move_x, jump, bite, big and aim_point each frame (and calls clear_presses after); the HUD drawing
## is here, on its own CanvasLayer child so it sits over the game in screen space.

const DinoArt := preload("dino_art.gd")

## How long a bite touch can last and still be a tap (a quick bite, not a charge).
const TAP_TIME := 0.18
## How far the left thumb drags for full speed, and a swipe up that jumps (px, within a short time).
const STICK := 22.0
const JUMP_SWIPE := 16.0
const JUMP_TIME := 0.25
## How far to look for something to lock onto.
const LOCK_RANGE := 170.0
## A fingertip is fat: a touch this close (screen px) to a creature still counts as on it.
const FINGER := 10.0
## The buttons, from the bottom-right corner: [offset of the centre, radius].
const BITE_BTN := [Vector2(-46, -50), 20.0]
const JUMP_BTN := [Vector2(-98, -34), 16.0]

var game: Node
var active := false

## This frame's controls, for main.gd.
var move_x := 0.0
var jump := false
var bite := false
var big := false
var aim_point := Vector2.ZERO
var target: Prey = null

var _left_id := -1
var _left_start := Vector2.ZERO
var _left_at := Vector2.ZERO
var _left_t := 0.0
var _left_jumped := false
## The finger biting: on a creature, or on BITE.
var _bite_id := -1
var _bite_t := 0.0
var _jump_id := -1
## The spot you last touched: a pixel of one of the creature's parts, so it moves with it.
var _spot_part: PixelPart = null
var _spot_px := Vector2.ZERO
var _layer: CanvasLayer
var _ui: Node2D

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 9
	add_child(_layer)
	_ui = Node2D.new()
	_ui.draw.connect(_draw_ui)
	_layer.add_child(_ui)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		active = true
		handle(event)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		# a real mouse: back to mouse and keyboard
		if (event as InputEventMouseMotion).relative.length() > 2.0:
			active = false

## Touch events, in screen (viewport) coordinates. Also called by the tests.
func handle(event: InputEvent) -> void:
	var vp := get_viewport().get_visible_rect().size
	if game and not game.playing():
		# level-up cards and the death screen: a lifted finger is a tap on them, and nothing stays held
		if event is InputEventScreenTouch and not event.pressed:
			game.touch_tap(event.position)
		_left_id = -1
		_bite_id = -1
		_jump_id = -1
		move_x = 0.0
		big = false
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _jump_id < 0 and _on_button(t.position, JUMP_BTN, vp):
				_jump_id = t.index
				jump = true
			elif _bite_id < 0 and _touch_creature(t.position):
				_bite_id = t.index
				_bite_t = 0.0
			elif t.position.x < vp.x * 0.5 and _left_id < 0:
				_left_id = t.index
				_left_start = t.position
				_left_at = t.position
				_left_t = 0.0
				_left_jumped = false
			elif t.position.x >= vp.x * 0.5 and _bite_id < 0:
				# BITE (or anywhere else on the right): the last spot, or the nearest creature's body
				_bite_id = t.index
				_bite_t = 0.0
		else:
			if t.index == _left_id:
				_left_id = -1
				move_x = 0.0
			elif t.index == _bite_id:
				# a short touch is a quick bite; a long one lets the charged big bite go
				if _bite_t < TAP_TIME:
					bite = true
				_bite_id = -1
				big = false
			elif t.index == _jump_id:
				_jump_id = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _left_id:
			_left_at = d.position
			var off := _left_at - _left_start
			move_x = clampf(off.x / STICK, -1.0, 1.0)
			if absf(move_x) < 0.2:
				move_x = 0.0
			if not _left_jumped and off.y < -JUMP_SWIPE and _left_t < JUMP_TIME:
				jump = true
				_left_jumped = true
			# a slow drag up re-centres, so walking after a jump doesn't need lifting the thumb
			if _left_jumped and _left_t >= JUMP_TIME:
				_left_start.y = _left_at.y

func _on_button(at: Vector2, btn: Array, vp: Vector2) -> bool:
	# a little bigger than it's drawn: thumbs miss
	return at.distance_to(vp + (btn[0] as Vector2)) < (btn[1] as float) + 6.0

## A touch at `at` (screen): if it's on (or a fingertip from) a creature, that spot becomes the aim. True if it was.
func _touch_creature(at: Vector2) -> bool:
	if game == null:
		return false
	var world := get_canvas_transform().affine_inverse() * at
	var within := FINGER / maxf(0.01, get_canvas_transform().get_scale().x)
	var best: Array = []
	var bd := INF
	for i in range(game.creatures.size() - 1, -1, -1):
		var c: Prey = game.creatures[i]
		var hit := _nearest_pixel(c, world, within)
		if hit.size() > 0 and (hit[2] as float) < bd:
			bd = hit[2]
			best = hit
			target = c
	if best.is_empty():
		return false
	_spot_part = best[0]
	_spot_px = best[1]
	return true

## The live pixel of `c` nearest `world`, no further than `within`: [part, pixel, distance], or [].
func _nearest_pixel(c: Prey, world: Vector2, within: float) -> Array:
	var best: Array = []
	var bd := within
	for part in c.parts:
		if not part.carvable:
			continue
		var s := maxf(0.01, absf(part.global_scale.x))
		var r := ceili(within / s) + 1
		var p := part.to_pixel(world)
		for y in range(maxi(0, floori(p.y) - r), mini(part.h, floori(p.y) + r + 1)):
			for x in range(maxi(0, floori(p.x) - r), mini(part.w, floori(p.x) + r + 1)):
				if part.alive[y * part.w + x] != 1:
					continue
				var px := Vector2(x + 0.5, y + 0.5)
				var dd := part.to_world(px).distance_to(world)
				if dd <= bd:
					bd = dd
					best = [part, px, dd]
	return best

## Ticks the timers, holds the charge, keeps the aim fresh. Called by main.gd once per frame.
func step(delta: float, player: Player) -> void:
	_left_t += delta
	if _bite_id >= 0:
		_bite_t += delta
		big = _bite_t >= TAP_TIME
	_update_aim(player)
	_ui.queue_redraw()

func clear_presses() -> void:
	jump = false
	bite = false

func _alive(c: Prey) -> bool:
	return c != null and is_instance_valid(c) and game.creatures.has(c)

func _update_aim(player: Player) -> void:
	var neck := player.neck()
	if target and (not _alive(target) or target.global_position.distance_to(neck) > LOCK_RANGE * 1.2):
		target = null
		_spot_part = null
	# the spot you touched, while there's something left there (bitten away: the nearest bit of it that's left)
	if target and _spot_part:
		if not is_instance_valid(_spot_part) or not target.parts.has(_spot_part):
			_spot_part = null
		elif _spot_part.alive[int(_spot_px.y) * _spot_part.w + int(_spot_px.x)] != 1:
			var hit := _nearest_pixel(target, _spot_part.to_world(_spot_px), 14.0)
			_spot_part = hit[0] if hit.size() > 0 else null
			if _spot_part:
				_spot_px = hit[1]
		if _spot_part:
			aim_point = _spot_part.to_world(_spot_px)
			return
	# nothing touched: the nearest thing wins, unless the current lock is nearly as close (no flicking between two)
	var best: Prey = null
	var best_d := LOCK_RANGE
	for c: Prey in game.creatures:
		var dd := c.global_position.distance_to(neck)
		if dd < best_d:
			best_d = dd
			best = c
	if target == null or (best and best != target and best_d < target.global_position.distance_to(neck) * 0.6):
		target = best
	if target == null:
		aim_point = neck + Vector2(player.facing * 30.0, 0.0)
		return
	aim_point = _body_point(target, neck)

## The pixel of the body nearest your neck (or of whatever's left, if the body's gone).
func _body_point(c: Prey, from: Vector2) -> Vector2:
	for zone in [DinoArt.BODY, -1]:
		var best := Vector2.INF
		var bd := INF
		for p in c.parts:
			# every other pixel: plenty for picking a spot
			for i in range(0, p.w * p.h, 2):
				if p.alive[i] == 1 and (zone < 0 or p.zone[i] == zone):
					var w := p.to_world(Vector2(i % p.w + 0.5, i / p.w + 0.5))
					var dd := w.distance_squared_to(from)
					if dd < bd:
						bd = dd
						best = w
		if bd < INF:
			return best
	return c.global_position + Vector2(0, -c.height * 0.5)

## Which part the aim is on, by name (tests).
func part_name() -> String:
	if target == null:
		return ""
	return DinoArt.ZONE_NAMES[target.zone_at(aim_point)]

func _draw_ui() -> void:
	if not active or game == null or game.state != game.PLAY:
		return
	var vp := get_viewport().get_visible_rect().size
	var font := ThemeDB.fallback_font
	# the stick, where the thumb is
	if _left_id >= 0:
		_ui.draw_circle(_left_start, STICK, Color(1, 1, 1, 0.08))
		_ui.draw_arc(_left_start, STICK, 0.0, TAU, 24, Color(1, 1, 1, 0.3), 1.0)
		var knob := _left_start + (_left_at - _left_start).limit_length(STICK)
		_ui.draw_circle(knob, 7.0, Color(1, 1, 1, 0.35))
	else:
		_ui.draw_string(font, Vector2(14, vp.y - 26), "DRAG HERE: MOVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.4))
		_ui.draw_string(font, Vector2(14, vp.y - 15), "TOUCH A CREATURE: BITE IT THERE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.4))
	# the bite button, bottom right, filling as the big bite charges
	var btn: Vector2 = vp + BITE_BTN[0]
	var br: float = BITE_BTN[1]
	_ui.draw_circle(btn, br, Color(1, 0.3, 0.2, 0.18 if _bite_id < 0 else 0.35))
	_ui.draw_arc(btn, br, 0.0, TAU, 28, Color(1, 0.5, 0.4, 0.6), 1.0)
	if game.player.charging:
		_ui.draw_arc(btn, br + 3.0, -PI * 0.5, -PI * 0.5 + TAU * game.player.charge, 28, Color(1, 0.55, 0.2), 2.0)
	_label(font, btn, "BITE" if not game.player.charging else "BIG")
	# the jump button beside it
	var jb: Vector2 = vp + JUMP_BTN[0]
	var jr: float = JUMP_BTN[1]
	_ui.draw_circle(jb, jr, Color(0.4, 0.7, 1.0, 0.18 if _jump_id < 0 else 0.35))
	_ui.draw_arc(jb, jr, 0.0, TAU, 24, Color(0.6, 0.8, 1.0, 0.6), 1.0)
	_label(font, jb, "JUMP")

func _label(font: Font, at: Vector2, text: String) -> void:
	var lw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_ui.draw_string(font, at + Vector2(-lw * 0.5, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.8))
