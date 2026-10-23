extends SceneTree
## Headless checks for step 1. Run from the dino folder:
##   godot --headless --path . --script res://tests/test_bite.gd
## Prints PASS / FAIL per check and exits with the number of failures.

const DinoArt := preload("res://scripts/dino_art.gd")

var _fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(name: String, ok: bool, detail := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))
	if not ok:
		_fails += 1

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _zone_points(p: Prey, zone: int) -> Array:
	var out: Array = []
	for part in p.parts:
		for i in part.w * part.h:
			if part.alive[i] == 1 and part.zone[i] == zone:
				out.append(part.to_world(Vector2(i % part.w + 0.5, i / part.w + 0.5)))
	return out

func _run() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var prey: Prey = main.prey[0]

	# a bite takes pixels from exactly the zone aimed at
	var tail: Array = _zone_points(prey, DinoArt.TAIL)
	var before: float = prey.zone_fraction(DinoArt.TAIL)
	var head_before: float = prey.zone_fraction(DinoArt.HEAD)
	var r: Dictionary = prey.bite(tail[tail.size() / 2], 4.5, rng)
	_check("bite removes pixels", r.removed.size() > 10, "%d" % r.removed.size())
	_check("tail bite hits the tail", prey.zone_fraction(DinoArt.TAIL) < before)
	_check("tail bite leaves the head", prey.zone_fraction(DinoArt.HEAD) == head_before)
	_check("wounds marked", prey.wound_count() > 0, "%d" % prey.wound_count())

	# biting the same spot again goes deeper (nothing left there = nothing removed is fine)
	var mass1: float = prey.mass_fraction()
	prey.bite(tail[tail.size() / 2], 4.5, rng)
	_check("mass only goes down", prey.mass_fraction() <= mass1)

	# chew through the neck: the head comes off as one piece
	var islands := 0
	var head_off := false
	for k in 40:
		var neck: Array = _zone_points(prey, DinoArt.NECK)
		if neck.is_empty():
			break
		# bite the middle of what's left of the neck
		var mid := Vector2.ZERO
		for p: Vector2 in neck:
			mid += p
		mid /= neck.size()
		var res: Dictionary = prey.bite(mid, 4.5, rng)
		for isl: Dictionary in res.islands:
			islands += 1
			if isl.zones[DinoArt.HEAD] > 20:
				head_off = true
		if head_off:
			break
	_check("head comes off when the neck is bitten through", head_off, "%d pieces" % islands)
	_check("head gone from the body", prey.zone_fraction(DinoArt.HEAD) < 0.1, "%.2f" % prey.zone_fraction(DinoArt.HEAD))
	_check("losing the head kills", prey.hurt(Vector2.ZERO) and prey.dead)

	# a leg bitten at the hip falls off whole
	var p2: Prey = main.spawn_prey(600.0)
	await _frames(2)
	var leg: PixelPart = p2.legs[2][0]
	var hip: Vector2 = leg.to_world(leg.offset * -1.0 + Vector2(0, 2))
	var off := false
	for k in 6:
		var res2: Dictionary = p2.bite(hip, 4.5, rng)
		if not res2.islands.is_empty():
			off = true
			break
		hip += Vector2(0, 1)
	_check("leg comes off at the hip", off)

	# the whole game runs with the bot for a while without errors, and stays quick
	main.demo = true
	var t0 := Time.get_ticks_msec()
	await _frames(1500)
	var ms := float(Time.get_ticks_msec() - t0) / 1500.0
	_check("demo runs 1500 frames", true, "%.2f ms a frame headless" % ms)
	_check("the bot landed bites", main.chunks > 0, "%d chunks, %d kills" % [main.chunks, main.kills])
	print("%d failed" % _fails)
	quit(_fails)
