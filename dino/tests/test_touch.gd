extends SceneTree
## Headless checks for the phone controls, driven by simulated finger touches. From the dino folder:
##   godot --headless --path . --script res://tests/test_touch.gd
## Prints PASS / FAIL per check and exits with the number of failures.

const DinoArt := preload("res://scripts/dino_art.gd")

var _fails := 0
var main: Node
var touch: Touch

func _initialize() -> void:
	_run.call_deferred()

func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))
	if not ok:
		_fails += 1

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _press(index: int, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = true
	touch.active = true
	touch.handle(e)

func _release(index: int, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = false
	touch.handle(e)

func _drag(index: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	touch.handle(e)

func _screen(world: Vector2) -> Vector2:
	return touch.get_canvas_transform() * world

## Keeps a creature standing still (and alive) for the test.
func _hold(c: Prey) -> void:
	c.state = 99
	c.vel = Vector2.ZERO

## The live pixel of a zone nearest that zone's middle.
func _zone_point(c: Prey, zone: int) -> Vector2:
	var pts: Array[Vector2] = []
	var sum := Vector2.ZERO
	for p in c.parts:
		for i in p.w * p.h:
			if p.alive[i] == 1 and p.zone[i] == zone:
				var w := p.to_world(Vector2(i % p.w + 0.5, i / p.w + 0.5))
				pts.append(w)
				sum += w
	var mid := sum / maxf(1.0, pts.size())
	var best := mid
	for w in pts:
		if w.distance_to(mid) < best.distance_to(mid) or best == mid:
			best = w
	return best

func _zone_count(c: Prey, zone: int) -> int:
	var n := 0
	for p in c.parts:
		for i in p.w * p.h:
			if p.alive[i] == 1 and p.zone[i] == zone:
				n += 1
	return n

## Waits for the bite to finish and the cooldown to run out, keeping the creature still.
func _settle(pl: Player, c: Prey) -> void:
	for f in 200:
		await process_frame
		if is_instance_valid(c):
			_hold(c)
		if pl.bite_t < 0.0 and pl.cool <= 0.0 and pl.grab.is_empty() and main.get("_stop") <= 0.0:
			break
	pl.cool = 0.0

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	touch = main.touch
	main.set("_hunt_t", 99999.0)
	main.set("_herd_t", 99999.0)
	for c in main.creatures.duplicate():
		c.queue_free()
	main.creatures.clear()
	main.obstacles.clear()
	main.platforms.clear()
	var pl: Player = main.player
	pl.position = Vector2(200.0, main.GROUND_Y)
	await _frames(2)

	# left thumb: drag right to walk
	var x0 := pl.position.x
	_press(0, Vector2(100, 200))
	_drag(0, Vector2(130, 200))
	_check("dragging the left thumb right walks right", touch.move_x > 0.9, "%.2f" % touch.move_x)
	await _frames(30)
	_check("...and you move", pl.position.x > x0 + 3.0, "%.0f -> %.0f" % [x0, pl.position.x])
	# a quick swipe up jumps
	touch.set("_left_t", 0.0)
	_drag(0, Vector2(130, 175))
	var jumped := false
	for f in 20:
		await process_frame
		if not pl.on_ground:
			jumped = true
			break
	_check("a quick swipe up jumps", jumped)
	_release(0, Vector2(130, 175))
	_check("letting go stops", touch.move_x == 0.0)
	for f in 120:
		await process_frame
		if pl.on_ground:
			break

	# with nothing touched, the aim goes for the nearest creature's body
	pl.position = Vector2(200.0, main.GROUND_Y)
	pl.vel = Vector2.ZERO
	var r: Prey = main.spawn_prey(235.0, Prey.RUNNER)
	await _frames(3)
	_hold(r)
	await _frames(3)
	_check("the aim locks onto the nearest creature", touch.target == r)
	_check("...on its body", touch.part_name() == "BODY", touch.part_name())

	# touching a creature's head aims there; a quick tap bites it there
	pl.cool = 0.0
	var head := _screen(_zone_point(r, DinoArt.HEAD))
	var heads := _zone_count(r, DinoArt.HEAD)
	_press(1, head)
	await _frames(1)
	_check("touching a creature's head aims at its head", touch.part_name() == "HEAD", touch.part_name())
	_check("...and doesn't bite until you let go", pl.bite_t < 0.0)
	_release(1, head)
	var bit := false
	for f in 3:
		await process_frame
		if pl.bite_t >= 0.0:
			bit = true
	_check("a tap on the head bites", bit and pl.bite_kind == Player.QUICK)
	await _settle(pl, r)
	_check("...and the head is what got bitten", _zone_count(r, DinoArt.HEAD) < heads,
			"%d -> %d head pixels" % [heads, _zone_count(r, DinoArt.HEAD)])

	# holding on the tail charges the big bite; letting go bites with it, on the tail
	var tail := _screen(_zone_point(r, DinoArt.TAIL))
	_press(1, tail)
	var charged := false
	for f in 400:
		await process_frame
		_hold(r)
		if pl.charging and pl.charge > 0.3:
			charged = true
			break
	_check("holding on the tail charges a big bite", charged, "%.2f" % pl.charge)
	_check("...aimed at the tail", touch.part_name() == "TAIL", touch.part_name())
	var spot := touch.aim_point
	_release(1, tail)
	await _frames(2)
	_check("letting go does the big bite", pl.bite_t >= 0.0 and pl.bite_kind == Player.BIG)
	await _settle(pl, r)

	# BITE goes back for the spot you last touched (or what's left nearest it)
	var btn: Vector2 = main.get_viewport().get_visible_rect().size + (Touch.BITE_BTN[0] as Vector2)
	_press(1, btn)
	await _frames(1)
	_check("BITE aims where you last touched", touch.target == r and touch.aim_point.distance_to(spot) < 16.0,
			"%.0f px away" % touch.aim_point.distance_to(spot))
	_release(1, btn)
	await _frames(2)
	_check("...and a tap on it bites", pl.bite_t >= 0.0)
	await _settle(pl, r)

	# a creature on the left half is bitten, not walked to
	var back: Prey = main.spawn_prey(pl.position.x - 30.0, Prey.RUNNER)
	await _frames(3)
	_hold(back)
	var on_left := _screen(_zone_point(back, DinoArt.BODY))
	_press(0, on_left)
	await _frames(1)
	_check("touching a creature on the left half aims at it", on_left.x < 240.0 and touch.target == back,
			"at x %.0f" % on_left.x)
	_check("...instead of being the move stick", touch.move_x == 0.0 and touch.get("_left_id") < 0)
	_release(0, on_left)
	await _settle(pl, back)

	# the JUMP button
	var jb: Vector2 = main.get_viewport().get_visible_rect().size + (Touch.JUMP_BTN[0] as Vector2)
	_press(2, jb)
	_check("the JUMP button isn't a bite", touch.get("_bite_id") < 0 and touch.get("_left_id") < 0)
	var hopped := false
	for f in 20:
		await process_frame
		if not pl.on_ground:
			hopped = true
			break
	_release(2, jb)
	_check("the JUMP button jumps", hopped)
	for f in 120:
		await process_frame
		if pl.on_ground:
			break

	# level-up cards: a tap on one picks it
	await _frames(30)
	main.set("_choices", 1)
	main.call("_offer")
	var card: Button = main.hud.get("_cards")[1]
	var at := card.get_global_rect().get_center()
	_press(1, at)
	_check("touching a level-up card doesn't pick it yet", not main.playing())
	_release(1, at)
	_check("lifting the finger on a card picks it", main.playing() and main.get("_choices") == 0)
	_check("...without biting", not touch.bite)
	# the death screen: a tap starts a new run (once it has settled)
	main.call("_game_over")
	_check("the death screen says tap on a phone", "TAP" in main.hud.get("_over_text").text)
	_press(0, Vector2(240, 135))
	_release(0, Vector2(240, 135))
	_check("an early tap on the death screen does nothing", not main.playing())
	main.set("_over_t", 0.0)
	_press(0, Vector2(240, 135))
	_release(0, Vector2(240, 135))
	_check("a tap on the death screen starts a new run", main.playing())

	# a real mouse takes over again
	var m := InputEventMouseMotion.new()
	m.relative = Vector2(10, 0)
	m.device = 0
	touch._input(m)
	_check("moving a real mouse switches back to mouse and keyboard", not touch.active)
	print("%d failed" % _fails)
	quit(_fails)
