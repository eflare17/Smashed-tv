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

	# the lock: a runner nearby is picked, on its body to start with
	pl.position = Vector2(200.0, main.GROUND_Y)
	pl.vel = Vector2.ZERO
	var r: Prey = main.spawn_prey(235.0, Prey.RUNNER)
	await _frames(3)
	r.state = 99
	r.vel = Vector2.ZERO
	await _frames(3)
	_check("the aim locks onto the nearest creature", touch.target == r)
	_check("...on its body to start", r.zone_at(touch.aim_point) == DinoArt.BODY or touch.part_name() == "BODY",
			touch.part_name())
	# a flick up on the right side picks the part nearer the head, without biting
	_press(1, Vector2(400, 200))
	_drag(1, Vector2(400, 180))
	_release(1, Vector2(400, 180))
	await _frames(2)
	_check("a flick up moves the pick toward the head", touch.part_name() == "NECK", touch.part_name())
	_check("...and doesn't bite", pl.bite_t < 0.0)
	_press(1, Vector2(400, 200))
	_drag(1, Vector2(400, 222))
	_release(1, Vector2(400, 222))
	_press(1, Vector2(400, 200))
	_drag(1, Vector2(400, 222))
	_release(1, Vector2(400, 222))
	await _frames(2)
	_check("two flicks down move it to the tail", touch.part_name() == "TAIL", touch.part_name())
	await _frames(2)
	_check("the aim sits on that part", r.zone_at(touch.aim_point) == DinoArt.TAIL,
			DinoArt.ZONE_NAMES[r.zone_at(touch.aim_point)])

	# a tap bites (at the locked spot)
	pl.cool = 0.0
	_press(1, Vector2(400, 200))
	_release(1, Vector2(400, 200))
	var bit := false
	for f in 3:
		await process_frame
		if pl.bite_t >= 0.0:
			bit = true
	_check("a tap on the right side bites", bit)
	for f in 120:
		await process_frame
		if pl.bite_t < 0.0 and pl.cool <= 0.0:
			break
	# holding charges the big bite; letting go bites with it
	r.state = 99
	r.vel = Vector2.ZERO
	pl.cool = 0.0
	_press(1, Vector2(400, 200))
	var charged := false
	for f in 400:
		await process_frame
		if pl.charging and pl.charge > 0.3:
			charged = true
			break
	_check("holding the right side charges a big bite", charged, "%.2f" % pl.charge)
	_release(1, Vector2(400, 200))
	await _frames(2)
	_check("letting go does the big bite", pl.bite_t >= 0.0 and pl.bite_kind == Player.BIG)

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
	# the death screen: a tap on NEXT RUN starts a new run (once it has settled)
	main.call("_game_over")
	_check("the death screen says tap on a phone", "TAP" in main.hud.get("_over_hint").text)
	var next: Vector2 = main.hud.get("_next").get_global_rect().get_center()
	_press(0, next)
	_release(0, next)
	_check("an early tap on the death screen does nothing", not main.playing())
	main.set("_over_t", 0.0)
	_press(0, Vector2(240, 60))
	_release(0, Vector2(240, 60))
	_check("a tap off the shop and the button does nothing", not main.playing())
	_press(0, next)
	_release(0, next)
	_check("a tap on NEXT RUN starts a new run", main.playing())

	# a real mouse takes over again
	var m := InputEventMouseMotion.new()
	m.relative = Vector2(10, 0)
	m.device = 0
	touch._input(m)
	_check("moving a real mouse switches back to mouse and keyboard", not touch.active)
	print("%d failed" % _fails)
	quit(_fails)
