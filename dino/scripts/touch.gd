class_name Touch
extends Node2D
## Phone and tablet controls. It switches itself on at the first touch (and back off if a real mouse moves), so
## the mouse and keyboard keep working on a PC.
##  - Left half of the screen: a stick that appears where your thumb lands. Drag left/right to walk; a quick
##    swipe up jumps.
##  - Right half: the bite. Aim is automatic: it locks onto the nearest creature, and a flick up or down picks
##    which part you're going for (head, neck, body, tail, legs), shown lit up on the creature and in the list at
##    the right edge. A tap is a quick bite; hold to charge the big bite and let go to bite.
## main.gd reads move_x, jump, bite, big and aim_point each frame (and calls clear_presses after); the HUD drawing
## is here, on its own CanvasLayer child so it sits over the game in screen space.

const DinoArt := preload("dino_art.gd")

## Parts in the order a flick walks them (up = toward the head).
const PARTS := [DinoArt.HEAD, DinoArt.NECK, DinoArt.BODY, DinoArt.TAIL, DinoArt.LEGS]
## How long a right-side touch can last and still be a tap (not a charge), and how far it can move.
const TAP_TIME := 0.18
const FLICK := 14.0
## How far the left thumb drags for full speed, and a swipe up that jumps (px, within a short time).
const STICK := 22.0
const JUMP_SWIPE := 16.0
const JUMP_TIME := 0.25
## How far to look for something to lock onto.
const LOCK_RANGE := 170.0

var game: Node
var active := false

## This frame's controls, for main.gd.
var move_x := 0.0
var jump := false
var bite := false
var big := false
var aim_point := Vector2.ZERO
var target: Prey = null
var part := 2

var _left_id := -1
var _left_start := Vector2.ZERO
var _left_at := Vector2.ZERO
var _left_t := 0.0
var _left_jumped := false
var _right_id := -1
var _right_start := Vector2.ZERO
var _right_t := 0.0
var _right_flicked := false
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
	var half: float = get_viewport().get_visible_rect().size.x * 0.5
	if game and not game.playing():
		# level-up cards and the death screen: a lifted finger is a tap on them, and nothing stays held
		if event is InputEventScreenTouch and not event.pressed:
			game.touch_tap(event.position)
		_left_id = -1
		_right_id = -1
		move_x = 0.0
		big = false
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if t.position.x < half and _left_id < 0:
				_left_id = t.index
				_left_start = t.position
				_left_at = t.position
				_left_t = 0.0
				_left_jumped = false
			elif t.position.x >= half and _right_id < 0:
				_right_id = t.index
				_right_start = t.position
				_right_t = 0.0
				_right_flicked = false
		else:
			if t.index == _left_id:
				_left_id = -1
				move_x = 0.0
			elif t.index == _right_id:
				# a short touch that didn't flick is a quick bite; a long one lets the charged big bite go
				if not _right_flicked and _right_t < TAP_TIME:
					bite = true
				_right_id = -1
				big = false
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
		elif d.index == _right_id and not _right_flicked and _right_t < TAP_TIME:
			var dy := d.position.y - _right_start.y
			if absf(dy) > FLICK:
				_right_flicked = true
				part = clampi(part + (-1 if dy < 0 else 1), 0, PARTS.size() - 1)
				if game:
					game.sfx.play("snap", 0.2, -14.0)

## Ticks the timers, holds the charge, keeps the lock fresh. Called by main.gd once per frame.
func step(delta: float, player: Player) -> void:
	_left_t += delta
	if _right_id >= 0:
		_right_t += delta
		big = not _right_flicked and _right_t >= TAP_TIME
	_update_lock(player)
	_ui.queue_redraw()

func clear_presses() -> void:
	jump = false
	bite = false

func _update_lock(player: Player) -> void:
	var neck := player.neck()
	if target and (not is_instance_valid(target) or not game.creatures.has(target)
			or target.global_position.distance_to(neck) > LOCK_RANGE * 1.2):
		target = null
	# the nearest thing wins, unless the current lock is nearly as close (no flicking between two)
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
	aim_point = _part_point(target, neck)

## The pixel of the chosen part nearest your neck (or of the nearest part it has, if it hasn't that one).
func _part_point(c: Prey, from: Vector2) -> Vector2:
	var order: Array = [part]
	for k in range(1, PARTS.size()):
		order.append(part - k)
		order.append(part + k)
	for idx in order:
		if idx < 0 or idx >= PARTS.size():
			continue
		var zone: int = PARTS[idx]
		if c is Flyer and zone == DinoArt.LEGS:
			zone = DinoArt.WING
		var best := Vector2.INF
		var bd := INF
		for p in c.parts:
			# every other pixel: plenty for picking a spot
			for i in range(0, p.w * p.h, 2):
				if p.alive[i] == 1 and p.zone[i] == zone:
					var w := p.to_world(Vector2(i % p.w + 0.5, i / p.w + 0.5))
					var dd := w.distance_squared_to(from)
					if dd < bd:
						bd = dd
						best = w
		if bd < INF:
			return best
	return c.global_position + Vector2(0, -c.height * 0.5)

## Which part the lock is on, by name (for the marker and the list).
func part_name() -> String:
	return DinoArt.ZONE_NAMES[PARTS[part]]

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
		_ui.draw_string(font, Vector2(14, vp.y - 26), "MOVE / SWIPE UP: JUMP", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.4))
	# the bite button, bottom right, filling as the big bite charges
	var btn := Vector2(vp.x - 46, vp.y - 50)
	_ui.draw_circle(btn, 20.0, Color(1, 0.3, 0.2, 0.18 if _right_id < 0 else 0.35))
	_ui.draw_arc(btn, 20.0, 0.0, TAU, 28, Color(1, 0.5, 0.4, 0.6), 1.0)
	if game.player.charging:
		_ui.draw_arc(btn, 23.0, -PI * 0.5, -PI * 0.5 + TAU * game.player.charge, 28, Color(1, 0.55, 0.2), 2.0)
	var label := "BITE" if not game.player.charging else "BIG"
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	_ui.draw_string(font, btn + Vector2(-lw * 0.5, 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.8))
	# the part list down the right edge: flick up/down to move along it
	for k in PARTS.size():
		var y := 70.0 + k * 13.0
		var on := k == part
		var n: String = DinoArt.ZONE_NAMES[PARTS[k]]
		var nw := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var col := Color(1, 0.85, 0.35) if on else Color(1, 1, 1, 0.35)
		_ui.draw_string(font, Vector2(vp.x - 10 - nw, y), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
		if on:
			_ui.draw_string(font, Vector2(vp.x - 20 - nw, y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
